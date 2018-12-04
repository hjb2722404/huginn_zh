module Agents
  class AdiosoAgent < Agent
    cannot_receive_events!

  	default_schedule "every_1d"

    description <<-MD
    Adioso Agent会告诉您一对城市之间以及在一段时间内的最低航空公司价格.

    货币是美元。 请确保`start_date`和`end_date`之间的差异小于150天。 您需要联系Adioso以获取用户名和密码。
    MD

    event_description <<-MD
      If flights are present then events look like:

          {
            "cost": 75.23,
            "date": "June 25, 2013",
  			    "route": "New York to Chicago"
          }

      otherwise
    
          {
            "nonetodest": "No flights found to the specified destination"
          }
    MD

    def default_options
      {
        'start_date' => Date.today.httpdate[0..15],
        'end_date'   => Date.today.plus_with_duration(100).httpdate[0..15],
        'from'       => "New York",
        'to'         => "Chicago",
        'username'   => "xx",
        'password'   => "xx",
				'expected_update_period_in_days' => "1"
      }
    end

    def working?
      event_created_within?(options['expected_update_period_in_days']) && !recent_error_logs?
    end

    def validate_options
			unless %w[start_date end_date from to username password expected_update_period_in_days].all? { |field| options[field].present? }
				errors.add(:base, "All fields are required")
			end
		end

    def date_to_unix_epoch(date)
      date.to_time.to_i
    end

    def check
      auth_options = {:basic_auth => {:username =>interpolated[:username], :password=>interpolated['password']}}
      parse_response = HTTParty.get "http://api.adioso.com/v2/search/parse?q=#{URI.encode(interpolated['from'])}+to+#{URI.encode(interpolated['to'])}", auth_options
      fare_request = parse_response["search_url"].gsub /(end=)(\d*)([^\d]*)(\d*)/, "\\1#{date_to_unix_epoch(interpolated['end_date'])}\\3#{date_to_unix_epoch(interpolated['start_date'])}"
      fare = HTTParty.get fare_request, auth_options

			if fare["warnings"]
				create_event :payload => fare["warnings"]
			else
				event = fare["results"].min {|a,b| a["cost"] <=> b["cost"]}
				event["date"]  = Time.at(event["date"]).to_date.httpdate[0..15]
				event["route"] = "#{interpolated['from']} to #{interpolated['to']}"
				create_event :payload => event
			end
    end
  end
end

