# frozen_string_literal: true

require_relative "test_helper"
require "fileutils"

# todo plan 51: tasks create fills `route` from TODOS_ROUTE, else from the
# route command (TODOS_ROUTE_COMMAND, default herdr-whoami), which prints one
# line "<agent> <workspace>". todos-cli itself never calls herdr. --route NAME
# and --no-route override; update sets or clears. A fake command stands in.
class RouteTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("todos-cli-route")
    @calls = File.join(@dir, "calls")
    # A fake herdr on PATH that only logs: todos-cli must never call it.
    herdr = File.join(@dir, "herdr")
    File.write(herdr, "#!/bin/sh\necho herdr \"$@\" >> \"#{@calls}\"\n")
    File.chmod(0o755, herdr)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  # A fake route command that logs each call (with its arguments) and prints
  # `output` (or fails, or hangs).
  def route_command(output: "cloud todo\n", exit_code: 0, sleep_for: 0, name: "whoami")
    payload = File.join(@dir, "#{name}.out")
    File.binwrite(payload, output)
    script = File.join(@dir, name)
    File.write(script, "#!/bin/sh\necho \"#{name} $#\" >> \"#{@calls}\"\nsleep #{sleep_for}\ncat \"#{payload}\"\nexit #{exit_code}\n")
    File.chmod(0o755, script)
    { "PATH" => "#{@dir}:#{ENV.fetch("PATH")}", "TODOS_ROUTE_COMMAND" => script }
  end

  def calls
    File.exist?(@calls) ? File.readlines(@calls, chomp: true) : []
  end

  def create(*extra, env:)
    server = StubServer.new({})
    output, stderr, status = run_cli("tasks", "create", "-t", "T", "--project", "3", *extra, server: server, env: env)
    assert_equal 0, status.exitstatus, stderr
    assert output["ok"]
    [json_body(server.requests.pop)["task"], stderr]
  end

  def test_the_route_command_gives_the_agent_name
    task, stderr = create(env: route_command)
    assert_equal "cloud", task["route"]
    refute task.key?("route_workspace"), "the workspace waits for the server column"
    assert_equal ["whoami 0"], calls, "run once, with no arguments, and herdr never"
    refute_includes stderr, "No route"
  end

  def test_admin_create_sends_the_route_too
    server = StubServer.new({})
    _output, stderr, status = run_cli("tasks", "create", "--user", "7", "-t", "T", server: server, env: route_command)
    assert_equal 0, status.exitstatus, stderr
    assert_equal "cloud", json_body(server.requests.pop)["task"]["route"]
  end

  def test_todos_route_wins_and_the_command_is_not_run
    task, = create(env: route_command.merge("TODOS_ROUTE" => "misc"))
    assert_equal "misc", task["route"]
    assert_empty calls
  end

  def test_a_bad_todos_route_is_no_route_with_the_warning
    task, stderr = create(env: route_command.merge("TODOS_ROUTE" => "Misc"))
    refute task.key?("route")
    assert_includes stderr, "No route"
    assert_empty calls, "a set TODOS_ROUTE is the answer, good or bad"
  end

  def test_route_flag_wins_and_nothing_is_run
    task, = create("--route", "misc", env: route_command)
    assert_equal "misc", task["route"]
    assert_empty calls
  end

  def test_no_route_sends_none_and_says_nothing
    task, stderr = create("--no-route", env: route_command)
    refute task.key?("route")
    assert_empty calls
    refute_includes stderr, "No route"
  end

  def test_empty_route_on_create_sends_none
    task, = create("--route", "", env: route_command)
    refute task.key?("route")
    assert_empty calls
  end

  def test_empty_output_outside_a_pane_warns_and_sends_none
    task, stderr = create(env: route_command(output: ""))
    refute task.key?("route")
    assert_includes stderr, "No route: run inside a herdr pane"
  end

  def test_any_odd_line_is_no_route
    ["cloud\n", "cloud todo extra\n", "Cloud todo\n", "cloud Todo\n", "cloud todo\nmore\n", "w2W:t1 todo\n",
     "#{"a" * 41} todo\n", "cloud;rm todo\n", "x" * 300].each do |output|
      task, stderr = create(env: route_command(output: output))
      refute task.key?("route"), output.inspect
      assert_includes stderr, "No route", output.inspect
    end
  end

  def test_a_failing_missing_or_slow_command_never_fails_the_create
    [route_command(exit_code: 1), { "TODOS_ROUTE_COMMAND" => File.join(@dir, "missing") }].each do |env|
      task, stderr = create(env: env)
      refute task.key?("route")
      assert_includes stderr, "No route"
    end

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    task, stderr = create(env: route_command(sleep_for: 20))
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 10
    refute task.key?("route")
    assert_includes stderr, "No route"
  end

  def test_the_command_is_run_without_a_shell
    marker = File.join(@dir, "pwned")
    task, = create(env: { "TODOS_ROUTE_COMMAND" => "touch #{marker}" })
    refute task.key?("route")
    refute File.exist?(marker), "TODOS_ROUTE_COMMAND is one program, never shell text"
  end

  def test_bad_route_and_both_flags_are_refused_before_any_request
    [["--route", "Cloud"], ["--route", "w9:t1"], ["--route", "a" * 41], ["--route", "misc", "--no-route"]].each do |extra|
      server = StubServer.new
      output, _stderr, status = run_cli("tasks", "create", "-t", "T", "--project", "3", *extra, server: server, env: route_command)
      assert_equal 1, status.exitstatus, extra.inspect
      assert_equal "INVALID_ARGUMENT", output["code"]
      assert_equal 0, server.requests.size
    end
  end

  def test_update_sets_or_clears_and_never_runs_the_command
    server = StubServer.new({})
    run_cli("tasks", "update", "11", "--route", "cloud", server: server, env: route_command)
    assert_equal({ "route" => "cloud" }, json_body(server.requests.pop)["task"])

    server = StubServer.new({})
    run_cli("tasks", "update", "11", "--route", "", server: server, env: route_command)
    assert_equal({ "route" => "" }, json_body(server.requests.pop)["task"])

    server = StubServer.new({})
    run_cli("tasks", "update", "11", "--title", "New", server: server, env: route_command)
    refute json_body(server.requests.pop)["task"].key?("route")
    assert_empty calls
  end

  def test_usage_names_the_flags_and_the_command
    output, = run_cli("help", server: StubServer.new)
    usage = output.dig("data", "usage").to_s
    assert_includes usage, "[--route NAME | --no-route]"
    assert_includes usage, "TODOS_ROUTE_COMMAND"
    refute_includes usage, "HERDR_PANE_ID"
  end
end
