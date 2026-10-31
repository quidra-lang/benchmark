
require 'set'

FIELDS = %w[author editor title journal booktitle edition volume number pages publisher institution school address howpublished month year doi note].freeze
TYPES = %w[article book inproceedings incollection techreport phdthesis misc].freeze
REQUIRED = [
  %w[author title journal year], %w[author title publisher year], %w[author title booktitle year],
  %w[author title booktitle publisher year], %w[author title institution year], %w[author title school year], %w[author title year]
].map(&:freeze).freeze
MONTHS = %w[January February March April May June July August September October November December].freeze
MONTH_MACROS = %w[jan feb mar apr may jun jul aug sep oct nov dec].freeze
MONTH_SHORT = %w[Jan. Feb. Mar. Apr. May June July Aug. Sep. Oct. Nov. Dec.].freeze
SMALL_WORDS = %w[a an and as at but by for from in into nor of on or over per so the to up via with yet].to_set.freeze
STYLES = %w[APA IEEE CHICAGO MLA].freeze

class Problem < StandardError; end
class LoadProblem < StandardError
  attr_reader :line
  def initialize(line, message)
    super(message)
    @line = line
  end
end

module Text
  module_function

  def lower?(c) = ('a'..'z').cover?(c)
  def upper?(c) = ('A'..'Z').cover?(c)
  def letter?(c) = lower?(c) || upper?(c)
  def digit?(c) = ('0'..'9').cover?(c)
  def lower(text) = text.tr('A-Z', 'a-z')
  def upper(text) = text.tr('a-z', 'A-Z')
  def plain(text) = text.delete('{}')
  def letters(text) = lower(text.delete('^A-Za-z'))
  def digits?(text) = !text.empty? && text.each_char.all? { |c| digit?(c) }

  def split_depth(text, separator)
    result = []
    start = i = depth = 0
    while i < text.length
      if depth.zero? && text[i, separator.length] == separator
        result << text[start...i]
        i += separator.length
        start = i
      else
        depth += 1 if text[i] == '{'
        depth -= 1 if text[i] == '}'
        i += 1
      end
    end
    result << text[start..]
  end

  def evaluate(expression, macros, line)
    depth = 0
    expression.each_char do |c|
      depth += 1 if c == '{'
      depth -= 1 if c == '}'
      raise LoadProblem.new(line, 'unbalanced braces') if depth.negative?
    end
    raise LoadProblem.new(line, 'unbalanced braces') unless depth.zero?
    expression.split(' # ', -1).map do |term|
      if ['{', '"'].include?(term[0])
        term[1...-1]
      elsif digit?(term[0])
        term
      else
        macros.fetch(term) { raise LoadProblem.new(line, "unknown macro '#{term}'") }
      end
    end.join
  end

  def accent(text, at)
    return nil if at + 1 >= text.length || text[at] != '\\'
    command = text[at + 1]
    return ['&', 2] if command == '&'
    symbol = "'\"`^~=.".include?(command)
    return [text[at + 2], 3] if symbol && at + 2 < text.length && letter?(text[at + 2])
    if (symbol || 'cuvH'.include?(command)) && at + 4 < text.length && text[at + 2] == '{' && letter?(text[at + 3]) && text[at + 4] == '}'
      return [text[at + 3], 5]
    end
    nil
  end

  def normalize(text)
    result = +''
    i = 0
    while i < text.length
      wrapped = text[i] == '{' ? accent(text, i + 1) : nil
      if wrapped && text[i + wrapped[1] + 1] == '}'
        result << wrapped[0]
        i += wrapped[1] + 2
      else
        current = accent(text, i)
        result << (current ? current[0] : text[i])
        i += current ? current[1] : 1
      end
    end
    result.tr('~', ' ').split(' ').join(' ')
  end

  def title_case(title, style)
    return title if style == 'IEEE'
    if style == 'APA'
      result = title.dup
      depth = 0
      title.each_char.with_index do |c, i|
        if c == '{'
          depth += 1
        elsif c == '}'
          depth -= 1
        elsif depth.zero? && letter?(c)
          result[i] = i.zero? || i >= 2 && title[i - 2, 2] == ': ' ? upper(c) : lower(c)
        end
      end
      return result
    end
    words = split_depth(title, ' ')
    words.each_index do |i|
      word = words[i]
      next if word.start_with?('{')
      make_lower = i.positive? && i + 1 < words.length && !words[i - 1].end_with?(':') && SMALL_WORDS.include?(letters(word))
      result = word.dup
      depth = 0
      first_letter = true
      word.each_char.with_index do |c, j|
        if c == '{'
          depth += 1
        elsif c == '}'
          depth -= 1
        elsif letter?(c)
          result[j] = lower(c) if depth.zero? && make_lower
          result[j] = upper(c) if depth.zero? && !make_lower && first_letter
          first_letter = false
        end
      end
      words[i] = result
    end
    words.join(' ')
  end

  def listed(names, conjunction, list_b)
    return names.first if names.length == 1
    return "#{names.first} #{conjunction} #{names.last}" if list_b && names.length == 2
    "#{names[0...-1].join(', ')}, #{conjunction} #{names.last}"
  end
