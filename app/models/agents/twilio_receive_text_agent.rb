module Agents
  class TwilioReceiveTextAgent < Agent
    cannot_be_scheduled!
    cannot_receive_events!

    gem_dependency_check { defined?(Twilio) }

    description do <<-MD
      Twilio Receive Text Agent 从Twilio接收文本消息并将其作为事件发出。

      (Twilio是一个做成开放插件的电话跟踪服务)。

      #{'## Include `twilio-ruby` in your Gemfile to use this Agent!' if dependencies_missing?}

      要使用此代理创建事件，请配置Twilio以将POST请求发送到：

      ```
      #{post_url}
      ```

      #{'保存代理后，上面的占位符符号将替换为其值。' unless id}

      配置项说明:

        *  `server_url`必须设置为您的Huginn安装的URL（可能是“https：// localhost：3000”），该URL必须可通过Web访问。 务必正确设置http / https。

        *  `account_sid`和`auth_token`是您的Twilio帐户凭据。 `auth_token`必须是Twilio accout的主要身份验证令牌。

        *  如果设置了reply_text，它的内容将作为确认文本发回。

        * `expected_receive_period_in_days` - 您希望以这种方式接收事件的频率。 用于确定代理是否正常工作。
      MD
    end

    def default_options
      {
        'account_sid' => 'ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
        'auth_token' => 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
        'server_url'    => "https://#{ENV['DOMAIN'].presence || 'example.com'}",
        'reply_text'    => '',
        "expected_receive_period_in_days" => 1
      }
    end

    def validate_options
      unless options['account_sid'].present? && options['auth_token'].present? && options['server_url'].present? && options['expected_receive_period_in_days'].present?
        errors.add(:base, 'account_sid, auth_token, server_url, and expected_receive_period_in_days are all required')
      end
    end

    def working?
      event_created_within?(interpolated['expected_receive_period_in_days']) && !recent_error_logs?
    end

    def post_url
      if interpolated['server_url'].present?
        "#{interpolated['server_url']}/users/#{user.id}/web_requests/#{id || ':id'}/sms-endpoint"
      else
        "https://#{ENV['DOMAIN']}/users/#{user.id}/web_requests/#{id || ':id'}/sms-endpoint"
      end
    end

    def receive_web_request(request)
      params = request.params.except(:action, :controller, :agent_id, :user_id, :format)
      method = request.method_symbol.to_s
      headers = request.headers

      # check the last url param: 'secret'
      secret = params.delete('secret')
      return ["Not Authorized", 401] unless secret == "sms-endpoint"

      signature = headers['HTTP_X_TWILIO_SIGNATURE']

      # validate from twilio
      @validator ||= Twilio::Util::RequestValidator.new interpolated['auth_token']
      if !@validator.validate(post_url, params, signature)
        error("Twilio Signature Failed to Validate\n\n"+
          "URL: #{post_url}\n\n"+
          "POST params: #{params.inspect}\n\n"+
          "Signature: #{signature}"
          )
        return ["Not authorized", 401]
      end

      if create_event(payload: params)
        response = Twilio::TwiML::Response.new do |r|
          if interpolated['reply_text'].present?
            r.Message interpolated['reply_text']
          end
        end
        return [response.text, 201, "text/xml"]
      else
        return ["Bad request", 400]
      end
    end
  end
end
