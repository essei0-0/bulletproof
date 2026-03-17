# frozen_string_literal: true

module Bulletproof
  class Configuration
    # ---- 静的解析 -----------------------------------------------------------

    # includes のネスト深さの上限（例: posts: { comments: :author } は深さ2）
    attr_accessor :max_includes_depth

    # 1つの includes で許容するアソシエーション数の上限
    attr_accessor :max_associations

    # ---- ランタイム監視 -----------------------------------------------------

    # ランタイム監視を有効にするか（デフォルト: false）
    # Rails では config/initializers/bulletproof.rb で true に設定して使う
    attr_accessor :enabled

    # 1モデルあたりのロード件数の上限
    # 超えると :mass_instantiation 警告を出す
    attr_accessor :max_records_per_model

    # リクエスト全体（全モデル合算）のロード件数の上限
    # 超えると :high_total_records 警告を出す
    attr_accessor :max_total_records

    # リクエスト中に許容する GC 実行回数の上限
    # 超えると :gc_pressure 警告を出す
    # nil（デフォルト）のとき無効。GC 頻度はアプリや Ruby 設定に依存するため
    # 必要な場合にのみ明示的に設定する（例: 10）
    attr_accessor :max_gc_runs_per_request

    # Rails.logger.warn に出力するか（デフォルト: true）
    attr_accessor :rails_logger

    # HTML レスポンスの </body> 直前に console.warn を注入するか（デフォルト: true）
    # ブラウザの開発者ツールの Console タブで確認できる
    attr_accessor :console

    # HTML レスポンスにオーバーレイパネルを注入するか（デフォルト: false）
    # 開発者ツールを開かなくても画面上で警告を確認できる
    attr_accessor :alert

    # 警告をファイルに追記するか（デフォルト: nil = 無効）
    # ファイルパスを文字列で指定する
    #   c.log_file = Rails.root.join("log/bulletproof.log").to_s
    attr_accessor :log_file

    # カスタム通知先。Slack 等に飛ばしたいときに設定する（デフォルト: nil = 無効）
    # callable で RuntimeWarning を引数に取る
    #   c.notifier = ->(w) { SlackNotifier.ping(w.message) }
    attr_accessor :notifier

    def initialize
      @enabled                  = false
      @max_includes_depth       = 2
      @max_associations         = 3
      @max_records_per_model    = 1_000
      @max_total_records        = 5_000
      @max_gc_runs_per_request  = nil
      @rails_logger             = true
      @console                  = true
      @alert                    = false
      @log_file                 = nil
      @notifier                 = nil
    end
  end
end
