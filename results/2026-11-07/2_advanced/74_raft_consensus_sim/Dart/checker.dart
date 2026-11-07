part of 'main.dart';

const propertyNames = [
  'ELECTION_SAFETY',
  'LEADER_COMPLETENESS',
  'LOG_MATCHING',
  'STATE_MACHINE_SAFETY',
  'COMMITTED_KEPT',
];

class CommitRecord {
  final int term, time;
  CommitRecord(this.term, this.time);
}

class ApplyRecord {
  final Entry entry;
  final String result;
  ApplyRecord(this.entry, this.result);
}

class Checker {
  final violations = List.filled(5, 0);
  final Map<int, int> leaders = {};
  final Map<int, CommitRecord> committed = {};
  final Map<int, ApplyRecord> applied = {};
  int elected = 0,
      logChecks = 0,
      pairChecks = 0,
      applies = 0,
      truncations = 0,
      removed = 0;
  void leader(Node n) {
    elected++;
    if (!leaders.containsKey(n.term)) {
      leaders[n.term] = n.id;
    } else if (leaders[n.term] != n.id) {
      violations[0]++;
    }
    for (final r in committed.entries) {
      if (r.key > n.log.length || n.termAt(r.key) != r.value.term) {
        violations[1]++;
        break;
      }
    }
  }

  void commit(int i, int term, int t) {
    committed.putIfAbsent(i, () => CommitRecord(term, t));
  }

  void apply(int i, Entry e, String result) {
    applies++;
    final old = applied[i];
    if (old == null) {
      applied[i] = ApplyRecord(e, result);
    } else if (!old.entry.same(e)) {
      violations[3]++;
    }
  }

  void truncate(int first, List<Entry> entries) {
    truncations++;
    removed += entries.length;
    for (var j = 0; j < entries.length; j++) {
      if (committed[first + j]?.term == entries[j].term) violations[4]++;
    }
  }

  void checkLogs(List<Node> nodes) {
    logChecks++;
    for (var a = 0; a < nodes.length; a++) {
      final x = nodes[a];
      for (final y in nodes.skip(a + 1)) {
        pairChecks++;
        final limit = min(x.log.length, y.log.length);
        var g = 0;
        for (var k = limit; k >= 1; k--) {
          if (x.termAt(k) == y.termAt(k)) {
            g = k;
            break;
          }
        }
        for (var k = 0; k < g; k++) {
          if (!x.log[k].same(y.log[k])) {
            violations[2]++;
            break;
          }
        }
      }
    }
  }

  List<String> lines(int k) {
    final details = [
      'terms $k leaders ${leaders.length} elected $elected',
      'checks $elected committed ${committed.length}',
      'checks $logChecks pairs $pairChecks',
      'applies $applies indices ${applied.length}',
      'truncations $truncations removed $removed',
    ];
    return [
      for (var i = 0; i < 5; i++)
        '${propertyNames[i]} ${violations[i] == 0 ? 'OK' : 'FAIL'} violations ${violations[i]} ${details[i]}',
    ];
  }
}
