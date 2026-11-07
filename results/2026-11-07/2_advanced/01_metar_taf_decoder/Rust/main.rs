use std::collections::BTreeMap;
use std::fs;
use std::io;
mod groups;
mod metar;
mod taf;
mod units;
mod verification;
use groups::{
    Cloud,
    Kind,
    Parsed,
    Pressure,
    Reading,
    Rvr,
    Visibility,
    Weather,
    Wind
};
use units::Calendar;
const CATEGORIES: [&str; 4] = ["VFR", "MVFR", "IFR", "LIFR"];

#[derive(Clone)]
struct Runway {
    name: String,
    heading: i64
}
struct Station {
    code: String,
    name: String,
    elevation: i64,
    runways: Vec<Runway>
}
struct Settings {
    calendar: Calendar,
    cross: i64,
    tail: i64,
    verify: Vec<String>
}
struct Group {
    position: usize,
    text: String
}

#[derive(Clone, Default)]
struct State {
    modifier: Option<String>,
    wind: Option<Wind>,
    variation: Option<(i64, i64)>,
    visibility: Option<Visibility>,
    rvr: Vec<Rvr>,
    weather: Option<Vec<Weather>>,
    cloud: Option<Vec<Cloud>>,
    temperature: Option<(i64, i64)>,
    pressure: Option<Pressure>,
    no_trend: bool
}

#[derive(Clone)]
struct Change {
    kind: String,
    start: i64,
    end: i64,
    state: State,
    times: Vec<String>
}

impl Change {
    fn new(kind: String) -> Self {
        Self {
            kind,
            start: 0,
            end: 0,
            state: State::default(),
            times: Vec::new()
        }
    }
}

#[derive(Clone, Default)]
struct Report {
    number: usize,
    kind: String,
    station: String,
    time: i64,
    start: i64,
    end: i64,
    modifier: Option<String>,
    state: State,
    changes: Vec<Change>,
    slp: Vec<i64>,
    precise: Vec<(i64, i64)>,
    speci: String
}
struct Error {
    report: usize,
    position: usize,
    reason: String,
    text: Option<String>
}

fn record(errors: &mut Vec<Error>, report: usize, position: usize, reason: &str, text: Option<&str>) {
    errors.push(Error {
        report,
        position,
        reason: reason.into(),
        text: text.map(str::to_owned)
    });
}

fn match_section(body: &[Group], slots: &[(Kind, bool)], context: bool, station: &Station, errors: &mut Vec<Error>,
number: usize) -> State {
    let mut state = State::default();
    let mut cursor = 0;
    for group in body {
        let found = (cursor..slots.len()).find_map(|index|groups::parse_group(slots[index].0, &group.text).map(|value|(index,
        value)));
        let Some((index, value)) = found else {
            let earlier = slots[..cursor].iter().any(|(kind, _)|groups::parse_group(*kind, &group.text).is_some());
            record(errors, number, group.position, if earlier {
                "out of order group"
            } else {
                "unknown group"
            }, Some(&group.text));
            continue;
        };
        if !groups::valid(&value, &state, station, context) {
            record(errors, number, group.position, "invalid group", Some(&group.text));
            continue;
        }
        let cavok = matches!(&value, Parsed::Visibility(Visibility::Meters {
            cavok: true,
            ..
        }));
        groups::accept(&mut state, value);
        cursor = index+usize::from(!slots[index].1);
        if cavok {
            cursor = slots.iter().position(|(kind, _)|*kind == Kind::Cloud).unwrap()+1;
        }
    }
    state
}

fn ceiling(state: &State) -> Option<i64> {
    state.cloud.as_ref()?.iter().find(|cloud|(2..=4).contains(&cloud.amount)).map(|cloud|cloud.height)
}

fn category(state: &State) -> usize {
    let c = ceiling(state);
    let (p, q) = state.visibility.as_ref().map(units::mile_fraction).unwrap_or((1000000, 1));
    if c.is_some_and(|h|h<500) || p<q {
        3
    } else if c.is_some_and(|h|h<1000) || p<3*q {
        2
    } else if c.is_some_and(|h|h <= 3000) || p <= 5*q {
        1
    } else {
        0
    }
}

