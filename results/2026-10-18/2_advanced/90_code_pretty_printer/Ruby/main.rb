require_relative 'lexer'
require_relative 'parser'
require_relative 'doc_builder'
require_relative 'printer'
require_relative 'report'

class Formatter
  include Docs
  attr_reader :item_docs

  def initialize(profile, tokens)
    @profile, @tokens = profile, tokens
    @indent = profile[:indent]
    @space = profile[:space_around_operators] ? ' ' : ''
    @keyword_space = profile[:space_after_keyword] ? ' ' : ''
    @operator_break = profile[:space_around_operators] ? LINE : SOFTLINE
    @kr = profile[:brace_style] == 'kr'
    @item_docs = []
  end
  def sep(count) = cat(Array.new(1 + [count, @profile[:max_blank_lines]].min, HARDLINE))
  def pre_blank(token) = (token[:leading].first || token)[:blank]
  def comments(sequence, following)
    parts = []
    sequence.each_with_index do |comment, index|
      parts << comment[:text]
      next_entry = sequence[index + 1] || following
      parts << (comment[:own] ? sep(next_entry[:blank]) : ' ') if next_entry
    end
    cat(parts)
  end
  def t(token, leading = token[:leading])
    cat(comments(leading, token), token[:text], trailing(token))
  end
  def trailing(token)
    suffix(token[:trailing].map { |comment| comment[:text] }.join(' ')) unless token[:trailing].empty?
  end
  def split_comments(token)
    last = token[:leading].rindex { |comment| comment[:own] }
    last ? [token[:leading][0..last], token[:leading][last + 1..]] : [[], token[:leading]]
  end
  def closing_comments(own, nonempty)
    return '' if own.empty?
    cat(nonempty ? sep(own.first[:blank]) : nil, comments(own, nil))
  end
  def whole_file(items, ending)
    parts = []
    items.each_with_index do |item, index|
      parts << sep(pre_blank(item[:first])) if index > 0
      document = item(item)
      @item_docs << document
      parts << document
    end
    parts << closing_comments(ending[:leading], !items.empty?)
    cat(parts)
  end
  def item(entry)
    return variable(entry) unless entry[:tag] == :function
    cat(t(entry[:typ]), ' ', t(entry[:name]), list_doc(entry[:parameters]), HARDLINE, block(entry[:body]))
  end
  def parameter(entry)
    cat(t(entry[:typ]), ' ', t(entry[:name]), entry[:brackets].map { |left, right| cat(t(left), t(right)) })
  end
  def variable(entry)
    parts = [t(entry[:typ]), ' ', t(entry[:name])]
    entry[:dimensions].each do |left, value, right|
      parts.concat([t(left), value ? expr(value, 0) : nil, t(right)])
    end
    if entry[:equals]
      parts.concat([@space, t(entry[:equals]), @space, initializer(entry[:initializer])])
    end
    parts << t(entry[:semi]) if entry[:semi]
    cat(parts)
  end
  def initializer(entry) = entry[:tag] == :list ? list_doc(entry) : expr(entry, 0)
  def list_doc(entry)
    left, right = entry.values_at(:left, :right)
    return cat(t(left), t(right)) if entry[:elements].empty?
    # Snapshot flags describe attachment before any parentheses are removed.
    force = @tokens[left[:index]...right[:index]].any? { |token| token[:source_trailing] }
    elements = entry[:elements].map do |element|
      if element[:tag] == :parameter
        parameter(element)
      elsif entry[:role] == '{'
        initializer(element)
      else
        expr(element, 0)
      end
    end
    contents = [SOFTLINE, elements.first]
    entry[:commas].zip(elements.drop(1)).each { |comma, element| contents.concat([t(comma), LINE, element]) }
    if entry[:role] == '{'
      contents << if_break(',', '')
      contents << trailing(entry[:trailing]) if entry[:trailing]
    end
    group(cat(force ? BREAK_PARENT : nil, t(left), nest(@indent, cat(contents)), SOFTLINE, t(right)))
  end
  def statement_sequence(statements)
    parts = []
    statements.each_with_index do |stmt, index|
      parts << (index.zero? ? HARDLINE : sep(pre_blank(stmt[:first])))
      parts << statement(stmt)
    end
    cat(parts)
  end
  def block(entry)
    own, inline = split_comments(entry[:right])
    stmts = entry[:statements]
    return cat(t(entry[:left]), t(entry[:right], inline)) if stmts.empty? && own.empty?
    inner = cat(stmts.empty? ? HARDLINE : statement_sequence(stmts), closing_comments(own, !stmts.empty?))
    cat(t(entry[:left]), nest(@indent, inner), HARDLINE, t(entry[:right], inline))
  end
  def body(entry)
    separator = @kr ? ' ' : HARDLINE
    return cat(separator, block(entry)) if entry[:tag] == :block
    if @profile[:add_braces]
      cat(separator, '{', nest(@indent, cat(HARDLINE, statement(entry))), HARDLINE, '}')
    else
      nest(@indent, cat(HARDLINE, statement(entry)))
    end
  end
  def simple(entry)
    return expr(entry[:expr], 0) unless entry[:tag] == :assign
    cat(expr(entry[:left], 0), @space, t(entry[:op]), @space, expr(entry[:right], 0))
  end
  def control_header(entry)
    cat(t(entry[:keyword]), @keyword_space, t(entry[:left]), expr(entry[:test], 0), t(entry[:right]))
  end
  def if_statement(entry)
    parts = [control_header(entry), body(entry[:body])]
    if entry[:else_token]
      join = @kr && (entry[:body][:tag] == :block || @profile[:add_braces]) ? ' ' : HARDLINE
      alternative = entry[:alternative]
      parts.concat([join, t(entry[:else_token]), alternative[:tag] == :if ? cat(' ', if_statement(alternative)) : body(alternative)])
    end
    cat(parts)
  end
  def for_statement(entry)
    contents = []
    initial = entry[:initial]
    contents << (initial[:tag] == :variable ? variable(initial) : simple(initial)) if initial
    contents << t(entry[:first_semi])
    contents.concat([LINE, expr(entry[:condition], 0)]) if entry[:condition]
    contents << t(entry[:second_semi])
    contents.concat([LINE, simple(entry[:update])]) if entry[:update]
    cat(t(entry[:keyword]), @keyword_space, t(entry[:left]), group(align(cat(contents))), t(entry[:right]), body(entry[:body]))
  end
  def clause(entry)
    cat(t(entry[:label]), entry[:value] ? cat(' ', expr(entry[:value], 0)) : nil,
        t(entry[:colon]), entry[:statements].empty? ? nil : nest(@indent, statement_sequence(entry[:statements])))
  end
  def switch_statement(entry)
    own, inline = split_comments(entry[:closing])
    header = cat(control_header(entry), @kr ? ' ' : HARDLINE, t(entry[:opening]))
    clauses = entry[:clauses]
    return cat(header, t(entry[:closing], inline)) if clauses.empty? && own.empty?
    contents = []
    clauses.each_with_index do |part, index|
      contents << (index.zero? ? HARDLINE : sep(pre_blank(part[:first])))
      contents << clause(part)
    end
    contents << HARDLINE if clauses.empty?
    contents << closing_comments(own, !clauses.empty?)
    cat(header, nest(@profile[:indent_case_labels] ? @indent : 0, cat(contents)), HARDLINE, t(entry[:closing], inline))
  end
  def statement(entry)
    case entry[:tag]
    when :block then block(entry)
    when :variable then variable(entry)
    when :simple_stmt then cat(simple(entry[:value]), t(entry[:semi]))
    when :return then cat(t(entry[:keyword]), entry[:expr] ? cat(' ', expr(entry[:expr], 0)) : nil, t(entry[:semi]))
    when :flow then cat(t(entry[:keyword]), t(entry[:semi]))
    when :if then if_statement(entry)
    when :while then cat(control_header(entry), body(entry[:body]))
    when :for then for_statement(entry)
    when :switch then switch_statement(entry)
    end
  end
  def level(entry) = entry.fetch(:level, 8)
  def last_token(entry)
    case entry[:tag]
    when :primary then entry[:value]
    when :paren, :index then entry[:right]
    when :unary then last_token(entry[:operand])
    when :binary then last_token(entry[:right])
    when :conditional then last_token(entry[:no])
    when :call then entry[:arguments][:right]
    when :member then entry[:member]
    end
  end
  def opened(entry, minimum)
    while @profile[:remove_parens] && entry[:tag] == :paren
      inner, left, right = entry.values_at(:inner, :left, :right)
      break if level(inner) < minimum || !left[:leading].empty? || !right[:leading].empty?
      inner[:first][:trailing].unshift(*left[:trailing])
      last_token(inner)[:trailing].concat(right[:trailing])
      left[:trailing] = []
      right[:trailing] = []
      entry = inner
    end
    entry
  end
  def binary(entry)
    precedence, chain, current = level(entry), [], entry
    while current[:tag] == :binary && level(current) == precedence
      chain << [current[:op], current[:right]]
      current = opened(current[:left], precedence)
    end
    contents = chain.reverse.map do |op, operand|
      cat(@operator_break, t(op), @space, expr(operand, precedence + 1))
    end
    group(cat(expr(current, precedence), nest(@indent, cat(contents))))
  end
  def conditional(entry)
    contents, current = [], entry
    loop do
      contents.concat([@operator_break, t(current[:question]), @space, expr(current[:yes], 0),
                       @operator_break, t(current[:colon]), @space])
      following = opened(current[:no], 0)
      unless following[:tag] == :conditional
        contents << expr(following, 0)
        break
      end
      contents << expr(following[:test], 1)
      current = following
    end
    group(cat(expr(entry[:test], 1), nest(@indent, cat(contents))))
  end
  def postfix_piece(entry)
    case entry[:tag]
    when :call then list_doc(entry[:arguments])
    when :index then cat(t(entry[:left]), expr(entry[:index], 0), t(entry[:right]))
    when :member then cat(t(entry[:dot]), t(entry[:member]))
    end
  end
  def postfix(entry)
    operations, current = [], entry
    while %i[call index member].include?(current[:tag])
      operations << current
      current = opened(current[:target], 8)
    end
    operations.reverse!
    segments = [[]]
    operations.each do |operation|
      segments << [] if operation[:tag] == :member
      segments.last << operation
    end
    calls = (1...segments.length).select { |index| segments[index].any? { |part| part[:tag] == :call } }
    head = expr(current, 8)
    return cat(head, operations.map { |op| postfix_piece(op) }) if calls.length < 2
    split = calls.first
    preceding = segments.take(split).flatten.map { |op| postfix_piece(op) }
    following = segments.drop(split).map { |segment| cat(SOFTLINE, segment.map { |op| postfix_piece(op) }) }
    group(cat(head, preceding, nest(@indent, cat(following))))
  end
  def expr(entry, minimum)
    entry = opened(entry, minimum)
    case entry[:tag]
    when :primary then t(entry[:value])
    when :paren then cat(t(entry[:left]), expr(entry[:inner], 0), t(entry[:right]))
    when :unary then cat(t(entry[:op]), expr(entry[:operand], 8))
    when :binary then binary(entry)
    when :conditional then conditional(entry)
    when :call, :index, :member then postfix(entry)
    end
  end
