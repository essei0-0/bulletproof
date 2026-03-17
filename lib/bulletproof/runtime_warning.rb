# frozen_string_literal: true

module Bulletproof
  RuntimeWarning = Data.define(:type, :message, :severity, :detail)
end
