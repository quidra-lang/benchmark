def decode(text)
  result = ''
  i = 0
  while i < text.length
    if text[i] == '+'
      result += ' '
    elsif text[i] == '%'
      result += text[i + 1, 2].to_i(16).chr
      i += 2
    else
      result += text[i]
    end
    i += 1
  end
  result
end

queries = [
  'name=Alice+Smith&age=30&city=New%20York',
  'q=c%2B%2B+tutorial&page=2&sort=desc&page=3',
  'msg=50%25+off%21&debug&lang=en&ref=&lang=ja',
  'redirect=https%3a%2f%2fexample.com%2Fhome&token=abc==&item10=pen&item2=fish%26chips'
]
queries.each_with_index do |query, number|
  values = Hash.new { |hash, key| hash[key] = [] }
  query.split('&').each do |item|
    key, _, value = item.partition('=')
    values[decode(key)] << decode(value)
  end
  puts "query #{number + 1}:"
  values.keys.sort.each do |key|
    quoted = values[key].map { |value| %("#{value}") }.join(', ')
    puts "  #{key}: #{quoted}"
  end
end
