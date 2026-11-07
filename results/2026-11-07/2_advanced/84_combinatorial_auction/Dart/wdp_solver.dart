part of 'main.dart';

class Improvement {
  final int node, welfare;
  final List<Bid> bids;
  Improvement(this.node, this.welfare, this.bids);
}

class SearchResult {
  int welfare = 0, nodes = 0, pruned = 0, leaves = 0, improvements = 0;
  List<Bid> bids = [];
  final List<Improvement> records = [];
  List<Fraction> shares = [];
  List<int> sources = [];
  Fraction bound = whole(0);
}

List<Bid> usable(List<Bid> bids, int decided, int xorWinners) => bids
    .where(
      (b) =>
          b.mask & decided == 0 &&
          (!b.xor || xorWinners & (1 << b.bidder) == 0),
    )
    .toList();
(List<Fraction>, List<int>, Fraction) shares(
  List<Item> items,
  int offered,
  int decided,
  List<Bid> bids,
  int welfare,
) {
  final values = List.filled(items.length, whole(0)),
      sources = List.filled(items.length, 0);
  var bound = whole(welfare);
  for (var i = 0; i < items.length; i++) {
    if (offered & (1 << i) == 0 || decided & (1 << i) != 0) continue;
    var value = whole(items[i].reserve);
    for (final b in bids) {
      if (b.mask & (1 << i) != 0) {
        final candidate = fraction(b.amount, b.size);
        if (candidate.compare(value) > 0) {
          value = candidate;
          sources[i] = b.number;
        }
      }
    }
    values[i] = value;
    bound = bound.add(value);
  }
  return (values, sources, bound);
}

SearchResult solveWDP(List<Item> items, int offered, List<Bid> bids) {
  final result = SearchResult();
  final (rootShares, sources, bound) = shares(items, offered, 0, bids, 0);
  result.shares = rootShares;
  result.sources = sources;
  result.bound = bound;
  var incumbent = false;
  void visit(int decided, int xorWinners, int welfare, List<Bid> chosen) {
    result.nodes++;
    if (decided == offered) {
      result.leaves++;
      final list = List<Bid>.of(chosen)
        ..sort((a, b) => a.number.compareTo(b.number));
      if (!incumbent ||
          welfare > result.welfare ||
          (welfare == result.welfare &&
              compareInts(
                    list.map((b) => b.number).toList(),
                    result.bids.map((b) => b.number).toList(),
                  ) <
                  0)) {
        incumbent = true;
        result.welfare = welfare;
        result.bids = list;
        result.improvements++;
        result.records.add(Improvement(result.nodes, welfare, list));
      }
      return;
    }
    final available = usable(bids, decided, xorWinners),
        bound = shares(items, offered, decided, available, welfare).$3;
    if (incumbent && bound.compare(whole(result.welfare)) < 0) {
      result.pruned++;
      return;
    }
    var j = 0;
    while (offered & (1 << j) == 0 || decided & (1 << j) != 0) {
      j++;
    }
    for (final b in available) {
      if (b.mask & (1 << j) == 0) continue;
      visit(
        decided | b.mask,
        b.xor ? xorWinners | (1 << b.bidder) : xorWinners,
        welfare + b.amount,
        [...chosen, b],
      );
    }
    visit(decided | (1 << j), xorWinners, welfare + items[j].reserve, chosen);
  }

  visit(0, 0, 0, []);
  return result;
}

List<Bid> greedyOrder(List<Bid> bids) => List<Bid>.of(bids)
  ..sort((a, b) {
    final left = a.amount * a.amount * b.size,
        right = b.amount * b.amount * a.size;
    return left != right ? right.compareTo(left) : a.number.compareTo(b.number);
  });
List<Bid> greedySelect(List<Bid> order, int excluded) {
  var mask = 0, xorWinners = 0;
  final out = <Bid>[];
  for (final b in order) {
    if (b.number == excluded ||
        b.mask & mask != 0 ||
        (b.xor && xorWinners & (1 << b.bidder) != 0))
      continue;
    out.add(b);
    mask |= b.mask;
    if (b.xor) xorWinners |= 1 << b.bidder;
  }
  return out;
}
