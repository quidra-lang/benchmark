require_relative 'bitio'

module ArchiveCompressor
  module ArithCoder
    TOP = 65535
    HALF = 32768
    QUARTER = 16384
    THREE = 49152
    EOF_CODE = 256
    Statistics = Struct.new(:bits, :contexts, :rescales, keyword_init: true)

    class FrequencyTable
      attr_reader :total, :rescales

      def initialize
        @frequencies = Array.new(257, 1)
        @total = 257
        @rescales = 0
      end

      def interval(symbol)
        [@frequencies.take(symbol).sum, @frequencies[symbol]]
      end

      def locate(value)
        cumulative = 0
        @frequencies.each_with_index do |frequency, symbol|
          return [symbol, cumulative, frequency] if value < cumulative + frequency

          cumulative += frequency
        end
      end

      def update(symbol)
        @frequencies[symbol] += 32
        @total += 32
        return if @total < 8192

        @frequencies.map! { |frequency| (frequency + 1) / 2 }
        @total = @frequencies.sum
        @rescales += 1
      end
    end

    module_function

    def encode(data)
      writer = BitWriter.new
      tables = Hash.new { |hash, context| hash[context] = FrequencyTable.new }
      low = 0
      high = TOP
      follow = 0
      context = 10
      emit = lambda do |bit|
        writer.write(bit, 1)
        follow.times { writer.write(1 - bit, 1) }
        follow = 0
      end
      (data.bytes + [EOF_CODE]).each do |symbol|
        table = tables[context]
        cumulative, frequency = table.interval(symbol)
        span = high - low + 1
        high = low + span * (cumulative + frequency) / table.total - 1
        low += span * cumulative / table.total
        loop do
          if high < HALF
            emit.call(0)
          elsif low >= HALF
            emit.call(1)
            low -= HALF
            high -= HALF
          elsif low >= QUARTER && high < THREE
            follow += 1
            low -= QUARTER
            high -= QUARTER
          else
            break
          end
          low *= 2
          high = high * 2 + 1
        end
        unless symbol == EOF_CODE
          table.update(symbol)
          context = symbol
        end
      end
      follow += 1
      emit.call(low < QUARTER ? 0 : 1)
      stats = Statistics.new(bits: writer.bit_count, contexts: tables.length,
                             rescales: tables.values.sum(&:rescales))
      [writer.finish, stats]
    end

    def decode(payload, original_size)
      reader = BitReader.new(payload, zero_fill: true)
      tables = Hash.new { |hash, context| hash[context] = FrequencyTable.new }
      output = ''.b
      low = 0
      high = TOP
      value = reader.read(16)
      context = 10
      loop do
        table = tables[context]
        span = high - low + 1
        quantile = ((value - low + 1) * table.total - 1) / span
        symbol, cumulative, frequency = table.locate(quantile)
        high = low + span * (cumulative + frequency) / table.total - 1
        low += span * cumulative / table.total
        loop do
          offset = if high < HALF
                     0
                   elsif low >= HALF
                     HALF
                   elsif low >= QUARTER && high < THREE
                     QUARTER
                   else
                     break
                   end
          low = (low - offset) * 2
          high = (high - offset) * 2 + 1
          value = (value - offset) * 2 + reader.read(1)
        end
        if symbol == EOF_CODE
          raise DecodeError.new('early_end', output.bytesize) if output.bytesize < original_size

          return output
        end
        raise DecodeError.new('overrun', output.bytesize) if output.bytesize == original_size

        output << symbol
        table.update(symbol)
        context = symbol
      end
    end
  end
end
