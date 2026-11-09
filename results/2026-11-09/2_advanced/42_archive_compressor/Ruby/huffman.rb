module ArchiveCompressor
  module Huffman
    module_function

    def tree_lengths(frequencies)
      lengths = Array.new(frequencies.length, 0)
      nodes = frequencies.each_with_index.filter_map do |weight, symbol|
        [weight, symbol, symbol] if weight.positive?
      end
      return lengths if nodes.empty?
      if nodes.length == 1
        lengths[nodes[0][1]] = 1
        return lengths
      end

      while nodes.length > 1
        nodes.sort_by! { |weight, minimum, _tree| [weight, minimum] }
        weight_a, minimum_a, first = nodes.shift
        weight_b, minimum_b, second = nodes.shift
        nodes << [weight_a + weight_b, [minimum_a, minimum_b].min, [first, second]]
      end
      pending = [[nodes[0][2], 0]]
      until pending.empty?
        node, depth = pending.pop
        if node.is_a?(Integer)
          lengths[node] = depth
        else
          pending << [node[0], depth + 1] << [node[1], depth + 1]
        end
      end
      lengths
    end

    def limited_lengths(frequencies, maximum)
      weights = frequencies.dup
      halvings = 0
      loop do
        lengths = tree_lengths(weights)
        return [lengths, halvings] if lengths.max <= maximum

        weights.map! { |weight| (weight + 1) / 2 }
        halvings += 1
      end
    end

    def canonical_codes(lengths)
      ordered = lengths.each_index.select { |symbol| lengths[symbol].positive? }
      ordered.sort_by! { |symbol| [lengths[symbol], symbol] }
      codes = Array.new(lengths.length, 0)
      code = previous_length = 0
      ordered.each_with_index do |symbol, index|
        length = lengths[symbol]
        code = (code + 1) << (length - previous_length) if index.positive?
        codes[symbol] = code
        previous_length = length
      end
      codes
    end
  end
end
