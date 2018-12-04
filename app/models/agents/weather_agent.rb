require 'date'
require 'cgi'

module Agents
  class WeatherAgent < Agent
    cannot_receive_events!

    gem_dependency_check { defined?(Wunderground) && defined?(ForecastIO) }

    description <<-MD
      Weather Agent会在指定位置为当天的天气创建一个事件

      #{'## Include `forecast_io` and `wunderground` in your Gemfile to use this Agent!' if dependencies_missing?}

      您还必须选择何时获取使用`which_day`选项的天气预报，其中数字`1`代表今天，`2`代表明天，依此类推。 天气预报信息每次最多只返回一周

      天气预报信息可以由Wunderground或Dark Sky提供。 要选择要使用的服务，请输入`darksky`或`wunderground`。

       `location` 应该是：

      * 对于Wunderground：美国邮政编码，或Wunderground支持的任何位置。 要找到一个，请搜索wunderground.com并复制URL的位置部分。 例如，旧金山的结果为https://www.wunderground.com/US/CA/San_Francisco.html和英国伦敦提供https://www.wunderground.com/q/zmw:00000.1.03772。 每个中的位置分别是US / CA / San_Francisco和zmw：00000.1.03772。
      * 对于黑暗天空：位置必须是以逗号分隔的地图坐标字符串（经度，纬度）。 例如，旧金山将是37.7771，-122.4196

      您必须为Wunderground设置API密钥才能将此代理与Wunderground一起使用。

      您必须为Dark Sky设置API密钥才能将此代理与Dark Sky一起使用

      将`expected_update_period_in_days`设置为您希望在此代理创建的事件之间传递的最长时间。

      如果要查看以您的语言返回的文本，请以ISO 639-1格式设置语言参数。
    MD

    event_description <<-MD
      Events look like this:

          {
            "location": "12345",
            "date": {
              "epoch": "1357959600",
              "pretty": "10:00 PM EST on January 11, 2013"
            },
            "high": {
              "fahrenheit": "64",
              "celsius": "18"
            },
            "low": {
              "fahrenheit": "52",
              "celsius": "11"
            },
            "conditions": "Rain Showers",
            "icon": "rain",
            "icon_url": "https://icons-ak.wxug.com/i/c/k/rain.gif",
            "skyicon": "mostlycloudy",
            ...
          }
    MD

    default_schedule "8pm"

    def working?
      event_created_within?((interpolated['expected_update_period_in_days'].presence || 2).to_i) && !recent_error_logs? && key_setup?
    end

    def key_setup?
      interpolated['api_key'].present? && interpolated['api_key'] != "your-key" && interpolated['api_key'] != "put-your-key-here"
    end

    def default_options
      {
        'service' => 'wunderground',
        'api_key' => 'your-key',
        'location' => '94103',
        'which_day' => '1',
        'language' => 'EN',
        'expected_update_period_in_days' => '2'
      }
    end

    def check
      if key_setup?
        create_event :payload => model(weather_provider, which_day).merge('location' => location)
      end
    end

    private

    def weather_provider
      interpolated["service"].presence || "wunderground"
    end

    # a check to see if the weather provider is wunderground.
    def wunderground?
      weather_provider.downcase == "wunderground"
    end

    # a check to see if the weather provider is one of the valid aliases for Dark Sky.
    def dark_sky?
      ["dark_sky", "darksky", "forecast_io", "forecastio"].include? weather_provider.downcase
    end

    def which_day
      (interpolated["which_day"].presence || 1).to_i
    end

    def location
      interpolated["location"].presence || interpolated["zipcode"]
    end

    def coordinates
      location.split(',').map { |e| e.to_f }
    end

    def language
      interpolated['language'].presence || 'EN'
    end

    VALID_COORDS_REGEX = /^\s*-?\d{1,3}\.\d+\s*,\s*-?\d{1,3}\.\d+\s*$/

    def validate_location
      errors.add(:base, "location is required") unless location.present?
      return if wunderground?
      if location.match? VALID_COORDS_REGEX
        lat, lon = coordinates
        errors.add :base, "too low of a latitude" unless lat > -90
        errors.add :base, "too big of a latitude" unless lat < 90
        errors.add :base, "too low of a longitude" unless lon > -180
        errors.add :base, "too high of a longitude" unless lon < 180
      else
        errors.add(
          :base,
          "Location #{location} is malformed. Location for " +
          'Dark Sky must be in the format "-00.000,-00.00000". The ' +
          "number of decimal places does not matter.")
      end
    end

    def validate_options
      errors.add(:base, "service must be set to 'darksky' or 'wunderground'") unless wunderground? || dark_sky?
      validate_location
      errors.add(:base, "api_key is required") unless interpolated['api_key'].present?
      errors.add(:base, "which_day selection is required") unless which_day.present?
    end

    def wunderground
      if key_setup?
        forecast = Wunderground.new(interpolated['api_key'], language: language.upcase).forecast_for(location)
        merged = {}
        forecast['forecast']['simpleforecast']['forecastday'].each { |daily| merged[daily['period']] = daily }
        forecast['forecast']['txt_forecast']['forecastday'].each { |daily| (merged[daily['period']] || {}).merge!(daily) }
        merged
      end
    end

    def dark_sky
      if key_setup?
        ForecastIO.api_key = interpolated['api_key']
        lat, lng = coordinates
        ForecastIO.forecast(lat, lng, params: {lang: language.downcase})['daily']['data']
      end
    end

    def model(weather_provider,which_day)
      if wunderground?
        wunderground[which_day]
      elsif dark_sky?
        dark_sky.each do |value|
          timestamp = Time.at(value.time)
          if (timestamp.to_date - Time.now.to_date).to_i == which_day
            day = {
              'date' => {
                'epoch' => value.time.to_s,
                'pretty' => timestamp.strftime("%l:%M %p %Z on %B %d, %Y"),
                'day' => timestamp.day,
                'month' => timestamp.month,
                'year' => timestamp.year,
                'yday' => timestamp.yday,
                'hour' => timestamp.hour,
                'min' => timestamp.strftime("%M"),
                'sec' => timestamp.sec,
                'isdst' => timestamp.isdst ? 1 : 0 ,
                'monthname' => timestamp.strftime("%B"),
                'monthname_short' => timestamp.strftime("%b"),
                'weekday_short' => timestamp.strftime("%a"),
                'weekday' => timestamp.strftime("%A"),
                'ampm' => timestamp.strftime("%p"),
                'tz_short' => timestamp.zone
              },
              'period' => which_day.to_i,
              'high' => {
                'fahrenheit' => value.temperatureMax.round().to_s,
                'epoch' => value.temperatureMaxTime.to_s,
                'fahrenheit_apparent' => value.apparentTemperatureMax.round().to_s,
                'epoch_apparent' => value.apparentTemperatureMaxTime.to_s,
                'celsius' => ((5*(Float(value.temperatureMax) - 32))/9).round().to_s
              },
              'low' => {
                'fahrenheit' => value.temperatureMin.round().to_s,
                'epoch' => value.temperatureMinTime.to_s,
                'fahrenheit_apparent' => value.apparentTemperatureMin.round().to_s,
                'epoch_apparent' => value.apparentTemperatureMinTime.to_s,
                'celsius' => ((5*(Float(value.temperatureMin) - 32))/9).round().to_s
              },
              'conditions' => value.summary,
              'icon' => value.icon,
              'avehumidity' => (value.humidity * 100).to_i,
              'sunriseTime' => value.sunriseTime.to_s,
              'sunsetTime' => value.sunsetTime.to_s,
              'moonPhase' => value.moonPhase.to_s,
              'precip' => {
                'intensity' => value.precipIntensity.to_s,
                'intensity_max' => value.precipIntensityMax.to_s,
                'intensity_max_epoch' => value.precipIntensityMaxTime.to_s,
                'probability' => value.precipProbability.to_s,
                'type' => value.precipType
              },
              'dewPoint' => value.dewPoint.to_s,
              'avewind' => {
                'mph' => value.windSpeed.round().to_s,
                'kph' =>  (Float(value.windSpeed) * 1.609344).round().to_s,
                'degrees' => value.windBearing.to_s
              },
              'visibility' => value.visibility.to_s,
              'cloudCover' => value.cloudCover.to_s,
              'pressure' => value.pressure.to_s,
              'ozone' => value.ozone.to_s
            }
            return day
          end
        end
      end
    end
  end
end
