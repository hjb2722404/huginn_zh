module Agents
  class HumanTaskAgent < Agent
    default_schedule "every_10m"

    gem_dependency_check { defined?(RTurk) }

    description <<-MD
      人工任务代理用于在Mechanical Turk上创建人工智能任务（HIT）。

      #{'## Include `rturk` in your Gemfile to use this Agent!' if dependencies_missing?}

      可以响应事件或按计划创建HIT。 将trigger_on设置为schedule或event。

      # 计划任务

      此代理的时间表是检查已完成的HIT的频率，而不是检查提交HIT的频率。 要配置在计划模式下应提交新HIT的频率，请将submission_period设置为小时数。

      # 例子

      如果使用事件创建，则所有HIT字段都可以通过液体模板包含插值。 例如，如果传入的事件是Twitter事件，您可以让HITT评估其情绪，如下所示：

          {
            "expected_receive_period_in_days": 2,
            "trigger_on": "event",
            "hit": {
              "assignments": 1,
              "title": "Sentiment evaluation",
              "description": "Please rate the sentiment of this message: '{{message}}'",
              "reward": 0.05,
              "lifetime_in_seconds": "3600",
              "questions": [
                {
                  "type": "selection",
                  "key": "sentiment",
                  "name": "Sentiment",
                  "required": "true",
                  "question": "Please select the best sentiment value:",
                  "selections": [
                    { "key": "happy", "text": "Happy" },
                    { "key": "sad", "text": "Sad" },
                    { "key": "neutral", "text": "Neutral" }
                  ]
                },
                {
                  "type": "free_text",
                  "key": "feedback",
                  "name": "Have any feedback for us?",
                  "required": "false",
                  "question": "Feedback",
                  "default": "Type here...",
                  "min_length": "2",
                  "max_length": "2000"
                }
              ]
            }
          }

      如您所见，您可以使用命中选项配置创建的HIT。 必填字段是标题，它是创建的HIT的标题，描述，它是HIT的描述，以及问题是一系列问题。 问题可以是类型选择或free_text。 两种类型都需要密钥，名称，必需，类型和问题配置选项。 此外，选择需要选择的选项数组，每个选项包含键和文本。 对于free_text，特殊配置选项都是可选的，并且是default，min_length和max_length。

      默认情况下，所有答案都在一个事件中发出。 如果您希望每个答案都有单独的事件，请将separate_answers设置为true

      # 合并答案

      有几种方法可以组合具有多个分配的HIT，所有这些方法都涉及在顶层设置combination_mode

      ## 占多数

      选项1：如果您的所有问题都是类型选择，则可以将combination_mode设置为take_majority。 这将导致代理自动为所有分配中的每个问题选择多数投票，并将其作为majority_answer返回。 如果所有选择都是数字，则还会生成average_answer。
      
      选项2：您可以让代理人要求其他人员对分配进行排名并返回排名最高的答案。 为此，请将combination_mode设置为poll并提供poll_options对象。 这是一个例子：
      
          {
            "trigger_on": "schedule",
            "submission_period": 12,
            "combination_mode": "poll",
            "poll_options": {
              "title": "Take a poll about some jokes",
              "instructions": "Please rank these jokes from most funny (5) to least funny (1)",
              "assignments": 3,
              "row_template": "{{joke}}"
            },
            "hit": {
              "assignments": 5,
              "title": "Tell a joke",
              "description": "Please tell me a joke",
              "reward": 0.05,
              "lifetime_in_seconds": "3600",
              "questions": [
                {
                  "type": "free_text",
                  "key": "joke",
                  "name": "Your joke",
                  "required": "true",
                  "question": "Joke",
                  "min_length": "2",
                  "max_length": "2000"
                }
              ]
            }
          }

        生成的事件将包含原始答案以及投票结果，以及一个名为best_answer的字段，其中包含由投票确定的最佳答案。 （请注意，执行轮询时，separate_answers不起作用。）

      # 其他设置

      lifetime_in_seconds是HIT在自动关闭之前留在亚马逊上的秒数。 默认值为1天。

      与大多数代理一样，如果trigger_on设置为event，则需要expected_receive_period_in_days。
    MD

    event_description <<-MD
      Events look like:

          {
            "answers": [
              {
                "feedback": "Hello!",
                "sentiment": "happy"
              }
            ]
          }
    MD

    def validate_options
      options['hit'] ||= {}
      options['hit']['questions'] ||= []

      errors.add(:base, "'trigger_on' must be one of 'schedule' or 'event'") unless %w[schedule event].include?(options['trigger_on'])
      errors.add(:base, "'hit.assignments' should specify the number of HIT assignments to create") unless options['hit']['assignments'].present? && options['hit']['assignments'].to_i > 0
      errors.add(:base, "'hit.title' must be provided") unless options['hit']['title'].present?
      errors.add(:base, "'hit.description' must be provided") unless options['hit']['description'].present?
      errors.add(:base, "'hit.questions' must be provided") unless options['hit']['questions'].present? && options['hit']['questions'].length > 0

      if options['trigger_on'] == "event"
        errors.add(:base, "'expected_receive_period_in_days' is required when 'trigger_on' is set to 'event'") unless options['expected_receive_period_in_days'].present?
      elsif options['trigger_on'] == "schedule"
        errors.add(:base, "'submission_period' must be set to a positive number of hours when 'trigger_on' is set to 'schedule'") unless options['submission_period'].present? && options['submission_period'].to_i > 0
      end

      if options['hit']['questions'].any? { |question| %w[key name required type question].any? {|k| !question[k].present? } }
        errors.add(:base, "all questions must set 'key', 'name', 'required', 'type', and 'question'")
      end

      if options['hit']['questions'].any? { |question| question['type'] == "selection" && (!question['selections'].present? || question['selections'].length == 0 || !question['selections'].all? {|s| s['key'].present? } || !question['selections'].all? { |s| s['text'].present? })}
        errors.add(:base, "all questions of type 'selection' must have a selections array with selections that set 'key' and 'name'")
      end

      if take_majority? && options['hit']['questions'].any? { |question| question['type'] != "selection" }
        errors.add(:base, "all questions must be of type 'selection' to use the 'take_majority' option")
      end

      if create_poll?
        errors.add(:base, "poll_options is required when combination_mode is set to 'poll' and must have the keys 'title', 'instructions', 'row_template', and 'assignments'") unless options['poll_options'].is_a?(Hash) && options['poll_options']['title'].present? && options['poll_options']['instructions'].present? && options['poll_options']['row_template'].present? && options['poll_options']['assignments'].to_i > 0
      end
    end

    def default_options
      {
        'expected_receive_period_in_days' => 2,
        'trigger_on' => "event",
        'hit' =>
          {
            'assignments' => 1,
            'title' => "Sentiment evaluation",
            'description' => "Please rate the sentiment of this message: '{{message}}'",
            'reward' => 0.05,
            'lifetime_in_seconds' => 24 * 60 * 60,
            'questions' =>
              [
                {
                  'type' => "selection",
                  'key' => "sentiment",
                  'name' => "Sentiment",
                  'required' => "true",
                  'question' => "Please select the best sentiment value:",
                  'selections' =>
                    [
                      { 'key' => "happy", 'text' => "Happy" },
                      { 'key' => "sad", 'text' => "Sad" },
                      { 'key' => "neutral", 'text' => "Neutral" }
                    ]
                },
                {
                  'type' => "free_text",
                  'key' => "feedback",
                  'name' => "Have any feedback for us?",
                  'required' => "false",
                  'question' => "Feedback",
                  'default' => "Type here...",
                  'min_length' => "2",
                  'max_length' => "2000"
                }
              ]
          }
      }
    end

    def working?
      last_receive_at && last_receive_at > interpolated['expected_receive_period_in_days'].to_i.days.ago && !recent_error_logs?
    end

    def check
      review_hits

      if interpolated['trigger_on'] == "schedule" && (memory['last_schedule'] || 0) <= Time.now.to_i - interpolated['submission_period'].to_i * 60 * 60
        memory['last_schedule'] = Time.now.to_i
        create_basic_hit
      end
    end

    def receive(incoming_events)
      if interpolated['trigger_on'] == "event"
        incoming_events.each do |event|
          create_basic_hit event
        end
      end
    end

    protected

    if defined?(RTurk)

      def take_majority?
        interpolated['combination_mode'] == "take_majority" || interpolated['take_majority'] == "true"
      end

      def create_poll?
        interpolated['combination_mode'] == "poll"
      end

      def event_for_hit(hit_id)
        if memory['hits'][hit_id].is_a?(Hash)
          Event.find_by_id(memory['hits'][hit_id]['event_id'])
        else
          nil
        end
      end

      def hit_type(hit_id)
        if memory['hits'][hit_id].is_a?(Hash) && memory['hits'][hit_id]['type']
          memory['hits'][hit_id]['type']
        else
          'user'
        end
      end

      def review_hits
        reviewable_hit_ids = RTurk::GetReviewableHITs.create.hit_ids
        my_reviewed_hit_ids = reviewable_hit_ids & (memory['hits'] || {}).keys
        if reviewable_hit_ids.length > 0
          log "MTurk reports #{reviewable_hit_ids.length} HITs, of which I own [#{my_reviewed_hit_ids.to_sentence}]"
        end

        my_reviewed_hit_ids.each do |hit_id|
          hit = RTurk::Hit.new(hit_id)
          assignments = hit.assignments

          log "Looking at HIT #{hit_id}.  I found #{assignments.length} assignments#{" with the statuses: #{assignments.map(&:status).to_sentence}" if assignments.length > 0}"
          if assignments.length == hit.max_assignments && assignments.all? { |assignment| assignment.status == "Submitted" }
            inbound_event = event_for_hit(hit_id)

            if hit_type(hit_id) == 'poll'
              # handle completed polls

              log "Handling a poll: #{hit_id}"

              scores = {}
              assignments.each do |assignment|
                assignment.answers.each do |index, rating|
                  scores[index] ||= 0
                  scores[index] += rating.to_i
                end
              end

              top_answer = scores.to_a.sort {|b, a| a.last <=> b.last }.first.first

              payload = {
                'answers' => memory['hits'][hit_id]['answers'],
                'poll' => assignments.map(&:answers),
                'best_answer' => memory['hits'][hit_id]['answers'][top_answer.to_i - 1]
              }

              event = create_event :payload => payload
              log "Event emitted with answer(s) for poll", :outbound_event => event, :inbound_event => inbound_event
            else
              # handle normal completed HITs
              payload = { 'answers' => assignments.map(&:answers) }

              if take_majority?
                counts = {}
                options['hit']['questions'].each do |question|
                  question_counts = question['selections'].inject({}) { |memo, selection| memo[selection['key']] = 0; memo }
                  assignments.each do |assignment|
                    answers = ActiveSupport::HashWithIndifferentAccess.new(assignment.answers)
                    answer = answers[question['key']]
                    question_counts[answer] += 1
                  end
                  counts[question['key']] = question_counts
                end
                payload['counts'] = counts

                majority_answer = counts.inject({}) do |memo, (key, question_counts)|
                  memo[key] = question_counts.to_a.sort {|a, b| a.last <=> b.last }.last.first
                  memo
                end
                payload['majority_answer'] = majority_answer

                if all_questions_are_numeric?
                  average_answer = counts.inject({}) do |memo, (key, question_counts)|
                    sum = divisor = 0
                    question_counts.to_a.each do |num, count|
                      sum += num.to_s.to_f * count
                      divisor += count
                    end
                    memo[key] = sum / divisor.to_f
                    memo
                  end
                  payload['average_answer'] = average_answer
                end
              end

              if create_poll?
                questions = []
                selections = 5.times.map { |i| { 'key' => i+1, 'text' => i+1 } }.reverse
                assignments.length.times do |index|
                  questions << {
                    'type' => "selection",
                    'name' => "Item #{index + 1}",
                    'key' => index,
                    'required' => "true",
                    'question' => interpolate_string(options['poll_options']['row_template'], assignments[index].answers),
                    'selections' => selections
                  }
                end

                poll_hit = create_hit 'title' => options['poll_options']['title'],
                                      'description' => options['poll_options']['instructions'],
                                      'questions' => questions,
                                      'assignments' => options['poll_options']['assignments'],
                                      'lifetime_in_seconds' => options['poll_options']['lifetime_in_seconds'],
                                      'reward' => options['poll_options']['reward'],
                                      'payload' => inbound_event && inbound_event.payload,
                                      'metadata' => { 'type' => 'poll',
                                                      'original_hit' => hit_id,
                                                      'answers' => assignments.map(&:answers),
                                                      'event_id' => inbound_event && inbound_event.id }

                log "Poll HIT created with ID #{poll_hit.id} and URL #{poll_hit.url}.  Original HIT: #{hit_id}", :inbound_event => inbound_event
              else
                if options[:separate_answers]
                  payload['answers'].each.with_index do |answer, index|
                    sub_payload = payload.dup
                    sub_payload.delete('answers')
                    sub_payload['answer'] = answer
                    event = create_event :payload => sub_payload
                    log "Event emitted with answer ##{index}", :outbound_event => event, :inbound_event => inbound_event
                  end
                else
                  event = create_event :payload => payload
                  log "Event emitted with answer(s)", :outbound_event => event, :inbound_event => inbound_event
                end
              end
            end

            assignments.each(&:approve!)
            hit.dispose!

            memory['hits'].delete(hit_id)
          end
        end
      end

      def all_questions_are_numeric?
        interpolated['hit']['questions'].all? do |question|
          question['selections'].all? do |selection|
            selection['key'] == selection['key'].to_f.to_s || selection['key'] == selection['key'].to_i.to_s
          end
        end
      end

      def create_basic_hit(event = nil)
        hit = create_hit 'title' => options['hit']['title'],
                         'description' => options['hit']['description'],
                         'questions' => options['hit']['questions'],
                         'assignments' => options['hit']['assignments'],
                         'lifetime_in_seconds' => options['hit']['lifetime_in_seconds'],
                         'reward' => options['hit']['reward'],
                         'payload' => event && event.payload,
                         'metadata' => { 'event_id' => event && event.id }

        log "HIT created with ID #{hit.id} and URL #{hit.url}", :inbound_event => event
      end

      def create_hit(opts = {})
        payload = opts['payload'] || {}
        title = interpolate_string(opts['title'], payload).strip
        description = interpolate_string(opts['description'], payload).strip
        questions = interpolate_options(opts['questions'], payload)
        hit = RTurk::Hit.create(:title => title) do |hit|
          hit.max_assignments = (opts['assignments'] || 1).to_i
          hit.description = description
          hit.lifetime = (opts['lifetime_in_seconds'] || 24 * 60 * 60).to_i
          hit.question_form AgentQuestionForm.new(:title => title, :description => description, :questions => questions)
          hit.reward = (opts['reward'] || 0.05).to_f
          #hit.qualifications.add :approval_rate, { :gt => 80 }
        end
        memory['hits'] ||= {}
        memory['hits'][hit.id] = opts['metadata'] || {}
        hit
      end

      # RTurk Question Form

      class AgentQuestionForm < RTurk::QuestionForm
        needs :title, :description, :questions

        def question_form_content
          Overview do
            Title do
              text @title
            end
            Text do
              text @description
            end
          end

          @questions.each.with_index do |question, index|
            Question do
              QuestionIdentifier do
                text question['key'] || "question_#{index}"
              end
              DisplayName do
                text question['name'] || "Question ##{index}"
              end
              IsRequired do
                text question['required'] || 'true'
              end
              QuestionContent do
                Text do
                  text question['question']
                end
              end
              AnswerSpecification do
                if question['type'] == "selection"

                  SelectionAnswer do
                    StyleSuggestion do
                      text 'radiobutton'
                    end
                    Selections do
                      question['selections'].each do |selection|
                        Selection do
                          SelectionIdentifier do
                            text selection['key']
                          end
                          Text do
                            text selection['text']
                          end
                        end
                      end
                    end
                  end

                else

                  FreeTextAnswer do
                    if question['min_length'].present? || question['max_length'].present?
                      Constraints do
                        lengths = {}
                        lengths['minLength'] = question['min_length'].to_s if question['min_length'].present?
                        lengths['maxLength'] = question['max_length'].to_s if question['max_length'].present?
                        Length lengths
                      end
                    end

                    if question['default'].present?
                      DefaultText do
                        text question['default']
                      end
                    end
                  end

                end
              end
            end
          end
        end
      end
    end
  end
end
