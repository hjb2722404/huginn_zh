module Agents
  class EventFormattingAgent < Agent
    cannot_be_scheduled!
    can_dry_run!

    description <<-MD
      Event Formatting Agent 允许您格式化传入的事件，根据需要添加新字段.

      例如，这是一个可能的事件：

          {
            "high": {
              "celsius": "18",
              "fahreinheit": "64"
            },
            "date": {
              "epoch": "1357959600",
              "pretty": "10:00 PM EST on January 11, 2013"
            },
            "conditions": "Rain showers",
            "data": "This is some data"
          }

          您可能希望将此事件发送给另一个代理，例如需要`message`密钥的Twilio代理。 您可以 Event Formatting Agent 的`instructions` 设置以下列方式执行此操作：

          "instructions": {
            "message": "Today's conditions look like {{conditions}} with a high temperature of {{high.celsius}} degrees Celsius.",
            "subject": "{{data}}",
            "created_at": "{{created_at}}"
          }

          这里的名称类似`conditions`，`high` 和`data` 引用事件哈希中的相应值。

          特殊键`created_at`引用事件的时间戳，可以通过日期过滤器重新格式化，如{{created_at | date：“at％I：％M％p”}}。

          每个接收事件的上游代理都可以通过密钥代理访问，密钥代理具有以下属性：: #{''.tap { |s| s << AgentDrop.instance_methods(false).map { |m| "`#{m}`" }.join(', ') }}.

          查看[Wiki](https://github.com/huginn/huginn/wiki/Formatting-Events-using-Liquid) 以了解有关Liquid模板的更多信息 

      此可能的Event Formatting Agent 生成的事件如下所示：

          {
            "message": "Today's conditions look like Rain showers with a high temperature of 18 degrees Celsius.",
            "subject": "This is some data"
          }

          在`matchers` 设置中，您可以对事件内容执行正则表达式匹配，并展开匹配数据以在`instructions` 设置中使用。 这是一个例子

          {
            "matchers": [
              {
                "path": "{{date.pretty}}",
                "regexp": "\\A(?<time>\\d\\d:\\d\\d [AP]M [A-Z]+)",
                "to": "pretty_date"
              }
            ]
          }

          这实际上将以下哈希合并到原始事件哈希中：

          "pretty_date": {
            "time": "10:00 PM EST",
            "0": "10:00 PM EST on January 11, 2013"
            "1": "10:00 PM EST"
          }

          所以你可以在这样的`instructions` 中使用它：

          "instructions": {
            "message": "Today's conditions look like {{conditions}} with a high temperature of {{high.celsius}} degrees Celsius according to the forecast at {{pretty_date.time}}.",
            "subject": "{{data}}"
          }

          如果要保留事件的原始内容并仅添加新键，则将`mode` 设置为`merge`，否则将其设置为`clean`

          CGI转义输出（例如，在创建链接时），使用Liquid uri_escape过滤器，如下所示：

          {
            "message": "A peak was on Twitter in {{group_by}}.  Search: https://twitter.com/search?q={{group_by | uri_escape}}"
          }
    MD

    event_description do
      "Events will have the following fields%s:\n\n    %s" % [
        case options['mode'].to_s
        when 'merge'
          ', merged with the original contents'
        when /\{/
          ', conditionally merged with the original contents'
        end,
        Utils.pretty_print(Hash[options['instructions'].keys.map { |key|
          [key, "..."]
        }])
      ]
    end

    def validate_options
      errors.add(:base, "instructions and mode need to be present.") unless options['instructions'].present? && options['mode'].present?

      if options['mode'].present? && !options['mode'].to_s.include?('{{') && !%[clean merge].include?(options['mode'].to_s)
        errors.add(:base, "mode must be 'clean' or 'merge'")
      end

      validate_matchers
    end

    def default_options
      {
        'instructions' => {
          'message' =>  "You received a text {{text}} from {{fields.from}}",
          'agent' => "{{agent.type}}",
          'some_other_field' => "Looks like the weather is going to be {{fields.weather}}"
        },
        'matchers' => [],
        'mode' => "clean",
      }
    end

    def working?
      !recent_error_logs?
    end

    def receive(incoming_events)
      matchers = compiled_matchers

      incoming_events.each do |event|
        interpolate_with(event) do
          apply_compiled_matchers(matchers, event) do
            formatted_event = interpolated['mode'].to_s == "merge" ? event.payload.dup : {}
            formatted_event.merge! interpolated['instructions']
            create_event payload: formatted_event
          end
        end
      end
    end

    private

    def validate_matchers
      matchers = options['matchers'] or return

      unless matchers.is_a?(Array)
        errors.add(:base, "matchers must be an array if present")
        return
      end

      matchers.each do |matcher|
        unless matcher.is_a?(Hash)
          errors.add(:base, "each matcher must be a hash")
          next
        end

        regexp, path, to = matcher.values_at(*%w[regexp path to])

        if regexp.present?
          begin
            Regexp.new(regexp)
          rescue
            errors.add(:base, "bad regexp found in matchers: #{regexp}")
          end
        else
          errors.add(:base, "regexp is mandatory for a matcher and must be a string")
        end

        errors.add(:base, "path is mandatory for a matcher and must be a string") if !path.present?

        errors.add(:base, "to must be a string if present in a matcher") if to.present? && !to.is_a?(String)
      end
    end

    def compiled_matchers
      if matchers = options['matchers']
        matchers.map { |matcher|
          regexp, path, to = matcher.values_at(*%w[regexp path to])
          [Regexp.new(regexp), path, to]
        }
      end
    end

    def apply_compiled_matchers(matchers, event, &block)
      return yield if matchers.nil?

      # event.payload.dup does not work; HashWithIndifferentAccess is
      # a source of trouble here.
      hash = {}.update(event.payload)

      matchers.each do |re, path, to|
        m = re.match(interpolate_string(path, hash)) or next

        mhash =
          if to
            case value = hash[to]
            when Hash
              value
            else
              hash[to] = {}
            end
          else
            hash
          end

        m.size.times do |i|
          mhash[i.to_s] = m[i]
        end

        m.names.each do |name|
          mhash[name] = m[name]
        end
      end

      interpolate_with(hash, &block)
    end
  end
end
