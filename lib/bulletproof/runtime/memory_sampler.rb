# frozen_string_literal: true

module Bulletproof
  module Runtime
    # GC 統計を計測するユーティリティ
    # RSS 計測はオーバーヘッドと精度の問題があるため採用しない
    module MemorySampler
      # GC 統計のスナップショットを返す（低オーバーヘッド）
      def self.gc_snapshot
        GC.stat.slice(:count, :total_allocated_objects, :heap_allocated_pages)
      end
    end
  end
end
