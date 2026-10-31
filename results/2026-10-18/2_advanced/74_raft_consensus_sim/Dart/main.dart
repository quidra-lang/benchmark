import 'dart:io';
import 'dart:math';
part 'minstd.dart';
part 'network.dart';
part 'raft_node.dart';
part 'cluster.dart';
part 'checker.dart';

class Election {
  final int time, node, term;
  int won = -1;
  final String trigger;
  final Set<int> votes;
  Election(this.time, this.node, this.term, this.trigger, this.votes);
}

class Leader {
  final int node, elected;
  int ended = -1, appended = 1, commit = 0;
  String reason = '';
  final Set<int> votes;
  Leader(this.node, this.elected, this.votes);
}

String nodeSet(Set<int> set) {
  final a = set.toList()..sort();
  return a.isEmpty ? '-' : a.map((i) => 'n$i').join(',');
}

List<String> keys(Map<String, int> a) => a.keys.toList()..sort();

class Simulator {
  final Settings settings;
  final List<Node> nodes;
  final Network network;
  final Generator random;
  final checker = Checker();
  final List<Control> controls;
  final List<Request> requests;
  int time = 0;
  final List<String> trace = [], timelines = [];
  final List<Election> elections = [];
  final Map<int, Leader> leaders = {};
  int leaderTicks = 0, multiTicks = 0, gapStart = -1, maximumTerm = 0;
  final List<(int, int)> gaps = [];
  final Map<String, int> reference = {},
      statusCounts = {},
      keyRequests = {},
      keyCommitted = {};
  final Map<int, Map<String, int>> replays = {0: {}};
  final List<int> latencies = [];
  Simulator(this.settings, this.controls, this.requests, this.network)
    : nodes = [for (var i = 1; i <= settings.n; i++) Node(i, settings.n)],
      random = Generator(settings.seed);
  Node node(int i) => nodes[i - 1];
  bool majority(int n) => 2 * n > settings.n;
  void traceLine(String text) {
    trace.add('$time $text');
  }

  void timer(Node n) {
    n.deadline = time + random.between(settings.emin, settings.emax);
  }

  void send(Node n, int destination, Message m) {
    m.source = n.id;
    m.destination = destination;
    m.term = n.term;
    network.send(time, m);
  }

  void appendTo(Node n, int d) {
    final prev = n.next[d] - 1,
        entries = n.log.sublist(prev, min(prev + settings.b, n.log.length));
    send(
      n,
      d,
      Message(
        'AE',
        previous: prev,
        previousTerm: n.termAt(prev),
        entries: entries,
        commit: n.commit,
      ),
    );
  }

  void broadcast(Node n) {
    for (final other in nodes) {
      if (other.id != n.id) appendTo(n, other.id);
    }
  }

  void endLeader(Node n, String reason) {
    final r = leaders[n.term]!;
    r.ended = time;
    r.reason = reason;
    r.commit = n.commit;
    n.cancelTransfer();
  }

  void control(Control e) {
    switch (e.kind) {
      case 'CRASH':
        final n = node(number(e.args[0]));
        traceLine('CRASH n${n.id} ${n.role} term ${n.term}');
        if (n.role == 'LEADER') endLeader(n, 'CRASH');
        n.up = false;
        n.reset(settings.n);
        break;
      case 'RESTART':
        final n = node(number(e.args[0]));
        n.up = true;
        timer(n);
        traceLine(
          'RESTART n${n.id} term ${n.term} length ${n.log.length} deadline ${n.deadline}',
        );
        break;
      case 'HEAL':
        network.groups.fillRange(0, network.groups.length, 0);
        traceLine('HEAL');
        break;
      case 'PARTITION':
        final groups = parseGroups(e.args), names = <String>[];
        for (var i = 0; i < groups.length; i++) {
          for (final id in groups[i]) {
            network.groups[id] = i;
          }
          names.add(nodeSet(groups[i].toSet()));
        }
        traceLine('PARTITION ${names.join(' ')}');
        break;
      case 'TRANSFER':
        transfer(node(number(e.args[0])), number(e.args[1]));
        break;
    }
  }

