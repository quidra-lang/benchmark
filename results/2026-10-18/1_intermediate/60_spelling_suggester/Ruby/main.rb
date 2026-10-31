require "set"

ADJACENT_KEYS = {
  "a" => "qswz", "b" => "ghnv", "c" => "dfvx", "d" => "cefrsx", "e" => "drsw",
  "f" => "cdgrtv", "g" => "bfhtvy", "h" => "bgjnuy", "i" => "jkou", "j" => "hikmnu",
  "k" => "ijlmo", "l" => "kop", "m" => "jkn", "n" => "bhjm", "o" => "iklp",
  "p" => "lo", "q" => "aw", "r" => "deft", "s" => "adewxz", "t" => "fgry",
  "u" => "hijy", "v" => "bcfg", "w" => "aeqs", "x" => "cdsz", "y" => "ghtu",
  "z" => "asx"
}.freeze
SOUNDEX_DIGITS = {}
{
  "bfpv" => "1", "cgjkqsxz" => "2", "dt" => "3",
  "l" => "4", "mn" => "5", "r" => "6", "aeiouy" => "0"
}.each { |letters, digit| letters.each_char { |letter| SOUNDEX_DIGITS[letter] = digit } }
TEXT_COMMANDS = %w[CHECK CORRECT FIX PROFILE LEARN].freeze
ARITIES = {
  "SUGGEST" => 1, "DIST" => 2, "SOUNDEX" => 1, "SOUNDS" => 1, "SPLIT" => 1,
  "PREFIX" => 2, "COMPLETE" => 2, "LIST" => 2, "WORD" => 1, "ADD" => 2,
  "REMOVE" => 1, "IGNORE" => 1, "UNIGNORE" => 1, "RULE" => 2, "UNRULE" => 1,
  "RULES" => 0, "KEYBOARD" => 1, "SET" => 2, "UNDO" => 0, "REPORT" => 0,
  "HISTORY" => 0, "STATS" => 0
}.freeze
COUNTERS = %w[checked unknown case capital repeats corrected].freeze
FINDINGS = %w[unknown case capital repeats].freeze

class CommandError < StandardError; end

def word_argument(text)
  raise CommandError, "BAD WORD #{text}" unless /\A[A-Za-z]{1,30}\z/.match?(text)
  text.downcase
end

def number_argument(text, minimum, maximum)
  raise CommandError, "BAD NUMBER #{text}" unless /\A[0-9]{1,7}\z/.match?(text)
  value = text.to_i
  raise CommandError, "BAD NUMBER #{text}" unless value.between?(minimum, maximum)
  value
end

def decimal_text(numerator, denominator, digits)
  scale = 10**digits
  rounded = (2 * numerator * scale + denominator) / (2 * denominator)
  "#{rounded / scale}.#{(rounded % scale).to_s.rjust(digits, "0")}"
end

def apply_case(token, word)
  return word.upcase if token.length >= 2 && token == token.upcase
  return word[0].upcase + word[1..] if /\A[A-Z]/.match?(token)
  word
end

Token = Struct.new(
  :number, :text, :word, :start, :finish, :gap,
  :sentence_start, :repeat, :mixed_case, keyword_init: true
)

def tokens(text)
  result = []
  previous = nil
  previous_end = 0
  text.to_enum(:scan, /[A-Za-z]+/).each do
    match = Regexp.last_match
    spelling = match[0]
    gap = text[previous_end...match.begin(0)]
    word = spelling.downcase
    token = Token.new(
      number: result.length + 1, text: spelling, word: word,
      start: match.begin(0), finish: match.end(0), gap: gap,
      sentence_start: previous.nil? || /[.!?]/.match?(gap),
      repeat: !previous.nil? && previous.word == word && /\A *\z/.match?(gap),
      mixed_case: /[A-Z]/.match?(spelling[1..]) && spelling != spelling.upcase
    )
    result << token
    previous = token
    previous_end = token.finish
  end
  result
end

def gap_cost(keyboard)
  keyboard ? 2 : 1
end

def substitution_cost(first, second, keyboard)
  return 0 if first == second
  return 1 unless keyboard
  ADJACENT_KEYS[first].include?(second) ? 1 : 2
end

def swapped?(first, second, i, j)
  i >= 2 && j >= 2 && first[i - 1] == second[j - 2] && first[i - 2] == second[j - 1]
end