end

def attach_comments(tokens, comments, sequence)
  cursor = 0
  comments.each do |comment|
    cursor += 1 while cursor < tokens.length - 1 && tokens[cursor][:order] < comment[:order]
    previous = cursor > 0 ? tokens[cursor - 1] : nil
    following = tokens[cursor]
    next_entry = sequence[comment[:order] + 1]
    comment[:own] = comment[:kind] == :line_comment || !next_entry || next_entry[:line] > comment[:line]
    if previous && previous[:line] == comment[:line] && (following[:kind] == :end || following[:line] > comment[:line])
      previous[:trailing] << comment
    else
      following[:leading] << comment
    end
  end
  tokens.each { |token| token[:source_trailing] = !token[:trailing].empty? }
end

def render_once(lines, profile)
  tokens, comments, sequence = Lexer.scan(lines)
  attach_comments(tokens, comments, sequence)
  items = Parser.new(tokens).parse
  tokens.each do |token|
    token[:leading].each do |comment|
      if token[:trailing_comma] || (comment[:own] && !token[:allowed])
        raise SourceError.new(comment[:line], comment[:column], 'comment not allowed here')
      end
    end
  end
  return {lines: [], comments: comments, document: nil, function: nil} if items.empty? && tokens.last[:leading].empty?
  builder = Formatter.new(profile, tokens)
  document = builder.whole_file(items, tokens.last)
  formatted = Printer.layout(document, profile)
  index = items.index { |item| item[:tag] == :function }
  {lines: formatted, comments: comments, document: document,
   function: index ? items[index] : nil, function_doc: index ? builder.item_docs[index] : nil}
