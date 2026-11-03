void main() {
  final balances = {'Nina': 12000, 'Leo': 3500, 'Emma': 800};
  const commands = [
    'deposit Emma 1200',
    'withdraw Leo 4000',
    'transfer Nina Leo 5000',
    'withdraw Leo 4000',
    'transfer Emma Nina 2500',
    'transfer Emma Nina 2000',
    'withdraw Emma 300',
    'deposit Nina 750',
    'transfer Leo Emma 3200',
    'withdraw Nina 9800',
  ];
  for (var k = 0; k < commands.length; k++) {
    final parts = commands[k].split(' '),
        op = parts[0],
        source = parts[1],
        amount = int.parse(parts.last);
    var success = true;
    if (op == 'deposit') {
      balances[source] = balances[source]! + amount;
    } else if (balances[source]! < amount) {
      success = false;
    } else {
      balances[source] = balances[source]! - amount;
      if (op == 'transfer') balances[parts[2]] = balances[parts[2]]! + amount;
    }
    print(
      'op ${k + 1}: ${commands[k]} ${success ? 'ok' : 'failed (insufficient funds)'}',
    );
  }
  final names = balances.keys.toList()..sort();
  for (final name in names) {
    print('$name: ${balances[name]}');
  }
}
