module Agents
  class CommanderAgent < Agent
    include AgentControllerConcern

    cannot_create_events!

    description <<-MD
        Commander Agent由时间计划或传入的事件触发，并命令其他代理（“目标”）运行，禁用，配置或启用自身

      # 操作类型

      将`action`设置为以下某个操作类型：

      * `run`: 触发此代理时会运行目标代理.

      * `disable`:  触发此代理时，将禁用目标代理（如果未禁用)

      * `enable`: 触发此代理时，将启用目标代理（如果未启用）.

      * `configure`: 目标代理使用`configure_options`的内容更新其选项。

      这是一个提示：您可以使用 [Liquid](https://github.com/huginn/huginn/wiki/Formatting-Events-using-Liquid)模板动态确定操作类型。 例如:

      - 要创建一个CommanderAgent，每天早上从WeatherAgent接收一个事件，以启动仅在天气晴朗时才有用的代理流程，请尝试以下操作：  `{% if conditions contains 'Sunny' or conditions contains 'Cloudy' %}` `run{% endif %}`

      - 同样，如果您有为雨天特制的预定代理流程，请尝试以下方法： `{% if conditions contains 'Rain' %}enable{% else %}disabled{% endif %}`

      - 如果要基于UserLocationAgent更新WeatherAgent，可以使用'action'：'configure'并将'configure_options'设置为 `{ 'location': '{{_location_.latlng}}' }`.

      - 在模板中，您可以使用变量目标来引用每个目标代理，它具有以下属性： #{AgentDrop.instance_methods(false).map { |m| "`#{m}`" }.to_sentence}.

      # 目标

      从此CommanderAgent中选择要控制的代理.
    MD

    def working?
      true
    end

    def check
      control!
    end

    def receive(incoming_events)
      incoming_events.each do |event|
        interpolate_with(event) do
          control!
        end
      end
    end
  end
end
