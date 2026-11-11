# frozen_string_literal: true

require_relative "test_helper"
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "stringio"
require "tmpdir"
require "todos/cli"

class ProjectCoverTest < Minitest::Test
  def run_cli(server, *args)
    out = StringIO.new
    err = StringIO.new
    client = Todos::Client.new(base_url: server.url, api_key: "test-key")
    status = Todos::CLI.run(args, client: client, out: out, err: err)
    server.finish
    [JSON.parse(out.string), status, server.requests]
  end

  def test_cover_posts_multipart_image
    Dir.mktmpdir do |dir|
      path = File.join(dir, "cover.jpg")
      File.binwrite(path, "\xFF\xD8\xFFfake-jpeg-bytes".b)
      server = StubServer.new(status: 201, body: JSON.generate(cover: { content_type: "image/jpeg" }))
      output, status, requests = run_cli(server, "projects", "cover", "12", path)
      assert_equal 0, status
      assert_equal "image/jpeg", output.dig("data", "cover", "content_type")
      request = requests.pop
      assert_equal ["POST", "/projects/12/cover.json"], request.values_at(:method, :target)
      assert_match %r{multipart/form-data}, request[:headers]["content-type"]
      assert_includes request[:body], %(name="image"; filename="cover.jpg")
    end
  end

  def test_cover_refuses_bad_input_without_a_request
    Dir.mktmpdir do |dir|
      txt = File.join(dir, "notes.txt")
      File.write(txt, "x")
      [["projects", "cover", "abc", txt], ["projects", "cover", "12", File.join(dir, "missing.jpg")], ["projects", "cover", "12", txt]].each do |args|
        server = StubServer.new
        output, status, requests = run_cli(server, *args)
        assert_equal 1, status, args.inspect
        refute_nil output["code"], args.inspect
        assert_empty requests, args.inspect
      end
    end
  end
end
