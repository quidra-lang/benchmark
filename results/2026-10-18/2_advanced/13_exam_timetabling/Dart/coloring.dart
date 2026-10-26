import 'conflict_graph.dart';

class Attempt {
  final List<String> courses;
  final ConflictGraph graph;
  final int limit;
  final List<int> Function(String, Map<String, int>) candidateSlots;
  var deadEnds = 0;
  String? deadEndCourse;
  var aborted = false;
  final chosen = <(String, int)>[];

  Attempt(this.courses, this.graph, this.limit, this.candidateSlots);

  int saturation(String id, Map<String, int> assignment) => {
    for (final other in graph.neighbours(id).keys) if (assignment.containsKey(other)) assignment[other]!
  }.length;

  bool search(Map<String, int> assignment) {
    String? course;
    var bestSaturation = -1, bestDegree = -1;
    for (final id in courses) {
      if (assignment.containsKey(id)) continue;
      final sat = saturation(id, assignment), degree = graph.degree(id);
      if (course == null || sat > bestSaturation || sat == bestSaturation && (degree > bestDegree || degree == bestDegree && id.compareTo(course) < 0)) {
        course = id;
        bestSaturation = sat;
        bestDegree = degree;
      }
    }
    if (course == null) return true;
    chosen.add((course, bestSaturation));
    for (final slot in candidateSlots(course, assignment)) {
      assignment[course] = slot;
      if (search(assignment)) return true;
      assignment.remove(course);
      if (aborted) return false;
    }
    chosen.removeLast();
    deadEnds++;
    deadEndCourse = course;
    aborted = deadEnds > limit;
    return false;
  }
}

int greedyNumbering(Iterable<String> order, ConflictGraph graph) {
  final numbers = <String, int>{};
  var largest = 0;
  for (final id in order) {
    final taken = {
      for (final other in graph.neighbours(id).keys) if (numbers.containsKey(other)) numbers[other]!
    };
    var number = 1;
    while (taken.contains(number)) {
      number++;
    }
    numbers[id] = number;
    if (number > largest) largest = number;
  }
  return largest;
}
