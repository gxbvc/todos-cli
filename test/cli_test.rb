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
        args: %w[tasks update 9 --user 7 --title Revised --project 4 --description <p>New</p> --due 2026-09-01 --estimate 30 --source-url https://tickets.gxb.vc/456 --schema] +
          [JSON.generate(schema)] + %w[--field ein=12-345 --notes Ready],
        method: "PATCH",
        target: "/users/7/tasks/9.json",
        body: {
          "task" => {
            "title" => "Revised", "project_id" => "4", "description" => "<p>New</p>",
            "due_date" => "2026-09-01", "estimated_minutes" => 30,
            "source_url" => "https://tickets.gxb.vc/456", "fields_schema" => schema
          },
          "response" => { "ein" => "12-345" },
          "notes" => "Ready"
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
        args: %w[tasks respond 9 --user 7 --field ein=12-345 --field name=Jane --notes Done],
        method: "PATCH",
        target: "/users/7/tasks/9.json",
        body: { "response" => { "ein" => "12-345", "name" => "Jane" }, "notes" => "Done" }
      },
      {
        args: %w[tasks respond 9 --field ein=12-345 --notes Done],
        method: "PATCH",
        target: "/tasks/9.json",
        body: { "response" => { "ein" => "12-345" }, "notes" => "Done" }
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
end
