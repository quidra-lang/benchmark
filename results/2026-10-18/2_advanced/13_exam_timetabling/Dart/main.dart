import 'dart:math' as math;
import 'coloring.dart';
import 'conflict_graph.dart';
import 'enrolment.dart';
import 'report.dart';
import 'rooms.dart';
const backToBack = 0, sameDay = 1, overnight = 2, frontLoadWeight = 3;
const relations = ['back_to_back', 'same_day', 'overnight'];
const exchangeVerdicts = ['fixed', 'invalid', 'worse', 'applied'];
const swapVerdicts = ['fixed', 'invalid', 'rooms', 'worse', 'applied'];

List<String> stringKeys<V>(Map<String, V> values) => values.keys.toList()..sort();

List<int> intKeys<V>(Map<int, V> values) => values.keys.toList()..sort();

int ceilDiv(int numerator, int denominator) => (numerator + denominator - 1) ~/ denominator;

String verdictCounts(Map<String, int> tally, List<String> verdicts) => verdicts.map((verdict) => '$verdict ${tally[verdict] ?? 0}').join(' ');

class Calendar {
  late final int days, periods, limit, frontCount, deadline, ratio, slotCount;
  late final List<int> lengths, weights;
  final closed = <int>{};
  final unavailable = <String, Set<int>>{};
  final fixed = <String, int>{};
  final orders = <(String, String)>[];
  final arrows = <String, List<String>>{};

  Calendar(List<String> lines) {
    final settings = [
      for (final line in lines.take(6))
        line.split(' ').skip(1).map(int.parse).toList(),
    ];
    days = settings[0][0];
    lengths = settings[1];
    periods = lengths.length;
    limit = settings[2][0];
    weights = settings[3];
    frontCount = settings[4][0];
    deadline = settings[4][1];
    ratio = settings[5][0];
    slotCount = days * periods;
  }
  Iterable<int> get slots => Iterable.generate(slotCount, (index) => index + 1);

  int? slotAt(String dayText, String periodText) {
    final day = int.parse(dayText), period = int.parse(periodText);
    return day >= 1 && day <= days && period >= 1 && period <= periods ? (day - 1) * periods + period : null;
  }

  int dayOf(int slot) => (slot - 1) ~/ periods + 1;

  String name(int slot) => 'D${dayOf(slot)}P${(slot - 1) % periods + 1}';

  int length(int slot) => lengths[(slot - 1) % periods];

  int? relation(int first, int second) {
    final low = math.min(first, second), high = math.max(first, second);
    if (dayOf(low) == dayOf(high)) {
      if (high - low == 1) return backToBack;
      if (high - low >= 2) return sameDay;
    } else if (high - low == 1) {
      return overnight;
    }
    return null;
  }
}

class Breakdown {
  final List<int> counts;
  final int late, total;

  Breakdown(this.counts, this.late, List<int> weights) : total = weights[0] * counts[0] + weights[1] * counts[1] + weights[2] * counts[2] + weights[frontLoadWeight] * late;
  String get text => 'back_to_back ${counts[0]} same_day ${counts[1]} overnight ${counts[2]} front_load $late penalty $total';
}

class PenaltyPair {
  final String first, second;
  final int relation, shared;

  PenaltyPair(this.first, this.second, this.relation, this.shared);
}

class StudentPair {
  final int relation, lowSlot, highSlot;
  final String lowCourse, highCourse;

  StudentPair(this.relation, this.lowSlot, this.lowCourse, this.highSlot, this.highCourse);
}

class Scheduler {
  final Map<String, Course> courses;
  final Map<String, List<String>> studentCourses;
  final List<Room> rooms;
  final Calendar calendar;
  final List<String> errors;
  late final int largestRoom;
  final empty = <String>[], oversized = <String>[], schedulable = <String>[];
  late final ConflictGraph graph;
  late final List<Edge> edges;
  late final List<String> frontLoad;
  final openSlots = <int>[], fixedSlots = <int>{};
  Map<String, int> assignment = {};
  var penalty = 0;
  final attempts = <(int, int, String?)>[];
  final assignmentOrder = <(String, int, int)>[];
  final excluded = <String>[];
  final insertions = <(String, int, int)>[];
  final reasons = <String, List<String>>{};
  late Breakdown initial, exchanged;
  final exchangeLog = <String>[], swapLog = <String>[];
  final placements = <String, Placement>{};
  final slotPlacements = <int, List<Placement>>{};

