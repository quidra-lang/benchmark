mod mesh;
mod materials;
mod transient;
mod steady;
mod report;

use std::fs;
use mesh::{Face, Mesh, Plate};
use report::{real, time};

struct Segment {
    name: String,
    edge: String,
    kind: String,
    faces: Vec<(usize, usize)>,
    h: f64,
    theta: f64,
}

struct Source {
    name: String,
    cells: Vec<usize>,
    power: f64,
    periods: Vec<(i64, i64)>,
}

impl Source {
    fn active(&self, time: i64) -> bool { self.periods.iter().any(|&(a, b)| a <= time && time < b) }
    fn duty(&self, end: i64) -> f64 {
        self.periods.iter().map(|&(a, b)| b.min(end)-a.min(end)).sum::<i64>() as f64 / end as f64
    }
}

struct Run { name: String, method: String, step: i64 }
struct Probe { name: String, cell: usize }

struct Params {
    initial: f64,
    end: i64,
    snapshots: Vec<i64>,
    every: i64,
    probes: Vec<Probe>,
    runs: Vec<Run>,
    reference: String,
    eps: f64,
    iterations: usize,
    omega: f64,
    bands: Vec<f64>,
    alarm: f64,
    limit: f64,
}

impl Params {
    fn read(mesh: &Mesh) -> Self {
        let mut p = Self { initial: 0.0, end: 0, snapshots: Vec::new(), every: 0, probes: Vec::new(),
            runs: Vec::new(), reference: String::new(), eps: 0.0, iterations: 0, omega: 0.0,
            bands: Vec::new(), alarm: 0.0, limit: 0.0 };
        for line in fs::read_to_string("input/params.txt").unwrap().lines() {
            let w: Vec<_> = line.split_whitespace().collect();
            match w[0] {
                "initial" => p.initial = w[1].parse().unwrap(),
                "end_time" => p.end = w[1].parse().unwrap(),
                "snapshots" => p.snapshots = w[1..].iter().map(|v| v.parse().unwrap()).collect(),
                "probe_every" => p.every = w[1].parse().unwrap(),
                "probe" => p.probes.push(Probe { name: w[1].to_owned(), cell: w[2].parse::<usize>().unwrap()*mesh.width+w[3].parse::<usize>().unwrap() }),
                "run" => p.runs.push(Run { name: w[1].to_owned(), method: w[2].to_owned(), step: w[3].parse().unwrap() }),
                "reference" => p.reference = w[1].to_owned(),
                "tolerance" => p.eps = w[1].parse().unwrap(),
                "max_iterations" => p.iterations = w[1].parse().unwrap(),
                "omega" => p.omega = w[1].parse().unwrap(),
                "bands" => p.bands = w[1..].iter().map(|v| v.parse().unwrap()).collect(),
                "alarm" => p.alarm = w[1].parse().unwrap(),
                _ => p.limit = w[1].parse().unwrap(),
            }
        }
        p
    }
}

fn boundary(mesh: &Mesh) -> (Vec<Segment>, Vec<Source>) {
    let mut segments = Vec::new();
    let mut sources = Vec::new();
    for line in fs::read_to_string("input/boundary.txt").unwrap().lines() {
        let w: Vec<_> = line.split_whitespace().collect();
        if w[0] == "segment" {
            let kind = w[5];
            segments.push(Segment { name: w[1].to_owned(), edge: w[2].to_owned(), kind: kind.to_owned(),
                faces: mesh.segment(w[2], w[3].parse().unwrap(), w[4].parse().unwrap()),
                h: if kind == "convective" { w[6].parse().unwrap() } else { 0.0 },
                theta: if kind == "insulated" { 0.0 } else { w[if kind == "fixed" { 6 } else { 7 }].parse().unwrap() } });
        } else {
            sources.push(Source { name: w[1].to_owned(),
                cells: mesh.rectangle(w[2].parse().unwrap(), w[3].parse().unwrap(), w[4].parse().unwrap(), w[5].parse().unwrap()),
                power: w[6].parse().unwrap(), periods: w[7..].chunks(2).map(|v| (v[0].parse().unwrap(), v[1].parse().unwrap())).collect() });
        }
    }
    (segments, sources)
}

