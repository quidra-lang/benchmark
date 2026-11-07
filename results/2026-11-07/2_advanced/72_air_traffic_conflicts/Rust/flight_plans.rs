use std::fs;
pub struct AircraftType {
    pub name: String,
    pub climb: i64,
    pub descent: i64,
    pub minimum: i64
}
#[derive(Clone)] pub struct Waypoint {
    pub x: i64,
    pub y: i64,
    pub level: Option<i64>
}
#[derive(Clone)] pub struct Plan {
    pub callsign: String,
    pub aircraft: usize,
    pub departure: i64,
    pub level: i64,
    pub speed: i64,
    pub waypoints: Vec<Waypoint>,
    pub delay: i64,
    pub offset: i64,
    pub manoeuvres: Vec<String>
}
impl Plan {
    pub fn levels(&self) -> Vec<i64> {
        std::iter::once(self.level+self.offset).chain(self.waypoints.iter().filter_map(|w| w.level.map(|l| l+self.offset))).collect()
    }
}
pub struct Sector {
    pub name: String,
    pub x1: i64,
    pub y1: i64,
    pub x2: i64,
    pub y2: i64,
    pub lower: i64,
    pub upper: i64,
    pub capacity: usize
}
impl Sector {
    pub fn ranges(&self) -> [(f64,f64);3] {
        [(self.x1 as f64/10.0,self.x2 as f64/10.0),(self.y1 as f64/10.0,self.y2 as f64/10.0),((self.lower*100) as f64,(self.upper*100) as f64)]
    }
    pub fn contains(&self, p: [f64;3]) -> bool {
        self.ranges().iter().zip(p.iter()).all(|(&(a,b),&v)| a <= v && v < b)
    }
}
pub struct Params {
    pub horizontal: f64,
    pub vertical: f64,
    pub lookahead: f64,
    pub max_delay: i64,
    pub levels: [i64;2],
    pub sampling: [i64;2],
    pub radar: [i64;6],
    pub snapshots: Vec<i64>,
    pub leader: i64,
    pub alert: i64
}
pub struct Input {
    pub plans: Vec<Plan>,
    pub types: Vec<AircraftType>,
    pub sectors: Vec<Sector>,
    pub params: Params
}
pub fn read() -> Input {
    let types: Vec<_> = fs::read_to_string("input/aircraft.txt").unwrap().lines().map(|line| {
        let w: Vec<_> = line.split_whitespace().collect();
        AircraftType {
            name: w[0].to_owned(),
            climb: w[1].parse().unwrap(),
            descent: w[2].parse().unwrap(),
            minimum: w[3].parse().unwrap()
        }
    }).collect();
    let mut plans: Vec<_> = fs::read_to_string("input/flights.csv").unwrap().lines().skip(1).map(|line| {
        let w: Vec<_> = line.split(',').collect();
        let waypoints = w[5].split_whitespace().map(|point| {
            let p: Vec<i64> = point.split(':').map(|s| s.parse().unwrap()).collect();
            Waypoint {
                x: p[0],
                y: p[1],
                level: p.get(2).copied()
            }
        }).collect();
        Plan {
            callsign: w[0].to_owned(),
            aircraft: types.iter().position(|t| t.name == w[1]).unwrap(),
            departure: w[2].parse().unwrap(),
            level: w[3].parse().unwrap(),
            speed: w[4].parse().unwrap(),
            waypoints,
            delay: 0,
            offset: 0,
            manoeuvres: Vec::new()
        }
    }).collect();
    plans.sort_by(|a,b| a.callsign.cmp(&b.callsign));
    let sectors = fs::read_to_string("input/sectors.txt").unwrap().lines().map(|line| {
        let w: Vec<_> = line.split_whitespace().collect();
        Sector {
            name: w[0].to_owned(),
            x1: w[1].parse().unwrap(),
            y1: w[2].parse().unwrap(),
            x2: w[3].parse().unwrap(),
            y2: w[4].parse().unwrap(),
            lower: w[5].parse().unwrap(),
            upper: w[6].parse().unwrap(),
            capacity: w[7].parse().unwrap()
        }
    }).collect();
    let lines: Vec<Vec<i64>> = fs::read_to_string("input/params.txt").unwrap().lines().map(|l| l.split_whitespace().skip(1).map(|s| s.parse().unwrap()).collect()).collect();
    let params = Params {
        horizontal: lines[0][0] as f64,
        vertical: lines[0][1] as f64,
        lookahead: lines[1][0] as f64,
        max_delay: lines[2][0],
        levels: [lines[3][0],lines[3][1]],
        sampling: [lines[4][0],lines[4][1]],
        radar: [lines[5][0],lines[5][1],lines[5][2],lines[5][3],lines[5][4],lines[5][5]],
        snapshots: lines[6].clone(),
        leader: lines[7][0],
        alert: lines[8][0]
    };
    Input {
        plans,
        types,
        sectors,
        params
    }
}
