# frozen_string_literal: true

RSpec.describe Bulletproof::Runtime::CallstackFilter do
  describe ".app_location" do
    it "gem のフレームを除外してアプリコードのフレームを返す" do
      gem_frame    = instance_double(Thread::Backtrace::Location,
                                     absolute_path: "/path/to/gems/activerecord-7.0/lib/foo.rb", path: nil, to_s: "gem:1:in 'x'")
      app_frame    = instance_double(Thread::Backtrace::Location,
                                     absolute_path: "/app/controllers/posts_controller.rb", path: nil, to_s: "app/controllers/posts_controller.rb:15:in 'index'")

      result = described_class.app_location([gem_frame, app_frame])
      expect(result).to eq("app/controllers/posts_controller.rb:15:in 'index'")
    end

    it "bulletproof 自身のフレームを除外する" do
      bp_frame  = instance_double(Thread::Backtrace::Location,
                                  absolute_path: "/path/lib/bulletproof/runtime/model_load_collector.rb", path: nil, to_s: "bp:1")
      app_frame = instance_double(Thread::Backtrace::Location, absolute_path: "/app/models/user.rb", path: nil,
                                                               to_s: "app/models/user.rb:10:in 'all_active'")

      result = described_class.app_location([bp_frame, app_frame])
      expect(result).to eq("app/models/user.rb:10:in 'all_active'")
    end

    it "アプリフレームが見つからない場合は nil を返す" do
      gem_frame = instance_double(Thread::Backtrace::Location, absolute_path: "/path/to/gems/foo/lib/bar.rb",
                                                               path: nil, to_s: "gem:1")

      result = described_class.app_location([gem_frame])
      expect(result).to be_nil
    end

    it "absolute_path が nil のフレームは path にフォールバックする" do
      frame = instance_double(Thread::Backtrace::Location, absolute_path: nil, path: "/app/services/loader.rb",
                                                           to_s: "app/services/loader.rb:5:in 'run'")

      result = described_class.app_location([frame])
      expect(result).to eq("app/services/loader.rb:5:in 'run'")
    end
  end
end
