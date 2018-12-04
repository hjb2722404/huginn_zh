module TwitterConcern
  extend ActiveSupport::Concern

  included do
    include Oauthable

    validate :validate_twitter_options
    valid_oauth_providers :twitter

    gem_dependency_check { defined?(Twitter) && Devise.omniauth_providers.include?(:twitter) && ENV['TWITTER_OAUTH_KEY'].present? && ENV['TWITTER_OAUTH_SECRET'].present? }
  end

  def validate_twitter_options
    unless twitter_consumer_key.present? &&
      twitter_consumer_secret.present? &&
      twitter_oauth_token.present? &&
      twitter_oauth_token_secret.present?
      errors.add(:base, "Twitter consumer_key, consumer_secret, oauth_token, and oauth_token_secret are required to authenticate with the Twitter API.  You can provide these as options to this Agent, or as Credentials with the same names, but starting with 'twitter_'.")
    end
  end

  def twitter_consumer_key
    (config = Devise.omniauth_configs[:twitter]) && config.strategy.consumer_key
  end

  def twitter_consumer_secret
    (config = Devise.omniauth_configs[:twitter]) && config.strategy.consumer_secret
  end

  def twitter_oauth_token
    service && service.token
  end

  def twitter_oauth_token_secret
    service && service.secret
  end

  def twitter
    @twitter ||= Twitter::REST::Client.new do |config|
      config.consumer_key = twitter_consumer_key
      config.consumer_secret = twitter_consumer_secret
      config.access_token = twitter_oauth_token
      config.access_token_secret = twitter_oauth_token_secret
    end
  end

  module ClassMethods
    def twitter_dependencies_missing
      if ENV['TWITTER_OAUTH_KEY'].blank? || ENV['TWITTER_OAUTH_SECRET'].blank?
        "## 在您的环境中设置TWITTER_OAUTH_KEY和TWITTER_OAUTH_SECRET以使用Twitter代理."
      elsif !defined?(Twitter) || !Devise.omniauth_providers.include?(:twitter)
        "## 在你的Gemfile中包含`twitter`，`omniauth-twitter`和`cantino-twitter-stream` gems以使用Twitter代理."
      end
    end
  end
end

class Twitter::Error
  remove_const :FORBIDDEN_MESSAGES

  FORBIDDEN_MESSAGES = proc do |message|
    case message
    when /(?=.*status).*duplicate/i
      # - "Status is a duplicate."
      Twitter::Error::DuplicateStatus
    when /already favorited/i
      # - "You have already favorited this status."
      Twitter::Error::AlreadyFavorited
    when /already retweeted|Share validations failed/i
      # - "You have already retweeted this Tweet." (Nov 2017-)
      # - "You have already retweeted this tweet." (?-Nov 2017)
      # - "sharing is not permissible for this status (Share validations failed)" (-? 2017)
      Twitter::Error::AlreadyRetweeted
    end
  end
end
