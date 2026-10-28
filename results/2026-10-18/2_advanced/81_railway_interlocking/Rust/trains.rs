use std::fs;
use crate::layout::Layout;
use crate::interlocking::Interlocking;
pub struct Stop {
    pub section: usize,
    pub turn: bool,
    pub dwell: usize,
    pub arrival: usize,
    pub departure: usize,
    pub actual_arrival: Option<usize>,
    pub actual_departure: Option<usize>
}
pub struct Train {
    pub name: String,
    pub length: i64,
    pub acceleration: i64,
    pub deceleration: i64,
    pub maximum: i64,
    pub entry: usize,
    pub scheduled_entry: usize,
    pub initial_speed: i64,
    pub stops: Vec<Stop>,
    pub exit: usize,
    pub scheduled_exit: usize,
    pub state: usize,
    pub up: bool,
    pub path: Vec<(usize,i64)>,
    pub head: i64,
    pub speed: i64,
    pub next_stop: usize,
    pub dwelling: bool,
    pub awaiting: Option<usize>,
    pub emergency: bool,
    pub crossed: Option<i64>,
    pub actual_entry: Option<usize>,
    pub actual_exit: Option<usize>,
    pub distance: i64,
    pub max_speed: i64,
    pub standing: usize,
    pub passes: usize
}
impl Train {
    pub fn head_index(&self) -> usize {
        self.path.iter().rposition(|&(_,start)| start < self.head).unwrap_or(0)
    }
    pub fn body(&self, layout: &Layout) -> Vec<(usize,i64,i64,i64)> {
        if self.state != 1 {
            return Vec::new();
        }
        self.path.iter().filter_map(|&(section,start)| {
            let end = start+layout.sections[section].length;
            if start < self.head && end > self.head-self.length {
                Some((section,start,(self.head-self.length).max(start),self.head.min(end)))
            } else {
                None
            }
        }).collect()
    }
}
pub fn braking(speed: i64, deceleration: i64) -> i64 {
    let n = speed/deceleration;
    n*speed-deceleration*n*(n+1)/2
}
pub fn speed(train: &Train, distance: Option<i64>) -> i64 {
    let low = (train.speed-train.deceleration).max(0);
    if train.emergency {
        return low;
    }
    let high = (train.speed+train.acceleration).min(train.maximum);
    (low..=high).rev().find(|&u| distance.map_or(true,|d| u+braking(u,train.deceleration) <= d)).unwrap_or(low)
}
pub fn read(layout: &Layout, routes: &Interlocking) -> (Vec<Train>,Vec<(usize,usize,usize)>) {
    let mut trains = Vec::<Train>::new();
    let mut requests = Vec::new();
    for line in fs::read_to_string("input/trains.txt").unwrap().lines() {
        let w: Vec<_> = line.split_whitespace().collect();
        if w[0] == "TRAIN" {
            trains.push(Train {
                name: w[1].to_owned(),
                length: w[2].parse().unwrap(),
                acceleration: w[3].parse().unwrap(),
                deceleration: w[4].parse().unwrap(),
                maximum: w[5].parse().unwrap(),
                entry: layout.boundary(w[6]),
                scheduled_entry: w[7].parse().unwrap(),
                initial_speed: w[8].parse().unwrap(),
                stops: Vec::new(),
                exit: 0,
                scheduled_exit: 0,
                state: 0,
                up: true,
                path: Vec::new(),
                head: 0,
                speed: 0,
                next_stop: 0,
                dwelling: false,
                awaiting: None,
                emergency: false,
                crossed: None,
                actual_entry: None,
                actual_exit: None,
                distance: 0,
                max_speed: 0,
                standing: 0,
                passes: 0
            });
        } else {
            let i = trains.iter().position(|t| t.name == w[1]).unwrap();
            match w[0] {
                "REQUEST" => requests.push((w[3].parse().unwrap(),routes.route(w[2]),i)),"EXIT" => {
                    trains[i].exit = layout.boundary(w[2]);
                    trains[i].scheduled_exit = w[3].parse().unwrap();
                },_ => trains[i].stops.push(Stop {
                    section: layout.section(w[2]),
                    turn: w[0] == "TURN",
                    dwell: w[3].parse().unwrap(),
                    arrival: w[4].parse().unwrap(),
                    departure: w[5].parse().unwrap(),
                    actual_arrival: None,
                    actual_departure: None
                })
            }
        }
    }
    (trains,requests)
}
