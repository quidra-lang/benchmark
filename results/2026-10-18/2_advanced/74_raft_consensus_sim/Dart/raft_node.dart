part of 'main.dart';

class Entry {
  final int term, request;
  final String command;
  Entry(this.term, this.command, this.request);
  bool same(Entry other) =>
      term == other.term &&
      request == other.request &&
      command == other.command;
}

class NodeStats {
  int elections = 0,
      leaderTerms = 0,
      votesGranted = 0,
      leaderTicks = 0,
      aeOK = 0,
      aeFail = 0,
      appended = 0,
      truncated = 0,
      applies = 0;
}

class Node {
  final int id;
  int term = 0, voted = 0;
  final List<Entry> log = [];
  bool up = true;
  final stats = NodeStats();
  String role = 'FOLLOWER';
  int commit = 0, applied = 0, known = 0, deadline = -1, election = -1;
  Map<String, int> store = {};
  Set<int> votes = {}, heard = {};
  List<int> next = [], match = [];
  int heartbeat = -1, quorum = -1, target = 0, transferDeadline = -1;
  bool transferSent = false;
  Node(this.id, int count) {
    reset(count);
  }
  void reset(int count) {
    role = 'FOLLOWER';
    commit = 0;
    applied = 0;
    known = 0;
    deadline = -1;
    election = -1;
    store = {};
    votes = {};
    heard = {};
    next = List.filled(count + 1, 0);
    match = List.filled(count + 1, 0);
    heartbeat = -1;
    quorum = -1;
    cancelTransfer();
  }

  void cancelTransfer() {
    target = 0;
    transferSent = false;
    transferDeadline = -1;
  }

  int termAt(int i) => i == 0 ? 0 : log[i - 1].term;
  int get lastTerm => termAt(log.length);
  bool accepts(int i, int t) =>
      t > lastTerm || t == lastTerm && i >= log.length;
}

String applyCommand(Map<String, int> store, String command) {
  final a = command.split(' ');
  if (a[0] == 'NOOP') return '';
  final key = a[1];
  switch (a[0]) {
    case 'SET':
      store[key] = number(a[2]);
      return 'ok';
    case 'ADD':
      store[key] = (store[key] ?? 0) + number(a[2]);
      return '${store[key]}';
    case 'DEL':
      if (store.containsKey(key)) {
        store.remove(key);
        return 'deleted';
      }
      return 'missing';
    default:
      return store.containsKey(key) ? '${store[key]}' : 'missing';
  }
}
