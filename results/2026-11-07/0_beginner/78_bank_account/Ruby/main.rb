balances = {'Nina' => 12000, 'Leo' => 3500, 'Emma' => 800}
transactions = [
  'deposit Emma 1200', 'withdraw Leo 4000', 'transfer Nina Leo 5000',
  'withdraw Leo 4000', 'transfer Emma Nina 2500', 'transfer Emma Nina 2000',
  'withdraw Emma 300', 'deposit Nina 750', 'transfer Leo Emma 3200', 'withdraw Nina 9800'
]
transactions.each_with_index do |transaction, number|
  parts = transaction.split(' ')
  operation, name, amount = parts[0], parts[1], parts[-1].to_i
  success = operation == 'deposit' || balances[name] >= amount
  if success
    if operation == 'deposit'
      balances[name] += amount
    else
      balances[name] -= amount
      balances[parts[2]] += amount if operation == 'transfer'
    end
  end
  result = success ? 'ok' : 'failed (insufficient funds)'
  puts "op #{number + 1}: #{transaction} #{result}"
end
balances.keys.sort.each { |name| puts "#{name}: #{balances[name]}" }