  void attempt(Request r) {
    r.attempts++;
    var destination = r.destination, redirected = 0, reason = '';
    late Node n;
    while (true) {
      n = node(destination);
      if (!n.up) {
        reason = 'down';
        break;
      }
      if (n.role == 'LEADER') {
        if (n.target != 0) {
          reason = 'transfer';
          break;
        }
        n.log.add(Entry(n.term, r.command, r.number));
        leaders[n.term]!.appended++;
        r.index = n.log.length;
        r.term = n.term;
        r.scheduled = -1;
        traceLine(
          'ACCEPT r${r.number} n${n.id} index ${r.index} term ${r.term}',
        );
        return;
      }
      if (n.known == 0 || redirected >= settings.n - 1) {
        reason = 'noleader';
        break;
      }
      destination = n.known;
      traceLine('REDIRECT r${r.number} n${n.id} n$destination');
      redirected++;
      r.redirects++;
    }
    if (r.attempts < settings.attempts) {
      r.destination = n.id % settings.n + 1;
      r.scheduled = time + settings.retry;
      traceLine(
        'REJECT r${r.number} n${n.id} $reason retry n${r.destination} at ${r.scheduled}',
      );
    } else {
      r.abandoned = true;
      r.scheduled = -1;
      traceLine('REJECT r${r.number} n${n.id} $reason giveup');
    }
  }

  void election(Node n, String trigger) {
    n.term++;
    n.role = 'CANDIDATE';
    n.voted = n.id;
    n.votes = {n.id};
    n.known = 0;
    timer(n);
    n.stats.elections++;
    n.election = elections.length;
    elections.add(Election(time, n.id, n.term, trigger, n.votes));
    traceLine(
      'ELECTION n${n.id} term ${n.term} last ${n.log.length}/${n.lastTerm} deadline ${n.deadline}',
    );
    for (final other in nodes) {
      if (other.id != n.id)
        send(
          n,
          other.id,
          Message('RV', last: n.log.length, lastTerm: n.lastTerm),
        );
    }
  }

  void becomeLeader(Node n) {
    n.role = 'LEADER';
    n.known = n.id;
    for (final other in nodes) {
      if (other.id != n.id) {
        n.next[other.id] = n.log.length + 1;
        n.match[other.id] = 0;
      }
    }
    n.log.add(Entry(n.term, 'NOOP', 0));
    n.stats.leaderTerms++;
    elections[n.election].won = time;
    checker.leader(n);
    leaders[n.term] = Leader(n.id, time, Set.of(n.votes));
    traceLine(
      'LEADER n${n.id} term ${n.term} votes ${nodeSet(n.votes)} noop ${n.log.length}',
    );
    broadcast(n);
    n.heartbeat = time + settings.h;
    n.quorum = time + settings.q;
    n.heard = {};
  }

  void advance(Node n, int index) {
    for (var i = n.commit + 1; i <= index; i++) {
      checker.commit(i, n.termAt(i), time);
    }
    n.commit = index;
    final first = n.applied + 1;
    for (var i = first; i <= index; i++) {
      final e = n.log[i - 1], result = applyCommand(n.store, e.command);
      n.stats.applies++;
      checker.apply(i, e, result);
    }
    n.applied = index;
    traceLine('APPLY n${n.id} $first-$index');
  }

  void checkCommit(Node n) {
    for (var i = n.log.length; i > n.commit; i--) {
      if (n.termAt(i) != n.term) return;
      var count = 1;
      for (final other in nodes) {
        if (other.id != n.id && n.match[other.id] >= i) count++;
      }
      if (majority(count)) {
        traceLine('COMMIT n${n.id} ${n.commit + 1}-$i term ${n.term}');
        advance(n, i);
        return;
      }
    }
  }

  void truncate(Node n, int first) {
    final removed = n.log.sublist(first - 1);
    n.stats.truncated += removed.length;
    checker.truncate(first, removed);
    traceLine('TRUNCATE n${n.id} from $first removed ${removed.length}');
    n.log.removeRange(first - 1, n.log.length);
  }

