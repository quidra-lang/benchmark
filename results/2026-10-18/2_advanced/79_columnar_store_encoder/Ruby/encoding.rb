require_relative 'bitstream'

module ValueEncoding
  METHODS = %w[PLAIN DICTIONARY RLE DELTA_BINARY_PACKED DELTA_LENGTH_BYTE_ARRAY].freeze
  CANDIDATES = { 'INT' => [0, 1, 3], 'DATE' => [0, 1, 3], 'STRING' => [0, 1, 4], 'BOOL' => [0, 2] }.freeze
  module_function

  def delta_encode(values)
    output = Bitstream.uleb(128) + Bitstream.uleb(4) + Bitstream.uleb(values.length) + Bitstream.zigzag(values.first || 0)
    values.each_cons(2).map { |first, second| second - first }.each_slice(128) do |block|
      minimum = block.min
      output << Bitstream.zigzag(minimum)
      miniblocks = 4.times.map { |index| (block[index * 32, 32] || []).map { |value| value - minimum } }
      widths = miniblocks.map { |mini| (mini.max || 0).bit_length }
      output << widths.pack('C*')
      miniblocks.zip(widths).each do |mini, width|
        output << Bitstream.pack_bits(mini + Array.new(32 - mini.length, 0), width) unless mini.empty?
      end
    end
    output
  end

  def delta_decode(reader)
    block_size, miniblock_count, count, first = reader.uleb, reader.uleb, reader.uleb, reader.zigzag
    values = count.zero? ? [] : [first]
    size = block_size / miniblock_count
    while values.length < count
      minimum = reader.zigzag
      widths = Array.new(miniblock_count) { reader.byte }
      widths.each do |width|
        break if values.length == count
        differences = Bitstream.unpack_bits(reader, width, size)
        differences.first([size, count - values.length].min).each { |value| values << values[-1] + minimum + value }
      end
    end
    values
  end

  def encode_values(type, method, values, dictionary = nil)
    case method
    when 0
      case type
      when 'INT', 'DATE' then values.map { |value| Bitstream.integer(value) }.join.b
      when 'STRING' then values.map { |value| Bitstream.integer(value.bytesize) + value.b }.join.b
      else
        bits = values.map { |value| value ? 1 : 0 }
        Bitstream.pack_bits(bits + Array.new((-bits.length) % 8, 0), 1)
      end
    when 1
      width = (dictionary.length - 1).bit_length
      ranks = dictionary.each_with_index.to_h
      [width].pack('C') + Bitstream.hybrid_encode(values.map { |value| ranks.fetch(value) }, width)
    when 2
      code = Bitstream.hybrid_encode(values.map { |value| value ? 1 : 0 }, 1)
      Bitstream.integer(code.bytesize) + code
    when 3 then delta_encode(values)
    when 4 then delta_encode(values.map(&:bytesize)) + values.join.b
    end
  end

  def decode_values(reader, type, method, count, dictionary = nil)
    case method
    when 0
      case type
      when 'INT', 'DATE' then Array.new(count) { reader.integer(true) }
      when 'STRING' then Array.new(count) { reader.read(reader.integer) }
      else Bitstream.unpack_bits(reader, 1, (count + 7) / 8 * 8).first(count).map { |value| value == 1 }
      end
    when 1
      width = reader.byte
      Bitstream.hybrid_decode(reader, width, count).map { |index| dictionary.fetch(index) }
    when 2
      code = Bitstream::Reader.new(reader.read(reader.integer))
      Bitstream.hybrid_decode(code, 1, count).map { |value| value == 1 }
    when 3 then delta_decode(reader)
    when 4 then delta_decode(reader).map { |length| reader.read(length) }
    end
  end

  def encode_statistics(type, bounds)
    return "\x00".b unless bounds
    output = "\x01".b
    bounds.each do |value|
      output << case type
                when 'INT', 'DATE' then Bitstream.zigzag(value)
                when 'STRING' then Bitstream.uleb(value.bytesize) + value.b
                else [value ? 1 : 0].pack('C')
                end
    end
    output
  end

  def decode_statistics(reader, type)
    return nil if reader.byte.zero?
    Array.new(2) do
      case type
      when 'INT', 'DATE' then reader.zigzag
      when 'STRING' then reader.read(reader.uleb)
      else reader.byte == 1
      end
    end
  end
end
