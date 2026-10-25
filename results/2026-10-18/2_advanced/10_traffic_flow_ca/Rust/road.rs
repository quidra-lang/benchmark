use crate::vehicles::Vehicle;

pub struct Turn { pub target: usize, pub weight: i64, pub vehicles: i64 }
pub struct BusStop { pub segment: usize, pub cell: usize, pub dwell: usize, pub buses: i64 }
#[derive(Clone, Copy)]
pub enum Change { Overtaking, Return, Avoidance }
pub struct Segment {
    pub id: String, pub start: String, pub end: String,
    pub length: usize, pub lanes: usize, pub limit: usize,
    pub cells: Vec<Vec<i64>>, pub junction: Option<usize>, pub turns: Vec<Turn>, pub stop: Option<usize>,
    pub entered: i64, pub vehicle_sum: i64, pub speed_sum: i64, pub max_vehicles: usize, pub green_steps: i64,
    pub queue_sum: i64, pub max_queue: usize, pub failures: i64, pub passed: i64, pub blocked: i64, pub changes: [i64; 3],
}
impl Segment {
    pub fn new(id: String, start: String, end: String, length: usize, lanes: usize, limit: usize) -> Self {
        Self { id, start, end, length, lanes, limit, cells: vec![vec![0; length]; lanes], junction: None, turns: Vec::new(), stop: None, entered: 0, vehicle_sum: 0, speed_sum: 0, max_vehicles: 0, green_steps: 0, queue_sum: 0, max_queue: 0, failures: 0, passed: 0, blocked: 0, changes: [0; 3] }
    }
    pub fn empty(&self, lane: usize, cell: usize) -> bool { self.cells[lane - 1][cell] == 0 }
    pub fn obstacle(&self, lane: usize, cell: usize) -> bool { self.cells[lane - 1][cell] == -1 }
    pub fn put(&mut self, lane: usize, cell: usize, value: i64) { self.cells[lane - 1][cell] = value; }
    pub fn clear(&mut self, lane: usize, cell: usize) { self.put(lane, cell, 0); }
    pub fn free(&self, lane: usize, cell: isize, cap: usize) -> usize {
        let mut count = 0; while count < cap && cell + count as isize + 1 < self.length as isize && self.empty(lane, (cell + count as isize + 1) as usize) { count += 1; } count
    }
    pub fn first(&self, lane: usize) -> usize { self.cells[lane - 1].iter().position(|&value| value != 0).unwrap_or(self.length) }
    pub fn safe(&self, lane: usize, cell: usize) -> bool { (cell.saturating_sub(self.limit)..=cell).all(|x| self.empty(lane, x)) }
    pub fn vehicle_numbers(&self, lane: usize) -> Vec<usize> { self.cells[lane - 1].iter().filter(|&&value| value > 0).map(|&value| value as usize - 1).collect() }
    pub fn cells_text(&self, lane: usize, vehicles: &[Vehicle]) -> String {
        self.cells[lane - 1].iter().map(|&value| match value { 0 => '.', -1 => '#', _ => (b'0' + vehicles[value as usize - 1].speed as u8) as char }).collect()
    }
}
pub struct Incident {
    pub segment: usize, pub lane: usize, pub cell: usize, pub start: usize, pub end: usize,
    pub state: &'static str, pub active_start: Option<usize>, pub active_end: Option<usize>,
}
impl Incident {
    pub fn update(&mut self, segments: &mut [Segment], step: usize) -> Option<&'static str> {
        let segment = &mut segments[self.segment]; let mut event = None;
        if self.state == "active" && step > self.end { self.state = "cleared"; segment.clear(self.lane, self.cell); event = Some("INCIDENT_END"); }
        else if self.state == "planned" && step > self.end { self.state = "cancelled"; }
        else if self.state == "planned" && step >= self.start && segment.empty(self.lane, self.cell) { self.state = "active"; segment.put(self.lane, self.cell, -1); self.active_start = Some(step); event = Some("INCIDENT_START"); }
        if self.state == "active" { self.active_end = Some(step); } event
    }
}
