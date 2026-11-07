# frozen_string_literal: true

require 'fileutils'
require_relative 'headers'
require_relative 'addresses'
require_relative 'mime'
require_relative 'dates'
require_relative 'threader'

module MailboxProgram
  DUPLICATE_NAMES = %w[From To Cc Subject Date Message-ID In-Reply-To References
                       MIME-Version Content-Type Content-Transfer-Encoding Content-Disposition].freeze
  HTML_PARAGRAPHS = %w[p div ul ol table tr blockquote h1 h2 h3 h4 h5 h6].freeze
  HTML_REFERENCES = { 'amp' => '&', 'lt' => '<', 'gt' => '>', 'quot' => '"',
                      'apos' => "'", 'nbsp' => ' ' }.freeze

  def self.read_mailbox
    messages = []
    lines = File.binread('input/mailbox.mbox').split("\n", -1)
    lines.pop
    lines.each_with_index do |line, index|
      if line.start_with?('From ')
        messages << []
      else
        line = line[1..] if line.match?(/\A>+From /)
        messages.last << [index + 1, line]
      end
    end
    messages.each do |message|
      message.pop if !message.empty? && message.last[1].empty?
    end
    messages
  end

  def self.sections(lines)
    separator = lines.index { |_, text| text.empty? }
    separator ? [lines[0...separator], lines[separator + 1..]] : [lines, []]
  end

  def self.first_fields(fields)
    result = {}
    fields.each { |name, value| result[name] = value unless result.key?(name) }
    result
  end

  def self.well_formed_id?(text)
    return false unless text.length >= 3 && text.start_with?('<') && text.end_with?('>')

    inside = text[1...-1]
    inside.count('@') == 1 && !inside.start_with?('@') && !inside.end_with?('@') &&
      inside.each_byte.all? { |byte| byte.between?(33, 126) && ![60, 62, 40, 41, 34, 92].include?(byte) }
  end

  def self.extract_ids(text)
    result = []
    index = 0
    while (first = text.index('<', index))
      last = text.index('>', first + 1)
      break unless last

      candidate = text[first..last]
      result << candidate if well_formed_id?(candidate)
      index = last + 1
    end
    result
  end

  def self.parse_message(lines, number, accepted)
    header_lines, body = sections(lines)
    fields, invalid = Headers.fields(header_lines)
    values = first_fields(fields)
    problems = invalid.map { |line| "bad header line #{line}" }
    counts = fields.map(&:first).tally
    DUPLICATE_NAMES.each do |name|
      problems << "duplicate #{name}" if counts.fetch(name.downcase, 0) >= 2
    end
    message = { number: number, id: '', sender: nil, to: [], cc: [], date: nil, problems: problems }
    if !values.key?('from')
      problems << 'missing From'
    else
      parsed = Addresses.parse(values['from'])
      if !parsed || parsed[0].length != 1 || parsed[0][0][:kind] == :group
        problems << 'bad From'
      else
        message[:sender] = parsed[0][0]
        problems << 'bad encoded word in From' if parsed[1]
      end
    end
    %w[To Cc].each do |name|
      field = name.downcase
      next unless values.key?(field)

      parsed = Addresses.parse(values[field])
      if parsed
        recipients = []
        parsed[0].each do |address|
          if address[:kind] == :mailbox
            recipients << address[:address]
          else
            address[:members].each { |member| recipients << member[:address] }
          end
        end
        message[field.to_sym] = recipients
        problems << "bad encoded word in #{name}" if parsed[1]
      else
        problems << "bad #{name}"
      end
    end
    subject, encoded_error = Headers.unstructured(values.fetch('subject', ''))
    message[:subject] = subject
    problems << 'bad encoded word in Subject' if encoded_error
    base = subject
    reply = false
    while base[0, 3].downcase == 're:'
      base = base[3..].sub(/\A +/, '')
      reply = true
    end
    message[:base_subject] = base
    message[:reply] = reply
    if values.key?('date')
      message[:date], problem = Dates.parse(values['date'])
      problems << problem if problem
    else
      problems << 'missing Date'
    end
    id = values['message-id']
    if id.nil?
      problems << 'missing Message-ID'
    elsif !well_formed_id?(id)
      problems << 'bad Message-ID'
    elsif accepted.key?(id)
      problems << "Message-ID already used by message #{accepted[id][:number]}"
    else
      message[:id] = id
      accepted[id] = message
    end
    references = extract_ids(values.fetch('references', ''))
    in_reply_to = extract_ids(values.fetch('in-reply-to', '')).first
    references << in_reply_to if in_reply_to && references.last != in_reply_to
    message[:refs] = references
    enabled = false
    if values.key?('mime-version')
      version = Headers.remove_comments(values['mime-version'])
      if version && version.delete(" \t") == '1.0'
        enabled = true
      else
        problems << 'bad MIME-Version'
      end
    end
    message[:entity] = parse_entity('1', values, body, enabled, problems)
    message[:key] = [message[:date] ? 0 : 1, message[:date] || 0, message[:id], number]
    message
  end

  def self.parse_entity(part, values, body, enabled, problems)
    type = 'text'
    subtype = 'plain'
    parameters = {}
    if enabled && values.key?('content-type')
      parsed = Headers.parameters(values['content-type'], subtype: true)
      if parsed
        type, subtype, parameters = parsed
      else
        problems << "bad Content-Type in part #{part}"
      end
    end
    disposition = nil
    filename = nil
    if enabled && values.key?('content-disposition')
      parsed = Headers.parameters(values['content-disposition'], subtype: false)
      if parsed
        disposition = parsed[0]
        filename = parsed[2]['filename']
      else
        problems << "bad Content-Disposition in part #{part}"
      end
    end
    filename = parameters['name'] if filename.nil? || filename.empty?
    if type == 'text' && parameters.key?('charset') && parameters['charset'].downcase != 'us-ascii'
      problems << "unsupported charset \"#{parameters['charset'].downcase}\" in part #{part}"
    end
    entity = { part: part, type: type, subtype: subtype, parameters: parameters,
               disposition: disposition, filename: filename, children: nil, content: '' }
    if enabled && type == 'multipart'
      boundary = parameters['boundary']
      if boundary.nil? || boundary.empty?
        problems << "missing boundary in part #{part}"
      else
        parts = []
        closed = false
        body.each do |line|
          text = line[1].sub(/[ \t]+\z/, '')
          if text == "--#{boundary}--"
            closed = true
            break
          elsif text == "--#{boundary}"
            parts << []
          elsif !parts.empty?
            parts.last << line
          end
        end
        if parts.empty?
          problems << "no parts in part #{part}"
        elsif !closed
          problems << "unterminated multipart in part #{part}"
        end
        entity[:children] = []
        parts.each_with_index do |lines, index|
          header_lines, child_body = sections(lines)
          fields, invalid = Headers.fields(header_lines)
          invalid.each { |line| problems << "bad header line #{line}" }
          child = parse_entity("#{part}.#{index + 1}", first_fields(fields), child_body, true, problems)
          entity[:children] << child
        end
        return entity
      end
    end
    original = body.map { |_, text| text }.join("\n")
    encoding = enabled ? values.fetch('content-transfer-encoding', '7bit').downcase : '7bit'
    content = original
    case encoding
    when 'base64'
      content = Mime.base64_body(original)
      unless content
        problems << "bad base64 in part #{part}"
        content = ''
      end
    when 'quoted-printable'
      content, error = Mime.quoted_printable(original)
      problems << "bad quoted-printable in part #{part}" if error
    when '7bit', '8bit', 'binary'
      content = original
    else
      problems << "unknown encoding \"#{encoding}\" in part #{part}"
    end
    entity[:content] = content
    entity
  end

  def self.text_parts(entity, allow_html)
    children = entity[:children]
    unless children
      return [] if entity[:disposition] == 'attachment' || entity[:type] != 'text'
      return [entity] if entity[:subtype] == 'plain' || (allow_html && entity[:subtype] == 'html')

      return []
    end
    if entity[:subtype] == 'alternative'
      [false, true].each do |html|
        children.each do |child|
          result = text_parts(child, html)
          return result unless result.empty?
        end
      end
      []
    else
      children.flat_map { |child| text_parts(child, allow_html) }
    end
  end

  def self.wrap(text, prefix)
    lines = []
    current = +''
    text.scan(/[^ \t]+/).each do |word|
      if !current.empty? && current.length + 1 + word.length > 72
        lines << prefix + current
        current = word.dup
      else
        current << ' ' unless current.empty?
        current << word
      end
    end
    lines << prefix + current
    lines
  end

  def self.flowed(content, parameters)
    return [] if content.empty?

    logical = []
    delete_space = parameters.fetch('delsp', '').downcase == 'yes'
    content.split("\n", -1).each do |line|
      depth = 0
      depth += 1 while line.getbyte(depth) == 62
      text = line[depth..]
      text = text[1..] if text.start_with?(' ')
      flows = text.end_with?(' ') && text != '-- '
      if !logical.empty? && logical.last[2] && logical.last[0] == depth
        logical.last[1] = logical.last[1][0...-1] if delete_space
        logical.last[1] << text
        logical.last[2] = flows
      else
        logical << [depth, text, flows]
      end
    end
    logical.flat_map do |depth, text, _|
      prefix = depth.positive? ? '>' * depth + ' ' : ''
      wrap(text, prefix)
    end
  end

  def self.character_references(text)
    result = +''
    index = 0
    while index < text.length
      if text.getbyte(index) == 38 && (last = text.index(';', index + 1))
        name = text[index + 1...last]
        replacement = HTML_REFERENCES[name]
        if replacement.nil? && name.match?(/\A#[0-9]{1,3}\z/)
          value = name[1..].to_i
          replacement = value.chr if value.between?(32, 126)
        end
        if replacement
          result << replacement
          index = last + 1
          next
        end
      end
      result << text[index]
      index += 1
    end
    result
  end

  def self.html_lines(content)
    rows = []
    current = +''
    depth = 0
    hide = nil
    index = 0
    while index < content.length
      if content.getbyte(index) == 60 && (last = content.index('>', index + 1))
        inside = content[index + 1...last]
        ending = inside.start_with?('/')
        inside = inside[1..] if ending
        name = inside[/\A[A-Za-z0-9]*/].downcase
        index = last + 1
        if hide
          hide = nil if ending && name == hide
        elsif !ending && %w[head style script].include?(name)
          hide = name
        elsif name == 'br' || (name == 'li' && !ending)
          rows << [depth, current]
          current = name == 'li' ? +'* ' : +''
        elsif HTML_PARAGRAPHS.include?(name)
          rows << [depth, current]
          rows << [depth, '']
          current = +''
          if name == 'blockquote'
            depth = ending ? [0, depth - 1].max : depth + 1
          end
        end
      else
        current << content[index] unless hide
        index += 1
      end
    end
    rows << [depth, current]
    display = []
    rows.each do |quote_depth, text|
      collapsed = Headers.trim(text.gsub(/[ \t\n]+/, ' '))
      restored = character_references(collapsed).gsub(/\A +| +\z/, '')
      if restored.empty?
        display << '' if !display.empty? && !display.last.empty?
      else
        prefix = quote_depth.positive? ? '>' * quote_depth + ' ' : ''
        display.concat(wrap(restored, prefix))
      end
    end
    display.pop while !display.empty? && display.last.empty?
    display
  end

  def self.display_part(entity)
    content = entity[:content]
    if entity[:subtype] == 'html'
      format = 'html'
      lines = html_lines(content)
    elsif entity[:parameters].fetch('format', '').downcase == 'flowed'
      format = 'flowed'
      lines = flowed(content, entity[:parameters])
    else
      format = 'plain'
      lines = content.empty? ? [] : content.split("\n", -1)
    end
    lines.map! { |line| line.sub(/[ \t]+\z/, '') }
    quoted = lines.count { |line| line.start_with?('>') }
    signature_at = lines.rindex('--')
    signature = signature_at ? lines.length - signature_at - 1 : 0
    [format, lines, quoted, signature]
  end

  def self.assign_positions(roots, messages)
    roots.each_with_index do |root, index|
      stack = [[root, 0]]
      until stack.empty?
        node, depth = stack.pop
        if node.message
          node.message[:thread] = index + 1
          node.message[:depth] = depth
          node.message[:parent] = node.parent&.message
        end
        node.children.reverse_each { |child| stack << [child, depth + 1] }
      end
    end
    messages.each do |message|
      parent = message[:parent]
      if parent && message[:date] && parent[:date] && message[:date] < parent[:date]
        message[:problems] << "dated before parent message #{parent[:number]}"
      end
    end
  end

  def self.subject_notation(subject)
    subject.empty? ? '(no subject)' : subject
  end

  def self.date_notation(message)
    message[:date] ? Dates.notation(message[:date]) : 'invalid'
  end

  def self.thread_block(root, number)
    tree_lines = []
    dates = []
    senders = {}
    messages = 0
    maximum_depth = 0
    stack = [[root, 0, '', '']]
    until stack.empty?
      node, depth, prefix, stem = stack.pop
      maximum_depth = depth if depth > maximum_depth
      if node.message
        message = node.message
        messages += 1
        dates << message[:date] if message[:date]
        sender = message[:sender] ? message[:sender][:address] : '-'
        senders[sender] = true if message[:sender]
        notation = "[#{message[:number]}] #{date_notation(message)} #{sender} #{subject_notation(message[:subject])}"
      elsif node.subject
        notation = "[subject] #{node.subject}"
      else
        notation = "[missing] #{node.id}"
      end
      tree_lines << prefix + notation
      (node.children.length - 1).downto(0) do |index|
        last = index == node.children.length - 1
        child_prefix = stem + (last ? '`- ' : '+- ')
        child_stem = stem + (last ? '   ' : '|  ')
        stack << [node.children[index], depth + 1, child_prefix, child_stem]
      end
    end
    span = dates.empty? ? 'span -' : "span #{Dates.notation(dates.min)} .. #{Dates.notation(dates.max)}"
    ["thread #{number} messages #{messages} depth #{maximum_depth} senders #{senders.length}",
     span, "subject #{subject_notation(Threader.subject(root))}"] + tree_lines
  end

  def self.message_block(message)
    sender = message[:sender]
    from = if sender.nil?
             '-'
           elsif sender[:name]
             "#{sender[:name]} <#{sender[:address]}>"
           else
             sender[:address]
           end
    parent = message[:parent] ? message[:parent][:number] : '-'
    lines = ["message #{message[:number]}", "id #{message[:id].empty? ? '-' : message[:id]}",
             "date #{date_notation(message)}", "from #{from}",
             "to #{message[:to].empty? ? '-' : message[:to].join(', ')}",
             "cc #{message[:cc].empty? ? '-' : message[:cc].join(', ')}",
             "subject #{subject_notation(message[:subject])}",
             "refs #{message[:refs].empty? ? '-' : message[:refs].join(' ')}",
             "thread #{message[:thread]} depth #{message[:depth]} parent #{parent}"]
    stack = [message[:entity]]
    until stack.empty?
      entity = stack.pop
      line = "part #{entity[:part]} #{entity[:type]}/#{entity[:subtype]}"
      if entity[:children]
        entity[:children].reverse_each { |child| stack << child }
      else
        line << " #{entity[:content].length}"
        line << " #{entity[:disposition]}" if entity[:disposition]
        line << " \"#{entity[:filename]}\"" if entity[:filename] && !entity[:filename].empty?
      end
      lines << line
    end
    lines
  end

  def self.body_block(request, accepted)
    lines = ["request #{request}"]
    message = accepted[request]
    return lines + ['not found'] unless message

    parts = text_parts(message[:entity], true)
    lines << "message #{message[:number]} text parts #{parts.length}"
    parts.each do |entity|
      format, display, quoted, signature = display_part(entity)
      lines << "part #{entity[:part]} #{format} lines #{display.length} quoted #{quoted} signature #{signature}"
      display.each { |line| lines << (line.empty? ? '|' : '| ' + line) }
    end
    lines
  end

  def self.sender_lines(messages)
    groups = {}
    messages.each do |message|
      sender = message[:sender]
      next unless sender

      group = (groups[sender[:address]] ||= { name: '', messages: 0, threads: {}, first: nil, last: nil })
      group[:messages] += 1
      group[:threads][message[:thread]] = true
      group[:name] = sender[:name] if sender[:name]
      if message[:date]
        group[:first] = message[:date] if group[:first].nil? || message[:date] < group[:first]
        group[:last] = message[:date] if group[:last].nil? || message[:date] > group[:last]
      end
    end
    lines = ['address,name,messages,threads,first,last']
    groups.sort_by { |address, group| [-group[:messages], address] }.each do |address, group|
      name = group[:name]
      name = '"' + name.gsub('"', '""') + '"' if name.include?(',') || name.include?('"')
      first = group[:first] ? Dates.notation(group[:first]) : '-'
      last = group[:last] ? Dates.notation(group[:last]) : '-'
      lines << "#{address},#{name},#{group[:messages]},#{group[:threads].length},#{first},#{last}"
    end
    lines
  end

  def self.malformed_lines(messages)
    malformed = messages.count { |message| !message[:problems].empty? }
    total = messages.sum { |message| message[:problems].length }
    lines = ["messages #{messages.length} malformed #{malformed} problems #{total}"]
    messages.each do |message|
      message[:problems].each { |problem| lines << "message #{message[:number]}: #{problem}" }
    end
    lines
  end

  def self.write_blocks(name, blocks)
    text = blocks.map { |lines| lines.map { |line| line.sub(/[ \t]+\z/, '') }.join("\n") }.join("\n\n")
    File.binwrite("output/#{name}", text + "\n")
  end

  def self.run
    accepted = {}
    messages = read_mailbox.each_with_index.map { |lines, index| parse_message(lines, index + 1, accepted) }
    roots = Threader.build(messages)
    assign_positions(roots, messages)
    requests = File.binread('input/requests.txt').split("\n", -1)
    requests.pop
    FileUtils.mkdir_p('output')
    write_blocks('threads.txt', roots.each_with_index.map { |root, index| thread_block(root, index + 1) })
    write_blocks('messages.txt', messages.map { |message| message_block(message) })
    write_blocks('bodies.txt', requests.map { |request| body_block(request, accepted) })
    write_blocks('senders.csv', [sender_lines(messages)])
    write_blocks('malformed.txt', [malformed_lines(messages)])
  end
end

MailboxProgram.run if $PROGRAM_NAME == __FILE__
