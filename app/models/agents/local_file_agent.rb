module Agents
  class LocalFileAgent < Agent
    include LongRunnable
    include FormConfigurable
    include FileHandling

    emits_file_pointer!

    default_schedule 'every_1h'

    def self.should_run?
      ENV['ENABLE_INSECURE_AGENTS'] == "true"
    end

    description do
      <<-MD
        LocalFileAgent可以监视文件/目录以进行更改，也可以为该目录中的每个文件发出事件。 收到事件时，它会将接收的数据写入文件。

        `mode`  确定代理是否正在为（已更改的）文件发送事件或将接收的事件数据写入磁盘。

        ### 读

        当watch设置为true时，LocalFileAgent将监视指定的更改路径，忽略计划并连续监视文件系统。 每次检测到的更改都会发出一个事件。

        当watch设置为false时，代理将为每个计划的运行中的目录中的每个文件发出一个事件。

        #{emitting_file_handling_agent_description}

        ### 写

        每个事件都将写入路径中的文件，液体插值可以更改每个事件的路径。 

        当append为true时，接收的数据将附加到文件中。

        在数据中使用Liquid模板来指定应写入接收事件的哪个部分。

        **警告**：此类型的代理可以读取和写入运行Huginn服务器的用户可以访问的任何文件，并且当前已禁用。 如果您信任所有使用Huginn安装的人，则仅启用此代理。 您可以通过将ENABLE_INSECURE_AGENTS设置为true来在.env文件中启用此代理。
      MD
    end

    event_description do
      "Events will looks like this:\n\n    %s" % if boolify(interpolated['watch'])
        Utils.pretty_print(
          "file_pointer" => {
            "file" => "/tmp/test/filename",
            "agent_id" => id
          },
          "event_type" => "modified/added/removed"
        )
      else
        Utils.pretty_print(
          "file_pointer" => {
            "file" => "/tmp/test/filename",
            "agent_id" => id
          }
        )
      end
    end

    def default_options
      {
        'mode' => 'read',
        'watch' => 'true',
        'append' => 'false',
        'path' => "",
        'data' => '{{ data }}'
      }
    end

    form_configurable :mode, type: :array, values: %w(read write)
    form_configurable :watch, type: :array, values: %w(true false)
    form_configurable :path, type: :string
    form_configurable :append, type: :boolean
    form_configurable :data, type: :string

    def validate_options
      if options['mode'].blank? || !['read', 'write'].include?(options['mode'])
        errors.add(:base, "The 'mode' option is required and must be set to 'read' or 'write'")
      end
      if options['watch'].blank? || ![true, false].include?(boolify(options['watch']))
        errors.add(:base, "The 'watch' option is required and must be set to 'true' or 'false'")
      end
      if options['append'].blank? || ![true, false].include?(boolify(options['append']))
        errors.add(:base, "The 'append' option is required and must be set to 'true' or 'false'")
      end
      if options['path'].blank?
        errors.add(:base, "The 'path' option is required.")
      end
    end

    def working?
      should_run?(false) && ((interpolated['mode'] == 'read' && check_path_existance && checked_without_error?) ||
                             (interpolated['mode'] == 'write' && received_event_without_error?))
    end

    def check
      return if interpolated['mode'] != 'read' || boolify(interpolated['watch']) || !should_run?
      return unless check_path_existance(true)
      if File.directory?(expanded_path)
        Dir.glob(File.join(expanded_path, '*')).select { |f| File.file?(f) }
      else
        [expanded_path]
      end.each do |file|
        create_event payload: get_file_pointer(file)
      end
    end

    def receive(incoming_events)
      return if interpolated['mode'] != 'write' || !should_run?
      incoming_events.each do |event|
        mo = interpolated(event)
        File.open(File.expand_path(mo['path']), boolify(mo['append']) ? 'a' : 'w') do |file|
          file.write(mo['data'])
        end
      end
    end

    def start_worker?
      interpolated['mode'] == 'read' && boolify(interpolated['watch']) && should_run? && check_path_existance
    end

    def check_path_existance(log = true)
      if !File.exist?(expanded_path)
        error("File or directory '#{expanded_path}' does not exist") if log
        return false
      end
      true
    end

    def get_io(file)
      File.open(file, 'r')
    end

    def expanded_path
      @expanded_path ||= File.expand_path(interpolated['path'])
    end

    private

    def should_run?(log = true)
      if self.class.should_run?
        true
      else
        error("Unable to run because insecure agents are not enabled. Set ENABLE_INSECURE_AGENTS to true in the Huginn .env configuration.") if log
        false
      end
    end

    class Worker < LongRunnable::Worker
      def setup
        require 'listen'
        @listener = Listen.to(*listen_options, &method(:callback))
      end

      def run
        sleep unless agent.check_path_existance(true)

        @listener.start
        sleep
      end

      def stop
        @listener.stop
      end

      private

      def callback(*changes)
        AgentRunner.with_connection do
          changes.zip([:modified, :added, :removed]).each do |files, event_type|
            files.each do |file|
              agent.create_event payload: agent.get_file_pointer(file).merge(event_type: event_type)
            end
          end
          agent.touch(:last_check_at)
        end
      end

      def listen_options
        if File.directory?(agent.expanded_path)
          [agent.expanded_path, ignore!: [] ]
        else
          [File.dirname(agent.expanded_path), { ignore!: [], only: /\A#{Regexp.escape(File.basename(agent.expanded_path))}\z/ } ]
        end
      end
    end
  end
end
