mod model_io;
mod assembly;
mod solver;
mod postprocess;
mod design;
use std::collections::BTreeSet;
use std::fs;
use model_io::Model;
use assembly::{Geometry, Property};
use postprocess::Result as Analysis;
fn real_digits(value: f64, digits: usize) -> String {
    let text = format!("{:.*}", digits, value);
    if text.starts_with('-') && text.parse::<f64>().unwrap() == 0.0 {
        text[1..].to_owned()
    } else {
        text
    }
}
fn real(value: f64) -> String {
    real_digits(value, 4)
}
fn rounded(value: f64) -> f64 {
    real(value).parse().unwrap()
}
fn extreme(values: &[f64], minimum: bool) -> usize {
    let mut chosen = 0;
    for i in 1..values.len() {
        if if minimum {
            rounded(values[i]) < rounded(values[chosen])
        } else {
            rounded(values[i]) > rounded(values[chosen])
        }
        {
            chosen = i;
        }
    }
    chosen
}
fn total(values: impl IntoIterator<Item=f64>) -> f64 {
    values.into_iter().fold(0.0, |sum, value| sum+value)
}
fn verdict(value: bool, failure: &str) -> &str {
    if value {
        "ok"
    } else {
        failure
    }
}
struct System {
    properties: Vec<Property>,
    matrix: Vec<Vec<f64>>,
    free_matrix: Vec<Vec<f64>>,
    lower: Vec<Vec<f64>>,
    removed: Option<usize>
}
struct Engine<'a> {
    model: &'a Model,
    order: Vec<usize>,
    numbers: Vec<usize>,
    neighbors: Vec<BTreeSet<usize>>,
    dofs: Vec<[usize; 2]>,
    restrained: Vec<usize>,
    free: Vec<usize>,
    prescribed: Vec<f64>,
    support_directions: Vec<(usize, usize, usize)>,
    geometry: Vec<Geometry>
}
struct Final {
    choices: Vec<usize>,
    system: System,
    results: Vec<Analysis>,
    limits: Vec<f64>,
    utilizations: Vec<Vec<f64>>,
    governing: Vec<usize>,
    weight: f64,
    history: Vec<String>
}
impl<'a> Engine<'a> {
    fn new(model: &'a Model) -> Self {
        let n = model.nodes.len();
        let mut neighbors = vec![BTreeSet::new(); n];
        for m in &model.members {
            neighbors[m.start].insert(m.end);
            neighbors[m.end].insert(m.start);
        }
        let key = |v: usize| (neighbors[v].len(), model.nodes[v].id);
        let mut order = vec![(0..n).min_by_key(|&v| key(v)).unwrap()];
        let mut seen: BTreeSet<_> = order.iter().copied().collect();
        let mut cursor = 0;
        while cursor < order.len() {
            let mut next: Vec<_> = neighbors[order[cursor]].iter().copied().filter(|v| !seen.contains(v)).collect();
            next.sort_by_key(|&v| key(v));
            for v in next {
                seen.insert(v);
                order.push(v);
            }
            cursor += 1;
        }
        order.reverse();
        let mut numbers = vec![0; n];
        for (i, &v) in order.iter().enumerate() {
            numbers[v] = i;
        }
        let dofs: Vec<_> = numbers.iter().map(|&v| [2*v, 2*v+1]).collect();
        let mut prescribed = vec![0.0; 2*n];
        let mut support_directions = Vec::new();
        for support in &model.supports {
            for axis in 0..2 {
                if support.fixed[axis] {
                    let degree = dofs[support.node][axis];
                    prescribed[degree] = support.prescribed[axis];
                    support_directions.push((support.node, axis, degree));
                }
            }
        }
        let mut restrained: Vec<_> = support_directions.iter().map(|t| t.2).collect();
        restrained.sort_unstable();
        let free = (0..2*n).filter(|d| !restrained.contains(d)).collect();
        let geometry = assembly::geometry(model, &dofs);
        Self {
            model,
            order,
            numbers,
            neighbors,
            dofs,
            restrained,
            free,
            prescribed,
            support_directions,
            geometry
        }
    }
    fn metrics(&self, numbers: &[usize]) -> (usize, usize) {
        let bandwidth = self.model.members.iter().map(|m| numbers[m.start].abs_diff(numbers[m.end])).max().unwrap();
        let profile = self.neighbors.iter().enumerate().map(|(v, adjacent)| numbers[v]-adjacent.iter().map(|&u| numbers[u]).chain(std::iter::once(numbers[v])).min().unwrap()).sum();
        (bandwidth, profile)
    }
    fn system(&self, choices: &[usize], removed: Option<usize>) -> Result<System, usize> {
        let properties = assembly::properties(self.model, choices, &self.geometry);
        let matrix = assembly::matrix(&self.geometry, &properties, self.dofs.len()*2, removed);
        let free_matrix: Vec<Vec<f64>> = self.free.iter().map(|&r| self.free.iter().map(|&c| matrix[r][c]).collect()).collect();
        let lower = solver::cholesky(&free_matrix, &self.free)?;
        Ok(System {
            properties,
            matrix,
            free_matrix,
            lower,
            removed
        })
    }
    fn displacement(&self, system: &System, force: &[f64], settlement: bool) -> Vec<f64> {
        let mut displacement = vec![0.0; force.len()];
        for &r in &self.restrained {
            if settlement {
                displacement[r] = self.prescribed[r];
            }
        }
        let right: Vec<_> = self.free.iter().map(|&f| {
            let mut value = force[f];
            for &r in &self.restrained {
                value -= system.matrix[f][r]*displacement[r];
            }
            value
        }).collect();
        let solution = solver::solve(&system.lower, &right);
        for (&f, value) in self.free.iter().zip(solution) {
            displacement[f] = value;
        }
        displacement
    }
    fn analyze(&self, system: &System) -> Vec<Analysis> {
        let mut results = Vec::new();
        for case in &self.model.cases {
            let loading = assembly::loads(case, &self.geometry, &system.properties, &self.dofs, system.removed);
            let displacement = self.displacement(system, &loading.total, loading.settlement);
            let forces = postprocess::forces(&self.geometry, &system.properties, &displacement, &loading.temperature, system.removed);
            let reactions = postprocess::reactions(&system.matrix, &displacement, &loading.total, &self.restrained);
            results.push(Analysis {
                displacement,
                forces,
                reactions,
                external: loading.external
            });
        }
        for combination in &self.model.combinations {
            results.push(postprocess::superpose(&combination.terms, &results));
        }
        results
    }
    fn unit(&self, system: &System, node: usize) -> Analysis {
        let mut external = vec![0.0; 2*self.dofs.len()];
        external[self.dofs[node][1]] = -1000.0;
        let displacement = self.displacement(system, &external, false);
        let forces = postprocess::forces(&self.geometry, &system.properties, &displacement, &vec![0.0; self.geometry.len()], None);
        let reactions = postprocess::reactions(&system.matrix, &displacement, &external, &self.restrained);
        Analysis {
            displacement,
            forces,
            reactions,
            external
        }
    }
    fn magnitude(&self, result: &Analysis) -> Vec<f64> {
        self.dofs.iter().map(|a| {
            let x = result.displacement[a[0]];
            let y = result.displacement[a[1]];
            (x*x+y*y).sqrt()
        }).collect()
    }
    fn design(&self) -> Final {
        let mut choices: Vec<_> = self.model.members.iter().map(|m| m.section).collect();
        let mut history = Vec::new();
        let cases = self.model.cases.len();
        for round in 1..=10 {
            let system = self.system(&choices, None).unwrap_or_else(|_| panic!("unstable structure"));
            let results = self.analyze(&system);
            let combinations = &results[cases..];
            let limits: Vec<_> = (0..self.model.members.len()).map(|m| design::limit(m, combinations, self.model.settings.slenderness)).collect();
            let utilizations: Vec<Vec<_>> = system.properties.iter().zip(&self.geometry).enumerate().map(|(m, (p, g))| combinations.iter().map(|r| design::utilization(r.forces[m], p, g, p.area, p.inertia)).collect()).collect();
            let all: Vec<_> = utilizations.iter().flatten().copied().collect();
            let peak = extreme(&all, false);
            let member = peak/combinations.len();
            let combination = peak%combinations.len();
            let weight = total(system.properties.iter().zip(&self.geometry).map(|(p,g)| assembly::weight(p,g)));
            let mut changes = Vec::new();
            for group in 0..self.model.groups.len() {
                let members: Vec<_> = self.model.members.iter().enumerate().filter(|(_,m)| m.group == group).map(|(m,_)| m).collect();
                let selected = design::select(&members, &self.model.sections, &system.properties, &self.geometry, combinations, &limits);
                let current = choices[members[0]];
                if selected != current {
                    let values: Vec<_> = members.iter().flat_map(|&m| utilizations[m].iter().copied()).collect();
                    changes.push((group, current, selected, values[extreme(&values, false)]));
                }
            }
            history.push(format!("round {} weight {} max_utilization {} at {} {} changes {}", round, real(weight/1000.0), real(all[peak]), self.model.members[member].id, self.model.combinations[combination].name, changes.len()));
            for &(group, current, selected, value) in &changes {
                history.push(format!("change {} {} {} utilization {}", self.model.groups[group], self.model.sections[current].name, self.model.sections[selected].name, real(value)));
            }
            if changes.is_empty() || round == 10 {
                history.push(format!("result {} rounds {}", if changes.is_empty() {
                    "converged"
                } else {
                    "not_converged"
                }, round));
                let governing = utilizations.iter().map(|row| extreme(row, false)).collect();
                return Final {
                    choices,
                    system,
                    results,
                    limits,
                    utilizations,
                    governing,
                    weight,
                    history
                };
            }
            for (group, _, selected, _) in changes {
                for (m, member) in self.model.members.iter().enumerate() {
                    if member.group == group {
                        choices[m] = selected;
                    }
                }
            }
        }
        unreachable!()
    }
    fn design_report(&self, final_state: &Final) -> Vec<String> {
        let f = final_state;
        let mut lines = f.history.clone();
        let governing: Vec<_> = f.utilizations.iter().zip(&f.governing).map(|(row,&c)| row[c]).collect();
        let cases = self.model.cases.len();
        for group in 0..self.model.groups.len() {
            let members: Vec<_> = self.model.members.iter().enumerate().filter(|(_,m)| m.group == group).map(|(m,_)| m).collect();
            let values: Vec<_> = members.iter().map(|&m| governing[m]).collect();
            let member = members[extreme(&values,false)];
            lines.push(format!("group {} section {} members {} utilization {} at {}", self.model.groups[group], self.model.sections[f.choices[members[0]]].name, members.len(), real(governing[member]), self.model.members[member].id));
        }
        for (m, member) in self.model.members.iter().enumerate() {
            let p = &f.system.properties[m];
            let slenderness = design::slenderness(&self.geometry[m], p.area, p.inertia);
            lines.push(format!("member {} group {} section {} utilization {} governing {} slenderness {} limit {} {}", member.id, self.model.groups[member.group], self.model.sections[f.choices[m]].name, real(governing[m]), self.model.combinations[f.governing[m]].name, real(slenderness), real(f.limits[m]), verdict(governing[m] <= 1.0 && slenderness <= f.limits[m], "over")));
        }
        let mut ranking: Vec<_> = (0..self.model.members.len()).collect();
        ranking.sort_by(|&a,&b| rounded(governing[b]).total_cmp(&rounded(governing[a])).then(a.cmp(&b)));
        for (rank,&m) in ranking.iter().take(5).enumerate() {
            lines.push(format!("rank {} member {} utilization {}", rank+1,self.model.members[m].id,real(governing[m])));
        }
        for (m, member) in self.model.members.iter().enumerate() {
            let values: Vec<_> = f.results[cases..].iter().map(|r| r.forces[m]/1000.0).collect();
            let high = extreme(&values,false);
            let low = extreme(&values,true);
            lines.push(format!("envelope {} max {} {} min {} {}",member.id,real(values[high]),self.model.combinations[high].name,real(values[low]),self.model.combinations[low].name));
        }
        for (section, description) in self.model.sections.iter().enumerate() {
            let members: Vec<_> = f.choices.iter().enumerate().filter(|(_,s)| **s == section).map(|(m,_)| m).collect();
            if !members.is_empty() {
                lines.push(format!("section {} members {} length {}",description.name,members.len(),real(total(members.iter().map(|&m| self.geometry[m].length)))));
            }
        }
        lines.push(format!("weight {}",real(f.weight/1000.0)));
        lines
    }
    fn analysis_report(&self, f: &Final) -> Vec<String> {
        let n = self.model.nodes.len();
        let cases = self.model.cases.len();
        let combinations = &f.results[cases..];
        let before = self.metrics(&(0..n).collect::<Vec<_>>());
        let after = self.metrics(&self.numbers);
        let mut lines = vec![format!("model nodes {} members {} supports {} free_dofs {} restrained_dofs {} indeterminacy {}",n,self.model.members.len(),self.model.supports.len(),self.free.len(),self.restrained.len(),self.model.members.len() as isize+self.restrained.len() as isize-2*n as isize),format!("renumbering {}",self.order.iter().map(|&v| self.model.nodes[v].id.to_string()).collect::<Vec<_>>().join(" ")),format!("bandwidth before {} after {}",before.0,after.0),format!("profile before {} after {}",before.1,after.1)];
        for (m,g) in self.model.members.iter().zip(&self.geometry) {
            lines.push(format!("member {} nodes {} {} length {} cos {} sin {}",m.id,self.model.nodes[m.start].id,self.model.nodes[m.end].id,real(g.length),real_digits(g.cosine,6),real_digits(g.sine,6)));
        }
        for (index,result) in f.results.iter().enumerate() {
            let magnitudes = self.magnitude(result);
            let node = extreme(&magnitudes,false);
            let energy = total(result.forces.iter().zip(&self.geometry).zip(&f.system.properties).map(|((&force,g),p)| force*force*g.length/(2.0*p.young*p.area)))/1000.0;
            let rx = total(self.dofs.iter().map(|a| result.reactions[a[0]]))/1000.0;
            let ry = total(self.dofs.iter().map(|a| result.reactions[a[1]]))/1000.0;
            let fx = total(self.dofs.iter().map(|a| result.external[a[0]]))/1000.0;
            let fy = total(self.dofs.iter().map(|a| result.external[a[1]]))/1000.0;
            let scale = result.external.iter().chain(&result.reactions).map(|v| v.abs()).fold(1.0,f64::max);
            let equilibrium = postprocess::residual(result,&self.geometry) <= 0.000001*scale;
            lines.push(format!("{} {} equilibrium {} max_displacement {} at {} energy {} reactions {} {} loads {} {}",if index < cases {
                "case"
            } else {
                "combination"
            },self.model.names[index],verdict(equilibrium,"failed"),real(magnitudes[node]),self.model.nodes[node].id,real(energy),real(rx),real(ry),real(fx),real(fy)));
        }
        for &(node,axis,degree) in &self.support_directions {
            let values: Vec<_> = combinations.iter().map(|r| r.reactions[degree]/1000.0).collect();
            let high = extreme(&values,false);
            let low = extreme(&values,true);
            let mut line = format!("reaction_envelope {} {} max {} {} min {} {}",self.model.nodes[node].id,if axis == 0 {
                "x"
            } else {
                "y"
            },real(values[high]),self.model.combinations[high].name,real(values[low]),self.model.combinations[low].name);
            if axis == 1 {
                line.push_str(if values.iter().any(|&v| v < 0.0) {
                    " uplift yes"
                } else {
                    " uplift no"
                });
            }
            lines.push(line);
        }
        let magnitudes: Vec<_> = combinations.iter().map(|r| self.magnitude(r)).collect();
        for node in 0..n {
            let values: Vec<_> = magnitudes.iter().map(|m| m[node]).collect();
            let high = extreme(&values,false);
            lines.push(format!("displacement_envelope {} max {} {}",self.model.nodes[node].id,real(values[high]),self.model.combinations[high].name));
        }
        lines.extend(self.deflection_report(f));
        lines.extend(self.removal_report(f));
        lines
    }
    fn deflection_report(&self, f: &Final) -> Vec<String> {
        let (index,ratio) = self.model.settings.deflection;
        let result = &f.results[index];
        let deck = &self.model.settings.deck;
        let mut lines = Vec::new();
        let anchors: Vec<_> = deck.iter().enumerate().filter(|(_,node)| self.support_directions.iter().any(|&(v,a,_)| v == **node && a == 1)).map(|(i,_)| i).collect();
        for span in anchors.windows(2) {
            let (first,last) = (span[0],span[1]);
            let (left,right) = (deck[first],deck[last]);
            let (xa,xb) = (self.model.nodes[left].x,self.model.nodes[right].x);
            let (va,vb) = (result.displacement[self.dofs[left][1]],result.displacement[self.dofs[right][1]]);
            let interior: Vec<_> = deck[first+1..last].to_vec();
            let values: Vec<_> = interior.iter().map(|&v| (result.displacement[self.dofs[v][1]]-(va+(vb-va)*(self.model.nodes[v].x-xa)/(xb-xa))).abs()).collect();
            let chosen = extreme(&values,false);
            let node = interior[chosen];
            let limit = (xb-xa)/ratio;
            lines.push(format!("deflection {} span {} {} max {} at {} limit {} {}",self.model.names[index],self.model.nodes[left].id,self.model.nodes[right].id,real(values[chosen]),self.model.nodes[node].id,real(limit),verdict(values[chosen] <= limit,"exceeded")));
            let unit = self.unit(&f.system,node);
            let virtual_work = total((0..self.geometry.len()).map(|m| result.forces[m]*(unit.forces[m]/1000.0)*self.geometry[m].length/(f.system.properties[m].young*f.system.properties[m].area)));
            let stiffness = -result.displacement[self.dofs[node][1]];
            lines.push(format!("virtual_work {} node {} stiffness {} virtual {} {}",self.model.names[index],self.model.nodes[node].id,real(stiffness),real(virtual_work),verdict((virtual_work-stiffness).abs() <= 0.000001*1.0f64.max(stiffness.abs()),"failed")));
        }
        lines
    }
    fn removal_report(&self, f: &Final) -> Vec<String> {
        let mut lines = Vec::new();
        for removed in 0..self.model.members.len() {
            match self.system(&f.choices,Some(removed)) {
                Err(degree) => {
                    let node = self.order[degree/2];
                    lines.push(format!("removal {} unstable at {} {}",self.model.members[removed].id,self.model.nodes[node].id,if degree%2 == 0 {
                        "x"
                    } else {
                        "y"
                    }));
                }
                Ok(system) => {
                    let results = self.analyze(&system);
                    let result = &results[self.model.settings.removal];
                    let members: Vec<_> = (0..self.geometry.len()).filter(|&m| m != removed).collect();
                    let values: Vec<_> = members.iter().map(|&m| {
                        let p = &system.properties[m];
                        design::utilization(result.forces[m],p,&self.geometry[m],p.area,p.inertia)
                    }).collect();
                    let chosen = extreme(&values,false);
                    let magnitudes = self.magnitude(result);
                    let node = extreme(&magnitudes,false);
                    lines.push(format!("removal {} stable max_utilization {} at {} max_displacement {} at {}",self.model.members[removed].id,real(values[chosen]),self.model.members[members[chosen]].id,real(magnitudes[node]),self.model.nodes[node].id));
                }
            }
        }
        lines
    }
    fn ordinate(&self, values: &[f64], x: f64) -> f64 {
        let deck = &self.model.settings.deck;
        let first = self.model.nodes[deck[0]].x;
        let last = self.model.nodes[*deck.last().unwrap()].x;
        if x < first || x > last {
            return 0.0;
        }
        if x == last {
            return *values.last().unwrap();
        }
        let k = (0..deck.len()-1).find(|&i| self.model.nodes[deck[i]].x <= x && x < self.model.nodes[deck[i+1]].x).unwrap();
        let a = self.model.nodes[deck[k]].x;
        let b = self.model.nodes[deck[k+1]].x;
        values[k]+(values[k+1]-values[k])*(x-a)/(b-a)
    }
    fn vehicle_range(&self, ordinates: &[f64], positions: &[i64]) -> (f64,i64,f64,i64) {
        let values: Vec<_> = positions.iter().map(|&p| total(self.model.settings.axles.iter().map(|&(offset,load)| load*self.ordinate(ordinates,(p-offset) as f64)))).collect();
        let high = extreme(&values,false);
        let low = extreme(&values,true);
        (values[high],positions[high],values[low],positions[low])
    }
    fn influence_report(&self, f: &Final) -> Vec<String> {
        let settings = &self.model.settings;
        let units: Vec<_> = settings.deck.iter().map(|&node| self.unit(&f.system,node)).collect();
        let mut lines = Vec::new();
        let mut ranges = Vec::new();
        for &m in &settings.influence {
            let ordinates: Vec<_> = units.iter().map(|u| u.forces[m]/1000.0).collect();
            let high = extreme(&ordinates,false);
            let low = extreme(&ordinates,true);
            lines.push(format!("influence {}",self.model.members[m].id));
            for (&node,&value) in settings.deck.iter().zip(&ordinates) {
                lines.push(format!("node {} {}",self.model.nodes[node].id,real(value)));
            }
            lines.push(format!("max {} at {} min {} at {} positive {} negative {}",real(ordinates[high]),self.model.nodes[settings.deck[high]].id,real(ordinates[low]),self.model.nodes[settings.deck[low]].id,real(total(ordinates.iter().copied().filter(|&v| v > 0.0))),real(total(ordinates.iter().copied().filter(|&v| v < 0.0)))));
            let mut crossings = Vec::new();
            for k in 0..ordinates.len()-1 {
                let (a,b) = (ordinates[k],ordinates[k+1]);
                if (a > 0.0 && b < 0.0) || (a < 0.0 && b > 0.0) {
                    let x = self.model.nodes[settings.deck[k]].x;
                    let y = self.model.nodes[settings.deck[k+1]].x;
                    crossings.push(real_digits(x+(y-x)*a/(a-b),1));
                }
            }
            lines.push(format!("crossings {}{}",crossings.len(),if crossings.is_empty() {
                String::new()
            } else {
                format!(" {}",crossings.join(" "))
            }));
        }
        let mut positions = Vec::new();
        let mut position = self.model.nodes[settings.deck[0]].x as i64;
        let end = self.model.nodes[*settings.deck.last().unwrap()].x as i64+settings.axles.last().unwrap().0;
        while position <= end {
            positions.push(position);
            position += settings.step;
        }
        lines.push(format!("vehicle axles {} positions {}",settings.axles.len(),positions.len()));
        for m in 0..self.model.members.len() {
            let ordinates: Vec<_> = units.iter().map(|u| u.forces[m]/1000.0).collect();
            let range = self.vehicle_range(&ordinates,&positions);
            ranges.push(range);
            lines.push(format!("vehicle_member {} max {} at {} min {} at {}",self.model.members[m].id,real(range.0),range.1,real(range.2),range.3));
        }
        for &(node,axis,degree) in &self.support_directions {
            let ordinates: Vec<_> = units.iter().map(|u| u.reactions[degree]/1000.0).collect();
            let range = self.vehicle_range(&ordinates,&positions);
            lines.push(format!("vehicle_reaction {} {} max {} at {} min {} at {}",self.model.nodes[node].id,if axis == 0 {
                "x"
            } else {
                "y"
            },real(range.0),range.1,real(range.2),range.3));
        }
        let (dead_index,dead_factor,live_factor) = settings.rating;
        let mut ratings = Vec::new();
        for (m,member) in self.model.members.iter().enumerate() {
            let p = &f.system.properties[m];
            let dead = f.results[dead_index].forces[m]/1000.0;
            let pt = p.area*p.yield_stress/1000.0;
            let pc = (p.area*p.yield_stress).min(design::buckling(p,&self.geometry[m],p.inertia))/1000.0;
            let (high,_,low,_) = ranges[m];
            let mut tension = "none".to_owned();
            let mut compression = tension.clone();
            if rounded(high) > 0.0 {
                let value = (pt-dead_factor*dead)/(live_factor*high);
                tension = real(value);
                ratings.push((value,m,"tension"));
            }
            if rounded(low) < 0.0 {
                let value = (pc+dead_factor*dead)/(live_factor*(-low));
                compression = real(value);
                ratings.push((value,m,"compression"));
            }
            lines.push(format!("rating {} tension {} compression {}",member.id,tension,compression));
        }
        let values: Vec<_> = ratings.iter().map(|r| r.0).collect();
        let rating = ratings[extreme(&values,true)];
        lines.push(format!("rating_min {} at {} {}",real(rating.0),self.model.members[rating.1].id,rating.2));
        lines
    }
    fn vibration_report(&self, f: &Final) -> Vec<String> {
        let (index,count,iterations) = self.model.settings.vibration;
        let masses: Vec<_> = self.dofs.iter().map(|d| -f.results[index].external[d[1]]/9.81).collect();
        let free_masses: Vec<_> = self.free.iter().map(|&d| masses[self.order[d/2]]).collect();
        let n = self.free.len();
        let mut modes: Vec<Vec<f64>> = Vec::new();
        let mut lines = vec![format!("vibration {} mass {} iterations {}",self.model.names[index],real(total(masses.iter().copied())),iterations)];
        for mode in 1..=count {
            let mut vector = vec![1.0; n];
            for _ in 0..iterations {
                for previous in &modes {
                    let beta = total((0..n).map(|i| previous[i]*free_masses[i]*vector[i]));
                    for i in 0..n {
                        vector[i] -= beta*previous[i];
                    }
                }
                let right: Vec<_> = (0..n).map(|i| free_masses[i]*vector[i]).collect();
                let solution = solver::solve(&f.system.lower,&right);
                let norm = total((0..n).map(|i| free_masses[i]*solution[i]*solution[i])).sqrt();
                vector = solution.iter().map(|&v| v/norm).collect();
            }
            let product: Vec<_> = (0..n).map(|i| total((0..n).map(|j| f.system.free_matrix[i][j]*vector[j]))).collect();
            let lambda = total((0..n).map(|i| vector[i]*product[i]))/total((0..n).map(|i| free_masses[i]*vector[i]*vector[i]));
            let frequency = (1000.0*lambda).sqrt()/(2.0*design::PI);
            lines.push(format!("mode {} frequency {} period {}",mode,real(frequency),real(1.0/frequency)));
            let peak = (0..n).max_by(|&a,&b| vector[a].abs().total_cmp(&vector[b].abs())).unwrap();
            let mut normalized = vec![0.0; 2*self.dofs.len()];
            for (i,&degree) in self.free.iter().enumerate() {
                normalized[degree] = vector[i]/vector[peak];
            }
            for (node,dofs) in self.model.nodes.iter().zip(&self.dofs) {
                lines.push(format!("node {} {} {}",node.id,real(normalized[dofs[0]]),real(normalized[dofs[1]])));
            }
            modes.push(vector);
        }
        lines
    }
    fn drawing_report(&self, f: &Final) -> Vec<String> {
        let mut lines = Vec::new();
        for &(result,magnification,wc,hc) in &self.model.settings.drawings {
            let mut canvas = Canvas::new(self.model,wc,hc);
            let original: Vec<_> = self.model.nodes.iter().map(|n| canvas.position(n.x,n.y)).collect();
            let deformed: Vec<_> = self.model.nodes.iter().zip(&self.dofs).map(|(n,d)| canvas.position(n.x+magnification*f.results[result].displacement[d[0]],n.y+magnification*f.results[result].displacement[d[1]])).collect();
            for m in &self.model.members {
                canvas.line(original[m.start],original[m.end],b'.');
            }
            for &position in &original {
                canvas.put(position,b'+');
            }
            for m in &self.model.members {
                canvas.line(deformed[m.start],deformed[m.end],b'*');
            }
            for &position in &deformed {
                canvas.put(position,b'o');
            }
            lines.push(format!("drawing {} magnification {} columns {} rows {}",self.model.names[result],magnification as usize,canvas.width,canvas.height));
            lines.extend(canvas.framed());
        }
        let mut canvas = Canvas::new(self.model,self.model.settings.map.0,self.model.settings.map.1);
        let positions: Vec<_> = self.model.nodes.iter().map(|n| canvas.position(n.x,n.y)).collect();
        for (i,m) in self.model.members.iter().enumerate() {
            let value = f.utilizations[i][f.governing[i]];
            canvas.line(positions[m.start],positions[m.end],if value >= 1.0 {
                b'#'
            } else {
                b'0'+(10.0*value).floor() as u8
            });
        }
        for position in positions {
            canvas.put(position,b'o');
        }
        lines.push(format!("utilization_map columns {} rows {}",canvas.width,canvas.height));
        lines.extend(canvas.framed());
        lines
    }
    fn csv_reports(&self, f: &Final) -> (Vec<String>,Vec<String>,Vec<String>) {
        let mut displacements = vec!["case,node,dx,dy".to_owned()];
        let mut forces = vec!["case,member,force,stress,utilization".to_owned()];
        let mut reactions = vec!["case,node,rx,ry".to_owned()];
        for (i,result) in f.results.iter().enumerate() {
            let name = &self.model.names[i];
            for (node,d) in self.model.nodes.iter().zip(&self.dofs) {
                displacements.push(format!("{},{},{},{}",name,node.id,real(result.displacement[d[0]]),real(result.displacement[d[1]])));
            }
            for (m,member) in self.model.members.iter().enumerate() {
                let p = &f.system.properties[m];
                let force = result.forces[m];
                forces.push(format!("{},{},{},{},{}",name,member.id,real(force/1000.0),real(force/p.area),real(design::utilization(force,p,&self.geometry[m],p.area,p.inertia))));
            }
            for support in &self.model.supports {
                let d = self.dofs[support.node];
                reactions.push(format!("{},{},{},{}",name,self.model.nodes[support.node].id,real(result.reactions[d[0]]/1000.0),real(result.reactions[d[1]]/1000.0)));
            }
        }
        (displacements,forces,reactions)
    }
}
struct Canvas {
    x0: f64,
    y1: f64,
    wc: f64,
    hc: f64,
    width: usize,
    height: usize,
    grid: Vec<Vec<u8>>
}
impl Canvas {
    fn new(model: &Model, wc: f64, hc: f64) -> Self {
        let x0 = model.nodes.iter().map(|n| n.x).fold(f64::INFINITY,f64::min);
        let x1 = model.nodes.iter().map(|n| n.x).fold(f64::NEG_INFINITY,f64::max);
        let y0 = model.nodes.iter().map(|n| n.y).fold(f64::INFINITY,f64::min);
        let y1 = model.nodes.iter().map(|n| n.y).fold(f64::NEG_INFINITY,f64::max);
        let width = ((x1-x0)/wc+0.5).floor() as usize+5;
        let height = ((y1-y0)/hc+0.5).floor() as usize+5;
        Self {
            x0,
            y1,
            wc,
            hc,
            width,
            height,
            grid: vec![vec![b' '; width]; height]
        }
    }
    fn position(&self, x: f64, y: f64) -> (i64,i64) {
        (((x-self.x0)/self.wc+0.5).floor() as i64+2,((self.y1-y)/self.hc+0.5).floor() as i64+2)
    }
    fn put(&mut self, (c,r): (i64,i64), character: u8) {
        if c >= 0 && r >= 0 && c < self.width as i64 && r < self.height as i64 {
            self.grid[r as usize][c as usize] = character;
        }
    }
    fn line(&mut self, first: (i64,i64), last: (i64,i64), character: u8) {
        let (mut c,mut r) = first;
        let dc = (last.0-c).abs();
        let dr = -(last.1-r).abs();
        let sc = if c < last.0 {
            1
        } else {
            -1
        };
        let sr = if r < last.1 {
            1
        } else {
            -1
        };
        let mut error = dc+dr;
        loop {
            self.put((c,r),character);
            if (c,r) == last {
                break;
            }
            let twice = 2*error;
            if twice >= dr {
                error += dr;
                c += sc;
            }
            if twice <= dc {
                error += dc;
                r += sr;
            }
        }
    }
    fn framed(&self) -> Vec<String> {
        let border = format!("+{}+","-".repeat(self.width));
        let mut lines = vec![border.clone()];
        for row in &self.grid {
            lines.push(format!("|{}|",String::from_utf8(row.clone()).unwrap()));
        }
        lines.push(border);
        lines
    }
}
fn main() {
    let model = model_io::read();
    let engine = Engine::new(&model);
    let final_state = engine.design();
    let (displacements,forces,reactions) = engine.csv_reports(&final_state);
    let outputs = [("analysis.txt",engine.analysis_report(&final_state)),("displacements.csv",displacements),("member_forces.csv",forces),("reactions.csv",reactions),("design.txt",engine.design_report(&final_state)),("influence.txt",engine.influence_report(&final_state)),("drawing.txt",engine.drawing_report(&final_state)),("vibration.txt",engine.vibration_report(&final_state))];
    fs::create_dir_all("output").unwrap();
    for (name,lines) in outputs {
        fs::write(format!("output/{}",name),lines.join("\n")+"\n").unwrap();
    }
}