  Scheduler(
    this.courses,
    this.studentCourses,
    this.rooms,
    this.calendar,
    this.errors,
  ) {
    largestRoom = rooms.map((room) => room.capacity).reduce(math.max);
    final vertices = <String>[];
    for (final id in stringKeys(courses)) {
      final size = courses[id]!.size;
      if (size > 0) vertices.add(id);
      if (size == 0) {
        empty.add(id);
      } else if (size > largestRoom) {
        oversized.add(id);
      } else {
        schedulable.add(id);
      }
    }
    graph = ConflictGraph(vertices, studentCourses.values);
    edges = graph.edges();
    frontLoad = bySize(schedulable).take(calendar.frontCount).toList();
  }

  List<String> bySize(Iterable<String> ids) => ids.toList()..sort((a, b) {
    final order = courses[b]!.size.compareTo(courses[a]!.size);
    return order != 0 ? order : a.compareTo(b);
  });

  List<String> byDegree(Iterable<String> ids) => ids.toList()..sort((a, b) {
    final order = graph.degree(b).compareTo(graph.degree(a));
    return order != 0 ? order : a.compareTo(b);
  });

  List<String> blockedStudents(Course course, int slot) => [for (final student in course.students) if (calendar.unavailable[student]?.contains(slot) ?? false) student];

  bool suitable(Course course, int slot) => calendar.length(slot) >= course.duration && blockedStudents(course, slot).isEmpty;

  bool packs(Iterable<String> ids) => pack(rooms, ids.map((id) => courses[id]!)) != null;

  String outside(String day, String period) => 'slot $day $period outside calendar';

  void validateCalendar(List<String> lines) {
    for (var index = 6; index < lines.length; index++) {
      final fields = lines[index].split(' '), args = fields.skip(1).toList();
      final message = switch (fields.first) {
        'closed' => acceptClosed(args),
        'unavailable' => acceptUnavailable(args),
        'fixed' => acceptFixed(args),
        'after' => acceptAfter(args),
        _ => null,
      };
      if (message != null) errors.add('calendar.txt line ${index + 1}: $message');
    }
    openSlots.addAll(calendar.slots.where((slot) => !calendar.closed.contains(slot)));
    fixedSlots.addAll(calendar.fixed.values);
  }

  String? acceptClosed(List<String> fields) {
    final slot = calendar.slotAt(fields[0], fields[1]);
    if (slot == null) return outside(fields[0], fields[1]);
    if (calendar.closed.contains(slot)) return 'duplicate closed ${calendar.name(slot)}';
    calendar.closed.add(slot);
    return null;
  }

  String? acceptUnavailable(List<String> fields) {
    final student = fields[0];
    if (!studentCourses.containsKey(student)) return 'unknown student $student';
    final slot = calendar.slotAt(fields[1], fields[2]);
    if (slot == null) return outside(fields[1], fields[2]);
    final blocked = calendar.unavailable.putIfAbsent(student, () => <int>{});
    if (blocked.contains(slot)) return 'duplicate unavailable $student ${calendar.name(slot)}';
    blocked.add(slot);
    return null;
  }

  String? acceptFixed(List<String> fields) {
    final id = fields[0];
    if (!courses.containsKey(id)) return 'unknown course $id';
    if (!schedulable.contains(id)) return 'course $id not schedulable';
    final slot = calendar.slotAt(fields[1], fields[2]);
    if (slot == null) return outside(fields[1], fields[2]);
    final name = calendar.name(slot);
    if (calendar.closed.contains(slot)) return 'slot $name closed';
    if (!suitable(courses[id]!, slot)) return 'slot $name unsuitable for $id';
    if (calendar.fixed.containsKey(id)) return 'duplicate fixed $id';
    final group = coursesAt(calendar.fixed, slot), clashes = group.where((other) => graph.neighbours(id).containsKey(other));
    if (clashes.isNotEmpty) return 'conflict $id ${clashes.first}';
    if (!packs([...group, id])) return 'rooms full $name';
    calendar.fixed[id] = slot;
    return null;
  }

