require 'base64'
require 'delegate'
require 'net/imap'
require 'mail'

module Agents
  class ImapFolderAgent < Agent
    cannot_receive_events!

    can_dry_run!

    default_schedule "every_30m"

    description <<-MD
      Imap文件夹代理检查指定文件夹中的IMAP服务器，并根据自上次运行后找到的新邮件创建事件。 在第一次访问文件夹时，此代理仅检查初始状态，但不创建事件。

      指定要与主机连接的IMAP服务器，如果服务器支持基于SSL的IMAP，则将ssl设置为true。 如果需要连接到标准以外的端口（143或993，具体取决于ssl值），请指定端口。

      在用户名和密码中指定登录凭据

      列出要在文件夹中签入的文件夹的名称。

      要按条件缩小邮件，请使用以下键构建条件哈希：

      - `subject`
      - `body`
          指定正则表达式以匹配每个邮件的已解码主题/正文

          使用（？i）指令进行不区分大小写的搜索。 例如，模式（？i）警报将匹配“警报”，“警报”或“警报”。 您还可以仅使模式的一部分不区分大小写：Re：（？i：alert）将匹配“Re：Alert”或“Re：alert”，但不匹配“RE：alert”。

          当邮件具有多个非附件文本部分时，根据mime_types选项（见下文）对它们进行优先级排序，并且匹配“body”模式的第一部分（如果指定）将被选为a中的“body”值。 创造了事件。

          命名捕获将出现在已创建事件的“匹配”哈希中。

      - `from`, `to`, `cc`
          指定一个shell glob模式字符串，该字符串与从每个邮件的相应标头值中提取的邮件地址匹配。

          模式以不区分大小写的方式匹配地址

          可以在数组中指定多个模式字符串，在这种情况下，如果任何模式匹配，则选择邮件。 （即模式是OR'd）

      - `mime_types`
          指定一个MIME类型数组，以告知邮件中哪个非附件部分的文本/ *部分应该用作邮件正文。 默认值为['text / plain'，'text / enriched'，'text / html']。

      - `is_unread`
          将此设置为true或false表示仅选择分别标记为未读或已读的邮件。

          如果未指定此键或将其设置为null，则忽略该键。

      - `has_attachment`
      
          将此设置为true或false表示仅选择具有或不具有附件的邮件。 

          如果未指定此键或将其设置为null，则忽略该键.

      将mark_as_read设置为true以将找到的邮件标记为已读

      将include_raw_mail设置为true可将raw_mail值添加到每个已创建的事件，该事件包含IM644标准中定义的“RFC822”格式的Base64编码blob。 请注意，虽然Base64编码的结果将以LF终止，但由于电子邮件协议和格式的性质，其原始内容通常将以CRLF终止。 原始邮件blob的主要用例是使用openssl enc -d -base64 |等命令传递给Shell Command Agent。 tr -d''| procmail -Yf-。

      每个代理程序实例都会记住在每个监视文件夹的上次运行中找到的邮件的最高UID，因此即使您更改了一组条件以使其与先前错过的邮件匹配，或者您更改了已找到的标记状态 邮件，它们不会显示为新事件。

      此外，为了避免重复通知，它会保留100个最近邮件的Message-Id列表，因此如果找到多个相同Message-Id的邮件，您将只看到其中一个事件。
    MD

    event_description <<-MD
      Events look like this:

          {
            "message_id": "...(Message-Id without angle brackets)...",
            "folder": "INBOX",
            "subject": "...",
            "from": "Nanashi <nanashi.gombeh@example.jp>",
            "to": ["Jane <jane.doe@example.com>"],
            "cc": [],
            "date": "2014-05-10T03:47:20+0900",
            "mime_type": "text/plain",
            "body": "Hello,\n\n...",
            "matches": {
            }
          }

      Additionally, "raw_mail" will be included if the `include_raw_mail` option is set.
    MD

    IDCACHE_SIZE = 100

    FNM_FLAGS = [:FNM_CASEFOLD, :FNM_EXTGLOB].inject(0) { |flags, sym|
      if File.const_defined?(sym)
        flags | File.const_get(sym)
      else
        flags
      end
    }

    def working?
      event_created_within?(interpolated['expected_update_period_in_days']) && !recent_error_logs?
    end

    def default_options
      {
        'expected_update_period_in_days' => "1",
        'host' => 'imap.gmail.com',
        'ssl' => true,
        'username' => 'your.account',
        'password' => 'your.password',
        'folders' => %w[INBOX],
        'conditions' => {}
      }
    end

    def validate_options
      %w[host username password].each { |key|
        String === options[key] or
          errors.add(:base, '%s is required and must be a string' % key)
      }

      if options['port'].present?
        errors.add(:base, "port must be a positive integer") unless is_positive_integer?(options['port'])
      end

      %w[ssl mark_as_read include_raw_mail].each { |key|
        if options[key].present?
          if boolify(options[key]).nil?
            errors.add(:base, '%s must be a boolean value' % key)
          end
        end
      }

      case mime_types = options['mime_types']
      when nil
      when Array
        mime_types.all? { |mime_type|
          String === mime_type && mime_type.start_with?('text/')
        } or errors.add(:base, 'mime_types may only contain strings that match "text/*".')
        if mime_types.empty?
          errors.add(:base, 'mime_types should not be empty')
        end
      else
        errors.add(:base, 'mime_types must be an array')
      end

      case folders = options['folders']
      when nil
      when Array
        folders.all? { |folder|
          String === folder
        } or errors.add(:base, 'folders may only contain strings')
        if folders.empty?
          errors.add(:base, 'folders should not be empty')
        end
      else
        errors.add(:base, 'folders must be an array')
      end

      case conditions = options['conditions']
      when Hash
        conditions.each { |key, value|
          value.present? or next
          case key
          when 'subject', 'body'
            case value
            when String
              begin
                Regexp.new(value)
              rescue
                errors.add(:base, 'conditions.%s contains an invalid regexp' % key)
              end
            else
              errors.add(:base, 'conditions.%s contains a non-string object' % key)
            end
          when 'from', 'to', 'cc'
            Array(value).each { |pattern|
              case pattern
              when String
                begin
                  glob_match?(pattern, '')
                rescue
                  errors.add(:base, 'conditions.%s contains an invalid glob pattern' % key)
                end
              else
                errors.add(:base, 'conditions.%s contains a non-string object' % key)
              end
            }
          when 'is_unread', 'has_attachment'
            case boolify(value)
            when true, false
            else
              errors.add(:base, 'conditions.%s must be a boolean value or null' % key)
            end
          end
        }
      else
        errors.add(:base, 'conditions must be a hash')
      end

      if options['expected_update_period_in_days'].present?
        errors.add(:base, "Invalid expected_update_period_in_days format") unless is_positive_integer?(options['expected_update_period_in_days'])
      end
    end

    def check
      each_unread_mail { |mail, notified|
        message_id = mail.message_id
        body_parts = mail.body_parts(mime_types)
        matched_part = nil
        matches = {}

        interpolated['conditions'].all? { |key, value|
          case key
          when 'subject'
            value.present? or next true
            re = Regexp.new(value)
            if m = re.match(mail.scrubbed(:subject))
              m.names.each { |name|
                matches[name] = m[name]
              }
              true
            else
              false
            end
          when 'body'
            value.present? or next true
            re = Regexp.new(value)
            matched_part = body_parts.find { |part|
               if m = re.match(part.scrubbed(:decoded))
                 m.names.each { |name|
                   matches[name] = m[name]
                 }
                 true
               else
                 false
               end
            }
          when 'from', 'to', 'cc'
            value.present? or next true
            begin
              # Mail::Field really needs to define respond_to_missing?
              # so we could use try(:addresses) here.
              addresses = mail.header[key].addresses
            rescue NoMethodError
              next false
            end
            addresses.any? { |address|
              Array(value).any? { |pattern|
                glob_match?(pattern, address)
              }
            }
          when 'has_attachment'
            boolify(value) == mail.has_attachment?
          when 'is_unread'
            true  # already filtered out by each_unread_mail
          else
            log 'Unknown condition key ignored: %s' % key
            true
          end
        } or next

        if notified.include?(mail.message_id)
          log 'Ignoring mail: %s (already notified)' % message_id
        else
          matched_part ||= body_parts.first

          if matched_part
            mime_type = matched_part.mime_type
            body = matched_part.scrubbed(:decoded)
          else
            mime_type = 'text/plain'
            body = ''
          end

          log 'Emitting an event for mail: %s' % message_id

          payload = {
            'message_id' => message_id,
            'folder' => mail.folder,
            'subject' => mail.scrubbed(:subject),
            'from' => mail.from_addrs.first,
            'to' => mail.to_addrs,
            'cc' => mail.cc_addrs,
            'date' => (mail.date.iso8601 rescue nil),
            'mime_type' => mime_type,
            'body' => body,
            'matches' => matches,
            'has_attachment' => mail.has_attachment?,
          }

          if boolify(interpolated['include_raw_mail'])
            payload['raw_mail'] = Base64.encode64(mail.raw_mail)
          end

          create_event payload: payload

          notified << mail.message_id if mail.message_id
        end

        if boolify(interpolated['mark_as_read'])
          log 'Marking as read'
          mail.mark_as_read unless dry_run?
        end
      }
    end

    def each_unread_mail
      host, port, ssl, username = interpolated.values_at(:host, :port, :ssl, :username)
      ssl = boolify(ssl)
      port = (Integer(port) if port.present?)

      log "Connecting to #{host}#{':%d' % port if port}#{' via SSL' if ssl}"
      Client.open(host, port: port, ssl: ssl) { |imap|
        log "Logging in as #{username}"
        imap.login(username, interpolated[:password])

        # 'lastseen' keeps a hash of { uidvalidity => lastseenuid, ... }
        lastseen, seen = self.lastseen, self.make_seen

        # 'notified' keeps an array of message-ids of {IDCACHE_SIZE}
        # most recent notified mails.
        notified = self.notified

        interpolated['folders'].each { |folder|
          log "Selecting the folder: %s" % folder

          imap.select(Net::IMAP.encode_utf7(folder))
          uidvalidity = imap.uidvalidity

          lastseenuid = lastseen[uidvalidity]

          if lastseenuid.nil?
            maxseq = imap.responses['EXISTS'].last

            log "Recording the initial status: %s" % pluralize(maxseq, 'existing mail')

            if maxseq > 0
              seen[uidvalidity] = imap.fetch(maxseq, 'UID').last.attr['UID']
            end

            next
          end

          seen[uidvalidity] = lastseenuid
          is_unread = boolify(interpolated['conditions']['is_unread'])

          uids = imap.uid_fetch((lastseenuid + 1)..-1, 'FLAGS').
                 each_with_object([]) { |data, ret|
            uid, flags = data.attr.values_at('UID', 'FLAGS')
            seen[uidvalidity] = uid
            next if uid <= lastseenuid

            case is_unread
            when nil, !flags.include?(:Seen)
              ret << uid
            end
          }

          log pluralize(uids.size,
                        case is_unread
                        when true
                          'new unread mail'
                        when false
                          'new read mail'
                        else
                          'new mail'
                        end)

          next if uids.empty?

          imap.uid_fetch_mails(uids).each { |mail|
            yield mail, notified
          }
        }

        self.notified = notified
        self.lastseen = seen

        save!
      }
    ensure
      log 'Connection closed'
    end

    def mime_types
      interpolated['mime_types'] || %w[text/plain text/enriched text/html]
    end

    def lastseen
      Seen.new(memory['lastseen'])
    end

    def lastseen= value
      memory.delete('seen')  # obsolete key
      memory['lastseen'] = value
    end

    def make_seen
      Seen.new
    end

    def notified
      Notified.new(memory['notified'])
    end

    def notified= value
      memory['notified'] = value
    end

    private

    def glob_match?(pattern, value)
      File.fnmatch?(pattern, value, FNM_FLAGS)
    end

    def pluralize(count, noun)
      "%d %s" % [count, noun.pluralize(count)]
    end

    class Client < ::Net::IMAP
      class << self
        def open(host, *args)
          imap = new(host, *args)
          yield imap
        ensure
          imap.disconnect unless imap.nil?
        end
      end

      attr_reader :uidvalidity

      def select(folder)
        ret = super(@folder = folder)
        @uidvalidity = responses['UIDVALIDITY'].last
        ret
      end

      def fetch(*args)
        super || []
      end

      def uid_fetch(*args)
        super || []
      end

      def uid_fetch_mails(set)
        uid_fetch(set, 'RFC822.HEADER').map { |data|
          Message.new(self, data, folder: @folder, uidvalidity: @uidvalidity)
        }
      end
    end

    class Seen < Hash
      def initialize(hash = nil)
        super()
        if hash
          # Deserialize a JSON hash which keys are strings
          hash.each { |uidvalidity, uid|
            self[uidvalidity.to_i] = uid
          }
        end
      end

      def []=(uidvalidity, uid)
        # Update only if the new value is larger than the current value
        if (curr = self[uidvalidity]).nil? || curr <= uid
          super
        end
      end
    end

    class Notified < Array
      def initialize(array = nil)
        super()
        replace(array) if array
      end

      def <<(value)
        slice!(0...-IDCACHE_SIZE) if size > IDCACHE_SIZE
        super
      end
    end

    class Message < SimpleDelegator
      DEFAULT_BODY_MIME_TYPES = %w[text/plain text/enriched text/html]

      attr_reader :uid, :folder, :uidvalidity

      module Scrubbed
        def scrubbed(method)
          (@scrubbed ||= {})[method.to_sym] ||=
            __send__(method).try(:scrub) { |bytes| "<#{bytes.unpack('H*')[0]}>" }
        end
      end

      include Scrubbed

      def initialize(client, fetch_data, props = {})
        @client = client
        props.each { |key, value|
          instance_variable_set(:"@#{key}", value)
        }
        attr = fetch_data.attr
        @uid = attr['UID']
        super(Mail.read_from_string(attr['RFC822.HEADER']))
      end

      def has_attachment?
        @has_attachment ||=
          if data = @client.uid_fetch(@uid, 'BODYSTRUCTURE').first
            struct_has_attachment?(data.attr['BODYSTRUCTURE'])
          else
            false
          end
      end

      def raw_mail
        @raw_mail ||=
          if data = @client.uid_fetch(@uid, 'BODY.PEEK[]').first
            data.attr['BODY[]']
          else
            ''
          end
      end

      def fetch
        @parsed ||= Mail.read_from_string(raw_mail)
      end

      def body_parts(mime_types = DEFAULT_BODY_MIME_TYPES)
        mail = fetch
        if mail.multipart?
          mail.body.set_sort_order(mime_types)
          mail.body.sort_parts!
          mail.all_parts
        else
          [mail]
        end.select { |part|
          if part.multipart? || part.attachment? || !part.text? ||
             !mime_types.include?(part.mime_type)
            false
          else
            part.extend(Scrubbed)
            true
          end
        }
      end

      def mark_as_read
        @client.uid_store(@uid, '+FLAGS', [:Seen])
      end

      private

      def struct_has_attachment?(struct)
        struct.multipart? && (
          struct.subtype == 'MIXED' ||
          struct.parts.any? { |part|
            struct_has_attachment?(part)
          }
        )
      end
    end
  end
end
