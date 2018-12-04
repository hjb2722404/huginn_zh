module Agents
  class TumblrLikesAgent < Agent
    include TumblrConcern

    gem_dependency_check { defined?(Tumblr::Client) }

    description <<-MD
      Tumblr Likes Agent检查来自特定博客的喜欢的Tumblr帖子。

      #{'## Include `tumblr_client` and `omniauth-tumblr` in your Gemfile to use this Agent!' if dependencies_missing?}

      为了能够使用此代理，您需要首先在“服务”部分中使用Tumblr进行身份验证。


      **必填字段：**

      `blog_name` 您查询的Tumblr URL（例如“staff.tumblr.com”）

      将expected_update_period_in_days设置为您希望在此代理创建的事件之间传递的最长时间。
    MD

    default_schedule 'every_1h'

    def validate_options
      errors.add(:base, 'blog_name is required') unless options['blog_name'].present?
      errors.add(:base, 'expected_update_period_in_days is required') unless options['expected_update_period_in_days'].present?
    end

    def working?
      event_created_within?(options['expected_update_period_in_days']) && !recent_error_logs?
    end

    def default_options
      {
        'expected_update_period_in_days' => '10',
        'blog_name' => 'someblog',
      }
    end

    def check
      memory[:ids] ||= []
      memory[:last_liked] ||= 0

      # Request Likes of blog_name after the last stored timestamp (or default of 0)
      liked = tumblr.blog_likes(options['blog_name'], after: memory[:last_liked])

      if liked['liked_posts']
        # Loop over all liked posts which came back from Tumblr, add to memory, and create events.
        liked['liked_posts'].each do |post|
          unless memory[:ids].include?(post['id'])
            memory[:ids].push(post['id'])
            memory[:last_liked] = post['liked_timestamp'] if post['liked_timestamp'] > memory[:last_liked]
            create_event(payload: post)
          end
        end
      elsif liked['status'] && liked['msg']
        # If there was a problem fetching likes (like 403 Forbidden or 404 Not Found) create an error message.
        error "Error finding liked posts for #{options['blog_name']}: #{liked['status']} #{liked['msg']}"
      end

      # Store only the last 50 (maximum the API will return) IDs in memory to prevent performance issues.
      memory[:ids] = memory[:ids].last(50) if memory[:ids].length > 50
    end
  end
end
