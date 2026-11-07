use std::collections::BTreeSet;
use crate::road::{BusStop, Segment};

pub struct VehicleClass { pub name: String, pub vmax: usize, pub weight: i64, pub overtakes: bool, pub stops: bool }
pub struct Vehicle {
    pub number: usize, pub class: usize, pub source: usize, pub arrival: usize, pub inserted: Option<usize>, pub exited: Option<usize>, pub sink: Option<String>,
    pub segment: Option<usize>, pub lane: usize, pub cell: usize, pub speed: usize, pub turn: Option<usize>, pub route: Vec<usize>,
    pub steps: i64, pub distance: i64, pub stopped_steps: i64, pub stop_count: i64, pub lane_changes: i64, pub dwell: usize, pub completed_stops: BTreeSet<usize>,
}
impl Vehicle {
    pub fn new(number: usize, class: usize, source: usize, arrival: usize) -> Self {
        Self { number, class, source, arrival, inserted: None, exited: None, sink: None, segment: None, lane: 0, cell: 0, speed: 0, turn: None, route: Vec::new(), steps: 0, distance: 0, stopped_steps: 0, stop_count: 0, lane_changes: 0, dwell: 0, completed_stops: BTreeSet::new() }
    }
    pub fn max_speed(&self, classes: &[VehicleClass], segments: &[Segment]) -> usize { classes[self.class].vmax.min(segments[self.segment.unwrap()].limit) }
    pub fn place(&mut self, segments: &mut [Segment], target: usize, lane: usize, cell: usize) {
        if let Some(previous) = self.segment { segments[previous].clear(self.lane, self.cell); } segments[target].put(lane, cell, self.number as i64); self.segment = Some(target); self.lane = lane; self.cell = cell;
    }
    pub fn leave(&mut self, segments: &mut [Segment]) { segments[self.segment.unwrap()].clear(self.lane, self.cell); self.segment = None; }
    pub fn heading_for_stop(&self, classes: &[VehicleClass], segments: &[Segment], stops: &[BusStop]) -> bool {
        let Some(segment) = self.segment else { return false; }; let Some(stop) = segments[segment].stop else { return false; };
        classes[self.class].stops && !self.completed_stops.contains(&segment) && self.cell <= stops[stop].cell
    }
    pub fn travel_time(&self) -> i64 { (self.exited.unwrap() - self.inserted.unwrap() + 1) as i64 }
}
pub fn random_slowdown(speed: usize, previous: usize, value: i64, dawdle: i64, stopped: i64) -> usize {
    let probability = if previous == 0 { stopped } else { dawdle };
    if speed > 0 && value % 1000 < probability { speed - 1 } else { speed }
}