def distance_table(first, second, keyboard)
  gap = gap_cost(keyboard)
  rows, columns = first.length, second.length
  table = Array.new(rows + 1) { Array.new(columns + 1, 0) }
  (0..rows).each { |i| table[i][0] = i * gap }
  (0..columns).each { |j| table[0][j] = j * gap }
  (1..rows).each do |i|
    (1..columns).each do |j|
      table[i][j] = [
        table[i - 1][j] + gap,
        table[i][j - 1] + gap,
        table[i - 1][j - 1] + substitution_cost(first[i - 1], second[j - 1], keyboard)
      ].min
      if swapped?(first, second, i, j)
        table[i][j] = [table[i][j], table[i - 2][j - 2] + 1].min
      end
    end
  end
  table
end

def edit_distance(first, second, keyboard)
  distance_table(first, second, keyboard)[first.length][second.length]
end

def prefix_distance(first, second, keyboard)
  distance_table(first, second, keyboard).last.min
end

def edit_operations(first, second, keyboard)
  table = distance_table(first, second, keyboard)
  gap = gap_cost(keyboard)
  operations = []
  i, j = first.length, second.length
  while i.positive? || j.positive?
    if i >= 1 && j >= 1 &&
       table[i][j] == table[i - 1][j - 1] + substitution_cost(first[i - 1], second[j - 1], keyboard)
      operations << "sub:#{first[i - 1]}>#{second[j - 1]}" if first[i - 1] != second[j - 1]
      i -= 1
      j -= 1
    elsif swapped?(first, second, i, j) && table[i][j] == table[i - 2][j - 2] + 1
      operations << "swap:#{first[i - 2, 2]}"
      i -= 2
      j -= 2
    elsif i >= 1 && table[i][j] == table[i - 1][j] + gap
      operations << "del:#{first[i - 1]}"
      i -= 1
    else
      operations << "ins:#{second[j - 1]}"
      j -= 1
    end
  end
  [table[first.length][second.length], operations.reverse]
end

def soundex(word)
  code = word[0].upcase
  previous = "hw".include?(word[0]) ? "0" : SOUNDEX_DIGITS[word[0]]
  word[1..].each_char do |letter|
    next if "hw".include?(letter)
    digit = SOUNDEX_DIGITS[letter]
    code += digit if digit != "0" && digit != previous
    previous = digit
  end
  (code + "000")[0, 4]
end

def segment(word, dictionary)
  n = word.length
  ways = Array.new(n + 1, 0)
  best = Array.new(n + 1)
  ways[n] = 1
  best[n] = []
  (n - 1).downto(0) do |start|
    (start + 1..n).each do |finish|
      piece = word[start...finish]
      next unless dictionary.key?(piece) && ways[finish].positive?
      ways[start] += ways[finish]
      candidate = [piece] + best[finish]
      current = best[start]
      if current.nil? || ([candidate.length, candidate] <=> [current.length, current]).negative?
        best[start] = candidate
      end
    end
  end
  [ways[0], best[0]]
end