fn build(mesh: &Mesh, materials: &[materials::Material], segments: &[Segment]) -> (Plate, Vec<usize>) {
    let which: Vec<_> = mesh.codes.iter().map(|c| materials.iter().position(|m| m.code == *c).unwrap()).collect();
    let capacity = which.iter().map(|&m| materials::capacity(&materials[m], mesh.dx, mesh.thickness)).collect();
    let mut faces: Vec<[Face; 4]> = (0..mesh.codes.len()).map(|p| mesh.neighbors(p).map(|q| Face {
        neighbor: q, conductance: q.map_or(0.0, |q| materials::interior(materials[which[p]].k,
            materials[which[q]].k, mesh.thickness)), outside: None,
    })).collect();
    for segment in segments {
        for &(p, f) in &segment.faces {
            let k = materials[which[p]].k;
            faces[p][f].conductance = match segment.kind.as_str() {
                "fixed" => materials::fixed(k, mesh.thickness),
                "convective" => materials::convective(k, segment.h, mesh.dx, mesh.thickness),
                _ => 0.0,
            };
            if segment.kind != "insulated" { faces[p][f].outside = Some(segment.theta); }
        }
    }
    let diagonal = faces.iter().map(|f| f.iter().map(|f| f.conductance).sum()).collect();
    (Plate { faces, capacity, diagonal }, which)
}

fn source_field(sources: &[Source], n: usize, time: Option<i64>) -> (Vec<f64>, f64) {
    let mut field = vec![0.0; n];
    let mut power = 0.0;
    for source in sources {
        if time.map_or(false, |t| !source.active(t)) { continue; }
        let w = source.power / source.cells.len() as f64;
        for &p in &source.cells { field[p] += w; }
        power += source.power;
    }
    (field, power)
}

fn segment_flow(segment: &Segment, plate: &Plate, field: &[f64], unit: bool) -> f64 {
    if segment.kind == "insulated" { return 0.0; }
    let mut sum = 0.0;
    for &(p, f) in &segment.faces {
        let face = plate.faces[p][f];
        sum += face.conductance * if unit { field[p] } else { face.outside.unwrap() - field[p] };
    }
    sum
}

fn stored(plate: &Plate, field: &[f64], initial: f64) -> f64 {
    field.iter().enumerate().map(|(p, &v)| plate.capacity[p] * (v-initial)).sum()
}

struct ResultRun {
    status: &'static str,
    fields: Vec<Vec<f64>>,
    energies: Vec<(f64, f64, f64)>,
    segments: Vec<f64>,
    peak: (f64, i64, usize),
    alarm: Option<(i64, usize)>,
    above: i64,
}

fn simulate(run: &Run, params: &Params, mesh: &Mesh, plate: &Plate, segments: &[Segment], sources: &[Source], max_dt: f64) -> ResultRun {
    let mut result = ResultRun { status: "accepted", fields: Vec::new(), energies: Vec::new(),
        segments: vec![0.0; segments.len()], peak: (params.initial, 0, 0), alarm: None, above: 0 };
    let mut times = vec![params.end, params.every];
    times.extend_from_slice(&params.snapshots);
    for source in sources { for &(a, b) in &source.periods { times.push(a); times.push(b); } }
    if times.iter().any(|t| t % run.step != 0) { result.status = "step"; return result; }
    let dt = run.step as f64 / 1000.0;
    if run.method == "ftcs" && dt > max_dt { result.status = "unstable"; return result; }
    let mut field = vec![params.initial; mesh.codes.len()];
    let mut generated = 0.0;
    for step in 0..=params.end/run.step {
        let t = step * run.step;
        let hot = report::hottest(&field);
        if field[hot] > result.peak.0 { result.peak = (field[hot], t, hot); }
        if field[hot] >= params.alarm {
            if result.alarm.is_none() { result.alarm = Some((t, hot)); }
            if step > 0 { result.above += run.step; }
        }
        result.energies.push((stored(plate, &field, params.initial), result.segments.iter().sum(), generated));
        result.fields.push(field.clone());
        if t == params.end { break; }
        let (source, power) = source_field(sources, mesh.codes.len(), Some(t));
        let (next, intermediate) = transient::step(mesh, plate, &run.method, dt, &field, &source);
        let average: Vec<_> = field.iter().zip(&next).map(|(a, b)| (a+b)/2.0).collect();
        for (j, segment) in segments.iter().enumerate() {
            let horizontal = segment.edge == "left" || segment.edge == "right";
            let x = match run.method.as_str() {
                "ftcs" => &field,
                "backward_euler" => if horizontal { &intermediate } else { &next },
                _ => if horizontal { &intermediate } else { &average },
            };
            result.segments[j] += dt * segment_flow(segment, plate, x, false);
        }
        generated += dt * power;
        field = next;
    }
    result
}

