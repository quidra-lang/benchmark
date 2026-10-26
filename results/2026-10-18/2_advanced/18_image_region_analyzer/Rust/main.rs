mod pgm_reader;
mod threshold;
mod morphology;
mod labeling;
mod report;

use std::collections::{BTreeMap, BTreeSet};
use std::{fs, io};
use labeling::{bit_quad_euler, label_components};
use morphology::{Mask, Point, closing, crossing_number, dilate, erode, opening, thin};
use pgm_reader::{Image, read_images};
use report::{Rational, decimal, hull_area_text, write_files};
use threshold::{Histogram, OtsuResult, isodata, otsu};

const SYMBOLS: &[u8] = b"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
const ORIENTATIONS: [&str; 5] = ["none", "horizontal", "vertical", "falling", "rising"];
const FOUR: [Point; 4] = [(1, 0), (0, -1), (-1, 0), (0, 1)];
const EIGHT: [Point; 8] = [(1, 0), (1, -1), (0, -1), (-1, -1), (-1, 0), (-1, 1), (0, 1), (1, 1)];
const CSV_HEADER: &str = "image,label,class,flags,area,x0,y0,x1,y1,cx,cy,mean,variance,min,max,contrast,border,perimeter,chain,straight,diagonal,turns,compactness,runs,holes,hole_area,euler,parent,depth,var_x,var_y,cov_xy,hu1,orientation,anisotropy,extent,mirror_lr,mirror_tb,hull_area,solidity,feret2,width2,elongation,bays,bay_area,skeleton,endpoints,branches,neighbor,distance2,codes";

#[derive(Clone)]
struct Setting {
    connectivity: usize,
    threshold: String,
    polarity: String,
    operations: Vec<String>,
}
impl Setting {
    fn method(&self) -> &str {
        if self.threshold == "otsu" || self.threshold == "isodata" { &self.threshold } else { "fixed" }
    }
}

struct Parameters {
    otsu_top: usize,
    sweep_step: usize,
    isotropy: Rational,
    bay_min: usize,
    elements: BTreeMap<String, Vec<Point>>,
    settings: BTreeMap<String, Setting>,
}

fn parse_rational(text: &str) -> Rational {
    match text.split_once('/') {
        Some((a, b)) => Rational::new(a.parse().unwrap(), b.parse().unwrap()),
        None => Rational::integer(text.parse().unwrap()),
    }
}

fn read_parameters(path: &str) -> io::Result<Parameters> {
    let mut result = Parameters { otsu_top: 0, sweep_step: 0, isotropy: Rational::integer(0),
        bay_min: 0, elements: BTreeMap::new(), settings: BTreeMap::new() };
    for line in fs::read_to_string(path)?.lines() {
        let words: Vec<_> = line.split(' ').collect();
        match words[0] {
            "otsu_top" => result.otsu_top = words[1].parse().unwrap(),
            "sweep" => result.sweep_step = words[1].parse().unwrap(),
            "isotropy" => result.isotropy = parse_rational(words[1]),
            "bay_min" => result.bay_min = words[1].parse().unwrap(),
            "element" => {
                let (ox, oy) = (words[4].parse::<i64>().unwrap(), words[5].parse::<i64>().unwrap());
                let mut offsets = Vec::new();
                for (y, row) in words[6..].iter().enumerate() {
                    for (x, symbol) in row.bytes().enumerate() { if symbol == b'#' { offsets.push((x as i64 - ox, y as i64 - oy)); } }
                }
                result.elements.insert(words[1].to_owned(), offsets);
            }
            "image" => {
                result.settings.insert(words[1].to_owned(), Setting { connectivity: words[2].parse().unwrap(),
                    threshold: words[3].to_owned(), polarity: words[4].to_owned(), operations: words[5..].iter().map(|word| (*word).to_owned()).collect() });
            }
            _ => unreachable!(),
        }
    }
    Ok(result)
}

