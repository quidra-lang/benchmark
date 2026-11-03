require 'csv'

module WaveformIO
  module_function

  def read_stations(path = 'input/stations.csv')
    CSV.read(path, headers: true).each_with_index.map do |row, index|
      {code: row['code'], x: row['x_m'].to_i, y: row['y_m'].to_i,
       elevation: row['elevation_m'].to_i, order: index}
    end
  end

  def read_waveforms(path = 'input/waveforms.txt')
    lines = File.readlines(path, chomp: true)
    result = {}
    cursor = 0
    while cursor < lines.length
      _, code, start, count = lines[cursor].split(' ')
      cursor += 1
      samples = []
      while samples.length < count.to_i
        samples.concat(lines[cursor].split(' ').map(&:to_i))
        cursor += 1
      end
      result[code] = {start: start.to_i, samples: samples}
    end
    result
  end

  def read_params(path = 'input/params.txt')
    File.readlines(path, chomp: true).to_h do |line|
      key, *words = line.split(' ')
      values = words.map { |word| word.include?('.') ? word.to_f : word.to_i }
      [key.to_sym, values.length == 1 ? values.first : values]
    end
  end

  def load
    stations = read_stations
    waveforms = read_waveforms
    stations.each { |station| station.merge!(waveforms[station[:code]]) }
    [stations, read_params]
  end
end
