# frozen_string_literal: true

require "rubocop-ast"

module Bulletproof
  module Detectors
    # Rubyソースを静的解析し、メモリ過剰消費につながるincludes呼び出しを検出する
    #
    # 検出の前提:
    #   includesのネスト深さ・アソシエーション数が大きくても、
    #   件数を絞るメソッドがチェーンにあれば安全とみなす。
    #
    # 危険パターン（フラグを立てる）:
    #   User.includes(posts: { comments: :author }).all          # 全件 + 深いネスト
    #   User.includes(:a, :b, :c, :d)                           # 全件 + 多アソシエーション
    #
    # 安全パターン（フラグを立てない）:
    #   User.includes(posts: { comments: :author }).limit(10)    # 件数制限あり
    #   User.includes(posts: { comments: :author }).find(1)      # 単件取得
    #   User.includes(posts: { comments: :author }).first        # 単件取得
    #   User.includes(:a, :b, :c, :d).page(1).per(20)           # ページネーションあり
    LIMITING_METHODS = %i[
      limit find find_by find_by!
      first first! last last! take take!
      page paginate per per_page
    ].freeze

    class ExcessiveIncludesDetector
      def initialize(config)
        @config = config
      end

      # @param source [String] Rubyソースコード
      # @param file [String] ファイルパス（表示用）
      # @return [Array<Violation>]
      def call(source, file: "(string)")
        processed = RuboCop::AST::ProcessedSource.new(source, RUBY_VERSION.to_f, file)
        return [] unless processed.valid_syntax?

        parent_map = build_parent_map(processed.ast)
        violations = []
        collect_includes_nodes(processed.ast).each do |node|
          check(node, violations, file, parent_map)
        end
        violations
      end

      private

      # ---- AST 走査 --------------------------------------------------------

      def collect_includes_nodes(node, result = [])
        return result unless node.is_a?(RuboCop::AST::Node)

        result << node if includes_call?(node)
        node.each_child_node { |child| collect_includes_nodes(child, result) }
        result
      end

      # 各ノードの親を記録するマップを構築する
      def build_parent_map(node, parent = nil, map = {}.compare_by_identity)
        return map unless node.is_a?(RuboCop::AST::Node)

        map[node] = parent
        node.each_child_node { |child| build_parent_map(child, node, map) }
        map
      end

      # ---- チェーン解析 ----------------------------------------------------

      # includes ノードから連続する send チェーンの根（最外ノード）を返す
      def chain_root(node, parent_map)
        current = node
        loop do
          parent = parent_map[current]
          break unless parent&.send_type? && parent.receiver.equal?(current)

          current = parent
        end
        current
      end

      # send チェーンに含まれる全メソッド名を収集する（チェーン根から下向き）
      def collect_chain_methods(node, methods = [])
        return methods unless node.is_a?(RuboCop::AST::Node) && node.send_type?

        methods << node.method_name
        collect_chain_methods(node.receiver, methods)
        methods
      end

      # ---- 検出ロジック ----------------------------------------------------

      def includes_call?(node)
        node.send_type? && node.method_name == :includes
      end

      def check(node, violations, file, parent_map)
        depth = max_includes_depth(node)
        count = count_top_level_associations(node.arguments)

        deep  = depth >= @config.max_includes_depth
        wide  = count > @config.max_associations

        return unless deep || wide

        root    = chain_root(node, parent_map)
        methods = collect_chain_methods(root)

        return if (methods & LIMITING_METHODS).any?

        issues = []
        issues << "ネスト深さ #{depth}（上限: #{@config.max_includes_depth}）" if deep
        issues << "アソシエーション数 #{count}（上限: #{@config.max_associations}）" if wide

        violations << Violation.new(
          file: file,
          line: node.loc.line,
          message: "#{issues.join("、")} かつ件数を絞るメソッド（limit / find 等）がチェーンにありません",
          severity: :warning
        )
      end

      # ---- 深さ・幅の計算 -------------------------------------------------

      # includes 引数のネスト深さを計算する
      #   :posts                                 → 0
      #   { posts: :comments }                   → 1
      #   { posts: { comments: :author } }       → 2
      #   { posts: [:comments, :likes] }         → 1
      def node_depth(node)
        case node.type
        when :hash  then 1 + (node.each_pair.map { |pair| node_depth(pair.value) }.max || 0)
        when :array then node.children.map { |child| node_depth(child) }.max || 0
        else             0
        end
      end

      def max_includes_depth(node)
        node.arguments.map { |arg| node_depth(arg) }.max || 0
      end

      # トップレベルのアソシエーション数を数える
      #   includes(:a, :b)         → 2
      #   includes(a: :b, c: :d)   → 2（ハッシュのキー数）
      #   includes(:a, b: :c)      → 2（sym + ハッシュキー）
      def count_top_level_associations(args)
        args.sum do |arg|
          case arg.type
          when :sym, :str then 1
          when :hash      then arg.keys.size
          else                 0
          end
        end
      end
    end
  end
end