  String? acceptAfter(List<String> fields) {
    final later = fields[0], earlier = fields[1];
    for (final id in fields) {
      if (!courses.containsKey(id)) return 'unknown course $id';
    }
    for (final id in fields) {
      if (!schedulable.contains(id)) return 'course $id not schedulable';
    }
    if (later == earlier) return 'bad order $later $earlier';
    if (calendar.orders.contains((later, earlier))) return 'duplicate order $later $earlier';
    if (reachable(calendar.arrows, earlier, later)) return 'cycle $later $earlier';
    final laterSlot = calendar.fixed[later], earlierSlot = calendar.fixed[earlier];
    if (laterSlot != null && earlierSlot != null && laterSlot <= earlierSlot) return 'fixed order $later $earlier';
    calendar.orders.add((later, earlier));
    calendar.arrows.putIfAbsent(later, () => []).add(earlier);
    return null;
  }

  List<String> coursesAt(Map<String, int> state, int slot) => [for (final entry in state.entries) if (entry.value == slot) entry.key]..sort();

  List<String> orderConflicts(String id, int slot, Map<String, int> state) {
    final conflicts = <String>[];
    for (final (later, earlier) in calendar.orders) {
      if (later == id && state.containsKey(earlier) && slot <= state[earlier]!) {
        conflicts.add(earlier);
      } else if (earlier == id && state.containsKey(later) && slot >= state[later]!) {
        conflicts.add(later);
      }
    }
    return conflicts;
  }

  bool ordersSatisfied(Map<String, int> state) => calendar.orders.every((order) => !state.containsKey(order.$1) || !state.containsKey(order.$2) || state[order.$1]! > state[order.$2]!);

  List<int> candidateSlots(String id, Map<String, int> state) {
    final candidates = <int>[];
    for (final slot in openSlots) {
      if (!suitable(courses[id]!, slot)) continue;
      if (graph.neighbours(id).keys.any((other) => state[other] == slot)) continue;
      if (orderConflicts(id, slot, state).isNotEmpty) continue;
      if (packs([...coursesAt(state, slot), id])) candidates.add(slot);
    }
    return candidates;
  }

  void buildTimetable() {
    while (true) {
      final pending = schedulable.where((id) =>
          !calendar.fixed.containsKey(id) && !excluded.contains(id)).toList();
      final state = Map<String, int>.from(calendar.fixed);
      final attempt = Attempt(pending, graph, calendar.limit, candidateSlots);
      final success = attempt.search(state);
      final failed = success ? null : attempt.deadEndCourse;
      attempts.add((pending.length, attempt.deadEnds, failed));
      if (!success) {
        excluded.add(failed!);
        continue;
      }
      assignment = state;
      assignmentOrder.addAll([for (final (id, saturation) in attempt.chosen) (id, state[id]!, saturation)]);
      return;
    }
  }

  List<PenaltyPair> penaltyPairs(Map<String, int> state) {
    final pairs = <PenaltyPair>[];
    for (final edge in edges) {
      final first = state[edge.first], second = state[edge.second];
      if (first == null || second == null) continue;
      final relation = calendar.relation(first, second);
      if (relation != null) pairs.add(PenaltyPair(edge.first, edge.second, relation, edge.shared));
    }
    return pairs;
  }

  List<String> lateCourses(Map<String, int> state) => [for (final id in frontLoad) if (state.containsKey(id) && state[id]! > calendar.deadline) id];
  Breakdown breakdown(Map<String, int> state) {
    final counts = [0, 0, 0];
    for (final pair in penaltyPairs(state)) {
      counts[pair.relation] += pair.shared;
    }
    return Breakdown(counts, lateCourses(state).length, calendar.weights);
  }

  Map<String, int> contributions() {
    final result = {for (final id in assignment.keys) id: 0};
    for (final pair in penaltyPairs(assignment)) {
      final amount = calendar.weights[pair.relation] * pair.shared;
      result[pair.first] = result[pair.first]! + amount;
      result[pair.second] = result[pair.second]! + amount;
    }
    for (final id in lateCourses(assignment)) {
      result[id] = result[id]! + calendar.weights[frontLoadWeight];
    }
    return result;
  }

