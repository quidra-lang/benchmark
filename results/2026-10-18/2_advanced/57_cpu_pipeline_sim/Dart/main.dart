import 'dart:io';
import 'dart:math';
part 'trace_io.dart';
part 'hazards.dart';
part 'pipeline.dart';
part 'predictors.dart';
part 'report.dart';

const classes = ['ALU', 'MUL', 'LOAD', 'STORE', 'BRANCH', 'JUMP', 'NOP'],
    causes = ['control', 'structural', 'load_use', 'raw'],
    stages = ['IF', 'ID', 'EX', 'MEM', 'WB'],
    mispredictionKinds = ['direction', 'btb_miss', 'wrong_target'];

class Trace {
  final int lines;
  final instructions = <Instruction>[],
      rejected = <(int, String)>[],
      gaps = <(int, int, int)>[],
      staticInstructions = <int, List<int>>{},
      pcs = <int>[];
  Trace(this.lines);
}

class Prediction {
  final int next, kind;
  final bool wrong;
  const Prediction(this.next, this.wrong, this.kind);
}

class PredictionResult {
  final PredictorConfig config;
  final List<Prediction> predictions;
  int control = 0,
      wrong = 0,
      branches = 0,
      jumps = 0,
      branchWrong = 0,
      jumpWrong = 0,
      btbHits = 0,
      rasPredictions = 0,
      rasCorrect = 0,
      calls = 0,
      returns = 0;
  final kinds = List.filled(3, 0), pcWrong = <int, int>{};
  PredictionResult(this.config, int n)
    : predictions = List.filled(n, const Prediction(0, false, -1));
  int wrongFor(int pc) => pcWrong[pc] ?? 0;
}

int sumInts(Iterable<int> values) => values.fold(0, (a, b) => a + b);
Trace traceCheck() {
  final lines = readLines('input/trace.txt'),
      out = Trace(lines.length),
      first = <int, Instruction>{};
  for (var line = 0; line < lines.length; line++) {
    final a = lines[line].split(' ');
    var reason = '',
        pc = 0,
        kind = '',
        rd = -1,
        rs1 = -1,
        rs2 = -1,
        taken = false,
        target = 0,
        address = 0;
    if (a.length != 8 || a.any((s) => s.isEmpty)) reason = 'fields';
    if (reason.isEmpty) {
      pc = hexValue(a[0]) ?? -1;
      if (pc < 0 || pc % 4 != 0) reason = 'pc';
    }
    if (reason.isEmpty) {
      kind = a[1];
      if (!classes.contains(kind)) reason = 'class';
    }
    if (reason.isEmpty) {
      final r = a.sublist(2, 5).map(register).toList();
      if (r.any((v) => v == null)) {
        reason = 'register';
      } else {
        rd = r[0]!;
        rs1 = r[1]!;
        rs2 = r[2]!;
      }
    }
    if (reason.isEmpty) {
      final d = rd >= 0, s1 = rs1 >= 0, s2 = rs2 >= 0;
      final valid = switch (kind) {
        'ALU' => d && s1,
        'MUL' => d && s1 && s2,
        'LOAD' => d && s1 && !s2,
        'STORE' => !d && s1 && s2,
        'BRANCH' => !d && s1,
        'JUMP' => !s2,
        'NOP' => !d && !s1 && !s2,
        _ => false,
      };
      if (!valid) reason = 'operands';
    }
    if (reason.isEmpty) {
      final valid = kind == 'BRANCH'
          ? (a[5] == 'T' || a[5] == 'N')
          : kind == 'JUMP'
          ? a[5] == 'T'
          : a[5] == '-';
      if (!valid) reason = 'taken';
      taken = a[5] == 'T';
    }
    if (reason.isEmpty) {
      if (kind == 'BRANCH' || kind == 'JUMP') {
        target = hexValue(a[6]) ?? -1;
        if (target < 0 || target % 4 != 0 || target == pc + 4)
          reason = 'target';
      } else if (a[6] != '-') {
        reason = 'target';
      }
    }
    if (reason.isEmpty) {
      if (kind == 'LOAD' || kind == 'STORE') {
        address = hexValue(a[7]) ?? -1;
        if (address < 0 || address % 4 != 0) reason = 'address';
      } else if (a[7] != '-') {
        reason = 'address';
      }
    }
    if (reason.isEmpty) {
      final old = first[pc];
      if (old != null &&
          (kind != old.kind ||
              rd != old.rd ||
              rs1 != old.rs1 ||
              rs2 != old.rs2 ||
              ((kind == 'BRANCH' || (kind == 'JUMP' && rs1 < 0)) &&
                  target != old.target)))
        reason = 'conflict';
    }
    if (reason.isNotEmpty) {
      out.rejected.add((line + 1, reason));
      continue;
    }
    final ins = Instruction(
      pc,
      kind,
      rd,
      rs1,
      rs2,
      taken,
      target,
      address,
      line + 1,
    );
    if (!first.containsKey(pc)) {
      first[pc] = ins;
      out.pcs.add(pc);
    }
    final n = out.instructions.length;
    if (n > 0 && pc != out.instructions.last.nextPC)
      out.gaps.add((line + 1, out.instructions.last.nextPC, pc));
    out.staticInstructions.putIfAbsent(pc, () => []).add(n);
    out.instructions.add(ins);
  }
  out.pcs.sort();
  dependences(out.instructions);
  return out;
}

