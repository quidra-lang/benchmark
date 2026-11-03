import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;

final class CommandError implements Exception {
  final String message;
  const CommandError(this.message);
  @override
  String toString() => 'ERROR $message';
}

enum MarketKind { twoSided, roommates, housing }

final class Market {
  final String name;
  final MarketKind kind;
  final List<String> agents;
  final int proposerCount;
  final List<String> houses;
  final List<List<int>> preferences;
  final List<int> capacities;
  List<int>? current;
  String source = '-';

  Market(this.name, this.kind, this.agents, {this.proposerCount = 0, List<String>? houses})
      : houses = houses ?? [],
        preferences = List.generate(agents.length, (_) => []),
        capacities = List.filled(agents.length, 1);

  int get count => agents.length;
  Iterable<int> get proposers => Iterable<int>.generate(proposerCount);
  Iterable<int> get receivers => Iterable<int>.generate(count - proposerCount, (i) => proposerCount + i);
  int agent(String text) {
    final index = agents.indexOf(text);
    if (index < 0) throw CommandError('UNKNOWN AGENT $text');
    return index;
  }
  int proposer(String text) {
    final index = agent(text);
    if (index >= proposerCount) throw CommandError('NOT PROPOSER $text');
    return index;
  }
  int receiver(String text) {
    final index = agent(text);
    if (index < proposerCount) throw CommandError('NOT RECEIVER $text');
    return index;
  }
  int choice(int agent, String text) {
    final index = (kind == MarketKind.housing ? houses : agents).indexOf(text);
    final valid = index >= 0 && (switch (kind) {
      MarketKind.twoSided => (agent < proposerCount) != (index < proposerCount),
      MarketKind.roommates => agent != index,
      MarketKind.housing => true,
    });
    if (!valid) throw CommandError('BAD CHOICE $text');
    return index;
  }
  void clearMatching() { current = null; source = '-'; }
  void setMatching(List<int> partners, String command) {
    current = List.of(partners);
    source = command;
  }
  String partner(int index) => index < 0 ? '*' : agents[index];
  String pairs(List<int> partners) => proposers.map((p) => '${agents[p]}-${partner(partners[p])}').join(' ');
  String allocation(List<int> assigned) => Iterable.generate(count, (a) =>
      '${agents[a]}-${assigned[a] < 0 ? '*' : houses[assigned[a]]}').join(' ');
  List<int> effective(int agent) {
    final list = preferences[agent];
    final own = list.indexOf(agent);
    return own < 0 ? [...list, agent] : list.sublist(0, own + 1);
  }
}

final class MatchingResult {
  final List<int> partners;
  final int proposals;
  final List<String> log;
  const MatchingResult(this.partners, this.proposals, this.log);
}
final class Candidate {
  final List<int> partners;
  final int origin;
  final int via;
  final int cost;
  final int regret;
  const Candidate(this.partners, this.origin, this.via, this.cost, this.regret);
}
final class Enumeration {
  final List<Candidate> matchings;
  final List<String> rotations;
  const Enumeration(this.matchings, this.rotations);
}

int rank(List<int> preference, int partner) {
  final index = preference.indexOf(partner);
  return index < 0 ? preference.length + 1 : index + 1;
}
bool equalLists(List<int> first, List<int> second) => first.length == second.length &&
    Iterable<int>.generate(first.length).every((i) => first[i] == second[i]);
String listText(Iterable<String> values) => values.isEmpty ? '-' : values.join(' ');

