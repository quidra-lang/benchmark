import 'dart:io';
import 'dart:math';
part 'tiles.dart';
part 'decomposition.dart';
part 'yaku.dart';
part 'scoring.dart';
part 'shanten.dart';

class Rule {
  final String name;
  final bool openTanyao, red, doubleYakuman, kazoe, kiriage;
  final int honba;
  Rule(
    this.name,
    this.openTanyao,
    this.red,
    this.doubleYakuman,
    this.kazoe,
    this.kiriage,
    this.honba,
  );
}

class Meld {
  final String kind;
  final Tiles tiles;
  final Block block;
  final bool valid;
  Meld(this.kind, this.tiles, this.block, this.valid);
}

class Situation {
  String label = '', by = '', seat = '', from = '', round = '';
  final Rule rule;
  Tiles hand = Tiles(),
      win = Tiles(),
      dora = Tiles(),
      ura = Tiles(),
      discards = Tiles();
  final List<Meld> melds = [];
  final Set<String> flags = {};
  int honba = 0, sticks = 0;
  bool notation = true;
  Situation(this.rule);
  bool get closed => melds.every((m) => m.kind == 'A');
  Tiles allTiles() => combineTiles([hand, win, ...melds.map((m) => m.tiles)]);
}

class Candidate {
  String kind = '', form = '', wait = '', category = 'none';
  int pair = 0,
      multiplier = 0,
      dora = 0,
      aka = 0,
      ura = 0,
      han = 0,
      fuTotal = 0,
      fu = 0,
      base = 0;
  List<Block> sets = [];
  final List<Block> blocks = [];
  List<Award> yaku = [], yakuman = [], fuItems = [];
}

int number(String s) => int.parse(s);
List<String> readLines(String path) => File(path).readAsLinesSync();
(String, Map<String, String>) readRecord(String line) {
  final a = line.split(' ');
  return (
    a[0],
    {
      for (final part in a.skip(1))
        part.substring(0, part.indexOf('=')): part.substring(
          part.indexOf('=') + 1,
        ),
    },
  );
}

int windKind(String wind) => 27 + 'ESWN'.indexOf(wind);
String checkCopies(Tiles tiles, Rule rule) {
  if (!rule.red && tiles.reds.any((n) => n > 0)) return 'red five not allowed';
  for (var kind = 0; kind < 34; kind++) {
    if (tiles.counts[kind] > 4) return 'too many copies of ${tileName(kind)}';
  }
  for (var suit = 0; suit < 3; suit++) {
    if (tiles.reds[suit] > 1) return 'too many copies of 0${'mps'[suit]}';
  }
  return '';
}

(Meld, bool) readMeld(String s) {
  final kind = s[0];
  final (tiles, ok) = parseTiles(s.substring(1), false);
  if (!ok) return (Meld(kind, Tiles(), Block(0), false), false);
  final kinds = [
        for (var k = 0; k < 34; k++)
          for (var j = 0; j < tiles.counts[k]; j++) k,
      ],
      size = tiles.tiles.length;
  var valid = false, sequence = false, kan = false;
  switch (kind) {
    case 'C':
      valid =
          size == 3 &&
          kinds[0] < 27 &&
          kinds[0] ~/ 9 == kinds[2] ~/ 9 &&
          kinds[1] == kinds[0] + 1 &&
          kinds[2] == kinds[0] + 2;
      sequence = true;
      break;
    case 'P':
      valid = size == 3 && kinds.first == kinds.last;
      break;
    case 'K':
    case 'A':
      valid = size == 4 && kinds.first == kinds.last;
      kan = true;
      break;
  }
  return (
    Meld(
      kind,
      tiles,
      Block(kinds[0], sequence: sequence, kan: kan, source: kind),
      valid,
    ),
    true,
  );
}

Situation readSituation(String label, Map<String, String> a, Rule rule) {
  final s = Situation(rule)
    ..label = label
    ..by = a['by']!
    ..seat = a['seat']!
    ..from = a['from']!
    ..round = a['round']!
    ..honba = number(a['honba']!)
    ..sticks = number(a['sticks']!);
  final parsed = <String, Tiles>{};
  for (final name in ['hand', 'win', 'dora', 'ura', 'discards']) {
    final (tiles, ok) = parseTiles(
      a[name]!,
      name == 'ura' || name == 'discards',
    );
    parsed[name] = tiles;
    s.notation = s.notation && ok;
  }
  s.hand = parsed['hand']!;
  s.win = parsed['win']!;
  s.dora = parsed['dora']!;
  s.ura = parsed['ura']!;
  s.discards = parsed['discards']!;
  if (a['melds'] != '-') {
    for (final part in a['melds']!.split(',')) {
      final (meld, valid) = readMeld(part);
      s.notation = s.notation && valid;
      s.melds.add(meld);
    }
  }
  if (a['flags'] != '-') s.flags.addAll(a['flags']!.split(','));
  return s;
}

