require 'json'
require 'google/apis/calendar_v3'

module Agents
  class GoogleCalendarPublishAgent < Agent
    cannot_be_scheduled!
    no_bulk_receive!

    gem_dependency_check { defined?(Google) && defined?(Google::Apis::CalendarV3) }

    description <<-MD
      Google日历发布代理会在您的Google日历上创建活动。

      #{'## Include `google-api-client` in your Gemfile to use this Agent!' if dependencies_missing?}

      此代理依赖于服务帐户，而不是oauth。

      步骤:

      1. 访问[google api控制台](https://code.google.com/apis/console/b/0/)
      2. New project -> Huginn
      3. APIs & Auth -> Enable google calendar
      4. Credentials -> Create new Client ID -> Service Account
      5. 下载JSON密钥文件并将其保存到路径，即：`/home/huginn/Huginn-5d12345678cd.json`。 或者打开该文件并复制`private_key`
      6. 通过Google日历用户界面将访问权限授予您希望管理的每个日历的服务帐户电子邮件地址。 对于整个谷歌应用程序域，您可以[委派权限](https://developers.google.com/+/domains/authentication/delegation)

      早期版本的Huginn使用PKCS12密钥文件进行身份验证。 这将不再有效，您应该生成一个新的JSON格式密钥文件，它看起来像：
      <pre><code>{
        "type": "service_account",
        "project_id": "huginn-123123",
        "private_key_id": "6d6b476fc6ccdb31e0f171991e5528bb396ffbe4",
        "private_key": "-----BEGIN PRIVATE KEY-----\\n...\\n-----END PRIVATE KEY-----\\n",
        "client_email": "huginn-calendar@huginn-123123.iam.gserviceaccount.com",
        "client_id": "123123...123123",
        "auth_uri": "https://accounts.google.com/o/oauth2/auth",
        "token_uri": "https://accounts.google.com/o/oauth2/token",
        "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
        "client_x509_cert_url": "https://www.googleapis.com/robot/v1/metadata/x509/huginn-calendar%40huginn-123123.iam.gserviceaccount.com"
      }</code></pre>


      代理配置：

      `calendar_id` - 要发布到的日历的ID。 通常是您的Google帐户电子邮件地址。 此处允许液体格式化（例如{{cal_id}}），以便从传入事件中提取`calendar_id`。

      `google` 代理的配置选项的哈希。

      `google` `service_account_email` -  授权服务帐户电子邮件地址。

      `google` `key_file` OR `google` `key` - 上面的JSON密钥文件的路径，或密钥本身（`private_key`的值）。 如果要使用凭据，则支持[Liquid](https://github.com/huginn/huginn/wiki/Formatting-Events-using-Liquid)格式。 （例如，{％credential google_key％}）

      将expected_update_period_in_days设置为您希望在此代理创建的事件之间传递的最长时间。

      将它与触发器一起使用以塑造您的有效负载！

      事件细节的哈希。 请参阅[Google Calendar API文档](https://developers.google.com/google-apps/calendar/v3/reference/events/insert)

      之前的版本Google的API期望像`dateTime`这样的密钥，但在最新版本中，他们期望像`date_time`这样的蛇案例密钥。

      触发器代理的示例负载：
      <pre><code>{
        "message": {
          "visibility": "default",
          "summary": "Awesome event",
          "description": "An example event with text. Pro tip: DateTimes are in RFC3339",
          "start": {
            "date_time": "2017-06-30T17:00:00-05:00"
          },
          "end": {
            "date_time": "2017-06-30T18:00:00-05:00"
          }
        }
      }</code></pre>
    MD

    event_description <<-MD
      {
        'success' => true,
        'published_calendar_event' => {
           ....
        },
        'agent_id' => 1234,
        'event_id' => 3432
      }
    MD

    def validate_options
      errors.add(:base, "expected_update_period_in_days is required") unless options['expected_update_period_in_days'].present?
    end

    def working?
      event_created_within?(options['expected_update_period_in_days']) && most_recent_event && most_recent_event.payload['success'] == true && !recent_error_logs?
    end

    def default_options
      {
        'expected_update_period_in_days' => "10",
        'calendar_id' => 'you@email.com',
        'google' => {
          'key_file' => '/path/to/private.key',
          'key' => '-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n',
          'service_account_email' => ''
        }
      }
    end

    def receive(incoming_events)
      require 'google_calendar'
      incoming_events.each do |event|
        GoogleCalendar.open(interpolate_options(options, event), Rails.logger) do |calendar|

          cal_message = event.payload["message"]
          if cal_message["start"].present? && cal_message["start"]["dateTime"].present? && !cal_message["start"]["date_time"].present?
            cal_message["start"]["date_time"] = cal_message["start"].delete "dateTime"
          end
          if cal_message["end"].present? && cal_message["end"]["dateTime"].present? && !cal_message["end"]["date_time"].present?
            cal_message["end"]["date_time"] = cal_message["end"].delete "dateTime"
          end

          calendar_event = calendar.publish_as(
                interpolated(event)['calendar_id'],
                cal_message
              )

          create_event :payload => {
            'success' => true,
            'published_calendar_event' => calendar_event,
            'agent_id' => event.agent_id,
            'event_id' => event.id
          }
        end
      end
    end
  end
end