MatchingResult deferred(Market market, {bool reverse = false, bool verbose = false, List<List<int>>? preferences}) {
  final lists = preferences ?? market.preferences;
  final next = List.filled(market.count, 0), counts = List.filled(market.count, 0);
  final queued = List.filled(market.count, false);
  final holding = List.generate(market.count, (_) => <int>[]);
  final queue = Queue<int>();
  bool able(int agent) => counts[agent] < market.capacities[agent] && next[agent] < lists[agent].length;
  void enqueue(int agent) {
    if (able(agent) && !queued[agent]) { queue.addLast(agent); queued[agent] = true; }
  }
  for (final agent in reverse ? market.receivers : market.proposers) { enqueue(agent); }
  var proposals = 0;
  final log = <String>[];
  while (queue.isNotEmpty) {
    final x = queue.removeFirst();
    queued[x] = false;
    final y = lists[x][next[x]++];
    proposals++;
    var action = 'REJECT';
    if (lists[y].contains(x)) {
      if (holding[y].length < market.capacities[y]) {
        holding[y].add(x); counts[x]++;
        action = 'HOLD';
      } else {
        var worst = 0;
        for (var i = 1; i < holding[y].length; i++) {
          if (rank(lists[y], holding[y][i]) > rank(lists[y], holding[y][worst])) worst = i;
        }
        final rejected = holding[y][worst];
        if (rank(lists[y], x) < rank(lists[y], rejected)) {
          holding[y][worst] = x;
          counts[rejected]--; counts[x]++;
          action = 'HOLD REJECT ${market.agents[rejected]}';
          enqueue(rejected);
        }
      }
    }
    if (verbose) log.add('PROPOSE ${market.agents[x]} ${market.agents[y]} $action');
    enqueue(x);
  }
  final partners = List.filled(market.proposerCount, -1);
  for (final y in reverse ? market.proposers : market.receivers) {
    for (final x in holding[y]) { partners[reverse ? y : x] = reverse ? x : y; }
  }
  return MatchingResult(partners, proposals, log);
}

MatchingResult boston(Market market, {List<List<int>>? preferences}) {
  final lists = preferences ?? market.preferences;
  final partners = List.filled(market.proposerCount, -1);
  final remaining = List.of(market.capacities);
  final rounds = market.proposers.map((p) => lists[p].length).reduce(math.max);
  var applications = 0;
  for (var round = 0; round < rounds; round++) {
    final applicants = List.generate(market.count, (_) => <int>[]);
    for (final p in market.proposers) {
      if (partners[p] >= 0 || round >= lists[p].length) continue;
      applicants[lists[p][round]].add(p);
      applications++;
    }
    for (final r in market.receivers) {
      applicants[r].sort((a, b) => rank(lists[r], a).compareTo(rank(lists[r], b)));
      for (final p in applicants[r]) {
        if (remaining[r] == 0 || !lists[r].contains(p)) continue;
        partners[p] = r; remaining[r]--;
      }
    }
  }
  return MatchingResult(partners, applications, []);
}

List<int> residents(Market market, List<int> partners, int receiver) =>
    market.proposers.where((p) => partners[p] == receiver).toList();

({List<(int, int)> unacceptable, List<(int, int)> blocking}) checkMatching(Market market, List<int> partners) {
  final unacceptable = <(int, int)>[], blocking = <(int, int)>[];
  final lists = market.preferences;
  bool acceptable(int a, int b) => lists[a].contains(b) && lists[b].contains(a);
  if (market.kind == MarketKind.roommates) {
    for (var a = 0; a < market.count; a++) {
      for (var b = a + 1; b < market.count; b++) {
        if (partners[a] == b) {
          if (!acceptable(a, b)) unacceptable.add((a, b));
        } else if (acceptable(a, b) && rank(lists[a], b) < rank(lists[a], partners[a]) &&
            rank(lists[b], a) < rank(lists[b], partners[b])) {
          blocking.add((a, b));
        }
      }
    }
  } else {
    for (final p in market.proposers) {
      if (partners[p] >= 0 && !acceptable(p, partners[p])) unacceptable.add((p, partners[p]));
      for (final r in market.receivers) {
        if (partners[p] == r || !acceptable(p, r) || rank(lists[p], r) >= rank(lists[p], partners[p])) continue;
        final held = residents(market, partners, r);
        if (held.length < market.capacities[r] || rank(lists[r], p) < held.map((a) => rank(lists[r], a)).reduce(math.max)) {
          blocking.add((p, r));
        }
      }
    }
  }
  return (unacceptable: unacceptable, blocking: blocking);
}

Candidate candidateFor(Market market, List<int> partners, int origin, int via) {
  var cost = 0, regret = 0;
  for (final p in market.proposers) {
    final r = partners[p];
    if (r < 0) continue;
    final a = rank(market.preferences[p], r), b = rank(market.preferences[r], p);
    cost += a + b;
    regret = math.max(regret, math.max(a, b));
  }
  return Candidate(partners, origin, via, cost, regret);
}

