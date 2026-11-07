# frozen_string_literal: true

module Report
  RULE_HEADER = 'rank,antecedent,consequent,count,support,confidence,lift,leverage,conviction,improvement'

  def fraction(value)
    numerator = value.numerator
    denominator = value.denominator
    scaled = numerator.abs * 10_000 / denominator
    decimal = "#{scaled / 10_000}.#{(scaled % 10_000).to_s.rjust(4, '0')}"
    decimal = '-' + decimal if numerator.negative? && scaled.positive?
    "#{numerator}/#{denominator}=#{decimal}"
  end

  def percentage(numerator, denominator)
    scaled = 10_000 * numerator / denominator
    "#{scaled / 100}.#{(scaled % 100).to_s.rjust(2, '0')}%"
  end

  def money(cents)
    "#{cents / 100}.#{(cents % 100).to_s.rjust(2, '0')}"
  end

  def itemset(items)
    items.join('+')
  end

  def rule_csv(rule)
    values = [rule.rank, itemset(rule.antecedent), itemset(rule.consequent), rule.count]
    values.concat([rule.support, rule.confidence, rule.lift, rule.leverage].map { |value| fraction(value) })
    values << (rule.conviction.nil? ? 'INF' : fraction(rule.conviction))
    values << fraction(rule.improvement)
    values.join(',')
  end

  def write_files(files)
    Dir.mkdir('output') unless Dir.exist?('output')
    files.each do |name, lines|
      File.binwrite("output/#{name}", lines.join("\n") + (lines.empty? ? '' : "\n"))
    end
  end
end
