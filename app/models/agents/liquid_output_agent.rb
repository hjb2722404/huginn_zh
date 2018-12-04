module Agents
  class LiquidOutputAgent < Agent
    include FormConfigurable

    cannot_be_scheduled!
    cannot_create_events!

    DATE_UNITS = %w[second seconds minute minutes hour hours day days week weeks month months year years]

    description  do
      <<-MD
      Liquid Output Agent通过您提供的Liquid模板输出事件。 使用它来创建HTML页面，或json提要，或其他任何可以从您的Huginn数据流中呈现为字符串的内容。

      此代理将输出以下数据：

        `https://#{ENV['DOMAIN']}#{Rails.application.routes.url_helpers.web_requests_path(agent_id: ':id', user_id: user_id, secret: ':secret', format: :any_extension)}`

        其中：secret是您选项中指定的秘密。 您可以使用任何您想要的扩展名。

        配置项:

          * `secret` - 请求者必须提供的用于轻量级身份验证的令牌。
          * `expected_receive_period_in_days` -  您希望此代理从其他代理接收数据的频率。
          * `content` - 有人请求此页面时显示的内容
          * `mime_type` -  当有人请求此页面时使用的mime类型。
          * `response_headers` - 具有任何自定义响应标头的对象。 （例如：{“Access-Control-Allow-Origin”：“*”}）
          * `mode` - 确定将哪些数据传递到Liquid模板的行为。
          * `event_limit` - 在“Last X events”模式下应用于传递给模板的事件的限制。 可以是“1”之类的计数，也可以是“1天”或“5分钟”之类的时间。

        # Liquid 模板

        您提供的内容将作为Liquid模板运行。 处理Liquid模板时将使用收到的最后一个事件的数据

        # 模式

        ### Merge events

        传入事件的数据将被合并。 所以如果有两个事件像这样：

```
{ 'a' => 'b',  'c' => 'd'}
{ 'a' => 'bb', 'e' => 'f'}
```

          最终结果将是：

```
{ 'a' => 'bb', 'c' => 'd', 'e' => 'f'}
```

        此合并版本将传递给Liquid模板。

        ### Last event in

        最后一个事件的数据将传递给模板。

        ### Last X events

          此代理接收的所有事件都将作为事件数组传递给模板。

          可以通过event_limit选项控制事件数。 如果`event_limit`是整数`X`，则最后的X事件将传递给模板。 如果`event_limit`是一个整数，其度量单位为“1天”或“5分钟”或“9年”，则日期过滤器将应用于传递给模板的事件。 如果未提供event_limit，则代理的所有事件都将传递给模板。
          
          对于性能，允许的最大`event_limit`为`1000`.

      MD
    end

    def default_options
      content = <<EOF
When you use the "Last event in" or "Merge events" option, you can use variables from the last event received, like this:

Name: {{name}}
Url:  {{url}}

If you use the "Last X Events" mode, a set of events will be passed to your Liquid template.  You can use them like this:

<table class="table">
  {% for event in events %}
    <tr>
      <td>{{ event.title }}</td>
      <td><a href="{{ event.url }}">Click here to see</a></td>
    </tr>
  {% endfor %}
</table>
EOF
      {
        "secret" => "a-secret-key",
        "expected_receive_period_in_days" => 2,
        "mime_type" => 'text/html',
        "mode" => 'Last event in',
        "event_limit" => '',
        "content" => content,
      }
    end

    form_configurable :secret
    form_configurable :expected_receive_period_in_days
    form_configurable :content, type: :text
    form_configurable :mime_type
    form_configurable :mode, type: :array, values: [ 'Last event in', 'Merge events', 'Last X events']
    form_configurable :event_limit

    def working?
      last_receive_at && last_receive_at > options['expected_receive_period_in_days'].to_i.days.ago && !recent_error_logs?
    end

    def validate_options
      if options['secret'].present?
        case options['secret']
        when %r{[/.]}
          errors.add(:base, "secret may not contain a slash or dot")
        when String
        else
          errors.add(:base, "secret must be a string")
        end
      else
        errors.add(:base, "Please specify one secret for 'authenticating' incoming feed requests")
      end

      unless options['expected_receive_period_in_days'].present? && options['expected_receive_period_in_days'].to_i > 0
        errors.add(:base, "Please provide 'expected_receive_period_in_days' to indicate how many days can pass before this Agent is considered to be not working")
      end

      if options['event_limit'].present?
        if((Integer(options['event_limit']) rescue false) == false)
          errors.add(:base, "Event limit must be an integer that is less than 1001.")
        elsif (options['event_limit'].to_i > 1000)
          errors.add(:base, "For performance reasons, you cannot have an event limit greater than 1000.")
        end
      else
      end
    end

    def receive(incoming_events)
      return unless ['merge events', 'last event in'].include?(mode)
      memory['last_event'] ||= {}
      incoming_events.each do |event|
        case mode
        when 'merge events'
          memory['last_event'] = memory['last_event'].merge(event.payload)
        else
          memory['last_event'] = event.payload
        end
      end
    end

    def receive_web_request(params, method, format)
      valid_authentication?(params) ? [liquified_content, 200, mime_type, interpolated['response_headers'].presence]
                                    : [unauthorized_content(format), 401]
    end

    private

    def mode
      options['mode'].to_s.downcase
    end

    def unauthorized_content(format)
      format =~ /json/ ? { error: "Not Authorized" }
                       : "Not Authorized"
    end

    def valid_authentication?(params)
      interpolated['secret'] == params['secret']
    end

    def mime_type
      options['mime_type'].presence || 'text/html'
    end

    def liquified_content
      interpolated(data_for_liquid_template)['content']
    end

    def data_for_liquid_template
      case mode
      when 'last x events'
        events = received_events
        events = events.where('events.created_at > ?', date_limit) if date_limit
        events = events.limit count_limit
        events = events.to_a.map { |x| x.payload }
        { 'events' => events }
      else
        memory['last_event'] || {}
      end
    end

    def count_limit
      limit = Integer(options['event_limit']) rescue 1000
      limit <= 1000 ? limit : 1000
    end

    def date_limit
      return nil unless options['event_limit'].to_s.include?(' ')
      value, unit = options['event_limit'].split(' ')
      value = Integer(value) rescue nil
      return nil unless value
      unit = unit.to_s.downcase
      return nil unless DATE_UNITS.include?(unit)
      value.send(unit.to_sym).ago
    end

  end
end