List<List<int>> rotations(Market market, List<int> partners) {
  final owners = List.filled(market.count, -1), successors = List.filled(market.proposerCount, -1);
  for (final p in market.proposers) { if (partners[p] >= 0) owners[partners[p]] = p; }
  for (final p in market.proposers) {
    if (partners[p] < 0) continue;
    final preference = market.preferences[p];
    for (var i = preference.indexOf(partners[p]) + 1; i < preference.length; i++) {
      final r = preference[i], owner = owners[r];
      if (market.preferences[r].contains(p) &&
          (owner < 0 || rank(market.preferences[r], p) < rank(market.preferences[r], owner))) {
        successors[p] = owner;
        break;
      }
    }
  }
  final result = <List<int>>[];
  final covered = List.filled(market.proposerCount, false);
  for (final start in market.proposers) {
    if (covered[start]) continue;
    final path = <int>[], seen = <int>{};
    var current = start;
    while (current >= 0 && seen.add(current)) { path.add(current); current = successors[current]; }
    if (current != start) continue;
    result.add(path);
    for (final p in path) { covered[p] = true; }
  }
  return result;
}

Enumeration enumerate(Market market) {
  if (market.receivers.any((r) => market.capacities[r] != 1)) throw const CommandError('NOT ONE TO ONE');
  final matchings = [candidateFor(market, deferred(market).partners, 0, 0)];
  final notations = <String>[], numbers = <String, int>{};
  for (var index = 0; index < matchings.length; index++) {
    final partners = matchings[index].partners;
    for (final rotation in rotations(market, partners)) {
      final notation = rotation.map((p) => '${market.agents[p]}-${market.agents[partners[p]]}').join(' ');
      final number = numbers.putIfAbsent(notation, () { notations.add(notation); return notations.length; });
      final next = List.of(partners);
      for (var i = 0; i < rotation.length; i++) { next[rotation[i]] = partners[rotation[(i + 1) % rotation.length]]; }
      if (matchings.any((candidate) => equalLists(candidate.partners, next))) continue;
      if (matchings.length == 50) throw const CommandError('TOO MANY MATCHINGS');
      matchings.add(candidateFor(market, next, index + 1, number));
    }
  }
  return Enumeration(matchings, notations);
}

List<String> roommates(Market market, bool verbose) {
  for (var a = 0; a < market.count; a++) {
    if (market.preferences[a].length != market.count - 1) throw CommandError('INCOMPLETE ${market.agents[a]}');
  }
  final lists = market.preferences.map((list) => List<int>.of(list)).toList();
  final held = List.filled(market.count, -1);
  final queue = Queue<int>.of(Iterable<int>.generate(market.count));
  final trace = <String>[];
  var proposals = 0, failure = -1, rotationCount = 0;
  void remove(int a, int b) { lists[a].remove(b); lists[b].remove(a); }
  void table() {
    for (var a = 0; a < market.count; a++) {
      trace.add('TABLE ${market.agents[a]} ${listText(lists[a].map((b) => market.agents[b]))}');
    }
  }
  int empty() => lists.indexWhere((list) => list.isEmpty);
  while (queue.isNotEmpty) {
    final x = queue.removeFirst(), y = lists[x].first;
    proposals++;
    if (held[y] >= 0) queue.addLast(held[y]);
    held[y] = x;
    final removed = lists[y].sublist(lists[y].indexOf(x) + 1);
    for (final w in removed) { remove(y, w); }
    failure = empty();
    if (failure >= 0) break;
  }
  if (failure < 0) {
    if (verbose) table();
    while (lists.any((list) => list.length > 1)) {
      var p = lists.indexWhere((list) => list.length > 1);
      final seen = List.filled(market.count, -1), path = <int>[];
      while (seen[p] < 0) {
        seen[p] = path.length; path.add(p);
        final q = lists[p][1];
        p = lists[q].last;
      }
      final xs = path.sublist(seen[p]);
      final ys = xs.map((x) => lists[x].first).toList();
      rotationCount++;
      trace.add('ROTATION $rotationCount ${Iterable.generate(xs.length, (i) => '${market.agents[xs[i]]}-${market.agents[ys[i]]}').join(' ')}');
      final removals = <(int, int)>[];
      for (var i = 0; i < xs.length; i++) {
        final u = ys[(i + 1) % ys.length];
        for (final w in lists[u].skip(lists[u].indexOf(xs[i]) + 1)) { removals.add((u, w)); }
      }
      for (final (a, b) in removals) { remove(a, b); }
      if (verbose) table();
      failure = empty();
      if (failure >= 0) break;
    }
  }
  final output = ['ROOMMATES ${market.name} proposals=$proposals', ...trace];
  if (failure >= 0) {
    output.add('NO STABLE MATCHING ${market.agents[failure]}');
  } else {
    final pairs = Iterable<int>.generate(market.count).where((a) => a < lists[a].first)
        .map((a) => '${market.agents[a]}-${market.agents[lists[a].first]}');
    output.add('MATCHING ${pairs.join(' ')}');
  }
  return output;
}

