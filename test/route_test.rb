# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"

# todo plan 51: tasks create fills `route` with the herdr agent name of the
# pane it runs in; --route NAME and --no-route override; update sets or clears.
# A fake `herdr` on PATH stands in for the real one (no herdr is called).
class RouteTest < Minitest::Test
  AGENTS = {
    "result" => {
      "agents" => [
        { "name" => "overseer", "pane_id" => "w22:p2" },
        { "name" => "cloud", "pane_id" => "w9:p1" },
        { "name" => "Bad Name", "pane_id" => "w9:p7" },
        { "pane_id" => "w9:p8" }
      ]
    }
  }.freeze

  def setup
    @dir = Dir.mktmpdir("todos-cli-route")
    @calls = File.join(@dir, "calls")
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  # A fake herdr that logs each call and prints `output` (or fails).
  def fake_herdr(output: JSON.generate(AGENTS), exit_code: 0, sleep_for: 0)
    payload = File.join(@dir, "agents.json")
    File.write(payload, output)
    script = File.join(@dir, "herdr")
    File.write(script, <<~SH)
      #!/bin/sh
      echo "$@" >> "#{@calls}"
      sleep #{sleep_for}
      cat "#{payload}"
      exit #{exit_code}
    SH
    File.chmod(0o755, script)
    { "PATH" => "#{@dir}:#{ENV.fetch("PATH")}" }
  end

  def herdr_calls
    File.exist?(@calls) ? File.readlines(@calls, chomp: true) : []
  end

  def create(*extra, env:)
    server = StubServer.new({})
    output, stderr, status = run_cli("tasks", "create", "-t", "T", "--project", "3", *extra, server: server, env: env)
    assert_equal 0, status.exitstatus, stderr
    [json_body(server.requests.pop)["task"], stderr]
  end

  def test_create_in_a_pane_sends_that_panes_agent_name
    task, stderr = create(env: fake_herdr.merge("HERDR_PANE_ID" => "w9:p1"))
    assert_equal "cloud", task["route"]
    assert_equal ["agent list"], herdr_calls
    refute_includes stderr, "No route"
  end

  def test_admin_create_sends_the_route_too
    server = StubServer.new({})
    output, stderr, status = run_cli("tasks", "create", "--user", "7", "-t", "T",
                                     server: server, env: fake_herdr.merge("HERDR_PANE_ID" => "w22:p2"))
    assert_equal 0, status.exitstatus, stderr
    assert output["ok"]
    assert_equal "overseer", json_body(server.requests.pop)["task"]["route"]
  end

  def test_route_flag_wins_and_herdr_is_not_asked
    task, = create("--route", "misc", env: fake_herdr.merge("HERDR_PANE_ID" => "w9:p1"))
    assert_equal "misc", task["route"]
    assert_empty herdr_calls
  end

  def test_no_route_sends_none_and_says_nothing
    task, stderr = create("--no-route", env: fake_herdr.merge("HERDR_PANE_ID" => "w9:p1"))
    refute task.key?("route")
    assert_empty herdr_calls
    refute_includes stderr, "No route"
  end

  def test_empty_route_on_create_sends_none
    task, = create("--route", "", env: fake_herdr.merge("HERDR_PANE_ID" => "w9:p1"))
    refute task.key?("route")
    assert_empty herdr_calls
  end

  def test_outside_a_pane_warns_and_sends_none
    task, stderr = create(env: fake_herdr)
    refute task.key?("route")
    assert_empty herdr_calls
    assert_includes stderr, "No route: run inside a herdr pane"
  end

  def test_unknown_pane_or_unnamed_agent_or_bad_name_warns_and_sends_none
    %w[w1:p1 w9:p8 w9:p7].each do |pane|
      task, stderr = create(env: fake_herdr.merge("HERDR_PANE_ID" => pane))
      refute task.key?("route"), pane
      assert_includes stderr, "No route", pane
    end
  end

  def test_herdr_failure_or_garbage_never_fails_the_create
    [
      fake_herdr(exit_code: 1),
      fake_herdr(output: "not json"),
      fake_herdr(output: JSON.generate("result" => { "agents" => "x" }))
    ].each do |env|
      task, stderr = create(env: env.merge("HERDR_PANE_ID" => "w9:p1"))
      refute task.key?("route")
      assert_includes stderr, "No route"
    end
  end

  def test_slow_herdr_is_cut_off
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    task, stderr = create(env: fake_herdr(sleep_for: 20).merge("HERDR_PANE_ID" => "w9:p1"))
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 10
    refute task.key?("route")
    assert_includes stderr, "No route"
  end

  def test_bad_route_and_both_flags_are_refused_before_any_request
    [["--route", "Cloud"], ["--route", "w9:t1"], ["--route", "a" * 41], ["--route", "misc", "--no-route"]].each do |extra|
      server = StubServer.new
      output, _stderr, status = run_cli("tasks", "create", "-t", "T", "--project", "3", *extra, server: server, env: fake_herdr)
      assert_equal 1, status.exitstatus, extra.inspect
      assert_equal "INVALID_ARGUMENT", output["code"]
      assert_equal 0, server.requests.size
    end
  end

  def test_update_sets_or_clears_and_never_asks_herdr
    server = StubServer.new({})
    run_cli("tasks", "update", "11", "--route", "cloud", server: server, env: fake_herdr.merge("HERDR_PANE_ID" => "w22:p2"))
    assert_equal({ "route" => "cloud" }, json_body(server.requests.pop)["task"])

    server = StubServer.new({})
    run_cli("tasks", "update", "11", "--route", "", server: server, env: fake_herdr.merge("HERDR_PANE_ID" => "w22:p2"))
    assert_equal({ "route" => "" }, json_body(server.requests.pop)["task"])

    server = StubServer.new({})
    run_cli("tasks", "update", "11", "--title", "New", server: server, env: fake_herdr.merge("HERDR_PANE_ID" => "w22:p2"))
    refute json_body(server.requests.pop)["task"].key?("route")
    assert_empty herdr_calls
  end

  def test_usage_names_the_flags
    server = StubServer.new
    output, = run_cli("help", server: server)
    usage = output.dig("data", "usage").to_s
    assert_includes usage, "[--route NAME | --no-route]"
    assert_includes usage, "HERDR_PANE_ID"
  end
end
