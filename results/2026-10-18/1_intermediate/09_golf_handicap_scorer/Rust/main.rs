use std::collections::{BTreeMap, BTreeSet};
use std::io::{self, BufRead};

fn number(text: &str) -> i32 {
    text.parse().unwrap()
}

fn half_up(numerator: i64, denominator: i64) -> i32 {
    (2 * numerator + denominator).div_euclid(2 * denominator) as i32
}

fn half_away(numerator: i64, denominator: i64) -> i32 {
    if numerator < 0 {
        -half_up(-numerator, denominator)
    } else {
        half_up(numerator, denominator)
    }
}

fn decimal(value: i32, negative_sign: &str) -> String {
    let sign = if value < 0 { negative_sign } else { "" };
    format!("{sign}{}.{:01}", value.abs() / 10, value.abs() % 10)
}

fn index_display(value: Option<i32>) -> String {
    value.map_or_else(|| "none".to_owned(), |v| decimal(v, "+"))
}

fn handicap_display(value: Option<i32>) -> String {
    value.map_or_else(|| "none".to_owned(), |v| {
        if v < 0 { format!("+{}", -v) } else { v.to_string() }
    })
}

fn average(total: i64, count: usize) -> String {
    if count == 0 {
        "-".to_owned()
    } else {
        let hundredths = total * 100 / count as i64;
        format!("{}.{:02}", hundredths / 100, hundredths % 100)
    }
}

fn allocation(handicap: i32, indexes: &[i32; 18]) -> [i32; 18] {
    let magnitude = handicap.abs();
    let quotient = magnitude / 18;
    let remainder = magnitude % 18;
    std::array::from_fn(|i| {
        if handicap >= 0 {
            quotient + i32::from(indexes[i] <= remainder)
        } else {
            -quotient - i32::from(indexes[i] >= 19 - remainder)
        }
    })
}

fn countback(values: &[i32; 18]) -> [i64; 5] {
    let sum = |start: usize| values[start..].iter().map(|&v| i64::from(v)).sum();
    [sum(0), sum(9), sum(12), sum(15), i64::from(values[17])]
}

fn match_status(lead: i32) -> String {
    if lead == 0 {
        "AS".to_owned()
    } else {
        format!("{} {}", lead.abs(), if lead > 0 { "UP" } else { "DN" })
    }
}

#[derive(Clone)]
struct Tee {
    id: String,
    rating: i32,
    slope: i32,
}

#[derive(Clone)]
struct Course {
    id: String,
    pars: [i32; 18],
    indexes: [i32; 18],
    par: i32,
    tees: BTreeMap<String, Tee>,
}

impl Tee {
    fn handicap(&self, index: i32, course: &Course) -> i32 {
        half_up(
            i64::from(index) * i64::from(self.slope)
                + 113 * i64::from(self.rating - 10 * course.par),
            1130,
        )
    }
}

#[derive(Clone)]
struct Calculation {
    lowest: usize,
    average: i32,
    adjustment: i32,
    low: Option<i32>,
    hard: bool,
    soft: bool,
    maximum: bool,
}

#[derive(Clone)]
struct Round {
    course_id: String,
    tee_id: String,
    pars: [i32; 18],
    indexes: [i32; 18],
    day: i32,
    scores: [i32; 18], // -1 is unplayed, 0 is X
    previous_index: Option<i32>,
    previous_records: usize,
    previous_calculation: Option<Calculation>,
    handicap: Option<i32>,
    adjusted: [i32; 18],
    ags: i32,
    differential: i32,
    exceptional: i32,
}

#[derive(Clone)]
struct Player {
    id: String,
    name: String,
    index: Option<i32>,
    rounds: Vec<Round>,
    records: Vec<(i32, i32)>, // day, index
    calculation: Option<Calculation>,
}

#[derive(Clone)]
struct Eligible {
    number: usize,
    adjusted: i32,
}

impl Player {
    fn low_index(&self, day: i32) -> Option<(i32, i32)> {
        self.records.iter()
            .filter(|(date, _)| *date >= day - 365 && *date < day)
            .map(|&(date, index)| (index, date))
            .min()
    }

    fn eligible(&self) -> Vec<Eligible> {
        let start = self.rounds.len().saturating_sub(20);
        let mut reduction = 0;
        let mut rows = Vec::new();
        for i in (start..self.rounds.len()).rev() {
            let record = &self.rounds[i];
            reduction += record.exceptional;
            rows.push(Eligible {
                number: i + 1,
                adjusted: record.differential - reduction,
            });
        }
        rows.reverse();
        rows
    }

