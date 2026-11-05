# frozen_string_literal: true

require_relative "test_helper"

# tasks settle N (Overseer, Nov 5): one answered card closes the cards that wait on it.
class SettleTest < Minitest::Test
  SERIAL = { "TODOS_SETTLE_THREADS" => "1" }.freeze

  def card(id, status:, title: "Card #{id}", blocked_by: [], blocking: nil)
    body = { id: id, title: title, status: status, blocked_by: blocked_by.map { |b| { id: b, title: "x", status: "approved" } } }
    body[:blocking] = blocking.map { |b| { id: b, title: "x", status: "open" } } if blocking
    { body: JSON.generate(body) }
  end

  def all_page(*rows, me: 1)
    { body: JSON.generate(user: { id: me }, filter: "all", tasks: rows, total: rows.size, next_offset: nil) }
  end

  def row(id, assigner: 1, status: "open") = { id: id, title: "Card #{id}", status: status, assigner_id: assigner }

  def ok = { body: JSON.generate(id: 0, status: "canceled") }

  def test_closes_my_own_waiting_cards_with_the_reason_and_prints_them
    server = StubServer.new(
      card(10, status: "approved"),
      all_page(row(11), row(12), row(13, assigner: 7), row(14, status: "approved")),
      card(11, status: "open", blocked_by: [ 10 ]),
      card(12, status: "open", blocked_by: [ 99 ]),
      ok
    )
    output, stderr, status = run_cli("tasks", "settle", "10", "--reason", "same proxy answer", server: server, env: SERIAL)
    assert status.success?, stderr
    data = output["data"]
    assert_equal [ 11 ], data["closed"].map { |c| c["id"] }
    assert_equal "Answered on #10: same proxy answer", data["reason"]
    assert_equal 2, data["scanned"], "only my own open cards are read (not 13, someone else's; not 14, approved)"
    assert_includes stderr, "Closed #11: Card 11"
    targets = Array.new(server.requests.size) { server.requests.pop }.map { |r| [ r[:method], r[:target] ] }
    assert_includes targets, [ "PATCH", "/tasks/11/cancel.json" ]
    refute targets.any? { |m, t| m == "PATCH" && t != "/tasks/11/cancel.json" }
  end

  def test_uses_the_blocking_list_when_the_server_sends_one
    server = StubServer.new(
      card(10, status: "submitted", blocking: [ 11, 13 ]),
      all_page(row(11), row(13, assigner: 7)),
      ok
    )
    output, _stderr, status = run_cli("tasks", "settle", "10", server: server, env: SERIAL)
    assert status.success?
    assert_equal [ 11 ], output["data"]["closed"].map { |c| c["id"] }, "13 is not mine and not listed"
    assert_equal "Answered on #10", output["data"]["reason"]
  end

  def test_listed_ids_are_closed_too_and_closed_ones_are_skipped
    server = StubServer.new(
      card(10, status: "approved"),
      card(20, status: "open"),
      ok,
      card(21, status: "canceled")
    )
    output, _stderr, status = run_cli("tasks", "settle", "10", "--ids", "20,21", server: server, env: SERIAL)
    assert status.success?
    assert_equal [ 20 ], output["data"]["closed"].map { |c| c["id"] }
    assert_equal [ { "id" => 21, "title" => "Card 21", "why" => "already canceled" } ], output["data"]["skipped"]
  end

  def test_dry_run_changes_nothing
    server = StubServer.new(
      card(10, status: "approved"),
      all_page(row(11)),
      card(11, status: "open", blocked_by: [ 10 ])
    )
    output, _stderr, status = run_cli("tasks", "settle", "10", "--dry-run", server: server, env: SERIAL)
    assert status.success?
    assert_equal true, output["data"]["dry_run"]
    assert_equal [ 11 ], output["data"]["would_close"].map { |c| c["id"] }
    targets = Array.new(server.requests.size) { server.requests.pop }.map { |r| r[:method] }
    refute_includes targets, "PATCH"
  end

  def test_an_open_card_cannot_settle_anything
    server = StubServer.new(card(10, status: "open"))
    output, _stderr, status = run_cli("tasks", "settle", "10", server: server, env: SERIAL)
    refute status.success?
    assert_match "needs an answered card", output["error"]
  end

  def test_a_refused_cancel_is_reported_not_fatal
    server = StubServer.new(
      card(10, status: "approved"),
      all_page(row(11)),
      card(11, status: "open", blocked_by: [ 10 ]),
      { status: 403, body: JSON.generate(error: "forbidden", message: "Only the reviewer can cancel") }
    )
    output, _stderr, status = run_cli("tasks", "settle", "10", server: server, env: SERIAL)
    assert status.success?
    assert_empty output["data"]["closed"]
    assert_equal 11, output["data"]["skipped"].first["id"]
  end

  def test_ids_must_be_numbers
    server = StubServer.new
    output, _stderr, status = run_cli("tasks", "settle", "10", "--ids", "11,abc", server: server)
    refute status.success?
    assert_match "--ids takes numbers", output["error"]
  end
end
