module SortableEvents
  extend ActiveSupport::Concern

  included do
    validate :validate_events_order
  end

  EVENTS_ORDER_KEY = 'events_order'.freeze
  EVENTS_DESCRIPTION = 'events created in each run'.freeze

  def description_events_order(*args)
    self.class.description_events_order(*args)
  end

  module ClassMethods
    def can_order_created_events!
      raise 'Cannot order events for agent that cannot create events' if cannot_create_events?
      prepend AutomaticSorter
    end

    def can_order_created_events?
      include? AutomaticSorter
    end

    def cannot_order_created_events?
      !can_order_created_events?
    end

    def description_events_order(events = EVENTS_DESCRIPTION, events_order_key = EVENTS_ORDER_KEY)
      <<-MD.lstrip
        要指定#{events}的顺序 , 将`#{events_order_key}`设置为排序键数组, 每个看起来都像`expression`或`[expression, type, descending]`，如下所述:

        * _expression_ 是一个Liquid模板，用于生成要用作排序键的字符串。

        * _type_ （可选）是字符串（默认），数字和时间之一，它指定如何计算表达式以进行比较。

        * _descending_ （可选）是一个布尔值，用于确定是否应按降序（反向）顺序进行比较，默认为false。

        前面列出的排序键优先于后面列出的键。 例如，如果您想按日期排序文章，然后按作者排序，请指定[[“{{date}}”，“time”]，“{{author}}”]。

        排序稳定，因此即使所有事件都具有相同的排序键值集，也会保留原始顺序。 此外，还提供了一个特殊的Liquid变量_index_，其中包含每个事件的从零开始的索引号，这意味着您可以通过指定[[“{{_index_}}”，“number”，true]来完全反转事件的顺序。 ]。

        #{description_include_sort_info if events == EVENTS_DESCRIPTION}
      MD
    end

    def description_include_sort_info
      <<-MD.lstrip
        If the `include_sort_info` option is set, each created event will have a `sort_info` key whose value is a hash containing the following keys:

        * `position`: 1-based index of each event after the sort
        * `count`: Total number of events sorted
      MD
    end
  end

  def can_order_created_events?
    self.class.can_order_created_events?
  end

  def cannot_order_created_events?
    self.class.cannot_order_created_events?
  end

  def events_order(key = EVENTS_ORDER_KEY)
    options[key]
  end

  def include_sort_info?
    boolify(interpolated['include_sort_info'])
  end

  def create_events(events)
    if include_sort_info?
      count = events.count
      events.each.with_index(1) do |event, position|
        event.payload[:sort_info] = {
          position: position,
          count: count
        }
        create_event(event)
      end
    else
      events.each do |event|
        create_event(event)
      end
    end
  end

  module AutomaticSorter
    def check
      return super unless events_order || include_sort_info?
      sorting_events do
        super
      end
    end

    def receive(incoming_events)
      return super unless events_order || include_sort_info?
      # incoming events should be processed sequentially
      incoming_events.each do |event|
        sorting_events do
          super([event])
        end
      end
    end

    def create_event(event)
      if @sortable_events
        event = build_event(event)
        @sortable_events << event
        event
      else
        super
      end
    end

    private

    def sorting_events(&block)
      @sortable_events = []
      yield
    ensure
      events, @sortable_events = sort_events(@sortable_events), nil
      create_events(events)
    end
  end

  private

  EXPRESSION_PARSER = {
    'string' => ->string { string },
    'number' => ->string { string.to_f },
    'time'   => ->string { Time.zone.parse(string) },
  }
  EXPRESSION_TYPES = EXPRESSION_PARSER.keys.freeze

  def validate_events_order(events_order_key = EVENTS_ORDER_KEY)
    case order_by = events_order(events_order_key)
    when nil
    when Array
      # Each tuple may be either [expression, type, desc] or just
      # expression.
      order_by.each do |expression, type, desc|
        case expression
        when String
          # ok
        else
          errors.add(:base, "first element of each #{events_order_key} tuple must be a Liquid template")
          break
        end
        case type
        when nil, *EXPRESSION_TYPES
          # ok
        else
          errors.add(:base, "second element of each #{events_order_key} tuple must be #{EXPRESSION_TYPES.to_sentence(last_word_connector: ' or ')}")
          break
        end
        if !desc.nil? && boolify(desc).nil?
          errors.add(:base, "third element of each #{events_order_key} tuple must be a boolean value")
          break
        end
      end
    else
      errors.add(:base, "#{events_order_key} must be an array of arrays")
    end
  end

  # Sort given events in order specified by the "events_order" option
  def sort_events(events, events_order_key = EVENTS_ORDER_KEY)
    order_by = events_order(events_order_key).presence or
      return events

    orders = order_by.map { |_, _, desc = false| boolify(desc) }

    Utils.sort_tuples!(
      events.map.with_index { |event, index|
        interpolate_with(event) {
          interpolation_context['_index_'] = index
          order_by.map { |expression, type, _|
            string = interpolate_string(expression)
            begin
              EXPRESSION_PARSER[type || 'string'.freeze][string]
            rescue
              error "Cannot parse #{string.inspect} as #{type}; treating it as string"
              string
            end
          }
        } << index << event  # index is to make sorting stable
      },
      orders
    ).collect!(&:last)
  end
end