    fn counting(&self, eligible: &[Eligible]) -> (Vec<Eligible>, i32) {
        let n = eligible.len();
        if n < 3 {
            return (Vec::new(), 0);
        }
        let limits = [5, 8, 11, 14, 16, 18, 19, 20];
        let k = limits.iter().position(|&limit| n <= limit).unwrap() + 1;
        let mut selected = eligible.to_vec();
        selected.sort_by_key(|row| (row.adjusted, -(row.number as i32)));
        selected.truncate(k);
        let adjustment = if n == 3 { -20 } else if n == 4 || n == 6 { -10 } else { 0 };
        (selected, adjustment)
    }

    fn update_index(&mut self, day: i32) {
        let (selected, adjustment) = self.counting(&self.eligible());
        if selected.is_empty() {
            self.calculation = None;
            return;
        }
        let total: i64 = selected.iter().map(|row| i64::from(row.adjusted)).sum();
        let average = half_away(total, selected.len() as i64);
        let mut candidate = average + adjustment;
        let low = self.low_index(day).map(|(index, _)| index);
        let (mut hard, mut soft, mut maximum) = (false, false, false);
        if let Some(lowest) = low {
            if candidate - lowest > 30 {
                candidate = lowest + 30 + (candidate - lowest - 30) / 2;
                soft = true;
            }
            if candidate - lowest > 50 {
                candidate = lowest + 50;
                hard = true;
            }
        }
        if candidate > 540 {
            candidate = 540;
            maximum = true;
        }
        self.index = Some(candidate);
        self.calculation = Some(Calculation {
            lowest: selected.len(), average, adjustment, low, hard, soft, maximum,
        });
    }
}

impl Round {
    fn new(player: &Player, course: &Course, tee: &Tee,
           day: i32, scores: [i32; 18]) -> Self {
        let handicap = player.index.map(|index| tee.handicap(index, course));
        let strokes = allocation(handicap.unwrap_or(0), &course.indexes);
        let adjusted = std::array::from_fn(|hole| {
            let limit = if handicap.is_some() {
                course.pars[hole] + 2 + strokes[hole]
            } else {
                course.pars[hole] + 5
            };
            match scores[hole] {
                -1 => course.pars[hole] + strokes[hole],
                0 => limit,
                value => value.min(limit),
            }
        });
        let ags: i32 = adjusted.iter().sum();
        let differential = half_away(
            113 * i64::from(10 * ags - tee.rating), i64::from(tee.slope));
        let exceptional = match player.index {
            Some(index) if index - differential >= 100 => 20,
            Some(index) if index - differential >= 70 => 10,
            _ => 0,
        };
        Self {
            course_id: course.id.clone(), tee_id: tee.id.clone(),
            pars: course.pars, indexes: course.indexes,
            day, scores, previous_index: player.index,
            previous_records: player.records.len(),
            previous_calculation: player.calculation.clone(),
            handicap, adjusted, ags, differential, exceptional,
        }
    }

    fn nets(&self, strokes: &[i32; 18]) -> [Option<i32>; 18] {
        std::array::from_fn(|i| (self.scores[i] > 0).then_some(self.scores[i] - strokes[i]))
    }

    fn points(&self, nets: &[Option<i32>; 18]) -> [i32; 18] {
        std::array::from_fn(|i| {
            nets[i].map_or(0, |net| (self.pars[i] + 2 - net).max(0))
        })
    }

    fn complete(&self) -> bool {
        self.scores.iter().all(|&score| score > 0)
    }
}

#[derive(Clone)]
struct Event {
    id: String,
    format: String,
    course_id: String,
    tee_id: String,
    day: i32,
    allowance: i32,
    players: Vec<String>,
}

struct EventData {
    rounds: Vec<Round>,
    handicaps: Vec<i32>,
    nets: Vec<[Option<i32>; 18]>,
    points: Vec<[i32; 18]>,
}

struct Scorer {
    courses: BTreeMap<String, Course>,
    players: BTreeMap<String, Player>,
    events: BTreeMap<String, Event>,
    output: Vec<String>,
}

impl Scorer {
    fn new() -> Self {
        Self {
            courses: BTreeMap::new(),
            players: BTreeMap::new(),
            events: BTreeMap::new(),
            output: Vec::new(),
        }
    }

    fn emit(&mut self, line: String) {
        self.output.push(line);
    }

    fn player(&self, id: &str) -> Result<Player, String> {
        self.players.get(id).cloned().ok_or_else(|| "unknown player".to_owned())
    }

    fn course(&self, id: &str) -> Result<Course, String> {
        self.courses.get(id).cloned().ok_or_else(|| "unknown course".to_owned())
    }