fn wind_phrase(wind: &Wind) -> String {
    if wind.direction == Some(0) {
        return "calm".into();
    }
    let mut text = if let Some(d) = wind.direction {
        format!("{d:03} degrees at {} KT", wind.speed)
    } else {
        format!("variable at {} KT", wind.speed)
    };
    if let Some(gust) = wind.gust {
        text.push_str(&format!(" gusting {gust} KT"));
    }
    text
}

fn wind_code(wind: &Wind) -> String {
    if wind.direction == Some(0) {
        return "00000KT".into();
    }
    let direction = wind.direction.map(|d|format!("{d:03}")).unwrap_or_else(|| "VRB".into());
    format!("{direction}{:02}{}KT", wind.speed, wind.gust.map(|g|format!("G{g:02}")).unwrap_or_default())
}

fn qualifier_prefix(qualifier: Option<char>) -> &'static str {
    match qualifier {
        Some('M') => "less than ",
        Some('P') => "more than ",
        _ => ""
    }
}

fn mile_number(whole: i64, numerator: i64, denominator: Option<i64>) -> String {
    if let Some(d) = denominator {
        format!("{}{numerator}/{d}", if whole>0 {
            format!("{whole} ")
        } else {
            String::new()
        })
    } else {
        whole.to_string()
    }
}

fn visibility_phrase(visibility: &Visibility) -> String {
    match visibility {
        Visibility::Meters {
            value,
            qualifier,
            cavok,
            ..
        } => if *cavok {
            "10 km or more (CAVOK)".into()
        } else if *qualifier == Some('P') {
            "10 km or more".into()
        } else {
            format!("{value} m")
        },
        Visibility::Miles {
            whole,
            numerator,
            denominator,
            qualifier,
            ..
        } => format!("{}{} SM", qualifier_prefix(*qualifier), mile_number(*whole, *numerator, *denominator)),
    }
}

fn visibility_code(visibility: &Visibility) -> String {
    match visibility {
        Visibility::Meters {
            raw,
            ..
        } => raw.clone(),
        Visibility::Miles {
            whole,
            numerator,
            denominator,
            qualifier,
            ..
        } => format!("{}{}SM", qualifier.map(|q|q.to_string()).unwrap_or_default(), mile_number(*whole, *numerator,
        *denominator))
    }
}

fn visibility_csv(visibility: &Visibility) -> String {
    let qualifier = match visibility {
        Visibility::Meters {
            qualifier,
            ..
        }
        |Visibility::Miles {
            qualifier,
            ..
        } => qualifier
    };
    format!("{}{}", qualifier.map(|q|q.to_string()).unwrap_or_default(), units::meter_value(visibility))
}

fn weather_phrase(weather: &Weather) -> String {
    if weather.nsw {
        return "no significant weather".into();
    }
    let mut parts = Vec::new();
    if let Some(i) = weather.intensity {
        parts.push(match i {
            '-' => "light",
            '+' => "heavy",
            _ => "nearby"
        }.to_string());
    }
    if let Some(d) = weather.descriptor {
        parts.push(groups::DESCRIPTOR_WORDS[d].into());
    }
    if !weather.phenomena.is_empty() {
        parts.push(weather.phenomena.iter().map(|code|groups::PHENOMENON_WORDS[code-8]).collect::<Vec<_>>().join(" and "));
    }
    parts.join(" ")
}

fn cloud_phrase(cloud: &Cloud) -> String {
    if cloud.amount >= 5 {
        return groups::CLEAR_WORDS[cloud.amount-5].into();
    }
    if cloud.amount == 4 {
        return format!("vertical visibility {} ft", cloud.height);
    }
    format!("{} at {} ft{}", groups::AMOUNT_WORDS[cloud.amount], cloud.height, match cloud.suffix.as_str() {
        "CB" => " cumulonimbus",
        "TCU" => " towering cumulus",
        _ => ""
    })
}

