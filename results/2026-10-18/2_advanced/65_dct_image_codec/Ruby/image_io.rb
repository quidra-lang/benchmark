require_relative 'entropy'

module ImageIO
  module_function

  def read_ppm(path)
    lines = File.readlines(path, chomp: true)
    _width, height = lines[1].split.map(&:to_i)
    lines[3, height].map { |line| line.split.map(&:to_i).each_slice(3).to_a }
  end

  def write_ppm(path, image)
    File.open(path, 'w') do |file|
      file.puts 'P3', "#{image.first.length} #{image.length}", '255'
      image.each { |row| file.puts row.flatten.join(' ') }
    end
  end

  def read_params(path)
    File.readlines(path).to_h do |line|
      name, *values = line.split
      value = if %w[sampling huffman].include?(name)
                values.first
              elsif %w[qualities truncate].include?(name)
                values.map(&:to_i)
              else
                values.first.to_i
              end
      [name, value]
    end
  end

  def read_tables(path)
    lines = File.readlines(path).each
    lines.next
    transform = Array.new(8) { lines.next.split.map(&:to_i) }
    quantization = Array.new(2) do
      lines.next
      Array.new(8) { lines.next.split.map(&:to_i) }
    end
    huffman = {}
    4.times do
      _, table_class, identifier = lines.next.split
      counts = lines.next.split.map(&:to_i)
      symbols = lines.next.split.map(&:to_i)
      huffman[[table_class.to_i, identifier.to_i]] = Entropy::HuffmanTable.new(counts, symbols)
    end
    [transform, quantization, huffman]
  end

  def read_hex(path)
    File.read(path).split.join.scan(/../).map { |pair| pair.to_i(16) }
  end

  def write_hex(path, data)
    File.open(path, 'w') do |file|
      data.each_slice(32) { |bytes| file.puts bytes.map { |v| format('%02x', v) }.join }
    end
  end
end
