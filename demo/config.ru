# frozen_string_literal: true

#
# Bulletproof デモアプリ
#
# 起動方法:
#   bundle exec rackup demo/config.ru
#
# ブラウザで開く:
#   http://localhost:9292/         → 安全なクエリ（件数制限あり）
#   http://localhost:9292/heavy    → 大量ロード（警告あり）
#   http://localhost:9292/batched  → find_each（警告なし）

require "active_record"
require "active_support"
require "active_support/isolated_execution_state"
require "active_support/notifications"
require_relative "../lib/bulletproof"

# ── DB セットアップ ──────────────────────────────────────────────

DB_PATH = File.join(__dir__, "demo.sqlite3")
FileUtils.rm_f(DB_PATH) # 起動のたびにリセット
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: DB_PATH)
ActiveRecord::Base.logger = nil

ActiveRecord::Schema.define do
  create_table :users do |t|
    t.string :name
  end
  create_table :posts do |t|
    t.string :title
    t.integer :user_id
  end
  create_table :comments do |t|
    t.string :body
    t.integer :post_id
  end
end

class User    < ActiveRecord::Base; has_many :posts;    end
class Post    < ActiveRecord::Base; has_many :comments; end
class Comment < ActiveRecord::Base; belongs_to :post;   end

50.times   { |i| User.create!(name: "user_#{i}") }
500.times  { |i| Post.create!(title: "post_#{i}", user_id: rand(1..50)) }
2_000.times { |i| Comment.create!(body: "comment_#{i}", post_id: rand(1..500)) }

# ── Bulletproof 設定 ─────────────────────────────────────────────

LOG_FILE = File.join(__dir__, "bulletproof.log")

Bulletproof.configure do |c|
  c.enabled               = true
  c.max_records_per_model = 100
  c.max_total_records     = 300
  c.rails_logger          = false        # Rails がないので無効
  c.console               = true         # 開発者ツール Console タブに表示
  c.alert                 = true         # 画面上にオーバーレイパネルを表示
  c.log_file              = LOG_FILE     # demo/bulletproof.log に追記
end

# ── アプリ本体 ───────────────────────────────────────────────────

NAV = <<~HTML
  <nav style="font-family:sans-serif; padding:12px; background:#f5f5f5; margin-bottom:16px;">
    <a href="/">✅ 安全なクエリ（limit）</a> &nbsp;|&nbsp;
    <a href="/heavy">⚠️  大量ロード（警告あり）</a> &nbsp;|&nbsp;
    <a href="/batched">🔄 find_each（警告なし）</a>
    <span style="float:right; color:#888; font-size:0.85em;">
      開発者ツール（F12）→ Console タブで警告を確認
    </span>
  </nav>
HTML

def page(title, body_html)
  <<~HTML
    <!DOCTYPE html>
    <html>
    <head><meta charset="utf-8"><title>#{title} | Bulletproof Demo</title></head>
    <body style="font-family:sans-serif; padding:16px;">
    #{NAV}
    <h2>#{title}</h2>
    #{body_html}
    </body>
    </html>
  HTML
end

app = lambda do |env|
  path = env["PATH_INFO"]

  case path
  when "/"
    posts = Post.limit(5).to_a
    rows  = posts.map { |p| "<li>#{p.title}</li>" }.join
    html  = page("✅ 安全なクエリ", "<p>Post.limit(5) — 5件のみロード</p><ul>#{rows}</ul>")
    [200, { "content-type" => "text/html" }, [html]]

  when "/heavy"
    posts    = Post.all.to_a
    comments = Comment.all.to_a
    html = page(
      "⚠️ 大量ロード",
      "<p>Post.all（#{posts.size}件）+ Comment.all（#{comments.size}件）を全件ロードしました。</p>" \
      "<p><strong>開発者ツールのコンソールに警告が出ているはずです。</strong></p>"
    )
    [200, { "content-type" => "text/html" }, [html]]

  when "/batched"
    count = 0
    Post.find_each(batch_size: 100) { count += 1 }
    html = page(
      "🔄 find_each",
      "<p>Post.find_each(batch_size: 100) で #{count}件を処理しました。</p>" \
      "<p>バッチ処理のため、コンソールに警告は出ません。</p>"
    )
    [200, { "content-type" => "text/html" }, [html]]

  else
    [404, { "content-type" => "text/plain" }, ["Not Found"]]
  end
end

use Bulletproof::Middleware
run app