fn summary(state: &State) -> String {
    let mut parts = Vec::new();
    if let Some(wind) = &state.wind {
        parts.push(format!("wind {}", wind_phrase(wind)));
    }
    if let Some(visibility) = &state.visibility {
        parts.push(format!("visibility {}", visibility_phrase(visibility)));
    }
    if let Some(weather) = &state.weather {
        if !weather.is_empty() {
            parts.push(format!("weather {}", weather.iter().map(weather_phrase).collect::<Vec<_>>().join(", ")));
        }
    }
    if let Some(cloud) = &state.cloud {
        if !cloud.is_empty() {
            parts.push(format!("cloud {}", cloud.iter().map(cloud_phrase).collect::<Vec<_>>().join(", ")));
        }
    }
    if parts.is_empty() {
        "no conditions".into()
    } else {
        parts.join("; ")
    }
}

fn tokens(state: &State) -> String {
    let mut parts = Vec::new();
    if let Some(wind) = &state.wind {
        parts.push(wind_code(wind));
    }
    if let Some(visibility) = &state.visibility {
        parts.push(visibility_code(visibility));
    }
    if let Some(weather) = &state.weather {
        parts.extend(weather.iter().filter(|w|!w.nsw).map(|w|w.raw.clone()));
    }
    if let Some(cloud) = &state.cloud {
        parts.extend(cloud.iter().map(|c|c.raw.clone()));
    }
    parts.push(CATEGORIES[category(state)].into());
    parts.join(" ")
}

fn wind_changes(earlier: Option<&Wind>, later: Option<&Wind>, angle: i64) -> Vec<&'static str> {
    let (Some(a), Some(b)) = (earlier, later) else {
        return Vec::new();
    };
    let mut reasons = Vec::new();
    if let (Some(d1), Some(d2)) = (a.direction, b.direction) {
        let d = (d1-d2).abs()%360;
        if d1>0 && d2>0 && a.speed.max(b.speed) >= 10 && d.min(360-d) >= angle {
            reasons.push("wind shift");
        }
    }
    if (a.speed-b.speed).abs() >= 10 {
        reasons.push("wind speed");
    }
    reasons
}

fn weather_has(state: &State, descriptor: usize, freezing: bool) -> bool {
    state.weather.as_ref().is_some_and(|weather|weather.iter().any(|w|w.descriptor == Some(descriptor) && (!freezing || w.phenomena.contains(&8) || w.phenomena.contains(&9))))
}

fn speci_check(previous: Option<&Report>, report: &Report) -> String {
    let Some(previous) = previous else {
        return "no previous report".into();
    };
    let a = &previous.state;
    let b = &report.state;
    let mut reasons = Vec::new();
    if category(a) != category(b) {
        reasons.push(format!("category {} to {}", CATEGORIES[category(a)], CATEGORIES[category(b)]));
    }
    reasons.extend(wind_changes(a.wind.as_ref(), b.wind.as_ref(), 45).into_iter().map(str::to_owned));
    if weather_has(a, 6, false) != weather_has(b, 6, false) {
        reasons.push(format!("thunderstorm {}", if weather_has(b, 6, false) {
            "began"
        } else {
            "ended"
        }));
    }
    if weather_has(a, 7, true) != weather_has(b, 7, true) {
        reasons.push(format!("freezing precipitation {}", if weather_has(b, 7, true) {
            "began"
        } else {
            "ended"
        }));
    }
    if reasons.is_empty() {
        "no criteria met".into()
    } else {
        reasons.join(", ")
    }
}

fn tenth(value: i64) -> String {
    format!("{}{}.{}", if value<0 {
        "-"
    } else {
        ""
    }, value.abs()/10, value.abs()%10)
}

fn pressure_phrase(pressure: &Pressure) -> String {
    let inch = format!("{}.{:02} inHg", pressure.inhg/100, pressure.inhg%100);
    let hpa = format!("{} hPa", pressure.hpa);
    if pressure.unit == 'A' {
        format!("{inch} ({hpa})")
    } else {
        format!("{hpa} ({inch})")
    }
}

fn reading_phrase(reading: &Reading) -> String {
    format!("{}{}", qualifier_prefix(reading.qualifier), reading.value)
}

