import 'dart:io';
import 'hashing.dart';

class Wallet {
  final String name, secret, address;
  Wallet(this.name, this.secret)
    : address = digest('addr:$secret').substring(0, 16);
}

List<Wallet> readWallets() => [
  for (final line in File('input/wallets.txt').readAsLinesSync())
    Wallet(line.split(' ')[0], line.split(' ')[1]),
];
String sign(String secret, int index, String body) =>
    digest('$secret:$index:$body').substring(0, 16);
