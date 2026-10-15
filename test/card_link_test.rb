# frozen_string_literal: true

require_relative "test_helper"

# No-sign-in card links (todo plan 36): tasks link, links, unlink, link-expire.
class CardLinkCliTest < Minitest::Test
  LINK = { id: 7, url: "https://todo.gxb.vc/l#SECRET", expires_at: "2026-10-28T15:00:00Z" }.freeze

  def test_link_makes_one_and_says_the_url_is_shown_once
    server = StubServer.new({ status: 201, body: JSON.generate(LINK) })
    output, stderr = run_cli("tasks", "link", "677", server: server)
    request = server.requests.pop

    assert_equal %w[POST /tasks/677/links.json], [request[:method], request[:target]]
    assert_nil json_body(request)
    assert_equal LINK[:url], output.dig("data", "url")
    assert_match(/Copy data\.url now: it is not shown again/, stderr)
    assert_match(/send it only to them/, stderr)
  end

  def test_link_takes_days
    server = StubServer.new({ status: 201, body: JSON.generate(LINK) })
    run_cli("tasks", "link", "677", "--days", "3", server: server)
    assert_equal({ "expires_in_days" => 3 }, json_body(server.requests.pop))
  end

  def test_link_refuses_days_outside_1_to_30
    %w[0 31 x -2].each do |days|
      server = StubServer.new
      output, = run_cli("tasks", "link", "677", "--days", days, server: server)
      assert_equal "INVALID_ARGUMENT", output["code"], days
      assert_equal "--days takes a whole number from 1 to 30", output["error"]
    end
  end

  def test_link_needs_a_task_id
    server = StubServer.new
    output, = run_cli("tasks", "link", server: server)
    assert_equal "Missing task id", output["error"]
  end

  def test_a_refused_link_shows_the_servers_reason
    server = StubServer.new({ status: 403, body: JSON.generate(error: "Only Ricky Bureau can make or end links to it.") })
    output, _stderr, status = run_cli("tasks", "link", "677", server: server)
    assert_equal 1, status.exitstatus
    assert_equal ["HTTP_403", "Only Ricky Bureau can make or end links to it."], [output["code"], output["error"]]
  end

  def test_links_lists_the_rows
    row = { id: 7, for: "Rita", created_by: "Ricky", expires_at: LINK[:expires_at], revoked_at: nil, last_used_at: nil, uses_count: 0, active: true }
    server = StubServer.new({ body: JSON.generate(links: [row]) })
    output, = run_cli("tasks", "links", "677", server: server)
    request = server.requests.pop

    assert_equal %w[GET /tasks/677/links.json], [request[:method], request[:target]]
    assert_equal [7], output["data"].map { |link| link["id"] }
    refute_includes JSON.generate(output), "url"
  end

  def test_unlink_ends_one
    server = StubServer.new({ body: JSON.generate(id: 7, active: false) })
    output, = run_cli("tasks", "unlink", "677", "7", server: server)
    request = server.requests.pop

    assert_equal %w[DELETE /tasks/677/links/7.json], [request[:method], request[:target]]
    assert_equal false, output.dig("data", "active")
  end

  def test_unlink_needs_both_ids
    server = StubServer.new
    output, = run_cli("tasks", "unlink", "677", server: server)
    assert_equal "Missing link id", output["error"]
  end

  def test_link_expire_sends_the_date_or_time
    [ "2026-10-20", "2026-10-20T15:00:00Z", "2026-10-20T15:00:00-05:00" ].each do |at|
      server = StubServer.new({ body: JSON.generate(id: 7, expires_at: at) })
      run_cli("tasks", "link-expire", "677", "7", "--at", at, server: server)
      request = server.requests.pop

      assert_equal %w[PATCH /tasks/677/links/7.json], [request[:method], request[:target]]
      assert_equal({ "expires_at" => at }, json_body(request))
    end
  end

  def test_link_expire_needs_a_good_at
    server = StubServer.new
    output, = run_cli("tasks", "link-expire", "677", "7", server: server)
    assert_equal "--at is required", output["error"]

    server = StubServer.new
    output, = run_cli("tasks", "link-expire", "677", "7", "--at", "next week", server: server)
    assert_equal "INVALID_ARGUMENT", output["code"]
    assert_match(/--at takes a date/, output["error"])
  end

  def test_the_help_lists_the_link_commands
    server = StubServer.new
    output, = run_cli("help", server: server)
    usage = output["data"]["usage"]

    [ "tasks link <id> [--days N]", "tasks links <id>", "tasks unlink <id> <link_id>", "tasks link-expire <id> <link_id> --at DATE" ].each do |line|
      assert_includes usage, line
    end
    assert_includes usage, "data.url holds the secret and is shown once"
  end
end
