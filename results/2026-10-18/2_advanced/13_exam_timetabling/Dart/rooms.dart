import 'enrolment.dart';

class Room {
  final String id;
  final int capacity;

  Room(this.id, this.capacity);
}

class Placement {
  final Course course;
  final Room room;
  final int firstSeat;
  int get lastSeat => firstSeat + course.size - 1;

  Placement(this.course, this.room, this.firstSeat);
}

List<Room> loadRooms(String path, List<String> errors) {
  final accepted = <String, Room>{};
  for (final (number, fields) in readRecords(path)) {
    final id = fields[0], capacity = int.parse(fields[1]);
    if (accepted.containsKey(id)) {
      errors.add('rooms.csv line $number: duplicate room $id');
    } else if (capacity < 1) {
      errors.add('rooms.csv line $number: bad capacity $capacity');
    } else {
      accepted[id] = Room(id, capacity);
    }
  }
  return accepted.values.toList()..sort((a, b) {
    final order = a.capacity.compareTo(b.capacity);
    return order != 0 ? order : a.id.compareTo(b.id);
  });
}

List<Course> packingOrder(Iterable<Course> courses) => courses.toList()..sort((a, b) {
  final order = b.size.compareTo(a.size);
  return order != 0 ? order : a.id.compareTo(b.id);
});

List<Placement>? pack(List<Room> rooms, Iterable<Course> courses) {
  final remaining = rooms.map((room) => room.capacity).toList();
  final durations = List.filled(rooms.length, 0);
  final placements = <Placement>[];
  for (final course in packingOrder(courses)) {
    var placed = false;
    for (var index = 0; index < rooms.length; index++) {
      final room = rooms[index];
      if (remaining[index] >= course.size && (durations[index] == 0 || durations[index] == course.duration)) {
        placements.add(Placement(course, room, room.capacity - remaining[index] + 1));
        remaining[index] -= course.size;
        durations[index] = course.duration;
        placed = true;
        break;
      }
    }
    if (!placed) return null;
  }
  return placements;
}
