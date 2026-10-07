# frozen_string_literal: true

require_relative "test_helper"

class TodosCliTest < Minitest::Test
  def test_mutating_commands_use_bound_routes_and_bodies
    schema = [{ "key" => "ein", "label" => "EIN", "type" => "text", "placeholder" => "" }]
    cases = [
      {
        args: %w[tasks create --user 7 -t Send-W9 --project 3 --description <p>Hi</p> --due 2026-08-01 --estimate 15 --source-url https://tickets.gxb.vc/123 --schema] + [JSON.generate(schema)],
        method: "POST",
        target: "/users/7/tasks.json",
        body: {
          "task" => {
            "title" => "Send-W9", "project_id" => "3", "description" => "<p>Hi</p>",
            "due_date" => "2026-08-01", "estimated_minutes" => 15,
            "source_url" => "https://tickets.gxb.vc/123", "fields_schema" => schema
          }
        }
      },
      {
        args: %w[tasks create -t Send-W9 --project 3 --assignee sam@example.com --description <p>Hi</p> --due 2026-08-01 --star --schema] + [JSON.generate(schema)],
        method: "POST",
        target: "/tasks.json",
        body: {
          "task" => {
            "title" => "Send-W9", "project_id" => "3", "description" => "<p>Hi</p>",
            "due_date" => "2026-08-01", "fields_schema" => schema, "starred" => true,
            "assignee_email" => "sam@example.com"
          }
        }
      },
      {
        args: %w[tasks create -t Send-W9 --project 3 --due 2026-10-02 --due-time 9:05],
        method: "POST",
        target: "/tasks.json",
        body: { "task" => { "title" => "Send-W9", "project_id" => "3", "due_date" => "2026-10-02", "due_time" => "09:05" } }
      },
      {
        args: %w[tasks create --user 7 -t Send-W9 --due 2026-10-02 --due-time 15:00],
        method: "POST",
        target: "/users/7/tasks.json",
        body: { "task" => { "title" => "Send-W9", "due_date" => "2026-10-02", "due_time" => "15:00" } }
      },
      {
        args: %w[tasks update 9 --user 7 --due-time 17:30],
        method: "PATCH",
        target: "/users/7/tasks/9.json",
        body: { "task" => { "due_time" => "17:30" } }
      },
      {
        args: [ "tasks", "update", "9", "--user", "7", "--due-time", "" ],
        method: "PATCH",
        target: "/users/7/tasks/9.json",
        body: { "task" => { "due_time" => "" } }
      },
      {
        args: [ "tasks", "update", "9", "--user", "7", "--due", "" ],
        method: "PATCH",
        target: "/users/7/tasks/9.json",
        body: { "task" => { "due_date" => "" } }
      },
      {
        args: %w[tasks create -t Send-W9 --project 3 --priority URGENT --priority-reason Penalty --estimate 10],
        method: "POST",
        target: "/tasks.json",
        body: { "task" => { "title" => "Send-W9", "project_id" => "3", "priority" => "urgent", "priority_reason" => "Penalty", "estimated_minutes" => 10 } }
      },
      {
        args: %w[tasks create -t Call-bank --project 3 --due 2026-10-09 --due-time 10:00 --zone America/New_York --do-on 2026-10-07],
        method: "POST",
        target: "/tasks.json",
        body: { "task" => { "title" => "Call-bank", "project_id" => "3", "due_date" => "2026-10-09", "due_time" => "10:00",
                              "due_zone" => "America/New_York", "do_on" => "2026-10-07" } }
      },
      {
        args: %w[tasks update 9 --no-deadline],
        method: "PATCH",
        target: "/tasks/9.json",
        body: { "task" => { "no_deadline" => true } }
      },
      {
        args: [ "tasks", "cancel", "9", "--reason", "The client dropped it" ],
        method: "PATCH",
        target: "/tasks/9/cancel.json",
        body: { "reason" => "The client dropped it" }
      },
      {
        args: [ "tasks", "reopen", "9", "--reason", "Numbers changed" ],
        method: "PATCH",
        target: "/tasks/9/reopen.json",
        body: { "reason" => "Numbers changed" }
      },
      {
        args: %w[tasks plan 9 --do-on 2026-10-06],
        method: "PATCH",
        target: "/tasks/9/plan.json",
        body: { "do_on" => "2026-10-06" }
      },
      {
        args: [ "tasks", "plan", "9", "--do-on", "", "--no-deadline" ],
        method: "PATCH",
        target: "/tasks/9/plan.json",
        body: { "do_on" => "", "no_deadline" => true }
      },
      {
        args: %w[tasks update 9 --priority high],
        method: "PATCH",
        target: "/tasks/9.json",
        body: { "task" => { "priority" => "high" } }
      },
      {
        args: %w[tasks update 9 --user 7 --priority low],
        method: "PATCH",
        target: "/users/7/tasks/9.json",
        body: { "task" => { "priority" => "low" } }
      },
      {
        args: %w[tasks create --user 7 -t Send-W9 --star],
        method: "POST",
        target: "/users/7/tasks.json",
        body: { "task" => { "title" => "Send-W9", "starred" => true } }
      },
      {
        args: %w[tasks check -t Send-W9 --description <p>Hi</p> --schema] + [JSON.generate(schema)],
        method: "POST",
        target: "/quality_checks.json",
        body: { "title" => "Send-W9", "description" => "<p>Hi</p>", "fields_schema" => schema }
      },
      {
        args: %w[tasks approve 9],
        method: "PATCH",
        target: "/tasks/9/approve.json",
        body: nil
      },
      {
        args: %w[tasks send-back 9 --note Add-the-invoice-number],
        method: "PATCH",
        target: "/tasks/9/send_back.json",
        body: { "note" => "Add-the-invoice-number" }
      },
      {
        args: [ "tasks", "block", "9", "--reason", "  I need Ricky's login for this.  " ],
        method: "PATCH",
        target: "/tasks/9/block.json",
        body: { "reason" => "I need Ricky's login for this." }
      },
      {
        args: [ "tasks", "unblock", "9", "--note", " It is in 1Password. " ],
        method: "PATCH",
        target: "/tasks/9/unblock.json",
        body: { "note" => "It is in 1Password." }
      },
      {
        args: %w[tasks unblock 9],
        method: "PATCH",
        target: "/tasks/9/unblock.json",
        body: nil
      },
      {
        args: %w[tasks star 9],
        method: "PATCH",
        target: "/tasks/9/star.json",
        body: { "starred" => true }
      },
      {
        args: %w[tasks star 9 --off],
        method: "PATCH",
        target: "/tasks/9/star.json",
        body: { "starred" => false }
      },
      {
        args: %w[tasks star 9 --user 7 --off],
        method: "PATCH",
        target: "/users/7/tasks/9/star.json",
        body: { "starred" => false }
      },
      {
        args: %w[tasks update 9 --user 7 --title Revised --project 4 --description <p>New</p> --due 2026-09-01 --estimate 30 --source-url https://tickets.gxb.vc/456 --schema] +
          [JSON.generate(schema)] + %w[--field ein=12-345],
        method: "PATCH",
        target: "/users/7/tasks/9.json",
        body: {
          "task" => {
            "title" => "Revised", "project_id" => "4", "description" => "<p>New</p>",
            "due_date" => "2026-09-01", "estimated_minutes" => 30,
            "source_url" => "https://tickets.gxb.vc/456", "fields_schema" => schema
          },
          "response" => { "ein" => "12-345" }
        }
      },
      {
        args: %w[tasks destroy 9 --user 7],
        method: "DELETE",
        target: "/users/7/tasks/9.json",
        body: nil,
        response: { status: 204, body: "" }
      },
      {
        args: %w[tasks approve 9 --user 7],
        method: "PATCH",
        target: "/users/7/tasks/9/approve.json",
        body: nil
      },
      {
        args: %w[tasks submit 9 --user 7],
        method: "PATCH",
        target: "/users/7/tasks/9/submit.json",
        body: nil
      },
      {
        args: %w[tasks submit 9 --field ein=12-345],
        method: "PATCH",
        target: "/tasks/9/submit.json",
        body: { "response" => { "ein" => "12-345" } }
      },
      {
        args: %w[tasks reopen 9 --user 7 --note Need-a-clearer-scan],
        method: "PATCH",
        target: "/users/7/tasks/9/reopen.json",
        body: { "note" => "Need-a-clearer-scan" }
      },
      {
        args: %w[tasks reopen 9],
        method: "PATCH",
        target: "/tasks/9/reopen.json",
        body: nil
      },
      {
        args: %w[tasks cancel 9 --user 7],
        method: "PATCH",
        target: "/users/7/tasks/9/cancel.json",
        body: nil
      },
      {
        args: %w[tasks cancel 9],
        method: "PATCH",
        target: "/tasks/9/cancel.json",
        body: nil
      },
      {
        args: %w[tasks remind 9 --user 7],
        method: "POST",
        target: "/users/7/tasks/9/remind.json",
        body: nil
      },
      {
        args: %w[users remind 7],
        method: "POST",
        target: "/users/7/remind.json",
        body: nil
      },
      {
        args: %w[tasks respond 9 --user 7 --field ein=12-345 --field name=Jane],
        method: "PATCH",
        target: "/users/7/tasks/9.json",
        body: { "response" => { "ein" => "12-345", "name" => "Jane" } }
      },
      {
        args: %w[tasks respond 9 --field ein=12-345],
        method: "PATCH",
        target: "/tasks/9.json",
        body: { "response" => { "ein" => "12-345" } }
      },
      {
        args: %w[areas create --user 7 -t BrightView --position 2 --active true],
        method: "POST",
        target: "/users/7/areas.json",
        body: { "area" => { "title" => "BrightView", "position" => 2, "active" => true } }
      },
      {
        args: %w[areas create --user 7 -t BrightView],
        method: "POST",
        target: "/users/7/areas.json",
        body: { "area" => { "title" => "BrightView" } }
      },
      {
        args: %w[projects create --user 7 -t Onboarding --area 3 --status active --position 1],
        method: "POST",
        target: "/users/7/projects.json",
        body: {
          "project" => {
            "title" => "Onboarding", "area_id" => "3", "status" => "active", "position" => 1
          }
        }
      },
      {
        args: %w[projects create --user 7 -t Default-area-project],
        method: "POST",
        target: "/users/7/projects.json",
        body: { "project" => { "title" => "Default-area-project" } }
      },
      {
        args: %w[projects create -t TAP-intake --area 4],
        method: "POST",
        target: "/projects.json",
        body: { "project" => { "title" => "TAP-intake", "area_id" => "4" } }
      },
      {
        args: %w[projects create -t Side-work],
        method: "POST",
        target: "/projects.json",
        body: { "project" => { "title" => "Side-work" } }
      },
      {
        args: %w[projects invite 12 --email sue@tap.test],
        method: "POST",
        target: "/projects/12/invites.json",
        body: { "email" => "sue@tap.test" },
        response: { body: JSON.generate(status: "invited", invite: { id: 3, email: "sue@tap.test" }) }
      },
      {
        args: %w[invites accept project-4 --area 9],
        method: "POST",
        target: "/invites/project-4/accept.json",
        body: { "area_id" => "9" },
        response: { body: JSON.generate(id: 150, title: "TriGate (internal)", role: "member", area_id: 9) }
      },
      {
        args: %w[areas invite 52 --email sue@tap.test],
        method: "POST",
        target: "/areas/52/invites.json",
        body: { "email" => "sue@tap.test" },
        response: { body: JSON.generate(status: "invited", invite: { id: 2, email: "sue@tap.test" }) }
      },
      {
        args: %w[invites accept area-2],
        method: "POST",
        target: "/invites/area-2/accept.json",
        body: {},
        response: { body: JSON.generate(area: { id: 52, title: "TriGate" }, filed_area_id: 9, projects: []) }
      }
    ]

    cases.each do |test_case|
      server = StubServer.new(test_case.fetch(:response, {}))
      output, = run_cli(*test_case[:args], server: server)
      request = server.requests.pop

      assert_equal true, output["ok"], test_case[:args].join(" ")
      assert_equal test_case[:method], request[:method], test_case[:args].join(" ")
      assert_equal test_case[:target], request[:target], test_case[:args].join(" ")
      if test_case[:body].nil?
        assert_nil json_body(request), test_case[:args].join(" ")
      else
        assert_equal test_case[:body], json_body(request), test_case[:args].join(" ")
      end
      assert_equal "Bearer test-key", request[:headers]["authorization"]
      assert_equal "application/json", request[:headers]["accept"]
      if test_case[:body]
        assert_equal "application/json", request[:headers]["content-type"]
      end
    end
  end

# Todo plan 23: notes are comments.
def test_tasks_comment_posts_on_the_member_route
  comment = { id: 5, kind: "comment", body: "Any update?", author: { id: 1, name: "Christian Genco" }, at: "2026-10-06T19:41:00Z" }
  server = StubServer.new({ status: 201, body: JSON.generate(comment) })

  output, _stderr, status = run_cli("tasks", "comment", "677", "Any update?", server: server)
  request = server.requests.pop

  assert status.success?
  assert_equal [ "POST", "/tasks/677/comments.json" ], [ request[:method], request[:target] ]
  assert_equal({ "body" => "Any update?" }, json_body(request))
  assert_equal "Any update?", output.dig("data", "body")
end

def test_tasks_comment_reads_a_file_and_needs_text
  Dir.mktmpdir do |dir|
    path = File.join(dir, "reply.md")
    File.write(path, "Line one\n\n```\nls -la\n```\n")
    server = StubServer.new({ status: 201, body: JSON.generate(id: 6) })
    run_cli("tasks", "comment", "677", "@#{path}", server: server)
    assert_equal "Line one\n\n```\nls -la\n```\n", json_body(server.requests.pop)["body"]
  end

  output, _stderr, status = run_cli("tasks", "comment", "677", server: StubServer.new)
  refute status.success?
  assert_equal "INVALID_ARGUMENT", output["code"]
end

def test_tasks_comments_lists_the_thread_from_my_route
  task = { id: 677, comments: [ { id: 5, kind: "changes_requested", body: "Add Tuesday", author: { id: 5, name: "Ricky Bureau" } } ] }
  server = StubServer.new({ body: JSON.generate(task) })

  output, = run_cli("tasks", "comments", "677", server: server)

  assert_equal "/my_tasks/677.json", server.requests.pop[:target]
  assert_equal [ "Add Tuesday" ], output["data"].map { |comment| comment["body"] }
end

def test_tasks_versions_lists_old_text_newest_first
  body = { task_id: 677, versions: [ { id: 9, created_at: "2026-10-07T20:00:00Z", by: { id: 1, name: "Christian Genco" },
                                       changes: { description: [ "Old", "New" ] } } ] }
  server = StubServer.new({ body: JSON.generate(body) })

  output, = run_cli("tasks", "versions", "677", server: server)

  assert_equal "/tasks/677/versions.json", server.requests.pop[:target]
  assert_equal [ [ "Old", "New" ] ], output["data"].map { |version| version.dig("changes", "description") }
end

def test_get_prints_the_thread_under_the_answers
  task = { id: 677, title: "Reply", comments: [
    { id: 5, kind: "changes_requested", body: "Add Tuesday\nand Wednesday", author: { id: 5, name: "Ricky Bureau" }, at: "2026-10-06T19:41:00Z" },
    { id: 6, kind: "comment", body: "Done", author: { id: 1, name: "Christian Genco" }, at: "2026-10-06T20:00:00Z" }
  ] }
  server = StubServer.new({ body: JSON.generate(task) })

  output, stderr, = run_cli("tasks", "get", "677", server: server)

  assert_equal 2, output.dig("data", "comments").size
  assert_includes stderr, "Comments (2):"
  assert_match(/  Ricky Bureau, Oct 6, .+ \[Sent back\]:\n    Add Tuesday\n    and Wednesday\n/, stderr)
  assert_match(/  Christian Genco, Oct 6, .+:\n    Done\n/, stderr)
end

def test_notes_on_respond_posts_a_comment_after_the_answers_and_warns
  task = { id: 9, status: "open", comments: [] }
  comment = { id: 7, kind: "comment", body: "Ready" }
  server = StubServer.new({ body: JSON.generate(task) }, { status: 201, body: JSON.generate(comment) })

  output, stderr, status = run_cli("tasks", "respond", "9", "--user", "7", "--field", "ein=12-345", "--notes", "Ready", server: server)
  patch = server.requests.pop
  post = server.requests.pop

  assert status.success?
  assert_equal [ "PATCH", "/users/7/tasks/9.json", { "response" => { "ein" => "12-345" } } ], [ patch[:method], patch[:target], json_body(patch) ]
  assert_equal [ "POST", "/tasks/9/comments.json", { "body" => "Ready" } ], [ post[:method], post[:target], json_body(post) ]
  assert_includes stderr, %(--notes is now a comment. Use: todos-cli tasks comment 9 "text")
  assert_equal [ "Ready" ], output.dig("data", "comments").map { |c| c["body"] }
end

def test_notes_alone_on_update_posts_only_the_comment
  server = StubServer.new({ status: 201, body: JSON.generate(id: 7, kind: "comment", body: "Received") })

  output, stderr, = run_cli("tasks", "update", "9", "--user", "7", "--notes", "Received", server: server)
  request = server.requests.pop

  assert_equal [ "POST", "/tasks/9/comments.json" ], [ request[:method], request[:target] ]
  assert_equal "Received", output.dig("data", "body")
  assert_includes stderr, "--notes is now a comment"
end

  def test_projects_create_without_user_says_it_is_my_own_project
    output, stderr, status = run_cli(*%w[projects create -t Side-work], server: StubServer.new({}))
    assert status.success?
    assert_equal true, output["ok"]
    assert_match(/^No --user: making the project in your own board\.$/, stderr)

    _output, stderr, = run_cli(*%w[projects create --user 7 -t Side-work], server: StubServer.new({}))
    refute_match(/No --user/, stderr)
  end

  def test_estimate_and_source_url_must_be_valid
    [
      [ %w[tasks create --user 7 -t Send-W9 --estimate nope], /invalid value for Integer/ ],
      [ %w[tasks create --user 7 -t Send-W9 --estimate 0], /--estimate must be greater than 0/ ],
      [ %w[tasks create --user 7 -t Send-W9 --source-url tickets.gxb.vc/123], /--source-url must be an http\/https URL/ ]
    ].each do |args, message|
      output, _stderr, status = run_cli(*args, server: StubServer.new)

      refute status.success?, args.join(" ")
      assert_equal false, output["ok"]
      assert_equal "INVALID_ARGUMENT", output["code"]
      assert_match message, output["error"]
    end
  end

  def test_empty_estimate_and_source_url_clear_their_fields
    {
      "--estimate" => "estimated_minutes",
      "--source-url" => "source_url"
    }.each do |flag, attribute|
      server = StubServer.new({})
      output, = run_cli("tasks", "update", "9", "--user", "7", "--title", "Revised", flag, "", server: server)

      assert_equal true, output["ok"]
      assert_nil json_body(server.requests.pop).dig("task", attribute)
    end
  end

  # The server's quality breakdown (todo TaskQuality) as JSON.
  def quality(passed:, failing: [])
    checks = [
      ["physical_action", "One physical next step", true, "Name one act someone could watch you do."],
      ["strong_verb", "Starts with a strong verb", false, "Start with Send, Pay, Reply, Confirm, or Upload."],
      ["prework_done", "Prep work is done", true, "Do the prep first. For a send, put the draft in the description."]
    ].map do |id, label, blocking, hint|
      failed = failing.include?(id)
      { id: id, label: label, p_yes: failed ? 0.2 : 0.9, score: failed ? 40 : 88, passed: !failed, blocking: blocking, hint: hint }
    end
    { score: failing.any? ? 40 : 88, version: "v2", gated: false, passed: passed, weakest: failing.first || "physical_action", checks: checks }
  end

  def test_create_prints_the_quality_checks_with_hints_for_fails
    body = { id: 99, title: "Send W-9", status: "open", quality: quality(passed: false, failing: %w[prework_done strong_verb]) }
    server = StubServer.new(status: 201, body: JSON.generate(body))
    output, stderr, status = run_cli("tasks", "create", "--user", "7", "-t", "Send W-9", server: server)

    assert status.success?
    assert_equal true, output["ok"]
    assert_equal 40, output.dig("data", "quality", "score")
    assert_match(/^Quality 40 \(weakest: prework_done\), failed$/, stderr)
    assert_match(/^  pass  One physical next step: 88$/, stderr)
    assert_match(/^  FAIL  Prep work is done: 40\. Do the prep first\. For a send, put the draft in the description\.$/, stderr)
    assert_match(/^  FAIL  Starts with a strong verb \(does not block\): 40\. Start with Send/, stderr)
    refute_match(/GTD warn/, stderr)
  end

  def test_a_quality_refusal_prints_the_failed_checks_and_exits_nonzero
    body = { errors: ["Fix these checks before you assign it: Prep work is done"], quality: quality(passed: false, failing: %w[prework_done]) }
    server = StubServer.new(status: 422, body: JSON.generate(body))
    output, stderr, status = run_cli(
      "tasks", "create", "-t", "Send W-9", "--project", "3", "--assignee", "sam@example.com", server: server
    )

    refute status.success?
    assert_equal false, output["ok"]
    assert_equal "HTTP_422", output["code"]
    assert_equal "Fix these checks before you assign it: Prep work is done", output["error"]
    assert_equal false, output.dig("quality", "passed")
    assert_equal "prework_done", output.dig("quality", "weakest")
    assert_match(/^  FAIL  Prep work is done: 40\. Do the prep first/, stderr)
  end

  def test_get_and_show_print_the_quality_checks
    %w[get show].each do |command|
      body = { id: 9, title: "Send W-9", status: "open", quality: quality(passed: true) }
      server = StubServer.new(body: JSON.generate(body))
      output, stderr, status = run_cli("tasks", command, "9", server: server)

      assert status.success?, command
      assert_equal "/tasks/9.json", server.requests.pop[:target]
      assert_equal true, output.dig("data", "quality", "passed")
      assert_match(/^Quality 88 \(weakest: physical_action\), passed$/, stderr)
    end
  end

  def test_an_unscored_task_says_so
    body = { id: 9, title: "Send W-9", status: "open", quality: { score: nil, passed: nil, checks: [] } }
    server = StubServer.new(body: JSON.generate(body))
    _output, stderr, = run_cli("tasks", "get", "9", server: server)

    assert_match(/^Quality: not scored yet$/, stderr)
  end

  def test_check_prints_the_checks_and_exits_zero_when_they_fail
    server = StubServer.new(body: JSON.generate(quality: quality(passed: false, failing: %w[prework_done])))
    output, stderr, status = run_cli("tasks", "check", "-t", "Review the website", server: server)

    assert status.success?
    assert_equal false, output.dig("data", "quality", "passed")
    assert_match(/FAIL  Prep work is done/, stderr)
  end

  def test_the_local_gtd_warning_and_force_flag_are_gone
    output, stderr, status = run_cli("tasks", "create", "--user", "7", "-t", "test todo", "--force", server: StubServer.new)

    refute status.success?
    assert_equal "INVALID_ARGUMENT", output["code"]
    assert_match(/invalid option: --force/, output["error"])
    refute_match(/GTD warn/, stderr)
  end

  def test_member_and_admin_create_flags_do_not_mix
    [
      [%w[tasks create -t Send-W9 --project 3 --source-url https://x.com/1], /--source-url needs --user/],
      [%w[tasks update 9 --source-url https://x.com/1], /--source-url needs --user/],
      [%w[tasks create -t Send-W9 --project 3 --priority critical], /--priority must be urgent, high, normal, or low/],
      [%w[tasks plan 9], /Pass --do-on DATE or --no-deadline/],
      [%w[tasks plan 9 --do-on tomorrow], /--do-on takes a date/],
      [%w[tasks create --user 7 -t Send-W9 --assignee sam@example.com], /--assignee is for the member route/],
      [%w[tasks create -t Send-W9], /Pass --user EMAIL for someone's board, or --project ID/],
      [%w[tasks create -t Send-W9 --assignee sam@example.com], /Pass --user EMAIL for someone's board, or --project ID/],
      [%w[tasks send-back 9], /--note is required/],
      [%w[tasks create -t Send-W9 --project 3 --due-time 15:00], /--due-time needs --due DATE/],
      [%w[tasks create -t Send-W9 --project 3 --due 2026-10-02 --due-time 25:00], /--due-time must be HH:MM/],
      [%w[tasks create -t Send-W9 --project 3 --due 2026-10-02 --due-time 3pm], /--due-time must be HH:MM/],
      [%w[tasks update 9 --user 7 --due-time 12:60], /--due-time must be HH:MM/],
      [%w[tasks create -t Send-W9 --project 3 --due 2026-10-02T15:00], /--due takes a date \(YYYY-MM-DD\); pass the time with --due-time/],
      [%w[tasks block 9 --reason No --due-time 15:00], /invalid option: --due-time/],
      [%w[tasks block 9], /--reason is required/],
      [[ "tasks", "block", "9", "--reason", "   " ], /--reason is required/],
      [%w[tasks block 9 --reason No --user 7], /invalid option: --user/],
      [%w[tasks block --reason No], /task id/],
      [%w[tasks unblock 9 --user 7], /invalid option: --user/],
      [%w[tasks check], /--title\/-t is required/]
    ].each do |args, message|
      output, _stderr, status = run_cli(*args, server: StubServer.new)

      refute status.success?, args.join(" ")
      assert_equal "INVALID_ARGUMENT", output["code"], args.join(" ")
      assert_match message, output["error"], args.join(" ")
    end
  end

  def test_source_url_is_stripped_before_sending
    server = StubServer.new({})
    output, = run_cli(
      "tasks", "create", "--user", "7", "--title", "Send W-9",
      "--source-url", "  https://x.com/1  ", server: server
    )

    assert_equal true, output["ok"]
    assert_equal "https://x.com/1", json_body(server.requests.pop).dig("task", "source_url")
  end

  def test_email_user_is_resolved_once_then_used_in_nested_route
    users = { users: [{ id: 7, email: "andy@example.com", name: "Andy" }] }
    server = StubServer.new({ body: JSON.generate(users) }, {})

    output, = run_cli(
      "tasks", "update", "9", "--user", "ANDY@example.com", "--title", "Revised",
      server: server
    )
    first = server.requests.pop
    second = server.requests.pop

    assert_equal true, output["ok"]
    assert_equal "/users.json", first[:target]
    assert_equal "/users/7/tasks/9.json", second[:target]
  end

  def test_tasks_remind_resolves_an_email_user
    users = { users: [{ id: 7, email: "andy@example.com", name: "Andy" }] }
    server = StubServer.new({ body: JSON.generate(users) }, {})

    output, = run_cli("tasks", "remind", "9", "--user", "andy@example.com", server: server)
    server.requests.pop
    second = server.requests.pop

    assert_equal true, output["ok"]
    assert_equal "POST", second[:method]
    assert_equal "/users/7/tasks/9/remind.json", second[:target]
  end

  def test_tasks_remind_requires_user
    output, _stderr, status = run_cli("tasks", "remind", "9", server: StubServer.new)

    refute status.success?
    assert_equal false, output["ok"]
    assert_equal "USER_REQUIRED", output["code"]
  end

  def test_users_remind_resolves_an_email_user
    users = { users: [{ id: 7, email: "andy@example.com", name: "Andy" }] }
    server = StubServer.new({ body: JSON.generate(users) }, {})

    output, = run_cli("users", "remind", "andy@example.com", server: server)
    server.requests.pop
    second = server.requests.pop

    assert_equal true, output["ok"]
    assert_equal "POST", second[:method]
    assert_equal "/users/7/remind.json", second[:target]
  end

  def test_users_remind_requires_a_positional_reference
    output, _stderr, status = run_cli("users", "remind", server: StubServer.new)

    refute status.success?
    assert_equal false, output["ok"]
    assert_equal "INVALID_ARGUMENT", output["code"]
  end

  def test_http_errors_always_use_json_envelope
    {
      401 => { error: "Unauthorized" },
      403 => { error: "Forbidden" },
      404 => { error: "Not found" },
      422 => { errors: ["Title can't be blank", "Project is invalid"] }
    }.each do |status_code, response_body|
      server = StubServer.new(status: status_code, body: JSON.generate(response_body))
      output, _stderr, status = run_cli("tasks", "get", "9", server: server)

      assert_equal false, status.success?
      assert_equal false, output["ok"]
      assert_equal "HTTP_#{status_code}", output["code"]
      assert_kind_of String, output["error"]
      assert_equal %w[code error ok], output.keys.sort
    end
  end

  def test_projects_create_without_user_refuses_admin_only_flags
    server = StubServer.new
    output, _stderr, status = run_cli("projects", "create", "-t", "TAP", "--status", "active", server: server)

    refute status.success?
    assert_equal "INVALID_ARGUMENT", output["code"]
    assert_empty server.requests
  end

  def test_projects_invite_needs_an_email_and_reports_the_servers_reason
    output, _stderr, status = run_cli("projects", "invite", "12", server: StubServer.new)
    refute status.success?
    assert_equal "INVALID_ARGUMENT", output["code"]

    server = StubServer.new(status: 403, body: JSON.generate(status: "refused", reason: "Only the project owner can invite people."))
    output, stderr, status = run_cli("projects", "invite", "12", "--email", "x@tap.test", server: server)
    refute status.success?
    assert_equal "HTTP_403", output["code"]
    assert_equal "Only the project owner can invite people.", output["error"]
    assert_includes stderr, "Only the project owner can invite people."

    server = StubServer.new(body: JSON.generate(status: "already_member"))
    output, = run_cli("projects", "invite", "12", "--email", "sam@tap.test", server: server)
    assert_equal({ "ok" => true, "data" => { "status" => "already_member" } }, output)
  end

  def test_projects_and_areas_invite_say_when_a_colleague_was_added_at_once
    added = JSON.generate(status: "added", member: { id: 5, name: "Ricky Bureau" })
    output, stderr, status = run_cli("projects", "invite", "12", "--email", "ricky@gxb.vc", server: StubServer.new(body: added))
    assert status.success?
    assert_equal({ "status" => "added", "member" => { "id" => 5, "name" => "Ricky Bureau" } }, output["data"])
    assert_includes stderr, "Ricky Bureau is on the project now (same work email domain). No invite was sent."

    _output, stderr, = run_cli("areas", "invite", "52", "--email", "ricky@gxb.vc", server: StubServer.new(body: added))
    assert_includes stderr, "Ricky Bureau is on the area now"

    invited = JSON.generate(status: "invited", invite: { id: 3, email: "sue@tap.test" })
    _output, stderr, = run_cli("projects", "invite", "12", "--email", "sue@tap.test", server: StubServer.new(body: invited))
    refute_match(/No invite was sent/, stderr)
  end

  def test_create_for_an_invited_person_says_it_waits
    body = { id: 31, title: "Send the signed contract", status: "open", assignee: nil,
             waiting_for_invite: { id: "project-4", expired: false }, quality: quality(passed: true, failing: []) }
    server = StubServer.new(status: 201, body: JSON.generate(body))
    output, stderr, status = run_cli("tasks", "create", "-t", "Send the signed contract", "--project", "12",
                                     "--assignee", "pat@partner.test", server: server)

    assert status.success?
    assert_nil output.dig("data", "assignee")
    assert_includes stderr, "Waiting on invite project-4: it lands on them when they accept."
    assert_equal "pat@partner.test", JSON.parse(server.requests.pop[:body]).dig("task", "assignee_email")
  end

  def external_task(outside: 1)
    { id: 31, title: "Send the signed contract", status: "open", quality: quality(passed: true, failing: []),
      project: { id: 12, title: "Partner work", external: true, audience: { members: 3, pending: 0, outside: outside } } }
  end

  def test_allow_external_is_sent_next_to_the_task_only_when_given
    server = StubServer.new(status: 201, body: JSON.generate(external_task))
    _output, stderr, status = run_cli("tasks", "create", "-t", "Send the signed contract", "--project", "12", "--allow-external", server: server)
    assert status.success?
    assert_equal true, JSON.parse(server.requests.pop[:body])["allow_external"]
    assert_includes stderr, "EXTERNAL: Partner work is an external project: 1 person outside your email domain can see this task."

    server = StubServer.new(status: 201, body: JSON.generate(external_task(outside: 2)))
    _output, stderr, = run_cli("tasks", "create", "-t", "Send the signed contract", "--project", "12", server: server)
    refute JSON.parse(server.requests.pop[:body]).key?("allow_external")
    assert_includes stderr, "2 people outside your email domain"
  end

  def test_an_internal_project_prints_no_external_line
    body = external_task.merge(project: { id: 3, title: "Launch", external: false, audience: { members: 2, pending: 0, outside: 0 } })
    _output, stderr, status = run_cli("tasks", "create", "-t", "Send it", "--project", "3", server: StubServer.new(status: 201, body: JSON.generate(body)))
    assert status.success?
    refute_match(/EXTERNAL/, stderr)
  end

  def test_the_external_refusal_says_how_to_go_on
    body = { error: "This project is external: 1 person outside your email domain can see it. Resend with allow_external: true if you meant it.",
             audience: { members: 3, pending: 0, outside: 1 } }
    output, stderr, status = run_cli("tasks", "create", "-t", "Send it", "--project", "12", server: StubServer.new(status: 422, body: JSON.generate(body)))
    refute status.success?
    assert_equal "HTTP_422", output["code"]
    assert_equal({ "members" => 3, "pending" => 0, "outside" => 1 }, output["audience"])
    assert_includes stderr, "Pick an internal project, or pass --allow-external only if the user named this one."
  end

  def test_admin_writes_print_the_external_line_and_refuse_the_flag
    _output, stderr, = run_cli("tasks", "create", "--user", "7", "-t", "Send it", server: StubServer.new(status: 201, body: JSON.generate(external_task)))
    assert_includes stderr, "EXTERNAL: Partner work"
    _output, stderr, = run_cli("tasks", "update", "31", "--user", "7", "--title", "Send it now", server: StubServer.new(body: JSON.generate(external_task)))
    assert_includes stderr, "EXTERNAL: Partner work"

    output, _stderr, status = run_cli("tasks", "create", "--user", "7", "-t", "Send it", "--allow-external", server: StubServer.new)
    refute status.success?
    assert_equal "INVALID_ARGUMENT", output["code"]
    output, = run_cli("tasks", "update", "31", "--user", "7", "--allow-external", server: StubServer.new)
    assert_equal "INVALID_ARGUMENT", output["code"], "update cannot move a task through a checked route, so it has no flag"
  end

  def test_projects_list_shows_external
    board = { user: { id: 7 }, areas: [{ id: 1, title: "Clients", external: true, projects: [
      { id: 12, title: "Partner work", external: true, audience: { members: 3, pending: 0, outside: 1 }, tasks: [] }
    ] }] }
    output, = run_cli("projects", "list", "--user", "7", server: StubServer.new(body: JSON.generate(board)))
    assert_equal true, output["data"][0]["external"]
    assert_equal({ "members" => 3, "pending" => 0, "outside" => 1 }, output["data"][0]["audience"])
  end

  def test_projects_list_without_user_reads_my_projects
    rows = [{ "id" => 12, "title" => "Partner work", "external" => true, "audience" => { "members" => 3, "pending" => 0, "outside" => 1 } }]
    server = StubServer.new(body: JSON.generate(projects: rows, open_invites: 0))
    output, _stderr, status = run_cli("projects", "list", server: server)

    assert status.success?
    assert_equal rows, output["data"]
    request = server.requests.pop
    assert_equal "GET", request[:method]
    assert_equal "/projects.json", request[:target]
  end

  LOGBOOK = { user: { id: 7 }, entries: [
    { id: 5, title: "Send the deck", status: "approved", kind: "logged", project_id: 3, logged_at: "2026-09-30T09:00:00-05:00" },
    { id: 6, title: "Upload the W-9", status: "canceled", kind: "canceled", project_id: 3, canceled_at: "2026-09-29T16:00:00-05:00",
      declined: { by: { id: 8, name: "Sam" }, reason: "Not mine" } },
    { id: 9, title: "Pay the invoice", status: "canceled", kind: "canceled", project_id: 4, canceled_at: "2026-09-28T10:00:00-05:00", declined: nil }
  ] }.freeze

  def test_description_is_markdown_and_can_come_from_a_file
    Dir.mktmpdir do |dir|
      path = File.join(dir, "card.md")
      File.write(path, "1. Open [the sheet](https://example.com)\n2. Sign it\n")
      server = StubServer.new(status: 201, body: JSON.generate(id: 5, description: "x"))
      output, _stderr, status = run_cli("tasks", "create", "-t", "Sign-it", "--project", "3", "--description", "@#{path}", server: server)
      assert status.success?, output.inspect
      assert_equal "1. Open [the sheet](https://example.com)\n2. Sign it\n", json_body(server.requests.pop).dig("task", "description")
    end

    server = StubServer.new(status: 201, body: JSON.generate(id: 5))
    run_cli("tasks", "create", "-t", "Sign-it", "--project", "3", "--description", "**Bold** and `code`", server: server)
    assert_equal "**Bold** and `code`", json_body(server.requests.pop).dig("task", "description")

    output, _stderr, status = run_cli("tasks", "create", "-t", "Sign-it", "--project", "3", "--description", "@/no/such/file.md", server: StubServer.new)
    refute status.success?
    assert_match "--description file not found", output["error"]
  end

  def test_decline_is_gone
    output, _stderr, status = run_cli("tasks", "decline", "9", "--reason", "No", server: StubServer.new)
    refute status.success?
    assert_equal "USAGE", output["code"]
    assert_includes output["error"], "block|unblock"
  end

  def test_logbook_reads_my_logbook_and_filters_by_kind
    server = StubServer.new(body: JSON.generate(LOGBOOK))
    output, _stderr, status = run_cli("logbook", server: server)
    assert status.success?
    assert_equal [ 5, 6, 9 ], output["data"].map { |entry| entry["id"] }
    request = server.requests.pop
    assert_equal [ "GET", "/logbook.json" ], [ request[:method], request[:target] ]

    output, = run_cli("logbook", "--kind", "canceled", server: StubServer.new(body: JSON.generate(LOGBOOK)))
    assert_equal [ 6, 9 ], output["data"].map { |entry| entry["id"] }
    assert_equal "Not mine", output["data"][0].dig("declined", "reason")

    output, _stderr, status = run_cli("logbook", "--kind", "approved", server: StubServer.new)
    refute status.success?
    assert_match "--kind must be logged or canceled", output["error"]
  end

  def test_logbook_pages_by_week_with_before_and_all
    first = LOGBOOK.merge(next_before: "2026-09-30")
    second = { user: { id: 7 }, entries: [ { id: 3, title: "Older", kind: "logged" } ], next_before: nil }

    server = StubServer.new(body: JSON.generate(first))
    output, stderr, status = run_cli("logbook", server: server)
    assert status.success?
    assert_equal [ 5, 6, 9 ], output["data"].map { |entry| entry["id"] }
    assert_includes stderr, "Older entries: todos-cli logbook --before 2026-09-30 (or --all)"

    server = StubServer.new(body: JSON.generate(second))
    output, = run_cli("logbook", "--before", "2026-09-30", server: server)
    assert_equal [ 3 ], output["data"].map { |entry| entry["id"] }
    assert_equal "/logbook.json?before=2026-09-30", server.requests.pop[:target]

    server = StubServer.new({ body: JSON.generate(first) }, { body: JSON.generate(second) })
    output, stderr, = run_cli("logbook", "--all", server: server)
    assert_equal [ 5, 6, 9, 3 ], output["data"].map { |entry| entry["id"] }
    refute_includes stderr, "Older entries"
    assert_equal [ "/logbook.json", "/logbook.json?before=2026-09-30" ], 2.times.map { server.requests.pop[:target] }

    output, _stderr, status = run_cli("logbook", "--before", "2026-09-30", "--all", server: StubServer.new)
    refute status.success?
    assert_match "not both", output["error"]
  end

  def test_tasks_list_status_canceled_reads_the_logbook_without_user
    server = StubServer.new(body: JSON.generate(LOGBOOK))
    output, _stderr, status = run_cli("tasks", "list", "--status", "canceled", "--project", "3", server: server)
    assert status.success?
    assert_equal [ 6 ], output["data"].map { |task| task["id"] }
    assert_equal "/logbook.json", server.requests.pop[:target]

    board = { user: { id: 7 }, areas: [ { id: 1, title: "Work", projects: [ { id: 3, title: "Launch", tasks: [ { id: 9, title: "Old", status: "canceled", project_id: 3 } ] } ] } ] }
    server = StubServer.new(body: JSON.generate(board))
    output, = run_cli("tasks", "list", "--user", "7", "--status", "canceled", server: server)
    assert_equal [ 9 ], output["data"].map { |task| task["id"] }
    assert_equal "/users/7.json", server.requests.pop[:target], "the admin board still has them"
  end

  def test_usage_says_assignee_can_be_an_invited_person
    output, = run_cli("help", server: StubServer.new)
    assert_includes output.dig("data", "usage"), "lands on them when they accept"
  end

  def test_invites_list_returns_the_rows
    invites = [{ "id" => "project-4", "kind" => "project", "project" => { "id" => 150, "title" => "TriGate (internal)" },
                 "inviter" => { "name" => "Ricky" }, "expires_at" => "2026-10-13T19:25:00Z" }]
    server = StubServer.new(body: JSON.generate(invites: invites))
    output, _stderr, status = run_cli("invites", "list", server: server)

    assert status.success?
    assert_equal invites, output["data"]
    request = server.requests.pop
    assert_equal "GET", request[:method]
    assert_equal "/invites.json", request[:target]
  end

  def test_invites_accept_checks_the_id_and_reports_not_found
    server = StubServer.new
    output, _stderr, status = run_cli("invites", "accept", "../users/1", server: server)
    refute status.success?
    assert_equal "INVALID_ARGUMENT", output["code"]
    assert_empty server.requests

    output, = run_cli("invites", "accept", server: StubServer.new)
    assert_equal false, output["ok"]

    server = StubServer.new(status: 404, body: JSON.generate(error: "Not found"))
    output, _stderr, status = run_cli("invites", "accept", "project-4", server: server)
    refute status.success?
    assert_equal "/invites/project-4/accept.json", server.requests.pop[:target]
    assert_equal "HTTP_404", output["code"]
  end

  def test_areas_invite_needs_an_email_and_reports_the_servers_reason
    output, _stderr, status = run_cli("areas", "invite", "52", server: StubServer.new)
    refute status.success?
    assert_equal false, output["ok"]

    server = StubServer.new(status: 403, body: JSON.generate(status: "refused", reason: "Only the area owner can invite people."))
    output, stderr, status = run_cli("areas", "invite", "52", "--email", "x@tap.test", server: server)
    refute status.success?
    assert_equal "Only the area owner can invite people.", output["error"]
    assert_includes stderr, "Only the area owner can invite people."
  end

  def test_board_and_tasks_list_say_when_invites_are_waiting
    board = JSON.generate(user: { id: 1 }, areas: [], open_invites: 4)

    _output, stderr, status = run_cli("board", server: StubServer.new(body: board))
    assert status.success?
    assert_includes stderr, "You have 4 open invites. Run: todos-cli invites list"

    output, stderr, = run_cli("tasks", "list", server: StubServer.new(body: board))
    assert_equal [], output["data"]
    assert_includes stderr, "You have 4 open invites. Run: todos-cli invites list"

    one = JSON.generate(user: { id: 1 }, areas: [], open_invites: 1)
    _output, stderr, = run_cli("board", server: StubServer.new(body: one))
    assert_includes stderr, "You have 1 open invite. Run: todos-cli invites list"

    none = JSON.generate(user: { id: 1 }, areas: [], open_invites: 0)
    _output, stderr, = run_cli("board", server: StubServer.new(body: none))
    refute_match(/invite/, stderr)
  end

  def test_204_is_success_with_null_data
    server = StubServer.new(status: 204, body: "")
    output, _stderr, status = run_cli("tasks", "destroy", "9", "--user", "7", server: server)

    assert status.success?
    assert_equal({ "ok" => true, "data" => nil }, output)
  end

  def test_non_json_html_success_is_an_error_envelope
    server = StubServer.new(status: 200, body: "<html>login</html>", content_type: "text/html")
    output, _stderr, status = run_cli("tasks", "get", "9", server: server)

    refute status.success?
    assert_equal false, output["ok"]
    assert_equal "NON_JSON_RESPONSE", output["code"]
    assert_match(/non-JSON/, output["error"])
  end

  def test_non_json_html_http_error_preserves_http_code
    server = StubServer.new(status: 500, body: "<html>error</html>", content_type: "text/html")
    output, _stderr, status = run_cli("tasks", "get", "9", server: server)

    refute status.success?
    assert_equal false, output["ok"]
    assert_equal "HTTP_500", output["code"]
    assert_match(/non-JSON/, output["error"])
  end

  def test_realpath_bootstrap_works_through_symlink_from_foreign_cwd
    Dir.mktmpdir do |dir|
      link = File.join(dir, "todos-cli")
      foreign_cwd = File.join(dir, "foreign")
      Dir.mkdir(foreign_cwd)
      File.symlink(EXECUTABLE, link)
      board = { user: { id: 1, email: "me@example.com" }, areas: [], tallies: {} }
      server = StubServer.new(body: JSON.generate(board))

      output, _stderr, status = run_cli(
        "me", server: server, cwd: foreign_cwd, executable: link,
        env: { "BUNDLE_GEMFILE" => File.join(foreign_cwd, "Gemfile") }
      )

      assert status.success?
      assert_equal({ "id" => 1, "email" => "me@example.com" }, output["data"])
      assert_equal "/tasks.json", server.requests.pop[:target]
    end
  end

  def test_missing_config_is_still_a_json_failure
    # Empty strings beat the tool .env, which only fills unset variables.
    stdout, _stderr, status = Open3.capture3(
      {
        "TODOS_API_KEY" => "",
        "TODOS_BASE_URL" => "",
        "BUNDLE_GEMFILE" => nil
      },
      EXECUTABLE, "me", chdir: Dir.tmpdir
    )
    output = JSON.parse(stdout)

    refute status.success?
    assert_equal false, output["ok"]
    assert_equal "CONFIG_ERROR", output["code"]
    assert_match(/TODOS_API_KEY/, output["error"])
    assert_match(/TODOS_BASE_URL/, output["error"])
  end

  def test_schema_can_be_loaded_from_file
    Dir.mktmpdir do |dir|
      schema_path = File.join(dir, "schema.json")
      File.write(schema_path, JSON.generate([{ key: "name", label: "Name", type: "text" }]))
      server = StubServer.new({})

      output, = run_cli(
        "tasks", "create", "--user", "7", "--title", "Collect name", "--schema", "@#{schema_path}",
        server: server
      )
      body = json_body(server.requests.pop)

      assert_equal true, output["ok"]
      assert_equal "name", body.dig("task", "fields_schema", 0, "key")
    end
  end

  def test_board_filters_and_project_flattening
    board = {
      user: { id: 7, email: "andy@example.com" },
      areas: [{
        id: 1,
        title: "Operations",
        position: 0,
        active: true,
        projects: [
          { id: 3, title: "Tax", status: "active", tasks: [
            { id: 9, project_id: 3, title: "W-9", status: "open" },
            { id: 10, project_id: 3, title: "EIN", status: "approved" }
          ] }
        ]
      }],
      tallies: { open: 1, approved: 1 }
    }

    server = StubServer.new(body: JSON.generate(board))
    output, = run_cli("tasks", "list", "--project", "3", "--status", "open", server: server)
    assert_equal [9], output["data"].map { |task| task["id"] }
    assert_equal "Operations", output["data"][0]["area_title"]

    server = StubServer.new(body: JSON.generate(board))
    output, = run_cli("projects", "list", "--user", "7", server: server)
    assert_equal "Operations", output["data"][0]["area_title"]
    refute output["data"][0].key?("tasks")
    assert_equal "/users/7.json", server.requests.pop[:target]

    server = StubServer.new(body: JSON.generate(board))
    output, = run_cli("areas", "list", "--user", "7", server: server)
    assert_equal true, output["ok"]
    assert_equal [{
      "id" => 1,
      "title" => "Operations",
      "position" => 0,
      "active" => true,
      "project_count" => 1
    }], output["data"]
    assert_equal "/users/7.json", server.requests.pop[:target]
  end

  def test_webhooks_commands_call_the_owner_routes
    hook = { id: 4, url: "https://hooks.example.com/todo", events: ["task.submitted"], state: "active" }
    cases = [
      [%w[webhooks list], "GET", "/webhooks.json", nil, { webhooks: [hook] }],
      [["webhooks", "create", "--url", "https://hooks.example.com/todo", "--events", "task.submitted, task.approved", "--description", "Pios"],
       "POST", "/webhooks.json",
       { "url" => "https://hooks.example.com/todo", "events" => %w[task.submitted task.approved], "description" => "Pios" },
       hook.merge(secret: "whsec_abc")],
      [%w[webhooks update 4 --events * --active true], "PATCH", "/webhooks/4.json", { "events" => ["*"], "active" => true }, hook],
      [%w[webhooks rotate 4], "POST", "/webhooks/4/rotate.json", nil, hook.merge(secret: "whsec_new")],
      [%w[webhooks test 4], "POST", "/webhooks/4/test.json", nil, { delivery: { id: 1, event_type: "ping" } }],
      [%w[webhooks deliveries 4], "GET", "/webhooks/4/deliveries.json", nil, { webhook: hook, deliveries: [] }]
    ]

    cases.each do |args, method, target, body, reply|
      server = StubServer.new(body: JSON.generate(reply))
      output, stderr = run_cli(*args, server: server)
      request = server.requests.pop

      assert_equal true, output["ok"], args.join(" ")
      assert_equal [method, target], [request[:method], request[:target]], args.join(" ")
      body.nil? ? assert_nil(json_body(request), args.join(" ")) : assert_equal(body, json_body(request), args.join(" "))
      if reply[:secret]
        assert_match(/not shown again/, stderr, args.join(" "))
      else
        refute_match(/not shown again/, stderr, args.join(" "))
      end
    end
  end

  def test_webhooks_list_returns_the_rows_and_delete_is_204
    server = StubServer.new(body: JSON.generate(webhooks: [{ id: 4 }]))
    output, = run_cli("webhooks", "list", server: server)
    assert_equal [{ "id" => 4 }], output["data"]

    server = StubServer.new(status: 204, body: "")
    output, = run_cli("webhooks", "delete", "4", server: server)
    request = server.requests.pop
    assert_equal true, output["ok"]
    assert_nil output["data"]
    assert_equal ["DELETE", "/webhooks/4.json"], [request[:method], request[:target]]
  end

  def test_webhooks_create_needs_a_url_and_reports_the_servers_errors
    server = StubServer.new
    output, _stderr, status = run_cli("webhooks", "create", server: server)
    assert_equal 1, status.exitstatus
    assert_equal "INVALID_ARGUMENT", output["code"]
    assert_equal "--url is required", output["error"]

    server = StubServer.new(status: 422, body: JSON.generate(errors: ["Url must start with https://"]))
    output, _stderr, status = run_cli("webhooks", "create", "--url", "http://x.test/hook", server: server)
    assert_equal 1, status.exitstatus
    assert_equal ["HTTP_422", "Url must start with https://"], [output["code"], output["error"]]

    server = StubServer.new
    output, = run_cli("webhooks", "update", "4", server: server)
    assert_equal "Pass --url, --events, --description, or --active", output["error"]
  end

  def test_usage_lists_webhooks
    server = StubServer.new
    output, = run_cli("help", server: server)
    assert_includes output["data"]["usage"], "todos-cli webhooks create --url URL"
    assert_includes output["data"]["usage"], "X-Todo-Signature"
  end
end
