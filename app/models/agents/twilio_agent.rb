require 'securerandom'

module Agents
  class TwilioAgent < Agent
    cannot_be_scheduled!
    cannot_create_events!
    no_bulk_receive!

    gem_dependency_check { defined?(Twilio) }

    description <<-MD
      Twilio Agent接收并收集事件并通过短信发送（最多160个字符）或在安排时给您打电话。

      #{'## Include `twilio-ruby` in your Gemfile to use this Agent!' if dependencies_missing?}

      假设事件具有消息，文本或短信密钥，其值作为文本消息/呼叫的内容发送。 如果您的事件未提供这些密钥，则可以使用EventFormattingAgent。

      将receiver_cell设置为接收文本消息/呼叫的号码，将sender_cell设置为发送它们的号码。

      `expected_receive_period_in_days`  是您希望在此代理接收的事件之间传递的最大天数。

      如果您想接听电话，请将receive_call设置为true。 在这种情况下，server_url必须设置为您的Huginn安装的URL（可能是“https：// localhost：3000”），该URL必须可通过Web访问。 务必正确设置http / https。
    MD

    def default_options
      {
        'account_sid' => 'ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
        'auth_token' => 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
        'sender_cell' => 'xxxxxxxxxx',
        'receiver_cell' => 'xxxxxxxxxx',
        'server_url'    => 'http://somename.com:3000',
        'receive_text'  => 'true',
        'receive_call'  => 'false',
        'expected_receive_period_in_days' => '1'
      }
    end

    def validate_options
      unless options['account_sid'].present? && options['auth_token'].present? && options['sender_cell'].present? && options['receiver_cell'].present? && options['expected_receive_period_in_days'].present? && options['receive_call'].present? && options['receive_text'].present?
        errors.add(:base, 'account_sid, auth_token, sender_cell, receiver_cell, receive_text, receive_call and expected_receive_period_in_days are all required')
      end
    end

    def receive(incoming_events)
      memory['pending_calls'] ||= {}
      interpolate_with_each(incoming_events) do |event|
        message = (event.payload['message'].presence || event.payload['text'].presence || event.payload['sms'].presence).to_s
        if message.present?
          if boolify(interpolated['receive_call'])
            secret = SecureRandom.hex 3
            memory['pending_calls'][secret] = message
            make_call secret
          end

          if boolify(interpolated['receive_text'])
            message = message.slice 0..160
            send_message message
          end
        end
      end
    end

    def working?
      last_receive_at && last_receive_at > interpolated['expected_receive_period_in_days'].to_i.days.ago && !recent_error_logs?
    end

    def send_message(message)
      client.account.messages.create :from => interpolated['sender_cell'],
                                         :to => interpolated['receiver_cell'],
                                         :body => message
    end

    def make_call(secret)
      client.account.calls.create :from => interpolated['sender_cell'],
                                  :to => interpolated['receiver_cell'],
                                  :url => post_url(interpolated['server_url'], secret)
    end

    def post_url(server_url, secret)
      "#{server_url}/users/#{user.id}/web_requests/#{id}/#{secret}"
    end

    def receive_web_request(params, method, format)
      if memory['pending_calls'].has_key? params['secret']
        response = Twilio::TwiML::Response.new {|r| r.Say memory['pending_calls'][params['secret']], :voice => 'woman'}
        memory['pending_calls'].delete params['secret']
        [response.text, 200]
      end
    end

    def client
      @client ||= Twilio::REST::Client.new interpolated['account_sid'], interpolated['auth_token']
    end
  end
end
