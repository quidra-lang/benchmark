mod fixed_point;
mod vector3;
mod scene;
mod intersect;
mod shading;

use fixed_point::{floor, mul, S};
use vector3::{Vector, add, subtract, negate, dot, scale, length, normalize, text};
use scene::{Scene, Color, LightKind};
use intersect::{Ray, Hit};
use std::{collections::BTreeSet, fs, io};

const KINDS: [&str; 4] = ["primary", "reflection", "refraction", "shadow"];

struct Settings {
    width: usize,
    height: usize,
    contrast: i64,
    depth: usize,
    far: i64,
    epsilon: i64,
    margin: i64,
}

fn read_settings() -> io::Result<Settings> {
    let content = fs::read_to_string("input/render.txt")?;
    let q: Vec<Vec<i64>> = content.lines().map(|s| s.split_whitespace().skip(1).map(|s| s.parse().unwrap()).collect()).collect();
    Ok(Settings { width: q[0][0] as usize, height: q[0][1] as usize, contrast: q[1][0], depth: q[2][0] as usize, far: q[3][0], epsilon: q[4][0], margin: q[5][0] })
}

#[derive(Clone)]
struct Node {
    lo: Vector,
    hi: Vector,
    objects: Vec<usize>,
    children: Option<(usize, usize)>,
    depth: usize,
}

fn union(group: &[usize], bounds: &[Option<(Vector, Vector)>]) -> (Vector, Vector) {
    let (mut lo, mut hi) = bounds[group[0]].unwrap();
    for &i in &group[1..] {
        let (a, b) = bounds[i].unwrap();
        for axis in 0..3 { lo[axis] = lo[axis].min(a[axis]); hi[axis] = hi[axis].max(b[axis]); }
    }
    (lo, hi)
}

fn area(group: &[usize], bounds: &[Option<(Vector, Vector)>]) -> i64 {
    let (lo, hi) = union(group, bounds);
    let (x, y, z) = (hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2]);
    x * y + y * z + z * x
}

fn build(mut group: Vec<usize>, depth: usize, bounds: &[Option<(Vector, Vector)>], nodes: &mut Vec<Node>) -> usize {
    let (lo, hi) = union(&group, bounds);
    let index = nodes.len();
    nodes.push(Node { lo, hi, objects: Vec::new(), children: None, depth });
    if group.len() <= 2 {
        group.sort();
        nodes[index].objects = group;
    } else {
        let mut best: Option<(i64, Vec<usize>, usize)> = None;
        for axis in 0..3 {
            let mut sorted = group.clone();
            sorted.sort_by_key(|&i| { let (lo, hi) = bounds[i].unwrap(); (floor(lo[axis] + hi[axis], 2), i) });
            for split in 1..sorted.len() {
                let cost = area(&sorted[..split], bounds) * split as i64 + area(&sorted[split..], bounds) * (sorted.len() - split) as i64;
                if best.as_ref().map_or(true, |b| cost < b.0) { best = Some((cost, sorted.clone(), split)); }
            }
        }
        let (_, sorted, split) = best.unwrap();
        let left = build(sorted[..split].to_vec(), depth + 1, bounds, nodes);
        let right = build(sorted[split..].to_vec(), depth + 1, bounds, nodes);
        nodes[index].children = Some((left, right));
    }
    index
}

#[derive(Default)]
struct LightStats {
    shadows: i64,
    blocked: i64,
    attenuated: i64,
    backfacing: i64,
    outside: i64,
}

struct Statistics {
    rays: [i64; 4],
    misses: [i64; 3],
    depth: Vec<i64>,
    tests: [[i64; 2]; 4],
    visits: Vec<i64>,
    primary: Vec<i64>,
    secondary: Vec<i64>,
    occlusions: Vec<i64>,
    lights: Vec<LightStats>,
    total_internal: i64,
    clamped: i64,
}

struct Sample {
    direction: Vector,
    distance: i64,
    intensity: i64,
}

