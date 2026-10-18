use std::io::{self, BufRead, Write};

type Color = [i64; 3];

struct Entry {
    name: String,
    color: Color,
}

struct Spec {
    name: &'static str,
    signature: &'static str,
    minimum: usize,
    maximum: usize,
    low: [i64; 4],
    high: [i64; 4],
    keywords: &'static str,
}

struct Arguments {
    colors: [Color; 33],
    numbers: [i64; 33],
    keyword: usize,
}

fn rounded(numerator: i64, denominator: i64) -> i64 {
    (2 * numerator + denominator).div_euclid(2 * denominator)
}

fn away(numerator: i64, denominator: i64) -> i64 {
    if numerator < 0 { -rounded(-numerator, denominator) }
    else { rounded(numerator, denominator) }
}

fn distance(a: Color, b: Color) -> i64 {
    (0..3).map(|j| (a[j] - b[j]) * (a[j] - b[j])).sum()
}

fn hue(c: Color) -> i64 {
    let maximum = *c.iter().max().unwrap();
    let minimum = *c.iter().min().unwrap();
    let delta = maximum - minimum;
    if delta == 0 { return 0; }
    let mut numerator;
    if maximum == c[0] {
        numerator = 60 * (c[1] - c[2]);
        if numerator < 0 { numerator += 360 * delta; }
    } else if maximum == c[1] {
        numerator = 60 * (c[2] - c[0]) + 120 * delta;
    } else {
        numerator = 60 * (c[0] - c[1]) + 240 * delta;
    }
    rounded(numerator, delta) % 360
}

fn hsl(c: Color) -> [i64; 3] {
    let maximum = *c.iter().max().unwrap();
    let minimum = *c.iter().min().unwrap();
    let delta = maximum - minimum;
    let saturation = if delta == 0 { 0 }
        else { rounded(100 * delta, 255 - (maximum + minimum - 255).abs()) };
    [hue(c), saturation, rounded(100 * (maximum + minimum), 510)]
}

fn sector(h: i64) -> Color {
    let q = h / 60;
    let f = h % 60;
    let x = if q % 2 == 0 { f } else { 60 - f };
    match q {
        0 => [60, x, 0],
        1 => [x, 60, 0],
        2 => [0, 60, x],
        3 => [0, x, 60],
        4 => [x, 0, 60],
        _ => [60, 0, x],
    }
}

fn from_hsl(h: i64, s: i64, l: i64) -> Color {
    let chroma = (100 - (2 * l - 100).abs()) * s;
    let offset = 30 * (200 * l - chroma);
    sector(h).map(|x| rounded(255 * (x * chroma + offset), 600000))
}

fn from_hsv(h: i64, s: i64, v: i64) -> Color {
    let chroma = v * s;
    let offset = 60 * (100 * v - chroma);
    sector(h).map(|x| rounded(255 * (x * chroma + offset), 600000))
}

fn from_hwb(h: i64, w: i64, k: i64) -> Color {
    if w + k >= 100 { return [rounded(255 * w, w + k); 3]; }
    sector(h).map(|x| rounded(255 * (x * (100 - w - k) + 60 * w), 6000))
}

fn ansi_color(index: usize) -> Color {
    const LEVELS: [i64; 6] = [0, 95, 135, 175, 215, 255];
    if index < 16 { return BUILTINS[index].1; }
    if index >= 232 { return [8 + 10 * (index as i64 - 232); 3]; }
    let code = index - 16;
    [LEVELS[code / 36], LEVELS[code / 6 % 6], LEVELS[code % 6]]
}

fn contrast(a: Color, b: Color) -> (i64, &'static str) {
    let luminance = |c: Color| 2126 * c[0] * c[0] + 7152 * c[1] * c[1] + 722 * c[2] * c[2];
    let (y1, y2) = (luminance(a), luminance(b));
    let high = y1.max(y2) + 32512500;
    let low = y1.min(y2) + 32512500;
    let verdict = if high >= 7 * low { "AAA" }
        else if 2 * high >= 9 * low { "AA" } else { "FAIL" };
    (rounded(100 * high, low), verdict)
}

fn contrast_text(c: Color, background: Color) -> String {
    let (ratio, verdict) = contrast(c, background);
    format!("{}.{:02} {}", ratio / 100, ratio % 100, verdict)
}

fn hex(c: Color) -> String {
    format!("#{:02X}{:02X}{:02X}", c[0], c[1], c[2])
}

fn rotate(c: Color, degrees: i64) -> Color {
    let [h, s, l] = hsl(c);
    from_hsl((h + degrees).rem_euclid(360), s, l)
}