  void receive(Message m) {
    final n = node(m.destination);
    if (m.term > n.term) {
      final role = n.role;
      traceLine(
        'TERM n${n.id} ${n.term}->${m.term} ${m.kind} n${m.source} $role',
      );
      if (role == 'LEADER') endLeader(n, 'STEPDOWN');
      n.term = m.term;
      n.voted = 0;
      n.known = 0;
      n.role = 'FOLLOWER';
      if (role == 'LEADER') timer(n);
    }
    switch (m.kind) {
      case 'RV':
        var reason = '';
        if (m.term < n.term) {
          reason = 'term';
        } else if (n.voted != 0 && n.voted != m.source) {
          reason = 'voted';
        } else if (!n.accepts(m.last, m.lastTerm)) {
          reason = 'log';
        }
        if (reason.isEmpty) {
          n.voted = m.source;
          n.stats.votesGranted++;
          timer(n);
          traceLine(
            'VOTE n${n.id} n${m.source} term ${n.term} deadline ${n.deadline}',
          );
        } else {
          traceLine('DENY n${n.id} n${m.source} term ${n.term} $reason');
        }
        send(n, m.source, Message('RVR', success: reason.isEmpty));
        break;
      case 'RVR':
        if (n.role == 'CANDIDATE' && m.term == n.term && m.success) {
          n.votes.add(m.source);
          if (majority(n.votes.length)) becomeLeader(n);
        }
        break;
      case 'AE':
        if (m.term < n.term) {
          send(n, m.source, Message('AER'));
          return;
        }
        if (n.role == 'CANDIDATE') {
          n.role = 'FOLLOWER';
          traceLine('YIELD n${n.id} term ${n.term} n${m.source}');
        }
        n.known = m.source;
        timer(n);
        if (m.previous > n.log.length ||
            n.termAt(m.previous) != m.previousTerm) {
          n.stats.aeFail++;
          final hint = m.previous > n.log.length
              ? n.log.length
              : m.previous - 1;
          send(n, m.source, Message('AER', m: hint));
          return;
        }
        n.stats.aeOK++;
        for (var j = 0; j < m.entries.length; j++) {
          final e = m.entries[j], k = m.previous + j + 1;
          if (k <= n.log.length && n.termAt(k) != e.term) truncate(n, k);
          if (k > n.log.length) {
            n.log.add(e);
            n.stats.appended++;
          }
        }
        final confirmed = m.previous + m.entries.length,
            c = min(m.commit, confirmed);
        if (c > n.commit) advance(n, c);
        send(n, m.source, Message('AER', success: true, m: confirmed));
        break;
      case 'AER':
        if (n.role != 'LEADER' || m.term != n.term) return;
        final j = m.source;
        n.heard.add(j);
        if (m.success) {
          n.match[j] = max(n.match[j], m.m);
          n.next[j] = max(n.next[j], m.m + 1);
          checkCommit(n);
          if (j == n.target && !n.transferSent && n.match[j] == n.log.length) {
            timeoutNow(n);
          } else if (n.next[j] <= n.log.length) {
            appendTo(n, j);
          }
        } else {
          n.next[j] = max(n.match[j] + 1, min(n.next[j] - 1, m.m + 1));
          traceLine('BACKTRACK n${n.id} n$j next ${n.next[j]}');
          appendTo(n, j);
        }
        break;
      case 'TN':
        if (m.term != n.term || n.role != 'FOLLOWER') {
          traceLine('IGNORE n${n.id} TN n${m.source} term ${m.term}');
        } else {
          election(n, 'transfer');
        }
        break;
    }
  }

  void timeoutNow(Node n) {
    traceLine(
      'TIMEOUTNOW n${n.id} n${n.target} term ${n.term} index ${n.log.length}',
    );
    n.transferSent = true;
    send(n, n.target, Message('TN'));
  }

  void transfer(Node n, int d) {
    if (!n.up || n.role != 'LEADER' || n.target != 0 || n.id == d) {
      traceLine('TRANSFER n${n.id} n$d ignored');
      return;
    }
    traceLine(
      'TRANSFER n${n.id} n$d start match ${n.match[d]}/${n.log.length}',
    );
    n.target = d;
    n.transferSent = false;
    n.transferDeadline = time + settings.emin;
    if (n.match[d] == n.log.length) {
      timeoutNow(n);
    } else {
      appendTo(n, d);
    }
  }

  void timers(Node n) {
    if (n.role == 'LEADER') {
      if (n.quorum == time) {
        if (!majority(1 + n.heard.length)) {
          traceLine(
            'STEPDOWN n${n.id} term ${n.term} heard ${nodeSet(n.heard)}',
          );
          endLeader(n, 'QUORUM');
          n.role = 'FOLLOWER';
          n.known = 0;
          timer(n);
          return;
        }
        n.heard = {};
        n.quorum = time + settings.q;
      }
      if (n.target != 0 && n.transferDeadline == time) {
        traceLine('TRANSFER n${n.id} n${n.target} abort');
        n.cancelTransfer();
      }
      if (n.heartbeat == time) {
        broadcast(n);
        n.heartbeat = time + settings.h;
      }
    } else if (n.deadline == time) {
      election(n, 'timeout');
    }
  }

  void endTick() {
    checker.checkLogs(nodes);
    var count = 0;
    for (final n in nodes) {
      if (n.up && n.role == 'LEADER') {
        count++;
        n.stats.leaderTicks++;
      }
    }
    if (count > 0) {
      leaderTicks++;
      if (count >= 2) multiTicks++;
      if (gapStart >= 0) {
        gaps.add((gapStart, time - 1));
        gapStart = -1;
      }
    } else if (gapStart < 0) {
      gapStart = time;
    }
    if (time % settings.sample == 0) {
      final fields = [
        for (final n in nodes) '${n.up ? n.role[0] : 'D'}${n.term}',
      ];
      timelines.add('TIMELINE $time ${fields.join(' ')}');
    }
  }

