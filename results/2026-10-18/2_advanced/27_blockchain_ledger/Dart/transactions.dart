import 'hashing.dart';
import 'wallets.dart';

typedef Reference = (String, int);
typedef Output = (String, int);
typedef Utxo = Map<Reference, Coin>;
String referenceText(Reference ref) => '${ref.$1}:${ref.$2}';
int compareReferences(Reference a, Reference b) {
  final order = a.$1.compareTo(b.$1);
  return order != 0 ? order : a.$2.compareTo(b.$2);
}

class Coin {
  final String address;
  final int amount, height;
  final bool coinbase;
  Coin(this.address, this.amount, this.height, this.coinbase);
  bool mature(int nextHeight, int maturity) =>
      !coinbase || height == 0 || nextHeight >= height + maturity;
}

class Transaction {
  final String text;
  late final String txid, body;
  late final int size;
  int? coinbaseHeight;
  final inputs = <Reference>[];
  final outputs = <Output>[];
  final signatures = <String>[];
  Transaction(this.text) {
    txid = digest(text);
    size = text.length;
    final parts = text.split(';');
    for (final field in parts[1].substring(4).split(',')) {
      final pair = field.split(':');
      outputs.add((pair[0], int.parse(pair[1])));
    }
    if (text.startsWith('cb=')) {
      coinbaseHeight = int.parse(parts[0].substring(3));
      body = '';
    } else {
      for (final field in parts[0].substring(3).split(',')) {
        final pair = field.split(':');
        inputs.add((pair[0], int.parse(pair[1])));
      }
      signatures.addAll(parts[2].substring(4).split(','));
      body = text.substring(0, text.indexOf(';sig='));
    }
  }
  bool get coinbase => coinbaseHeight != null;
  int get outputTotal => outputs.fold(0, (total, output) => total + output.$2);
}

String outputsText(List<Output> outputs) =>
    outputs.map((out) => '${out.$1}:${out.$2}').join(',');
Transaction payment(
  List<Reference> inputs,
  List<Output> outputs,
  String secret,
) {
  final body =
      'in=${inputs.map(referenceText).join(',')};out=${outputsText(outputs)}';
  return Transaction(
    '$body;sig=${[for (var i = 0; i < inputs.length; i++) sign(secret, i, body)].join(',')}',
  );
}

Transaction coinbase(int height, List<Output> outputs) =>
    Transaction('cb=$height;out=${outputsText(outputs)}');
(String?, int) checkTransaction(
  Transaction t,
  Utxo utxo,
  Set<Reference> spent,
  int height,
  int maturity,
  Map<String, Wallet> owners,
) {
  for (final out in t.outputs) {
    if (!owners.containsKey(out.$1) || out.$2 == 0) return ('bad-output', 0);
  }
  final seen = <Reference>{};
  var total = 0;
  for (var i = 0; i < t.inputs.length; i++) {
    final ref = t.inputs[i];
    if (spent.contains(ref) || seen.contains(ref)) return ('double-spend', 0);
    final c = utxo[ref];
    if (c == null) return ('missing-input', 0);
    if (!c.mature(height, maturity)) return ('immature', 0);
    if (t.signatures[i] != sign(owners[c.address]!.secret, i, t.body))
      return ('bad-sig', 0);
    seen.add(ref);
    total += c.amount;
  }
  return total < t.outputTotal
      ? ('overspend', 0)
      : (null, total - t.outputTotal);
}

void applyTransaction(Utxo utxo, Transaction t, int height) {
  for (final ref in t.inputs) {
    utxo.remove(ref);
  }
  for (var j = 0; j < t.outputs.length; j++) {
    final out = t.outputs[j];
    utxo[(t.txid, j)] = Coin(out.$1, out.$2, height, t.coinbase);
  }
}
