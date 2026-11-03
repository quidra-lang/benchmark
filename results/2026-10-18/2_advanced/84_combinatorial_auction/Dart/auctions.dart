part of 'main.dart';

class Candidate {
  final int mask, value;
  Candidate(this.mask, this.value);
}

List<Candidate> candidates(List<Bid> bids, bool xor) {
  final out = <Candidate>[];
  for (var code = 1; code < (1 << bids.length); code++) {
    if (xor && popcount(code) != 1) continue;
    var mask = 0, value = 0, valid = true;
    for (var i = 0; i < bids.length; i++) {
      if (code & (1 << i) == 0) continue;
      final b = bids[i];
      if (mask & b.mask != 0) {
        valid = false;
        break;
      }
      mask |= b.mask;
      value += b.amount;
    }
    if (valid) out.add(Candidate(mask, value));
  }
  return out;
}

int candidateValue(List<Candidate> candidates, int mask) {
  var value = 0;
  for (final c in candidates) {
    if (c.mask & mask == c.mask) value = max(value, c.value);
  }
  return value;
}

class ClockResult {
  int winner = -1, steps = 0, price;
  final List<int> drops;
  ClockResult(this.price, int n) : drops = List.filled(n, -1);
}

ClockResult english(
  List<Participant> participants,
  int reserve,
  int increment,
) {
  final r = ClockResult(reserve, participants.length);
  List<int> remaining(int price) {
    final out = <int>[];
    for (var i = 0; i < participants.length; i++) {
      final p = participants[i];
      if (p.value >= price) {
        out.add(i);
      } else if (r.drops[i] < 0) {
        r.drops[i] = price;
      }
    }
    return out;
  }

  var active = remaining(reserve);
  if (active.isEmpty) return r;
  if (active.length == 1) {
    r.winner = active.first;
    return r;
  }
  while (true) {
    final previous = active, price = r.price;
    r.price += increment;
    r.steps++;
    active = remaining(r.price);
    if (active.length == 1) {
      r.winner = active.first;
      return r;
    }
    if (active.isEmpty) {
      r.winner = previous.first;
      r.price = price;
      return r;
    }
  }
}

ClockResult dutch(
  List<Participant> participants,
  int reserve,
  int start,
  int decrement,
) {
  final r = ClockResult(start, participants.length);
  while (r.price >= reserve) {
    var winner = -1;
    for (var i = 0; i < participants.length; i++) {
      final p = participants[i];
      if (p.bid >= r.price && (winner < 0 || p.bid > participants[winner].bid))
        winner = i;
    }
    if (winner >= 0) {
      r.winner = winner;
      return r;
    }
    r.price -= decrement;
    r.steps++;
  }
  return r;
}
