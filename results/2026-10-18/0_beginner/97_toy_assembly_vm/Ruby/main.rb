program = [
  'SET A 1', 'SET B 1', 'SET D 8', 'MUL A B', 'PRINT A', 'ADD B 1', 'SUB D 1',
  'JNZ D -4', 'SET A 1071', 'SET B 462', 'SET C A', 'MOD C B', 'SET A B',
  'SET B C', 'JNZ B -4', 'PRINT A', 'HALT'
]
registers = %w[A B C D].to_h { |register| [register, 0] }
value = ->(token) { registers.key?(token) ? registers[token] : token.to_i }
pc = executed = 0
while pc.between?(0, program.length - 1)
  parts = program[pc].split
  operation = parts[0]
  executed += 1
  break if operation == 'HALT'
  if operation == 'JNZ'
    pc += value.call(parts[1]).zero? ? 1 : parts[2].to_i
    next
  end
  if operation == 'PRINT'
    puts value.call(parts[1])
  else
    register, operand = parts[1], value.call(parts[2])
    case operation
    when 'SET' then registers[register] = operand
    when 'ADD' then registers[register] += operand
    when 'SUB' then registers[register] -= operand
    when 'MUL' then registers[register] *= operand
    when 'MOD' then registers[register] %= operand
    end
  end
  pc += 1
end
puts "executed: #{executed}"
