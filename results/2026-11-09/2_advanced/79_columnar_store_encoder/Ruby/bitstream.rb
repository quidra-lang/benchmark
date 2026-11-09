module Bitstream
  class Reader
    attr_accessor :position

    def initialize(data, position = 0)
      @data, @position = data, position
    end

    def read(count)
      result = @data.byteslice(@position, count)
      @position += count
      result
    end

    def byte
      result = @data.getbyte(@position)
      @position += 1
      result
    end

    def uleb
      value, shift = 0, 0
      loop do
        item = byte
        value |= (item & 127) << shift
        return value if item < 128
        shift += 7
      end
    end

    def zigzag
      value = uleb
      value.even? ? value / 2 : -(value + 1) / 2
    end

    def integer(signed = false)
      value = read(4).unpack1('V')
      signed && value >= 2**31 ? value - 2**32 : value
    end
  end

  module_function

  def uleb(value)
    bytes = []
    while value >= 128
      bytes << (value % 128 + 128)
      value /= 128
    end
    (bytes << value).pack('C*')
  end

  def zigzag(value)
    uleb(value >= 0 ? 2 * value : -2 * value - 1)
  end

  def integer(value)
    [value & 0xffffffff].pack('V')
  end

  def pack_bits(values, width)
    bytes, buffer, occupied = [], 0, 0
    values.each do |value|
      buffer |= value << occupied
      occupied += width
      while occupied >= 8
        bytes << (buffer & 255)
        buffer >>= 8
        occupied -= 8
      end
    end
    bytes.pack('C*')
  end

  def unpack_bits(reader, width, count)
    buffer, occupied, mask = 0, 0, (1 << width) - 1
    Array.new(count) do
      while occupied < width
        buffer |= reader.byte << occupied
        occupied += 8
      end
      value = buffer & mask
      buffer >>= width
      occupied -= width
      value
    end
  end

  def adler32(data)
    first, second = 1, 0
    data.each_byte do |byte|
      first = (first + byte) % 65521
      second = (second + first) % 65521
    end
    second * 65536 + first
  end

  def hybrid_encode(values, width)
    count = values.length
    runs = Array.new(count, 1)
    (count - 2).downto(0) { |index| runs[index] += runs[index + 1] if values[index] == values[index + 1] }
    output, index = ''.b, 0
    while index < count
      if runs[index] >= 8
        output << uleb(2 * runs[index])
        ((width + 7) / 8).times { |byte| output << ((values[index] >> (8 * byte)) & 255) }
        index += runs[index]
      else
        finish, groups = index, 0
        loop do
          finish += 8
          groups += 1
          break if finish >= count || groups == 63 || runs[finish] >= 8
        end
        output << uleb(2 * groups + 1)
        block = values[index...[finish, count].min]
        output << pack_bits(block + Array.new(finish - index - block.length, 0), width)
        index = finish
      end
    end
    output
  end

  def hybrid_decode(reader, width, count)
    values = []
    while values.length < count
      header = reader.uleb
      if header.even?
        value = 0
        ((width + 7) / 8).times { |index| value |= reader.byte << (8 * index) }
        values.concat(Array.new(header / 2, value))
      else
        values.concat(unpack_bits(reader, width, (header - 1) / 2 * 8))
      end
    end
    values.first(count)
  end
end
