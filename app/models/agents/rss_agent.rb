module Agents
  class RssAgent < Agent
    include WebRequestConcern

    cannot_receive_events!
    can_dry_run!
    default_schedule "every_1d"

    gem_dependency_check { defined?(Feedjira::Feed) }

    DEFAULT_EVENTS_ORDER = [['{{date_published}}', 'time'], ['{{last_updated}}', 'time']]

    description do
      <<-MD
        RSS代理使用RSS源并在更改时发出事件

        此代理使用Feedjira作为基础，可以解析各种类型的RSS和Atom提要，并为FeedBurner，iTunes RSS等提供一些特殊处理程序。 但是，受支持的字段受其一般和抽象性质的限制。 对于具有其他字段类型的复杂Feed，我们建议使用WebsiteAgent。 看[这个例子](https://github.com/huginn/huginn/wiki/Agent-configuration-examples#itunes-trailers)。

        如果要输出RSS源，请使用DataOutputAgent。  

        配置项:

          * `url` - RSS提要的URL（也可以使用URL数组;在提要中具有相同guid的项目将被视为重复项）
          * `include_feed_info` - 设置为true以在每个事件中包含Feed信息
          * `clean` - 设置为true以将描述和内容清理为HTML片段，删除未知/不安全的元素和属性。
          * `expected_update_period_in_days` - 您希望此RSS源更改的频率。 如果超过此时间量而没有更新，代理将标记为无法正常工作。
          * `headers` - 如果存在，它应该是与请求一起发送的标头的散列。
          * `basic_auth` - 指定HTTP基本身份验证参数：“username：password”或[“username”，“password”]。
          * `disable_ssl_verification` - 设置为true以禁用ssl验证。
          * `disable_url_encoding` - 设置为true以禁用URL编码。
          * `force_encoding` - 如果已知网站在Content-Type标头中响应丢失，无效或错误的字符集，请将force_encoding设置为编码名称。 请注意，没有字符集的文本内容采用UTF-8（非ISO-8859-1）编码。
          * `user_agent` - 自定义User-Agent名称（默认值：“Faraday v#{Faraday::VERSION}”)
          * `max_events_per_run` - 限制每次运行创建的事件数（解析的项目）。
          * `remembered_id_count` - 要跟踪并避免重新发光的ID数量（默认值：500）。

        # 事件排序

        #{description_events_order}

        在此代理中，事件顺序的默认值为`#{DEFAULT_EVENTS_ORDER.to_json}`
      MD
    end

    def default_options
      {
        'expected_update_period_in_days' => "5",
        'clean' => 'false',
        'url' => "https://github.com/huginn/huginn/commits/master.atom"
      }
    end

    event_description <<-MD
      Events look like:

          {
            "feed": {
              "id": "...",
              "type": "atom",
              "generator": "...",
              "url": "http://example.com/",
              "links": [
                { "href": "http://example.com/", "rel": "alternate", "type": "text/html" },
                { "href": "http://example.com/index.atom", "rel": "self", "type": "application/atom+xml" }
              ],
              "title": "Some site title",
              "description": "Some site description",
              "copyright": "...",
              "icon": "http://example.com/icon.png",
              "authors": [ "..." ],

              "itunes_block": "no",
              "itunes_categories": [
                "Technology", "Gadgets",
                "TV & Film",
                "Arts", "Food"
              ],
              "itunes_complete": "yes",
              "itunes_explicit": "yes",
              "itunes_image": "http://...",
              "itunes_new_feed_url": "http://...",
              "itunes_owners": [ "John Doe <john.doe@example.com>" ],
              "itunes_subtitle": "...",
              "itunes_summary": "...",
              "language": "en-US",

              "date_published": "2014-09-11T01:30:00-07:00",
              "last_updated": "2014-09-11T01:30:00-07:00"
            },
            "id": "829f845279611d7925146725317b868d",
            "url": "http://example.com/...",
            "urls": [ "http://example.com/..." ],
            "links": [
              { "href": "http://example.com/...", "rel": "alternate" },
            ],
            "title": "Some title",
            "description": "Some description",
            "content": "Some content",
            "authors": [ "Some Author <email@address>" ],
            "categories": [ "..." ],
            "image": "http://example.com/...",
            "enclosure": {
              "url" => "http://example.com/file.mp3", "type" => "audio/mpeg", "length" => "123456789"
            },

            "itunes_block": "no",
            "itunes_closed_captioned": "yes",
            "itunes_duration": "04:34",
            "itunes_explicit": "yes",
            "itunes_image": "http://...",
            "itunes_order": "1",
            "itunes_subtitle": "...",
            "itunes_summary": "...",

            "date_published": "2014-09-11T01:30:00-0700",
            "last_updated": "2014-09-11T01:30:00-0700"
          }

      Some notes:

      - The `feed` key is present only if `include_feed_info` is set to true.
      - The keys starting with `itunes_`, and `language` are only present when the feed is a podcast.  See [Podcasts Connect Help](https://help.apple.com/itc/podcasts_connect/#/itcb54353390) for details.
      - Each element in `authors` and `itunes_owners` is a string normalized in the format "*name* <*email*> (*url*)", where each space-separated part is optional.
      - Timestamps are converted to the ISO 8601 format.
    MD

    def working?
      event_created_within?((interpolated['expected_update_period_in_days'].presence || 10).to_i) && !recent_error_logs?
    end

    def validate_options
      errors.add(:base, "url is required") unless options['url'].present?

      unless options['expected_update_period_in_days'].present? && options['expected_update_period_in_days'].to_i > 0
        errors.add(:base, "Please provide 'expected_update_period_in_days' to indicate how many days can pass without an update before this Agent is considered to not be working")
      end

      if options['remembered_id_count'].present? && options['remembered_id_count'].to_i < 1
        errors.add(:base, "Please provide 'remembered_id_count' as a number bigger than 0 indicating how many IDs should be saved to distinguish between new and old IDs in RSS feeds. Delete option to use default (500).")
      end

      validate_web_request_options!
      validate_events_order
    end

    def events_order(key = SortableEvents::EVENTS_ORDER_KEY)
      if key == SortableEvents::EVENTS_ORDER_KEY
        super.presence || DEFAULT_EVENTS_ORDER
      else
        raise ArgumentError, "unsupported key: #{key}"
      end
    end

    def check
      check_urls(Array(interpolated['url']))
    end

    protected

    def check_urls(urls)
      new_events = []
      max_events = (interpolated['max_events_per_run'].presence || 0).to_i

      urls.each do |url|
        begin
          response = faraday.get(url)
          if response.success?
            feed = Feedjira::Feed.parse(preprocessed_body(response))
            new_events.concat feed_to_events(feed)
          else
            error "Failed to fetch #{url}: #{response.inspect}"
          end
        rescue => e
          error "Failed to fetch #{url} with message '#{e.message}': #{e.backtrace}"
        end
      end

      events = sort_events(new_events).select.with_index { |event, index|
        check_and_track(event.payload[:id]) &&
          !(max_events && max_events > 0 && index >= max_events)
      }
      create_events(events)
      log "Fetched #{urls.to_sentence} and created #{events.size} event(s)."
    end

    def remembered_id_count
      (options['remembered_id_count'].presence || 500).to_i
    end

    def check_and_track(entry_id)
      memory['seen_ids'] ||= []
      if memory['seen_ids'].include?(entry_id)
        false
      else
        memory['seen_ids'].unshift entry_id
        memory['seen_ids'].pop(memory['seen_ids'].length - remembered_id_count) if memory['seen_ids'].length > remembered_id_count
        true
      end
    end

    unless dependencies_missing?
      require 'feedjira_extension'
    end

    def preprocessed_body(response)
      body = response.body
      case body.encoding
      when Encoding::ASCII_8BIT
        # Encoding is unknown from the Content-Type, so let the SAX
        # parser detect it from the content.
      else
        # Encoding is already known, so do not let the parser detect
        # it from the XML declaration in the content.
        body.sub!(/(?<noenc>\A\u{FEFF}?\s*<\?xml(?:\s+\w+(?<av>\s*=\s*(?:'[^']*'|"[^"]*")))*?)\s+encoding\g<av>/, '\\k<noenc>')
      end
      body
    end

    def feed_data(feed)
      type =
        case feed.class.name
        when /Atom/
          'atom'
        else
          'rss'
        end

      {
        id: feed.feed_id,
        type: type,
        url: feed.url,
        links: feed.links,
        title: feed.title,
        description: feed.description,
        copyright: feed.copyright,
        generator: feed.generator,
        icon: feed.icon,
        authors: feed.authors,
        date_published: feed.date_published,
        last_updated: feed.last_updated,
        **itunes_feed_data(feed)
      }
    end

    def itunes_feed_data(feed)
      data = {}
      case feed
      when Feedjira::Parser::ITunesRSS
        %i[
          itunes_block
          itunes_categories
          itunes_complete
          itunes_explicit
          itunes_image
          itunes_new_feed_url
          itunes_owners
          itunes_subtitle
          itunes_summary
          language
        ].each { |attr|
          if value = feed.try(attr).presence
            data[attr] =
              case attr
              when :itunes_summary
                clean_fragment(value)
              else
                value
              end
          end
        }
      end
      data
    end

    def entry_data(entry)
      {
        id: entry.id,
        url: entry.url,
        urls: entry.links.map(&:href),
        links: entry.links,
        title: entry.title,
        description: clean_fragment(entry.summary),
        content: clean_fragment(entry.content || entry.summary),
        image: entry.try(:image),
        enclosure: entry.enclosure,
        authors: entry.authors,
        categories: Array(entry.try(:categories)),
        date_published: entry.date_published,
        last_updated: entry.last_updated,
        **itunes_entry_data(entry)
      }
    end

    def itunes_entry_data(entry)
      data = {}
      case entry
      when Feedjira::Parser::ITunesRSSItem
        %i[
          itunes_block
          itunes_closed_captioned
          itunes_duration
          itunes_explicit
          itunes_image
          itunes_order
          itunes_subtitle
          itunes_summary
        ].each { |attr|
          if value = entry.try(attr).presence
            data[attr] = value
          end
        }
      end
      data
    end

    def feed_to_events(feed)
      payload_base = {}

      if boolify(interpolated['include_feed_info'])
        payload_base[:feed] = feed_data(feed)
      end

      feed.entries.map { |entry|
        Event.new(payload: payload_base.merge(entry_data(entry)))
      }
    end

    def clean_fragment(fragment)
      if boolify(interpolated['clean']) && fragment.present?
        Loofah.scrub_fragment(fragment, :prune).to_s
      else
        fragment
      end
    end
  end
end