struct Condition { feature: String, comparison: String, text: String, value: Rational }
impl Condition {
    fn new(words: &[&str]) -> Self {
        Self { feature: words[0].to_owned(), comparison: words[1].to_owned(), text: words[2].to_owned(),
            value: if words[0] == "orientation" { Rational::integer(0) } else { parse_rational(words[2]) } }
    }
    fn holds(&self, region: &Region) -> bool {
        let order = if self.feature == "orientation" { region.orientation.cmp(&self.text) }
            else { region.value(&self.feature).cmp(&self.value) };
        match self.comparison.as_str() {
            "<" => order.is_lt(), "<=" => !order.is_gt(), ">" => order.is_gt(), ">=" => !order.is_lt(),
            "=" => order.is_eq(), "!=" => !order.is_eq(), _ => unreachable!(),
        }
    }
    fn words(&self) -> String { format!("{} {} {}", self.feature, self.comparison, self.text) }
}
struct Rule { name: String, conditions: Vec<Condition> }
impl Rule { fn matches(&self, region: &Region) -> bool { self.conditions.iter().all(|condition| condition.holds(region)) } }
struct Rules { filters: Vec<Condition>, classes: Vec<Rule>, flags: Vec<Rule> }
impl Rules {
    fn class_names(&self) -> Vec<String> {
        let mut names = Vec::new();
        for rule in &self.classes { if !names.contains(&rule.name) { names.push(rule.name.clone()); } }
        names.push("other".to_owned());
        names
    }
}
fn read_rules(path: &str) -> io::Result<Rules> {
    let mut result = Rules { filters: Vec::new(), classes: Vec::new(), flags: Vec::new() };
    for line in fs::read_to_string(path)?.lines() {
        let words: Vec<_> = line.split(' ').collect();
        if words[0] == "filter" { result.filters.push(Condition::new(&words[1..])); }
        else {
            let rule = Rule { name: words[1].to_owned(), conditions: words[2..].chunks(3).map(Condition::new).collect() };
            if words[0] == "class" { result.classes.push(rule); } else { result.flags.push(rule); }
        }
    }
    Ok(result)
}

