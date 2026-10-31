
WORD_PATTERN = /\A[A-Za-z]{1,30}\z/
NUMBER_PATTERN = /\A[0-9]{1,7}\z/
PREFIX_TERM_PATTERN = /\A[A-Za-z]{1,30}\*\z/
LEXEME_PATTERN = /[()]|[^ ()]+/
OPERATORS = %w[AND OR NOT].freeze
PARENTHESES = %w[( )].freeze
CONJUNCTION_CONTINUATIONS = %w[AND NOT ( term prefix].freeze
VOWELS = 'aeiou'
STEP_NAMES = %w[1a 1b 1c 2 3 4 5a 5b].freeze
STEP_4_SUFFIXES = %w[
  al ance ence er ic able ible ant ement ment ent ion ou ism ate iti ous ive ize
].freeze
KWIC_WIDTH = 30
MAX_COUNT = 100
MAX_DOCUMENT_NUMBER = 999
MAX_LINE_NUMBER = 999

class CommandError < StandardError; end

Rule = Data.define(:suffix, :replacement, :condition)

def letter_pattern(word)
  kinds = []
  word.each_char.with_index do |letter, index|
    vowel = VOWELS.include?(letter) || (letter == 'y' && index.positive? && kinds[-1] == 'C')
    kinds << (vowel ? 'V' : 'C')
  end
  kinds.join
end

def measure(word) = letter_pattern(word).scan('VC').size

def vowel?(word) = letter_pattern(word).include?('V')

def ends_double?(word) = letter_pattern(word).end_with?('CC') && word[-1] == word[-2]

def ends_cvc?(word) = letter_pattern(word).end_with?('CVC') && !'wxy'.include?(word[-1])

ALWAYS = ->(_remainder) { true }
MEASURE_ABOVE_ZERO = ->(remainder) { measure(remainder).positive? }
MEASURE_ABOVE_ONE = ->(remainder) { measure(remainder) > 1 }
ION_CONDITION = ->(remainder) { measure(remainder) > 1 && remainder.end_with?('s', 't') }
FINAL_E_CONDITION = lambda do |remainder|
  value = measure(remainder)
  value > 1 || (value == 1 && !ends_cvc?(remainder))
end

def rules_with(condition, replacements)
  replacements.map { |suffix, replacement| Rule.new(suffix, replacement, condition) }
end

RULE_TABLES = {
  '1a' => rules_with(ALWAYS, { 'sses' => 'ss', 'ies' => 'i', 'ss' => 'ss', 's' => '' }),
  '1b' => [
    Rule.new('eed', 'ee', MEASURE_ABOVE_ZERO),
    Rule.new('ed', '', method(:vowel?)),
    Rule.new('ing', '', method(:vowel?)),
  ],
  '1c' => [Rule.new('y', 'i', method(:vowel?))],
  '2' => rules_with(MEASURE_ABOVE_ZERO, {
    'ational' => 'ate', 'tional' => 'tion', 'enci' => 'ence', 'anci' => 'ance',
    'izer' => 'ize', 'abli' => 'able', 'alli' => 'al', 'entli' => 'ent', 'eli' => 'e',
    'ousli' => 'ous', 'ization' => 'ize', 'ation' => 'ate', 'ator' => 'ate',
    'alism' => 'al', 'iveness' => 'ive', 'fulness' => 'ful', 'ousness' => 'ous',
    'aliti' => 'al', 'iviti' => 'ive', 'biliti' => 'ble'
  }),
  '3' => rules_with(MEASURE_ABOVE_ZERO, {
    'icate' => 'ic', 'ative' => '', 'alize' => 'al', 'iciti' => 'ic',
    'ical' => 'ic', 'ful' => '', 'ness' => ''
  }),
  '4' => STEP_4_SUFFIXES.map do |suffix|
    Rule.new(suffix, '', suffix == 'ion' ? ION_CONDITION : MEASURE_ABOVE_ONE)
  end,
  '5a' => [Rule.new('e', '', FINAL_E_CONDITION)],
}.freeze

def apply_rules(word, rules)
  matching = rules.select { |candidate| word.end_with?(candidate.suffix) }
  rule = matching.max_by { |candidate| candidate.suffix.size }
  return [word, nil] if rule.nil?

  remainder = word.delete_suffix(rule.suffix)
  return [word, nil] unless rule.condition.call(remainder)

  [remainder + rule.replacement, rule.suffix]
end

def tidy_step_1b(word)
  return "#{word}e" if word.end_with?('at', 'bl', 'iz')
  return word[0...-1] if ends_double?(word) && !'lsz'.include?(word[-1])
  return "#{word}e" if measure(word) == 1 && ends_cvc?(word)

  word
end

def apply_step(name, word)
  if name == '5b'
    return word[0...-1] if measure(word) > 1 && ends_double?(word) && word.end_with?('l')

    return word
  end
  result, suffix = apply_rules(word, RULE_TABLES[name])
  return tidy_step_1b(result) if name == '1b' && %w[ed ing].include?(suffix)

  result
end

def stemming_steps(word)
  changes = []
  if word.size > 2
    STEP_NAMES.each do |name|
      result = apply_step(name, word)
      changes << "#{name}:#{result}" if result != word
      word = result
    end
  end
  [word, changes]
end

STEMS = Hash.new { |stems, word| stems[word] = stemming_steps(word).first }

def porter_stem(word) = STEMS[word]

def yes_no(flag) = flag ? 'YES' : 'NO'

def word_argument(text)
  raise CommandError, "BAD WORD #{text}" unless WORD_PATTERN.match?(text)

  text.downcase
end

def number_argument(text, minimum, maximum)
  raise CommandError, "BAD NUMBER #{text}" unless NUMBER_PATTERN.match?(text)

  value = text.to_i
  raise CommandError, "BAD NUMBER #{text}" unless value.between?(minimum, maximum)

  value
end

def split_arguments(name, rest)
  case name
  when 'SEARCH' then [rest]
  when 'APPEND' then rest.split(/ /, 2)
  else rest.split(/ /, -1)
  end
end

def by_count(entry)
  stem, count = entry
  [-count, stem]
end

def document_count(occurrences) = occurrences.map { |document, _| document.number }.uniq.size

def closest_distance(positions, others, same_stem)
  if same_stem
    gaps = positions.each_cons(2).map { |earlier, later| later - earlier }
  else
    merged = (positions.map { |position| [position, 0] } + others.map { |other| [other, 1] }).sort
    gaps = merged.each_cons(2).filter_map do |earlier, later|
      later[0] - earlier[0] if earlier[1] != later[1]
    end
  end
  gaps.min
end

def classify(lexeme)
  return [lexeme, lexeme] if OPERATORS.include?(lexeme) || PARENTHESES.include?(lexeme)
  return ['term', lexeme.downcase] if WORD_PATTERN.match?(lexeme)
  return ['prefix', lexeme[0...-1].downcase] if PREFIX_TERM_PATTERN.match?(lexeme)

  raise CommandError, "BAD TERM #{lexeme}"
end

Token = Data.define(:text, :line, :position, :start) do
  def form = text.downcase

  def finish = start + text.size
end

class Document
  attr_reader :number, :lines, :tokens

  def initialize(number)
    @number = number
    @lines = []
    @tokens = []
  end

  def add_line(text)
    @lines << text
    added = []
    text.scan(/[A-Za-z]+/) do |word|
      position = @tokens.size + added.size + 1
      added << Token.new(word, @lines.size, position, Regexp.last_match.begin(0))
    end
    @tokens.concat(added)
    added
  end

  def line_tokens(line_number) = @tokens.select { |token| token.line == line_number }

  def reference(token) = "#{@number}:#{token.line}:#{token.position}"
end

class QueryParser
  def initialize(items, stem_sets)
    @items = items
    @position = 0
    @stem_sets = stem_sets
  end

  def parse
    result = expression
    raise CommandError, 'SYNTAX' if @position < @items.size

    result
  end

  private

  def peek = @items[@position]&.first

  def take
    raise CommandError, 'SYNTAX' if @position >= @items.size

    item = @items[@position]
    @position += 1
    item
  end

  def expression
    canonical, documents = conjunction
    while peek == 'OR'
      @position += 1
      right, right_documents = conjunction
      canonical = "(#{canonical} OR #{right})"
      documents |= right_documents
    end
    [canonical, documents]
  end

  def conjunction
    canonical, documents = negation
    while CONJUNCTION_CONTINUATIONS.include?(peek)
      @position += 1 if peek == 'AND'
      right, right_documents = negation
      canonical = "(#{canonical} AND #{right})"
      documents &= right_documents
    end
    [canonical, documents]
  end

  def negation
    return element unless peek == 'NOT'

    @position += 1
    canonical, documents = negation
    ["(NOT #{canonical})", @stem_sets.keys.to_set - documents]
  end

  def element
    kind, spelling = take
    case kind
    when '('
      result = expression
      raise CommandError, 'SYNTAX' unless take.first == ')'

      result
    when 'term'
      stem = porter_stem(spelling)
      [stem, @stem_sets.filter_map { |number, stems| number if stems.include?(stem) }.to_set]
    when 'prefix'
      documents = @stem_sets.filter_map do |number, stems|
        number if stems.any? { |stem| stem.start_with?(spelling) }
      end
      ["#{spelling}*", documents.to_set]
    else
      raise CommandError, 'SYNTAX'
    end
  end
end

class SearchEngine
  HANDLERS = {
    'STEM' => [1, 10, :stem_words],
    'STEPS' => [1, 1, :show_steps],
    'MEASURE' => [1, 1, :show_measure],
    'INDEX' => [0, 1, :show_index],
    'SEARCH' => [1, 1, :search],
    'PHRASE' => [2, 10, :phrase],
    'NEAR' => [3, 3, :near],
    'TOP' => [1, 2, :top],
    'KWIC' => [1, 1, :kwic],
    'TF' => [2, 2, :term_frequency],
    'DF' => [1, 1, :document_frequency],
    'VARIANTS' => [1, 1, :variants],
    'SIMILAR' => [2, 2, :similar],
    'RANK' => [2, 11, :rank],
    'INFO' => [1, 1, :info],
    'LINE' => [2, 2, :show_line],
    'STATS' => [0, 0, :stats],
    'STOP' => [1, 1, :stop],
    'UNSTOP' => [1, 1, :unstop],
    'APPEND' => [2, 2, :append],
    'DELETE' => [1, 1, :delete],
  }.freeze

  attr_reader :output

  def initialize(stopwords)
    @stopwords = stopwords
    @documents = {}
    @output = []
  end

  def add_document(number)
    @documents[number] = Document.new(number)
  end

  def execute(line)
    name, separator, rest = line.partition(' ')
    raise CommandError, "UNKNOWN COMMAND #{name}" unless HANDLERS.key?(name)

    minimum, maximum, handler = HANDLERS[name]
    arguments = separator.empty? ? [] : split_arguments(name, rest)
    raise CommandError, "BAD ARGUMENTS #{name}" unless arguments.size.between?(minimum, maximum)

    send(handler, arguments)
  rescue CommandError => e
    emit('ERROR', e.message)
  end

  private

  def emit(*parts)
    @output << parts.join(' ')
  end

  def ordered_documents = @documents.values.sort_by(&:number)

  def indexed?(token) = !@stopwords.include?(token.form)

  def indexed_tokens(document) = document.tokens.select { |token| indexed?(token) }

  def term_frequencies(document)
    indexed_tokens(document).map { |token| porter_stem(token.form) }.tally
  end

  def stem_set(document) = term_frequencies(document).keys.to_set

  def total_frequencies
    totals = Hash.new(0)
    @documents.each_value do |document|
      term_frequencies(document).each { |stem, count| totals[stem] += count }
    end
    totals
  end

  def occurrence_map
    occurrences = {}
    ordered_documents.each do |document|
      indexed_tokens(document).each do |token|
        (occurrences[porter_stem(token.form)] ||= []) << [document, token]
      end
    end
    occurrences
  end

  def stem_positions(document, stem)
    indexed_tokens(document).select { |token| porter_stem(token.form) == stem }.map(&:position)
  end

  def form_count(form)
    @documents.values.sum { |document| document.tokens.count { |token| token.form == form } }
  end

  def token_matches?(token, target)
    target == '?' || (indexed?(token) && porter_stem(token.form) == target)
  end

  def describe_token(token)
    indexed?(token) ? "#{token.form}/#{porter_stem(token.form)}" : "#{token.form}/-"
  end

  def term_argument(text)
    word = word_argument(text)
    raise CommandError, "STOPWORD #{word}" if @stopwords.include?(word)

    porter_stem(word)
  end

  def document_argument(text)
    number = number_argument(text, 1, MAX_DOCUMENT_NUMBER)
    @documents.fetch(number) { raise CommandError, "NO DOC #{number}" }
  end

  def stem_words(arguments)
    words = arguments.map { |argument| word_argument(argument) }
    emit('STEM', *words.map { |word| "#{word}:#{porter_stem(word)}" })
  end

  def show_steps(arguments)
    word = word_argument(arguments[0])
    _, changes = stemming_steps(word)
    if changes.empty?
      emit('STEPS', word, 'NONE')
    else
      emit('STEPS', word, *changes)
    end
  end

  def show_measure(arguments)
    word = word_argument(arguments[0])
    emit(
      'MEASURE', word, letter_pattern(word), "m=#{measure(word)}",
      "vowel=#{yes_no(vowel?(word))}", "double=#{yes_no(ends_double?(word))}",
      "cvc=#{yes_no(ends_cvc?(word))}"
    )
  end

  def show_index(arguments)
    prefix = arguments.empty? ? '' : word_argument(arguments[0])
    occurrences = occurrence_map
    stems = occurrences.keys.select { |stem| stem.start_with?(prefix) }.sort
    emit('INDEX', "stems=#{stems.size}")
    stems.each do |stem|
      found = occurrences[stem]
      references = found.map { |document, token| document.reference(token) }
      emit(stem, "df=#{document_count(found)}", *references)
    end
  end

  def search(arguments)
    items = arguments[0].scan(LEXEME_PATTERN).map { |lexeme| classify(lexeme) }
    stem_sets = @documents.transform_values { |document| stem_set(document) }
    canonical, matches = QueryParser.new(items, stem_sets).parse
    items.each do |kind, spelling|
      raise CommandError, "STOPWORD #{spelling}" if kind == 'term' && @stopwords.include?(spelling)
    end
    emit('SEARCH', canonical, "count=#{matches.size}", *matches.sort)
  end

  def phrase(arguments)
    words = arguments.map { |argument| word_argument(argument) }
    raise CommandError, 'STOPWORDS ONLY' if words.all? { |word| @stopwords.include?(word) }

    targets = words.map { |word| @stopwords.include?(word) ? '?' : porter_stem(word) }
    matches = []
    ordered_documents.each do |document|
      tokens = document.tokens
      (0..tokens.size - targets.size).each do |start|
        window = tokens[start, targets.size]
        next unless window.zip(targets).all? { |token, target| token_matches?(token, target) }

        matches << document.reference(tokens[start])
      end
    end
    phrase_text = targets.join(' ')
    emit("PHRASE \"#{phrase_text}\"", "matches=#{matches.size}", *matches)
  end

  def near(arguments)
    first = term_argument(arguments[0])
    second = term_argument(arguments[1])
    limit = number_argument(arguments[2], 1, MAX_COUNT)
    found = ordered_documents.filter_map do |document|
      distance = closest_distance(
        stem_positions(document, first), stem_positions(document, second), first == second
      )
      "#{document.number}:#{distance}" if distance && distance <= limit
    end
    emit('NEAR', first, second, limit, "count=#{found.size}", *found)
  end

  def top(arguments)
    limit = number_argument(arguments[0], 1, MAX_COUNT)
    if arguments.size == 2
      document = document_argument(arguments[1])
      counts = term_frequencies(document)
      header = "TOP #{limit} doc=#{document.number}"
    else
      counts = total_frequencies
      header = "TOP #{limit}"
    end
    ranked = counts.sort_by { |entry| by_count(entry) }.first(limit)
    emit(header, *ranked.map { |stem, count| "#{stem}:#{count}" })
  end

  def kwic(arguments)
    stem = term_argument(arguments[0])
    found = occurrence_map.fetch(stem, [])
    emit('KWIC', stem, "count=#{found.size}")
    found.each do |document, token|
      text = document.lines[token.line - 1]
      before = text[[0, token.start - KWIC_WIDTH].max...token.start].rjust(KWIC_WIDTH)
      after = text[token.finish, KWIC_WIDTH].ljust(KWIC_WIDTH)
      emit("|#{before}[#{token.text}]#{after}|", document.reference(token))
    end
  end

  def term_frequency(arguments)
    document = document_argument(arguments[0])
    stem = term_argument(arguments[1])
    emit('TF', document.number, stem, term_frequencies(document).fetch(stem, 0))
  end

  def document_frequency(arguments)
    stem = term_argument(arguments[0])
    emit('DF', stem, document_count(occurrence_map.fetch(stem, [])))
  end

  def variants(arguments)
    stem = term_argument(arguments[0])
    forms = occurrence_map.fetch(stem, []).map { |_, token| token.form }.tally
    shown = forms.sort.map { |form, count| "#{form}:#{count}" }
    emit('VARIANTS', stem, "count=#{forms.size}", *shown)
  end

  def similar(arguments)
    document = document_argument(arguments[0])
    limit = number_argument(arguments[1], 1, MAX_COUNT)
    stems = stem_set(document)
    scores = @documents.values.reject { |other| other.equal?(document) }.map do |other|
      other_stems = stem_set(other)
      union = (stems | other_stems).size
      score = union.zero? ? Rational(0) : Rational((stems & other_stems).size, union)
      [score, other.number]
    end
    scores.sort_by! { |score, number| [-score, number] }
    shown = scores.first(limit).map do |score, number|
      "#{number}:#{score.numerator}/#{score.denominator}"
    end
    emit('SIMILAR', document.number, *shown)
  end

  def rank(arguments)
    limit = number_argument(arguments[0], 1, MAX_COUNT)
    query = arguments[1..].map { |argument| term_argument(argument) }.to_set
    ranked = @documents.values.filter_map do |document|
      counts = term_frequencies(document)
      matched = query.count { |stem| counts.fetch(stem, 0).positive? }
      total = query.sum { |stem| counts.fetch(stem, 0) }
      [matched, total, document.number] if matched.positive?
    end
    ranked.sort_by! { |matched, total, number| [-matched, -total, number] }
    shown = ranked.first(limit).map { |matched, total, number| "#{number}:#{matched}:#{total}" }
    emit("RANK count=#{ranked.size}", *shown)
  end

  def info(arguments)
    document = document_argument(arguments[0])
    counts = term_frequencies(document)
    top = counts.empty? ? '-' : counts.min_by { |entry| by_count(entry) }.join(':')
    emit(
      'INFO', document.number, "lines=#{document.lines.size}",
      "tokens=#{document.tokens.size}", "indexed=#{counts.values.sum}",
      "stems=#{counts.size}", "top=#{top}"
    )
  end

  def show_line(arguments)
    document = document_argument(arguments[0])
    line_number = number_argument(arguments[1], 1, MAX_LINE_NUMBER)
    if line_number > document.lines.size
      raise CommandError, "NO LINE #{document.number}:#{line_number}"
    end

    tokens = document.line_tokens(line_number)
    emit(
      "LINE #{document.number}:#{line_number}", "tokens=#{tokens.size}",
      *tokens.map { |token| describe_token(token) }
    )
  end

  def stats(_arguments)
    documents = @documents.values
    emit(
      'STATS', "docs=#{documents.size}",
      "lines=#{documents.sum { |document| document.lines.size }}",
      "tokens=#{documents.sum { |document| document.tokens.size }}",
      "indexed=#{documents.sum { |document| indexed_tokens(document).size }}",
      "stems=#{total_frequencies.size}", "stopwords=#{@stopwords.size}"
    )
  end

  def stop(arguments)
    word = word_argument(arguments[0])
    raise CommandError, "ALREADY STOPWORD #{word}" if @stopwords.include?(word)

    @stopwords.add(word)
    emit('STOP', word, "unindexed=#{form_count(word)}")
  end

  def unstop(arguments)
    word = word_argument(arguments[0])
    raise CommandError, "NOT STOPWORD #{word}" unless @stopwords.include?(word)

    @stopwords.delete(word)
    emit('UNSTOP', word, "indexed=#{form_count(word)}")
  end

  def append(arguments)
    number = number_argument(arguments[0], 1, MAX_DOCUMENT_NUMBER)
    created = !@documents.key?(number)
    document = created ? add_document(number) : @documents[number]
    tokens = document.add_line(arguments[1])
    indexed = tokens.count { |token| indexed?(token) }
    emit(
      'APPEND', number, "line=#{document.lines.size}", "tokens=#{tokens.size}",
      "indexed=#{indexed}", "new=#{yes_no(created)}"
    )
  end

  def delete(arguments)
    document = document_argument(arguments[0])
    @documents.delete(document.number)
    emit(
      'DELETE', document.number, "lines=#{document.lines.size}", "tokens=#{document.tokens.size}"
    )
  end
end

def main
  lines = $stdin.read.lines(chomp: true)
  engine = SearchEngine.new(lines[0].split[1..].to_set)
  index = 1
  while lines[index].start_with?('DOC ')
    document = engine.add_document(lines[index][4..].to_i)
    index += 1
    until lines[index] == 'ENDDOC'
      document.add_line(lines[index])
      index += 1
    end
    index += 1
  end
  lines[index..].each do |line|
    break if line == 'END'

    engine.execute(line)
  end
  $stdout.write(engine.output.join("\n"), "\n")
end

main
