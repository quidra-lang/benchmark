import 'dart:io';
import 'dart:math' as math;
part 'heap.dart';
part 'mutator.dart';
part 'mark_sweep.dart';
part 'copying.dart';
part 'generational.dart';

String line(List<Object> parts) => parts.join(' ');
void writeLines(String name, List<String> lines) => File(
  'output/$name',
).writeAsStringSync(lines.isEmpty ? '' : '${lines.join('\n')}\n');
List<String> joinBlocks(List<List<String>> blocks) => [
  for (var i = 0; i < blocks.length; i++) ...[if (i > 0) '', ...blocks[i]],
];
HeapObject? value(List<HeapObject?> roots, int source) =>
    source < 0 ? null : roots[source];
Set<int> reachableNumbers(List<HeapObject?> roots) {
  final reached = <int>{}, stack = List<HeapObject?>.of(roots);
  while (stack.isNotEmpty) {
    final object = stack.removeLast();
    if (object == null || !reached.add(object.number)) continue;
    stack.addAll(object.fields);
  }
  return reached;
}

Pair pairOf(Iterable<HeapObject> objects) {
  final pair = Pair();
  for (final object in objects) {
    pair.add(object);
  }
  return pair;
}

String fragmentation(List<FreeBlock> blocks) =>
    pct(totalFree(blocks) - largestFree(blocks), totalFree(blocks));

class Checkpoint {
  final String label;
  final int line, stack;
  final Pair live, allocated, phase, survivors;
  final Set<int> reachable;
  Checkpoint(
    this.label,
    this.line,
    this.stack,
    this.live,
    this.allocated,
    this.phase,
    this.survivors,
    this.reachable,
  );
}

class Script {
  int lineCount = 0, clock = 0, peakLine = 0, phaseStart = 0;
  final commands = <Command>[],
      errors = <String>[],
      counts = <String, int>{},
      roots = <HeapObject?>[],
      objects = <HeapObject>[];
  final births = <int>[],
      deaths = <int>[],
      lifetimes = <int>[],
      checkpoints = <Checkpoint>[],
      labels = <String>{};
  var alive = <int>{}, live = Pair(), peak = Pair();
  String? check(Command command) {
    final depth = roots.length, name = command.name;
    if (['ALLOC', 'PUSH', 'LOAD'].contains(name) && depth == 64) return 'stack';
    if (['LOAD', 'SET', 'OVERWRITE'].contains(name) && command.slot >= depth)
      return 'stack';
    if (['PUSH', 'SET', 'OVERWRITE'].contains(name) && command.source >= depth)
      return 'stack';
    if (name == 'POP' && command.count > depth) return 'stack';
    if (name == 'LOAD' || name == 'SET') {
      final target = roots[command.slot];
      if (target == null) return 'null';
      if (command.field >= target.fields.length) return 'field';
    }
    if (name == 'CHECKPOINT' && labels.contains(command.label))
      return 'duplicate';
    return null;
  }

