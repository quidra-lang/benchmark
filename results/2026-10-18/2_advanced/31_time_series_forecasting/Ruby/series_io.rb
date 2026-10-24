require 'csv'
require 'fileutils'

module SeriesIO
  extend self

  def rows(name, &block)
    CSV.foreach(File.join('input', name), headers: true, encoding: 'US-ASCII', &block)
  end

  def read_inputs
    series = {}
    rows('series.csv') do |row|
      record = (series[row['series']] ||= { periods: [], raw: [] })
      record[:periods] << row['period']
      record[:raw] << (row['value'] == 'NA' ? nil : row['value'].to_i)
    end
    events = series.keys.to_h { |name| [name, {}] }
    rows('events.csv') { |row| events[row['series']][row['period']] = row['kind'] }
    inventory = {}
    rows('inventory.csv') do |row|
      inventory[row['series']] = {
        on_hand: row['on_hand'].to_i, lead_time: row['lead_time'].to_i,
        review: row['review'].to_i, service: row['service'].to_f
      }
    end
    settings = {}
    File.foreach('input/params.txt', encoding: 'US-ASCII') do |line|
      key, *values = line.split
      settings[key.to_sym] = case key
                            when 'alpha', 'beta', 'gamma', 'phi', 'interval'
                              values.map(&:to_f)
                            when 'ljung_box'
                              values.map(&:to_i)
                            when 'outlier'
                              values.first.to_f
                            else
                              values.first.to_i
                            end
    end
    [series, events, inventory, settings]
  end

  def next_month(period)
    year, month = period.split('-').map(&:to_i)
    year += 1 if month == 12
    month = month % 12 + 1
    format('%04d-%02d', year, month)
  end

  def real(value)
    return 'NA' if value.nil?

    result = format('%.4f', value)
    result == '-0.0000' ? '0.0000' : result
  end

  def write_lines(name, lines)
    FileUtils.mkdir_p('output')
    File.write(File.join('output', name), lines.join("\n") + "\n", encoding: 'US-ASCII')
  end
end