class SpellChecker
  attr_reader :output

  def initialize(dictionary)
    @dictionary = dictionary
    @ignored = Set.new
    @rules = {}
    @keyboard = false
    @base_limit = 2
    @suggestion_count = 5
    @undo_history = []
    @unknown_log = Hash.new(0)
    @correction_log = Hash.new(0)
    @counters = COUNTERS.to_h { |name| [name, 0] }
    @output = []
  end

  def emit(*parts)
    @output << parts.join(" ")
  end

  def limit
    @keyboard ? 2 * @base_limit : @base_limit
  end

  def known?(word)
    @dictionary.key?(word) || @ignored.include?(word)
  end

  def frequency_order
    @dictionary.sort_by { |word, frequency| [-frequency, word] }.map(&:first)
  end

  def require_entry(word)
    raise CommandError, "NOT FOUND #{word}" unless @dictionary.key?(word)
    @dictionary[word]
  end

  def candidates(word)
    gap = gap_cost(@keyboard)
    found = []
    @dictionary.each do |other, frequency|
      next if other == word || (other.length - word.length).abs * gap > limit
      distance = edit_distance(word, other, @keyboard)
      found << [distance, -frequency, other] if distance <= limit
    end
    found.sort.map { |distance, _, other| [other, distance] }
  end

  def correction(word)
    return nil if known?(word)
    return @rules[word] if @rules.key?(word)
    candidates(word).first&.first
  end

  def save_undo(name)
    @undo_history << [name, @dictionary.dup, @ignored.dup, @rules.dup]
  end

  def log_correction(original, replacement)
    @correction_log[[original, replacement]] += 1
    @counters["corrected"] += 1
  end

  def unknown_finding(token)
    prefix = "UNKNOWN #{token.number} #{token.text}"
    return "#{prefix} RULE #{@rules[token.word]}" if @rules.key?(token.word)
    found = candidates(token.word)
    return "#{prefix} NONE" if found.empty?
    "#{prefix} SUGGEST #{found.first(@suggestion_count).map(&:first).join(' ')}"
  end

  def check_text(text)
    list = tokens(text)
    findings = []
    counts = FINDINGS.to_h { |kind| [kind, 0] }
    list.each do |token|
      unless known?(token.word)
        findings << unknown_finding(token)
        counts["unknown"] += 1
        @unknown_log[token.word] += 1
      end
      if token.mixed_case
        findings << "CASE #{token.number} #{token.text}"
        counts["case"] += 1
      end
      if token.sentence_start && /\A[a-z]/.match?(token.text)
        findings << "CAPITAL #{token.number} #{token.text}"
        counts["capital"] += 1
      end
      if token.repeat
        findings << "REPEAT #{token.number} #{token.text}"
        counts["repeats"] += 1
      end
    end
    @counters["checked"] += list.length
    FINDINGS.each { |kind| @counters[kind] += counts[kind] }
    emit("CHECK", "words=#{list.length}", *FINDINGS.map { |kind| "#{kind}=#{counts[kind]}" })
    findings.each { |line| emit(line) }
  end

  def correct_text(text)
    pieces = []
    position = 0
    changed = 0
    tokens(text).each do |token|
      replacement = correction(token.word)
      if replacement.nil?
        pieces << token.gap + token.text
      else
        pieces << token.gap + apply_case(token.text, replacement)
        log_correction(token.word, replacement)
        changed += 1
      end
      position = token.finish
    end
    pieces << text[position..]
    emit("CORRECT", "changed=#{changed}:", pieces.join)
  end

  def fix_text(text)
    pieces = []
    position = 0
    removed = 0
    replaced = 0
    recased = 0
    tokens(text).each do |token|
      position = token.finish
      if token.repeat
        removed += 1
        next
      end
      replacement = correction(token.word)
      target = replacement.nil? ? token.word : replacement
      result = apply_case(token.text, target)
      result = result[0].upcase + result[1..] if token.sentence_start && /\A[a-z]/.match?(result)
      if replacement
        log_correction(token.word, replacement)
        replaced += 1
      elsif result != token.text
        recased += 1
      end
      pieces << token.gap + result
    end
    pieces << text[position..]
    emit("FIX", "removed=#{removed}", "replaced=#{replaced}", "recased=#{recased}:", pieces.join)
  end

  def profile_text(text)
    list = tokens(text)
    distinct = list.map(&:word).uniq.length
    unknown = list.count { |token| !known?(token.word) }
    sentences = list.count(&:sentence_start)
    if list.empty?
      rate, avglen, longest = "0.0", "0.00", "-"
    else
      rate = decimal_text(100 * unknown, list.length, 1)
      avglen = decimal_text(list.sum { |token| token.text.length }, list.length, 2)
      longest = list.max_by { |token| token.text.length }.word
    end
    emit("PROFILE", "words=#{list.length}", "distinct=#{distinct}",
         "unknown=#{unknown}", "rate=#{rate}", "avglen=#{avglen}",
         "longest=#{longest}", "sentences=#{sentences}")
  end

  def learn_text(text)
    save_undo("LEARN")
    updated = added = skipped = 0
    tokens(text).each do |token|
      if token.word.length > 30
        skipped += 1
      elsif @dictionary.key?(token.word)
        @dictionary[token.word] += 1
        updated += 1
      else
        @dictionary[token.word] = 1
        @ignored.delete(token.word)
        added += 1
      end
    end
    emit("LEARN", "updated=#{updated}", "added=#{added}", "skipped=#{skipped}")
  end

  def suggest(arguments)
    word = word_argument(arguments[0])
    if known?(word)
      emit("SUGGEST", word, "KNOWN")
    elsif @rules.key?(word)
      emit("SUGGEST", word, "RULE", @rules[word])
    else
      found = candidates(word)
      emit("SUGGEST", word, "found=#{found.length}",
           *found.first(@suggestion_count).map { |other, distance| "#{other}:#{distance}" })
    end
  end

  def dist(arguments)
    first = word_argument(arguments[0])
    second = word_argument(arguments[1])
    distance, operations = edit_operations(first, second, @keyboard)
    emit("DIST", first, second, distance, *operations)
  end

  def soundex_code(arguments)
    word = word_argument(arguments[0])
    emit("SOUNDEX", word, soundex(word))
  end

  def sounds(arguments)
    word = word_argument(arguments[0])
    code = soundex(word)
    found = frequency_order.select { |other| other != word && soundex(other) == code }
    emit("SOUNDS", word, code, "count=#{found.length}", *found.first(10))
  end

  def split_word(arguments)
    word = word_argument(arguments[0])
    ways, best = segment(word, @dictionary)
    emit("SPLIT", word, "ways=#{ways}", "->", *(ways.zero? ? ["NONE"] : best))
  end

  def prefix(arguments)
    word = word_argument(arguments[0])
    count = number_argument(arguments[1], 1, 20)
    found = frequency_order.select { |other| other.start_with?(word) }
    emit("PREFIX", word, "count=#{found.length}",
         *found.first(count).map { |other| "#{other}:#{@dictionary[other]}" })
  end

  def complete(arguments)
    word = word_argument(arguments[0])
    count = number_argument(arguments[1], 1, 20)
    threshold = limit / 2
    found = []
    @dictionary.each do |other, frequency|
      distance = prefix_distance(word, other, @keyboard)
      found << [distance, -frequency, other] if distance <= threshold
    end
    found.sort!
    emit("COMPLETE", word, "count=#{found.length}",
         *found.first(count).map { |distance, _, other| "#{other}:#{distance}" })
  end

  def list_words(arguments)
    word = word_argument(arguments[0])
    count = number_argument(arguments[1], 1, 20)
    found = @dictionary.keys.select { |other| other >= word }.sort
    emit("LIST", word, "count=#{found.length}",
         *found.first(count).map { |other| "#{other}:#{@dictionary[other]}" })
  end

  def word_info(arguments)
    word = word_argument(arguments[0])
    frequency = require_entry(word)
    rank = frequency_order.index(word) + 1
    emit("WORD", word, "freq=#{frequency}", "rank=#{rank}",
         "soundex=#{soundex(word)}", "neighbors=#{candidates(word).length}")
  end

  def add(arguments)
    word = word_argument(arguments[0])
    frequency = number_argument(arguments[1], 1, 1_000_000)
    raise CommandError, "DUPLICATE #{word}" if @dictionary.key?(word)
    save_undo("ADD")
    @dictionary[word] = frequency
    @ignored.delete(word)
    emit("ADD", word, frequency)
  end

  def remove(arguments)
    word = word_argument(arguments[0])
    frequency = require_entry(word)
    save_undo("REMOVE")
    @dictionary.delete(word)
    emit("REMOVE", word, frequency)
  end

  def ignore(arguments)
    word = word_argument(arguments[0])
    raise CommandError, "IN DICTIONARY #{word}" if @dictionary.key?(word)
    raise CommandError, "ALREADY IGNORED #{word}" if @ignored.include?(word)
    save_undo("IGNORE")
    @ignored.add(word)
    emit("IGNORE", word)
  end

  def unignore(arguments)
    word = word_argument(arguments[0])
    raise CommandError, "NOT IGNORED #{word}" unless @ignored.include?(word)
    save_undo("UNIGNORE")
    @ignored.delete(word)
    emit("UNIGNORE", word)
  end

  def rule(arguments)
    source = word_argument(arguments[0])
    target = word_argument(arguments[1])
    raise CommandError, "IN DICTIONARY #{source}" if @dictionary.key?(source)
    raise CommandError, "NOT FOUND #{target}" unless @dictionary.key?(target)
    save_undo("RULE")
    previous = @rules[source]
    @rules[source] = target
    if previous.nil?
      emit("RULE", source, target)
    else
      emit("RULE", source, target, "REPLACED", previous)
    end
  end

  def unrule(arguments)
    word = word_argument(arguments[0])
    raise CommandError, "NO RULE #{word}" unless @rules.key?(word)
    save_undo("UNRULE")
    target = @rules.delete(word)
    emit("UNRULE", word, target)
  end

  def show_rules
    rows = @rules.sort_by(&:first)
    emit("RULES", "count=#{rows.length}", *rows.map { |source, target| "#{source}>#{target}" })
  end

  def keyboard_mode(arguments)
    mode = arguments[0]
    raise CommandError, "BAD MODE #{mode}" unless %w[ON OFF].include?(mode)
    @keyboard = mode == "ON"
    emit("KEYBOARD", mode)
  end

  def set_option(arguments)
    option = arguments[0]
    maximum = { "LIMIT" => 3, "SUGGESTIONS" => 10 }[option]
    raise CommandError, "BAD OPTION #{option}" if maximum.nil?
    value = number_argument(arguments[1], 1, maximum)
    if option == "LIMIT"
      @base_limit = value
    else
      @suggestion_count = value
    end
    emit("SET", option, value)
  end

  def undo
    raise CommandError, "NOTHING TO UNDO" if @undo_history.empty?
    name, @dictionary, @ignored, @rules = @undo_history.pop
    emit("UNDO", name)
  end

  def report
    rows = @unknown_log.sort_by { |word, count| [-count, word] }
    emit("REPORT", "distinct=#{rows.length}",
         *rows.first(10).map { |word, count| "#{word}:#{count}" })
  end

  def history
    rows = @correction_log.sort_by { |pair, count| [-count, pair[0], pair[1]] }
    emit("HISTORY", "distinct=#{rows.length}",
         *rows.first(10).map { |pair, count| "#{pair[0]}>#{pair[1]}:#{count}" })
  end

  def stats
    top = frequency_order.first
    emit("STATS", "words=#{@dictionary.length}",
         "total=#{@dictionary.values.sum}",
         "avglen=#{decimal_text(@dictionary.keys.sum(&:length), @dictionary.length, 2)}",
         "top=#{top}:#{@dictionary[top]}", "ignored=#{@ignored.length}",
         "rules=#{@rules.length}", "keyboard=#{@keyboard ? 'ON' : 'OFF'}",
         "limit=#{limit}", "suggestions=#{@suggestion_count}", "undo=#{@undo_history.length}")
    emit("SESSION", *COUNTERS.map { |kind| "#{kind}=#{@counters[kind]}" })
  end

  def execute(line)
    name, separator, rest = line.partition(" ")
    begin
      unless TEXT_COMMANDS.include?(name) || ARITIES.key?(name)
        raise CommandError, "UNKNOWN COMMAND #{name}"
      end
      if TEXT_COMMANDS.include?(name)
        raise CommandError, "BAD ARGUMENTS #{name}" if separator.empty?
        case name
        when "CHECK" then check_text(rest)
        when "CORRECT" then correct_text(rest)
        when "FIX" then fix_text(rest)
        when "PROFILE" then profile_text(rest)
        when "LEARN" then learn_text(rest)
        end
      else
        arguments = separator.empty? ? [] : rest.split(/ /, -1)
        raise CommandError, "BAD ARGUMENTS #{name}" unless arguments.length == ARITIES[name]
        case name
        when "SUGGEST" then suggest(arguments)
        when "DIST" then dist(arguments)
        when "SOUNDEX" then soundex_code(arguments)
        when "SOUNDS" then sounds(arguments)
        when "SPLIT" then split_word(arguments)
        when "PREFIX" then prefix(arguments)
        when "COMPLETE" then complete(arguments)
        when "LIST" then list_words(arguments)
        when "WORD" then word_info(arguments)
        when "ADD" then add(arguments)
        when "REMOVE" then remove(arguments)
        when "IGNORE" then ignore(arguments)
        when "UNIGNORE" then unignore(arguments)
        when "RULE" then rule(arguments)
        when "UNRULE" then unrule(arguments)
        when "RULES" then show_rules
        when "KEYBOARD" then keyboard_mode(arguments)
        when "SET" then set_option(arguments)
        when "UNDO" then undo
        when "REPORT" then report
        when "HISTORY" then history
        when "STATS" then stats
        end
      end
    rescue CommandError => error
      emit("ERROR", error.message)
    end
  end
end

dictionary = {}
word_count = Integer(STDIN.gets)
word_count.times do
  word, frequency = STDIN.gets.split
  dictionary[word] = frequency.to_i
end
checker = SpellChecker.new(dictionary)
command_count = Integer(STDIN.gets)
command_count.times { checker.execute(STDIN.gets.chomp) }
STDOUT.write(checker.output.join("\n") + "\n")
