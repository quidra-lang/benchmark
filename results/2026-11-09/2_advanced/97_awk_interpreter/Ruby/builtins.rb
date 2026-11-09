class AwkRuntimeError < StandardError
  attr_reader :token
  def initialize(message, token)
    super(message)
    @token = token
  end
end

module Builtins
  def self.format_values(values, token)
    fmt, arguments = values[0].string, values.drop(1)
    result, at, argument = +'', 0, 0
    while at < fmt.length
      if fmt[at] != '%'
        result << fmt[at]
        at += 1
        next
      end
      at += 1
      if fmt[at] == '%'
        result << '%'
        at += 1
        next
      end
      flags = +''
      while ['-', '0'].include?(fmt[at])
        flags << fmt[at]
        at += 1
      end
      first = at
      at += 1 while Lexer.digit?(fmt[at])
      width = fmt[first...at].to_i
      precision = nil
      if fmt[at] == '.'
        at += 1
        first = at
        at += 1 while Lexer.digit?(fmt[at])
        precision = fmt[first...at].to_i
      end
      conversion = fmt[at]
      raise AwkRuntimeError.new('invalid format', token) unless conversion && 'discxo'.include?(conversion)
      raise AwkRuntimeError.new('not enough arguments', token) if argument >= arguments.length
      value = arguments[argument]
      argument += 1
      at += 1
      numeric = 'dixo'.include?(conversion)
      if numeric
        n = value.number
        digits = n.abs.to_s({ 'x' => 16, 'o' => 8 }.fetch(conversion, 10))
        digits = '' if precision == 0 && n == 0
        digits = digits.rjust(precision, '0') if precision
        body = (n.negative? ? '-' : '') + digits
      elsif conversion == 's'
        body = precision ? value.string[0, precision] : value.string
      elsif [:number, :strnum].include?(value.kind)
        n = value.number
        raise AwkRuntimeError.new('invalid character code', token) unless n == 10 || (32..126).cover?(n)
        body = n.chr
      else
        body = value.string[0, 1]
      end
      if body.length < width
        padding = width - body.length
        body = if flags.include?('-')
                 body + ' ' * padding
               elsif numeric && flags.include?('0') && precision.nil?
                 body.start_with?('-') ? '-' + '0' * padding + body[1..] : '0' * padding + body
               else
                 ' ' * padding + body
               end
      end
      result << body
    end
    result
  end

  def self.call(name, values, token)
    case name
    when 'sprintf' then Value.string(format_values(values, token))
    when 'int' then Value.number(values[0].number)
    when 'toupper' then Value.string(values[0].string.upcase)
    when 'tolower' then Value.string(values[0].string.downcase)
    when 'index'
      text, needle = values.map(&:string)
      Value.number(needle.empty? ? 0 : (text.index(needle) || -1) + 1)
    when 'substr'
      text, start = values[0].string, values[1].number
      ending = values[2] ? start + values[2].number : text.length + 1
      start = [start, 1].max
      ending = [ending, text.length + 1].min
      Value.string(ending > start ? text[(start - 1)...(ending - 1)] : '')
    end
  end
end
