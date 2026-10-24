class WordIndex
  attr_reader :scores, :ranked, :by_length

  def self.valid_word?(word)
    /\A[A-Z]{3,15}\z/.match?(word)
  end

  def self.valid_integer?(text, minimum, maximum)
    /\A[1-9][0-9]*\z/.match?(text) && text.to_i.between?(minimum, maximum)
  end

  def self.word_line_error(line)
    return 'bad format' unless line.count(' ') == 1

    word, _, score = line.partition(' ')
    return 'bad word' unless valid_word?(word)
    return 'bad score' unless valid_integer?(score, 1, 100)

    nil
  end

  def self.clue_line_error(line)
    return 'bad format' unless line.count('|') == 1

    word, _, clue = line.partition('|')
    return 'bad word' unless valid_word?(word)
    return 'bad clue' unless clue.length.between?(1, 60) &&
                             !clue.start_with?(' ') && !clue.end_with?(' ')

    nil
  end

  def initialize(scores)
    @scores = scores
    @ranked = scores.keys.sort_by { |word| [-scores.fetch(word), word] }
    @by_length = Hash.new { |hash, length| hash[length] = [] }
    @by_position = Hash.new { |hash, key| hash[key] = [] }
    @ranked.each do |word|
      @by_length[word.length] << word
      word.each_char.with_index do |letter, position|
        @by_position[[word.length, position, letter]] << word
      end
    end
  end

  def candidates(pattern, minimum, used)
    pool = @by_length.fetch(pattern.length, [])
    known = []
    pattern.each_char.with_index do |letter, position|
      next if letter == '.'

      known << [position, letter]
      matching = @by_position.fetch([pattern.length, position, letter], [])
      pool = matching if matching.length < pool.length
    end
    result = []
    pool.each do |word|
      break if @scores.fetch(word) < minimum
      next if used.include?(word)
      next unless known.all? { |position, letter| word[position] == letter }

      result << word
    end
    result
  end
end
