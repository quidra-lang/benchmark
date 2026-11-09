part of 'main.dart';

class SnapshotRecord {
  final int process, time, balance, l;
  final String reason;
  final List<int> v;
  final List<MessageCopy> pending;
  SnapshotRecord(
    this.process,
    this.time,
    this.balance,
    this.l,
    this.reason,
    this.v,
    this.pending,
  );
}

class SnapshotChannel {
  int dispatched = -1, accepted = -1;
  final state = <MessageCopy>[];
}

class Snapshot {
  final String name;
  final int start;
  int completed = -1, markers = 0;
  final List<SnapshotRecord?> records;
  final channels = <(int, int), SnapshotChannel>{}, ignored = <(int, int)>[];
  Snapshot(this.name, this.start, int n) : records = List.filled(n, null);
}

class CutResult {
  final orphans = <MessageCopy>[], transit = <MessageCopy>[];
  int balances = 0, money = 0;
  bool vector = true;
}

CutResult analyzeCut(Simulation sim, List<int> cut) {
  final out = CutResult();
  for (var p = 0; p < sim.processes.length; p++) {
    final state = sim.processes[p];
    out.balances += balanceAt(state, cut[p]);
    if (cut[p] > 0 && !lessEqual(state.events[cut[p] - 1].v, cut))
      out.vector = false;
  }
  out.money = out.balances;
  for (final c in sim.copies) {
    final sent = c.message.event.local <= cut[c.source],
        received =
            c.received != null && c.received!.local <= cut[c.destination];
    if (received && !sent) out.orphans.add(c);
    if (sent && !received) {
      out.transit.add(c);
      out.money += c.message.amount;
    }
  }
  return out;
}

List<int> snapshotCut(Snapshot s) => [
  for (var p = 0; p < s.records.length; p++) s.records[p]!.v[p],
];
