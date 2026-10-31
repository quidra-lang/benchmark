part of 'main.dart';

class Source {
  final int register, producer;
  Source(this.register, this.producer);
}

class Instruction {
  final int pc, rd, rs1, rs2, target, address, line;
  final String kind;
  final bool taken;
  final sources = <Source>[];
  Instruction(
    this.pc,
    this.kind,
    this.rd,
    this.rs1,
    this.rs2,
    this.taken,
    this.target,
    this.address,
    this.line,
  );
  bool get control => kind == 'BRANCH' || kind == 'JUMP';
  int get nextPC => taken ? target : pc + 4;
}

void dependences(List<Instruction> a) {
  final last = List.filled(32, -1);
  for (var i = 0; i < a.length; i++) {
    for (final r in [a[i].rs1, a[i].rs2]) {
      if (r > 0) a[i].sources.add(Source(r, last[r]));
    }
    if (a[i].rd > 0) last[a[i].rd] = i;
  }
}

bool idResolved(Instruction i, Variant v) =>
    i.control && (v.stage == 'ID' || (i.kind == 'JUMP' && i.rs1 < 0));
int ready(
  Instruction i,
  Source source,
  List<Instruction> a,
  List<Timing> t,
  Variant v,
) {
  final p = source.producer;
  if (!v.forward) return t[p].w + 1;
  var r = a[p].kind == 'LOAD' ? t[p].w : t[p].m;
  if (idResolved(i, v)) r++;
  return r;
}

int forwardingPath(
  int index,
  Instruction i,
  Source source,
  List<Timing> t,
  Variant v,
) {
  if (!v.forward || source.producer < 0) return 0;
  var u = t[index].x;
  final resolved = idResolved(i, v);
  if (resolved) u--;
  final p = t[source.producer];
  if (p.m == u) return 1;
  if (!resolved && p.w == u) return 2;
  return 0;
}