  String blockingReason(String id, int slot) {
    final course = courses[id]!;
    if (calendar.closed.contains(slot)) return 'closed';
    if (calendar.length(slot) < course.duration) return 'too_short';
    final blocked = blockedStudents(course, slot);
    if (blocked.isNotEmpty) return 'unavailable ${blocked.first}';
    final clashes = graph.neighbours(id).entries.where((entry) => assignment[entry.key] == slot).toList()..sort((a, b) {
      final order = b.value.compareTo(a.value);
      return order != 0 ? order : a.key.compareTo(b.key);
    });
    if (clashes.isNotEmpty) return 'conflict ${clashes.first.key} shared ${clashes.first.value}';
    final conflicts = orderConflicts(id, slot, assignment)..sort();
    if (conflicts.isNotEmpty) return 'order ${conflicts.first}';
    return 'rooms';
  }

  void insertExcluded() {
    final ids = excluded.toList()..sort();
    for (final id in ids) {
      final slots = candidateSlots(id, assignment);
      if (slots.isEmpty) {
        reasons[id] = [for (final slot in calendar.slots) blockingReason(id, slot)];
        continue;
      }
      final before = breakdown(assignment).total;
      int? best, bestTotal;
      for (final slot in slots) {
        final trial = Map<String, int>.from(assignment)..[id] = slot;
        final total = breakdown(trial).total;
        if (best == null || total < bestTotal!) {
          best = slot;
          bestTotal = total;
        }
      }
      final chosen = best!;
      assignment[id] = chosen;
      insertions.add((id, chosen, bestTotal! - before));
    }
    initial = breakdown(assignment);
    penalty = initial.total;
  }

  List<String> unscheduled() => [...oversized, ...excluded.where((id) => !assignment.containsKey(id))]..sort();

  bool validTrial(Map<String, int> trial, Iterable<String> moved) => moved.every((id) => suitable(courses[id]!, trial[id]!)) && ordersSatisfied(trial);

  List<String> movedCourses(Map<String, int> trial) => [for (final entry in trial.entries) if (assignment[entry.key] != entry.value) entry.key]..sort();

  (String, Map<String, int>?, int) exchangeTrial(int first, int second) {
    if (fixedSlots.contains(first) || fixedSlots.contains(second)) return ('fixed', null, 0);
    final trial = Map<String, int>.from(assignment);
    for (final entry in assignment.entries) {
      if (entry.value == first) {
        trial[entry.key] = second;
      } else if (entry.value == second) {
        trial[entry.key] = first;
      }
    }
    if (!validTrial(trial, movedCourses(trial))) return ('invalid', null, 0);
    final total = breakdown(trial).total;
    return total >= penalty ? ('worse', null, 0) : ('applied', trial, total);
  }

  void exchangeSlots() {
    var serial = 0, round = 0;
    while (true) {
      round++;
      final tally = <String, int>{}, records = <String>[];
      var pairs = 0;
      for (var index = 0; index < openSlots.length; index++) {
        final first = openSlots[index];
        for (final second in openSlots.skip(index + 1)) {
          pairs++;
          final (verdict, trial, total) = exchangeTrial(first, second);
          tally[verdict] = (tally[verdict] ?? 0) + 1;
          if (verdict == 'applied') {
            serial++;
            records.add('EXCHANGE $serial ${calendar.name(first)} ${calendar.name(second)} penalty $penalty -> $total');
            assignment = trial!;
            penalty = total;
          }
        }
      }
      exchangeLog.add('ROUND $round pairs $pairs ${verdictCounts(tally, exchangeVerdicts)}');
      exchangeLog.addAll(records);
      if ((tally['applied'] ?? 0) == 0) break;
    }
    exchanged = breakdown(assignment);
  }

  (String, Map<String, int>?, int) swapTrial(String id, int home, int target) {
    final chain = graph.kempeChain(assignment, id, home, target);
    if (chain.any(calendar.fixed.containsKey)) return ('fixed', null, 0);
    final trial = Map<String, int>.from(assignment);
    for (final member in chain) {
      trial[member] = assignment[member] == home ? target : home;
    }
    if (!validTrial(trial, chain)) return ('invalid', null, 0);
    if (!packs(coursesAt(trial, home)) || !packs(coursesAt(trial, target))) return ('rooms', null, 0);
    final total = breakdown(trial).total;
    return total >= penalty ? ('worse', null, 0) : ('applied', trial, total);
  }

