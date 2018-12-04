module Agents
  class WebhookAgent < Agent
    include WebRequestConcern

    cannot_be_scheduled!
    cannot_receive_events!

    description do <<-MD
      Webhook Agent将通过从任何来源接收webhook来创建事件。 要使用此代理创建事件，请发出POST请求：

      ```
         https://#{ENV['DOMAIN']}/users/#{user.id}/web_requests/#{id || ':id'}/#{options['secret'] || ':secret'}
      ```

      #{' 保存代理后，上面的占位符符号将替换为其值.' unless id}

      配置项说明:

        * `secret` - 主机提供的用于身份验证的令牌。
        * `expected_receive_period_in_days` - 您希望以这种方式接收事件的频率。 用于确定代理是否正常工作。
        * `payload_path` -  POST主体中属性的JSONPath，用作事件的有效内容。 设置成`.`将返回整个消息。 如果`payload_path`指向数组，则将为数组中每个元素创建事件。
        * `verbs` - 逗号分隔的代理将接受的http动词列表。 例如，“post，get”将启用POST和GET请求。 默认为“post”。
        * `response` - 请求的响应消息。 默认为“事件已创建” 。
        * `response_headers` - 具有任何自定义响应标头的对象。 (例如: `{"Access-Control-Allow-Origin": "*"}`)
        * `code` - 请求的响应代码。 默认为'201'。 如果代码为“301”或“302”，则请求将自动重定向到“响应”中定义的URL。
        * `recaptcha_secret` - 将它设置为 reCAPTCHA“secret” 密钥可使您的代理使用 reCAPTCHA 验证传入请求。 不要忘记在原始表单中嵌入包含“site”键的reCAPTCHA片段。
        * `recaptcha_send_remote_addr` -  如果您的服务器已正确配置为将REMOTE_ADDR设置为每个访问者（而不是代理服务器的IP地址）的IP地址，请将此项设置为true。
      MD
    end

    event_description do
      <<-MD
        The event payload is based on the value of the `payload_path` option,
        which is set to `#{interpolated['payload_path']}`.
      MD
    end

    def default_options
      { "secret" => "supersecretstring",
        "expected_receive_period_in_days" => 1,
        "payload_path" => "some_key"
      }
    end

    def receive_web_request(params, method, format)
      # check the secret
      secret = params.delete('secret')
      return ["Not Authorized", 401] unless secret == interpolated['secret']

      # check the verbs
      verbs = (interpolated['verbs'] || 'post').split(/,/).map { |x| x.strip.downcase }.select { |x| x.present? }
      return ["Please use #{verbs.join('/').upcase} requests only", 401] unless verbs.include?(method)

      # check the code
      code = (interpolated['code'].presence || 201).to_i

      # check the reCAPTCHA response if required
      if recaptcha_secret = interpolated['recaptcha_secret'].presence
        recaptcha_response = params.delete('g-recaptcha-response') or
          return ["Not Authorized", 401]

        parameters = {
          secret: recaptcha_secret,
          response: recaptcha_response,
        }

        if boolify(interpolated['recaptcha_send_remote_addr'])
          parameters[:remoteip] = request.env['REMOTE_ADDR']
        end

        begin
          response = faraday.post('https://www.google.com/recaptcha/api/siteverify',
                                  parameters)
        rescue => e
          error "Verification failed: #{e.message}"
          return ["Not Authorized", 401]
        end

        JSON.parse(response.body)['success'] or
          return ["Not Authorized", 401]
      end

      [payload_for(params)].flatten.each do |payload|
        create_event(payload: payload)
      end

      if interpolated['response_headers'].presence
        [interpolated(params)['response'] || 'Event Created', code, "text/plain", interpolated['response_headers'].presence]
      else
        [interpolated(params)['response'] || 'Event Created', code]
      end
    end

    def working?
      event_created_within?(interpolated['expected_receive_period_in_days']) && !recent_error_logs?
    end

    def validate_options
      unless options['secret'].present?
        errors.add(:base, "Must specify a secret for 'Authenticating' requests")
      end

      if options['code'].present? && options['code'].to_s !~ /\A\s*(\d+|\{.*)\s*\z/
        errors.add(:base, "Must specify a code for request responses")
      end

      if options['code'].to_s.in?(['301', '302']) && !options['response'].present?
        errors.add(:base, "Must specify a url for request redirect")
      end
    end

    def payload_for(params)
      Utils.value_at(params, interpolated['payload_path']) || {}
    end
  end
end
