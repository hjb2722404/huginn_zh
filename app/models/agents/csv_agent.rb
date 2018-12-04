module Agents
  class CsvAgent < Agent
    include FormConfigurable
    include FileHandling

    cannot_be_scheduled!
    consumes_file_pointer!

    def default_options
      {
        'mode' => 'parse',
        'separator' => ',',
        'use_fields' => '',
        'output' => 'event_per_row',
        'with_header' => 'true',
        'data_path' => '$.data',
        'data_key' => 'data'
      }
    end

    description do
      <<-MD
        CsvAgent解析或序列化CSV数据。 解析时，可以为整个CSV发出事件，也可以每行发送一个事件。

        将模式设置为解析以从传入事件解析CSV，当设置为序列化时，代理会将事件数据血清化为CSV。

        ### 通用选项

        指定用于将字段彼此分隔开的separator （默认为，）。

        `data_key` 在发出的事件中设置包含序列化CSV或已解析CSV数据的键。

        ### 解析

        如果use_fields设置为以逗号分隔的字符串，并且CSV文件包含字段标题，则代理将仅提取指定的字段。

        output确定每行发出一个事件或包含所有行的一个事件。

        如果CSV文件的第一行是字段名称，请将with_header设置为true。

        #{receiving_file_handling_agent_description}

        在常规事件中接收CSV数据时，使用JSONPath选择data_path中的路径。 data_path仅在接收的事件不包含“文件指针”时使用。

        ### 序列化

        如果use_fields设置为逗号分隔字符串，并且第一个接收到的事件在指定的data_path处有一个对象，则生成的CSV将仅包含给定字段。

        将with_header设置为true以在CSV中包含字段标题

        在data_path中使用JSONPath来选择部分接收到的事件应该被序列化。
      MD
    end

    event_description do
      "Events will looks like this:\n\n    %s" % if interpolated['mode'] == 'parse'
        rows = if boolify(interpolated['with_header'])
          [{'column' => 'row1 value1', 'column2' => 'row1 value2'}, {'column' => 'row2 value3', 'column2' => 'row2 value4'}]
        else
          [['row1 value1', 'row1 value2'], ['row2 value1', 'row2 value2']]
        end
        if interpolated['output'] == 'event_per_row'
          Utils.pretty_print(interpolated['data_key'] => rows[0])
        else
          Utils.pretty_print(interpolated['data_key'] => rows)
        end
      else
        Utils.pretty_print(interpolated['data_key'] => '"generated","csv","data"' + "\n" + '"column1","column2","column3"')
      end
    end

    form_configurable :mode, type: :array, values: %w(parse serialize)
    form_configurable :separator, type: :string
    form_configurable :data_key, type: :string
    form_configurable :with_header, type: :boolean
    form_configurable :use_fields, type: :string
    form_configurable :output, type: :array, values: %w(event_per_row event_per_file)
    form_configurable :data_path, type: :string

    def validate_options
      if options['with_header'].blank? || ![true, false].include?(boolify(options['with_header']))
        errors.add(:base, "The 'with_header' options is required and must be set to 'true' or 'false'")
      end
      if options['mode'] == 'serialize' && options['data_path'].blank?
        errors.add(:base, "When mode is set to serialize data_path has to be present.")
      end
    end

    def working?
      received_event_without_error?
    end

    def receive(incoming_events)
      case options['mode']
      when 'parse'
        parse(incoming_events)
      when 'serialize'
        serialize(incoming_events)
      end
    end

    private
    def serialize(incoming_events)
      mo = interpolated(incoming_events.first)
      rows = rows_from_events(incoming_events, mo)
      csv = CSV.generate(col_sep: separator(mo), force_quotes: true ) do |csv|
        if boolify(mo['with_header']) && rows.first.is_a?(Hash)
          if mo['use_fields'].present?
            csv << extract_options(mo)
          else
            csv << rows.first.keys
          end
        end
        rows.each do |data|
          if data.is_a?(Hash)
            if mo['use_fields'].present?
              csv << data.extract!(*extract_options(mo)).values
            else
              csv << data.values
            end
          else
            csv << data
          end
        end
      end
      create_event payload: { mo['data_key'] => csv }
    end

    def rows_from_events(incoming_events, mo)
      [].tap do |rows|
        incoming_events.each do |event|
          data = Utils.value_at(event.payload, mo['data_path'])
          if data.is_a?(Array) && (data[0].is_a?(Array) || data[0].is_a?(Hash))
            data.each { |row| rows << row }
          else
            rows << data
          end
        end
      end
    end

    def parse(incoming_events)
      incoming_events.each do |event|
        mo = interpolated(event)
        next unless io = local_get_io(event)
        if mo['output'] == 'event_per_row'
          parse_csv(io, mo) do |payload|
            create_event payload: { mo['data_key'] => payload }
          end
        else
          create_event payload: { mo['data_key'] => parse_csv(io, mo, []) }
        end
      end
    end

    def local_get_io(event)
      if io = get_io(event)
        io
      else
        Utils.value_at(event.payload, interpolated['data_path'])
      end
    end

    def parse_csv_options(mo)
      options = {
        col_sep: separator(mo),
        headers: boolify(mo['with_header']),
      }
      options[:liberal_parsing] = true if CSV::DEFAULT_OPTIONS.key?(:liberal_parsing)
      options
    end

    def parse_csv(io, mo, array = nil)
      CSV.new(io, **parse_csv_options(mo)).each do |row|
        if block_given?
          yield get_payload(row, mo)
        else
          array << get_payload(row, mo)
        end
      end
      array
    end

    def separator(mo)
      mo['separator'] == '\\t' ? "\t" : mo['separator']
    end

    def get_payload(row, mo)
      if boolify(mo['with_header'])
        if mo['use_fields'].present?
          row.to_hash.extract!(*extract_options(mo))
        else
          row.to_hash
        end
      else
        row
      end
    end

    def extract_options(mo)
      mo['use_fields'].split(',').map(&:strip)
    end
  end
end