  void analyze() {
    final texts = readLines('input/mutator.txt');
    lineCount = texts.length;
    for (var i = 0; i < texts.length; i++) {
      final (parsed, parseReason) = parseLine(i + 1, texts[i]);
      final reason = parseReason ?? check(parsed!);
      if (reason != null) {
        errors.add('error line ${i + 1} $reason');
        continue;
      }
      final command = parsed!;
      commands.add(command);
      counts[command.name] = (counts[command.name] ?? 0) + 1;
      switch (command.name) {
        case 'ALLOC':
          final object = HeapObject(
            objects.length + 1,
            command.pointers,
            command.data,
          );
          objects.add(object);
          births.add(clock);
          deaths.add(0);
          lifetimes.add(-1);
          clock += object.size;
          roots.add(object);
        case 'PUSH':
          roots.add(value(roots, command.source));
        case 'LOAD':
          roots.add(roots[command.slot]!.fields[command.field]);
        case 'POP':
          roots.removeRange(roots.length - command.count, roots.length);
        case 'SET':
          roots[command.slot]!.fields[command.field] = value(
            roots,
            command.source,
          );
        case 'OVERWRITE':
          roots[command.slot] = value(roots, command.source);
      }
      final reached = reachableNumbers(roots);
      for (final number in alive.difference(reached)) {
        deaths[number - 1] = command.line;
        lifetimes[number - 1] =
            clock - births[number - 1] - objects[number - 1].size;
      }
      alive = reached;
      live = pairOf(reached.map((number) => objects[number - 1]));
      if (peakLine == 0 || live.words > peak.words) {
        peak = live;
        peakLine = command.line;
      }
      if (command.name == 'CHECKPOINT') {
        final phase = pairOf(objects.skip(phaseStart)),
            survivors = pairOf(
              objects
                  .skip(phaseStart)
                  .where((object) => reached.contains(object.number)),
            );
        checkpoints.add(
          Checkpoint(
            command.label,
            command.line,
            roots.length,
            live,
            pairOf(objects),
            phase,
            survivors,
            reached,
          ),
        );
        phaseStart = objects.length;
        labels.add(command.label);
      }
    }
  }

  List<String> report() {
    final lines = [
      'script lines $lineCount valid ${commands.length} errors ${errors.length}',
      ...errors,
      'commands ${commandNames.map((name) => '$name ${counts[name] ?? 0}').join(' ')}',
      'allocated objects ${objects.length} words $clock sizes ${classTable(objects.map((object) => object.size))}',
      'peak_live objects ${peak.count} words ${peak.words} line $peakLine',
      'end_live objects ${live.count} words ${live.words} stack ${roots.length}',
    ];
    final lifeCounts = List.filled(6, 0), limits = [63, 255, 1023, 4095];
    for (final life in lifetimes) {
      var index = 5;
      if (life >= 0) {
        index = 4;
        for (var i = 0; i < limits.length; i++) {
          if (life <= limits[i]) {
            index = i;
            break;
          }
        }
      }
      lifeCounts[index]++;
    }
    lines.add(
      'lifetimes 0-63 ${lifeCounts[0]} 64-255 ${lifeCounts[1]} 256-1023 ${lifeCounts[2]} 1024-4095 ${lifeCounts[3]} 4096+ ${lifeCounts[4]} live ${lifeCounts[5]}',
    );
    for (final c in checkpoints) {
      lines.add(
        'checkpoint ${c.label} line ${c.line} stack ${c.stack} live ${c.live} allocated ${c.allocated} phase ${c.phase} survivors ${c.survivors} survival ${pct(c.survivors.words, c.phase.words)}',
      );
    }
    return lines;
  }
}

List<String> leakReport(
  String title,
  List<HeapObject> garbage,
  List<int> deaths,
) {
  final members = {for (final object in garbage) object.number: object},
      neighbors = <int, List<int>>{},
      ids = garbage.map((object) => object.number).toList()..sort();
  for (final object in garbage) {
    for (final child in object.fields) {
      if (child != null && members.containsKey(child.number)) {
        neighbors.putIfAbsent(object.number, () => []).add(child.number);
        neighbors.putIfAbsent(child.number, () => []).add(object.number);
      }
    }
  }
  final groups = <List<HeapObject>>[], grouped = <int>{};
  for (final id in ids) {
    if (!grouped.add(id)) continue;
    final stack = [id], group = <HeapObject>[];
    while (stack.isNotEmpty) {
      final current = stack.removeLast();
      group.add(members[current]!);
      for (final other in neighbors[current] ?? <int>[]) {
        if (grouped.add(other)) stack.add(other);
      }
    }
    group.sort((a, b) => a.number.compareTo(b.number));
    groups.add(group);
  }
  bool onCycle(HeapObject object) {
    final visited = <int>{}, stack = List<HeapObject?>.of(object.fields);
    while (stack.isNotEmpty) {
      final current = stack.removeLast();
      if (current == null || !members.containsKey(current.number)) continue;
      if (identical(current, object)) return true;
      if (!visited.add(current.number)) continue;
      stack.addAll(current.fields);
    }
    return false;
  }

  final lines = [
    '$title groups ${groups.length} objects ${garbage.length} words ${usedWords(garbage)}',
  ];
  for (var i = 0; i < groups.length; i++) {
    final group = groups[i], codes = <String>[];
    var cycles = 0, died = 0;
    for (final object in group) {
      final cycle = onCycle(object);
      if (cycle) cycles++;
      codes.add('${object.number}${cycle ? '*' : ''}');
      died = math.max(died, deaths[object.number - 1]);
    }
    lines.add(
      'group ${i + 1} objects ${group.length} words ${usedWords(group)} cycle $cycles died $died ids ${codes.join(' ')}',
    );
  }
  return lines;
}

