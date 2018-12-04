module Agents
  class GrowlAgent < Agent
    include FormConfigurable
    attr_reader :growler

    cannot_be_scheduled!
    cannot_create_events!
    can_dry_run!

    gem_dependency_check { defined?(Growl) }

    description <<-MD
      Growl代理会立即将收到的任何事件发送到Growl GNTP服务器。

      Growl网络传输协议（GNTP）是一种协议，允许应用程序和集中通知系统（如Growl for Mac OS X）之间的双向通信，并允许两台运行集中通知系统的机器之间进行双向通信，以进行通知转发

      #{'## Include `ruby-growl` in your Gemfile to use this Agent!' if dependencies_missing?}

      选项消息将包含Growl通知的正文，而主题选项将包含Growl通知的标题。 所有其他选项都是可选的。 当`callback_url`设置为URL时，单击该通知将打开默认浏览器中的链接.

      将`expected_receive_period_in_days`设置为您希望在此代理接收的事件之间传递的最长时间。

      查看[Wiki](https://github.com/huginn/huginn/wiki/Formatting-Events-using-Liquid) 以了解有关液体模板的更多信息。
    MD

    def default_options
      {
          'growl_server' => 'localhost',
          'growl_password' => '',
          'growl_app_name' => 'HuginnGrowl',
          'growl_notification_name' => 'Notification',
          'expected_receive_period_in_days' => "2",
          'subject' => '{{subject}}',
          'message' => '{{message}}',
          'sticky' => 'false',
          'priority' => '0'
      }
    end

    form_configurable :growl_server
    form_configurable :growl_password
    form_configurable :growl_app_name
    form_configurable :growl_notification_name
    form_configurable :expected_receive_period_in_days
    form_configurable :subject
    form_configurable :message, type: :text
    form_configurable :sticky, type: :boolean
    form_configurable :priority
    form_configurable :callback_url

    def working?
      last_receive_at && last_receive_at > options['expected_receive_period_in_days'].to_i.days.ago && !recent_error_logs?
    end

    def validate_options
      unless options['growl_server'].present? && options['expected_receive_period_in_days'].present?
        errors.add(:base, "growl_server and expected_receive_period_in_days are required fields")
      end
    end

    def register_growl
      @growler = Growl::GNTP.new(interpolated['growl_server'], interpolated['growl_app_name'])
      @growler.password = interpolated['growl_password']
      @growler.add_notification(interpolated['growl_notification_name'])
    end

    def notify_growl(subject:, message:, priority:, sticky:, callback_url:)
      @growler.notify(interpolated['growl_notification_name'], subject, message, priority, sticky, nil, callback_url)
    end

    def receive(incoming_events)
      incoming_events.each do |event|
        interpolate_with(event) do
          register_growl
          message = interpolated[:message]
          subject = interpolated[:subject]
          if message.present? && subject.present?
            log "Sending Growl notification '#{subject}': '#{message}' to #{interpolated(event)['growl_server']} with event #{event.id}"
            notify_growl(subject: subject,
                         message: message,
                         priority: interpolated[:priority].to_i,
                         sticky: boolify(interpolated[:sticky]) || false,
                         callback_url: interpolated[:callback_url].presence)
          else
            log "Event #{event.id} not sent, message and subject expected"
          end
        end
      end
    end
  end
end
