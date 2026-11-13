# frozen_string_literal: true

require_relative "test_helper"
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "stringio"
require "tmpdir"
require "todos/cli"

# The commands for the API routes added after plan 54 (lib/todos/api_commands.rb): each sends the
# documented method, path, and body, and bad input fails before any request.
class ApiCommandsTest < Minitest::Test
  def call(server, *args)
    out = StringIO.new
    err = StringIO.new
    client = Todos::Client.new(base_url: server.url, api_key: "test-key")
    status = Todos::CLI.run(args, client: client, out: out, err: err)
    server.finish
    requests = []
    requests << server.requests.pop until server.requests.empty?
    [JSON.parse(out.string), status, requests, err.string]
  end

  def sent(*args, response: {})
    output, status, requests, err = call(StubServer.new(response), *args)
    assert_equal 0, status, "#{args.inspect}: #{output.inspect}"
    request = requests.fetch(0)
    [request[:method], request[:target], request[:body].empty? ? nil : (JSON.parse(request[:body]) rescue request[:body]), output, err]
  end

  def test_project_update_sends_the_details_and_clears_with_empty
    method, target, body = sent("projects", "update", "428", "--emoji", "x", "--done-when", "It ships", "--manager-agent", "admin")
    assert_equal ["PATCH", "/projects/428.json"], [method, target]
    assert_equal({ "project" => { "emoji" => "x", "done_when" => "It ships", "manager_agent" => "admin" } }, body)

    _, _, body = sent("projects", "update", "428", "--done-when", "")
    assert_equal({ "project" => { "done_when" => nil } }, body)
  end

  def test_project_update_reads_done_when_from_a_file_and_prints_server_warnings
    Dir.mktmpdir do |dir|
      path = File.join(dir, "done.md")
      File.write(path, "All three machines")
      _, _, body, _, err = sent("projects", "update", "4", "--done-when", "@#{path}", "--manager-agent", "x",
                                response: { body: JSON.generate(id: 4, warnings: ["manager_agent ignored"]) })
      assert_equal "All three machines", body.dig("project", "done_when")
      assert_includes err, "Warning: manager_agent ignored"
    end
  end

  def test_area_update_and_cover_remove
    method, target, body = sent("areas", "update", "108", "--standard", "Agents that ship")
    assert_equal ["PATCH", "/areas/108.json", { "area" => { "standard" => "Agents that ship" } }], [method, target, body]
    assert_equal ["DELETE", "/areas/108/cover.json"], sent("areas", "cover-remove", "108").first(2)
    assert_equal ["DELETE", "/projects/9/cover.json"], sent("projects", "cover-remove", "9").first(2)
  end

  def test_area_cover_uploads_an_image
    Dir.mktmpdir do |dir|
      path = File.join(dir, "c.png")
      File.binwrite(path, "\x89PNG fake".b)
      output, status, requests = call(StubServer.new({ status: 201, body: "{}" }), "areas", "cover", "108", path)
      assert_equal 0, status, output.inspect
      assert_equal ["POST", "/areas/108/cover.json"], requests[0].values_at(:method, :target)
      assert_includes requests[0][:body], %(name="image"; filename="c.png")
    end
  end

  def test_archive_and_restore_need_confirm
    output, status, requests = call(StubServer.new, "projects", "archive", "12")
    assert_equal [1, "CONFIRM_REQUIRED"], [status, output["code"]]
    assert_empty requests
    assert_equal ["POST", "/projects/12/archive.json"], sent("projects", "archive", "12", "--confirm").first(2)
    assert_equal ["DELETE", "/projects/12/archive.json"], sent("projects", "restore", "12", "--confirm").first(2)
  end

  def test_project_files
    assert_equal ["GET", "/projects/5/files.json"], sent("projects", "files", "5").first(2)
    assert_equal ["GET", "/projects/5/files/7.json"], sent("projects", "file-url", "5", "7").first(2)
    assert_equal ["DELETE", "/projects/5/files/7.json"], sent("projects", "file-delete", "5", "7").first(2)
    Dir.mktmpdir do |dir|
      a = File.join(dir, "a.txt")
      b = File.join(dir, "b.pdf")
      File.write(a, "a")
      File.write(b, "b")
      output, status, requests = call(StubServer.new({ status: 201, body: "{}" }), "projects", "upload", "5", a, b)
      assert_equal 0, status, output.inspect
      assert_equal ["POST", "/projects/5/files.json"], requests[0].values_at(:method, :target)
      assert_includes requests[0][:body], %(name="files[]"; filename="a.txt")
      assert_includes requests[0][:body], %(name="files[]"; filename="b.pdf")

      output, status, requests = call(StubServer.new, "projects", "upload", "5", File.join(dir, "missing"))
      assert_equal 1, status
      assert_empty requests
    end
  end

  def test_project_invite_resend_and_revoke
    assert_equal ["PATCH", "/projects/3/invites/8.json"], sent("projects", "invite-resend", "3", "8").first(2)
    assert_equal ["DELETE", "/projects/3/invites/8.json"], sent("projects", "invite-revoke", "3", "8").first(2)
  end

  def test_chat_on_projects_and_areas
    method, target = sent("projects", "messages", "428", "--order", "desc", "--limit", "5")
    assert_equal "GET", method
    assert_equal "/projects/428/messages.json", target.split("?").first
    assert_includes target, "order=desc"
    assert_includes target, "limit=5"
    method, target, body = sent("areas", "post", "108", "Hello", "--as", "Misc")
    assert_equal ["POST", "/areas/108/messages.json", { "body" => "Hello", "agent_name" => "Misc" }], [method, target, body]
    assert_equal ["DELETE", "/projects/428/messages/3.json"], sent("projects", "message-delete", "428", "3").first(2)
  end

  def test_contexts_crud_and_list_without_a_subcommand
    assert_equal ["GET", "/contexts.json"], sent("contexts", response: { body: JSON.generate(contexts: []) }).first(2)
    method, target, body = sent("contexts", "create", "garage", "--description", "In the garage")
    assert_equal ["POST", "/contexts.json", { "name" => "garage", "description" => "In the garage" }], [method, target, body]
    _, target, body = sent("contexts", "update", "7", "--name", "shop")
    assert_equal ["/contexts/7.json", { "name" => "shop" }], [target, body]
    assert_equal ["DELETE", "/contexts/7.json"], sent("contexts", "delete", "7").first(2)
    assert_equal ["PATCH", "/contexts/7/move.json", { "direction" => "up" }], sent("contexts", "move", "7", "up").first(3)
  end

  def test_notifications_and_read_marks
    assert_equal ["GET", "/notifications.json"], sent("notifications", "list").first(2)
    assert_equal ["PATCH", "/notifications/4.json", { "read" => false }], sent("notifications", "read", "4", "--unread").first(3)
    assert_equal ["POST", "/notification_reads.json", { "project_id" => 9 }], sent("notifications", "read-all", "--project", "9").first(3)
    assert_equal ["POST", "/task_reads.json", { "task_id" => 5, "through_comment_id" => 6 }], sent("tasks", "read", "5", "--through-comment", "6").first(3)
    assert_equal ["POST", "/task_reads.json", { "area_id" => 2 }], sent("tasks", "read-all", "--area", "2").first(3)

    output, status, requests = call(StubServer.new, "tasks", "read-all", "--area", "2", "--project", "3")
    assert_equal 1, status, output.inspect
    assert_empty requests
  end

  def test_task_verbs
    method, target, body = sent("tasks", "act", "5", "choose", "--option", "UPS")
    assert_equal ["POST", "/tasks/5/act.json", { "verb" => "choose", "option" => "UPS" }], [method, target, body]
    _, _, body = sent("tasks", "act", "5", "send", "--field", "name=Ada")
    assert_equal({ "verb" => "send", "response" => { "name" => "Ada" } }, body)
    assert_equal ["PATCH", "/tasks/5/log.json"], sent("tasks", "log", "5").first(2)
    assert_equal ["PATCH", "/tasks/log_all.json"], sent("tasks", "log-all").first(2)
    _, target = sent("tasks", "lookup", "5933,5937")
    assert_equal "/lists.json?ids=5933%2C5937", target

    output, status, requests = call(StubServer.new, "tasks", "act", "5", "explode")
    assert_equal 1, status, output.inspect
    assert_empty requests
  end

  def test_search_why_proposals_auto_approve_and_orgs
    _, target = sent("search", "rpi trust", "--sort", "updated_at", "--direction", "asc")
    assert_equal "/search.json", target.split("?").first
    assert_includes target, "q=rpi+trust"
    assert_includes target, "sort=updated_at"
    assert_equal ["GET", "/why.json"], sent("why").first(2)
    assert_equal ["PATCH", "/why.json", { "why" => "Ship" }], sent("why", "set", "Ship").first(3)
    assert_equal ["PATCH", "/why.json", { "why" => nil }], sent("why", "clear").first(3)
    assert_equal ["GET", "/inbox_threads/35/proposals.json"], sent("inbox", "proposals", "35").first(2)
    assert_equal ["GET", "/auto_approve_rules.json"], sent("auto-approve", "list").first(2)
    assert_equal ["GET", "/auto_approve_entries.json"], sent("auto-approve", "entries").first(2)
    assert_equal ["GET", "/auto_approve_rules/3/entries.json"], sent("auto-approve", "entries", "3").first(2)
    assert_equal ["GET", "/organizations.json"], sent("orgs", "list").first(2)
    assert_equal ["GET", "/organizations/1/members.json"], sent("organizations", "members", "1").first(2)
  end

  def test_test_stop_allows_the_new_reads_only
    reads = [%w[search x], %w[why], %w[contexts list], %w[notifications list], %w[orgs list], %w[projects files 1], %w[tasks lookup 1]]
    writes = [%w[why set x], %w[contexts create x], %w[projects update 1], %w[tasks act 1 done], %w[notifications read 1]]
    reads.each { |args| assert Todos::TestStop.allowed?(args), args.inspect }
    writes.each { |args| refute Todos::TestStop.allowed?(args), args.inspect }
  end
end
