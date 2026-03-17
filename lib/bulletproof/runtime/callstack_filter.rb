# frozen_string_literal: true

module Bulletproof
  module Runtime
    # コールスタックからアプリケーションコードのフレームを探すユーティリティ
    #
    # gem 内部・bulletproof 自身のフレームを除外し、
    # 最初にヒットしたアプリケーションコードの位置を返す。
    module CallstackFilter
      # 除外するパスのパターン（gem・bulletproof 自身・eval を対象外にする）
      EXCLUDE_PATTERNS = [
        %r{/gems/}, # bundler でインストールされた gem
        %r{lib/bulletproof}, # bulletproof 自身
        /\A\(eval\)/ # eval されたコード
      ].freeze

      # @param locations [Array<Thread::Backtrace::Location>]
      # @return [String, nil]  "path/to/file.rb:42:in 'method_name'" 形式、見つからなければ nil
      def self.app_location(locations)
        frame = locations.find do |loc|
          path = loc.absolute_path || loc.path || ""
          EXCLUDE_PATTERNS.none? { |pattern| path.match?(pattern) }
        end
        frame&.to_s
      end
    end
  end
end