List<String> tradingCycles(Market market) {
  final remaining = List.filled(market.count, true);
  final effective = List.generate(market.count, market.effective);
  final assigned = List.filled(market.count, -1);
  final cycles = <String>[];
  while (remaining.any((value) => value)) {
    final pointers = List.filled(market.count, -1);
    for (var a = 0; a < market.count; a++) {
      if (remaining[a]) pointers[a] = effective[a].firstWhere((house) => remaining[house]);
    }
    final seen = List.filled(market.count, -1), path = <int>[];
    var current = remaining.indexOf(true);
    while (seen[current] < 0) {
      seen[current] = path.length; path.add(current); current = pointers[current];
    }
    final cycle = path.sublist(seen[current]);
    for (final a in cycle) { assigned[a] = pointers[a]; remaining[a] = false; }
    cycles.add('CYCLE ${cycles.length + 1} ${cycle.map((a) => '${market.agents[a]}:${market.houses[assigned[a]]}').join(' ')}');
  }
  return ['TTC ${market.name} cycles=${cycles.length}', ...cycles, 'ALLOCATION ${market.allocation(assigned)}'];
}

String rankSummary(List<int> ranks) {
  final total = ranks.fold(0, (sum, rank) => sum + rank);
  var average = '-', truncated = '-';
  if (ranks.isNotEmpty) {
    final divisor = total.gcd(ranks.length), cents = total * 100 ~/ ranks.length;
    average = '${total ~/ divisor}/${ranks.length ~/ divisor}';
    truncated = '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';
  }
  return 'sum=$total average=$average truncated=$truncated first=${ranks.where((rank) => rank == 1).length}';
}

final class Lab {
  final Map<String, Market> markets = {};