fn rvr_phrase(rvr: &Rvr) -> String {
    let range = if let Some(second) = &rvr.second {
        format!("between {} and {}", reading_phrase(&rvr.first), reading_phrase(second))
    } else {
        reading_phrase(&rvr.first)
    };
    format!("runway {} {range} {}{}", rvr.runway, if rvr.feet {
        "ft"
    } else {
        "m"
    }, match rvr.trend {
        Some('U') => ", rising",
        Some('D') => ", falling",
        Some('N') => ", no change",
        _ => ""
    })
}

fn components(wind: &Wind, runway: &Runway, speed: i64) -> (i64, i64) {
    let angle = wind.direction.unwrap()-runway.heading;
    ((speed*units::cos(angle)).div_euclid(1000), (speed*units::sin(angle)).div_euclid(1000))
}

fn component_phrase(head: i64, cross: i64) -> String {
    format!("{} {} KT, crosswind {} KT{}", if head<0 {
        "tailwind"
    } else {
        "headwind"
    }, head.abs(), cross.abs(), if cross>0 {
        " from right"
    } else if cross<0 {
        " from left"
    } else {
        ""
    })
}

fn observation_lines(report: &Report, station: &Station, settings: &Settings) -> Vec<String> {
    let state = &report.state;
    let calendar = &settings.calendar;
    let mut lines = vec![format!("time: {}", calendar.stamp(report.time))];
    if let Some(modifier) = &state.modifier {
        lines.push(format!("modifier: {}", if modifier == "AUTO" {
            "automated"
        } else {
            "corrected"
        }));
    }
    let mut wind = state.wind.as_ref().map(wind_phrase).unwrap_or_else(|| "not reported".into());
    if let Some((a, b)) = state.variation {
        wind.push_str(&format!(", varying between {a:03} and {b:03} degrees"));
    }
    lines.push(format!("wind: {wind}"));
    lines.push(format!("visibility: {}", state.visibility.as_ref().map(visibility_phrase).unwrap_or_else(|| "not reported".into())));
    for rvr in &state.rvr {
        lines.push(format!("runway visual range: {}", rvr_phrase(rvr)));
    }
    if let Some(weather) = &state.weather {
        for w in weather {
            lines.push(format!("weather: {}", weather_phrase(w)));
        }
    }
    if matches!(&state.visibility, Some(Visibility::Meters {
        cavok: true,
        ..
    })) {
        lines.push("cloud: no significant cloud".into());
    } else if let Some(cloud) = &state.cloud {
        for c in cloud {
            lines.push(format!("cloud: {}", cloud_phrase(c)));
        }
    } else {
        lines.push("cloud: not reported".into());
    }
    lines.push(if let Some((temperature, dew_point)) = state.temperature {
        format!("temperature: {temperature} C, dew point {dew_point} C, spread {} C", temperature-dew_point)
    } else {
        "temperature: not reported".into()
    });
    lines.push(format!("altimeter: {}", state.pressure.as_ref().map(pressure_phrase).unwrap_or_else(|| "not reported".into())));
    if state.no_trend {
        lines.push("trend: no significant change".into());
    }
    for change in &report.changes {
        let mut text = if change.kind == "BECMG" {
            "becoming"
        } else {
            "temporarily"
        }.to_string();
        for time in &change.times {
            text.push_str(&format!(" {} {}:{}Z", match &time[..2] {
                "FM" => "from",
                "TL" => "until",
                _ => "at"
            }, &time[2..4], &time[4..]));
        }
        lines.push(format!("trend: {text}: {}", summary(&change.state)));
    }
    for &pressure in &report.slp {
        lines.push(format!("sea level pressure: {} hPa", tenth(pressure)));
    }
    for &(temperature, dew_point) in &report.precise {
        lines.push(format!("precise temperature: {} C, dew point {} C", tenth(temperature), tenth(dew_point)));
    }
    lines.push(format!("ceiling: {}", ceiling(state).map(|c|format!("{c} ft")).unwrap_or_else(|| "none".into())));
    lines.push(format!("flight category: {}", CATEGORIES[category(state)]));
    let pa = state.pressure.as_ref().map(|pressure|station.elevation+(2992-pressure.inhg)*10);
    lines.push(format!("pressure altitude: {}", pa.map(|p|format!("{p} ft")).unwrap_or_else(|| "not available".into())));
    let da = pa.zip(state.temperature).map(|(pa, (temperature, _))|pa+(120*(1000*temperature-15000+2*pa)).div_euclid(1000));
    lines.push(format!("density altitude: {}", da.map(|d|format!("{d} ft")).unwrap_or_else(|| "not available".into())));
    if let Some(wind) = state.wind.as_ref().filter(|w|w.direction.is_some_and(|d|d>0)) {
        let mut usable = Vec::new();
        let mut preferred: Option<(&str, i64)> = None;
        for runway in &station.runways {
            let (h, c) = components(wind, runway, wind.speed);
            let (gh, gc) = components(wind, runway, wind.gust.unwrap_or(wind.speed));
            lines.push(format!("runway {}: {}{}", runway.name, component_phrase(h, c), if wind.gust.is_some() {
                format!("; gusts {}", component_phrase(gh, gc))
            } else {
                String::new()
            }));
            if gc.abs() <= settings.cross && -gh <= settings.tail {
                usable.push(runway.name.clone());
                if preferred.is_none_or(|(_, best)|h>best) {
                    preferred = Some((&runway.name, h));
                }
            }
        }
        lines.push(format!("usable runways: {}", if usable.is_empty() {
            "none".into()
        } else {
            usable.join(" ")
        }));
        lines.push(format!("preferred runway: {}", preferred.map(|(name, _)|name).unwrap_or("none")));
    } else {
        lines.push("runway wind: not computed".into());
    }
    if report.kind == "SPECI" {
        lines.push(format!("speci check: {}", report.speci));
    }
    lines
}

