module Agents
  class ManualEventAgent < Agent
    cannot_be_scheduled!
    cannot_receive_events!

    description <<-MD
      Manual Event Agent 用于手动创建事件以进行测试或其他目的。

      不要为此代理设置配置项。 而是将其连接到其他代理，并使用此代理的“摘要”页面上提供的UI创建事件.
    MD

    event_description "User determined"

    def default_options
      { "no options" => "are needed" }
    end

    def handle_details_post(params)
      if params['payload']
        json = interpolate_options(JSON.parse(params['payload']))
        if json['payloads'] && (json.keys - ['payloads']).length > 0
          { :success => false, :error => "If you provide the 'payloads' key, please do not provide any other keys at the top level." }
        else
          [json['payloads'] || json].flatten.each do |payload|
            create_event(:payload => payload)
          end
          { :success => true }
        end
      else
        { :success => false, :error => "You must provide a JSON payload" }
      end
    end

    def working?
      true
    end

    def validate_options
    end
  end
end
