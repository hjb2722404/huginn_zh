module Agents
  class TwitterPublishAgent < Agent
    include TwitterConcern

    cannot_be_scheduled!

    description <<-MD
      Twitter Publish Agent 从其收到的事件中发布推文.

      #{twitter_dependencies_missing if dependencies_missing?}

      为了能够使用此代理，您需要首先在[“服务”](/services)功能中使用Twitter进行身份验证。

      
      您还必须指定`message`参数，您可以使用 [Liquid](https://github.com/huginn/huginn/wiki/Formatting-Events-using-Liquid) 格式化消息。

      将`expected_update_period_in_days`设置为您希望在此代理创建的事件之间传递的最长时间。
    MD

    def validate_options
      errors.add(:base, "expected_update_period_in_days is required") unless options['expected_update_period_in_days'].present?
    end

    def working?
      event_created_within?(interpolated['expected_update_period_in_days']) && most_recent_event && most_recent_event.payload['success'] == true && !recent_error_logs?
    end

    def default_options
      {
        'expected_update_period_in_days' => "10",
        'message' => "{{text}}"
      }
    end

    def receive(incoming_events)
      # if there are too many, dump a bunch to avoid getting rate limited
      if incoming_events.count > 20
        incoming_events = incoming_events.first(20)
      end
      incoming_events.each do |event|
        tweet_text = interpolated(event)['message']
        begin
          tweet = publish_tweet tweet_text
          create_event :payload => {
            'success' => true,
            'published_tweet' => tweet_text,
            'tweet_id' => tweet.id,
            'agent_id' => event.agent_id,
            'event_id' => event.id
          }
        rescue Twitter::Error => e
          create_event :payload => {
            'success' => false,
            'error' => e.message,
            'failed_tweet' => tweet_text,
            'agent_id' => event.agent_id,
            'event_id' => event.id
          }
        end
      end
    end

    def publish_tweet(text)
      twitter.update(text)
    end
  end
end
