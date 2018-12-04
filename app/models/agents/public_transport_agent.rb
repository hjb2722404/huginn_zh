require 'date'
require 'cgi'
module Agents
  class PublicTransportAgent < Agent
    cannot_receive_events!

    default_schedule "every_2m"

    description <<-MD
      The Public Transport Request Agent (公共传输请求代理)基于NextBus GPS传输预测生成事件

      指定以下用户设置：

      * agency (string)
      * stops (array)
      * alert_window_in_minutes (integer)

      首先，通过访问[http://www.nextbus.com/predictor/adaAgency.jsp](http://www.nextbus.com/predictor/adaAgency.jsp)并找到您的运输系统来选择代理商。 找到后，在？a =之后复制URL的一部分。 例如，对于旧金山MUNI系统，您最终会访问[http://www.nextbus.com/predictor/adaDirection.jsp?a=**sf-muni**](http://www.nextbus.com/predictor/adaDirection.jsp?a=sf-muni)并复制“sf-muni”。 将其添加到此代理的代理商设置中。
      
      接下来，找到您关心的停止标记。 

      选择目的地，然后使用n-judah路线。 链接应该是[http://www.nextbus.com/predictor/adaStop.jsp?a=sf-muni&r=N](http://www.nextbus.com/predictor/adaStop.jsp?a=sf-muni&r=N)找到后，在r =之后复制URL的一部分。

      该链接可能无法正常工作，但我们只是试图在r =之后获取该部分，因此即使它出现错误，也要继续下一步。

      要查找sf-muni系统的标签，请访问以下URL：
      [http://webservices.nextbus.com/service/publicXMLFeed?command=routeConfig&a=sf-muni&r=**N**](http://webservices.nextbus.com/service/publicXMLFeed?command=routeConfig&a=sf-muni&r=N)

      标签列为tag =“1234”。 复制该数字并在其前面添加路由，用管道“|”符号分隔。 从该页面获得一个或多个标签后，将其添加到此代理的停止列表中。 例如

          agency: "sf-muni"
          stops: ["N|5221", "N|5215"]

      请记住选择适当的停靠点，它将具有入站和出站的不同标记。

      此代理将通过请求类似于以下内容的URL生成预测：

      [http://webservices.nextbus.com/service/publicXMLFeed?command=predictionsForMultiStops&a=sf-muni&stops=N&#124;5221&stops=N&#124;5215](http://webservices.nextbus.com/service/publicXMLFeed?command=predictionsForMultiStops&a=sf-muni&stops=N&#124;5221&stops=N&#124;5215)

      最后，设置您感兴趣的到达窗口。例如，5分钟。 当新火车或公共汽车进入该时间窗口时，代理人将创建事件。

          alert_window_in_minutes: 5
    MD

    event_description <<-MD
    Events look like this:
      { "routeTitle":"N-Judah",
        "stopTag":"5215",
        "prediction":
           {"epochTime":"1389622846689",
            "seconds":"3454","minutes":"57","isDeparture":"false",
            "affectedByLayover":"true","dirTag":"N__OB4KJU","vehicle":"1489",
            "block":"9709","tripTag":"5840086"
            }
      }
    MD

    def check_url
      stop_query = URI.encode(interpolated["stops"].collect{|a| "&stops=#{a}"}.join)
      "http://webservices.nextbus.com/service/publicXMLFeed?command=predictionsForMultiStops&a=#{interpolated["agency"]}#{stop_query}"
    end

    def stops
      interpolated["stops"].collect{|a| a.split("|").last}
    end

    def check
      hydra = Typhoeus::Hydra.new
      request = Typhoeus::Request.new(check_url, :followlocation => true)
      request.on_success do |response|
        page = Nokogiri::XML response.body
        predictions = page.css("//prediction")
        predictions.each do |pr|
          parent = pr.parent.parent
          vals = {"routeTitle" => parent["routeTitle"], "stopTag" => parent["stopTag"]}
          if pr["minutes"] && pr["minutes"].to_i < interpolated["alert_window_in_minutes"].to_i
            vals = vals.merge Hash.from_xml(pr.to_xml)
            if not_already_in_memory?(vals)
              create_event(:payload => vals)
              log "creating event..."
              update_memory(vals)
            else
              log "not creating event since already in memory"
            end
          end
        end
      end
      hydra.queue request
      hydra.run
    end

    def update_memory(vals)
      add_to_memory(vals)
      cleanup_old_memory
    end

    def cleanup_old_memory
      self.memory["existing_routes"] ||= []
      self.memory["existing_routes"].reject!{|h| h["currentTime"].to_time <= (Time.now - 2.hours)}
    end

    def add_to_memory(vals)
      self.memory["existing_routes"] ||= []
      self.memory["existing_routes"] << {"stopTag" => vals["stopTag"], "tripTag" => vals["prediction"]["tripTag"], "epochTime" => vals["prediction"]["epochTime"], "currentTime" => Time.now}
    end

    def not_already_in_memory?(vals)
      m = self.memory["existing_routes"] || []
      m.select{|h| h['stopTag'] == vals["stopTag"] &&
                h['tripTag'] == vals["prediction"]["tripTag"] &&
                h['epochTime'] == vals["prediction"]["epochTime"]
              }.count == 0
    end

    def default_options
      {
        agency: "sf-muni",
        stops: ["N|5221", "N|5215"],
        alert_window_in_minutes: 5
      }
    end

    def validate_options
      errors.add(:base, 'agency is required') unless options['agency'].present?
      errors.add(:base, 'alert_window_in_minutes is required') unless options['alert_window_in_minutes'].present?
      errors.add(:base, 'stops are required') unless options['stops'].present?
    end

    def working?
      event_created_within?(2) && !recent_error_logs?
    end
  end
end
