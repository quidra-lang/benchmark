# frozen_string_literal: true

class Scaling
  attr_reader :centers, :scales

  def initialize(rows, method)
    @centers = []
    @scales = []
    rows.first.features.each_index do |feature|
      values = rows.map { |row| row.features[feature] }
      if method == 'standard'
        center = values.reduce(0.0, :+) / rows.length.to_f
        squares = values.reduce(0.0) { |total, value| total + (value - center) * (value - center) }
        scale = rows.length == 1 ? 0.0 : Math.sqrt(squares / (rows.length - 1).to_f)
      else
        center = values.min
        scale = values.max - center
      end
      @centers << center
      @scales << scale
    end
  end

  def transform(row, features)
    features.map do |feature|
      @scales[feature].positive? ? (row.features[feature] - @centers[feature]) / @scales[feature] : 0.0
    end
  end
end
