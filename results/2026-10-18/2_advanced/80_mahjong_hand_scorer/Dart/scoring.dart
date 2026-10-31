part of 'main.dart';

int pairFu(int pair, int seat, int round) =>
    (pair >= 31 ? 2 : 0) + (pair == seat ? 2 : 0) + (pair == round ? 2 : 0);
bool concealed(Block b, String by) =>
    b.source == 'A' || b.source == 'concealed' && (!b.winning || by == 'tsumo');
(List<Award>, int, int) fuBreakdown(
  Candidate candidate,
  Situation s,
  bool closed,
  bool pinfu,
) {
  if (candidate.kind == 'chiitoitsu')
    return ([Award('chiitoitsu', 25)], 25, 25);
  final out = [Award('base', 20)];
  if (closed && s.by == 'ron') out.add(Award('closed_ron', 10));
  if (s.by == 'tsumo' && !pinfu) out.add(Award('tsumo', 2));
  final value = pairFu(candidate.pair, windKind(s.seat), windKind(s.round));
  if (value > 0)
    out.add(Award('pair ${blockNotation(candidate.pair, 2, false)}', value));
  for (final b in candidate.blocks) {
    if (b.sequence) continue;
    var kind = concealed(b, s.by) ? 'closed_triplet' : 'open_triplet',
        value = concealed(b, s.by) ? 4 : 2;
    if (b.kan) {
      kind = concealed(b, s.by) ? 'closed_kan' : 'open_kan';
      value = concealed(b, s.by) ? 16 : 8;
    }
    if (yaochuu(b.kind)) value *= 2;
    out.add(Award('$kind ${b.notation()}', value));
  }
  if (['kanchan', 'penchan', 'tanki'].contains(candidate.wait))
    out.add(Award('wait ${candidate.wait}', 2));
  var total = out.fold(0, (a, b) => a + b.value);
  if (!closed && total == 20) {
    out.add(Award('open_pinfu', 10));
    total += 10;
  }
  return (out, total, (total + 9) ~/ 10 * 10);
}

(String, int) limitScore(int han, int fu, Rule rule) {
  if (han >= 13 && rule.kazoe) return ('kazoe_yakuman', 8000);
  if (han >= 11) return ('sanbaiman', 6000);
  if (han >= 8) return ('baiman', 4000);
  if (han >= 6) return ('haneman', 3000);
  final base = fu * (1 << (han + 2));
  if (han == 5 || base >= 2000 || rule.kiriage && base == 1920)
    return ('mangan', 2000);
  return ('none', base);
}

int roundHundred(int x) => (x + 99) ~/ 100 * 100;

class Payment {
  int points = 0, ron = 0, dealer = 0, nondealer = 0, all = 0;
}

Payment payments(int base, String seat, String by) {
  final p = Payment();
  if (by == 'ron') {
    p.ron = roundHundred((seat == 'E' ? 6 : 4) * base);
    p.points = p.ron;
  } else if (seat == 'E') {
    p.all = roundHundred(2 * base);
    p.points = 3 * p.all;
  } else {
    p.dealer = roundHundred(2 * base);
    p.nondealer = roundHundred(base);
    p.points = p.dealer + 2 * p.nondealer;
  }
  return p;
}
