part of 'main.dart';

class BTB {
  final List<int> pc, target;
  final List<bool> valid;
  BTB(int n)
    : pc = List.filled(n, 0),
      target = List.filled(n, 0),
      valid = List.filled(n, false);
  int? lookup(int p) {
    final i = (p ~/ 4) % pc.length;
    return valid[i] && pc[i] == p ? target[i] : null;
  }

  void insert(int p, int t) {
    final i = (p ~/ 4) % pc.length;
    pc[i] = p;
    target[i] = t;
    valid[i] = true;
  }
}

class RAS {
  final int depth;
  final stack = <int>[];
  RAS(this.depth);
  void push(int v) {
    if (depth == 0) return;
    if (stack.length == depth) stack.removeAt(0);
    stack.add(v);
  }

  int? pop() => stack.isEmpty ? null : stack.removeLast();
}

int counter(int v, bool taken) => taken ? min(3, v + 1) : max(0, v - 1);

class Direction {
  final PredictorConfig config;
  List<int> local = [], global = [], chooser = [];
  int history = 0;
  Direction(this.config) {
    final p = config.parameters;
    switch (config.scheme) {
      case 'ONEBIT':
        local = List.filled(p[0], 0);
      case 'TWOBIT':
        local = List.filled(p[0], 1);
      case 'GSHARE':
        global = List.filled(p[0], 1);
      case 'TOURNAMENT':
        local = List.filled(p[0], 1);
        global = List.filled(p[1], 1);
        chooser = List.filled(p[3], 1);
    }
  }
  bool predict(Instruction i) {
    final pc = i.pc ~/ 4;
    switch (config.scheme) {
      case 'BTFN':
        return i.target < i.pc;
      case 'ONEBIT':
        return local[pc % local.length] == 1;
      case 'TWOBIT':
        return local[pc % local.length] >= 2;
      case 'GSHARE':
        return global[(pc ^ history) % global.length] >= 2;
      case 'TOURNAMENT':
        return chooser[pc % chooser.length] >= 2
            ? global[(pc ^ history) % global.length] >= 2
            : local[pc % local.length] >= 2;
    }
    return false;
  }

  void update(Instruction i) {
    final pc = i.pc ~/ 4, p = config.parameters;
    switch (config.scheme) {
      case 'ONEBIT':
        local[pc % local.length] = i.taken ? 1 : 0;
      case 'TWOBIT':
        final k = pc % local.length;
        local[k] = counter(local[k], i.taken);
      case 'GSHARE':
      case 'TOURNAMENT':
        final k = (pc ^ history) % global.length;
        var h = p[1];
        if (config.scheme == 'TOURNAMENT') {
          final li = pc % local.length,
              ci = pc % chooser.length,
              lp = local[li] >= 2,
              gp = global[k] >= 2;
          if (lp != gp) chooser[ci] = counter(chooser[ci], gp == i.taken);
          local[li] = counter(local[li], i.taken);
          h = p[2];
        }
        global[k] = counter(global[k], i.taken);
        history = (2 * history + (i.taken ? 1 : 0)) % (1 << h);
    }
  }
}

int storage(PredictorConfig p) {
  final a = p.parameters;
  switch (p.scheme) {
    case 'ONEBIT':
      return a[0];
    case 'TWOBIT':
      return 2 * a[0];
    case 'GSHARE':
      return 2 * a[0] + a[1];
    case 'TOURNAMENT':
      return 2 * (a[0] + a[1] + a[3]) + a[2];
  }
  return 0;
}