  Market get(String name, [MarketKind? kind]) {
    final market = markets[name];
    if (market == null) throw CommandError('UNKNOWN MARKET $name');
    if (kind != null && market.kind != kind) throw CommandError('WRONG TYPE $name');
    return market;
  }
  void newName(String name) {
    if (markets.containsKey(name)) throw CommandError('DUPLICATE MARKET $name');
  }
  void distinctAgents(Iterable<String> agents) {
    final seen = <String>{};
    for (final agent in agents) {
      if (!seen.add(agent)) throw CommandError('DUPLICATE AGENT $agent');
    }
  }
  List<String> show(Market market) {
    String preference(int agent) => listText(market.preferences[agent]
        .map((choice) => market.kind == MarketKind.housing ? market.houses[choice] : market.agents[choice]));
    final output = <String>[];
    if (market.kind == MarketKind.twoSided) {
      output.add('SHOW ${market.name} MARKET proposers=${market.proposerCount} receivers=${market.count - market.proposerCount}');
      for (final p in market.proposers) { output.add('PROPOSER ${market.agents[p]} ${preference(p)}'); }
      for (final r in market.receivers) { output.add('RECEIVER ${market.agents[r]} cap=${market.capacities[r]} ${preference(r)}'); }
      output.add('CURRENT ${market.source}');
    } else {
      output.add('SHOW ${market.name} ${market.kind == MarketKind.roommates ? 'ROOMS' : 'HOUSES'} agents=${market.count}');
      for (var a = 0; a < market.count; a++) {
        final house = market.kind == MarketKind.housing ? 'house=${market.houses[a]} ' : '';
        output.add('AGENT ${market.agents[a]} $house${preference(a)}');
      }
    }
    return output;
  }
  List<String> check(Market market, List<String> words) {
    if (market.kind == MarketKind.housing) throw CommandError('WRONG TYPE ${market.name}');
    final partners = List.filled(market.kind == MarketKind.twoSided ? market.proposerCount : market.count, -1);
    final used = List.filled(market.count, false), counts = List.filled(market.count, 0);
    for (final word in words.skip(2)) {
      final pair = word.split('-');
      if (market.kind == MarketKind.twoSided) {
        final p = market.proposer(pair[0]);
        final r = market.receiver(pair[1]);
        if (used[p]) throw CommandError('DUPLICATE AGENT ${pair[0]}');
        if (counts[r] + 1 > market.capacities[r]) throw CommandError('OVER CAPACITY ${pair[1]}');
        used[p] = true; counts[r]++; partners[p] = r;
      } else {
        final a = market.agent(pair[0]);
        final b = market.agent(pair[1]);
        if (used[a]) throw CommandError('DUPLICATE AGENT ${pair[0]}');
        if (a == b || used[b]) throw CommandError('DUPLICATE AGENT ${pair[1]}');
        used[a] = used[b] = true; partners[a] = b; partners[b] = a;
      }
    }
    final result = checkMatching(market, partners);
    if (result.unacceptable.isEmpty && result.blocking.isEmpty) return ['CHECK ${market.name} STABLE'];
    return [
      'CHECK ${market.name} UNSTABLE unacceptable=${result.unacceptable.length} blocking=${result.blocking.length}',
      for (final (p, r) in result.unacceptable) 'UNACCEPTABLE ${market.agents[p]} ${market.agents[r]}',
      for (final (p, r) in result.blocking) 'BLOCKING ${market.agents[p]} ${market.agents[r]}',
    ];
  }
  List<String> hospitals(Market market) {
    final a = deferred(market).partners, h = deferred(market, reverse: true).partners;
    final output = [
      'HR ${market.name} residents=${market.proposerCount} hospitals=${market.count - market.proposerCount}',
      'RESIDENT-OPTIMAL ${market.pairs(a)}', 'HOSPITAL-OPTIMAL ${market.pairs(h)}',
      'UNMATCHED ${listText(market.proposers.where((p) => a[p] < 0).map((p) => market.agents[p]))}',
    ];
    var rural = market.proposers.every((p) => (a[p] >= 0) == (h[p] >= 0));
    for (final r in market.receivers) {
      final first = residents(market, a, r), second = residents(market, h, r);
      final same = equalLists(first, second);
      output.add('HOSPITAL ${market.agents[r]} cap=${market.capacities[r]} resident=${first.length} hospital=${second.length} same=${same ? 'YES' : 'NO'}');
      rural = rural && first.length == second.length && (first.length == market.capacities[r] || same);
    }
    output.add(rural ? 'RURAL HOLDS' : 'RURAL FAILS');
    return output;
  }
  List<String> serial(Market market, List<String> words) {
    final order = <int>[], seen = <int>{};
    for (final name in words.skip(2)) {
      final agent = market.agent(name);
      if (!seen.add(agent)) throw CommandError('DUPLICATE AGENT $name');
      order.add(agent);
    }
    if (order.length != market.count) throw const CommandError('BAD ORDER');
    final assigned = List.filled(market.count, -1), available = List.filled(market.count, true);
    for (final a in order) {
      for (final house in market.preferences[a]) {
        if (available[house]) { assigned[a] = house; available[house] = false; break; }
      }
    }
    final worse = <String>[];
    for (var a = 0; a < market.count; a++) {
      if (assigned[a] < 0 || !market.effective(a).contains(assigned[a])) worse.add(market.agents[a]);
    }
    return ['SERIAL ${market.name} assigned=${assigned.where((h) => h >= 0).length}',
      'ALLOCATION ${market.allocation(assigned)}', 'WORSE ${listText(worse)}'];
  }
  List<String> manipulate(Market market, int agent) {
    final truth = market.preferences[agent];
    final b0 = boston(market).partners[agent], g0 = deferred(market).partners[agent];
    final output = ['MANIPULATE ${market.name} ${market.agents[agent]} boston=${market.partner(b0)} gs=${market.partner(g0)} swaps=${math.max(0, truth.length - 1)}'];
    for (var i = 0; i + 1 < truth.length; i++) {
      final preferences = List.of(market.preferences);
      preferences[agent] = List.of(truth);
      final first = preferences[agent][i];
      preferences[agent][i] = preferences[agent][i + 1];
      preferences[agent][i + 1] = first;
      final b = boston(market, preferences: preferences).partners[agent];
      final g = deferred(market, preferences: preferences).partners[agent];
      final swap = '${i + 1} ${market.agents[truth[i]]} ${market.agents[truth[i + 1]]}';
      if (rank(truth, b) < rank(truth, b0)) output.add('IMPROVE BOSTON $swap result=${market.partner(b)}');
      if (rank(truth, g) < rank(truth, g0)) output.add('IMPROVE GS $swap result=${market.partner(g)}');
    }
    if (output.length == 1) output.add('NO IMPROVEMENT');
    return output;
  }
  List<String> stats(Market market) {
    final partners = market.current;
    if (partners == null) throw const CommandError('NO MATCHING');
    final proposerRanks = <int>[], receiverRanks = <int>[], occupied = <int>{};
    for (final p in market.proposers) {
      final r = partners[p];
      if (r < 0) continue;
      proposerRanks.add(rank(market.preferences[p], r));
      receiverRanks.add(rank(market.preferences[r], p));
      occupied.add(r);
    }
    final pairs = proposerRanks.length;
    return ['STATS ${market.name} source=${market.source} pairs=$pairs',
      'PROPOSERS ${rankSummary(proposerRanks)} unmatched=${market.proposerCount - pairs}',
      'RECEIVERS ${rankSummary(receiverRanks)} unmatched=${market.count - market.proposerCount - occupied.length}'];
  }
  List<String> execute(String line) {
    final words = line.split(' ');
    final command = words[0], name = words[1];
    switch (command) {
      case 'MARKET':
        newName(name);
        final bar = words.indexOf('|');
        final proposers = words.sublist(2, bar), receivers = words.sublist(bar + 1);
        final agents = [...proposers, ...receivers];
        distinctAgents(agents);
        markets[name] = Market(name, MarketKind.twoSided, agents, proposerCount: proposers.length);
        return ['MARKET $name proposers=${proposers.length} receivers=${receivers.length}'];
      case 'ROOMS':
        newName(name);
        final agents = words.sublist(2);
        distinctAgents(agents);
        markets[name] = Market(name, MarketKind.roommates, agents);
        return ['ROOMS $name agents=${agents.length}'];
      case 'HOUSES':
        newName(name);
        final agents = <String>[], houses = <String>[];
        final agentNames = <String>{}, houseNames = <String>{};
        for (final word in words.skip(2)) {
          final pair = word.split(':');
          if (!agentNames.add(pair[0])) throw CommandError('DUPLICATE AGENT ${pair[0]}');
          if (!houseNames.add(pair[1])) throw CommandError('DUPLICATE HOUSE ${pair[1]}');
          agents.add(pair[0]); houses.add(pair[1]);
        }
        markets[name] = Market(name, MarketKind.housing, agents, houses: houses);
        return ['HOUSES $name agents=${agents.length}'];
      case 'RANDOM':
        newName(name);
        final size = int.parse(words[2]), seed = int.parse(words[3]);
        var state = seed;
        final agents = [for (var i = 1; i <= size; i++) 'P$i', for (var i = 1; i <= size; i++) 'R$i'];
        final market = Market(name, MarketKind.twoSided, agents, proposerCount: size);
        for (var a = 0; a < market.count; a++) {
          final preferences = (a < size ? market.receivers : market.proposers).toList();
          for (var i = size - 1; i > 0; i--) {
            state = 48271 * state % 2147483647;
            final j = state % (i + 1);
            final first = preferences[i];
            preferences[i] = preferences[j];
            preferences[j] = first;
          }
          market.preferences[a] = preferences;
        }
        markets[name] = market;
        return ['RANDOM $name n=$size seed=$seed'];
      case 'PREF':
        final market = get(name);
        final agent = market.agent(words[2]);
        final choices = <int>[], seen = <int>{};
        for (final word in words.skip(3)) {
          final choice = market.choice(agent, word);
          if (!seen.add(choice)) throw CommandError('DUPLICATE CHOICE $word');
          choices.add(choice);
        }
        market.preferences[agent] = choices;
        if (market.kind == MarketKind.twoSided) market.clearMatching();
        return ['PREF $name ${words[2]} length=${choices.length}'];
      case 'CAPACITY':
        final market = get(name, MarketKind.twoSided);
        final receiver = market.receiver(words[2]), capacity = int.parse(words[3]);
        market.capacities[receiver] = capacity;
        market.clearMatching();
        return ['CAPACITY $name ${words[2]} $capacity'];
      case 'SHOW': return show(get(name));
      case 'CHECK': return check(get(name), words);
      case 'GS':
      case 'GSR':
      case 'BOSTON':
        final market = get(name, MarketKind.twoSided);
        final result = command == 'BOSTON' ? boston(market)
            : deferred(market, reverse: command == 'GSR', verbose: words.length == 3);
        market.setMatching(result.partners, command);
        return ['$command $name ${command == 'BOSTON' ? 'applications' : 'proposals'}=${result.proposals}',
          ...result.log, 'MATCHING ${market.pairs(result.partners)}'];
      case 'LATTICE':
      case 'EGALITARIAN':
      case 'MINREGRET':
        final market = get(name, MarketKind.twoSided);
        final result = enumerate(market);
        if (command == 'LATTICE') {
          final output = ['LATTICE $name matchings=${result.matchings.length} rotations=${result.rotations.length}'];
          for (var i = 0; i < result.matchings.length; i++) {
            final matching = result.matchings[i];
            final origin = matching.origin == 0 ? '-' : '${matching.origin}';
            final via = matching.via == 0 ? '-' : '${matching.via}';
            output.add('MATCHING ${i + 1} from=$origin via=$via cost=${matching.cost} regret=${matching.regret} ${market.pairs(matching.partners)}');
          }
          for (var i = 0; i < result.rotations.length; i++) { output.add('ROTATION ${i + 1} ${result.rotations[i]}'); }
          return output;
        }
        var best = 0;
        for (var i = 1; i < result.matchings.length; i++) {
          if (command == 'EGALITARIAN' ? result.matchings[i].cost < result.matchings[best].cost
              : result.matchings[i].regret < result.matchings[best].regret) best = i;
        }
        final selected = result.matchings[best];
        market.setMatching(selected.partners, command);
        final criterion = command == 'EGALITARIAN' ? 'cost=${selected.cost}' : 'regret=${selected.regret}';
        return ['$command $name matching=${best + 1} $criterion', 'MATCHING ${market.pairs(selected.partners)}'];
      case 'HR': return hospitals(get(name, MarketKind.twoSided));
      case 'ROOMMATES': return roommates(get(name, MarketKind.roommates), words.length == 3);
      case 'TTC': return tradingCycles(get(name, MarketKind.housing));
      case 'SERIAL': return serial(get(name, MarketKind.housing), words);
      case 'MANIPULATE':
        final market = get(name, MarketKind.twoSided);
        return manipulate(market, market.proposer(words[2]));
      case 'STATS': return stats(get(name, MarketKind.twoSided));
      default: throw StateError('Unknown command in well-formed input');
    }
  }
}

void main() {
  final lab = Lab();
  final count = int.parse(stdin.readLineSync()!);
  for (var i = 0; i < count; i++) {
    final line = stdin.readLineSync()!;
    try {
      final output = lab.execute(line);
      for (final row in output) { stdout.writeln(row); }
    } on CommandError catch (error) {
      stdout.writeln(error);
    }
  }
}
