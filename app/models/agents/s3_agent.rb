module Agents
  class S3Agent < Agent
    include FormConfigurable
    include FileHandling

    emits_file_pointer!
    no_bulk_receive!

    default_schedule 'every_1h'

    gem_dependency_check { defined?(Aws::S3) }

    description do
      <<-MD
        S3Agent可以监视存储桶的更改，也可以为该存储桶中的每个文件发出事件。 接收事件时，它会将数据写入S3上的文件。

        #{'## Include `aws-sdk-core` in your Gemfile to use this Agent!' if dependencies_missing?}

        `mode` 必须存在且为`read `(读取)或`write`（写入），在读取模式下，代理会检查S3存储桶中是否有已更改的文件，写入时会将接收到的事件写入存储桶中的文件

        ### 通用选项

        要使用access_key和access_key_secret的证书，请使用liquid credential标记，如{％credential name-of-credential％}

        选择创建存储区的`region `(区域)。

        ### 读取

        当watch设置为true时，S3Agent将监视指定的存储桶以进行更改。 每次检测到的更改都会发出一个事件。

        当watch设置为false时，代理将在每个已运行的运行中为存储桶中的每个文件发出一个事件。

        #{emitting_file_handling_agent_description}

        ### 写入

        指定要在`filename`中使用的文件名，可以使用液体插值更改每个事件的名称。

        在`data`中使用Liquid模板来指定应写入接收事件的哪个部分。
      MD
    end

    event_description do
      "Events will looks like this:\n\n    %s" % if boolify(interpolated['watch'])
        Utils.pretty_print({
          "file_pointer" => {
            "file" => "filename",
            "agent_id" => id
          },
          "event_type" => "modified/added/removed"
        })
      else
        Utils.pretty_print({
          "file_pointer" => {
            "file" => "filename",
            "agent_id" => id
          }
        })
      end
    end

    def default_options
      {
        'mode' => 'read',
        'access_key_id' => '',
        'access_key_secret' => '',
        'watch' => 'true',
        'bucket' => "",
        'data' => '{{ data }}'
      }
    end

    form_configurable :mode, type: :array, values: %w(read write)
    form_configurable :access_key_id, roles: :validatable
    form_configurable :access_key_secret, roles: :validatable
    form_configurable :region, type: :array, values: %w(us-east-1 us-west-1 us-west-2 eu-west-1 eu-central-1 ap-southeast-1 ap-southeast-2 ap-northeast-1 ap-northeast-2 sa-east-1)
    form_configurable :watch, type: :array, values: %w(true false)
    form_configurable :bucket, roles: :completable
    form_configurable :filename
    form_configurable :data

    def validate_options
      if options['mode'].blank? || !['read', 'write'].include?(options['mode'])
        errors.add(:base, "The 'mode' option is required and must be set to 'read' or 'write'")
      end
      if options['bucket'].blank?
        errors.add(:base, "The 'bucket' option is required.")
      end
      if options['region'].blank?
        errors.add(:base, "The 'region' option is required.")
      end

      case interpolated['mode']
      when 'read'
        if options['watch'].blank? || ![true, false].include?(boolify(options['watch']))
          errors.add(:base, "The 'watch' option is required and must be set to 'true' or 'false'")
        end
      when 'write'
        if options['filename'].blank?
          errors.add(:base, "filename must be specified in 'write' mode")
        end
        if options['data'].blank?
          errors.add(:base, "data must be specified in 'write' mode")
        end
      end
    end

    def validate_access_key_id
      !!buckets
    end

    def validate_access_key_secret
      !!buckets
    end

    def complete_bucket
      (buckets || []).collect { |room| {text: room.name, id: room.name} }
    end

    def working?
      checked_without_error?
    end

    def check
      return if interpolated['mode'] != 'read'
      contents = safely do
                   get_bucket_contents
                 end
      if boolify(interpolated['watch'])
        watch(contents)
      else
        contents.each do |key, _|
          create_event payload: get_file_pointer(key)
        end
      end
    end

    def get_io(file)
      client.get_object(bucket: interpolated['bucket'], key: file).body
    end

    def receive(incoming_events)
      return if interpolated['mode'] != 'write'
      incoming_events.each do |event|
        safely do
          mo = interpolated(event)
          client.put_object(bucket: mo['bucket'], key: mo['filename'], body: mo['data'])
        end
      end
    end

    private

    def safely
      yield
    rescue Aws::S3::Errors::AccessDenied => e
      error("Could not access '#{interpolated['bucket']}' #{e.class} #{e.message}")
    rescue Aws::S3::Errors::ServiceError =>e
      error("#{e.class}: #{e.message}")
    end

    def watch(contents)
      if last_check_at.nil?
        self.memory['seen_contents'] = contents
        return
      end

      new_memory = contents.dup

      memory['seen_contents'].each do |key, etag|
        if contents[key].blank?
          create_event payload: get_file_pointer(key).merge(event_type: :removed)
        elsif contents[key] != etag
          create_event payload: get_file_pointer(key).merge(event_type: :modified)
        end
        contents.delete(key)
      end
      contents.each do |key, etag|
        create_event payload: get_file_pointer(key).merge(event_type: :added)
      end

      self.memory['seen_contents'] = new_memory
    end

    def get_bucket_contents
      contents = {}
      client.list_objects(bucket: interpolated['bucket']).each do |response|
        response.contents.each do |file|
          contents[file.key] = file.etag
        end
      end
      contents
    end

    def client
      @client ||= Aws::S3::Client.new(credentials: Aws::Credentials.new(interpolated['access_key_id'], interpolated['access_key_secret']),
                                      region: interpolated['region'])
    end

    def buckets(log = false)
      @buckets ||= client.list_buckets.buckets
    rescue Aws::S3::Errors::ServiceError => e
      false
    end
  end
end
