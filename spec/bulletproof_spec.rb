# frozen_string_literal: true

RSpec.describe Bulletproof do
  it "has a version number" do
    expect(Bulletproof::VERSION).not_to be nil
  end

  describe ".config" do
    it "Configuration インスタンスを返す" do
      expect(Bulletproof.config).to be_a(Bulletproof::Configuration)
    end

    it "同一インスタンスを返す（シングルトン）" do
      expect(Bulletproof.config).to equal(Bulletproof.config)
    end
  end

  describe ".configure" do
    after { Bulletproof.instance_variable_set(:@config, nil) }

    it "ブロックで設定を変更できる" do
      Bulletproof.configure do |c|
        c.max_includes_depth    = 5
        c.max_associations      = 10
        c.max_records_per_model = 2_000
        c.max_total_records     = 10_000
      end
      expect(Bulletproof.config.max_includes_depth).to eq(5)
      expect(Bulletproof.config.max_associations).to eq(10)
      expect(Bulletproof.config.max_records_per_model).to eq(2_000)
      expect(Bulletproof.config.max_total_records).to eq(10_000)
    end
  end

  describe ".analyze" do
    let(:tmpfile) { Tempfile.new(["test", ".rb"]) }

    after do
      tmpfile.close
      tmpfile.unlink
      Bulletproof.instance_variable_set(:@config, nil)
    end

    it "クリーンなコードはok?がtrue" do
      tmpfile.write("User.includes(:posts)")
      tmpfile.flush
      report = Bulletproof.analyze(tmpfile.path)
      expect(report).to be_ok
    end

    it "違反があるコードはok?がfalse" do
      tmpfile.write("User.includes(:a, :b, :c, :d)")
      tmpfile.flush
      report = Bulletproof.analyze(tmpfile.path)
      expect(report).not_to be_ok
    end
  end
end
