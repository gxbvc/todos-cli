# frozen_string_literal: true

module Todos
  # Commands for the todo.gxb.vc API routes added after plan 54 (Nov 2026): project and area details,
  # covers, project files, project and area chat, archive, invite resend and revoke, notifications,
  # read marks, search, the why text, contexts, inbox proposals, auto-approve reads, organization reads,
  # and the to-do verbs (act, log). The routes and their rules are in https://api.todo.gxb.vc/openapi.json.
  class CLI
    private

    # ---- projects ------------------------------------------------------------------------------

    # PATCH /projects/:id.json: emoji, done_when (500 characters at most) and manager_agent (GXB staff
    # only; the server ignores anyone else's value with a warning). "" clears a field. The owner or admin.
    def projects_update
      id = numeric_id!("project id")
      options = parse_options(@args, emoji: true, done_when: true, manager_agent: true)
      ensure_no_args!
      project = {}
      project[:emoji] = blank_to_nil(options[:emoji]) if options.key?(:emoji)
      project[:done_when] = blank_to_nil(options[:done_when]) if options.key?(:done_when)
      project[:manager_agent] = blank_to_nil(options[:manager_agent]) if options.key?(:manager_agent)
      raise Error.new("Pass --emoji, --done-when, or --manager-agent", code: "INVALID_ARGUMENT") if project.empty?

      note_warnings(request(:patch, "/projects/#{id}.json", body: { project: project }))
    end

    # POST (archive) or DELETE (restore) /projects/:id/archive.json. The server's own rule: confirm the
    # project and its id with the person first. --confirm says that was done.
    def projects_archive(restore: false)
      id = numeric_id!("project id")
      options = parse_options(@args, confirm: true)
      ensure_no_args!
      verb = restore ? "restore" : "archive"
      unless options[:confirm]
        raise Error.new("projects #{verb} changes every member's board. Confirm the project and its id with the person, then pass --confirm", code: "CONFIRM_REQUIRED")
      end

      request(restore ? :delete : :post, "/projects/#{id}/archive.json")
    end

    def projects_cover_remove
      id = numeric_id!("project id")
      ensure_no_args!
      request(:delete, "/projects/#{id}/cover.json")
    end

    def projects_files
      id = numeric_id!("project id")
      ensure_no_args!
      request(:get, "/projects/#{id}/files.json")
    end

    # POST /projects/:id/files.json, multipart files[]: up to 10 per call, 100 MB each. Owner or admin.
    def projects_upload
      id = numeric_id!("project id")
      paths = []
      paths << File.expand_path(@args.shift) until @args.empty?
      raise Error.new("Give 1 to 10 file paths", code: "INVALID_ARGUMENT") unless paths.size.between?(1, 10)

      paths.each do |path|
        raise Error.new("File not found: #{path}", code: "INVALID_ARGUMENT") unless File.file?(path)
        raise Error.new("File is over 100 MB: #{path}", code: "INVALID_ARGUMENT") if File.size(path) > 100 * 1024 * 1024
      end
      ios = paths.map { |path| File.open(path, "rb") }
      begin
        form = ios.zip(paths).map { |io, path| [ "files[]", io, { filename: File.basename(path) } ] }
        @client.request(:post, "/projects/#{id}/files.json", form: form)
      ensure
        ios.each(&:close)
      end
    end

    # GET /projects/:id/files/:file_id.json: { url, expires_at, byte_size, content_type }, a short-lived link.
    def projects_file_url
      id = numeric_id!("project id")
      file_id = numeric_id!("file id")
      ensure_no_args!
      request(:get, "/projects/#{id}/files/#{file_id}.json")
    end

    def projects_file_delete
      id = numeric_id!("project id")
      file_id = numeric_id!("file id")
      ensure_no_args!
      request(:delete, "/projects/#{id}/files/#{file_id}.json")
    end

    # PATCH (resend: a new link, the old one stops working) or DELETE (revoke) a project invite.
    def projects_invite_member(method)
      id = numeric_id!("project id")
      invite_id = numeric_id!("invite id")
      ensure_no_args!
      request(method, "/projects/#{id}/invites/#{invite_id}.json")
    end

    # ---- areas ---------------------------------------------------------------------------------

    # PATCH /areas/:id.json: standard (the line under the title, 500 characters at most) and emoji.
    # "" clears. The area owner or admin. Moving an area between organizations is browser-only.
    def areas_update
      id = numeric_id!("area id")
      options = parse_options(@args, emoji: true, standard: true)
      ensure_no_args!
      area = {}
      area[:emoji] = blank_to_nil(options[:emoji]) if options.key?(:emoji)
      area[:standard] = blank_to_nil(options[:standard]) if options.key?(:standard)
      raise Error.new("Pass --emoji or --standard", code: "INVALID_ARGUMENT") if area.empty?

      request(:patch, "/areas/#{id}.json", body: { area: area })
    end

    def areas_cover
      id = numeric_id!("area id")
      path = File.expand_path(required_positional!("image path"))
      ensure_no_args!
      upload_cover("/areas/#{id}/cover.json", path)
    end

    def areas_cover_remove
      id = numeric_id!("area id")
      ensure_no_args!
      request(:delete, "/areas/#{id}/cover.json")
    end

    # One image, 10 MB at most; a second upload replaces it. Shared by areas and projects.
    def upload_cover(path_on_server, path)
      raise Error.new("File not found: #{path}", code: "INVALID_ARGUMENT") unless File.file?(path)
      raise Error.new("Cover is over 10 MB", code: "INVALID_ARGUMENT") if File.size(path) > 10 * 1024 * 1024

      type = COVER_TYPES[File.extname(path).downcase]
      raise Error.new("Cover must be .jpg, .png, .webp or .gif", code: "INVALID_ARGUMENT") unless type

      File.open(path, "rb") do |io|
        @client.request(:post, path_on_server, form: [ [ "image", io, { filename: File.basename(path), content_type: type } ] ])
      end
    end

    # ---- the chat on a project or an area (plan 59 section 6) ----------------------------------

    def chat_messages(parent)
      id = numeric_id!("#{parent} id")
      options = parse_options(@args, cursor: true, limit: true, order: true)
      ensure_no_args!
      if options.key?(:order) && !%w[asc desc].include?(options[:order])
        raise Error.new("--order must be asc or desc", code: "INVALID_ARGUMENT")
      end

      @client.request(:get, "/#{parent}s/#{id}/messages.json", query: options.slice(:cursor, :limit, :order))
    end

    def chat_post(parent)
      id = numeric_id!("#{parent} id")
      options = parse_options(@args, as: true)
      body = inline_or_file_text(@args.shift.to_s, "Message")
      ensure_no_args!
      raise Error.new("Message text is required", code: "INVALID_ARGUMENT") if body.strip.empty?

      payload = { body: body }
      payload[:agent_name] = options[:as] if options.key?(:as)
      request(:post, "/#{parent}s/#{id}/messages.json", body: payload)
    end

    def chat_delete(parent)
      id = numeric_id!("#{parent} id")
      message_id = numeric_id!("message id")
      ensure_no_args!
      request(:delete, "/#{parent}s/#{id}/messages/#{message_id}.json")
    end

    # ---- contexts ------------------------------------------------------------------------------

    # My GTD contexts (plan 42). Without a subcommand: the list, as before.
    def contexts
      subcommand = @args.shift
      case subcommand
      when nil, "list"
        ensure_no_args!
        request(:get, "/contexts.json")["contexts"]
      when "create" then contexts_create
      when "update" then contexts_update
      when "delete"
        id = numeric_id!("context id")
        ensure_no_args!
        request(:delete, "/contexts/#{id}.json")
      when "move" then contexts_move
      else
        fail_usage!("Usage: todos-cli contexts [list|create|update|delete|move]")
      end
    end

    def contexts_create
      name = required_positional!("context name")
      options = parse_options(@args, description: true)
      ensure_no_args!
      body = { name: name }
      body[:description] = options[:description] if options.key?(:description)
      request(:post, "/contexts.json", body: body)
    end

    def contexts_update
      id = numeric_id!("context id")
      options = parse_options(@args, name: true, description: true)
      ensure_no_args!
      body = options.slice(:name, :description)
      raise Error.new("Pass --name or --description", code: "INVALID_ARGUMENT") if body.empty?

      request(:patch, "/contexts/#{id}.json", body: body)
    end

    def contexts_move
      id = numeric_id!("context id")
      direction = required_positional!("direction (up or down)")
      ensure_no_args!
      raise Error.new("Direction must be up or down", code: "INVALID_ARGUMENT") unless %w[up down].include?(direction)

      request(:patch, "/contexts/#{id}/move.json", body: { direction: direction })
    end

    # ---- notifications and read marks ----------------------------------------------------------

    def notifications
      subcommand = @args.shift
      case subcommand
      when "list"
        options = parse_options(@args, cursor: true, limit: true)
        ensure_no_args!
        @client.request(:get, "/notifications.json", query: options.slice(:cursor, :limit))
      when "show"
        id = numeric_id!("notification id")
        ensure_no_args!
        request(:get, "/notifications/#{id}.json")
      when "read"
        id = numeric_id!("notification id")
        options = parse_options(@args, unread: true)
        ensure_no_args!
        request(:patch, "/notifications/#{id}.json", body: { read: !options[:unread] })
      when "read-all"
        options = parse_options(@args, project: true, area: true)
        ensure_no_args!
        request(:post, "/notification_reads.json", body: scope_body(options))
      else
        fail_usage!("Usage: todos-cli notifications <list|show|read|read-all>")
      end
    end

    # POST /task_reads.json for one to-do: read through its newest comment, or --through-comment ID.
    def tasks_read
      id = numeric_id!("task id")
      options = parse_options(@args, through_comment: true)
      ensure_no_args!
      body = { task_id: id.to_i }
      body[:through_comment_id] = options[:through_comment] if options.key?(:through_comment)
      request(:post, "/task_reads.json", body: body)
    end

    # POST /task_reads.json for every unread to-do in one project or area (500 per call at most).
    def tasks_read_all
      options = parse_options(@args, project: true, area: true)
      ensure_no_args!
      body = scope_body(options)
      raise Error.new("Pass --project ID or --area ID", code: "INVALID_ARGUMENT") if body.empty?

      request(:post, "/task_reads.json", body: body)
    end

    # { project_id } or { area_id }, never both.
    def scope_body(options)
      raise Error.new("Pass --project or --area, not both", code: "INVALID_ARGUMENT") if options.key?(:project) && options.key?(:area)

      body = {}
      body[:project_id] = Integer(options[:project], exception: false) || raise(Error.new("--project must be numeric", code: "INVALID_ARGUMENT")) if options.key?(:project)
      body[:area_id] = Integer(options[:area], exception: false) || raise(Error.new("--area must be numeric", code: "INVALID_ARGUMENT")) if options.key?(:area)
      body
    end

    # ---- to-do verbs ---------------------------------------------------------------------------

    ACT_VERBS = %w[done approve request_changes decline choose send undo got_it accept send_back unblock].freeze

    # POST /tasks/:id/act.json: one of the verbs in the to-do's actions list (tasks get shows them).
    def tasks_act
      id = numeric_id!("task id")
      verb = required_positional!("verb")
      options = parse_options(@args, option: true, note: true, fields: true)
      ensure_no_args!
      raise Error.new("Verb must be one of: #{ACT_VERBS.join(", ")}", code: "INVALID_ARGUMENT") unless ACT_VERBS.include?(verb)

      body = { verb: verb }
      chosen = Array(options[:options])
      raise Error.new("Pass --option once", code: "INVALID_ARGUMENT") if chosen.size > 1

      body[:option] = chosen.first if chosen.any?
      body[:note] = options[:note] if options.key?(:note)
      body[:response] = parse_fields(options[:fields]) if options[:fields]
      request(:post, "/tasks/#{id}/act.json", body: body)
    end

    def tasks_log
      id = numeric_id!("task id")
      ensure_no_args!
      request(:patch, "/tasks/#{id}/log.json")
    end

    def tasks_log_all
      ensure_no_args!
      request(:patch, "/tasks/log_all.json")
    end

    # GET /lists.json?ids=: any to-dos by id, in that order; ids I cannot open are skipped.
    def tasks_lookup
      ids = required_positional!("task ids (comma list)").split(",").map(&:strip).reject(&:empty?)
      ensure_no_args!
      raise Error.new("Task ids must be numeric", code: "INVALID_ARGUMENT") unless ids.any? && ids.all? { |v| v.match?(/\A\d+\z/) }

      @client.request(:get, "/lists.json", query: { ids: ids.join(",") })
    end

    # ---- search, why, inbox proposals, auto-approve, organizations -----------------------------

    SEARCH_SORTS = %w[priority created_at updated_at].freeze

    def search
      query = @args.shift.to_s
      options = parse_options(@args, sort: true, direction: true, cursor: true, limit: true)
      ensure_no_args!
      raise Error.new("Search words are required", code: "INVALID_ARGUMENT") if query.strip.empty?
      if options.key?(:sort) && !SEARCH_SORTS.include?(options[:sort])
        raise Error.new("--sort must be one of: #{SEARCH_SORTS.join(", ")}", code: "INVALID_ARGUMENT")
      end
      if options.key?(:direction) && !%w[asc desc].include?(options[:direction])
        raise Error.new("--direction must be asc or desc", code: "INVALID_ARGUMENT")
      end

      @client.request(:get, "/search.json", query: { q: query }.merge(options.slice(:sort, :direction, :cursor, :limit)))
    end

    # My own why text (plan 53), 2,000 characters at most. `why` shows it, `why set TEXT|@file`
    # saves it, `why clear` clears it.
    def why
      subcommand = @args.shift
      case subcommand
      when nil, "show"
        ensure_no_args!
        request(:get, "/why.json")
      when "set"
        text = inline_or_file_text(required_positional!("text"), "Why text")
        ensure_no_args!
        request(:patch, "/why.json", body: { why: text })
      when "clear"
        ensure_no_args!
        request(:patch, "/why.json", body: { why: nil })
      else
        fail_usage!("Usage: todos-cli why [show|set TEXT|@file|clear]")
      end
    end

    def inbox_proposals
      id = inbox_id!
      options = parse_options(@args, cursor: true, limit: true)
      ensure_no_args!
      @client.request(:get, "/inbox_threads/#{id}/proposals.json", query: options.slice(:cursor, :limit))
    end

    # Reads only: rules are a person's decision, made on todo.gxb.vc.
    def auto_approve
      subcommand = @args.shift
      case subcommand
      when "list"
        options = parse_options(@args, cursor: true, limit: true)
        ensure_no_args!
        @client.request(:get, "/auto_approve_rules.json", query: options.slice(:cursor, :limit))
      when "entries"
        rule_id = @args.first&.match?(/\A\d+\z/) ? @args.shift : nil
        options = parse_options(@args, cursor: true, limit: true)
        ensure_no_args!
        path = rule_id ? "/auto_approve_rules/#{rule_id}/entries.json" : "/auto_approve_entries.json"
        @client.request(:get, path, query: options.slice(:cursor, :limit))
      else
        fail_usage!("Usage: todos-cli auto-approve <list|entries [RULE_ID]>")
      end
    end

    # Reads only: organization writes need a browser session on todo.gxb.vc.
    def organizations
      subcommand = @args.shift
      case subcommand
      when "list"
        ensure_no_args!
        request(:get, "/organizations.json")
      when "show"
        id = numeric_id!("organization id")
        ensure_no_args!
        request(:get, "/organizations/#{id}.json")
      when "members"
        id = numeric_id!("organization id")
        ensure_no_args!
        request(:get, "/organizations/#{id}/members.json")
      else
        fail_usage!("Usage: todos-cli orgs <list|show|members>")
      end
    end

    # ---- helpers -------------------------------------------------------------------------------

    def numeric_id!(name)
      id = required_positional!(name)
      raise Error.new("#{name.capitalize} must be numeric", code: "INVALID_ARGUMENT") unless id.match?(/\A\d+\z/)

      id
    end

    def blank_to_nil(value)
      value.to_s.strip.empty? ? nil : value
    end

    # The server's warnings (a non-staff manager_agent), on stderr.
    def note_warnings(result)
      Array(result.is_a?(Hash) ? result["warnings"] : nil).each { |warning| @err.puts("Warning: #{warning}") }
      result
    end
  end
end
