module PgmIO
  module_function

  def read_pgm(path)
    lines = File.readlines(path, chomp: true)
    width, height = lines[1].split.map(&:to_i)
    [width, height, lines.drop(3).flat_map { |line| line.split.map(&:to_i) }]
  end

  def read_parameters(path = 'input/params.txt')
    params = { 'sample_pixels' => [] }
    File.foreach(path) do |line|
      key, *values = line.split
      if key == 'sample'
        params['sample_pixels'] << values.map(&:to_i)
      elsif %w[wta_cost sgm_cost].include?(key)
        params[key] = values.first
      elsif key.end_with?('_windows')
        params[key] = values.map(&:to_i)
      else
        params[key] = values.first.to_i
      end
    end
    params
  end

  def write_pgm(path, width, height, pixels)
    File.open(path, 'w') do |file|
      file.puts 'P2', "#{width} #{height}", '255'
      pixels.each_slice(width) { |row| file.puts row.join(' ') }
    end
  end
end
