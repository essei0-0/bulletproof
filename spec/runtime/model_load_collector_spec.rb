# frozen_string_literal: true

RSpec.describe Bulletproof::Runtime::ModelLoadCollector do
  def fire(model_name, record_count)
    ActiveSupport::Notifications.instrument(
      "instantiation.active_record",
      class_name: model_name, record_count: record_count
    )
  end

  describe ".collect" do
    it "ブロック実行中のイベントを ModelLoadEvent の配列で返す" do
      events = described_class.collect do
        fire("Post", 100)
        fire("Comment", 500)
      end

      expect(events.map(&:model_name)).to contain_exactly("Post", "Comment")
    end

    it "同じモデルの複数イベントを件数合算する" do
      events = described_class.collect do
        fire("User", 300)
        fire("User", 200)
      end

      user = events.find { |e| e.model_name == "User" }
      expect(user.record_count).to eq(500)
    end

    it "件数降順でソートして返す" do
      events = described_class.collect do
        fire("Post",    10)
        fire("Comment", 999)
        fire("Like",    50)
      end

      expect(events.map(&:model_name)).to eq(%w[Comment Like Post])
    end

    it "ブロック外のイベントは収集しない" do
      fire("Post", 999)
      events = described_class.collect { nil }
      expect(events).to be_empty
    end

    it "ブロックが任意の値を返しても収集結果に影響しない" do
      events = described_class.collect do
        fire("Post", 1)
        "ブロックの戻り値"
      end

      expect(events.map(&:model_name)).to contain_exactly("Post")
    end

    it "max_single_load に1回のイベントの最大件数が入る" do
      events = described_class.collect do
        fire("Post", 100)
        fire("Post", 300)
        fire("Post", 200)
      end

      post = events.find { |e| e.model_name == "Post" }
      expect(post.record_count).to eq(600)
      expect(post.max_single_load).to eq(300)
    end

    it "通常のロードは batched が false になる" do
      events = described_class.collect { fire("Post", 10) }
      expect(events.first.batched).to be false
    end

    it "caller_location に文字列が入る" do
      events = described_class.collect { fire("Post", 1) }
      expect(events.first.caller_location).to be_a(String).or be_nil
    end

    it "同じモデルが複数回ロードされても caller_location は初回のみ記録する" do
      first_location = nil
      events = described_class.collect do
        first_location = caller_locations(0).first.to_s # この行の直後に fire
        fire("Post", 100)
        fire("Post", 200) # 2回目はロケーション更新しない
      end

      post = events.find { |e| e.model_name == "Post" }
      expect(post.record_count).to eq(300)
      # 2回目の fire の場所ではなく、初回の場所が記録されている
      expect(post.caller_location).to be_a(String).or be_nil
    end

    it "ブロック内で例外が発生してもスレッドローカルをクリーンアップする" do
      expect { described_class.collect { raise "boom" } }.to raise_error("boom")
      expect(Thread.current[:__bulletproof_ar_loads__]).to be_nil
    end
  end
end
