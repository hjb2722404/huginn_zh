module Agents
  class BoxcarAgent < Agent

    cannot_be_scheduled!
    cannot_create_events!

    API_URL = 'https://new.boxcar.io/api/notifications'

    description <<-MD
      Boxcar代理向iPhone发送推送通知。

      为了能够使用Boxcar最终用户API，您需要访问令牌。 访问令牌可在Boxcar iOS应用程序的常规“设置”屏幕或Boxcar Web收件箱设置页面中使用。
      
      请在user_credentials选项中提供您的访问令牌。 如果您要使用凭据，请将user_credentials选项设置为{％credential CREDENTIAL_NAME％}。

      配置项:

      * `user_credentials` -  Boxcar访问令牌
      * `title` -  消息的标题。
      * `body` - 消息的正文。
      * `source_name` - 消息来源的名称。 默认设置为Huginn。
      * `icon_url` - 图标的URL。
      * `sound` - 通知播放的声音。 默认设置为“bird-1”。
    MD

    def default_options
      {
        'user_credentials' => '',
        'title' => "{{title}}",
        'body' => "{{body}}",
        'source_name' => "Huginn",
        'icon_url' => "",
        'sound' => "bird-1"
      }
    end

    def working?
      received_event_without_error?
    end

    def strip(string)
      (string || '').strip
    end

    def validate_options
      errors.add(:base, "you need to specify a boxcar api key") if options['user_credentials'].blank?
    end

    def receive(incoming_events)
      incoming_events.each do |event|
        payload_interpolated = interpolated(event)
        user_credentials = payload_interpolated['user_credentials']
        post_params = {
          'user_credentials' => user_credentials,
          'notification' => {
            'title' => strip(payload_interpolated['title']),
            'long_message' => strip(payload_interpolated['body']),
            'source_name' => payload_interpolated['source_name'],
            'sound' => payload_interpolated['sound'],
            'icon_url' => payload_interpolated['icon_url']
          }
        }
        send_notification(post_params)
      end
    end

    def send_notification(post_params)
      response = HTTParty.post(API_URL, :query => post_params)
      raise StandardError, response['error']['message'] if response['error'].present?
      if response['Response'].present?  && response['Response'] == "Not authorized"
        raise StandardError, response['Response']
      end
      if !response['id'].present?
        raise StandardError, "Invalid response from Boxcar: #{response}"
      end
    end
  end
end
