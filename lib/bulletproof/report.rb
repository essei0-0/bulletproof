# frozen_string_literal: true

module Bulletproof
  Violation = Data.define(:file, :line, :message, :severity)

  class Report
    attr_reader :violations

    def initialize
      @violations = []
    end

    def add_violation(violation)
      @violations << violation
      self
    end

    def ok?
      @violations.empty?
    end

    def to_s
      return "No violations found." if ok?

      @violations.map do |v|
        "[#{v.severity.upcase}] #{v.file}:#{v.line} — #{v.message}"
      end.join("\n")
    end
  end
end