PredictionResult predict(List<Instruction> a, Config c, PredictorConfig p) {
  final out = PredictionResult(p, a.length),
      btb = BTB(c.btb),
      ras = RAS(c.ras),
      d = Direction(p);
  for (var i = 0; i < a.length; i++) {
    final ins = a[i];
    if (!ins.control) continue;
    out.control++;
    if (ins.kind == 'BRANCH') {
      out.branches++;
    } else {
      out.jumps++;
    }
    var candidate = btb.lookup(ins.pc);
    if (candidate != null) out.btbHits++;
    if (ins.kind == 'JUMP' && ins.rd < 0 && ins.rs1 == 31) {
      out.returns++;
      final v = ras.pop();
      if (v != null) {
        candidate = v;
        out.rasPredictions++;
        if (v == ins.target) out.rasCorrect++;
      }
    }
    if (ins.kind == 'JUMP' && ins.rd == 31) {
      out.calls++;
      ras.push(ins.pc + 4);
    }
    final direction = ins.kind == 'BRANCH' && d.predict(ins);
    var next = ins.pc + 4;
    if (p.scheme == 'PERFECT') {
      next = ins.nextPC;
    } else if (candidate != null && (ins.kind == 'JUMP' || direction)) {
      next = candidate;
    }
    final wrong = next != ins.nextPC;
    var kind = -1;
    if (wrong) {
      kind = ins.kind == 'BRANCH' && direction != ins.taken
          ? 0
          : candidate == null
          ? 1
          : 2;
      out.wrong++;
      out.kinds[kind]++;
      out.pcWrong[ins.pc] = out.wrongFor(ins.pc) + 1;
      if (ins.kind == 'BRANCH') {
        out.branchWrong++;
      } else {
        out.jumpWrong++;
      }
    }
    out.predictions[i] = Prediction(next, wrong, kind);
    if (ins.kind == 'BRANCH') d.update(ins);
    if (ins.taken) btb.insert(ins.pc, ins.target);
  }
  return out;
}

List<DiagramRow> rows(
  List<Instruction> a,
  Variant v,
  PredictionResult p,
  Run run,
) {
  final out = <DiagramRow>[], annotations = List.filled(a.length, '');
  for (final s in run.stalls) {
    if (s.waiting >= 0)
      annotations[s.waiting] += ' ${causes[s.cause]} ${s.cycles}';
  }
  for (var i = 0; i < a.length; i++) {
    final ins = a[i], t = run.timings[i], prediction = p.predictions[i];
    var annotation = annotations[i];
    if (prediction.wrong)
      annotation += ' mispredict ${mispredictionKinds[prediction.kind]}';
    out.add(
      DiagramRow(i, ins.pc, ins.kind, false, [
        Span(t.f, t.f, 'F', 0),
        Span(t.f + 1, t.d - 1, '*', 0),
        Span(t.d, t.d, 'D', 1),
        Span(t.d + 1, t.x - 1, '*', 1),
        Span(t.x, t.m - 1, 'X', 2),
        Span(t.m, t.m, 'M', 3),
        Span(t.w, t.w, 'W', 4),
      ], annotation),
    );
    if (!prediction.wrong) continue;
    final spans = [Span(t.d, t.d, 'F', 0), Span(t.d + 1, t.x - 1, '*', 0)];
    if (idResolved(ins, v)) {
      spans.add(Span(t.x, t.x, 'x', -1));
      out.add(DiagramRow(-1, prediction.next, 'FLUSH', true, spans));
    } else {
      spans.addAll([Span(t.x, t.x, 'D', 1), Span(t.x + 1, t.x + 1, 'x', -1)]);
      out.addAll([
        DiagramRow(-1, prediction.next, 'FLUSH', true, spans),
        DiagramRow(-1, prediction.next + 4, 'FLUSH', true, [
          Span(t.x, t.x, 'F', 0),
          Span(t.x + 1, t.x + 1, 'x', -1),
        ]),
      ]);
    }
  }
  return out;
}

