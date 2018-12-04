module Agents
  class TwitterFavorites < Agent
    include TwitterConcern

    cannot_receive_events!

    description <<-MD
      Twitter Favorites List Agent 跟踪指定Twitter用户的收藏夹列表.

      #{twitter_dependencies_missing if dependencies_missing?}

      为了能够使用此代理，您需要首先在“服务”部分中使用Twitter进行身份验证.

      您还必须提供Twitter用户的用户名，要监控的最新推文的数量和“历史记录”作为将在内存中保存的推文的数量.

      将expected_update_period_in_days设置为您希望在此代理创建的事件之间传递的最长时间。
      
      将starting_at设置为日期/时间（例如，2014年6月2日00:38:12 +0000）你想开始接收推文（默认：代理商的created_at）
    MD

    event_description <<-MD
      Events are the raw JSON provided by the [Twitter API](https://dev.twitter.com/docs/api/1.1/get/favorites/list). Should look something like:
          {
             ... every Tweet field, including ...
            "text": "something",
            "user": {
              "name": "Mr. Someone",
              "screen_name": "Someone",
              "location": "Vancouver BC Canada",
              "description":  "...",
              "followers_count": 486,
              "friends_count": 1983,
              "created_at": "Mon Aug 29 23:38:14 +0000 2011",
              "time_zone": "Pacific Time (US & Canada)",
              "statuses_count": 3807,
              "lang": "en"
            },
            "retweet_count": 0,
            "entities": ...
            "lang": "en"
          }
    MD

    default_schedule "every_1h"

    def working?
      event_created_within?(interpolated['expected_update_period_in_days']) && !recent_error_logs?
    end

    def default_options
      {
        'username' => 'tectonic',
        'number' => '10',
        'history' => '100',
        'expected_update_period_in_days' => '2'
      }
    end

     def validate_options
      errors.add(:base, "username is required") unless options['username'].present?
      errors.add(:base, "number is required") unless options['number'].present?
      errors.add(:base, "history is required") unless options['history'].present?
      errors.add(:base, "expected_update_period_in_days is required") unless options['expected_update_period_in_days'].present?

      if options[:starting_at].present?
        Time.parse(options[:starting_at]) rescue errors.add(:base, "Error parsing starting_at")
      end
    end

    def starting_at
      if interpolated[:starting_at].present?
        Time.parse(interpolated[:starting_at]) rescue created_at
      else
        created_at
      end
    end

    def check
      opts = {:count => interpolated['number'], tweet_mode: 'extended'}
      tweets = twitter.favorites(interpolated['username'], opts)
      memory[:last_seen] ||= []

      tweets.each do |tweet|
        unless memory[:last_seen].include?(tweet.id) || tweet.created_at < starting_at
          memory[:last_seen].push(tweet.id)
          memory[:last_seen].shift if memory[:last_seen].length > interpolated['history'].to_i
          create_event payload: tweet.attrs
        end
      end
    end
  end
end