fn interpolate(first: Color, last: Color, i: i64, denominator: i64) -> Color {
    std::array::from_fn(|j| first[j] + away((last[j] - first[j]) * i, denominator))
}

fn blend(mode: usize, base: Color, top: Color) -> Color {
    if mode >= 13 {
        let mut a = hsl(base);
        let b = hsl(top);
        if mode == 13 || mode == 15 { a[0] = b[0]; }
        if mode == 14 || mode == 15 { a[1] = b[1]; }
        if mode == 16 { a[2] = b[2]; }
        return from_hsl(a[0], a[1], a[2]);
    }
    std::array::from_fn(|j| {
        let (x, y) = (base[j], top[j]);
        match mode {
            0 => x * y / 255,
            1 => 255 - (255 - x) * (255 - y) / 255,
            2 | 3 => {
                if (if mode == 2 { x } else { y }) < 128 { 2 * x * y / 255 }
                else { 255 - 2 * (255 - x) * (255 - y) / 255 }
            }
            4 => {
                let multiply = x * y / 255;
                let screen = 255 - (255 - x) * (255 - y) / 255;
                ((255 - x) * multiply + x * screen) / 255
            }
            5 => x.min(y),
            6 => x.max(y),
            7 => (x - y).abs(),
            8 => x + y - 2 * x * y / 255,
            9 => 255.min(x + y),
            10 => 0.max(x - y),
            11 => if y == 255 { 255 } else { 255.min(255 * x / (255 - y)) },
            12 => if y == 0 { 0 } else { 0.max(255 - 255 * (255 - x) / y) },
            _ => unreachable!(),
        }
    })
}

fn mean(colors: &[Color]) -> Color {
    std::array::from_fn(|j| rounded(colors.iter().map(|c| c[j]).sum(), colors.len() as i64))
}

fn palette(colors: &[Color], wanted: usize) -> Vec<(Color, usize)> {
    let mut boxes = vec![colors.to_vec()];
    while boxes.len() < wanted {
        let (mut chosen, mut channel, mut best_width) = (0, 0, -1);
        for (i, colors) in boxes.iter().enumerate() {
            if colors.len() < 2 { continue; }
            let (mut width, mut component) = (-1, 0);
            for j in 0..3 {
                let minimum = colors.iter().map(|c| c[j]).min().unwrap();
                let maximum = colors.iter().map(|c| c[j]).max().unwrap();
                if maximum - minimum > width {
                    width = maximum - minimum;
                    component = j;
                }
            }
            if width > best_width {
                best_width = width;
                chosen = i;
                channel = component;
            }
        }
        let mut selected = boxes.remove(chosen);
        selected.sort_by_key(|c| c[channel]);
        let right = selected.split_off(selected.len() / 2);
        boxes.insert(chosen, selected);
        boxes.insert(chosen + 1, right);
    }
    boxes.iter().map(|colors| (mean(colors), colors.len())).collect()
}

fn kmeans(colors: &[Color], wanted: usize) -> (usize, Vec<(Color, usize)>) {
    let mut representatives: Vec<Color> = palette(colors, wanted).iter().map(|item| item.0).collect();
    for iteration in 1..=20 {
        let mut sums = vec![[0; 3]; wanted];
        let mut counts = vec![0; wanted];
        for &color in colors {
            let mut closest = 0;
            for j in 1..wanted {
                if distance(color, representatives[j]) < distance(color, representatives[closest]) {
                    closest = j;
                }
            }
            counts[closest] += 1;
            for j in 0..3 { sums[closest][j] += color[j]; }
        }
        let mut unchanged = true;
        for i in 0..wanted {
            if counts[i] == 0 { continue; }
            let updated = sums[i].map(|x| rounded(x, counts[i] as i64));
            if updated != representatives[i] { unchanged = false; }
            representatives[i] = updated;
        }
        if unchanged || iteration == 20 {
            return (iteration, representatives.into_iter().zip(counts).collect());
        }
    }
    unreachable!()
}

fn parse_integer(text: &str, low: i64, high: i64) -> Option<i64> {
    let digits = text.strip_prefix('-').unwrap_or(text);
    if digits.is_empty() || digits.len() > 9 || !digits.bytes().all(|c| c.is_ascii_digit()) {
        return None;
    }
    let value = text.parse::<i64>().ok()?;
    if value < low || value > high { None } else { Some(value) }
}

fn valid_name(text: &str) -> bool {
    (1..=12).contains(&text.len()) && text.bytes().all(|c| c.is_ascii_lowercase())
}

