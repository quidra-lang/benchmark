module Verification
  CATEGORIES = %w[VFR MVFR IFR LIFR].freeze

  module_function

  def covers?(forecast, observation)
    hour = observation[:time] - observation[:time] % 60
    forecast[:time] <= observation[:time] && forecast[:start] <= hour && hour < forecast[:end]
  end

  def select_forecast(forecasts, observation)
    chosen = nil
    forecasts.each do |forecast|
      next unless covers?(forecast, observation)
      if chosen.nil? || forecast[:time] > chosen[:time] ||
         (forecast[:time] == chosen[:time] && forecast[:number] > chosen[:number])
        chosen = forecast
      end
    end
    chosen
  end

  def compare(observations, forecasts)
    table = Array.new(4) { Array.new(4, 0) }
    selected = []
    no_forecast = 0
    temporary_hits = 0
    observations.each do |observation|
      forecast = select_forecast(forecasts, observation)
      unless forecast
        no_forecast += 1
        next
      end
      hour = observation[:time] - observation[:time] % 60
      states = forecast[:hours][hour]
      category = states[:state][:category]
      actual = observation[:state][:category]
      possible = [category] + states[:temporary].map { |change| change[:state][:category] }
      table[CATEGORIES.index(category)][CATEGORIES.index(actual)] += 1
      temporary_hits += 1 if possible.include?(actual)
      selected << {observation:, forecast:, states:, possible:}
    end
    rows = table.map(&:sum)
    columns = Array.new(4) { |column| table.sum { |row| row[column] } }
    total = rows.sum
    hits = (0...4).sum { |index| table[index][index] }
    expected = (0...4).sum { |index| rows[index] * columns[index] }
    {table:, rows:, columns:, total:, hits:, temporary_hits:, no_forecast:, selected:,
     skill: [total * hits - expected, total * total - expected],
     pod: Array.new(4) { |index| [table[index][index], columns[index]] },
     far: Array.new(4) { |index| [rows[index] - table[index][index], rows[index]] }}
  end
end