  void run() {
    for (final n in nodes) {
      timer(n);
      traceLine('START n${n.id} deadline ${n.deadline}');
    }
    var nextControl = 0;
    for (time = 0; time <= settings.end; time++) {
      while (nextControl < controls.length &&
          controls[nextControl].time == time) {
        control(controls[nextControl++]);
      }
      for (final r in requests) {
        if (r.scheduled == time) attempt(r);
      }
      for (final m in network.arrivals(time)) {
        if (network.deliver(m, node(m.destination).up)) receive(m);
      }
      for (final n in nodes) {
        if (n.up) timers(n);
      }
      endTick();
    }
    if (gapStart >= 0) gaps.add((gapStart, settings.end));
    finish();
  }

  void finish() {
    for (var i = 1; i <= checker.applied.length; i++) {
      applyCommand(reference, checker.applied[i]!.entry.command);
      replays[i] = Map.of(reference);
    }
    for (final n in nodes) {
      maximumTerm = max(maximumTerm, n.term);
    }
    for (final r in requests) {
      final key = r.command.split(' ')[1];
      keyRequests[key] = (keyRequests[key] ?? 0) + 1;
      if (r.index != 0) {
        final c = checker.committed[r.index];
        if (c != null && c.term == r.term) {
          r.status = 'COMMITTED';
          r.latency = c.time - r.time;
          r.result = checker.applied[r.index]!.result;
          latencies.add(r.latency);
          keyCommitted[key] = (keyCommitted[key] ?? 0) + 1;
        } else {
          r.status = 'LOST';
          for (final n in nodes) {
            if (n.log.length >= r.index && n.termAt(r.index) == r.term) {
              r.status = 'UNCOMMITTED';
              break;
            }
          }
        }
      } else {
        r.status = r.abandoned ? 'FAILED' : 'WAITING';
      }
      statusCounts[r.status] = (statusCounts[r.status] ?? 0) + 1;
    }
  }

  List<String> leaderLines() {
    final out = <String>[], byTerm = <int, List<Election>>{};
    for (final e in elections) {
      byTerm.putIfAbsent(e.term, () => []).add(e);
      final outcome = e.won >= 0 ? 'WON ${e.won}' : 'LOST';
      out.add(
        'ELECTION ${e.time} n${e.node} term ${e.term} trigger ${e.trigger} votes ${e.votes.length} $outcome',
      );
    }
    for (var term = 1; term <= maximumTerm; term++) {
      final candidates = {for (final e in byTerm[term] ?? <Election>[]) e.node},
          r = leaders[term];
      if (r == null) {
        out.add('TERM $term NONE candidates ${nodeSet(candidates)}');
        continue;
      }
      final ended = r.ended >= 0 ? '${r.ended}' : '-',
          reason = r.ended >= 0 ? r.reason : 'ACTIVE',
          commit = r.ended >= 0 ? r.commit : node(r.node).commit,
          start = byTerm[term]![0].time;
      out.add(
        'TERM $term LEADER n${r.node} elected ${r.elected} votes ${nodeSet(r.votes)} ended $ended $reason appended ${r.appended} commit $commit candidates ${nodeSet(candidates)} started $start wait ${r.elected - start}',
      );
    }
    for (final n in nodes) {
      final a = n.stats;
      out.add(
        'NODE n${n.id} elections ${a.elections} leader_terms ${a.leaderTerms} leader_ticks ${a.leaderTicks} votes_granted ${a.votesGranted}',
      );
    }
    out.addAll(timelines);
    var longest = 0;
    for (final g in gaps) {
      final length = g.$2 - g.$1 + 1;
      longest = max(longest, length);
      out.add('GAP ${g.$1}-${g.$2} length $length');
    }
    out.add(
      'SUMMARY terms $maximumTerm leaders ${leaders.length} elections ${elections.length} leader_ticks $leaderTicks multi_ticks $multiTicks ticks ${settings.end + 1} gaps ${gaps.length} longest $longest',
    );
    return out;
  }

