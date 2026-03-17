# frozen_string_literal: true

RSpec.describe Bulletproof::Middleware do
  let(:config)  { Bulletproof::Configuration.new }
  let(:warning) do
    Bulletproof::RuntimeWarning.new(
      type: :mass_instantiation, message: "Post を 500 件ロードしました", severity: :warning, detail: nil
    )
  end

  def build_app(body: "<html><body>Hello</body></html>", content_type: "text/html")
    ->(_env) { [200, { "content-type" => content_type }, [body]] }
  end

  def stub_monitor(middleware, warnings:)
    monitor = instance_double(Bulletproof::Runtime::RequestMonitor)
    allow(Bulletproof::Runtime::RequestMonitor).to receive(:new).and_return(monitor)
    allow(monitor).to receive(:monitor) do |&blk|
      [blk.call, warnings]
    end
    # middleware を再生成して新しい monitor を使わせる
    described_class.new(middleware.instance_variable_get(:@app), config)
  end

  describe "#call" do
    context "警告がないとき" do
      let(:middleware) { described_class.new(build_app, config) }

      before do
        allow_any_instance_of(Bulletproof::Runtime::RequestMonitor)
          .to receive(:monitor) { |_, &blk| [blk.call, []] }
      end

      it "レスポンスをそのまま返す" do
        status, _, body = middleware.call({})
        expect(status).to eq(200)
        expect(body.join).to eq("<html><body>Hello</body></html>")
      end

      it "スクリプトを注入しない" do
        _, _, body = middleware.call({})
        expect(body.join).not_to include("<script>")
      end
    end

    context "警告があるとき" do
      let(:middleware) { described_class.new(build_app, config) }

      before do
        allow_any_instance_of(Bulletproof::Runtime::RequestMonitor)
          .to receive(:monitor) { |_, &blk| [blk.call, [warning]] }
      end

      context "console: true（デフォルト）かつ HTML レスポンスのとき" do
        it "console.warn を </body> 直前に注入する" do
          _, _, body = middleware.call({})
          html = body.join
          expect(html).to include("console.warn")
          expect(html).to include("Post を 500 件ロードしました")
          expect(html.index("<script>")).to be < html.index("</body>")
        end

        it "Content-Length を更新する" do
          app_with_length = lambda { |_env|
            body = ["<html><body>Hello</body></html>"]
            [200, { "content-type" => "text/html", "content-length" => body.sum(&:bytesize).to_s }, body]
          }
          mw = described_class.new(app_with_length, config)
          allow_any_instance_of(Bulletproof::Runtime::RequestMonitor)
            .to receive(:monitor) { |_, &blk| [blk.call, [warning]] }

          _, headers, body = mw.call({})
          expect(headers["content-length"].to_i).to eq(body.sum(&:bytesize))
        end
      end

      context "console: false のとき" do
        before { config.console = false }

        it "スクリプトを注入しない" do
          _, _, body = middleware.call({})
          expect(body.join).not_to include("<script>")
        end
      end

      context "alert: true のとき" do
        before { config.alert = true }

        it "オーバーレイ div を </body> 直前に注入する" do
          _, _, body = middleware.call({})
          html = body.join
          expect(html).to include("__bp_overlay__")
          expect(html).to include("Post を 500 件ロードしました")
          expect(html.index("__bp_overlay__")).to be < html.index("</body>")
        end
      end

      context "console: true かつ alert: true のとき" do
        before { config.alert = true }

        it "スクリプトとオーバーレイの両方を注入する" do
          _, _, body = middleware.call({})
          html = body.join
          expect(html).to include("console.warn")
          expect(html).to include("__bp_overlay__")
        end
      end

      context "log_file が設定されているとき" do
        let(:log_path) { Tempfile.new("bp_test").path }
        before { config.log_file = log_path }
        after  { FileUtils.rm_f(log_path) }

        it "警告をファイルに追記する" do
          middleware.call({})
          content = File.read(log_path)
          expect(content).to include("[WARNING]")
          expect(content).to include("[mass_instantiation]")
          expect(content).to include("Post を 500 件ロードしました")
        end

        it "タイムスタンプを含む" do
          middleware.call({})
          expect(File.read(log_path)).to match(/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/)
        end
      end

      context "HTML 以外のレスポンスのとき" do
        let(:middleware) { described_class.new(build_app(content_type: "application/json"), config) }

        it "スクリプトを注入しない" do
          _, _, body = middleware.call({})
          expect(body.join).not_to include("<script>")
        end
      end

      context "rails_logger: true かつ Rails が定義されているとき" do
        let(:fake_logger) { double("logger", warn: nil) }

        before do
          stub_const("Rails", double("Rails", logger: fake_logger, respond_to?: true))
          allow(Rails).to receive(:respond_to?).with(:logger).and_return(true)
        end

        it "Rails.logger.warn を呼ぶ" do
          middleware.call({})
          expect(fake_logger).to have_received(:warn).with(/Bulletproof/)
        end
      end

      context "rails_logger: false のとき" do
        let(:fake_logger) { double("logger", warn: nil) }

        before do
          config.rails_logger = false
          stub_const("Rails", double("Rails", logger: fake_logger, respond_to?: true))
          allow(Rails).to receive(:respond_to?).with(:logger).and_return(true)
        end

        it "Rails.logger.warn を呼ばない" do
          middleware.call({})
          expect(fake_logger).not_to have_received(:warn)
        end
      end

      context "notifier が設定されているとき" do
        let(:received) { [] }
        before { config.notifier = ->(w) { received << w } }

        it "notifier を呼ぶ" do
          middleware.call({})
          expect(received).to eq([warning])
        end
      end

      context "ボディが each のみ持つオブジェクト（RackBody）のとき" do
        let(:rack_body) do
          chunks = ["<html><body>Hello</body></html>"]
          obj = Object.new
          obj.define_singleton_method(:each) { |&blk| chunks.each(&blk) }
          obj
        end
        let(:middleware) do
          app = ->(_env) { [200, { "content-type" => "text/html" }, rack_body] }
          described_class.new(app, config)
        end

        it "map を呼ばずに注入できる" do
          _, _, body = middleware.call({})
          expect(body.join).to include("console.warn")
        end
      end
    end
  end
end
