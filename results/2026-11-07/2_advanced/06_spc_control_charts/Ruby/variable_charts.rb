# frozen_string_literal: true

require_relative 'dataset'

module VariableCharts
  Subgroup = Struct.new(:number, :total, :squares, :mean, :range, :sd, keyword_init: true)
  Limits = Struct.new(:lcl, :cl, :ucl, keyword_init: true) do
    def outside?(value)
      value > ucl || value < lcl
    end
  end
  Estimate = Struct.new(:limits, :sequences, keyword_init: true)

  module_function

  def statistics(samples, size)
    samples.each_slice(size).with_index.map do |values, index|
      total = values.sum
      squares = values.sum { |value| value * value }
      variance = (size * squares - total * total).to_f / (size * (size - 1)).to_f
      Subgroup.new(number: index + 1, total: total, squares: squares, mean: total.to_f / size.to_f,
                   range: values.max - values.min, sd: Math.sqrt(variance))
    end
  end

  def estimate(family, points, subgroups, samples, size, constants)
    points = points.sort
    return individual_estimate(points, samples) if family == 'I_MR'

    selected = points.map { |point| subgroups[point - 1] }
    center = selected.sum(&:total).to_f / (points.length * size).to_f
    if family == 'XBAR_R'
      spread = selected.sum(&:range).to_f / points.length.to_f
      multiplier, lower, upper = constants.values_at(:a2, :d3, :d4)
      values = selected.map(&:range)
    else
      total = 0.0
      selected.each { |subgroup| total += subgroup.sd }
      spread = total / points.length.to_f
      multiplier, lower, upper = constants.values_at(:a3, :b3, :b4)
      values = selected.map(&:sd)
    end
    limits = [Limits.new(lcl: center - multiplier * spread, cl: center, ucl: center + multiplier * spread),
              Limits.new(lcl: lower * spread, cl: spread, ucl: upper * spread)]
    sequences = [points.zip(selected.map(&:mean)), points.zip(values)]
    Estimate.new(limits: limits, sequences: sequences)
  end

  def individual_estimate(points, samples)
    values = points.map { |point| samples[point - 1] }
    moving = values.each_cons(2).map { |first, second| (second - first).abs }
    center = values.sum.to_f / values.length.to_f
    average = moving.sum.to_f / moving.length.to_f
    constants = Dataset::CONSTANTS.fetch(2)
    width = 3 * average / constants[:d2]
    limits = [Limits.new(lcl: center - width, cl: center, ucl: center + width),
              Limits.new(lcl: constants[:d3] * average, cl: average, ucl: constants[:d4] * average)]
    Estimate.new(limits: limits, sequences: [points.zip(values), points.drop(1).zip(moving)])
  end
end