fn forecast_lines(report: &Report, calendar: &Calendar) -> Vec<String> {
    let mut lines = vec![format!("issued: {}", calendar.stamp(report.time))];
    if let Some(modifier) = &report.modifier {
        lines.push(format!("modifier: {}", if modifier == "AMD" {
            "amended"
        } else {
            "corrected"
        }));
    }
    lines.push(format!("valid: {} to {}", calendar.stamp(report.start), calendar.stamp(report.end)));
    lines.push(format!("base: {}", summary(&report.state)));
    for change in &report.changes {
        let period = if change.kind == "FM" {
            calendar.stamp(change.start)
        } else {
            format!("{} to {}", calendar.stamp(change.start), calendar.stamp(change.end))
        };
        lines.push(format!("{} {period}: {}", change.kind, summary(&change.state)));
    }
    lines
}

fn count_text(counts: &[i64; 4]) -> String {
    (0..4).map(|i|format!("{} {}", CATEGORIES[i], counts[i])).collect::<Vec<_>>().join(", ")
}

fn timeline(report: &Report, calendar: &Calendar) -> String {
    let mut lines = vec![format!("TAF {} issued {} valid {} to {}", report.station, calendar.stamp(report.time),
    calendar.stamp(report.start), calendar.stamp(report.end))];
    let mut counts = [0; 4];
    let mut hour = report.start;
    while hour<report.end {
        let state = taf::prevailing(report, hour);
        counts[category(&state)] += 1;
        let mut line = format!("{} {}", calendar.stamp(hour), tokens(&state));
        for change in &report.changes {
            if taf::temporary(change, hour) {
                line.push_str(&format!(" | {} {}", change.kind, tokens(&taf::overlay(state.clone(), &change.state))));
            }
        }
        lines.push(line);
        hour += 60;
    }
    lines.push(format!("summary: {}", count_text(&counts)));
    lines.join("\n")
}

fn visibility_less(a: &Visibility, b: &Visibility) -> bool {
    let (p, q) = units::mile_fraction(a);
    let (r, s) = units::mile_fraction(b);
    p*s<r*q
}

fn wind_strength(wind: &Wind) -> i64 {
    wind.gust.unwrap_or(wind.speed)
}

fn table_row(label: &str, cells: &[String]) -> String {
    format!("{label:<8}{}", cells.iter().map(|c|format!("{c:>6}")).collect::<String>())
}