String checkSituation(Situation s) {
  if (!s.notation || s.win.tiles.length != 1) return 'bad tile notation';
  if (s.melds.length > 4 || s.melds.any((m) => !m.valid)) return 'bad meld';
  final kans = s.melds.where((m) => m.block.kan).length;
  if (s.hand.tiles.length != 13 - 3 * s.melds.length) return 'wrong tile count';
  final copies = checkCopies(
    combineTiles([s.allTiles(), s.dora, s.ura, s.discards]),
    s.rule,
  );
  if (copies.isNotEmpty) return copies;
  if (s.by == 'tsumo' && s.from != '-' ||
      s.by == 'ron' && (s.from == '-' || s.from == s.seat))
    return 'invalid discarder';
  final riichi =
      s.flags.contains('riichi') || s.flags.contains('double_riichi');
  for (final flag in flagsOrder) {
    if (!s.flags.contains(flag)) continue;
    final valid = switch (flag) {
      'riichi' => s.closed,
      'double_riichi' => s.closed && !s.flags.contains('riichi'),
      'ippatsu' => riichi && !s.flags.contains('rinshan'),
      'haitei' => s.by == 'tsumo' && !s.flags.contains('rinshan'),
      'houtei' => s.by == 'ron' && !s.flags.contains('chankan'),
      'rinshan' => s.by == 'tsumo' && kans > 0,
      'chankan' => s.by == 'ron',
      'tenhou' =>
        s.seat == 'E' &&
            s.by == 'tsumo' &&
            s.melds.isEmpty &&
            s.flags.length == 1,
      'chiihou' =>
        s.seat != 'E' &&
            s.by == 'tsumo' &&
            s.melds.isEmpty &&
            s.flags.length == 1,
      _ => true,
    };
    if (!valid) return 'invalid flag $flag';
  }
  if (s.dora.tiles.length != 1 + kans) return 'invalid dora indicators';
  if (riichi && s.ura.tiles.length != s.dora.tiles.length ||
      !riichi && s.ura.tiles.isNotEmpty)
    return 'invalid ura indicators';
  if (riichi && s.sticks == 0) return 'invalid sticks';
  if (!winningForm(combineTiles([s.hand, s.win]).counts, s.melds.length))
    return 'not a winning hand';
  return '';
}

List<Candidate> makeCandidates(Situation s) {
  final counts = combineTiles([s.hand, s.win]).counts,
      win = s.win.tiles[0].kind,
      out = <Candidate>[];
  for (final decomposition in standardDecompositions(counts, s.melds.length)) {
    final seen = <String>{};
    for (var winning = -1; winning < decomposition.sets.length; winning++) {
      if (winning < 0) {
        if (decomposition.pair != win) continue;
      } else {
        final b = decomposition.sets[winning];
        if (b.sequence) {
          if (win < b.kind || win > b.kind + 2) continue;
        } else if (win != b.kind) {
          continue;
        }
      }
      final shape = winning < 0
          ? blockNotation(decomposition.pair, 2, false)
          : decomposition.sets[winning].notation();
      if (!seen.add(shape)) continue;
      final c = Candidate()
        ..kind = 'standard'
        ..pair = decomposition.pair
        ..wait = 'tanki'
        ..sets = [
          for (var i = 0; i < decomposition.sets.length; i++)
            i == winning ? decomposition.sets[i].won() : decomposition.sets[i],
        ];
      if (winning >= 0) c.wait = waitShape(c.sets[winning], win);
      var pair = blockNotation(c.pair, 2, false);
      if (winning < 0) pair += '*';
      final parts = [
        'standard',
        pair,
        for (final b in c.sets) '${b.notation()}${b.winning ? '*' : ''}',
      ];
      c.blocks.addAll(c.sets);
      for (final meld in s.melds) {
        parts.add('${meld.kind}${meld.block.notation()}');
        c.blocks.add(meld.block);
      }
      c.form = parts.join(' ');
      out.add(c);
    }
  }
  if (sevenPairs(counts, s.melds.length)) {
    final c = Candidate()
      ..kind = 'chiitoitsu'
      ..wait = 'tanki';
    c.form = [
      'chiitoitsu',
      for (var kind = 0; kind < 34; kind++)
        if (counts[kind] == 2)
          '${blockNotation(kind, 2, false)}${kind == win ? '*' : ''}',
    ].join(' ');
    out.add(c);
  }
  if (thirteenOrphans(counts, s.melds.length)) {
    final c = Candidate()
          ..kind = 'kokushi'
          ..wait = 'thirteen',
        parts = ['kokushi'];
    for (var kind = 0; kind < 34; kind++) {
      if (counts[kind] == 0) continue;
      parts.add(
        '${blockNotation(kind, counts[kind], false)}${kind == win ? '*' : ''}',
      );
      if (s.hand.counts[kind] != 1) c.wait = 'single';
    }
    c.form = parts.join(' ');
    out.add(c);
  }
  out.sort((a, b) => a.form.compareTo(b.form));
  for (final c in out) {
    evaluateCandidate(c, s);
  }
  return out;
}