void pipelineOutput(Config c, Run run, List<DiagramRow> diagram) {
  final lines = [
        'pipeline variant=${c.primaryVariant} predictor=${c.primaryPredictor} cycles ${c.start}-${c.end}',
        'cycle${' ' * 18}${cycleDigits(c.start, c.end)}',
      ],
      contents = List.generate(c.end - c.start + 1, (_) => List.filled(5, '.'));
  var count = 0, stars = 0, flush = 0;
  for (final row in diagram) {
    final (text, visible, s, f) = row.render(c.start, c.end);
    if (visible) {
      lines.add(text);
      count++;
      stars += s;
      flush += f;
    }
    final id = row.wrong ? 'w' : '${row.instruction + 1}';
    for (final span in row.spans) {
      if (span.stage < 0) continue;
      for (
        var cycle = max(c.start, span.first);
        cycle <= min(c.end, span.last);
        cycle++
      ) {
        contents[cycle - c.start][span.stage] = id;
      }
    }
  }
  final completed = run.timings
      .where((t) => t.w >= c.start && t.w <= c.end)
      .length;
  lines.addAll([
    'rows $count completed $completed stall_cells $stars flushed $flush',
    '',
    'stages',
    'cycle IF ID EX MEM WB',
  ]);
  for (var i = 0; i < contents.length; i++) {
    lines.add('${c.start + i} ${contents[i].join(' ')}');
  }
  writeLines('pipeline.txt', lines);
}

class DependencyGroup {
  final (int, int, int) key;
  int cycles = 0, events = 0;
  DependencyGroup(this.key);
}

void writeParts(String name, List<List<String>> parts) {
  final lines = <String>[];
  for (var i = 0; i < parts.length; i++) {
    if (i > 0) lines.add('');
    lines.addAll(parts[i]);
  }
  writeLines(name, lines);
}

