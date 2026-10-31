<?php

class Room
{
    public function __construct(public string $id, public int $capacity)
    {
    }
}

class Placement
{
    public int $lastSeat;

    public function __construct(public Course $course, public Room $room, public int $firstSeat)
    {
        $this->lastSeat = $firstSeat + $course->size() - 1;
    }
}

function load_rooms(string $path, array &$errors): array
{
    $rooms = [];
    foreach (read_records($path) as [$number, [$id, $capacity]]) {
        $key = id_key($id);
        if (isset($rooms[$key])) {
            $errors[] = "rooms.csv line $number: duplicate room $id";
        } elseif ((int) $capacity < 1) {
            $errors[] = "rooms.csv line $number: bad capacity $capacity";
        } else {
            $rooms[$key] = new Room($id, (int) $capacity);
        }
    }
    $rooms = array_values($rooms);
    usort($rooms, fn($a, $b) => $a->capacity <=> $b->capacity ?: strcmp($a->id, $b->id));
    return $rooms;
}

function packing_order(array $courses): array
{
    usort($courses, fn($a, $b) => $b->size() <=> $a->size() ?: strcmp($a->id, $b->id));
    return $courses;
}

function pack_courses(array $rooms, array $courses): ?array
{
    $remaining = array_map(fn($room) => $room->capacity, $rooms);
    $durations = array_fill(0, count($rooms), null);
    $placements = [];
    foreach (packing_order($courses) as $course) {
        $found = false;
        foreach ($rooms as $index => $room) {
            if ($remaining[$index] >= $course->size()
                && ($durations[$index] === null || $durations[$index] === $course->duration)) {
                $placements[] = new Placement($course, $room, $room->capacity - $remaining[$index] + 1);
                $remaining[$index] -= $course->size();
                $durations[$index] = $course->duration;
                $found = true;
                break;
            }
        }
        if (!$found) {
            return null;
        }
    }
    return $placements;
}
