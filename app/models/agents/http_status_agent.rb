require 'time_tracker'

module Agents

  class HttpStatusAgent < Agent

    include WebRequestConcern
    include FormConfigurable

    can_dry_run!
    can_order_created_events!

    default_schedule "every_12h"

    form_configurable :url
    form_configurable :disable_redirect_follow, type: :boolean
    form_configurable :changes_only, type: :boolean
    form_configurable :headers_to_save

    description <<-MD
      HttpStatusAgent将检查一个url，并在等待回复时发出生成的HTTP状态代码。 此外，它还可以选择性地发出一个或多个指定标头的值。

      指定`url`并且Http Status Agent将生成具有HTTP状态代码的事件。 如果您指定一个或多个`Headers to save`（逗号分隔），那么标题或标题的值将包含在事件中。

      `disable redirect follow `选项会导致代理不遵循HTTP重定向。 例如，将此设置为`true`将导致接收301重定向到`http://yahoo.com`的代理返回301状态，而不是遵循重定向并返回200。

      仅`changes only`会导致代理仅在状态更改时报告事件。 如果设置为`false`，则将为每个检查创建一个事件。 如果设置为`true`，则仅在状态更改时创建事件（例如，如果您的站点从200更改为500）。
    MD

    event_description <<-MD
      Events will have the following fields:

          {
            "url": "...",
            "status": "...",
            "elapsed_time": "...",
            "headers": {
              "...": "..."
            }
          }
    MD

    def working?
      memory['last_status'].to_i > 0
    end

    def default_options
      {
        'url' => "http://google.com",
        'disable_redirect_follow' => "true",
      }
    end

    def validate_options
      errors.add(:base, "a url must be specified") unless options['url'].present?
    end

    def header_array(str)
      (str || '').split(',').map(&:strip)
    end

    def check
      check_this_url interpolated[:url], header_array(interpolated[:headers_to_save])
    end

    def receive(incoming_events)
      incoming_events.each do |event|
        interpolate_with(event) do
          check_this_url interpolated[:url],
                         header_array(interpolated[:headers_to_save])
        end
      end
    end

    private

    def check_this_url(url, local_headers)
      # Track time
      measured_result = TimeTracker.track { ping(url) }

      current_status = measured_result.result ? measured_result.status.to_s : ''
      return if options['changes_only'] == 'true' && current_status == memory['last_status'].to_s

      payload = { 'url' => url, 'response_received' => false, 'elapsed_time' => measured_result.elapsed_time }

      # Deal with failures
      if measured_result.result
        final_url = boolify(interpolated['disable_redirect_follow']) ? url : measured_result.result.env.url.to_s
        payload.merge!({ 'final_url' => final_url, 'redirected' => (url != final_url), 'response_received' => true, 'status' => current_status })
        # Deal with headers
        if local_headers.present?
          header_results = local_headers.each_with_object({}) { |header, hash| hash[header] = measured_result.result.headers[header] }
          payload.merge!({ 'headers' => header_results })
        end
        create_event payload: payload
        memory['last_status'] = measured_result.status.to_s
      else
        create_event payload: payload
        memory['last_status'] = nil
      end

    end

    def ping(url)
      result = faraday.get url
      result.status > 0 ? result : nil
    rescue
      nil
    end
  end

end
