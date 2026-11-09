class Hyphenation
  def self.letter?(character)
    character.match?(/\A[A-Za-z]\z/)
  end

  def initialize(lines, additions, left_min, right_min)
    @words = {}
    @left_min, @right_min = left_min, right_min
    (lines + additions).each { |spelling| register(spelling) }
  end

  def register(spelling)
    parts = spelling.split('-')
    position = 0
    points = parts[0...-1].map do |part|
      position += part.length
    end
    @words[parts.join] = points
  end

  def split_points(word)
    points = {}
    first, last = 0, word.length
    first += 1 while first < word.length && !self.class.letter?(word[first])
    last -= 1 while last > first && !self.class.letter?(word[last - 1])
    core = word[first...last]
    if !core.empty? && core.match?(/\A[A-Za-z]+\z/)
      @words.fetch(core.downcase, []).each do |position|
        if position >= @left_min && core.length - position >= @right_min
          points[first + position] = true
        end
      end
    end
    (1...(word.length - 1)).each do |position|
      if word[position] == '-' && self.class.letter?(word[position - 1]) && self.class.letter?(word[position + 1])
        points[position + 1] = false
      end
    end
    points.sort_by { |position, _append_hyphen| position }
  end
end
