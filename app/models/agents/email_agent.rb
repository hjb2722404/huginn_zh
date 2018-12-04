module Agents
  class EmailAgent < Agent
    include EmailConcern

    cannot_be_scheduled!
    cannot_create_events!
    no_bulk_receive!

    description <<-MD
      电子邮件代理会立即发送通过电子邮件收到的任何事件。

      您可以通过提供主题选项来指定电子邮件的主题行，该选项可以包含Liquid格式。 例如，您可以提供“Huginn电子邮件”来设置一个简单的主题，或{{subject}}来使用来自传入事件的主题密钥。

      默认情况下，电子邮件正文将包含可选标题，后跟事件键的列表。

      您可以通过包含可选的正文参数来自定义电子邮件正文。 与主题一样，正文可以是简单的消息或液体模板。 您只能发送事件的some_text字段，并将正文设置为{{some_text}}。 正文可以包含简单的HTML并将被清理。 请注意，使用body时，它将使用<html>和<body>标记进行包装，因此您无需自己添加它们。

      您可以为电子邮件指定一个或多个收件人，也可以跳过该选项以将电子邮件发送到您帐户的默认电子邮件地址。

      您可以提供电子邮件的发件人地址，或将其留空以默认为EMAIL_FROM_ADDRESS（from_address@gmail.com）的值。

      您可以为电子邮件提供`content_type` ，并指定要发送的text / plain或text / html。 如果未指定content_type，则收件人电子邮件服务器将确定正确的呈现。

      将`expected_receive_period_in_days`设置为您希望在此代理接收的事件之间传递的最长时间。
    MD

    def default_options
      {
          'subject' => "You have a notification!",
          'headline' => "Your notification:",
          'expected_receive_period_in_days' => "2"
      }
    end

    def working?
      received_event_without_error?
    end

    def receive(incoming_events)
      incoming_events.each do |event|
        recipients(event.payload).each do |recipient|
          begin
            SystemMailer.send_message(
              to: recipient,
              from: interpolated(event)['from'],
              subject: interpolated(event)['subject'],
              headline: interpolated(event)['headline'],
              body: interpolated(event)['body'],
              content_type: interpolated(event)['content_type'],
              groups: [present(event.payload)]
            ).deliver_now
            log "Sent mail to #{recipient} with event #{event.id}"
          rescue => e
            error("Error sending mail to #{recipient} with event #{event.id}: #{e.message}")
            raise
          end
        end
      end
    end
  end
end