int doraCount(Tiles indicators, List<int> counts) =>
    indicators.tiles.fold(0, (n, tile) => n + counts[nextDora(tile.kind)]);
void evaluateCandidate(Candidate c, Situation s) {
  final all = s.allTiles(),
      closed = s.closed,
      yaku = <String>{},
      yakuman = <String>{};
  void y(String name, bool condition) {
    if (condition) yaku.add(name);
  }

  void k(String name, bool condition) {
    if (condition) yakuman.add(name);
  }

  var allSimple = true,
      allYao = true,
      allHonor = true,
      allTerminal = true,
      allGreen = true,
      suitMask = 0,
      hasHonor = false;
  const green = {19, 20, 21, 23, 25, 32};
  for (var kind = 0; kind < 34; kind++) {
    if (all.counts[kind] == 0) continue;
    if (yaochuu(kind)) {
      allSimple = false;
    } else {
      allYao = false;
    }
    if (honor(kind)) {
      hasHonor = true;
    } else {
      allHonor = false;
      suitMask |= 1 << (kind ~/ 9);
    }
    if (!terminal(kind)) allTerminal = false;
    if (!green.contains(kind)) allGreen = false;
  }
  for (final name in [
    'riichi',
    'double_riichi',
    'ippatsu',
    'haitei',
    'houtei',
    'rinshan',
    'chankan',
  ]) {
    y(name, s.flags.contains(name));
  }
  y('menzen_tsumo', closed && s.by == 'tsumo');
  y('tanyao', allSimple && (closed || s.rule.openTanyao));
  y('honroutou', allYao);
  final oneSuit = suitMask != 0 && (suitMask & (suitMask - 1)) == 0;
  y('honitsu', oneSuit && hasHonor);
  y('chinitsu', oneSuit && !hasHonor);
  k('tenhou', s.flags.contains('tenhou'));
  k('chiihou', s.flags.contains('chiihou'));
  k('tsuuiisou', allHonor);
  k('chinroutou', allTerminal);
  k('ryuuiisou', allGreen);
  if (s.melds.isEmpty && oneSuit && !hasHonor) {
    var suit = 0;
    while (((suitMask >> suit) & 1) == 0) {
      suit++;
    }
    var chuuren = true, pure = true;
    for (var rank = 0; rank < 9; rank++) {
      final required = rank == 0 || rank == 8 ? 3 : 1;
      if (all.counts[suit * 9 + rank] < required) chuuren = false;
      if (s.hand.counts[suit * 9 + rank] != required) pure = false;
    }
    if (chuuren) yakuman.add(pure ? 'junsei_chuuren' : 'chuuren');
  }
  switch (c.kind) {
    case 'chiitoitsu':
      yaku.add('chiitoitsu');
      break;
    case 'kokushi':
      yakuman.add(c.wait == 'thirteen' ? 'kokushi_13' : 'kokushi');
      break;
    case 'standard':
      final triplets = <int>{}, sequences = <int>{};
      var concealedCount = 0,
          kans = 0,
          dragons = 0,
          winds = 0,
          allBlocksYao = yaochuu(c.pair);
      for (final b in c.blocks) {
        if (b.sequence) {
          sequences.add(b.kind);
          if (b.kind % 9 != 0 && b.kind % 9 != 6) allBlocksYao = false;
        } else {
          triplets.add(b.kind);
          if (concealed(b, s.by)) concealedCount++;
          if (b.kan) kans++;
          if (b.kind >= 31) {
            dragons++;
          } else if (b.kind >= 27) {
            winds++;
          }
          if (!yaochuu(b.kind)) allBlocksYao = false;
        }
      }
      final closedSequences = <int, int>{};
      var allSequences = c.sets.length == 4;
      for (final b in c.sets) {
        if (b.sequence) {
          closedSequences[b.kind] = (closedSequences[b.kind] ?? 0) + 1;
        } else {
          allSequences = false;
        }
      }
      var pairs = 0, hasDuplicate = false;
      for (final n in closedSequences.values) {
        pairs += n ~/ 2;
        if (n >= 2) hasDuplicate = true;
      }
      y(
        'pinfu',
        closed &&
            s.melds.isEmpty &&
            allSequences &&
            pairFu(c.pair, windKind(s.seat), windKind(s.round)) == 0 &&
            c.wait == 'ryanmen',
      );
      y('ryanpeikou', closed && allSequences && pairs == 2);
      y('iipeikou', closed && !yaku.contains('ryanpeikou') && hasDuplicate);
      y('haku', triplets.contains(31));
      y('hatsu', triplets.contains(32));
      y('chun', triplets.contains(33));
      y('jikaze', triplets.contains(windKind(s.seat)));
      y('bakaze', triplets.contains(windKind(s.round)));
      y('toitoi', triplets.length == 4);
      y('sanankou', concealedCount == 3);
      for (var rank = 0; rank < 9; rank++) {
        y(
          'sanshoku_doujun',
          rank <= 6 &&
              sequences.contains(rank) &&
              sequences.contains(9 + rank) &&
              sequences.contains(18 + rank),
        );
        y(
          'sanshoku_doukou',
          triplets.contains(rank) &&
              triplets.contains(9 + rank) &&
              triplets.contains(18 + rank),
        );
      }
      for (var suit = 0; suit < 3; suit++) {
        y(
          'ittsu',
          sequences.contains(suit * 9) &&
              sequences.contains(suit * 9 + 3) &&
              sequences.contains(suit * 9 + 6),
        );
      }
      if (sequences.isNotEmpty && allBlocksYao)
        yaku.add(hasHonor ? 'chanta' : 'junchan');
      y('sankantsu', kans == 3);
      y('shousangen', dragons == 2 && c.pair >= 31);
      if (concealedCount == 4)
        yakuman.add(c.wait == 'tanki' ? 'suuankou_tanki' : 'suuankou');
      k('daisangen', dragons == 3);
      k('daisuushii', winds == 4);
      k('shousuushii', winds == 3 && c.pair >= 27 && c.pair <= 30);
      k('suukantsu', kans == 4);
      break;
  }
  c.yakuman = yakumanAwards(yakuman, s.rule.doubleYakuman);
  if (c.yakuman.isNotEmpty) {
    c.multiplier = c.yakuman.fold(0, (n, a) => n + a.value);
    c.category = 'yakuman';
    c.base = 8000 * c.multiplier;
    return;
  }
  c.yaku = yakuAwards(yaku, closed);
  c.dora = doraCount(s.dora, all.counts);
  c.ura = doraCount(s.ura, all.counts);
  c.aka = all.reds.fold(0, (a, b) => a + b);
  c.han = c.dora + c.ura + c.aka + c.yaku.fold(0, (n, a) => n + a.value);
  final (items, total, fu) = fuBreakdown(c, s, closed, yaku.contains('pinfu'));
  c.fuItems = items;
  c.fuTotal = total;
  c.fu = fu;
  if (c.yaku.isNotEmpty) {
    final (category, base) = limitScore(c.han, c.fu, s.rule);
    c.category = category;
    c.base = base;
  }
}

