module Bitstream
  class DecodeError < StandardError
    attr_reader :kind
    def initialize(kind)
      @kind = kind
      super(kind)
    end
  end

  class BitWriter
    attr_reader :data, :padding_bits, :stuffed_bytes

    def initialize
      @data = []
      @buffer = @pending = @padding_bits = @stuffed_bytes = 0
    end

    def write(value, width)
      (width - 1).downto(0) do |shift|
        @buffer = 2 * @buffer + ((value >> shift) & 1)
        @pending += 1
        next unless @pending == 8
        @data << @buffer
        if @buffer == 0xff
          @data << 0
          @stuffed_bytes += 1
        end
        @buffer = @pending = 0
      end
    end

    def pad
      return if @pending.zero?
      width = 8 - @pending
      @padding_bits += width
      write((1 << width) - 1, width)
    end

    def restart(number)
      pad
      @data.concat([0xff, 0xd0 + number % 8])
    end
  end

  class BitReader
    attr_accessor :position

    def initialize(data, position)
      @data, @position = data, position
      @buffer = @remaining = 0
    end

    def bit
      if @remaining.zero?
        value = @data[@position]
        if value == 0xff
          raise DecodeError, 'marker' if @data[@position + 1] != 0
          @position += 2
        else
          @position += 1
        end
        @buffer = value
        @remaining = 8
      end
      @remaining -= 1
      (@buffer >> @remaining) & 1
    end

    def read(width)
      value = 0
      width.times { value = 2 * value + bit }
      value
    end

    def discard
      @buffer = @remaining = 0
    end
  end

  def self.find_resync(data, position)
    (position...data.length - 1).find do |q|
      data[q] == 0xff && (data[q + 1].between?(0xd0, 0xd7) || data[q + 1] == 0xd9)
    end
  end
end
