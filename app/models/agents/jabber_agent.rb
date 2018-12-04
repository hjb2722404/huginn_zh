module Agents
  class JabberAgent < Agent
    include LongRunnable
    include FormConfigurable

    cannot_be_scheduled!

    gem_dependency_check { defined?(Jabber) }

    description <<-MD
      Jabber代理会将收到的任何事件发送到您的Jabber / XMPP IM帐户。

      #{'## Include `xmpp4r` in your Gemfile to use this Agent!' if dependencies_missing?}

      为Jabber服务器指定jabber_server和jabber_port。

      消息从jabber_sender发送到jaber_receiver。 此消息可以包含在源的有效负载中找到的任何键，使用双花括号进行转义。 例如：“新闻故事：{{title}}：{{url}}”

      当connect_to_receiver设置为true时，JabberAgent将为它接收的每条消息发出一个事件。

      查看Wiki以了解有关liquid模板的更多信息。
    MD

    event_description <<-MD
      `event` will be set to either `on_join`, `on_leave`, `on_message`, `on_room_message` or `on_subject`

          {
            "event": "on_message",
            "time": null,
            "nick": "Dominik Sander",
            "message": "Hello from huginn."
          }
    MD

    def default_options
      {
        'jabber_server'   => '127.0.0.1',
        'jabber_port'     => '5222',
        'jabber_sender'   => 'huginn@localhost',
        'jabber_receiver' => 'muninn@localhost',
        'jabber_password' => '',
        'message'         => 'It will be {{temp}} out tomorrow',
        'expected_receive_period_in_days' => "2"
      }
    end

    form_configurable :jabber_server
    form_configurable :jabber_port
    form_configurable :jabber_sender
    form_configurable :jabber_receiver
    form_configurable :jabber_password
    form_configurable :message, type: :text
    form_configurable :connect_to_receiver, type: :boolean
    form_configurable :expected_receive_period_in_days

    def working?
      last_receive_at && last_receive_at > interpolated['expected_receive_period_in_days'].to_i.days.ago && !recent_error_logs?
    end

    def receive(incoming_events)
      incoming_events.each do |event|
        log "Sending IM to #{interpolated['jabber_receiver']} with event #{event.id}"
        deliver body(event)
      end
    end

    def validate_options
      errors.add(:base, "server and username is required") unless credentials_present?
    end

    def deliver(text)
      client.send Jabber::Message::new(interpolated['jabber_receiver'], text).set_type(:chat)
    end

    def start_worker?
      boolify(interpolated[:connect_to_receiver])
    end

    private

    def client
      Jabber::Client.new(Jabber::JID::new(interpolated['jabber_sender'])).tap do |sender|
        sender.connect(interpolated['jabber_server'], interpolated['jabber_port'] || '5222')
        sender.auth interpolated['jabber_password']
      end
    end

    def credentials_present?
      options['jabber_server'].present? && options['jabber_sender'].present? && options['jabber_receiver'].present?
    end

    def body(event)
      interpolated(event)['message']
    end

    class Worker < LongRunnable::Worker
      IGNORE_MESSAGES_FOR=5

      def setup
        require 'xmpp4r/muc/helper/simplemucclient'
      end

      def run
        @started_at = Time.now
        @client = client
        muc = Jabber::MUC::SimpleMUCClient.new(@client)

        [:on_join, :on_leave, :on_message, :on_room_message, :on_subject].each do |event|
          muc.__send__(event) do |*args|
            message_handler(event, args)
          end
        end

        muc.join(agent.interpolated['jabber_receiver'])

        sleep(1) while @client.is_connected?
      end

      def message_handler(event, args)
        return if Time.now - @started_at < IGNORE_MESSAGES_FOR

        time, nick, message = normalize_args(event, args)

        AgentRunner.with_connection do
          agent.create_event(payload: {event: event, time: time, nick: nick, message: message})
        end
      end

      def stop
        @client.close
        @client.stop
        thread.terminate
      end

      def client
        agent.send(:client)
      end

      private
      def normalize_args(event, args)
        case event
        when :on_join, :on_leave
          [args[0], args[1]]
        when :on_message, :on_subject
          args
        when :on_room_message
          [args[0], nil, args[1]]
        end
      end
    end
  end
end
