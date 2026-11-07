# frozen_string_literal: true

require_relative 'evaluation'

module Pruning
  Decision = Struct.new(:node, :rows, :leaf_error, :subtree_error, :pruned, keyword_init: true)
  SequenceTree = Struct.new(:cuts, :alpha, :leaves, :errors, keyword_init: true)

  module_function

  def reduced_error(root, validation)
    counts = Hash.new(0)
    errors = Hash.new(0)
    validation.each do |row|
      Evaluation.route(root, row).path.each do |node|
        counts[node.number] += 1
        errors[node.number] += 1 if row.klass != node.stats.majority
      end
    end
    cuts = {}
    decisions = []
    visit = lambda do |node|
      leaf_error = errors[node.number]
      next leaf_error if node.split.nil?

      left_error = visit.call(node.left)
      right_error = visit.call(node.right)
      subtree_error = left_error + right_error
      prune = leaf_error <= subtree_error
      cuts[node.number] = true if prune
      decisions << Decision.new(node: node, rows: counts[node.number], leaf_error: leaf_error,
                                subtree_error: subtree_error, pruned: prune)
      prune ? leaf_error : subtree_error
    end
    visit.call(root)
    [cuts, decisions]
  end

  def complexity(node, cuts, candidates)
    return [1, node.stats.errors] if Evaluation.leaf?(node, cuts)

    left_leaves, left_errors = complexity(node.left, cuts, candidates)
    right_leaves, right_errors = complexity(node.right, cuts, candidates)
    leaves = left_leaves + right_leaves
    errors = left_errors + right_errors
    candidates << [node.number, Rational(node.stats.errors - errors, leaves - 1)]
    [leaves, errors]
  end

  def cost_complexity(root)
    cuts = {}
    alpha = Rational(0, 1)
    sequence = []
    loop do
      candidates = []
      leaves, errors = complexity(root, cuts, candidates)
      sequence << SequenceTree.new(cuts: cuts.dup, alpha: alpha / root.stats.size,
                                   leaves: leaves, errors: errors)
      break if candidates.empty?

      alpha = candidates.map(&:last).min
      candidates.each { |number, value| cuts[number] = true if value == alpha }
    end
    sequence
  end
end
