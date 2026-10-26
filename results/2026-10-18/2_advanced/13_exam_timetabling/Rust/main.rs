mod enrolment;
mod conflict_graph;
mod coloring;
mod rooms;
mod report;

use std::cmp::Reverse;
use std::collections::{BTreeMap, BTreeSet};
use std::{fs, io};
use coloring::{Attempt, greedy_numbering};
use conflict_graph::{ConflictGraph, Edge, reachable};
use enrolment::{Course, StudentCourses, load_courses, load_enrolments};
use report::{fixed_width_line, rounded_percent, write_files};
use rooms::{Placement, Room, load_rooms, pack, packing_order};

type Assignment = Vec<Option<usize>>;

const RELATIONS: [&str; 3] = ["BACK_TO_BACK", "SAME_DAY", "OVERNIGHT"];

struct Calendar {
    days: usize,
    periods: usize,
    lengths: Vec<usize>,
    limit: usize,
    weights: Vec<usize>,
    front_count: usize,
    deadline: usize,
    ratio: usize,
    slot_count: usize,
    closed: BTreeSet<usize>,
    unavailable: BTreeMap<String, BTreeSet<usize>>,
    fixed: Assignment,
    orders: Vec<(usize, usize)>,
    arrows: Vec<Vec<usize>>,
}

impl Calendar {
    fn new(lines: &[String], course_count: usize) -> Self {
        let settings: Vec<Vec<usize>> = lines[..6].iter().map(|line| {
            line.split_whitespace().skip(1).map(|value| value.parse().unwrap()).collect()
        }).collect();
        let days = settings[0][0];
        let lengths = settings[1].clone();
        let periods = lengths.len();
        Self {
            days, periods, lengths, limit: settings[2][0], weights: settings[3].clone(),
            front_count: settings[4][0], deadline: settings[4][1], ratio: settings[5][0],
            slot_count: days * periods, closed: BTreeSet::new(), unavailable: BTreeMap::new(),
            fixed: vec![None; course_count], orders: Vec::new(), arrows: vec![Vec::new(); course_count],
        }
    }

    fn slots(&self) -> std::ops::RangeInclusive<usize> {
        1..=self.slot_count
    }

    fn slot_at(&self, day: &str, period: &str) -> Option<usize> {
        let day: usize = day.parse().unwrap();
        let period: usize = period.parse().unwrap();
        if (1..=self.days).contains(&day) && (1..=self.periods).contains(&period) {
            Some((day - 1) * self.periods + period)
        } else {
            None
        }
    }

    fn day_of(&self, slot: usize) -> usize {
        (slot - 1) / self.periods + 1
    }

    fn name(&self, slot: usize) -> String {
        format!("D{}P{}", self.day_of(slot), (slot - 1) % self.periods + 1)
    }

    fn length(&self, slot: usize) -> usize {
        self.lengths[(slot - 1) % self.periods]
    }

    fn relation(&self, first: usize, second: usize) -> Option<usize> {
        let low = first.min(second);
        let high = first.max(second);
        if self.day_of(low) == self.day_of(high) {
            if high - low == 1 { Some(0) }
            else if high - low >= 2 { Some(1) }
            else { None }
        } else if high - low == 1 {
            Some(2)
        } else {
            None
        }
    }
}

#[derive(Clone)]
struct Breakdown {
    counts: [usize; 3],
    late: usize,
    total: usize,
}

impl Breakdown {
    fn new(counts: [usize; 3], late: usize, weights: &[usize]) -> Self {
        let total = counts.iter().zip(weights).map(|(count, weight)| count * weight).sum::<usize>()
            + weights[3] * late;
        Self { counts, late, total }
    }

    fn text(&self) -> String {
        format!("back_to_back {} same_day {} overnight {} front_load {} penalty {}",
            self.counts[0], self.counts[1], self.counts[2], self.late, self.total)
    }
}

struct AttemptRecord {
    courses: usize,
    dead_ends: usize,
    failed: Option<usize>,
}

struct Choice {
    course: usize,
    slot: usize,
    saturation: usize,
}

struct Insertion {
    course: usize,
    slot: usize,
    increase: usize,
}

struct StudentPair {
    relation: usize,
    low_slot: usize,
    low_course: usize,
    high_slot: usize,
    high_course: usize,
}

enum Judgement {
    Fixed,
    Invalid,
    Rooms,
    Worse,
    Applied(Assignment, usize),
}

struct Scheduler {
    courses: Vec<Course>,
    student_courses: StudentCourses,
    rooms: Vec<Room>,
    calendar: Calendar,
    errors: Vec<String>,
    largest_room: usize,
    empty: Vec<usize>,
    oversized: Vec<usize>,
    schedulable: Vec<usize>,
    graph: ConflictGraph,
    edges: Vec<Edge>,
    front_load: Vec<usize>,
    open_slots: Vec<usize>,
    fixed_slots: BTreeSet<usize>,
    assignment: Assignment,
    penalty: usize,
    attempts: Vec<AttemptRecord>,
    assignment_order: Vec<Choice>,
    excluded: Vec<usize>,
    insertions: Vec<Insertion>,
    reasons: BTreeMap<usize, Vec<String>>,
    initial: Option<Breakdown>,
    exchanged: Option<Breakdown>,
    exchange_log: Vec<String>,
    swap_log: Vec<String>,
    placements: Vec<Option<Placement>>,
    slot_placements: Vec<Vec<Placement>>,
}

