mod flight_plans;
mod trajectory;
mod conflict;
mod resolution;
mod report;
use std::collections::{BTreeMap,BTreeSet};
use flight_plans::{Input,Plan,Sector};
use trajectory::{Segment,Trajectory};
use conflict::Conflict;
use report::real;
fn r(value: f64) -> String {
    real(value,3)
}
fn pair(input: &Input, a: usize, b: usize) -> String {
    format!("{}-{}",input.plans[a].callsign,input.plans[b].callsign)
}
fn track(segment: &Segment) -> f64 {
    let angle = segment.velocity[0].atan2(segment.velocity[1])*180.0/3.141592653589793;
    if angle < 0.0 {
        angle+360.0
    } else {
        angle
    }
}
fn manoeuvres(plan: &Plan) -> String {
    if plan.manoeuvres.is_empty() {
        "-".to_owned()
    } else {
        plan.manoeuvres.join(",")
    }
}
fn resolve(input: &Input, initial: &[Trajectory], initial_conflicts: &[Conflict]) -> (Vec<Plan>,Vec<Trajectory>,BTreeSet<(usize,usize)>,Vec<String>) {
    let mut plans = input.plans.clone();
    let mut trajectories = initial.to_vec();
    let mut unresolved = BTreeSet::new();
    let mut resolved = BTreeSet::new();
    let mut recorded = Vec::new();
    let mut lines = Vec::new();
    let moves = resolution::manoeuvres(input.params.max_delay);
    let mut rounds = 0;
    let mut accepted_count = 0;
    let mut counts = [0usize;3];
    let mut trials = 0;
    let mut infeasible = 0;
    let mut blocked = 0;
    loop {
        let conflicts = conflict::list(&trajectories,input.params.horizontal,input.params.vertical);
        let Some(target) = conflicts.into_iter().find(|c| !unresolved.contains(&c.pair())) else {
            break;
        };
        rounds += 1;
        lines.push(format!("ROUND {} {} start={} end={} dist={}",rounds,pair(input,target.a,target.b),r(target.start),r(target.end),r(target.closest().loss.distance)));
        let lower = if resolution::lower_priority(&plans[target.a],&plans[target.b]) {
            target.a
        } else {
            target.b
        };
        let higher = if lower == target.a {
            target.b
        } else {
            target.a
        };
        let mut accepted = None;
        'aircraft: for (f,partner) in [(lower,higher),(higher,lower)].iter().copied() {
            for movement in &moves {
                trials += 1;
                let Some(next) = resolution::apply(&plans[f],movement,&input.types[plans[f].aircraft],&input.params) else {
                    infeasible += 1;
                    lines.push(format!("  TRY {} {} infeasible",plans[f].callsign,movement.name));
                    continue;
                };
                let trajectory = trajectory::build(&next,&input.types[next.aircraft]);
                let mut blockers = Vec::new();
                for g in 0..plans.len() {
                    if f == g {
                        continue;
                    }
                    let (a,b) = (f.min(g),f.max(g));
                    if unresolved.contains(&(a,b)) {
                        continue;
                    }
                    let (first,second) = if f == a {
                        (&trajectory,&trajectories[g])
                    } else {
                        (&trajectories[g],&trajectory)
                    };
                    blockers.extend(conflict::pair(a,b,first,second,input.params.horizontal,input.params.vertical).into_iter().filter(|c| g == partner || c.start < target.start+input.params.lookahead));
                }
                conflict::sort(&mut blockers);
                if let Some(blocker) = blockers.first() {
                    blocked += 1;
                    lines.push(format!("  TRY {} {} blocked {} start={}",plans[f].callsign,movement.name,pair(input,blocker.a,blocker.b),r(blocker.start)));
                } else {
                    lines.push(format!("  TRY {} {} accepted",plans[f].callsign,movement.name));
                    plans[f] = next;
                    trajectories[f] = trajectory;
                    accepted = Some((f,movement.name.clone(),movement.kind));
                    break 'aircraft;
                }
            }
        }
        if let Some((f,name,kind)) = accepted {
            resolved.insert(target.pair());
            accepted_count += 1;
            counts[kind] += 1;
            lines.push(format!("  RESULT resolved {} {}",plans[f].callsign,name));
        } else {
            unresolved.insert(target.pair());
            lines.push("  RESULT unresolved".to_owned());
            recorded.push(target);
        }
    }
    let final_conflicts = conflict::list(&trajectories,input.params.horizontal,input.params.vertical);
    for (i,plan) in plans.iter().enumerate() {
        let before = initial_conflicts.iter().filter(|c| c.a == i || c.b == i).count();
        let after = final_conflicts.iter().filter(|c| c.a == i || c.b == i).count();
        lines.push(format!("FLIGHT {} departure={} delay={} level={} speed={}->{} arrival={}->{} extra={} length={} conflicts={}->{} manoeuvres={}",plan.callsign,plan.departure+plan.delay,plan.delay,report::signed(plan.offset),input.plans[i].speed,plan.speed,r(initial[i].arrival()),r(trajectories[i].arrival()),r(trajectories[i].arrival()-initial[i].arrival()),r(trajectories[i].length),before,after,manoeuvres(plan)));
    }
    for c in &recorded {
        lines.push(format!("UNRESOLVED {} start={} dist={}",pair(input,c.a,c.b),r(c.start),r(c.closest().loss.distance)));
    }
    let total_extra = trajectories.iter().zip(initial).fold(0.0,|sum,(a,b)| sum+(a.arrival()-b.arrival()));
    lines.push(format!("TOTAL rounds={} resolved={} unresolved={} level={} speed={} delay={} total_delay={} total_extra={} trials={} infeasible={} blocked={}",rounds,accepted_count,recorded.len(),counts[0],counts[1],counts[2],plans.iter().map(|p| p.delay).sum::<i64>(),r(total_extra),trials,infeasible,blocked));
    (plans,trajectories,resolved,lines)
}
struct Classification {
    altitudes: [f64;2],
    tracks: [f64;2],
    angle: f64,
    geometry: usize,
    severity: usize,
    sector: Option<usize>
}
fn classify(input: &Input, trajectories: &[Trajectory], c: &Conflict) -> Classification {
    let piece = c.closest();
    let a = &trajectories[c.a].segments[piece.a];
    let b = &trajectories[c.b].segments[piece.b];
    let pa = a.at(piece.loss.time);
    let pb = b.at(piece.loss.time);
    let ta = track(a);
    let tb = track(b);
    let gap = (ta-tb).abs();
    let dot = a.velocity[0]*b.velocity[0]+a.velocity[1]*b.velocity[1];
    let cross = a.velocity[0]*b.velocity[1]-a.velocity[1]*b.velocity[0];
    let geometry = if dot*dot > cross*cross {
        if dot < 0.0 {
            0
        } else {
            2
        }
    } else {
        1
    };
    let severity = if 10.0*piece.loss.distance < 4.0*input.params.horizontal {
        0
    } else if 10.0*piece.loss.distance < 7.0*input.params.horizontal {
        1
    } else {
        2
    };
    let midpoint = [(pa[0]+pb[0])/2.0,(pa[1]+pb[1])/2.0,(pa[2]+pb[2])/2.0];
    let sector = input.sectors.iter().position(|s| s.contains(midpoint));
    Classification {
        altitudes: [pa[2]/100.0,pb[2]/100.0],
        tracks: [ta,tb],
        angle: if gap > 180.0 {
            360.0-gap
        } else {
            gap
        },
        geometry,
        severity,
        sector
    }
}
fn conflict_report(input: &Input, trajectories: &[Trajectory], conflicts: &[Conflict], classes: &[Classification], final_pairs: &BTreeSet<(usize,usize)>, resolved: &BTreeSet<(usize,usize)>, name: &str, times: &[i64]) -> Vec<String> {
    let geometries = ["head_on","crossing","trailing"];
    let severities = ["HIGH","MEDIUM","LOW"];
    let mut counts = [[0usize;3];2];
    let mut lines = vec![format!("CONFLICTS plan={} count={}",name,conflicts.len())];
    for (i,(c,class)) in conflicts.iter().zip(classes).enumerate() {
        let closest = c.closest();
        let loss = &closest.loss;
        let a = &trajectories[c.a].segments[closest.a];
        let b = &trajectories[c.b].segments[closest.b];
        let outcome = if final_pairs.contains(&c.pair()) {
            "remaining"
        } else if resolved.contains(&c.pair()) {
            "resolved"
        } else {
            "indirect"
        };
        lines.push(format!("CONFLICT {} {} start={} end={} duration={} outcome={}",i+1,pair(input,c.a,c.b),r(c.start),r(c.end),r(c.end-c.start),outcome));
        lines.push(format!("  CPA t={} dist={} vert={} levels={}/{} tracks={}/{} angle={}",r(loss.time),r(loss.distance),real(loss.vertical,1),real(class.altitudes[0],2),real(class.altitudes[1],2),real(class.tracks[0],1),real(class.tracks[1],1),real(class.angle,1)));
        lines.push(format!("  TYPE geometry={} phases={}/{} segments={}/{} sector={} severity={}",geometries[class.geometry],a.phase,b.phase,closest.a+1,closest.b+1,class.sector.map_or("-",|s| input.sectors[s].name.as_str()),severities[class.severity]));
        for piece in &c.pieces {
            lines.push(format!("  PIECE {}/{} {} {}",piece.a+1,piece.b+1,r(piece.loss.lo),r(piece.loss.hi)));
        }
        counts[0][class.geometry] += 1;
        counts[1][class.severity] += 1;
    }
    let duration = conflicts.iter().fold(0.0,|sum,c| sum+(c.end-c.start));
    let minimum = conflicts.iter().map(|c| c.closest().loss.distance).reduce(f64::min).map_or_else(|| "-".to_owned(),r);
    lines.push(format!("SUMMARY count={} total={} min_dist={} head_on={} crossing={} trailing={} high={} medium={} low={}",conflicts.len(),r(duration),minimum,counts[0][0],counts[0][1],counts[0][2],counts[1][0],counts[1][1],counts[1][2]));
    let involved: Vec<_> = (0..input.plans.len()).filter(|&f| conflicts.iter().any(|c| c.a == f || c.b == f)).collect();
    for &f in &involved {
        let relevant: Vec<_> = conflicts.iter().filter(|c| c.a == f || c.b == f).collect();
        let partners: BTreeSet<_> = relevant.iter().map(|c| if c.a == f {
            c.b
        } else {
            c.a
        }).collect();
        lines.push(format!("FLIGHT {} conflicts={} first={} partners={}",input.plans[f].callsign,relevant.len(),r(relevant[0].start),partners.iter().map(|&p| input.plans[p].callsign.as_str()).collect::<Vec<_>>().join(",")));
    }
    lines.push(format!("TIMELINE from={} to={} step=60",input.params.sampling[0],input.params.sampling[1]));
    for f in involved {
        let text: String = times.iter().map(|&time| if trajectories[f].at(time as f64).is_none() {
            '.'
        } else if conflicts.iter().any(|c| (c.a == f || c.b == f) && c.active(time as f64)) {
            'X'
        } else {
            '-'
        }).collect();
        lines.push(format!("{} {}",input.plans[f].callsign,text));
    }
    lines
}
struct Transit {
    flight: usize,
    sector: usize,
    entry: f64,
    exit: f64,
    previous: Option<usize>,
    next: Option<usize>
}
fn inside(segment: &Segment, sector: &Sector) -> Option<(f64,f64)> {
    let (mut lo,mut hi) = (segment.start,segment.end);
    for (axis,(a,b)) in sector.ranges().iter().copied().enumerate() {
        let p = segment.position[axis];
        let v = segment.velocity[axis];
        if v == 0.0 {
            if !(a <= p && p < b) {
                return None;
            }
        } else {
            let r1 = (a-p)/v;
            let r2 = (b-p)/v;
            lo = lo.max(segment.start+r1.min(r2));
            hi = hi.min(segment.start+r1.max(r2));
        }
    }
    if hi-lo > 0.000001 {
        Some((lo,hi))
    } else {
        None
    }
}
fn transits(input: &Input, trajectories: &[Trajectory]) -> Vec<Transit> {
    let mut result = Vec::new();
    for (flight,trajectory) in trajectories.iter().enumerate() {
        let mut current = Vec::new();
        for (sector,s) in input.sectors.iter().enumerate() {
            let mut times: Vec<(f64,f64)> = Vec::new();
            for segment in &trajectory.segments {
                if let Some((lo,hi)) = inside(segment,s) {
                    if let Some(last) = times.last_mut() {
                        if lo-last.1 <= 0.000001 {
                            last.1 = hi;
                            continue;
                        }
                    }
                    times.push((lo,hi));
                }
            }
            for (entry,exit) in times {
                current.push(Transit {
                    flight,
                    sector,
                    entry,
                    exit,
                    previous: None,
                    next: None
                });
            }
        }
        current.sort_by(|a,b| a.entry.total_cmp(&b.entry).then(a.sector.cmp(&b.sector)));
        for i in 1..current.len() {
            if (current[i].entry-current[i-1].exit).abs() <= 0.000001 {
                current[i-1].next = Some(current[i].sector);
                current[i].previous = Some(current[i-1].sector);
            }
        }
        result.extend(current);
    }
    result
}
fn occupancy(input: &Input, trajectories: &[Trajectory], times: &[i64]) -> Vec<Vec<usize>> {
    input.sectors.iter().map(|sector| times.iter().map(|&time| trajectories.iter().filter(|t| t.at(time as f64).map_or(false,|(_,p)| sector.contains(p))).count()).collect()).collect()
}
fn entries(transits: &[Transit], sector: usize, first: i64, last: i64) -> usize {
    transits.iter().filter(|t| t.sector == sector && first as f64 <= t.entry && t.entry < last as f64).count()
}
fn sector_reports(input: &Input, trajectories: [&[Trajectory];2], conflicts: [&[Conflict];2], classes: [&[Classification];2], transits: [&[Transit];2], occupancy: [&[Vec<usize>];2], times: &[i64]) -> (Vec<String>,Vec<String>) {
    let mut load = vec!["sector,period,start,end,entries_initial,entries_final,peak_initial,peak_final,mean_final,capacity,status".to_owned()];
    let mut lines = Vec::new();
    for (s,sector) in input.sectors.iter().enumerate() {
        let mut over = [0usize;2];
        for period in 0..times.len()/5 {
            let start = input.params.sampling[0]+300*period as i64;
            let end = start+300;
            let first = period*5;
            let peak_initial = *occupancy[0][s][first..first+5].iter().max().unwrap();
            let peak_final = *occupancy[1][s][first..first+5].iter().max().unwrap();
            let mean = occupancy[1][s][first..first+5].iter().sum::<usize>() as f64/5.0;
            over[0] += usize::from(peak_initial > sector.capacity);
            over[1] += usize::from(peak_final > sector.capacity);
            load.push(format!("{},{},{},{},{},{},{},{},{},{},{}",sector.name,period+1,start,end,entries(transits[0],s,start,end),entries(transits[1],s,start,end),peak_initial,peak_final,real(mean,1),sector.capacity,if peak_final > sector.capacity {
                "OVER"
            } else if peak_initial > sector.capacity {
                "RELIEVED"
            } else {
                "OK"
            }));
        }
        lines.push(format!("SECTOR {} x={}..{} y={}..{} fl={}..{} capacity={}",sector.name,sector.x1,sector.x2,sector.y1,sector.y2,sector.lower,sector.upper,sector.capacity));
        for plan in 0..2 {
            let relevant: Vec<_> = transits[plan].iter().filter(|t| t.sector == s).collect();
            let dwell = relevant.iter().fold(0.0,|sum,t| sum+(t.exit-t.entry));
            let count = relevant.len();
            let peak = *occupancy[plan][s].iter().max().unwrap();
            lines.push(format!("{} entries={} time={} mean={} peak={} over={} conflicts={}",if plan == 0 {
                "INITIAL"
            } else {
                "FINAL"
            },count,r(dwell),if count == 0 {
                "-".to_owned()
            } else {
                r(dwell/count as f64)
            },peak,over[plan],conflicts[plan].iter().zip(classes[plan]).filter(|(_,class)| class.sector == Some(s)).count()));
        }
        let height = (sector.capacity+1).max(*occupancy[1][s].iter().max().unwrap());
        let grid: Vec<_> = (1..=height).rev().map(|k| occupancy[1][s].iter().map(|&v| if v >= k {
            b'#'
        } else if k == sector.capacity {
            b'-'
        } else {
            b'.'
        }).collect()).collect();
        lines.extend(report::chart(&grid));
    }
    let mut levels = BTreeMap::<i64,[(BTreeSet<usize>,f64);2]>::new();
    for plan in 0..2 {
        for (flight,trajectory) in trajectories[plan].iter().enumerate() {
            for segment in &trajectory.segments {
                if segment.phase == "LVL" {
                    let level = (segment.position[2]/100.0) as i64;
                    let value = levels.entry(level).or_insert_with(|| [(BTreeSet::new(),0.0),(BTreeSet::new(),0.0)]);
                    value[plan].0.insert(flight);
                    value[plan].1 += segment.end-segment.start;
                }
            }
        }
    }
    lines.push("LEVELS".to_owned());
    for (level,value) in levels.iter().rev() {
        lines.push(format!("LEVEL {} flights={}->{} time={}->{}",level,value[0].0.len(),value[1].0.len(),r(value[0].1),r(value[1].1)));
    }
    let mut handoffs = BTreeMap::new();
    for transit in transits[1] {
        if let Some(next) = transit.next {
            *handoffs.entry((transit.sector,next)).or_insert(0usize) += 1;
        }
    }
    lines.push(format!("HANDOFFS plan=final count={}",handoffs.values().sum::<usize>()));
    for ((from,to),count) in handoffs {
        lines.push(format!("HANDOFF {} {} {}",input.sectors[from].name,input.sectors[to].name,count));
    }
    (load,lines)
}
struct Alert {
    a: usize,
    b: usize,
    first: i64,
    last: i64,
    samples: usize,
    predicted: f64,
    minimum: f64
}
fn alerts(input: &Input, trajectories: &[Trajectory], conflicts: &[Conflict], times: &[i64], name: &str) -> Vec<String> {
    let mut alerts = Vec::new();
    for a in 0..trajectories.len() {
        for b in a+1..trajectories.len() {
            let mut current: Option<Alert> = None;
            for &time in times {
                let loss = trajectories[a].at(time as f64).zip(trajectories[b].at(time as f64)).and_then(|((sa,pa),(sb,pb))| conflict::loss(conflict::difference(pa,pb),conflict::difference(sa.velocity,sb.velocity),0.0,input.params.alert as f64,input.params.horizontal,input.params.vertical));
                if let Some(loss) = loss {
                    if let Some(alert) = current.as_mut() {
                        if time-alert.last == 60 {
                            alert.last = time;
                            alert.samples += 1;
                            alert.minimum = alert.minimum.min(loss.distance);
                            continue;
                        }
                    }
                    if let Some(alert) = current.take() {
                        alerts.push(alert);
                    }
                    current = Some(Alert {
                        a,
                        b,
                        first: time,
                        last: time,
                        samples: 1,
                        predicted: time as f64+loss.lo,
                        minimum: loss.distance
                    });
                } else if let Some(alert) = current.take() {
                    alerts.push(alert);
                }
            }
            if let Some(alert) = current {
                alerts.push(alert);
            }
        }
    }
    alerts.sort_by_key(|a| (a.first,a.a,a.b));
    let mut detected = vec![false;conflicts.len()];
    let mut true_count = 0;
    let mut lead_sum = 0.0;
    let mut lines = vec![format!("ALERTS plan={} horizon={} count={}",name,input.params.alert,alerts.len())];
    for (index,alert) in alerts.iter().enumerate() {
        let matches: Vec<_> = conflicts.iter().enumerate().filter(|(_,c)| c.a == alert.a && c.b == alert.b && c.start < (alert.last+input.params.alert) as f64 && c.end > alert.first as f64).map(|(i,_)| i).collect();
        let matching = if let Some(&first) = matches.first() {
            for i in matches {
                detected[i] = true;
            }
            true_count += 1;
            let lead = conflicts[first].start-alert.first as f64;
            lead_sum += lead;
            format!("status=true lead={}",r(lead))
        } else {
            "status=false lead=-".to_owned()
        };
        lines.push(format!("ALERT {} {} first={} last={} samples={} predicted={} min_dist={} {}",index+1,pair(input,alert.a,alert.b),alert.first,alert.last,alert.samples,r(alert.predicted),r(alert.minimum),matching));
    }
    let mut missed = 0;
    for (c,seen) in conflicts.iter().zip(detected) {
        if !seen {
            missed += 1;
            lines.push(format!("MISSED {} start={} end={}",pair(input,c.a,c.b),r(c.start),r(c.end)));
        }
    }
    lines.push(format!("SUMMARY alerts={} true={} false={} missed={} mean_lead={}",alerts.len(),true_count,alerts.len()-true_count,missed,if true_count == 0 {
        "-".to_owned()
    } else {
        r(lead_sum/true_count as f64)
    }));
    lines
}
fn cell(input: &Input, position: [f64;3]) -> Option<(usize,usize)> {
    let p = input.params.radar;
    let column = ((10.0*position[0]-p[0] as f64)*p[4] as f64/(p[2]-p[0]) as f64).floor() as i64;
    let row = ((10.0*position[1]-p[1] as f64)*p[5] as f64/(p[3]-p[1]) as f64).floor() as i64;
    if column >= 0 && column < p[4] && row >= 0 && row < p[5] {
        Some((column as usize,(p[5]-1-row) as usize))
    } else {
        None
    }
}
fn radar(input: &Input, trajectories: [&[Trajectory];2], conflicts: [&[Conflict];2], times: &[i64]) -> Vec<String> {
    let width = input.params.radar[4] as usize;
    let height = input.params.radar[5] as usize;
    let mut lines = Vec::new();
    for &time in &input.params.snapshots {
        for plan in 0..2 {
            let positions: Vec<_> = trajectories[plan].iter().map(|t| t.at(time as f64)).collect();
            let active: Vec<_> = conflicts[plan].iter().filter(|c| c.active(time as f64)).collect();
            let mut placements = vec![vec![Vec::new();width];height];
            let mut grid = vec![vec![b'.';width];height];
            for (flight,position) in positions.iter().enumerate() {
                if let Some((_,p)) = position {
                    if let Some((c,r)) = cell(input,*p) {
                        placements[r][c].push(flight);
                    }
                }
            }
            for row in 0..height {
                for col in 0..width {
                    let placed = &placements[row][col];
                    if placed.len() > 1 {
                        grid[row][col] = b'0'+placed.len() as u8;
                    } else if let Some(&flight) = placed.first() {
                        let character = input.plans[flight].callsign.as_bytes()[0];
                        grid[row][col] = if active.iter().any(|c| c.a == flight || c.b == flight) {
                            character.to_ascii_lowercase()
                        } else {
                            character
                        };
                    }
                }
            }
            for (flight,position) in positions.iter().enumerate() {
                if position.is_some() {
                    if let Some((_,p)) = trajectories[plan][flight].at((time+input.params.leader) as f64) {
                        if let Some((c,r)) = cell(input,p) {
                            if grid[r][c] == b'.' {
                                grid[r][c] = b'*';
                            }
                        }
                    }
                }
            }
            lines.push(format!("RADAR plan={} t={} aircraft={} conflicts={}",if plan == 0 {
                "initial"
            } else {
                "final"
            },time,positions.iter().filter(|p| p.is_some()).count(),active.len()));
            lines.extend(report::chart(&grid));
            for (flight,position) in positions.iter().enumerate() {
                if let Some((segment,p)) = position {
                    let location = cell(input,*p).map_or_else(|| "outside".to_owned(),|(c,r)| format!("{},{}",c,r));
                    lines.push(format!("{} x={} y={} fl={} track={} phase={} cell={}",input.plans[flight].callsign,r(p[0]),r(p[1]),real(p[2]/100.0,2),real(track(segment),1),segment.phase,location));
                }
            }
            for c in active {
                let pa = positions[c.a].as_ref().unwrap().1;
                let pb = positions[c.b].as_ref().unwrap().1;
                let d = conflict::difference(pa,pb);
                lines.push(format!("CONFLICT {} dist={} vert={}",pair(input,c.a,c.b),r((d[0]*d[0]+d[1]*d[1]).sqrt()),real(d[2].abs(),1)));
            }
        }
    }
    for plan in 0..2 {
        let mut density = vec![vec![0usize;width];height];
        for &time in times {
            for trajectory in trajectories[plan] {
                if let Some((_,p)) = trajectory.at(time as f64) {
                    if let Some((c,r)) = cell(input,p) {
                        density[r][c] += 1;
                    }
                }
            }
        }
        let maximum = density.iter().flatten().copied().max().unwrap();
        let grid: Vec<_> = density.iter().map(|row| row.iter().map(|&v| if v == 0 {
            b'.'
        } else if v < 10 {
            b'0'+v as u8
        } else {
            b'#'
        }).collect()).collect();
        lines.push(format!("DENSITY plan={} from={} to={} step=60 max={}",if plan == 0 {
            "initial"
        } else {
            "final"
        },input.params.sampling[0],input.params.sampling[1],maximum));
        lines.extend(report::chart(&grid));
    }
    lines
}
fn strips(input: &Input, plans: &[Plan], initial: &[Trajectory], final_trajectories: &[Trajectory], transits: &[Transit]) -> Vec<String> {
    let mut lines = Vec::new();
    for (flight,plan) in plans.iter().enumerate() {
        lines.push(format!("STRIP {} type={} waypoints={} length={} manoeuvres={}",plan.callsign,input.types[plan.aircraft].name,plan.waypoints.len(),r(final_trajectories[flight].length),manoeuvres(plan)));
        for (k,waypoint) in plan.waypoints.iter().enumerate() {
            let passing = |trajectory: &Trajectory| if k == 0 {
                let s = &trajectory.segments[0];
                (s.start,(s.position[2]/100.0) as i64)
            } else {
                let s = trajectory.segments.iter().rev().find(|s| s.leg == k).unwrap();
                (s.end,(s.finish[2]/100.0) as i64)
            };
            let a = passing(&initial[flight]);
            let b = passing(&final_trajectories[flight]);
            lines.push(format!("WPT {} at={}:{} eta={}->{} fl={}->{}",k,waypoint.x,waypoint.y,r(a.0),r(b.0),a.1,b.1));
        }
        let sequence: Vec<_> = transits.iter().filter(|t| t.flight == flight).map(|t| format!("{}@{}",input.sectors[t.sector].name,r(t.entry))).collect();
        lines.push(format!("SECTORS {}",if sequence.is_empty() {
            "-".to_owned()
        } else {
            sequence.join(",")
        }));
    }
    lines
}
fn main() {
    let input = flight_plans::read();
    let initial: Vec<_> = input.plans.iter().map(|p| trajectory::build(p,&input.types[p.aircraft])).collect();
    let initial_conflicts = conflict::list(&initial,input.params.horizontal,input.params.vertical);
    let (plans,final_trajectories,resolved,resolutions) = resolve(&input,&initial,&initial_conflicts);
    let final_conflicts = conflict::list(&final_trajectories,input.params.horizontal,input.params.vertical);
    let final_pairs = final_conflicts.iter().map(Conflict::pair).collect();
    let initial_classes: Vec<_> = initial_conflicts.iter().map(|c| classify(&input,&initial,c)).collect();
    let final_classes: Vec<_> = final_conflicts.iter().map(|c| classify(&input,&final_trajectories,c)).collect();
    let mut times = Vec::new();
    let mut time = input.params.sampling[0];
    while time < input.params.sampling[1] {
        times.push(time);
        time += 60;
    }
    let initial_transits = transits(&input,&initial);
    let final_transits = transits(&input,&final_trajectories);
    let initial_occupancy = occupancy(&input,&initial,&times);
    let final_occupancy = occupancy(&input,&final_trajectories,&times);
    let mut trajectories = vec!["callsign,segment,leg,phase,t_start,t_end,x_start,y_start,fl_start,x_end,y_end,fl_end".to_owned()];
    for (plan,trajectory) in plans.iter().zip(&final_trajectories) {
        for (i,s) in trajectory.segments.iter().enumerate() {
            trajectories.push(format!("{},{},{},{},{},{},{},{},{},{},{},{}",plan.callsign,i+1,s.leg,s.phase,r(s.start),r(s.end),r(s.position[0]),r(s.position[1]),(s.position[2]/100.0) as i64,r(s.finish[0]),r(s.finish[1]),(s.finish[2]/100.0) as i64));
        }
    }
    let mut conflicts = conflict_report(&input,&initial,&initial_conflicts,&initial_classes,&final_pairs,&resolved,"initial",&times);
    conflicts.extend(conflict_report(&input,&final_trajectories,&final_conflicts,&final_classes,&final_pairs,&resolved,"final",&times));
    let mut transit_csv = vec!["callsign,sector,entry,exit,duration,from,to".to_owned()];
    for t in &final_transits {
        transit_csv.push(format!("{},{},{},{},{},{},{}",plans[t.flight].callsign,input.sectors[t.sector].name,r(t.entry),r(t.exit),r(t.exit-t.entry),t.previous.map_or("-",|s| input.sectors[s].name.as_str()),t.next.map_or("-",|s| input.sectors[s].name.as_str())));
    }
    let (load,sector_report) = sector_reports(&input,[&initial,&final_trajectories],[&initial_conflicts,&final_conflicts],[&initial_classes,&final_classes],[&initial_transits,&final_transits],[&initial_occupancy,&final_occupancy],&times);
    let mut alert_report = alerts(&input,&initial,&initial_conflicts,&times,"initial");
    alert_report.extend(alerts(&input,&final_trajectories,&final_conflicts,&times,"final"));
    let radar_report = radar(&input,[&initial,&final_trajectories],[&initial_conflicts,&final_conflicts],&times);
    let strips = strips(&input,&plans,&initial,&final_trajectories,&final_transits);
    for (name,lines) in [("trajectories.csv",trajectories),("conflicts.txt",conflicts),("resolutions.txt",resolutions),("sector_transits.csv",transit_csv),("sector_load.csv",load),("sector_report.txt",sector_report),("alerts.txt",alert_report),("radar.txt",radar_report),("strips.txt",strips)] {
        report::write(name,&lines);
    }
}
