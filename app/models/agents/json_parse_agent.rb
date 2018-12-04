module Agents
  class JsonParseAgent < Agent
    include FormConfigurable

    cannot_be_scheduled!
    can_dry_run!

    description <<-MD
      JSON Parse代理解析JSON字符串并在新事件中发出数据或与原始事件合并。

      `data` 是要解析的JSON。 使用Liquid模板指定JSON字符串。

      `data_key` 设置包含已发布事件中已解析JSON数据的键

      `mode` 确定是创建新的干净事件还是将旧有效负载与新值合并（默认值：clean）
    MD

    def default_options
      {
        'data' => '{{ data }}',
        'data_key' => 'data',
        'mode' => 'clean',
      }
    end

    event_description do
      "Events will looks like this:\n\n    %s" % Utils.pretty_print(interpolated['data_key'] => {parsed: 'object'})
    end

    form_configurable :data
    form_configurable :data_key
    form_configurable :mode, type: :array, values: ['clean', 'merge']

    def validate_options
      errors.add(:base, "data needs to be present") if options['data'].blank?
      errors.add(:base, "data_key needs to be present") if options['data_key'].blank?
      if options['mode'].present? && !options['mode'].to_s.include?('{{') && !%[clean merge].include?(options['mode'].to_s)
        errors.add(:base, "mode must be 'clean' or 'merge'")
      end
    end

    def working?
      received_event_without_error?
    end

    def receive(incoming_events)
      incoming_events.each do |event|
        begin
          mo = interpolated(event)
          existing_payload = mo['mode'].to_s == 'merge' ? event.payload : {}
          create_event payload: existing_payload.merge({ mo['data_key'] => JSON.parse(mo['data']) })
        rescue JSON::JSONError => e
          error("Could not parse JSON: #{e.class} '#{e.message}'")
        end
      end
    end
  end
end
