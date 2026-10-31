use std::collections::BTreeMap;
use std::fs;
use crate::report::Fraction;

#[derive(Clone)]
pub struct Row { pub line: usize, pub case: String, pub activity: String, pub timestamp: String, pub resource: String }
#[derive(Clone)]
pub struct Event { pub row: Row, pub time: i64 }
pub struct Case { pub id: String, pub events: Vec<Event> }
impl Case {
    pub fn trace(&self) -> Vec<String> { self.events.iter().map(|e| e.row.activity.clone()).collect() }
    pub fn duration(&self) -> i64 { self.events.last().unwrap().time-self.events[0].time }
}
pub struct Params { pub filter: i64, pub sla: i64, pub observations: i64, pub dependency: Fraction, pub relative: Fraction, pub loop1: Fraction, pub loop2: Fraction, pub and: Fraction }

pub fn read() -> (Vec<Row>, Params) {
    let rows = fs::read_to_string("input/eventlog.csv").unwrap().lines().skip(1).enumerate().map(|(i, line)| {
        let w: Vec<_> = line.split(',').collect();
        Row { line: i+2, case: w[0].to_owned(), activity: w[1].to_owned(), timestamp: w[2].to_owned(), resource: w[3].to_owned() }
    }).collect();
    let input = fs::read_to_string("input/params.txt").unwrap();
    let values: Vec<_> = input.lines().map(|line| line.split_once(' ').unwrap().1).collect();
    let p = Params { filter: values[0].parse().unwrap(), sla: values[1].parse().unwrap(), observations: values[2].parse().unwrap(),
        dependency: Fraction::parse(values[3]), relative: Fraction::parse(values[4]), loop1: Fraction::parse(values[5]), loop2: Fraction::parse(values[6]), and: Fraction::parse(values[7]) };
    (rows, p)
}

pub fn timestamp(value: &str) -> Option<i64> {
    let month = value[5..7].parse::<usize>().ok()?;
    let day = value[8..10].parse::<i64>().ok()?;
    let hour = value[11..13].parse::<i64>().ok()?;
    let minute = value[14..16].parse::<i64>().ok()?;
    let months = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    if month == 0 || month > 12 || day < 1 || day > months[month-1] || hour > 23 || minute > 59 { return None; }
    Some(((months[..month-1].iter().sum::<i64>()+day-1)*24+hour)*60+minute)
}

pub fn cases(events: &[Event]) -> Vec<Case> {
    let mut groups = BTreeMap::<String, Vec<Event>>::new();
    for event in events { groups.entry(event.row.case.clone()).or_default().push(event.clone()); }
    groups.into_iter().map(|(id, mut events)| { events.sort_by_key(|e| (e.time, e.row.line)); Case { id, events } }).collect()
}

pub fn median(values: &[i64]) -> Fraction {
    let mut sorted = values.to_vec(); sorted.sort_unstable();
    let n = sorted.len();
    if n%2 == 1 { Fraction::new(sorted[n/2], 1) } else { Fraction::new(sorted[n/2-1]+sorted[n/2], 2) }
}