fn verification_block(station: &Station, reports: &[Report], calendar: &Calendar) -> String {
    let mut counts = [0; 4];
    let (mut metars, mut specis, mut missing) = (0, 0, 0);
    let mut extremes: [Option<&Report>; 5] = [None; 5];
    let mut contingency = verification::Contingency::default();
    let mut buckets = [[0i64; 2]; 5];
    let mut amendments = Vec::new();
    for report in reports.iter().filter(|r|r.station == station.code && r.kind != "TAF") {
        let state = &report.state;
        let observed = category(state);
        counts[observed] += 1;
        if report.kind == "METAR" {
            metars += 1;
        } else {
            specis += 1;
        }
        if let Some((temperature, _)) = state.temperature {
            if extremes[0].is_none_or(|r|temperature<r.state.temperature.unwrap().0) {
                extremes[0] = Some(report);
            }
            if extremes[1].is_none_or(|r|temperature>r.state.temperature.unwrap().0) {
                extremes[1] = Some(report);
            }
        }
        if let Some(wind) = &state.wind {
            if extremes[2].is_none_or(|r|wind_strength(wind)>wind_strength(r.state.wind.as_ref().unwrap())) {
                extremes[2] = Some(report);
            }
        }
        if let Some(c) = ceiling(state) {
            if extremes[3].is_none_or(|r|c<ceiling(&r.state).unwrap()) {
                extremes[3] = Some(report);
            }
        }
        if let Some(visibility) = &state.visibility {
            if extremes[4].is_none_or(|r|visibility_less(visibility, r.state.visibility.as_ref().unwrap())) {
                extremes[4] = Some(report);
            }
        }
        let hour = report.time-report.time%60;
        for forecast in reports.iter().filter(|r|r.station == station.code && verification::covers(r, report.time)) {
            let bucket = ((hour-forecast.start)/360)as usize;
            buckets[bucket][1] += 1;
            if category(&taf::prevailing(forecast, hour)) == observed {
                buckets[bucket][0] += 1;
            }
        }
        let Some(forecast) = verification::chosen(reports, &station.code, report.time) else {
            missing += 1;
            continue;
        };
        let prevailing = taf::prevailing(forecast, hour);
        let forecast_category = category(&prevailing);
        let hit = observed == forecast_category || forecast.changes.iter().any(|c|taf::temporary(c, hour) && category(&taf::overlay(prevailing.clone(),
        &c.state)) == observed);
        contingency.add(forecast_category, observed, hit);
        let mut reasons = Vec::new();
        if !hit {
            reasons.push(format!("category {}, forecast {}", CATEGORIES[observed], CATEGORIES[forecast_category]));
        }
        if !wind_changes(prevailing.wind.as_ref(), state.wind.as_ref(), 60).is_empty() {
            reasons.push(format!("wind {}, forecast {}", wind_code(state.wind.as_ref().unwrap()), wind_code(prevailing.wind.as_ref().unwrap())));
        }
        if !reasons.is_empty() {
            amendments.push(format!("amendment {}: {}", calendar.stamp(report.time), reasons.join("; ")));
        }
    }
    let mut lines = vec![format!("station {} ({})", station.code, station.name), format!("reports: METAR {metars}, SPECI {specis}"),
    format!("observed categories: {}", count_text(&counts))];
    let labels = ["lowest temperature", "highest temperature", "strongest wind", "lowest ceiling", "lowest visibility"];
    for (i, extreme) in extremes.iter().enumerate() {
        if let Some(report) = extreme {
            let state = &report.state;
            let value = match i {
                0|1 => format!("{} C", state.temperature.unwrap().0),
                2 => wind_phrase(state.wind.as_ref().unwrap()),
                3 => format!("{} ft", ceiling(state).unwrap()),
                _ => visibility_phrase(state.visibility.as_ref().unwrap())
            };
            lines.push(format!("{}: {value} at {}", labels[i], calendar.stamp(report.time)));
        } else {
            lines.push(format!("{}: not available", labels[i]));
        }
    }
    let n = contingency.total();
    lines.push(format!("verified: {n}"));
    lines.push(format!("no forecast: {missing}"));
    lines.push(table_row("forecast", &["VFR", "MVFR", "IFR", "LIFR", "total"].map(str::to_owned)));
    for (i, category) in CATEGORIES.iter().enumerate() {
        let mut cells = contingency.table[i].map(|x|x.to_string()).to_vec();
        cells.push(contingency.row(i).to_string());
        lines.push(table_row(category, &cells));
    }
    let mut totals = (0..4).map(|i|contingency.column(i).to_string()).collect::<Vec<_>>();
    totals.push(n.to_string());
    lines.push(table_row("total", &totals));
    lines.push(format!("hit rate: {}", units::fraction(contingency.hits(), n)));
    lines.push(format!("hit rate with temporary groups: {}", units::fraction(contingency.temporary_hits, n)));
    let (p, q) = contingency.skill();
    lines.push(format!("heidke skill score: {}", units::fraction(p, q)));
    for (i, category) in CATEGORIES.iter().enumerate() {
        let (p, q) = contingency.detection(i);
        let (r, s) = contingency.false_alarm(i);
        lines.push(format!("{category}: pod {}, far {}", units::fraction(p, q), units::fraction(r, s)));
    }
    for (i, bucket) in buckets.iter().enumerate() {
        lines.push(format!("hours {}-{}: {}", i*6, i*6+5, units::fraction(bucket[0], bucket[1])));
    }
    lines.extend(amendments);
    lines.join("\n")
}