fn samples(scene: &Scene, light: usize, point: Vector, far: i64) -> Vec<Sample> {
    let light = &scene.lights[light];
    if let LightKind::Sun(direction) = light.kind { return vec![Sample { direction, distance: far, intensity: light.intensity }]; }
    let mut positions = Vec::new();
    match light.kind {
        LightKind::Point(position) | LightKind::Spot { position, .. } => positions.push(position),
        LightKind::Area { position, u, v, divisions } => {
            let k = divisions as i64;
            for j in 0..k {
                for i in 0..k {
                    let mut q = position;
                    for axis in 0..3 { q[axis] += floor((2 * i + 1) * u[axis], 2 * k) + floor((2 * j + 1) * v[axis], 2 * k); }
                    positions.push(q);
                }
            }
        }
        LightKind::Sun(_) => unreachable!(),
    }
    let intensity = floor(light.intensity, positions.len() as i64);
    positions.iter().map(|&q| { let delta = subtract(q, point); Sample { direction: normalize(delta), distance: length(delta), intensity } }).collect()
}

fn cone(scene: &Scene, light: usize, direction: Vector) -> i64 {
    if let LightKind::Spot { direction: spot, outer, inner, .. } = scene.lights[light].kind {
        let cosine = -dot(direction, spot);
        if cosine <= outer { 0 } else if cosine >= inner { S } else { floor((cosine - outer) * S, inner - outer) }
    } else { S }
}

#[derive(Clone)]
struct Information {
    object: usize,
    distance: i64,
    point: Vector,
    normal: Vector,
    base: Color,
    illumination: usize,
    lit: Vec<bool>,
}

struct TraceResult {
    color: Color,
    information: Option<Information>,
    rays: i64,
    depth: usize,
}

fn log(lines: &mut Option<Vec<String>>, line: String) {
    if let Some(lines) = lines { lines.push(line); }
}

struct Tracer<'a> {
    scene: &'a Scene,
    settings: &'a Settings,
    bounds: Vec<Option<(Vector, Vector)>>,
    nodes: Vec<Node>,
    root: Option<usize>,
    stats: Statistics,
}

impl<'a> Tracer<'a> {
    fn new(scene: &'a Scene, settings: &'a Settings) -> Self {
        let bounds: Vec<_> = scene.objects.iter().map(|o| intersect::bounds(o, settings.margin)).collect();
        let group: Vec<usize> = (0..bounds.len()).filter(|&i| bounds[i].is_some()).collect();
        let mut nodes = Vec::new();
        let root = if group.is_empty() { None } else { Some(build(group, 0, &bounds, &mut nodes)) };
        let stats = Statistics { rays: [0; 4], misses: [0; 3], depth: vec![0; settings.depth + 1], tests: [[0; 2]; 4], visits: vec![0; nodes.len()],
            primary: vec![0; scene.objects.len()], secondary: vec![0; scene.objects.len()], occlusions: vec![0; scene.objects.len()],
            lights: (0..scene.lights.len()).map(|_| LightStats::default()).collect(), total_internal: 0, clamped: 0 };
        Self { scene, settings, bounds, nodes, root, stats }
    }

    fn test_object(&mut self, object: usize, ray: Ray, kind: usize, tally: bool) -> Option<Hit> {
        if tally { self.stats.tests[kind][1] += 1; }
        intersect::object(ray, &self.scene.objects[object].geometry, self.settings.epsilon).map(|(distance, face)| Hit { object, distance, face })
    }

    fn consider(&mut self, object: usize, ray: Ray, kind: usize, tally: bool, best: &mut Option<Hit>) {
        if let Some(hit) = self.test_object(object, ray, kind, tally) {
            if hit.distance <= self.settings.far && (*best).map_or(true, |b| (hit.distance, hit.object) < (b.distance, b.object)) { *best = Some(hit); }
        }
    }

