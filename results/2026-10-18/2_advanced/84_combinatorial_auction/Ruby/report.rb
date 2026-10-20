require 'fileutils'

module Report
  def fraction(value)
    value = Rational(value)
    value.denominator == 1 ? value.numerator.to_s : "#{value.numerator}/#{value.denominator}"
  end

  def bundle(items, order)
    names = order.select { |item| items.include?(item) }
    names.empty? ? '-' : names.join('+')
  end

  def write_reports(reports)
    FileUtils.mkdir_p('output')
    reports.each do |name, lines|
      File.write("output/#{name}", lines.join("\n") + "\n", encoding: 'US-ASCII')
    end
  end
end
