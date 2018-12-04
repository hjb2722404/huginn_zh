module Agents
  class GoogleTranslationAgent < Agent
    cannot_be_scheduled!

    gem_dependency_check { defined?(Google) && defined?(Google::Cloud::Translate) }

    description <<-MD
      Translation Agent 尝试在自然语言之间翻译文本

      #{'## Include `google-api-client` in your Gemfile to use this Agent!' if dependencies_missing?}

      使用Google翻译提供服务。 您可以注册以获取使用此代理所需的google_api_key。 该服务不是免费的。

      要使用google_api_key的证书，请使用liquid `credential` 标记，例如{％credential google-api-key％}

      `to`  必须填写[翻译目标语言代码](https://cloud.google.com/translate/docs/languages)。 

      `from` 需要翻译的语言。 如果未指定，API将尝试自动检测源语言并在响应中返回。

      在内容字段中指定要翻译的内容，您可以使用Liquid指定要翻译的有效负载的哪个部分。

      `expected_receive_period_in_days` 是允许在事件之间传递的最大天数。
    MD

    event_description "User defined"

    def default_options
      {
        'to' => "sv",
        'from' => 'en',
        'google_api_key' => '',
        'expected_receive_period_in_days' => 1,
        'content' => {
          'text' => "{{message}}",
          'moretext' => "{{another message}}"
        }
      }
    end

    def working?
      last_receive_at && last_receive_at > interpolated['expected_receive_period_in_days'].to_i.days.ago && !recent_error_logs?
    end

    def validate_options
      unless options['google_api_key'].present? && options['to'].present? && options['content'].present? && options['expected_receive_period_in_days'].present?
        errors.add :base, "google_api_key, to, content and expected_receive_period_in_days are all required"
      end
    end

    def translate_from
      interpolated["from"].presence
    end

    def receive(incoming_events)
      incoming_events.each do |event|
        translated_event = {}
        opts = interpolated(event)
        opts['content'].each_pair do |key, value|
          result = translate(value)
          translated_event[key] = result.text
        end
        create_event payload: translated_event
      end
    end

    def google_client
      @google_client ||= Google::APIClient.new(
        {
          application_name: "Huginn",
          application_version: "0.0.1",
          key: options['google_api_key'],
          authorization: nil
        }
      )
    end

    def translate_service
      @translate_service ||= google_client.discovered_api('translate','v2')
    end

    def cloud_translate_service
      # https://github.com/GoogleCloudPlatform/google-cloud-ruby/blob/master/google-cloud-translate/lib/google-cloud-translate.rb#L130
      @google_client ||= Google::Cloud::Translate.new(key: interpolated['google_api_key'])
    end

    def translate(value)
      # google_client.execute(
      #   api_method: translate_service.translations.list,
      #   parameters: {
      #     format: 'text',
      #     source: translate_from,
      #     target: options["to"],
      #     q: value
      #   }
      # )
      cloud_translate_service.translate(value, to: interpolated["to"], from: translate_from, format: "text")
    end
  end
end
