module SuffixArray
  SYMBOLS = '$#ACGT'
  SYMBOL_NUMBER = SYMBOLS.chars.each_with_index.to_h.freeze
  BASES = 'ACGT'
  def self.counting_sort(positions, keys, key_count)
    counts = Array.new(key_count, 0)
    positions.each { |position| counts[keys[position]] += 1 }
    offset = 0
    counts.each_with_index do |count, key|
      counts[key] = offset
      offset += count
    end
    result = Array.new(positions.size)
    positions.each do |position|
      key = keys[position]
      result[counts[key]] = position
      counts[key] += 1
    end
    result
  end

  def self.build(text)
    size = text.size
    positions = (0...size).to_a
    codes = text.chars.map { |symbol| SYMBOL_NUMBER.fetch(symbol) }
    order = counting_sort(positions, codes, SYMBOLS.size)
    ranks = Array.new(size)
    count, previous = 0, nil
    order.each do |position|
      if codes[position] != previous
        count += 1
        previous = codes[position]
      end
      ranks[position] = count - 1
    end
    classes, width = [count], 1
    while count < size
      second = positions.map { |position| position + width < size ? ranks[position + width] + 1 : 0 }
      order = counting_sort(counting_sort(positions, second, count + 1), ranks, count)
      updated = Array.new(size)
      count, previous = 0, nil
      order.each do |position|
        key = [ranks[position], second[position]]
        if key != previous
          count += 1
          previous = key
        end
        updated[position] = count - 1
      end
      ranks = updated
      classes << count
      width *= 2
    end
    [order, classes]
  end

  def self.direct_sort(text) = (0...text.size).sort_by { |position| text[position..] }

  def self.adjacent_check(text, suffixes)
    ordered = lcp_sum = 0
    longest, longest_row = -1, 1
    1.upto(suffixes.size - 1) do |row|
      left, right = suffixes[row - 1], suffixes[row]
      common = 0
      common += 1 while text[left + common] == text[right + common]
      ordered += 1 if SYMBOL_NUMBER.fetch(text[left + common]) < SYMBOL_NUMBER.fetch(text[right + common])
      lcp_sum += common
      longest, longest_row = common, row if common > longest
    end
    [ordered, lcp_sum, longest, longest_row]
  end
end