Candidate? bestCandidate(List<Candidate> candidates) {
  Candidate? best;
  for (final c in candidates) {
    if (c.base <= 0) continue;
    var better = best == null;
    if (best != null) {
      if (c.base != best.base) {
        better = c.base > best.base;
      } else if ((c.multiplier > 0) != (best.multiplier > 0)) {
        better = c.multiplier > 0;
      } else if (c.multiplier == 0 && c.han != best.han) {
        better = c.han > best.han;
      } else if (c.multiplier == 0 && c.fu != best.fu) {
        better = c.fu > best.fu;
      } else {
        better = c.form.compareTo(best.form) < 0;
      }
    }
    if (better) best = c;
  }
  return best;
}

String awardNames(List<Award> a, String separator) =>
    a.map((v) => v.name).join(separator);
String candidateText(Candidate c) => c.multiplier > 0
    ? 'yakuman ${c.multiplier} base ${c.base} yaku ${awardNames(c.yakuman, ',')}'
    : c.base == 0
    ? 'no_yaku'
    : 'han ${c.han} fu ${c.fu} base ${c.base} yaku ${awardNames(c.yaku, ',')}';
bool discardedWait(Tiles discards, List<int> waits) =>
    waits.any((kind) => discards.counts[kind] > 0);

class HandStats {
  int hands = 0,
      wins = 0,
      furiten = 0,
      noYaku = 0,
      errors = 0,
      totalPoints = 0,
      maxPoints = 0;
  String maxHand = '-';
  final Map<String, int> winsBy = {}, waits = {}, limits = {}, yaku = {};
  final Map<int, int> han = {}, fu = {};
  final Map<String, List<int>> rules = {};
  List<String> lines(List<Rule> rules) {
    final out = [
      'STATS hands $hands wins $wins furiten $furiten no_yaku $noYaku errors $errors',
      'WINS dealer_ron ${winsBy['dealer_ron'] ?? 0} dealer_tsumo ${winsBy['dealer_tsumo'] ?? 0} nondealer_ron ${winsBy['nondealer_ron'] ?? 0} nondealer_tsumo ${winsBy['nondealer_tsumo'] ?? 0}',
      'WAIT_COUNT ${[for (final shape in waitShapes) '$shape ${waits[shape] ?? 0}'].join(' ')}',
    ];
    for (final h in han.keys.toList()..sort()) {
      out.add('HAN_COUNT $h ${han[h]}');
    }
    for (final f in fu.keys.toList()..sort()) {
      out.add('FU_COUNT $f ${fu[f]}');
    }
    for (final category in categories) {
      out.add('LIMIT $category ${limits[category] ?? 0}');
    }
    for (final name in [
      ...yakuTable.map((y) => y.$1),
      ...yakumanTable.map((y) => y.$1),
    ]) {
      if ((yaku[name] ?? 0) > 0) out.add('YAKU_COUNT $name ${yaku[name]}');
    }
    out.add('POINTS total $totalPoints max $maxPoints hand $maxHand');
    for (final rule in rules) {
      final values = this.rules[rule.name] ?? [0, 0, 0];
      out.add(
        'RULE ${rule.name} hands ${values[0]} wins ${values[1]} points ${values[2]}',
      );
    }
    return out;
  }
}