void statsOutput(
  Trace trace,
  Config c,
  List<PredictionResult> predictions,
  List<List<Run>> runs,
  int pv,
  int pp,
  List<DiagramRow> diagram,
) {
  final a = trace.instructions,
      n = a.length,
      v = c.variants[pv],
      pr = predictions[pp],
      run = runs[pv][pp],
      parts = <List<String>>[],
      input = [
        'input lines ${trace.lines} accepted $n rejected ${trace.rejected.length} gaps ${trace.gaps.length}',
      ];
  for (final (line, reason) in trace.rejected) {
    input.add('reject line $line $reason');
  }
  for (final (line, expected, found) in trace.gaps) {
    input.add('gap line $line expected ${hex(expected)} found ${hex(found)}');
  }
  parts.add(input);
  final mix = <String, int>{},
      addresses = <int>{},
      distances = List.filled(5, 0);
  var taken = 0,
      backward = 0,
      indirect = 0,
      link = 0,
      staticBranches = 0,
      staticJumps = 0,
      sources = 0,
      produced = 0;
  for (final ins in a) {
    mix[ins.kind] = (mix[ins.kind] ?? 0) + 1;
    if (ins.kind == 'BRANCH') {
      if (ins.taken) taken++;
      if (ins.target < ins.pc) backward++;
    }
    if (ins.kind == 'JUMP') {
      if (ins.rs1 >= 0) indirect++;
      if (ins.rd >= 0) link++;
    }
    if (ins.kind == 'LOAD' || ins.kind == 'STORE') addresses.add(ins.address);
  }
  int classCount(String cl) => mix[cl] ?? 0;
  for (final pc in trace.pcs) {
    final ins = a[trace.staticInstructions[pc]!.first];
    if (ins.kind == 'BRANCH') staticBranches++;
    if (ins.kind == 'JUMP') staticJumps++;
  }
  for (var i = 0; i < n; i++) {
    for (final s in a[i].sources) {
      sources++;
      if (s.producer >= 0) {
        produced++;
        distances[min(5, i - s.producer) - 1]++;
      }
    }
  }
  parts.add([
    'trace',
    'instructions $n',
    'static_instructions ${trace.pcs.length}',
    'mix ${classes.map((cl) => '$cl ${classCount(cl)}').join(' ')}',
    'branches ${classCount('BRANCH')} taken $taken backward $backward',
    'jumps ${classCount('JUMP')} indirect $indirect link $link',
    'static_control branches $staticBranches jumps $staticJumps',
    'memory loads ${classCount('LOAD')} stores ${classCount('STORE')} distinct_addresses ${addresses.length}',
    'operands $sources with_producer $produced distance 1 ${distances[0]} 2 ${distances[1]} 3 ${distances[2]} 4 ${distances[3]} 5+ ${distances[4]}',
  ]);
  final pl = ['prediction'];
  for (final p in predictions) {
    pl.add(
      '${p.config.name} ${p.config.scheme} bits ${storage(p.config)} control ${p.control} mispredicted ${p.wrong} accuracy ${percent(p.control - p.wrong, p.control)} branches ${percent(p.branches - p.branchWrong, p.branches)} jumps ${percent(p.jumps - p.jumpWrong, p.jumps)} direction ${p.kinds[0]} btb_miss ${p.kinds[1]} wrong_target ${p.kinds[2]}',
    );
  }
  final first = predictions.first;
  pl.addAll([
    'btb entries ${c.btb} lookups ${first.control} hits ${first.btbHits} misses ${first.control - first.btbHits}',
    'ras depth ${c.ras} calls ${first.calls} returns ${first.returns} predicted ${first.rasPredictions} correct ${first.rasCorrect}',
  ]);
  parts.add(pl);
  final total = sumInts(run.totals),
      lengths = List.filled(5, 0),
      finish = List.filled(n, 0);
  for (var i = 1; i < n; i++) {
    final g = run.timings[i].x - run.timings[i - 1].x - 1;
    if (g > 0) lengths[min(5, g) - 1]++;
  }
  var height = 0;
  for (var i = 0; i < n; i++) {
    final ins = a[i];
    var start = 0;
    for (final s in ins.sources) {
      if (s.producer >= 0) start = max(start, finish[s.producer]);
    }
    final latency = ins.kind == 'LOAD'
        ? 2
        : ins.kind == 'MUL'
        ? v.latency
        : 1;
    finish[i] = start + latency;
    height = max(height, finish[i]);
  }
  parts.add([
    'timing variant=${v.name} predictor=${pr.config.name}',
    'forwarding ${v.forward ? 'on' : 'off'} branch_stage ${v.stage} mul_latency ${v.latency}',
    'cycles ${run.cycles}',
    'cpi ${fraction(run.cycles, n)} ${decimal(run.cycles, n)}',
    'ipc ${decimal(n, run.cycles)}',
    'stall_cycles total $total control ${run.totals[0]} structural ${run.totals[1]} load_use ${run.totals[2]} raw ${run.totals[3]}',
    'stall_events control ${run.events[0]} structural ${run.events[1]} load_use ${run.events[2]} raw ${run.events[3]}',
    'flushed ${run.refetch}',
    'cycle_check $n + 4 + $total = ${n + 4 + total}',
    'cpi_stack base 1.0000 fill ${decimal(4, n)} control ${decimal(run.totals[0], n)} structural ${decimal(run.totals[1], n)} load_use ${decimal(run.totals[2], n)} raw ${decimal(run.totals[3], n)}',
    'stall_lengths 1 ${lengths[0]} 2 ${lengths[1]} 3 ${lengths[2]} 4 ${lengths[3]} 5+ ${lengths[4]}',
    'dataflow height $height ilp ${decimal(n, height)}',
  ]);
  final what = ['whatif'],
      names = [
        'perfect_prediction',
        'single_cycle_mul',
        v.forward ? 'forwarding_off' : 'forwarding_on',
        v.stage == 'EX' ? 'branch_stage_ID' : 'branch_stage_EX',
      ];
  for (var i = 0; i < names.length; i++) {
    var variant = v, flags = pr.predictions;
    switch (i) {
      case 0:
        flags = List.filled(n, const Prediction(0, false, -1));
      case 1:
        variant = v.copy(latency: 1);
      case 2:
        variant = v.copy(forward: !v.forward);
      case 3:
        variant = v.copy(stage: v.stage == 'EX' ? 'ID' : 'EX');
    }
    final cycles = simulate(a, variant, flags).cycles;
    what.add(
      '${names[i]} cycles $cycles saved ${run.cycles - cycles} speedup ${decimal(run.cycles, cycles)}',
    );
  }
  parts.add(what);
  final classStalls = <String, int>{},
      hot = <int, List<int>>{},
      dependencies = <(int, int, int), DependencyGroup>{};
  for (final s in run.stalls) {
    final ins = a[s.responsible];
    classStalls[ins.kind] = (classStalls[ins.kind] ?? 0) + s.cycles;
    hot.putIfAbsent(ins.pc, () => List.filled(4, 0))[s.cause] += s.cycles;
    if (s.cause >= 2) {
      final key = (a[s.producer].pc, a[s.waiting].pc, s.cause),
          g = dependencies.putIfAbsent(key, () => DependencyGroup(key));
      g.cycles += s.cycles;
      g.events++;
    }
  }
  final cl = ['classes'];
  for (final name in classes) {
    final count = classCount(name),
        stalls = classStalls[name] ?? 0,
        rate = count > 0 ? decimal(stalls, count) : '-';
    cl.add('$name count $count stall_cycles $stalls per_instruction $rate');
  }
  parts.add(cl);
  final paths = List.filled(3, 0);
  for (var i = 0; i < n; i++) {
    for (final source in a[i].sources) {
      paths[forwardingPath(i, a[i], source, run.timings, v)]++;
    }
  }
  parts.add([
    'forwarding regfile ${paths[0]} ex_mem ${paths[1]} mem_wb ${paths[2]}',
  ]);
  final occupancy = List.generate(5, (_) => List.filled(2, 0));
  for (final row in diagram) {
    final kind = row.wrong ? 1 : 0;
    for (final span in row.spans) {
      if (span.stage >= 0 && span.last >= span.first)
        occupancy[span.stage][kind] += span.last - span.first + 1;
    }
  }
  final occ = ['occupancy cycles ${run.cycles}'];
  for (var i = 0; i < 5; i++) {
    final correct = occupancy[i][0], wrong = occupancy[i][1];
    occ.add(
      '${stages[i]} correct $correct wrong $wrong idle ${run.cycles - correct - wrong} busy ${percent(correct + wrong, run.cycles)}',
    );
  }
  parts.add(occ);
  final hotPCs = hot.keys.toList()
        ..sort((x, y) {
          final c = sumInts(hot[y]!).compareTo(sumInts(hot[x]!));
          return c != 0 ? c : x.compareTo(y);
        }),
      hl = ['hotspots'];
  for (var rank = 0; rank < min(c.top, hotPCs.length); rank++) {
    final pc = hotPCs[rank], t = hot[pc]!;
    hl.add(
      '${rank + 1} ${hex(pc)} ${a[trace.staticInstructions[pc]!.first].kind} stall_cycles ${sumInts(t)} control ${t[0]} structural ${t[1]} load_use ${t[2]} raw ${t[3]}',
    );
  }
  parts.add(hl);
  final groups = dependencies.values.toList()
        ..sort((x, y) {
          var c = y.cycles.compareTo(x.cycles);
          if (c != 0) return c;
          c = x.key.$1.compareTo(y.key.$1);
          if (c != 0) return c;
          c = x.key.$2.compareTo(y.key.$2);
          return c != 0 ? c : x.key.$3.compareTo(y.key.$3);
        }),
      dl = ['dependencies total ${dependencies.length}'];
  for (var rank = 0; rank < min(c.top, groups.length); rank++) {
    final g = groups[rank], key = g.key;
    dl.add(
      '${rank + 1} ${hex(key.$1)} ${a[trace.staticInstructions[key.$1]!.first].kind} -> ${hex(key.$2)} ${a[trace.staticInstructions[key.$2]!.first].kind} ${causes[key.$3]} stall_cycles ${g.cycles} events ${g.events}',
    );
  }
  parts.add(dl);
  final intervals = ['intervals size ${c.interval}'];
  for (var lo = 0; lo < n; lo += c.interval) {
    final hi = min(n, lo + c.interval) - 1,
        cycles = run.timings[hi].w - (lo > 0 ? run.timings[lo - 1].w : 0);
    intervals.add(
      '${lo + 1}-${hi + 1} cycles $cycles cpi ${decimal(cycles, hi - lo + 1)}',
    );
  }
  parts.add(intervals);
  final table = ['cycles_table ${c.predictors.map((p) => p.name).join(' ')}'];
  for (var i = 0; i < c.variants.length; i++) {
    table.add(
      '${c.variants[i].name} ${runs[i].map((r) => r.cycles).join(' ')}',
    );
  }
  parts.add(table);
  writeParts('stats.txt', parts);
}

