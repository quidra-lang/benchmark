use super::{
    State,
    Station
};
use crate::units;
pub const DESCRIPTORS: [&str; 8] = ["MI", "BC", "PR", "DR", "BL", "SH", "TS", "FZ"];
pub const DESCRIPTOR_WORDS: [&str; 8] = ["shallow", "patches", "partial", "low drifting", "blowing", "showers",
"thunderstorm", "freezing"];
pub const PHENOMENA: [&str; 22] = ["DZ", "RA", "SN", "SG", "IC", "PL", "GR", "GS", "UP", "BR", "FG", "FU",
"VA", "DU", "SA", "HZ", "PY", "PO", "SQ", "FC", "SS", "DS"];
pub const PHENOMENON_WORDS: [&str; 22] = ["drizzle", "rain", "snow", "snow grains", "ice crystals", "ice pellets",
"hail", "small hail", "unknown precipitation", "mist", "fog", "smoke", "volcanic ash", "dust", "sand", "haze",
"spray", "dust whirls", "squalls", "funnel cloud", "sandstorm", "duststorm"];
pub const AMOUNTS: [&str; 8] = ["FEW", "SCT", "BKN", "OVC", "VV", "SKC", "CLR", "NSC"];
pub const AMOUNT_WORDS: [&str; 4] = ["few", "scattered", "broken", "overcast"];
pub const CLEAR_WORDS: [&str; 3] = ["sky clear", "clear below 12000 ft", "no significant cloud"];

#[derive(Clone)]
pub struct Wind {
    pub direction: Option<i64>,
    pub speed: i64,
    pub gust: Option<i64>,
    pub mps: bool
}

#[derive(Clone)]
pub enum Visibility {
    Meters {
        raw: String,
        value: i64,
        qualifier: Option<char>,
        cavok: bool
    },
    Miles {
        whole: i64,
        numerator: i64,
        denominator: Option<i64>,
        qualifier: Option<char>,
        mixed: bool
    },
}

#[derive(Clone)]
pub struct Reading {
    pub qualifier: Option<char>,
    pub value: i64
}

#[derive(Clone)]
pub struct Rvr {
    pub runway: String,
    pub first: Reading,
    pub second: Option<Reading>,
    pub feet: bool,
    pub trend: Option<char>
}

#[derive(Clone)]
pub struct Weather {
    pub raw: String,
    pub intensity: Option<char>,
    pub descriptor: Option<usize>,
    pub phenomena: Vec<usize>,
    pub nsw: bool
}

#[derive(Clone)]
pub struct Cloud {
    pub raw: String,
    pub amount: usize,
    pub height: i64,
    pub suffix: String
}

#[derive(Clone)]
pub struct Pressure {
    pub unit: char,
    pub value: i64,
    pub inhg: i64,
    pub hpa: i64
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    Modifier,
    Wind,
    Variation,
    Visibility,
    Rvr,
    Weather,
    Cloud,
    Temperature,
    Pressure,
    NoTrend
}

#[derive(Clone)]
pub enum Parsed {
    Modifier(String),
    Wind(Wind),
    Variation(i64, i64),
    Visibility(Visibility),
    Rvr(Rvr),
    Weather(Weather),
    Cloud(Cloud),
    Temperature(i64, i64),
    Pressure(Pressure),
    NoTrend
}

pub fn digits(s: &str, min: usize, max: usize) -> bool {
    (min..=max).contains(&s.len()) && s.bytes().all(|c| c.is_ascii_digit())
}

fn number(s: &str) -> i64 {
    s.parse().unwrap()
}

fn fraction(s: &str) -> Option<(i64, i64)> {
    let (p, q) = s.split_once('/')?;
    if digits(p, 1, 1) && digits(q, 1, 2) {
        Some((number(p), number(q)))
    } else {
        None
    }
}

pub fn fraction_word(s: &str) -> bool {
    s.strip_suffix("SM").and_then(fraction).is_some()
}

fn qualifier(s: &str) -> (Option<char>, &str) {
    if s.starts_with('M') || s.starts_with('P') {
        (s.chars().next(), &s[1..])
    } else {
        (None, s)
    }
}

fn reading(s: &str) -> Option<Reading> {
    let (qualifier, n) = qualifier(s);
    if digits(n, 4, 4) {
        Some(Reading {
            qualifier,
            value: number(n)
        })
    } else {
        None
    }
}

fn temperature(s: &str) -> Option<i64> {
    let (sign, n) = if let Some(n) = s.strip_prefix('M') {
        (-1, n)
    } else {
        (1, s)
    };
    if digits(n, 2, 2) {
        Some(sign*number(n))
    } else {
        None
    }
}

fn weather_code(s: &str) -> Option<usize> {
    DESCRIPTORS.iter().position(|c| *c == s).or_else(|| PHENOMENA.iter().position(|c| *c == s).map(|i|i+8))
}