    fn tee(&self, course_id: &str, tee_id: &str) -> Result<(Course, Tee), String> {
        let course = self.course(course_id)?;
        let tee = course.tees.get(tee_id).cloned()
            .ok_or_else(|| "unknown tee".to_owned())?;
        Ok((course, tee))
    }

    fn register_course(&mut self, a: &[&str]) -> Result<(), String> {
        if self.courses.contains_key(a[0]) {
            return Err("duplicate course".into());
        }
        let pars = std::array::from_fn(|i| number(a[i + 1]));
        let indexes = std::array::from_fn(|i| number(a[i + 19]));
        let mut sorted = indexes;
        sorted.sort();
        if !pars.iter().all(|par| (3..=5).contains(par)) ||
           !sorted.iter().enumerate().all(|(i, &si)| si == i as i32 + 1) {
            return Err("invalid course".into());
        }
        let course = Course {
            id: a[0].into(), pars, indexes, par: pars.iter().sum(),
            tees: BTreeMap::new(),
        };
        self.courses.insert(a[0].into(), course);
        Ok(())
    }

    fn register_tee(&mut self, a: &[&str]) -> Result<(), String> {
        let mut course = self.course(a[0])?;
        if course.tees.contains_key(a[1]) {
            return Err("duplicate tee".into());
        }
        let rating = number(a[2]);
        let slope = number(a[3]);
        if !(500..=900).contains(&rating) || !(55..=155).contains(&slope) {
            return Err("invalid tee".into());
        }
        course.tees.insert(a[1].into(), Tee {
            id: a[1].into(), rating, slope,
        });
        self.courses.insert(a[0].into(), course);
        Ok(())
    }

    fn register_player(&mut self, a: &[&str]) -> Result<(), String> {
        if self.players.contains_key(a[0]) {
            return Err("duplicate player".into());
        }
        let index = a.get(2).map(|text| number(text));
        if index.is_some_and(|v| !(-100..=540).contains(&v)) {
            return Err("invalid index".into());
        }
        self.players.insert(a[0].into(), Player {
            id: a[0].into(), name: a[1].into(), index,
            rounds: Vec::new(), records: Vec::new(), calculation: None,
        });
        Ok(())
    }

    fn add_round(&mut self, a: &[&str]) -> Result<(), String> {
        let player = self.player(a[0])?;
        let (course, tee) = self.tee(a[1], a[2])?;
        let day = number(a[3]);
        if player.rounds.last().is_some_and(|r| day < r.day) {
            return Err("invalid day".into());
        }
        let scores = std::array::from_fn(|i| match a[i + 4] {
            "-" => -1,
            "X" => 0,
            value => number(value),
        });
        if scores.iter().filter(|&&score| score == -1).count() >= 5 {
            return Err("too few holes".into());
        }
        let record = Round::new(&player, &course, &tee, day, scores);
        let p = self.players.get_mut(a[0]).unwrap();
        p.rounds.push(record.clone());
        p.update_index(day);
        if let Some(index) = p.index {
            p.records.push((day, index));
        }
        let mut parts = vec![
            "round".to_owned(), p.id.clone(), format!("{}:", p.rounds.len()),
            "ags".into(), record.ags.to_string(),
            "diff".into(), decimal(record.differential, "-"),
        ];
        if record.exceptional != 0 {
            parts.push("exceptional".into());
            parts.push(decimal(-record.exceptional, "-"));
        }
        parts.push("index".into());
        parts.push(index_display(p.index));
        self.emit(parts.join(" "));
        Ok(())
    }

    fn remove(&mut self, a: &[&str]) -> Result<(), String> {
        let p = self.players.get_mut(a[0]).ok_or("unknown player")?;
        let number = p.rounds.len();
        let record = p.rounds.pop().ok_or("no rounds")?;
        p.index = record.previous_index;
        p.records.truncate(record.previous_records);
        p.calculation = record.previous_calculation;
        let line = format!(
            "removed {} {}: index {}", p.id, number, index_display(p.index));
        self.emit(line);
        Ok(())
    }

    fn show_index(&mut self, a: &[&str]) -> Result<(), String> {
        let p = self.player(a[0])?;
        let mut parts = vec![
            "index".to_owned(), format!("{}:", p.id), index_display(p.index),
            "rounds".into(), p.rounds.len().to_string(),
        ];
        if let Some(c) = p.calculation {
            parts.extend([
                "lowest".into(), c.lowest.to_string(),
                "average".into(), decimal(c.average, "-"),
                "adjustment".into(), decimal(c.adjustment, "-"),
            ]);
            if let Some(low) = c.low {
                parts.push("low".into());
                parts.push(index_display(Some(low)));
            }
            if c.hard {
                parts.extend(["hard".into(), "cap".into()]);
            } else if c.soft {
                parts.extend(["soft".into(), "cap".into()]);
            }
            if c.maximum {
                parts.push("maximum".into());
            }
        }
        self.emit(parts.join(" "));
        Ok(())
    }

