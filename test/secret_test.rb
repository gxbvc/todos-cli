# frozen_string_literal: true

require_relative "test_helper"
require "digest"
require "fileutils"

# A secret for the doer (todo plan 40): tasks secret and tasks secret-wipe.
# The value comes from a 0600 file or stdin, is never an argument, and is
# never printed: only its length and sha8. Made-up values only.
class SecretCliTest < Minitest::Test
  FAKE = "made-up-value-for-tests-only"
  REPLY = { secret: { key: "qb.pass", label: "QuickBooks", set: true, expires_at: "2026-11-04T12:00:00Z",
                      revealed_at: nil, received_at: nil, wiped_at: nil } }.freeze

  def setup
    @dir = Dir.mktmpdir("todos-secret-test")
    File.chmod(0o700, @dir)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def secret_file(content = "#{FAKE}\n", mode: 0o600)
    path = File.join(@dir, "value.txt")
    File.write(path, content)
    File.chmod(mode, path)
    path
  end

  def test_sets_from_a_file_prints_only_length_and_sha8_and_deletes_the_file
    path = secret_file
    server = StubServer.new({ body: JSON.generate(REPLY) })
    output, stderr = run_cli("tasks", "secret", "677", "--key", "qb.pass", "--secret-file", path, "--days", "3", server: server)
    request = server.requests.pop

    assert_equal %w[PUT /tasks/677/secrets/qb.pass], [request[:method], request[:target]]
    assert_equal({ "secret" => FAKE, "expires_in_days" => 3 }, json_body(request))
    data = output["data"]
    assert_equal [677, "qb.pass", FAKE.length, Digest::SHA256.hexdigest(FAKE)[0, 8], true],
                 [data["task_id"], data["key"], data["length"], data["sha8"], data["file_deleted"]]
    assert_equal "qb.pass", data.dig("secret", "key")
    refute_includes JSON.generate(output), FAKE
    refute_includes stderr, FAKE
    refute File.exist?(path), "the file is deleted after the server holds the value"
  end

  def test_keep_file_keeps_it
    path = secret_file
    server = StubServer.new({ body: JSON.generate(REPLY) })
    output, = run_cli("tasks", "secret", "677", "--key", "k", "--secret-file", path, "--keep-file", server: server)
    assert_equal false, output.dig("data", "file_deleted")
    assert File.exist?(path)
  end

  def test_sets_from_stdin
    server = StubServer.new({ body: JSON.generate(REPLY) })
    output, = run_cli("tasks", "secret", "677", "--key", "k", "--secret-stdin", server: server, stdin: "#{FAKE}\n")
    assert_equal({ "secret" => FAKE }, json_body(server.requests.pop))
    refute_includes JSON.generate(output), FAKE
  end

  def test_refuses_a_file_others_can_read_and_sends_nothing
    path = secret_file(mode: 0o644)
    server = StubServer.new
    output, stderr = run_cli("tasks", "secret", "677", "--key", "k", "--secret-file", path, server: server)
    assert_equal "--secret-file must be readable by you only (chmod 600)", output["error"]
    assert server.requests.empty?
    refute_includes stderr, FAKE
    assert File.exist?(path), "a refused file is not deleted"
  end

  def test_refuses_a_link
    target = secret_file
    link = File.join(@dir, "link.txt")
    File.symlink(target, link)
    server = StubServer.new
    output, = run_cli("tasks", "secret", "677", "--key", "k", "--secret-file", link, server: server)
    assert_equal "--secret-file must be a regular file, not a link", output["error"]
    assert server.requests.empty?
  end

  def test_a_value_typed_as_an_argument_is_never_echoed
    [["tasks", "secret", "677", "--key", "k", FAKE],
     ["tasks", "secret", "677", "--key", "k", "--secret=#{FAKE}"],
     ["tasks", "secret", "677", "--key", "k", "--value", FAKE]].each do |args|
      server = StubServer.new
      output, stderr = run_cli(*args, server: server)
      assert_equal "INVALID_ARGUMENT", output["code"], args.inspect
      refute_includes JSON.generate(output), FAKE, args.inspect
      refute_includes stderr, FAKE, args.inspect
      assert server.requests.empty?
    end
  end

  def test_a_value_typed_where_the_id_goes_sends_nothing_and_is_never_echoed
    path = secret_file
    [["tasks", "secret", FAKE, "--key", "k", "--secret-file", path],
     ["tasks", "secret", "12#{FAKE}", "--key", "k", "--secret-stdin"],
     ["tasks", "secret-wipe", FAKE, "--key", "k"],
     ["tasks", "secret"]].each do |args|
      server = StubServer.new
      output, stderr = run_cli(*args, server: server, stdin: FAKE)
      assert_equal "INVALID_ARGUMENT", output["code"], args.inspect
      assert_match(/digits only/, output["error"])
      refute_includes JSON.generate(output), FAKE, args.inspect
      refute_includes stderr, FAKE, args.inspect
      assert server.requests.empty?, args.inspect
    end
    assert File.exist?(path), "the file is not read or deleted"
  end

  def test_needs_a_source_and_a_key
    server = StubServer.new
    output, = run_cli("tasks", "secret", "677", "--key", "k", server: server)
    assert_match(/--secret-file PATH or --secret-stdin/, output["error"])
    output, = run_cli("tasks", "secret", "677", "--secret-stdin", server: StubServer.new, stdin: FAKE)
    assert_equal "--key is required", output["error"]
    output, = run_cli("tasks", "secret", "677", "--key", "a/b", "--secret-stdin", server: StubServer.new, stdin: FAKE)
    assert_equal "--key may not contain a /", output["error"]
  end

  def test_refuses_an_empty_value
    server = StubServer.new
    output, = run_cli("tasks", "secret", "677", "--key", "k", "--secret-stdin", server: server, stdin: "  \n")
    assert_equal "The secret is empty", output["error"]
  end

  def test_a_refused_set_keeps_the_file_and_shows_the_servers_reason
    path = secret_file
    server = StubServer.new({ status: 403, body: JSON.generate(error: "This API key may not set secrets. The admin allows it on todo.gxb.vc, Settings.") })
    output, stderr, status = run_cli("tasks", "secret", "677", "--key", "k", "--secret-file", path, server: server)
    assert_equal 1, status.exitstatus
    assert_equal "HTTP_403", output["code"]
    assert File.exist?(path), "the file stays when the server did not keep the value"
    refute_includes stderr, FAKE
  end

  def test_wipe
    server = StubServer.new({ body: JSON.generate(secret: REPLY[:secret].merge(set: false, wiped_at: "2026-10-28T12:00:00Z")) })
    output, = run_cli("tasks", "secret-wipe", "677", "--key", "qb.pass", server: server)
    request = server.requests.pop
    assert_equal %w[DELETE /tasks/677/secrets/qb.pass], [request[:method], request[:target]]
    assert_equal false, output.dig("data", "secret", "set")
  end
end