class Segment {
  final int pc;
  int instances = 0, instructions = 0, cycles = 0;
  Segment(this.pc);
}

void profileOutput(
  Trace trace,
  Config c,
  List<PredictionResult> predictions,
  Run run,
) {
  final a = trace.instructions,
      branches = ['branches'],
      loops = ['loops'],
      indirect = ['indirect'],
      instructions = ['instructions'],
      stallPC = <int, int>{};
  for (final s in run.stalls) {
    final pc = a[s.responsible].pc;
    stallPC[pc] = (stallPC[pc] ?? 0) + s.cycles;
  }
  for (final pc in trace.pcs) {
    final executions = trace.staticInstructions[pc]!, ins = a[executions.first];
    if (ins.kind == 'BRANCH') {
      var taken = 0,
          transitions = 0,
          longT = 0,
          longN = 0,
          current = 0,
          trip = 0,
          longTrip = 0,
          trips = 0,
          previous = false;
      for (var j = 0; j < executions.length; j++) {
        final t = a[executions[j]].taken;
        if (t) taken++;
        if (j > 0 && t != previous) transitions++;
        current = j == 0 || t != previous ? 1 : current + 1;
        if (t) {
          longT = max(longT, current);
        } else {
          longN = max(longN, current);
        }
        previous = t;
        trip++;
        if (!t) {
          trips++;
          longTrip = max(longTrip, trip);
          trip = 0;
        }
      }
      if (trip > 0) {
        trips++;
        longTrip = max(longTrip, trip);
      }
      var best = -1;
      for (var i = 0; i < predictions.length; i++) {
        final p = predictions[i];
        if (p.config.scheme != 'PERFECT' &&
            (best < 0 || p.wrongFor(pc) < predictions[best].wrongFor(pc)))
          best = i;
      }
      final direction = ins.target < pc ? 'backward' : 'forward';
      branches.add(
        '${hex(pc)} $direction executions ${executions.length} taken $taken transitions $transitions longest_taken $longT longest_not_taken $longN best ${predictions[best].config.name} ${predictions[best].wrongFor(pc)}',
      );
      if (direction == 'backward')
        loops.add(
          '${hex(ins.target)}-${hex(pc)} body ${(pc - ins.target) ~/ 4 + 1} entries $trips iterations ${executions.length} avg_trip ${decimal(executions.length, trips)} max_trip $longTrip',
        );
    }
    if (ins.kind == 'JUMP' && ins.rs1 >= 0) {
      final counts = <int, int>{};
      for (final index in executions) {
        final target = a[index].target;
        counts[target] = (counts[target] ?? 0) + 1;
      }
      final targets = counts.keys.toList()
        ..sort((x, y) {
          final c = counts[y]!.compareTo(counts[x]!);
          return c != 0 ? c : x.compareTo(y);
        });
      indirect.add(
        '${hex(pc)} executions ${executions.length} distinct ${targets.length} targets ${targets.map((t) => '${hex(t)}:${counts[t]}').join(' ')}',
      );
    }
    instructions.add(
      '${hex(pc)} ${ins.kind} ${registerText(ins.rd)} ${registerText(ins.rs1)} ${registerText(ins.rs2)} executions ${executions.length} stall_cycles ${stallPC[pc] ?? 0}',
    );
  }
  final groups = <int, Segment>{};
  var lo = 0;
  for (var i = 0; i < a.length; i++) {
    if (a[i].control || i == a.length - 1) {
      final pc = a[lo].pc, g = groups.putIfAbsent(pc, () => Segment(pc));
      g.instances++;
      g.instructions += i - lo + 1;
      g.cycles += run.timings[i].w - (lo > 0 ? run.timings[lo - 1].w : 0);
      lo = i + 1;
    }
  }
  final segments = groups.values.toList()
        ..sort((x, y) {
          final c = y.cycles.compareTo(x.cycles);
          return c != 0 ? c : x.pc.compareTo(y.pc);
        }),
      sl = ['segments total ${groups.length}'];
  for (var rank = 0; rank < min(c.top, segments.length); rank++) {
    final s = segments[rank];
    sl.add(
      '${rank + 1} ${hex(s.pc)} instances ${s.instances} instructions ${s.instructions} cycles ${s.cycles} cpi ${decimal(s.cycles, s.instructions)}',
    );
  }
  writeParts('profile.txt', [branches, loops, sl, indirect, instructions]);
}