fn parse_visibility(s: &str) -> Option<Visibility> {
    if s == "CAVOK" {
        return Some(Visibility::Meters {
            raw: s.into(),
            value: 10000,
            qualifier: Some('P'),
            cavok: true
        });
    }
    if digits(s, 4, 4) {
        let value = number(s);
        return Some(Visibility::Meters {
            raw: s.into(),
            value: if value == 9999 {
                10000
            } else {
                value
            },
            qualifier: if value == 9999 {
                Some('P')
            } else {
                None
            },
            cavok: false
        });
    }
    let body = s.strip_suffix("SM")?;
    if let Some((whole, part)) = body.split_once(' ') {
        if !digits(whole, 1, 1) {
            return None;
        }
        let (numerator, denominator) = fraction(part)?;
        return Some(Visibility::Miles {
            whole: number(whole),
            numerator,
            denominator: Some(denominator),
            qualifier: None,
            mixed: true
        });
    }
    let (qualifier, body) = qualifier(body);
    if digits(body, 1, 2) {
        Some(Visibility::Miles {
            whole: number(body),
            numerator: 0,
            denominator: None,
            qualifier,
            mixed: false
        })
    } else {
        let (numerator, denominator) = fraction(body)?;
        Some(Visibility::Miles {
            whole: 0,
            numerator,
            denominator: Some(denominator),
            qualifier,
            mixed: false
        })
    }
}

pub fn parse_group(kind: Kind, s: &str) -> Option<Parsed> {
    match kind {
        Kind::Modifier => if s == "AUTO" || s == "COR" {
            Some(Parsed::Modifier(s.into()))
        } else {
            None
        },
        Kind::Wind => {
            let (body, mps) = if let Some(b) = s.strip_suffix("MPS") {
                (b, true)
            } else {
                (s.strip_suffix("KT")?, false)
            };
            if body.len()<5 {
                return None;
            }
            let (d, rest) = body.split_at(3);
            let direction = if d == "VRB" {
                None
            } else if digits(d, 3, 3) {
                Some(number(d))
            } else {
                return None
            };
            let (speed, gust) = if let Some((speed, gust)) = rest.split_once('G') {
                if !digits(gust, 2, 3) {
                    return None;
                }
                (speed, Some(number(gust)))
            } else {
                (rest, None)
            };
            if !digits(speed, 2, 3) {
                return None;
            }
            Some(Parsed::Wind(Wind {
                direction,
                speed: number(speed),
                gust,
                mps
            }))
        },
        Kind::Variation => if s.len() == 7 && &s[3..4] == "V" && digits(&s[..3], 3, 3) && digits(&s[4..], 3, 3) {
            Some(Parsed::Variation(number(&s[..3]), number(&s[4..])))
        } else {
            None
        },
        Kind::Visibility => parse_visibility(s).map(Parsed::Visibility),
        Kind::Rvr => {
            let body = s.strip_prefix('R')?;
            let (runway, mut readings) = body.split_once('/')?;
            if !matches!(runway.len(), 2|3) {
                return None;
            }
            if runway.len()<2 || !digits(&runway[..2], 2, 2) || (runway.len() == 3 && !matches!(runway.as_bytes()[2], b'L'|b'C'|b'R')) {
                return None;
            }
            let trend = readings.chars().last().filter(|c|matches!(*c, 'U' | 'D' | 'N'));
            if trend.is_some() {
                readings = &readings[..readings.len()-1];
            }
            let feet = readings.ends_with("FT");
            if feet {
                readings = &readings[..readings.len()-2];
            }
            let (first, second) = if let Some((a, b)) = readings.split_once('V') {
                (reading(a)?, Some(reading(b)?))
            } else {
                (reading(readings)?, None)
            };
            Some(Parsed::Rvr(Rvr {
                runway: runway.into(),
                first,
                second,
                feet,
                trend
            }))
        },
        Kind::Weather => {
            if s == "NSW" {
                return Some(Parsed::Weather(Weather {
                    raw: s.into(),
                    intensity: None,
                    descriptor: None,
                    phenomena: Vec::new(),
                    nsw: true
                }));
            }
            let (intensity, body) = if let Some(b) = s.strip_prefix("VC") {
                (Some('V'), b)
            } else if s.starts_with('-') || s.starts_with('+') {
                (s.chars().next(), &s[1..])
            } else {
                (None, s)
            };
            if body.is_empty() || body.len()%2 != 0 {
                return None;
            }
            let mut codes = Vec::new();
            for i in (0..body.len()).step_by(2) {
                codes.push(weather_code(&body[i..i+2])?);
            }
            let descriptor = if codes[0]<8 {
                Some(codes.remove(0))
            } else {
                None
            };
            Some(Parsed::Weather(Weather {
                raw: s.into(),
                intensity,
                descriptor,
                phenomena: codes,
                nsw: false
            }))
        },
        Kind::Cloud => {
            if let Some(amount) = AMOUNTS[5..].iter().position(|a|*a == s) {
                return Some(Parsed::Cloud(Cloud {
                    raw: s.into(),
                    amount: amount+5,
                    height: 0,
                    suffix: String::new()
                }));
            }
            if let Some(h) = s.strip_prefix("VV") {
                if digits(h, 3, 3) {
                    return Some(Parsed::Cloud(Cloud {
                        raw: s.into(),
                        amount: 4,
                        height: number(h)*100,
                        suffix: String::new()
                    }));
                }
                return None;
            }
            if s.len()<6 {
                return None;
            }
            let amount = AMOUNTS[..4].iter().position(|a|*a == &s[..3])?;
            if !digits(&s[3..6], 3, 3) || !matches!(&s[6..], ""|"CB"|"TCU") {
                return None;
            }
            Some(Parsed::Cloud(Cloud {
                raw: s.into(),
                amount,
                height: number(&s[3..6])*100,
                suffix: s[6..].into()
            }))
        },
        Kind::Temperature => {
            let (t, d) = s.split_once('/')?;
            Some(Parsed::Temperature(temperature(t)?, temperature(d)?))
        },
        Kind::Pressure => if s.len() == 5 && matches!(s.as_bytes()[0], b'A'|b'Q') && digits(&s[1..], 4, 4) {
            Some(Parsed::Pressure(Pressure {
                unit: s.as_bytes()[0] as char,
                value: number(&s[1..]),
                inhg: 0,
                hpa: 0
            }))
        } else {
            None
        },
        Kind::NoTrend => if s == "NOSIG" {
            Some(Parsed::NoTrend)
        } else {
            None
        },
    }
}

