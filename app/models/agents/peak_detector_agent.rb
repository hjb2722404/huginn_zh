require 'pp'

module Agents
  class PeakDetectorAgent < Agent
    cannot_be_scheduled!

    DEFAULT_SEARCH_URL = 'https://twitter.com/search?q={q}'

    description <<-MD

      Peak Detector Agent将监视事件流中的峰值。 检测到峰值时，生成的事件将显示消息的有效负载消息。 您可以在消息中包含提取，例如：我看到了一个栏：{{foo.bar}}，请查看Wiki以获取详细信息

       value_path值是感兴趣的值的JSONPath。 group_by_path是一个JSONPath，用于对值进行分组（如果存在）。

       将expected_receive_period_in_days设置为您希望在此代理接收的事件之间传递的最长时间。

       您可以设置window_duration_in_days以更改默认内存窗口长度14天，min_peak_spacing_in_days更改默认最小峰值间隔2天（更接近的峰值将被忽略），并且std_multiple更改默认标准差阈值阈值倍数3。

       在代理开始检测之前，您可以将min_events设置为最小累积事件数。

       您可以使用RFC 6570中定义的URI模板语法将search_url设置为指向除Twitter搜索之外的其他内容。默认值为https://twitter.com/search?q={q}其中{q}将替换为组 名称。
    MD

    event_description <<-MD
      Events look like:

          {
            "message": "Your message",
            "peak": 6,
            "peak_time": 3456789242,
            "grouped_by": "something"
          }
    MD

    def validate_options
      unless options['expected_receive_period_in_days'].present? && options['message'].present? && options['value_path'].present? && options['min_events'].present?
        errors.add(:base, "expected_receive_period_in_days, value_path, min_events and message are required")
      end
      begin
        tmpl = search_url
      rescue => e
        errors.add(:base, "search_url must be a valid URI template: #{e.message}")
      else
        unless tmpl.keys.include?('q')
          errors.add(:base, "search_url must include a variable named 'q'")
        end
      end
    end

    def default_options
      {
        'expected_receive_period_in_days' => "2",
        'group_by_path' => "filter",
        'value_path' => "count",
        'message' => "A peak of {{count}} was found in {{filter}}",
        'min_events' => '4',
      }
    end

    def working?
      last_receive_at && last_receive_at > interpolated['expected_receive_period_in_days'].to_i.days.ago && !recent_error_logs?
    end

    def receive(incoming_events)
      incoming_events.sort_by(&:created_at).each do |event|
        group = group_for(event)
        remember group, event
        check_for_peak group, event
      end
    end

    def search_url
      Addressable::Template.new(options[:search_url].presence || DEFAULT_SEARCH_URL)
    end

    private

    def check_for_peak(group, event)
      memory['peaks'] ||= {}
      memory['peaks'][group] ||= []

      return if memory['data'][group].length <= options['min_events'].to_i

      if memory['peaks'][group].empty? || memory['peaks'][group].last < event.created_at.to_i - peak_spacing
        average_value, standard_deviation = stats_for(group, :skip_last => 1)
        newest_value, newest_time = memory['data'][group][-1].map(&:to_f)

        if newest_value > average_value + std_multiple * standard_deviation
          memory['peaks'][group] << newest_time
          memory['peaks'][group].reject! { |p| p <= newest_time - window_duration }
          create_event :payload => { 'message' => interpolated(event)['message'], 'peak' => newest_value, 'peak_time' => newest_time, 'grouped_by' => group.to_s }
        end
      end
    end

    def stats_for(group, options = {})
      data = memory['data'][group].map { |d| d.first.to_f }
      data = data[0...(data.length - (options[:skip_last] || 0))]
      length = data.length.to_f
      mean = 0
      mean_variance = 0
      data.each do |value|
        mean += value
      end
      mean /= length
      data.each do |value|
        variance = (value - mean)**2
        mean_variance += variance
      end
      mean_variance /= length
      standard_deviation = Math.sqrt(mean_variance)
      [mean, standard_deviation]
    end

    def window_duration
      if interpolated['window_duration'].present? # The older option
        interpolated['window_duration'].to_i
      else
        (interpolated['window_duration_in_days'] || 14).to_f.days
      end
    end

    def std_multiple
      (interpolated['std_multiple'] || 3).to_f
    end

    def peak_spacing
      if interpolated['peak_spacing'].present? # The older option
        interpolated['peak_spacing'].to_i
      else
        (interpolated['min_peak_spacing_in_days'] || 2).to_f.days
      end
    end

    def group_for(event)
      ((interpolated['group_by_path'].present? && Utils.value_at(event.payload, interpolated['group_by_path'])) || 'no_group')
    end

    def remember(group, event)
      memory['data'] ||= {}
      memory['data'][group] ||= []
      memory['data'][group] << [ Utils.value_at(event.payload, interpolated['value_path']).to_f, event.created_at.to_i ]
      cleanup group
    end

    def cleanup(group)
      newest_time = memory['data'][group].last.last
      memory['data'][group].reject! { |value, time| time <= newest_time - window_duration }
    end
  end
end
