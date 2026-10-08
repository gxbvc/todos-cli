# frozen_string_literal: true

require "json"
require "optparse"
require "time"
require "uri"

require "todos/client"
require "todos/error"

module Todos
  class CLI
    STATUSES = %w[open submitted approved canceled blocked].freeze
    PROJECT_STATUSES = %w[active waiting someday completed].freeze
    USAGE = <<~TEXT.freeze
      Usage:
        todos-cli me
        todos-cli users list
        todos-cli users show <id|email>
        todos-cli users remind <id|email>
        todos-cli board [--user <id|email>]
        todos-cli logbook [--kind logged|canceled] [--before DATE | --all]
        todos-cli areas list --user <id|email>
        todos-cli areas create --user <id|email> -t TITLE [--position N] [--active true|false]
        todos-cli areas invite <id> --email EMAIL
        todos-cli projects list [--user <id|email>]
        todos-cli projects create -t TITLE [--area ID]
        todos-cli projects create --user <id|email> -t TITLE [--area ID] [--status STATUS] [--position N]
        todos-cli projects invite <id> --email EMAIL
        todos-cli invites list
        todos-cli invites accept <id> [--area ID]
        todos-cli tasks list [--user <id|email>] [--project ID] [--status STATUS]
        todos-cli tasks get|show <id> [--user <id|email>]
        todos-cli tasks check -t TITLE [--description MARKDOWN|@file] [--schema JSON|@file]
        todos-cli tasks create -t TITLE --project ID [--assignee EMAIL] [--description MARKDOWN|@file] [--due DATE] [--due-time HH:MM] [--zone ZONE] [--no-deadline] [--do-on DATE] [--priority LEVEL] [--priority-reason TEXT] [--estimate N] [--schema JSON|@file] [--star] [--allow-external]
        todos-cli tasks create --user <id|email> -t TITLE [--project ID] [--description MARKDOWN|@file] [--due DATE] [--due-time HH:MM] [--zone ZONE] [--no-deadline] [--do-on DATE] [--priority LEVEL] [--priority-reason TEXT] [--estimate N] [--source-url URL] [--schema JSON|@file] [--star]
        todos-cli tasks update <id> [--user <id|email>] [--title TITLE] [--project ID] [--description MARKDOWN|@file] [--due DATE] [--due-time HH:MM] [--zone ZONE] [--no-deadline] [--do-on DATE] [--priority LEVEL] [--priority-reason TEXT] [--estimate N] [--source-url URL] [--schema JSON|@file] [--field key=value]
        todos-cli tasks destroy <id> --user <id|email>
        todos-cli tasks submit <id> [--user <id|email>] [--field key=value]
        todos-cli tasks approve <id> [--user <id|email>]
        todos-cli tasks send-back <id> --note TEXT
        todos-cli tasks star <id> [--off] [--user <id|email>]
        todos-cli tasks plan <id> [--do-on DATE|""] [--no-deadline]
        todos-cli tasks reopen <id> [--user <id|email>] [--note TEXT] [--reason TEXT]
        todos-cli tasks cancel <id> [--user <id|email>] [--reason TEXT]
        todos-cli tasks block <id> --reason TEXT
        todos-cli tasks unblock <id> [--note TEXT]
        todos-cli tasks remind <id> --user <id|email>
        todos-cli tasks respond <id> [--user <id|email>] --field key=value [--field key=value]
        todos-cli tasks comment <id> "TEXT"|@file.md
        todos-cli tasks comments <id>
        todos-cli tasks versions <id>
        todos-cli webhooks list
        todos-cli webhooks create --url URL [--events TYPE,TYPE|*] [--description TEXT]
        todos-cli webhooks update <id> [--url URL] [--events TYPE,TYPE|*] [--description TEXT] [--active true|false]
        todos-cli webhooks delete <id>
        todos-cli webhooks rotate <id>
        todos-cli webhooks test <id>
        todos-cli webhooks deliveries <id>

      Every task must be a next physical action.
      Rules and examples: write-human-todos skill.
      The server scores every task on 7 checks; create, get, and check print them on stderr.
      tasks create --assignee can name someone you invited to that project (or its area) who has
      not joined yet: the task waits on the invite and lands on them when they accept.
      A project is external when people outside your email domain can see it (projects list: external).
      Use an internal project unless the user names an external one; only then pass --allow-external.
      Writes in an external project print an EXTERNAL line on stderr.
      --description is markdown (or @file.md); tasks get returns it as data.description.
      Text they must copy (a prompt, an email body, a command) goes in a ``` code block: the card
      shows a Copy button. Under a numbered step, indent the block to line up with the step text.
      Short values (an email address, a subject line) go in `inline code`: a tap copies it.
      --schema is a JSON array (or @file.json) of fields, one per answer you need back:
        [{"label":"Booking URL","type":"url","required":true}]
      Types: text, textarea, url, password (a secret only the asker reads back), file, voice,
      recording (a screen and voice recording: only the assignee records; Scribe transcribes it),
      radio (pick one), checkboxes (pick any). radio and checkboxes need "options": 2 or more,
      recommended first. Optional: "key" (made from the label), "placeholder", "required": true.
      Leave --schema out when marking done is enough.
      My board leaves canceled to-dos off: they are in the logbook (todos-cli logbook), and
      tasks list --status canceled reads them from there (every week).
      logbook gives one week: the 7 days before --before DATE (default: up to today). stderr names
      the --before for the week before; --all reads every week.
      --due-time HH:MM is 24-hour Central time and goes with --due. On update, --due-time "" clears the
      time and --due "" clears the date and the time.
      --zone is the zone of --due-time (an IANA name like America/New_York; Central when left out).
      --do-on DATE is the day to work on it: it shows in Today that day, and the deadline stays.
      Set --do-on only when the person chose that day. Never set it to today to get their attention:
      Today fills with to-dos nobody planned. Use --due for a real deadline, or --priority.
      --no-deadline says there is no deadline on purpose. tasks plan is the doer's own: --do-on and
      --no-deadline (only while the asker set no deadline).
      tasks cancel and tasks reopen take --reason TEXT: one line on why, shown in the history. Give it
      whenever someone else is on the to-do (the web asks for it; the API will require it).
      --priority is urgent, high, normal (the default), or low. Each person can hold 3 open Urgent
      to-dos from one asker; past that, --priority-reason TEXT is required and goes in the history.
      --star (and tasks star) pins the to-do for you only: pins do not reorder anyone's list.
      tasks update without --user is the asker's edit (PATCH /tasks/:id); with --user, the admin's.
      Notes are comments now. tasks comment <id> "TEXT" (or @file.md, markdown) posts one as you: the
      person doing it, the person who asked, and the reviewer can comment in any status, and a comment
      never changes the status. tasks comments <id> lists the thread; tasks get prints it on stderr.
      tasks versions <id> lists the old copies of the title, description, and fields, newest first:
      {id, created_at, by, changes: {description: [old, new]}}. Never answers.
      --notes on tasks update and tasks respond still works for one release: it posts a comment.
      Webhooks: todo.gxb.vc POSTs a signed event to your https URL when a to-do you can open changes.
      --events: task.created task.updated task.submitted task.approved task.reopened task.canceled
      task.blocked task.unblocked task.logged comment.created comment.deleted, or * (all, the default).
      create and rotate print the secret once (data.secret): keep it. Check each request:
      X-Todo-Signature t=<unix>,v1=<hex HMAC-SHA256(secret, "<t>.<raw body>")>; refuse t older than
      5 minutes. The payload is thin (id, title, status, link): read the rest with tasks get.
      update --active true turns on a webhook that was disabled after 50 failed deliveries.
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
      # The server refused a task in a project that is external for me.
      audience = e.details && e.details["audience"]
      if audience.is_a?(Hash)
        err.puts("Pick an internal project, or pass --allow-external only if the user named this one.")
        envelope[:audience] = audience
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
      weakest = quality["weakest_label"] || quality["weakest"]
      err.puts("Quality #{quality["score"]} (weakest: #{weakest}), #{verdict}")
      Array(quality["checks"]).each do |check|
        mark = check["passed"] ? "pass" : "FAIL"
        blocks = check["blocking"] ? "" : " (does not block)"
        # The check's one name (label), as on the card; the id is for code.
        line = "  #{mark}  #{check["label"] || check["id"]}#{blocks}: #{check["score"]}"
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
      when "logbook" then logbook
      when "areas" then areas
      when "projects" then projects
      when "tasks" then tasks
      when "invites" then invites
      when "webhooks" then webhooks
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
      when "invite" then areas_invite
      else
        fail_usage!("Usage: todos-cli areas <list|create|invite>")
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

    # Email someone a link to join a whole area I own: every project I own in
    # it, now and later, never projects others shared with me that I filed
    # there. data.status is added (a colleague at my own work email domain
    # with an account joined at once, no link), invited, or already_member;
    # a refusal (not the owner, bad email, rate limit) exits 1 with the
    # server's reason.
    def areas_invite
      id = required_positional!("area id")
      options = parse_options(@args, email: true)
      ensure_no_args!
      email = required_option!(options[:email], "--email")
      note_added(request(:post, "/areas/#{id}/invites.json", body: { email: email }), "area")
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

    # Two routes. With --user: the admin's flattened view of that person's
    # board. Without it: my own projects (GET /projects.json), with members,
    # and external relative to me.
    def projects_list
      options = parse_options(@args, user: true)
      ensure_no_args!
      unless options[:user]
        payload = request(:get, "/projects.json")
        projects = payload.is_a?(Hash) ? payload["projects"] : nil
        raise Error.new("Projects response did not include projects", code: "INVALID_RESPONSE") unless projects.is_a?(Array)

        return projects
      end

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

    # Email someone a link to join a project I own. data.status is added (a
    # colleague at my own work email domain with an account joined at once,
    # no link), invited, or already_member; a refusal (not the owner, bad
    # email, rate limit) exits 1 with the server's reason.
    def projects_invite
      id = required_positional!("project id")
      options = parse_options(@args, email: true)
      ensure_no_args!
      email = required_option!(options[:email], "--email")
      note_added(request(:post, "/projects/#{id}/invites.json", body: { email: email }), "project")
    end

    # An immediate share sends no link, so say so on stderr.
    def note_added(result, kind)
      if result.is_a?(Hash) && result["status"] == "added"
        name = result.dig("member", "name") || "They"
        @err.puts("#{name} is on the #{kind} now (same work email domain). No invite was sent.")
      end
      result
    end

    # Project and area invites sent to my own email (GET /invites.json). An
    # invited project or area is not on my board until I accept.
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

    # Join the project (project-4), filed in one of my areas (--area) or my
    # Shared area; data is the project as projects.json shows it. Or join the
    # area (area-2), its projects filed in one of my areas (--area) or a new
    # area named after it; data is { area, filed_area_id, projects }. Any
    # invite I cannot accept (not mine, expired, revoked, used) is the same
    # NOT_FOUND.
    def invites_accept
      id = required_positional!("invite id")
      options = parse_options(@args, area: true)
      ensure_no_args!
      unless id.match?(/\A[a-z]+-\d+\z/)
        raise Error.new("Invite id looks like project-4 or area-2 (from todos-cli invites list)", code: "INVALID_ARGUMENT")
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

    # My webhooks (todo plan 25). Only mine: anyone else's id is HTTP_404.
    def webhooks
      subcommand = @args.shift
      case subcommand
      when "list"
        ensure_no_args!
        request(:get, "/webhooks.json")["webhooks"]
      when "create" then webhooks_create
      when "update" then webhooks_update
      when "delete" then webhook_member(:delete, "")
      when "rotate" then webhook_member(:post, "/rotate")
      when "test" then webhook_member(:post, "/test")
      when "deliveries" then webhook_member(:get, "/deliveries")
      else
        fail_usage!("Usage: todos-cli webhooks <list|create|update|delete|rotate|test|deliveries>")
      end
    end

    # data.secret is shown here and on rotate only, so say so on stderr.
    def webhooks_create
      options = parse_options(@args, url: true, events: true, description: true)
      ensure_no_args!
      body = { url: required_option!(options[:url], "--url") }
      body[:events] = options[:events] if options.key?(:events)
      body[:description] = options[:description] if options.key?(:description)
      note_secret(request(:post, "/webhooks.json", body: body))
    end

    def webhooks_update
      id = required_positional!("webhook id")
      options = parse_options(@args, url: true, events: true, description: true, active: true)
      ensure_no_args!
      body = options.slice(:url, :events, :description, :active)
      raise Error.new("Pass --url, --events, --description, or --active", code: "INVALID_ARGUMENT") if body.empty?

      request(:patch, "/webhooks/#{id}.json", body: body)
    end

    # delete (data null), rotate (a new secret), test (a ping, queued now),
    # deliveries (the last 50).
    def webhook_member(method, action)
      id = required_positional!("webhook id")
      ensure_no_args!
      result = request(method, "/webhooks/#{id}#{action}.json")
      action == "/rotate" ? note_secret(result) : result
    end

    def note_secret(result)
      @err.puts("Copy data.secret now: it is not shown again.") if result.is_a?(Hash) && result["secret"]
      result
    end

    # A comma list of event types, or * for all.
    def event_types(value)
      types = value.to_s.split(",").map(&:strip).reject(&:empty?)
      raise ArgumentError, "--events needs at least one type, or *" if types.empty?

      types
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
      when "plan" then tasks_plan
      when "submit" then tasks_submit
      when "reopen" then tasks_reopen
      when "cancel" then tasks_cancel
      when "block" then tasks_block
      when "unblock" then tasks_unblock
      when "remind" then tasks_remind
      when "respond" then tasks_respond
      when "comment" then tasks_comment
      when "comments" then tasks_comments
      when "versions" then tasks_versions
      else
        fail_usage!("Usage: todos-cli tasks <list|get|show|check|create|update|destroy|approve|send-back|star|plan|submit|reopen|cancel|block|unblock|remind|respond|comment|comments|versions>")
      end
    end

    def tasks_list
      options = parse_options(@args, user: true, project: true, status: true)
      ensure_no_args!
      if options[:status] && !STATUSES.include?(options[:status])
        raise Error.new("Status must be one of: #{STATUSES.join(", ")}", code: "INVALID_ARGUMENT")
      end
      # My board leaves canceled to-dos off; they are in my logbook. The
      # admin's --user board still has them.
      if options[:status] == "canceled" && !options[:user]
        tasks = logbook_entries("canceled", all: true)
        tasks.select! { |task| task["project_id"].to_s == options[:project].to_s } if options[:project]
        return tasks
      end

      payload = board_for(options[:user])
      note_open_invites(payload)
      tasks = flatten_tasks(payload)
      tasks.select! { |task| task["project_id"].to_s == options[:project].to_s } if options[:project]
      tasks.select! { |task| task["status"] == options[:status] } if options[:status]
      tasks
    end

    # What left my board, newest first (GET /logbook.json): to-dos I logged
    # (kind logged, logged_at) and canceled to-dos of my board's projects
    # (kind canceled, canceled_at, declined with the reason).
    # One week at a time (todo plan 26): the 7 days before --before DATE
    # (the server's default: up to today). The reply's next_before is the
    # week before; stderr names it. --all follows it to the oldest week.
    def logbook
      options = parse_options(@args, kind: true, before: true, all: true)
      ensure_no_args!
      if options[:kind] && !%w[logged canceled].include?(options[:kind])
        raise Error.new("--kind must be logged or canceled", code: "INVALID_ARGUMENT")
      end
      raise Error.new("Pass --before DATE or --all, not both", code: "INVALID_ARGUMENT") if options[:before] && options[:all]

      logbook_entries(options[:kind], before: options[:before], all: options[:all])
    end

    LOGBOOK_MAX_WEEKS = 520

    def logbook_entries(kind = nil, before: nil, all: false)
      entries = []
      LOGBOOK_MAX_WEEKS.times do
        payload = @client.request(:get, "/logbook.json", query: (before.to_s.empty? ? {} : { before: before }))
        page = payload.is_a?(Hash) ? payload["entries"] : nil
        raise Error.new("Logbook response did not include entries", code: "INVALID_RESPONSE") unless page.is_a?(Array)

        entries.concat(page)
        before = payload["next_before"]
        break if before.to_s.empty?
        next if all

        @err.puts("Older entries: todos-cli logbook --before #{before} (or --all)")
        break
      end
      kind ? entries.select { |entry| entry["kind"] == kind } : entries
    end

    def tasks_get
      id = required_positional!("task id")
      parse_options(@args, user: true)
      ensure_no_args!
      with_comments(with_quality(request(:get, "/tasks/#{id}.json")))
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
    # projects, for me or for --assignee, an active member of that project,
    # or someone I invited to it or its area who has not joined yet (the
    # task waits: data.assignee is null and data.waiting_for_invite has the
    # invite id). The server scores it; a refusal (422) prints the failed
    # checks. A project that is external for me needs --allow-external on
    # this route (todo plan 20d); the admin route is not checked.
    def tasks_create
      options = parse_options(
        @args,
        user: true, title: true, project: true, assignee: true, description: true, due: true, due_time: true, estimate: true,
        source_url: true, schema: true, star: true, allow_external: true, priority: true, priority_reason: true,
        zone: true, do_on: true, no_deadline: true
      )
      ensure_no_args!
      title = required_option!(options[:title], "--title/-t")
      task = { title: title }
      task[:project_id] = options[:project] if options.key?(:project)
      task[:description] = options[:description] if options.key?(:description)
      task[:due_date] = options[:due] if options.key?(:due)
      if options[:due_time].to_s != ""
        raise Error.new("--due-time needs --due DATE", code: "INVALID_ARGUMENT") if options[:due].to_s.empty?
        task[:due_time] = options[:due_time]
      end
      task[:fields_schema] = parse_schema(options[:schema]) if options.key?(:schema)
      task[:starred] = true if options[:star]
      task[:priority] = options[:priority] if options.key?(:priority)
      task[:priority_reason] = options[:priority_reason] if options.key?(:priority_reason)
      task[:estimated_minutes] = options[:estimate] if options.key?(:estimate)
      add_plan_fields!(task, options)

      if options[:user]
        if options.key?(:assignee)
          raise Error.new("--assignee is for the member route; --user already names who does it", code: "INVALID_ARGUMENT")
        end
        if options[:allow_external]
          raise Error.new("--allow-external is for the member route; the admin route (--user) is not checked", code: "INVALID_ARGUMENT")
        end
        task[:source_url] = options[:source_url] if options.key?(:source_url)
        return note_external(with_quality(request(:post, "/users/#{resolve_user(options[:user])}/tasks.json", body: { task: task })))
      end

      if options.key?(:source_url)
        raise Error.new("--source-url needs --user (admin create)", code: "INVALID_ARGUMENT")
      end
      # A forgotten --user must fail, not land a client's to-do on my board.
      unless options.key?(:project)
        raise Error.new("Pass --user EMAIL for someone's board, or --project ID (and --assignee EMAIL) for a shared project", code: "INVALID_ARGUMENT")
      end
      task[:assignee_email] = options[:assignee] if options.key?(:assignee)
      body = { task: task }
      body[:allow_external] = true if options[:allow_external]
      result = note_external(with_quality(request(:post, "/tasks.json", body: body)))
      if result.is_a?(Hash) && (waiting = result.dig("waiting_for_invite", "id"))
        @err.puts("Waiting on invite #{waiting}: it lands on them when they accept.")
      end
      result
    end

    def tasks_update
      id = required_positional!("task id")
      options = parse_options(
        @args,
        user: true, title: true, project: true, description: true, due: true, due_time: true,
        estimate: true, source_url: true, schema: true, fields: true, notes: true, priority: true, priority_reason: true,
        zone: true, do_on: true, no_deadline: true
      )
      ensure_no_args!

      task = {}
      task[:title] = options[:title] if options.key?(:title)
      task[:project_id] = options[:project] if options.key?(:project)
      task[:description] = options[:description] if options.key?(:description)
      task[:due_date] = options[:due] if options.key?(:due)
      task[:due_time] = options[:due_time] if options.key?(:due_time)
      task[:estimated_minutes] = options[:estimate] if options.key?(:estimate)
      task[:source_url] = options[:source_url] if options.key?(:source_url)
      task[:fields_schema] = parse_schema(options[:schema]) if options.key?(:schema)
      task[:priority] = options[:priority] if options.key?(:priority)
      task[:priority_reason] = options[:priority_reason] if options.key?(:priority_reason)
      add_plan_fields!(task, options)

      body = {}
      body[:task] = task unless task.empty?
      body[:response] = parse_fields(options[:fields]) if options[:fields]&.any?
      raise Error.new("Nothing to update", code: "INVALID_ARGUMENT") if body.empty? && !options.key?(:notes)
      if options.key?(:source_url) && !options[:user]
        raise Error.new("--source-url needs --user (admin edit)", code: "INVALID_ARGUMENT")
      end

      # Without --user: the asker's own edit on the member route.
      path = options[:user] ? "/users/#{resolve_user(options[:user])}/tasks/#{id}.json" : "/tasks/#{id}.json"
      result = note_external(request(:patch, path, body: body)) unless body.empty?
      notes_as_comment(id, options, result)
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

    # Pin (or --off to unpin) for me only (the server's old star route): any
    # member of the to-do's project; the admin with --user.
    def tasks_star
      id = required_positional!("task id")
      options = parse_options(@args, user: true, off: true)
      ensure_no_args!
      body = { starred: !options[:off] }
      return request(:patch, "/tasks/#{id}/star.json", body: body) unless options[:user]

      request(:patch, "/users/#{resolve_user(options[:user])}/tasks/#{id}/star.json", body: body)
    end

    # The doer plans it: --do-on DATE ("" clears) puts it in Today that day
    # without changing the deadline; --no-deadline says there is none (only
    # while the asker set none). Member route.
    def tasks_plan
      id = required_positional!("task id")
      options = parse_options(@args, do_on: true, no_deadline: true)
      ensure_no_args!
      body = {}
      body[:do_on] = options[:do_on] if options.key?(:do_on)
      body[:no_deadline] = true if options[:no_deadline]
      raise Error.new("Pass --do-on DATE or --no-deadline", code: "INVALID_ARGUMENT") if body.empty?

      request(:patch, "/tasks/#{id}/plan.json", body: body)
    end

    def add_plan_fields!(task, options)
      task[:due_zone] = options[:zone] if options.key?(:zone)
      task[:do_on] = options[:do_on] if options.key?(:do_on)
      task[:no_deadline] = true if options[:no_deadline]
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
      options = parse_options(@args, user: true, note: true, reason: true)
      ensure_no_args!
      reason = options[:reason].to_s.strip
      if options[:user]
        body = {}
        body[:note] = options[:note] if options.key?(:note)
        body[:reason] = reason unless reason.empty?
        request(:patch, "/users/#{resolve_user(options[:user])}/tasks/#{id}/reopen.json", body: body.empty? ? nil : body)
      else
        if options.key?(:note)
          raise Error.new("--note requires --user because self reopen is silent", code: "INVALID_ARGUMENT")
        end
        request(:patch, "/tasks/#{id}/reopen.json", body: reason.empty? ? nil : { reason: reason })
      end
    end

    def tasks_cancel
      id = required_positional!("task id")
      options = parse_options(@args, user: true, reason: true)
      ensure_no_args!
      path = if options[:user]
               "/users/#{resolve_user(options[:user])}/tasks/#{id}/cancel.json"
             else
               "/tasks/#{id}/cancel.json"
             end
      reason = options[:reason].to_s.strip
      request(:patch, path, body: reason.empty? ? nil : { reason: reason })
    end

    # The assignee cannot do an open to-do someone else gave them without
    # something from that person: it goes to their court (status blocked)
    # with what is needed, and they get it in their email batch. Member route
    # only (I must be the assignee); a to-do I wrote for myself I cancel.
    def tasks_block
      id = required_positional!("task id")
      options = parse_options(@args, reason: true)
      ensure_no_args!
      reason = required_option!(options[:reason].to_s.strip, "--reason")
      request(:patch, "/tasks/#{id}/block.json", body: { reason: reason })
    end

    # The person who asked added what was needed: back to the assignee,
    # open. --note (optional) says what was added; it is posted as a comment
    # on the to-do and goes in the assignee's email.
    def tasks_unblock
      id = required_positional!("task id")
      options = parse_options(@args, note: true)
      ensure_no_args!
      body = options[:note].to_s.strip.empty? ? nil : { note: options[:note].strip }
      request(:patch, "/tasks/#{id}/unblock.json", body: body)
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
      raise Error.new("Pass at least one --field", code: "INVALID_ARGUMENT") if body.empty? && !options.key?(:notes)

      path = if options[:user]
               "/users/#{resolve_user(options[:user])}/tasks/#{id}.json"
             else
               "/tasks/#{id}.json"
             end
      result = request(:patch, path, body: body) unless body.empty?
      notes_as_comment(id, options, result)
    end

    # Post a comment on a to-do as me (todo plan 23: notes are comments), on
    # the member route: the person doing it, the person who asked, and the
    # reviewer may post, in any status, and the status never changes.
    # "@file.md" reads a file; the text is markdown. data is the comment
    # {id, kind, body, author, at}.
    def tasks_comment
      id = required_positional!("task id")
      text = @args.shift.to_s
      ensure_no_args!
      text = comment_text(text)
      raise Error.new("Missing comment text (or @file.md)", code: "INVALID_ARGUMENT") if text.strip.empty?

      post_comment(id, text)
    end

    # The thread, oldest first, from my own route (GET /my_tasks/:id.json).
    def tasks_comments
      id = required_positional!("task id")
      ensure_no_args!
      task = request(:get, "/my_tasks/#{id}.json")
      comments = task.is_a?(Hash) ? task["comments"] : nil
      raise Error.new("Task response did not include comments", code: "INVALID_RESPONSE") unless comments.is_a?(Array)

      comments
    end

    # Old copies of the title, description, and fields (todo plan 26),
    # newest first, from GET /tasks/:id/versions.json: each
    # {id, created_at, by, changes: {"description" => [old, new]}}. Only
    # people who can open the to-do (the admin too) read them.
    def tasks_versions
      id = required_positional!("task id")
      ensure_no_args!
      body = request(:get, "/tasks/#{id}/versions.json")
      versions = body.is_a?(Hash) ? body["versions"] : nil
      raise Error.new("Response did not include versions", code: "INVALID_RESPONSE") unless versions.is_a?(Array)

      versions
    end

    def post_comment(id, text) = request(:post, "/tasks/#{id}/comments.json", body: { body: text })

    # The deprecated --notes (one release): posts a comment as me, after the
    # rest of the change, and says so on stderr. Returns the task from the
    # change with the new comment in its thread, or the comment when
    # --notes was all there was.
    def notes_as_comment(id, options, result)
      return result unless options.key?(:notes)

      @err.puts(%(--notes is now a comment. Use: todos-cli tasks comment #{id} "text"))
      return result if options[:notes].to_s.strip.empty?

      comment = post_comment(id, options[:notes])
      return comment unless result.is_a?(Hash)

      result["comments"] = Array(result["comments"]) + [ comment ] if result.key?("comments")
      result
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
      parser.on("--url URL", "The https URL a webhook posts to") { |value| options[:url] = value.strip } if allowed[:url]
      parser.on("--events TYPES", "Comma list of event types, or *") { |value| options[:events] = event_types(value) } if allowed[:events]
      parser.on("--description MARKDOWN", "Card body in markdown, or @file.md. Text to copy goes in a ``` block (Copy button).") { |value| options[:description] = description_text(value) } if allowed[:description]
      parser.on("--due DATE") { |value| options[:due] = due_date(value) } if allowed[:due]
      parser.on("--due-time HH:MM") { |value| options[:due_time] = due_time(value) } if allowed[:due_time]
      parser.on("--estimate N") { |value| options[:estimate] = positive_integer(value, "--estimate") } if allowed[:estimate]
      parser.on("--zone ZONE", "Time zone of --due-time, like America/New_York") { |value| options[:zone] = value.strip } if allowed[:zone]
      parser.on("--do-on DATE", "Day to work on it (YYYY-MM-DD), or "" to clear") { |value| options[:do_on] = plan_date(value, "--do-on") } if allowed[:do_on]
      parser.on("--no-deadline", "There is no deadline on purpose") { options[:no_deadline] = true } if allowed[:no_deadline]
      parser.on("--priority LEVEL", "urgent, high, normal, or low") { |value| options[:priority] = priority(value) } if allowed[:priority]
      parser.on("--priority-reason TEXT", "Why one more Urgent (needed past 3 open Urgent from one asker)") { |value| options[:priority_reason] = value } if allowed[:priority_reason]
      parser.on("--source-url URL") { |value| options[:source_url] = source_url(value) } if allowed[:source_url]
      parser.on("--schema JSON", "Fields as a JSON array, or @file.json: [{label, type, options?, required?}]. " \
                                  "Types: text textarea url password file voice recording radio checkboxes.") { |value| options[:schema] = value } if allowed[:schema]
      parser.on("--status STATUS") { |value| options[:status] = value } if allowed[:status]
      parser.on("--kind KIND") { |value| options[:kind] = value } if allowed[:kind]
      parser.on("--before DATE", "Logbook: the 7 days before this day (YYYY-MM-DD)") { |value| options[:before] = plan_date(value, "--before") } if allowed[:before]
      parser.on("--all", "Logbook: every week") { options[:all] = true } if allowed[:all]
      if allowed[:position]
        parser.on("--position N") { |value| options[:position] = Integer(value) }
      end
      if allowed[:active]
        parser.on("--active VALUE") { |value| options[:active] = parse_bool(value, "--active") }
      end
      parser.on("--field KEY=VALUE") { |value| (options[:fields] ||= []) << value } if allowed[:fields]
      parser.on("--notes TEXT") { |value| options[:notes] = value } if allowed[:notes]
      parser.on("--note TEXT") { |value| options[:note] = value } if allowed[:note]
      parser.on("--reason TEXT") { |value| options[:reason] = value } if allowed[:reason]
      parser.on("--star") { options[:star] = true } if allowed[:star]
      parser.on("--off") { options[:off] = true } if allowed[:off]
      parser.on("--allow-external") { options[:allow_external] = true } if allowed[:allow_external]
      parser.parse!(args)
      options
    rescue OptionParser::ParseError => e
      raise Error.new(e.message, code: "INVALID_ARGUMENT")
    rescue ArgumentError => e
      raise Error.new(e.message, code: "INVALID_ARGUMENT")
    end

    # After a write: one stderr line when the task's project is external for
    # me (people outside my email domain can see it, or will once invites
    # are accepted). Counts only. Returns the task as is.
    def note_external(task)
      project = task.is_a?(Hash) ? task["project"] : nil
      return task unless project.is_a?(Hash) && project["external"] == true

      outside = project.dig("audience", "outside").to_i
      people = outside == 1 ? "1 person" : "#{outside} people"
      @err.puts("EXTERNAL: #{project["title"]} is an external project: #{people} outside your email domain can see this task.")
      task
    end

    # Print the task's quality checks on stderr and return the task as is.
    def with_quality(task)
      self.class.print_quality(@err, task["quality"]) if task.is_a?(Hash) && task["quality"].is_a?(Hash)
      task
    end

    COMMENT_LABELS = { "changes_requested" => "Sent back", "blocked" => "Blocked", "unblocked" => "Unblocked", "migrated" => "From the old notes" }.freeze

    # The thread under the answers, on stderr (data has it as comments).
    # Returns the task as is.
    def with_comments(task)
      comments = task.is_a?(Hash) ? task["comments"] : nil
      return task unless comments.is_a?(Array) && comments.any?

      @err.puts("Comments (#{comments.size}):")
      comments.each do |comment|
        label = COMMENT_LABELS[comment["kind"]]
        head = [ comment.dig("author", "name") || "Someone", comment_time(comment["at"]) ].compact.join(", ")
        head += " [#{label}]" if label
        @err.puts("  #{head}:")
        comment["body"].to_s.each_line { |line| @err.puts("    #{line.chomp}") }
      end
      task
    end

    def comment_time(value)
      Time.iso8601(value.to_s).localtime.strftime("%b %-d, %-l:%M %p")
    rescue ArgumentError
      value
    end

    # Comment text in markdown, or "@file.md" for a file.
    def comment_text(value)
      return value unless value.start_with?("@")

      path = File.expand_path(value.delete_prefix("@"))
      raise Error.new("Comment file not found: #{path}", code: "INVALID_ARGUMENT") unless File.file?(path)

      File.read(path)
    end

    # A day only. A time in --due would be dropped by the server without a
    # word, so it is refused here and pointed at --due-time.
    def due_date(value)
      value = value.strip
      if value.match?(/\d{1,2}:\d{2}/)
        raise Error.new("--due takes a date (YYYY-MM-DD); pass the time with --due-time HH:MM", code: "INVALID_ARGUMENT")
      end

      value
    end

    PRIORITIES = %w[urgent high normal low].freeze

    def priority(value)
      level = value.to_s.strip.downcase
      return level if PRIORITIES.include?(level)

      raise Error.new("--priority must be urgent, high, normal, or low", code: "INVALID_ARGUMENT")
    end

    # A day (YYYY-MM-DD) for --do-on, or "" to clear it.
    def plan_date(value, flag)
      value = value.strip
      return value if value.empty? || value.match?(/\A\d{4}-\d{2}-\d{2}\z/)

      raise Error.new("#{flag} takes a date (YYYY-MM-DD), or "" to clear it", code: "INVALID_ARGUMENT")
    end

    # "15:00" (24-hour, Central time on the server, or the --zone), "9:05"
    # becomes "09:05", and "" clears the time on update.
    def due_time(value)
      value = value.strip
      return "" if value.empty?

      match = value.match(/\A(\d{1,2}):(\d{2})\z/)
      unless match && match[1].to_i < 24 && match[2].to_i < 60
        raise Error.new("--due-time must be HH:MM, 24-hour Central time (for example 15:00), or \"\" to clear it", code: "INVALID_ARGUMENT")
      end

      format("%02d:%02d", match[1].to_i, match[2].to_i)
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

    # The card text in markdown (todo stores markdown). "@notes.md" reads a
    # file, for long text. HTML still works for one release: the server
    # converts it.
    def description_text(value)
      return value unless value.start_with?("@")

      path = File.expand_path(value.delete_prefix("@"))
      raise Error.new("--description file not found: #{path}", code: "INVALID_ARGUMENT") unless File.file?(path)

      File.read(path)
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
