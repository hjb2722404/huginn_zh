module Agents
  class TriggerAgent < Agent
    cannot_be_scheduled!
    can_dry_run!

    VALID_COMPARISON_TYPES = %w[regex !regex field<value field<=value field==value field!=value field>=value field>value not\ in]

    description <<-MD
      Trigger Agent 将监视事件有效负载中的特定值.

      `rules`数组包含路径，值和类型的哈希值。 路径值是[JSONPaths](http://goessner.net/articles/JsonPath/)语法中通过哈希的虚线路径。 对于简单事件，这通常只是您想要的字段的名称，例如事件的文本键的“text” 。

      类型可以是 #{VALID_COMPARISON_TYPES.map { |t| "`#{t}`" }.to_sentence}，而不是和值进行比较。 请注意，正则表达式模式不区分大小写。 如果你想要区分大小写的匹配，请在模式前加上（？-i）.

      值可以是单个值或值数组。 对于数组，所有项必须是字符串，如果一个或多个值匹配，则规则匹配。 注意：避免对数组使用field！= value，不应该使用

      默认情况下，所有规则必须匹配才能触发代理。 您可以通过将`must_match`设置为1来切换此选项，以便只有一个规则必须匹配

      生成的事件将具有消息的有效负载消息。 您可以在`消息中使用液体模板，查看[Wiki](https://github.com/huginn/huginn/wiki/Formatting-Events-using-Liquid)以获取详细信息。

      如果您想重新发出传入事件，请将`keep_event`设置为`true`，并在提供时选择与“message”合并

      将`expected_receive_period_in_days`设置为您希望在此代理接收的事件之间传递的最长时间.
    MD

    event_description <<-MD
      Events look like this:

          { "message": "Your message" }
    MD

    def validate_options
      unless options['expected_receive_period_in_days'].present? && options['rules'].present? &&
             options['rules'].all? { |rule| rule['type'].present? && VALID_COMPARISON_TYPES.include?(rule['type']) && rule['value'].present? && rule['path'].present? }
        errors.add(:base, "expected_receive_period_in_days, message, and rules, with a type, value, and path for every rule, are required")
      end

      errors.add(:base, "message is required unless 'keep_event' is 'true'") unless options['message'].present? || keep_event?

      errors.add(:base, "keep_event, when present, must be 'true' or 'false'") unless options['keep_event'].blank? || %w[true false].include?(options['keep_event'])

      if options['must_match'].present?
        if options['must_match'].to_i < 1
          errors.add(:base, "If used, the 'must_match' option must be a positive integer")
        elsif options['must_match'].to_i > options['rules'].length
          errors.add(:base, "If used, the 'must_match' option must be equal to or less than the number of rules")
        end
      end
    end

    def default_options
      {
        'expected_receive_period_in_days' => "2",
        'keep_event' => 'false',
        'rules' => [{
                      'type' => "regex",
                      'value' => "foo\\d+bar",
                      'path' => "topkey.subkey.subkey.goal",
                    }],
        'message' => "Looks like your pattern matched in '{{value}}'!"
      }
    end

    def working?
      last_receive_at && last_receive_at > interpolated['expected_receive_period_in_days'].to_i.days.ago && !recent_error_logs?
    end

    def receive(incoming_events)
      incoming_events.each do |event|

        opts = interpolated(event)

        match_results = opts['rules'].map do |rule|
          value_at_path = Utils.value_at(event['payload'], rule['path'])
          rule_values = rule['value']
          rule_values = [rule_values] unless rule_values.is_a?(Array)

          if rule['type'] == 'not in'
            !rule_values.include?(value_at_path.to_s)
          elsif rule['type'] == 'field==value'
            rule_values.include?(value_at_path.to_s)
          else
            rule_values.any? do |rule_value|
              case rule['type']
              when "regex"
                value_at_path.to_s =~ Regexp.new(rule_value, Regexp::IGNORECASE)
              when "!regex"
                value_at_path.to_s !~ Regexp.new(rule_value, Regexp::IGNORECASE)
              when "field>value"
                value_at_path.to_f > rule_value.to_f
              when "field>=value"
                value_at_path.to_f >= rule_value.to_f
              when "field<value"
                value_at_path.to_f < rule_value.to_f
              when "field<=value"
                value_at_path.to_f <= rule_value.to_f
              when "field!=value"
                value_at_path.to_s != rule_value.to_s
              else
                raise "Invalid type of #{rule['type']} in TriggerAgent##{id}"
              end
            end
          end
        end

        if matches?(match_results)
          if keep_event?
            payload = event.payload.dup
            payload['message'] = opts['message'] if opts['message'].present?
          else
            payload = { 'message' => opts['message'] }
          end

          create_event :payload => payload
        end
      end
    end

    def matches?(matches)
      if options['must_match'].present?
        matches.select { |match| match }.length >= options['must_match'].to_i
      else
        matches.all?
      end
    end

    def keep_event?
      boolify(interpolated['keep_event'])
    end
  end
end