    fn history(&mut self, a: &[&str]) -> Result<(), String> {
        let p = self.player(a[0])?;
        let eligible = p.eligible();
        let (selected, _) = p.counting(&eligible);
        let counted: BTreeSet<usize> = selected.iter().map(|row| row.number).collect();
        self.emit(format!("history {}: rounds {}", p.id, p.rounds.len()));
        for row in eligible {
            let record = &p.rounds[row.number - 1];
            let mut parts = vec![
                row.number.to_string(), "day".into(), record.day.to_string(),
                record.course_id.clone(), record.tee_id.clone(),
                "ags".into(), record.ags.to_string(), "diff".into(),
                decimal(record.differential, "-"),
            ];
            if row.adjusted != record.differential {
                parts.push("adjusted".into());
                parts.push(decimal(row.adjusted, "-"));
            }
            if counted.contains(&row.number) {
                parts.push("*".into());
            }
            self.emit(parts.join(" "));
        }
        Ok(())
    }

    fn lowindex(&mut self, a: &[&str]) -> Result<(), String> {
        let p = self.player(a[0])?;
        let line = match p.low_index(number(a[1])) {
            Some((index, date)) => format!(
                "lowindex {} {}: {} day {}", p.id, a[1], index_display(Some(index)), date),
            None => format!("lowindex {} {}: none", p.id, a[1]),
        };
        self.emit(line);
        Ok(())
    }

    fn coursehcp(&mut self, a: &[&str]) -> Result<(), String> {
        let p = self.player(a[0])?;
        let (c, t) = self.tee(a[1], a[2])?;
        let index = p.index.ok_or("no index")?;
        let handicap = t.handicap(index, &c);
        let mut parts = vec![
            "coursehcp".to_owned(), p.id, c.id, format!("{}:", t.id),
            handicap_display(Some(handicap)), "strokes".into(),
        ];
        parts.extend(allocation(handicap, &c.indexes).iter().map(i32::to_string));
        self.emit(parts.join(" "));
        Ok(())
    }

    fn hcptable(&mut self, a: &[&str]) -> Result<(), String> {
        let (c, t) = self.tee(a[0], a[1])?;
        let first = number(a[2]);
        let last = number(a[3]);
        if first < -100 || last > 540 || first > last {
            return Err("invalid index".into());
        }
        self.emit(format!(
            "hcptable {} {}: {} to {}", c.id, t.id,
            index_display(Some(first)), index_display(Some(last))));
        let mut start = first;
        let mut handicap = t.handicap(first, &c);
        for index in first + 1..=last {
            let next = t.handicap(index, &c);
            if next != handicap {
                self.emit(format!(
                    "{} to {}: {}", index_display(Some(start)),
                    index_display(Some(index - 1)), handicap_display(Some(handicap))));
                start = index;
                handicap = next;
            }
        }
        self.emit(format!(
            "{} to {}: {}", index_display(Some(start)),
            index_display(Some(last)), handicap_display(Some(handicap))));
        Ok(())
    }

    fn card_total(&mut self, label: &str, record: &Round,
                  strokes: &[i32; 18], nets: &[Option<i32>; 18],
                  points: &[i32; 18], first: usize, last: usize) {
        let complete = record.scores[first..last].iter().all(|&score| score > 0);
        let gross: i32 = record.scores[first..last].iter().filter(|&&v| v > 0).sum();
        let net: i32 = nets[first..last].iter().flatten().copied().sum();
        let pars: i32 = record.pars[first..last].iter().sum();
        let ags: i32 = record.adjusted[first..last].iter().sum();
        let allocated: i32 = strokes[first..last].iter().sum();
        let pts: i32 = points[first..last].iter().sum();
        self.emit(format!(
            "{label} {pars} {} {ags} {allocated} {} {pts}",
            if complete { gross.to_string() } else { "-".into() },
            if complete { net.to_string() } else { "-".into() },
        ));
    }

