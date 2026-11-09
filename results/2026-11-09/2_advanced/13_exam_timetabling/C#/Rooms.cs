#nullable enable
using System;
using System.Linq;
using System.Collections.Generic;

sealed record Room(string Id, int Capacity);
sealed record Placement(Course Course, Room Room, int FirstSeat, int LastSeat);

static class Rooms
{
    public static List<Room> Load(string path, List<string> errors)
    {
        var rooms = new Dictionary<string, Room>(StringComparer.Ordinal);
        int line = 1;
        foreach (string[] fields in Enrolment.Records(path))
        {
            line++;
            string id = fields[0];
            int capacity = int.Parse(fields[1]);
            if (rooms.ContainsKey(id)) errors.Add($"rooms.csv line {line}: duplicate room {id}");
            else if (capacity < 1) errors.Add($"rooms.csv line {line}: bad capacity {fields[1]}");
            else rooms[id] = new Room(id, capacity);
        }
        return rooms.Values.OrderBy(room => room.Capacity).ThenBy(room => room.Id, StringComparer.Ordinal).ToList();
    }

    public static List<Placement>? Pack(List<Room> rooms, IEnumerable<Course> courses)
    {
        int[] remaining = rooms.Select(room => room.Capacity).ToArray();
        var durations = new int[rooms.Count];
        var placements = new List<Placement>();
        foreach (Course course in courses.OrderByDescending(course => course.Size)
            .ThenBy(course => course.Id, StringComparer.Ordinal))
        {
            bool placed = false;
            for (int i = 0; i < rooms.Count; i++)
            {
                if (remaining[i] < course.Size || (durations[i] != 0 && durations[i] != course.Duration)) continue;
                Room room = rooms[i];
                int first = room.Capacity - remaining[i] + 1;
                placements.Add(new Placement(course, room, first, first + course.Size - 1));
                remaining[i] -= course.Size;
                durations[i] = course.Duration;
                placed = true;
                break;
            }
            if (!placed) return null;
        }
        return placements;
    }
}
