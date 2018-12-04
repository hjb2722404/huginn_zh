module Agents
  class AttributeDifferenceAgent < Agent
    cannot_be_scheduled!

    description <<-MD
      Attribute Difference Agent 接收事件并发出新事件，其具有与先前接收的事件相比的特定属性的差异或变化。

      `path`  指定要从事件中使用的属性的JSON路径。

      `output` 指定将在原始有效内容上创建的新属性名称，它将包含差异或更改。

      `method` 指定它是否应该.....

      * `percentage_change` 例如： 之前的值为160，新值为116.百分比变化为-27.5
      * `decimal_difference` 例如： 先前的值为5.5，新值为15.2。 差异是9.7
      * `integer_difference` 例如： 之前的值为50，新值为40.差值为-10

      `decimal_precision` 默认为3，但如果需要，您可以覆盖它。

      `expected_update_period_in_days` 用于确定代理是否正常工作。

      生成的事件将是已接收事件的副本，并将差异或更改添加为额外属性。 如果您使用percentage_change，则属性将被格式化为{{attribute}} _ change，否则它将是{{attribute}} _ diff。

      所有配置选项都将根据传入事件进行liquid插值。
    MD

    event_description <<-MD
      This will change based on the source event.
    MD

    def default_options
      {
        'path' => '.data.rate',
        'output' => 'rate_diff',
        'method' => 'integer_difference',
        'expected_update_period_in_days' => 1
      }
    end

    def validate_options
      unless options['path'].present? && options['method'].present? && options['output'].present? && options['expected_update_period_in_days'].present?
        errors.add(:base, 'The attribute, method and expected_update_period_in_days fields are all required.')
      end
    end

    def working?
      event_created_within?(interpolated['expected_update_period_in_days']) && !recent_error_logs?
    end

    def receive(incoming_events)
      incoming_events.each do |event|
        handle(interpolated(event), event)
      end
    end

    private

    def handle(opts, event)
      opts['decimal_precision'] ||= 3
      attribute_value = Utils.value_at(event.payload, opts['path'])
      attribute_value = attribute_value.nil? ? 0 : attribute_value
      payload = event.payload.deep_dup

      if opts['method'] == 'percentage_change'
        change = calculate_percentage_change(attribute_value, opts['decimal_precision'])
        payload[opts['output']] = change

      elsif opts['method'] == 'decimal_difference'
        difference = calculate_decimal_difference(attribute_value, opts['decimal_precision'])
        payload[opts['output']] = difference

      elsif opts['method'] == 'integer_difference'
        difference = calculate_integer_difference(attribute_value)
        payload[opts['output']] = difference
      end

      created_event = create_event(payload: payload)
      log('Propagating new event', outbound_event: created_event, inbound_event: event)
      update_memory(attribute_value)
    end

    def calculate_integer_difference(new_value)
      return 0 if last_value.nil?
      (new_value.to_i - last_value.to_i)
    end

    def calculate_decimal_difference(new_value, dec_pre)
      return 0.0 if last_value.nil?
      (new_value.to_f - last_value.to_f).round(dec_pre.to_i)
    end

    def calculate_percentage_change(new_value, dec_pre)
      return 0.0 if last_value.nil?
      (((new_value.to_f / last_value.to_f) * 100) - 100).round(dec_pre.to_i)
    end

    def last_value
      memory['last_value']
    end

    def update_memory(new_value)
      memory['last_value'] = new_value
    end
  end
end