fn max_diff(a: &[f64], b: &[f64]) -> f64 { a.iter().zip(b).map(|(x, y)| (x-y).abs()).fold(0.0, f64::max) }
fn verdict(value: bool) -> &'static str { if value { "ok" } else { "failed" } }

fn main() {
    let mesh = Mesh::read();
    let materials = materials::read();
    let params = Params::read(&mesh);
    let (segments, sources) = boundary(&mesh);
    let (plate, which) = build(&mesh, &materials, &segments);
    let n = mesh.codes.len();
    let (all, total_power) = source_field(&sources, n, None);
    let beta: Vec<_> = plate.faces.iter().map(|faces| {
        let mut value = 0.0;
        for f in faces { if let Some(theta) = f.outside { value += f.conductance * theta; } }
        value
    }).collect();
    let rhs: Vec<_> = beta.iter().zip(&all).map(|(a, b)| a+b).collect();
    let mut vectors = vec![rhs.clone(), beta];
    for source in &sources {
        let mut unit = vec![0.0; n];
        for &p in &source.cells { unit[p] = 1.0/source.cells.len() as f64; }
        vectors.push(unit);
    }
    let direct = steady::direct(&plate, mesh.width, vectors);
    let (temperature, base) = (&direct[0], &direct[1]);
    let jacobi = steady::iterate(&plate, &all, params.initial, params.eps, params.iterations, "jacobi", params.omega);
    let k = jacobi.deltas.len();
    let rho = (jacobi.deltas[k-1]/jacobi.deltas[k-3]).sqrt();
    let omega = 2.0/(1.0+(1.0-rho*rho).sqrt());
    let solvers = vec![jacobi,
        steady::iterate(&plate, &all, params.initial, params.eps, params.iterations, "gauss_seidel", params.omega),
        steady::iterate(&plate, &all, params.initial, params.eps, params.iterations, "sor", params.omega),
        steady::iterate(&plate, &all, params.initial, params.eps, params.iterations, "sor_estimated", omega)];
    let solver_names = ["jacobi", "gauss_seidel", "sor", "sor_estimated"];
    let max_dt = plate.capacity.iter().zip(&plate.diagonal).map(|(c, a)| c/a).fold(f64::INFINITY, f64::min);
    let results: Vec<_> = params.runs.iter().map(|run| simulate(run, &params, &mesh, &plate, &segments, &sources, max_dt)).collect();
    let reference = params.runs.iter().position(|r| r.name == params.reference).unwrap();
    let mut snapshots = Vec::new();
    let mut probes = vec!["run,time,probe,temperature".to_owned()];
    let mut comparison = vec![format!("ftcs_max_dt {}", real(max_dt, 4))];
    for (i, run) in params.runs.iter().enumerate() {
        let result = &results[i];
        let prefix = format!("run {} {} dt {}", run.name, run.method, time(run.step));
        if result.status != "accepted" {
            comparison.push(format!("{} rejected {}", prefix, result.status));
            snapshots.push(if result.status == "unstable" { format!("{} rejected unstable max_dt {}", prefix, real(max_dt, 4)) }
                else { format!("{} rejected step", prefix) });
            continue;
        }
        for &t in &params.snapshots {
            let field = &result.fields[(t/run.step) as usize];
            snapshots.push(format!("{} time {} {}", prefix, time(t), report::summary(&mesh, field)));
            snapshots.extend(report::field(&mesh, field));
        }
        for (step, field) in result.fields.iter().enumerate() {
            let t = step as i64 * run.step;
            if t % params.every != 0 { continue; }
            for probe in &params.probes { probes.push(format!("{},{},{},{}", run.name, time(t), probe.name, real(field[probe.cell], 3))); }
        }
        let alarm = result.alarm.map_or_else(|| "never".to_owned(), |(t, p)| format!("{} at {}", time(t), mesh.cell(p)));
        comparison.push(format!("{} steps {} peak {} time {} at {} alarm {} above {}", prefix, params.end/run.step,
            real(result.peak.0, 2), time(result.peak.1), mesh.cell(result.peak.2), alarm, time(result.above)));
        let &(u, b, q) = result.energies.last().unwrap();
        comparison.push(format!("energy {} stored {} boundary {} source {} balance {}", run.name,
            real(u, 2), real(b, 2), real(q, 2), verdict((u-b-q).abs() <= 0.000001*(u.abs()+b.abs()+q.abs()))));
        for &t in &params.snapshots {
            let (u, b, q) = result.energies[(t/run.step) as usize];
            comparison.push(format!("energy_at {} time {} stored {} boundary {} source {}", run.name, time(t), real(u, 2), real(b, 2), real(q, 2)));
        }
        let final_field = result.fields.last().unwrap();
        for (m, material) in materials.iter().enumerate() {
            let energy: f64 = (0..n).filter(|&p| which[p] == m).map(|p| plate.capacity[p]*(final_field[p]-params.initial)).sum();
            comparison.push(format!("energy_material {} {} {}", run.name, material.code as char, real(energy, 2)));
        }
        for (j, segment) in segments.iter().enumerate() {
            comparison.push(format!("energy_segment {} {} {}", run.name, segment.name, real(result.segments[j], 2)));
        }
        for probe in &params.probes {
            let (mut maximum, mut minimum) = ((f64::NEG_INFINITY, 0), (f64::INFINITY, 0));
            for (step, field) in result.fields.iter().enumerate() {
                let t = step as i64 * run.step;
                if t % params.every != 0 { continue; }
                let value = field[probe.cell];
                if value > maximum.0 { maximum = (value, t); }
                if value < minimum.0 { minimum = (value, t); }
            }
            comparison.push(format!("probe_summary {} {} max {} time {} min {} time {}", run.name, probe.name,
                real(maximum.0, 3), time(maximum.1), real(minimum.0, 3), time(minimum.1)));
        }
        if i != reference {
            for &t in &params.snapshots {
                let a = &result.fields[(t/run.step) as usize];
                let b = &results[reference].fields[(t/params.runs[reference].step) as usize];
                let rms = (a.iter().zip(b).map(|(x, y)| { let e = (x-y).abs(); e*e }).sum::<f64>()/n as f64).sqrt();
                comparison.push(format!("compare {} {} time {} max_diff {} rms_diff {}", run.name, params.reference,
                    time(t), real(max_diff(a, b), 6), real(rms, 6)));
            }
        }
        comparison.push(format!("final {} steady_max_diff {}", run.name, real(max_diff(final_field, temperature), 6)));
    }
    let mut lines = vec![format!("steady {}", report::summary(&mesh, temperature))];
    lines.extend(report::field(&mesh, temperature));
    for (m, material) in materials.iter().enumerate() {
        let values: Vec<_> = (0..n).filter(|&p| which[p] == m).map(|p| temperature[p]).collect();
        lines.push(format!("material {} {} cells {} min {} max {} mean {}", material.code as char, material.name,
            values.len(), real(values.iter().copied().fold(f64::INFINITY, f64::min), 2),
            real(values.iter().copied().fold(f64::NEG_INFINITY, f64::max), 2), real(values.iter().sum::<f64>()/values.len() as f64, 2)));
    }
    for source in &sources {
        let mean = source.cells.iter().map(|&p| temperature[p]).sum::<f64>()/source.cells.len() as f64;
        let maximum = source.cells.iter().map(|&p| temperature[p]).fold(f64::NEG_INFINITY, f64::max);
        lines.push(format!("source {} power {} duty {} mean {} max {}", source.name, real(source.power, 4),
            real(source.duty(params.end), 4), real(mean, 2), real(maximum, 2)));
    }
    for source in &sources {
        for (s, other) in sources.iter().enumerate() {
            let influence = source.cells.iter().map(|&p| direct[s+2][p]).sum::<f64>()/source.cells.len() as f64;
            lines.push(format!("influence {} {} {}", source.name, other.name, real(influence, 4)));
        }
    }
    let mut superposition = base.clone();
    let mut duty = base.clone();
    for (s, source) in sources.iter().enumerate() {
        for p in 0..n {
            superposition[p] += source.power*direct[s+2][p];
            duty[p] += (source.duty(params.end)*source.power)*direct[s+2][p];
        }
    }
    lines.push(format!("superposition {}", verdict(max_diff(&superposition, temperature) <= 0.000001)));
    for (s, source) in sources.iter().enumerate() {
        for segment in &segments {
            lines.push(format!("path {} {} {}", source.name, segment.name, real(segment_flow(segment, &plate, &direct[s+2], true), 4)));
        }
    }
    lines.push(format!("duty_steady {}", report::summary(&mesh, &duty)));
    for (s, source) in sources.iter().enumerate() {
        let mut best = (f64::INFINITY, 0);
        for p in 0..n {
            let value = (params.limit-(temperature[p]-source.power*direct[s+2][p]))/direct[s+2][p];
            if value < best.0 { best = (value, p); }
        }
        lines.push(format!("headroom {} max_power {} at {}", source.name, real(best.0, 4), mesh.cell(best.1)));
    }
    let mut interfaces = vec![vec![(0usize, 0.0, 0.0); materials.len()]; materials.len()];
    let mut gradient = (f64::NEG_INFINITY, 0, 0);
    for p in 0..n {
        for f in [1, 3] {
            if let Some(q) = plate.faces[p][f].neighbor {
                let value = (temperature[p]-temperature[q]).abs()/mesh.dx;
                if value > gradient.0 { gradient = (value, p, q); }
                if which[p] == which[q] { continue; }
                let (a, b) = (which[p].min(which[q]), which[p].max(which[q]));
                let mut flow = plate.faces[p][f].conductance*(temperature[p]-temperature[q]);
                if which[p] > which[q] { flow = -flow; }
                let entry = &mut interfaces[a][b];
                entry.0 += 1;
                if flow > 0.0 { entry.1 += flow; } else if flow < 0.0 { entry.2 += -flow; }
            }
        }
    }
    for a in 0..materials.len() { for b in a+1..materials.len() {
        let (count, forward, backward) = interfaces[a][b];
        if count > 0 { lines.push(format!("interface {} {} faces {} forward {} backward {}", materials[a].code as char,
            materials[b].code as char, count, real(forward, 4), real(backward, 4))); }
    } }
    let mut flows = Vec::new();
    for segment in &segments {
        let flow = segment_flow(segment, &plate, temperature, false);
        flows.push(flow);
        lines.push(format!("segment {} {} {} flow {}", segment.name, segment.edge, segment.kind, real(flow, 4)));
    }
    lines.push(format!("sources {}", real(total_power, 4)));
    lines.push(format!("balance {}", verdict((flows.iter().sum::<f64>()+total_power).abs()
        <= 0.000001*(flows.iter().map(|v| v.abs()).sum::<f64>()+total_power))));
    lines.push(format!("max_gradient {} between {} and {}", real(gradient.0, 2), mesh.cell(gradient.1), mesh.cell(gradient.2)));
    comparison.push(format!("steady direct max_residual {}", real(steady::residual(&plate, &rhs, temperature), 6)));
    for (i, solver) in solvers.iter().enumerate() {
        let k = solver.deltas.len();
        let rate = (solver.deltas[k-1]/solver.deltas[k-3]).sqrt();
        let milestones: Vec<_> = [1000.0, 100.0, 10.0, 1.0].iter().map(|factor|
            solver.deltas.iter().position(|&d| d < params.eps*factor).map_or_else(|| "never".to_owned(), |k| (k+1).to_string())).collect();
        let omega_text = if i >= 2 { format!(" omega {}", real(if i == 2 { params.omega } else { omega }, 4)) } else { String::new() };
        lines.push(format!("solver {}{} iterations {} converged {} rate {} milestones {}", solver_names[i], omega_text,
            k, if solver.converged { "yes" } else { "no" }, real(rate, 6), milestones.join(" ")));
        comparison.push(format!("steady {} iterations {} max_diff {} max_residual {}", solver_names[i], k,
            real(max_diff(&solver.field, temperature), 6), real(steady::residual(&plate, &rhs, &solver.field), 6)));
    }
    comparison.push(format!("jacobi_spectral_radius {} squared {}", real(rho, 6), real(rho*rho, 6)));
    comparison.push(format!("omega_estimated {}", real(omega, 4)));
    let (counts, map) = report::isotherms(&mesh, temperature, &params.bands);
    let mut isotherms = vec![format!("isotherms steady counts {}", counts)];
    isotherms.extend(map);
    for &t in &params.snapshots {
        let field = &results[reference].fields[(t/params.runs[reference].step) as usize];
        let (counts, map) = report::isotherms(&mesh, field, &params.bands);
        isotherms.push(format!("isotherms {} time {} counts {}", params.reference, time(t), counts));
        isotherms.extend(map);
    }
    for (file, output) in [("snapshots.txt", snapshots), ("probes.csv", probes), ("steady_state.txt", lines),
        ("solver_comparison.txt", comparison), ("isotherms.txt", isotherms)] { report::write(file, &output); }
}
