import 'dart:io';
import 'dart:math' as math;

const modes = ['FIRST', 'NEXT', 'BEST', 'WORST', 'SEGFIT', 'BUDDY'];
const counterNames = [
  'allocs',
  'frees',
  'reallocs',
  'moves',
  'failures',
  'collected',
];
bool power(int n) => n > 0 && (n & (n - 1)) == 0;
int sizeClass(int n) => n.bitLength - 1;
int random(int x) => x * 48271 % 2147483647;
int sum(Iterable<int> values) => values.fold(0, (a, b) => a + b);

class CommandError implements Exception {
  final String message;
  CommandError(this.message);
}

class Block {
  int start, size, requested = 0, stamp = 0;
  bool used = false;
  String owner = '';
  List<int> contents = [];
  Block(this.start, this.size);
  int get end => start + size;
  int get payload => start + 8;
  String get area => '$start+$size';
}

class Heap {
  final String mode;
  int size, rover = 0, age = 0;
  List<Block> blocks = [];
  Heap(this.mode, this.size) {
    blocks.add(register(Block(0, size)));
  }
  bool get buddy => mode == 'BUDDY';
  Block register(Block b) {
    b.stamp = ++age;
    return b;
  }

  int required(int n) {
    int s = (n + 7) ~/ 8 * 8 + 8;
    if (!buddy) return s;
    int p = 32;
    while (p < s) {
      p *= 2;
    }
    return p;
  }

  List<Block> get used => blocks.where((b) => b.used).toList();
  List<Block> get free => blocks.where((b) => !b.used).toList();
  int get total => sum(used.map((b) => b.size));
  int get frag {
    int f = sum(free.map((b) => b.size));
    int l = free.fold(0, (v, b) => math.max(v, b.size));
    return f == 0 ? 0 : (f - l) * 100 ~/ f;
  }

  int locate(int p) => blocks.indexWhere((b) => p < b.end);
  Block? allocate(int s, int al) {
    int ri = locate(rover), chosen = -1, placement = 0;
    int bestA = 1 << 60, bestB = 1 << 60;
    for (int i = 0; i < blocks.length; i++) {
      Block b = blocks[i];
      if (b.used) continue;
      int p = (b.start + 8 + al - 1) ~/ al * al - 8;
      if (p > b.start && p - b.start < 16) p += al;
      if (p + s > b.end) continue;
      int a, c;
      switch (mode) {
        case 'NEXT':
          {
            a = (i - ri + blocks.length) % blocks.length;
            c = 0;
          }
        case 'BEST':
        case 'BUDDY':
          {
            a = b.size;
            c = b.start;
          }
        case 'WORST':
          {
            a = -b.size;
            c = b.start;
          }
        case 'SEGFIT':
          {
            a = sizeClass(b.size);
            c = -b.stamp;
          }
        default:
          {
            a = b.start;
            c = 0;
          }
      }
      if (a < bestA || a == bestA && c < bestB) {
        chosen = i;
        placement = p;
        bestA = a;
        bestB = c;
      }
    }
    if (chosen < 0) return null;
    Block b;
    if (buddy) {
      b = blocks[chosen];
      halve(chosen, s);
    } else {
      Block old = blocks.removeAt(chosen);
      List<Block> parts = [];
      if (placement > old.start)
        parts.add(register(Block(old.start, placement - old.start)));
      b = Block(placement, old.end - placement);
      parts.add(b);
      if (b.size - s >= 16) {
        parts.add(register(Block(placement + s, b.size - s)));
        b.size = s;
      }
      blocks.insertAll(chosen, parts);
    }
    b.used = true;
    if (mode == 'NEXT') rover = b.end == size ? 0 : b.end;
    return b;
  }

  void halve(int i, int s) {
    Block b = blocks[i];
    while (b.size > s) {
      b.size ~/= 2;
      blocks.insert(i + 1, register(Block(b.end, b.size)));
    }
  }

  void merge(int i) {
    blocks[i].size += blocks.removeAt(i + 1).size;
  }

