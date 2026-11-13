# frozen_string_literal: true

# Test stop (GXB_TEST_NO_REAL_IO, Nov 10): only the allowed reads run; every other command exits 3 before the
# .env file is read and before any network call. Local stub server only; no credentials.
# Run: bundle exec ruby -Itest test/test_stop_test.rb
require_relative "test_helper"
require "fileutils"
require "stringio"
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "todos/cli"

class TestStopTest < Minitest::Test
  STOP = Todos::TestStop
  READS = [
    %w[me], %w[users list], %w[users show 7], %w[board], %w[logbook], %w[events], %w[areas list --user 7],
    %w[projects list], %w[invites list], %w[contexts], %w[inbox list], %w[inbox show 3], %w[tasks list],
    %w[tasks get 5], %w[tasks show 5], %w[tasks check -t X], %w[tasks comments 5], %w[tasks versions 5],
    %w[tasks email 5], %w[tasks links 5], %w[questions list], %w[webhooks list], %w[webhooks deliveries 4],
    %w[contexts list], %w[areas messages 1], %w[projects files 1], %w[projects file-url 1 2], %w[projects messages 1],
    %w[inbox proposals 3], %w[tasks lookup 1,2], %w[notifications list], %w[notifications show 1], %w[search words],
    %w[why], %w[why show], %w[auto-approve list], %w[auto-approve entries], %w[orgs list], %w[orgs show 1],
    %w[orgs members 1], %w[organizations list]
  ].freeze
  NAMED_WRITES = [
    %w[tasks create], %w[tasks update], %w[tasks destroy], %w[tasks submit], %w[tasks approve],
    %w[tasks send-back], %w[tasks star], %w[tasks plan], %w[tasks reopen], %w[tasks cancel], %w[tasks settle],
    %w[tasks block], %w[tasks unblock], %w[tasks remind], %w[tasks respond], %w[tasks comment], %w[tasks ask],
    %w[tasks link], %w[tasks unlink], %w[tasks link-expire], %w[tasks secret], %w[tasks secret-wipe],
    %w[tasks password-pull], %w[users remind], %w[areas create], %w[areas invite], %w[projects create],
    %w[projects invite], %w[invites accept], %w[inbox create], %w[inbox message], %w[inbox process],
    %w[questions answer], %w[questions withdraw], %w[webhooks create], %w[webhooks update], %w[webhooks delete],
    %w[webhooks rotate], %w[webhooks test],
    %w[projects update], %w[projects archive], %w[projects restore], %w[projects upload], %w[projects file-delete],
    %w[projects post], %w[projects message-delete], %w[projects cover-remove], %w[projects invite-resend],
    %w[projects invite-revoke], %w[areas update], %w[areas cover], %w[areas cover-remove], %w[areas post],
    %w[contexts create], %w[contexts update], %w[contexts delete], %w[contexts move], %w[notifications read],
    %w[notifications read-all], %w[tasks act], %w[tasks log], %w[tasks log-all], %w[tasks read], %w[tasks read-all],
    %w[why set], %w[why clear]
  ].freeze

  def on
    { STOP::ENV_NAME => "1" }
  end

  # Every "todos-cli A B" line in the usage text that is not an allowed read is refused: a command added later
  # is refused by default.
  def test_every_usage_command_that_is_not_a_read_is_refused
    pairs = Todos::CLI::USAGE.scan(/^\s+todos-cli ([a-z-]+)(?: ([a-z-]+))?/).map(&:compact).uniq
    assert_operator pairs.length, :>, 40
    pairs.each do |pair|
      read = READS.any? { |r| r.first(pair.length) == pair || r.first(2) == pair }
      assert_equal !read, STOP.refuse?(pair, on), pair.join(" ")
    end
  end

  def test_named_writes_unknown_and_bare_commands_are_refused
    (NAMED_WRITES + [%w[tasks frobnicate], %w[tasks], %w[inbox], %w[webhooks], %w[frobnicate], %w[users]]).each do |args|
      assert STOP.refuse?(args, on), args.join(" ")
    end
  end

  def test_reads_and_help_are_allowed
    (READS + [%w[help], %w[--help], []]).each { |args| refute STOP.refuse?(args, on), args.join(" ") }
  end

  def test_any_non_empty_value_turns_it_on
    %w[1 yes true 0 no false x].each { |v| assert STOP.refuse?(%w[tasks create], { STOP::ENV_NAME => v }), v }
    refute STOP.refuse?(%w[tasks create], { STOP::ENV_NAME => "" })
    refute STOP.refuse?(%w[tasks create], {})
  end

  def test_library_run_refuses_without_building_a_client
    out = StringIO.new
    err = StringIO.new
    original = ENV[STOP::ENV_NAME]
    ENV[STOP::ENV_NAME] = "1"
    client = Object.new
    def client.request(*)
      raise "a request was made"
    end
    status = Todos::CLI.run(%w[tasks create -t X --project 151], client: client, out: out, err: err)
    assert_equal 3, status
    assert_equal({ "ok" => false, "code" => "TEST_NO_REAL_IO" }, JSON.parse(out.string).slice("ok", "code"))
    assert_includes err.string, "TEST STOP"
  ensure
    original.nil? ? ENV.delete(STOP::ENV_NAME) : ENV[STOP::ENV_NAME] = original
  end

  # The real executable: a write exits 3 and the server gets NO request. The stub server answers one request
  # if one comes, so a request would show in server.requests.
  def test_executable_refuses_writes_with_exit_3_and_no_request
    (NAMED_WRITES.first(8) + [%w[tasks create --user christian@gxb.vc --project 151 -t X]]).each do |args|
      server = StubServer.new({ status: 201 })
      stdout, stderr, status = Open3.capture3(cli_env(server).merge(on), EXECUTABLE, *args)
      assert_equal 3, status.exitstatus, args.join(" ")
      assert_equal "TEST_NO_REAL_IO", JSON.parse(stdout)["code"]
      assert_includes stderr, "TEST STOP"
      assert_equal 0, server.requests.size, args.join(" ")
      close_unused(server)
    end
  end

  def test_executable_still_runs_reads_with_the_stop_on
    server = StubServer.new({ status: 200, body: JSON.generate(user: { id: 1 }) })
    data, _stderr, status = run_cli("me", server: server, env: on)
    assert_equal 0, status.exitstatus
    assert_equal true, data["ok"]
    assert_equal 1, server.requests.size
  end

  # The stop comes BEFORE the .env file is read: a copy of the tool with an unreadable .env still exits 3
  # (reading it would fail with a different error).
  def test_refusal_happens_before_the_env_file_is_read
    Dir.mktmpdir do |dir|
      FileUtils.cp(EXECUTABLE, dir)
      FileUtils.cp_r(File.join(TOOL_ROOT, "lib"), dir)
      env_file = File.join(dir, ".env")
      File.write(env_file, "TODOS_API_KEY=never-read\n")
      File.chmod(0o000, env_file)
      stdout, _stderr, status = Open3.capture3({ STOP::ENV_NAME => "1", "TODOS_BASE_URL" => "http://127.0.0.1:9" },
                                               File.join(dir, "todos-cli"), "tasks", "create", "-t", "X")
      assert_equal 3, status.exitstatus
      assert_equal "TEST_NO_REAL_IO", JSON.parse(stdout)["code"]
      # Without the stop the same copy reads .env and fails on it: the test above is meaningful.
      _out, _err, status2 = Open3.capture3({ STOP::ENV_NAME => "" }, File.join(dir, "todos-cli"), "me")
      refute_equal 3, status2.exitstatus
    ensure
      File.chmod(0o600, env_file) if env_file && File.exist?(env_file)
    end
  end

  private

  def close_unused(server)
    server.instance_variable_get(:@server).close
    server.instance_variable_get(:@thread).join(2)
  end

  def cli_env(server)
    { "TODOS_API_KEY" => "test-key", "TODOS_BASE_URL" => server.url, "BUNDLE_GEMFILE" => nil, "RUBYOPT" => nil,
      "RUBYLIB" => nil, "HTTP_PROXY" => nil, "http_proxy" => nil, "HERDR_PANE_ID" => nil, "TODOS_ROUTE" => nil,
      "TODOS_ROUTE_COMMAND" => "/nonexistent/todos-cli-test-route-command", "TODOS_SIMILAR_CHECK" => "0" }
  end
end
