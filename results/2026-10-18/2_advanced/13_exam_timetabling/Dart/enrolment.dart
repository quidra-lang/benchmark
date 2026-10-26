import 'dart:io';

class Course {
  final String id;
  final int duration;
  final String name;
  final students = <String>[];

  Course(this.id, this.duration, this.name);
  int get size => students.length;
}

List<String> readLines(String path) => File(path).readAsLinesSync();

List<(int, List<String>)> readRecords(String path) {
  final lines = readLines(path);
  return [for (var index = 1; index < lines.length; index++) (index + 1, lines[index].split(','))];
}

Map<String, Course> loadCourses(String path, List<String> errors) {
  final courses = <String, Course>{};
  for (final (number, fields) in readRecords(path)) {
    final id = fields[0];
    if (courses.containsKey(id)) {
      errors.add('courses.csv line $number: duplicate course $id');
    } else {
      courses[id] = Course(id, int.parse(fields[1]), fields[2]);
    }
  }
  return courses;
}

Map<String, List<String>> loadEnrolments(String path, Map<String, Course> courses, List<String> errors) {
  final accepted = <(String, String)>{}, studentCourses = <String, List<String>>{};
  for (final (number, fields) in readRecords(path)) {
    final student = fields[0], id = fields[1], pair = (student, id);
    if (!courses.containsKey(id)) {
      errors.add('enrolments.csv line $number: unknown course $id');
    } else if (accepted.contains(pair)) {
      errors.add('enrolments.csv line $number: duplicate enrolment $student $id');
    } else {
      accepted.add(pair);
      courses[id]!.students.add(student);
      studentCourses.putIfAbsent(student, () => []).add(id);
    }
  }
  for (final course in courses.values) {
    course.students.sort();
  }
  for (final ids in studentCourses.values) {
    ids.sort();
  }
  return studentCourses;
}
