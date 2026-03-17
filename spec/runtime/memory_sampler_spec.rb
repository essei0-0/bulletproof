# frozen_string_literal: true

RSpec.describe Bulletproof::Runtime::MemorySampler do
  describe ".gc_snapshot" do
    it ":count / :total_allocated_objects / :heap_allocated_pages を含むハッシュを返す" do
      snapshot = described_class.gc_snapshot
      expect(snapshot).to include(:count, :total_allocated_objects, :heap_allocated_pages)
    end

    it "全て整数値を返す" do
      described_class.gc_snapshot.each_value do |v|
        expect(v).to be_a(Integer)
      end
    end
  end
end
