module Agents
  class HipchatAgent < Agent
    include FormConfigurable

    cannot_be_scheduled!
    cannot_create_events!
    no_bulk_receive!

    gem_dependency_check { defined?(HipChat) }

    description <<-MD
      Hipchat Agent将消息发送到Hipchat Room

      #{'## Include `hipchat` in your Gemfile to use this Agent!' if dependencies_missing?}

      要进行身份验证，您需要设置auth_token，您可以在Hipchat Group Admin页面上找到一个，您可以在此处找到：

      `https://`yoursubdomain`.hipchat.com/admin/api`

      将room_name更改为要向其发送通知的房间的名称。

      您可以提供用户名和消息。 如果要使用提及更改格式为“文本”（详细信息）

      如果您希望您的消息通知会议室成员，请将通知更改为“True”。

      通过颜色属性（“黄色”，“红色”，“绿色”，“紫色”，“灰色”或“随机”之一）修改消息的背景颜色

      查看Wiki以了解有关liquid模板的更多信息。
    MD

    def default_options
      {
        'auth_token' => '',
        'room_name' => '',
        'username' => "Huginn",
        'message' => "Hello from Huginn!",
        'notify' => false,
        'color' => 'yellow',
        'format' => 'html'
      }
    end

    form_configurable :auth_token, roles: :validatable
    form_configurable :room_name, roles: :completable
    form_configurable :username
    form_configurable :message, type: :text
    form_configurable :notify, type: :boolean
    form_configurable :color, type: :array, values: ['yellow', 'red', 'green', 'purple', 'gray', 'random']
    form_configurable :format, type: :array, values: ['html', 'text']

    def validate_auth_token
      client.rooms
      true
    rescue HipChat::UnknownResponseCode
      return false
    end

    def complete_room_name
      client.rooms.collect { |room| {text: room.name, id: room.name} }
    end

    def validate_options
      errors.add(:base, "you need to specify a hipchat auth_token or provide a credential named hipchat_auth_token") unless options['auth_token'].present? || credential('hipchat_auth_token').present?
      errors.add(:base, "you need to specify a room_name or a room_name_path") if options['room_name'].blank? && options['room_name_path'].blank?
    end

    def working?
      (last_receive_at.present? && last_error_log_at.nil?) || (last_receive_at.present? && last_error_log_at.present? && last_receive_at > last_error_log_at)
    end

    def receive(incoming_events)
      incoming_events.each do |event|
        mo = interpolated(event)
        client[mo[:room_name]].send(mo[:username][0..14], mo[:message],
                                      notify: boolify(mo[:notify]),
                                      color: mo[:color],
                                      message_format: mo[:format].presence || 'html'
                                    )
      end
    end

    private
    def client
      @client ||= HipChat::Client.new(interpolated[:auth_token].presence || credential('hipchat_auth_token'))
    end
  end
end
