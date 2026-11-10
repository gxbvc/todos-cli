# frozen_string_literal: true

require_relative "test_helper"
require "digest"
require "fileutils"
require "stringio"
$LOAD_PATH.unshift(File.join(TOOL_ROOT, "lib"))
require "todos/cli"

class PasswordPullCliTest < Minitest::Test
  VALUE = "fake-password-pull-only-714".freeze

  def setup
    @dir = Dir.mktmpdir("password-pull-test")
    @path = File.join(@dir, "destination.key")
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_saves_value_to_new_private_file_without_printing_it
    server = StubServer.new({ body: JSON.generate(value: VALUE) })
    output, stderr, status = run_cli("tasks", "password-pull", "743", "--key", "vendor_password",
                                     "--name", "vendor-key", "--to", @path, server: server)
    request = server.requests.pop
    assert status.success?
    assert_equal %w[POST /tasks/743/passwords/vendor_password/pull], [ request[:method], request[:target] ]
    assert_equal({ "name" => "vendor-key" }, json_body(request))
    assert_equal VALUE, File.read(@path)
    assert_equal 0o600, File.stat(@path).mode & 0o777
    assert_empty Dir.glob(File.join(@dir, ".destination.key.pull-*"))
    assert_equal({ "ok" => true, "data" => { "present" => 1, "length" => VALUE.length,
                                               "sha8" => Digest::SHA256.hexdigest(VALUE)[0, 8] } }, output)
    refute_includes JSON.generate(output) + stderr, VALUE
  end

  def test_refuses_existing_destination_before_request
    File.write(@path, "keep this")
    server = StubServer.new
    output, = run_cli("tasks", "password-pull", "743", "--key", "vendor_password",
                      "--name", "vendor-key", "--to", @path, server: server)
    assert_equal "INVALID_ARGUMENT", output["code"]
    assert_equal "keep this", File.read(@path)
    assert server.requests.empty?
    assert_empty Dir.glob(File.join(@dir, ".destination.key.pull-*"))
  end

  def test_refuses_symlink_path_and_symlink_directory_before_request
    alias_path = File.join(@dir, "alias")
    File.symlink("no-such-target", @path)
    server = StubServer.new
    output, = run_cli("tasks", "password-pull", "743", "--key", "vendor_password",
                      "--name", "vendor-key", "--to", @path, server: server)
    assert_equal "INVALID_ARGUMENT", output["code"]
    assert server.requests.empty?
    assert File.symlink?(@path)

    File.symlink(@dir, alias_path)
    destination = File.join(alias_path, "another.key")
    server = StubServer.new
    output, = run_cli("tasks", "password-pull", "743", "--key", "vendor_password",
                      "--name", "vendor-key", "--to", destination, server: server)
    assert_equal "INVALID_ARGUMENT", output["code"]
    assert server.requests.empty?
    refute File.exist?(File.join(@dir, "another.key"))
  end

  def test_refused_request_cleans_new_destination_without_printing_value
    server = StubServer.new({ status: 422, body: JSON.generate(error: "already pulled") })
    output, stderr = run_cli("tasks", "password-pull", "743", "--key", "vendor_password",
                             "--name", "vendor-key", "--to", @path, server: server)
    assert_equal "HTTP_422", output["code"]
    refute File.exist?(@path)
    assert_empty Dir.glob(File.join(@dir, ".destination.key.pull-*"))
    refute_includes JSON.generate(output) + stderr, VALUE
  end

  def test_non_200_or_non_string_reply_cleans_temp
    [ { status: 201, body: JSON.generate(value: VALUE) },
      { body: JSON.generate(value: 42) } ].each do |reply|
      server = StubServer.new(reply)
      output, stderr = run_cli("tasks", "password-pull", "743", "--key", "vendor_password",
                               "--name", "vendor-key", "--to", @path, server: server)
      assert_equal reply[:status] == 201 ? "HTTP_201" : "INVALID_RESPONSE", output["code"]
      refute File.exist?(@path)
      assert_empty Dir.glob(File.join(@dir, ".destination.key.pull-*"))
      refute_includes JSON.generate(output) + stderr, VALUE
    end
  end

  def test_failed_link_keeps_synced_private_temp_with_metadata
    server = StubServer.new({ body: JSON.generate(value: VALUE) })
    output = StringIO.new
    errors = StringIO.new
    checked = false
    File.stub(:link, lambda { |source, destination|
      assert_equal @path, destination
      assert_equal VALUE, File.read(source)
      assert_equal 0o600, File.stat(source).mode & 0o777
      checked = true
      raise Errno::EEXIST
    }) do
      status = Todos::CLI.run([ "tasks", "password-pull", "743", "--key", "vendor_password",
                                "--name", "vendor-key", "--to", @path ],
                              client: Todos::Client.new(base_url: server.url, api_key: "test-key"), out: output, err: errors)
      assert_equal 1, status
    end
    server.finish
    assert checked
    result = JSON.parse(output.string)
    assert_equal false, result["ok"]
    assert_equal "PULL_FILE_KEPT", result["code"]
    assert_equal VALUE.length, result["length"]
    assert_equal Digest::SHA256.hexdigest(VALUE)[0, 8], result["sha8"]
    assert_match(/\.destination\.key\.pull-/, result["kept"])
    assert_equal VALUE, File.read(result["kept"])
    refute File.exist?(@path)
    refute_includes output.string + errors.string, VALUE
  end

  def test_invalid_task_id_and_name_send_nothing
    [ [ VALUE, "vendor-key" ], [ "743", "Bad Name" ] ].each do |id, name|
      server = StubServer.new
      output, stderr = run_cli("tasks", "password-pull", id, "--key", "vendor_password",
                               "--name", name, "--to", @path, server: server)
      assert_equal "INVALID_ARGUMENT", output["code"]
      assert server.requests.empty?
      refute File.exist?(@path)
      refute_includes JSON.generate(output) + stderr, VALUE
    end
  end
end
