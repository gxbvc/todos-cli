# frozen_string_literal: true

module Todos
  # Test stop (Nov 10, after a test run made real to-dos #5507 to #5514). When GXB_TEST_NO_REAL_IO has any
  # non-empty value, only the read commands below may run. Every other command, including any command added
  # later, exits 3 before the .env file is read and before any network call. Spec: the Todo manager, Nov 10.
  module TestStop
    ENV_NAME = "GXB_TEST_NO_REAL_IO"
    EXIT_CODE = 3
    CODE = "TEST_NO_REAL_IO"

    # command => allowed subcommands; [nil] means the command takes no subcommand.
    READS = {
      "me" => [nil],
      "users" => %w[list show],
      "board" => [nil],
      "logbook" => [nil],
      "events" => [nil],
      "areas" => %w[list messages],
      "projects" => %w[list files file-url messages],
      "invites" => %w[list],
      "contexts" => [nil, "list"],
      "inbox" => %w[list show proposals],
      "tasks" => %w[list get show check comments versions email links lookup],
      "questions" => %w[list],
      "webhooks" => %w[list deliveries],
      "notifications" => %w[list show],
      "search" => :any,
      "why" => [nil, "show"],
      "auto-approve" => %w[list entries],
      "orgs" => %w[list show members],
      "organizations" => %w[list show members],
      # Usage text only: no key, no network.
      "help" => [nil], "-h" => [nil], "--help" => [nil], nil => [nil]
    }.freeze

    module_function

    def on?(env = ENV)
      !env[ENV_NAME].to_s.empty?
    end

    def allowed?(args)
      command = args[0]
      subs = READS[command]
      return false unless subs
      return true if subs == [nil] || subs == :any

      subs.include?(args[1])
    end

    def refuse?(args, env = ENV)
      on?(env) && !allowed?(args)
    end

    def message(args)
      "TEST STOP: #{ENV_NAME} is set, so todos-cli refuses \"#{args.first(2).join(" ")}\" " \
        "(only read commands may run in tests). Nothing was sent."
    end
  end
end
