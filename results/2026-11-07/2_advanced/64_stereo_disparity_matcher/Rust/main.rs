mod pgm_io;
mod costs;
mod aggregation;
mod refinement;
mod evaluation;

use std::collections::{BTreeMap, BTreeSet, VecDeque};
use pgm_io::{Image, Params};
use costs::Volume;
use refinement::decimal;
use evaluation::{evaluate, ratio};

type Disparity = Vec<Option<i64>>;

#[derive(Clone)]
struct Selection { disparity: Disparity, codes: Vec<i64>, margins: Vec<i64>, lr: [usize; 4], bounds: usize, window: usize }

fn select(volume: &Volume, texture: &[i64], image: &Image, p: &Params, window: usize) -> Selection {
    let n = image.pixels.len();
    let mut right = vec![None; n];
    for y in 0..image.height { for x in 0..image.width {
        let mut best = i64::MAX;
        for d in p.minimum..=p.maximum {
            if x as i64+d >= image.width as i64 { continue; }
            let cost = volume[y*image.width+x+d as usize][(d-p.minimum) as usize];
            if cost < best { best = cost; right[y*image.width+x] = Some(d); }
        }
    } }
    let mut result = Selection { disparity: vec![None; n], codes: vec![0; n], margins: vec![0; n], lr: [0; 4], bounds: 0, window };
    for pixel in 0..n {
        let x = (pixel%image.width) as i64;
        let row = pixel-pixel%image.width;
        let index = (0..volume[pixel].len()).min_by_key(|&d| (volume[pixel][d], d)).unwrap();
        let d1 = index as i64+p.minimum;
        let c1 = volume[pixel][index];
        let c2 = (0..volume[pixel].len()).filter(|&d| (d as i64-index as i64).abs() >= 2).map(|d| volume[pixel][d]).min().unwrap();
        result.bounds += usize::from(d1 == p.minimum || d1 == p.maximum);
        let consistent = |d: i64| x >= d && (d-right[row+(x-d) as usize].unwrap()).abs() <= p.lr;
        let code = if texture[pixel] < p.texture_threshold { 50 }
            else if 100*c2 <= (100+p.uniqueness)*c1 { 100 }
            else if x < d1 { 150 }
            else if !consistent(d1) {
                if (p.minimum..=p.maximum).any(consistent) { 200 } else { 255 }
            } else { 0 };
        result.codes[pixel] = code;
        if code == 0 { result.disparity[pixel] = Some(d1); result.margins[pixel] = c2-c1; }
        if code == 0 || code == 200 || code == 255 {
            let difference = (d1-right[row+(x-d1) as usize].unwrap()).abs();
            result.lr[difference.min(3) as usize] += 1;
        }
    }
    result
}

fn neighbors(pixel: usize, width: usize, height: usize, eight: bool) -> Vec<usize> {
    let (x, y) = ((pixel%width) as i64, (pixel/width) as i64);
    let mut result = Vec::new();
    for dy in -1i64..=1 { for dx in -1i64..=1 {
        if dx == 0 && dy == 0 { continue; }
        if !eight && dx.abs()+dy.abs() != 1 { continue; }
        let (xx, yy) = (x+dx, y+dy);
        if xx >= 0 && yy >= 0 && xx < width as i64 && yy < height as i64 { result.push(yy as usize*width+xx as usize); }
    } }
    result
}

fn components(disparity: &Disparity, width: usize, height: usize, range: i64) -> Vec<Vec<usize>> {
    let mut visited = vec![false; disparity.len()];
    let mut result = Vec::new();
    for pixel in 0..disparity.len() {
        if visited[pixel] || disparity[pixel].is_none() { continue; }
        visited[pixel] = true;
        let mut queue = VecDeque::from([pixel]);
        let mut component = Vec::new();
        while let Some(a) = queue.pop_front() {
            component.push(a);
            for b in neighbors(a, width, height, false) {
                if !visited[b] && disparity[b].is_some() && (disparity[a].unwrap()-disparity[b].unwrap()).abs() <= range {
                    visited[b] = true; queue.push_back(b);
                }
            }
        }
        component.sort_unstable(); result.push(component);
    }
    result
}

