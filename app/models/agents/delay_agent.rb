module Agents
  class DelayAgent < Agent
    default_schedule "every_12h"

    description <<-MD
       DelayAgent 存储收到的事件并按计划发出它们的副本。 将其用作事件的缓冲区或队列。

      `max_events` 应设置为您希望在缓冲区中保留的最大事件数。 达到此数字时，新事件将被忽略，或者将替换缓冲区中已有的最早事件，具体取决于您是将keep设置为newest 还是oldest。

      `expected_receive_period_in_days`  用于确定代理是否正常工作。 将其设置为您预期在没有此代理接收传入事件的情况下通过的最大天数。

      `max_emitted_events`  用于限制应创建的最大事件的数量。 如果省略此DelayAgent，将为存储在内存中的每个事件创建事件。
    MD

    def default_options
      {
        'expected_receive_period_in_days' => "10",
        'max_events' => "100",
        'keep' => 'newest'
      }
    end

    def validate_options
      unless options['expected_receive_period_in_days'].present? && options['expected_receive_period_in_days'].to_i > 0
        errors.add(:base, "Please provide 'expected_receive_period_in_days' to indicate how many days can pass before this Agent is considered to be not working")
      end

      unless options['keep'].present? && options['keep'].in?(%w[newest oldest])
        errors.add(:base, "The 'keep' option is required and must be set to 'oldest' or 'newest'")
      end

      unless options['max_events'].present? && options['max_events'].to_i > 0
        errors.add(:base, "The 'max_events' option is required and must be an integer greater than 0")
      end
    end

    def working?
      last_receive_at && last_receive_at > options['expected_receive_period_in_days'].to_i.days.ago && !recent_error_logs?
    end

    def receive(incoming_events)
      incoming_events.each do |event|
        memory['event_ids'] ||= []
        memory['event_ids'] << event.id
        if memory['event_ids'].length > interpolated['max_events'].to_i
          if interpolated['keep'] == 'newest'
            memory['event_ids'].shift
          else
            memory['event_ids'].pop
          end
        end
      end
    end

    def check
      if memory['event_ids'] && memory['event_ids'].length > 0
        events = received_events.where(id: memory['event_ids']).reorder('events.id asc')

        if options['max_emitted_events'].present?
          events = events.limit(options['max_emitted_events'].to_i)
        end

        events.each do |event|
          create_event payload: event.payload
          memory['event_ids'].delete(event.id)
        end
      end
    end
  end
end
