use crate::flight_plans::{AircraftType, Plan};
#[derive(Clone)] pub struct Segment {
    pub leg: usize,
    pub phase: &'static str,
    pub start: f64,
    pub end: f64,
    pub position: [f64;3],
    pub velocity: [f64;3],
    pub finish: [f64;3]
}
impl Segment {
    pub fn at(&self, time: f64) -> [f64;3] {
        let t = time-self.start;
        [self.position[0]+self.velocity[0]*t,self.position[1]+self.velocity[1]*t,self.position[2]+self.velocity[2]*t]
    }
}
#[derive(Clone)] pub struct Trajectory {
    pub segments: Vec<Segment>,
    pub length: f64
}
impl Trajectory {
    pub fn at(&self, time: f64) -> Option<(&Segment,[f64;3])> {
        self.segments.iter().find(|s| s.start <= time && time < s.end).map(|s| (s,s.at(time)))
    }
    pub fn arrival(&self) -> f64 {
        self.segments.last().unwrap().end
    }
}
pub fn build(plan: &Plan, aircraft: &AircraftType) -> Trajectory {
    let mut time = (plan.departure+plan.delay) as f64;
    let mut level = plan.level+plan.offset;
    let mut length = 0.0;
    let mut segments = Vec::new();
    for (index,waypoints) in plan.waypoints.windows(2).enumerate() {
        let (p,q) = (&waypoints[0],&waypoints[1]);
        let dx = q.x-p.x;
        let dy = q.y-p.y;
        let leg_length = ((dx*dx+dy*dy) as f64).sqrt()/10.0;
        let duration = leg_length*3600.0/plan.speed as f64;
        length += leg_length;
        let vx = (dx as f64/10.0)/duration;
        let vy = (dy as f64/10.0)/duration;
        let start = [p.x as f64/10.0,p.y as f64/10.0,(level*100) as f64];
        let target = q.level.map_or(level,|l| l+plan.offset);
        let finish = [q.x as f64/10.0,q.y as f64/10.0,(target*100) as f64];
        if target == level {
            segments.push(Segment {
                leg: index+1,
                phase: "LVL",
                start: time,
                end: time+duration,
                position: start,
                velocity: [vx,vy,0.0],
                finish
            });
        } else {
            let climbing = target > level;
            let rate = if climbing {
                aircraft.climb
            } else {
                aircraft.descent
            };
            let vertical = if climbing {
                rate as f64/60.0
            } else {
                -(rate as f64/60.0)
            };
            let change = ((target-level).abs()*6000) as f64/rate as f64;
            let middle = [start[0]+vx*change,start[1]+vy*change,finish[2]];
            segments.push(Segment {
                leg: index+1,
                phase: if climbing {
                    "CLB"
                } else {
                    "DES"
                },
                start: time,
                end: time+change,
                position: start,
                velocity: [vx,vy,vertical],
                finish: middle
            });
            segments.push(Segment {
                leg: index+1,
                phase: "LVL",
                start: time+change,
                end: time+duration,
                position: middle,
                velocity: [vx,vy,0.0],
                finish
            });
        }
        time += duration;
        level = target;
    }
    Trajectory {
        segments,
        length
    }
}