end

Name = Data.define(:first, :von, :last, :jr) do
  def self.parse(text)
    parts = Text.split_depth(text, ',').map(&:strip)
    words = Text.split_depth(parts.first, ' ')
    lower_words = (0...(words.length - 1)).select { |i| Text.lower?(words[i][0]) }
    first_lower = lower_words.first
    last_lower = lower_words.last
    if parts.length == 1
      return new(words[0...-1].join(' '), '', words.last, '') unless first_lower
      return new(words[0...first_lower].join(' '), words[first_lower..last_lower].join(' '), words[last_lower + 1..].join(' '), '')
    end
    von = last_lower ? words[0..last_lower].join(' ') : ''
    last = words[(last_lower ? last_lower + 1 : 0)..].join(' ')
    new(parts.last, von, last, parts.length == 3 ? parts[1] : '')
  end

  def surname = Text.plain(von.empty? ? last : "#{von} #{last}")
  def initials
    Text.plain(first).split(' ').map do |word|
      word.split('-', -1).map { |piece| "#{Text.upper(piece.each_char.find { |c| Text.letter?(c) })}." }.join('-')
    end.join(' ')
  end

  def text(inverted, abbreviated)
    given = abbreviated ? initials : Text.plain(first)
    result = surname
    result = inverted ? "#{result}, #{given}" : "#{given} #{result}" unless first.empty?
    result += ", #{Text.plain(jr)}" unless jr.empty?
    result
  end
end

NameList = Data.define(:names, :et_al) do
  def self.parse(text)
    parts = Text.split_depth(text, ' and ')
    et_al = parts.last == 'others'
    parts.pop if et_al
    new(parts.map { |part| Name.parse(part) }.freeze, et_al)
  end

  def single? = names.length == 1 && !et_al

  def format(style, editor = false)
    values = names.each_with_index.map { |name, i| name.text(!editor && (style == 'APA' || style != 'IEEE' && i.zero?), %w[APA IEEE].include?(style)) }
    return et_al ? "#{values.first} et al." : Text.listed(values, style == 'APA' ? '&' : 'and', true) if editor
    case style
    when 'APA'
      return "#{values.join(', ')}, et al." if et_al
      return "#{values.take(19).join(', ')}, . . . #{values.last}" if values.length >= 21
      Text.listed(values, '&', false)
    when 'IEEE'
      et_al || values.length >= 7 ? "#{values.first} et al." : Text.listed(values, 'and', true)
    when 'CHICAGO'
      et_al || values.length >= 11 ? "#{values.take(7).join(', ')}, et al." : Text.listed(values, 'and', false)
    when 'MLA'
      et_al || values.length >= 3 ? "#{values.first}, et al." : Text.listed(values, 'and', false)
    end
  end
end

class Entry
  attr_reader :key, :kind, :fields, :authors, :editors, :year, :plain_title, :lower_title, :sort_title, :sort_key, :base_key
  attr_accessor :suffix

  def initialize(key, kind, fields)
    @key, @kind, @fields = key, kind, fields.dup.freeze
    @authors = NameList.parse(fields['author']) if fields.key?('author')
    @editors = NameList.parse(fields['editor']) if fields.key?('editor')
    lead = primary.names.first
    @year = Text.plain(fields.fetch('year'))
    @plain_title = Text.plain(fields.fetch('title'))
    @lower_title = Text.lower(plain_title)
    prefix = ['a ', 'an ', 'the '].find { |item| lower_title.start_with?(item) }
    @sort_title = prefix ? lower_title.delete_prefix(prefix) : lower_title
    @sort_key = [Text.lower(Text.plain(lead.last)), year, sort_title, key].freeze
    word = plain_title.split(' ').map { |item| Text.letters(item) }.find { |item| !item.empty? && !SMALL_WORDS.include?(item) } || ''
    @base_key = Text.letters(Text.plain(lead.last)) + fields.fetch('year').delete('^0-9') + word
    @suffix = ''
  end

  def primary = authors || editors
  def year_label(style) = year + (%w[APA CHICAGO].include?(style) ? suffix : '')
  def short_name(style, parenthetical)
    list = primary
    return "#{list.names.first.surname} et al." if list.et_al || list.names.length >= (style == 'CHICAGO' ? 4 : 3)
    Text.listed(list.names.map(&:surname), style == 'APA' && parenthetical ? '&' : 'and', true)
  end
  def unknown_fields = (fields.keys - FIELDS).sort
