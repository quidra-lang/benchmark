expressions = [
  '3 4 + 2 *', '-17 5 / 4 -3 * -', '1 2 + * 3',
  '15 7 1 1 + - / 3 * 2 1 1 + + -', '4 2 5 * + 1 3 2 * - 5 + /',
  '2 3 4 + 5', '46341 46339 * -2 /'
]
expressions.each do |expression|
  stack = []
  error = nil
  expression.split.each do |token|
    unless %w[+ - * /].include?(token)
      stack << token.to_i
      next
    end
    if stack.length < 2
      error = 'stack underflow'
      break
    end
    b, a = stack.pop, stack.pop
    if token == '/' && b.zero?
      error = 'division by zero'
      break
    end
    result = case token
             when '+' then a + b
             when '-' then a - b
             when '*' then a * b
             else
               quotient = a.abs / b.abs
               (a.negative? != b.negative?) ? -quotient : quotient
             end
    stack << result
  end
  error = 'leftover operands' if error.nil? && stack.length != 1
  answer = error ? "error: #{error}" : stack[0].to_s
  puts "#{expression} => #{answer}"
end