    fn card(&mut self, a: &[&str]) -> Result<(), String> {
        let p = self.player(a[0])?;
        let number = number(a[1]) as usize;
        let record = p.rounds.get(number - 1).ok_or("unknown round")?;
        let strokes = allocation(record.handicap.unwrap_or(0), &record.indexes);
        let nets = record.nets(&strokes);
        let points = record.points(&nets);
        self.emit(format!(
            "card {} {}: {} {} day {} handicap {}", p.id, number,
            record.course_id, record.tee_id, record.day,
            handicap_display(record.handicap)));
        for h in 0..18 {
            let score = match record.scores[h] {
                -1 => "-".into(),
                0 => "X".into(),
                value => value.to_string(),
            };
            self.emit(format!(
                "{} {} {} {} {} {} {} {}", h + 1, record.pars[h],
                record.indexes[h], score, record.adjusted[h], strokes[h],
                nets[h].map_or_else(|| "-".into(), |v| v.to_string()), points[h]));
            if h == 8 {
                self.card_total("OUT", record, &strokes, &nets, &points, 0, 9);
            }
            if h == 17 {
                self.card_total("IN", record, &strokes, &nets, &points, 9, 18);
                self.card_total("TOTAL", record, &strokes, &nets, &points, 0, 18);
            }
        }
        self.emit(format!(
            "ags {} diff {}", record.ags, decimal(record.differential, "-")));
        Ok(())
    }

    fn stats(&mut self, a: &[&str]) -> Result<(), String> {
        let p = self.player(a[0])?;
        let labels = [
            "eagles", "birdies", "pars", "bogeys", "doubles", "others", "pickups"
        ];
        let mut categories = [0usize; 7];
        let mut par_total = [0i64; 6];
        let mut par_count = [0usize; 6];
        let mut complete_totals = Vec::new();
        for record in &p.rounds {
            if record.complete() {
                complete_totals.push(record.scores.iter().sum::<i32>());
            }
            for (&score, &par) in record.scores.iter().zip(record.pars.iter()) {
                if score == 0 {
                    categories[6] += 1;
                } else if score > 0 {
                    let category = (score - par + 2).clamp(0, 5) as usize;
                    categories[category] += 1;
                    par_total[par as usize] += i64::from(score);
                    par_count[par as usize] += 1;
                }
            }
        }
        let best = complete_totals.iter().min().map_or_else(
            || "-".to_owned(), i32::to_string);
        let mut parts = vec![
            format!("stats {}:", p.id), "rounds".into(), p.rounds.len().to_string(),
            "best".into(), best, "average".into(),
            average(complete_totals.iter().map(|&v| i64::from(v)).sum(),
                    complete_totals.len()),
        ];
        for (label, count) in labels.iter().zip(categories) {
            parts.push((*label).into());
            parts.push(count.to_string());
        }
        for par in 3..=5 {
            parts.push(format!("par{par}"));
            parts.push(average(par_total[par], par_count[par]));
        }
        self.emit(parts.join(" "));
        Ok(())
    }

    fn holestats(&mut self, a: &[&str]) -> Result<(), String> {
        let c = self.course(a[0])?;
        let mut totals = [0i64; 18];
        let mut counts = [0i64; 18];
        let mut considered = 0usize;
        for p in self.players.values() {
            for r in &p.rounds {
                if r.course_id != c.id {
                    continue;
                }
                considered += 1;
                for h in 0..18 {
                    if r.scores[h] > 0 {
                        counts[h] += 1;
                        totals[h] += i64::from(r.scores[h]);
                    }
                }
            }
        }
        let mut holes: Vec<usize> = (0..18).collect();
        holes.sort_by(|&a, &b| match (counts[a], counts[b]) {
            (0, 0) => a.cmp(&b),
            (0, _) => std::cmp::Ordering::Greater,
            (_, 0) => std::cmp::Ordering::Less,
            _ => {
                let left = (totals[a] - i64::from(c.pars[a]) * counts[a]) * counts[b];
                let right = (totals[b] - i64::from(c.pars[b]) * counts[b]) * counts[a];
                right.cmp(&left).then(a.cmp(&b))
            }
        });
        let mut ranks = [0usize; 18];
        for (rank, hole) in holes.into_iter().enumerate() {
            ranks[hole] = rank + 1;
        }
        self.emit(format!("holestats {}: rounds {}", c.id, considered));
        for h in 0..18 {
            self.emit(format!(
                "{} par {} si {} scores {} avg {} rank {}",
                h + 1, c.pars[h], c.indexes[h], counts[h],
                average(totals[h], counts[h] as usize), ranks[h]));
        }
        Ok(())
    }

    fn show_players(&mut self) {
        let mut players: Vec<Player> = self.players.values().cloned().collect();
        players.sort_by(|a, b| {
            (a.index.is_none(), a.index.unwrap_or(0), &a.id)
                .cmp(&(b.index.is_none(), b.index.unwrap_or(0), &b.id))
        });
        self.emit(format!("players {}", players.len()));
        for p in players {
            self.emit(format!(
                "{} {} {} rounds {}", p.id, p.name,
                index_display(p.index), p.rounds.len()));
        }
    }

