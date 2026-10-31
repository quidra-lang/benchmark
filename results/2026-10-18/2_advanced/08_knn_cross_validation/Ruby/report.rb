# frozen_string_literal: true

module Report
  def self.real(value, digits = 4)
    return '-' if value.nil?

    text = format('%.*f', digits, value)
    /\A-0\.0+\z/.match?(text) ? text[1..] : text
  end

  def self.rounded(value)
    real(value).delete('.').to_i
  end

  def self.ratio(numerator, denominator)
    "#{numerator}/#{denominator} #{real(numerator.to_f / denominator.to_f)}"
  end

  def self.reduced(numerator, denominator)
    return '- -' if denominator.zero?

    divisor = numerator.gcd(denominator)
    ratio(numerator / divisor, denominator / divisor)
  end

  def self.write(files)
    Dir.mkdir('output') unless Dir.exist?('output')
    files.each { |name, lines| File.binwrite("output/#{name}", lines.empty? ? '' : lines.join("\n") + "\n") }
  end
end