fn median(mut values: Vec<i64>) -> i64 { values.sort_unstable(); values[(values.len()-1)/2] }

struct Postprocessed { disparity: Disparity, sources: Vec<usize>, summary: [usize; 6] }

fn postprocess(selection: &Selection, image: &Image, p: &Params) -> Postprocessed {
    let mut first = selection.disparity.clone();
    let mut summary = [0; 6];
    for component in components(&first, image.width, image.height, p.speckle_range) {
        if component.len() < p.speckle_size {
            summary[0] += 1; summary[1] += component.len();
            for pixel in component { first[pixel] = None; }
        }
    }
    let mut second = first.clone();
    for pixel in 0..first.len() {
        if first[pixel].is_none() { continue; }
        let mut values = vec![first[pixel].unwrap()];
        values.extend(neighbors(pixel, image.width, image.height, true).iter().filter_map(|&q| first[q]));
        second[pixel] = Some(median(values));
        summary[2] += usize::from(second[pixel] != first[pixel]);
    }
    let mut result = Postprocessed { disparity: second.clone(), sources: vec![4; first.len()], summary };
    for pixel in 0..first.len() {
        if second[pixel].is_some() {
            result.sources[pixel] = usize::from(second[pixel] != selection.disparity[pixel]);
            continue;
        }
        let (x, y) = ((pixel%image.width) as i64, (pixel/image.width) as i64);
        let background = selection.codes[pixel] == 150 || selection.codes[pixel] == 255;
        let directions: &[(i64, i64)] = if background { &aggregation::DIRECTIONS[..2] } else { &aggregation::DIRECTIONS };
        let mut values = Vec::new();
        for &(dx, dy) in directions {
            let (mut xx, mut yy) = (x+dx, y+dy);
            while xx >= 0 && yy >= 0 && xx < image.width as i64 && yy < image.height as i64 {
                if let Some(d) = second[yy as usize*image.width+xx as usize] { values.push(d); break; }
                xx += dx; yy += dy;
            }
        }
        if !values.is_empty() {
            result.disparity[pixel] = Some(if background { *values.iter().min().unwrap() } else { median(values) });
            result.sources[pixel] = if background { 2 } else { 3 };
        }
    }
    for &source in &result.sources { if source >= 2 { result.summary[source+1] += 1; } }
    result
}

fn metric_line(name: &str, metric: &evaluation::Metrics) -> String {
    format!("region {} pixels {} valid {} bad1 {} bad2 {} mae {} exact {}", name, metric.pixels, metric.valid,
        ratio(metric.bad1, metric.pixels), ratio(metric.bad2, metric.pixels),
        if metric.valid == 0 { "-".to_owned() } else { decimal(metric.error, metric.valid as i64) }, metric.exact)
}