fn hex_digit(c: u8) -> Option<i64> {
    match c {
        b'0'..=b'9' => Some(i64::from(c - b'0')),
        b'a'..=b'f' => Some(i64::from(c - b'a' + 10)),
        b'A'..=b'F' => Some(i64::from(c - b'A' + 10)),
        _ => None,
    }
}

fn parse_color(text: &str, registry: &[Entry]) -> Option<Color> {
    let bytes = text.as_bytes();
    if text.starts_with('#') {
        if bytes.len() != 4 && bytes.len() != 7 { return None; }
        let mut result = [0; 3];
        for j in 0..3 {
            result[j] = if bytes.len() == 4 { 17 * hex_digit(bytes[j + 1])? }
                else { 16 * hex_digit(bytes[2 * j + 1])? + hex_digit(bytes[2 * j + 2])? };
        }
        return Some(result);
    }
    if text.starts_with("rgb(") {
        let inner = text.strip_prefix("rgb(")?.strip_suffix(')')?;
        let parts: Vec<&str> = inner.split(',').collect();
        if parts.len() != 3 { return None; }
        let mut result = [0; 3];
        for j in 0..3 {
            if parts[j].is_empty() || parts[j].len() > 3 || !parts[j].bytes().all(|c| c.is_ascii_digit()) {
                return None;
            }
            result[j] = parts[j].parse().ok()?;
            if result[j] > 255 { return None; }
        }
        return Some(result);
    }
    for &(name, color) in &BUILTINS {
        if text == name { return Some(color); }
    }
    registry.iter().find(|entry| entry.name == text).map(|entry| entry.color)
}

fn table(registry: &[Entry]) -> impl Iterator<Item = (&str, Color)> + '_ {
    BUILTINS.iter().copied()
        .chain(registry.iter().map(|entry| (entry.name.as_str(), entry.color)))
}

fn prepare(spec: &Spec, words: &[&str], registry: &[Entry]) -> Option<Arguments> {
    if words.len() < spec.minimum || words.len() > spec.maximum { return None; }
    let mut args = Arguments { colors: [[0; 3]; 33], numbers: [0; 33], keyword: 0 };
    let signature = spec.signature.as_bytes();
    for (i, &word) in words.iter().enumerate() {
        let kind = match signature.first() {
            Some(b'*') => b'C',
            Some(b'P') => if i == 0 { b'I' } else { b'C' },
            _ => signature[i],
        };
        match kind {
            b'C' => args.colors[i] = parse_color(word, registry)?,
            b'I' => {
                let (low, high) = if signature[0] == b'P' { (1, 32) } else { (spec.low[i], spec.high[i]) };
                args.numbers[i] = parse_integer(word, low, high)?;
            }
            b'N' => if !valid_name(word) { return None; },
            b'K' => args.keyword = spec.keywords.split('|').position(|candidate| candidate == word)?,
            b'W' => {
                if word.len() != 6 || !word.starts_with("0x") { return None; }
                let mut value = 0;
                for digit in word.bytes().skip(2) { value = 16 * value + hex_digit(digit)?; }
                args.numbers[i] = value;
            }
            _ => unreachable!(),
        }
    }
    if spec.signature == "P" && args.numbers[0] as usize > words.len() - 1 { return None; }
    if spec.name == "DEFINE" && BUILTINS.iter().any(|&(name, _)| name == words[0]) { return None; }
    if spec.name == "UNDEFINE" && !registry.iter().any(|entry| entry.name == words[0]) { return None; }
    Some(args)
}

fn model(name: &str, c: Color) -> String {
    let maximum = *c.iter().max().unwrap();
    let minimum = *c.iter().min().unwrap();
    let [r, g, b] = c;
    match name {
        "HSL" => {
            let [h, s, l] = hsl(c);
            format!("hsl({h},{s}%,{l}%)")
        }
        "HSV" => {
            let s = if maximum == 0 { 0 } else { rounded(100 * (maximum - minimum), maximum) };
            format!("hsv({},{}%,{}%)", hue(c), s, rounded(100 * maximum, 255))
        }
        "HWB" => format!("hwb({},{}%,{}%)", hue(c), rounded(100 * minimum, 255), rounded(100 * (255 - maximum), 255)),
        "CMYK" => {
            let cyan = if maximum == 0 { 0 } else { rounded(100 * (maximum - r), maximum) };
            let magenta = if maximum == 0 { 0 } else { rounded(100 * (maximum - g), maximum) };
            let yellow = if maximum == 0 { 0 } else { rounded(100 * (maximum - b), maximum) };
            format!("cmyk({}%,{}%,{}%,{}%)", cyan, magenta, yellow, rounded(100 * (255 - maximum), 255))
        }
        "YCBCR" => format!("ycbcr({},{},{})", rounded(299 * r + 587 * g + 114 * b, 1000).clamp(0, 255),
            rounded(128000 - 169 * r - 331 * g + 500 * b, 1000).clamp(0, 255),
            rounded(128000 + 500 * r - 419 * g - 81 * b, 1000).clamp(0, 255)),
        "YIQ" => format!("yiq({},{},{})", rounded(299 * r + 587 * g + 114 * b, 1000),
            rounded(596 * r - 274 * g - 322 * b, 1000), rounded(211 * r - 523 * g + 312 * b, 1000)),
        _ => unreachable!(),
    }
}

