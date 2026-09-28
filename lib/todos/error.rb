# frozen_string_literal: true

module Todos
  class Error < StandardError
    attr_reader :code, :details

    # details: the parsed JSON error body, when the server sent one. A 422
    # from a create or edit carries { errors, quality }.
    def initialize(message, code: "ERROR", details: nil)
      super(message)
      @code = code
      @details = details.is_a?(Hash) ? details : nil
    end
  end
end
