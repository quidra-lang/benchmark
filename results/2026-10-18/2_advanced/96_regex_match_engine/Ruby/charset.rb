module Charset
  ALL = (0..127).to_a.freeze
  DIGITS = (48..57).to_a.freeze
  WORD = (DIGITS + (65..90).to_a + [95] + (97..122).to_a).freeze
  SPACE = [9, 10, 11, 12, 13, 32].freeze

  def self.letter?(c)
    c && ((65..90).cover?(c) || (97..122).cover?(c))
  end

  def self.digit?(c)
    c && (48..57).cover?(c)
  end

  def self.swap(c)
    letter?(c) ? c ^ 32 : c
  end

  def self.predefined(c)
    base = { 'd' => DIGITS, 'w' => WORD, 's' => SPACE }[c.downcase]
    c == c.downcase ? base.dup : ALL - base
  end

  def self.equal?(a, b, flags)
    a == b || (flags.include?('i') && letter?(a) && swap(a) == b)
  end

  def self.class?(c, set, negated, flags)
    found = set.include?(c) || (flags.include?('i') && letter?(c) && set.include?(swap(c)))
    found != negated
  end

  def self.consume?(instruction, text, q, flags)
    return false if q >= text.length
    c = text.getbyte(q)
    case instruction[0]
    when :char then equal?(c, instruction[1], flags)
    when :any then flags.include?('s') || c != 10
    when :class then class?(c, instruction[1], instruction[2], flags)
    end
  end

  def self.assert?(kind, text, q, flags)
    case kind
    when :BOL then q.zero? || (flags.include?('m') && text.getbyte(q - 1) == 10)
    when :EOL then q == text.length || (flags.include?('m') && text.getbyte(q) == 10)
    else
      left = q.positive? && WORD.include?(text.getbyte(q - 1))
      right = q < text.length && WORD.include?(text.getbyte(q))
      kind == :WORD ? left != right : left == right
    end
  end
end