pub fn valid(value: &Parsed, state: &State, station: &Station, context: bool) -> bool {
    match value {
        Parsed::Wind(w) => {
            if let Some(d) = w.direction {
                if d>360 || d%10 != 0 || ((d == 0) != (w.speed == 0)) {
                    return false;
                }
            } else if w.speed<1 {
                return false;
            }
            w.gust.is_none_or(|g|w.direction != Some(0) && g>w.speed)
        },
        Parsed::Variation(a, b) => [a, b].iter().all(|d|**d >= 10 && **d <= 360 && **d%10 == 0) && a != b && state.wind.as_ref().is_some_and(|w|w.direction.is_some_and(|d|d>0)),
        Parsed::Visibility(Visibility::Miles {
            whole,
            numerator,
            denominator,
            mixed,
            ..
        }) => if let Some(d) = denominator {
            matches!(*d, 2 | 4 | 8 | 16) && *numerator >= 1 && numerator<d && (!*mixed || *whole >= 1)
        } else {
            *whole >= 1
        },
        Parsed::Rvr(r) => station.runways.iter().any(|rw|rw.name == r.runway) && r.second.as_ref().is_none_or(|v|r.first.value<v.value),
        Parsed::Weather(w) => {
            let accepted = state.weather.as_deref().unwrap_or(&[]);
            if accepted.len() >= 3 || accepted.iter().any(|x|x.nsw) {
                return false;
            }
            if w.nsw {
                return context && accepted.is_empty();
            }
            let mut seen = Vec::new();
            let mut precipitation = 0;
            for &code in &w.phenomena {
                if code<8 || seen.contains(&code) {
                    return false;
                }
                seen.push(code);
                if code<17 {
                    precipitation += 1;
                }
            }
            if w.phenomena.is_empty() && !matches!(w.descriptor, Some(5|6)) {
                return false;
            }
            if matches!(w.intensity, Some('-'|'+')) && precipitation == 0 {
                return false;
            }
            w.phenomena.len()<2 || precipitation == w.phenomena.len()
        },
        Parsed::Cloud(c) => state.cloud.as_ref().and_then(|v|v.last()).is_none_or(|last|c.amount<4 && last.amount<4 && c.height>last.height),
        Parsed::Temperature(t, d) => d <= t,
        Parsed::Pressure(p) => if p.unit == 'A' {
            (2500..=3150).contains(&p.value)
        } else {
            (850..=1070).contains(&p.value)
        },
        _ => true,
    }
}

pub fn accept(state: &mut State, value: Parsed) {
    match value {
        Parsed::Modifier(m) => state.modifier = Some(m),
        Parsed::Wind(mut w) => {
            if w.mps {
                w.speed = units::knots(w.speed);
                w.gust = w.gust.map(units::knots);
            }
            state.wind = Some(w);
        },
        Parsed::Variation(a, b) => state.variation = Some((a, b)),
        Parsed::Visibility(v) => {
            if matches!(&v, Visibility::Meters {
                cavok: true,
                ..
            }) {
                state.weather = Some(Vec::new());
                state.cloud = Some(Vec::new());
            }
            state.visibility = Some(v);
        },
        Parsed::Rvr(r) => state.rvr.push(r),
        Parsed::Weather(w) => state.weather.get_or_insert_with(Vec::new).push(w),
        Parsed::Cloud(c) => state.cloud.get_or_insert_with(Vec::new).push(c),
        Parsed::Temperature(t, d) => state.temperature = Some((t, d)),
        Parsed::Pressure(mut p) => {
            p.inhg = if p.unit == 'A' {
                p.value
            } else {
                units::inhg(p.value)
            };
            p.hpa = if p.unit == 'Q' {
                p.value
            } else {
                units::hpa(p.value)
            };
            state.pressure = Some(p);
        },
        Parsed::NoTrend => state.no_trend = true,
    }
}