const BUILTINS: [(&str, Color); 24] = [
    ("black", [0, 0, 0]),
    ("maroon", [128, 0, 0]),
    ("green", [0, 128, 0]),
    ("olive", [128, 128, 0]),
    ("navy", [0, 0, 128]),
    ("purple", [128, 0, 128]),
    ("teal", [0, 128, 128]),
    ("silver", [192, 192, 192]),
    ("gray", [128, 128, 128]),
    ("red", [255, 0, 0]),
    ("lime", [0, 255, 0]),
    ("yellow", [255, 255, 0]),
    ("blue", [0, 0, 255]),
    ("magenta", [255, 0, 255]),
    ("cyan", [0, 255, 255]),
    ("white", [255, 255, 255]),
    ("orange", [255, 165, 0]),
    ("pink", [255, 192, 203]),
    ("brown", [165, 42, 42]),
    ("gold", [255, 215, 0]),
    ("coral", [255, 127, 80]),
    ("salmon", [250, 128, 114]),
    ("violet", [238, 130, 238]),
    ("indigo", [75, 0, 130]),
];

const SPECS: [Spec; 53] = [
    Spec { name: "PARSE", signature: "C", minimum: 1, maximum: 1,
           low: [0; 4], high: [0; 4], keywords: "" },
    Spec { name: "DEFINE", signature: "NC", minimum: 2, maximum: 2,
           low: [0; 4], high: [0; 4], keywords: "" },
    Spec { name: "UNDEFINE", signature: "N", minimum: 1, maximum: 1,
           low: [0; 4], high: [0; 4], keywords: "" },
    Spec { name: "LIST", signature: "", minimum: 0, maximum: 0,
           low: [0; 4], high: [0; 4], keywords: "" },
    Spec { name: "HSL", signature: "C", minimum: 1, maximum: 1,
           low: [0; 4], high: [0; 4], keywords: "" },
    Spec { name: "FROMHSL", signature: "III", minimum: 3, maximum: 3,
           low: [0; 4], high: [359,100,100,0], keywords: "" },
    Spec { name: "HSV", signature: "C", minimum: 1, maximum: 1,
           low: [0; 4], high: [0; 4], keywords: "" },
    Spec { name: "FROMHSV", signature: "III", minimum: 3, maximum: 3,
           low: [0; 4], high: [359,100,100,0], keywords: "" },
    Spec { name: "HWB", signature: "C", minimum: 1, maximum: 1,
           low: [0; 4], high: [0; 4], keywords: "" },
    Spec { name: "FROMHWB", signature: "III", minimum: 3, maximum: 3,
           low: [0; 4], high: [359,100,100,0], keywords: "" },
    Spec { name: "CMYK", signature: "C", minimum: 1, maximum: 1,
           low: [0; 4], high: [0; 4], keywords: "" },
    Spec { name: "FROMCMYK", signature: "IIII", minimum: 4, maximum: 4,
           low: [0; 4], high: [100,100,100,100], keywords: "" },
    Spec { name: "YCBCR", signature: "C", minimum: 1, maximum: 1,
           low: [0; 4], high: [0; 4], keywords: "" },
    Spec { name: "FROMYCBCR", signature: "III", minimum: 3, maximum: 3,
           low: [0; 4], high: [255,255,255,0], keywords: "" },
    Spec { name: "YIQ", signature: "C", minimum: 1, maximum: 1,
           low: [0; 4], high: [0; 4], keywords: "" },
    Spec { name: "FROMYIQ", signature: "III", minimum: 3, maximum: 3,
           low: [0,-255,-255,0], high: [255,255,255,0], keywords: "" },
    Spec { name: "RGB565", signature: "C", minimum: 1, maximum: 1,
           low: [0; 4], high: [0; 4], keywords: "" },
    Spec { name: "FROM565", signature: "W", minimum: 1, maximum: 1,
           low: [0; 4], high: [0; 4], keywords: "" },
    Spec { name: "ANSI", signature: "C", minimum: 1, maximum: 1,
           low: [0; 4], high: [0; 4], keywords: "" },
    Spec { name: "FROMANSI", signature: "I", minimum: 1, maximum: 1,
           low: [0; 4], high: [255,0,0,0], keywords: "" },
    Spec { name: "WEBSAFE", signature: "C", minimum: 1, maximum: 1,
           low: [0; 4], high: [0; 4], keywords: "" },
    Spec { name: "GRAY", signature: "CK", minimum: 2, maximum: 2,
           low: [0; 4], high: [0; 4], keywords: "LUMA|AVERAGE|LIGHTNESS|HSP" },
    Spec { name: "INVERT", signature: "C", minimum: 1, maximum: 1,
           low: [0; 4], high: [0; 4], keywords: "" },
    Spec { name: "MIX", signature: "CCI", minimum: 3, maximum: 3,
           low: [0; 4], high: [0,0,100,0], keywords: "" },
    Spec { name: "MIXHSL", signature: "CCI", minimum: 3, maximum: 3,
           low: [0; 4], high: [0,0,100,0], keywords: "" },
    Spec { name: "GRADIENT", signature: "CCI", minimum: 3, maximum: 3,
           low: [0,0,2,0], high: [0,0,16,0], keywords: "" },
    Spec { name: "TINTS", signature: "CI", minimum: 2, maximum: 2,
           low: [0,1,0,0], high: [0,10,0,0], keywords: "" },
    Spec { name: "SHADES", signature: "CI", minimum: 2, maximum: 2,
           low: [0,1,0,0], high: [0,10,0,0], keywords: "" },
    Spec { name: "TONES", signature: "CI", minimum: 2, maximum: 2,
           low: [0,1,0,0], high: [0,10,0,0], keywords: "" },
    Spec { name: "BLEND", signature: "KCC", minimum: 3, maximum: 3,
           low: [0; 4], high: [0; 4], keywords: "MULTIPLY|SCREEN|OVERLAY|HARDLIGHT|SOFTLIGHT|DARKEN|LIGHTEN|DIFFERENCE|EXCLUSION|ADD|SUBTRACT|COLORDODGE|COLORBURN|HUE|SATURATION|COLOR|LUMINOSITY" },
    Spec { name: "ALPHA", signature: "CICI", minimum: 4, maximum: 4,
           low: [0; 4], high: [0,100,0,100], keywords: "" },
    Spec { name: "SIMULATE", signature: "CK", minimum: 2, maximum: 2,
           low: [0; 4], high: [0; 4], keywords: "PROTANOPIA|DEUTERANOPIA|TRITANOPIA|ACHROMATOPSIA" },
    Spec { name: "ROTATE", signature: "CI", minimum: 2, maximum: 2,
           low: [0,-720,0,0], high: [0,720,0,0], keywords: "" },
    Spec { name: "COMPLEMENT", signature: "C", minimum: 1, maximum: 1,
           low: [0; 4], high: [0; 4], keywords: "" },
    Spec { name: "TRIADIC", signature: "C", minimum: 1, maximum: 1,
           low: [0; 4], high: [0; 4], keywords: "" },
    Spec { name: "TETRADIC", signature: "C", minimum: 1, maximum: 1,
           low: [0; 4], high: [0; 4], keywords: "" },
    Spec { name: "SPLITCOMP", signature: "C", minimum: 1, maximum: 1,
           low: [0; 4], high: [0; 4], keywords: "" },
    Spec { name: "ANALOGOUS", signature: "CII", minimum: 3, maximum: 3,
           low: [0,1,1,0], high: [0,6,60,0], keywords: "" },
    Spec { name: "LIGHTEN", signature: "CI", minimum: 2, maximum: 2,
           low: [0; 4], high: [0,100,0,0], keywords: "" },
    Spec { name: "DARKEN", signature: "CI", minimum: 2, maximum: 2,
           low: [0; 4], high: [0,100,0,0], keywords: "" },
    Spec { name: "SATURATE", signature: "CI", minimum: 2, maximum: 2,
           low: [0; 4], high: [0,100,0,0], keywords: "" },
    Spec { name: "DESATURATE", signature: "CI", minimum: 2, maximum: 2,
           low: [0; 4], high: [0,100,0,0], keywords: "" },
    Spec { name: "NEAREST", signature: "C", minimum: 1, maximum: 1,
           low: [0; 4], high: [0; 4], keywords: "" },
    Spec { name: "DISTANCE", signature: "CC", minimum: 2, maximum: 2,
           low: [0; 4], high: [0; 4], keywords: "" },
    Spec { name: "CONTRAST", signature: "CC", minimum: 2, maximum: 2,
           low: [0; 4], high: [0; 4], keywords: "" },
    Spec { name: "ACCESSIBLE", signature: "CC", minimum: 2, maximum: 2,
           low: [0; 4], high: [0; 4], keywords: "" },
    Spec { name: "BEST", signature: "*", minimum: 2, maximum: 33,
           low: [0; 4], high: [0; 4], keywords: "" },
    Spec { name: "DESCRIBE", signature: "C", minimum: 1, maximum: 1,
           low: [0; 4], high: [0; 4], keywords: "" },
    Spec { name: "PALETTE", signature: "P", minimum: 2, maximum: 33,
           low: [0; 4], high: [0; 4], keywords: "" },
    Spec { name: "KMEANS", signature: "P", minimum: 2, maximum: 33,
           low: [0; 4], high: [0; 4], keywords: "" },
    Spec { name: "SORT", signature: "*", minimum: 1, maximum: 32,
           low: [0; 4], high: [0; 4], keywords: "" },
    Spec { name: "DITHER", signature: "*", minimum: 1, maximum: 32,
           low: [0; 4], high: [0; 4], keywords: "" },
    Spec { name: "RANDOM", signature: "II", minimum: 2, maximum: 2,
           low: [1,1,0,0], high: [999999999,16,0,0], keywords: "" },
];