void increment<K>(Map<K, int> map, K key) {
  map[key] = (map[key] ?? 0) + 1;
}

String tileList(List<int> kinds) => kinds.map(tileName).join(' ');
String signed(int n) => n > 0 ? '+$n' : '$n';
(List<String>, String) outputHand(Situation s, HandStats stats) {
  final out = ['HAND ${s.label}'];
  stats.hands++;
  final ruleStats = stats.rules.putIfAbsent(s.rule.name, () => [0, 0, 0]);
  ruleStats[0]++;
  final errorText = checkSituation(s);
  if (errorText.isNotEmpty) {
    stats.errors++;
    out.add('ERROR $errorText');
    return (out, '${s.label},-,-,0,ERROR');
  }
  final waits = waitingTiles(s.hand, s.melds);
  out.add('WAITS ${tileList(waits)}');
  final candidates = makeCandidates(s);
  for (final candidate in candidates) {
    out.add(
      'CANDIDATE ${candidate.form} = ${candidate.wait} ${candidateText(candidate)}',
    );
  }
  if (s.by == 'ron' && discardedWait(s.discards, waits)) {
    stats.furiten++;
    out.add('RESULT furiten');
    return (out, '${s.label},-,-,0,FURITEN');
  }
  final best = bestCandidate(candidates);
  if (best == null) {
    stats.noYaku++;
    out.add('RESULT no_yaku');
    return (out, '${s.label},-,-,0,NO_YAKU');
  }
  stats.wins++;
  increment(stats.winsBy, '${s.seat == 'E' ? 'dealer' : 'nondealer'}_${s.by}');
  increment(stats.waits, best.wait);
  increment(stats.limits, best.category);
  out.addAll(['FORM ${best.form}', 'WAIT ${best.wait}']);
  final payment = payments(best.base, s.seat, s.by);
  late String summary;
  if (best.multiplier > 0) {
    for (final a in best.yakuman) {
      out.add('YAKUMAN ${a.name} ${a.value}');
      increment(stats.yaku, a.name);
    }
    out.add('SCORE yakuman ${best.multiplier} base ${best.base}');
    summary =
        '${s.label},Y${best.multiplier},-,${payment.points},${awardNames(best.yakuman, ';')}';
  } else {
    increment(stats.han, best.han);
    increment(stats.fu, best.fu);
    for (final a in best.yaku) {
      out.add('YAKU ${a.name} ${a.value}');
      increment(stats.yaku, a.name);
    }
    out.add('DORA dora ${best.dora} aka ${best.aka} ura ${best.ura}');
    for (final a in best.fuItems) {
      out.add('FU ${a.name} ${a.value}');
    }
    out.addAll([
      'FU total ${best.fuTotal} ${best.fu}',
      'SCORE han ${best.han} fu ${best.fu} limit ${best.category} base ${best.base}',
    ]);
    summary =
        '${s.label},${best.han},${best.fu},${payment.points},${awardNames(best.yaku, ';')}';
  }
  out.add(
    s.by == 'ron'
        ? 'PAY ron ${payment.ron}'
        : s.seat == 'E'
        ? 'PAY tsumo all ${payment.all}'
        : 'PAY tsumo dealer ${payment.dealer} nondealer ${payment.nondealer}',
  );
  final honba = s.honba * s.rule.honba,
      sticks = s.sticks * 1000,
      gain = payment.points + honba + sticks,
      delta = List.filled(4, 0),
      winner = 'ESWN'.indexOf(s.seat);
  out.addAll([
    'BONUS honba $honba sticks $sticks',
    'TOTAL points ${payment.points} gain $gain',
  ]);
  delta[winner] = gain;
  if (s.by == 'ron') {
    delta['ESWN'.indexOf(s.from)] = -(payment.ron + honba);
  } else {
    for (var player = 0; player < 4; player++) {
      if (player == winner) continue;
      final pay = s.seat == 'E'
          ? payment.all
          : player == 0
          ? payment.dealer
          : payment.nondealer;
      delta[player] = -(pay + honba ~/ 3);
    }
  }
  out.add(
    'DELTA E ${signed(delta[0])} S ${signed(delta[1])} W ${signed(delta[2])} N ${signed(delta[3])}',
  );
  stats.totalPoints += payment.points;
  if (payment.points > stats.maxPoints) {
    stats.maxPoints = payment.points;
    stats.maxHand = s.label;
  }
  ruleStats[1]++;
  ruleStats[2] += payment.points;
  return (out, summary);
}

