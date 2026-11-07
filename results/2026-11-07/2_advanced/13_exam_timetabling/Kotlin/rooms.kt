data class Room(val id: String, val capacity: Int)
data class Placement(val course: Course, val room: Room, val firstSeat: Int, val lastSeat: Int)

object Rooms {
    fun load(path: String, errors: MutableList<String>): List<Room> {
        val rooms = mutableMapOf<String, Room>()
        for ((index, fields) in Enrolment.records(path).withIndex()) {
            val (id, capacityText) = fields
            val capacity = capacityText.toInt()
            if (id in rooms) errors += "rooms.csv line ${index + 2}: duplicate room $id"
            else if (capacity < 1) errors += "rooms.csv line ${index + 2}: bad capacity $capacityText"
            else rooms[id] = Room(id, capacity)
        }
        return rooms.values.sortedWith(compareBy<Room> { it.capacity }.thenBy { it.id })
    }

    fun pack(rooms: List<Room>, courses: Collection<Course>): List<Placement>? {
        val remaining = rooms.map { it.capacity }.toIntArray()
        val durations = IntArray(rooms.size)
        val placements = mutableListOf<Placement>()
        for (course in courses.sortedWith(compareByDescending<Course> { it.size }.thenBy { it.id })) {
            var placed = false
            for ((index, room) in rooms.withIndex()) {
                if (remaining[index] < course.size || (durations[index] != 0 && durations[index] != course.duration)) continue
                val first = room.capacity - remaining[index] + 1
                placements += Placement(course, room, first, first + course.size - 1)
                remaining[index] -= course.size
                durations[index] = course.duration
                placed = true
                break
            }
            if (!placed) return null
        }
        return placements
    }
}