extension RefcountCollector on Heap {
  void retain(HeapObject? object) {
    if (object != null) {
      object.count++;
      increments++;
    }
  }

  void release(HeapObject? object) {
    if (object == null) return;
    decrements++;
    object.count--;
    if (object.count > 0) return;
    final pending = [object];
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      objects.remove(current);
      released.add(current);
      for (final child in current.fields) {
        if (child == null) continue;
        decrements++;
        child.count--;
        if (child.count == 0) pending.add(child);
      }
    }
  }

  void backup(List<HeapObject?> roots, int lineNumber, int request) {
    final record = CollectionRecord(
      records.length + 1,
      lineNumber,
      request,
      'backup',
      freeList(),
    );
    mark(record, roots, objects);
    final garbage = objects.where((object) => !object.marked).toList();
    reports.add(
      leakReport('backup ${record.number} line $lineNumber', garbage, deaths),
    );
    objects = sweep(record, objects);
    for (final object in garbage) {
      for (final child in object.fields) {
        if (child != null && child.marked) {
          child.count--;
          decrements++;
        }
      }
    }
    record.finish(freeList());
    records.add(record);
  }
}

class Pause {
  final int line, work, freed, count;
  final bool collection;
  Pause(this.line, this.work, this.freed, this.collection, [this.count = 0]);
}

class PauseStats {
  final int count, collections, work, freed, maximum;
  final String p50, p90;
  PauseStats._(
    this.count,
    this.collections,
    this.work,
    this.freed,
    this.maximum,
    this.p50,
    this.p90,
  );
  factory PauseStats(List<Pause> pauses) {
    final works = pauses.map((pause) => pause.work).toList()..sort();
    return PauseStats._(
      pauses.length,
      pauses.where((pause) => pause.collection).length,
      works.fold(0, (total, work) => total + work),
      pauses.fold(0, (total, pause) => total + pause.freed),
      works.isEmpty ? 0 : works.last,
      works.isEmpty ? '-' : '${works[(50 * works.length + 99) ~/ 100 - 1]}',
      works.isEmpty ? '-' : '${works[(90 * works.length + 99) ~/ 100 - 1]}',
    );
  }
}

class Segment {
  final int start, mutatorBefore;
  int length;
  final bool mutator;
  Segment(this.start, this.length, this.mutatorBefore, this.mutator);
}

class Timeline {
  final segments = <Segment>[];
  int length = 0, mutator = 0;
  void add(bool isMutator, int units) {
    if (units == 0) return;
    if (segments.isNotEmpty && segments.last.mutator == isMutator) {
      segments.last.length += units;
    } else {
      segments.add(Segment(length, units, mutator, isMutator));
    }
    length += units;
    if (isMutator) mutator += units;
  }

  int mutatorUntil(int position) {
    if (segments.isEmpty) return 0;
    var low = 0, high = segments.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (segments[middle].start <= position) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    final segment = segments[low - 1];
    return segment.mutatorBefore +
        (segment.mutator ? position - segment.start : 0);
  }

