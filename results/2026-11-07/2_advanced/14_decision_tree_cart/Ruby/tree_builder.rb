# frozen_string_literal: true

require_relative 'impurity'

class TreeBuilder
  Split = Struct.new(:attribute, :value, keyword_init: true) do
    def left?(observed)
      attribute.type == 'INT' ? 2 * observed <= value : observed == value
    end

    def condition(left = true)
      if attribute.type == 'INT'
        "#{attribute.name} #{left ? '<=' : '>'} #{TreeBuilder.threshold(value)}"
      else
        "#{attribute.name} #{left ? '=' : '!='} #{attribute.values[value]}"
      end
    end
  end
  Surrogate = Struct.new(:split, :direction, :score, keyword_init: true)
  Node = Struct.new(:number, :depth, :rows, :stats, :split, :left, :right,
                    :surrogates, :default_left, keyword_init: true)
  Candidate = Struct.new(:split, :left_rows, :right_rows, :left_stats, :right_stats,
                         :quality, keyword_init: true)

  def self.threshold(value)
    "#{value.div(2)}.#{value.even? ? '0' : '5'}"
  end

  def initialize(attributes, class_count, settings)
    @attributes = attributes
    @class_count = class_count
    @max_depth = settings[:max_depth]
    @min_split = settings[:min_samples_split]
    @min_leaf = settings[:min_samples_leaf]
    @max_surrogates = settings[:max_surrogates]
  end

  def candidates(rows, attribute)
    values = rows.map { |row| row.values[attribute.index] }.uniq.sort
    return [] if values.length < 2

    parameters = if attribute.type == 'INT'
                   values.each_cons(2).map { |first, second| first + second }
                 else
                   values
                 end
    parameters.map { |value| Split.new(attribute: attribute, value: value) }
  end

  def best_for_attribute(rows, attribute)
    best = nil
    candidates(rows, attribute).each do |split|
      left, right = rows.partition { |row| split.left?(row.values[attribute.index]) }
      next if left.length < @min_leaf || right.length < @min_leaf

      left_stats = Impurity.statistics(left, @class_count)
      right_stats = Impurity.statistics(right, @class_count)
      quality = Impurity.quality(left_stats, right_stats)
      next if best && quality <= best.quality

      best = Candidate.new(split: split, left_rows: left, right_rows: right,
                           left_stats: left_stats, right_stats: right_stats, quality: quality)
    end
    best
  end

  def best_split(rows)
    best = nil
    @attributes.each do |attribute|
      candidate = best_for_attribute(rows, attribute)
      best = candidate if candidate && (!best || candidate.quality > best.quality)
    end
    best
  end

  def find_surrogates(rows, primary, left_size, right_size)
    return [] if @max_surrogates.zero?

    primary_directions = rows.map { |row| primary.left?(row.values[primary.attribute.index]) }
    surrogates = []
    @attributes.each do |attribute|
      next if attribute.index == primary.attribute.index

      best = nil
      candidates(rows, attribute).each do |split|
        agreement = 0
        rows.each_with_index do |row, index|
          agreement += 1 if split.left?(row.values[attribute.index]) == primary_directions[index]
        end
        direction = agreement >= rows.length - agreement ? :left : :right
        score = [agreement, rows.length - agreement].max
        best = Surrogate.new(split: split, direction: direction, score: score) if !best || score > best.score
      end
      surrogates << best if best && best.score > [left_size, right_size].max
    end
    surrogates.sort_by { |surrogate| [-surrogate.score, surrogate.split.attribute.index] }.first(@max_surrogates)
  end

  def grow(rows, number = 1, depth = 0)
    stats = Impurity.statistics(rows, @class_count)
    node = Node.new(number: number, depth: depth, rows: rows, stats: stats, surrogates: [])
    return node if stats.errors.zero? || depth == @max_depth || rows.length < @min_split

    best = best_split(rows)
    return node unless best && Impurity.improves?(best.quality, stats)

    node.split = best.split
    node.default_left = best.left_rows.length >= best.right_rows.length
    node.surrogates = find_surrogates(rows, best.split, best.left_rows.length, best.right_rows.length)
    node.left = grow(best.left_rows, number * 2, depth + 1)
    node.right = grow(best.right_rows, number * 2 + 1, depth + 1)
    node
  end
end
