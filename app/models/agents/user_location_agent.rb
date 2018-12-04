require 'securerandom'

module Agents
  class UserLocationAgent < Agent
    cannot_be_scheduled!

    gem_dependency_check { defined?(Haversine) }

    description do <<-MD
      用户位置代理根据包含纬度和经度的WebHook POSTS创建事件。 您可以使用POSTLocation或PostGPS iOS应用程序将您的位置发布到https：// localhost：3000 / users / 1 / update_location /：secret其中：您的选项中指定了secret。

      #{'## Include `haversine` in your Gemfile to use this Agent!' if dependencies_missing?}

      如果您只想保留更精确的位置，请将max_accuracy设置为上限，以米为单位。 此字段的默认名称是准确性，但您可以通过设置accuracy_field的值来更改此值

      如果您想要行驶一定距离，请将min_distance设置为最小距离（以米为单位）。 请注意，GPS读数和测量本身并不精确，因此不要依赖于此进行精确过滤。

      要在地图上查看位置，请将api_key设置为您的Google Maps JavaScript API密钥。
    MD
    end

    event_description <<-MD
      Assuming you're using the iOS application, events look like this:

          {
            "latitude": "37.12345",
            "longitude": "-122.12345",
            "timestamp": "123456789.0",
            "altitude": "22.0",
            "horizontal_accuracy": "5.0",
            "vertical_accuracy": "3.0",
            "speed": "0.52595",
            "course": "72.0703",
            "device_token": "..."
          }
    MD

    def working?
      event_created_within?(2) && !recent_error_logs?
    end

    def default_options
      {
        'secret' => SecureRandom.hex(7),
        'max_accuracy' => '',
        'min_distance' => '',
        'api_key' => '',
      }
    end

    def validate_options
      errors.add(:base, "secret is required and must be longer than 4 characters") unless options['secret'].present? && options['secret'].length > 4
    end

    def receive(incoming_events)
      incoming_events.each do |event|
        interpolate_with(event) do
          handle_payload event.payload
        end
      end
    end

    def receive_web_request(params, method, format)
      params = params.symbolize_keys
      if method != 'post'
        return ['Not Found', 404]
      end
      if interpolated['secret'] != params[:secret]
        return ['Not Authorized', 401]
      end

      handle_payload params.except(:secret)

      return ['ok', 200]
    end

    private

    def handle_payload(payload)
      location = Location.new(payload)

      accuracy_field = interpolated[:accuracy_field].presence || "accuracy"

      def accurate_enough?(payload, accuracy_field)
        !interpolated[:max_accuracy].present? || !payload[accuracy_field] || payload[accuracy_field].to_i < interpolated[:max_accuracy].to_i
      end

      def far_enough?(payload)
        if memory['last_location'].present?
          travel = Haversine.distance(memory['last_location']['latitude'].to_i, memory['last_location']['longitude'].to_i, payload['latitude'].to_i, payload['longitude'].to_i).to_meters
          !interpolated[:min_distance].present? || travel > interpolated[:min_distance].to_i
        else # for the first run, before "last_location" exists
          true
        end
      end

      if location.present? && accurate_enough?(payload, accuracy_field) && far_enough?(payload)
        if interpolated[:max_accuracy].present? && !payload[accuracy_field].present?
          log "Accuracy field missing; all locations will be kept"
        end
        create_event payload: payload, location: location
        memory["last_location"] = payload
      end
    end
  end
end