impl Scheduler {
    fn new(courses: Vec<Course>, student_courses: StudentCourses, rooms: Vec<Room>, calendar: Calendar, errors: Vec<String>) -> Self {
        let largest_room = rooms.iter().map(|room| room.capacity).max().unwrap();
        let empty = (0..courses.len()).filter(|&c| courses[c].size() == 0).collect();
        let oversized = (0..courses.len()).filter(|&c| courses[c].size() > largest_room).collect();
        let schedulable: Vec<_> = (0..courses.len())
            .filter(|&c| courses[c].size() > 0 && courses[c].size() <= largest_room).collect();
        let graph = ConflictGraph::new(&courses, &student_courses);
        let edges = graph.edges();
        let front_load = packing_order(&courses, &schedulable).into_iter().take(calendar.front_count).collect();
        let assignment = vec![None; courses.len()];
        let placements = vec![None; courses.len()];
        let slot_placements = vec![Vec::new(); calendar.slot_count + 1];
        Self {
            courses, student_courses, rooms, calendar, errors, largest_room, empty, oversized,
            schedulable, graph, edges, front_load, open_slots: Vec::new(), fixed_slots: BTreeSet::new(),
            assignment, penalty: 0, attempts: Vec::new(), assignment_order: Vec::new(),
            excluded: Vec::new(), insertions: Vec::new(), reasons: BTreeMap::new(), initial: None,
            exchanged: None, exchange_log: Vec::new(), swap_log: Vec::new(), placements, slot_placements,
        }
    }

    fn course_index(&self, id: &str) -> Option<usize> {
        self.courses.binary_search_by(|course| course.id.as_str().cmp(id)).ok()
    }

    fn by_size(&self, courses: &[usize]) -> Vec<usize> {
        packing_order(&self.courses, courses)
    }

    fn by_degree(&self, courses: &[usize]) -> Vec<usize> {
        let mut order = courses.to_vec();
        order.sort_by_key(|&course| (Reverse(self.graph.degree(course)), course));
        order
    }

    fn blocked_students(&self, course: usize, slot: usize) -> Vec<&str> {
        self.courses[course].students.iter().filter(|student| {
            self.calendar.unavailable.get(student.as_str()).is_some_and(|slots| slots.contains(&slot))
        }).map(String::as_str).collect()
    }

    fn suitable(&self, course: usize, slot: usize) -> bool {
        self.calendar.length(slot) >= self.courses[course].duration
            && self.blocked_students(course, slot).is_empty()
    }

    fn packs(&self, courses: &[usize]) -> bool {
        pack(&self.rooms, &self.courses, courses).is_some()
    }

    fn outside(day: &str, period: &str) -> String {
        format!("slot {day} {period} outside calendar")
    }

    fn validate_calendar(&mut self, lines: &[String]) {
        for (index, line) in lines.iter().enumerate().skip(6) {
            let fields: Vec<_> = line.split_whitespace().collect();
            let message = match fields[0] {
                "closed" => self.accept_closed(&fields[1..]),
                "unavailable" => self.accept_unavailable(&fields[1..]),
                "fixed" => self.accept_fixed(&fields[1..]),
                "after" => self.accept_after(&fields[1..]),
                _ => unreachable!(),
            };
            if let Some(message) = message {
                self.errors.push(format!("calendar.txt line {}: {message}", index + 1));
            }
        }
        self.open_slots = self.calendar.slots().filter(|s| !self.calendar.closed.contains(s)).collect();
        self.fixed_slots = self.calendar.fixed.iter().flatten().copied().collect();
    }

    fn accept_closed(&mut self, fields: &[&str]) -> Option<String> {
        let Some(slot) = self.calendar.slot_at(fields[0], fields[1]) else {
            return Some(Self::outside(fields[0], fields[1]));
        };
        if !self.calendar.closed.insert(slot) {
            return Some(format!("duplicate closed {}", self.calendar.name(slot)));
        }
        None
    }

    fn accept_unavailable(&mut self, fields: &[&str]) -> Option<String> {
        let student = fields[0];
        if !self.student_courses.contains_key(student) {
            return Some(format!("unknown student {student}"));
        }
        let Some(slot) = self.calendar.slot_at(fields[1], fields[2]) else {
            return Some(Self::outside(fields[1], fields[2]));
        };
        if !self.calendar.unavailable.entry(student.to_owned()).or_default().insert(slot) {
            return Some(format!("duplicate unavailable {student} {}", self.calendar.name(slot)));
        }
        None
    }

    fn accept_fixed(&mut self, fields: &[&str]) -> Option<String> {
        let id = fields[0];
        let Some(course) = self.course_index(id) else { return Some(format!("unknown course {id}")); };
        if !self.schedulable.contains(&course) {
            return Some(format!("course {id} not schedulable"));
        }
        let Some(slot) = self.calendar.slot_at(fields[1], fields[2]) else {
            return Some(Self::outside(fields[1], fields[2]));
        };
        let name = self.calendar.name(slot);
        if self.calendar.closed.contains(&slot) {
            return Some(format!("slot {name} closed"));
        }
        if !self.suitable(course, slot) {
            return Some(format!("slot {name} unsuitable for {id}"));
        }
        if self.calendar.fixed[course].is_some() {
            return Some(format!("duplicate fixed {id}"));
        }
        let mut group = self.courses_at(&self.calendar.fixed, slot);
        if let Some(&other) = group.iter().find(|&&other| self.graph.neighbours(course).contains_key(&other)) {
            return Some(format!("conflict {id} {}", self.courses[other].id));
        }
        group.push(course);
        if !self.packs(&group) {
            return Some(format!("rooms full {name}"));
        }
        self.calendar.fixed[course] = Some(slot);
        None
    }

