# frozen_string_literal: true

module Bulletproof
  module Runtime
    # リクエスト中の AR ロード件数・GC 統計を計測し、閾値超過時に RuntimeWarning を生成する
    class RequestMonitor
      Snapshot = Data.define(
        :ar_loads,               # Array<ModelLoadEvent>  モデルごとのロード件数
        :total_records,          # Integer                リクエスト全体の合計レコード数
        :gc_count_delta,         # Integer                GC 実行回数の増分
        :allocated_objects_delta # Integer                生成オブジェクト数の増分
      )

      def initialize(config)
        @config = config
      end

      # ブロックを実行し、[戻り値, Array<RuntimeWarning>] を返す
      def monitor
        gc_before = MemorySampler.gc_snapshot
        result    = nil
        ar_loads  = ModelLoadCollector.collect { result = yield }
        gc_after  = MemorySampler.gc_snapshot

        snapshot = Snapshot.new(
          ar_loads: ar_loads,
          total_records: ar_loads.sum(&:record_count),
          gc_count_delta: gc_after[:count] - gc_before[:count],
          allocated_objects_delta: gc_after[:total_allocated_objects] - gc_before[:total_allocated_objects]
        )

        [result, build_warnings(snapshot)]
      end

      private

      def build_warnings(snapshot)
        warnings = []

        snapshot.ar_loads.each do |event|
          # max_single_load で判定することで find_each のバッチ処理を誤検知しない
          # find_each(batch_size: 100) → max_single_load: 100 → 閾値以下なら警告しない
          # Post.all.to_a (500件)      → max_single_load: 500 → 閾値超えで警告
          next unless event.max_single_load > @config.max_records_per_model

          location_hint = event.caller_location ? "\n  → #{event.caller_location}" : ""
          warnings << RuntimeWarning.new(
            type: :mass_instantiation,
            message: "#{event.model_name} を一度に #{format_count(event.max_single_load)} 件ロードしました" \
                     "（上限: #{format_count(@config.max_records_per_model)} 件）#{location_hint}",
            severity: :warning,
            detail: snapshot
          )
        end

        # find_each / in_batches のバッチ処理は意図的な大量処理なので合計から除外する
        non_batched_loads   = snapshot.ar_loads.reject(&:batched)
        non_batched_total   = non_batched_loads.sum(&:record_count)

        if non_batched_total > @config.max_total_records
          summary = non_batched_loads
                    .map { |e| "#{e.model_name}: #{format_count(e.record_count)}" }
                    .join(", ")
          warnings << RuntimeWarning.new(
            type: :high_total_records,
            message: "リクエスト全体で #{format_count(non_batched_total)} 件のレコードをロードしました" \
                     "（上限: #{format_count(@config.max_total_records)} 件）[#{summary}]",
            severity: :warning,
            detail: snapshot
          )
        end

        if @config.max_gc_runs_per_request && snapshot.gc_count_delta > @config.max_gc_runs_per_request
          warnings << RuntimeWarning.new(
            type: :gc_pressure,
            message: "リクエスト中に GC が #{snapshot.gc_count_delta} 回実行されました" \
                     "（上限: #{@config.max_gc_runs_per_request} 回）",
            severity: :warning,
            detail: snapshot
          )
        end

        warnings
      end

      def format_count(num)
        num.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
      end
    end
  end
end