  void swapChains() {
    var serial = 0, pass = 0;
    while (true) {
      pass++;
      final tally = <String, int>{}, records = <String>[];
      var candidates = 0;
      final movable = assignment.keys.where((id) => !calendar.fixed.containsKey(id)).toList()..sort();
      for (final id in movable) {
        final home = assignment[id]!;
        for (final target in openSlots) {
          if (target == home) continue;
          candidates++;
          final (verdict, trial, total) = swapTrial(id, home, target);
          tally[verdict] = (tally[verdict] ?? 0) + 1;
          if (verdict != 'applied') continue;
          final accepted = trial!;
          serial++;
          final chain = movedCourses(accepted);
          records.add('SWAP $serial $id ${calendar.name(home)} ${calendar.name(target)} chain ${chain.length} penalty $penalty -> $total');
          for (final member in chain) {
            records.add('  MOVE $member ${calendar.name(assignment[member]!)} -> ${calendar.name(accepted[member]!)}');
          }
          assignment = accepted;
          penalty = total;
          break;
        }
      }
      swapLog.add('PASS $pass candidates $candidates ${verdictCounts(tally, swapVerdicts)}');
      swapLog.addAll(records);
      if ((tally['applied'] ?? 0) == 0) break;
    }
  }

  void assignRooms() {
    for (final slot in openSlots) {
      final placed = pack(rooms, coursesAt(assignment, slot).map((id) => courses[id]!))!;
      slotPlacements[slot] = placed;
      for (final placement in placed) {
        placements[placement.course.id] = placement;
      }
    }
  }

  List<(Room, List<Placement>)> roomGroups(int slot) {
    final groups = <(Room, List<Placement>)>[];
    for (final room in rooms) {
      final placed = slotPlacements[slot]!.where((placement) => identical(placement.room, room)).toList();
      if (placed.isNotEmpty) groups.add((room, placed));
    }
    return groups;
  }

  int invigilators(int slot) => roomGroups(slot).fold(0, (total, group) =>
      total + ceilDiv(group.$2.fold(0, (students, placed) =>
          students + placed.course.size), calendar.ratio));

  (int, int) slotLoad(int slot) {
    final ids = coursesAt(assignment, slot);
    return (ids.length, ids.fold(0, (students, id) => students + courses[id]!.size));
  }

  List<(int, String)> studentExams(String student) => [for (final id in studentCourses[student]!) if (assignment.containsKey(id)) (assignment[id]!, id)]..sort((a, b) {
    final order = a.$1.compareTo(b.$1);
    return order != 0 ? order : a.$2.compareTo(b.$2);
  });

  List<StudentPair> studentPairs(String student) {
    final assigned = studentExams(student), pairs = <StudentPair>[];
    for (var index = 0; index < assigned.length; index++) {
      final (lowSlot, lowCourse) = assigned[index];
      for (final (highSlot, highCourse) in assigned.skip(index + 1)) {
        final relation = calendar.relation(lowSlot, highSlot);
        if (relation != null) pairs.add(StudentPair(relation, lowSlot, lowCourse, highSlot, highCourse));
      }
    }
    return pairs;
  }

  (List<int>, int) studentPenalty(String student) {
    final counts = [0, 0, 0];
    for (final pair in studentPairs(student)) {
      counts[pair.relation]++;
    }
    return (counts, counts[0] * calendar.weights[0] + counts[1] * calendar.weights[1] + counts[2] * calendar.weights[2]);
  }

