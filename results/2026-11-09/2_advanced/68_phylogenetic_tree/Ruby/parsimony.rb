require_relative 'alignment'
require_relative 'tree_building'

module Parsimony
  def self.merge(a, b)
    common = a & b
    common.zero? ? [a | b, 1] : [common, 0]
  end
  def self.provisional(rooted, pattern)
    sets, changes = {}, 0
    rooted.order.reverse_each do |node|
      if node < rooted.tree.size
        sets[node] = pattern[node]
      else
        a, b = rooted.children[node].reject { |child| child == rooted.outgroup }
        sets[node], added = merge(sets[a], sets[b])
        changes += added
        changes += merge(sets[node], sets[rooted.outgroup])[1] if node == rooted.root
      end
    end
    [sets, changes]
  end
  def self.pattern_scores(tree, patterns, outgroup)
    rooted = tree.rooted(outgroup)
    patterns.encoded.map { |pattern| provisional(rooted, pattern)[1] }
  end
  def self.score(tree, patterns, outgroup)
    pattern_scores(tree, patterns, outgroup).zip(patterns.weights).sum { |change, weight| change * weight }
  end
  def self.reconstruct(tree, patterns, outgroup)
    rooted = tree.rooted(outgroup)
    ancestors = tree.internal_nodes.to_h { |node| [node, []] }
    branch_changes = tree.edges.to_h { |a, b, _| [[a, b], 0] }
    scores = []
    patterns.encoded.zip(patterns.weights).each do |pattern, weight|
      sets, changes = provisional(rooted, pattern)
      scores << changes
      combined = merge(sets[rooted.root], sets[outgroup])[0]
      first = combined & -combined
      states = {}
      [rooted.root, outgroup].each do |node|
        states[node] = (sets[node] & first).zero? ? sets[node] & -sets[node] : first
      end
      rooted.order.drop(1).each do |node|
        next if node == outgroup
        parent = states[rooted.parents[node]]
        states[node] = (sets[node] & parent).zero? ? sets[node] & -sets[node] : parent
      end
      ancestors.each_key { |node| ancestors[node] << Alignment::BASES[states[node].bit_length - 1] }
      branch_changes.each_key { |a, b| branch_changes[[a, b]] += weight if states[a] != states[b] }
    end
    sequences = ancestors.transform_values { |bases| patterns.columns.map { |index| bases[index] }.join }
    [sequences, branch_changes, patterns.columns.map { |index| scores[index] }]
  end
  def self.branches(tree, outgroup)
    rooted = tree.rooted(outgroup)
    rooted.order.drop(1).map do |node|
      [node == outgroup ? rooted.ingroup : rooted.masks[node], rooted.parents[node], node]
    end.sort
  end
  def self.insert(tree, a, b, taxon)
    result = tree.copy
    result.disconnect(a, b)
    node = result.internal
    result.adjacent[taxon] = {}
    [a, b, taxon].each { |child| result.connect(child, node) }
    result
  end
  def self.nni_candidates(tree, outgroup)
    return enum_for(__method__, tree, outgroup) unless block_given?
    rooted = tree.rooted(outgroup)
    branches(tree, outgroup).each do |mask, a, b|
      next if a < tree.size || b < tree.size
      sibling = rooted.children[a].find { |child| child != b && child != outgroup }
      rooted.children[b].sort_by { |child| rooted.masks[child] }.each_with_index do |child, index|
        result = tree.copy
        sibling_length = result.disconnect(a, sibling)
        child_length = result.disconnect(b, child)
        result.connect(a, child, child_length)
        result.connect(b, sibling, sibling_length)
        yield mask, index + 1, result
      end
    end
  end
end
