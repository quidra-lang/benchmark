module DocumentParser
  BODY_KINDS = %w[paragraph item enum quote term].freeze
  SETTINGS = %w[width indent align].freeze
  PREAMBLE = %w[page header footer].freeze
  BLOCKS = %w[title author h1 h2 item enum quote term table verbatim toc lot index bibliography].freeze
  DIRECTIVES = (SETTINGS + PREAMBLE + BLOCKS + %w[newpage hyphenation bib]).freeze
  EMPTY_ARGUMENTS = %w[newpage verbatim toc lot index bibliography].freeze

  def self.valid_argument?(name, argument)
    case name
    when 'width', 'indent', 'page'
      return false unless argument.match?(/\A[0-9]{1,9}\z/)

      range = { 'width' => 20..80, 'indent' => 0..8, 'page' => 10..100 }.fetch(name)
      range.cover?(argument.to_i)
    when 'align'
      %w[left right center justify].include?(argument)
    when 'header', 'footer'
      argument.count('|') == 2
    when *EMPTY_ARGUMENTS
      argument.empty?
    when 'hyphenation'
      argument.match?(/\A[a-z]+(?:-[a-z]+)*(?: [a-z]+(?:-[a-z]+)*)*\z/)
    when 'bib'
      key, separator, fields = argument.partition(' ')
      parts = fields.split('|', -1)
      !separator.empty? && key.match?(/\A[a-z0-9]+\z/) && parts.length == 3 &&
        !parts[0].empty? && parts[1].match?(/\A[0-9]{4}\z/) && !parts[2].empty?
    when 'term'
      term, separator, description = argument.partition('|')
      !separator.empty? && !term.empty? && !description.empty?
    when 'table'
      argument.partition(' ').first.match?(/\A[lrc]+\z/)
    else
      !argument.empty?
    end
  end

  def self.parse(lines)
    document = { blocks: [], warnings: [], height: 40, page_width: 60,
                 header: ['', '', ''], footer: ['', '', ''],
                 hyphenation_words: [], bibliography: [] }
    settings = { width: 60, indent: 0, align: 'left' }
    accepted = []
    open_body = inner_block = nil
    pending_break = false
    create_block = lambda do |kind, line_number, argument = ''|
      document[:page_width] = settings[:width] if document[:blocks].empty?
      block = settings.merge(kind: kind, line_number: line_number, argument: argument,
                             page_break: pending_break)
      pending_break = false
      block[:body_lines] = [] if BODY_KINDS.include?(kind)
      block[:inner_lines] = [] if %w[table verbatim].include?(kind)
      document[:blocks] << block
      block
    end

    lines.each_with_index do |line, i|
      line_number = i + 1
      if inner_block
        if line == '.end'
          inner_block = nil
        else
          inner_block[:inner_lines] << [line_number, line]
        end
        next
      end
      if line.empty?
        open_body = nil
        next
      end
      unless line.start_with?('.')
        open_body ||= create_block.call('paragraph', line_number)
        open_body[:body_lines] << [line_number, line]
        next
      end

      open_body = nil
      name, _separator, argument = line[1..].partition(' ')
      warning = if !DIRECTIVES.include?(name)
                  "unknown directive .#{name}"
                elsif !valid_argument?(name, argument)
                  "bad argument for .#{name}"
                elsif PREAMBLE.include?(name) && !document[:blocks].empty?
                  ".#{name} ignored after the preamble"
                elsif PREAMBLE.include?(name) && accepted.include?(name)
                  "duplicate .#{name}"
                end
      if warning
        document[:warnings] << [line_number, warning]
        next
      end

      if SETTINGS.include?(name)
        settings[name.to_sym] = name == 'align' ? argument : argument.to_i
      elsif PREAMBLE.include?(name)
        accepted << name
        if name == 'page'
          document[:height] = argument.to_i
        else
          document[name.to_sym] = argument.split('|', -1)
        end
      elsif name == 'newpage'
        pending_break = true
      elsif name == 'hyphenation'
        document[:hyphenation_words].concat(argument.split(' '))
      elsif name == 'bib'
        key, _space, fields = argument.partition(' ')
        author, year, title = fields.split('|', -1)
        document[:bibliography] << { line_number: line_number, key: key, author: author, year: year, title: title }
      else
        block = create_block.call(name, line_number, argument)
        case name
        when 'item', 'enum', 'quote'
          block[:body_lines] << [line_number, argument]
          open_body = block
        when 'term'
          term, _pipe, description = argument.partition('|')
          block[:term] = term
          block[:body_lines] << [line_number, description]
          open_body = block
        when 'table'
          block[:columns], _space, block[:caption] = argument.partition(' ')
          inner_block = block
        when 'verbatim'
          inner_block = block
        end
      end
    end
    if inner_block
      document[:warnings] << [inner_block[:line_number], "unterminated #{inner_block[:kind]}"]
    end
    document
  end
end