end

module References
  TEMPLATES = [
    [
      '{author}. ({year}). {title}. {journal}<, {volume}<({number})>><, {pages}>.< https://doi.org/{doi}>',
      '{author}. ({year}). {title}< ({edition})>. {publisher}.',
      '{author}. ({year}). {title}. In <{editor} ({eds}), >{booktitle}< ({pp})>.< {publisher}.>',
      '{author}. ({year}). {title}< (Report No. {number})>. {institution}.',
      '{author}. ({year}). {title} [Doctoral dissertation, {school}].',
      '{author}. ({year}<, {month}>). {title}.< {howpublished}.>< {note}.>'
    ], [
      '{author}, "{title}," {journal}<, vol. {volume}><, no. {number}><, {pp}>, <{mon} >{year}<, doi: {doi}>.',
      '{author}, {title}<, {edition}>. <{address}: >{publisher}, {year}.',
      '{author}, "{title}," in {booktitle}<, {editor}, {eds}><, {address}><, {publisher}>, {year}<, {pp}>.',
      '{author}, "{title}," {institution}<, {address}>, Tech. Rep.< {number}>, {year}.',
      '{author}, "{title}," Ph.D. dissertation, {school}<, {address}>, {year}.',
      '{author}, "{title},"< {howpublished},> <{mon} >{year}.< {note}.>'
    ], [
      '{author}. {year}. "{title}." {journal}< {volume}>< ({number})><: {pages}>.< https://doi.org/{doi}.>',
      '{author}. {year}. {title}.< {edition}.> <{address}: >{publisher}.',
      '{author}. {year}. "{title}." In {booktitle}<, edited by {editor}><, {pages}>.< <{address}: >{publisher}.>',
      '{author}. {year}. {title}. Technical Report< {number}>. <{address}: >{institution}.',
      '{author}. {year}. "{title}." PhD diss., {school}.',
      '{author}. {year}. {title}.< {howpublished}.>< {note}.>'
    ], [
      '{author}. "{title}." {journal}<, vol. {volume}><, no. {number}>, <{mon} >{year}<, {pp}>.< https://doi.org/{doi}.>',
      '{author}. {title}.< {edition},> {publisher}, {year}.',
      '{author}. "{title}." {booktitle},< edited by {editor},>< {publisher},> {year}<, {pp}>.',
      '{author}. {title}. {institution}, {year}.< Technical Report {number}.>',
      '{author}. {title}. {year}. {school}, PhD dissertation.',
      '{author}. {title}.< {howpublished},> <{mon} >{year}.< {note}.>'
    ]
  ].map(&:freeze).freeze
  ANNOTATIONS = [[' (Ed.)', ' (Eds.)'], [', Ed.', ', Eds.'], [', ed.', ', eds.'], [', editor', ', editors']].map(&:freeze).freeze
  module_function

  def optional_end(pattern, start)
    depth = 1
    i = start
    until depth.zero?
      i += 1
      depth += 1 if pattern[i] == '<'
      depth -= 1 if pattern[i] == '>'
    end
    i
  end

  def optional_present?(pattern, start, finish, values)
    i = start
    while i < finish
      if pattern[i] == '<'
        i = optional_end(pattern, i)
      elsif pattern[i] == '{'
        close = pattern.index('}', i)
        return false if values.fetch(pattern[i + 1...close], '').empty?
        i = close
      end
      i += 1
    end
    true
  end

  def render(pattern, start, finish, values, result)
    i = start
    while i < finish
      c = pattern[i]
      if c == '<'
        close = optional_end(pattern, i)
        render(pattern, i + 1, close, values, result) if optional_present?(pattern, i + 1, close, values)
        i = close
      elsif c == '{'
        close = pattern.index('}', i)
        result << values.fetch(pattern[i + 1...close], '')
        i = close
      elsif c != '.' || result.empty? || !'.?!'.include?(result[-1])
        result << c
      end
      i += 1
    end
  end

  def format(entry, style, number, repeated = false)
    values = FIELDS.to_h { |field| [field, Text.plain(entry.fields.fetch(field, ''))] }
    author = repeated ? '---' : entry.primary.format(style)
    author += ANNOTATIONS[STYLES.index(style)][entry.primary.single? ? 0 : 1] unless entry.authors
    values['author'] = author
    if entry.editors
      values['editor'] = entry.editors.format(style, true)
      values['eds'] = entry.editors.single? ? 'Ed.' : 'Eds.'
    end
    values['title'] = Text.plain(Text.title_case(entry.fields.fetch('title'), style))
    values['year'] = entry.year_label(style)
    if entry.fields.key?('pages')
      pages = Text.plain(entry.fields['pages']).gsub('--', '-')
      values['pages'] = pages
      values['pp'] = (pages.include?('-') ? 'pp. ' : 'p. ') + pages
    end
    if entry.fields.key?('edition')
      edition = Text.plain(entry.fields['edition'])
      if Text.digits?(edition)
        n = edition.to_i
        suffix = (11..13).cover?(n % 100) ? 'th' : { 1 => 'st', 2 => 'nd', 3 => 'rd' }.fetch(n % 10, 'th')
        edition = "#{n}#{suffix}"
      end
      values['edition'] = "#{edition} ed."
    end
    if entry.fields.key?('month')
      month = Text.plain(entry.fields['month'])
      index = MONTHS.index(month)
      values['mon'] = index ? MONTH_SHORT[index] : month
    end
    kind = entry.kind == 3 ? 2 : entry.kind > 3 ? entry.kind - 1 : entry.kind
    pattern = TEMPLATES[STYLES.index(style)][kind]
    result = style == 'IEEE' ? "[#{number}] " : +''
    render(pattern, 0, pattern.length, values, result)
    result
  end
