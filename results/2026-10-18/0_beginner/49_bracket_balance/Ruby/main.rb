strings = [
  '(a + b) * [c - d]', '{x = [1, 2, (3 + 4)]}', 'f(a[i] + g(b)}', '(1 + 2)) * 3',
  'if (a < b) { c = d[0]; }', '((a + b] * c', '[{(x * y) - z}'
]
matching = {')' => '(', ']' => '[', '}' => '{'}
strings.each do |text|
  stack = []
  error = nil
  text.each_char.with_index do |char, i|
    if '([{'.include?(char)
      stack << char
    elsif matching.key?(char)
      if stack.empty? || stack[-1] != matching[char]
        error = i
        break
      end
      stack.pop
    end
  end
  error = text.length if error.nil? && !stack.empty?
  result = error.nil? ? 'balanced' : "error at index #{error}"
  puts "#{text} -> #{result}"
end
