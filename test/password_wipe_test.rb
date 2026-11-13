# frozen_string_literal: true

require_relative "test_helper"

class PasswordWipeCliTest < Minitest::Test
  def test_wipes_one_password_answer_without_returning_a_value
    server = StubServer.new({ body: JSON.generate(wiped: true, field_key: "qb.pass") })
    output, = run_cli("tasks", "password-wipe", "743", "--key", "qb.pass", server: server)
    request = server.requests.pop
    assert_equal %w[DELETE /tasks/743/passwords/qb.pass], [request[:method], request[:target]]
    assert_equal({ "wiped" => true, "field_key" => "qb.pass" }, output.fetch("data"))
  end

  def test_rejects_non_numeric_id_before_request
    server = StubServer.new
    output, = run_cli("tasks", "password-wipe", "not-an-id", "--key", "qb.pass", server: server)
    assert_equal "INVALID_ARGUMENT", output["code"]
    assert_empty server.requests
  end
end