end

Citation = Data.define(:start, :finish, :kind, :entries)

class Database
  attr_reader :entries, :record, :lookup, :output

  def initialize(lines)
    @entries, @record, @lookup, @output = [], [], {}, []
    @macros = MONTH_MACROS.zip(MONTHS).to_h
    @macro_count = 0
    i = 0
    while i < lines.length
      line = lines[i]
      if line.empty? || line.start_with?('%')
        i += 1
        next
      end
      if line.start_with?('@string{')
        equals = line.index(' = ')
        name = line[8...equals]
        begin
          value = Text.evaluate(line[equals + 3...-1], @macros, i + 1)
          raise LoadProblem.new(i + 1, 'duplicate macro') if @macros.key?(name)
          @macros[name] = value.freeze
          @macro_count += 1
        rescue LoadProblem => error
          report(name, error)
        end
      else
        finish = i + 1
        finish += 1 until lines[finish] == '}'
        brace = line.index('{')
        kind, key = line[1...brace], line[brace + 1...-1]
        begin
          read_entry(lines, i, finish, kind, key)
        rescue LoadProblem => error
          report(key, error)
        end
        i = finish
      end
      i += 1
    end
    output << "LOADED entries=#{entries.length} macros=#{@macro_count} errors=#{output.length}"
    entries.group_by { |entry| [entry.primary, entry.fields['year']] }.each_value do |group|
      next if group.length == 1
      group.sort_by { |entry| [entry.sort_title, entry.key] }.each_with_index { |entry, index| entry.suffix = (97 + index).chr }
    end
  end

  def report(name, error) = output << "ERROR line #{error.line}: #{name}: #{error.message}"

  def read_entry(lines, start, finish, kind_name, key)
    kind = TYPES.index(kind_name)
    raise LoadProblem.new(start + 1, "unknown type '#{kind_name}'") unless kind
    raise LoadProblem.new(start + 1, 'duplicate key') if lookup.key?(key)
    fields = {}
    (start + 1...finish).each do |i|
      equals = lines[i].index(' = ')
      name = lines[i][2...equals]
      expression = lines[i][equals + 3..].delete_suffix(',')
      value = Text.evaluate(expression, @macros, i + 1)
      raise LoadProblem.new(i + 1, "duplicate field '#{name}'") if fields.key?(name)
      fields[name] = Text.normalize(value).freeze
    end
    REQUIRED[kind].each do |field|
      unless fields.key?(field) || kind == 1 && field == 'author' && fields.key?('editor')
        raise LoadProblem.new(finish + 1, "missing field '#{field}'")
      end
    end
    entry = Entry.new(key, kind, fields)
    entries << entry
    lookup[key] = entry
  end

  def numbering
    cited = record.to_set
    order = record + lookup.keys.sort.filter_map { |key| lookup[key] unless cited.include?(lookup[key]) }
    [order, order.each_with_index.to_h { |entry, index| [entry, index + 1] }]
  end

  def citation_text(citation, style, numbers)
    parenthetical = %w[cite citep].include?(citation.kind)
    if %w[citeauthor citeyear].include?(citation.kind) || style == 'MLA' || style == 'IEEE' && !parenthetical
      text = citation.entries.map do |entry|
        if citation.kind == 'citeyear'
          entry.year_label(style)
        else
          entry.short_name(style, false) + (style == 'IEEE' && citation.kind == 'citet' ? " [#{numbers.fetch(entry)}]" : '')
        end
      end.join(citation.kind == 'citeyear' ? ', ' : '; ')
      return style == 'MLA' && parenthetical ? "(#{text})" : text
    end
    parts = []
    if style == 'IEEE'
      sorted = citation.entries.map { |entry| numbers.fetch(entry) }.sort
      i = 0
      while i < sorted.length
        finish = i + 1
        finish += 1 while finish < sorted.length && sorted[finish] == sorted[finish - 1] + 1
        if finish - i >= 3
          parts << "[#{sorted[i]}]-[#{sorted[finish - 1]}]"
        else
          (i...finish).each { |j| parts << "[#{sorted[j]}]" }
        end
        i = finish
      end
      return parts.join(', ')
    end
    ordered = parenthetical ? citation.entries.sort_by(&:sort_key) : citation.entries
    i = 0
    while i < ordered.length
      name = ordered[i].short_name(style, parenthetical)
      finish = i + 1
      finish += 1 while finish < ordered.length && ordered[finish].short_name(style, parenthetical) == name
      years = ordered[i...finish].map { |entry| entry.year_label(style) }.join(', ')
      parts << (parenthetical ? name + (style == 'APA' ? ', ' : ' ') + years : "#{name} (#{years})")
      i = finish
    end
    text = parts.join('; ')
    parenthetical ? "(#{text})" : text
  end

  def cite(style, text)
    citations = []
    start = text.index('\\')
    while start
      brace = text.index('{', start)
      finish = text.index('}', brace)
      seen = Set.new
      text[brace + 1...finish].split(',').each do |key|
        seen << lookup.fetch(key) { raise Problem, "unknown key '#{key}'" }
      end
      citations << Citation.new(start, finish + 1, text[start + 1...brace], seen.to_a.freeze)
      start = text.index('\\', finish + 1)
    end
    recorded = record.to_set
    citations.each { |citation| citation.entries.each { |entry| record << entry if recorded.add?(entry) } }
    numbers = numbering[1]
    result = +''
    position = 0
    citations.each do |citation|
      result << text[position...citation.start] << citation_text(citation, style, numbers)
      position = citation.finish
    end
    result << text[position..]
  end

  def keygen
    counts = entries.map(&:base_key).tally
    used = Hash.new(0)
    entries.map do |entry|
      key = entry.base_key
      if counts[key] >= 2
        index = used[key]
        used[key] += 1
        key += (97 + index).chr(Encoding::UTF_8)
      end
      "#{entry.key} -> #{key}"
    end
  end

  def check
    result = []
    titles = {}
    entries.each do |entry|
      warnings = []
      if entry.fields.key?('pages')
        pages = Text.plain(entry.fields['pages'])
        warnings << 'pages use a single hyphen' if pages.include?('-') && !pages.include?('--')
        parts = pages.split('-', -1).reject(&:empty?)
        warnings << 'pages are reversed' if parts.length == 2 && parts.all? { |part| Text.digits?(part) } && parts[0].to_i > parts[1].to_i
      end
      warnings << 'year is not 4 digits' unless entry.year.length == 4 && Text.digits?(entry.year)
      warnings << 'title is all caps' if entry.plain_title.each_char.none? { |c| Text.lower?(c) } && entry.plain_title.each_char.count { |c| Text.upper?(c) } >= 2
      warnings << 'article has no doi' if entry.kind.zero? && !entry.fields.key?('doi')
      if titles.key?(entry.lower_title)
        warnings << "same title as #{titles[entry.lower_title]}"
      else
        titles[entry.lower_title] = entry.key
      end
      entry.unknown_fields.each { |field| warnings << "unknown field '#{field}'" }
      warnings.each { |warning| result << "WARN #{entry.key}: #{warning}" }
    end
    result << "CHECK warnings=#{result.length}"
  end

  def export(key)
    entry = lookup.fetch(key) { raise Problem, "unknown key '#{key}'" }
    names = FIELDS.select { |field| entry.fields.key?(field) } + entry.unknown_fields
    rows = names.each_with_index.map do |name, i|
      "  #{name} = {#{entry.fields.fetch(name)}}#{i + 1 == names.length ? '' : ','}"
    end
    ["@#{TYPES[entry.kind]}{#{key},"] + rows + ['}']
  end

  def stats
    types = entries.map { |entry| TYPES[entry.kind] }.tally
    years = entries.map(&:year).tally
    authors = Set.new
    pairs = Hash.new(0)
    entries.each do |entry|
      next unless entry.authors
      names = entry.authors.names.map { |name| name.text(false, false) }.uniq.sort
      authors.merge(names)
      names.combination(2) { |pair| pairs[pair.freeze] += 1 }
    end
    result = ["ENTRIES #{entries.length}"]
    types.keys.sort.each { |type| result << "TYPE #{type} #{types[type]}" }
    years.keys.sort.each { |year| result << "YEAR #{year} #{years[year]}" }
    result << "AUTHORS #{authors.length}"
    best = pairs.keys.min_by { |pair| [-pairs[pair], *pair] }
    result << (best ? "PAIR #{best[0]} & #{best[1]} #{pairs[best]}" : 'PAIR none')
  end

  def command(line)
    first = line.index(' ')
    command = first ? line[0...first] : line
    if %w[CITE SEARCH].include?(command) && first
      second = line.index(' ', first + 1)
      words = second ? [command, line[first + 1...second], line[second + 1..]] : [command, line[first + 1..]]
    else
      words = line.split(' ')
    end
    arity = { 'FORMAT' => -1, 'BIBLIOGRAPHY' => 1, 'CITE' => 2, 'KEYGEN' => 0, 'CHECK' => 0, 'SEARCH' => 2, 'EXPORT' => 1, 'STATS' => 0 }
      .fetch(command) { raise Problem, "unknown command '#{command}'" }
    raise Problem, 'wrong number of arguments' if (arity == -1 ? words.length < 3 : words.length != arity + 1)
    style = 'APA'
    if %w[FORMAT BIBLIOGRAPHY CITE].include?(command)
      style = words[1]
      raise Problem, "unknown style '#{style}'" unless STYLES.include?(style)
    end
    case command
    when 'FORMAT'
      numbers = numbering[1]
      words.drop(2).map { |key| lookup.key?(key) ? References.format(lookup[key], style, numbers.fetch(lookup[key])) : "ERROR unknown key '#{key}'" }
    when 'BIBLIOGRAPHY'
      order, numbers = numbering
      order = order.sort_by(&:sort_key) unless style == 'IEEE'
      rows = order.each_with_index.map do |entry, index|
        repeated = index.positive? && %w[CHICAGO MLA].include?(style) && entry.primary == order[index - 1].primary
        References.format(entry, style, numbers.fetch(entry), repeated)
      end
      [style == 'MLA' ? 'Works Cited' : 'References'] + rows
    when 'CITE' then [cite(style, words[2])]
    when 'KEYGEN' then keygen
    when 'CHECK' then check
    when 'EXPORT' then export(words[1])
    when 'STATS' then stats
    when 'SEARCH'
      needle = Text.lower(words[2])
      matches = entries.select { |entry| entry.fields.key?(words[1]) && Text.lower(Text.plain(entry.fields[words[1]])).include?(needle) }.map(&:key)
      [matches.empty? ? 'MATCHES 0' : "MATCHES #{matches.length}: #{matches.join(' ')}"]
    end
  end
end

lines = []
while (line = STDIN.gets(chomp: true)) != '%%'
  lines << line
end
database = Database.new(lines)
puts database.output
STDIN.gets.to_i.times do
  begin
    puts database.command(STDIN.gets(chomp: true))
  rescue Problem => error
    puts "ERROR #{error.message}"
  end
end
