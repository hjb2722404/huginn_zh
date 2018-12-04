module Agents
  class SlackAgent < Agent
    DEFAULT_USERNAME = 'Huginn'
    ALLOWED_PARAMS = ['channel', 'username', 'unfurl_links', 'attachments']

    cannot_be_scheduled!
    cannot_create_events!
    no_bulk_receive!

    gem_dependency_check { defined?(Slack) }

    description <<-MD
      Slack Agent允许您接收事件并向[Slack](https://slack.com/)发送通知 .

      #{'## Include `slack-notifier` in your Gemfile to use this Agent!' if dependencies_missing?}

      首先，您将首先需要配置传入的webhook.

      - 转到https://my.slack.com/services/new/incoming-webhook，选择默认频道并添加集成。

      您的webhook网址将如下所示: `https://hooks.slack.com/services/some/random/characters`

      配置webhook后，可以将其用于发布到其他渠道或直接发送给团队成员。 要向团队成员发送私人消息，请使用他们的@username作为频道。 可以使用[Liquid](https://github.com/huginn/huginn/wiki/Formatting-Events-using-Liquid)格式化消息.

      最后，您可以在图标中为此webhook设置自定义图标，可以是[emoji](http://www.emoji-cheat-sheet.com) ，也可以是图像的URL。 将此字段留空将使用webhook的默认图标。
    MD

    def default_options
      {
        'webhook_url' => 'https://hooks.slack.com/services/...',
        'channel' => '#general',
        'username' => DEFAULT_USERNAME,
        'message' => "Hey there, It's Huginn",
        'icon' => '',
      }
    end

    def validate_options
      unless options['webhook_url'].present? ||
             (options['auth_token'].present? && options['team_name'].present?)  # compatibility
        errors.add(:base, "webhook_url is required")
      end

      errors.add(:base, "channel is required") unless options['channel'].present?
    end

    def working?
      received_event_without_error?
    end

    def webhook_url
      case
      when url = interpolated[:webhook_url].presence
        url
      when (team = interpolated[:team_name].presence) && (token = interpolated[:auth_token])
        webhook = interpolated[:webhook].presence || 'incoming-webhook'
        # old style webhook URL
        "https://#{Rack::Utils.escape_path(team)}.slack.com/services/hooks/#{Rack::Utils.escape_path(webhook)}?token=#{Rack::Utils.escape(token)}"
      end
    end

    def username
      interpolated[:username].presence || DEFAULT_USERNAME
    end

    def slack_notifier
      @slack_notifier ||= Slack::Notifier.new(webhook_url, username: username)
    end

    def filter_options(opts)
      opts.select { |key, value| ALLOWED_PARAMS.include? key }.symbolize_keys
    end

    def receive(incoming_events)
      incoming_events.each do |event|
        opts = interpolated(event)
        slack_opts = filter_options(opts)
        if opts[:icon].present?
          if /^:/.match(opts[:icon])
            slack_opts[:icon_emoji] = opts[:icon]
          else
            slack_opts[:icon_url] = opts[:icon]
          end
        end
        slack_notifier.ping opts[:message], slack_opts
      end
    end
  end
end