    fn accept_after(&mut self, fields: &[&str]) -> Option<String> {
        for &id in fields {
            if self.course_index(id).is_none() {
                return Some(format!("unknown course {id}"));
            }
        }
        let later = self.course_index(fields[0]).unwrap();
        let earlier = self.course_index(fields[1]).unwrap();
        for course in [later, earlier] {
            if !self.schedulable.contains(&course) {
                return Some(format!("course {} not schedulable", self.courses[course].id));
            }
        }
        let pair = format!("{} {}", fields[0], fields[1]);
        if later == earlier { return Some(format!("bad order {pair}")); }
        if self.calendar.orders.contains(&(later, earlier)) { return Some(format!("duplicate order {pair}")); }
        if reachable(&self.calendar.arrows, earlier, later) { return Some(format!("cycle {pair}")); }
        if let (Some(a), Some(b)) = (self.calendar.fixed[later], self.calendar.fixed[earlier]) {
            if a <= b { return Some(format!("fixed order {pair}")); }
        }
        self.calendar.orders.push((later, earlier));
        self.calendar.arrows[later].push(earlier);
        None
    }

    fn courses_at(&self, assignment: &[Option<usize>], slot: usize) -> Vec<usize> {
        assignment.iter().enumerate().filter_map(|(course, &assigned)| (assigned == Some(slot)).then_some(course)).collect()
    }

    fn order_conflicts(&self, course: usize, slot: usize, assignment: &[Option<usize>]) -> Vec<usize> {
        let mut conflicts = Vec::new();
        for &(later, earlier) in &self.calendar.orders {
            if later == course && assignment[earlier].is_some_and(|s| slot <= s) {
                conflicts.push(earlier);
            } else if earlier == course && assignment[later].is_some_and(|s| slot >= s) {
                conflicts.push(later);
            }
        }
        conflicts
    }

    fn orders_satisfied(&self, assignment: &[Option<usize>]) -> bool {
        self.calendar.orders.iter().all(|&(later, earlier)| {
            match (assignment[later], assignment[earlier]) {
                (Some(a), Some(b)) => a > b,
                _ => true,
            }
        })
    }

    fn candidate_slots(&self, course: usize, assignment: &[Option<usize>]) -> Vec<usize> {
        self.open_slots.iter().copied().filter(|&slot| {
            if !self.suitable(course, slot) { return false; }
            if self.graph.neighbours(course).keys().any(|&other| assignment[other] == Some(slot)) { return false; }
            if !self.order_conflicts(course, slot, assignment).is_empty() { return false; }
            let mut group = self.courses_at(assignment, slot);
            group.push(course);
            self.packs(&group)
        }).collect()
    }

    fn build_timetable(&mut self) {
        loop {
            let pending: Vec<_> = self.schedulable.iter().copied().filter(|&c| {
                self.calendar.fixed[c].is_none() && !self.excluded.contains(&c)
            }).collect();
            let mut assignment = self.calendar.fixed.clone();
            let (success, dead_ends, failed, chosen) = {
                let mut attempt = Attempt::new(pending.clone(), &self.graph, self.calendar.limit,
                    |course, current: &[Option<usize>]| self.candidate_slots(course, current));
                let success = attempt.search(&mut assignment);
                (success, attempt.dead_ends, attempt.dead_end_course, attempt.chosen)
            };
            self.attempts.push(AttemptRecord { courses: pending.len(), dead_ends, failed: if success { None } else { failed } });
            if success {
                self.assignment_order = chosen.into_iter().map(|(course, saturation)| {
                    Choice { course, slot: assignment[course].unwrap(), saturation }
                }).collect();
                self.assignment = assignment;
                break;
            }
            self.excluded.push(failed.unwrap());
        }
    }

    fn penalty_pairs(&self, assignment: &[Option<usize>]) -> Vec<(usize, usize, usize, usize)> {
        self.edges.iter().filter_map(|edge| {
            let first = assignment[edge.first]?;
            let second = assignment[edge.second]?;
            let relation = self.calendar.relation(first, second)?;
            Some((edge.first, edge.second, relation, edge.shared))
        }).collect()
    }

    fn late_courses(&self, assignment: &[Option<usize>]) -> Vec<usize> {
        self.front_load.iter().copied().filter(|&course| {
            assignment[course].is_some_and(|slot| slot > self.calendar.deadline)
        }).collect()
    }

    fn breakdown(&self, assignment: &[Option<usize>]) -> Breakdown {
        let mut counts = [0; 3];
        for (_, _, relation, shared) in self.penalty_pairs(assignment) {
            counts[relation] += shared;
        }
        Breakdown::new(counts, self.late_courses(assignment).len(), &self.calendar.weights)
    }

    fn contributions(&self) -> Vec<usize> {
        let mut result = vec![0; self.courses.len()];
        for (first, second, relation, shared) in self.penalty_pairs(&self.assignment) {
            let value = self.calendar.weights[relation] * shared;
            result[first] += value;
            result[second] += value;
        }
        for course in self.late_courses(&self.assignment) {
            result[course] += self.calendar.weights[3];
        }
        result
    }