    fn register_event(&mut self, a: &[&str]) -> Result<(), String> {
        if self.events.contains_key(a[0]) {
            return Err("duplicate event".into());
        }
        let _ = self.tee(a[2], a[3])?;
        let allowance = number(a[5]);
        if !(1..=100).contains(&allowance) {
            return Err("invalid allowance".into());
        }
        for id in &a[6..] {
            let _ = self.player(id)?;
        }
        let players: Vec<String> = a[6..].iter().map(|s| (*s).to_owned()).collect();
        let count = players.len();
        let valid = match a[1] {
            "MATCH" | "NASSAU" => count == 2,
            "FOURBALL" => count == 4,
            "BETTERBALL" => [4, 6, 8].contains(&count),
            _ => (2..=8).contains(&count),
        };
        if !valid || players.iter().collect::<BTreeSet<_>>().len() != count {
            return Err("invalid players".into());
        }
        self.events.insert(a[0].into(), Event {
            id: a[0].into(), format: a[1].into(),
            course_id: a[2].into(), tee_id: a[3].into(),
            day: number(a[4]), allowance, players,
        });
        Ok(())
    }

    fn event_data(&self, event: &Event) -> Result<EventData, String> {
        let course = self.course(&event.course_id)?;
        let mut rounds = Vec::new();
        let mut handicaps = Vec::new();
        for id in &event.players {
            let p = self.player(id)?;
            let record = p.rounds.iter().find(|r| {
                r.course_id == event.course_id && r.tee_id == event.tee_id &&
                r.day == event.day
            }).ok_or("missing round")?;
            let handicap = record.handicap.ok_or("no index")?;
            rounds.push(record.clone());
            handicaps.push(half_up(
                i64::from(handicap) * i64::from(event.allowance), 100));
        }
        let minimum = if ["MATCH", "NASSAU", "FOURBALL"].contains(&event.format.as_str()) {
            *handicaps.iter().min().unwrap()
        } else {
            0
        };
        let mut nets = Vec::new();
        let mut points = Vec::new();
        for (record, &handicap) in rounds.iter().zip(handicaps.iter()) {
            let strokes = allocation(handicap - minimum, &course.indexes);
            let net = record.nets(&strokes);
            points.push(record.points(&net));
            nets.push(net);
        }
        Ok(EventData { rounds, handicaps, nets, points })
    }

    fn event_ranking(&self, event: &Event, data: &EventData)
        -> (Vec<usize>, Vec<[i32; 18]>) {
        let mut order = Vec::new();
        let mut values = Vec::new();
        for i in 0..event.players.len() {
            let record = &data.rounds[i];
            let row = std::array::from_fn(|h| match event.format.as_str() {
                "STABLEFORD" => data.points[i][h],
                "STROKE" => data.nets[i][h].unwrap_or(0),
                _ => match data.nets[i][h] {
                    None => -1,
                    Some(net) if net > record.pars[h] => -1,
                    Some(net) if net < record.pars[h] => 1,
                    _ => 0,
                },
            });
            values.push(row);
            if event.format != "STROKE" || record.complete() {
                order.push(i);
            }
        }
        let larger = event.format != "STROKE";
        order.sort_by(|&a, &b| {
            let left = countback(&values[a]);
            let right = countback(&values[b]);
            let relation = if larger { right.cmp(&left) } else { left.cmp(&right) };
            relation.then(event.players[a].cmp(&event.players[b]))
        });
        (order, values)
    }

    fn individual_results(&mut self, event: &Event, data: &EventData) {
        let (order, values) = self.event_ranking(event, data);
        for (rank, &i) in order.iter().enumerate() {
            let handicap = handicap_display(Some(data.handicaps[i]));
            let details = match event.format.as_str() {
                "STROKE" => format!(
                    "net {} gross {}", values[i].iter().sum::<i32>(),
                    data.rounds[i].scores.iter().sum::<i32>()),
                "STABLEFORD" => format!("points {}", data.points[i].iter().sum::<i32>()),
                _ => match_status(values[i].iter().sum::<i32>()),
            };
            self.emit(format!(
                "{} {} {} hcp {}", rank + 1, event.players[i], details, handicap));
        }
        if event.format == "STROKE" {
            let mut no_returns: Vec<usize> = (0..event.players.len())
                .filter(|&i| !data.rounds[i].complete()).collect();
            no_returns.sort_by_key(|&i| &event.players[i]);
            for i in no_returns {
                self.emit(format!(
                    "NR {} hcp {}", event.players[i],
                    handicap_display(Some(data.handicaps[i]))));
            }
            if !order.is_empty() {
                let winner = *order.iter().min_by(|&&a, &&b| {
                    countback(&data.rounds[a].scores)
                        .cmp(&countback(&data.rounds[b].scores))
                        .then(event.players[a].cmp(&event.players[b]))
                }).unwrap();
                self.emit(format!(
                    "gross {} {}", event.players[winner],
                    data.rounds[winner].scores.iter().sum::<i32>()));
            }
        }
    }

