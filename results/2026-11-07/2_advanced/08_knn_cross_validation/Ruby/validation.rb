# frozen_string_literal: true

require_relative 'scaling'
require_relative 'neighbors'

module Validation
  def self.folds(rows, count)
    assignment = {}
    rows.sort_by { |row| [row.label, row.id] }.each_with_index { |row, index| assignment[row.id] = index % count }
    Array.new(count) { |index| rows.select { |row| assignment[row.id] == index } }
  end

  class Predictor
    def initialize(rows, features)
      @rows = rows
      @features = features
      @scalings = {}
      @vectors = {}
      @orders = {}
    end

    def order(query, model)
      method = model[:scaling]
      unless @scalings.key?(method)
        @scalings[method] = Scaling.new(@rows, method)
        @vectors[method] = @rows.to_h { |row| [row.id, @scalings[method].transform(row, @features)] }
      end
      key = [query.id, method, model[:metric]]
      @orders[key] ||= Neighbors.order(@scalings[method].transform(query, @features), @rows, @vectors[method], model[:metric])
    end

    def predict(query, model)
      Neighbors.vote(order(query, model), model[:k], model[:weighting])
    end
  end

  def self.errors(rows, predictions)
    return { rmse: nil, mae: nil, r2: nil } if rows.empty?

    squares = absolute = 0.0
    rows.each do |row|
      residual = predictions.fetch(row.id).estimate - row.target
      squares += residual * residual
      absolute += residual.abs
    end
    mean = rows.reduce(0.0) { |total, row| total + row.target } / rows.length.to_f
    variance = rows.reduce(0.0) { |total, row| total + (row.target - mean) * (row.target - mean) }
    { rmse: Math.sqrt(squares / rows.length.to_f), mae: absolute / rows.length.to_f,
      r2: variance.zero? ? nil : 1.0 - squares / variance }
  end
end
