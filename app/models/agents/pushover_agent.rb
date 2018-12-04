module Agents
  class PushoverAgent < Agent
    cannot_be_scheduled!
    cannot_create_events!
    no_bulk_receive!


    API_URL = 'https://api.pushover.net/1/messages.json'

    description <<-MD
      Pushover Agent接收并收集事件，并通过推送通知将其发送给用户/组。

      **您需要一个Pushover API令牌:** [https://pushover.net/apps/build](https://pushover.net/apps/build)

      * `token`: 您的应用程序的API令牌
      * `user`: 用户或组密钥（不是电子邮件地址）
      * `expected_receive_period_in_days`:  是您希望在此代理接收的事件之间传递的最大天数。

      以下选项均为[Liquid](https://github.com/huginn/huginn/wiki/Formatting-Events-using-Liquid) 模板，其评估值将推送到Pushover API。 只需要message参数，如果是空白，则省略API调用。 

      Pushover API有512个字符限制，包括标题。 消息将被截断.

      * `message` - 你的信息（必填）
      * `device` - 用户的设备名称将消息直接发送到该设备，而不是所有用户的设备。
      * `title` or `subject` - 你的通知标题
      * `url` - 与您的消息一起显示的补充URL - 512字符限制。
      * `url_title` - 您的补充URL的标题，否则只显示URL - 100字符限制
      * `timestamp` - 消息的Unix时间戳显示给用户的日期和时间，而不是Pushover API接收消息的时间。
      * `priority` - 发送为`-1`始终作为安静通知发送，`0`表示默认，`1`表示高优先级并绕过用户的安静时间，或`2`表示紧急优先：[请阅读Pushover Docs](https://pushover.net/api#priority).
      * `sound` - 设备客户端支持的声音之一的名称，以覆盖用户的默认声音选择。 有关声音选项，[请参阅PushOver文档](https://pushover.net/api#sounds)
      * `retry` - 紧急优先级必需 - 指定Pushover服务器向用户发送相同通知的频率（以秒为单位）。 最低价值：`30`
      * `expire` - 紧急优先级必需 - 指定继续重试通知的秒数（每次重试秒数）。 最大值：`86400`
      * `html` - 设置为`true`以使Pushover的应用程序将消息内容显示为HTML

    MD

    def default_options
      {
        'token' => '',
        'user' => '',
        'message' => '{{ message }}',
        'device' => '{{ device }}',
        'title' => '{{ title }}',
        'url' => '{{ url }}',
        'url_title' => '{{ url_title }}',
        'priority' => '{{ priority }}',
        'timestamp' => '{{ timestamp }}',
        'sound' => '{{ sound }}',
        'retry' => '{{ retry }}',
        'expire' => '{{ expire }}',
        'html' => 'false',
        'expected_receive_period_in_days' => '1'
      }
    end

    def validate_options
      unless options['token'].present? && options['user'].present? && options['expected_receive_period_in_days'].present?
        errors.add(:base, 'token, user, and expected_receive_period_in_days are all required.')
      end
    end

    def receive(incoming_events)
      incoming_events.each do |event|
        interpolate_with(event) do
          post_params = {}

          # required parameters
          %w[
            token
            user
            message
          ].all? { |key|
            if value = String.try_convert(interpolated[key].presence)
              post_params[key] = value
            end
          } or next

          # optional parameters
          %w[
            device
            title
            url
            url_title
            priority
            timestamp
            sound
            retry
            expire
          ].each do |key|
            if value = String.try_convert(interpolated[key].presence)
              case key
              when 'url'
                value.slice!(512..-1)
              when 'url_title'
                value.slice!(100..-1)
              end
              post_params[key] = value
            end
          end
          # html is special because String.try_convert(true) gives nil (not even "nil", just nil)
          if value = interpolated['html'].presence
            post_params['html'] =
              case value.to_s
              when 'true', '1'
                '1'
              else
                '0'
              end
          end

          send_notification(post_params)
        end
      end
    end

    def working?
      last_receive_at && last_receive_at > interpolated['expected_receive_period_in_days'].to_i.days.ago && !recent_error_logs?
    end

    def send_notification(post_params)
      response = HTTParty.post(API_URL, query: post_params)
      puts response
      log "Sent the following notification: \"#{post_params.except('token').inspect}\""
    end
  end
end
