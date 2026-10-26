SMALL = %w[
  zero one two three four five six seven eight nine
  ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen
]
TENS = ['', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety']

def under_thousand(value)
  parts = []
  parts << SMALL[value / 100] + ' hundred' if value >= 100
  remainder = value % 100
  if remainder >= 20
    word = TENS[remainder / 10]
    word += '-' + SMALL[remainder % 10] unless (remainder % 10).zero?
    parts << word
  elsif remainder.positive?
    parts << SMALL[remainder]
  end
  parts.join(' ')
end

[0, 13, 40, 100, 568, 71000, 300019, 999999].each do |number|
  parts = []
  parts << under_thousand(number / 1000) + ' thousand' if number >= 1000
  parts << under_thousand(number % 1000) unless (number % 1000).zero?
  words = parts.empty? ? SMALL[0] : parts.join(' ')
  puts "#{number}: #{words}"
end