  (Block, int) coalesce(int i) {
    int merges = 0;
    if (buddy) {
      while (blocks[i].size < size) {
        Block b = blocks[i];
        int j = b.start % (2 * b.size) == 0 ? i + 1 : i - 1;
        if (j < 0 ||
            j >= blocks.length ||
            blocks[j].used ||
            blocks[j].size != b.size)
          break;
        i = math.min(i, j);
        merge(i);
        merges++;
      }
    } else {
      if (i + 1 < blocks.length && !blocks[i + 1].used) {
        merge(i);
        merges++;
      }
      if (i > 0 && !blocks[i - 1].used) {
        i--;
        merge(i);
        merges++;
      }
    }
    return (register(blocks[i]), merges);
  }

  (Block, int) release(Block b) {
    b.used = false;
    b.owner = '';
    b.requested = 0;
    b.contents = [];
    return coalesce(blocks.indexOf(b));
  }

  String? resize(Block b, int s) {
    int i = blocks.indexOf(b);
    if (s <= b.size) {
      if (buddy) {
        if (s == b.size) return 'kept';
        halve(i, s);
      } else {
        if (b.size - s < 16) return 'kept';
        blocks.insert(i + 1, Block(b.start + s, b.size - s));
        b.size = s;
        coalesce(i + 1);
      }
      return 'shrunk';
    }
    if (buddy) {
      int t = b.size, j = i;
      while (t < s) {
        j++;
        if (b.start % (2 * t) != 0 ||
            j >= blocks.length ||
            blocks[j].used ||
            blocks[j].size != t)
          return null;
        t *= 2;
      }
      blocks.removeRange(i + 1, j + 1);
      b.size = s;
    } else {
      if (i + 1 >= blocks.length ||
          blocks[i + 1].used ||
          b.size + blocks[i + 1].size < s)
        return null;
      int total = b.size + blocks.removeAt(i + 1).size;
      b.size = total - s >= 16 ? s : total;
      if (total - s >= 16)
        blocks.insert(i + 1, register(Block(b.end, total - s)));
    }
    return 'grown';
  }

  int trim() {
    int old = size;
    if (buddy) {
      while (!blocks.last.used && blocks.last.size * 2 == size) {
        blocks.removeLast();
        size ~/= 2;
      }
    } else if (blocks.length > 1 && !blocks.last.used) {
      size = blocks.removeLast().start;
    }
    if (rover >= size) rover = 0;
    return old - size;
  }
}

String experiment(String mode, int s, int seed, int ops, int maxreq) {
  Heap h = Heap(mode, s);
  List<Block> live = [];
  int x = seed, ok = 0, fail = 0, peak = 0;
  for (int i = 0; i < ops; i++) {
    x = random(x);
    bool alloc = live.isEmpty || x % 3 != 0;
    x = random(x);
    if (alloc) {
      Block? b = h.allocate(h.required(1 + x % maxreq), 8);
      if (b == null) {
        fail++;
      } else {
        ok++;
        live.add(b);
      }
    } else {
      h.release(live.removeAt(x % live.length));
    }
    peak = math.max(peak, h.total);
  }
  return 'BENCH $mode ok=$ok fail=$fail peak=$peak used=${h.total} frag=${h.frag} blocks=${h.blocks.length}';
}

class Allocator {
  Heap? heap;
  final Map<String, Block> live = {};
  final Set<String> freed = {}, roots = {};
  final Map<String, Set<String>> links = {};
  final Map<String, List<String>> history = {};
  List<int> counters = List.filled(6, 0);
  int peak = 0;
  final List<String> out = [];
  Never fail(String s) => throw CommandError(s);
  void record(String id, String s) {
    out.add(s);
    (history[id] ??= []).add(s);
  }

  Block block(String id) =>
      live[id] ??
      fail(freed.contains(id) ? 'USE AFTER FREE $id' : 'UNKNOWN ID $id');
  Block range(String id, int off, int len) {
    Block b = block(id);
    if (off + len > b.requested) fail('OUT OF BOUNDS $id');
    return b;
  }

  Never oom(String id) {
    counters[4]++;
    fail('OUT OF MEMORY $id');
  }