  List<String> timetableLines() {
    final c = calendar;
    final lines = [
      'TIMETABLE days ${c.days} periods ${c.periods} open ${openSlots.length}'
      ' courses ${courses.length} scheduled ${assignment.length}'
      ' unscheduled ${unscheduled().length} empty ${empty.length}',
    ];
    lines.add(fixedWidthLine('DAY', [for (var period = 1; period <= c.periods; period++) 'P$period', 'TOTAL'], 4, 10));
    for (var day = 1; day <= c.days; day++) {
      final cells = <String>[];
      var dayExams = 0, dayStudents = 0;
      for (var period = 1; period <= c.periods; period++) {
        final slot = (day - 1) * c.periods + period;
        if (c.closed.contains(slot)) {
          cells.add('closed');
          continue;
        }
        final (exams, students) = slotLoad(slot);
        cells.add('$exams/$students');
        dayExams += exams;
        dayStudents += students;
      }
      cells.add('$dayExams/$dayStudents');
      lines.add(fixedWidthLine('D$day', cells, 4, 10));
    }
    for (final slot in c.slots) {
      final prefix = 'SLOT $slot ${c.name(slot)} minutes ${c.length(slot)}';
      if (c.closed.contains(slot)) {
        lines.add('$prefix closed');
        continue;
      }
      final (exams, students) = slotLoad(slot);
      final groups = roomGroups(slot), seats = groups.fold(0, (total, group) => total + group.$1.capacity);
      lines.add('$prefix exams $exams students $students rooms ${groups.length} seats $seats invigilators ${invigilators(slot)}');
      for (final placement in slotPlacements[slot]!) {
        final course = placement.course, marker = c.fixed.containsKey(course.id) ? ' fixed' : '';
        lines.add('  ${course.id} ${course.duration}min students ${course.size} room ${placement.room.id} seats ${placement.firstSeat}-${placement.lastSeat}$marker ${course.name}');
      }
    }
    for (final room in rooms) {
      var slotsUsed = 0, exams = 0, seated = 0;
      for (final slot in openSlots) {
        for (final (groupRoom, placed) in roomGroups(slot)) {
          if (identical(groupRoom, room)) {
            slotsUsed++;
            exams += placed.length;
            seated += placed.fold(0, (total, placement) => total + placement.course.size);
          }
        }
      }
      lines.add('ROOM ${room.id} capacity ${room.capacity} slots $slotsUsed exams $exams seated $seated utilization ${roundedPercent(seated, room.capacity * openSlots.length)}');
    }
    lines.add('INVIGILATORS total ${openSlots.fold(0, (total, slot) => total + invigilators(slot))} ratio ${c.ratio}');
    return lines;
  }

  List<String> roomLines() => [
    'slot,room,course,students,first_seat,last_seat',
    for (final slot in openSlots)
      for (final (room, placed) in roomGroups(slot))
        for (final p in placed)
          '${calendar.name(slot)},${room.id},${p.course.id},${p.course.size},${p.firstSeat},${p.lastSeat}',
  ];

  List<String> penaltyLines() {
    final c = calendar;
    final weights = c.weights;
    final finalPenalty = breakdown(assignment);
    final lines = [
      'WEIGHTS back_to_back ${weights[0]} same_day ${weights[1]} overnight ${weights[2]} front_load ${weights[frontLoadWeight]}',
      'FRONT_LOAD courses ${frontLoad.length} last_slot ${c.name(c.deadline)}',
      'INITIAL ${initial.text}',
      ...exchangeLog,
      'EXCHANGED ${exchanged.text}',
      ...swapLog,
      'FINAL ${finalPenalty.text}',
      'SAVED ${initial.total - finalPenalty.total}',
    ];
    final daily = List.generate(c.days + 1, (_) => [0, 0, 0]);
    for (final pair in penaltyPairs(assignment)) {
      final day = c.dayOf(math.min(assignment[pair.first]!, assignment[pair.second]!));
      daily[day][pair.relation] += pair.shared;
    }
    for (var day = 1; day <= c.days; day++) {
      final counts = daily[day];
      lines.add('DAY D$day back_to_back ${counts[0]} same_day ${counts[1]} overnight ${counts[2]}');
    }
    for (final id in lateCourses(assignment)) {
      lines.add('LATE $id ${c.name(assignment[id]!)} students ${courses[id]!.size}');
    }
    final contribution = contributions(), ranked = stringKeys(contribution)..sort((a, b) {
      final order = contribution[b]!.compareTo(contribution[a]!);
      return order != 0 ? order : a.compareTo(b);
    });
    for (final id in ranked.take(10)) {
      if (contribution[id]! > 0) lines.add('COURSE $id ${c.name(assignment[id]!)} penalty ${contribution[id]}');
    }
    lines.addAll(studentStatistics());
    return lines;
  }