end

def main
  profiles, profile = {}, nil
  File.foreach('input/style.txt', chomp: true) do |line|
    next if line.empty?
    if line.start_with?('[')
      profile = profiles[line[1...-1]] = {}
    else
      key, value = line.split('=', 2)
      value = value.to_i if %w[width indent max_blank_lines comment_column].include?(key)
      value = value == 'yes' if %w[space_around_operators space_after_keyword indent_case_labels add_braces remove_parens].include?(key)
      profile[key.to_sym] = value
    end
  end
  sources = []
  File.foreach('input/sources.txt', chomp: true) do |line|
    if line.start_with?('=== ')
      _, name, style = line.split(' ')
      sources << {header: line, name: name, profile: profiles[style], lines: []}
    else
      sources.last[:lines] << line
    end
  end
  output = %w[formatted idempotency diagnostics doc_tree changes].to_h { |name| [name, []] }
  sources.each do |source|
    name, profile = source.values_at(:name, :profile)
    original = source[:lines].map(&:rstrip)
    output['formatted'] << source[:header]
    output['doc_tree'] << "=== #{name}"
    output['changes'] << "=== #{name}"
    begin
      first = render_once(source[:lines], profile)
    rescue SourceError => error
      output['formatted'].concat(original)
      output['idempotency'] << "#{name}: skipped (syntax error)"
      output['diagnostics'] << "#{name}:#{error.line}:#{error.column}: error: #{error.message}"
      output['doc_tree'] << 'syntax error'
      output['changes'] << 'skipped (syntax error)'
      next
    end
    formatted = first[:lines]
    output['formatted'].concat(formatted)
    begin
      second = render_once(formatted, profile)[:lines]
      difference = (0...[formatted.length, second.length].min).find { |i| formatted[i] != second[i] }
      status = if formatted == second
                 'stable'
               else
                 "unstable at line #{difference ? difference + 1 : [formatted.length, second.length].min + 1}"
               end
    rescue SourceError => error
      status = "unstable (second pass: #{error.line}:#{error.column}: #{error.message})"
    end
    output['idempotency'] << "#{name}: #{status}"
    formatted.each_with_index do |line, index|
      output['diagnostics'] << "#{name}:#{index + 1}: warning: line too long (#{line.length} > #{profile[:width]})" if line.length > profile[:width]
    end
    groups = Docs.groups(first[:document])
    output['doc_tree'] << "metrics lines=#{formatted.length} longest=#{formatted.map(&:length).max || 0} comments=#{first[:comments].length} groups=#{groups.length} broken=#{groups.count { |g| %i[break forced].include?(g[:mode]) }} forced=#{groups.count { |g| g[:mode] == :forced }}"
    if first[:function]
      output['doc_tree'] << "function #{first[:function][:name][:text]}"
      output['doc_tree'].concat(Report.tree(first[:function_doc]))
    else
      output['doc_tree'] << 'no function'
    end
    output['changes'].concat(Report.diff(original, formatted))
  end
  output['diagnostics'] << 'no diagnostics' if output['diagnostics'].empty?
  output.each { |name, rows| File.write("output/#{name}.txt", rows.map { |line| line.rstrip + "\n" }.join) }
end

main if $PROGRAM_NAME == __FILE__
