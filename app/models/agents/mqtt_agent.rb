# encoding: utf-8 
require "json"

module Agents
  class MqttAgent < Agent
    gem_dependency_check { defined?(MQTT) }

    description <<-MD

      MQTT代理允许发布和订阅MQTT主题。

      #{'## Include `mqtt` in your Gemfile to use this Agent!' if dependencies_missing?}

      MQTT是用于机器到机器通信的通用传输协议。

      你可以这样做：

       * 发布到 [RabbitMQ](http://www.rabbitmq.com/mqtt.html)
       * 运行OwnTracks，一款适用于iOS和Android的位置跟踪工具
       * 订阅您的家庭自动化设置，如Ninjablocks或TheThingSystem

      只需选择一个主题（思考电子邮件主题行）即可发布/收听，并配置您的服务。

      您可以轻松设置自己的代理或连接到云服务

      提示：许多服务通常使用自定义证书运行mqtts（基于SSL的mqtt）。

      您需要下载其证书并在本地安装，指定certificate_path配置。


      配置示例：

      <pre><code>{
        'uri' => 'mqtts://user:pass@localhost:8883'
        'ssl' => :TLSv1,
        'ca_file' => './ca.pem',
        'cert_file' => './client.crt',
        'key_file' => './client.key',
        'topic' => 'huginn'
      }
      </code></pre>

      订阅CloCkWeRX的TheThingSystem实例（thethingsystem.com），其中发布温度和其他事件。

      <pre><code>{
        'uri' => 'mqtt://kcqlmkgx:sVNoccqwvXxE@m10.cloudmqtt.com:13858',
        'topic' => 'the_thing_system/demo'
      }
      </code></pre>

      订阅所有主题

      <pre><code>{
        'uri' => 'mqtt://kcqlmkgx:sVNoccqwvXxE@m10.cloudmqtt.com:13858',
        'topic' => '/#'
      }
      </code></pre>

      了解有关订阅通配符的更多详细信息
    MD

    event_description <<-MD
      Events are simply nested MQTT payloads. For example, an MQTT payload for Owntracks

      <pre><code>{
        "topic": "owntracks/kcqlmkgx/Dan",
        "message": {"_type": "location", "lat": "-34.8493644", "lon": "138.5218119", "tst": "1401771049", "acc": "50.0", "batt": "31", "desc": "Home", "event": "enter"},
        "time": 1401771051
      }</code></pre>
    MD

    def validate_options
      unless options['uri'].present? &&
             options['topic'].present?
        errors.add(:base, "topic and uri are required")
      end
    end

    def working?
      (event_created_within?(interpolated['expected_update_period_in_days']) && !recent_error_logs?) || received_event_without_error?
    end

    def default_options
      {
        'uri' => 'mqtts://user:pass@localhost:8883',
        'ssl' => :TLSv1,
        'ca_file'  => './ca.pem',
        'cert_file' => './client.crt',
        'key_file' => './client.key',
        'topic' => 'huginn',
        'max_read_time' => '10',
        'expected_update_period_in_days' => '2'
      }
    end

    def mqtt_client
      @client ||= MQTT::Client.new(interpolated['uri'])

      if interpolated['ssl']
        @client.ssl = interpolated['ssl'].to_sym
        @client.ca_file = interpolated['ca_file']
        @client.cert_file = interpolated['cert_file']
        @client.key_file = interpolated['key_file']
      end

      @client
    end

    def receive(incoming_events)
      mqtt_client.connect do |c|
        incoming_events.each do |event|
          c.publish(interpolated(event)['topic'], event.payload['message'])
        end
      end
    end


    def check
      last_message = memory['last_message']

      mqtt_client.connect do |c|
        begin
          Timeout.timeout((interpolated['max_read_time'].presence || 15).to_i) {
            c.get_packet(interpolated['topic']) do |packet|
              topic, payload = message = [packet.topic, packet.payload]

              # Ignore a message if it is previously received
              next if (packet.retain || packet.duplicate) && message == last_message

              last_message = message

              # A lot of services generate JSON, so try that.
              begin
                payload = JSON.parse(payload)
              rescue
              end

              create_event payload: {
                'topic' => topic,
                'message' => payload,
                'time' => Time.now.to_i
              }
            end
          }
        rescue Timeout::Error
        end
      end

      # Remember the last original (non-retain, non-duplicate) message
      self.memory['last_message'] = last_message
      save!
    end

  end
end