    fn blocking_reason(&self, course: usize, slot: usize) -> String {
        if self.calendar.closed.contains(&slot) { return "closed".to_owned(); }
        if self.calendar.length(slot) < self.courses[course].duration { return "too_short".to_owned(); }
        if let Some(student) = self.blocked_students(course, slot).first() {
            return format!("unavailable {student}");
        }
        let clash = self.graph.neighbours(course).iter()
            .filter(|(other, _)| self.assignment[**other] == Some(slot))
            .min_by_key(|(other, shared)| (Reverse(**shared), **other));
        if let Some((&other, &shared)) = clash {
            return format!("conflict {} shared {shared}", self.courses[other].id);
        }
        if let Some(other) = self.order_conflicts(course, slot, &self.assignment).into_iter().min() {
            return format!("order {}", self.courses[other].id);
        }
        "rooms".to_owned()
    }

    fn insert_excluded(&mut self) {
        let mut excluded = self.excluded.clone();
        excluded.sort_unstable();
        for course in excluded {
            let slots = self.candidate_slots(course, &self.assignment);
            if slots.is_empty() {
                let reasons = self.calendar.slots().map(|slot| self.blocking_reason(course, slot)).collect();
                self.reasons.insert(course, reasons);
                continue;
            }
            let before = self.breakdown(&self.assignment).total;
            let (total, slot) = slots.into_iter().map(|slot| {
                let mut trial = self.assignment.clone();
                trial[course] = Some(slot);
                (self.breakdown(&trial).total, slot)
            }).min().unwrap();
            self.assignment[course] = Some(slot);
            self.insertions.push(Insertion { course, slot, increase: total - before });
        }
        let initial = self.breakdown(&self.assignment);
        self.penalty = initial.total;
        self.initial = Some(initial);
    }

    fn unscheduled(&self) -> Vec<usize> {
        let mut result = self.oversized.clone();
        result.extend(self.excluded.iter().copied().filter(|&c| self.assignment[c].is_none()));
        result.sort_unstable();
        result
    }

    fn valid_trial(&self, trial: &[Option<usize>], moved: &[usize]) -> bool {
        moved.iter().all(|&course| self.suitable(course, trial[course].unwrap())) && self.orders_satisfied(trial)
    }

    fn moved_courses(&self, trial: &[Option<usize>]) -> Vec<usize> {
        (0..trial.len()).filter(|&course| trial[course] != self.assignment[course]).collect()
    }

    fn exchange_trial(&self, first: usize, second: usize) -> Judgement {
        if self.fixed_slots.contains(&first) || self.fixed_slots.contains(&second) { return Judgement::Fixed; }
        let mut trial = self.assignment.clone();
        for slot in &mut trial {
            if *slot == Some(first) { *slot = Some(second); }
            else if *slot == Some(second) { *slot = Some(first); }
        }
        if !self.valid_trial(&trial, &self.moved_courses(&trial)) { return Judgement::Invalid; }
        let total = self.breakdown(&trial).total;
        if total >= self.penalty { return Judgement::Worse; }
        Judgement::Applied(trial, total)
    }

    fn exchange_slots(&mut self) {
        let mut round = 0;
        let mut serial = 0;
        loop {
            round += 1;
            let mut tally = [0; 4];
            let mut pairs = 0;
            let mut records = Vec::new();
            for (index, &first) in self.open_slots.iter().enumerate() {
                for &second in &self.open_slots[index + 1..] {
                    pairs += 1;
                    match self.exchange_trial(first, second) {
                        Judgement::Fixed => tally[0] += 1,
                        Judgement::Invalid => tally[1] += 1,
                        Judgement::Worse => tally[2] += 1,
                        Judgement::Rooms => unreachable!(),
                        Judgement::Applied(trial, total) => {
                            tally[3] += 1;
                            serial += 1;
                            records.push(format!("EXCHANGE {serial} {} {} penalty {} -> {total}",
                                self.calendar.name(first), self.calendar.name(second), self.penalty));
                            self.assignment = trial;
                            self.penalty = total;
                        }
                    }
                }
            }
            self.exchange_log.push(format!("ROUND {round} pairs {pairs} fixed {} invalid {} worse {} applied {}",
                tally[0], tally[1], tally[2], tally[3]));
            self.exchange_log.extend(records);
            if tally[3] == 0 { break; }
        }
        self.exchanged = Some(self.breakdown(&self.assignment));
    }

    fn swap_trial(&self, course: usize, home: usize, target: usize) -> Judgement {
        let chain = self.graph.kempe_chain(&self.assignment, course, home, target);
        if chain.iter().any(|&member| self.calendar.fixed[member].is_some()) { return Judgement::Fixed; }
        let mut trial = self.assignment.clone();
        for &member in &chain {
            trial[member] = Some(if self.assignment[member] == Some(home) { target } else { home });
        }
        if !self.valid_trial(&trial, &chain) { return Judgement::Invalid; }
        if !self.packs(&self.courses_at(&trial, home)) || !self.packs(&self.courses_at(&trial, target)) {
            return Judgement::Rooms;
        }
        let total = self.breakdown(&trial).total;
        if total >= self.penalty { return Judgement::Worse; }
        Judgement::Applied(trial, total)
    }

