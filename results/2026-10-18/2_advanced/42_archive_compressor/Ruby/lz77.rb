require_relative 'bitio'

module ArchiveCompressor
  module LZ77
    module_function

    def tokenize(data, offset_bits, length_bits)
      window = 1 << offset_bits
      lookahead = (1 << length_bits) + 2
      prefixes = Hash.new { |hash, key| hash[key] = [] }
      tokens = []
      position = 0
      while position < data.bytesize
        distance = longest = 0
        limit = [lookahead, data.bytesize - position].min
        if limit >= 3
          # Reverse positions are increasing distances: the first tie wins.
          prefixes[data.byteslice(position, 3)].reverse_each do |start|
            break if start < position - window

            candidate_distance = position - start
            length = 3
            while length < limit &&
                  data.getbyte(position + length) == data.getbyte(position + length - candidate_distance)
              length += 1
            end
            if length > longest
              distance = candidate_distance
              longest = length
            end
            break if longest == limit
          end
        end
        if longest >= 3
          tokens << [distance, longest]
          consumed = longest
        else
          tokens << data.getbyte(position)
          consumed = 1
        end
        # Match interiors are eligible starting positions for later matches.
        (position...[position + consumed, data.bytesize - 2].min).each do |start|
          prefixes[data.byteslice(start, 3)] << start
        end
        position += consumed
      end
      tokens
    end

    def copy_match(output, distance, length, original_size)
      raise DecodeError.new('bad_offset', output.bytesize) if distance > output.bytesize
      if output.bytesize + length > original_size
        raise DecodeError.new('overrun', output.bytesize)
      end

      length.times { output << output.getbyte(output.bytesize - distance) }
    end
  end
end
