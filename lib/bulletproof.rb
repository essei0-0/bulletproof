# frozen_string_literal: true

require_relative "bulletproof/version"
require_relative "bulletproof/configuration"
require_relative "bulletproof/report"
require_relative "bulletproof/runtime_warning"
require_relative "bulletproof/detectors/excessive_includes_detector"
require_relative "bulletproof/analyzer"
require_relative "bulletproof/railtie" if defined?(Rails::Railtie)
require_relative "bulletproof/runtime/memory_sampler"
require_relative "bulletproof/runtime/callstack_filter"
require_relative "bulletproof/runtime/model_load_event"
require_relative "bulletproof/runtime/model_load_collector"
require_relative "bulletproof/runtime/request_monitor"
require_relative "bulletproof/middleware"

module Bulletproof
  class Error < StandardError; end

  class << self
    def config
      @config ||= Configuration.new
    end

    def configure
      yield config
    end

    # @param path [String] 解析対象のファイルまたはディレクトリ
    # @return [Report]
    def analyze(path)
      Analyzer.new(config).call(path)
    end
  end
end