void comparisons(
  Trace trace,
  Config c,
  List<PredictionResult> p,
  List<List<Run>> runs,
  int primary,
) {
  final a = trace.instructions,
      branches = [
        'predictor,pc,class,executions,taken,mispredictions,accuracy',
      ];
  for (final pr in p) {
    for (final pc in trace.pcs) {
      final executions = trace.staticInstructions[pc]!,
          ins = a[executions.first];
      if (!ins.control) continue;
      final taken = executions.where((i) => a[i].taken).length,
          wrong = pr.wrongFor(pc);
      branches.add(
        '${pr.config.name},${hex(pc)},${ins.kind},${executions.length},$taken,$wrong,${percent(executions.length - wrong, executions.length)}',
      );
    }
  }
  writeLines('branches.csv', branches);
  final combinations = <(int, int, Run)>[];
  for (var vi = 0; vi < runs.length; vi++) {
    for (var pi = 0; pi < runs[vi].length; pi++) {
      combinations.add((vi, pi, runs[vi][pi]));
    }
  }
  combinations.sort((x, y) {
    var compare = x.$3.cycles.compareTo(y.$3.cycles);
    if (compare != 0) return compare;
    compare = c.variants[x.$1].name.compareTo(c.variants[y.$1].name);
    return compare != 0
        ? compare
        : p[x.$2].config.name.compareTo(p[y.$2].config.name);
  });
  final out = [
    'rank,variant,predictor,cycles,cpi,speedup,accuracy,mispredictions,control,structural,load_use,raw',
  ];
  for (var rank = 0; rank < combinations.length; rank++) {
    final (vi, pi, run) = combinations[rank];
    final pr = p[pi];
    out.add(
      '${rank + 1},${c.variants[vi].name},${pr.config.name},${run.cycles},${decimal(run.cycles, a.length)},${decimal(primary, run.cycles)},${percent(pr.control - pr.wrong, pr.control)},${pr.wrong},${run.totals.join(',')}',
    );
  }
  writeLines('comparison.csv', out);
}

void main() {
  final trace = traceCheck(), c = readConfig(), p = <PredictionResult>[];
  var pp = 0, pv = 0;
  for (var i = 0; i < c.predictors.length; i++) {
    final pc = c.predictors[i];
    p.add(predict(trace.instructions, c, pc));
    if (pc.name == c.primaryPredictor) pp = i;
  }
  final runs = <List<Run>>[];
  for (var vi = 0; vi < c.variants.length; vi++) {
    final v = c.variants[vi];
    if (v.name == c.primaryVariant) pv = vi;
    runs.add([
      for (final pr in p) simulate(trace.instructions, v, pr.predictions),
    ]);
  }
  final primary = runs[pv][pp],
      diagram = rows(trace.instructions, c.variants[pv], p[pp], primary);
  pipelineOutput(c, primary, diagram);
  statsOutput(trace, c, p, runs, pv, pp, diagram);
  profileOutput(trace, c, p, primary);
  comparisons(trace, c, p, runs, primary.cycles);
}
