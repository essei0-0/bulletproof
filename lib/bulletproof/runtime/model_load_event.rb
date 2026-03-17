# frozen_string_literal: true

module Bulletproof
  module Runtime
    # 1モデルのロード集計結果
    # record_count:     リクエスト全体の累計ロード件数（find_each の複数バッチも合算）
    # max_single_load:  1回のイベントで最大何件ロードされたか（find_each のバッチ上限に相当）
    # batched:          find_each / in_batches 経由のロードかどうか
    # caller_location:  アプリコードで最初にロードが発生した箇所（"path:line:in 'method'" 形式）
    ModelLoadEvent = Data.define(:model_name, :record_count, :max_single_load, :batched, :caller_location)
  end
end
