module ArchiveCompressor
  class DecodeError < StandardError
    attr_reader :kind, :position

    def initialize(kind, position)
      @kind = kind
      @position = position
      super("#{kind} at #{position}")
    end
  end

  class BitWriter
    attr_reader :bit_count

    def initialize
      @data = ''.b
      @partial = @used = @bit_count = 0
    end

    def write(value, width)
      (width - 1).downto(0) do |shift|
        @partial = (@partial << 1) | ((value >> shift) & 1)
        @used += 1
        next unless @used == 8

        @data << @partial
        @partial = @used = 0
      end
      @bit_count += width
    end

    def finish
      @used.zero? ? @data.dup : @data + [@partial << (8 - @used)].pack('C')
    end
  end

  class BitReader
    attr_reader :position

    def initialize(payload, zero_fill: false)
      @payload = payload
      @position = 0
      @limit = payload.bytesize * 8
      @zero_fill = zero_fill
    end

    def read(width, output_position = 0)
      if !@zero_fill && @position + width > @limit
        raise DecodeError.new('end_of_data', output_position)
      end

      value = 0
      width.times do
        value <<= 1
        if @position < @limit
          value |= (@payload.getbyte(@position / 8) >> (7 - @position % 8)) & 1
        end
        @position += 1
      end
      value
    end
  end
end