    fn swap_chains(&mut self) {
        let mut pass = 0;
        let mut serial = 0;
        loop {
            pass += 1;
            let mut tally = [0; 5];
            let mut candidates = 0;
            let mut records = Vec::new();
            let movable: Vec<_> = (0..self.courses.len()).filter(|&c| {
                self.assignment[c].is_some() && self.calendar.fixed[c].is_none()
            }).collect();
            for course in movable {
                let home = self.assignment[course].unwrap();
                for &target in &self.open_slots {
                    if home == target { continue; }
                    candidates += 1;
                    match self.swap_trial(course, home, target) {
                        Judgement::Fixed => tally[0] += 1,
                        Judgement::Invalid => tally[1] += 1,
                        Judgement::Rooms => tally[2] += 1,
                        Judgement::Worse => tally[3] += 1,
                        Judgement::Applied(trial, total) => {
                            tally[4] += 1;
                            serial += 1;
                            let chain = self.moved_courses(&trial);
                            records.push(format!("SWAP {serial} {} {} {} chain {} penalty {} -> {total}",
                                self.courses[course].id, self.calendar.name(home), self.calendar.name(target), chain.len(), self.penalty));
                            for member in chain {
                                records.push(format!("  MOVE {} {} -> {}", self.courses[member].id,
                                    self.calendar.name(self.assignment[member].unwrap()), self.calendar.name(trial[member].unwrap())));
                            }
                            self.assignment = trial;
                            self.penalty = total;
                            break;
                        }
                    }
                }
            }
            self.swap_log.push(format!("PASS {pass} candidates {candidates} fixed {} invalid {} rooms {} worse {} applied {}",
                tally[0], tally[1], tally[2], tally[3], tally[4]));
            self.swap_log.extend(records);
            if tally[4] == 0 { break; }
        }
    }

    fn assign_rooms(&mut self) {
        for &slot in &self.open_slots {
            let placed = pack(&self.rooms, &self.courses, &self.courses_at(&self.assignment, slot)).unwrap();
            for placement in &placed {
                self.placements[placement.course] = Some(placement.clone());
            }
            self.slot_placements[slot] = placed;
        }
    }

    fn room_groups(&self, slot: usize) -> Vec<(usize, Vec<&Placement>)> {
        (0..self.rooms.len()).filter_map(|room| {
            let placed: Vec<_> = self.slot_placements[slot].iter().filter(|p| p.room == room).collect();
            (!placed.is_empty()).then_some((room, placed))
        }).collect()
    }

    fn invigilators(&self, slot: usize) -> usize {
        self.room_groups(slot).iter().map(|(_, placed)| {
            let seated: usize = placed.iter().map(|p| self.courses[p.course].size()).sum();
            seated.div_ceil(self.calendar.ratio)
        }).sum()
    }

    fn slot_load(&self, slot: usize) -> (usize, usize) {
        let courses = self.courses_at(&self.assignment, slot);
        (courses.len(), courses.iter().map(|&c| self.courses[c].size()).sum())
    }

    fn student_pairs(&self, student: &str) -> Vec<StudentPair> {
        let mut assigned: Vec<_> = self.student_courses[student].iter()
            .filter_map(|&course| self.assignment[course].map(|slot| (slot, course))).collect();
        assigned.sort_unstable();
        let mut pairs = Vec::new();
        for (index, &(low_slot, low_course)) in assigned.iter().enumerate() {
            for &(high_slot, high_course) in &assigned[index + 1..] {
                if let Some(relation) = self.calendar.relation(low_slot, high_slot) {
                    pairs.push(StudentPair { relation, low_slot, low_course, high_slot, high_course });
                }
            }
        }
        pairs
    }

    fn student_penalty(&self, student: &str) -> ([usize; 3], usize) {
        let mut counts = [0; 3];
        for pair in self.student_pairs(student) {
            counts[pair.relation] += 1;
        }
        let total = counts.iter().zip(&self.calendar.weights).map(|(count, weight)| count * weight).sum();
        (counts, total)
    }

    fn assigned_slots(&self, student: &str) -> Vec<usize> {
        let mut slots: Vec<_> = self.student_courses[student].iter().filter_map(|&c| self.assignment[c]).collect();
        slots.sort_unstable();
        slots
    }

