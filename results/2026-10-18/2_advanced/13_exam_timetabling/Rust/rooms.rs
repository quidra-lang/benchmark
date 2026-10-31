use std::collections::BTreeMap;
use std::io;
use crate::enrolment::{read_records, Course};

pub struct Room {
    pub id: String,
    pub capacity: usize,
}

#[derive(Clone)]
pub struct Placement {
    pub course: usize,
    pub room: usize,
    pub first_seat: usize,
    pub last_seat: usize,
}

pub fn load_rooms(path: &str, errors: &mut Vec<String>) -> io::Result<Vec<Room>> {
    let mut accepted = BTreeMap::new();
    for (number, fields) in read_records(path)? {
        let id = &fields[0];
        let capacity: usize = fields[1].parse().unwrap();
        if accepted.contains_key(id) {
            errors.push(format!("rooms.csv line {number}: duplicate room {id}"));
        } else if capacity < 1 {
            errors.push(format!("rooms.csv line {number}: bad capacity {capacity}"));
        } else {
            accepted.insert(id.clone(), Room { id: id.clone(), capacity });
        }
    }
    let mut rooms: Vec<Room> = accepted.into_values().collect();
    rooms.sort_by(|a, b| a.capacity.cmp(&b.capacity).then_with(|| a.id.cmp(&b.id)));
    Ok(rooms)
}

pub fn packing_order(courses: &[Course], group: &[usize]) -> Vec<usize> {
    let mut order = group.to_vec();
    order.sort_by_key(|&course| (std::cmp::Reverse(courses[course].size()), course));
    order
}

pub fn pack(rooms: &[Room], courses: &[Course], group: &[usize]) -> Option<Vec<Placement>> {
    let mut remaining: Vec<_> = rooms.iter().map(|room| room.capacity).collect();
    let mut durations = vec![None; rooms.len()];
    let mut placements = Vec::new();
    for index in packing_order(courses, group) {
        let course = &courses[index];
        let room = (0..rooms.len()).find(|&room| {
            remaining[room] >= course.size()
                && (durations[room].is_none() || durations[room] == Some(course.duration))
        })?;
        let first_seat = rooms[room].capacity - remaining[room] + 1;
        placements.push(Placement {
            course: index, room, first_seat, last_seat: first_seat + course.size() - 1,
        });
        remaining[room] -= course.size();
        durations[room] = Some(course.duration);
    }
    Some(placements)
}
