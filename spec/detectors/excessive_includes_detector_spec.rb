# frozen_string_literal: true

require "spec_helper"

RSpec.describe Bulletproof::Detectors::ExcessiveIncludesDetector do
  let(:config) { Bulletproof::Configuration.new }
  subject(:detector) { described_class.new(config) }

  def detect(source)
    detector.call(source, file: "test.rb")
  end

  # ---------------------------------------------------------------------------
  # 安全パターン：件数を絞るメソッドがあれば深さ・幅に関わらず検出しない
  # ---------------------------------------------------------------------------
  describe "安全パターン（誤検知しないこと）" do
    context "深いネストでも件数制限があれば問題なし" do
      it ".limit があれば検出しない" do
        expect(detect("User.includes(posts: { comments: :author }).limit(10)")).to be_empty
      end

      it ".find があれば検出しない（単件取得）" do
        expect(detect("User.includes(posts: { comments: :author }).find(1)")).to be_empty
      end

      it ".find_by があれば検出しない" do
        expect(detect("User.includes(posts: { comments: :author }).find_by(slug: 'foo')")).to be_empty
      end

      it ".first があれば検出しない" do
        expect(detect("User.includes(posts: { comments: :author }).first")).to be_empty
      end

      it ".last があれば検出しない" do
        expect(detect("User.includes(posts: { comments: :author }).last")).to be_empty
      end

      it ".take があれば検出しない" do
        expect(detect("User.includes(posts: { comments: :author }).take(5)")).to be_empty
      end
    end

    context "多アソシエーションでもページネーションがあれば問題なし" do
      it ".page があれば検出しない（kaminari）" do
        expect(detect("User.includes(:a, :b, :c, :d).page(1)")).to be_empty
      end

      it ".page + .per があれば検出しない" do
        expect(detect("User.includes(:a, :b, :c, :d).page(1).per(20)")).to be_empty
      end

      it ".paginate があれば検出しない（will_paginate）" do
        expect(detect("User.includes(:a, :b, :c, :d).paginate(page: 1, per_page: 20)")).to be_empty
      end
    end

    context "チェーンの順序に関わらず検出しない" do
      it "includes の前に limit があっても検出しない" do
        expect(detect("User.limit(10).includes(posts: { comments: :author })")).to be_empty
      end

      it "where を挟んでも limit があれば検出しない" do
        expect(detect("User.where(active: true).includes(posts: { comments: :author }).limit(5)")).to be_empty
      end
    end

    context "浅いネスト・少ないアソシエーションは件数制限がなくても問題なし" do
      it "フラットな includes は検出しない" do
        expect(detect("User.includes(:posts)")).to be_empty
      end

      it "深さ1のネストは検出しない" do
        expect(detect("User.includes(posts: :comments)")).to be_empty
      end

      it "アソシエーション3つは検出しない" do
        expect(detect("User.includes(:a, :b, :c)")).to be_empty
      end
    end
  end

  # ---------------------------------------------------------------------------
  # 危険パターン：深い or 多い includes で件数制限なし
  # ---------------------------------------------------------------------------
  describe "危険パターン（正しく検出すること）" do
    context "深いネスト + 件数制限なし" do
      it "深さ2のネストを検出する" do
        source = "User.includes(posts: { comments: :author })"
        violations = detect(source)
        expect(violations.size).to eq(1)
        expect(violations.first.message).to include("ネスト深さ")
        expect(violations.first.message).to include("件数を絞るメソッド")
      end

      it ".all があっても件数制限なしとして検出する" do
        source = "User.includes(posts: { comments: :author }).all"
        expect(detect(source)).not_to be_empty
      end

      it "深さ3を検出する" do
        source = "User.includes(posts: { comments: { likes: :user } })"
        expect(detect(source)).not_to be_empty
      end
    end

    context "多アソシエーション + 件数制限なし" do
      it "4つのシンボルを検出する" do
        source = "User.includes(:a, :b, :c, :d)"
        violations = detect(source)
        expect(violations.size).to eq(1)
        expect(violations.first.message).to include("アソシエーション数 4")
      end

      it "シンボルとハッシュキーの混在でも正確に数える" do
        # :a + b: :c + d: :e = 3つ → 上限3を超えない（= 検出しない）
        expect(detect("User.includes(:a, b: :c, d: :e)")).to be_empty
      end

      it "シンボル2 + ハッシュキー2 = 4で検出する" do
        source = "User.includes(:a, :b, c: :x, d: :y)"
        expect(detect(source)).not_to be_empty
      end
    end

    context "深さと多アソシエーションの両方に問題がある場合" do
      it "1つの violation にまとめて報告する" do
        # 深さ2 かつ アソシエーション4
        source = "User.includes(:x, :y, :z, posts: { comments: :author })"
        violations = detect(source)
        expect(violations.size).to eq(1)
        expect(violations.first.message).to include("ネスト深さ")
        expect(violations.first.message).to include("アソシエーション数")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # その他
  # ---------------------------------------------------------------------------
  describe "行番号" do
    it "違反が発生したソース行を記録する" do
      source = <<~RUBY
        class PostsController
          def index
            User.includes(:a, :b, :c, :d)
          end
        end
      RUBY
      violations = detect(source)
      expect(violations.first.line).to eq(3)
    end
  end

  describe "複数箇所の検出" do
    it "複数の危険な includes を全て検出する" do
      source = <<~RUBY
        User.includes(:a, :b, :c, :d)
        Post.includes(comments: { likes: :user })
      RUBY
      expect(detect(source).size).to eq(2)
    end

    it "安全なものと危険なものが混在する場合、危険なものだけ検出する" do
      source = <<~RUBY
        User.includes(:a, :b, :c, :d).limit(10)
        Post.includes(comments: { likes: :user })
      RUBY
      violations = detect(source)
      expect(violations.size).to eq(1)
      expect(violations.first.line).to eq(2)
    end
  end

  describe "カスタム設定" do
    before do
      config.max_includes_depth = 3
      config.max_associations   = 5
    end

    it "深さ2は上限3未満なので検出しない" do
      expect(detect("User.includes(posts: { comments: :author })")).to be_empty
    end

    it "深さ3は検出する" do
      source = "User.includes(posts: { comments: { likes: :user } })"
      expect(detect(source)).not_to be_empty
    end
  end

  describe "構文エラーのファイル" do
    it "空の配列を返す" do
      expect(detect("def foo\n  @@@invalid")).to be_empty
    end
  end
end
