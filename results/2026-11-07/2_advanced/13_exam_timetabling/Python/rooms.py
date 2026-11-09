from enrolment import read_records


class Room:
    def __init__(self, room_id, capacity):
        self.id = room_id
        self.capacity = capacity


class Placement:
    def __init__(self, course, room, first_seat):
        self.course = course
        self.room = room
        self.first_seat = first_seat
        self.last_seat = first_seat + course.size() - 1


def load_rooms(path, errors):
    rooms = {}
    for number, (room_id, capacity) in read_records(path):
        if room_id in rooms:
            errors.append(f"rooms.csv line {number}: duplicate room {room_id}")
        elif int(capacity) < 1:
            errors.append(f"rooms.csv line {number}: bad capacity {capacity}")
        else:
            rooms[room_id] = Room(room_id, int(capacity))
    return sorted(rooms.values(), key=lambda room: (room.capacity, room.id))


def packing_order(courses):
    return sorted(courses, key=lambda course: (-course.size(), course.id))


def pack(rooms, courses):
    remaining = [room.capacity for room in rooms]
    durations = [None] * len(rooms)
    placements = []
    for course in packing_order(courses):
        for index, room in enumerate(rooms):
            fits = remaining[index] >= course.size()
            if fits and durations[index] in (None, course.duration):
                placements.append(Placement(course, room, room.capacity - remaining[index] + 1))
                remaining[index] -= course.size()
                durations[index] = course.duration
                break
        else:
            return None
    return placements
