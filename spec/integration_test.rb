#!/usr/bin/env ruby
# frozen_string_literal: true

#
# Bulletproof 動作確認スクリプト
# Rails なし・SQLite インメモリ DB で静的解析とランタイム監視を確認できる
#
# 実行方法:
#   bundle exec ruby spec/integration_test.rb

require "active_record"
require "active_support"
require "active_support/isolated_execution_state"
require "active_support/notifications"
require_relative "../lib/bulletproof"

# ──────────────────────────────────────────────
# DB セットアップ（インメモリ SQLite）
# ──────────────────────────────────────────────

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Base.logger = nil # SQL ログを抑制

ActiveRecord::Schema.define do
  create_table :users do |t|
    t.string :name
  end
  create_table :posts do |t|
    t.string  :title
    t.integer :user_id
  end
  create_table :comments do |t|
    t.string  :body
    t.integer :post_id
  end
end

class User    < ActiveRecord::Base; has_many :posts; end

class Post    < ActiveRecord::Base
  belongs_to :user
  has_many :comments
end

class Comment < ActiveRecord::Base; belongs_to :post; end

# テストデータを投入（User 50件、Post 500件、Comment 2000件）
puts "テストデータを投入中..."
50.times  { |i| User.create!(name: "user_#{i}") }
500.times { |i| Post.create!(title: "post_#{i}", user_id: rand(1..50)) }
2_000.times { |i| Comment.create!(body: "comment_#{i}", post_id: rand(1..500)) }
puts "投入完了: User=#{User.count}, Post=#{Post.count}, Comment=#{Comment.count}\n\n"

# ──────────────────────────────────────────────
# 1. 静的解析の確認
# ──────────────────────────────────────────────

puts "=" * 60
puts "1. 静的解析"
puts "=" * 60

# 問題のあるコードを一時ファイルに書き出して解析
require "tempfile"

safe_code = <<~RUBY
  User.includes(posts: :comments).limit(10)
  Post.includes(:user).first
RUBY

bad_code = <<~RUBY
  User.includes(posts: { comments: :author }).all
  Post.includes(:user, :comments, :tags, :likes)
RUBY

[["安全なコード", safe_code], ["問題のあるコード", bad_code]].each do |label, code|
  Tempfile.create(["test", ".rb"]) do |f|
    f.write(code)
    f.flush
    report = Bulletproof.analyze(f.path)
    puts "\n[#{label}]"
    puts code.strip.split("\n").map { |l| "  #{l}" }.join("\n")
    puts report.ok? ? "  → ✓ No violations" : report.to_s.gsub(/^/, "  → ")
  end
end

# ──────────────────────────────────────────────
# 2. ランタイム監視の確認
# ──────────────────────────────────────────────

puts "\n\n"
puts "=" * 60
puts "2. ランタイム監視"
puts "=" * 60

Bulletproof.configure do |c|
  c.enabled               = true
  c.max_records_per_model = 100  # 100件超えたら警告
  c.max_total_records     = 300  # 合計300件超えたら警告
  c.rails_logger          = false
  c.console               = false
  c.notifier              = ->(w) { puts "\n  [#{w.type.upcase}] #{w.message}" }
end

monitor = Bulletproof::Runtime::RequestMonitor.new(Bulletproof.config)

# ケース1: 件数を絞っているので警告なし
puts "\n--- ケース1: limit(10) で件数を絞る（警告なし）"
_, warnings = monitor.monitor do
  User.includes(:posts).limit(10).to_a
end
puts warnings.empty? ? "  → ✓ No warnings" : ""

# ケース2: 全件ロードで mass_instantiation 警告
puts "\n--- ケース2: Post.all で全件ロード（警告あり）"
_, warnings = monitor.monitor do
  Post.all.to_a # 500件ロード → max_records_per_model(100) を超える
end
warnings.each { |w| Bulletproof.config.notifier.call(w) } if warnings.any?
puts "  → ✓ No warnings" if warnings.empty?

# ケース3: 複数モデルで合計件数オーバー
puts "\n--- ケース3: Post + Comment を全件ロード（high_total_records 警告あり）"
_, warnings = monitor.monitor do
  posts    = Post.all.to_a    # 500件
  comments = Comment.all.to_a # 2000件
  [posts, comments]
end
warnings.each { |w| Bulletproof.config.notifier.call(w) } if warnings.any?
puts "  → ✓ No warnings" if warnings.empty?

# ケース4: find_each（バッチ処理）
puts "\n--- ケース4: find_each で全件処理（batch_size: 100）"
_, warnings = monitor.monitor do
  Post.find_each(batch_size: 100, &:title)
end
warnings.each { |w| Bulletproof.config.notifier.call(w) } if warnings.any?
puts "  → ✓ No warnings" if warnings.empty?

# ──────────────────────────────────────────────
# 3. 通知先の動作確認
# ──────────────────────────────────────────────

puts "\n\n"
puts "=" * 60
puts "3. 通知先の動作確認"
puts "=" * 60

# ── 共通: 全件ロードを起こす内側の Rack アプリ ──────────────────
# Post.all（500件）を全件ロードするアプリ。
# 実際のリクエストは Middleware#call(env) で処理される。
heavy_rack_app = lambda do |_env|
  Post.all.to_a
  [200, { "Content-Type" => "text/html" },
   ["<html><body><h1>Posts</h1></body></html>"]]
end

# ── console: true（ブラウザコンソール注入） ───────────────────────
puts "\n--- console: true（HTML に <script> を注入）"

Bulletproof.configure do |c|
  c.enabled               = true
  c.max_records_per_model = 100
  c.max_total_records     = 300
  c.rails_logger          = false
  c.console               = true
  c.notifier              = nil
end

middleware = Bulletproof::Middleware.new(heavy_rack_app)
_, _, body = middleware.call({})
html = body.join
if html.include?("<script>") && html.include?("console.warn")
  puts "  → ✓ <script> が注入されています"
  # 注入されたスクリプト部分だけ抜き出して表示
  script = html[%r{<script>.*?</script>}m]
  script.each_line { |l| puts "    #{l.chomp}" unless l.strip.empty? }
else
  puts "  → ✗ <script> が見つかりません"
end

# ── rails_logger: true（Rails.logger シミュレート） ──────────────
puts "\n--- rails_logger: true（Rails.logger.warn をシミュレート）"

# Rails が存在しない環境なので、同じインターフェースのオブジェクトで代替する
fake_logger = Object.new
fake_logger.define_singleton_method(:warn) { |msg| puts "  [Rails.logger] #{msg}" }

# Rails 定数をスタブ
rails_stub = Object.new
rails_stub.define_singleton_method(:logger) { fake_logger }
rails_stub.define_singleton_method(:respond_to?) { |_| true }
Object.const_set(:Rails, rails_stub) unless defined?(Rails)

Bulletproof.configure do |c|
  c.rails_logger = true
  c.console      = false
  c.notifier     = nil
end

middleware = Bulletproof::Middleware.new(heavy_rack_app)
middleware.call({})

# ── notifier（カスタム通知先） ────────────────────────────────────
puts "\n--- notifier: callable（カスタム通知先）"

Bulletproof.configure do |c|
  c.rails_logger = false
  c.console      = false
  c.notifier     = ->(w) { puts "  [Custom] type=#{w.type} message=#{w.message.lines.first.chomp}" }
end

middleware = Bulletproof::Middleware.new(heavy_rack_app)
middleware.call({})

puts "\n\n完了"
