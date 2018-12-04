require 'rufus-scheduler'

module Agents
  class SchedulerAgent < Agent
    include AgentControllerConcern

    cannot_be_scheduled!
    cannot_receive_events!
    cannot_create_events!

    @@second_precision_enabled = ENV['ENABLE_SECOND_PRECISION_SCHEDULE'] == 'true'

    cattr_reader :second_precision_enabled

    description <<-MD
      Scheduler Agent 根据用户定义的计划定期对目标代理执行操作

      # 操作类型

      将`action`设置为以下某个操作类型:

      * `run`: 目标代理每隔一段时间运行一次，但禁用的代理除外。

      * `disable`: 目标代理会每隔一段时间禁用（如果不是）。

      * `enable`: 目标代理每隔一段时间启用（如果不是）.

      #  目标

      选择要由此SchedulerAgent定期运行的代理。

      # 计划任务

      将 `schedule` 设置为cron格式的计划规范。 例如：

      * `0 22 * * 1-5`: 每周的每一天22:00（晚上10点）

      * `*/10 8-11 * * *`: 从8:00到每隔10分钟，不包括12:00

      该变体具有若干扩展，如下所述。

      ## 时区

      您可以选择使用[tz database](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones)数据库中的标签在星期几字段后指定时区（默认值：`#{Time.zone.name}`） (default: )  

      * `0 22 * * 1-5 Europe/Paris`: 每周的每一天都是在巴黎时间22:00

      * `0 22 * * 1-5 Etc/GMT+2`: 在GMT + 2（东二区）的22:00这一周的每一天

      ## 秒

      您可以选择指定分钟字段前的秒数

      * `*/30 * * * * *`: 每30秒一次

      #{" 只允许十五的倍数作为秒字段的值, 例如. `*/15`, `*/30`, `15,45` etc." unless second_precision_enabled}

      ## 一个月的最后一天

      L表示每月的“最后一天”。

      * `0 22 L * *`: 每个月的最后一天的22:00

      ## 工作日名称

      您可以在工作日字段中使用三个字母名称而不是数字。

      * `0 22 * * Sat,Sun`: 每周六和周日，22：00

      ## 本月的第N个工作日

      您可以像这样指定“当月的第n个工作日”。

      * `0 22 * * Sun#1,Sun#2`:  每个月的第一个和第二个星期日，22：00

      * `0 22 * * Sun#L1`: 每个月的最后一个星期天，22：00
    MD

    def default_options
      super.update({
        'schedule' => '0 * * * *',
      })
    end

    def working?
      true
    end

    def validate_options
      if (spec = options['schedule']).present?
        begin
          cron = Rufus::Scheduler::CronLine.new(spec)
          unless second_precision_enabled || (cron.seconds - [0, 15, 30, 45, 60]).empty?
            errors.add(:base, "second precision schedule is not allowed in this service")
          end
        rescue ArgumentError
          errors.add(:base, "invalid schedule")
        end
      else
        errors.add(:base, "schedule is missing")
      end
    end

    before_save do
      self.memory.delete('scheduled_at') if self.options_changed?
    end
  end
end
