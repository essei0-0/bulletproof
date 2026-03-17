# frozen_string_literal: true

module Bulletproof
  class Analyzer
    def initialize(config = Bulletproof.config)
      @config = config
      @detectors = [
        Detectors::ExcessiveIncludesDetector.new(config)
      ]
    end

    # @param path [String] ファイルまたはディレクトリのパス
    # @return [Report]
    def call(path)
      report = Report.new
      ruby_files(path).each do |file|
        source = File.read(file)
        @detectors.each do |detector|
          detector.call(source, file: file).each { |v| report.add_violation(v) }
        end
      end
      report
    end

    private

    def ruby_files(path)
      if File.directory?(path)
        Dir.glob(File.join(path, "**", "*.rb"))
      else
        [path]
      end
    end
  end
end