    fn nearest_node(&mut self, index: usize, ray: Ray, kind: usize, tally: bool, best: &mut Option<Hit>) {
        let node = self.nodes[index].clone();
        if tally { self.stats.tests[kind][0] += 1; self.stats.visits[index] += 1; }
        let slab = match intersect::slab(ray, node.lo, node.hi) { Some(s) => s, None => return };
        if slab.far <= self.settings.epsilon || slab.near > self.settings.far || (*best).map_or(false, |b| slab.near > b.distance) { return; }
        if let Some((left, right)) = node.children {
            self.nearest_node(left, ray, kind, tally, best);
            self.nearest_node(right, ray, kind, tally, best);
        } else { for object in node.objects { self.consider(object, ray, kind, tally, best); } }
    }

    fn nearest(&mut self, ray: Ray, kind: usize, tally: bool) -> Option<Hit> {
        let mut best = None;
        for object in 0..self.scene.objects.len() { if self.bounds[object].is_none() { self.consider(object, ray, kind, tally, &mut best); } }
        if let Some(root) = self.root { self.nearest_node(root, ray, kind, tally, &mut best); }
        best
    }

    fn occluder_node(&mut self, index: usize, ray: Ray, distance: i64, tally: bool, occluders: &mut Vec<usize>) {
        let node = self.nodes[index].clone();
        if tally { self.stats.tests[3][0] += 1; self.stats.visits[index] += 1; }
        let slab = match intersect::slab(ray, node.lo, node.hi) { Some(s) => s, None => return };
        if slab.far <= self.settings.epsilon || slab.near >= distance { return; }
        if let Some((left, right)) = node.children {
            self.occluder_node(left, ray, distance, tally, occluders);
            self.occluder_node(right, ray, distance, tally, occluders);
        } else {
            for object in node.objects { if let Some(hit) = self.test_object(object, ray, 3, tally) { if hit.distance < distance { occluders.push(object); } } }
        }
    }

    fn occluders(&mut self, ray: Ray, distance: i64, tally: bool) -> Vec<usize> {
        let mut result = Vec::new();
        for object in 0..self.scene.objects.len() {
            if self.bounds[object].is_none() { if let Some(hit) = self.test_object(object, ray, 3, tally) { if hit.distance < distance { result.push(object); } } }
        }
        if let Some(root) = self.root { self.occluder_node(root, ray, distance, tally, &mut result); }
        result.sort();
        if tally { for &object in &result { self.stats.occlusions[object] += 1; } }
        result
    }

    fn camera(&self, qx: i64, qy: i64) -> Ray {
        let s = self.scene;
        let w = self.settings.width as i64;
        let h = self.settings.height as i64;
        let u = floor((qx - 2 * w) * s.half_width, 2 * w);
        let v = floor((2 * h - qy) * s.half_height, 2 * h);
        Ray { origin: s.eye, direction: normalize(add(add(s.forward, scale(s.right, u)), scale(s.up, v))) }
    }