  String mmu(int width) {
    if (width > length) return '-';
    var lowest = width;
    for (final segment in segments) {
      for (final begin in [
        segment.start,
        segment.start + segment.length - width,
      ]) {
        if (begin >= 0 && begin <= length - width)
          lowest = math.min(
            lowest,
            mutatorUntil(begin + width) - mutatorUntil(begin),
          );
      }
    }
    return pct(lowest, width);
  }
}

class Run {
  final CollectorEntry entry;
  final Config config;
  final Script script;
  late final Heap heap;
  final roots = <HeapObject?>[],
      placed = <HeapObject>[],
      cascades = <Pause>[],
      observations = <List<String>>[];
  final timeline = Timeline();
  int peakUsed = 0, failedLine = 0, failedSize = 0;
  Run(this.entry, this.config, this.script) {
    heap = Heap(
      config.heapSize,
      entry.type,
      entry.young,
      entry.age,
      script.deaths,
    );
  }
  void simulate() {
    for (final command in script.commands) {
      if (!step(command)) return;
    }
    if (entry.type == 'REFCOUNT')
      heap.reports.add(
        leakReport(
          'end',
          heap.objects
              .where((object) => !script.alive.contains(object.number))
              .toList(),
          script.deaths,
        ),
      );
  }

  void retain(HeapObject? object) {
    if (entry.type == 'REFCOUNT') heap.retain(object);
  }

  void release(HeapObject? object) {
    if (entry.type == 'REFCOUNT') heap.release(object);
  }

  void push(HeapObject? object) {
    retain(object);
    roots.add(object);
  }

  bool step(Command command) {
    final collections = heap.records.length;
    var units = 1, success = true;
    switch (command.name) {
      case 'ALLOC':
        final object = HeapObject(
          placed.length + 1,
          command.pointers,
          command.data,
        );
        units = object.size;
        success = switch (heap.type) {
          'COPYING' => heap.allocateCopy(object, roots, command.line),
          'GENERATIONAL' => heap.allocateGeneration(
            object,
            roots,
            command.line,
          ),
          _ => heap.allocateMark(object, roots, command.line),
        };
        if (success) {
          placed.add(object);
          push(object);
          peakUsed = math.max(peakUsed, usedWords(heap.objects));
        }
      case 'PUSH':
        push(value(roots, command.source));
      case 'LOAD':
        push(roots[command.slot]!.fields[command.field]);
      case 'POP':
        for (var i = 0; i < command.count; i++) {
          release(roots.removeLast());
        }
      case 'SET':
        final target = roots[command.slot]!,
            newValue = value(roots, command.source);
        if (heap.type == 'GENERATIONAL') heap.writeBarrier(target, newValue);
        retain(newValue);
        final previous = target.fields[command.field];
        target.fields[command.field] = newValue;
        release(previous);
      case 'OVERWRITE':
        final newValue = value(roots, command.source);
        retain(newValue);
        final previous = roots[command.slot];
        roots[command.slot] = newValue;
        release(previous);
      case 'CHECKPOINT':
        observations.add(observe(script.checkpoints[observations.length]));
    }
    for (final record in heap.records.skip(collections)) {
      timeline.add(false, record.work);
    }
    if (!success) {
      failedLine = command.line;
      failedSize = units;
      return false;
    }
    timeline.add(true, units);
    if (heap.type == 'REFCOUNT' && heap.released.isNotEmpty) {
      var work = 0;
      for (final object in heap.released) {
        work += 1 + object.fields.length;
      }
      cascades.add(
        Pause(
          command.line,
          work,
          usedWords(heap.released),
          false,
          heap.released.length,
        ),
      );
      heap.released.clear();
      timeline.add(false, work);
    }
    return true;
  }