  List<String> studentStatistics() {
    final histogram = <int, int>{};
    final gaps = <int, int>{};
    final dayLoads = <int, int>{};
    final ranking = <(String, List<int>, int)>[];
    for (final student in studentCourses.keys) {
      final (counts, total) = studentPenalty(student);
      histogram[total] = (histogram[total] ?? 0) + 1;
      ranking.add((student, counts, total));
      final exams = studentExams(student);
      for (var index = 1; index < exams.length; index++) {
        final gap = exams[index].$1 - exams[index - 1].$1;
        gaps[gap] = (gaps[gap] ?? 0) + 1;
      }
      if (exams.isNotEmpty) {
        final perDay = <int, int>{};
        for (final (slot, _) in exams) {
          final day = calendar.dayOf(slot);
          perDay[day] = (perDay[day] ?? 0) + 1;
        }
        final most = perDay.values.reduce(math.max);
        dayLoads[most] = (dayLoads[most] ?? 0) + 1;
      }
    }
    final lines = [
      for (final value in intKeys(histogram)) 'HISTOGRAM $value ${histogram[value]}',
      for (final value in intKeys(gaps)) 'GAP $value ${gaps[value]}',
      for (final value in intKeys(dayLoads)) 'DAYLOAD $value ${dayLoads[value]}',
    ];
    ranking.sort((a, b) {
      final order = b.$3.compareTo(a.$3);
      return order != 0 ? order : a.$1.compareTo(b.$1);
    });
    for (final (student, counts, total) in ranking.take(5)) {
      if (total > 0) lines.add('WORST $student penalty $total back_to_back ${counts[0]} same_day ${counts[1]} overnight ${counts[2]}');
    }
    return lines;
  }

  List<String> scheduleLines(List<String> queries) {
    final lines = <String>[];
    for (final student in queries) {
      if (!studentCourses.containsKey(student)) {
        lines.add('STUDENT $student not found');
        continue;
      }
      final ids = studentCourses[student]!, assigned = studentExams(student);
      final (_, total) = studentPenalty(student);
      lines.add('STUDENT $student exams ${ids.length} scheduled ${assigned.length} penalty $total');
      for (final (slot, id) in assigned) {
        final placement = placements[id]!, course = placement.course, seat = placement.firstSeat + course.students.indexOf(student);
        lines.add('  ${calendar.name(slot)} $id room ${placement.room.id} seat $seat ${course.name}');
      }
      for (final id in ids) {
        if (!assignment.containsKey(id)) lines.add('  UNSCHEDULED $id ${courses[id]!.name}');
      }
      for (final pair in studentPairs(student)) {
        lines.add('  ${relations[pair.relation].toUpperCase()} ${calendar.name(pair.lowSlot)} ${pair.lowCourse} ${calendar.name(pair.highSlot)} ${pair.highCourse}');
      }
      final blocked = (calendar.unavailable[student] ?? <int>{}).toList()..sort();
      for (final slot in blocked) {
        lines.add('  UNAVAILABLE ${calendar.name(slot)}');
      }
    }
    return lines;
  }

  List<String> statusLines() {
    final contribution = contributions(), lines = ['course,status,slot,students,minutes,degree,penalty'];
    for (final id in stringKeys(courses)) {
      final course = courses[id]!;
      final status = calendar.fixed.containsKey(id) ? 'fixed' : assignment.containsKey(id) ? 'scheduled' : oversized.contains(id) ? 'too_large' : empty.contains(id) ? 'empty' : 'no_slot';
      final slot = assignment.containsKey(id) ? calendar.name(assignment[id]!) : '-';
      lines.add('$id,$status,$slot,${course.size},${course.duration},${graph.degree(id)},${contribution[id] ?? 0}');
    }
    return lines;
  }

  List<String> graphLines() {
    final vertices = graph.vertices.length;
    final edgeCount = edges.length;
    final shared = edges.fold(0, (total, edge) => total + edge.shared);
    final density = vertices >= 2 ? 2000 * edgeCount ~/ (vertices * (vertices - 1)) : 0;
    final lines = ['GRAPH courses $vertices edges $edgeCount shared $shared density $density'];
    for (final id in byDegree(graph.vertices).take(5)) {
      lines.add('DEGREE $id neighbours ${graph.degree(id)} shared ${graph.sharedTotal(id)} students ${courses[id]!.size}');
    }
    final components = graph.components();
    lines.add('COMPONENTS ${components.length}');
    for (var index = 0; index < components.length; index++) {
      final component = components[index];
      lines.add('COMPONENT ${index + 1} size ${component.length} first ${component.first}');
    }
    final clique = graph.greedyClique(schedulable);
    lines.add(['CLIQUE', 'size', '${clique.length}', ...clique].join(' '));
    return lines;
  }

