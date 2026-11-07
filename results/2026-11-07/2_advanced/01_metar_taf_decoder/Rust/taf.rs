use super::*;
pub const SLOTS: [(Kind, bool); 4] = [(Kind::Wind, false), (Kind::Visibility, false), (Kind::Weather, true),
(Kind::Cloud, true)];

pub fn observation_time(s: &str, calendar: &Calendar) -> Option<i64> {
    if s.len() != 7 || !s.ends_with('Z') || !groups::digits(&s[..6], 6, 6) {
        return None;
    }
    let d: i64 = s[..2].parse().ok()?;
    let h: i64 = s[2..4].parse().ok()?;
    let m: i64 = s[4..6].parse().ok()?;
    if !(1..=calendar.days).contains(&d) || h>23 || m>59 {
        None
    } else {
        Some(((d-1)*24+h)*60+m)
    }
}

pub fn period_format(s: &str) -> bool {
    s.len() == 9 && s.as_bytes()[4] == b'/' && groups::digits(&s[..4], 4, 4) && groups::digits(&s[5..], 4, 4)
}

pub fn period(s: &str, day: i64, calendar: &Calendar) -> Option<(i64, i64)> {
    if !period_format(s) {
        return None;
    }
    let h1: i64 = s[2..4].parse().ok()?;
    let h2: i64 = s[7..].parse().ok()?;
    if h1>23 || !(1..=24).contains(&h2) {
        return None;
    }
    let start = calendar.forecast_time(s[..2].parse().ok()?, h1, 0, day)?;
    let end = calendar.forecast_time(s[5..7].parse().ok()?, h2, 0, day)?;
    if start<end {
        Some((start, end))
    } else {
        None
    }
}

fn fm_indicator(s: &str) -> bool {
    s.len() == 8 && s.starts_with("FM") && groups::digits(&s[2..], 6, 6)
}

fn indicator(s: &str) -> bool {
    fm_indicator(s) || metar::trend_indicator(s) || matches!(s, "PROB30"|"PROB40")
}

pub fn decode(report: &mut Report, body: &[Group], station: &Station, calendar: &Calendar, errors: &mut Vec<Error>) {
    let base = body.iter().position(|g|indicator(&g.text)).unwrap_or(body.len());
    report.state = match_section(&body[..base], &SLOTS, false, station, errors, report.number);
    let mut i = base;
    while i<body.len() {
        let pos = body[i].position;
        let kind = body[i].text.clone();
        i += 1;
        let mut change = Change::new(kind.clone());
        let mut valid = true;
        if matches!(kind.as_str(), "PROB30"|"PROB40") && i<body.len() && body[i].text == "TEMPO" {
            change.kind.push_str(" TEMPO");
            i += 1;
        }
        if fm_indicator(&kind) {
            change.kind = "FM".into();
            let hour: i64 = kind[4..6].parse().unwrap();
            let minute: i64 = kind[6..].parse().unwrap();
            let time = calendar.forecast_time(kind[2..4].parse().unwrap(), hour, minute, report.time/1440+1);
            if hour>23 || minute>59 || time.is_none_or(|t|t<report.start || t >= report.end) {
                record(errors, report.number, pos, "invalid period", Some(&kind));
                valid = false;
            } else {
                change.start = time.unwrap();
            }
        } else if i == body.len() || !period_format(&body[i].text) {
            record(errors, report.number, pos, "missing period", Some(&change.kind));
            valid = false;
        } else {
            let p = period(&body[i].text, report.time/1440+1, calendar);
            if p.is_none_or(|(s, e)|s<report.start || e>report.end) {
                record(errors, report.number, body[i].position, "invalid period", Some(&body[i].text));
                valid = false;
            } else {
                (change.start, change.end) = p.unwrap();
            }
            i += 1;
        }
        let mut end = i;
        while end<body.len() && !indicator(&body[end].text) {
            end += 1;
        }
        if valid {
            change.state = match_section(&body[i..end], &SLOTS, true, station, errors, report.number);
            report.changes.push(change);
        }
        i = end;
    }
}

pub fn overlay(mut base: State, change: &State) -> State {
    if change.wind.is_some() {
        base.wind = change.wind.clone();
    }
    if change.visibility.is_some() {
        base.visibility = change.visibility.clone();
    }
    if change.weather.is_some() {
        base.weather = change.weather.clone();
    }
    if change.cloud.is_some() {
        base.cloud = change.cloud.clone();
    }
    base
}

pub fn prevailing(report: &Report, hour: i64) -> State {
    let mut state = report.state.clone();
    for change in &report.changes {
        if change.kind == "FM" && change.start <= hour {
            state = change.state.clone();
        } else if change.kind == "BECMG" && change.end <= hour {
            state = overlay(state, &change.state);
        }
    }
    state
}

pub fn temporary(change: &Change, hour: i64) -> bool {
    change.kind != "FM" && change.kind != "BECMG" && change.start <= hour && hour<change.end
}