    fn trace(&mut self, ray: Ray, kind: usize, depth: usize, tally: bool, lines: &mut Option<Vec<String>>) -> TraceResult {
        let scene = self.scene;
        let settings = self.settings;
        if tally { self.stats.rays[kind] += 1; self.stats.depth[depth] += 1; }
        log(lines, format!("ray {} {} origin {} direction {}", KINDS[kind], depth, text(ray.origin), text(ray.direction)));
        let hit = match self.nearest(ray, kind, tally) {
            Some(hit) => hit,
            None => {
                if tally { self.stats.misses[kind] += 1; }
                log(lines, "miss".into());
                log(lines, format!("color {}", text(scene.background)));
                return TraceResult { color: scene.background, information: None, rays: 1, depth };
            }
        };
        if tally { if kind == 0 { self.stats.primary[hit.object] += 1; } else { self.stats.secondary[hit.object] += 1; } }
        let object = &scene.objects[hit.object];
        let material = &scene.materials[object.material];
        let point = add(ray.origin, scale(ray.direction, hit.distance));
        let outward = intersect::outward(object, ray, point, hit.face);
        let front = dot(outward, ray.direction) <= 0;
        let normal = if front { outward } else { negate(outward) };
        let base = shading::base(material, point);
        log(lines, format!("hit {} t {} point {} normal {} base {}", object.label, hit.distance, text(point), text(normal), text(base)));
        let mut rays = 1;
        let mut maximum_depth = depth;
        let mut lit = vec![false; scene.lights.len()];
        let mut diffuse = 0;
        let mut specular = 0;
        for light in 0..scene.lights.len() {
            let samples = samples(scene, light, point, settings.far);
            let (mut count, mut diffuse_sum, mut specular_sum) = (0, 0, 0);
            for sample in &samples {
                let ndl = dot(normal, sample.direction);
                if ndl <= 0 { if tally { self.stats.lights[light].backfacing += 1; } continue; }
                let g = cone(scene, light, sample.direction);
                if g == 0 { if tally { self.stats.lights[light].outside += 1; } continue; }
                let occluders = self.occluders(Ray { origin: point, direction: sample.direction }, sample.distance, tally);
                rays += 1;
                if tally { self.stats.rays[3] += 1; self.stats.lights[light].shadows += 1; }
                let mut factor = g;
                for &i in &occluders { factor = mul(factor, scene.materials[scene.objects[i].material].transmission); }
                if factor == 0 { if tally { self.stats.lights[light].blocked += 1; } continue; }
                if !occluders.is_empty() && tally { self.stats.lights[light].attenuated += 1; }
                count += 1;
                let (d, s) = shading::components(material, normal, sample.direction, negate(ray.direction), mul(sample.intensity, factor), ndl);
                diffuse_sum += d;
                specular_sum += s;
            }
            lit[light] = count > 0;
            diffuse += diffuse_sum;
            specular += specular_sum;
            log(lines, format!("light {} lit {} of {} diffuse {} specular {}", light + 1, count, samples.len(), diffuse_sum, specular_sum));
        }
        let mut local = [0; 3];
        for component in 0..3 {
            let raw = floor(base[component] * (scene.ambient + diffuse), S) + floor(255 * specular, S);
            local[component] = raw.min(255);
            if raw > 255 && tally { self.stats.clamped += 1; }
        }
        log(lines, format!("local {}", text(local)));
        let mut color = local;
        if depth < settings.depth && (material.reflection > 0 || material.transmission > 0) {
            let weights = shading::refraction(material, ray.direction, normal, front);
            if weights.total_internal { if tally { self.stats.total_internal += 1; } log(lines, "total_internal_reflection".into()); }
            log(lines, format!("weights {} {} {}", S - material.reflection - material.transmission, weights.reflected, weights.transmitted));
            let mut reflected = [0; 3];
            let mut transmitted = [0; 3];
            if weights.reflected > 0 {
                let result = self.trace(Ray { origin: point, direction: shading::reflection(ray.direction, normal) }, 1, depth + 1, tally, lines);
                reflected = result.color;
                rays += result.rays;
                maximum_depth = maximum_depth.max(result.depth);
            }
            if weights.transmitted > 0 {
                let result = self.trace(Ray { origin: point, direction: weights.direction.unwrap() }, 2, depth + 1, tally, lines);
                transmitted = result.color;
                rays += result.rays;
                maximum_depth = maximum_depth.max(result.depth);
            }
            color = shading::mix(&[(local, S - material.reflection - material.transmission), (reflected, weights.reflected), (transmitted, weights.transmitted)]);
        }
        if let Some(fog) = &scene.fog {
            let factor = if hit.distance <= fog.start { 0 } else if hit.distance >= fog.end { S } else { floor((hit.distance - fog.start) * S, fog.end - fog.start) };
            color = shading::mix(&[(color, S - factor), (fog.color, factor)]);
        }
        log(lines, format!("color {}", text(color)));
        let illumination = lit.iter().filter(|&&v| v).count();
        TraceResult { color, information: Some(Information { object: hit.object, distance: hit.distance, point, normal, base, illumination, lit }), rays, depth: maximum_depth }
    }
}

fn write(name: &str, lines: &[String]) -> io::Result<()> {
    fs::write(format!("output/{}", name), if lines.is_empty() { String::new() } else { lines.join("\n") + "\n" })
}

fn image_lines(values: &[Color], width: usize, height: usize) -> Vec<String> {
    let mut lines = vec!["P3".into(), format!("{} {}", width, height), "255".into()];
    lines.extend(values.chunks(width).map(|row| row.iter().map(|&c| text(c)).collect::<Vec<_>>().join(" ")));
    lines
}

