module Agents
  class DigestAgent < Agent
    include FormConfigurable

    default_schedule "6am"

    description <<-MD
      Digest Agent 收集发送给它的任何事件，并将它们作为单个事件发出。

      生成的事件将具有消息的有效负载消息。 您可以在消息中使用液体模板，有关详细信息，请查看[Wiki](https://github.com/huginn/huginn/wiki/Formatting-Events-using-Liquid)。

      将expected_receive_period_in_days设置为您希望在此代理接收的事件之间传递的最长时间.

      如果retain_events设置为0（默认值），则在发送摘要后将清除所有已接收事件。 将retained_events设置为大于0的值，以便在滚动的基础上保留一定数量的事件，以便在将来的摘要中重新发送

      例如，假设`retain_events`设置为`3`，并且代理已经收到事件`5`,`4`和`3`.当发送摘要时，将保留事件`5`,`4`和`3`以供将来摘要使用。 收到事件`6`后，下一个摘要将包含事件`6`,`5`和`4`。
    MD

    event_description <<-MD
      Events look like this:

          {
            "events": [ event list ],
            "message": "Your message"
          }
    MD

    def default_options
      {
          "expected_receive_period_in_days" => "2",
          "message" => "{{ events | map: 'message' | join: ',' }}",
          "retained_events" => "0"
      }
    end

    form_configurable :message, type: :text
    form_configurable :expected_receive_period_in_days
    form_configurable :retained_events

    def validate_options
      errors.add(:base, 'retained_events must be 0 to 999') unless options['retained_events'].to_i >= 0 && options['retained_events'].to_i < 1000
    end

    def working?
      last_receive_at && last_receive_at > interpolated["expected_receive_period_in_days"].to_i.days.ago && !recent_error_logs?
    end

    def receive(incoming_events)
      self.memory["queue"] ||= []
      incoming_events.each do |event|
        self.memory["queue"] << event.id
      end
      if interpolated["retained_events"].to_i > 0 && memory["queue"].length > interpolated["retained_events"].to_i
        memory["queue"].shift(memory["queue"].length - interpolated["retained_events"].to_i)
      end
    end

    def check
      if self.memory["queue"] && self.memory["queue"].length > 0
        events = received_events.where(id: self.memory["queue"]).order(id: :asc).to_a
        payload = { "events" => events.map { |event| event.payload } }
        payload["message"] = interpolated(payload)["message"]
        create_event :payload => payload
        if interpolated["retained_events"].to_i == 0
          self.memory["queue"] = []
        end
      end
    end
  end
end