  List<String> observe(Checkpoint checkpoint) {
    final live = pairOf(
          heap.objects.where(
            (object) => checkpoint.reachable.contains(object.number),
          ),
        ),
        garbage = pairOf(
          heap.objects.where(
            (object) => !checkpoint.reachable.contains(object.number),
          ),
        ),
        blocks = heap.freeList();
    var pointers = 0, forward = 0, backward = 0, distance = 0;
    for (final object in heap.objects) {
      if (!checkpoint.reachable.contains(object.number)) continue;
      for (final child in object.fields) {
        if (child == null) continue;
        pointers++;
        if (child.address > object.address) {
          forward++;
        } else if (child.address < object.address) {
          backward++;
        }
        distance += (child.address - object.address).abs();
      }
    }
    final lines = [
      'heap objects ${pairOf(heap.objects)} reachable $live garbage $garbage',
      'free total ${totalFree(blocks)} largest ${largestFree(blocks)} blocks ${blocks.length} sizes ${classTable(blocks.map((block) => block.$2))} fragmentation ${fragmentation(blocks)}',
      'locality pointers $pointers forward $forward backward $backward mean_distance ${pointers == 0 ? '-' : dec2(distance, pointers)}',
    ];
    if (heap.type == 'GENERATIONAL') {
      final young = Pair(), old = Pair(), ages = List.filled(4, 0);
      for (final object in heap.objects) {
        if (heap.isYoung(object)) {
          young.add(object);
          ages[math.min(object.age, 3)]++;
        } else {
          old.add(object);
        }
      }
      lines.add(
        'generations young $young old $old remembered ${heap.remembered.length} ages 0:${ages[0]} 1:${ages[1]} 2:${ages[2]} 3+:${ages[3]}',
      );
    }
    if (config.maps.contains(checkpoint.label)) {
      final text = heapMap(
        heap.size,
        heap.objects,
        checkpoint.reachable,
        heap.inactive(),
      );
      for (var start = 0; start < text.length; start += config.width) {
        lines.add(
          '${start.toString().padLeft(4, '0')} ${text.substring(start, start + config.width)}',
        );
      }
    }
    return lines;
  }

  List<Pause> pauses() => [
    for (final record in heap.records)
      Pause(record.line, record.work, record.freed.words, true),
    ...cascades,
  ];
  List<String> collectionBlock() {
    final lines = ['collector ${entry.name} ${entry.type}'];
    for (final record in heap.records) {
      lines.add(
        line([
          record.number,
          'line',
          record.line,
          'size',
          record.request,
          'kind',
          record.kind,
          'live',
          record.live,
          'freed',
          record.freed,
          'moved',
          record.moved,
          'promoted',
          record.promoted,
          'stack',
          record.stack,
          'work',
          record.work,
          'before',
          record.before.$1,
          record.before.$2,
          'after',
          record.after.$1,
          record.after.$2,
        ]),
      );
    }
    final allPauses = pauses(), stats = PauseStats(pauses());
    lines.add(
      'totals collections ${stats.collections} pauses ${stats.count} work ${stats.work} freed ${stats.freed} pause p50 ${stats.p50} p90 ${stats.p90} max ${stats.maximum}',
    );
    lines.add(
      'utilization ${pct(timeline.mutator, timeline.length)} mmu ${config.windows.map((width) => '$width:${timeline.mmu(width)}').join(' ')}',
    );
    if (heap.type == 'GENERATIONAL') {
      final parts = <Object>['generational'], promoted = Pair();
      for (final kind in ['minor', 'major', 'tenure', 'full']) {
        final records = heap.records
            .where((record) => record.kind == kind)
            .toList();
        parts.addAll([
          kind,
          records.length,
          records.fold(0, (total, record) => total + record.work),
        ]);
      }
      for (final record in heap.records) {
        promoted.addPair(record.promoted);
      }
      parts.addAll([
        'promoted',
        promoted,
        'barrier',
        heap.barriers,
        'remembered',
        heap.remembers,
      ]);
      lines.add(line(parts));
    }
    if (heap.type == 'REFCOUNT') {
      final freed = Pair();
      Pause? largest;
      for (final cascade in cascades) {
        freed.count += cascade.count;
        freed.words += cascade.freed;
        if (largest == null || cascade.work > largest.work) largest = cascade;
      }
      final maximum = largest == null
          ? 'max_cascade 0 0 line -'
          : 'max_cascade ${largest.count} ${largest.work} line ${largest.line}';
      lines.add(
        'refcount increments ${heap.increments} decrements ${heap.decrements} cascades ${cascades.length} freed $freed $maximum',
      );
    }
    var previous = 0;
    for (final checkpoint in script.checkpoints) {
      if (failedLine > 0 && failedLine < checkpoint.line) {
        lines.add('phase ${checkpoint.label} out_of_memory');
      } else {
        final stats = PauseStats(
          allPauses
              .where(
                (pause) =>
                    pause.line > previous && pause.line <= checkpoint.line,
              )
              .toList(),
        );
        lines.add(
          'phase ${checkpoint.label} collections ${stats.collections} pauses ${stats.count} work ${stats.work} freed ${stats.freed} max_pause ${stats.maximum}',
        );
      }
      previous = checkpoint.line;
    }
    lines.add(
      failedLine == 0
          ? 'status completed'
          : 'status out_of_memory line $failedLine size $failedSize',
    );
    return lines;
  }

