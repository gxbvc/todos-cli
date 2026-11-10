# frozen_string_literal: true

require_relative "test_helper"
require "digest"
require "fileutils"

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
  end

  def test_refused_request_cleans_new_destination_without_printing_value
    server = StubServer.new({ status: 422, body: JSON.generate(error: "already pulled") })
    output, stderr = run_cli("tasks", "password-pull", "743", "--key", "vendor_password",
                             "--name", "vendor-key", "--to", @path, server: server)
    assert_equal "HTTP_422", output["code"]
    refute File.exist?(@path)
    refute_includes JSON.generate(output) + stderr, VALUE
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