fn run(line: &str, registry: &mut Vec<Entry>) -> Option<String> {
    let tokens: Vec<&str> = line.split(' ').collect();
    let spec = SPECS.iter().find(|spec| spec.name == tokens[0])?;
    let words = &tokens[1..];
    let args = prepare(spec, words, registry)?;
    let c = args.colors[0];
    let [a, b, d] = [args.numbers[0], args.numbers[1], args.numbers[2]];
    let mut output = Vec::new();
    match spec.name {
        "DEFINE" => {
            output.push(format!("{} {}", words[0], hex(args.colors[1])));
            if let Some(entry) = registry.iter_mut().find(|entry| entry.name == words[0]) {
                entry.color = args.colors[1];
            } else {
                registry.push(Entry { name: words[0].to_string(), color: args.colors[1] });
            }
        }
        "UNDEFINE" => {
            output.push(format!("{} removed", words[0]));
            let index = registry.iter().position(|entry| entry.name == words[0]).unwrap();
            registry.remove(index);
        }
        "LIST" => {
            let mut sorted: Vec<&Entry> = registry.iter().collect();
            sorted.sort_by(|a, b| a.name.cmp(&b.name));
            for entry in sorted { output.push(format!("{}={}", entry.name, hex(entry.color))); }
            if output.is_empty() { output.push("NONE".to_string()); }
        }
        "PARSE" => {
            output.push(hex(c));
            output.push(format!("rgb({},{},{})", c[0], c[1], c[2]));
            for name in ["HSL", "HSV", "HWB", "CMYK", "YCBCR", "YIQ"] { output.push(model(name, c)); }
            let name = table(registry).find(|entry| entry.1 == c).map_or("-", |entry| entry.0);
            output.push(name.to_string());
        }
        "HSL" | "HSV" | "HWB" | "CMYK" | "YCBCR" | "YIQ" => output.push(model(spec.name, c)),
        "FROMHSL" => output.push(hex(from_hsl(a, b, d))),
        "FROMHSV" => output.push(hex(from_hsv(a, b, d))),
        "FROMHWB" => output.push(hex(from_hwb(a, b, d))),
        "FROMCMYK" => output.push(hex(std::array::from_fn(|j|
            rounded(255 * (100 - args.numbers[j]) * (100 - args.numbers[3]), 10000)))),
        "FROMYCBCR" => output.push(hex([
            rounded(1000 * a + 1402 * (d - 128), 1000).clamp(0, 255),
            rounded(1000 * a - 344 * (b - 128) - 714 * (d - 128), 1000).clamp(0, 255),
            rounded(1000 * a + 1772 * (b - 128), 1000).clamp(0, 255),
        ])),
        "FROMYIQ" => output.push(hex([
            rounded(1000 * a + 956 * b + 619 * d, 1000).clamp(0, 255),
            rounded(1000 * a - 272 * b - 647 * d, 1000).clamp(0, 255),
            rounded(1000 * a - 1106 * b + 1703 * d, 1000).clamp(0, 255),
        ])),
        "RGB565" => {
            let value = 2048 * rounded(31 * c[0], 255) + 32 * rounded(63 * c[1], 255)
                + rounded(31 * c[2], 255);
            output.push(format!("0x{value:04X}"));
        }
        "FROM565" => output.push(hex([
            rounded(255 * (a / 2048), 31), rounded(255 * (a / 32 % 64), 63), rounded(255 * (a % 32), 31),
        ])),
        "FROMANSI" => output.push(hex(ansi_color(a as usize))),
        "ANSI" => {
            let mut best = 16;
            for i in 17..=255 {
                if distance(c, ansi_color(i)) < distance(c, ansi_color(best)) { best = i; }
            }
            output.push(format!("{} {} {}", best, hex(ansi_color(best)), distance(c, ansi_color(best))));
        }
        "WEBSAFE" => output.push(hex(c.map(|x| 51 * rounded(x, 51)))),
        "GRAY" => {
            let maximum = *c.iter().max().unwrap();
            let minimum = *c.iter().min().unwrap();
            let value = match args.keyword {
                0 => rounded(299 * c[0] + 587 * c[1] + 114 * c[2], 1000),
                1 => rounded(c[0] + c[1] + c[2], 3),
                2 => rounded(maximum + minimum, 2),
                _ => ((299 * c[0] * c[0] + 587 * c[1] * c[1] + 114 * c[2] * c[2]) / 1000).isqrt(),
            };
            output.push(hex([value; 3]));
        }
        "INVERT" => output.push(hex(c.map(|x| 255 - x))),
        "MIX" => output.push(hex(std::array::from_fn(|j|
            rounded(c[j] * (100 - d) + args.colors[1][j] * d, 100)))),
        "MIXHSL" => {
            let first = hsl(c);
            let last = hsl(args.colors[1]);
            let mut delta = (last[0] - first[0]).rem_euclid(360);
            if delta > 180 { delta -= 360; }
            output.push(hex(from_hsl((first[0] + away(delta * d, 100)).rem_euclid(360),
                first[1] + away((last[1] - first[1]) * d, 100),
                first[2] + away((last[2] - first[2]) * d, 100))));
        }
        "GRADIENT" => {
            for i in 0..d { output.push(hex(interpolate(c, args.colors[1], i, d - 1))); }
        }
        "TINTS" | "SHADES" | "TONES" => {
            let target = match spec.name { "TINTS" => 255, "SHADES" => 0, _ => 128 };
            for i in 1..=b { output.push(hex(interpolate(c, [target; 3], i, b + 1))); }
        }
        "BLEND" => output.push(hex(blend(args.keyword, args.colors[1], args.colors[2]))),
        "ALPHA" => {
            let q = args.numbers[3];
            let alpha = 100 * b + q * (100 - b);
            let color = if alpha == 0 { [0; 3] } else {
                std::array::from_fn(|j| rounded(100 * b * c[j] + q * (100 - b) * args.colors[2][j], alpha))
            };
            output.push(format!("{} {}%", hex(color), rounded(alpha, 100)));
        }
        "SIMULATE" => {
            const COEFFICIENTS: [[[i64; 3]; 3]; 4] = [
                [[567,433,0],[558,442,0],[0,242,758]],
                [[625,375,0],[700,300,0],[0,300,700]],
                [[950,50,0],[0,433,567],[0,475,525]],
                [[299,587,114],[299,587,114],[299,587,114]],
            ];
            let color = std::array::from_fn(|j|
                rounded((0..3).map(|k| COEFFICIENTS[args.keyword][j][k] * c[k]).sum(), 1000));
            output.push(hex(color));
        }
        "ROTATE" => output.push(hex(rotate(c, b))),
        "COMPLEMENT" => output.push(hex(rotate(c, 180))),
        "TRIADIC" => for shift in [120, 240] { output.push(hex(rotate(c, shift))); },
        "TETRADIC" => for shift in [90, 180, 270] { output.push(hex(rotate(c, shift))); },
        "SPLITCOMP" => for shift in [150, 210] { output.push(hex(rotate(c, shift))); },
        "ANALOGOUS" => {
            for i in -b..=b {
                if i != 0 { output.push(hex(rotate(c, i * d))); }
            }
        }
        "LIGHTEN" | "DARKEN" | "SATURATE" | "DESATURATE" => {
            let mut value = hsl(c);
            match spec.name {
                "LIGHTEN" => value[2] = 100.min(value[2] + b),
                "DARKEN" => value[2] = 0.max(value[2] - b),
                "SATURATE" => value[1] = 100.min(value[1] + b),
                _ => value[1] = 0.max(value[1] - b),
            }
            output.push(hex(from_hsl(value[0], value[1], value[2])));
        }
        "NEAREST" => {
            let (name, color) = table(registry).min_by_key(|entry| distance(c, entry.1)).unwrap();
            output.push(format!("{} {} {}", name, hex(color), distance(c, color)));
        }
        "DISTANCE" => {
            let other = args.colors[1];
            let differences: Color = std::array::from_fn(|j| c[j] - other[j]);
            let [r, g, b] = differences;
            let weight = (1024 + c[0] + other[0]) * r * r + 2048 * g * g
                + (1534 - c[0] - other[0]) * b * b;
            output.push(format!("{} {}", distance(c, other), (weight / 512).isqrt()));
        }
        "CONTRAST" => output.push(contrast_text(c, args.colors[1])),
        "ACCESSIBLE" => {
            let background = args.colors[1];
            let mut result = c;
            if contrast(c, background).1 == "FAIL" {
                let [h, s, l] = hsl(c);
                let mut found = false;
                for step in 1..=100 {
                    for sign in [-1, 1] {
                        let lightness = l + sign * step;
                        if !(0..=100).contains(&lightness) { continue; }
                        let candidate = from_hsl(h, s, lightness);
                        if contrast(candidate, background).1 != "FAIL" {
                            result = candidate;
                            found = true;
                            break;
                        }
                    }
                    if found { break; }
                }
            }
            output.push(format!("{} {}", hex(result), contrast_text(result, background)));
        }
        "BEST" => {
            let mut best = 1;
            for i in 2..words.len() {
                if contrast(args.colors[i], c).0 > contrast(args.colors[best], c).0 { best = i; }
            }
            output.push(format!("{} {}", hex(args.colors[best]), contrast_text(args.colors[best], c)));
        }
        "DESCRIBE" => {
            let [h, s, l] = hsl(c);
            if l <= 5 { output.push("black".to_string()); }
            else if l >= 95 { output.push("white".to_string()); }
            else {
                let lightness = if l <= 20 { "very dark" } else if l <= 40 { "dark" }
                    else if l <= 60 { "medium" } else if l <= 80 { "light" } else { "very light" };
                if s < 10 { output.push(format!("{lightness} gray")); }
                else {
                    const NAMES: [&str; 12] = ["red","orange","yellow","chartreuse","green","spring-green",
                        "cyan","azure","blue","violet","magenta","rose"];
                    let saturation = if s < 40 { "muted" } else if s < 80 { "moderate" } else { "vivid" };
                    output.push(format!("{} {} {}", lightness, saturation, NAMES[((h + 15) % 360 / 30) as usize]));
                }
            }
        }
        "PALETTE" | "KMEANS" => {
            let colors = &args.colors[1..words.len()];
            let means = if spec.name == "PALETTE" { palette(colors, a as usize) }
                else {
                    let (iterations, result) = kmeans(colors, a as usize);
                    output.push(iterations.to_string());
                    result
                };
            for (color, size) in means { output.push(format!("{}:{}", hex(color), size)); }
        }
        "SORT" => {
            let mut colors = args.colors[..words.len()].to_vec();
            colors.sort_by_key(|&color| hsl(color));
            for color in colors { output.push(hex(color)); }
        }
        "DITHER" => {
            let mut error = [0; 3];
            for color in &args.colors[..words.len()] {
                let target: Color = std::array::from_fn(|j| (color[j] + error[j]).clamp(0, 255));
                let mut best = 0;
                for i in 1..16 {
                    if distance(target, BUILTINS[i].1) < distance(target, BUILTINS[best].1) { best = i; }
                }
                output.push(BUILTINS[best].0.to_string());
                error = std::array::from_fn(|j| target[j] - BUILTINS[best].1[j]);
            }
        }
        "RANDOM" => {
            let mut state = a;
            for _ in 0..b {
                state = state * 48271 % 2147483647;
                let h = state % 360;
                state = state * 48271 % 2147483647;
                let s = 40 + state % 61;
                state = state * 48271 % 2147483647;
                let l = 25 + state % 51;
                output.push(hex(from_hsl(h, s, l)));
            }
        }
        _ => unreachable!(),
    }
    Some(output.join(" "))
}

fn main() {
    let stdin = io::stdin();
    let mut lines = stdin.lock().lines();
    let count: usize = lines.next().unwrap().unwrap().parse().unwrap();
    let stdout = io::stdout();
    let mut writer = io::BufWriter::new(stdout.lock());
    let mut registry = Vec::new();
    for _ in 0..count {
        let line = lines.next().unwrap().unwrap();
        let result = run(&line, &mut registry).unwrap_or_else(|| "INVALID".to_string());
        writeln!(writer, "{}", result).unwrap();
    }
}
