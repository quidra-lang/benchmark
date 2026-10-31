part of 'main.dart';

class CacheLine {
  final int block;
  String state;
  int stamp;
  CacheLine([this.block = 0, this.state = '', this.stamp = 0]);
}

class CacheSet {
  final List<CacheLine> ways;
  final List<int> bits;
  int fills = 0, evictions = 0;
  CacheSet(int count)
    : ways = List.generate(count, (_) => CacheLine()),
      bits = List.filled(count, 0);
}

class Cache {
  final List<CacheSet> sets;
  final String policy;
  int clock = 0;
  Cache(int count, int ways, this.policy)
    : sets = List.generate(count, (_) => CacheSet(ways));
  (int, int) find(int b) {
    final set = b % sets.length;
    for (var i = 0; i < sets[set].ways.length; i++) {
      final line = sets[set].ways[i];
      if (line.state.isNotEmpty && line.block == b) return (set, i);
    }
    return (set, -1);
  }

  String state(int b) {
    final (set, way) = find(b);
    return way < 0 ? 'I' : sets[set].ways[way].state;
  }

  void change(int b, String state) {
    final (set, way) = find(b);
    if (way >= 0) sets[set].ways[way].state = state;
  }

  void remove(int b) {
    final (set, way) = find(b);
    if (way >= 0) sets[set].ways[way].state = '';
  }

  void touch(int set, int way, bool fill) {
    if (policy == 'FIFO' && !fill) return;
    sets[set].ways[way].stamp = ++clock;
    if (policy == 'PLRU') {
      var node = 1, lo = 0, hi = sets[set].ways.length;
      while (hi - lo > 1) {
        final mid = (lo + hi) ~/ 2;
        if (way < mid) {
          sets[set].bits[node] = 1;
          node *= 2;
          hi = mid;
        } else {
          sets[set].bits[node] = 0;
          node = node * 2 + 1;
          lo = mid;
        }
      }
    }
  }

  void hit(int b) {
    final (set, way) = find(b);
    touch(set, way, false);
  }

  int victim(int set) {
    final a = sets[set];
    for (var i = 0; i < a.ways.length; i++) {
      if (a.ways[i].state.isEmpty) return i;
    }
    if (policy == 'PLRU') {
      var node = 1, lo = 0, hi = a.ways.length;
      while (hi - lo > 1) {
        final mid = (lo + hi) ~/ 2;
        if (a.bits[node] == 0) {
          node *= 2;
          hi = mid;
        } else {
          node = node * 2 + 1;
          lo = mid;
        }
      }
      return lo;
    }
    var way = 0;
    for (var i = 1; i < a.ways.length; i++) {
      if (a.ways[i].stamp < a.ways[way].stamp) way = i;
    }
    return way;
  }

  CacheLine fill(int b, String state) {
    final set = b % sets.length,
        way = victim(set),
        a = sets[set],
        old = a.ways[way];
    a.fills++;
    if (old.state.isNotEmpty) a.evictions++;
    a.ways[way] = CacheLine(b, state);
    touch(set, way, true);
    return old;
  }

  String replacement(int set) {
    final a = sets[set];
    if (policy == 'PLRU')
      return a.bits.length == 1 ? '-' : a.bits.skip(1).join();
    final ways = [
      for (var i = 0; i < a.ways.length; i++)
        if (a.ways[i].state.isNotEmpty) i,
    ]..sort((i, j) => a.ways[j].stamp.compareTo(a.ways[i].stamp));
    return ways.isEmpty ? '-' : ways.join(' ');
  }
}