struct Hole { number: usize, pixels: Vec<Point>, owner: usize }
#[derive(Clone)]
struct Region {
    number: usize,
    pixels: Vec<Point>,
    features: BTreeMap<&'static str, Rational>,
    orientation: String,
    codes: Vec<usize>,
    skeleton: BTreeSet<Point>,
    hull_doubled: i64,
    parent: Option<usize>,
    depth: usize,
    children: Vec<usize>,
    kept: bool,
    dropped_by: Option<usize>,
    class_name: String,
    flags: Vec<String>,
    neighbor: Option<usize>,
    distance: i64,
}
impl Region {
    fn new(number: usize, pixels: Vec<Point>) -> Self {
        Self { number, pixels, features: BTreeMap::new(), orientation: String::new(), codes: Vec::new(),
            skeleton: BTreeSet::new(), hull_doubled: 0, parent: None, depth: 0, children: Vec::new(), kept: false,
            dropped_by: None, class_name: "other".to_owned(), flags: Vec::new(), neighbor: None, distance: 0 }
    }
    fn value(&self, name: &str) -> Rational { self.features[name] }
    fn int(&self, name: &str) -> i64 { let value = self.value(name); value.numerator / value.denominator }
    fn set(&mut self, name: &'static str, value: Rational) { self.features.insert(name, value); }
    fn set_int(&mut self, name: &'static str, value: i64) { self.set(name, Rational::integer(value)); }
}

fn directions(connectivity: usize) -> &'static [Point] { if connectivity == 4 { &FOUR } else { &EIGHT } }
fn count_foreground(mask: &[Vec<bool>]) -> usize { mask.iter().flat_map(|row| row.iter()).filter(|&&value| value).count() }
fn group_pixels(labels: &[Vec<usize>], count: usize) -> Vec<Vec<Point>> {
    let mut groups = vec![Vec::new(); count + 1];
    for (y, row) in labels.iter().enumerate() { for (x, &label) in row.iter().enumerate() { groups[label].push((x as i64, y as i64)); } }
    groups
}
fn enclosed_components(mask: &[Vec<bool>], connectivity: usize) -> Vec<Vec<Point>> {
    let background: Mask = mask.iter().map(|row| row.iter().map(|&value| !value).collect()).collect();
    let result = label_components(&background, connectivity);
    group_pixels(&result.labels, result.count).into_iter().skip(1).filter(|pixels| !pixels.iter().any(|&(x, y)|
        x == 0 || y == 0 || x == mask[0].len() as i64 - 1 || y == mask.len() as i64 - 1)).collect()
}
fn fill_holes(mask: &[Vec<bool>], connectivity: usize) -> Mask {
    let mut filled = mask.to_vec();
    for pixels in enclosed_components(mask, connectivity) { for (x, y) in pixels { filled[y as usize][x as usize] = true; } }
    filled
}
fn cross(a: Point, b: Point, p: Point) -> i64 { (b.0 - a.0) * (p.1 - a.1) - (b.1 - a.1) * (p.0 - a.0) }
fn squared_distance(a: Point, b: Point) -> i64 { let (dx, dy) = (a.0 - b.0, a.1 - b.1); dx * dx + dy * dy }
fn half_hull(points: impl IntoIterator<Item = Point>) -> Vec<Point> {
    let mut chain = Vec::new();
    for point in points {
        while chain.len() >= 2 && cross(chain[chain.len() - 2], chain[chain.len() - 1], point) <= 0 { chain.pop(); }
        chain.push(point);
    }
    chain
}
fn convex_hull(pixels: &[Point]) -> Vec<Point> {
    let mut corners = BTreeSet::new();
    for &(x, y) in pixels { corners.extend([(x, y), (x + 1, y), (x, y + 1), (x + 1, y + 1)]); }
    let mut lower = half_hull(corners.iter().copied());
    let mut upper = half_hull(corners.iter().rev().copied());
    lower.pop(); upper.pop(); lower.extend(upper); lower
}
fn hull_edges(hull: &[Point]) -> impl Iterator<Item = (Point, Point)> + '_ {
    hull.iter().copied().zip(hull.iter().copied().cycle().skip(1)).take(hull.len())
}
fn contains_center(hull: &[Point], x: i64, y: i64) -> bool {
    hull_edges(hull).all(|(a, b)| cross((2 * a.0, 2 * a.1), (2 * b.0, 2 * b.1), (2 * x + 1, 2 * y + 1)) >= 0)
}
fn box_bounds(pixels: &[Point]) -> (i64, i64, i64, i64) {
    (pixels.iter().map(|point| point.0).min().unwrap(), pixels.iter().map(|point| point.1).min().unwrap(),
        pixels.iter().map(|point| point.0).max().unwrap(), pixels.iter().map(|point| point.1).max().unwrap())
}
fn box_distance(first: &Region, second: &Region) -> i64 {
    let dx = first.int("x0") + first.int("x1") - second.int("x0") - second.int("x1");
    let dy = first.int("y0") + first.int("y1") - second.int("y0") - second.int("y1");
    dx * dx + dy * dy
}
fn mean_text(total: i64, count: usize) -> String {
    if count == 0 { "-".to_owned() } else { decimal(Rational::new(total, count as i64), 2) }
}
fn orientation_line(regions: &[&Region]) -> String {
    let mut parts = vec!["orientations".to_owned()];
    for name in ORIENTATIONS { parts.extend([name.to_owned(), regions.iter().filter(|region| region.orientation == name).count().to_string()]); }
    parts.join(" ")
}

struct ImageAnalysis {
    image: Image,
    setting: Setting,
    histogram: Histogram,
    otsu: OtsuResult,
    isodata_cutoff: usize,
    isodata_iterations: usize,
    cutoff: usize,
    initial: Mask,
    final_mask: Mask,
    morph_counts: Vec<usize>,
    sweep: Vec<(usize, usize, usize)>,
    labels: Vec<Vec<usize>>,
    provisional: usize,
    regions: Vec<Region>,
    four_components: usize,
    eight_components: usize,
    bit_quad: i64,
    holes: Vec<Hole>,
    hole_of: Vec<Vec<usize>>,
}

impl ImageAnalysis {
    fn new(image: Image, setting: Setting, parameters: &Parameters) -> Self {
        let histogram = Histogram::new(&image);
        let otsu = otsu(&histogram);
        let (isodata_cutoff, isodata_iterations) = isodata(&histogram);
        let cutoff = match setting.threshold.as_str() { "otsu" => otsu.cutoff, "isodata" => isodata_cutoff, value => value.parse().unwrap() };
        let binarize = |threshold| image.pixels.iter().map(|row| row.iter().map(|&value|
            if setting.polarity == "bright" { value > threshold as i64 } else { value <= threshold as i64 }).collect()).collect::<Mask>();
        let initial = binarize(cutoff);
        let mut final_mask = initial.clone();
        let mut morph_counts = Vec::new();
        for operation in &setting.operations {
            if operation == "fill" { final_mask = fill_holes(&final_mask, 12 - setting.connectivity); }
            else {
                let (kind, name) = operation.split_once(':').unwrap();
                let offsets = &parameters.elements[name];
                final_mask = match kind { "erode" => erode(&final_mask, offsets), "dilate" => dilate(&final_mask, offsets),
                    "open" => opening(&final_mask, offsets), "close" => closing(&final_mask, offsets), _ => unreachable!() };
            }
            morph_counts.push(count_foreground(&final_mask));
        }
        let sweep = (parameters.sweep_step..image.maxval).step_by(parameters.sweep_step).map(|cutoff| {
            let mask = binarize(cutoff);
            (cutoff, count_foreground(&mask), label_components(&mask, setting.connectivity).count)
        }).collect();
        let labeled = label_components(&final_mask, setting.connectivity);
        let regions = group_pixels(&labeled.labels, labeled.count).into_iter().enumerate().skip(1)
            .map(|(number, pixels)| Region::new(number, pixels)).collect();
        let four_components = label_components(&final_mask, 4).count;
        let eight_components = label_components(&final_mask, 8).count;
        let bit_quad = bit_quad_euler(&final_mask, setting.connectivity);
        let mut holes = Vec::new();
        let mut hole_of = vec![vec![0; image.width]; image.height];
        for pixels in enclosed_components(&final_mask, 12 - setting.connectivity) {
            let (x, y) = pixels[0];
            let number = holes.len() + 1;
            let owner = labeled.labels[y as usize - 1][x as usize];
            for &(x, y) in &pixels { hole_of[y as usize][x as usize] = number; }
            holes.push(Hole { number, pixels, owner });
        }
        let mut result = Self { image, setting, histogram, otsu, isodata_cutoff, isodata_iterations, cutoff,
            initial, final_mask, morph_counts, sweep, labels: labeled.labels, provisional: labeled.provisional,
            regions, four_components, eight_components, bit_quad, holes, hole_of };
        for index in 0..result.regions.len() {
            let (x, y) = result.regions[index].pixels[0];
            if y >= 1 && result.hole_of[y as usize - 1][x as usize] > 0 {
                let owner = result.holes[result.hole_of[y as usize - 1][x as usize] - 1].owner - 1;
                result.regions[index].parent = Some(owner);
                result.regions[index].depth = result.regions[owner].depth + 1;
                result.regions[owner].children.push(index);
            }
        }
        for index in 0..result.regions.len() {
            let mut region = result.regions[index].clone();
            result.measure(&mut region, parameters);
            result.regions[index] = region;
        }
        result
    }
    fn label_at(&self, x: i64, y: i64) -> i64 {
        if x >= 0 && x < self.image.width as i64 && y >= 0 && y < self.image.height as i64 { self.labels[y as usize][x as usize] as i64 } else { -1 }
    }
    fn chain_code(&self, region: &Region) -> Vec<usize> {
        let directions = directions(self.setting.connectivity);
        let mut visited = vec![region.pixels[0]];
        let mut codes = Vec::new();
        let mut heading = directions.len() - 1;
        loop {
            let (x, y) = *visited.last().unwrap();
            let start = if directions.len() == 4 { (heading + 3) % 4 }
                else if heading % 2 == 0 { (heading + 7) % 8 } else { (heading + 6) % 8 };
            let next = (0..directions.len()).map(|offset| (start + offset) % directions.len()).find(|&direction| {
                let (dx, dy) = directions[direction]; self.label_at(x + dx, y + dy) == region.number as i64
            });
            let Some(direction) = next else { return Vec::new(); };
            let (dx, dy) = directions[direction];
            visited.push((x + dx, y + dy)); codes.push(direction); heading = direction;
            let moves = codes.len();
            if moves >= 2 && visited[moves] == visited[1] && visited[moves - 1] == visited[0] { codes.pop(); return codes; }
        }
    }
    fn measure(&self, region: &mut Region, parameters: &Parameters) {
        let area = region.pixels.len() as i64;
        let (x0, y0, x1, y1) = box_bounds(&region.pixels);
        for (name, value) in [("area", area), ("x0", x0), ("y0", y0), ("x1", x1), ("y1", y1),
            ("width", x1 - x0 + 1), ("height", y1 - y0 + 1)] { region.set_int(name, value); }
        region.set_int("border", (x0 == 0 || y0 == 0 || x1 == self.image.width as i64 - 1 || y1 == self.image.height as i64 - 1) as i64);
        let values: Vec<_> = region.pixels.iter().map(|&(x, y)| self.image.pixels[y as usize][x as usize]).collect();
        let sum_values: i64 = values.iter().sum();
        let sum_squares: i64 = values.iter().map(|value| value * value).sum();
        region.set("mean", Rational::new(sum_values, area));
        region.set("variance", Rational::new(area * sum_squares - sum_values * sum_values, area * area));
        region.set_int("min", *values.iter().min().unwrap());
        region.set_int("max", *values.iter().max().unwrap());
        let mut surrounding = BTreeSet::new();
        for &(x, y) in &region.pixels { for &(dx, dy) in &EIGHT {
            if self.label_at(x + dx, y + dy) == 0 { surrounding.insert((x + dx, y + dy)); }
        } }
        let count = surrounding.len() as i64;
        let sum_surrounding: i64 = surrounding.iter().map(|&(x, y)| self.image.pixels[y as usize][x as usize]).sum();
        region.set("contrast", if count == 0 { Rational::integer(0) }
            else { Rational::new(sum_values * count - sum_surrounding * area, area * count) });
        let perimeter = region.pixels.iter().filter(|&&(x, y)| directions(12 - self.setting.connectivity).iter()
            .any(|&(dx, dy)| self.label_at(x + dx, y + dy) != region.number as i64)).count();
        region.set_int("perimeter", perimeter as i64);
        region.codes = self.chain_code(region);
        let straight = if self.setting.connectivity == 4 { region.codes.len() }
            else { region.codes.iter().filter(|&&code| code % 2 == 0).count() };
        let diagonal = region.codes.len() - straight;
        let turns = (0..region.codes.len()).filter(|&index| region.codes[index] != region.codes[(index + region.codes.len() - 1) % region.codes.len()]).count();
        for (name, value) in [("chain", region.codes.len()), ("straight", straight), ("diagonal", diagonal), ("turns", turns)] {
            region.set_int(name, value as i64);
        }
        let length = 5 * straight as i64 + 7 * diagonal as i64;
        region.set("compactness", Rational::new(length * length, 25 * area));
        let runs = region.pixels.iter().filter(|&&(x, y)| self.label_at(x - 1, y) != region.number as i64).count();
        region.set_int("runs", runs as i64);
        let owned: Vec<_> = self.holes.iter().filter(|hole| hole.owner == region.number).collect();
        region.set_int("holes", owned.len() as i64);
        region.set_int("hole_area", owned.iter().map(|hole| hole.pixels.len() as i64).sum());
        region.set_int("euler", 1 - owned.len() as i64);
        region.set_int("depth", region.depth as i64);
        let sum_x: i64 = region.pixels.iter().map(|point| point.0).sum();
        let sum_y: i64 = region.pixels.iter().map(|point| point.1).sum();
        let m20 = area * region.pixels.iter().map(|point| point.0 * point.0).sum::<i64>() - sum_x * sum_x;
        let m02 = area * region.pixels.iter().map(|point| point.1 * point.1).sum::<i64>() - sum_y * sum_y;
        let m11 = area * region.pixels.iter().map(|point| point.0 * point.1).sum::<i64>() - sum_x * sum_y;
        region.set("cx", Rational::new(sum_x, area));
        region.set("cy", Rational::new(sum_y, area));
        region.set("var_x", Rational::new(m20, area * area));
        region.set("var_y", Rational::new(m02, area * area));
        region.set("cov_xy", Rational::new(m11, area * area));
        region.set("hu1", Rational::new(m20 + m02, area * area * area));
        let anisotropy = if m20 + m02 > 0 { Rational::new((m20 - m02).abs() + 2 * m11.abs(), m20 + m02) }
            else { Rational::integer(0) };
        region.set("anisotropy", anisotropy);
        let (u, v) = (m20 - m02, 2 * m11);
        region.orientation = (if anisotropy <= parameters.isotropy { "none" }
            else if v.abs() >= u.abs() { if v > 0 { "falling" } else { "rising" } }
            else if u > 0 { "horizontal" } else { "vertical" }).to_owned();
        region.set("extent", Rational::new(area, (x1 - x0 + 1) * (y1 - y0 + 1)));
        let mirrored_lr = region.pixels.iter().filter(|&&(x, y)| self.label_at(x0 + x1 - x, y) == region.number as i64).count();
        let mirrored_tb = region.pixels.iter().filter(|&&(x, y)| self.label_at(x, y0 + y1 - y) == region.number as i64).count();
        region.set("mirror_lr", Rational::new(mirrored_lr as i64, area));
        region.set("mirror_tb", Rational::new(mirrored_tb as i64, area));
        let hull = convex_hull(&region.pixels);
        region.hull_doubled = hull_edges(&hull).map(|(a, b)| a.0 * b.1 - b.0 * a.1).sum::<i64>().abs();
        let feret2 = hull.iter().flat_map(|&a| hull.iter().map(move |&b| squared_distance(a, b))).max().unwrap();
        let width2 = hull_edges(&hull).map(|(a, b)| {
            let reach = hull.iter().map(|&point| cross(a, b, point).abs()).max().unwrap();
            Rational::new(reach * reach, squared_distance(a, b))
        }).min().unwrap();
        region.set("solidity", Rational::new(2 * area, region.hull_doubled));
        region.set_int("feret2", feret2);
        region.set("width2", width2);
        region.set("elongation", Rational::new(feret2 * width2.denominator, width2.numerator));
        let bay_mask: Mask = (y0..=y1).map(|y| (x0..=x1).map(|x|
            self.labels[y as usize][x as usize] == 0 && self.hole_of[y as usize][x as usize] == 0 && contains_center(&hull, x, y)).collect()).collect();
        let bays = label_components(&bay_mask, 12 - self.setting.connectivity);
        let sizes: Vec<_> = group_pixels(&bays.labels, bays.count).iter().skip(1).map(Vec::len).collect();
        region.set_int("bays", sizes.iter().filter(|&&size| size >= parameters.bay_min).count() as i64);
        region.set_int("bay_area", sizes.iter().sum::<usize>() as i64);
        region.skeleton = thin(&region.pixels);
        let crossings: Vec<_> = region.skeleton.iter().map(|&point| crossing_number(&region.skeleton, point)).collect();
        region.set_int("skeleton", region.skeleton.len() as i64);
        region.set_int("endpoints", crossings.iter().filter(|&&count| count == 1).count() as i64);
        region.set_int("branches", crossings.iter().filter(|&&count| count >= 3).count() as i64);
    }
    fn apply_rules(&mut self, rules: &Rules) {
        for region in &mut self.regions {
            region.dropped_by = rules.filters.iter().position(|condition| !condition.holds(region));
            if region.dropped_by.is_some() { continue; }
            region.kept = true;
            if let Some(rule) = rules.classes.iter().find(|rule| rule.matches(region)) { region.class_name = rule.name.clone(); }
            region.flags = rules.flags.iter().filter(|rule| rule.matches(region)).map(|rule| rule.name.clone()).collect();
        }
        for index in 0..self.regions.len() {
            if !self.regions[index].kept { continue; }
            let candidate = self.regions.iter().filter(|other| other.kept && other.number != index + 1)
                .map(|other| (box_distance(&self.regions[index], other), other.number)).min();
            if let Some((distance, number)) = candidate { self.regions[index].distance = distance; self.regions[index].neighbor = Some(number); }
        }
    }
    fn kept(&self) -> Vec<&Region> { self.regions.iter().filter(|region| region.kept).collect() }
    fn tree_text(&self, index: usize) -> String {
        let region = &self.regions[index];
        if region.children.is_empty() { return region.number.to_string(); }
        let children = region.children.iter().map(|&child| self.tree_text(child)).collect::<Vec<_>>().join(" ");
        format!("{}({children})", region.number)
    }
    fn threshold_lines(&self, top: usize) -> Vec<String> {
        let h = &self.histogram;
        let mut lines = vec![format!("image {} size {} {} maxval {}", self.image.name, self.image.width, self.image.height, self.image.maxval),
            format!("histogram pixels {} min {} max {} mean {} median {} mode {} levels {}", h.pixels, h.minimum, h.maximum,
                mean_text(h.total, h.pixels as usize), h.median, h.mode, h.levels)];
        let bins = std::iter::once(h.bin_width as i64).chain(h.bins.iter().copied()).map(|value| value.to_string()).collect::<Vec<_>>().join(" ");
        lines.push(format!("bins {bins}"));
        lines.push(format!("otsu threshold {} upper {} candidates {}", self.otsu.cutoff, self.otsu.upper, self.otsu.candidates.len()));
        for (position, c) in self.otsu.candidates.iter().take(top).enumerate() {
            let gap = Rational::new(c.sum_above * c.below - c.sum_below * c.above, c.below * c.above);
            lines.push(format!("rank {} t {} below {} above {} mean_below {} mean_above {} gap {}", position + 1, c.cutoff,
                c.below, c.above, mean_text(c.sum_below, c.below as usize), mean_text(c.sum_above, c.above as usize), decimal(gap, 2)));
        }
        lines.push(format!("isodata threshold {} iterations {}", self.isodata_cutoff, self.isodata_iterations));
        lines.push(format!("threshold {} {} {} foreground {}", self.cutoff, self.setting.method(), self.setting.polarity, count_foreground(&self.initial)));
        for (operation, count) in self.setting.operations.iter().zip(&self.morph_counts) { lines.push(format!("morph {operation} foreground {count}")); }
        for &(cutoff, foreground, regions) in &self.sweep { lines.push(format!("sweep {cutoff} foreground {foreground} regions {regions}")); }
        lines
    }
    fn region_symbol(&self, x: usize, y: usize, skeleton_only: bool) -> char {
        let label = self.labels[y][x];
        if label == 0 { return if self.hole_of[y][x] > 0 { ':' } else { '.' }; }
        let region = &self.regions[label - 1];
        if skeleton_only && !region.skeleton.contains(&(x as i64, y as i64)) { return '+'; }
        if region.kept { SYMBOLS[label % SYMBOLS.len()] as char } else { '#' }
    }
    fn map_lines(&self) -> Vec<String> {
        let size = format!("{} {} {}", self.image.name, self.image.width, self.image.height);
        let mut lines = vec![format!("morphology {size}")];
        for (initial, final_row) in self.initial.iter().zip(&self.final_mask) {
            lines.push(initial.iter().zip(final_row).map(|(&before, &after)| match (before, after) {
                (true, true) => '#', (false, true) => '+', (true, false) => '-', (false, false) => '.',
            }).collect());
        }
        for (heading, skeleton_only) in [("labels", false), ("skeleton", true)] {
            lines.push(format!("{heading} {size}"));
            for y in 0..self.image.height { lines.push((0..self.image.width).map(|x| self.region_symbol(x, y, skeleton_only)).collect()); }
        }
        lines
    }
    fn csv_row(&self, region: &Region) -> String {
        let mut fields = vec![self.image.name.clone(), region.number.to_string(), region.class_name.clone(),
            if region.flags.is_empty() { "-".to_owned() } else { region.flags.join("+") }];
        for name in ["area", "x0", "y0", "x1", "y1"] { fields.push(region.int(name).to_string()); }
        for (name, digits) in [("cx", 3), ("cy", 3), ("mean", 2), ("variance", 2)] { fields.push(decimal(region.value(name), digits)); }
        fields.extend([region.int("min").to_string(), region.int("max").to_string(), decimal(region.value("contrast"), 2)]);
        for name in ["border", "perimeter", "chain", "straight", "diagonal", "turns"] { fields.push(region.int(name).to_string()); }
        fields.push(decimal(region.value("compactness"), 3));
        for name in ["runs", "holes", "hole_area", "euler"] { fields.push(region.int(name).to_string()); }
        fields.push(region.parent.map(|index| (index + 1).to_string()).unwrap_or_else(|| "-".to_owned()));
        fields.push(region.depth.to_string());
        for (name, digits) in [("var_x", 3), ("var_y", 3), ("cov_xy", 3), ("hu1", 4)] { fields.push(decimal(region.value(name), digits)); }
        fields.push(region.orientation.clone());
        for name in ["anisotropy", "extent", "mirror_lr", "mirror_tb"] { fields.push(decimal(region.value(name), 3)); }
        fields.extend([hull_area_text(region.hull_doubled), decimal(region.value("solidity"), 3), region.int("feret2").to_string(),
            decimal(region.value("width2"), 3), decimal(region.value("elongation"), 3)]);
        for name in ["bays", "bay_area", "skeleton", "endpoints", "branches"] { fields.push(region.int(name).to_string()); }
        fields.push(region.neighbor.map(|number| number.to_string()).unwrap_or_else(|| "-".to_owned()));
        fields.push(if region.neighbor.is_some() { decimal(Rational::new(region.distance, 4), 2) } else { "-".to_owned() });
        fields.push(if region.codes.is_empty() { "-".to_owned() } else { region.codes.iter().map(usize::to_string).collect::<Vec<_>>().join("") });
        fields.join(",")
    }
    fn intensity_text(&self, foreground: bool) -> String {
        let mut sum = 0;
        let mut count = 0;
        for (pixels, mask) in self.image.pixels.iter().zip(&self.final_mask) {
            for (&value, &flag) in pixels.iter().zip(mask) { if flag == foreground { sum += value; count += 1; } }
        }
        mean_text(sum, count)
    }
    fn area_line(&self) -> String {
        let kept = self.kept();
        if kept.is_empty() { return "area total 0 mean - largest - smallest -".to_owned(); }
        let area: i64 = kept.iter().map(|region| region.int("area")).sum();
        let largest = kept.iter().min_by_key(|region| (std::cmp::Reverse(region.int("area")), region.number)).unwrap();
        let smallest = kept.iter().min_by_key(|region| (region.int("area"), region.number)).unwrap();
        format!("area total {area} mean {} largest {} {} smallest {} {}", mean_text(area, kept.len()),
            largest.number, largest.int("area"), smallest.number, smallest.int("area"))
    }
    fn summary_lines(&self, rules: &Rules) -> Vec<String> {
        let kept = self.kept();
        let count = self.regions.len();
        let hole_pixels: usize = self.holes.iter().map(|hole| hole.pixels.len()).sum();
        let mut lines = vec![format!("image {}", self.image.name),
            format!("threshold {} {} {} conn {}", self.cutoff, self.setting.method(), self.setting.polarity, self.setting.connectivity),
            format!("foreground {} {}", count_foreground(&self.initial), count_foreground(&self.final_mask)),
            format!("regions {count} provisional {} kept {} dropped {}", self.provisional, kept.len(), count - kept.len()),
            format!("connectivity four {} eight {}", self.four_components, self.eight_components),
            format!("holes {} hole_pixels {hole_pixels} euler {} bitquad {}", self.holes.len(), count as i64 - self.holes.len() as i64, self.bit_quad)];
        for hole in &self.holes {
            let (x0, y0, x1, y1) = box_bounds(&hole.pixels);
            lines.push(format!("hole {} owner {} area {} box {x0} {y0} {x1} {y1}", hole.number, hole.owner, hole.pixels.len()));
        }
        lines.push(format!("depth_max {}", self.regions.iter().map(|region| region.depth).max().unwrap_or(0)));
        let mut tree = vec!["tree".to_owned()];
        tree.extend(self.regions.iter().enumerate().filter(|(_, region)| region.parent.is_none()).map(|(index, _)| self.tree_text(index)));
        lines.push(tree.join(" "));
        lines.push(format!("intensity foreground {} background {}", self.intensity_text(true), self.intensity_text(false)));
        lines.push(self.area_line());
        let mut classes = vec!["classes".to_owned()];
        for name in rules.class_names() {
            let count = kept.iter().filter(|region| region.class_name == name).count();
            classes.extend([name, count.to_string()]);
        }
        lines.push(classes.join(" "));
        lines.push(orientation_line(&kept));
        let mut flags = vec!["flags".to_owned()];
        for rule in &rules.flags { flags.extend([rule.name.clone(), kept.iter().filter(|region| region.flags.contains(&rule.name)).count().to_string()]); }
        lines.push(flags.join(" "));
        lines
    }
}

fn overall_lines(analyses: &[ImageAnalysis], rules: &Rules) -> Vec<String> {
    let regions: Vec<_> = analyses.iter().flat_map(|analysis| analysis.regions.iter()).collect();
    let kept: Vec<_> = regions.iter().copied().filter(|region| region.kept).collect();
    let holes: usize = analyses.iter().map(|analysis| analysis.holes.len()).sum();
    let mut lines = vec!["overall".to_owned(), format!("images {}", analyses.len()),
        format!("regions {} kept {} dropped {}", regions.len(), kept.len(), regions.len() - kept.len()),
        format!("holes {holes} euler {}", regions.len() as i64 - holes as i64)];
    for (index, condition) in rules.filters.iter().enumerate() {
        let count = regions.iter().filter(|region| region.dropped_by == Some(index)).count();
        lines.push(format!("filter {} {} dropped {count}", index + 1, condition.words()));
    }
    for name in rules.class_names() {
        let members: Vec<_> = kept.iter().filter(|region| region.class_name == name).collect();
        let area: i64 = members.iter().map(|region| region.int("area")).sum();
        lines.push(format!("class {name} count {} area {area} mean {}", members.len(), mean_text(area, members.len())));
    }
    for rule in &rules.flags {
        lines.push(format!("flag {} count {}", rule.name, kept.iter().filter(|region| region.flags.contains(&rule.name)).count()));
    }
    lines.push(orientation_line(&kept));
    let mut largest: Option<(&str, &Region)> = None;
    for analysis in analyses { for region in analysis.kept() {
        if largest.is_none_or(|(_, previous)| region.int("area") > previous.int("area")) { largest = Some((&analysis.image.name, region)); }
    } }
    lines.push(match largest { Some((name, region)) => format!("largest {name} {} {}", region.number, region.int("area")), None => "largest -".to_owned() });
    lines
}

fn main() -> io::Result<()> {
    let parameters = read_parameters("input/params.txt")?;
    let rules = read_rules("input/rules.txt")?;
    let mut analyses = Vec::new();
    for image in read_images("input/images.txt")? {
        let setting = parameters.settings[&image.name].clone();
        let mut analysis = ImageAnalysis::new(image, setting, &parameters);
        analysis.apply_rules(&rules);
        analyses.push(analysis);
    }
    let (mut thresholds, mut maps, mut summary) = (Vec::new(), Vec::new(), Vec::new());
    let mut rows = vec![CSV_HEADER.to_owned()];
    for analysis in &analyses {
        thresholds.extend(analysis.threshold_lines(parameters.otsu_top));
        maps.extend(analysis.map_lines());
        rows.extend(analysis.kept().iter().map(|region| analysis.csv_row(region)));
        summary.extend(analysis.summary_lines(&rules));
    }
    summary.extend(overall_lines(&analyses, &rules));
    write_files("output", &[("thresholds.txt", thresholds), ("labels.txt", maps), ("regions.csv", rows), ("summary.txt", summary)])
}