    fn timetable_lines(&self) -> Vec<String> {
        let calendar = &self.calendar;
        let mut lines = vec![format!("TIMETABLE days {} periods {} open {} courses {} scheduled {} unscheduled {} empty {}",
            calendar.days, calendar.periods, self.open_slots.len(), self.courses.len(),
            self.assigned_count(), self.unscheduled().len(), self.empty.len())];
        let mut header: Vec<_> = (1..=calendar.periods).map(|p| format!("P{p}")).collect();
        header.push("TOTAL".to_owned());
        lines.push(fixed_width_line("DAY", &header, 4, 10));
        for day in 1..=calendar.days {
            let mut cells = Vec::new();
            let mut day_exams = 0;
            let mut day_students = 0;
            for period in 1..=calendar.periods {
                let slot = (day - 1) * calendar.periods + period;
                if calendar.closed.contains(&slot) {
                    cells.push("closed".to_owned());
                } else {
                    let (exams, students) = self.slot_load(slot);
                    cells.push(format!("{exams}/{students}"));
                    day_exams += exams;
                    day_students += students;
                }
            }
            cells.push(format!("{day_exams}/{day_students}"));
            lines.push(fixed_width_line(&format!("D{day}"), &cells, 4, 10));
        }
        for slot in calendar.slots() {
            let prefix = format!("SLOT {slot} {} minutes {}", calendar.name(slot), calendar.length(slot));
            if calendar.closed.contains(&slot) {
                lines.push(prefix + " closed");
                continue;
            }
            let (exams, students) = self.slot_load(slot);
            let groups = self.room_groups(slot);
            let seats: usize = groups.iter().map(|(room, _)| self.rooms[*room].capacity).sum();
            lines.push(format!("{prefix} exams {exams} students {students} rooms {} seats {seats} invigilators {}",
                groups.len(), self.invigilators(slot)));
            for placement in &self.slot_placements[slot] {
                let course = &self.courses[placement.course];
                let marker = if calendar.fixed[placement.course].is_some() { " fixed" } else { "" };
                lines.push(format!("  {} {}min students {} room {} seats {}-{}{marker} {}",
                    course.id, course.duration, course.size(), self.rooms[placement.room].id,
                    placement.first_seat, placement.last_seat, course.name));
            }
        }
        for (room_index, room) in self.rooms.iter().enumerate() {
            let mut slots_used = 0;
            let mut exams = 0;
            let mut seated = 0;
            for &slot in &self.open_slots {
                let placed: Vec<_> = self.slot_placements[slot].iter().filter(|p| p.room == room_index).collect();
                if !placed.is_empty() {
                    slots_used += 1;
                    exams += placed.len();
                    seated += placed.iter().map(|p| self.courses[p.course].size()).sum::<usize>();
                }
            }
            let utilization = rounded_percent(seated, room.capacity * self.open_slots.len());
            lines.push(format!("ROOM {} capacity {} slots {slots_used} exams {exams} seated {seated} utilization {utilization}",
                room.id, room.capacity));
        }
        let total: usize = self.open_slots.iter().map(|&slot| self.invigilators(slot)).sum();
        lines.push(format!("INVIGILATORS total {total} ratio {}", calendar.ratio));
        lines
    }

    fn room_lines(&self) -> Vec<String> {
        let mut lines = vec!["slot,room,course,students,first_seat,last_seat".to_owned()];
        for &slot in &self.open_slots {
            for (room, placed) in self.room_groups(slot) {
                for p in placed {
                    lines.push(format!("{},{},{},{},{},{}", self.calendar.name(slot), self.rooms[room].id,
                        self.courses[p.course].id, self.courses[p.course].size(), p.first_seat, p.last_seat));
                }
            }
        }
        lines
    }

    fn penalty_lines(&self) -> Vec<String> {
        let calendar = &self.calendar;
        let weights = &calendar.weights;
        let final_penalty = self.breakdown(&self.assignment);
        let initial = self.initial.as_ref().unwrap();
        let mut lines = vec![
            format!("WEIGHTS back_to_back {} same_day {} overnight {} front_load {}", weights[0], weights[1], weights[2], weights[3]),
            format!("FRONT_LOAD courses {} last_slot {}", self.front_load.len(), calendar.name(calendar.deadline)),
            format!("INITIAL {}", initial.text()),
        ];
        lines.extend(self.exchange_log.iter().cloned());
        lines.push(format!("EXCHANGED {}", self.exchanged.as_ref().unwrap().text()));
        lines.extend(self.swap_log.iter().cloned());
        lines.push(format!("FINAL {}", final_penalty.text()));
        lines.push(format!("SAVED {}", initial.total - final_penalty.total));
        let mut daily = vec![[0; 3]; calendar.days + 1];
        for (first, second, relation, shared) in self.penalty_pairs(&self.assignment) {
            let day = calendar.day_of(self.assignment[first].unwrap().min(self.assignment[second].unwrap()));
            daily[day][relation] += shared;
        }
        for (day, counts) in daily.iter().enumerate().skip(1) {
            lines.push(format!("DAY D{day} back_to_back {} same_day {} overnight {}", counts[0], counts[1], counts[2]));
        }
        for course in self.late_courses(&self.assignment) {
            lines.push(format!("LATE {} {} students {}", self.courses[course].id,
                calendar.name(self.assignment[course].unwrap()), self.courses[course].size()));
        }
        let contributions = self.contributions();
        let mut ranked: Vec<_> = (0..self.courses.len()).filter(|&c| self.assignment[c].is_some()).collect();
        ranked.sort_by_key(|&c| (Reverse(contributions[c]), c));
        for course in ranked.into_iter().take(10) {
            if contributions[course] > 0 {
                lines.push(format!("COURSE {} {} penalty {}", self.courses[course].id,
                    calendar.name(self.assignment[course].unwrap()), contributions[course]));
            }
        }
        lines.extend(self.student_statistics());
        lines
    }

