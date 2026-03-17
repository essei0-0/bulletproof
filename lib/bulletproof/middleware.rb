# frozen_string_literal: true

require "json"
require "time"

module Bulletproof
  # Rack ミドルウェア。リクエストごとに AR ロード件数・GC 負荷を計測し、
  # 閾値を超えた場合は設定済みの通知先へ RuntimeWarning を送る。
  #
  # 通知先:
  #   rails_logger: true     → Rails.logger.warn に出力
  #   console:      true     → HTML に console.warn を注入（開発者ツール Console タブ）
  #   alert:        true     → HTML にオーバーレイパネルを注入（画面上で確認）
  #   log_file:     "path"   → ファイルに追記
  #   notifier:     callable → Slack 等カスタム通知先
  class Middleware
    def initialize(app, config = Bulletproof.config)
      @app     = app
      @config  = config
      @monitor = Runtime::RequestMonitor.new(config)
    end

    def call(env)
      response, warnings = @monitor.monitor { @app.call(env) }
      return response if warnings.empty?

      notify_logger(warnings)
      notify_log_file(warnings)
      notify_custom(warnings)
      inject_html(response, warnings)
    end

    private

    # ---- ログ通知 ------------------------------------------------------------

    def notify_logger(warnings)
      return unless @config.rails_logger
      return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

      warnings.each { |w| Rails.logger.warn("[Bulletproof] #{w.message}") }
    end

    def notify_log_file(warnings)
      return unless @config.log_file

      File.open(@config.log_file, "a") do |f|
        warnings.each do |w|
          f.puts "[#{Time.now.strftime("%Y-%m-%d %H:%M:%S")}] [#{w.severity.upcase}] [#{w.type}] #{w.message}"
        end
      end
    end

    def notify_custom(warnings)
      return unless @config.notifier

      warnings.each { |w| @config.notifier.call(w) }
    end

    # ---- HTML 注入 -----------------------------------------------------------

    def inject_html(response, warnings)
      return response unless @config.console || @config.alert

      status, headers, body = response
      return response unless html?(headers)

      content  = ""
      content += build_console_script(warnings) if @config.console
      content += build_alert_overlay(warnings)  if @config.alert

      new_body = inject_into_body(body, content)
      [status, update_content_length(headers, new_body), new_body]
    end

    def html?(headers)
      (headers["content-type"] || "").include?("text/html")
    end

    # console.warn を発火する <script> タグ
    def build_console_script(warnings)
      lines = warnings.map do |w|
        "  console.warn('[Bulletproof] ' + #{JSON.generate(w.message)});"
      end.join("\n")
      "\n<script>\n#{lines}\n</script>"
    end

    # 画面右下に浮かぶオーバーレイパネル
    def build_alert_overlay(warnings)
      items = warnings.map do |w|
        msg = w.message
               .gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
               .gsub("\n", "<br>&nbsp;&nbsp;")
        "<li style='margin-bottom:6px;'>#{msg}</li>"
      end.join

      <<~HTML
        <div id="__bp_overlay__" style="position:fixed;bottom:16px;right:16px;max-width:500px;background:#fff3cd;border:2px solid #ffc107;border-radius:8px;padding:12px 16px;font-family:monospace;font-size:12px;line-height:1.5;z-index:999999;box-shadow:0 4px 16px rgba(0,0,0,0.2);">
          <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px;">
            <strong style="color:#856404;font-size:13px;">⚠ Bulletproof (#{warnings.size}件の警告)</strong>
            <button onclick="document.getElementById('__bp_overlay__').remove()" style="background:none;border:none;cursor:pointer;font-size:20px;line-height:1;color:#856404;padding:0 0 0 12px;">✕</button>
          </div>
          <ul style="margin:0;padding:0 0 0 16px;">#{items}</ul>
        </div>
      HTML
    end

    def inject_into_body(body, content)
      injected = false
      body.map do |chunk|
        if !injected && chunk.include?("</body>")
          injected = true
          chunk.sub("</body>", "#{content}\n</body>")
        else
          chunk
        end
      end
    end

    def update_content_length(headers, body)
      return headers unless headers["content-length"]

      headers.merge("content-length" => body.sum(&:bytesize).to_s)
    end
  end
end