fn gray_lines(values: &[i64], width: usize, height: usize) -> Vec<String> {
    let mut lines = vec!["P2".into(), format!("{} {}", width, height), "255".into()];
    lines.extend(values.chunks(width).map(|row| row.iter().map(ToString::to_string).collect::<Vec<_>>().join(" ")));
    lines
}

fn mean(colors: &[Color], indices: &[usize]) -> Color {
    let mut result = [0; 3];
    for &i in indices { for c in 0..3 { result[c] += colors[i][c]; } }
    for component in &mut result { *component = floor(*component, indices.len() as i64); }
    result
}

fn main() -> io::Result<()> {
    let scene = scene::read()?;
    let settings = read_settings()?;
    let (w, h) = (settings.width, settings.height);
    let mut tracer = Tracer::new(&scene, &settings);
    let mut center = Vec::new();
    for y in 0..h {
        for x in 0..w {
            let ray = tracer.camera((4 * x + 2) as i64, (4 * y + 2) as i64);
            center.push(tracer.trace(ray, 0, 0, true, &mut None));
        }
    }
    let labels: Vec<char> = center.iter().map(|r| r.information.as_ref().map_or('.', |i| scene.objects[i.object].label)).collect();
    let mut colors: Vec<Color> = center.iter().map(|r| r.color).collect();
    let mut counts: Vec<i64> = center.iter().map(|r| r.rays).collect();
    let mut depths: Vec<usize> = center.iter().map(|r| r.depth).collect();
    let mut subsampled = vec![false; w * h];
    for y in 0..h {
        for x in 0..w {
            let index = y * w + x;
            let adaptive = [(-1i64, 0i64), (1, 0), (0, -1), (0, 1)].iter().any(|&(dx, dy)| {
                let (a, b) = (x as i64 + dx, y as i64 + dy);
                if a < 0 || b < 0 || a >= w as i64 || b >= h as i64 { return false; }
                let other = b as usize * w + a as usize;
                labels[index] != labels[other] || (0..3).map(|c| (center[index].color[c] - center[other].color[c]).abs()).max().unwrap() > settings.contrast
            });
            if adaptive {
                subsampled[index] = true;
                let mut sum = [0; 3];
                for (dx, dy) in [(1, 1), (3, 1), (1, 3), (3, 3)] {
                    let ray = tracer.camera((4 * x + dx) as i64, (4 * y + dy) as i64);
                    let result = tracer.trace(ray, 0, 0, true, &mut None);
                    for c in 0..3 { sum[c] += result.color[c]; }
                    counts[index] += result.rays;
                    depths[index] = depths[index].max(result.depth);
                }
                for c in 0..3 { colors[index][c] = floor(sum[c], 4); }
            }
        }
    }
    let distances: Vec<i64> = center.iter().filter_map(|r| r.information.as_ref().map(|i| i.distance)).collect();
    let minimum_distance = distances.iter().copied().min();
    let maximum_distance = distances.iter().copied().max();
    let maximum_count = *counts.iter().max().unwrap();
    let mut depth_image = Vec::new();
    let mut normal_image = Vec::new();
    let mut albedo = Vec::new();
    let mut light_map = Vec::new();
    for result in &center {
        if let Some(info) = &result.information {
            let minimum = minimum_distance.unwrap();
            let maximum = maximum_distance.unwrap();
            depth_image.push(if minimum == maximum { 255 } else { 255 - floor(235 * (info.distance - minimum), maximum - minimum) });
            let mut normal = [0; 3];
            for c in 0..3 { normal[c] = floor((info.normal[c] + S) * 255, 2 * S).max(0).min(255); }
            normal_image.push(normal);
            albedo.push(info.base);
            light_map.push((b'0' + info.illumination as u8) as char);
        } else {
            depth_image.push(0);
            normal_image.push([0; 3]);
            albedo.push([0; 3]);
            light_map.push('.');
        }
    }
    let mut stats = vec![format!("image {} {}", w, h), format!("supersampled {}", subsampled.iter().filter(|&&v| v).count()),
        format!("rays primary {} reflection {} refraction {} shadow {} total {}", tracer.stats.rays[0], tracer.stats.rays[1], tracer.stats.rays[2], tracer.stats.rays[3], tracer.stats.rays.iter().sum::<i64>()),
        format!("misses primary {} reflection {} refraction {}", tracer.stats.misses[0], tracer.stats.misses[1], tracer.stats.misses[2]),
        format!("depth {}", tracer.stats.depth.iter().map(ToString::to_string).collect::<Vec<_>>().join(" "))];
    for i in 0..4 { stats.push(format!("tests {} nodes {} objects {}", KINDS[i], tracer.stats.tests[i][0], tracer.stats.tests[i][1])); }
    stats.extend([format!("total_internal_reflection {}", tracer.stats.total_internal), format!("clamped {}", tracer.stats.clamped),
        minimum_distance.map_or("distance none".into(), |minimum| format!("distance {} {}", minimum, maximum_distance.unwrap())), format!("max_pixel_rays {}", maximum_count),
        format!("mean {}", text(mean(&colors, &(0..w * h).collect::<Vec<_>>())))]);
    let mut histogram = [0i64; 8];
    for &color in &colors { let brightness = floor(299 * color[0] + 587 * color[1] + 114 * color[2], 1000); histogram[(brightness / 32) as usize] += 1; }
    stats.push(format!("histogram {}", histogram.iter().map(ToString::to_string).collect::<Vec<_>>().join(" ")));
    for (i, node) in tracer.nodes.iter().enumerate() {
        let kind = if node.children.is_some() { "inner".into() } else { format!("leaf {}", node.objects.iter().map(|&i| scene.objects[i].label).collect::<String>()) };
        stats.push(format!("node {} {} box {} {} visits {}", node.depth, kind, text(node.lo), text(node.hi), tracer.stats.visits[i]));
    }
    for (i, object) in scene.objects.iter().enumerate() {
        let pixels: Vec<usize> = (0..w * h).filter(|&p| labels[p] == object.label).collect();
        let suffix = if pixels.is_empty() { "box none color none".into() } else {
            format!("box {} {} {} {} color {}", pixels.iter().map(|p| p % w).min().unwrap(), pixels.iter().map(|p| p / w).min().unwrap(),
                pixels.iter().map(|p| p % w).max().unwrap(), pixels.iter().map(|p| p / w).max().unwrap(), text(mean(&colors, &pixels)))
        };
        stats.push(format!("object {} {} primary {} secondary {} shadow {} pixels {} {}", object.label, object.kind(), tracer.stats.primary[i], tracer.stats.secondary[i], tracer.stats.occlusions[i], pixels.len(), suffix));
    }
    for (i, light) in scene.lights.iter().enumerate() {
        let stats_light = &tracer.stats.lights[i];
        let lit_pixels = center.iter().filter(|r| r.information.as_ref().map_or(false, |info| info.lit[i])).count();
        stats.push(format!("light {} {} samples {} pixels {} shadow_rays {} blocked {} attenuated {} backfacing {} outside {}", i + 1, light.kind(), light.samples(), lit_pixels,
            stats_light.shadows, stats_light.blocked, stats_light.attenuated, stats_light.backfacing, stats_light.outside));
    }
    let mut queries = Vec::new();
    for (number, line) in fs::read_to_string("input/queries.txt")?.lines().enumerate() {
        queries.push(format!("query {} {}", number + 1, line));
        let words: Vec<&str> = line.split_whitespace().collect();
        if words[0] == "object" {
            let label = words[1].chars().next().unwrap();
            let i = scene.objects.iter().position(|o| o.label == label).unwrap();
            let object = &scene.objects[i];
            let bounds = tracer.bounds[i].map_or("none leaf none".into(), |(lo, hi)| {
                let node = tracer.nodes.iter().find(|n| n.objects.contains(&i)).unwrap();
                format!("{} {} leaf {}", text(lo), text(hi), node.depth)
            });
            queries.push(format!("{} material {} bounds {}", object.kind(), scene.materials[object.material].name, bounds));
            continue;
        }
        let values: Vec<i64> = words[1..].iter().map(|s| s.parse().unwrap()).collect();
        match words[0] {
            "pixel" => {
                let index = values[1] as usize * w + values[0] as usize;
                let distance = center[index].information.as_ref().map_or("none".into(), |i| i.distance.to_string());
                queries.push(format!("label {} distance {} color {} samples {} rays {}", labels[index], distance, text(colors[index]), if subsampled[index] { 4 } else { 1 }, counts[index]));
            }
            "trace" | "ray" => {
                let ray = if words[0] == "trace" { tracer.camera(4 * values[0] + 2, 4 * values[1] + 2) }
                    else { Ray { origin: [values[0], values[1], values[2]], direction: normalize([values[3], values[4], values[5]]) } };
                let mut record = Some(Vec::new());
                tracer.trace(ray, 0, 0, false, &mut record);
                queries.extend(record.unwrap());
            }
            "visible" => {
                let point = [values[0], values[1], values[2]];
                let relative = subtract(point, scene.eye);
                let ray = Ray { origin: scene.eye, direction: normalize(relative) };
                let visible = tracer.occluders(ray, length(relative) - settings.epsilon, false).is_empty();
                let nearest = tracer.nearest(ray, 0, false);
                queries.push(if let Some(hit) = nearest { format!("{} first {} t {}", if visible { "yes" } else { "no" }, scene.objects[hit.object].label, hit.distance) }
                    else { format!("{} first none", if visible { "yes" } else { "no" }) });
            }
            "shadow" => {
                let point = [values[0], values[1], values[2]];
                for light in 0..scene.lights.len() {
                    let mut objects = BTreeSet::new();
                    let mut transmittance = 0;
                    for sample in samples(&scene, light, point, settings.far) {
                        let mut factor = cone(&scene, light, sample.direction);
                        let occluders = tracer.occluders(Ray { origin: point, direction: sample.direction }, sample.distance, false);
                        for i in occluders { factor = mul(factor, scene.materials[scene.objects[i].material].transmission); objects.insert(i); }
                        transmittance += factor;
                    }
                    let labels = if objects.is_empty() { "none".into() } else { objects.iter().map(|&i| scene.objects[i].label).collect::<String>() };
                    queries.push(format!("light {} factor {} occluders {}", light + 1, transmittance, labels));
                }
            }
            "region" => {
                let mut indices = Vec::new();
                for y in values[1]..=values[3] { for x in values[0]..=values[2] { indices.push(y as usize * w + x as usize); } }
                queries.push(format!("pixels {} mean {}", indices.len(), text(mean(&colors, &indices))));
                for label in scene.objects.iter().map(|o| o.label).chain(std::iter::once('.')) {
                    let count = indices.iter().filter(|&&i| labels[i] == label).count();
                    if count > 0 { queries.push(format!("label {} {}", label, count)); }
                }
            }
            _ => unreachable!(),
        }
    }
    let object_map: Vec<String> = labels.chunks(w).map(|r| r.iter().collect()).collect();
    let light_map: Vec<String> = light_map.chunks(w).map(|r| r.iter().collect()).collect();
    let ray_depth: Vec<String> = depths.chunks(w).map(|r| r.iter().map(|&d| (b'0' + d as u8) as char).collect()).collect();
    let cost: Vec<i64> = counts.iter().map(|&c| floor(255 * c, maximum_count)).collect();
    fs::create_dir_all("output")?;
    for (name, lines) in [("image.ppm", image_lines(&colors, w, h)), ("depth.pgm", gray_lines(&depth_image, w, h)), ("normal.ppm", image_lines(&normal_image, w, h)),
        ("albedo.ppm", image_lines(&albedo, w, h)), ("cost.pgm", gray_lines(&cost, w, h)), ("object_map.txt", object_map), ("light_map.txt", light_map),
        ("ray_depth.txt", ray_depth), ("stats.txt", stats), ("queries.txt", queries)] { write(name, &lines)?; }
    Ok(())
}
