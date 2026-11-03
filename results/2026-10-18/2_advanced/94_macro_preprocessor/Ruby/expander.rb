require_relative 'lexer'
require_relative 'definitions'

class Expander
  attr_reader :builtin_counts

  def initialize(macros, diagnostic)
    @macros, @diagnostic = macros, diagnostic
    @counter = 0
    @builtin_counts = Hash.new(0)
  end

  def error(context, token, message)
    @diagnostic.call(context.position(token.line), 'error', message)
  end

  def builtin(token, context)
    builtin_counts[token.spelling] += 1
    case token.spelling
    when '__FILE__'
      Token.make(:string, '"' + context.display_file + '"', token.line, token.space)
    when '__LINE__'
      Token.make(:number, context.position(token.line)[1].to_s, token.line, token.space)
    else
      result = Token.make(:number, @counter.to_s, token.line, token.space)
      @counter += 1
      result
    end
  end

  def collect(pending, macro, token, context)
    arguments, separators, nesting = [[]], [], 0
    closing, consumed = nil, nil
    pending.reverse_each.with_index do |current, index|
      next if index.zero?
      if current.spelling == ')' && nesting.zero?
        closing, consumed = current, index + 1
        break
      elsif current.spelling == ',' && nesting.zero?
        separators << current
        arguments << []
      else
        nesting += 1 if current.spelling == '('
        nesting -= 1 if current.spelling == ')'
        arguments[-1] << current
      end
    end
    unless closing
      error(context, token, "unterminated argument list invoking macro \"#{macro.name}\"")
      return nil
    end
    count = arguments.length
    fixed = macro.parameters.length - (macro.variadic ? 1 : 0)
    message = if !macro.variadic && fixed.zero? && !(count == 1 && arguments[0].empty?)
                "macro \"#{macro.name}\" passed #{count} arguments, but takes just 0"
              elsif count < fixed
                "macro \"#{macro.name}\" requires #{fixed} arguments, but only #{count} given"
              elsif count > fixed && !macro.variadic
                "macro \"#{macro.name}\" passed #{count} arguments, but takes just #{fixed}"
              end
    if message
      error(context, token, message)
      return nil
    end
    raw = macro.parameters.take(fixed).zip(arguments.take(fixed)).to_h
    if macro.variadic
      variable = []
      (fixed...count).each do |index|
        variable << separators[index - 1] if index > fixed
        variable.concat(arguments[index])
      end
      raw[Definitions::VARIADIC] = variable
    end
    [raw, consumed, closing]
  end

  def stringize(tokens, sharp)
    spelling = tokens.each_with_index.map do |token, index|
      text = token.spelling
      text = text.gsub(/[\\"]/) { |character| '\\' + character } if [:string, :character].include?(token.kind)
      (index.positive? && token.space ? ' ' : '') + text
    end.join
    Token.make(:string, '"' + spelling + '"', sharp.line, sharp.space)
  end

  def paste(left, right, token, context)
    return [right.with(space: left.space)] if left.kind == :placemarker
    return [left] if right.kind == :placemarker
    spelling = left.spelling + right.spelling
    kind = Lexer.single_token(spelling)
    return [Token.make(kind, spelling, left.line, left.space, left.hide & right.hide)] if kind
    error(context, token, "pasting \"#{left.spelling}\" and \"#{right.spelling}\" does not give a valid preprocessing token")
    [left, right.with(space: false)]
  end

  # Return an argument-expansion job when first needed; otherwise finish items.
  def build_items(state)
    macro, raw, items = state.values_at(:macro, :raw, :items)
    replacement = macro.replacement
    while state[:index] < replacement.length
      index = state[:index]
      current = replacement[index]
      if current.spelling == '#' && macro.parameters
        items << [stringize(raw[replacement[index + 1].spelling], current)]
        state[:index] += 2
        next
      elsif current.spelling == '##'
        items << current
      elsif current.kind == :identifier && raw.key?(current.spelling)
        adjacent = replacement[index - 1]&.spelling == '##' && index.positive? || replacement[index + 1]&.spelling == '##'
        unless adjacent || state[:expanded].key?(current.spelling)
          return [current.spelling, raw[current.spelling]]
        end
        sequence = adjacent ? raw[current.spelling] : state[:expanded][current.spelling]
        items << if sequence.empty?
                   [Token.make(:placemarker, '', current.line, current.space)]
                 else
                   [sequence[0].with(space: current.space), *sequence.drop(1)]
                 end
      else
        items << [current]
      end
      state[:index] += 1
    end
    nil
  end

  def finish_substitution(state, context)
    token, hide, items = state.values_at(:token, :hide, :items)
    pasted, index = [], 0
    while index < items.length
      item = items[index]
      if item.is_a?(Token)
        left = pasted.pop
        right = items[index + 1]
        right = [right] if right.is_a?(Token)
        pasted.concat(paste(left, right[0], token, context))
        pasted.concat(right.drop(1))
        index += 2
      else
        pasted.concat(item)
        index += 1
      end
    end
    result, carry = [], false
    pasted.each do |current|
      if current.kind == :placemarker
        carry ||= current.space
      else
        result << current.with(line: token.line, space: current.space || carry, hide: (current.hide | hide).freeze)
        carry = false
      end
    end
    result[0] = result[0].with(space: token.space) unless result.empty?
    result
  end

  def expansion_frame(sequence)
    {pending: sequence.reverse, result: [], substitution: nil, argument: nil}
  end

  # Argument expansion uses explicit frames, not the Ruby call stack.
  def expand(sequence, context)
    frames = [expansion_frame(sequence)]
    until frames.empty?
      frame = frames[-1]
      pending, result, state = frame.values_at(:pending, :result, :substitution)
      if state
        job = build_items(state)
        if job
          frame[:argument] = job[0]
          frames << expansion_frame(job[1])
          next
        end
        replacement = finish_substitution(state, context)
        state[:macro].expanded += 1
        if replacement.empty? && state[:token].space && !pending.empty?
          pending[-1] = pending[-1].with(space: true)
        end
        pending.concat(replacement.reverse)
        frame[:substitution] = nil
        next
      end
      if pending.empty?
        frames.pop
        return result if frames.empty?
        parent = frames[-1]
        parent[:substitution][:expanded][parent[:argument]] = result
        next
      end
      token = pending.pop
      if token.kind != :identifier || token.hide.include?(token.spelling)
        result << token
      elsif Definitions::BUILTINS.include?(token.spelling)
        result << builtin(token, context)
      else
        macro = @macros[token.spelling]
        if !macro || (macro.parameters && pending[-1]&.spelling != '(')
          result << token
          next
        end
        raw, hide = {}, token.hide | Set[macro.name]
        if macro.parameters
          collected = collect(pending, macro, token, context)
          unless collected
            result << token
            next
          end
          raw, consumed, closing = collected
          consumed.times { pending.pop }
          hide = (token.hide & closing.hide) | Set[macro.name]
        end
        frame[:substitution] = {macro: macro, raw: raw, token: token, hide: hide,
                                index: 0, items: [], expanded: {}}
      end
    end
  end
end
