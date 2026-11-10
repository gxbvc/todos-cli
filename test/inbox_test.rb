# frozen_string_literal: true

require_relative "test_helper"
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "stringio"
require "todos/cli"

class InboxTest < Minitest::Test
  def run_inbox(server, *args)
    out = StringIO.new
    err = StringIO.new
    client = Todos::Client.new(base_url: server.url, api_key: "test-key")
    status = Todos::CLI.run(args, client: client, out: out, err: err)
    server.finish
    [JSON.parse(out.string), status, server.requests]
  end

  def test_create_sends_key_identity_without_forged_author
    server = StubServer.new(status: 201, body: JSON.generate(id: "5", title: "First line"))
    output, status, requests = run_inbox(server, "inbox", "create", "First line\nSecond line")
    assert_equal 0, status
    assert_equal({ "id" => "5", "title" => "First line" }, output["data"])
    request = requests.pop
    assert_equal ["POST", "/inbox_threads.json"], request.values_at(:method, :target)
    assert_equal({ "kind" => "text", "body" => "First line\nSecond line" }, json_body(request))
    assert_equal "Bearer test-key", request[:headers]["authorization"]

    Dir.mktmpdir do |dir|
      path = File.join(dir, "capture.md")
      File.write(path, "Meet with Chris\nDiscuss scope\n")
      server = StubServer.new(status: 201)
      output, status, requests = run_inbox(server, "inbox", "create", "@#{path}", "--kind", "meeting",
                                           "--title", "Meeting", "--owner-email", "chris@gxb.vc", "--as", "GXBot")
      assert_equal 0, status
      assert_equal true, output["ok"]
      assert_equal({ "kind" => "meeting", "title" => "Meeting", "body" => "Meet with Chris\nDiscuss scope\n",
                     "owner_email" => "chris@gxb.vc", "agent_name" => "GXBot" }, json_body(requests.pop))
    end
  end

  def test_list_preserves_page_and_passes_cursor_for_next_page
    first = { items: [{ id: "5" }], next_cursor: "eyJvIjoyfQ" }
    server = StubServer.new(body: JSON.generate(first))
    output, status, requests = run_inbox(server, "inbox", "list", "--limit", "1")
    assert_equal 0, status
    assert_equal JSON.parse(JSON.generate(first)), output["data"]
    assert_equal "/inbox_threads.json?limit=1", requests.pop[:target]

    second = { items: [{ id: "4" }], next_cursor: nil }
    server = StubServer.new(body: JSON.generate(second))
    output, status, requests = run_inbox(server, "inbox", "list", "--cursor", first[:next_cursor], "--limit", "1")
    assert_equal 0, status
    assert_equal JSON.parse(JSON.generate(second)), output["data"]
    assert_equal "/inbox_threads.json?cursor=eyJvIjoyfQ&limit=1", requests.pop[:target]
  end

  def test_list_filters_status_and_sorts_by_activity
    %w[needs_processing processed all].each do |filter|
      page = { items: [{ id: "12", status: filter }], next_cursor: nil }
      server = StubServer.new(body: JSON.generate(page))
      output, status, requests = run_inbox(server, "inbox", "list", "--cursor", "next", "--limit", "3",
                                           "--status", filter, "--sort", "activity")
      assert_equal 0, status
      assert_equal JSON.parse(JSON.generate(page)), output["data"]
      request = requests.pop
      assert_equal ["GET", "/inbox_threads.json?cursor=next&limit=3&status=#{filter}&sort=activity"],
                   request.values_at(:method, :target)
    end
  end

  def test_show_and_message_use_bound_thread_routes
    server = StubServer.new(body: JSON.generate(id: "12", messages: [{ body: "First" }]))
    output, status, requests = run_inbox(server, "inbox", "show", "12")
    assert_equal 0, status
    assert_equal "12", output.dig("data", "id")
    assert_equal ["GET", "/inbox_threads/12.json"], requests.pop.values_at(:method, :target)

    server = StubServer.new(status: 201, body: JSON.generate(id: "4", body: "Reply"))
    output, status, requests = run_inbox(server, "inbox", "message", "12", "Reply", "--as", "GXBot")
    assert_equal 0, status
    assert_equal "Reply", output.dig("data", "body")
    request = requests.pop
    assert_equal ["POST", "/inbox_threads/12/messages.json"], request.values_at(:method, :target)
    assert_equal({ "body" => "Reply", "agent_name" => "GXBot" }, json_body(request))

    Dir.mktmpdir do |dir|
      path = File.join(dir, "reply.md")
      File.write(path, "From file\n")
      server = StubServer.new(status: 201)
      _output, status, requests = run_inbox(server, "inbox", "message", "12", "@#{path}")
      assert_equal 0, status
      assert_equal({ "body" => "From file\n" }, json_body(requests.pop))
    end
  end

  def test_process_marks_thread_processed_and_prints_only_processing_fields
    reply = { id: "12", status: "processed", processed_at: "2026-11-10T12:00:00Z", title: "Capture" }
    server = StubServer.new(body: JSON.generate(reply))
    output, status, requests = run_inbox(server, "inbox", "process", "12")
    assert_equal 0, status
    assert_equal({ "id" => "12", "status" => "processed", "processed_at" => "2026-11-10T12:00:00Z" }, output["data"])
    request = requests.pop
    assert_equal ["PATCH", "/inbox_threads/12.json"], request.values_at(:method, :target)
    assert_equal({ "status" => "processed" }, json_body(request))
    assert_equal "application/json", request[:headers]["content-type"]
    assert_equal "Bearer test-key", request[:headers]["authorization"]
  end

  def test_bad_ids_missing_bodies_kinds_and_extra_arguments_never_request
    cases = [
      ["inbox", "show", "../12"], ["inbox", "show", ""], ["inbox", "message", "12/no", "Body"],
      ["inbox", "process", "12/no"], ["inbox", "process"], ["inbox", "process", "12", "Extra"],
      ["inbox", "create"], ["inbox", "create", "  "], ["inbox", "message", "12"],
      ["inbox", "message", "12", "  "], ["inbox", "create", "Body", "--kind", "proposal"],
      ["inbox", "create", "Body", "Extra"], ["inbox", "show", "12", "Extra"],
      ["inbox", "message", "12", "Body", "Extra"], ["inbox", "list", "Extra"],
      ["inbox", "list", "--limit", "0"], ["inbox", "list", "--status", "open"],
      ["inbox", "list", "--status", "done"], ["inbox", "list", "--status", ""],
      ["inbox", "list", "--sort", "priority"], ["inbox", "list", "--sort", ""],
      ["inbox", "create", "@/nonexistent/inbox.md"],
      ["inbox", "create", "Body", "--owner-email", "   "]
    ]
    cases.each do |args|
      server = StubServer.new
      output, status, requests = run_inbox(server, *args)
      assert_equal 1, status, args.inspect
      assert_equal "INVALID_ARGUMENT", output["code"], args.inspect
      assert_empty requests, args.inspect
    end
  end

  def test_server_refusal_is_returned_without_retry_or_identity_change
    server = StubServer.new(status: 422, body: JSON.generate(errors: ["Only an agent may open a thread in someone else's inbox."]))
    output, status, requests = run_inbox(server, "inbox", "create", "Hello", "--owner-email", "other@gxb.vc")
    assert_equal 1, status
    assert_equal "HTTP_422", output["code"]
    assert_match(/Only an agent/, output["error"])
    assert_equal 1, requests.size
    assert_equal({ "kind" => "text", "body" => "Hello", "owner_email" => "other@gxb.vc" }, json_body(requests.pop))
  end

  def test_thread_access_refusal_is_preserved
    server = StubServer.new(status: 404, body: JSON.generate(error: "Not Found"))
    output, status, requests = run_inbox(server, "inbox", "show", "88")
    assert_equal 1, status
    assert_equal "HTTP_404", output["code"]
    assert_equal 1, requests.size

    server = StubServer.new(status: 404, body: JSON.generate(error: "Not Found"))
    output, status, requests = run_inbox(server, "inbox", "message", "88", "Hello")
    assert_equal 1, status
    assert_equal "HTTP_404", output["code"]
    assert_equal 1, requests.size
  end

  def test_process_preserves_owner_refusal
    server = StubServer.new(status: 403, body: JSON.generate(error: "Only the person who owns this inbox thread can change it."))
    output, status, requests = run_inbox(server, "inbox", "process", "88")
    assert_equal 1, status
    assert_equal "HTTP_403", output["code"]
    assert_equal ["PATCH", "/inbox_threads/88.json"], requests.pop.values_at(:method, :target)
  end

  def test_help_lists_inbox_commands_and_scope
    output, status, requests = run_inbox(StubServer.new, "help")
    assert_equal 0, status
    %w[create list show message process].each { |subcommand| assert_includes output.dig("data", "usage"), "inbox #{subcommand}" }
    assert_includes output.dig("data", "usage"), "--status needs_processing|processed|all"
    assert_includes output.dig("data", "usage"), "--sort activity"
    assert_includes output.dig("data", "usage"), "Reply first (inbox message), then inbox process. A later message from a person puts it back in the queue."
    assert_includes output.dig("data", "usage"), "Only an agent key may use"
    assert_empty requests

    output, status, requests = run_inbox(StubServer.new, "inbox", "proposal", "12")
    assert_equal 1, status
    assert_equal "USAGE", output["code"]
    assert_empty requests
  end
end