fn join_groups(words: &[String], mut cursor: usize) -> Vec<Group> {
    let mut groups = Vec::new();
    while cursor<words.len() {
        let position = cursor+1;
        let mut text = words[cursor].clone();
        if groups::digits(&text, 1, 1) && cursor+1<words.len() && groups::fraction_word(&words[cursor+1]) {
            cursor += 1;
            text.push(' ');
            text.push_str(&words[cursor]);
        }
        groups.push(Group {
            position,
            text
        });
        cursor += 1;
    }
    groups
}

fn parse_report(words: &[String], number: usize, stations: &BTreeMap<String, Station>, calendar: &Calendar,
errors: &mut Vec<Error>) -> Option<Report> {
    let mut report = Report {
        number,
        kind: words[0].clone(),
        ..Report::default()
    };
    if !matches!(report.kind.as_str(), "METAR"|"SPECI"|"TAF") {
        record(errors, number, 1, "rejected report, invalid type", Some(&words[0]));
        return None;
    }
    let forecast = report.kind == "TAF";
    let mut cursor = 1;
    if forecast && cursor<words.len() && matches!(words[cursor].as_str(), "AMD"|"COR") {
        report.modifier = Some(words[cursor].clone());
        cursor += 1;
    }
    let header_items = if forecast { 3 } else { 2 };
    for item in 0..header_items {
        let name = match item {
            0 => "station",
            1 => "time",
            _ => "validity"
        };
        if cursor == words.len() {
            record(errors, number, cursor+1, &format!("rejected report, missing {name}"), None);
            return None;
        }
        let word = &words[cursor];
        let valid = match item {
            0 => {
                report.station = word.clone();
                stations.contains_key(word)
            },
            1 => if let Some(time) = taf::observation_time(word, calendar) {
                report.time = time;
                true
            } else {
                false
            },
            _ => if let Some((start, end)) = taf::period(word, report.time/1440+1, calendar) {
                report.start = start;
                report.end = end;
                end <= start+1800
            } else {
                false
            }
        };
        if !valid {
            record(errors, number, cursor+1, &format!("rejected report, invalid {name}"), Some(word));
            return None;
        }
        cursor += 1;
    }
    let body = join_groups(words, cursor);
    let station = &stations[&report.station];
    if forecast {
        taf::decode(&mut report, &body, station, calendar, errors);
    } else {
        metar::decode(&mut report, &body, station, errors);
    }
    Some(report)
}

fn read_lines(name: &str) -> io::Result<Vec<String>> {
    Ok(fs::read_to_string(format!("input/{name}"))?.lines().map(str::to_owned).collect())
}

