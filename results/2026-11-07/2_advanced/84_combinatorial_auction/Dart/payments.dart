part of 'main.dart';

class VCGPayment {
  int value = 0, without = 0, payment = 0, utility = 0;
  final List<Bid> won = [];
  List<Bid> alternative = [];
}

List<VCGPayment> vcgPayments(
  List<Item> items,
  int offered,
  int n,
  List<Bid> eligible,
  List<Bid> winning,
  int welfare,
) {
  final out = List.generate(n, (_) => VCGPayment());
  for (var k = 0; k < n; k++) {
    final p = out[k];
    for (final b in winning) {
      if (b.bidder == k) {
        p.won.add(b);
        p.value += b.amount;
      }
    }
    if (p.won.isEmpty) continue;
    final r = solveWDP(
      items,
      offered,
      eligible.where((b) => b.bidder != k).toList(),
    );
    p.without = r.welfare;
    p.alternative = r.bids;
    p.payment = r.welfare - (welfare - p.value);
    p.utility = p.value - p.payment;
  }
  return out;
}

class Critical {
  final int payment, rival;
  Critical(this.payment, this.rival);
}

Map<int, Critical> criticalPayments(List<Bid> order, List<Bid> winning) {
  final out = <int, Critical>{};
  for (final b in winning) {
    Bid? rival;
    for (final c in greedySelect(order, b.number)) {
      if (c.mask & b.mask != 0 || (b.xor && b.bidder == c.bidder)) {
        rival = c;
        break;
      }
    }
    var payment = b.reserve, against = 0;
    if (rival != null) {
      final c = rival;
      against = c.number;
      bool before(int t) {
        final left = t * t * c.size, right = c.amount * c.amount * b.size;
        return left > right || (left == right && b.number < c.number);
      }

      var lo = 1, hi = 1;
      while (!before(hi)) {
        hi *= 2;
      }
      while (lo < hi) {
        final mid = (lo + hi) ~/ 2;
        if (before(mid)) {
          hi = mid;
        } else {
          lo = mid + 1;
        }
      }
      payment = max(payment, lo);
    }
    out[b.number] = Critical(payment, against);
  }
  return out;
}

class Coalition {
  final int mask, welfare;
  final List<Bid> bids;
  final List<int> members;
  Coalition(this.mask, this.welfare, this.bids, this.members);
}

List<Coalition> coalitions(
  List<Item> items,
  int offered,
  int n,
  List<Bid> bids,
) {
  final out = <Coalition>[];
  for (var mask = 0; mask < (1 << n); mask++) {
    final members = [
          for (var i = 0; i < n; i++)
            if (mask & (1 << i) != 0) i,
        ],
        r = solveWDP(
          items,
          offered,
          bids.where((b) => mask & (1 << b.bidder) != 0).toList(),
        );
    out.add(Coalition(mask, r.welfare, r.bids, members));
  }
  out.sort((a, b) {
    final c = a.members.length.compareTo(b.members.length);
    return c != 0 ? c : compareInts(a.members, b.members);
  });
  return out;
}

class Blocking {
  final Coalition coalition;
  final int payoff, deficit;
  final bool minimal;
  Blocking(this.coalition, this.payoff, this.deficit, this.minimal);
}

List<Blocking> blockers(
  List<Coalition> coalitions,
  int seller,
  List<int> utilities,
) {
  final out = <Blocking>[];
  for (final c in coalitions) {
    var payoff = seller;
    for (final i in c.members) {
      payoff += utilities[i];
    }
    if (c.welfare <= payoff) continue;
    final minimal = !out.any(
      (old) => old.coalition.mask & c.mask == old.coalition.mask,
    );
    out.add(Blocking(c, payoff, c.welfare - payoff, minimal));
  }
  return out;
}

int gspPrice(List<Participant> participants, List<int> order, int rank) =>
    rank + 1 >= order.length ? 0 : participants[order[rank + 1]].bid;
Fraction slotVCG(
  List<Participant> participants,
  List<int> order,
  List<Fraction> ctr,
  int rank,
) {
  var value = whole(0);
  Fraction rate(int i) => i >= ctr.length ? whole(0) : ctr[i];
  for (var t = rank + 1; t < min(order.length, ctr.length + 1); t++) {
    value = value.add(
      whole(participants[order[t]].value).mul(rate(t - 1).sub(rate(t))),
    );
  }
  return value;
}
