require 'fileutils'
require_relative 'document_parser'
require_relative 'hyphenation'
require_relative 'line_breaker'
require_relative 'page_builder'
require_relative 'renderer'

BreakPosition = Struct.new(:start, :finish, :midword, :append_hyphen)

class TextMetrics
  attr_reader :breaks, :end_index

  def initialize(words, first_capacity, later_capacity, dictionary)
    @words, @first_capacity, @later_capacity = words, first_capacity, later_capacity
    @offsets = []
    @breaks = [BreakPosition.new([0, 0], [0, 0], false, false)]
    offset = 0
    words.each_with_index do |word, i|
      @offsets << offset
      offset += word.length + 1
      dictionary.split_points(word).each do |position, append_hyphen|
        point = [i, position]
        @breaks << BreakPosition.new(point, point, true, append_hyphen)
      end
      @breaks << BreakPosition.new([i + 1, 0], [i, word.length], false, false)
    end
    @end_index = @breaks.length - 1
  end

  def capacity(start)
    start.zero? ? @first_capacity : @later_capacity
  end

  def length(start, finish)
    first_word, first_position = @breaks[start].start
    last_word, last_position = @breaks[finish].finish
    size = @offsets[last_word] + last_position - @offsets[first_word] - first_position
    size += 1 if @breaks[finish].append_hyphen
    size
  end

  def slack(start, finish)
    capacity(start) - length(start, finish)
  end

  def measure(start, finish)
    first_word, first_position = @breaks[start].start
    last_word, last_position = @breaks[finish].finish
    pieces, ranges = [], []
    (first_word..last_word).each do |word|
      first = word == first_word ? first_position : 0
      last = word == last_word ? last_position : @words[word].length
      pieces << @words[word][first...last]
      ranges << [word, first, last]
    end
    pieces[-1] += '-' if @breaks[finish].append_hyphen
    size = length(start, finish)
    { start: start, finish: finish, pieces: pieces, ranges: ranges, gaps: pieces.length - 1,
      length: size, capacity: capacity(start), slack: capacity(start) - size,
      last: finish == @end_index, midword: @breaks[finish].midword }
  end
end

