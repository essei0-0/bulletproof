# frozen_string_literal: true

module Bulletproof
  module Runtime
    # リクエスト中に ActiveRecord の instantiation.active_record イベントを購読し、
    # モデルごとのロード件数とロード発生箇所を集計する。
    #
    # スレッドローカル変数を使うため、Puma 等のマルチスレッドサーバーでも
    # 並列リクエスト間で集計が混線しない。
    #
    # 同一モデルが複数回ロードされた場合は件数を合算し、ロード箇所は初回を記録する。
    module ModelLoadCollector
      THREAD_KEY = :__bulletproof_ar_loads__
      private_constant :THREAD_KEY

      # ブロック実行中のイベントを収集し、ModelLoadEvent の配列を返す（件数降順）
      def self.collect(&block)
        Thread.current[THREAD_KEY] = {}

        ActiveSupport::Notifications.subscribed(
          method(:handle_event),
          "instantiation.active_record", &block
        )

        build_events(Thread.current[THREAD_KEY])
      ensure
        Thread.current[THREAD_KEY] = nil
      end

      # ActiveSupport::Notifications のコールバック形式 (name, start, finish, id, payload)
      # ActiveRecord の find_each / in_batches 経由かどうかを判定するパス
      BATCH_PATH_PATTERN = %r{activerecord.*/relation/batches}

      def self.handle_event(_name, _start, _finish, _id, payload)
        loads = Thread.current[THREAD_KEY]
        return unless loads

        model_name   = payload[:class_name]
        record_count = payload[:record_count].to_i
        locs         = caller_locations(1)
        batched      = locs.any? { |l| (l.absolute_path || l.path || "").match?(BATCH_PATH_PATTERN) }

        if loads.key?(model_name)
          # 2回目以降: 件数を累計、1回の最大値を更新（ロード箇所・batched フラグは初回を保持）
          loads[model_name][:count]           += record_count
          loads[model_name][:max_single_load]  = [loads[model_name][:max_single_load], record_count].max
        else
          # 初回: アプリコードのフレームをキャプチャ
          location = CallstackFilter.app_location(locs)
          loads[model_name] =
            { count: record_count, max_single_load: record_count, batched: batched, location: location }
        end
      end
      private_class_method :handle_event

      def self.build_events(loads)
        loads
          .map do |model_name, data|
            ModelLoadEvent.new(
              model_name: model_name,
              record_count: data[:count],
              max_single_load: data[:max_single_load],
              batched: data[:batched],
              caller_location: data[:location]
            )
          end
          .sort_by { |e| -e.record_count }
      end
      private_class_method :build_events
    end
  end
end