  void allocate(String kind, String id, int n, [int al = 8, int fill = -1]) {
    if (n == 0) fail('BAD SIZE');
    if (live.containsKey(id)) fail('DUPLICATE ID $id');
    Block b = heap!.allocate(heap!.required(n), al) ?? oom(id);
    b.owner = id;
    b.requested = n;
    b.contents = List.filled(n, fill);
    live[id] = b;
    freed.remove(id);
    counters[0]++;
    record(id, '$kind $id addr=${b.payload} block=${b.size}');
  }

  String release(String id) {
    Block b = live.remove(id)!;
    int size = b.size;
    freed.add(id);
    roots.remove(id);
    links.remove(id);
    for (Set<String> targets in links.values) {
      targets.remove(id);
    }
    final (f, merges) = heap!.release(b);
    return 'block=$size merges=$merges free=${f.area}';
  }

  void free(String id) {
    if (freed.contains(id)) fail('DOUBLE FREE $id');
    if (!live.containsKey(id)) fail('UNKNOWN ID $id');
    String detail = release(id);
    counters[1]++;
    record(id, 'FREE $id $detail');
  }

  void realloc(String id, int n) {
    if (n == 0) {
      free(id);
      return;
    }
    if (freed.contains(id)) fail('USE AFTER FREE $id');
    Block? original = live[id];
    if (original == null) {
      allocate('MALLOC', id, n);
      return;
    }
    Block b = original;
    List<int> contents = List.generate(
      n,
      (i) => i < original.requested ? original.contents[i] : -1,
    );
    int old = b.payload;
    String? kind = heap!.resize(b, heap!.required(n));
    if (kind == null) {
      Block moved = heap!.allocate(heap!.required(n), 8) ?? oom(id);
      moved.owner = id;
      live[id] = moved;
      heap!.release(b);
      b = moved;
      counters[3]++;
      kind = 'moved from=$old';
    }
    b.requested = n;
    b.contents = contents;
    counters[2]++;
    record(id, 'REALLOC $id addr=${b.payload} block=${b.size} $kind');
  }

  Set<String> reachable() {
    Set<String> seen = {...roots};
    List<String> stack = roots.toList();
    while (stack.isNotEmpty) {
      String id = stack.removeLast();
      for (String dst in links[id] ?? <String>{}) {
        if (seen.add(dst)) stack.add(dst);
      }
    }
    return seen;
  }

  void tree(int a, int s, int depth) {
    Block? b;
    for (Block candidate in heap!.blocks) {
      if (candidate.start == a && candidate.size == s) {
        b = candidate;
        break;
      }
    }
    String prefix = ''.padLeft(depth * 2) + '$a+$s';
    if (b != null) {
      out.add(prefix + (b.used ? ' USED ${b.owner}' : ' FREE'));
    } else {
      out.add('$prefix split');
      tree(a, s ~/ 2, depth + 1);
      tree(a + s ~/ 2, s ~/ 2, depth + 1);
    }
  }

