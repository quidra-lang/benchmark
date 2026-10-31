require_relative 'bitio'

module ArchiveCompressor
  module LZW
    CLEAR = 256
    END_CODE = 257
    FIRST = 258
    LIMIT = 4096
    Statistics = Struct.new(:codes, :clears, :widths, :longest, keyword_init: true)

    module_function

    def initial_dictionary
      256.times.to_h { |value| [value.chr(Encoding::BINARY), value] }
    end

    def encode(data)
      writer = BitWriter.new
      stats = Statistics.new(codes: 0, clears: 0, widths: Array.new(4, 0), longest: 0)
      dictionary = initial_dictionary
      next_code = FIRST
      since_clear = 0
      emit = lambda do |code, length = 0|
        width = [12, (FIRST + since_clear).bit_length].min
        writer.write(code, width)
        stats.codes += 1
        stats.widths[width - 9] += 1
        stats.longest = [stats.longest, length].max
        if code == CLEAR
          stats.clears += 1
          since_clear = 0
        else
          since_clear += 1
        end
      end
      emit.call(CLEAR)
      sequence = ''.b
      data.each_byte do |value|
        byte = value.chr(Encoding::BINARY)
        extended = sequence + byte
        if dictionary.key?(extended)
          sequence = extended
          next
        end
        emit.call(dictionary.fetch(sequence), sequence.bytesize)
        dictionary[extended] = next_code
        next_code += 1
        if next_code == LIMIT
          emit.call(CLEAR)
          dictionary = initial_dictionary
          next_code = FIRST
        end
        sequence = byte
      end
      emit.call(dictionary.fetch(sequence), sequence.bytesize) unless sequence.empty?
      emit.call(END_CODE)
      [writer.finish, stats]
    end

    def decode(payload, original_size)
      reader = BitReader.new(payload)
      dictionary = Array.new(256) { |value| value.chr(Encoding::BINARY) } + [nil, nil]
      previous = nil
      since_clear = 0
      output = ''.b
      loop do
        count = since_clear
        width = [12, (FIRST + count).bit_length].min
        code = reader.read(width, output.bytesize)
        if code == CLEAR
          dictionary = Array.new(256) { |value| value.chr(Encoding::BINARY) } + [nil, nil]
          previous = nil
          since_clear = 0
          next
        end
        since_clear += 1
        if code == END_CODE
          raise DecodeError.new('early_end', output.bytesize) if output.bytesize < original_size

          return output
        end
        raise DecodeError.new('bad_code', output.bytesize) if count == LIMIT - FIRST

        sequence = if previous.nil?
                     raise DecodeError.new('bad_code', output.bytesize) if code >= 256

                     dictionary[code]
                   elsif code < dictionary.length
                     dictionary[code]
                   elsif code == dictionary.length
                     dictionary[previous] + dictionary[previous].byteslice(0, 1)
                   else
                     raise DecodeError.new('bad_code', output.bytesize)
                   end
        if output.bytesize + sequence.bytesize > original_size
          raise DecodeError.new('overrun', output.bytesize)
        end
        output << sequence
        dictionary << dictionary[previous] + sequence.byteslice(0, 1) unless previous.nil?
        previous = code
      end
    end
  end
end
