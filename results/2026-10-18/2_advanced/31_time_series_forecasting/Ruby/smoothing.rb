require_relative 'decomposition'

module Smoothing
  extend self

  def recurse(name, values, season, parameters)
    alpha = parameters[:alpha]
    beta = parameters.fetch(:beta, 0.0)
    phi = parameters.fetch(:phi, 1.0)
    gamma = parameters.fetch(:gamma, 0.0)
    seasonal = %w[hw_add hw_mult].include?(name)
    if seasonal
      level = Decomposition.mean(values.first(season))
      slope = (Decomposition.mean(values[season, season]) - level) / season
      components = values.first(season).map { |value| name == 'hw_add' ? value - level : value / level }
    else
      level = values.first
      slope = name == 'ses' ? 0.0 : (values[season] - values.first) / season
      components = nil
    end
    states = []
    residuals = []
    values.each_with_index do |observed, t|
      states << [level, slope, components&.dup]
      if name == 'ses'
        predicted = level
        next_level = alpha * observed + (1 - alpha) * level
        next_slope = slope
      elsif seasonal
        position = t % season
        previous = components[position]
        base = level + slope
        if name == 'hw_add'
          predicted = base + previous
          next_level = alpha * (observed - previous) + (1 - alpha) * base
          components[position] = gamma * (observed - base) + (1 - gamma) * previous
        else
          predicted = base * previous
          next_level = alpha * (observed / previous) + (1 - alpha) * base
          components[position] = gamma * (observed / base) + (1 - gamma) * previous
        end
        next_slope = beta * (next_level - level) + (1 - beta) * slope
      else
        predicted = level + phi * slope
        next_level = alpha * observed + (1 - alpha) * predicted
        next_slope = beta * (next_level - level) + (1 - beta) * phi * slope
      end
      residuals << observed - predicted
      level, slope = next_level, next_slope
    end
    states << [level, slope, components&.dup]
    [residuals, states]
  end

  def forecast(name, state, parameters, origin, steps, season)
    level, slope, components = state
    return Array.new(steps, level) if name == 'ses'

    if %w[holt damped].include?(name)
      phi = parameters.fetch(:phi, 1.0)
      power = phi
      accumulated = 0.0
      return Array.new(steps) do
        accumulated += power
        value = level + accumulated * slope
        power *= phi
        value
      end
    end
    (1..steps).map do |step|
      component = components[(origin + step - 1) % season]
      base = level + step * slope
      name == 'hw_add' ? base + component : base * component
    end
  end
end