fn read_inputs() -> io::Result<(BTreeMap<String, Station>, Settings, Vec<Vec<String>>)> {
    let mut stations = BTreeMap::new();
    for line in read_lines("stations.txt")? {
        let mut parts = line.splitn(4, ' ');
        let code = parts.next().unwrap().to_string();
        let elevation = parts.next().unwrap().parse().unwrap();
        let runways = parts.next().unwrap().split(',').map(|entry| {
            let (name, heading) = entry.split_once('/').unwrap();
            Runway {
                name: name.into(),
                heading: heading.parse().unwrap()
            }
        }).collect();
        let name = parts.next().unwrap().to_string();
        stations.insert(code.clone(), Station {
            code,
            name,
            elevation,
            runways
        });
    }
    let params = read_lines("params.txt")?;
    let value = |i: usize|params[i].split_whitespace().nth(1).unwrap().parse::<i64>().unwrap();
    let settings = Settings {
        calendar: Calendar::new(value(0), value(1)),
        cross: value(2),
        tail: value(3),
        verify: params[4].split_whitespace().skip(1).map(str::to_owned).collect()
    };
    let mut reports: Vec<Vec<String>> = Vec::new();
    for line in read_lines("reports.txt")? {
        let words = line.split_whitespace().map(str::to_owned);
        if line.starts_with(' ') {
            reports.last_mut().unwrap().extend(words);
        } else {
            reports.push(words.collect());
        }
    }
    Ok((stations, settings, reports))
}

fn save(name: &str, items: &[String], separator: &str) -> io::Result<()> {
    let text = if items.is_empty() {
        String::new()
    } else {
        format!("{}\n", items.join(separator))
    };
    fs::write(format!("output/{name}"), text)
}

fn main() -> io::Result<()> {
    let (stations, settings, raw) = read_inputs()?;
    let calendar = &settings.calendar;
    let mut reports: Vec<Report> = Vec::new();
    let mut errors = Vec::new();
    let mut previous: BTreeMap<String, usize> = BTreeMap::new();
    for (number, words) in raw.iter().enumerate() {
        if let Some(mut report) = parse_report(words, number+1, &stations, calendar, &mut errors) {
            if report.kind != "TAF" {
                if report.kind == "SPECI" {
                    report.speci = speci_check(previous.get(&report.station).map(|i|&reports[*i]), &report);
                }
                previous.insert(report.station.clone(), reports.len());
            }
            reports.push(report);
        }
    }
    let mut decoded = Vec::new();
    let mut csv = vec!["station,time,ceiling,visibility,category".to_string()];
    let mut timelines = Vec::new();
    for report in &reports {
        let station = &stations[&report.station];
        let mut block = format!("REPORT {}: {} {} ({})", report.number, report.kind, report.station, station.name);
        let lines = if report.kind == "TAF" {
            forecast_lines(report, calendar)
        } else {
            observation_lines(report, station, &settings)
        };
        for line in lines {
            block.push_str(&format!("\n  {line}"));
        }
        decoded.push(block);
        if report.kind == "TAF" {
            timelines.push(timeline(report, calendar));
        } else {
            csv.push(format!("{},{},{},{},{}", report.station, calendar.stamp(report.time), ceiling(&report.state).map(|c|c.to_string()).unwrap_or_else(|| "NONE".into()),
            report.state.visibility.as_ref().map(visibility_csv).unwrap_or_else(|| "NONE".into()), CATEGORIES[category(&report.state)]));
        }
    }
    let verification = settings.verify.iter().map(|code|verification_block(&stations[code], &reports, calendar)).collect::<Vec<_>>();
    errors.sort_by_key(|error|(error.report, error.position));
    let error_lines = errors.iter().map(|error|format!("report {} word {}: {}{}", error.report, error.position,
    error.reason, error.text.as_ref().map(|text|format!(" \"{text}\"")).unwrap_or_default())).collect::<Vec<_>>();
    fs::create_dir_all("output")?;
    save("decoded.txt", &decoded, "\n\n")?;
    save("categories.csv", &csv, "\n")?;
    save("taf_timeline.txt", &timelines, "\n\n")?;
    save("verification.txt", &verification, "\n\n")?;
    save("errors.txt", &error_lines, "\n")?;
    Ok(())
}