    fn match_holes(&self, event: &Event, data: &EventData)
        -> ([String; 2], [i32; 18]) {
        let (sides, names) = if event.format == "FOURBALL" {
            (
                [vec![0, 1], vec![2, 3]],
                [
                    format!("{}+{}", event.players[0], event.players[1]),
                    format!("{}+{}", event.players[2], event.players[3]),
                ],
            )
        } else {
            (
                [vec![0], vec![1]],
                [event.players[0].clone(), event.players[1].clone()],
            )
        };
        let holes = std::array::from_fn(|h| {
            let best = |side: &Vec<usize>| {
                side.iter().filter_map(|&i| data.nets[i][h]).min()
            };
            match (best(&sides[0]), best(&sides[1])) {
                (None, None) => 0,
                (None, Some(_)) => -1,
                (Some(_), None) => 1,
                (Some(a), Some(b)) => i32::from(a < b) - i32::from(a > b),
            }
        });
        (names, holes)
    }

    fn play_match(names: &[String; 2], holes: &[i32; 18],
                  first: usize, last: usize) -> (Vec<String>, String) {
        let mut lead: i32 = 0;
        let mut remaining = 0usize;
        let mut statuses = Vec::new();
        for hole in first..last {
            lead += holes[hole];
            statuses.push(match_status(lead));
            remaining = last - hole - 1;
            if lead.abs() as usize > remaining || remaining == 0 {
                break;
            }
        }
        let result = if lead == 0 {
            "AS".to_owned()
        } else {
            let winner = &names[usize::from(lead < 0)];
            let margin = if remaining == 0 {
                format!("{} UP", lead.abs())
            } else {
                format!("{}&{remaining}", lead.abs())
            };
            format!("{winner} {margin}")
        };
        (statuses, result)
    }

    fn match_results(&mut self, event: &Event, data: &EventData) {
        let minimum = *data.handicaps.iter().min().unwrap();
        let mut parts = vec!["strokes".to_owned()];
        for (id, &handicap) in event.players.iter().zip(data.handicaps.iter()) {
            parts.push(id.clone());
            parts.push((handicap - minimum).to_string());
        }
        self.emit(parts.join(" "));
        let (names, holes) = self.match_holes(event, data);
        if event.format == "NASSAU" {
            for (label, first, last) in [("front", 0, 9), ("back", 9, 18), ("total", 0, 18)] {
                let (_, result) = Self::play_match(&names, &holes, first, last);
                self.emit(format!("{label} {result}"));
            }
        } else {
            let (statuses, result) = Self::play_match(&names, &holes, 0, 18);
            self.emit(format!("status {}", statuses.join(", ")));
            self.emit(format!("result {result}"));
        }
    }

    fn betterball_results(&mut self, event: &Event, data: &EventData) {
        let mut values = Vec::new();
        for pair in (0..event.players.len()).step_by(2) {
            values.push(std::array::from_fn(|h| data.points[pair][h]
                .max(data.points[pair + 1][h])));
        }
        let mut order: Vec<usize> = (0..values.len()).collect();
        order.sort_by(|&a, &b| {
            countback(&values[b]).cmp(&countback(&values[a]))
                .then(event.players[2 * a].cmp(&event.players[2 * b]))
        });
        for (rank, team) in order.into_iter().enumerate() {
            self.emit(format!(
                "{} {}+{} points {} hcp {} {}", rank + 1,
                event.players[2 * team], event.players[2 * team + 1],
                values[team].iter().sum::<i32>(),
                handicap_display(Some(data.handicaps[2 * team])),
                handicap_display(Some(data.handicaps[2 * team + 1])),
            ));
        }
    }