class WaitStats {
  int hands = 0, errors = 0, tenpai = 0, furiten = 0;
  final shanten = List.filled(7, 0);
  List<String> lines() => [
    'STATS hands $hands errors $errors tenpai $tenpai furiten $furiten',
    for (var n = 0; n < 7; n++) 'SHANTEN_COUNT $n ${shanten[n]}',
  ];
}

List<String> analyzeWait(
  String label,
  Map<String, String> a,
  Rule rule,
  WaitStats stats,
) {
  final out = ['HAND $label'];
  stats.hands++;
  final (hand, handOK) = parseTiles(a['hand']!, false);
  final (dora, doraOK) = parseTiles(a['dora']!, false);
  final (discards, discardsOK) = parseTiles(a['discards']!, true);
  final (visible, visibleOK) = parseTiles(a['visible']!, true);
  var errorText = '';
  if (!handOK || !doraOK || !discardsOK || !visibleOK) {
    errorText = 'bad tile notation';
  } else if (hand.tiles.length != 13) {
    errorText = 'wrong tile count';
  } else {
    errorText = checkCopies(
      combineTiles([hand, dora, discards, visible]),
      rule,
    );
  }
  if (errorText.isNotEmpty) {
    stats.errors++;
    out.add('ERROR $errorText');
    return out;
  }
  final analyzer = Shanten(),
      numbers = analyzer.numbers(hand.counts),
      shanten = minimumShanten(numbers);
  stats.shanten[shanten]++;
  out.add(
    'SHANTEN standard ${numbers[0]} chiitoitsu ${numbers[1]} kokushi ${numbers[2]}',
  );
  final all = combineTiles([hand, dora, discards, visible]),
      accept = <int>[],
      left = <int>[];
  var remaining = 0;
  for (var kind = 0; kind < 34; kind++) {
    if (hand.counts[kind] >= 4) continue;
    final counts = List<int>.of(hand.counts);
    counts[kind]++;
    if (minimumShanten(analyzer.numbers(counts)) < shanten) {
      accept.add(kind);
      final count = 4 - all.counts[kind];
      left.add(count);
      remaining += count;
    }
  }
  if (shanten > 0) {
    out.add(
      'ACCEPT kinds ${accept.length} tiles $remaining${[for (var i = 0; i < accept.length; i++) ' ${tileName(accept[i])}:${left[i]}'].join()}',
    );
    return out;
  }
  stats.tenpai++;
  final furiten = discardedWait(discards, accept);
  if (furiten) stats.furiten++;
  out.add(
    'TENPAI kinds ${accept.length} tiles $remaining furiten ${furiten ? 'yes' : 'no'}',
  );
  var bestRon = 'none', bestTsumo = 'none', ronPoints = 0, tsumoPoints = 0;
  for (var i = 0; i < accept.length; i++) {
    final kind = accept[i], values = List.filled(2, '');
    for (var method = 0; method < 2; method++) {
      if (method == 0 && furiten) {
        values[method] = 'furiten';
        continue;
      }
      final by = method == 0 ? 'ron' : 'tsumo', win = Tiles();
      win.tiles.add(Tile(kind));
      win.counts[kind] = 1;
      final s = Situation(rule)
        ..hand = hand
        ..win = win
        ..dora = dora
        ..by = by
        ..seat = a['seat']!
        ..round = a['round']!;
      if (a['riichi'] == 'yes') s.flags.add('riichi');
      final best = bestCandidate(makeCandidates(s));
      if (best == null) {
        values[method] = 'no_yaku';
        continue;
      }
      final points = payments(best.base, s.seat, by).points;
      values[method] = '$points';
      if (method == 0 && points > ronPoints) {
        ronPoints = points;
        bestRon = '${tileName(kind)} $points';
      }
      if (method == 1 && points > tsumoPoints) {
        tsumoPoints = points;
        bestTsumo = '${tileName(kind)} $points';
      }
    }
    out.add(
      'WAIT ${tileName(kind)} left ${left[i]} ron ${values[0]} tsumo ${values[1]}',
    );
  }
  out.add('BEST ron $bestRon tsumo $bestTsumo');
  return out;
}

