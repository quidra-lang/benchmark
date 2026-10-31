
WHITESPACE = " \n"
PUNCTUATION = %q(!"#$%&'()*+,-./:;<=>?@[\]^_`{|}~)
TOC_MARKER = "\0toc\0"
Block = Struct.new(:kind, :text, :number, :children, :items, :alignments, :rows, :lines, :ordered, keyword_init: true)
Delimiter = Data.define(:char, :length, :can_open, :can_close)
TocEntry = Struct.new(:level, :id, :label, :children)

def escape_html(text)
  text.gsub(/[&<>"]/, '&' => '&amp;', '<' => '&lt;', '>' => '&gt;', '"' => '&quot;')
end

def strip_tags(text) = text.gsub(/<[^>]*>/, '')
def normalize(text) = text.downcase.gsub(/[ \n]+/, ' ').strip

def skip_space(text, at)
  at += 1 while at < text.size && WHITESPACE.include?(text[at])
  at
end

def escaped_read(text, at, stops)
  result = +''
  while at < text.size && !stops.include?(text[at])
    at += 1 if text[at] == '\\' && at + 1 < text.size && PUNCTUATION.include?(text[at + 1])
    result << text[at]
    at += 1
  end
  [result, at]
end

def opening_fence(line)
  match = /\A(`{3,}|~{3,})/.match(line)
  return nil unless match

  fence = match[0]
  info = line[fence.size..].strip
  return nil if fence[0] == '`' && info.include?('`')

  [fence, info]
end

def atx_heading(line)
  match = /\A(\#{1,6})(?: |\z)/.match(line)
  return nil unless match

  text = line[match[1].size..].strip
  trimmed = text.sub(/\#+\z/, '')
  text = trimmed.strip if trimmed.empty? || trimmed.end_with?(' ')
  Block.new(kind: :heading, text: text, number: match[1].size)
end

def rule?(line) = /\A(?:-{3,}|\*{3,}|_{3,})\z/.match?(line.delete(' '))

def list_marker(line)
  return nil if rule?(line)

  match = /\A(?:([-*+])|([0-9]{1,9})([.)])) +/.match(line)
  return nil unless match

  [match[1] || match[3], !match[2].nil?, match[2]&.to_i, line[match[0].size..]]
end

def interrupts?(line)
  !line.start_with?(' ') && (opening_fence(line) || atx_heading(line) || rule?(line) || line.start_with?('>') || list_marker(line))
end

def split_cells(line)
  text = line.strip.delete_prefix('|')
  cells = [+'']
  at = 0
  separator = false
  while at < text.size
    char = text[at]
    at += 1
    separator = false
    if char == '\\' && at < text.size
      cells[-1] << '\\' unless text[at] == '|'
      cells[-1] << text[at]
      at += 1
    elsif char == '|'
      cells << +''
      separator = true
    else
      cells[-1] << char
    end
  end
  cells.pop if separator
  cells.map(&:strip)
end

class BlockParser
  attr_reader :references, :footnotes

  def initialize
    @references = {}
    @footnotes = {}
  end

  def parse(lines)
    blocks = []
    at = 0
    while at < lines.size
      line = lines[at]
      if line.empty?
        at += 1
        next
      end
      if line.start_with?('    ')
        finish = at
        finish += 1 while finish < lines.size && (lines[finish].empty? || lines[finish].start_with?('    '))
        finish -= 1 while lines[finish - 1].empty?
        blocks << Block.new(kind: :code, text: '', lines: lines[at...finish].map { |row| row[4..] || '' })
        at = finish
        next
      end
      unless line.start_with?(' ')
        if (fence = opening_fence(line))
          marker, info = fence
          code = []
          at += 1
          while at < lines.size
            row = lines[at]
            at += 1
            break if row.size >= marker.size && row.delete(marker[0]).empty?

            code << row
          end
          blocks << Block.new(kind: :code, text: info.split(' ').first || '', lines: code)
          next
        end
        if (heading = atx_heading(line))
          blocks << heading
          at += 1
          next
        end
        if rule?(line)
          blocks << Block.new(kind: :rule)
          at += 1
          next
        end
        if line.start_with?('>')
          content = []
          while at < lines.size && lines[at].start_with?('>')
            content << lines[at][1..].delete_prefix(' ')
            at += 1
          end
          alert = /\A\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\z/.match(content.first)
          content.shift if alert
          blocks << Block.new(kind: alert ? :alert : :quote, text: alert&.[](1), children: parse(content))
          next
        end
        if (marker = list_marker(line))
          kind, ordered, number, = marker
          items = []
          loop do
            content = [marker[3]]
            at += 1
            while at < lines.size && lines[at].start_with?('  ')
              content << lines[at][2..]
              at += 1
            end
            items << parse(content)
            following = at
            following += 1 while following < lines.size && lines[following].empty?
            marker = following < lines.size ? list_marker(lines[following]) : nil
            break unless marker && marker[0] == kind && marker[1] == ordered

            at = following
          end
          blocks << Block.new(kind: :list, ordered: ordered, number: number, items: items)
          next
        end
        if definition?(line)
          at += 1
          next
        end
        if at + 1 < lines.size && line.include?('|') && lines[at + 1].include?('|')
          header = split_cells(line)
          delimiters = split_cells(lines[at + 1])
          if header.size == delimiters.size && delimiters.all? { |cell| /\A:?-+:?\z/.match?(cell) }
            alignments = delimiters.map do |cell|
              cell.start_with?(':') ? (cell.end_with?(':') ? 'center' : 'left') : (cell.end_with?(':') ? 'right' : nil)
            end
            rows = []
            at += 2
            while at < lines.size && lines[at].include?('|')
              row = split_cells(lines[at]).take(header.size)
              rows << row + Array.new(header.size - row.size, '')
              at += 1
            end
            blocks << Block.new(kind: :table, alignments: alignments, lines: header, rows: rows)
            next
          end
        end
      end
      text = [line.lstrip]
      at += 1
      level = nil
      while at < lines.size && !lines[at].empty?
        if /\A(?:={3,}|-{3,})\z/.match?(lines[at])
          level = lines[at][0] == '=' ? 1 : 2
          at += 1
          break
        end
        break if interrupts?(lines[at])

        text << lines[at].lstrip
        at += 1
      end
      text = text.join("\n")
      blocks << Block.new(kind: level ? :heading : (text == '[TOC]' ? :toc : :paragraph), text: text, number: level)
    end
    blocks
  end

  def definition?(line)
    if (match = /\A\[\^([A-Za-z0-9_-]+)\]:(.*)\z/.match(line)) && !match[2].strip.empty?
      @footnotes[match[1].downcase] ||= match[2].strip
      return true
    end
    return false unless line.start_with?('[')

    close = line.index(']')
    return false unless close && line[close + 1] == ':'

    label = line[1...close]
    return false if label.include?('[') || label.strip.empty? || label.start_with?('^')

    url, finish = escaped_read(line, skip_space(line, close + 2), ' ')
    return false if url.empty?

    at = skip_space(line, finish)
    title = nil
    if at < line.size
      return false if at == finish || !"\"'".include?(line[at])

      title, finish = escaped_read(line, at + 1, line[at])
      return false unless finish == line.size - 1
    end
    @references[normalize(label)] ||= [url, title]
    true
  end
end

def run_end(text, at)
  char = text[at]
  at += 1
  at += 1 while at < text.size && text[at] == char
  at
end

def backtick_closer(text, at, length)
  while (at = text.index('`', at))
    finish = run_end(text, at)
    return at if finish - at == length

    at = finish
  end
  nil
end

def closing_bracket(text, at)
  depth = 0
  while at < text.size
    char = text[at]
    if char == '\\'
      at += 2
      next
    end
    if char == '`'
      finish = run_end(text, at)
      close = backtick_closer(text, finish, finish - at)
      at = close ? close + finish - at : finish
      next
    end
    depth += 1 if char == '['
    if char == ']'
      depth -= 1
      return at if depth.zero?
    end
    at += 1
  end
  nil
end

def emphasis(pieces, first = 0, finish = pieces.size)
  html = +''
  at = first
  while at < finish
    piece = pieces[at]
    if piece.is_a?(String)
      html << piece
    else
      close = piece.can_open && ((at + 1)...finish).find do |index|
        other = pieces[index]
        other.is_a?(Delimiter) && other.char == piece.char && other.length == piece.length && other.can_close
      end
      if close
        opening, closing = piece.char == '~' ? ['<del>', '</del>'] :
          { 1 => ['<em>', '</em>'], 2 => ['<strong>', '</strong>'], 3 => ['<em><strong>', '</strong></em>'] }.fetch(piece.length)
        html << opening << emphasis(pieces, at + 1, close) << closing
        at = close
      else
        html << piece.char * piece.length
      end
    end
    at += 1
  end
  html
end

class Renderer
  def initialize(references, footnotes)
    @references, @footnotes = references, footnotes
    @used_ids = {}
    @headings = []
    @note_numbers = {}
    @note_counts = Hash.new(0)
  end

  def inline(text, links: true, notes: true)
    pieces = []
    at = 0
    while at < text.size
      char = text[at]
      following = text[at + 1]
      if char == '\\'
        if following && PUNCTUATION.include?(following)
          pieces << escape_html(following)
          at += 2
        elsif following == "\n"
          pieces << "<br />\n"
          at += 2
        else
          pieces << '\\'
          at += 1
        end
        next
      end
      if char == '`'
        finish = run_end(text, at)
        close = backtick_closer(text, finish, finish - at)
        if close
          code = text[finish...close].tr("\n", ' ')
          code = code[1...-1] if code.start_with?(' ') && code.end_with?(' ') && !code.strip.empty?
          pieces << "<code>#{escape_html(code)}</code>"
          at = close + finish - at
        else
          pieces << text[at...finish]
          at = finish
        end
        next
      end
      if links && char == '<' && (close = text.index('>', at + 1))
        target = text[(at + 1)...close]
        href = nil
        if !target.match?(/[ \n<]/) && /\Ahttps?:\/\/.+/m.match?(target)
          href = target
        elsif /\A[A-Za-z0-9.+_-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+\z/.match?(target)
          href = "mailto:#{target}"
        end
        if href
          pieces << %(<a href="#{escape_html(href)}">#{escape_html(target)}</a>)
          at = close + 1
          next
        end
      end
      if links && (at.zero? || " \n*_~(".include?(text[at - 1])) && (match = /\Ahttps?:\/\/[^ \n<]*/.match(text[at..]))
        url = match[0].sub(/[.,:;!?*_~)]+\z/, '')
        unless %w[http:// https://].include?(url)
          pieces << %(<a href="#{escape_html(url)}">#{escape_html(url)}</a>)
          at += url.size
          next
        end
      end
      if char == '[' || (char == '!' && following == '[')
        if links && notes && text[at, 2] == '[^' && (close = text.index(']', at + 2))
          name = text[(at + 2)...close].downcase
          if @footnotes.key?(name)
            pieces << footnote_reference(name)
            at = close + 1
            next
          end
        end
        image = char == '!'
        opening = at + (image ? 1 : 0)
        if (image || links) && (close = closing_bracket(text, opening))
          label = text[(opening + 1)...close]
          if (dest = destination(text, close + 1, label))
            reference, finish = dest
            url, title = reference
            attribute = title.nil? ? '' : %( title="#{escape_html(title)}")
            content = inline(label, links: false, notes: false)
            pieces << if image
                        %(<img src="#{escape_html(url)}" alt="#{strip_tags(content)}"#{attribute} />)
                      else
                        %(<a href="#{escape_html(url)}"#{attribute}>#{content}</a>)
                      end
            at = finish
            next
          end
        end
      end
      if '*_~'.include?(char)
        finish = run_end(text, at)
        length = finish - at
        before = at.zero? ? ' ' : text[at - 1]
        after = text[finish] || ' '
        can_open, can_close = !WHITESPACE.include?(after), !WHITESPACE.include?(before)
        can_open = can_close = false if char == '_' && /[A-Za-z0-9]/.match?(before) && /[A-Za-z0-9]/.match?(after)
        pieces << if (char != '~' && length <= 3) || (char == '~' && length == 2)
                    Delimiter.new(char, length, can_open, can_close)
                  else char * length
                  end
        at = finish
      else
        pieces << escape_html(char)
        at += 1
      end
    end
    emphasis(pieces)
  end

  def destination(text, at, label)
    if text[at] == '['
      close = text.index(']', at + 1)
      if close && !text[(at + 1)...close].include?('[')
        name = text[(at + 1)...close]
        reference = @references[normalize(name.empty? ? label : name)]
        return reference ? [reference, close + 1] : nil
      end
    elsif text[at] == '('
      url, finish = escaped_read(text, skip_space(text, at + 1), " \n)")
      position = skip_space(text, finish)
      title = nil
      valid = true
      if position > finish && position < text.size && "\"'".include?(text[position])
        title, finish = escaped_read(text, position + 1, text[position])
        valid = finish < text.size
        position = skip_space(text, finish + 1) if valid
      end
      return [[url, title], position + 1] if valid && text[position] == ')'
    end
    reference = @references[normalize(label)]
    reference && [reference, at]
  end

  def document(blocks)
    html = render_blocks(blocks)
    contents = table_of_contents
    html = html.gsub(TOC_MARKER) { contents }
    html << footnote_list unless @note_numbers.empty?
    html
  end

  def render_blocks(blocks) = blocks.map { |block| render(block) + "\n" }.join

  def render(block)
    case block.kind
    when :heading then heading(block.number, block.text)
    when :paragraph then "<p>#{inline(block.text)}</p>"
    when :rule then '<hr />'
    when :code
      attribute = block.text.empty? ? '' : %( class="language-#{escape_html(block.text)}")
      "<pre><code#{attribute}>#{block.lines.map { |line| escape_html(line) + "\n" }.join}</code></pre>"
    when :quote then "<blockquote>\n#{render_blocks(block.children)}</blockquote>"
    when :alert
      %(<div class="alert alert-#{block.text.downcase}">\n<p class="alert-title">#{block.text.capitalize}</p>\n#{render_blocks(block.children)}</div>)
    when :list
      tag = block.ordered ? 'ol' : 'ul'
      attribute = block.ordered && block.number != 1 ? %( start="#{block.number}") : ''
      "<#{tag}#{attribute}>\n#{block.items.map { |item| render_item(item) + "\n" }.join}</#{tag}>"
    when :table
      html = "<table>\n<thead>\n<tr>\n#{table_cells('th', block, block.lines)}</tr>\n</thead>\n"
      unless block.rows.empty?
        html << "<tbody>\n"
        block.rows.each { |row| html << "<tr>\n#{table_cells('td', block, row)}</tr>\n" }
        html << "</tbody>\n"
      end
      html << '</table>'
    when :toc then TOC_MARKER
    end
  end

  def heading(level, text)
    start = text.rindex(' {#')
    candidate = start && text.end_with?('}') ? text[(start + 3)...-1] : nil
    if candidate && /\A[A-Za-z0-9_-]+\z/.match?(candidate)
      id = candidate
      text = text[...start].sub(/ +\z/, '')
    else
      base = text.downcase.gsub(/[^a-z0-9_ \n-]/, '').tr(" \n", '--')
      base = 'heading' if base.empty?
      id = base
      suffix = 1
      while @used_ids.key?(id)
        id = "#{base}-#{suffix}"
        suffix += 1
      end
    end
    @used_ids[id] = true
    html = inline(text)
    @headings << TocEntry.new(level, id, strip_tags(html), [])
    %(<h#{level} id="#{id}">#{html}</h#{level}>)
  end

  def render_item(blocks)
    html = +'<li>'
    blocks.each_with_index do |block, index|
      if block.kind == :paragraph
        text = block.text
        if index.zero? && text.size > 4 && ['[ ] ', '[x] ', '[X] '].include?(text[0, 4])
          checked = text[1] == ' ' ? '' : ' checked=""'
          html << %(<input type="checkbox"#{checked} disabled="" /> )
          text = text[4..]
        end
        html << inline(text)
      else
        html << "\n" unless html.end_with?("\n")
        html << render(block) << "\n"
      end
    end
    html << '</li>'
  end

  def table_cells(tag, table, cells)
    cells.zip(table.alignments).map do |cell, alignment|
      style = alignment ? %( style="text-align:#{alignment}") : ''
      "<#{tag}#{style}>#{inline(cell)}</#{tag}>\n"
    end.join
  end

  def toc_list(entries)
    html = +"<ul>\n"
    entries.each do |entry|
      html << %(<li><a href="##{entry.id}">#{entry.label}</a>)
      html << "\n#{toc_list(entry.children)}\n" unless entry.children.empty?
      html << "</li>\n"
    end
    html << '</ul>'
  end

  def table_of_contents
    return "<nav class=\"toc\">\n</nav>" if @headings.empty?

    roots = []
    parents = []
    @headings.each do |entry|
      parents.pop while !parents.empty? && parents.last.level >= entry.level
      (parents.empty? ? roots : parents.last.children) << entry
      parents << entry
    end
    %(<nav class="toc">\n#{toc_list(roots)}\n</nav>)
  end

  def reference_id(number, count) = "fnref-#{number}#{count == 1 ? '' : "-#{count}"}"

  def footnote_reference(name)
    @note_numbers[name] ||= @note_numbers.size + 1
    number = @note_numbers.fetch(name)
    @note_counts[name] += 1
    %(<sup id="#{reference_id(number, @note_counts[name])}"><a href="#fn-#{number}">#{number}</a></sup>)
  end

  def footnote_list
    html = +"<section class=\"footnotes\">\n<ol>\n"
    @note_numbers.each do |name, number|
      body = inline(@footnotes.fetch(name), notes: false)
      backlinks = (1..@note_counts[name]).map { |count| %(<a href="##{reference_id(number, count)}">&#8617;</a>) }.join(' ')
      html << %(<li id="fn-#{number}">#{body} #{backlinks}</li>\n)
    end
    html << "</ol>\n</section>\n"
  end
end

lines = []
STDIN.each_line do |line|
  line = line.chomp
  break if line == '@@END@@'

  lines << line
end
parser = BlockParser.new
blocks = parser.parse(lines)
print Renderer.new(parser.references, parser.footnotes).document(blocks)
