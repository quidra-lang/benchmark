require 'set'
require_relative 'tac_parser'

module TAC
  Block = Struct.new(:id, :labels, :instructions, :preds, :succs, :dom, :idom, :depth, keyword_init: true) do
    def to_s = "B#{id}"
    def hash = id.hash
    def eql?(other) = other.is_a?(Block) && id == other.id
    def ==(other) = eql?(other)
  end
  Loop = Struct.new(:header, :latches, :blocks, :exits, :outside, :depth, keyword_init: true)
  class CFG
    attr_reader :blocks, :postorder, :order, :reachable, :loops, :owner
    def initialize(function)
      function.number!
      @blocks, labels, current = [], [], nil
      function.code.each do |s|
        if s.is_a?(String)
          labels << s
          current = nil
        else
          unless current
            current = Block.new(id: blocks.length + 1, labels: labels, instructions: [], preds: [], succs: [], depth: 0)
            blocks << current
            labels = []
          end
          current.instructions << s
          current = nil if %i[goto if return].include?(s.kind)
        end
      end
      targets = blocks.flat_map { |b| b.labels.map { |l| [l, b] } }.to_h
      @owner = {}
      blocks.each_with_index do |b, i|
        b.instructions.each { |s| owner[s.number] = b }
        s = b.instructions.last
        b.succs = case s.kind
                  when :goto then [targets.fetch(s.target)]
                  when :if then [blocks[i + 1], targets.fetch(s.target)].compact.uniq
                  when :return then []
                  else [blocks[i + 1]].compact
                  end
        b.succs.each { |v| v.preds << b }
      end
      @postorder, seen = [], Set.new
      visit = lambda do |b|
        return unless seen.add?(b.id)
        b.succs.each { |v| visit.call(v) }
        postorder << b
      end
      visit.call(blocks.first)
      @order, @reachable = postorder.reverse, blocks.select { |b| seen.include?(b.id) }
      reachable.each { |b| b.dom = b == blocks.first ? Set[b.id] : seen.dup }
      loop do
        changed = false
        order.drop(1).each do |b|
          d = b.preds.select { |p| seen.include?(p.id) }.map(&:dom).reduce { |a, v| a & v } | Set[b.id]
          changed ||= d != b.dom
          b.dom = d
        end
        break unless changed
      end
      reachable.drop(1).each { |b| b.idom = reachable.select { |d| d.id != b.id && b.dom.include?(d.id) }.max_by { |d| d.dom.size } }
      @loops = []
      reachable.each do |h|
        latches = h.preds.select { |t| seen.include?(t.id) && t.dom.include?(h.id) }
        next if latches.empty?
        members, work = Set[h.id], latches.dup
        until work.empty?
          t = work.pop
          next unless members.add?(t.id)
          work.concat(t.preds.select { |p| seen.include?(p.id) }) unless t == h
        end
        bs = reachable.select { |b| members.include?(b.id) }
        outside = bs.flat_map(&:succs).reject { |b| members.include?(b.id) }.uniq
        exits = bs.select { |b| b.instructions.last.kind == :return || b.succs.any? { |v| !members.include?(v.id) } }
        loops << Loop.new(header: h, latches: latches, blocks: bs, exits: exits, outside: outside)
      end
      loops.each { |l| l.depth = loops.count { |v| v.blocks.include?(l.header) } }
      blocks.each { |b| b.depth = loops.count { |l| l.blocks.include?(b) } }
    end
  end
end
