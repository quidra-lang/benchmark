import 'dart:io';
import 'dart:math' as math;

const policies = ['FIFO', 'LRU', 'LFU', 'NRU', 'AGING', 'CLOCK', 'ECLOCK', 'WSCLOCK', 'RANDOM', 'OPT'];
final List<String> output = [];
String hex(int value) => '0x${value.toRadixString(16).toUpperCase()}';
int address(String s) => int.parse(s.substring(2), radix: 16);
String decimal(int v) => '${v ~/ 100}.${(v % 100).toString().padLeft(2, '0')}';
String ratio(int x, int y) => '${decimal(y == 0 ? 0 : x * 10000 ~/ y)}%';
class CommandError implements Exception {
  final String message;
  CommandError(this.message);
}
class Config {
  int page = 256, frames = 4, tlb = 4, sets = 1, tick = 0, tau = 8, seed = 1;
  String policy = 'FIFO', scope = 'GLOBAL', asid = 'OFF';
  Config copy() => Config()
    ..page = page ..frames = frames ..tlb = tlb ..sets = sets ..tick = tick ..tau = tau
    ..seed = seed ..policy = policy ..scope = scope ..asid = asid;
  String description() => 'SYSTEM page=$page frames=$frames tlb=$tlb sets=$sets policy=$policy scope=$scope asid=$asid tick=$tick tau=$tau seed=$seed';
}
Config settings(List<String> tokens) {
  Config c = Config();
  Set<String> seen = {};
  for (String token in tokens.skip(1)) {
    List<String> pair = token.split('=');
    String key = pair[0], value = pair[1];
    if (!['page', 'frames', 'tlb', 'sets', 'policy', 'scope', 'asid', 'tick', 'tau', 'seed'].contains(key)) throw CommandError('unknown key $key');
    if (!seen.add(key)) throw CommandError('duplicate key $key');
    bool valid;
    if (key == 'policy') { valid = policies.contains(value); if (valid) c.policy = value; }
    else if (key == 'scope') { valid = ['GLOBAL', 'LOCAL'].contains(value); if (valid) c.scope = value; }
    else if (key == 'asid') { valid = ['ON', 'OFF'].contains(value); if (valid) c.asid = value; }
    else {
      int n = int.parse(value);
      valid = switch (key) {
        'page' => n >= 16 && n <= 4096 && (n & (n - 1)) == 0,
        'frames' => n >= 1 && n <= 16,
        'tlb' || 'sets' => n >= 1 && n <= 8,
        'tick' => n >= 0 && n <= 1000,
        'tau' => n >= 1 && n <= 1000,
        _ => n >= 1 && n <= 2147483646,
      };
      if (valid) {
        switch (key) {
          case 'page': {
            c.page = n;
          }
          case 'frames': {
            c.frames = n;
          }
          case 'tlb': {
            c.tlb = n;
          }
          case 'sets': {
            c.sets = n;
          }
          case 'tick': {
            c.tick = n;
          }
          case 'tau': {
            c.tau = n;
          }
          case 'seed': {
            c.seed = n;
          }
        }
      }
    }
    if (!valid) throw CommandError('invalid $key');
  }
  if (c.tlb % c.sets != 0) throw CommandError('invalid sets');
  return c;
}
class Page {
  final int pid, number;
  int frame = -1, slot = -1, r = 0, m = 0, load = 0, last = 0, uses = 0, age = 0, references = 0;
  bool ro = false, locked = false, ever = false;
  Page(this.pid, this.number);
  String label() => 'P$pid:$number';
}
class Process {
  final int pid;
  late final List<Page> pages;
  int accesses = 0, faults = 0, writebacks = 0, segfaults = 0, protfaults = 0, peak = 0, hand = 0;
  bool exited = false;
  final List<int> history = [];
  Process(this.pid, int count) { pages = List.generate(count, (i) => Page(pid, i)); }
  int resident() => pages.where((p) => p.frame >= 0).length;
}
class Access {
  final int pid, address;
  final String op;
  Access(this.pid, this.op, this.address);
}
class Log {
  final String kind, op;
  final int pid, a, b;
  Log(this.kind, this.pid, this.op, this.a, this.b);
}
class Simulation {
  final Config c;
  final Map<int, Process> processes = {};
  late final List<Page?> frames;
  late final List<List<Page>> tlb;
  final Map<int, Page> swap = {};
  final List<Access> future;
  int cursor = -1, time = 0, faults = 0, zero = 0, swapin = 0, tlbhits = 0, writebacks = 0, switches = 0, previous = -1, hand = 0;
  late int random;
  bool fixed = false, trace = false;
  final bool silent;
  final List<bool> faultHistory = [];
  final List<Log> log = [];
  Simulation(this.c, this.future, this.silent) {
    random = c.seed; frames = List.filled(c.frames, null); tlb = List.generate(c.sets, (_) => []);
  }
  List<int> get pids => processes.keys.toList()..sort();
  void emit(String text) { if (!silent) output.add(text); }
  Process process(int pid) {
    Process? p = processes[pid];
    if (p == null) throw CommandError('unknown process $pid');
    if (p.exited) throw CommandError('process $pid exited');
    return p;
  }
  int quota(int pid) => c.frames ~/ processes.length + (pids.indexOf(pid) < c.frames % processes.length ? 1 : 0);
  void declare(int pid, int count) {
    if (fixed) throw CommandError('processes are fixed');
    if (processes.containsKey(pid)) throw CommandError('duplicate process $pid');
    if (count < 1 || count > 256) throw CommandError('invalid page count');
    if (processes.length >= 8 || c.scope == 'LOCAL' && processes.length == c.frames) throw CommandError('too many processes');
    processes[pid] = Process(pid, count);
  }
  void invalidate(Page page) { for (List<Page> set in tlb) { set.remove(page); } }
  void write(Page p) {
    writebacks++; processes[p.pid]!.writebacks++; p.m = 0;
    if (p.slot < 0) {
      int slot = 0;
      while (swap.containsKey(slot)) { slot++; }
      p.slot = slot; swap[slot] = p;
    }
  }
  int nextUse(Page p) {
    for (int i = cursor + 1; i < future.length; i++) {
      Access a = future[i];
      if (a.pid == p.pid && a.address ~/ c.page == p.number) return i;
    }
    return 1 << 30;
  }
  int choose(List<int> candidates, Process owner) {
    List<int> unlocked = candidates.where((f) => !frames[f]!.locked).toList();
    if (unlocked.isNotEmpty) candidates = unlocked;
    if (c.policy == 'RANDOM') {
      random = random * 48271 % 2147483647;
      return candidates[random % candidates.length];
    }
    if (!['CLOCK', 'ECLOCK', 'WSCLOCK'].contains(c.policy)) {
      (int, int) rank(int f) {
        Page p = frames[f]!;
        return switch (c.policy) {
          'FIFO' => (p.load, 0),
          'LRU' => (p.last, 0),
          'LFU' => (p.uses, p.load),
          'NRU' => (2 * p.r + p.m, f),
          'AGING' => (p.age, p.load),
          _ => (-nextUse(p), f),
        };
      }
      candidates.sort((a, b) {
        final x = rank(a), y = rank(b);
        int first = x.$1.compareTo(y.$1);
        return first != 0 ? first : x.$2.compareTo(y.$2);
      });
      return candidates.first;
    }
    int h = c.scope == 'GLOBAL' ? hand : owner.hand;
    candidates.sort((a, b) => ((a - h + c.frames) % c.frames).compareTo((b - h + c.frames) % c.frames));
    int chosen = -1;
    if (c.policy == 'CLOCK') {
      while (chosen < 0) {
        for (int f in candidates) {
          if (frames[f]!.r == 0) { chosen = f; break; }
          frames[f]!.r = 0;
        }
      }
    } else if (c.policy == 'ECLOCK') {
      while (chosen < 0) {
        for (int f in candidates) { if (frames[f]!.r == 0 && frames[f]!.m == 0) { chosen = f; break; } }
        if (chosen >= 0) break;
        for (int f in candidates) {
          if (frames[f]!.r == 0 && frames[f]!.m == 1) { chosen = f; break; }
          frames[f]!.r = 0;
        }
      }
    } else {
      for (int f in candidates) {
        Page p = frames[f]!;
        if (p.r == 1) { p.r = 0; p.last = time; }
        else if (time - p.last > c.tau) {
          if (p.m == 0) { chosen = f; break; }
          write(p);
        }
      }
      if (chosen < 0) {
        for (int f in candidates) { if (frames[f]!.m == 0) { chosen = f; break; } }
        if (chosen < 0) chosen = candidates.first;
      }
    }
    if (c.scope == 'GLOBAL') { hand = (chosen + 1) % c.frames; }
    else { owner.hand = (chosen + 1) % c.frames; }
    return chosen;
  }
  void access(int pid, String op, int addr) {
    fixed = true; cursor++;
    Process owner = process(pid);
    if (addr >= owner.pages.length * c.page) { owner.segfaults++; emit('SEGFAULT P$pid ${hex(addr)}'); return; }
    Page p = owner.pages[addr ~/ c.page];
    if (op == 'W' && p.ro) { owner.protfaults++; emit('PROTFAULT P$pid ${hex(addr)}'); return; }
    time++; owner.accesses++;
    bool switched = previous >= 0 && previous != pid;
    if (switched) {
      switches++;
      if (c.asid == 'OFF') { for (List<Page> set in tlb) { set.clear(); } }
    }
    previous = pid;
    List<Page> set = tlb[p.number % c.sets];
    bool hit = set.remove(p), fault = false;
    String result;
    if (hit) { tlbhits++; result = 'TLBHIT'; }
    else if (p.frame >= 0) { result = 'HIT'; }
    else {
      fault = true; faults++; owner.faults++;
      if (p.slot >= 0) { swapin++; result = 'FAULT SWAPIN'; }
      else { zero++; result = 'FAULT ZERO'; }
      int frame = -1;
      bool mayUseFree = c.scope == 'GLOBAL' || owner.resident() < quota(pid);
      if (mayUseFree) {
        for (int i = 0; i < frames.length; i++) { if (frames[i] == null) { frame = i; break; } }
      }
      if (frame < 0) {
        List<int> candidates = [];
        for (int i = 0; i < frames.length; i++) { if (frames[i] != null && (c.scope == 'GLOBAL' || frames[i]!.pid == pid)) candidates.add(i); }
        frame = choose(candidates, owner);
        Page victim = frames[frame]!;
        result += ' evict=${victim.label()}'; invalidate(victim);
        if (victim.m == 1) { write(victim); result += ' writeback'; }
        victim.frame = -1;
      }
      frames[frame] = p; p.frame = frame; p.load = time; p.uses = 0; p.m = 0; p.age = 0;
      owner.peak = math.max(owner.peak, owner.resident());
    }
    if (set.length == c.tlb ~/ c.sets) set.removeAt(0);
    set.add(p);
    p.r = 1; if (op == 'W') p.m = 1;
    p.last = time; p.uses++; p.ever = true; p.references++;
    owner.history.add(p.number); faultHistory.add(fault); log.add(Log('ACCESS', pid, op, addr, 0));
    bool interrupt = c.tick > 0 && time % c.tick == 0;
    if (interrupt) {
      for (Page? page in frames) { if (page != null) { page.age = page.age ~/ 2 + 128 * page.r; page.r = 0; } }
    }
    if (trace) {
      emit('t=$time P$pid $op ${hex(addr)} page=${p.number} frame=${p.frame} phys=${hex(p.frame * c.page + addr % c.page)} $result${switched ? ' switch' : ''}');
      if (interrupt) emit('t=$time tick');
    }
  }
  void exit(int pid) {
    Process p = process(pid);
    int count = 0, slots = 0;
    for (Page page in p.pages) {
      if (page.frame >= 0) { frames[page.frame] = null; page.frame = -1; count++; }
      invalidate(page);
      if (page.slot >= 0) { swap.remove(page.slot); page.slot = -1; slots++; }
    }
    p.exited = true; log.add(Log('EXIT', pid, '', 0, 0));
    emit('EXIT P$pid freed=$count slots=$slots');
  }
  void attributes(String cmd, int pid, int first, int last, String protection) {
    Process p = process(pid);
    if (first > last || last >= p.pages.length) throw CommandError('invalid page range');
    for (int i = first; i <= last; i++) {
      if (cmd == 'PROTECT') { p.pages[i].ro = protection == 'RO'; }
      else { p.pages[i].locked = cmd == 'LOCK'; }
    }
    if (cmd != 'PROTECT') log.add(Log(cmd, pid, '', first, last));
  }
  void clean() {
    int count = 0;
    for (Page? p in frames) { if (p != null && p.m == 1) { write(p); count++; } }
    log.add(Log('CLEAN', 0, '', 0, 0)); emit('CLEAN written=$count');
  }
  Simulation rerun(String policy, int count) {
    Config config = c.copy()..policy = policy ..frames = count;
    List<Access> references = log.where((e) => e.kind == 'ACCESS').map((e) => Access(e.pid, e.op, e.a)).toList();
    Simulation replay = Simulation(config, references, true);
    for (int pid in pids) { replay.declare(pid, processes[pid]!.pages.length); }
    for (Log e in log) {
      switch (e.kind) {
        case 'ACCESS': {
          replay.access(e.pid, e.op, e.a);
        }
        case 'EXIT': {
          replay.exit(e.pid);
        }
        case 'CLEAN': {
          replay.clean();
        }
        default: {
          replay.attributes(e.kind, e.pid, e.a, e.b, '');
        }
      }
    }
    return replay;
  }
  void summary() {
    emit('SUMMARY policy=${c.policy} scope=${c.scope} time=$time');
    int seg = processes.values.fold(0, (v, p) => v + p.segfaults), prot = processes.values.fold(0, (v, p) => v + p.protfaults);
    emit('total faults=$faults zero=$zero swapin=$swapin faultrate=${ratio(faults, time)} tlbhits=$tlbhits tlbrate=${ratio(tlbhits, time)} writebacks=$writebacks switches=$switches segfaults=$seg protfaults=$prot');
    for (int pid in pids) {
      Process p = processes[pid]!;
      emit('P$pid accesses=${p.accesses} faults=${p.faults} writebacks=${p.writebacks} segfaults=${p.segfaults} protfaults=${p.protfaults} resident=${p.resident()} peak=${p.peak}${c.scope == 'LOCAL' ? ' quota=${quota(pid)}' : ''}${p.exited ? ' exited' : ''}');
    }
  }
  void frameDump() {
    emit('FRAMES used=${frames.where((p) => p != null).length}/${c.frames}');
    for (int i = 0; i < frames.length; i++) {
      Page? p = frames[i];
      emit(p == null ? '$i free' : '$i ${p.label()} R=${p.r} M=${p.m} load=${p.load} last=${p.last} uses=${p.uses} age=${p.age}${p.locked ? ' locked' : ''}');
    }
    if (['CLOCK', 'ECLOCK', 'WSCLOCK'].contains(c.policy)) {
      if (c.scope == 'GLOBAL') { emit('hand=$hand'); }
      else { emit('hand${pids.map((pid) => ' P$pid=${processes[pid]!.hand}').join()}'); }
    }
  }
  void pageTable(int pid) {
    Process p = process(pid);
    emit('PAGETABLE P$pid pages=${p.pages.length} resident=${p.resident()}');
    for (Page page in p.pages.where((p) => p.ever)) {
      String info = page.frame >= 0 ? 'frame=${page.frame} R=${page.r} M=${page.m}' : page.slot >= 0 ? 'swap=${page.slot}' : 'zero';
      emit('${page.number} $info${page.ro ? ' RO' : ''}${page.locked ? ' locked' : ''}');
    }
  }
  void tlbDump() {
    int used = tlb.fold(0, (v, set) => v + set.length);
    emit('TLB used=$used/${c.tlb} sets=${c.sets}');
    for (int i = 0; i < tlb.length; i++) { emit('set $i:${tlb[i].reversed.map((p) => ' ${p.label()}->${p.frame}').join()}'); }
  }
  void compare() {
    emit('COMPARE accesses=$time frames=${c.frames}');
    Map<String, Simulation> results = {};
    for (String policy in policies) {
      Simulation r = rerun(policy, c.frames); results[policy] = r;
      emit('$policy faults=${r.faults} writebacks=${r.writebacks} tlbhits=${r.tlbhits}');
    }
    List<String> ranking = [...policies]..sort((a, b) {
      int d = results[a]!.faults.compareTo(results[b]!.faults);
      if (d != 0) return d;
      d = results[a]!.writebacks.compareTo(results[b]!.writebacks);
      return d != 0 ? d : policies.indexOf(a).compareTo(policies.indexOf(b));
    });
    emit('ranking ${ranking.join(' ')}');
  }
  void execute(List<String> t) {
    String cmd = t[0];
    int n(int i) => int.parse(t[i]);
    if (int.tryParse(cmd) != null) { access(n(0), t[1], address(t[2])); return; }
    switch (cmd) {
      case 'PROCESS': {
        declare(n(1), n(2));
      }
      case 'EXIT': {
        exit(n(1));
      }
      case 'PROTECT':
      case 'LOCK':
      case 'UNLOCK': {
        attributes(cmd, n(1), n(2), n(3), t.length > 4 ? t[4] : '');
      }
      case 'TRACE': {
        trace = t[1] == 'ON';
      }
      case 'SUMMARY': {
        summary();
      }
      case 'FRAMES': {
        frameDump();
      }
      case 'PAGETABLE': {
        pageTable(n(1));
      }
      case 'TLB': {
        tlbDump();
      }
      case 'SWAP': {
        emit('SWAP used=${swap.length}');
        for (int slot in swap.keys.toList()..sort()) { emit('$slot ${swap[slot]!.label()}'); }
      }
      case 'CLEAN': {
        clean();
      }
      case 'COMPARE': {
        compare();
      }
      case 'CURVE': {
        String policy = t[1]; int lo = n(2), hi = n(3);
        if (!policies.contains(policy)) throw CommandError('unknown policy');
        if (lo < 1 || lo > hi || hi > 16 || c.scope == 'LOCAL' && lo < processes.length) throw CommandError('invalid frame range');
        emit('CURVE $policy frames=$lo..$hi');
        int prior = 1 << 30;
        for (int f = lo; f <= hi; f++) {
          int value = rerun(policy, f).faults;
          emit('F=$f faults=$value${value > prior ? ' ANOMALY' : ''}'); prior = value;
        }
      }
      case 'EAT': {
        int total = n(1) * time + n(2) * (2 * time - tlbhits) + n(3) * (swapin + writebacks);
        emit(time == 0 ? 'EAT accesses=0' : 'EAT accesses=$time total=$total average=${decimal(total * 100 ~/ time)}');
      }
      case 'TIMELINE': {
        int w = n(1);
        if (w < 1) throw CommandError('invalid window');
        StringBuffer text = StringBuffer('TIMELINE window=$w');
        for (int i = 0; i < faultHistory.length; i += w) { text.write(' ${faultHistory.sublist(i, math.min(i + w, faultHistory.length)).where((v) => v).length}'); }
        emit(text.toString());
      }
      case 'WSET': {
        int pid = n(1); Process p = process(pid); int w = n(2);
        if (w < 1) throw CommandError('invalid window');
        List<int> pages = p.history.skip(math.max(0, p.history.length - w)).toSet().toList()..sort();
        emit('WSET P$pid window=$w size=${pages.length}${pages.map((p) => ' $p').join()}');
      }
      case 'HOT': {
        int pid = n(1); Process p = process(pid); int k = n(2);
        if (k < 1) throw CommandError('invalid count');
        List<Page> pages = p.pages.where((p) => p.references > 0).toList()..sort((a, b) => a.references != b.references ? b.references.compareTo(a.references) : a.number.compareTo(b.number));
        emit('HOT P$pid${pages.take(k).map((p) => ' ${p.number}:${p.references}').join()}');
      }
    }
  }
}
void main() {
  int count = int.parse(stdin.readLineSync()!);
  List<List<String>> commands = [];
  for (int i = 0; i < count; i++) {
    List<String> t = stdin.readLineSync()!.split(' ');
    if (t[0] == 'LOOP') {
      int start = address(t[3]), interval = int.parse(t[4]), length = int.parse(t[5]), repeats = int.parse(t[6]);
      for (int r = 0; r < repeats; r++) {
        for (int j = 0; j < length; j++) { commands.add([t[1], t[2], hex(start + j * interval)]); }
      }
    } else if (t[0] == 'RAND') {
      int lo = address(t[2]), hi = address(t[3]), count = int.parse(t[4]), rate = int.parse(t[6]), x = int.parse(t[5]);
      for (int j = 0; j < count; j++) {
        x = x * 48271 % 2147483647; int addr = lo + x % (hi - lo);
        x = x * 48271 % 2147483647;
        commands.add([t[1], x % 100 < rate ? 'W' : 'R', hex(addr)]);
      }
    } else { commands.add(t); }
  }
  Simulation? simulation;
  for (int i = 0; i < commands.length; i++) {
    List<String> t = commands[i];
    try {
      if (t[0] == 'SYSTEM') {
        simulation = null;
        Config c = settings(t);
        List<Access> future = [];
        for (int j = i + 1; j < commands.length && commands[j][0] != 'SYSTEM'; j++) {
          List<String> entry = commands[j];
          if (int.tryParse(entry[0]) != null) future.add(Access(int.parse(entry[0]), entry[1], address(entry[2])));
        }
        simulation = Simulation(c, future, false); output.add(c.description());
      } else if (simulation == null) { output.add('ERROR no system'); }
      else { simulation.execute(t); }
    } on CommandError catch (e) { output.add('ERROR ${e.message}'); }
  }
  if (output.isNotEmpty) stdout.write('${output.join('\n')}\n');
}
