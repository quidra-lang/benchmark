# frozen_string_literal: true

require 'set'

module Apriori
  class SupportCounter
    def initialize(baskets)
      @total = baskets.length
      @postings = Hash.new { |hash, item| hash[item] = Set.new }
      baskets.each_with_index do |basket, index|
        basket.each { |item| @postings[item].add(index) }
      end
      @cache = { [] => @total }
    end

    def count(itemset)
      key = itemset.sort
      return @cache[key] if @cache.key?(key)

      lists = key.map { |item| @postings[item] }
      shortest = lists.min_by(&:length)
      @cache[key] = shortest.count { |index| lists.all? { |list| list.include?(index) } }
    end
  end

  def self.candidates(previous, size, categories = nil)
    membership = Set.new(previous)
    groups = previous.sort.group_by { |itemset| itemset.take(size - 2) }
    remaining = []
    joined = 0
    excluded = 0
    pruned = 0
    groups.each_value do |group|
      group.combination(2) do |left, right|
        joined += 1
        candidate = left + [right.last]
        if categories && size == 2 &&
           (categories[candidate[0]] == candidate[1] || categories[candidate[1]] == candidate[0])
          excluded += 1
        elsif candidate.each_index.any? { |index| !membership.include?(candidate.take(index) + candidate.drop(index + 1)) }
          pruned += 1
        else
          remaining << candidate
        end
      end
    end
    [remaining.sort, { candidates: joined, excluded: excluded, pruned: pruned, counted: remaining.length }]
  end

  def self.count(candidates, counter)
    candidates.to_h { |itemset| [itemset, counter.count(itemset)] }
  end
end
