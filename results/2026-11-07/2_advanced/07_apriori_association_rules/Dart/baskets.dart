import 'dart:io';

typedef Itemset = List<String>;
typedef Counted = ({Itemset items, int count});
typedef Frequent = Map<String, Counted>;

class Product {
  final String name, category;
  final int price;
  Product(this.name, this.category, this.price);
}

class Transaction {
  final String tid, customer;
  final int day;
  final Map<String, int> counts = {};
  Transaction(this.tid, this.customer, this.day);
  bool add(String product) { final duplicate = counts.containsKey(product); counts[product] = (counts[product] ?? 0) + 1; return duplicate; }
  Itemset get products => counts.keys.toList()..sort();
  int get units => counts.values.fold(0, (sum, value) => sum + value);
}

List<List<String>> readRecords(String name) => File('input/$name').readAsLinesSync().skip(1).map((line) => line.split(',')).toList();
bool containsSet(Set<String> basket, Itemset items) => items.every(basket.contains);
Set<String> extendedBasket(Itemset products, Map<String, String> taxonomy) => {...products, for (final product in products) taxonomy[product]!};
String setKey(Itemset items) => items.join('+');
int compareSets(Itemset first, Itemset second) {
  for (var i = 0; i < first.length; i++) { if (i == second.length) return 1; final comparison = first[i].compareTo(second[i]); if (comparison != 0) return comparison; }
  return first.length.compareTo(second.length);
}
int sizeOrder(Itemset first, Itemset second) { final comparison = first.length.compareTo(second.length); return comparison != 0 ? comparison : compareSets(first, second); }