  List<String> logLines() {
    final out = <String>[];
    var prefix = nodes[0].log.length;
    for (final n in nodes) {
      final status = n.up ? n.role : 'DOWN',
          voted = n.voted != 0 ? 'n${n.voted}' : '-';
      out.add(
        'NODE n${n.id} $status term ${n.term} voted $voted commit ${n.commit} applied ${n.applied} length ${n.log.length}',
      );
      for (var j = 0; j < n.log.length; j++) {
        final e = n.log[j];
        var text = '${j + 1} ${e.term} ${e.command}';
        if (e.request != 0) text += ' r${e.request}';
        out.add(text);
      }
      prefix = min(prefix, n.log.length);
      for (var j = 0; j < prefix; j++) {
        if (!n.log[j].same(nodes[0].log[j])) {
          prefix = j;
          break;
        }
      }
    }
    final c = checker.committed.length;
    out.add('AGREE prefix $prefix committed $c');
    for (final n in nodes) {
      var common = 0;
      for (var i = 1; i <= min(n.log.length, c); i++) {
        if (n.termAt(i) != checker.committed[i]!.term) break;
        common = i;
      }
      final a = n.stats;
      out.add(
        'DIFF n${n.id} common $common behind ${c - common} extra ${n.log.length - common} ae_ok ${a.aeOK} ae_fail ${a.aeFail} appended ${a.appended} truncated ${a.truncated} applies ${a.applies}',
      );
    }
    return out;
  }

  List<String> stateLines() {
    final out = <String>[];
    for (final n in nodes) {
      final status = n.up ? 'UP' : 'DOWN', ref = replays[n.applied]!;
      var replay = 'match';
      if (ref.length != n.store.length) replay = 'mismatch';
      for (final e in ref.entries) {
        if (n.store[e.key] != e.value) replay = 'mismatch';
      }
      out.add(
        'NODE n${n.id} $status applied ${n.applied} keys ${n.store.length} replay $replay',
      );
      for (final key in keys(n.store)) {
        out.add('$key ${n.store[key]}');
      }
    }
    for (final r in requests) {
      var text =
          'REQUEST r${r.number} at ${r.time} n${r.initial} ${r.command} attempts ${r.attempts} redirects ${r.redirects} ${r.status}';
      if (r.index != 0) {
        text += ' index ${r.index} term ${r.term}';
        if (r.status == 'COMMITTED')
          text += ' latency ${r.latency} result ${r.result}';
      } else if (r.status == 'WAITING') {
        text += ' next ${r.scheduled}';
      }
      out.add(text);
    }
    for (final key in keys(keyRequests)) {
      out.add(
        'KEY $key requests ${keyRequests[key]} committed ${keyCommitted[key] ?? 0} final ${reference.containsKey(key) ? reference[key] : 'missing'}',
      );
    }
    final counts = [
      for (final status in [
        'COMMITTED',
        'UNCOMMITTED',
        'LOST',
        'FAILED',
        'WAITING',
      ])
        '${status.toLowerCase()} ${statusCounts[status] ?? 0}',
    ];
    out.add('REQUESTS total ${requests.length} ${counts.join(' ')}');
    var sum = 0, lo = 0, hi = 0;
    for (var i = 0; i < latencies.length; i++) {
      final v = latencies[i];
      sum += v;
      if (i == 0 || v < lo) lo = v;
      hi = max(hi, v);
    }
    out.add('LATENCY count ${latencies.length} total $sum min $lo max $hi');
    return out;
  }

  List<String> safetyLines() {
    final out = checker.lines(maximumTerm);
    out.add('MESSAGES ${network.total.text()}');
    for (final kind in messageTypes) {
      out.add('TYPE $kind ${network.byType[kind]!.text()}');
    }
    for (var a = 1; a <= settings.n; a++) {
      for (var b = 1; b <= settings.n; b++) {
        if (a == b) continue;
        final link = network.links[a][b]!,
            dropped = link.stats.values.skip(3).fold(0, (a, b) => a + b);
        out.add(
          'LINK n$a->n$b delay ${link.delay} loss ${link.loss} sent ${link.stats.values[0]} delivered ${link.stats.values[1]} dropped $dropped',
        );
      }
    }
    out.add('DRAWS ${random.draws}');
    out.add(
      checker.violations.any((v) => v != 0) ? 'RESULT UNSAFE' : 'RESULT SAFE',
    );
    return out;
  }
}

void main() {
  final settings = readSettings();
  final (controls, requests) = readScript();
  final s = Simulator(settings, controls, requests, readNetwork(settings.n));
  s.run();
  Directory('output').createSync(recursive: true);
  final reports = {
    'trace.txt': s.trace,
    'leaders.txt': s.leaderLines(),
    'logs.txt': s.logLines(),
    'state.txt': s.stateLines(),
    'safety.txt': s.safetyLines(),
  };
  for (final e in reports.entries) {
    File('output/${e.key}').writeAsStringSync('${e.value.join('\n')}\n');
  }
}
