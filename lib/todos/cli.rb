# frozen_string_literal: true

require "json"
require "optparse"
require "uri"

require "todos/client"
require "todos/error"

module Todos
  class CLI
    STATUSES = %w[open submitted approved canceled].freeze
    PROJECT_STATUSES = %w[active waiting someday completed].freeze
    USAGE = <<~TEXT.freeze
      Usage:
        todos-cli me
        todos-cli users list
        todos-cli users show <id|email>
        todos-cli users remind <id|email>
        todos-cli board [--user <id|email>]
        todos-cli areas list --user <id|email>
        todos-cli areas create --user <id|email> -t TITLE [--position N] [--active true|false]
        todos-cli projects list --user <id|email>
        todos-cli projects create -t TITLE [--area ID]
        todos-cli projects create --user <id|email> -t TITLE [--area ID] [--status STATUS] [--position N]
        todos-cli projects invite <id> --email EMAIL
        todos-cli invites list
        todos-cli invites accept <id> [--area ID]
        todos-cli tasks list [--user <id|email>] [--project ID] [--status STATUS]
        todos-cli tasks get|show <id> [--user <id|email>]
        todos-cli tasks check -t TITLE [--description HTML] [--schema JSON|@file]
        todos-cli tasks create -t TITLE --project ID [--assignee EMAIL] [--description HTML] [--due DATE] [--schema JSON|@file] [--star]
        todos-cli tasks create --user <id|email> -t TITLE [--project ID] [--description HTML] [--due DATE] [--estimate N] [--source-url URL] [--schema JSON|@file] [--star]
        todos-cli tasks update <id> --user <id|email> [--title TITLE] [--project ID] [--description HTML] [--due DATE] [--estimate N] [--source-url URL] [--schema JSON|@file] [--field key=value] [--notes TEXT]
        todos-cli tasks destroy <id> --user <id|email>
        todos-cli tasks submit <id> [--user <id|email>] [--field key=value]
        todos-cli tasks approve <id> [--user <id|email>]
        todos-cli tasks send-back <id> --note TEXT
        todos-cli tasks star <id> [--off] [--user <id|email>]
        todos-cli tasks reopen <id> [--user <id|email>] [--note TEXT]
        todos-cli tasks cancel <id> [--user <id|email>]
        todos-cli tasks remind <id> --user <id|email>
        todos-cli tasks respond <id> [--user <id|email>] --field key=value [--field key=value] [--notes TEXT]

      Every task must be a next physical action.
      Rules and examples: write-human-todos skill.
      The server scores every task on 7 checks; create, get, and check print them on stderr.
    TEXT

    def self.run(args, client: Client.new, out: $stdout, err: $stderr)
      data = new(args, client: client, err: err).execute
      out.puts(JSON.generate(ok: true, data: data))
      0
    rescue Todos::Error => e
      err.puts(e.message)
      envelope = { ok: false, error: e.message, code: e.code }
      # A create or edit the quality gate refused: say which checks failed and
      # how to fix each one, and keep the whole object for agents.
      quality = e.details && e.details["quality"]
      if quality.is_a?(Hash)
        print_quality(err, quality)
        envelope[:quality] = quality
      end
      out.puts(JSON.generate(envelope))
      1
    rescue StandardError => e
      message = "Unexpected error: #{e.message}"
      err.puts(message)
      out.puts(JSON.generate(ok: false, error: message, code: "INTERNAL_ERROR"))
      1
    end

    # The server's quality breakdown, for people: the score, then each check,
    # with the hint on each fail.
    def self.print_quality(err, quality)
      if quality["score"].nil?
        err.puts("Quality: not scored yet")
        return
      end

      verdict = quality["passed"] ? "passed" : "failed"
      err.puts("Quality #{quality["score"]} (weakest: #{quality["weakest"]}), #{verdict}")
      Array(quality["checks"]).each do |check|
        mark = check["passed"] ? "pass" : "FAIL"
        blocks = check["blocking"] ? "" : " (does not block)"
        line = "  #{mark}  #{check["id"]}#{blocks}: #{check["score"]}"
        line += ". #{check["hint"]}" unless check["passed"]
        err.puts(line)
      end
    end

    def initialize(args, client:, err: $stderr)
      @args = args.dup
      @client = client
      @err = err
      @users = nil
    end

    def execute
      command = @args.shift
      case command
      when "me" then me
      when "users" then users
      when "board" then board
      when "areas" then areas
      when "projects" then projects
      when "tasks" then tasks
      when "invites" then invites
      when "help", "-h", "--help", nil then { usage: USAGE }
      else
        fail_usage!("Unknown command: #{command}")
      end
    end

    private

    def me
      ensure_no_args!
      payload = request(:get, "/tasks.json")
      user = payload.is_a?(Hash) && payload["user"]
      raise Error.new("Board response did not include user", code: "INVALID_RESPONSE") unless user

      user
    end

    def users
      subcommand = @args.shift
      case subcommand
      when "list"
        ensure_no_args!
        users_list
      when "show"
        reference = required_positional!("id or email")
        ensure_no_args!
        request(:get, "/users/#{resolve_user(reference)}.json")
      when "remind"
        reference = required_positional!("id or email")
        ensure_no_args!
        request(:post, "/users/#{resolve_user(reference)}/remind.json")
      else
        fail_usage!("Usage: todos-cli users list|show|remind")
      end
    end

    def board
      options = parse_options(@args, user: true)
      ensure_no_args!
      board_for(options[:user]).tap { |payload| note_open_invites(payload) }
    end

    def areas
      subcommand = @args.shift
      case subcommand
      when "list" then areas_list
      when "create" then areas_create
      else
        fail_usage!("Usage: todos-cli areas <list|create>")
      end
    end

    def areas_list
      options = parse_options(@args, user: true)
      ensure_no_args!
      user_id = require_user!(options[:user])
      flatten_areas(board_for(user_id))
    end

    def areas_create
      options = parse_options(@args, user: true, title: true, position: true, active: true)
      ensure_no_args!
      user_id = require_user!(options[:user])
      title = required_option!(options[:title], "--title/-t")
      area = { title: title }
      area[:position] = options[:position] if options.key?(:position)
      area[:active] = options[:active] if options.key?(:active)
      request(:post, "/users/#{user_id}/areas.json", body: { area: area })
    end

    def projects
      subcommand = @args.shift
      case subcommand
      when "list" then projects_list
      when "create" then projects_create
      when "invite" then projects_invite
      else
        fail_usage!("Usage: todos-cli projects <list|create|invite>")
      end
    end

    def projects_list
      options = parse_options(@args, user: true)
      ensure_no_args!
      user_id = require_user!(options[:user])
      flatten_projects(board_for(user_id))
    end

    # Two routes. With --user: the admin's create on that person's board.
    # Without it: my own project (POST /projects.json), in one of my areas
    # (--area), and I own it.
    def projects_create
      options = parse_options(@args, user: true, title: true, area: true, status: true, position: true)
      ensure_no_args!
      title = required_option!(options[:title], "--title/-t")
      unless options[:user]
        if options.key?(:status) || options.key?(:position)
          raise Error.new("--status and --position need --user (admin create)", code: "INVALID_ARGUMENT")
        end

        # Without --user it is my own project, not a client's: say so, in
        # case --user was forgotten.
        @err.puts("No --user: making the project in your own board.")
        project = { title: title }
        project[:area_id] = options[:area] if options.key?(:area)
        return request(:post, "/projects.json", body: { project: project })
      end

      user_id = require_user!(options[:user])
      if options[:status] && !PROJECT_STATUSES.include?(options[:status])
        raise Error.new("Status must be one of: #{PROJECT_STATUSES.join(", ")}", code: "INVALID_ARGUMENT")
      end

      project = { title: title }
      project[:area_id] = options[:area] if options.key?(:area)
      project[:status] = options[:status] if options.key?(:status)
      project[:position] = options[:position] if options.key?(:position)
      request(:post, "/users/#{user_id}/projects.json", body: { project: project })
    end

    # Email someone a link to join a project I own. data.status is invited or
    # already_member; a refusal (not the owner, bad email, rate limit) exits 1
    # with the server's reason.
    def projects_invite
      id = required_positional!("project id")
      options = parse_options(@args, email: true)
      ensure_no_args!
      email = required_option!(options[:email], "--email")
      request(:post, "/projects/#{id}/invites.json", body: { email: email })
    end

    # Project invites sent to my own email (GET /invites.json). An invited
    # project is not on my board until I accept.
    def invites
      subcommand = @args.shift
      case subcommand
      when "list"
        ensure_no_args!
        request(:get, "/invites.json")["invites"]
      when "accept" then invites_accept
      else
        fail_usage!("Usage: todos-cli invites <list|accept>")
      end
    end

    # Join the project, filed in one of my areas (--area) or my Shared area.
    # data is the project as projects.json shows it. Any invite I cannot
    # accept (not mine, expired, revoked, used) is the same NOT_FOUND.
    def invites_accept
      id = required_positional!("invite id")
      options = parse_options(@args, area: true)
      ensure_no_args!
      unless id.match?(/\A[a-z]+-\d+\z/)
        raise Error.new("Invite id looks like project-4 (from todos-cli invites list)", code: "INVALID_ARGUMENT")
      end

      body = {}
      body[:area_id] = options[:area] if options.key?(:area)
      request(:post, "/invites/#{id}/accept.json", body: body)
    end

    # The board carries my open invite count. Say it on stderr so an agent
    # reading only data still sees it.
    def note_open_invites(payload)
      count = payload.is_a?(Hash) ? payload["open_invites"] : nil
      return unless count.is_a?(Integer) && count.positive?

      noun = count == 1 ? "invite" : "invites"
      @err.puts("You have #{count} open #{noun}. Run: todos-cli invites list")
    end

    def tasks
      subcommand = @args.shift
      case subcommand
      when "list" then tasks_list
      when "get", "show" then tasks_get
      when "check" then tasks_check
      when "create" then tasks_create
      when "update" then tasks_update
      when "destroy" then tasks_destroy
      when "approve" then tasks_approve
      when "send-back" then tasks_send_back
      when "star" then tasks_star
      when "submit" then tasks_submit
      when "reopen" then tasks_reopen
      when "cancel" then tasks_cancel
      when "remind" then tasks_remind
      when "respond" then tasks_respond
      else
        fail_usage!("Usage: todos-cli tasks <list|get|show|check|create|update|destroy|approve|send-back|star|submit|reopen|cancel|remind|respond>")
      end
    end

    def tasks_list
      options = parse_options(@args, user: true, project: true, status: true)
      ensure_no_args!
      if options[:status] && !STATUSES.include?(options[:status])
        raise Error.new("Status must be one of: #{STATUSES.join(", ")}", code: "INVALID_ARGUMENT")
      end

      payload = board_for(options[:user])
      note_open_invites(payload)
      tasks = flatten_tasks(payload)
      tasks.select! { |task| task["project_id"].to_s == options[:project].to_s } if options[:project]
      tasks.select! { |task| task["status"] == options[:status] } if options[:status]
      tasks
    end

    def tasks_get
      id = required_positional!("task id")
      parse_options(@args, user: true)
      ensure_no_args!
      with_quality(request(:get, "/tasks/#{id}.json"))
    end

    # Score a draft without saving it (POST /quality_checks.json). Exits 0
    # either way; data.quality.passed says whether every check passed.
    def tasks_check
      options = parse_options(@args, title: true, description: true, schema: true)
      ensure_no_args!
      body = { title: required_option!(options[:title], "--title/-t") }
      body[:description] = options[:description] if options.key?(:description)
      body[:fields_schema] = parse_schema(options[:schema]) if options.key?(:schema)
      result = request(:post, "/quality_checks.json", body: body)
      self.class.print_quality(@err, result["quality"]) if result.is_a?(Hash) && result["quality"].is_a?(Hash)
      result
    end

    # Two routes. With --user: the admin's nested create on that person's
    # board. Without it: the member create (POST /tasks.json) in one of my
    # projects, for me or for --assignee, an active member of that project.
    # The server scores it; a refusal (422) prints the failed checks.
    def tasks_create
      options = parse_options(
        @args,
        user: true, title: true, project: true, assignee: true, description: true, due: true, estimate: true,
        source_url: true, schema: true, star: true
      )
      ensure_no_args!
      title = required_option!(options[:title], "--title/-t")
      task = { title: title }
      task[:project_id] = options[:project] if options.key?(:project)
      task[:description] = options[:description] if options.key?(:description)
      task[:due_date] = options[:due] if options.key?(:due)
      task[:fields_schema] = parse_schema(options[:schema]) if options.key?(:schema)
      task[:starred] = true if options[:star]

      if options[:user]
        if options.key?(:assignee)
          raise Error.new("--assignee is for the member route; --user already names who does it", code: "INVALID_ARGUMENT")
        end
        task[:estimated_minutes] = options[:estimate] if options.key?(:estimate)
        task[:source_url] = options[:source_url] if options.key?(:source_url)
        return with_quality(request(:post, "/users/#{resolve_user(options[:user])}/tasks.json", body: { task: task }))
      end

      if options.key?(:estimate) || options.key?(:source_url)
        raise Error.new("--estimate and --source-url need --user (admin create)", code: "INVALID_ARGUMENT")
      end
      # A forgotten --user must fail, not land a client's to-do on my board.
      unless options.key?(:project)
        raise Error.new("Pass --user EMAIL for someone's board, or --project ID (and --assignee EMAIL) for a shared project", code: "INVALID_ARGUMENT")
      end
      task[:assignee_email] = options[:assignee] if options.key?(:assignee)
      with_quality(request(:post, "/tasks.json", body: { task: task }))
    end

    def tasks_update
      id = required_positional!("task id")
      options = parse_options(
        @args,
        user: true, title: true, project: true, description: true, due: true,
        estimate: true, source_url: true, schema: true, fields: true, notes: true
      )
      ensure_no_args!
      user_id = require_user!(options[:user])

      task = {}
      task[:title] = options[:title] if options.key?(:title)
      task[:project_id] = options[:project] if options.key?(:project)
      task[:description] = options[:description] if options.key?(:description)
      task[:due_date] = options[:due] if options.key?(:due)
      task[:estimated_minutes] = options[:estimate] if options.key?(:estimate)
      task[:source_url] = options[:source_url] if options.key?(:source_url)
      task[:fields_schema] = parse_schema(options[:schema]) if options.key?(:schema)

      body = {}
      body[:task] = task unless task.empty?
      body[:response] = parse_fields(options[:fields]) if options[:fields]&.any?
      body[:notes] = options[:notes] if options.key?(:notes)
      raise Error.new("Nothing to update", code: "INVALID_ARGUMENT") if body.empty?

      request(:patch, "/users/#{user_id}/tasks/#{id}.json", body: body)
    end

    def tasks_destroy
      id = required_positional!("task id")
      options = parse_options(@args, user: true)
      ensure_no_args!
      request(:delete, "/users/#{require_user!(options[:user])}/tasks/#{id}.json")
    end

    # Without --user: the reviewer's route (a to-do I asked for). With it:
    # the admin's nested route.
    def tasks_approve
      id = required_positional!("task id")
      options = parse_options(@args, user: true)
      ensure_no_args!
      return request(:patch, "/tasks/#{id}/approve.json") unless options[:user]

      request(:patch, "/users/#{resolve_user(options[:user])}/tasks/#{id}/approve.json")
    end

    # The reviewer sends a checked-off to-do back with a note (mailed to the
    # assignee). The admin's nested equivalent is reopen --user --note.
    def tasks_send_back
      id = required_positional!("task id")
      options = parse_options(@args, note: true)
      ensure_no_args!
      note = required_option!(options[:note].to_s.strip, "--note")
      request(:patch, "/tasks/#{id}/send_back.json", body: { note: note })
    end

    # Star (or --off to unstar): the assignee or the reviewer; the admin with
    # --user.
    def tasks_star
      id = required_positional!("task id")
      options = parse_options(@args, user: true, off: true)
      ensure_no_args!
      body = { starred: !options[:off] }
      return request(:patch, "/tasks/#{id}/star.json", body: body) unless options[:user]

      request(:patch, "/users/#{resolve_user(options[:user])}/tasks/#{id}/star.json", body: body)
    end

    def tasks_submit
      id = required_positional!("task id")
      options = parse_options(@args, user: true, fields: true)
      ensure_no_args!
      if options[:user]
        if options[:fields]&.any?
          raise Error.new("--field is only supported for self submit; use tasks update before admin submit", code: "INVALID_ARGUMENT")
        end
        user_id = resolve_user(options[:user])
        request(:patch, "/users/#{user_id}/tasks/#{id}/submit.json")
      else
        body = options[:fields]&.any? ? { response: parse_fields(options[:fields]) } : nil
        request(:patch, "/tasks/#{id}/submit.json", body: body)
      end
    end

    def tasks_reopen
      id = required_positional!("task id")
      options = parse_options(@args, user: true, note: true)
      ensure_no_args!
      if options[:user]
        body = options.key?(:note) ? { note: options[:note] } : nil
        request(:patch, "/users/#{resolve_user(options[:user])}/tasks/#{id}/reopen.json", body: body)
      else
        if options.key?(:note)
          raise Error.new("--note requires --user because self reopen is silent", code: "INVALID_ARGUMENT")
        end
        request(:patch, "/tasks/#{id}/reopen.json")
      end
    end

    def tasks_cancel
      id = required_positional!("task id")
      options = parse_options(@args, user: true)
      ensure_no_args!
      path = if options[:user]
               "/users/#{resolve_user(options[:user])}/tasks/#{id}/cancel.json"
             else
               "/tasks/#{id}/cancel.json"
             end
      request(:patch, path)
    end

    # Admin-only, like approve/destroy: re-sends TaskMailer#reminder for one
    # to-do without touching its status or assignment state.
    def tasks_remind
      id = required_positional!("task id")
      options = parse_options(@args, user: true)
      ensure_no_args!
      request(:post, "/users/#{require_user!(options[:user])}/tasks/#{id}/remind.json")
    end

    def tasks_respond
      id = required_positional!("task id")
      options = parse_options(@args, user: true, fields: true, notes: true)
      ensure_no_args!
      body = {}
      body[:response] = parse_fields(options[:fields]) if options[:fields]&.any?
      body[:notes] = options[:notes] if options.key?(:notes)
      raise Error.new("Pass at least one --field or --notes", code: "INVALID_ARGUMENT") if body.empty?

      path = if options[:user]
               "/users/#{resolve_user(options[:user])}/tasks/#{id}.json"
             else
               "/tasks/#{id}.json"
             end
      request(:patch, path, body: body)
    end

    def users_list
      payload = request(:get, "/users.json")
      list = payload.is_a?(Hash) ? payload["users"] : payload
      unless list.is_a?(Array)
        raise Error.new("Users response did not include a users array", code: "INVALID_RESPONSE")
      end

      list
    end

    def resolve_user(reference)
      reference = reference.to_s
      return reference unless reference.include?("@")

      @users ||= users_list
      user = @users.find { |candidate| candidate["email"].to_s.casecmp?(reference) }
      raise Error.new("User not found: #{reference}", code: "USER_NOT_FOUND") unless user

      user.fetch("id")
    end

    def require_user!(reference)
      raise Error.new("--user <id|email> is required", code: "USER_REQUIRED") if reference.to_s.empty?

      resolve_user(reference)
    end

    def board_for(user)
      return request(:get, "/tasks.json") unless user

      request(:get, "/users/#{resolve_user(user)}.json")
    end

    def flatten_areas(payload)
      areas = payload.is_a?(Hash) ? payload["areas"] : nil
      raise Error.new("Board response did not include areas", code: "INVALID_RESPONSE") unless areas.is_a?(Array)

      areas.map do |area|
        {
          "id" => area["id"],
          "title" => area["title"],
          "position" => area["position"],
          "active" => area["active"],
          "project_count" => Array(area["projects"]).size
        }
      end
    end

    def flatten_projects(payload)
      areas = payload.is_a?(Hash) ? payload["areas"] : nil
      raise Error.new("Board response did not include areas", code: "INVALID_RESPONSE") unless areas.is_a?(Array)

      areas.flat_map do |area|
        Array(area["projects"]).map do |project|
          project.merge("area_id" => area["id"], "area_title" => area["title"]).reject { |key, _| key == "tasks" }
        end
      end
    end

    def flatten_tasks(payload)
      areas = payload.is_a?(Hash) ? payload["areas"] : nil
      raise Error.new("Board response did not include areas", code: "INVALID_RESPONSE") unless areas.is_a?(Array)

      areas.flat_map do |area|
        Array(area["projects"]).flat_map do |project|
          Array(project["tasks"]).map do |task|
            task.merge(
              "area_id" => area["id"],
              "area_title" => area["title"],
              "project_title" => project["title"]
            )
          end
        end
      end
    end

    def parse_options(args, **allowed)
      options = {}
      parser = OptionParser.new
      parser.on("--user USER") { |value| options[:user] = value } if allowed[:user]
      if allowed[:title]
        parser.on("-t", "--title TITLE") { |value| options[:title] = value }
      end
      parser.on("--project ID") { |value| options[:project] = value } if allowed[:project]
      parser.on("--assignee EMAIL") { |value| options[:assignee] = value } if allowed[:assignee]
      parser.on("--email EMAIL") { |value| options[:email] = value } if allowed[:email]
      parser.on("--area ID") { |value| options[:area] = value } if allowed[:area]
      parser.on("--description HTML") { |value| options[:description] = value } if allowed[:description]
      parser.on("--due DATE") { |value| options[:due] = value } if allowed[:due]
      parser.on("--estimate N") { |value| options[:estimate] = positive_integer(value, "--estimate") } if allowed[:estimate]
      parser.on("--source-url URL") { |value| options[:source_url] = source_url(value) } if allowed[:source_url]
      parser.on("--schema JSON") { |value| options[:schema] = value } if allowed[:schema]
      parser.on("--status STATUS") { |value| options[:status] = value } if allowed[:status]
      if allowed[:position]
        parser.on("--position N") { |value| options[:position] = Integer(value) }
      end
      if allowed[:active]
        parser.on("--active VALUE") { |value| options[:active] = parse_bool(value, "--active") }
      end
      parser.on("--field KEY=VALUE") { |value| (options[:fields] ||= []) << value } if allowed[:fields]
      parser.on("--notes TEXT") { |value| options[:notes] = value } if allowed[:notes]
      parser.on("--note TEXT") { |value| options[:note] = value } if allowed[:note]
      parser.on("--star") { options[:star] = true } if allowed[:star]
      parser.on("--off") { options[:off] = true } if allowed[:off]
      parser.parse!(args)
      options
    rescue OptionParser::ParseError => e
      raise Error.new(e.message, code: "INVALID_ARGUMENT")
    rescue ArgumentError => e
      raise Error.new(e.message, code: "INVALID_ARGUMENT")
    end

    # Print the task's quality checks on stderr and return the task as is.
    def with_quality(task)
      self.class.print_quality(@err, task["quality"]) if task.is_a?(Hash) && task["quality"].is_a?(Hash)
      task
    end

    def positive_integer(value, name)
      return if value.strip.empty?

      integer = Integer(value)
      raise Error.new("#{name} must be greater than 0", code: "INVALID_ARGUMENT") unless integer.positive?

      integer
    end

    def source_url(value)
      value = value.strip
      return if value.empty?

      # Mirrors Task#source_url_is_http server-side: userinfo is rejected so a
      # https://trusted.example@evil.example/ link cannot look trustworthy.
      uri = URI.parse(value)
      unless uri.is_a?(URI::HTTP) && uri.host && uri.userinfo.nil?
        raise Error.new("--source-url must be an http/https URL", code: "INVALID_ARGUMENT")
      end

      value
    rescue URI::InvalidURIError
      raise Error.new("--source-url must be an http/https URL", code: "INVALID_ARGUMENT")
    end

    def parse_bool(value, name)
      case value.to_s.downcase
      when "true", "1", "yes" then true
      when "false", "0", "no" then false
      else
        raise Error.new("#{name} must be true or false", code: "INVALID_ARGUMENT")
      end
    end

    def parse_schema(value)
      source = if value.start_with?("@")
                 path = File.expand_path(value.delete_prefix("@"))
                 File.read(path)
               else
                 value
               end
      parsed = JSON.parse(source)
      unless parsed.is_a?(Array)
        raise Error.new("--schema must be a JSON array", code: "INVALID_ARGUMENT")
      end

      parsed
    rescue Errno::ENOENT => e
      raise Error.new("Schema file not found: #{e.message}", code: "FILE_NOT_FOUND")
    rescue JSON::ParserError => e
      raise Error.new("Invalid schema JSON: #{e.message}", code: "INVALID_JSON")
    end

    def parse_fields(fields)
      fields.each_with_object({}) do |field, parsed|
        key, separator, value = field.partition("=")
        if separator.empty? || key.empty?
          raise Error.new("--field must use key=value", code: "INVALID_ARGUMENT")
        end
        parsed[key] = value
      end
    end

    def required_positional!(name)
      value = @args.shift
      raise Error.new("Missing #{name}", code: "INVALID_ARGUMENT") if value.to_s.empty? || value.start_with?("-")

      value
    end

    def required_option!(value, name)
      raise Error.new("#{name} is required", code: "INVALID_ARGUMENT") if value.to_s.empty?

      value
    end

    def ensure_no_args!
      return if @args.empty?

      raise Error.new("Unexpected argument: #{@args.first}", code: "INVALID_ARGUMENT")
    end

    def request(method, path, body: nil)
      @client.request(method, path, body: body)
    end

    def fail_usage!(message)
      raise Error.new("#{message}\n#{USAGE}", code: "USAGE")
    end
  end
end
