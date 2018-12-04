module Agents
  class TwitterSearchAgent < Agent
    include TwitterConcern

    cannot_receive_events!

    description <<-MD
      Twitter搜索代理执行并发出指定Twitter搜索的结果。

      #{twitter_dependencies_missing if dependencies_missing?}

      如果你想从Twitter获得关于频繁更新的条目的实时数据，你肯定应该使用Twitter Stream Agent。

      为了能够使用此代理，您需要首先在[“服务”](/services)部分中使用Twitter进行身份验证。

      您必须提供所需的 `search`.
      
      设置result_type以指定您希望接收哪种[类型](https://dev.twitter.com/rest/reference/get/search/tweets) 的搜索结果。 选项是“mixed”(混合)，“recent”（近期）和“popular”（流行）。 （默认：mixed）

      设置max_results以限制每次运行检索的结果数量（默认值：500。API速率限制为每15分钟约18,000。[点击此处](https://dev.twitter.com/rest/public/rate-limiting)了解有关速率限制的更多信息。

      将expected_update_period_in_days设置为您希望在此代理创建的事件之间传递的最长时间。

      将starting_at设置为日期/时间（例如，2014年6月2日00:38:12 +0000）你想开始接收推文（默认：代理商的created_at）
    MD

    event_description <<-MD
      Events are the raw JSON provided by the [Twitter API](https://dev.twitter.com/rest/reference/get/search/tweets). Should look something like:

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
        'search' => 'freebandnames',
        'expected_update_period_in_days' => '2'
      }
    end

    def validate_options
      errors.add(:base, "search is required") unless options['search'].present?
      errors.add(:base, "expected_update_period_in_days is required") unless options['expected_update_period_in_days'].present?

      if options[:starting_at].present?
        Time.parse(interpolated[:starting_at]) rescue errors.add(:base, "Error parsing starting_at")
      end
    end

    def starting_at
      if interpolated[:starting_at].present?
        Time.parse(interpolated[:starting_at]) rescue created_at
      else
        created_at
      end
    end

    def max_results
      (interpolated['max_results'].presence || 500).to_i
    end

    def check
      since_id = memory['since_id'] || nil
      opts = {include_entities: true, tweet_mode: 'extended'}
      opts.merge! result_type: interpolated[:result_type] if interpolated[:result_type].present?
      opts.merge! since_id: since_id unless since_id.nil?

      # http://www.rubydoc.info/gems/twitter/Twitter/REST/Search
      tweets = twitter.search(interpolated['search'], opts).take(max_results)

      tweets.each do |tweet|
        if (tweet.created_at >= starting_at)
          memory['since_id'] = tweet.id if !memory['since_id'] || (tweet.id > memory['since_id'])

          create_event payload: tweet.attrs
        end
      end

      save!
    end
  end
end