    fn skins_results(&mut self, event: &Event, data: &EventData) {
        let mut totals = vec![0i32; event.players.len()];
        let mut carry = 0i32;
        let mut last_minimum: Vec<usize> = Vec::new();
        for hole in 0..18 {
            carry += 1;
            let best = (0..event.players.len())
                .filter_map(|i| data.nets[i][hole]).min();
            let winners: Vec<usize> = (0..event.players.len())
                .filter(|&i| best.is_some() && data.nets[i][hole] == best).collect();
            last_minimum = winners.clone();
            if winners.len() == 1 {
                self.emit(format!(
                    "hole {} {} {}", hole + 1, event.players[winners[0]], carry));
                totals[winners[0]] += 100 * carry;
                carry = 0;
            }
        }
        if carry != 0 {
            let mut sharing = if last_minimum.is_empty() {
                (0..event.players.len()).collect::<Vec<_>>()
            } else {
                last_minimum
            };
            sharing.sort_by_key(|&i| &event.players[i]);
            let portion = 100 * carry / sharing.len() as i32;
            for &i in &sharing {
                totals[i] += portion;
            }
            let mut parts = vec!["carry".into(), carry.to_string()];
            parts.extend(sharing.iter().map(|&i| event.players[i].clone()));
            self.emit(parts.join(" "));
        }
        let mut order: Vec<usize> = (0..event.players.len()).collect();
        order.sort_by(|&a, &b| {
            totals[b].cmp(&totals[a]).then(event.players[a].cmp(&event.players[b]))
        });
        for i in order {
            self.emit(format!(
                "{} {}.{:02}", event.players[i], totals[i] / 100, totals[i] % 100));
        }
    }

    fn results(&mut self, a: &[&str]) -> Result<(), String> {
        let event = self.events.get(a[0]).cloned().ok_or("unknown event")?;
        let data = self.event_data(&event)?;
        self.emit(format!(
            "results {}: {} {} {} day {} allowance {}", event.id, event.format,
            event.course_id, event.tee_id, event.day, event.allowance));
        match event.format.as_str() {
            "STROKE" | "STABLEFORD" | "PAR" => self.individual_results(&event, &data),
            "MATCH" | "NASSAU" | "FOURBALL" => self.match_results(&event, &data),
            "BETTERBALL" => self.betterball_results(&event, &data),
            _ => self.skins_results(&event, &data),
        }
        Ok(())
    }

    fn merit(&mut self) {
        let awards = [10, 8, 6, 5, 4, 3, 2, 1];
        let mut tally: BTreeMap<String, [i32; 3]> = BTreeMap::new();
        let mut counted = 0;
        for event in self.events.values() {
            if !["STROKE", "STABLEFORD", "PAR"].contains(&event.format.as_str()) {
                continue;
            }
            let Ok(data) = self.event_data(event) else { continue };
            counted += 1;
            let (order, _) = self.event_ranking(event, &data);
            for id in &event.players {
                tally.entry(id.clone()).or_default()[2] += 1;
            }
            for (rank, i) in order.into_iter().enumerate() {
                let row = tally.entry(event.players[i].clone()).or_default();
                row[0] += awards[rank];
                if rank == 0 {
                    row[1] += 1;
                }
            }
        }
        self.emit(format!("merit: events {counted}"));
        let mut rows: Vec<_> = tally.into_iter().collect();
        rows.sort_by(|(id_a, a), (id_b, b)| {
            b[0].cmp(&a[0]).then(b[1].cmp(&a[1])).then(id_a.cmp(id_b))
        });
        for (rank, (id, row)) in rows.into_iter().enumerate() {
            self.emit(format!(
                "{} {} {} wins {} played {}", rank + 1, id, row[0], row[1], row[2]));
        }
    }

    fn dispatch(&mut self, command: &str, a: &[&str]) -> Result<(), String> {
        match command {
            "COURSE" => self.register_course(a),
            "TEE" => self.register_tee(a),
            "PLAYER" => self.register_player(a),
            "ROUND" => self.add_round(a),
            "REMOVE" => self.remove(a),
            "INDEX" => self.show_index(a),
            "HISTORY" => self.history(a),
            "LOWINDEX" => self.lowindex(a),
            "COURSEHCP" => self.coursehcp(a),
            "HCPTABLE" => self.hcptable(a),
            "CARD" => self.card(a),
            "STATS" => self.stats(a),
            "HOLESTATS" => self.holestats(a),
            "PLAYERS" => { self.show_players(); Ok(()) }
            "EVENT" => self.register_event(a),
            "RESULTS" => self.results(a),
            "MERIT" => { self.merit(); Ok(()) }
            _ => unreachable!(),
        }
    }

    fn execute(&mut self, line: &str) {
        let mut words = line.split_whitespace();
        let command = words.next().unwrap();
        let arguments: Vec<_> = words.collect();
        if let Err(reason) = self.dispatch(command, &arguments) {
            self.emit(format!("ERROR {reason}"));
        }
    }
}

fn main() {
    let stdin = io::stdin();
    let mut lines = stdin.lock().lines();
    let count: usize = lines.next().unwrap().unwrap().parse().unwrap();
    let mut scorer = Scorer::new();
    for _ in 0..count {
        scorer.execute(&lines.next().unwrap().unwrap());
    }
    if !scorer.output.is_empty() {
        println!("{}", scorer.output.join("\n"));
    }
}
