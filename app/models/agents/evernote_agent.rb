module Agents
  class EvernoteAgent < Agent
    include EvernoteConcern

    description <<-MD
      Evernote代理连接用户的Evernote笔记商店

      访问Evernote以设置Evernote应用程序并获得api密钥和密钥。 将它们存储在.env文件中的Evernote环境变量中。 您还需要创建一个[沙盒](https://sandbox.evernote.com/Registration.action)帐户，以便在开发期间使用。

      接下来，您需要在“服务”部分中使用Evernote进行身份验证

      配置项:

        * `mode` - 两个可能的值：

            - `update` 根据收到的事件，代理将创建具有相同title 和notebook的注释或更新注释

            - `read`   按计划，它将生成包含新添加或更新的备注数据的事件

        * `include_xhtml_content` - 设置为true以包含注释的ENML（Evernote标记语言）中的内容

        * `note`

          - 当mode为update时，note的参数是要添加/编辑的音符的属性。 要编辑注释，必须同时设置title 和notebook 。

              例如，要将标签“漫画”和“CS”添加到笔记本“xkcd”中标题为“xkcd Survey”的注释中，请使用：

                "notes": {
                  "title": "xkcd Survey",
                  "content": "",
                  "notebook": "xkcd",
                  "tagNames": "comic, CS"
                }

              如果已经存在具有上述标题和笔记本的注释，则会创建一个注释。

          - 当mode为read时，值为搜索参数。 注意：content参数不用于搜索。 设置标题仅过滤标题包含标题作为子字符串的注释，而不是精确标题。

            例如，要在笔记本“xkcd”中查找标记为“CS”的所有笔记，请使用：

                "notes": {
                  "title": "",
                  "content": "",
                  "notebook": "xkcd",
                  "tagNames": "CS"
                }
    MD

    event_description <<-MD
      When `mode` is `update`, events look like:

          {
            "title": "...",
            "content": "...",
            "notebook": "...",
            "tags": "...",
            "source": "...",
            "sourceURL": "..."
          }

      When `mode` is `read`, events look like:

          {
            "title": "...",
            "content": "...",
            "notebook": "...",
            "tags": "...",
            "source": "...",
            "sourceURL": "...",
            "resources" : [
              {
                "url": "resource1_url",
                "name": "resource1_name",
                "mime_type": "resource1_mime_type"
              }
              ...
            ]
          }
    MD

    default_schedule "never"

    def working?
      event_created_within?(interpolated['expected_update_period_in_days']) && !recent_error_logs?
    end

    def default_options
      {
        "expected_update_period_in_days" => "2",
        "mode" => "update",
        "include_xhtml_content" => "false",
        "note" => {
          "title" => "{{title}}",
          "content" => "{{content}}",
          "notebook" => "{{notebook}}",
          "tagNames" => "{{tag1}}, {{tag2}}"
        }
      }
    end

    def validate_options
      errors.add(:base, "mode must be 'update' or 'read'") unless %w(read update).include?(options[:mode])

      if options[:mode] == "update" && schedule != "never"
        errors.add(:base, "when mode is set to 'update', schedule must be 'never'")
      end

      if options[:mode] == "read" && schedule == "never"
        errors.add(:base, "when mode is set to 'read', agent must have a schedule")
      end

      errors.add(:base, "expected_update_period_in_days is required") unless options['expected_update_period_in_days'].present?

      if options[:mode] == "update" && options[:note].values.all?(&:empty?)
        errors.add(:base, "you must specify at least one note parameter to create or update a note")
      end
    end

    def include_xhtml_content?
      options[:include_xhtml_content] == "true"
    end

    def receive(incoming_events)
      if options[:mode] == "update"
        incoming_events.each do |event|
          note = note_store.create_or_update_note(note_params(event))
          create_event :payload => note.attr(include_content: include_xhtml_content?)
        end
      end
    end

    def check
      if options[:mode] == "read"
        opts = note_params(options)

        # convert time to evernote timestamp format:
        # https://dev.evernote.com/doc/reference/Types.html#Typedef_Timestamp
        opts.merge!(agent_created_at: created_at.to_i * 1000)
        opts.merge!(last_checked_at: (memory[:last_checked_at] ||= created_at.to_i * 1000))

        if opts[:tagNames]
          opts.merge!(notes_with_tags: (memory[:notes_with_tags] ||=
            NoteStore::Search.new(note_store, {tagNames: opts[:tagNames]}).note_guids))
        end

        notes = NoteStore::Search.new(note_store, opts).notes
        notes.each do |note|
          memory[:notes_with_tags] << note.guid unless memory[:notes_with_tags].include?(note.guid)

          create_event :payload => note.attr(include_resources: true, include_content: include_xhtml_content?)
        end

        memory[:last_checked_at] = Time.now.to_i * 1000
      end
    end

    private

    def note_params(options)
      params = interpolated(options)[:note]
      errors.add(:base, "only one notebook allowed") unless params[:notebook].to_s.split(/\s*,\s*/) == 1

      params[:tagNames] = params[:tagNames].to_s.split(/\s*,\s*/)
      params[:title].strip!
      params[:notebook].strip!
      params
    end

    def evernote_note_store
      evernote_client.note_store
    end

    def note_store
      @note_store ||= NoteStore.new(evernote_note_store)
    end

    # wrapper for evernote api NoteStore
    # https://dev.evernote.com/doc/reference/
    class NoteStore
      attr_reader :en_note_store
      delegate :createNote, :updateNote, :getNote, :listNotebooks, :listTags, :getNotebook,
               :createNotebook, :findNotesMetadata, :getNoteTagNames, :to => :en_note_store

      def initialize(en_note_store)
        @en_note_store = en_note_store
      end

      def create_or_update_note(params)
        search = Search.new(self, {title: params[:title], notebook: params[:notebook]})

        # evernote search can only filter notes with titles containing a substring;
        # this finds a note with the exact title
        note = search.notes.detect {|note| note.title == params[:title]}

        if note
          # a note with specified title and notebook exists, so update it
          update_note(params.merge(guid: note.guid, notebookGuid: note.notebookGuid))
        else
          # create the notebook unless it already exists
          notebook = find_notebook(name: params[:notebook])
          notebook_guid =
            notebook ? notebook.guid : create_notebook(params[:notebook]).guid

          create_note(params.merge(notebookGuid: notebook_guid))
        end
      end

      def create_note(params)
        note = Evernote::EDAM::Type::Note.new(with_wrapped_content(params))
        en_note = createNote(note)
        find_note(en_note.guid)
      end

      def update_note(params)
        # do not empty note properties that have not been set in `params`
        params.keys.each { |key| params.delete(key) unless params[key].present? }
        params = with_wrapped_content(params)

        # append specified tags instead of replacing current tags
        # evernote will create any new tags
        tags = getNoteTagNames(params[:guid])
        tags.each { |tag|
          params[:tagNames] << tag unless params[:tagNames].include?(tag) }

        note = Evernote::EDAM::Type::Note.new(params)
        updateNote(note)
        find_note(params[:guid])
      end

      def find_note(guid)
        # https://dev.evernote.com/doc/reference/NoteStore.html#Fn_NoteStore_getNote
        en_note = getNote(guid, true, false, false, false)
        build_note(en_note)
      end

      def build_note(en_note)
        notebook = find_notebook(guid: en_note.notebookGuid).try(:name)
        tags = en_note.tagNames || find_tags(en_note.tagGuids.to_a).map(&:name)
        Note.new(en_note, notebook, tags)
      end

      def find_tags(guids)
        listTags.select {|tag| guids.include?(tag.guid)}
      end

      def find_notebook(params)
        if params[:guid]
          listNotebooks.detect {|notebook| notebook.guid == params[:guid]}
        elsif params[:name]
          listNotebooks.detect {|notebook| notebook.name == params[:name]}
        end
      end

      def create_notebook(name)
        notebook = Evernote::EDAM::Type::Notebook.new(name: name)
        createNotebook(notebook)
      end

      def with_wrapped_content(params)
        params.delete(:notebook)

        if params[:content]
          params[:content] =
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" \
            "<!DOCTYPE en-note SYSTEM \"http://xml.evernote.com/pub/enml2.dtd\">" \
            "<en-note>#{params[:content].encode(:xml => :text)}</en-note>"
        end

        params
      end

      class Search
        attr_reader :note_store, :opts
        def initialize(note_store, opts)
          @note_store = note_store
          @opts = opts
        end

        def note_guids
          filtered_metadata.map(&:guid)
        end

        def notes
          metadata = filtered_metadata

          if opts[:last_checked_at] && opts[:tagNames]

            # evernote does note change Note#updated timestamp when a tag is added to a note
            # the following selects recently updated notes
            # and notes that recently had the specified tags added
            metadata.select! do |note_data|
              note_data.updated > opts[:last_checked_at] ||
              !opts[:notes_with_tags].include?(note_data.guid)
            end

          elsif opts[:last_checked_at]
            metadata.select! { |note_data| note_data.updated > opts[:last_checked_at] }
          end

          metadata.map! { |note_data| note_store.find_note(note_data.guid) }
          metadata
        end

        def create_filter
          filter = Evernote::EDAM::NoteStore::NoteFilter.new

          # evernote search grammar:
          # https://dev.evernote.com/doc/articles/search_grammar.php#Search_Terms
          query_terms = []
          query_terms << "notebook:\"#{opts[:notebook]}\"" if opts[:notebook].present?
          query_terms << "intitle:\"#{opts[:title]}\""     if opts[:title].present?
          query_terms << "updated:day-1"                   if opts[:last_checked_at].present?
          opts[:tagNames].to_a.each { |tag| query_terms << "tag:#{tag}" }

          filter.words = query_terms.join(" ")
          filter
        end

        private

        def filtered_metadata
          filter, spec = create_filter, create_spec
          metadata = note_store.findNotesMetadata(filter, 0, 100, spec).notes
        end

        def create_spec
          Evernote::EDAM::NoteStore::NotesMetadataResultSpec.new(
            includeTitle: true,
            includeAttributes: true,
            includeNotebookGuid: true,
            includeTagGuids: true,
            includeUpdated: true,
            includeCreated: true
          )
        end
      end
    end

    class Note
      attr_accessor :en_note
      attr_reader :notebook, :tags
      delegate :guid, :notebookGuid, :title, :tagGuids, :content, :resources,
               :attributes, :to => :en_note

      def initialize(en_note, notebook, tags)
        @en_note = en_note
        @notebook = notebook
        @tags = tags
      end

      def attr(opts = {})
        return_attr = {
          title:        title,
          notebook:     notebook,
          tags:         tags,
          source:       attributes.source,
          source_url:   attributes.sourceURL
        }

        return_attr[:content] = content if opts[:include_content]

        if opts[:include_resources] && resources
          return_attr[:resources] = []
          resources.each do |resource|
            return_attr[:resources] << {
              url:       resource.attributes.sourceURL,
              name:      resource.attributes.fileName,
              mime_type: resource.mime
            }
          end
        end
        return_attr
      end
    end
  end
end
