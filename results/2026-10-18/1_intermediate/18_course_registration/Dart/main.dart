import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;

const days = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
const gradePoints = {'A': 4, 'B': 3, 'C': 2, 'D': 1, 'F': 0};
final coursePattern = RegExp(r'^[A-Z]{2,4}[0-9]{3}$');
final yearPattern = RegExp(r'^Y[1-9]$');

class CommandError implements Exception {
  final String message;
  CommandError(this.message);
}

Never fail(String message) => throw CommandError(message);

String time(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
    '${(minutes % 60).toString().padLeft(2, '0')}';

String rate(int enrolled, int capacity) =>
    capacity == 0 ? 'n/a' : '${enrolled * 100 ~/ capacity}%';

class Slot {
  final String raw;
  final int day;
  final int start;
  final int end;
  Slot(this.raw, this.day, this.start, this.end);

  bool overlaps(Slot other) =>
      day == other.day && start < other.end && other.start < end;

  String get range => '${time(start)}-${time(end)}';
}

List<Slot> parseSlots(String text) {
  if (text == '-') return [];
  final slots = <Slot>[];
  for (final raw in text.split(',')) {
    final day = days.indexOf(raw.substring(0, 2));
    final sh = int.parse(raw.substring(2, 4));
    final sm = int.parse(raw.substring(4, 6));
    final eh = int.parse(raw.substring(7, 9));
    final em = int.parse(raw.substring(9, 11));
    final start = sh * 60 + sm;
    final end = eh * 60 + em;
    if (day < 0 || sh > 23 || sm > 59 || eh > 23 || em > 59 ||
        start >= end) {
      fail('invalid slot $raw');
    }
    slots.add(Slot(raw, day, start, end));
  }
  for (var i = 0; i < slots.length; i++) {
    for (var j = i + 1; j < slots.length; j++) {
      if (slots[i].overlaps(slots[j])) {
        fail('overlapping slots ${slots[i].raw} ${slots[j].raw}');
      }
    }
  }
  return slots;
}

sealed class Prerequisite {
  bool accepts(Student student);
  bool contains(String code);
  String get canonical;
}

class Condition extends Prerequisite {
  final String word;
  Condition(this.word);

  bool get isYear => word.length == 2;

  @override
  bool accepts(Student student) => isYear
      ? student.year >= int.parse(word[1])
      : student.passed(word);

  @override
  bool contains(String code) => !isYear && word == code;

  @override
  String get canonical => word;
}

class Junction extends Prerequisite {
  final bool all;
  final List<Prerequisite> children;
  Junction(this.all, this.children);

  @override
  bool accepts(Student student) => all
      ? children.every((child) => child.accepts(student))
      : children.any((child) => child.accepts(student));

  @override
  bool contains(String code) => children.any((child) => child.contains(code));

  @override
  String get canonical => children.map((child) {
    final text = child.canonical;
    return all && child is Junction && !child.all ? '($text)' : text;
  }).join(all ? '&' : '|');
}

class PrerequisiteParser {
  final String course;
  final List<String> tokens;
  int position = 0;

  PrerequisiteParser(this.course, String source)
      : tokens = RegExp(r'[A-Z0-9]+|[&|()]')
            .allMatches(source).map((match) => match[0]!).toList();

  bool take(String token) {
    if (position == tokens.length || tokens[position] != token) return false;
    position++;
    return true;
  }

  Prerequisite join(bool all, List<Prerequisite> nodes) {
    final children = <Prerequisite>[];
    for (final node in nodes) {
      if (node is Junction && node.all == all) {
        children.addAll(node.children);
      } else {
        children.add(node);
      }
    }
    return children.length == 1 ? children.single : Junction(all, children);
  }

  Prerequisite expression() {
    final nodes = [term()];
    while (take('|')) {
      nodes.add(term());
    }
    return join(false, nodes);
  }

  Prerequisite term() {
    final nodes = [factor()];
    while (take('&')) {
      nodes.add(factor());
    }
    return join(true, nodes);
  }

  Prerequisite factor() {
    if (take('(')) {
      final node = expression();
      if (!take(')')) fail('invalid prereq $course');
      return node;
    }
    if (position == tokens.length) fail('invalid prereq $course');
    final word = tokens[position++];
    if (!coursePattern.hasMatch(word) && !yearPattern.hasMatch(word)) {
      fail('invalid prereq $course');
    }
    return Condition(word);
  }
}

Prerequisite? parsePrerequisite(String course, String text) {
  if (text == '-') return null;
  final parser = PrerequisiteParser(course, text);
  final root = parser.expression();
  if (parser.position != parser.tokens.length) fail('invalid prereq $course');
  if (root.contains(course)) fail('self prereq $course');
  return root;
}

class GradeRecord {
  final String code;
  final String grade;
  final int credits;
  GradeRecord(this.code, this.grade, this.credits);
}

typedef HistoryEvent = ({int command, String event});
typedef Meeting = ({Course course, Slot slot});

class Student {
  final String id;
  final int year;
  int limit;
  final SplayTreeMap<String, GradeRecord> records;
  final Set<Course> enrolled = {};
  final List<HistoryEvent> history = [];

  Student(this.id, this.year, this.limit, this.records);

  bool passed(String code) {
    final record = records[code];
    return record != null && gradePoints[record.grade]! >= 2;
  }

  int get credits => enrolled.fold(0, (sum, course) => sum + course.credits);
  int get earned => records.values.where((record) => record.grade != 'F')
      .fold(0, (sum, record) => sum + record.credits);

  String get gpa {
    if (records.isEmpty) return 'n/a';
    final points = records.values.fold<int>(0,
        (sum, record) => sum + gradePoints[record.grade]! * record.credits);
    final credits = records.values.fold<int>(0,
        (sum, record) => sum + record.credits);
    final value = (200 * points + credits) ~/ (2 * credits);
    return '${value ~/ 100}.${(value % 100).toString().padLeft(2, '0')}';
  }

  List<Course> get orderedCourses => enrolled.toList()
    ..sort((a, b) => a.code.compareTo(b.code));
}

class Course {
  final String code;
  final int credits;
  int capacity;
  final List<Slot> slots;
  Prerequisite? prerequisite;
  bool open = true;
  final Set<Student> enrolled = {};
  final List<Student> waitlist = [];

  Course(this.code, this.credits, this.capacity, this.slots, this.prerequisite);

  String get status => open ? 'open' : 'closed';
  String get canonical => prerequisite?.canonical ?? '-';
  String get department => code.substring(0, code.length - 3);
  int get weekly => slots.fold(0, (sum, slot) => sum + slot.end - slot.start);
  bool get hasSeat => enrolled.length < capacity;
  bool accepts(Student student) => prerequisite?.accepts(student) ?? true;
  bool conflicts(Course other) =>
      slots.any((slot) => other.slots.any(slot.overlaps));

  int positionFor(Student student) =>
      1 + waitlist.where((other) => other.year >= student.year).length;

  void enroll(Student student) {
    enrolled.add(student);
    student.enrolled.add(this);
  }

  void drop(Student student) {
    enrolled.remove(student);
    student.enrolled.remove(this);
  }
}

class Reason {
  final String word;
  final String extra;
  Reason(this.word, [this.extra = '']);

  String get text => extra.isEmpty ? word : '$word $extra';
  Never reject(Student student, Course course) => fail(
      '$word ${student.id} ${course.code}${extra.isEmpty ? '' : ' $extra'}');
}

class Decision {
  final Reason? reason;
  final int position;
  Decision({this.reason, this.position = 0});

  String get text => reason?.text ??
      (position == 0 ? 'enroll' : 'waitlist $position');
}

class Registration {
  final courses = SplayTreeMap<String, Course>();
  final students = SplayTreeMap<String, Student>();
  final output = StringBuffer();
  int commandNumber = 0;

  void emit(String line) => output.writeln(line);

  Student student(String id) => students[id] ?? (fail('unknown student $id'));
  Course course(String code) => courses[code] ?? (fail('unknown course $code'));

  void remember(Student student, String event) =>
      student.history.add((command: commandNumber, event: event));

  List<Course> waiting(Student student) => courses.values
      .where((course) => course.waitlist.contains(student)).toList();

  Reason? availability(Student student, Course course, [Course? excluded]) {
    final enrolled = student.orderedCourses
        .where((other) => other != excluded).toList();
    for (final other in enrolled) {
      if (course.conflicts(other)) return Reason('time conflict', other.code);
    }
    final credits = course.credits +
        enrolled.fold<int>(0, (sum, other) => sum + other.credits);
    return credits > student.limit
        ? Reason('credit limit', '$credits ${student.limit}') : null;
  }

  Reason? eligibility(Student student, Course course, [Course? excluded]) {
    if (!course.open) return Reason('course closed');
    if (course.enrolled.contains(student)) return Reason('already enrolled');
    if (course.waitlist.contains(student)) return Reason('already waitlisted');
    if (student.passed(course.code)) {
      return Reason('already completed', student.records[course.code]!.grade);
    }
    if (!course.accepts(student)) return Reason('prereq not met');
    return availability(student, course, excluded);
  }

  Decision judge(Student student, Course course) {
    final reason = eligibility(student, course);
    if (reason != null) return Decision(reason: reason);
    if (course.hasSeat) return Decision();
    if (waiting(student).length >= 3) {
      return Decision(reason: Reason('waitlist limit'));
    }
    return Decision(position: course.positionFor(student));
  }

  String enrollment(Student student, Course course) =>
      'enrolled ${course.enrolled.length}/${course.capacity} '
      'credits ${student.credits}/${student.limit}';

  void promote() {
    for (final course in courses.values) {
      if (!course.open) continue;
      while (course.hasSeat) {
        final index = course.waitlist.indexWhere(
            (student) => availability(student, course) == null);
        if (index < 0) break;
        final student = course.waitlist.removeAt(index);
        course.enroll(student);
        remember(student, 'promote ${course.code}');
        emit('  PROMOTE ${student.id} ${course.code} ${enrollment(student, course)}');
      }
    }
  }

  void addCourse(List<String> args) {
    final code = args[0];
    if (courses.containsKey(code)) fail('duplicate course $code');
    final slots = parseSlots(args[3]);
    final prerequisite = parsePrerequisite(code, args[4]);
    final added = Course(code, int.parse(args[1]), int.parse(args[2]),
        slots, prerequisite);
    courses[code] = added;
    emit('COURSE $code credits ${added.credits} capacity ${added.capacity} '
        'meetings ${slots.length} weekly ${time(added.weekly)} prereq ${added.canonical}');
  }

  void addStudent(List<String> args) {
    final id = args[0];
    if (students.containsKey(id)) fail('duplicate student $id');
    final records = SplayTreeMap<String, GradeRecord>();
    if (args[3] != '-') {
      for (final raw in args[3].split(',')) {
        final parts = raw.split(':');
        final code = parts[0];
        final grade = parts[1];
        if (!gradePoints.containsKey(grade)) fail('invalid grade $id $code $grade');
        if (records.containsKey(code)) fail('duplicate record $id $code');
        records[code] = GradeRecord(code, grade, int.parse(parts[2]));
      }
    }
    final added = Student(id, int.parse(args[1]), int.parse(args[2]), records);
    students[id] = added;
    emit('STUDENT $id year ${added.year} limit ${added.limit} '
        'records ${records.length} earned ${added.earned} gpa ${added.gpa}');
  }

  void request(List<String> args, bool check) {
    final selected = student(args[0]);
    final target = course(args[1]);
    final decision = judge(selected, target);
    if (check) {
      emit('CHECK ${selected.id} ${target.code} ${decision.text}');
      return;
    }
    decision.reason?.reject(selected, target);
    if (decision.position == 0) {
      target.enroll(selected);
      remember(selected, 'enroll ${target.code}');
      emit('ENROLL ${selected.id} ${target.code} ${enrollment(selected, target)}');
    } else {
      final position = decision.position;
      target.waitlist.insert(position - 1, selected);
      remember(selected, 'waitlist ${target.code} $position');
      emit('ENROLL ${selected.id} ${target.code} waitlist $position');
    }
  }

  void drop(List<String> args) {
    final selected = student(args[0]);
    final target = course(args[1]);
    if (target.enrolled.contains(selected)) {
      target.drop(selected);
      remember(selected, 'drop ${target.code}');
      emit('DROP ${selected.id} ${target.code} ${enrollment(selected, target)}');
    } else if (target.waitlist.remove(selected)) {
      remember(selected, 'drop ${target.code} waitlist');
      emit('DROP ${selected.id} ${target.code} waitlist removed');
    } else {
      fail('not registered ${selected.id} ${target.code}');
    }
    promote();
  }

  void swap(List<String> args) {
    final selected = student(args[0]);
    final source = course(args[1]);
    final target = course(args[2]);
    if (!source.enrolled.contains(selected)) {
      fail('not enrolled ${selected.id} ${source.code}');
    }
    if (source == target) fail('same course ${source.code}');
    eligibility(selected, target, source)?.reject(selected, target);
    if (!target.hasSeat) fail('course full ${target.code}');
    source.drop(selected);
    target.enroll(selected);
    remember(selected, 'swap ${source.code} ${target.code}');
    emit('SWAP ${selected.id} ${source.code} -> ${target.code} '
        'credits ${selected.credits}/${selected.limit}');
    promote();
  }

  void setOpen(String code, bool open) {
    final target = course(code);
    if (target.open == open) fail('already ${target.status} $code');
    target.open = open;
    emit('${open ? 'OPEN' : 'CLOSE'} $code enrolled '
        '${target.enrolled.length}/${target.capacity} waitlist ${target.waitlist.length}');
    if (open) promote();
  }

  void capacity(List<String> args) {
    final target = course(args[0]);
    final value = int.parse(args[1]);
    if (value < target.enrolled.length) {
      fail('capacity below enrollment ${target.code} ${target.enrolled.length}');
    }
    final previous = target.capacity;
    target.capacity = value;
    emit('CAPACITY ${target.code} $previous -> $value');
    promote();
  }

  void limit(List<String> args) {
    final selected = student(args[0]);
    final value = int.parse(args[1]);
    if (value < selected.credits) {
      fail('limit below enrolled ${selected.id} ${selected.credits}');
    }
    final previous = selected.limit;
    selected.limit = value;
    emit('LIMIT ${selected.id} $previous -> $value');
    promote();
  }

  void prerequisite(List<String> args) {
    final target = course(args[0]);
    final replacement = parsePrerequisite(target.code, args[1]);
    target.prerequisite = replacement;
    emit('PREREQ ${target.code} ${target.canonical}');
    for (final selected in target.waitlist.toList()) {
      if (!target.accepts(selected)) {
        target.waitlist.remove(selected);
        remember(selected, 'unlist ${target.code}');
        emit('  UNLIST ${selected.id} ${target.code}');
      }
    }
  }

  void cancel(String code) {
    final target = course(code);
    emit('CANCEL $code enrolled ${target.enrolled.length} waitlist ${target.waitlist.length}');
    for (final selected in target.enrolled) {
      selected.enrolled.remove(target);
      remember(selected, 'cancel $code');
    }
    for (final selected in target.waitlist) {
      remember(selected, 'cancel $code waitlist');
    }
    courses.remove(code);
    promote();
  }

  void roster(String code) {
    final target = course(code);
    emit('ROSTER $code ${target.status} enrolled '
        '${target.enrolled.length}/${target.capacity} waitlist ${target.waitlist.length}');
    final enrolled = target.enrolled.toList()..sort((a, b) => a.id.compareTo(b.id));
    for (final selected in enrolled) {
      emit('  enrolled ${selected.id} year ${selected.year}');
    }
    for (var i = 0; i < target.waitlist.length; i++) {
      final selected = target.waitlist[i];
      emit('  waitlist ${i + 1} ${selected.id} year ${selected.year}');
    }
  }

  List<Meeting> meetings(Student student, int day) => [
    for (final course in student.enrolled)
      for (final slot in course.slots)
        if (slot.day == day) (course: course, slot: slot),
  ]..sort((a, b) => a.slot.start.compareTo(b.slot.start));

  void schedule(String id) {
    final selected = student(id);
    final weekly = selected.enrolled.fold<int>(0, (sum, course) => sum + course.weekly);
    emit('SCHEDULE $id courses ${selected.enrolled.length} credits ${selected.credits} weekly ${time(weekly)}');
    for (var day = 0; day < days.length; day++) {
      final entries = meetings(selected, day);
      if (entries.isNotEmpty) {
        emit('  ${days[day]} ${entries.map((entry) => '${entry.slot.range} ${entry.course.code}').join(' ')}');
      }
    }
    final tba = selected.orderedCourses.where((course) => course.slots.isEmpty);
    if (tba.isNotEmpty) emit('  TBA ${tba.map((course) => course.code).join(' ')}');
  }

  void free(List<String> args) {
    final selected = student(args[0]);
    final day = days.indexOf(args[1]);
    if (day < 0) fail('invalid day ${args[1]}');
    var cursor = 480;
    var total = 0;
    final ranges = <String>[];
    void append(int start, int end) {
      if (start >= end) return;
      total += end - start;
      ranges.add('${time(start)}-${time(end)}');
    }
    for (final entry in meetings(selected, day)) {
      final start = math.max(480, entry.slot.start);
      final end = math.min(1320, entry.slot.end);
      if (start >= end) continue;
      append(cursor, start);
      cursor = math.max(cursor, end);
    }
    append(cursor, 1320);
    emit('FREE ${selected.id} ${args[1]} total ${time(total)}'
        '${ranges.isEmpty ? '' : ' ${ranges.join(' ')}'}');
  }

  void info(String code) {
    final target = course(code);
    emit('INFO $code ${target.status} credits ${target.credits} '
        'capacity ${target.capacity} prereq ${target.canonical}');
    final slots = target.slots.toList()..sort((a, b) =>
        a.day != b.day ? a.day.compareTo(b.day) : a.start.compareTo(b.start));
    if (slots.isEmpty) emit('  meet TBA');
    for (final slot in slots) {
      emit('  meet ${days[slot.day]} ${slot.range}');
    }
    final required = courses.values.where(
        (course) => course.prerequisite?.contains(code) ?? false).map((course) => course.code);
    emit('  required by ${required.isEmpty ? 'none' : required.join(' ')}');
  }

  void audit(String id) {
    final selected = student(id);
    emit('AUDIT $id year ${selected.year} limit ${selected.limit}');
    for (final record in selected.records.values) {
      emit('  record ${record.code} ${record.grade} ${record.credits}');
    }
    emit('  earned ${selected.earned} gpa ${selected.gpa}');
    for (final course in selected.orderedCourses) {
      emit('  enrolled ${course.code} ${course.credits}');
    }
    emit('  credits ${selected.credits} remaining ${selected.limit - selected.credits}');
    for (final course in waiting(selected)) {
      emit('  waitlist ${course.code} ${course.waitlist.indexOf(selected) + 1}');
    }
  }

  void report() {
    String totals(Iterable<Course> selected) {
      final list = selected.toList();
      final enrolled = list.fold<int>(0, (sum, course) => sum + course.enrolled.length);
      final capacity = list.fold<int>(0, (sum, course) => sum + course.capacity);
      final waitlisted = list.fold<int>(0, (sum, course) => sum + course.waitlist.length);
      return 'courses ${list.length} enrolled $enrolled/$capacity '
          'rate ${rate(enrolled, capacity)} waitlisted $waitlisted';
    }
    emit('REPORT ${totals(courses.values)}');
    for (final course in courses.values) {
      emit('  ${course.code} ${course.status} ${course.enrolled.length}/${course.capacity} '
          '${rate(course.enrolled.length, course.capacity)} waitlist ${course.waitlist.length}');
    }
    final departments = SplayTreeSet<String>.of(courses.values.map((course) => course.department));
    for (final department in departments) {
      emit('  dept $department ${totals(courses.values.where((course) => course.department == department))}');
    }
  }

  void execute(String line) {
    commandNumber++;
    final words = line.split(' ');
    final args = words.skip(1).toList();
    try {
      switch (words[0]) {
        case 'COURSE': addCourse(args); break;
        case 'STUDENT': addStudent(args); break;
        case 'ENROLL': request(args, false); break;
        case 'CHECK': request(args, true); break;
        case 'OPTIONS': {
          final selected = student(args[0]);
          emit('OPTIONS ${selected.id} courses ${courses.length}');
          for (final course in courses.values) {
            emit('  ${course.code} ${judge(selected, course).text}');
          }
          break;
        }
        case 'DROP': drop(args); break;
        case 'SWAP': swap(args); break;
        case 'CLOSE': setOpen(args[0], false); break;
        case 'OPEN': setOpen(args[0], true); break;
        case 'CAPACITY': capacity(args); break;
        case 'LIMIT': limit(args); break;
        case 'PREREQ': prerequisite(args); break;
        case 'CANCEL': cancel(args[0]); break;
        case 'ROSTER': roster(args[0]); break;
        case 'SCHEDULE': schedule(args[0]); break;
        case 'FREE': free(args); break;
        case 'INFO': info(args[0]); break;
        case 'AUDIT': audit(args[0]); break;
        case 'HISTORY': {
          final selected = student(args[0]);
          emit('HISTORY ${selected.id} events ${selected.history.length}');
          for (final entry in selected.history) {
            emit('  ${entry.command} ${entry.event}');
          }
          break;
        }
        case 'STUDENTS': {
          emit('STUDENTS ${students.length}');
          for (final selected in students.values) {
            emit('  ${selected.id} year ${selected.year} credits ${selected.credits}/${selected.limit} '
                'courses ${selected.enrolled.length} waitlists ${waiting(selected).length}');
          }
          break;
        }
        case 'REPORT': report(); break;
      }
    } on CommandError catch (error) {
      emit('ERROR ${error.message}');
    }
  }
}

void main() {
  final count = int.parse(stdin.readLineSync()!);
  final registration = Registration();
  for (var i = 0; i < count; i++) {
    registration.execute(stdin.readLineSync()!);
  }
  stdout.write(registration.output);
}
