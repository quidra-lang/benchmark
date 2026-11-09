class Invalid < StandardError
end

class Romaji
  SYSTEMS = %w[HEPBURN TRADITIONAL KUNREI NIHON WAPURO].freeze
  BASE_ROWS = %w[a ka sa ta na ha ma ya ra wa].freeze
  ROW_DATA = [
    ["a", %w[a i u e o]], ["ka", %w[ka ki ku ke ko]],
    ["sa", %w[sa si su se so]], ["ta", %w[ta ti tu te to]],
    ["na", %w[na ni nu ne no]], ["ha", %w[ha hi hu he ho]],
    ["ma", %w[ma mi mu me mo]], ["ya", %w[ya yu yo]],
    ["ra", %w[ra ri ru re ro]], ["wa", %w[wa wi we wo]],
    ["ga", %w[ga gi gu ge go]], ["za", %w[za zi zu ze zo]],
    ["da", %w[da di du de do]], ["ba", %w[ba bi bu be bo]],
    ["pa", %w[pa pi pu pe po]]
  ].freeze
  CONTRACTED_ROWS = %w[ka sa ta na ha ma ra ga za da ba pa].freeze
  HEPBURN = {
    "si" => "shi", "ti" => "chi", "tu" => "tsu", "hu" => "fu",
    "zi" => "ji", "di" => "ji", "du" => "zu", "wi" => "i",
    "we" => "e", "wo" => "o"
  }.freeze
  KUNREI = {
    "di" => "zi", "du" => "zu", "wi" => "i", "we" => "e",
    "wo" => "o", "dya" => "zya", "dyu" => "zyu", "dyo" => "zyo"
  }.freeze
  WAPURO = {
    "si" => "shi", "ti" => "chi", "tu" => "tsu", "hu" => "fu", "zi" => "ji"
  }.freeze
  ORDERS = {
    "GOJUON" => %w[a i u e o ka ki ku ke ko sa si su se so ta ti tu te to
                   na ni nu ne no ha hi hu he ho ma mi mu me mo ya yu yo
                   ra ri ru re ro wa wi we wo N],
    "IROHA" => %w[i ro ha ni ho he to ti ri nu ru wo wa ka yo ta re so tu ne
                  na ra mu u wi no o ku ya ma ke hu ko e te a sa ki yu me mi
                  si we hi mo se su N]
  }.freeze
  ARGUMENT_COUNTS = {
    "SET" => 2, "TABLE" => 2, "CONVERT" => 2, "NORMALIZE" => 0,
    "REVERSE" => 1, "VALID" => 1, "DETECT" => 0, "DIFF" => 2,
    "SAME" => 2, "MORAE" => 1, "SYLLABLES" => 1, "ROW" => 1,
    "STATS" => 1, "SORT" => 1, "INDEX" => 1, "FIND" => 2,
    "HAIKU" => 1, "KAIBUN" => 1, "SHIRITORI" => 1
  }.freeze
  CHOICES = {
    "LONG" => %w[KEEP DROP PASSPORT HYPHEN DOUBLE],
    "CASE" => %w[KEEP LOWER UPPER TITLE],
    "ORDER" => %w[GOJUON IROHA]
  }.freeze

  def initialize
    @table = []
    @info = {}
    ROW_DATA.each do |row, ids|
      ids.each do |id|
        item = { id: id, row: row, dan: id[-1], contracted: false }
        @table << item
        @info[id] = item
      end
    end
    CONTRACTED_ROWS.each do |row|
      %w[ya yu yo].each do |dan|
        id = row[0] + dan
        item = { id: id, row: row, dan: dan, contracted: true }
        @table << item
        @info[id] = item
      end
    end
    @lexicons = {}
    (SYSTEMS + ["NORMALIZE"]).each do |system|
      sources = system == "NORMALIZE" ? %w[HEPBURN KUNREI NIHON WAPURO] : [system]
      entries = {}
      @table.each do |item|
        sources.each do |source|
          text = spelling(source, item[:id])
          entries[text] = item[:id] unless entries.key?(text)
        end
      end
      @lexicons[system] = entries.to_a.sort_by { |text, _| -text.length }
    end
    @settings = { "LONG" => "KEEP", "CASE" => "KEEP", "ORDER" => "GOJUON" }
  end

  def fail_with(message)
    raise Invalid, message
  end

  def at(column, message)
    fail_with("col #{column}: #{message}")
  end

  def spelling(system, id)
    return KUNREI.fetch(id, id) if system == "KUNREI"
    return id if system == "NIHON"

    replacements = system == "WAPURO" ? WAPURO : HEPBURN
    return replacements[id] if replacements.key?(id)
    return "sh" + id[2..] if id.start_with?("sy")
    return "ch" + id[2..] if id.start_with?("ty")
    if id.start_with?("zy") || (system != "WAPURO" && id.start_with?("dy"))
      return "j" + id[2..]
    end
    id
  end

  def match_at(text, position, system)
    @lexicons[system].find { |spelling, _| text[position, spelling.length] == spelling }
  end

  def case_pattern(word)
    return "LOWER" unless word.match?(/[A-Z]/)
    return "TITLE" if word.match?(/\A[A-Z]/) && !word[1..].match?(/[A-Z]/)

    letters = word.delete("^A-Za-z")
    return "UPPER" if letters.length >= 2 && !letters.match?(/[a-z]/)

    nil
  end

  def scan_words(text)
    words = []
    position = 0
    while (match = /[A-Za-z'-]+/.match(text, position))
      original = match[0]
      words << {
        original: original, start: match.begin(0),
        pattern: case_pattern(original), morae: []
      }
      position = match.end(0)
    end
    words
  end

  def parse_word(word, system)
    text = word[:original].downcase
    result = []
    position = 0
    while position < text.length
      c = text[position]
      c2 = text[position + 1] || ""
      column = word[:start] + position + 1
      length = 1
      if c == "-"
        if result.empty? || !@info.key?(result[-1][:id])
          at(column, "misplaced long mark")
        end
        id = "-"
      elsif c == "'"
        at(column, "misplaced apostrophe")
      else
        match = match_at(text, position, system)
        if match
          id = match[1]
          length = match[0].length
        elsif %w[WAPURO NORMALIZE].include?(system) && text[position, 3] == "xtu"
          id = "Q"
          length = 3
        elsif c == "n"
          id = "N"
          if system == "NORMALIZE"
            third = text[position + 2] || ""
            if c2 == "'" || (c2 == "n" && !third.match?(/\A[aiueoy']\z/))
              length = 2
            end
          elsif (system == "WAPURO" && c2 == "n") || (system != "WAPURO" && c2 == "'")
            length = 2
          end
        elsif %w[TRADITIONAL NORMALIZE].include?(system) && c == "m" && c2.match?(/\A[bmp]\z/)
          id = "N"
        elsif c.match?(/\A[a-z]\z/) && !c.match?(/[aiueon]/) &&
              c2 == c && match_at(text, position + 1, system)
          id = "Q"
        elsif %w[HEPBURN TRADITIONAL NORMALIZE].include?(system) && c == "t" &&
              text[position + 1, 2] == "ch" && match_at(text, position + 1, system)
          id = "Q"
        else
          at(column, "unknown syllable")
        end
      end
      result << { id: id, column: column }
      position += length
    end
    result
  end

  def long_data(morae)
    pairs = {}
    elements = {}
    morae.each_with_index do |mora, i|
      elements[i] = morae[i - 1][:id][-1] if mora[:id] == "-"
    end
    i = 0
    while i + 1 < morae.length
      current = morae[i][:id]
      following = morae[i + 1][:id]
      vowel = current[-1]
      if @info.key?(current) && following.match?(/\A[aiueo]\z/) &&
         (vowel == following || (vowel == "o" && following == "u") ||
          (vowel == "e" && following == "i"))
        pairs[i + 1] = true
        if (vowel == "o" && %w[o u].include?(following)) || (vowel == "u" && following == "u")
          elements[i + 1] = vowel
        end
        i += 2
      else
        i += 1
      end
    end
    [pairs, elements]
  end

  def written_parts(morae, system, long_mode)
    _, elements = long_data(morae)
    morae.each_with_index.map do |mora, i|
      following = morae[i + 1]&.fetch(:id) || ""
      next_spelling = @info.key?(following) ? spelling(system, following) : ""
      first = next_spelling[0] || ""
      if elements.key?(i)
        vowel = elements[i]
        case long_mode
        when "KEEP"
          mora[:id] == "-" ? "-" : spelling(system, mora[:id])
        when "PASSPORT"
          vowel == "o" && !first.match?(/\A[aiueo]\z/) ? "h" : ""
        when "HYPHEN"
          "-"
        when "DOUBLE"
          vowel
        else
          ""
        end
      elsif @info.key?(mora[:id])
        spelling(system, mora[:id])
      elsif mora[:id] == "N"
        if system == "WAPURO"
          following == "N" || first.match?(/\A[aiueoyn]\z/) ? "nn" : "n"
        elsif system == "TRADITIONAL" && first.match?(/\A[bmp]\z/)
          "m"
        else
          first.match?(/\A[aiueoy]\z/) ? "n'" : "n"
        end
      elsif mora[:id] == "Q"
        if !first.empty? && !first.match?(/[aiueon]/)
          if %w[HEPBURN TRADITIONAL].include?(system) && next_spelling.start_with?("ch")
            "t"
          else
            first
          end
        elsif system == "WAPURO"
          "xtu"
        else
          at(mora[:column], "small tsu cannot be written")
        end
      end
    end
  end

  def write_word(word, system, canonical: false, morae: word[:morae])
    value = written_parts(morae, system, canonical ? "KEEP" : @settings["LONG"]).join
    pattern = canonical || @settings["CASE"] == "KEEP" ? word[:pattern] : @settings["CASE"]
    case pattern
    when "UPPER"
      value.upcase
    when "TITLE"
      value.capitalize
    else
      value
    end
  end

  def replace_words(text, words)
    iterator = words.each
    text.gsub(/[A-Za-z'-]+/) { yield(iterator.next) }
  end

  def devoice(id)
    id[0].tr("gzdbp", "ksthh") + id[1..]
  end

  def collation_elements(morae)
    result = []
    morae.each do |mora|
      id = mora[:id]
      next if id == "-"

      if id == "N" || id == "Q"
        result << { base: id == "N" ? "N" : "tu", voice: 0, size: id == "Q" ? 1 : 0 }
        next
      end
      item = @info[id]
      voice = if %w[ga za da ba].include?(item[:row])
                1
              elsif item[:row] == "pa"
                2
              else
                0
              end
      base = item[:contracted] ? devoice(item[:row][0] + "i") : devoice(id)
      result << { base: base, voice: voice, size: 0 }
      if item[:contracted]
        result << { base: item[:dan], voice: 0, size: 1 }
      end
    end
    result
  end

  def sorted_words(words)
    ranks = ORDERS[@settings["ORDER"]].each_with_index.to_h
    words.each_with_index.sort_by do |word, index|
      elements = collation_elements(word[:morae])
      [
        elements.map { |item| ranks[item[:base]] },
        elements.map { |item| item[:voice] },
        elements.map { |item| item[:size] },
        word[:morae].map { |mora| mora[:id] == "-" ? 1 : 0 },
        index
      ]
    end.map(&:first)
  end

  def parse_pattern(pattern, system)
    fail_with("invalid pattern") unless pattern.match?(/\A[a-z'?*-]+\z/)

    result = []
    begin
      pattern.split(/([?*])/, -1).each do |part|
        if part == "?" || part == "*"
          result << part
        elsif !part.empty?
          word = { original: part, start: 0, pattern: "LOWER", morae: [] }
          result.concat(parse_word(word, system).map { |mora| mora[:id] })
        end
      end
    rescue Invalid
      fail_with("invalid pattern")
    end
    result
  end

  def matches_pattern?(pattern, morae)
    previous = Array.new(morae.length + 1, false)
    previous[0] = true
    pattern.each do |token|
      current = Array.new(morae.length + 1, false)
      current[0] = previous[0] if token == "*"
      (1..morae.length).each do |j|
        current[j] = if token == "*"
                       previous[j] || current[j - 1]
                     else
                       previous[j - 1] && (token == "?" || token == morae[j - 1][:id])
                     end
      end
      previous = current
    end
    previous[morae.length]
  end

  def ids(morae)
    morae.map { |mora| mora[:id] }
  end

  def counted(items, total)
    "#{items.length} of #{total}" + (items.empty? ? "" : ": " + items.join(" "))
  end

  def command(line)
    name = line.split(" ", 2)[0]
    fail_with("unknown command #{name}") unless ARGUMENT_COUNTS.key?(name)

    count = ARGUMENT_COUNTS[name]
    args = []
    text = ""
    if name == "SET" || name == "TABLE"
      parts = line.split(" ")
      fail_with("missing argument") if parts.length < 3
      fail_with("too many arguments") if parts.length > 3
      args = parts[1..]
    else
      position = 0
      (0..count).each do |i|
        space = line.index(" ", position)
        fail_with("missing argument") unless space
        args << line[position...space] if i.positive?
        position = space + 1
      end
      text = line[position..]
    end
    system_count = if %w[NORMALIZE DETECT SET].include?(name)
                     0
                   elsif %w[CONVERT DIFF SAME].include?(name)
                     2
                   else
                     1
                   end
    args.first(system_count).each do |system|
      fail_with("unknown system #{system}") unless SYSTEMS.include?(system)
    end
    system = name == "NORMALIZE" ? "NORMALIZE" : args[0]
    if name == "SET"
      fail_with("unknown option #{args[0]}") unless CHOICES.key?(args[0])
      fail_with("unknown value #{args[1]}") unless CHOICES[args[0]].include?(args[1])
      @settings[args[0]] = args[1]
      return "#{args[0]}=#{args[1]}"
    end
    if name == "TABLE"
      fail_with("unknown row #{args[1]}") unless ROW_DATA.any? { |row, _| row == args[1] }
      return @table.select { |item| item[:row] == args[1] }
                   .map { |item| spelling(system, item[:id]) }.join(" ")
    end
    pattern = name == "FIND" ? parse_pattern(args[1], system) : []
    allow_slash = name == "HAIKU" || name == "SAME"
    text.each_char.with_index do |char, i|
      unless char.match?(/[A-Za-z0-9' .,! ?;:()"-]/) || (allow_slash && char == "/")
        at(i + 1, "invalid character")
      end
    end
    pieces = text.split("/", -1)
    if name == "SAME" && (pieces.length != 2 || pieces.any? { |piece| scan_words(piece).empty? })
      fail_with("expected two texts")
    end
    if name == "HAIKU" && (![3, 5].include?(pieces.length) || pieces.any? { |piece| scan_words(piece).empty? })
      fail_with("expected 3 or 5 lines")
    end
    words = scan_words(text)
    fail_with("no words") if words.empty?
    words.each do |word|
      at(word[:start] + 1, "mixed case") unless word[:pattern]
    end
    if name == "DETECT"
      return SYSTEMS.map do |source|
        verdict = "canonical"
        begin
          words.each { |word| word[:morae] = parse_word(word, source) }
          if words.any? { |word| word[:original] != write_word(word, source, canonical: true) }
            verdict = "readable"
          end
        rescue Invalid
          verdict = "error"
        end
        "#{source}=#{verdict}"
      end.join(" ")
    end
    slash = text.index("/")
    words.each do |word|
      source = name == "SAME" && word[:start] > slash ? args[1] : system
      word[:morae] = parse_word(word, source)
    end
    case name
    when "CONVERT", "NORMALIZE", "REVERSE"
      target = if name == "NORMALIZE"
                 "HEPBURN"
               elsif name == "CONVERT"
                 args[1]
               else
                 system
               end
      replace_words(text, words) do |word|
        morae = word[:morae]
        if name == "REVERSE"
          morae = morae.each_with_index.map do |mora, i|
            id = mora[:id] == "-" ? word[:morae][i - 1][:id][-1] : mora[:id]
            { id: id, column: mora[:column] }
          end.reverse
        end
        write_word(word, target, morae: morae)
      end
    when "VALID"
      words.each do |word|
        canonical = write_word(word, system, canonical: true)
        next if canonical == word[:original]

        i = 0
        while i < [canonical.length, word[:original].length].min && canonical[i] == word[:original][i]
          i += 1
        end
        return "INVALID col #{word[:start] + i + 1}: expected #{canonical}"
      end
      "VALID"
    when "DIFF"
      differences = []
      words.each do |word|
        a = write_word(word, system)
        b = write_word(word, args[1])
        differences << "#{a}>#{b}" if a != b
      end
      counted(differences, words.length)
    when "SAME"
      left, right = words.partition { |word| word[:start] < slash }
      [left.length, right.length].min.times do |i|
        loose = [left[i], right[i]].map do |word|
          _, long_elements = long_data(word[:morae])
          kept = word[:morae].each_with_index.filter_map do |mora, index|
            mora unless long_elements.key?(index)
          end
          ids(kept)
        end
        return "DIFFERENT at word #{i + 1}" if loose[0] != loose[1]
      end
      if left.length != right.length
        return "DIFFERENT at word #{[left.length, right.length].min + 1}"
      end
      left.each_with_index.all? { |word, i| ids(word[:morae]) == ids(right[i][:morae]) } ? "EXACT" : "LOOSE"
    when "MORAE"
      total = words.sum { |word| word[:morae].length }
      displays = words.map do |word|
        word[:morae].map { |mora| @info.key?(mora[:id]) ? spelling(system, mora[:id]) : mora[:id] }.join(".")
      end
      "#{total}: " + displays.join(" ")
    when "SYLLABLES"
      total = 0
      displays = words.map do |word|
        pairs, = long_data(word[:morae])
        parts = written_parts(word[:morae], system, "KEEP")
        groups = []
        word[:morae].each_with_index do |mora, i|
          if i.zero? || (@info.key?(mora[:id]) && !pairs.key?(i))
            groups << parts[i]
          else
            groups[-1] += parts[i]
          end
        end
        total += groups.length
        groups.join(".")
      end
      "#{total}: " + displays.join(" ")
    when "ROW"
      words.flat_map do |word|
        word[:morae].map do |mora|
          item = @info[mora[:id]]
          if item
            "#{spelling(system, mora[:id])}: #{item[:row]} #{item[:dan]}"
          else
            "#{mora[:id]}: special"
          end
        end
      end.join(", ")
    when "STATS"
      counts = Hash.new(0)
      all = words.flat_map { |word| word[:morae] }
      all.each do |mora|
        item = @info[mora[:id]]
        if item
          counts[devoice(item[:row])] += 1
          counts["voiced"] += 1 if %w[ga za da ba].include?(item[:row])
          counts["semivoiced"] += 1 if item[:row] == "pa"
          counts["contracted"] += 1 if item[:contracted]
        else
          counts[mora[:id] == "-" ? "L" : mora[:id]] += 1
        end
      end
      output = ["morae=#{all.length}"]
      BASE_ROWS.each do |row|
        output << "#{row}=#{counts[row]}" if counts[row].positive?
      end
      %w[voiced semivoiced contracted N Q L].each do |key|
        output << "#{key}=#{counts[key]}"
      end
      output.join(" ")
    when "SORT", "INDEX"
      sorted = sorted_words(words)
      return sorted.map { |word| word[:original] }.join(" ") if name == "SORT"

      groups = []
      sorted.each do |word|
        base = collation_elements(word[:morae])[0][:base]
        heading = @settings["ORDER"] == "IROHA" || base == "N" ? base : @info[base][:row]
        if groups.empty? || groups[-1][:heading] != heading
          groups << { heading: heading, words: [] }
        end
        groups[-1][:words] << word[:original]
      end
      groups.map { |group| group[:heading] + ": " + group[:words].join(" ") }.join("; ")
    when "FIND"
      matches = words.select { |word| matches_pattern?(pattern, word[:morae]) }
      counted(matches.map { |word| word[:original] }, words.length)
    when "HAIKU"
      counts = Array.new(pieces.length, 0)
      words.each do |word|
        line_index = text[0...word[:start]].count("/")
        counts[line_index] += word[:morae].length
      end
      expected = pieces.length == 3 ? [5, 7, 5] : [5, 7, 5, 7, 7]
      verdict = counts == expected ? "OK" : "NG"
      "#{verdict} #{pieces.length == 3 ? 'haiku' : 'tanka'} " + counts.join("-")
    when "KAIBUN"
      sequence = words.flat_map { |word| collation_elements(word[:morae]).map { |item| item[:base] } }
      (sequence == sequence.reverse ? "YES " : "NO ") + sequence.join(".")
    when "SHIRITORI"
      seen = {}
      previous_tail = nil
      words.each_with_index do |word, i|
        sequence = collation_elements(word[:morae])
        head = sequence[0][:base]
        tail = sequence[-1][:base]
        prefix = "NG #{i + 1}: #{word[:original]}"
        if i.positive? && head != previous_tail
          return prefix + " must start with " + spelling(system, previous_tail)
        end
        key = ids(word[:morae])
        return prefix + " is repeated" if seen.key?(key)
        return prefix + " ends with N" if tail == "N"

        seen[key] = true
        previous_tail = tail
      end
      "OK #{words.length}"
    end
  end
end

converter = Romaji.new
count = STDIN.readline.to_i
output = Array.new(count) do
  line = STDIN.readline.chomp
  begin
    converter.command(line)
  rescue Invalid => error
    "ERROR " + error.message
  end
end
STDOUT.write(output.join("\n") + "\n")