    fn student_statistics(&self) -> Vec<String> {
        let mut histogram = BTreeMap::new();
        let mut gaps = BTreeMap::new();
        let mut day_loads = BTreeMap::new();
        let mut ranking = Vec::new();
        for student in self.student_courses.keys() {
            let (counts, penalty) = self.student_penalty(student);
            *histogram.entry(penalty).or_insert(0usize) += 1;
            ranking.push((Reverse(penalty), student.as_str(), counts));
            let slots = self.assigned_slots(student);
            for pair in slots.windows(2) {
                *gaps.entry(pair[1] - pair[0]).or_insert(0usize) += 1;
            }
            if !slots.is_empty() {
                let mut per_day = BTreeMap::new();
                for slot in slots {
                    *per_day.entry(self.calendar.day_of(slot)).or_insert(0usize) += 1;
                }
                *day_loads.entry(*per_day.values().max().unwrap()).or_insert(0usize) += 1;
            }
        }
        let mut lines: Vec<_> = histogram.iter().map(|(value, count)| format!("HISTOGRAM {value} {count}")).collect();
        lines.extend(gaps.iter().map(|(gap, count)| format!("GAP {gap} {count}")));
        lines.extend(day_loads.iter().map(|(load, count)| format!("DAYLOAD {load} {count}")));
        ranking.sort_unstable();
        for (Reverse(penalty), student, counts) in ranking.into_iter().take(5) {
            if penalty > 0 {
                lines.push(format!("WORST {student} penalty {penalty} back_to_back {} same_day {} overnight {}",
                    counts[0], counts[1], counts[2]));
            }
        }
        lines
    }

    fn schedule_lines(&self, queries: &[String]) -> Vec<String> {
        let mut lines = Vec::new();
        for student in queries {
            let Some(courses) = self.student_courses.get(student) else {
                lines.push(format!("STUDENT {student} not found"));
                continue;
            };
            let mut assigned: Vec<_> = courses.iter().filter_map(|&course| self.assignment[course].map(|slot| (slot, course))).collect();
            assigned.sort_unstable();
            let (_, penalty) = self.student_penalty(student);
            lines.push(format!("STUDENT {student} exams {} scheduled {} penalty {penalty}", courses.len(), assigned.len()));
            for (slot, index) in assigned {
                let placement = self.placements[index].as_ref().unwrap();
                let course = &self.courses[index];
                let seat = placement.first_seat + course.students.binary_search(student).unwrap();
                lines.push(format!("  {} {} room {} seat {seat} {}", self.calendar.name(slot), course.id, self.rooms[placement.room].id, course.name));
            }
            for &course in courses {
                if self.assignment[course].is_none() {
                    lines.push(format!("  UNSCHEDULED {} {}", self.courses[course].id, self.courses[course].name));
                }
            }
            for pair in self.student_pairs(student) {
                lines.push(format!("  {} {} {} {} {}", RELATIONS[pair.relation], self.calendar.name(pair.low_slot),
                    self.courses[pair.low_course].id, self.calendar.name(pair.high_slot), self.courses[pair.high_course].id));
            }
            if let Some(slots) = self.calendar.unavailable.get(student) {
                for &slot in slots {
                    lines.push(format!("  UNAVAILABLE {}", self.calendar.name(slot)));
                }
            }
        }
        lines
    }

    fn status_lines(&self) -> Vec<String> {
        let contributions = self.contributions();
        let mut lines = vec!["course,status,slot,students,minutes,degree,penalty".to_owned()];
        for (index, course) in self.courses.iter().enumerate() {
            let status = if self.calendar.fixed[index].is_some() { "fixed" }
                else if self.assignment[index].is_some() { "scheduled" }
                else if self.oversized.contains(&index) { "too_large" }
                else if self.empty.contains(&index) { "empty" }
                else { "no_slot" };
            let slot = self.assignment[index].map(|s| self.calendar.name(s)).unwrap_or_else(|| "-".to_owned());
            lines.push(format!("{},{status},{slot},{},{},{},{}", course.id, course.size(), course.duration,
                self.graph.degree(index), contributions[index]));
        }
        lines
    }

    fn graph_lines(&self) -> Vec<String> {
        let vertices = self.graph.vertices.len();
        let edges = self.edges.len();
        let shared: usize = self.edges.iter().map(|edge| edge.shared).sum();
        let density = if vertices >= 2 { 2000 * edges / (vertices * (vertices - 1)) } else { 0 };
        let mut lines = vec![format!("GRAPH courses {vertices} edges {edges} shared {shared} density {density}")];
        for course in self.by_degree(&self.graph.vertices).into_iter().take(5) {
            lines.push(format!("DEGREE {} neighbours {} shared {} students {}", self.courses[course].id,
                self.graph.degree(course), self.graph.shared_total(course), self.courses[course].size()));
        }
        let components = self.graph.components();
        lines.push(format!("COMPONENTS {}", components.len()));
        for (index, component) in components.iter().enumerate() {
            lines.push(format!("COMPONENT {} size {} first {}", index + 1, component.len(), self.courses[component[0]].id));
        }
        let clique = self.graph.greedy_clique(&self.schedulable);
        let mut fields = vec!["CLIQUE".to_owned(), "size".to_owned(), clique.len().to_string()];
        fields.extend(clique.iter().map(|&course| self.courses[course].id.clone()));
        lines.push(fields.join(" "));
        lines
    }

