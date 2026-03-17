# frozen_string_literal: true

RSpec.describe Bulletproof::Runtime::RequestMonitor do
  let(:config)  { Bulletproof::Configuration.new }
  let(:monitor) { described_class.new(config) }

  def stub_collector(events)
    allow(Bulletproof::Runtime::ModelLoadCollector).to receive(:collect) do |&blk|
      blk.call
      events
    end
  end

  def make_event(model_name, record_count, max_single_load: record_count, batched: false,
                 location: "app/controllers/posts_controller.rb:10:in 'index'")
    Bulletproof::Runtime::ModelLoadEvent.new(
      model_name: model_name, record_count: record_count,
      max_single_load: max_single_load, batched: batched, caller_location: location
    )
  end

  def gc_zero = { count: 0, total_allocated_objects: 0, heap_allocated_pages: 0 }

  def stub_gc(delta_count: 0)
    call_count = 0
    allow(Bulletproof::Runtime::MemorySampler).to receive(:gc_snapshot) do
      call_count += 1
      call_count == 1 ? gc_zero : gc_zero.merge(count: delta_count)
    end
  end

  describe "#monitor" do
    context "全ての計測値が閾値内のとき" do
      before do
        stub_collector([make_event("Post", 10)])
        stub_gc
      end

      it "ブロックの戻り値を返す" do
        result, = monitor.monitor { :ok }
        expect(result).to eq(:ok)
      end

      it "警告を生成しない" do
        _, warnings = monitor.monitor { nil }
        expect(warnings).to be_empty
      end
    end

    context "1モデルのロード件数が max_records_per_model を超えるとき" do
      before do
        config.max_records_per_model = 500
        stub_collector([make_event("Post", 1_200)])
        stub_gc
      end

      it ":mass_instantiation 警告を生成する" do
        _, warnings = monitor.monitor { nil }
        expect(warnings.map(&:type)).to include(:mass_instantiation)
      end

      it "モデル名とレコード数をメッセージに含む" do
        _, warnings = monitor.monitor { nil }
        msg = warnings.find { |w| w.type == :mass_instantiation }.message
        expect(msg).to include("Post").and include("1,200")
      end

      it "caller_location をメッセージに含む" do
        _, warnings = monitor.monitor { nil }
        msg = warnings.find { |w| w.type == :mass_instantiation }.message
        expect(msg).to include("posts_controller.rb")
      end
    end

    context "find_each のバッチ処理のとき" do
      before do
        config.max_records_per_model = 500
        config.max_total_records     = 300
        # 累計1200件でも、1バッチは100件・batched:true なので両警告とも出ない
        stub_collector([make_event("Post", 1_200, max_single_load: 100, batched: true)])
        stub_gc
      end

      it ":mass_instantiation 警告を生成しない" do
        _, warnings = monitor.monitor { nil }
        expect(warnings.map(&:type)).not_to include(:mass_instantiation)
      end

      it ":high_total_records 警告を生成しない" do
        _, warnings = monitor.monitor { nil }
        expect(warnings.map(&:type)).not_to include(:high_total_records)
      end
    end

    context "複数モデルが閾値を超えるとき" do
      before do
        config.max_records_per_model = 500
        stub_collector([make_event("Post", 1_000), make_event("Comment", 2_000)])
        stub_gc
      end

      it "超えたモデルごとに :mass_instantiation 警告を生成する" do
        _, warnings = monitor.monitor { nil }
        expect(warnings.count { |w| w.type == :mass_instantiation }).to eq(2)
      end
    end

    context "合計レコード数が max_total_records を超えるとき" do
      before do
        config.max_total_records = 1_000
        stub_collector([make_event("Post", 600), make_event("Comment", 600)])
        stub_gc
      end

      it ":high_total_records 警告を生成する" do
        _, warnings = monitor.monitor { nil }
        expect(warnings.map(&:type)).to include(:high_total_records)
      end

      it "合計数と内訳をメッセージに含む" do
        _, warnings = monitor.monitor { nil }
        msg = warnings.find { |w| w.type == :high_total_records }.message
        expect(msg).to include("1,200").and include("Post").and include("Comment")
      end
    end

    context "max_gc_runs_per_request が nil（デフォルト）のとき" do
      before do
        stub_collector([])
        stub_gc(delta_count: 100)
      end

      it "GC が何回実行されても :gc_pressure 警告を生成しない" do
        _, warnings = monitor.monitor { nil }
        expect(warnings.map(&:type)).not_to include(:gc_pressure)
      end
    end

    context "GC 実行回数が max_gc_runs_per_request を超えるとき" do
      before do
        config.max_gc_runs_per_request = 2 # nil（デフォルト無効）を明示的に有効化
        stub_collector([])
        stub_gc(delta_count: 5)
      end

      it ":gc_pressure 警告を生成する" do
        _, warnings = monitor.monitor { nil }
        expect(warnings.map(&:type)).to include(:gc_pressure)
      end
    end

    it "ブロック内で例外が発生しても伝播する" do
      stub_collector([])
      stub_gc
      expect { monitor.monitor { raise "boom" } }.to raise_error("boom")
    end
  end
end
