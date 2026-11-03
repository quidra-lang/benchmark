package main

import (
	"fmt"
	"sort"
)

type Room struct {
	id       string
	capacity int
}
type Placement struct {
	course              *Course
	room                *Room
	firstSeat, lastSeat int
}

func loadRooms(path string, errors *[]string) []*Room {
	accepted := map[string]*Room{}
	for _, record := range readRecords(path) {
		id, capacity := record.fields[0], integer(record.fields[1])
		if _, exists := accepted[id]; exists {
			*errors = append(*errors, fmt.Sprintf("rooms.csv line %d: duplicate room %s", record.number, id))
		} else if capacity < 1 {
			*errors = append(*errors, fmt.Sprintf("rooms.csv line %d: bad capacity %d", record.number, capacity))
		} else {
			accepted[id] = &Room{id, capacity}
		}
	}
	rooms := make([]*Room, 0, len(accepted))
	for _, room := range accepted {
		rooms = append(rooms, room)
	}
	sort.Slice(rooms, func(i, j int) bool {
		if rooms[i].capacity != rooms[j].capacity {
			return rooms[i].capacity < rooms[j].capacity
		}
		return rooms[i].id < rooms[j].id
	})
	return rooms
}
func packingOrder(courses []*Course) []*Course {
	ordered := append([]*Course(nil), courses...)
	sort.Slice(ordered, func(i, j int) bool {
		if ordered[i].size() != ordered[j].size() {
			return ordered[i].size() > ordered[j].size()
		}
		return ordered[i].id < ordered[j].id
	})
	return ordered
}
func pack(rooms []*Room, courses []*Course) ([]Placement, bool) {
	remaining, durations := make([]int, len(rooms)), make([]int, len(rooms))
	for i, room := range rooms {
		remaining[i] = room.capacity
	}
	placements := make([]Placement, 0, len(courses))
	for _, course := range packingOrder(courses) {
		placed := false
		for index, room := range rooms {
			if remaining[index] >= course.size() && (durations[index] == 0 || durations[index] == course.duration) {
				first := room.capacity - remaining[index] + 1
				placements = append(placements, Placement{course, room, first, first + course.size() - 1})
				remaining[index] -= course.size()
				durations[index] = course.duration
				placed = true
				break
			}
		}
		if !placed {
			return nil, false
		}
	}
	return placements, true
}
