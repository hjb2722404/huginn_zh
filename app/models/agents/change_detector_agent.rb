module Agents
  class ChangeDetectorAgent < Agent
    cannot_be_scheduled!

    description <<-MD
      The Change Detector Agent  更改检测器代理接收事件流，并在接收到的事件的属性更改时发出新事件。

      property指定一个Liquid模板，该模板扩展为要监视的属性，您可以在其中使用变量last_property作为最后一个属性值。 如果要检测新的最低价格，请尝试以下操作：{％assign drop = last_property | 减去：price％} {％if last_property == blank或drop> 0％} {{price | 默认值：last_property}} {％else％} {{last_property}} {％endif％}

      `expected_update_period_in_days` 用于确定代理是否正常工作。

      结果事件将是收到的事件的副本.
    MD

    event_description <<-MD
    This will change based on the source event. If you were event from the ShellCommandAgent, your outbound event might look like:

      {
        'command' => 'pwd',
        'path' => '/home/Huginn',
        'exit_status' => '0',
        'errors' => '',
        'output' => '/home/Huginn'
      }
    MD

    def default_options
      {
          'property' => '{{output}}',
          'expected_update_period_in_days' => 1
      }
    end

    def validate_options
      unless options['property'].present? && options['expected_update_period_in_days'].present?
        errors.add(:base, "The property and expected_update_period_in_days fields are all required.")
      end
    end

    def working?
      event_created_within?(interpolated['expected_update_period_in_days']) && !recent_error_logs?
    end

    def receive(incoming_events)
      incoming_events.each do |event|
        interpolation_context.stack do
          interpolation_context['last_property'] = last_property
          handle(interpolated(event), event)
        end
      end
    end

    private

    def handle(opts, event = nil)
      property = opts['property']
      if has_changed?(property)
        created_event = create_event :payload => event.payload

        log("Propagating new event as property has changed to #{property} from #{last_property}", :outbound_event => created_event, :inbound_event => event )
        update_memory(property)
      else
        log("Not propagating as incoming event has not changed from #{last_property}.", :inbound_event => event )
      end
    end

    def has_changed?(property)
      property != last_property
    end

    def last_property
      self.memory['last_property']
    end

    def update_memory(property)
      self.memory['last_property'] = property
    end
  end
end
