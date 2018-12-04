require 'nokogiri'
require 'date'

module Agents
  class WebsiteAgent < Agent
    include WebRequestConcern

    can_dry_run!
    can_order_created_events!
    no_bulk_receive!

    default_schedule "every_12h"

    UNIQUENESS_LOOK_BACK = 200
    UNIQUENESS_FACTOR = 3

    description <<-MD

      网站代理会抓取网站，XML文档或JSON Feed，并根据结果创建事件

      指定一个url并根据已删除的数据（all，on_change或merge）选择何时创建事件的模式（如果基于事件获取，请参见下文）。

      url选项可以是单个url，也可以是url数组（例如，对于具有完全相同结构但不同内容要刮的多个页面）。

      WebsiteAgent还可以根据传入的事件进行搜索。

      * 将url_from_event选项设置为Liquid模板，以根据Event生成要访问的URL。 （例如，要获取Event的url键中的url，请将url_from_event设置为{{url}}。）
      * 或者，将data_from_event设置为Liquid模板以直接使用数据而不提取任何URL。 （例如，将其设置为{{html}}以使用包含在传入事件的html键中的HTML。）
      * 如果为mode选项指定merge，Huginn将保留旧有效负载并使用新值更新它。

      # 支持的文档类型

      类型值可以是xml，html，json或text

      要告诉代理如何解析内容，请将extract指定为哈希，并使用键命名哈希的提取和值。

      请注意，对于所有格式，无论您提取什么，每个提取器都必须具有相同数量的匹配，除非它重复设置为true。 例如，如果要提取行，则所有提取器必须匹配所有行。 为了生成CSS选择器，像SelectorGadget这样的东西可能会有所帮助。

      对于隐藏设置为true的提取器，它们将从代理创建的事件的有效负载中排除，但可以在下面解释的模板选项中使用和插值。

      对于重复设置为true的提取器，它们的第一个匹配将包含在所有提取中。 这非常有用，例如当您想要在页面创建的所有事件中包含页面标题时。

      # 解析 HTML 和 XML

      解析HTML或XML时，这些子哈希指定了每次提取的完成方式。 代理首先通过评估css中的CSS选择器或xpath中的XPath表达式，为每个提取键从文档中选择一个节点集。 然后，它在节点集中的每个节点上以值（默认值：。）计算XPath表达式，并将结果转换为字符串。 这是一个例子：

          "extract": {
            "url": { "css": "#comic img", "value": "@src" },
            "title": { "css": "#comic img", "value": "@title" },
            "body_text": { "css": "div.main", "value": "string(.)" },
            "page_title": { "css": "title", "value": "string(.)", "repeat": true }
          }
      or
          "extract": {
            "url": { "xpath": "//*[@class="blog-item"]/a/@href", "value": "."
            "title": { "xpath": "//*[@class="blog-item"]/a", "value": "normalize-space(.)" },
            "description": { "xpath": "//*[@class="blog-item"]/div[0]", "value": "string(.)" }
          }

      “@attr”是用于从节点中提取名为attr的属性的值的XPath表达式（例如来自超链接的“@href”），而string（。）给出一个字符串，其中所有包含的文本节点在没有实体转义的情况下连接在一起 （例如＆amp;）。 要提取innerHTML，请使用./node（）; 并提取外部HTML，使用..

      您还可以使用像规范化空格这样的XPath函数来剥离和压缩空格，使用substring-after提取文本的一部分，然后翻译以从格式化的数字中删除逗号等。而不是将字符串（。）传递给这些函数，您可以 刚过去 像normalize-space（。）和translate（。，'，'，''）。

      请注意，在使用xpath表达式解析XML文档（即type为xml）时，除非将顶级选项use_namespaces设置为true，否则将从文档中删除所有名称空间。

      对于数组设置为true的提取，所有匹配都将提取到数组中。 这在提取只能与同一选择器匹配的列表元素或网站的多个部分时非常有用。

      # 解析 JSON

      解析JSON时，这些子哈希将JSONPath指定为您关心的值。

      传入事件示例：

          { "results": {
              "data": [
                {
                  "title": "Lorem ipsum 1",
                  "description": "Aliquam pharetra leo ipsum."
                  "price": 8.95
                },
                {
                  "title": "Lorem ipsum 2",
                  "description": "Suspendisse a pulvinar lacus."
                  "price": 12.99
                },
                {
                  "title": "Lorem ipsum 3",
                  "description": "Praesent ac arcu tellus."
                  "price": 8.99
                }
              ]
            }
          }

        示例规则：

          "extract": {
            "title": { "path": "results.data[*].title" },
            "description": { "path": "results.data[*].description" }
          }

        在此示例中，*通配符使解析器迭代数据数组的所有项。 结果将创建三个事件。

      示例传出事件：

          [
            {
              "title": "Lorem ipsum 1",
              "description": "Aliquam pharetra leo ipsum."
            },
            {
              "title": "Lorem ipsum 2",
              "description": "Suspendisse a pulvinar lacus."
            },
            {
              "title": "Lorem ipsum 3",
              "description": "Praesent ac arcu tellus."
            }
          ]


      可以跳过JSON类型的extract选项，从而返回完整的JSON响应。

      # 解析文本

      解析文本时，每个子哈希应包含正则表达式和索引。 输出文本从开头到结尾重复匹配正则表达式，收集每个匹配中由index指定的捕获组。 每个索引应该是整数或字符串名称，对应于（？<name> ...）。 例如，要解析word：definition的行，以下内容应该有效：

          "extract": {
            "word": { "regexp": "^(.+?): (.+)$", "index": 1 },
            "definition": { "regexp": "^(.+?): (.+)$", "index": 2 }
          }

      或者，如果您更喜欢名称与索引的数字：

          "extract": {
            "word": { "regexp": "^(?<word>.+?): (?<definition>.+)$", "index": "word" },
            "definition": { "regexp": "^(?<word>.+?): (?<definition>.+)$", "index": "definition" }
          }

      要将整个内容提取为一个事件：

          "extract": {
            "content": { "regexp": "\\A(?m:.)*\\z", "index": 0 }
          }

      要小心。 除非m标志生效，否则与换行符（LF）不匹配，并且^ / $基本匹配每行开头/结尾。 请参阅此文档以了解此服务中使用的正则表达式变体。

      # 常规选项

      可以通过将basic_auth参数包含在“username：password”或[“username”，“password”]中来配置为使用HTTP basic auth。

      将expected_update_period_in_days设置为您希望在此代理创建的事件之间传递的最长时间。 这仅用于设置“工作”状态。

      设置uniqueness_look_back以限制为唯一性检查的事件数（通常用于性能）。 默认值为检测到的接收结果数量的200或3倍。

      如果已知网站在Content-Type标头中响应丢失，无效或错误的字符集，则将force_encoding设置为编码名称（例如UTF-8和ISO-8859-1）。 以下是Huginn用于检测已获取内容的编码的步骤：

      1. 如果给出force_encoding，则使用该值
      2. 如果Content-Type标头包含charset参数，则使用该值。
      3. 当type为html或xml时，Huginn会检查是否存在BOM，带有属性“encoding”的XML声明，或带有charset信息的HTML元标记，如果找到则使用它。
      4. Huginn回归到UTF-8（不是ISO-8859-1）。

      如果网站不喜欢默认值（Huginn - https://github.com/huginn/huginn），请将user_agent设置为自定义User-Agent名称。

      标题字段是可选的。 如果存在，它应该是与请求一起发送的标头的散列。

      将disable_ssl_verification设置为true以禁用ssl验证。

      设置解压缩到gzip以使用gzip来扩充资源。

      将http_success_codes设置为状态代码数组（例如，[404,422]）以将超过200的HTTP响应代码视为成功。

      如果给出了模板选项，则其值必须是散列，其键值对在每次迭代的提取后进行插值并与有效负载合并。 在模板中，可以插入提取数据的键，并且还可以使用一些其他变量，如下一节中所述。 例如：

          "template": {
            "url": "{{ url | to_uri: _response_.url }}",
            "description": "{{ body_text }}",
            "last_modified": "{{ _response_.headers.Last-Modified | date: '%FT%T' }}"
          }

      在on_change模式下，应用此选项后，将根据生成的事件有效内容检测更改。 如果要为每个事件添加一些键但忽略其中的任何更改，请将mode设置为all并将DeDuplicationAgent置于下游。

      # Liquid 模板

      在Liquid模板中，可以使用以下变量：

      * `_url_`: 指定用于从中获取内容的URL。 解析data_from_event时，未设置此值。

      * `_response_`: 具有以下键的响应对象：

          * `status`: HTTP状态为整数。 （几乎总是200）在解析data_from_event时，如果它是一个数字或可转换为整数的字符串，则将其设置为传入事件中状态键的值。

          * `headers`: 响应标头; 例如，{{_ response_.headers.Content-Type}}扩展为Content-Type标头的值。 键对案例不敏感，而且 - / _。 解析data_from_event时，如果它是一个哈希，则由传入事件中的头键值构成。

          * `url`: 重定向后，获取页面的最终URL。 解析data_from_event时，将其设置为传入事件中url键的值。 在模板选项中使用此选项，您可以解析从{{link | to_uri：_response_.url}}和{{content | rebase_hrefs：_response_.url}}。

      # 事件排序

      #{description_events_order}
    MD

    event_description do
      if keys = event_keys
        "Events will have the following fields:\n\n    %s" % [
          Utils.pretty_print(Hash[event_keys.map { |key|
                                    [key, "..."]
                                  }])
        ]
      else
        "Events will be the raw JSON returned by the URL."
      end
    end

    def event_keys
      extract = options['extract'] or return nil

      extract.each_with_object([]) { |(key, value), keys|
        keys << key unless boolify(value['hidden'])
      } | (options['template'].presence.try!(:keys) || [])
    end

    def working?
      event_created_within?(options['expected_update_period_in_days']) && !recent_error_logs?
    end

    def default_options
      {
          'expected_update_period_in_days' => "2",
          'url' => "https://xkcd.com",
          'type' => "html",
          'mode' => "on_change",
          'extract' => {
            'url' => { 'css' => "#comic img", 'value' => "@src" },
            'title' => { 'css' => "#comic img", 'value' => "@alt" },
            'hovertext' => { 'css' => "#comic img", 'value' => "@title" }
          }
      }
    end

    def validate_options
      # Check for required fields
      errors.add(:base, "either url, url_from_event, or data_from_event are required") unless options['url'].present? || options['url_from_event'].present? || options['data_from_event'].present?
      errors.add(:base, "expected_update_period_in_days is required") unless options['expected_update_period_in_days'].present?
      validate_extract_options!
      validate_template_options!
      validate_http_success_codes!

      # Check for optional fields
      if options['mode'].present?
        errors.add(:base, "mode must be set to on_change, all or merge") unless %w[on_change all merge].include?(options['mode'])
      end

      if options['expected_update_period_in_days'].present?
        errors.add(:base, "Invalid expected_update_period_in_days format") unless is_positive_integer?(options['expected_update_period_in_days'])
      end

      if options['uniqueness_look_back'].present?
        errors.add(:base, "Invalid uniqueness_look_back format") unless is_positive_integer?(options['uniqueness_look_back'])
      end

      validate_web_request_options!
    end

    def validate_http_success_codes!
      consider_success = options["http_success_codes"]
      if consider_success.present?

        if (consider_success.class != Array)
          errors.add(:http_success_codes, "must be an array and specify at least one status code")
        else
          if consider_success.uniq.count != consider_success.count
            errors.add(:http_success_codes, "duplicate http code found")
          else
            if consider_success.any?{|e| e.to_s !~ /^\d+$/ }
              errors.add(:http_success_codes, "please make sure to use only numeric values for code, ex 404, or \"404\"")
            end
          end
        end

      end
    end

    def validate_extract_options!
      extraction_type = (extraction_type() rescue extraction_type(options))
      case extract = options['extract']
      when Hash
        if extract.each_value.any? { |value| !value.is_a?(Hash) }
          errors.add(:base, 'extract must be a hash of hashes.')
        else
          case extraction_type
          when 'html', 'xml'
            extract.each do |name, details|
              case details['css']
              when String
                # ok
              when nil
                case details['xpath']
                when String
                  # ok
                when nil
                  errors.add(:base, "When type is html or xml, all extractions must have a css or xpath attribute (bad extraction details for #{name.inspect})")
                else
                  errors.add(:base, "Wrong type of \"xpath\" value in extraction details for #{name.inspect}")
                end
              else
                errors.add(:base, "Wrong type of \"css\" value in extraction details for #{name.inspect}")
              end

              case details['value']
              when String, nil
                # ok
              else
                errors.add(:base, "Wrong type of \"value\" value in extraction details for #{name.inspect}")
              end
            end
          when 'json'
            extract.each do |name, details|
              case details['path']
              when String
                # ok
              when nil
                errors.add(:base, "When type is json, all extractions must have a path attribute (bad extraction details for #{name.inspect})")
              else
                errors.add(:base, "Wrong type of \"path\" value in extraction details for #{name.inspect}")
              end
            end
          when 'text'
            extract.each do |name, details|
              case regexp = details['regexp']
              when String
                begin
                  re = Regexp.new(regexp)
                rescue => e
                  errors.add(:base, "invalid regexp for #{name.inspect}: #{e.message}")
                end
              when nil
                errors.add(:base, "When type is text, all extractions must have a regexp attribute (bad extraction details for #{name.inspect})")
              else
                errors.add(:base, "Wrong type of \"regexp\" value in extraction details for #{name.inspect}")
              end

              case index = details['index']
              when Integer, /\A\d+\z/
                # ok
              when String
                if re && !re.names.include?(index)
                  errors.add(:base, "no named capture #{index.inspect} found in regexp for #{name.inspect})")
                end
              when nil
                errors.add(:base, "When type is text, all extractions must have an index attribute (bad extraction details for #{name.inspect})")
              else
                errors.add(:base, "Wrong type of \"index\" value in extraction details for #{name.inspect}")
              end
            end
          when /\{/
            # Liquid templating
          else
            errors.add(:base, "Unknown extraction type #{extraction_type.inspect}")
          end
        end
      when nil
        unless extraction_type == 'json'
          errors.add(:base, 'extract is required for all types except json')
        end
      else
        errors.add(:base, 'extract must be a hash')
      end
    end

    def validate_template_options!
      template = options['template'].presence or return

      unless Hash === template &&
             template.each_pair.all? { |key, value| String === value }
        errors.add(:base, 'template must be a hash of strings.')
      end
    end

    def check
      check_urls(interpolated['url'])
    end

    def check_urls(in_url, existing_payload = {})
      return unless in_url.present?

      Array(in_url).each do |url|
        check_url(url, existing_payload)
      end
    end

    def check_url(url, existing_payload = {})
      unless /\Ahttps?:\/\//i === url
        error "Ignoring a non-HTTP url: #{url.inspect}"
        return
      end
      uri = Utils.normalize_uri(url)
      log "Fetching #{uri}"
      response = faraday.get(uri)

      raise "Failed: #{response.inspect}" unless consider_response_successful?(response)

      interpolation_context.stack {
        interpolation_context['_url_'] = uri.to_s
        interpolation_context['_response_'] = ResponseDrop.new(response)
        handle_data(response.body, response.env[:url], existing_payload)
      }
    rescue => e
      error "Error when fetching url: #{e.message}\n#{e.backtrace.join("\n")}"
    end

    def default_encoding
      case extraction_type
      when 'html', 'xml'
        # Let Nokogiri detect the encoding
        nil
      else
        super
      end
    end

    def handle_data(body, url, existing_payload)
      # Beware, url may be a URI object, string or nil

      doc = parse(body)

      if extract_full_json?
        if store_payload!(previous_payloads(1), doc)
          log "Storing new result for '#{name}': #{doc.inspect}"
          create_event payload: existing_payload.merge(doc)
        end
        return
      end

      output =
        case extraction_type
          when 'json'
            extract_json(doc)
          when 'text'
            extract_text(doc)
          else
            extract_xml(doc)
        end

      num_tuples = output.size or
        raise "At least one non-repeat key is required"

      old_events = previous_payloads num_tuples

      template = options['template'].presence

      output.each do |extracted|
        result = extracted.except(*output.hidden_keys)

        if template
          result.update(interpolate_options(template, extracted))
        end

        if store_payload!(old_events, result)
          log "Storing new parsed result for '#{name}': #{result.inspect}"
          create_event payload: existing_payload.merge(result)
        end
      end
    end

    def receive(incoming_events)
      incoming_events.each do |event|
        interpolate_with(event) do
          existing_payload = interpolated['mode'].to_s == "merge" ? event.payload : {}

          if data_from_event = options['data_from_event'].presence
            data = interpolate_options(data_from_event)
            if data.present?
              handle_event_data(data, event, existing_payload)
            else
              error "No data was found in the Event payload using the template #{data_from_event}", inbound_event: event
            end
          else
            url_to_scrape =
              if url_template = options['url_from_event'].presence
                interpolate_options(url_template)
              else
                interpolated['url']
              end
            check_urls(url_to_scrape, existing_payload)
          end
        end
      end
    end

    private
    def consider_response_successful?(response)
      response.success? || begin
        consider_success = options["http_success_codes"]
        consider_success.present? && (consider_success.include?(response.status.to_s) || consider_success.include?(response.status))
      end
    end

    def handle_event_data(data, event, existing_payload)
      interpolation_context.stack {
        interpolation_context['_response_'] = ResponseFromEventDrop.new(event)
        handle_data(data, event.payload['url'].presence, existing_payload)
      }
    rescue => e
      error "Error when handling event data: #{e.message}\n#{e.backtrace.join("\n")}", inbound_event: event
    end

    # This method returns true if the result should be stored as a new event.
    # If mode is set to 'on_change', this method may return false and update an existing
    # event to expire further in the future.
    def store_payload!(old_events, result)
      case interpolated['mode'].presence
      when 'on_change'
        result_json = result.to_json
        if found = old_events.find { |event| event.payload.to_json == result_json }
          found.update!(expires_at: new_event_expiration_date)
          false
        else
          true
        end
      when 'all', 'merge', ''
        true
      else
        raise "Illegal options[mode]: #{interpolated['mode']}"
      end
    end

    def previous_payloads(num_events)
      if interpolated['uniqueness_look_back'].present?
        look_back = interpolated['uniqueness_look_back'].to_i
      else
        # Larger of UNIQUENESS_FACTOR * num_events and UNIQUENESS_LOOK_BACK
        look_back = UNIQUENESS_FACTOR * num_events
        if look_back < UNIQUENESS_LOOK_BACK
          look_back = UNIQUENESS_LOOK_BACK
        end
      end
      events.order("id desc").limit(look_back) if interpolated['mode'] == "on_change"
    end

    def extract_full_json?
      !interpolated['extract'].present? && extraction_type == "json"
    end

    def extraction_type(interpolated = interpolated())
      (interpolated['type'] || begin
        case interpolated['url']
        when /\.(rss|xml)$/i
          "xml"
        when /\.json$/i
          "json"
        when /\.(txt|text)$/i
          "text"
        else
          "html"
        end
      end).to_s
    end

    def use_namespaces?
      if interpolated.key?('use_namespaces')
        boolify(interpolated['use_namespaces'])
      else
        interpolated['extract'].none? { |name, extraction_details|
          extraction_details.key?('xpath')
        }
      end
    end

    def extract_each(&block)
      interpolated['extract'].each_with_object(Output.new) { |(name, extraction_details), output|
        if boolify(extraction_details['repeat'])
          values = Repeater.new { |repeater|
            block.call(extraction_details, repeater)
          }
        else
          values = []
          block.call(extraction_details, values)
        end
        log "Values extracted: #{values}"
        begin
          output[name] = values
        rescue UnevenSizeError
          raise "Got an uneven number of matches for #{interpolated['name']}: #{interpolated['extract'].inspect}"
        else
          output.hidden_keys << name if boolify(extraction_details['hidden'])
        end
      }
    end

    def extract_json(doc)
      extract_each { |extraction_details, values|
        log "Extracting #{extraction_type} at #{extraction_details['path']}"
        Utils.values_at(doc, extraction_details['path']).each { |value|
          values << value
        }
      }
    end

    def extract_text(doc)
      extract_each { |extraction_details, values|
        regexp = Regexp.new(extraction_details['regexp'])
        log "Extracting #{extraction_type} with #{regexp}"
        case index = extraction_details['index']
        when /\A\d+\z/
          index = index.to_i
        end
        doc.scan(regexp) {
          values << Regexp.last_match[index]
        }
      }
    end

    def extract_xml(doc)
      extract_each { |extraction_details, values|
        case
        when css = extraction_details['css']
          nodes = doc.css(css)
        when xpath = extraction_details['xpath']
          nodes = doc.xpath(xpath)
        else
          raise '"css" or "xpath" is required for HTML or XML extraction'
        end
        log "Extracting #{extraction_type} at #{xpath || css}"
        case nodes
        when Nokogiri::XML::NodeSet
          stringified_nodes  = nodes.map do |node|
            case value = node.xpath(extraction_details['value'] || '.')
            when Float
              # Node#xpath() returns any numeric value as float;
              # convert it to integer as appropriate.
              value = value.to_i if value.to_i == value
            end
            value.to_s
          end
          if boolify(extraction_details['array'])
            values << stringified_nodes
          else
            stringified_nodes.each { |n| values << n }
          end
        else
          raise "The result of HTML/XML extraction was not a NodeSet"
        end
      }
    end

    def parse(data)
      case type = extraction_type
      when "xml"
        doc = Nokogiri::XML(data)
        # ignore xmlns, useful when parsing atom feeds
        doc.remove_namespaces! unless use_namespaces?
        doc
      when "json"
        JSON.parse(data)
      when "html"
        Nokogiri::HTML(data)
      when "text"
        data
      else
        raise "Unknown extraction type: #{type}"
      end
    end

    class UnevenSizeError < ArgumentError
    end

    class Output
      def initialize
        @hash = {}
        @size = nil
        @hidden_keys = []
      end

      attr_reader :size
      attr_reader :hidden_keys

      def []=(key, value)
        case size = value.size
        when Integer
          if @size && @size != size
            raise UnevenSizeError, 'got an uneven size'
          end
          @size = size
        end

        @hash[key] = value
      end

      def each
        @size.times.zip(*@hash.values) do |index, *values|
          yield @hash.each_key.lazy.zip(values).to_h
        end
      end
    end

    class Repeater < Enumerator
      # Repeater.new { |y|
      #   # ...
      #   y << value
      # } #=> [value, ...]
      def initialize(&block)
        @value = nil
        super(Float::INFINITY) { |y|
          loop { y << @value }
        }
        catch(@done = Object.new) {
          block.call(self)
        }
      end

      def <<(value)
        @value = value
        throw @done
      end

      def to_s
        "[#{@value.inspect}, ...]"
      end
    end

    # Wraps Faraday::Response
    class ResponseDrop < LiquidDroppable::Drop
      def headers
        HeaderDrop.new(@object.headers)
      end

      # Integer value of HTTP status
      def status
        @object.status
      end

      # The URL
      def url
        @object.env.url.to_s
      end
    end

    class ResponseFromEventDrop < LiquidDroppable::Drop
      def headers
        headers = Faraday::Utils::Headers.from(@object.payload[:headers]) rescue {}

        HeaderDrop.new(headers)
      end

      # Integer value of HTTP status
      def status
        Integer(@object.payload[:status]) rescue nil
      end

      # The URL
      def url
        @object.payload[:url]
      end
    end

    # Wraps Faraday::Utils::Headers
    class HeaderDrop < LiquidDroppable::Drop
      def liquid_method_missing(name)
        @object[name.tr('_', '-')]
      end
    end
  end
end