  void execute(String line) {
    List<String> t = line.split(' '), a = line.split(' ').sublist(1);
    String cmd = t[0];
    int n(int i) => int.parse(a[i]);
    try {
      if (heap == null && cmd != 'HEAP' && cmd != 'BENCH') fail('NO HEAP');
      switch (cmd) {
        case 'HEAP':
          {
            int s = n(0);
            if (s < 32 ||
                s > 65536 ||
                s % 8 != 0 ||
                a[1] == 'BUDDY' && !power(s))
              fail('BAD HEAP SIZE');
            heap = Heap(a[1], s);
            live.clear();
            freed.clear();
            roots.clear();
            links.clear();
            history.clear();
            counters = List.filled(6, 0);
            peak = 0;
            out.add('HEAP size=$s mode=${a[1]}');
          }
        case 'BENCH':
          {
            int s = n(0);
            if (s < 32 || s > 65536 || !power(s)) fail('BAD HEAP SIZE');
            out.add('BENCH heap=$s seed=${a[1]} ops=${a[2]} maxreq=${a[3]}');
            for (String mode in modes) {
              out.add(experiment(mode, s, n(1), n(2), n(3)));
            }
          }
        case 'MALLOC':
          {
            allocate(cmd, a[0], n(1));
          }
        case 'CALLOC':
          {
            allocate(cmd, a[0], n(1) * n(2), 8, 0);
          }
        case 'MEMALIGN':
          {
            if (heap!.buddy) fail('UNSUPPORTED IN BUDDY MODE');
            if (n(1) < 8 || n(1) > 4096 || !power(n(1))) fail('BAD ALIGNMENT');
            allocate(cmd, a[0], n(2), n(1));
          }
        case 'REALLOC':
          {
            realloc(a[0], n(1));
          }
        case 'FREE':
          {
            free(a[0]);
          }
        case 'FILL':
          {
            Block b = range(a[0], n(1), n(2));
            b.contents.fillRange(n(1), n(1) + n(2), n(3));
            out.add('FILL ${a[0]} ${a[1]}+${a[2]} = ${a[3]}');
          }
        case 'COPY':
          {
            Block dst = range(a[0], n(1), n(4)), src = range(a[2], n(3), n(4));
            List<int> copy = src.contents.sublist(n(3), n(3) + n(4));
            dst.contents.setRange(n(1), n(1) + n(4), copy);
            out.add('COPY ${a[0]} ${a[1]}+${a[4]} from ${a[2]} ${a[3]}');
          }
        case 'READ':
          {
            Block b = range(a[0], n(1), n(2));
            String values = b.contents
                .sublist(n(1), n(1) + n(2))
                .map((v) => v < 0 ? '?' : '$v')
                .join(' ');
            out.add('READ ${a[0]} ${a[1]}+${a[2]} = $values');
          }
        case 'ROOT':
        case 'UNROOT':
          {
            block(a[0]);
            if (cmd == 'ROOT') {
              roots.add(a[0]);
            } else if (!roots.remove(a[0])) {
              fail('NOT ROOT ${a[0]}');
            }
            out.add('$cmd ${a[0]}');
          }
        case 'LINK':
        case 'UNLINK':
          {
            block(a[0]);
            block(a[1]);
            if (cmd == 'LINK') {
              (links[a[0]] ??= {}).add(a[1]);
            } else if (links[a[0]]?.remove(a[1]) != true) {
              fail('NO LINK ${a[0]} ${a[1]}');
            }
            out.add('$cmd ${a[0]} ${a[1]}');
          }
        case 'GC':
          {
            Set<String> seen = reachable();
            List<Block> garbage = heap!.used
                .where((b) => !seen.contains(b.owner))
                .toList();
            out.add(
              'GC collected=${garbage.length} bytes=${sum(garbage.map((b) => b.size))}',
            );
            for (Block b in garbage) {
              String id = b.owner;
              record(id, 'COLLECT $id ${release(id)}');
            }
            counters[5] += garbage.length;
          }
        case 'SBRK':
          {
            Heap h = heap!;
            int k = n(0);
            bool valid = h.buddy
                ? k == h.size && h.size * 2 <= 65536
                : k >= 16 && k % 8 == 0 && h.size + k <= 65536;
            if (!valid) fail('BAD SBRK SIZE');
            h.blocks.add(Block(h.size, k));
            h.size += k;
            Block f = h.coalesce(h.blocks.length - 1).$1;
            out.add('SBRK heap=${h.size} free=${f.area}');
          }
        case 'TRIM':
          {
            int released = heap!.trim();
            out.add('TRIM heap=${heap!.size} released=$released');
          }
        case 'COMPACT':
          {
            Heap h = heap!;
            if (h.buddy) fail('UNSUPPORTED IN BUDDY MODE');
            List<Block> used = h.used;
            List<(Block, int)> moved = [];
            int pos = 0;
            for (Block b in used) {
              if (b.start != pos) {
                moved.add((b, b.payload));
                b.start = pos;
              }
              pos += b.size;
            }
            if (pos < h.size) used.add(h.register(Block(pos, h.size - pos)));
            h.blocks = used;
            h.rover = 0;
            counters[3] += moved.length;
            String f = pos < h.size ? '$pos+${h.size - pos}' : 'none';
            out.add('COMPACT moved=${moved.length} free=$f');
            for (final (b, old) in moved) {
              record(b.owner, 'MOVE ${b.owner} $old -> ${b.payload}');
            }
          }
        case 'WHO':
          {
            Heap h = heap!;
            int p = n(0);
            String detail;
            if (p >= h.size) {
              detail = 'outside';
            } else {
              Block b = h.blocks[h.locate(p)];
              if (!b.used) {
                detail = 'free ${b.area}';
              } else if (p < b.payload) {
                detail = 'header ${b.owner}';
              } else {
                detail =
                    '${p - b.payload < b.requested ? 'data' : 'slack'} ${b.owner}+${p - b.payload}';
              }
            }
            out.add('WHO $p $detail');
          }
        case 'DUMP':
          {
            Heap h = heap!;
            out.add(
              'DUMP mode=${h.mode} heap=${h.size} blocks=${h.blocks.length}${h.mode == 'NEXT' ? ' rover=${h.rover}' : ''}',
            );
            for (Block b in h.blocks) {
              out.add(
                '${b.start} ${b.size} ${b.used ? 'USED ${b.owner} req=${b.requested}' : 'FREE'}',
              );
            }
          }
        case 'MAP':
          {
            Heap h = heap!;
            out.add('MAP heap=${h.size}');
            StringBuffer units = StringBuffer();
            for (Block b in h.blocks) {
              units.write(b.used ? 'H' : 'F');
              for (int i = 0; i < b.size ~/ 8 - 1; i++) {
                units.write(
                  !b.used
                      ? '.'
                      : i * 8 < b.requested
                      ? '#'
                      : '-',
                );
              }
            }
            String all = units.toString();
            for (int i = 0; i < all.length; i += 64) {
              out.add(
                '${(i * 8).toString().padLeft(5, '0')} ${all.substring(i, math.min(i + 64, all.length))}',
              );
            }
          }
        case 'FREELIST':
          {
            Heap h = heap!;
            List<Block> free = h.free;
            if (h.mode == 'SEGFIT')
              free.sort((a, b) => b.stamp.compareTo(a.stamp));
            out.add('FREELIST count=${free.length}');
            Map<int, List<Block>> groups = {};
            for (Block b in free) {
              (groups[sizeClass(b.size)] ??= []).add(b);
            }
            for (int k in groups.keys.toList()..sort()) {
              out.add(
                '${1 << k}-${(1 << (k + 1)) - 1}: ${groups[k]!.map((b) => b.area).join(' ')}',
              );
            }
          }
        case 'TREE':
          {
            if (!heap!.buddy) fail('REQUIRES BUDDY MODE');
            out.add('TREE heap=${heap!.size}');
            tree(0, heap!.size, 0);
          }
        case 'STATS':
          {
            Heap h = heap!;
            List<Block> used = h.used, free = h.free;
            int largest = free.fold(0, (v, b) => math.max(v, b.size));
            out.add(
              'STATS used=${h.total} used_blocks=${used.length} free=${sum(free.map((b) => b.size))} free_blocks=${free.length} largest=$largest frag=${h.frag} requested=${sum(used.map((b) => b.requested))} peak=$peak',
            );
            out.add(
              'OPS ${List.generate(6, (i) => '${counterNames[i]}=${counters[i]}').join(' ')}',
            );
          }
        case 'LEAKS':
          {
            Set<String> seen = reachable();
            out.add(
              'LEAKS count=${live.length} requested=${sum(live.values.map((b) => b.requested))} lost=${live.keys.where((id) => !seen.contains(id)).length}',
            );
            for (String id in live.keys.toList()..sort()) {
              Block b = live[id]!;
              out.add(
                'LEAK $id addr=${b.payload} block=${b.size} req=${b.requested} ${seen.contains(id) ? 'reachable' : 'lost'}',
              );
            }
          }
        case 'HISTORY':
          {
            List<String> events = history[a[0]] ?? [];
            out.add('HISTORY ${a[0]} events=${events.length}');
            out.addAll(events);
          }
      }
    } on CommandError catch (e) {
      out.add('ERROR ${e.message}');
    }
    if (heap != null) peak = math.max(peak, heap!.total);
  }
}

void main() {
  int count = int.parse(stdin.readLineSync()!);
  Allocator allocator = Allocator();
  for (int i = 0; i < count; i++) {
    allocator.execute(stdin.readLineSync()!);
  }
  stdout.write('${allocator.out.join('\n')}\n');
}
