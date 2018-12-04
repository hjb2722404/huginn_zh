module Agents
  class TwitterActionAgent < Agent
    include TwitterConcern

    cannot_be_scheduled!

    description <<-MD
      Twitter动作代理能够从其收到的事件转发或收藏推文。

      #{ twitter_dependencies_missing if dependencies_missing? }

      它期望消耗由twitter代理生成的事件，其中有效载荷是推特信息的散列。 现有的TwitterStreamAgent是此代理的有效事件生成器的一个示例。

      为了能够使用此代理，您需要首先在“服务”部分中使用Twitter进行身份验证。

      将expected_receive_period_in_days设置为您希望在此代理接收的事件之间传递的最长时间。 将转发设置为true或false。 将收藏夹设置为true或false。 将emit_error_events设置为true以在操作失败时发出事件，否则将重试该操作。
    MD

    def validate_options
      unless options['expected_receive_period_in_days'].present?
        errors.add(:base, "expected_receive_period_in_days is required")
      end
      unless retweet? || favorite?
        errors.add(:base, "at least one action must be true")
      end
      if emit_error_events?.nil?
        errors.add(:base, "emit_error_events must be set to 'true' or 'false'")
      end
    end

    def working?
      last_receive_at && last_receive_at > interpolated['expected_receive_period_in_days'].to_i.days.ago && !recent_error_logs?
    end

    def default_options
      {
        'expected_receive_period_in_days' => '2',
        'favorite' => 'false',
        'retweet' => 'true',
        'emit_error_events' => 'false'
      }
    end

    def retweet?
      boolify(options['retweet'])
    end

    def favorite?
      boolify(options['favorite'])
    end

    def emit_error_events?
      boolify(options['emit_error_events'])
    end

    def receive(incoming_events)
      tweets = tweets_from_events(incoming_events)

      begin
        twitter.favorite(tweets) if favorite?
        twitter.retweet(tweets) if retweet?
      rescue Twitter::Error => e
        case e
        when Twitter::Error::AlreadyRetweeted, Twitter::Error::AlreadyFavorited
          error e.message
        else
          raise e unless emit_error_events?
        end
        if emit_error_events?
          create_event payload: {
            'success' => false,
            'error' => e.message,
            'tweets' => Hash[tweets.map { |t| [t.id, t.text] }],
            'agent_ids' => incoming_events.map(&:agent_id),
            'event_ids' => incoming_events.map(&:id)
          }
        end
      end
    end

    def tweets_from_events(events)
      events.map do |e|
        Twitter::Tweet.new(id: e.payload["id"], text: e.payload["text"])
      end
    end
  end
end
