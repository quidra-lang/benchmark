use std::collections::BTreeSet;
use std::io::{self, Read};

type Integer = i64;
type Answer<T> = Result<T, ()>;
macro_rules! require {
    ($condition:expr) => {
        if !($condition) {
            return Err(());
        }
    };
}
#[derive(Clone, Copy)]
struct Grid {
    precision: Integer,
    width: Integer,
    height: Integer,
}
#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
struct Cell {
    precision: usize,
    x: Integer,
    y: Integer,
}
const SYSTEMS: [&str; 6] = ["GEOHASH", "MAIDENHEAD", "PLUSCODE", "GARS", "GEOREF", "MESH"];
const HASH: &[u8] = b"0123456789bcdefghjkmnpqrstuvwxyz";
const PLUS: &[u8] = b"23456789CFGHJMPQRVWX";
const LETTERS: &[u8] = b"ABCDEFGHJKLMNPQRSTUVWXYZ";
const OS_LETTERS: &[u8] = b"ABCDEFGHJKLMNOPQRSTUVWXYZ";
const BANDS: &[u8] = b"CDEFGHJKLMNPQRSTUVWX";
const MGRS_ROWS: &[u8] = b"ABCDEFGHJKLMNPQRSTUV";
const MESH_SCALE: [Integer; 6] = [1, 8, 80, 160, 320, 640];
const MAIDEN_ALPHABETS: [&[u8]; 4] = [b"ABCDEFGHIJKLMNOPQR", b"0123456789", b"abcdefghijklmnopqrstuvwx", b"0123456789"];
struct Codec {
    grids: [Vec<Grid>; 6],
}
fn floor_ratio(a: Integer, b: Integer) -> Integer { a.div_euclid(b) }
fn modulo(a: Integer, b: Integer) -> Integer { a.rem_euclid(b) }
fn padded(value: Integer, width: usize) -> String { format!("{:0width$}", value, width = width) }
fn coordinate(value: Integer) -> String {
    let magnitude = value.abs();
    format!("{}{}.{:06}", if value < 0 { "-" } else { "" }, magnitude / 1_000_000, magnitude % 1_000_000)
}
fn digits(s: &str, low: usize, high: usize) -> bool {
    s.len() >= low && s.len() <= high && s.bytes().all(|c| c.is_ascii_digit())
}
fn integer(s: &str, low: Integer, high: Integer) -> Answer<Integer> {
    let negative = s.starts_with('-');
    let body = if negative { &s[1..] } else { s };
    require!(digits(body, 1, 9));
    let mut value = 0;
    for c in body.bytes() { value = value * 10 + Integer::from(c - b'0'); }
    if negative { value = -value; }
    require!(value >= low && value <= high);
    Ok(value)
}
fn location(s: &str, latitude: bool) -> Answer<Integer> {
    let negative = s.starts_with('-');
    let body = if negative { &s[1..] } else { s };
    let parts: Vec<&str> = body.split('.').collect();
    require!(parts.len() == 1 || parts.len() == 2);
    require!(digits(parts[0], 1, 3));
    let mut fraction = if parts.len() == 2 { parts[1].to_owned() } else { String::new() };
    if parts.len() == 2 { require!(digits(&fraction, 1, 6)); }
    let mut value = integer(parts[0], 0, 999)? * 1_000_000;
    fraction.push_str(&"0".repeat(6 - fraction.len()));
    value += integer(&fraction, 0, 999999)?;
    if negative { value = -value; }
    require!(if latitude { (-90000000..=90000000).contains(&value) } else { (-180000000..180000000).contains(&value) });
    Ok(value)
}
fn system_id(s: &str) -> Answer<usize> { SYSTEMS.iter().position(|name| *name == s).ok_or(()) }
fn digit(alphabet: &[u8], c: u8) -> Answer<Integer> {
    alphabet.iter().position(|v| *v == c).map(|i| i as Integer).ok_or(())
}
fn center_numerator(position: Integer, divisions: Integer, span: Integer) -> Integer {
    span * (2 * position + 1 - divisions)
}
fn compare(a: Integer, b: Integer, c: Integer, d: Integer) -> std::cmp::Ordering {
    (a * d).cmp(&(c * b))
}
fn mgrs_columns(zone: Integer) -> &'static [u8] {
    match zone % 3 {
        1 => b"ABCDEFGH",
        2 => b"JKLMNPQR",
        _ => b"STUVWXYZ",
    }
}
fn square_digits(a: &[&str], start: usize, e: &mut Integer, n: &mut Integer) -> Answer<Integer> {
    if a.len() == start { return Ok(100000); }
    require!(digits(a[start], 1, 5) && digits(a[start + 1], 1, 5) && a[start].len() == a[start + 1].len());
    let scale = 10_i64.pow((5 - a[start].len()) as u32);
    *e += integer(a[start], 0, 99999)? * scale;
    *n += integer(a[start + 1], 0, 99999)? * scale;
    Ok(scale)
}
impl Codec {
    fn new() -> Self {
        let mut grids: [Vec<Grid>; 6] = std::array::from_fn(|_| Vec::new());
        for p in 1..=9 {
            grids[0].push(Grid { precision: p, width: 1 << ((5 * p + 1) / 2), height: 1 << (5 * p / 2) });
        }
        let definitions: [&[(Integer, Integer, Integer)]; 5] = [
            &[(2,18,18), (4,180,180), (6,4320,4320), (8,43200,43200)],
            &[(2,18,9), (4,360,180), (6,7200,3600), (8,144000,72000), (10,2880000,1440000), (11,11520000,7200000)],
            &[(5,720,360), (6,1440,720), (7,4320,2160)],
            &[(2,24,12), (4,360,180), (8,21600,10800), (10,216000,108000), (12,2160000,1080000)],
            &[(4,360,270), (6,2880,2160), (8,28800,21600), (9,57600,43200), (10,115200,86400), (11,230400,172800)],
        ];
        for (i, entries) in definitions.iter().enumerate() {
            for &(precision, width, height) in entries.iter() { grids[i + 1].push(Grid { precision, width, height }); }
        }
        Self { grids }
    }
    fn precision_id(&self, system: usize, p: Integer) -> Answer<usize> {
        self.grids[system].iter().position(|g| g.precision == p).ok_or(())
    }
    fn precision_argument(&self, system: usize, s: &str) -> Answer<usize> {
        self.precision_id(system, integer(s, 0, 999999999)?)
    }
    fn point(&self, system: usize, precision: usize, latitude: Integer, longitude: Integer) -> Cell {
        let g = self.grids[system][precision];
        Cell { precision, x: (longitude + 180000000) * g.width / 360000000, y: ((latitude + 90000000) * g.height / 180000000).min(g.height - 1) }
    }
    fn ancestor(&self, system: usize, c: Cell, precision: usize) -> Cell {
        let g = self.grids[system][c.precision];
        let parent = self.grids[system][precision];
        Cell { precision, x: c.x * parent.width / g.width, y: c.y * parent.height / g.height }
    }
    fn encode(&self, system: usize, c: Cell) -> String {
        let p = self.grids[system][c.precision].precision as usize;
        let (mut x, mut y) = (c.x, c.y);
        let mut result = String::new();
        match system {
            0 => {
                let (a, b, mut value) = ((5 * p + 1) / 2, 5 * p / 2, 0);
                for i in 0..5 * p {
                    let bit = if i % 2 == 0 { x >> (a - 1 - i / 2) & 1 } else { y >> (b - 1 - i / 2) & 1 };
                    value = value * 2 + bit;
                    if i % 5 == 4 {
                        result.push(HASH[value as usize] as char);
                        value = 0;
                    }
                }
            }
            1 | 2 => {
                let count = if system == 1 { p / 2 } else { p.min(10) / 2 };
                let tail = if system == 2 && p == 11 {
                    let value = 4 * (y % 5) + x % 4;
                    x /= 4;
                    y /= 5;
                    Some(value)
                } else { None };
                let (mut xd, mut yd) = (vec![0; count], vec![0; count]);
                for i in (0..count).rev() {
                    let rx = if system == 1 { MAIDEN_ALPHABETS[i].len() as Integer } else if i == 0 { 18 } else { 20 };
                    let ry = if system == 1 { rx } else if i == 0 { 9 } else { 20 };
                    xd[i] = (x % rx) as usize;
                    yd[i] = (y % ry) as usize;
                    x /= rx;
                    y /= ry;
                }
                for i in 0..count {
                    if system == 1 {
                        result.push(MAIDEN_ALPHABETS[i][xd[i]] as char);
                        result.push(MAIDEN_ALPHABETS[i][yd[i]] as char);
                    } else {
                        result.push(PLUS[yd[i]] as char);
                        result.push(PLUS[xd[i]] as char);
                    }
                }
                if let Some(value) = tail { result.push(PLUS[value as usize] as char); }
                if system == 2 {
                    if p < 8 { result.push_str(&"0".repeat(8 - p)); }
                    result.insert(8, '+');
                }
            }
            3 => {
                let scale = if p == 5 { 1 } else if p == 6 { 2 } else { 6 };
                let base_y = y / scale;
                result = padded(x / scale + 1, 3);
                result.push(LETTERS[(base_y / 24) as usize] as char);
                result.push(LETTERS[(base_y % 24) as usize] as char);
                if p >= 6 {
                    let (xx, yy) = if p == 7 { (x / 3, y / 3) } else { (x, y) };
                    result.push((b'1' + (xx % 2 + 2 * (1 - yy % 2)) as u8) as char);
                }
                if p == 7 { result.push((b'1' + (x % 3 + 3 * (2 - y % 3)) as u8) as char); }
            }
            4 => {
                if p == 2 { return format!("{}{}", LETTERS[x as usize] as char, LETTERS[y as usize] as char); }
                let m = (p - 4) / 2;
                let scale = if p < 8 { 1 } else if m == 2 { 60 } else if m == 3 { 600 } else { 6000 };
                let (xx, yy) = (x / scale, y / scale);
                for value in [xx / 15, yy / 15, xx % 15, yy % 15] { result.push(LETTERS[value as usize] as char); }
                if p >= 8 { result.push_str(&(padded(x % scale, m) + &padded(y % scale, m))); }
            }
            _ => {
                let scale = MESH_SCALE[c.precision];
                x -= 280 * scale;
                y -= 135 * scale;
                if x < 0 || x >= 80 * scale || y < 0 || y >= 100 * scale { return result; }
                let count = c.precision + 1;
                let radices = [0, 8, 10, 2, 2, 2];
                let (mut xd, mut yd) = (vec![0; count], vec![0; count]);
                for i in (1..count).rev() {
                    xd[i] = x % radices[i];
                    yd[i] = y % radices[i];
                    x /= radices[i];
                    y /= radices[i];
                }
                result = padded(y, 2) + &padded(x, 2);
                for i in 1..count {
                    if i <= 2 {
                        result.push((b'0' + yd[i] as u8) as char);
                        result.push((b'0' + xd[i] as u8) as char);
                    } else { result.push((b'1' + (xd[i] + 2 * yd[i]) as u8) as char); }
                }
            }
        }
        result
    }
    fn decode(&self, system: usize, code: &str) -> Answer<Cell> {
        let bytes = code.as_bytes();
        let mut p = bytes.len();
        let (mut x, mut y) = (0, 0);
        match system {
            0 => {
                require!((1..=9).contains(&p));
                let mut position = 0;
                for &c in bytes {
                    let value = digit(HASH, c)?;
                    for bit in (0..=4).rev() {
                        if position % 2 == 0 {
                            x = 2 * x + (value >> bit & 1);
                        } else {
                            y = 2 * y + (value >> bit & 1);
                        }
                        position += 1;
                    }
                }
            }
            1 => {
                self.precision_id(system, p as Integer)?;
                for i in 0..p / 2 {
                    x = x * MAIDEN_ALPHABETS[i].len() as Integer + digit(MAIDEN_ALPHABETS[i], bytes[2 * i])?;
                    y = y * MAIDEN_ALPHABETS[i].len() as Integer + digit(MAIDEN_ALPHABETS[i], bytes[2 * i + 1])?;
                }
            }
            2 => {
                require!(p >= 9 && bytes[8] == b'+' && bytes.iter().filter(|&&c| c == b'+').count() == 1);
                let mut prefix = 0;
                while prefix < 8 && bytes[prefix] != b'0' {
                    digit(PLUS, bytes[prefix])?;
                    prefix += 1;
                }
                require!([2, 4, 6, 8].contains(&prefix));
                require!(bytes[prefix..8].iter().all(|&c| c == b'0'));
                let suffix = p - 9;
                require!(if prefix == 8 { [0, 2, 3].contains(&suffix) } else { suffix == 0 });
                require!(digit(PLUS, bytes[0])? <= 8 && digit(PLUS, bytes[1])? <= 17);
                let sequence: Vec<u8> = bytes[..prefix].iter().chain(bytes[9..].iter()).copied().collect();
                p = sequence.len();
                for i in 0..p.min(10) / 2 {
                    y = y * (if i == 0 { 9 } else { 20 }) + digit(PLUS, sequence[2 * i])?;
                    x = x * (if i == 0 { 18 } else { 20 }) + digit(PLUS, sequence[2 * i + 1])?;
                }
                if p == 11 {
                    let tail = digit(PLUS, sequence[10])?;
                    x = x * 4 + tail % 4;
                    y = y * 5 + tail / 4;
                }
            }
            3 => {
                require!((5..=7).contains(&p) && digits(&code[..3], 3, 3));
                x = integer(&code[..3], 1, 720)? - 1;
                let (a, b) = (digit(LETTERS, bytes[3])?, digit(LETTERS, bytes[4])?);
                require!(a < 15);
                y = 24 * a + b;
                if p >= 6 {
                    require!((b'1'..=b'4').contains(&bytes[5]));
                    let q = Integer::from(bytes[5] - b'1');
                    x = 2 * x + q % 2;
                    y = 2 * y + 1 - q / 2;
                }
                if p == 7 {
                    require!((b'1'..=b'9').contains(&bytes[6]));
                    let q = Integer::from(bytes[6] - b'1');
                    x = 3 * x + q % 3;
                    y = 3 * y + 2 - q / 3;
                }
            }
            4 => {
                self.precision_id(system, p as Integer)?;
                x = digit(LETTERS, bytes[0])?;
                y = digit(LETTERS, bytes[1])?;
                require!(y < 12);
                if p >= 4 {
                    let (a, b) = (digit(LETTERS, bytes[2])?, digit(LETTERS, bytes[3])?);
                    require!(a < 15 && b < 15);
                    x = 15 * x + a;
                    y = 15 * y + b;
                }
                if p >= 8 {
                    let m = (p - 4) / 2;
                    let scale = if m == 2 { 60 } else if m == 3 { 600 } else { 6000 };
                    require!(digits(&code[4..4 + m], m, m) && digits(&code[4 + m..], m, m));
                    x = x * scale + integer(&code[4..4 + m], 0, scale - 1)?;
                    y = y * scale + integer(&code[4 + m..], 0, scale - 1)?;
                }
            }
            _ => {
                let precision = self.precision_id(system, p as Integer)?;
                require!(digits(code, p, p));
                y = integer(&code[..2], 0, 99)?;
                x = integer(&code[2..4], 0, 79)?;
                if p >= 6 {
                    require!(bytes[4] <= b'7' && bytes[5] <= b'7');
                    y = y * 8 + Integer::from(bytes[4] - b'0');
                    x = x * 8 + Integer::from(bytes[5] - b'0');
                }
                if p >= 8 {
                    y = y * 10 + Integer::from(bytes[6] - b'0');
                    x = x * 10 + Integer::from(bytes[7] - b'0');
                }
                for &c in &bytes[8.min(p)..] {
                    require!((b'1'..=b'4').contains(&c));
                    let q = Integer::from(c - b'1');
                    x = x * 2 + q % 2;
                    y = y * 2 + q / 2;
                }
                x += 280 * MESH_SCALE[precision];
                y += 135 * MESH_SCALE[precision];
            }
        }
        Ok(Cell { precision: self.precision_id(system, p as Integer)?, x, y })
    }
    fn display(&self, system: usize, c: Cell) -> String {
        let code = self.encode(system, c);
        if code.is_empty() { "-".to_owned() } else { code }
    }
    fn relation(&self, sa: usize, a: Cell, sb: usize, b: Cell) -> &'static str {
        use std::cmp::Ordering::{Equal, Greater, Less};
        let (ga, gb) = (self.grids[sa][a.precision], self.grids[sb][b.precision]);
        let west = compare(a.x, ga.width, b.x, gb.width);
        let east = compare(a.x + 1, ga.width, b.x + 1, gb.width);
        let south = compare(a.y, ga.height, b.y, gb.height);
        let north = compare(a.y + 1, ga.height, b.y + 1, gb.height);
        if [west, east, south, north].iter().all(|v| *v == Equal) { return "EQUAL"; }
        if west != Less && east != Greater && south != Less && north != Greater { return "INSIDE"; }
        if west != Greater && east != Less && south != Greater && north != Less { return "CONTAINS"; }
        let x1 = compare(a.x, ga.width, b.x + 1, gb.width);
        let x2 = compare(b.x, gb.width, a.x + 1, ga.width);
        let y1 = compare(a.y, ga.height, b.y + 1, gb.height);
        let y2 = compare(b.y, gb.height, a.y + 1, ga.height);
        if [x1, x2, y1, y2].iter().all(|v| *v == Less) { return "OVERLAP"; }
        let wrap = a.x == 0 && b.x + 1 == gb.width || b.x == 0 && a.x + 1 == ga.width;
        if y1 != Greater && y2 != Greater && (x1 != Greater && x2 != Greater || wrap) { return "TOUCH"; }
        "DISJOINT"
    }
    fn prune(&self, system: usize, cells: &mut BTreeSet<Cell>) {
        let removed: Vec<Cell> = cells.iter().copied().filter(|&c| cells.iter().any(|&other| other.precision < c.precision && self.ancestor(system, c, other.precision) == other)).collect();
        for c in removed { cells.remove(&c); }
    }
    fn compact(&self, system: usize, codes: &[&str]) -> Answer<String> {
        let mut cells = BTreeSet::new();
        for code in codes { cells.insert(self.decode(system, code)?); }
        self.prune(system, &mut cells);
        loop {
            let mut merge = None;
            for &c in &cells {
                if c.precision == 0 { continue; }
                let parent = self.ancestor(system, c, c.precision - 1);
                let (g, pg) = (self.grids[system][c.precision], self.grids[system][parent.precision]);
                let needed = g.width / pg.width * (g.height / pg.height);
                if needed > cells.len() as Integer { continue; }
                let children: Vec<Cell> = cells.iter().copied().filter(|&other| other.precision == c.precision && self.ancestor(system, other, parent.precision) == parent).collect();
                if children.len() as Integer == needed {
                    merge = Some((parent, children));
                    break;
                }
            }
            if let Some((parent, children)) = merge {
                for child in children { cells.remove(&child); }
                cells.insert(parent);
                self.prune(system, &mut cells);
            } else { break; }
        }
        let mut ordered: Vec<Cell> = cells.into_iter().collect();
        ordered.sort_by_key(|c| (c.precision, -c.y, c.x));
        Ok(ordered.iter().map(|&c| self.encode(system, c)).collect::<Vec<_>>().join(" "))
    }
    fn execute(&self, a: &[&str]) -> Answer<String> {
        const NAMES: [&str; 23] = [
            "ENCODE", "DECODE", "NEIGHBORS", "PARENT", "CHILDREN", "COMMON",
            "COMPACT", "CONTAINS", "COVER", "CONVERT", "STEPS", "PATH", "RELATE",
            "SIZE", "SHORTEN", "RECOVER", "UTMZONE", "OSGB", "UNOSGB", "MGRS",
            "UNMGRS", "QUADKEY", "UNQUADKEY",
        ];
        const LENGTHS: [usize; 23] = [5,3,3,3,3,4,0,5,7,6,4,4,5,3,4,4,3,4,0,6,0,4,2];
        let command = NAMES.iter().position(|name| *name == a[0]).ok_or(())?;
        require!(match command {
            6 => (3..=102).contains(&a.len()),
            18 => a.len() == 2 || a.len() == 4,
            20 => a.len() == 3 || a.len() == 5,
            _ => a.len() == LENGTHS[command],
        });
        if command <= 13 {
            let system = system_id(a[1])?;
            if command == 0 {
                let (lat, lon) = (location(a[2], true)?, location(a[3], false)?);
                let precision = self.precision_argument(system, a[4])?;
                let code = self.encode(system, self.point(system, precision, lat, lon));
                return Ok(if code.is_empty() { "OUT OF AREA".to_owned() } else { code });
            }
            if command == 8 {
                let precision = self.precision_argument(system, a[2])?;
                let (lat1, lon1, lat2, lon2) = (location(a[3], true)?, location(a[4], false)?, location(a[5], true)?, location(a[6], false)?);
                require!(lat1 <= lat2);
                let (first, last) = (self.point(system, precision, lat1, lon1), self.point(system, precision, lat2, lon2));
                let g = self.grids[system][precision];
                let columns = if lon1 <= lon2 { last.x - first.x + 1 } else { g.width.min(last.x - first.x + 1 + g.width) };
                if (last.y - first.y + 1) * columns > 100 { return Ok("TOO MANY".to_owned()); }
                let mut result = Vec::new();
                for y in (first.y..=last.y).rev() {
                    for i in 0..columns { result.push(self.display(system, Cell { precision, x: (first.x + i) % g.width, y })); }
                }
                return Ok(result.join(" "));
            }
            if command == 13 {
                let precision = self.precision_argument(system, a[2])?;
                let g = self.grids[system][precision];
                let count = if system == 5 { 8000 * MESH_SCALE[precision] * MESH_SCALE[precision] } else { g.width * g.height };
                return Ok(format!("w={} h={} cells={}", coordinate(360000000 / g.width), coordinate(180000000 / g.height), count));
            }
            if command == 6 { return self.compact(system, &a[2..]); }
            let c = self.decode(system, a[2])?;
            let g = self.grids[system][c.precision];
            match command {
                1 => {
                    let (south, west) = (-90000000 + 180000000 * c.y / g.height, -180000000 + 360000000 * c.x / g.width);
                    let (north, east) = (-90000000 + 180000000 * (c.y + 1) / g.height, -180000000 + 360000000 * (c.x + 1) / g.width);
                    let (cy, cx) = (floor_ratio(center_numerator(c.y, g.height, 180000000), 2 * g.height), floor_ratio(center_numerator(c.x, g.width, 360000000), 2 * g.width));
                    return Ok(format!("sw={},{} ne={},{} c={},{}", coordinate(south), coordinate(west), coordinate(north), coordinate(east), coordinate(cy), coordinate(cx)));
                }
                2 => {
                    let dx = [0,1,1,1,0,-1,-1,-1];
                    let dy = [1,1,0,-1,-1,-1,0,1];
                    let result: Vec<String> = (0..8).map(|i| {
                        if c.y + dy[i] < 0 || c.y + dy[i] >= g.height { "-".to_owned() }
                        else { self.display(system, Cell { precision: c.precision, x: modulo(c.x + dx[i], g.width), y: c.y + dy[i] }) }
                    }).collect();
                    return Ok(result.join(" "));
                }
                3 => return Ok(if c.precision == 0 { "NONE".to_owned() } else { self.encode(system, self.ancestor(system, c, c.precision - 1)) }),
                4 => {
                    if c.precision + 1 == self.grids[system].len() { return Ok("NONE".to_owned()); }
                    let next = self.grids[system][c.precision + 1];
                    let (rx, ry) = (next.width / g.width, next.height / g.height);
                    if rx * ry > 100 { return Ok("TOO MANY".to_owned()); }
                    let mut result = Vec::new();
                    for j in (0..ry).rev() {
                        for i in 0..rx { result.push(self.display(system, Cell { precision: c.precision + 1, x: rx * c.x + i, y: ry * c.y + j })); }
                    }
                    return Ok(result.join(" "));
                }
                7 => {
                    let (lat, lon) = (location(a[3], true)?, location(a[4], false)?);
                    return Ok((if self.point(system, c.precision, lat, lon) == c { "YES" } else { "NO" }).to_owned());
                }
                9 => {
                    require!(a[3] == "TO");
                    let destination = system_id(a[4])?;
                    let precision = self.precision_argument(destination, a[5])?;
                    let next = self.grids[destination][precision];
                    let code = self.encode(destination, Cell { precision, x: (2 * c.x + 1) * next.width / (2 * g.width), y: (2 * c.y + 1) * next.height / (2 * g.height) });
                    return Ok(if code.is_empty() { "OUT OF AREA".to_owned() } else { code });
                }
                12 => {
                    let other_system = system_id(a[3])?;
                    return Ok(self.relation(system, c, other_system, self.decode(other_system, a[4])?).to_owned());
                }
                _ => {}
            }
            let other = self.decode(system, a[3])?;
            if command == 5 {
                for precision in (0..=c.precision.min(other.precision)).rev() {
                    let parent = self.ancestor(system, c, precision);
                    if parent == self.ancestor(system, other, precision) { return Ok(self.encode(system, parent)); }
                }
                return Ok("NONE".to_owned());
            }
            if c.precision != other.precision { return Ok("MISMATCH".to_owned()); }
            let (mut dx, dy) = (modulo(other.x - c.x, g.width), other.y - c.y);
            if dx > g.width / 2 { dx -= g.width; }
            if command == 10 { return Ok(format!("dx={} dy={}", dx, dy)); }
            let n = dx.abs().max(dy.abs());
            if n + 1 > 100 { return Ok("TOO MANY".to_owned()); }
            let mut result = Vec::new();
            for i in 0..=n {
                let x = c.x + if n == 0 { 0 } else { floor_ratio(2 * i * dx + n, 2 * n) };
                let y = c.y + if n == 0 { 0 } else { floor_ratio(2 * i * dy + n, 2 * n) };
                result.push(self.display(system, Cell { precision: c.precision, x: modulo(x, g.width), y }));
            }
            return Ok(result.join(" "));
        }
        if command == 14 || command == 15 {
            let (lat, lon) = (location(a[2], true)?, location(a[3], false)?);
            let mut full = a[1].to_owned();
            let mut removed = 0;
            if command == 15 {
                let plus = full.find('+').ok_or(())?;
                require!((plus == 2 || plus == 4) && full.bytes().filter(|&c| c == b'+').count() == 1);
                let suffix = full.len() - plus - 1;
                require!([0, 2, 3].contains(&suffix));
                for c in full.bytes().filter(|&c| c != b'+') { digit(PLUS, c)?; }
                removed = 8 - plus;
                let prefix = self.encode(2, self.point(2, self.precision_id(2, 10)?, lat, lon));
                full = prefix[..removed].to_owned() + &full;
            }
            let mut c = self.decode(2, &full)?;
            let g = self.grids[2][c.precision];
            require!(g.precision >= 8);
            let (cy, cx) = (center_numerator(c.y, g.height, 180000000), center_numerator(c.x, g.width, 360000000));
            let (yd, xd) = (2 * g.height, 2 * g.width);
            if command == 14 {
                if (cy - lat * yd).abs() < 15000 * yd && (cx - lon * xd).abs() < 15000 * xd { return Ok(full[6..].to_owned()); }
                if (cy - lat * yd).abs() < 300000 * yd && (cx - lon * xd).abs() < 300000 * xd { return Ok(full[4..].to_owned()); }
                return Ok(full);
            }
            let distance = if removed == 4 { 1000000 } else { 50000 };
            let (my, mx) = (distance * g.height / 180000000, distance * g.width / 360000000);
            if (lat + distance / 2) * yd < cy && cy - distance * yd >= -90000000 * yd { c.y -= my; }
            else if (lat - distance / 2) * yd > cy && cy + distance * yd <= 90000000 * yd { c.y += my; }
            if (lon + distance / 2) * xd < cx { c.x = modulo(c.x - mx, g.width); }
            else if (lon - distance / 2) * xd > cx { c.x = modulo(c.x + mx, g.width); }
            return Ok(self.encode(2, c));
        }
        if command == 16 {
            let (lat, lon) = (location(a[1], true)?, location(a[2], false)?);
            if !(-80000000..84000000).contains(&lat) { return Ok("NONE".to_owned()); }
            let band = BANDS[((lat + 80000000) / 8000000).min(19) as usize];
            let mut zone = (lon + 180000000) / 6000000 + 1;
            if band == b'V' && (3000000..12000000).contains(&lon) { zone = 32; }
            if band == b'X' && (0..42000000).contains(&lon) {
                zone = if lon < 9000000 { 31 } else if lon < 21000000 { 33 } else if lon < 33000000 { 35 } else { 37 };
            }
            return Ok(format!("{}{}", zone, band as char));
        }
        if command == 17 || command == 19 {
            let (e, n, d);
            let mut prefix;
            if command == 17 {
                e = integer(a[1], 0, 699999)?;
                n = integer(a[2], 0, 1299999)?;
                d = integer(a[3], 0, 5)? as usize;
                prefix = format!("{}{}", OS_LETTERS[(5 * (3 - n / 500000) + 2 + e / 500000) as usize] as char, OS_LETTERS[(5 * (4 - n / 100000 % 5) + e / 100000 % 5) as usize] as char);
            } else {
                let zone = integer(a[1], 1, 60)?;
                require!(a[2].len() == 1);
                digit(BANDS, a[2].as_bytes()[0])?;
                e = integer(a[3], 100000, 899999)?;
                n = integer(a[4], 0, 9999999)?;
                d = integer(a[5], 0, 5)? as usize;
                prefix = format!("{}{} {}{}", zone, a[2], mgrs_columns(zone)[(e / 100000 - 1) as usize] as char, MGRS_ROWS[((n / 100000 + if zone % 2 == 0 { 5 } else { 0 }) % 20) as usize] as char);
            }
            if d > 0 { prefix.push_str(&format!(" {} {}", &padded(e % 100000, 5)[..d], &padded(n % 100000, 5)[..d])); }
            return Ok(prefix);
        }
        if command == 18 || command == 20 {
            let (mut e, mut n, scale);
            let mut prefix = String::new();
            if command == 18 {
                require!(a[1].len() == 2);
                let (first, second) = (digit(OS_LETTERS, a[1].as_bytes()[0])?, digit(OS_LETTERS, a[1].as_bytes()[1])?);
                e = 500000 * (first % 5 - 2) + 100000 * (second % 5);
                n = 500000 * (3 - first / 5) + 100000 * (4 - second / 5);
                require!((0..700000).contains(&e) && (0..1300000).contains(&n));
                scale = square_digits(a, 2, &mut e, &mut n)?;
            } else {
                require!(a[1].len() == 2 || a[1].len() == 3);
                let zone_text = &a[1][..a[1].len() - 1];
                require!(digits(zone_text, 1, 2) && zone_text.as_bytes()[0] != b'0');
                let zone = integer(zone_text, 1, 60)?;
                digit(BANDS, a[1].as_bytes()[a[1].len() - 1])?;
                require!(a[2].len() == 2);
                e = 100000 * (digit(mgrs_columns(zone), a[2].as_bytes()[0])? + 1);
                n = 100000 * modulo(digit(MGRS_ROWS, a[2].as_bytes()[1])? - (if zone % 2 == 0 { 5 } else { 0 }), 20);
                scale = square_digits(a, 3, &mut e, &mut n)?;
                prefix = a[1].to_owned() + " ";
            }
            return Ok(format!("{}sw={},{} size={}", prefix, e, n, scale));
        }
        if command == 21 {
            let z = integer(a[3], 1, 23)?;
            let (x, y) = (integer(a[1], 0, (1 << z) - 1)?, integer(a[2], 0, (1 << z) - 1)?);
            let key: String = (0..z).rev().map(|i| (b'0' + ((x >> i & 1) + 2 * (y >> i & 1)) as u8) as char).collect();
            return Ok(key);
        }
        require!((1..=23).contains(&a[1].len()));
        let (mut x, mut y) = (0, 0);
        for c in a[1].bytes() {
            require!((b'0'..=b'3').contains(&c));
            let q = Integer::from(c - b'0');
            x = 2 * x + q % 2;
            y = 2 * y + q / 2;
        }
        Ok(format!("x={} y={} z={}", x, y, a[1].len()))
    }
}
fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut lines = input.lines();
    let count: usize = lines.next().unwrap().parse().unwrap();
    let codec = Codec::new();
    let mut output = String::new();
    for _ in 0..count {
        let arguments: Vec<&str> = lines.next().unwrap().split(' ').collect();
        let answer = codec.execute(&arguments).unwrap_or_else(|_| "INVALID".to_owned());
        output.push_str(&answer);
        output.push('\n');
    }
    print!("{}", output);
}
