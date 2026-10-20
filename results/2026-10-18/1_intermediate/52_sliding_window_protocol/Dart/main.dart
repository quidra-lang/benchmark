import 'dart:io';
import 'dart:math' as math;

const keys = ['PROTOCOL', 'FRAMES', 'WINDOW', 'SEQBITS', 'TIMEOUT', 'DELAY', 'INTERVAL', 'MAXTICKS', 'DUPACK', 'NAK', 'BACKOFF', 'CONGESTION', 'UNSAFE', 'TRACE', 'RANDOM', 'LOSEDATA', 'LOSECTRL', 'CORRUPTDATA', 'CORRUPTCTRL', 'DELAYDATA', 'DELAYCTRL', 'SNAPSHOT'];
final List<String> output = [];
String fixed(int n, int d, int digits) {
  int scale = digits == 2 ? 100 : 10;
  int v = d == 0 ? 0 : n * scale ~/ d;
  return '${v ~/ scale}.${(v % scale).toString().padLeft(digits, '0')}';
}
String tick(int t) => t < 0 ? '-' : '$t';
String onOff(bool value) => value ? 'on' : 'off';
class Scenario {
  final String name;
  String protocol = '', trace = 'ALL';
  String? error;
  final Map<String, List<String>> values = {};
  final Map<String, Set<int>> lists = {};
  final Map<String, Map<int, int>> delays = {};
  int n = 0, w = 0, k = 0, timeout = 0, delay = 0, interval = 0, limit = 1000, dupack = 0;
  bool nak = false, backoff = false, congestion = false, unsafe = false, random = false;
  int seed = 0, loss = 0, corruption = 0;
  int completion = -1, end = 0, delivered = 0, data = 0;
  Scenario(this.name);
  int number(String key) => int.parse(values[key]![0]);
  bool on(String key) => values[key]?[0] == 'ON';
  void line(List<String> words) {
    if (error != null) return;
    String key = words[0];
    int pos = keys.indexOf(key);
    if (pos < 0) { error = 'unknown key $key'; return; }
    if (values.containsKey(key)) { error = 'duplicate key $key'; return; }
    int count = words.length - 1;
    bool bad = key == 'RANDOM' ? count != 3 : pos >= 15 ? count < 1 : count != 1;
    if (bad) { error = 'wrong number of values for $key'; return; }
    values[key] = words.sublist(1);
  }
  bool valid(String key) {
    List<String> v = values[key]!;
    if (key == 'PROTOCOL') return ['SW', 'GBN', 'SR'].contains(v[0]);
    if (['NAK', 'BACKOFF', 'CONGESTION', 'UNSAFE'].contains(key)) return ['ON', 'OFF'].contains(v[0]);
    if (key == 'TRACE') return ['ALL', 'SENDER', 'RECEIVER', 'NONE'].contains(v[0]);
    if (key == 'RANDOM') {
      int s = int.parse(v[0]), p = int.parse(v[1]), c = int.parse(v[2]);
      return s >= 1 && s <= 2147483646 && p >= 0 && c >= 0 && p + c <= 100;
    }
    if (keys.indexOf(key) >= 15) {
      Set<int> found = {};
      Map<int, int> extra = {};
      bool delayed = key.startsWith('DELAY');
      for (String item in v) {
        List<String> pair = item.split(':');
        int a = int.parse(pair[0]);
        bool snapshot = key == 'SNAPSHOT';
        if (a < (snapshot ? 0 : 1) || a > (snapshot ? 2000 : 9999) || !found.add(a)) return false;
        if (delayed) {
          int e = int.parse(pair[1]);
          if (e < 1 || e > 50) return false;
          extra[a] = e;
        }
      }
      lists[key] = found;
      if (delayed) delays[key] = extra;
      return true;
    }
    int a = number(key), lo = 1, hi = 0;
    switch (key) {
      case 'FRAMES': {
        hi = 60;
      }
      case 'WINDOW': {
        hi = 32;
      }
      case 'SEQBITS': {
        hi = 6;
      }
      case 'TIMEOUT': {
        hi = 50;
      }
      case 'DELAY':
      case 'DUPACK': {
        hi = 10;
      }
      case 'INTERVAL': {
        lo = 0; hi = 10;
      }
      case 'MAXTICKS': {
        hi = 2000;
      }
    }
    return a >= lo && a <= hi;
  }
  void check() {
    if (error != null) return;
    for (String key in keys.take(6)) {
      if (!values.containsKey(key)) { error = 'missing key $key'; return; }
    }
    for (String key in keys) {
      if (values.containsKey(key) && !valid(key)) { error = 'bad value for $key'; return; }
    }
    protocol = values['PROTOCOL']![0];
    n = number('FRAMES'); w = number('WINDOW'); k = number('SEQBITS'); timeout = number('TIMEOUT'); delay = number('DELAY');
    if (values.containsKey('INTERVAL')) interval = number('INTERVAL');
    if (values.containsKey('MAXTICKS')) limit = number('MAXTICKS');
    if (values.containsKey('DUPACK')) dupack = number('DUPACK');
    nak = on('NAK'); backoff = on('BACKOFF'); congestion = on('CONGESTION'); unsafe = on('UNSAFE');
    if (values.containsKey('TRACE')) trace = values['TRACE']![0];
    random = values.containsKey('RANDOM');
    if (random) {
      List<String> v = values['RANDOM']!;
      seed = int.parse(v[0]); loss = int.parse(v[1]); corruption = int.parse(v[2]);
    }
    if (protocol == 'SR' && dupack > 0) { error = 'DUPACK not supported for SR'; return; }
    int upper = protocol == 'SW' ? 1 : protocol == 'GBN' ? (1 << k) - 1 : 1 << (k - 1);
    if (w > upper && !(unsafe && protocol != 'SW')) { error = 'window $w exceeds limit $upper for $protocol'; return; }
    for (String kind in ['DATA', 'CTRL']) {
      List<int> both = (lists['LOSE$kind'] ?? <int>{}).intersection(lists['CORRUPT$kind'] ?? {}).toList()..sort();
      if (both.isNotEmpty) { error = '${kind == 'DATA' ? 'data' : 'control'} #${both.first} both lost and corrupted'; return; }
    }
  }
  bool contains(String key, int i) => lists[key]?.contains(i) ?? false;
  int extra(String key, int i) => delays[key]?[i] ?? 0;
}
class Event {
  final int arrival, number, value, outcome;
  final String kind;
  Event(this.arrival, this.number, this.value, this.outcome, this.kind);
}
class Simulation {
  final Scenario s;
  late final int modulus;
  late final bool sr;
  int t = 0, base = 0, high = 0, next = 0, timer = -1, length = 0, duplicates = 0, r = 0;
  bool nakSent = false;
  int cwnd = 1, threshold = 0, growth = 0;
  int controlCount = 0, naks = 0, resent = 0, timeouts = 0, fast = 0;
  int lostData = 0, lostControl = 0, corruptData = 0, corruptControl = 0;
  int errors = 0, discarded = 0, maxBuffer = 0, latency = 0, random = 0;
  late final List<int> tx, first, delivery, acked, timers;
  late final List<bool> marks;
  final List<int> queue = [];
  final Map<int, int> buffer = {};
  final List<Event> dataEvents = [], controlEvents = [];
  Simulation(this.s) {
    modulus = 1 << s.k; sr = s.protocol == 'SR'; length = s.timeout; threshold = s.w; random = s.seed;
    tx = List.filled(s.n, 0); first = List.filled(s.n, -1); delivery = List.filled(s.n, -1);
    acked = List.filled(s.n, -1); timers = List.filled(s.n, -1); marks = List.filled(s.n, false);
  }
  int mod(int a) => a % modulus;
  void emit(String side, String text) {
    if (side == 'ALWAYS' || s.trace == 'ALL' || s.trace == side) output.add('$t $text');
  }
  int effective() => s.congestion ? math.min(s.w, cwnd) : s.w;
  int outcome(String kind, int number) {
    int result = 0;
    if (s.random) {
      random = random * 48271 % 2147483647;
      int v = random % 100;
      result = v < s.loss ? 1 : v < s.loss + s.corruption ? 2 : 0;
    }
    String suffix = kind == 'data' ? 'DATA' : 'CTRL';
    if (s.contains('LOSE$suffix', number)) result = 1;
    if (s.contains('CORRUPT$suffix', number)) result = 2;
    return result;
  }
  void control(bool nak, int a) {
    int id = ++controlCount;
    if (nak) naks++;
    String kind = nak ? 'nak' : 'ack';
    emit('RECEIVER', '${kind.toUpperCase()} a=$a #$id');
    controlEvents.add(Event(t + s.delay + s.extra('DELAYCTRL', id), id, a, outcome(kind, id), kind));
  }
  void deliver(int payload) {
    if (payload == r) {
      emit('RECEIVER', 'DELIVER f=$r');
      if (delivery[payload] < 0) delivery[payload] = t;
      s.delivered++; latency += t - first[payload];
    } else { emit('RECEIVER', 'DELIVER f=$r wrong=$payload'); errors++; }
    r++; nakSent = false;
  }
  void discard(int seq) { discarded++; emit('RECEIVER', 'DISCARD seq=$seq'); }
  void receive(Event e) {
    int seq = mod(e.value);
    emit('RECEIVER', 'RECV seq=$seq #${e.number}');
    if (!sr) {
      if (seq == mod(r)) { deliver(e.value); control(false, seq); }
      else {
        discard(seq);
        if (s.nak && !nakSent) { control(true, mod(r)); nakSent = true; }
        else if (r > 0) { control(false, mod(r - 1)); }
      }
    } else {
      int offset = mod(seq - r);
      if (offset < s.w) {
        int position = r + offset;
        if (buffer.containsKey(position)) { discard(seq); control(false, seq); }
        else if (offset == 0) {
          deliver(e.value);
          while (buffer.containsKey(r)) { deliver(buffer.remove(r)!); }
          control(false, seq);
        } else {
          buffer[position] = e.value; maxBuffer = math.max(maxBuffer, buffer.length);
          emit('RECEIVER', 'BUFFER f=$position'); control(false, seq);
          if (s.nak && !nakSent) { control(true, mod(r)); nakSent = true; }
        }
      } else {
        discard(seq);
        if (mod(r - seq) <= s.w) control(false, seq);
      }
    }
  }
  void goBack() { next = base; timer = -1; duplicates = 0; }
  void increase(int count) {
    if (!s.congestion) return;
    for (int i = 0; i < count && cwnd < s.w; i++) {
      if (cwnd < threshold) { cwnd++; }
      else if (++growth == cwnd) { cwnd++; growth = 0; }
    }
  }
  void decrease(bool timeout) {
    if (!s.congestion) return;
    threshold = math.max(cwnd ~/ 2, 1); cwnd = timeout ? 1 : threshold; growth = 0;
  }
  void cwndLine(int c, int h) {
    if (s.congestion && (c != cwnd || h != threshold)) emit('SENDER', 'CWND $cwnd ssthresh=$threshold');
  }
  void acknowledge(Event e) {
    int oldC = cwnd, oldS = threshold, oldBase = base;
    int a = e.value, f = base + mod(a - base);
    bool nak = e.kind == 'nak', accepted = false;
    if (sr) {
      if (f < high && !marks[f]) {
        accepted = true; timers[f] = -1;
        if (nak) { if (!queue.contains(f)) queue.add(f); }
        else {
          marks[f] = true; if (acked[f] < 0) acked[f] = t;
          queue.remove(f);
          while (base < high && marks[base]) { base++; }
          increase(1);
        }
      }
    } else if (nak ? f <= high : f < high) {
      accepted = true; base = nak ? f : f + 1;
      increase(base - oldBase);
      for (int i = oldBase; i < base; i++) { if (acked[i] < 0) acked[i] = t; }
      if (nak) { goBack(); } else if (next < base) { next = base; }
    }
    if (base > oldBase) { length = s.timeout; duplicates = 0; }
    if (accepted && !sr && !nak) timer = base == next ? -1 : t + length;
    String label = nak ? 'NAK' : 'ACK';
    emit('SENDER', '${accepted ? 'GOT' : 'OLD'}$label a=$a #${e.number}${accepted ? ' base=$base' : ''}');
    if (accepted && nak) decrease(false);
    if (!accepted && !nak && !sr && s.dupack > 0 && base >= 1 && a == mod(base - 1)) {
      duplicates++;
      if (duplicates == s.dupack) { fast++; emit('SENDER', 'FASTRETX f=$base'); goBack(); decrease(false); }
    }
    cwndLine(oldC, oldS);
  }
  void timeout(int f) {
    int oldC = cwnd, oldS = threshold;
    timeouts++; emit('SENDER', 'TIMEOUT f=$f');
    if (sr) { timers[f] = -1; queue.add(f); } else { goBack(); }
    if (s.backoff) length = math.min(length * 2, 8 * s.timeout);
    decrease(true); cwndLine(oldC, oldS);
  }
  void send(int f) {
    int id = ++s.data;
    bool again = tx[f]++ > 0;
    if (again) { resent++; } else { first[f] = t; }
    emit('SENDER', '${again ? 'RESEND' : 'SEND'} f=$f seq=${mod(f)} #$id');
    dataEvents.add(Event(t + s.delay + s.extra('DELAYDATA', id), id, f, outcome('data', id), 'data'));
  }
  void arrivals(List<Event> events, bool data) {
    List<Event> ready = events.where((e) => e.arrival == t).toList()..sort((a, b) => a.number.compareTo(b.number));
    events.removeWhere((e) => e.arrival == t);
    for (Event e in ready) {
      if (e.outcome != 0) {
        bool lost = e.outcome == 1;
        if (data) { if (lost) { lostData++; } else { corruptData++; } }
        else { if (lost) { lostControl++; } else { corruptControl++; } }
        emit(data ? 'RECEIVER' : 'SENDER', '${lost ? 'LOST' : 'CORRUPT'} ${e.kind} #${e.number}');
      } else if (data) { receive(e); } else { acknowledge(e); }
    }
  }
  void snapshot() {
    StringBuffer x = StringBuffer(), y = StringBuffer();
    for (int f = 0; f < s.n; f++) {
      bool ack = sr ? marks[f] : f < base;
      bool retransmit = sr ? queue.contains(f) : next <= f && f < high;
      bool sent = sr ? f < high : f < next;
      x.write(ack ? 'A' : retransmit ? 'R' : sent ? 'O' : f < base + effective() ? 'W' : '.');
      y.write(f < r ? 'D' : sr && buffer.containsKey(f) ? 'B' : (sr ? f < r + s.w : f == r) ? 'W' : '.');
    }
    emit('ALWAYS', 'SNAPSHOT sender=$x receiver=$y');
  }
  void run() {
    for (t = 0; t <= s.limit; t++) {
      arrivals(dataEvents, true); arrivals(controlEvents, false);
      bool done = base == s.n;
      if (!done) {
        if (sr) {
          for (int f = base; f < high; f++) { if (timers[f] == t) timeout(f); }
        } else if (timer == t) { timeout(base); }
        if (sr) {
          int f = -1;
          if (queue.isNotEmpty) { f = queue.removeAt(0); }
          else if (high < s.n && high < base + effective() && high * s.interval <= t) { f = high++; }
          if (f >= 0) { send(f); timers[f] = t + length; }
        } else if (next < s.n && next < base + effective() && (next < high || next * s.interval <= t)) {
          send(next); high = math.max(high, ++next);
          if (timer < 0) timer = t + length;
        }
      }
      if (s.contains('SNAPSHOT', t)) snapshot();
      if (done || t == s.limit) {
        s.end = t; if (done) s.completion = t;
        emit('ALWAYS', done ? 'DONE' : 'ABORT'); break;
      }
    }
    for (int f = 0; f < s.n; f++) { output.add('frame $f: seq=${mod(f)} tx=${tx[f]} first=${tick(first[f])} delivered=${tick(delivery[f])} acked=${tick(acked[f])}'); }
    output.add('totals: data=${s.data} resent=$resent control=$controlCount nak=$naks timeouts=$timeouts fastretx=$fast');
    output.add('channel: lost_data=$lostData lost_ctrl=$lostControl corrupt_data=$corruptData corrupt_ctrl=$corruptControl');
    output.add('receiver: delivered=${s.delivered} errors=$errors discarded=$discarded max_buffer=$maxBuffer');
    String goodput = s.completion < 0 ? '-' : fixed(s.delivered, s.completion, 2);
    String latencyText = s.delivered == 0 ? '-' : fixed(latency, s.delivered, 2);
    output.add('result: completion=${tick(s.completion)} goodput=$goodput efficiency=${fixed(s.delivered * 100, s.data, 1)}% utilization=${fixed(s.data * 100, s.end + 1, 1)}% latency=$latencyText');
  }
}
void main() {
  int count = int.parse(stdin.readLineSync()!);
  List<Scenario> scenarios = [];
  for (int i = 0; i < count; i++) {
    Scenario s = Scenario(stdin.readLineSync()!.split(' ')[1]);
    while (true) {
      String line = stdin.readLineSync()!;
      if (line == 'END') break;
      s.line(line.split(' '));
    }
    s.check(); scenarios.add(s); output.add('== ${s.name} ==');
    if (s.error != null) { output.add('error: ${s.error}'); }
    else {
      output.add('config: ${s.protocol} n=${s.n} w=${s.w} k=${s.k} T=${s.timeout} d=${s.delay}');
      String random = s.random ? '${s.seed}/${s.loss}/${s.corruption}' : 'off';
      output.add('options: interval=${s.interval} limit=${s.limit} dupack=${s.dupack == 0 ? 'off' : s.dupack} nak=${onOff(s.nak)} backoff=${onOff(s.backoff)} congestion=${onOff(s.congestion)} unsafe=${onOff(s.unsafe)} trace=${s.trace.toLowerCase()} random=$random');
      Simulation(s).run();
    }
  }
  output.add('== ranking ==');
  List<Scenario> completed = scenarios.where((s) => s.completion >= 0).toList();
  Map<Scenario, int> order = {for (int i = 0; i < scenarios.length; i++) scenarios[i]: i};
  completed.sort((a, b) {
    int c = (b.delivered * a.completion).compareTo(a.delivered * b.completion);
    if (c != 0) return c;
    c = (b.delivered * a.data).compareTo(a.delivered * b.data);
    return c != 0 ? c : order[a]!.compareTo(order[b]!);
  });
  for (int i = 0; i < completed.length; i++) {
    Scenario s = completed[i];
    output.add('${i + 1}. ${s.name} ${s.protocol} goodput=${fixed(s.delivered, s.completion, 2)} efficiency=${fixed(s.delivered * 100, s.data, 1)}%');
  }
  for (Scenario s in scenarios) { if (s.completion < 0) output.add('- ${s.name} ${s.error != null ? 'invalid' : 'aborted'}'); }
  output.add('== protocols ==');
  for (String p in ['SW', 'GBN', 'SR']) {
    int runs = 0, d = 0, t = 0, x = 0;
    for (Scenario s in completed) { if (s.protocol == p) { runs++; d += s.delivered; t += s.completion; x += s.data; } }
    if (runs > 0) output.add('$p: runs=$runs goodput=${fixed(d, t, 2)} efficiency=${fixed(d * 100, x, 1)}%');
  }
  stdout.write('${output.join('\n')}\n');
}
