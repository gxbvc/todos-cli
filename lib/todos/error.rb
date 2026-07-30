# frozen_string_literal: true

module Todos
  class Error < StandardError
    attr_reader :code

    def initialize(message, code: "ERROR")
      super(message)
      @code = code
    end
  end
end
