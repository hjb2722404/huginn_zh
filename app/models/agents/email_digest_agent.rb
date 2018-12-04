module Agents
  class EmailDigestAgent < Agent
    include EmailConcern

    default_schedule "5am"

    cannot_create_events!

    description <<-MD
      
      Email Digest Agent-电子邮件摘要代理会收集发送给它的任何事件，并在安排时通过电子邮件发送所有事件。 已使用事件的数量还依赖于发出代理的Keep事件选项，这意味着如果事件在此代理程序计划运行之前到期，它们将不会出现在电子邮件中。

      默认情况下，在列出事件之前，将有主题和可选标题。 如果事件的有效负载包含消息，则会突出显示该消息，否则将显示其有效负载中的所有内容。

      您可以为电子邮件指定一个或多个收件人，也可以跳过该选项以将电子邮件发送到您帐户的默认电子邮件地址。

      您可以提供电子邮件的发件人地址，或将其留空以默认为EMAIL_FROM_ADDRESS（from_address@gmail.com）的值。

      您可以为电子邮件提供`content_type`，并指定要发送的text / plain或text / html。 如果未指定content_type，则收件人电子邮件服务器将确定正确的呈现。

      将`expected_receive_period_in_days`设置为您希望在此代理接收的事件之间传递的最长时间。
    MD

    def default_options
      {
          'subject' => "You have some notifications!",
          'headline' => "Your notifications:",
          'expected_receive_period_in_days' => "2"
      }
    end

    def working?
      received_event_without_error?
    end

    def receive(incoming_events)
      self.memory['events'] ||= []
      incoming_events.each do |event|
        self.memory['events'] << event.id
      end
    end

    def check
      if self.memory['events'] && self.memory['events'].length > 0
        payloads = received_events.reorder("events.id ASC").where(id: self.memory['events']).pluck(:payload).to_a
        groups = payloads.map { |payload| present(payload) }
        recipients.each do |recipient|
          begin
            SystemMailer.send_message(
              to: recipient,
              from: interpolated['from'],
              subject: interpolated['subject'],
              headline: interpolated['headline'],
              content_type: interpolated['content_type'],
              groups: groups
            ).deliver_now

            log "Sent digest mail to #{recipient}"
          rescue => e
            error("Error sending digest mail to #{recipient}: #{e.message}")
            raise
          end
        end
        self.memory['events'] = []
      end
    end
  end
end
