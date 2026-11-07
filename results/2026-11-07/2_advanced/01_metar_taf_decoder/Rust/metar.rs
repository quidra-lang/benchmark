use super::*;
pub const MAIN_SLOTS: [(Kind, bool); 10] = [(Kind::Modifier, false), (Kind::Wind, false), (Kind::Variation,
false), (Kind::Visibility, false), (Kind::Rvr, true), (Kind::Weather, true), (Kind::Cloud, true), (Kind::Temperature,
false), (Kind::Pressure, false), (Kind::NoTrend, false)];

pub fn trend_indicator(s: &str) -> bool {
    matches!(s, "BECMG"|"TEMPO")
}

fn time_group(s: &str, prefix: &str) -> bool {
    s.len() == 6 && s.starts_with(prefix) && groups::digits(&s[2..], 4, 4)
}

pub fn decode(report: &mut Report, body: &[Group], station: &Station, errors: &mut Vec<Error>) {
    let remark = body.iter().position(|g|g.text == "RMK").unwrap_or(body.len());
    let trend = body[..remark].iter().position(|g|trend_indicator(&g.text)).unwrap_or(remark);
    report.state = match_section(&body[..trend], &MAIN_SLOTS, false, station, errors, report.number);
    let mut i = trend;
    while i<remark {
        let mut end = i+1;
        while end<remark && !trend_indicator(&body[end].text) {
            end += 1;
        }
        let mut change = Change::new(body[i].text.clone());
        let cursor = i+1;
        let count = if cursor<end && time_group(&body[cursor].text, "FM") {
            if cursor+1<end && time_group(&body[cursor+1].text, "TL") {
                2
            } else {
                1
            }
        } else if cursor<end && (time_group(&body[cursor].text, "TL") || time_group(&body[cursor].text, "AT")) {
            1
        } else {
            0
        };
        let mut valid = true;
        for g in &body[cursor..cursor+count] {
            let hour: i64 = g.text[2..4].parse().unwrap();
            let minute: i64 = g.text[4..].parse().unwrap();
            if hour>23 || minute>59 {
                record(errors, report.number, g.position, "invalid period", Some(&g.text));
                valid = false;
                break;
            }
            change.times.push(g.text.clone());
        }
        if valid {
            change.state = match_section(&body[cursor+count..end], &taf::SLOTS, true, station, errors, report.number);
            report.changes.push(change);
        }
        i = end;
    }
    for g in body.iter().skip(remark+1) {
        let s = &g.text;
        if s.len() == 6 && s.starts_with("SLP") && groups::digits(&s[3..], 3, 3) {
            let p: i64 = s[3..].parse().unwrap();
            report.slp.push(if p >= 500 {
                9000+p
            } else {
                10000+p
            });
        } else if s.len() == 9 && s.starts_with('T') && matches!(s.as_bytes()[1], b'0'|b'1') && matches!(s.as_bytes()[5],
        b'0'|b'1') && groups::digits(&s[2..5], 3, 3) && groups::digits(&s[6..], 3, 3) {
            let t: i64 = s[2..5].parse().unwrap();
            let d: i64 = s[6..].parse().unwrap();
            report.precise.push((if s.as_bytes()[1] == b'1' {
                -t
            } else {
                t
            }, if s.as_bytes()[5] == b'1' {
                -d
            } else {
                d
            }));
        }
    }
}
