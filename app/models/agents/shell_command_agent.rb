module Agents
  class ShellCommandAgent < Agent
    default_schedule "never"

    can_dry_run!
    no_bulk_receive!


    def self.should_run?
      ENV['ENABLE_INSECURE_AGENTS'] == "true"
    end

    description <<-MD
      Shell命令代理将在本地系统上执行命令，并返回输出。

      `command` 指定要执行的命令（shell命令行字符串或命令行参数数组），path将告诉ShellCommandAgent在哪个目录中运行此命令。 stdin的内容将通过标准输入提供给命令。

      `expected_update_period_in_days`  用于确定代理是否正常工作。

      ShellCommandAgent也可以根据收到的事件采取行动。 收到事件时，此代理的选项可以插入来自传入事件的值。 例如，您的命令可以定义为{{cmd}}，在这种情况下，将使用事件的cmd属性。

      生成的事件将包含已执行的命令，在其下执行的路径，命令的exit_status，错误和实际输出。 如果结果意味着出错，ShellCommandAgent将不会记录错误。

      如果unbundle设置为true，则命令在Huginn的bundler上下文之外的干净环境中运行。

      如果suppress_on_failure设置为true，则exit_status不为零时不会发出任何事件。

      如果suppress_on_empty_output设置为true，则输出为空时不会发出任何事件。

      警告：此类型的代理程序在您的系统上运行任意命令，并且当前已禁用。 如果您信任所有使用Huginn安装的人，则仅启用此代理。 您可以通过将ENABLE_INSECURE_AGENTS设置为true来在.env文件中启用此代理。
    MD

    event_description <<-MD
    Events look like this:

        {
          "command": "pwd",
          "path": "/home/Huginn",
          "exit_status": 0,
          "errors": "",
          "output": "/home/Huginn"
        }
    MD

    def default_options
      {
          'path' => "/",
          'command' => "pwd",
          'unbundle' => false,
          'suppress_on_failure' => false,
          'suppress_on_empty_output' => false,
          'expected_update_period_in_days' => 1
      }
    end

    def validate_options
      unless options['path'].present? && options['command'].present? && options['expected_update_period_in_days'].present?
        errors.add(:base, "The path, command, and expected_update_period_in_days fields are all required.")
      end

      case options['stdin']
      when String, nil
      else
        errors.add(:base, "stdin must be a string.")
      end

      unless Array(options['command']).all? { |o| o.is_a?(String) }
        errors.add(:base, "command must be a shell command line string or an array of command line arguments.")
      end

      unless File.directory?(interpolated['path'])
        errors.add(:base, "#{options['path']} is not a real directory.")
      end
    end

    def working?
      Agents::ShellCommandAgent.should_run? && event_created_within?(interpolated['expected_update_period_in_days']) && !recent_error_logs?
    end

    def receive(incoming_events)
      incoming_events.each do |event|
        handle(interpolated(event), event)
      end
    end

    def check
      handle(interpolated)
    end

    private

    def handle(opts, event = nil)
      if Agents::ShellCommandAgent.should_run?
        command = opts['command']
        path = opts['path']
        stdin = opts['stdin']

        result, errors, exit_status = run_command(path, command, stdin, interpolated.slice(:unbundle).symbolize_keys)

        payload = {
          'command' => command,
          'path' => path,
          'exit_status' => exit_status,
          'errors' => errors,
          'output' => result,
        }

        unless suppress_event?(payload)
          created_event = create_event payload: payload
        end

        log("Ran '#{command}' under '#{path}'", outbound_event: created_event, inbound_event: event)
      else
        log("Unable to run because insecure agents are not enabled.  Edit ENABLE_INSECURE_AGENTS in the Huginn .env configuration.")
      end
    end

    def run_command(path, command, stdin, unbundle: false)
      if unbundle
        return Bundler.with_original_env {
          run_command(path, command, stdin)
        }
      end

      begin
        rout, wout = IO.pipe
        rerr, werr = IO.pipe
        rin,  win = IO.pipe

        pid = spawn(*command, chdir: path, out: wout, err: werr, in: rin)

        wout.close
        werr.close
        rin.close

        if stdin
          win.write stdin
          win.close
        end

        (result = rout.read).strip!
        (errors = rerr.read).strip!

        _, status = Process.wait2(pid)
        exit_status = status.exitstatus
      rescue => e
        errors = e.to_s
        result = ''.freeze
        exit_status = nil
      end

      [result, errors, exit_status]
    end

    def suppress_event?(payload)
      (boolify(interpolated['suppress_on_failure']) && payload['exit_status'].nonzero?) ||
        (boolify(interpolated['suppress_on_empty_output']) && payload['output'].empty?)
    end
  end
end
