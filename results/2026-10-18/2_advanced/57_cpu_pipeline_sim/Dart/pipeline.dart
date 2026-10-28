part of 'main.dart';

class Timing {
  int f, d, x, m = 0, w = 0;
  Timing(this.f, this.d, this.x);
}

class Stall {
  final int cause, cycles, responsible, waiting, producer;
  Stall(this.cause, this.cycles, this.responsible, this.waiting, this.producer);
}

class Run {
  final timings = <Timing>[],
      stalls = <Stall>[],
      totals = List.filled(4, 0),
      events = List.filled(4, 0);
  int cycles = 0, refetch = 0;
}

Run simulate(List<Instruction> a, Variant v, List<Prediction> p) {
  final out = Run();
  for (var i = 0; i < a.length; i++) {
    final ins = a[i], t = Timing(1, 2, 3);
    if (i > 0) {
      final previous = out.timings[i - 1];
      t.f = previous.d;
      if (p[i - 1].wrong) t.f = previous.x + (idResolved(a[i - 1], v) ? 0 : 1);
      t.d = max(t.f + 1, previous.x);
      final bounds = [t.d + 1, previous.m, previous.x + 1, previous.x + 1],
          producer = List.filled(4, -1);
      for (final source in ins.sources) {
        if (source.producer < 0) continue;
        final cause = a[source.producer].kind == 'LOAD' ? 2 : 3,
            r = ready(ins, source, a, out.timings, v);
        if (r > bounds[cause]) {
          bounds[cause] = r;
          producer[cause] = source.producer;
        }
      }
      var current = previous.x + 1;
      for (var cause = 0; cause < 4; cause++) {
        final b = bounds[cause];
        if (b > current) {
          out.stalls.add(
            Stall(
              cause,
              b - current,
              cause < 2 ? i - 1 : i,
              i,
              producer[cause],
            ),
          );
          out.totals[cause] += b - current;
          out.events[cause]++;
          current = b;
        }
      }
      t.x = current;
    }
    final e = ins.kind == 'MUL' ? v.latency : 1;
    t.m = t.x + e;
    t.w = t.m + 1;
    out.timings.add(t);
    if (p[i].wrong) out.refetch += idResolved(ins, v) ? 1 : 2;
  }
  final last = a.length - 1;
  if (a[last].kind == 'MUL' && v.latency >= 2) {
    final n = v.latency - 1;
    out.stalls.add(Stall(1, n, last, -1, -1));
    out.totals[1] += n;
    out.events[1]++;
  }
  out.cycles = out.timings.last.w;
  return out;
}