  String summaryRow() {
    final stats = PauseStats(pauses());
    var live = 0, moved = 0, movedObjects = 0, maxMoves = 0;
    for (final record in heap.records) {
      live += record.live.count;
      moved += record.moved.count;
    }
    for (final object in placed) {
      if (object.moves > 0) {
        movedObjects++;
        maxMoves = math.max(maxMoves, object.moves);
      }
    }
    final end = <Object>['-', '-', '-', '-'];
    if (failedLine == 0) {
      final blocks = heap.freeList();
      end.setAll(0, [
        usedWords(heap.objects),
        totalFree(blocks),
        largestFree(blocks),
        fragmentation(blocks),
      ]);
    }
    return [
      entry.name,
      entry.type,
      failedLine == 0 ? 'completed' : 'out_of_memory',
      heap.records.length,
      stats.count,
      live,
      moved,
      movedObjects,
      maxMoves,
      stats.freed,
      stats.work,
      stats.p50,
      stats.p90,
      stats.maximum,
      peakUsed,
      ...end,
    ].join(',');
  }
}

void main() {
  final config = readConfig(), script = Script()..analyze();
  final runs = [
    for (final entry in config.collectors)
      Run(entry, config, script)..simulate(),
  ];
  final maps = <List<String>>[],
      collections = <List<String>>[],
      leaks = <List<String>>[];
  final summary = [
    'collector,type,status,collections,pauses,live,moved,moved_objects,max_moves,freed,total_work,p50_pause,p90_pause,max_pause,peak_used,end_used,end_free,largest_free,fragmentation',
  ];
  for (var i = 0; i < script.checkpoints.length; i++) {
    final checkpoint = script.checkpoints[i];
    for (final run in runs) {
      maps.add([
        'checkpoint ${checkpoint.label} line ${checkpoint.line} collector ${run.entry.name}',
        if (i < run.observations.length)
          ...run.observations[i]
        else
          'out_of_memory',
      ]);
    }
  }
  for (final run in runs) {
    collections.add(run.collectionBlock());
    summary.add(run.summaryRow());
    if (run.entry.type == 'REFCOUNT')
      leaks.add([
        'collector ${run.entry.name}',
        ...run.heap.reports.expand((report) => report),
        if (run.failedLine > 0) 'status out_of_memory',
      ]);
  }
  Directory('output').createSync(recursive: true);
  writeLines('mutator.txt', script.report());
  writeLines('heap_maps.txt', joinBlocks(maps));
  writeLines('collections.txt', joinBlocks(collections));
  writeLines('summary.csv', summary);
  writeLines('leaks.txt', leaks.isEmpty ? ['none'] : joinBlocks(leaks));
}
