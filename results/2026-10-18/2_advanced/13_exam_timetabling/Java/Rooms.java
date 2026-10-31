import java.io.IOException;
import java.util.ArrayList;
import java.util.Collection;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;

record Room(String id, int capacity) {}
record Placement(Course course, Room room, int firstSeat, int lastSeat) {}

final class Rooms {
    static List<Room> load(String path, List<String> errors) throws IOException {
        Map<String, Room> rooms = new TreeMap<>();
        int line = 1;
        for (String[] fields : Enrolment.records(path)) {
            line++;
            String id = fields[0];
            int capacity = Integer.parseInt(fields[1]);
            if (rooms.containsKey(id))
                errors.add("rooms.csv line " + line + ": duplicate room " + id);
            else if (capacity < 1)
                errors.add("rooms.csv line " + line + ": bad capacity " + fields[1]);
            else rooms.put(id, new Room(id, capacity));
        }
        return rooms.values().stream().sorted(Comparator.comparingInt(Room::capacity)
            .thenComparing(Room::id)).toList();
    }

    static List<Placement> pack(List<Room> rooms, Collection<Course> courses) {
        int[] remaining = rooms.stream().mapToInt(Room::capacity).toArray();
        int[] durations = new int[rooms.size()];
        List<Placement> placements = new ArrayList<>();
        List<Course> order = courses.stream().sorted(Comparator.comparingInt(Course::size)
            .reversed().thenComparing(course -> course.id)).toList();
        for (Course course : order) {
            boolean placed = false;
            for (int i = 0; i < rooms.size(); i++) {
                if (remaining[i] < course.size() || (durations[i] != 0 && durations[i] != course.duration))
                    continue;
                Room room = rooms.get(i);
                int first = room.capacity() - remaining[i] + 1;
                placements.add(new Placement(course, room, first, first + course.size() - 1));
                remaining[i] -= course.size();
                durations[i] = course.duration;
                placed = true;
                break;
            }
            if (!placed) return null;
        }
        return placements;
    }
}