    fn capacity_lines(&self) -> Vec<String> {
        let loads: Vec<_> = self.student_courses.values().map(Vec::len).collect();
        let most = *loads.iter().max().unwrap();
        let demand: usize = self.schedulable.iter().map(|&c| self.courses[c].size()).sum();
        let capacity: usize = self.rooms.iter().map(|room| room.capacity).sum();
        let degree_slots = greedy_numbering(&self.by_degree(&self.schedulable), &self.graph, self.courses.len());
        let size_slots = greedy_numbering(&self.by_size(&self.schedulable), &self.graph, self.courses.len());
        let mut lines = vec![
            format!("LOAD max_exams {most} students {}", loads.iter().filter(|&&load| load == most).count()),
            format!("SEATS demand {demand} capacity {capacity} min_slots {}", demand.div_ceil(capacity)),
            format!("HEURISTIC largest_degree slots {degree_slots}"),
            format!("HEURISTIC largest_enrolment slots {size_slots}"),
        ];
        let table: Vec<_> = self.by_size(&self.graph.vertices).into_iter().take(8).collect();
        let ids: Vec<_> = table.iter().map(|&course| self.courses[course].id.clone()).collect();
        lines.push(fixed_width_line("MATRIX", &ids, 9, 9));
        for &row in &table {
            let cells: Vec<_> = table.iter().map(|&column| {
                if row == column { "-".to_owned() }
                else { self.graph.neighbours(row).get(&column).copied().unwrap_or(0).to_string() }
            }).collect();
            lines.push(fixed_width_line(&self.courses[row].id, &cells, 9, 9));
        }
        lines
    }

    fn assigned_count(&self) -> usize {
        self.assignment.iter().flatten().count()
    }

    fn report_lines(&self) -> Vec<String> {
        let calendar = &self.calendar;
        let enrolments: usize = self.student_courses.values().map(Vec::len).sum();
        let mut lines = vec![format!("INPUT courses {} enrolments {enrolments} rooms {} students {} errors {}",
            self.courses.len(), self.rooms.len(), self.student_courses.len(), self.errors.len())];
        lines.extend(self.errors.iter().map(|error| format!("ERROR {error}")));
        lines.extend(self.graph_lines());
        lines.extend(self.capacity_lines());
        for &course in &self.empty { lines.push(format!("EMPTY {}", self.courses[course].id)); }
        for &course in &self.oversized {
            lines.push(format!("TOO_LARGE {} students {} largest_room {}", self.courses[course].id, self.courses[course].size(), self.largest_room));
        }
        for &slot in &calendar.closed { lines.push(format!("CLOSED {}", calendar.name(slot))); }
        for (course, &slot) in calendar.fixed.iter().enumerate() {
            if let Some(slot) = slot { lines.push(format!("FIXED {} {}", self.courses[course].id, calendar.name(slot))); }
        }
        for &(later, earlier) in &calendar.orders {
            lines.push(format!("AFTER {} {}", self.courses[later].id, self.courses[earlier].id));
        }
        for (index, attempt) in self.attempts.iter().enumerate() {
            let result = attempt.failed.map(|c| format!("failed {}", self.courses[c].id)).unwrap_or_else(|| "success".to_owned());
            lines.push(format!("ATTEMPT {} courses {} backtracks {} {result}", index + 1, attempt.courses, attempt.dead_ends));
        }
        for (index, choice) in self.assignment_order.iter().enumerate() {
            lines.push(format!("ORDER {} {} {} saturation {} degree {}", index + 1, self.courses[choice.course].id,
                calendar.name(choice.slot), choice.saturation, self.graph.degree(choice.course)));
        }
        for insertion in &self.insertions {
            lines.push(format!("INSERTED {} {} penalty {}", self.courses[insertion.course].id, calendar.name(insertion.slot), insertion.increase));
        }
        let unscheduled = self.unscheduled();
        for &course in &unscheduled {
            let reason = if self.oversized.contains(&course) { "too_large" } else { "no_slot" };
            lines.push(format!("UNSCHEDULED {} reason {reason} students {}", self.courses[course].id, self.courses[course].size()));
            if let Some(reasons) = self.reasons.get(&course) {
                for (index, reason) in reasons.iter().enumerate() {
                    lines.push(format!("  {} {reason}", calendar.name(index + 1)));
                }
            }
        }
        let slots_used = self.assignment.iter().flatten().copied().collect::<BTreeSet<_>>().len();
        lines.push(format!("SUMMARY scheduled {} unscheduled {} slots_used {slots_used} penalty {}", self.assigned_count(), unscheduled.len(), self.penalty));
        lines
    }
}

fn read_lines(name: &str) -> io::Result<Vec<String>> {
    Ok(fs::read_to_string(format!("input/{name}"))?.lines().map(str::to_owned).collect())
}

fn main() -> io::Result<()> {
    let mut errors = Vec::new();
    let mut courses = load_courses("input/courses.csv", &mut errors)?;
    let students = load_enrolments("input/enrolments.csv", &mut courses, &mut errors)?;
    let rooms = load_rooms("input/rooms.csv", &mut errors)?;
    let calendar_lines = read_lines("calendar.txt")?;
    let calendar = Calendar::new(&calendar_lines, courses.len());
    let mut scheduler = Scheduler::new(courses, students, rooms, calendar, errors);
    scheduler.validate_calendar(&calendar_lines);
    scheduler.build_timetable();
    scheduler.insert_excluded();
    scheduler.exchange_slots();
    scheduler.swap_chains();
    scheduler.assign_rooms();
    let queries = read_lines("queries.txt")?;
    write_files("output", vec![
        ("timetable.txt", scheduler.timetable_lines()),
        ("rooms.csv", scheduler.room_lines()),
        ("penalties.txt", scheduler.penalty_lines()),
        ("student_schedules.txt", scheduler.schedule_lines(&queries)),
        ("course_status.csv", scheduler.status_lines()),
        ("report.txt", scheduler.report_lines()),
    ])
}
