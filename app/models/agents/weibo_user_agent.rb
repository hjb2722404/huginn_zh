# encoding: utf-8 

module Agents
  class WeiboUserAgent < Agent
    include WeiboConcern

    cannot_receive_events!

    description <<-MD
      The Weibo User Agent 跟踪指定微博用户的时间线。 它使用此端点：http：//open.weibo.com/wiki/2/statuses/user_timeline/en

      #{'## Include `weibo_2` in your Gemfile to use this Agent!' if dependencies_missing?}

      您必须首先设置一个微博应用程序并生成一个`acess_token`来进行身份验证。 在选项中为您的微博应用程序提供`app_key`和`app_secret`。

      指定要查看其时间线的微博用户的`uid`。

       将`expected_update_period_in_days`设置为您希望在此代理创建的事件之间传递的最长时间。
    MD

    event_description <<-MD
      Events are the raw JSON provided by the Weibo API. Should look something like:

          {
            "created_at": "Tue May 31 17:46:55 +0800 2011",
            "id": 11488058246,
            "text": "求关注。",
            "source": "<a href=\"http://weibo.com\" rel=\"nofollow\">新浪微博</a>",
            "favorited": false,
            "truncated": false,
            "in_reply_to_status_id": "",
            "in_reply_to_user_id": "",
            "in_reply_to_screen_name": "",
            "geo": null,
            "mid": "5612814510546515491",
            "reposts_count": 8,
            "comments_count": 9,
            "annotations": [],
            "user": {
                "id": 1404376560,
                "screen_name": "zaku",
                "name": "zaku",
                "province": "11",
                "city": "5",
                "location": "北京 朝阳区",
                "description": "人生五十年，乃如梦如幻；有生斯有死，壮士复何憾。",
                "url": "http://blog.sina.com.cn/zaku",
                "profile_image_url": "http://tp1.sinaimg.cn/1404376560/50/0/1",
                "domain": "zaku",
                "gender": "m",
                "followers_count": 1204,
                "friends_count": 447,
                "statuses_count": 2908,
                "favourites_count": 0,
                "created_at": "Fri Aug 28 00:00:00 +0800 2009",
                "following": false,
                "allow_all_act_msg": false,
                "remark": "",
                "geo_enabled": true,
                "verified": false,
                "allow_all_comment": true,
                "avatar_large": "http://tp1.sinaimg.cn/1404376560/180/0/1",
                "verified_reason": "",
                "follow_me": false,
                "online_status": 0,
                "bi_followers_count": 215
          }
        }
    MD

    default_schedule "every_1h"

    def validate_options
      unless options['uid'].present? &&
             options['expected_update_period_in_days'].present?
        errors.add(:base, "expected_update_period_in_days and uid are required")
      end
    end

    def working?
      event_created_within?(interpolated['expected_update_period_in_days']) && !recent_error_logs?
    end

    def default_options
      {
        'uid' => "",
        'access_token' => "---",
        'app_key' => "---",
        'app_secret' => "---",
        'expected_update_period_in_days' => "2"
      }
    end

    def check
      since_id = memory['since_id'] || nil
      opts = {:uid => interpolated['uid'].to_i}
      opts.merge! :since_id => since_id unless since_id.nil?

      # http://open.weibo.com/wiki/2/statuses/user_timeline/en
      resp = weibo_client.statuses.user_timeline opts
      if resp[:statuses]


        resp[:statuses].each do |status|
          memory['since_id'] = status.id if !memory['since_id'] || (status.id > memory['since_id'])

          create_event :payload => status.as_json
        end
      end

      save!
    end
  end
end