void writeLines(String name, List<String> lines) {
  File('output/$name').writeAsStringSync('${lines.join('\n')}\n');
}

void main() {
  final rules = <Rule>[], byName = <String, Rule>{};
  for (final line in readLines('input/rules.txt')) {
    final (label, a) = readRecord(line);
    final rule = Rule(
      label,
      a['open_tanyao'] == 'yes',
      a['red_fives'] == 'yes',
      a['double_yakuman'] == 'yes',
      a['kazoe_yakuman'] == 'yes',
      a['kiriage'] == 'yes',
      number(a['honba']!),
    );
    rules.add(rule);
    byName[label] = rule;
  }
  final stats = HandStats(),
      scores = <String>[],
      waits = <String>[],
      summary = ['hand,han,fu,points,yaku'];
  for (final line in readLines('input/hands.txt')) {
    final (label, a) = readRecord(line);
    final (out, row) = outputHand(
      readSituation(label, a, byName[a['rules']]!),
      stats,
    );
    scores.addAll(out);
    summary.add(row);
  }
  scores.addAll(stats.lines(rules));
  final waitStats = WaitStats();
  for (final line in readLines('input/waits.txt')) {
    final (label, a) = readRecord(line);
    waits.addAll(analyzeWait(label, a, byName[a['rules']]!, waitStats));
  }
  waits.addAll(waitStats.lines());
  Directory('output').createSync(recursive: true);
  writeLines('scores.txt', scores);
  writeLines('waits.txt', waits);
  writeLines('summary.csv', summary);
}