class Typesetter
  def initialize(document, params, dictionary_lines)
    @document, @params = document, params
    @blocks, @warnings = document.values_at(:blocks, :warnings)
    @labels, @bibliography, @index_entries = {}, {}, {}
    @cited_entries, @body_blocks, @headings, @numbered_tables = [], [], [], []
    @footnotes, @index_marks = [], []
    @dictionary = Hyphenation.new(dictionary_lines, document[:hyphenation_words],
                                  params[:left_min], params[:right_min])
    register_document
    check_document
    assign_bibliography_labels
    prepare_index
    @warnings = @warnings.each_with_index.sort_by { |(line, _message), i| [line, i] }.map(&:first)
  end

  def warn(line_number, message)
    @warnings << [line_number, message]
  end

  def text_line(text)
    { text: text, footnotes: [], indexes: [] }
  end

  def split_label(text)
    if text.end_with?('}') && text.include?(' {#')
      heading, _separator, label = text.rpartition(' {#')
      [heading, label[0...-1]]
    else
      [text, nil]
    end
  end

  def register_document
    chapter, section, table_number, previous = 0, 0, 0, nil
    @blocks.each_with_index do |block, i|
      block[:id], block[:label] = i, nil
      kind = block[:kind]
      case kind
      when 'h1', 'h2'
        block[:text], block[:label] = split_label(block[:argument])
        if kind == 'h1'
          chapter += 1
          section = 0
          block[:number] = chapter.to_s
          block[:page_break] = true unless i.zero?
        else
          section += 1
          block[:number] = "#{chapter}.#{section}"
        end
        @headings << block
      when 'enum'
        block[:number] = previous && previous[:kind] == 'enum' ? previous[:number] + 1 : 1
      when 'table'
        block[:caption], block[:label] = split_label(block[:caption])
        block[:number] = nil
        unless block[:caption].empty?
          table_number += 1
          block[:number] = table_number.to_s
          @numbered_tables << block
        end
      end
      if block[:label]
        label = block[:label]
        if @labels.key?(label)
          warn(block[:line_number], "duplicate label #{label}")
          block[:label] = nil
        else
          @labels[label] = block
        end
      end
      block[:indent] = 0 if kind == 'paragraph' && previous && %w[h1 h2].include?(previous[:kind])
      if DocumentParser::BODY_KINDS.include?(kind)
        @body_blocks << block
        block[:paragraph_number] = @body_blocks.length
      end
      previous = block
    end
    @document[:bibliography].each do |entry|
      key = entry[:key]
      if @bibliography.key?(key)
        warn(entry[:line_number], "duplicate bibliography key #{key}")
      else
        @bibliography[key] = entry.merge(cited: false)
      end
    end
  end

  def check_table(block)
    count = block[:columns].length
    rows = block[:inner_lines].map do |line_number, text|
      cells = text.empty? ? [''] : text.split('|', -1).map { |cell| cell.strip }
      if cells.length != count
        warn(line_number, "table row has #{cells.length} cells, expected #{count}")
        cells = (cells + Array.new([count - cells.length, 0].max, '')).first(count)
      end
      cells
    end
    block[:rows] = rows
    block[:table_lines] = Renderer.format_table(rows, block[:columns], block[:caption], block[:number])
    excess = block[:table_lines].map(&:length).max - block[:width]
    warn(block[:line_number], "table too wide by #{excess}") if excess > 0
  end

  def accept_command(name, argument, line_number)
    case name
    when 'ref', 'page'
      warn(line_number, "undefined label #{argument}") unless @labels.key?(argument)
    when 'cite'
      argument.split(',').each do |key|
        if @bibliography.key?(key)
          @bibliography[key][:cited] = true
        else
          warn(line_number, "undefined citation #{key}")
        end
      end
    when 'fn'
      @footnotes << argument
      return [name, @footnotes.length]
    when 'idx'
      @index_marks << argument
      return [name, @index_marks.length]
    end
    [name, argument]
  end

  def parse_body_line(text, line_number)
    tokens, position = [], 0
    while position < text.length
      opening = text.index('{', position)
      unless opening
        tokens << text[position..]
        break
      end
      tokens << text[position...opening] if opening > position
      closing = text.index('}', opening + 1)
      unless closing
        warn(line_number, 'unclosed brace')
        tokens << text[opening..]
        break
      end
      content = text[(opening + 1)...closing]
      name, separator, argument = content.partition(':')
      if %w[ref page fn idx cite].include?(name) && !separator.empty? && !argument.empty?
        tokens << accept_command(name, argument, line_number)
      else
        warn(line_number, "bad command {#{content}}")
      end
      position = closing + 1
    end
    tokens
  end

  def check_document
    @blocks.each do |block|
      if block[:kind] == 'table'
        check_table(block)
      elsif block[:kind] == 'verbatim'
        block[:inner_lines].each do |line_number, text|
          excess = text.length - block[:width]
          warn(line_number, "verbatim line too long by #{excess}") if excess > 0
        end
      elsif DocumentParser::BODY_KINDS.include?(block[:kind])
        tokens = []
        block[:body_lines].each_with_index do |(line_number, text), i|
          tokens << ' ' unless i.zero?
          tokens.concat(parse_body_line(text, line_number))
        end
        block[:tokens] = tokens
      end
    end
    @bibliography.each_value do |entry|
      warn(entry[:line_number], "unused bibliography entry #{entry[:key]}") unless entry[:cited]
    end
  end

  def assign_bibliography_labels
    @cited_entries = @bibliography.values.select { |entry| entry[:cited] }
    @cited_entries.each do |entry|
      surnames = entry[:author].split(' and ')
      base = if surnames.length == 1
               surnames.first[0, 3]
             elsif surnames.length <= 4
               surnames.map { |surname| surname[0] }.join
             else
               surnames.first(3).map { |surname| surname[0] }.join + '+'
             end
      entry[:base_label] = base + entry[:year][-2, 2]
    end
    @cited_entries.sort_by! { |entry| entry.values_at(:base_label, :author, :title, :key) }
    @cited_entries.group_by { |entry| entry[:base_label] }.each do |base, entries|
      entries.each_with_index { |entry, i| entry[:label] = base + (entries.length > 1 ? (97 + i).chr : '') }
    end
  end

  def prepare_index
    @index_marks.each_with_index do |phrase, i|
      entry_part, reference_separator, reference = phrase.partition('|')
      parent_name, child_separator, child_name = entry_part.partition('!')
      parent = @index_entries[parent_name] ||= { name: parent_name, marks: [], references: [], children: {} }
      entry = if child_separator.empty?
                parent
              else
                parent[:children][child_name] ||= { name: child_name, marks: [], references: [] }
              end
      if reference_separator.empty?
        entry[:marks] << i + 1
      else
        entry[:references] << reference
      end
    end
  end

  def citation_text(argument)
    labels, undefined = [], false
    argument.split(',').each do |key|
      entry = @bibliography[key]
      if entry
        labels << entry[:label]
      else
        undefined = true
      end
    end
    parts = labels.uniq.sort
    parts << '?' if undefined
    '[' + parts.join(', ') + ']'
  end

  def expand_body(block, page_values)
    parts, marks, offset = [], [], 0
    block[:tokens].each do |token|
      if token.is_a?(String)
        text = token
      else
        name, argument = token
        case name
        when 'idx'
          marks << [offset - 1, name, argument]
          next
        when 'fn'
          marks << [offset, name, argument]
          text = "[#{argument}]"
        when 'ref'
          target = @labels[argument]
          text = target ? target[:number] : '??'
        when 'page'
          text = page_values.fetch(argument, '??')
        when 'cite'
          text = citation_text(argument)
        end
      end
      parts << text
      offset += text.length
    end
    expanded = parts.join
    words, starts = [], []
    expanded.scan(/[^ ]+/) do |word|
      words << word
      starts << Regexp.last_match.begin(0)
    end
    word_marks = Hash.new { |hash, word| hash[word] = [] }
    marks.each do |mark_offset, kind, number|
      after = starts.bsearch_index { |start| start > mark_offset } || starts.length
      word = after - 1
      word_marks[word] << [kind, number, mark_offset - starts[word]]
    end
    [words, word_marks]
  end

  def place_marks(line, measured, word_marks)
    measured[:ranges].each do |word, first, last|
      word_marks.fetch(word, []).each do |kind, number, position|
        next unless first <= position && position < last

        line[kind == 'fn' ? :footnotes : :indexes] << number
      end
    end
  end

  def lay_out_text(words, capacities, alignment, prefixes, method, word_marks = nil)
    metrics = TextMetrics.new(words, *capacities, @dictionary)
    breaking, cost = LineBreaker.break_text(metrics, method, @params)
    lines, measured_lines, start = [], [], 0
    breaking.each_with_index do |finish, i|
      measured = metrics.measure(start, finish)
      text = Renderer.display_line(measured[:pieces], measured[:slack], alignment, measured[:last])
      line = text_line(prefixes[i.zero? ? 0 : 1] + text)
      place_marks(line, measured, word_marks) if word_marks
      lines << line
      measured_lines << measured
      start = finish
    end
    { lines: lines, broken: measured_lines, cost: cost }
  end

  def body_format(block)
    width = block[:width]
    case block[:kind]
    when 'paragraph'
      indent = block[:indent]
      [[width - indent, width], [' ' * indent, '']]
    when 'item'
      [[width - 2, width - 2], ['- ', '  ']]
    when 'enum'
      [[width - 4, width - 4], [format('%2d. ', block[:number]), ' ' * 4]]
    when 'quote'
      [[width - 8, width - 8], [' ' * 4, ' ' * 4]]
    when 'term'
      first = block[:term].length <= 10 ? block[:term].ljust(12) : ' ' * 12
      [[width - 12, width - 12], [first, ' ' * 12]]
    end
  end

  def lay_out_body(block, page_values, method)
    words, marks = expand_body(block, page_values)
    capacities, prefixes = body_format(block)
    result = lay_out_text(words, capacities, block[:align], prefixes, method, marks)
    result[:lines].unshift(text_line(block[:term])) if block[:kind] == 'term' && block[:term].length >= 11
    result
  end

  def lay_out_footnotes(method)
    @footnotes.each_with_index.to_h do |text, i|
      prefix = "[#{i + 1}] "
      capacity = @document[:page_width] - prefix.length
      result = lay_out_text(text.split(' '), [capacity, capacity], 'left', [prefix, ' ' * prefix.length], method)
      [i + 1, result]
    end
  end

  def lay_out_reference(entry, width, method)
    margin = @cited_entries.map { |item| item[:label].length }.max + 3
    text = "#{entry[:author]}. #{entry[:year]}. #{entry[:title]}"
    capacity = width - margin
    prefix = "[#{entry[:label]}]".ljust(margin)
    lay_out_text(text.split(' '), [capacity, capacity], 'left', [prefix, ' ' * margin], method)
  end

  def page_list(numbers)
    numbers = numbers.uniq.sort
    parts, i = [], 0
    while i < numbers.length
      last = i
      last += 1 while last + 1 < numbers.length && numbers[last + 1] == numbers[last] + 1
      if last - i >= 2
        parts << "#{numbers[i]}-#{numbers[last]}"
      else
        parts.concat(numbers[i..last].map(&:to_s))
      end
      i = last + 1
    end
    parts.join(', ')
  end

  def index_entry_line(entry, mark_pages, child = false)
    text = (child ? '  ' : '') + entry[:name]
    numbers = entry[:marks].filter_map { |number| mark_pages[number] }
    text += ', ' + page_list(numbers) unless numbers.empty?
    references = entry[:references].uniq.sort
    text += ', see ' + references.join(', ') unless references.empty?
    text
  end

  def index_lines(mark_pages)
    lines, previous_group = [], nil
    @index_entries.keys.sort_by { |name| [name.downcase, name] }.each do |name|
      parent = @index_entries[name]
      group = Hyphenation.letter?(name[0]) ? name[0].upcase : 'Symbols'
      if group != previous_group
        lines << group
        previous_group = group
      end
      lines << index_entry_line(parent, mark_pages)
      parent[:children].keys.sort_by { |child| [child.downcase, child] }.each do |child|
        lines << index_entry_line(parent[:children][child], mark_pages, true)
      end
    end
    lines
  end

  def contents_lines(block, block_pages)
    entries = block[:kind] == 'toc' ? @headings : @numbered_tables
    entries.map do |entry|
      left = if block[:kind] == 'toc'
               (entry[:kind] == 'h2' ? '  ' : '') + "#{entry[:number]} #{entry[:text]}"
             else
               "Table #{entry[:number]}. #{entry[:caption]}"
             end
      page = block_pages[entry[:id]]
      number = page ? page[:display] : '??'
      dots = block[:width] - left.length - number.length - 2
      left + ' ' + '.' * dots + ' ' + number
    end
  end

  def add_layout_block(layout, source, kind, lines, list_mark: false, first: true)
    if first
      lines.first[:anchor] = source[:id]
      lines.first[:chapter_start] = true if source[:kind] == 'h1'
    end
    layout << { kind: kind, lines: lines, list: list_mark, page_break: first && source[:page_break] }
  end

  def build_layout_blocks(page_values, method, result)
    layout = []
    @blocks.each do |block|
      kind = block[:kind]
      if DocumentParser::BODY_KINDS.include?(kind)
        body = lay_out_body(block, page_values, method)
        result[:bodies][block[:id]] = body
        result[:warning_texts] << ["paragraph #{block[:paragraph_number]}", body, block[:align] == 'justify']
        add_layout_block(layout, block, 'flow', body[:lines], list_mark: %w[item enum term].include?(kind))
      elsif %w[title author].include?(kind)
        text = kind == 'title' ? block[:argument].upcase : block[:argument]
        text = ' ' * ((block[:width] - text.length) / 2) + text
        add_layout_block(layout, block, 'heading', [text_line(text)])
      elsif %w[h1 h2].include?(kind)
        text = kind == 'h1' ? block[:text].upcase : block[:text]
        text = "#{block[:number]} #{text}"
        rule = (kind == 'h1' ? '=' : '-') * text.length
        add_layout_block(layout, block, 'heading', [text_line(text), text_line(rule)])
      elsif kind == 'table'
        add_layout_block(layout, block, 'solid', block[:table_lines].map { |text| text_line(text) })
      elsif kind == 'verbatim'
        add_layout_block(layout, block, 'flow', block[:inner_lines].map { |_line, text| text_line(text) })
      elsif %w[toc lot index].include?(kind)
        title = { 'toc' => 'CONTENTS', 'lot' => 'TABLES', 'index' => 'INDEX' }.fetch(kind)
        add_layout_block(layout, block, 'heading', [text_line(title), text_line('=' * title.length)])
        entries = kind == 'index' ? index_lines({}) : contents_lines(block, {})
        lines = entries.map { |text| text_line(text) }
        add_layout_block(layout, block, 'flow', lines, first: false)
        result[:generated] << [block, lines]
      elsif kind == 'bibliography'
        add_layout_block(layout, block, 'heading', [text_line('REFERENCES'), text_line('==========')])
        @cited_entries.each do |entry|
          reference = lay_out_reference(entry, block[:width], method)
          result[:warning_texts] << ["reference #{entry[:label]}", reference, false]
          add_layout_block(layout, block, 'flow', reference[:lines], list_mark: true, first: false)
        end
      end
    end
    layout
  end

  def roman(number)
    units = ['', 'i', 'ii', 'iii', 'iv', 'v', 'vi', 'vii', 'viii', 'ix']
    tens, remainder = number.divmod(10)
    'x' * tens + units[remainder]
  end

  def number_pages(pages, result)
    numbered = []
    pages.each do |page|
      chapter_start = !!page[:content].first[:chapter_start]
      serial = numbered.length + 1
      if chapter_start && serial.even?
        numbered << { serial: serial, blank: true, content: [], footnotes: [], height: 0,
                      ends_by_force: true, chapter_start: false }
        serial += 1
      end
      page[:serial], page[:chapter_start] = serial, chapter_start
      numbered << page
    end
    block_pages = {}
    numbered.each do |page|
      page[:content].each { |line| block_pages[line[:anchor]] = page if line.key?(:anchor) }
    end
    front_matter = @headings.empty? ? 0 : block_pages[@headings.first[:id]][:serial] - 1
    mark_pages = {}
    numbered.each do |page|
      serial = page[:serial]
      page[:body_number] = serial - front_matter
      page[:display] = serial <= front_matter ? roman(serial) : page[:body_number].to_s
      page[:content].each { |line| line[:indexes].each { |mark| mark_pages[mark] = page[:body_number] } }
    end
    result[:pages], result[:front_matter] = numbered, front_matter
    result[:block_pages], result[:mark_pages] = block_pages, mark_pages
    result[:label_values] = @labels.to_h { |label, block| [label, block_pages[block[:id]][:display]] }
  end

  def layout_once(page_values, method)
    footnotes = lay_out_footnotes(method)
    result = { method: method, bodies: {}, footnotes: footnotes, warning_texts: [], generated: [] }
    blocks = build_layout_blocks(page_values, method, result)
    heights = footnotes.to_h { |number, note| [number, note[:lines].length] }
    pages = PageBuilder.choose_pages(blocks, heights, @document[:height], @params[:orphan_lines], @params[:widow_lines])
    number_pages(pages, result)
    footnotes.each { |number, note| result[:warning_texts] << ["footnote #{number}", note, false] }
    result
  end

  def complete_generated_lines(result)
    result[:generated].each do |block, records|
      texts = block[:kind] == 'index' ? index_lines(result[:mark_pages]) : contents_lines(block, result[:block_pages])
      # Layout blocks and page contents share these records.
      records.each_with_index { |record, i| record[:text] = texts[i] }
    end
  end

  def assemble_pages(result)
    chapter, section = '', ''
    height = @document[:height]
    total = result[:pages].length - result[:front_matter]
    result[:pages].each do |page|
      if page[:blank]
        page[:header] = page[:footer] = ''
        page[:body] = Array.new(height, '')
        next
      end
      page[:content].each do |line|
        next unless line.key?(:anchor)

        block = @blocks[line[:anchor]]
        if block[:kind] == 'h1'
          chapter, section = "#{block[:number]} #{block[:text]}", ''
        elsif block[:kind] == 'h2'
          section = "#{block[:number]} #{block[:text]}"
        end
      end
      values = { page: page[:display], pages: total.to_s, chapter: chapter, section: section }
      page[:header] = if page[:chapter_start]
                        ''
                      else
                        Renderer.running_head(@document[:header], values, @document[:page_width], page[:serial])
                      end
      page[:footer] = Renderer.running_head(@document[:footer], values, @document[:page_width], page[:serial])
      content = page[:content].map { |line| line[:text] }
      note_lines = page[:footnotes].flat_map { |number| result[:footnotes][number][:lines].map { |line| line[:text] } }
      page[:body] = if note_lines.empty?
                      content + Array.new(height - content.length, '')
                    else
                      padding = height - content.length - note_lines.length - 1
                      content + Array.new(padding, '') + ['----------'] + note_lines
                    end
    end
  end

  def layout(method)
    page_values = @labels.to_h { |label, _block| [label, '??'] }
    loop do
      result = layout_once(page_values, method)
      if result[:label_values] == page_values
        complete_generated_lines(result)
        assemble_pages(result)
        return result
      end
      page_values = result[:label_values]
    end
  end

  def layout_warnings(result)
    warnings = []
    result[:warning_texts].each do |name, text, justify|
      text[:broken].each_with_index do |line, i|
        slack = line[:slack]
        if slack < 0
          warnings << "#{name} line #{i + 1}: overfull by #{-slack}"
        elsif justify && !line[:last] && slack >= @params[:underfull_slack]
          warnings << "#{name} line #{i + 1}: underfull, slack #{slack}"
        end
      end
    end
    result[:pages].each do |page|
      next if page[:blank] || page[:ends_by_force]

      empty = @document[:height] - page[:height]
      warnings << "page #{page[:serial]}: underfull, #{empty} empty lines" if empty >= @params[:underfull_page]
    end
    hyphenated = result[:bodies].values.sum { |body| body[:broken].count { |line| line[:midword] } }
    warnings << "#{result[:pages].length} pages, #{hyphenated} hyphenated lines"
    warnings.map { |message| "#{result[:method]}: #{message}" }
  end

  def statistics(optimal, greedy)
    lines = ['paragraph,lines_kp,cost_kp,lines_greedy,cost_greedy']
    totals = [0, 0, 0, 0]
    @body_blocks.each do |block|
      kp_body, greedy_body = optimal[:bodies][block[:id]], greedy[:bodies][block[:id]]
      values = [kp_body[:broken].length, kp_body[:cost], greedy_body[:broken].length, greedy_body[:cost]]
      values.each_with_index { |value, i| totals[i] += value }
      lines << ([block[:paragraph_number]] + values).join(',')
    end
    lines << 'total,' + totals.join(',')
    lines.join("\n") + "\n"
  end

  def write_outputs(optimal, greedy)
    FileUtils.mkdir_p('output')
    outputs = { 'pages.txt' => Renderer.pages_text(optimal[:pages]),
                'greedy_pages.txt' => Renderer.pages_text(greedy[:pages]),
                'stats.csv' => statistics(optimal, greedy) }
    warnings = @warnings.map { |number, message| "line #{number}: #{message}" }
    warnings.concat(layout_warnings(optimal)).concat(layout_warnings(greedy))
    outputs['log.txt'] = warnings.join("\n") + "\n"
    outputs.each { |name, text| File.write(File.join('output', name), text, encoding: 'US-ASCII') }
  end
end

if $PROGRAM_NAME == __FILE__
  params = File.readlines('input/params.txt', chomp: true, encoding: 'US-ASCII').to_h do |line|
    name, value = line.split(' ')
    [name.to_sym, value.to_i]
  end
  dictionary = File.readlines('input/hyphenation.txt', chomp: true, encoding: 'US-ASCII')
  lines = File.readlines('input/document.txt', chomp: true, encoding: 'US-ASCII')
  typesetter = Typesetter.new(DocumentParser.parse(lines), params, dictionary)
  optimal = typesetter.layout('kp')
  greedy = typesetter.layout('greedy')
  typesetter.write_outputs(optimal, greedy)
end
