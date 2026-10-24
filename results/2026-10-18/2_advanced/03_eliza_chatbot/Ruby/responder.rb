module Responder
  def self.reflect(words, substitutions)
    words.flat_map { |word| substitutions.key?(word) ? substitutions[word][:replacement] : [word] }
  end

  def self.binding(bindings, number)
    number.between?(1, bindings.length) ? bindings[number - 1] : []
  end

  def self.build(template, bindings, substitutions)
    text = template.gsub(/\(([0-9])\)/) do
      reflect(binding(bindings, Regexp.last_match(1).to_i), substitutions).join(' ')
    end
    text = text.split(' ').join(' ')
    text[0] = text[0].upcase if /\A[a-z]/.match?(text)
    text
  end

  def self.restate(arguments, bindings)
    arguments.drop(1).flat_map do |argument|
      if /\A\([0-9]\)\z/.match?(argument)
        binding(bindings, argument[1].to_i)
      else
        [argument]
      end
    end
  end

  def self.wrap(text)
    words = text.split(' ')
    lines = ["ELIZA: #{words.first}"]
    words.drop(1).each do |word|
      if lines.last.length + 1 + word.length <= 72
        lines[-1] += " #{word}"
      else
        lines << "       #{word}"
      end
    end
    lines
  end
end