fn main() {
    let left = Image::read("input/left.pgm");
    let right = Image::read("input/right.pgm");
    let truth = Image::read("input/ground_truth.pgm");
    let p = pgm_io::params();
    let n = left.pixels.len();
    let regions = evaluation::regions(&truth.pixels, left.width, left.height);
    let lc = costs::census(&left);
    let rc = costs::census(&right);
    let texture = costs::texture(&left, p.texture_window);
    let mut lines = vec![format!("image {} {}", left.width, left.height), format!("disparities {} {}", p.minimum, p.maximum)];
    for (name, image) in [("left", &left), ("right", &right)] {
        lines.push(format!("{} mean {} min {} max {}", name, decimal(image.pixels.iter().sum(), n as i64), image.pixels.iter().min().unwrap(), image.pixels.iter().max().unwrap()));
    }
    lines.push(format!("texture mean {} textureless {}", decimal(texture.iter().sum(), n as i64), texture.iter().filter(|&&t| t < p.texture_threshold).count()));
    lines.push(format!("ground_truth known {} nonocc {} occluded {} disc {} unknown {}", regions.all.len(), regions.nonocc.len(),
        regions.occluded.iter().filter(|&&b| b).count(), regions.disc.len(), n-regions.all.len()));
    let differences: Vec<_> = regions.nonocc.iter().map(|&q| right.pixels[q-truth.pixels[q] as usize]-left.pixels[q]).collect();
    let sum: i64 = differences.iter().sum();
    let bias = decimal(sum.abs(), differences.len() as i64);
    lines.push(format!("photometric pixels {} mean_abs {} bias {}{}", differences.len(), decimal(differences.iter().map(|v| v.abs()).sum(), differences.len() as i64),
        if sum < 0 && bias != "0.00" { "-" } else { "" }, bias));
    let kinds = ["sad", "ssd", "census"];
    let mut selections = Vec::new();
    for (kind, &name) in kinds.iter().enumerate() {
        let mut best: Option<(usize, usize, Selection)> = None;
        for &window in &p.windows[kind] {
            let volume = costs::volume(&left, &right, &lc, &rc, name, window, p.minimum, p.maximum);
            let selection = select(&volume, &texture, &left, &p, window);
            let m = evaluate(&selection.disparity, &truth.pixels, &regions.nonocc);
            lines.push(format!("sweep {} window {} valid {} bad1 {} bad2 {}", name, window, selection.disparity.iter().flatten().count(), ratio(m.bad1, m.pixels), ratio(m.bad2, m.pixels)));
            if best.as_ref().map_or(true, |(a, b, _)| (m.bad1, m.bad2) < (*a, *b)) { best = Some((m.bad1, m.bad2, selection)); }
        }
        selections.push(best.unwrap().2);
    }
    let volume = costs::volume(&left, &right, &lc, &rc, &p.sgm_cost, p.sgm_window, p.minimum, p.maximum);
    let stages = aggregation::paths(&volume, &left, &p);
    for (i, stage) in stages.iter().enumerate() {
        let selection = select(stage, &texture, &left, &p, p.sgm_window);
        let m = evaluate(&selection.disparity, &truth.pixels, &regions.nonocc);
        lines.push(format!("paths {} valid {} bad1 {} bad2 {}", i+1, selection.disparity.iter().flatten().count(), ratio(m.bad1, m.pixels), ratio(m.bad2, m.pixels)));
        if i+1 == stages.len() { selections.push(selection); }
    }
    let wta = kinds.iter().position(|&k| k == p.wta_cost).unwrap();
    let wta_final = postprocess(&selections[wta], &left, &p);
    let sgm_final = postprocess(&selections[3], &left, &p);
    let mut votes = [0; 5];
    let fusion: Disparity = (0..n).map(|pixel| {
        let values: Vec<_> = selections.iter().filter_map(|s| s.disparity[pixel]).collect();
        votes[values.len()] += 1;
        if values.is_empty() { return None; }
        let middle = median(values.clone());
        if values.iter().filter(|&&v| (v-middle).abs() <= 1).count() >= p.votes { Some(middle) } else { None }
    }).collect();
    let names = ["sad", "ssd", "census", "sgm", "fusion", "wta_final", "sgm_final"];
    let mut methods: Vec<_> = selections.iter().map(|s| s.disparity.clone()).collect();
    methods.push(fusion); methods.push(wta_final.disparity.clone()); methods.push(sgm_final.disparity.clone());
    let region_names = ["nonocc", "all", "disc"];
    let region_sets = [&regions.nonocc, &regions.all, &regions.disc];
    let metrics: Vec<Vec<_>> = methods.iter().map(|d| region_sets.iter().map(|r| evaluate(d, &truth.pixels, r)).collect()).collect();
    let source_names = ["kept", "median", "background", "interpolated", "none"];
    for (i, disparity) in methods.iter().enumerate() {
        let valid = disparity.iter().flatten().count();
        lines.push(format!("method {} valid {} invalid {}", names[i], valid, n-valid));
        let values: Vec<_> = disparity.iter().filter_map(|&v| v).collect();
        if values.is_empty() { lines.push("disparity min - max - median - distinct 0".to_owned()); }
        else { lines.push(format!("disparity min {} max {} median {} distinct {}", values.iter().min().unwrap(), values.iter().max().unwrap(), median(values.clone()), values.iter().collect::<BTreeSet<_>>().len())); }
        let mut jumps = [0; 2];
        for pixel in 0..n {
            for (axis, neighbor) in [if pixel%left.width+1 < left.width { Some(pixel+1) } else { None }, if pixel/left.width+1 < left.height { Some(pixel+left.width) } else { None }].iter().copied().enumerate() {
                if let (Some(a), Some(q)) = (disparity[pixel], neighbor) { if let Some(b) = disparity[q] { jumps[axis] += usize::from((a-b).abs() >= 2); } }
            }
        }
        lines.push(format!("jumps horizontal {} vertical {}", jumps[0], jumps[1]));
        if i < 4 {
            let s = &selections[i];
            lines.push(format!("window {} bounds {}", s.window, s.bounds));
            let count = |code| s.codes.iter().filter(|&&v| v == code).count();
            lines.push(format!("reasons textureless {} nonunique {} outside {} mismatch {} occluded {}", count(50), count(100), count(150), count(200), count(255)));
            lines.push(format!("lr 0 {} 1 {} 2 {} 3+ {}", s.lr[0], s.lr[1], s.lr[2], s.lr[3]));
        } else if i == 4 { lines.push(format!("votes 0 {} 1 {} 2 {} 3 {} 4 {}", votes[0], votes[1], votes[2], votes[3], votes[4])); }
        else {
            let post = if i == 5 { &wta_final } else { &sgm_final };
            let s = post.summary;
            lines.push(format!("postprocess speckles {} {} median {} background {} interpolated {} unfilled {}", s[0], s[1], s[2], s[3], s[4], s[5]));
            for (source, &name) in source_names.iter().enumerate() {
                let set: Vec<_> = regions.all.iter().copied().filter(|&pixel| post.sources[pixel] == source).collect();
                let m = evaluate(disparity, &truth.pixels, &set);
                lines.push(format!("source {} pixels {} bad1 {}", name, m.pixels, ratio(m.bad1, m.pixels)));
            }
        }
        for r in 0..3 { lines.push(metric_line(region_names[r], &metrics[i][r])); }
        let mut depth_errors = Vec::new();
        for &pixel in &regions.nonocc {
            if let Some(d) = disparity[pixel] {
                depth_errors.push((refinement::depth(d, p.focal, p.baseline)-refinement::depth(truth.pixels[pixel], p.focal, p.baseline)).abs());
            }
        }
        if depth_errors.is_empty() { lines.push("depth_error pixels 0 mean - max -".to_owned()); }
        else { lines.push(format!("depth_error pixels {} mean {} max {}", depth_errors.len(), decimal(depth_errors.iter().sum(), 100*depth_errors.len() as i64), decimal(*depth_errors.iter().max().unwrap(), 100))); }
        let mut errors = [0; 6];
        for &pixel in &regions.all {
            if let Some(d) = disparity[pixel] { errors[(d-truth.pixels[pixel]).abs().min(4) as usize] += 1; } else { errors[5] += 1; }
        }
        lines.push(format!("errors 0 {} 1 {} 2 {} 3 {} 4+ {} invalid {}", errors[0], errors[1], errors[2], errors[3], errors[4], errors[5]));
    }
    for r in 0..3 {
        let mut rank: Vec<_> = (0..7).collect();
        rank.sort_by(|&a, &b| {
            let (x, y) = (&metrics[a][r], &metrics[b][r]);
            x.bad1.cmp(&y.bad1).then(x.bad2.cmp(&y.bad2)).then_with(|| {
                match (x.valid == 0, y.valid == 0) {
                    (true, false) => std::cmp::Ordering::Greater, (false, true) => std::cmp::Ordering::Less,
                    _ => (x.error*y.valid as i64).cmp(&(y.error*x.valid as i64)),
                }
            }).then(a.cmp(&b))
        });
        lines.push(format!("ranking {} {}", region_names[r], rank.iter().map(|&i| names[i]).collect::<Vec<_>>().join(" ")));
    }
    for i in 0..4 {
        let (mut tp, mut fp, mut missed) = (0, 0, 0);
        for &pixel in &regions.all {
            let detected = selections[i].codes[pixel] == 150 || selections[i].codes[pixel] == 255;
            if regions.occluded[pixel] { if detected { tp += 1; } else { missed += 1; } } else if detected { fp += 1; }
        }
        lines.push(format!("occlusion {} tp {} fp {} fn {} precision {} recall {}", names[i], tp, fp, missed, ratio(tp, tp+fp), ratio(tp, tp+missed)));
    }
    for i in 0..4 {
        let mut valid: Vec<_> = regions.nonocc.iter().copied().filter(|&pixel| selections[i].disparity[pixel].is_some()).collect();
        valid.sort_by_key(|&pixel| (std::cmp::Reverse(selections[i].margins[pixel]), pixel));
        for percent in [25, 50, 75, 100] {
            let count = (valid.len()*percent+99)/100;
            let bad = valid[..count].iter().filter(|&&pixel| (selections[i].disparity[pixel].unwrap()-truth.pixels[pixel]).abs() > 1).count();
            lines.push(format!("confidence {} {} pixels {} margin {} bad1 {}", names[i], percent, count,
                if count == 0 { "-".to_owned() } else { selections[i].margins[valid[count-1]].to_string() }, ratio(bad, count)));
        }
    }
    let layers: BTreeSet<_> = regions.all.iter().map(|&pixel| truth.pixels[pixel]).collect();
    for &g in &layers {
        let all = regions.all.iter().filter(|&&pixel| truth.pixels[pixel] == g).count();
        let set: Vec<_> = regions.nonocc.iter().copied().filter(|&pixel| truth.pixels[pixel] == g).collect();
        lines.push(format!("layer {} pixels {} nonocc {} bad1 {}", g, all, set.len(), methods.iter().map(|d| evaluate(d, &truth.pixels, &set).bad1.to_string()).collect::<Vec<_>>().join(" ")));
    }
    for d in p.minimum..=p.maximum { lines.push(format!("histogram {} {}", d, sgm_final.disparity.iter().filter(|&&value| value == Some(d)).count())); }
    let mut depth = vec!["x,y,sad,ssd,census,sgm,disparity,source,subpixel,depth,truth,truth_depth".to_owned()];
    for &(x, y) in &p.samples {
        let pixel = y*left.width+x;
        let mut fields = vec![x.to_string(), y.to_string()];
        for selection in &selections { fields.push(selection.disparity[pixel].map_or_else(|| "-".to_owned(), |d| d.to_string())); }
        if let Some(d) = sgm_final.disparity[pixel] {
            let (subpixel, distance) = refinement::subpixel(d, &stages.last().unwrap()[pixel], p.minimum, p.maximum, p.focal, p.baseline);
            fields.extend([d.to_string(), source_names[sgm_final.sources[pixel]].to_owned(), subpixel, distance]);
        } else { fields.extend(["-", "none", "-", "-"].iter().map(|v| (*v).to_owned())); }
        if truth.pixels[pixel] == 0 { fields.extend(["-".to_owned(), "-".to_owned()]); }
        else { fields.extend([truth.pixels[pixel].to_string(), decimal(p.focal*p.baseline, truth.pixels[pixel])]); }
        depth.push(fields.join(","));
    }
    struct Object { pixels: Vec<usize>, median: i64, values: Vec<i64>, truth: Option<(i64, usize)> }
    let mut objects = Vec::new();
    let mut small = 0;
    for pixels in components(&sgm_final.disparity, left.width, left.height, p.object_range) {
        if pixels.len() < p.object_size { small += 1; continue; }
        let values: Vec<_> = pixels.iter().map(|&pixel| sgm_final.disparity[pixel].unwrap()).collect();
        let mut counts = BTreeMap::<i64, usize>::new();
        for &pixel in &pixels { if truth.pixels[pixel] != 0 { *counts.entry(truth.pixels[pixel]).or_default() += 1; } }
        let true_layer = counts.into_iter().min_by_key(|&(g, count)| (std::cmp::Reverse(count), g));
        objects.push(Object { median: median(values.clone()), pixels, values, truth: true_layer });
    }
    objects.sort_by_key(|o| (std::cmp::Reverse(o.median), std::cmp::Reverse(o.pixels.len()), o.pixels[0]));
    let mut object_lines = vec![format!("objects {} small {} pixels {}", objects.len(), small, objects.iter().map(|o| o.pixels.len()).sum::<usize>())];
    let mut detected = BTreeSet::new();
    for (i, object) in objects.iter().enumerate() {
        let (x0, x1) = (object.pixels.iter().map(|pixel| pixel%left.width).min().unwrap(), object.pixels.iter().map(|pixel| pixel%left.width).max().unwrap());
        let (y0, y1) = (object.pixels.iter().map(|pixel| pixel/left.width).min().unwrap(), object.pixels.iter().map(|pixel| pixel/left.width).max().unwrap());
        let sum: i64 = object.values.iter().sum();
        let n = object.pixels.len();
        let truth_text = if let Some((g, hits)) = object.truth {
            let total = truth.pixels.iter().filter(|&&v| v == g).count();
            let union = n+total-hits;
            if 2*hits > union { detected.insert(g); }
            format!("{} iou {}", g, ratio(hits, union))
        } else { "- iou -".to_owned() };
        object_lines.push(format!("object {} pixels {} box {} {} {} {} disparity {} {} median {} mean {} depth {} size {} {} truth {}", i+1, n,
            x0, y0, x1, y1, object.values.iter().min().unwrap(), object.values.iter().max().unwrap(), object.median, decimal(sum, n as i64),
            decimal(p.focal*p.baseline*n as i64, sum), decimal((x1-x0+1) as i64*p.baseline, object.median), decimal((y1-y0+1) as i64*p.baseline, object.median), truth_text));
    }
    let missed: Vec<_> = layers.difference(&detected).map(i64::to_string).collect();
    object_lines.push(format!("layers {} detected {} missed {}", layers.len(), detected.len(), if missed.is_empty() { "-".to_owned() } else { missed.join(" ") }));
    let image = |pixels| Image { width: left.width, height: left.height, pixels };
    image(wta_final.disparity.iter().map(|d| 8*d.unwrap_or(0)).collect()).write("disparity_wta.pgm");
    image(sgm_final.disparity.iter().map(|d| 8*d.unwrap_or(0)).collect()).write("disparity_sgm.pgm");
    image(selections[3].codes.clone()).write("occlusion.pgm");
    image((0..n).map(|pixel| if truth.pixels[pixel] == 0 { 0 } else if let Some(d) = sgm_final.disparity[pixel] {
        match (d-truth.pixels[pixel]).abs() { 0 => 50, 1 => 100, 2 => 150, _ => 200 }
    } else { 255 }).collect()).write("error_sgm.pgm");
    pgm_io::write("depth.csv", &depth); pgm_io::write("evaluation.txt", &lines); pgm_io::write("objects.txt", &object_lines);
}