  List<String> capacityLines() {
    final loads = studentCourses.values.map((ids) => ids.length).toList();
    final most = loads.reduce(math.max);
    final demand = schedulable.fold(0, (total, id) => total + courses[id]!.size);
    final capacity = rooms.fold(0, (total, room) => total + room.capacity);
    final lines = [
      'LOAD max_exams $most students ${loads.where((load) => load == most).length}',
      'SEATS demand $demand capacity $capacity min_slots ${ceilDiv(demand, capacity)}',
      'HEURISTIC largest_degree slots ${greedyNumbering(byDegree(schedulable), graph)}',
      'HEURISTIC largest_enrolment slots ${greedyNumbering(bySize(schedulable), graph)}',
    ];
    final table = bySize(graph.vertices).take(8).toList();
    lines.add(fixedWidthLine('MATRIX', table, 9, 9));
    for (final row in table) {
      final cells = [for (final column in table) column == row ? '-' : '${graph.neighbours(row)[column] ?? 0}'];
      lines.add(fixedWidthLine(row, cells, 9, 9));
    }
    return lines;
  }

  List<String> reportLines() {
    final c = calendar;
    final enrolments = studentCourses.values.fold(0, (total, ids) => total + ids.length);
    final lines = [
      'INPUT courses ${courses.length} enrolments $enrolments rooms ${rooms.length} students ${studentCourses.length} errors ${errors.length}',
      for (final error in errors) 'ERROR $error',
      ...graphLines(),
      ...capacityLines(),
      for (final id in empty) 'EMPTY $id',
      for (final id in oversized) 'TOO_LARGE $id students ${courses[id]!.size} largest_room $largestRoom',
    ];
    final closed = c.closed.toList()..sort();
    for (final slot in closed) {
      lines.add('CLOSED ${c.name(slot)}');
    }
    for (final id in stringKeys(c.fixed)) {
      lines.add('FIXED $id ${c.name(c.fixed[id]!)}');
    }
    for (final (later, earlier) in c.orders) {
      lines.add('AFTER $later $earlier');
    }
    for (var index = 0; index < attempts.length; index++) {
      final (size, deadEnds, failed) = attempts[index];
      final result = failed == null ? 'success' : 'failed $failed';
      lines.add('ATTEMPT ${index + 1} courses $size backtracks $deadEnds $result');
    }
    for (var index = 0; index < assignmentOrder.length; index++) {
      final (id, slot, saturation) = assignmentOrder[index];
      lines.add('ORDER ${index + 1} $id ${c.name(slot)} saturation $saturation degree ${graph.degree(id)}');
    }
    for (final (id, slot, increase) in insertions) {
      lines.add('INSERTED $id ${c.name(slot)} penalty $increase');
    }
    for (final id in unscheduled()) {
      final reason = oversized.contains(id) ? 'too_large' : 'no_slot';
      lines.add('UNSCHEDULED $id reason $reason students ${courses[id]!.size}');
      final recorded = reasons[id] ?? <String>[];
      for (var index = 0; index < recorded.length; index++) {
        lines.add('  ${c.name(index + 1)} ${recorded[index]}');
      }
    }
    lines.add('SUMMARY scheduled ${assignment.length} unscheduled ${unscheduled().length} slots_used ${assignment.values.toSet().length} penalty $penalty');
    return lines;
  }
}

void main() {
  final errors = <String>[];
  final courses = loadCourses('input/courses.csv', errors);
  final students = loadEnrolments('input/enrolments.csv', courses, errors);
  final rooms = loadRooms('input/rooms.csv', errors);
  final calendarLines = readLines('input/calendar.txt');
  final scheduler = Scheduler(courses, students, rooms, Calendar(calendarLines), errors);
  scheduler.validateCalendar(calendarLines);
  scheduler.buildTimetable();
  scheduler.insertExcluded();
  scheduler.exchangeSlots();
  scheduler.swapChains();
  scheduler.assignRooms();
  writeFiles('output', {
    'timetable.txt': scheduler.timetableLines(),
    'rooms.csv': scheduler.roomLines(),
    'penalties.txt': scheduler.penaltyLines(),
    'student_schedules.txt': scheduler.scheduleLines(readLines('input/queries.txt')),
    'course_status.csv': scheduler.statusLines(),
    'report.txt': scheduler.reportLines(),
  });
}
