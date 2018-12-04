module Agents
  class PostAgent < Agent
    include WebRequestConcern
    include FileHandling

    consumes_file_pointer!

    MIME_RE = /\A\w+\/.+\z/

    can_dry_run!
    no_bulk_receive!
    default_schedule "never"

    description do
      <<-MD
        Post Agent从其他代理接收事件（或定期运行），将这些事件与Liquid内插的有效负载内容合并，并将结果作为POST（或GET）请求发送到指定的url。 要跳过合并传入事件，但仍发送插值有效负载，请将no_merge设置为true。

        post_url字段必须指定您要发送请求的位置。 请包含URI方案（http或https）。

        使用的方法可以是get，post，put，patch和delete中的任何一个

        默认情况下，非GET将使用表单编码（application / x-www-form-urlencoded）发送。

        将content_type更改为json以改为发送JSON

        将content_type更改为xml以发送XML，其中可以使用xml_root指定根元素的名称，默认为post。

        当content_type包含MIME类型，并且payload是一个字符串时，其插值将作为HTTP请求主体中的字符串发送，并且请求的Content-Type HTTP标头将设置为content_type。 当payload是一个字符串时，no_merge必须设置为true

        如果emit_events设置为true，则服务器响应将作为Event发出，并可以提供给WebsiteAgent进行解析（使用其data_from_event和type选项）。 此代理不会尝试任何数据处理，因此Event的“body”值将始终为原始文本。 事件还将具有“标题”哈希值和“状态”整数值。

        如果output_mode设置为merge，则发出的Event将合并到接收到的Event的原始内容中。

        将event_headers_style设置为以下值之一，以规范化“标题”的键，以便下游代理方便：

          * `capitalized` （默认） - 标题名称大写; 例如 “内容类型”
          * `downcased` - 标题名称是低级的; 例如 “内容类型”
          * `snakecased` - 标题名称是蛇形的; 例如 “内容类型”
          * `raw` - 向后兼容性选项，使其不受基础HTTP库返回的修改。

        其他选择：

          * `headers` - 如果存在，它应该是与请求一起发送的标头的散列。
          * `basic_auth` -  指定HTTP基本身份验证参数：“username：password”或[“username”，“password”]。
          * `disable_ssl_verification` - 设置为true以禁用ssl验证。
          * `user_agent` -自定义User-Agent名称（默认值：“Faraday v0.12.1”）

        #{receiving_file_handling_agent_description}

        当接收到file_pointer时，将使用多部分编码（multipart / form-data）发送请求，并忽略content_type。 upload_key可用于指定文件将在其中发送的参数，默认为file
      MD
    end

    event_description <<-MD
      Events look like this:
        {
          "status": 200,
          "headers": {
            "Content-Type": "text/html",
            ...
          },
          "body": "<html>Some data...</html>"
        }

      Original event contents will be merged when `output_mode` is set to `merge`.
    MD

    def default_options
      {
        'post_url' => "http://www.example.com",
        'expected_receive_period_in_days' => '1',
        'content_type' => 'form',
        'method' => 'post',
        'payload' => {
          'key' => 'value',
          'something' => 'the event contained {{ somekey }}'
        },
        'headers' => {},
        'emit_events' => 'false',
        'no_merge' => 'false',
        'output_mode' => 'clean'
      }
    end

    def working?
      return false if recent_error_logs?
      
      if interpolated['expected_receive_period_in_days'].present?
        return false unless last_receive_at && last_receive_at > interpolated['expected_receive_period_in_days'].to_i.days.ago
      end

      true
    end

    def method
      (interpolated['method'].presence || 'post').to_s.downcase
    end

    def validate_options
      unless options['post_url'].present?
        errors.add(:base, "post_url is a required field")
      end

      if options['payload'].present? && %w[get delete].include?(method) && !(options['payload'].is_a?(Hash) || options['payload'].is_a?(Array))
        errors.add(:base, "if provided, payload must be a hash or an array")
      end

      if options['payload'].present? && %w[post put patch].include?(method)
        if !(options['payload'].is_a?(Hash) || options['payload'].is_a?(Array)) && options['content_type'] !~ MIME_RE
          errors.add(:base, "if provided, payload must be a hash or an array")
        end
      end

      if options['content_type'] =~ MIME_RE && options['payload'].is_a?(String) && boolify(options['no_merge']) != true
        errors.add(:base, "when the payload is a string, `no_merge` has to be set to `true`")
      end

      if options['content_type'] == 'form' && options['payload'].present? && options['payload'].is_a?(Array)
        errors.add(:base, "when content_type is a form, if provided, payload must be a hash")
      end

      if options.has_key?('emit_events') && boolify(options['emit_events']).nil?
        errors.add(:base, "if provided, emit_events must be true or false")
      end

      begin
        normalize_response_headers({})
      rescue ArgumentError => e
        errors.add(:base, e.message)
      end

      unless %w[post get put delete patch].include?(method)
        errors.add(:base, "method must be 'post', 'get', 'put', 'delete', or 'patch'")
      end

      if options['no_merge'].present? && !%[true false].include?(options['no_merge'].to_s)
        errors.add(:base, "if provided, no_merge must be 'true' or 'false'")
      end

      if options['output_mode'].present? && !options['output_mode'].to_s.include?('{') && !%[clean merge].include?(options['output_mode'].to_s)
        errors.add(:base, "if provided, output_mode must be 'clean' or 'merge'")
      end

      unless headers.is_a?(Hash)
        errors.add(:base, "if provided, headers must be a hash")
      end

      validate_web_request_options!
    end

    def receive(incoming_events)
      incoming_events.each do |event|
        interpolate_with(event) do
          outgoing = interpolated['payload'].presence || {}
          if boolify(interpolated['no_merge'])
            handle outgoing, event, headers(interpolated[:headers])
          else
            handle outgoing.merge(event.payload), event, headers(interpolated[:headers])
          end
        end
      end
    end

    def check
      handle interpolated['payload'].presence || {}, headers
    end

    private

    def normalize_response_headers(headers)
      case interpolated['event_headers_style']
      when nil, '', 'capitalized'
        normalize = ->name {
          name.gsub(/(?:\A|(?<=-))([[:alpha:]])|([[:alpha:]]+)/) {
            $1 ? $1.upcase : $2.downcase
          }
        }
      when 'downcased'
        normalize = :downcase.to_proc
      when 'snakecased', nil
        normalize = ->name { name.tr('A-Z-', 'a-z_') }
      when 'raw'
        normalize = ->name { name }  # :itself.to_proc in Ruby >= 2.2
      else
        raise ArgumentError, "if provided, event_headers_style must be 'capitalized', 'downcased', 'snakecased' or 'raw'"
      end

      headers.each_with_object({}) { |(key, value), hash|
        hash[normalize[key]] = value
      }
    end

    def handle(data, event = Event.new, headers)
      url = interpolated(event.payload)[:post_url]

      case method
      when 'get', 'delete'
        params, body = data, nil
      when 'post', 'put', 'patch'
        params = nil

        content_type =
          if has_file_pointer?(event)
            data[interpolated(event.payload)['upload_key'].presence || 'file'] = get_upload_io(event)
            nil
          else
            interpolated(event.payload)['content_type']
          end

        case content_type
        when 'json'
          headers['Content-Type'] = 'application/json; charset=utf-8'
          body = data.to_json
        when 'xml'
          headers['Content-Type'] = 'text/xml; charset=utf-8'
          body = data.to_xml(root: (interpolated(event.payload)[:xml_root] || 'post'))
        when MIME_RE
          headers['Content-Type'] = content_type
          body = data.to_s
        else
          body = data
        end
      else
        error "Invalid method '#{method}'"
      end

      response = faraday.run_request(method.to_sym, url, body, headers) { |request|
        request.params.update(params) if params
      }

      if boolify(interpolated['emit_events'])
        new_event = interpolated['output_mode'].to_s == 'merge' ? event.payload.dup : {}
        create_event payload: new_event.merge(
          body: response.body,
          headers: normalize_response_headers(response.headers),
          status: response.status
        )
      end
    end
  end
end
