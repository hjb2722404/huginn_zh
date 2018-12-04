module Agents
  class DropboxFileUrlAgent < Agent
    include DropboxConcern

    cannot_be_scheduled!
    no_bulk_receive!
    can_dry_run!

    description <<-MD
      DropboxFileUrlAgent用于使用Dropbox。 它采用文件路径（或多个文件路径）并使用临时链接或永久链接发出事件。

      #{'## Include the `dropbox-api` and `omniauth-dropbox` gems in your `Gemfile` and set `DROPBOX_OAUTH_KEY` and `DROPBOX_OAUTH_SECRET` in your environment to use Dropbox Agents.' if dependencies_missing?}

      传入的事件有效负载需要有一个路径密钥，以及您想要URL的逗号分隔的文件列表。 例如：

          {
            "paths": "first/path, second/path"
          }

      提示：您可以使用事件格式代理在事件进入之前对事件进行格式化。以下是格式化Dropbox Watch Agent事件的示例配置：

          {
            "instructions": {
              "paths": "{{ added | map: 'path' | join: ',' }}"
            },
            "matchers": [],
            "mode": "clean"
          }

      使用的一个示例是观察特定的Dropbox目录（使用DropboxWatchAgent）并获取添加或更新的文件的URL。 例如，您可以使用这些链接发送电子邮件

      如果你想要临时链接，可以将link_type设置为'temporary'，或者为永久链接设置为'permanent'。

    MD

    event_description do
      "Events will looks like this:\n\n    %s" % if options['link_type'] == 'permanent'
        Utils.pretty_print({
          url: "https://www.dropbox.com/s/abcde3/example?dl=1",
          :".tag" => "file",
          id: "id:abcde3",
          name: "hi",
          path_lower: "/huginn/hi",
          link_permissions:          {
            resolved_visibility: {:".tag"=>"public"},
            requested_visibility: {:".tag"=>"public"},
            can_revoke: true
          },
          client_modified: "2017-10-14T18:38:39Z",
          server_modified: "2017-10-14T18:38:45Z",
          rev: "31db0615354b",
          size: 0
        })
      else
        Utils.pretty_print({
          url: "https://dl.dropboxusercontent.com/apitl/1/somelongurl",
          metadata: {
            name: "hi",
            path_lower: "/huginn/hi",
            path_display: "/huginn/hi",
            id: "id:abcde3",
            client_modified: "2017-10-14T18:38:39Z",
            server_modified: "2017-10-14T18:38:45Z",
            rev: "31db0615354b",
            size: 0,
            content_hash: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
          }
        })
      end
    end

    def default_options
      {
        'link_type' => 'temporary'
      }
    end

    def working?
      !recent_error_logs?
    end

    def receive(events)
      events.flat_map { |e| e.payload['paths'].split(',').map(&:strip) }
        .each do |path|
          create_event payload: (options['link_type'] == 'permanent' ? permanent_url_for(path) : temporary_url_for(path))
        end
    end

    private

    def temporary_url_for(path)
      dropbox.find(path).direct_url.response.tap do |response|
        response['url'] = response.delete('link')
      end
    end

    def permanent_url_for(path)
      dropbox.find(path).share_url.response.tap do |response|
        response['url'].gsub!('?dl=0','?dl=1')
      end
    end

  end

end
