# frozen_string_literal: true

require_relative "test_helper"

# One card per topic and no cancel without a reason (Overseer, Nov 5).
class SimilarCardTest < Minitest::Test
  ON = { "TODOS_SIMILAR_CHECK" => "1" }.freeze

  def board(*titles)
    JSON.generate(user: { id: 1, email: "owner@example.test" }, filter: "waiting_on_me",
                  tasks: titles.each_with_index.map { |t, i| { id: 100 + i, title: t, status: "open" } })
  end

  def created
    { status: 201, body: JSON.generate(id: 200, title: "x", status: "open") }
  end

  def test_create_warns_about_a_similar_open_card_and_still_creates
    server = StubServer.new({ body: board("Approve the two-step sign-in email to 17 Bailey staff", "Pay the invoice") }, created)
    output, stderr, status = run_cli("tasks", "create", "-t", "Approve the final two-step sign-in email to 17 Bailey staff",
                                     "--project", "3", server: server, env: ON)
    assert status.success?
    assert_equal 200, output.dig("data", "id")
    assert_includes stderr, "SIMILAR OPEN CARD #100: Approve the two-step sign-in email to 17 Bailey staff"
    refute_includes stderr, "#101"
    assert_includes stderr, "--new-topic"
    first = server.requests.pop
    assert_equal [ "GET", "/tasks.json?filter=waiting_on_me" ], [ first[:method], first[:target] ]
    assert_equal "POST", server.requests.pop[:method]
  end

  def test_a_different_topic_prints_nothing
    server = StubServer.new({ body: board("Pick where to store fire incident data", "Upload the W-9") }, created)
    _output, stderr, status = run_cli("tasks", "create", "-t", "Approve the email to Erik with two test pages",
                                      "--project", "3", server: server, env: ON)
    assert status.success?
    refute_includes stderr, "SIMILAR OPEN CARD"
  end

  def test_the_same_words_with_a_tag_prefix_match
    server = StubServer.new({ body: board("[ASC] Pick the daily spend cap for the fee page AI reader") }, created)
    _output, stderr, = run_cli("tasks", "create", "-t", "Pick the daily spend cap for the fee page AI reader",
                               "--project", "3", server: server, env: ON)
    assert_includes stderr, "SIMILAR OPEN CARD #100"
  end

  def test_a_card_for_someone_else_is_not_checked_against_my_list
    server = StubServer.new({ body: board("Upload the W-9") }, created)
    _output, stderr, status = run_cli("tasks", "create", "-t", "Upload the W-9", "--project", "3",
                                      "--assignee", "pat@partner.test", server: server, env: ON)
    assert status.success?
    refute_includes stderr, "SIMILAR OPEN CARD"
  end

  def test_assignee_me_is_checked
    server = StubServer.new({ body: board("Upload the W-9 for the bank") }, created)
    _output, stderr, = run_cli("tasks", "create", "-t", "Upload the W-9 for the bank", "--project", "3",
                               "--assignee", "Owner@Example.test", server: server, env: ON)
    assert_includes stderr, "SIMILAR OPEN CARD #100"
  end

  def test_new_topic_skips_the_read
    server = StubServer.new(created)
    _output, stderr, status = run_cli("tasks", "create", "-t", "Upload the W-9", "--project", "3", "--new-topic",
                                      server: server, env: ON)
    assert status.success?
    assert_equal "POST", server.requests.pop[:method]
    assert server.requests.empty?
    refute_includes stderr, "SIMILAR"
  end

  def test_a_failed_read_never_blocks_the_create
    server = StubServer.new({ status: 500, body: JSON.generate(error: "boom") }, created)
    output, stderr, status = run_cli("tasks", "create", "-t", "Upload the W-9", "--project", "3", server: server, env: ON)
    assert status.success?
    assert_equal 200, output.dig("data", "id")
    assert_includes stderr, "Similar-card check skipped"
  end

  def test_cancel_without_a_reason_is_refused_and_sends_nothing
    server = StubServer.new
    output, _stderr, status = run_cli("tasks", "cancel", "9", server: server)
    refute status.success?
    assert_match "--reason", output["error"]
    assert server.requests.empty?
  end

  def test_cancel_with_a_blank_reason_is_refused
    server = StubServer.new
    output, _stderr, status = run_cli("tasks", "cancel", "9", "--reason", "   ", server: server)
    refute status.success?
    assert_match "--reason", output["error"]
  end
end
