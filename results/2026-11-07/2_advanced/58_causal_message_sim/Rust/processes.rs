use std::collections::BTreeMap;
use std::fs;

#[derive(Clone)]
pub enum Destination { Process(usize), Sender }

#[derive(Clone)]
pub enum Action {
    Local(String),
    Send(Destination, String),
    Transfer(Destination, i64),
    Broadcast(String),
    Snapshot(String),
}

pub struct Schedule {
    pub time: i64,
    pub period: Option<i64>,
    pub action: Action,
}

pub struct Program {
    pub initial: i64,
    pub scheduled: Vec<Schedule>,
    pub reactions: Vec<(String, Action)>,
}

fn action(w: &[&str], names: &[String]) -> Action {
    let destination = || if w[1] == "SENDER" { Destination::Sender }
        else { Destination::Process(names.iter().position(|n| n == w[1]).unwrap()) };
    match w[0] {
        "LOCAL" => Action::Local(w[1].to_owned()),
        "SEND" => Action::Send(destination(), w[2].to_owned()),
        "TRANSFER" => Action::Transfer(destination(), w[2].parse().unwrap()),
        "BROADCAST" => Action::Broadcast(w[1].to_owned()),
        _ => Action::Snapshot(w[1].to_owned()),
    }
}

pub fn read(names: &[String]) -> Vec<Program> {
    let input = fs::read_to_string("input/programs.txt").unwrap();
    let mut programs = Vec::<Program>::new();
    for line in input.lines() {
        let w: Vec<_> = line.split_whitespace().collect();
        match w[0] {
            "PROCESS" => programs.push(Program { initial: w[3].parse().unwrap(),
                scheduled: Vec::new(), reactions: Vec::new() }),
            "AT" => {
                let recurring = w[2] == "EVERY";
                programs.last_mut().unwrap().scheduled.push(Schedule {
                    time: w[1].parse().unwrap(),
                    period: if recurring { Some(w[3].parse().unwrap()) } else { None },
                    action: action(&w[if recurring { 4 } else { 2 }..], names),
                });
            }
            "ON" => programs.last_mut().unwrap().reactions.push((w[1].to_owned(), action(&w[2..], names))),
            _ => {}
        }
    }
    programs
}

pub fn expand(programs: &[Program], end: i64) -> Vec<(i64, usize, Action)> {
    let mut items = Vec::new();
    for (p, program) in programs.iter().enumerate() {
        for line in &program.scheduled {
            let mut time = line.time;
            while time <= end {
                items.push((time, p, line.action.clone()));
                if let Some(period) = line.period { time += period; } else { break; }
            }
        }
    }
    items
}

#[derive(Clone)]
pub enum EventKind {
    Local(String), NoFunds { destination: usize, amount: i64 },
    Send(usize), Broadcast(usize), Receive(usize),
}

pub struct Event {
    pub process: usize,
    pub ordinal: usize,
    pub time: i64,
    pub lamport: usize,
    pub vector: Vec<usize>,
    pub balance: i64,
    pub kind: EventKind,
}

pub struct Message {
    pub source: usize,
    pub destination: Option<usize>,
    pub broadcast: bool,
    pub tag: String,
    pub amount: i64,
    pub event: usize,
    pub stamp: Vec<usize>,
    pub copies: Vec<usize>,
}

pub struct Copy {
    pub message: usize,
    pub source: usize,
    pub destination: usize,
    pub packet: usize,
    pub received: Option<usize>,
    pub fifo: bool,
    pub causal: bool,
    pub missing: Vec<usize>,
}

pub struct State {
    pub balance: i64,
    pub lamport: usize,
    pub vector: Vec<usize>,
    pub broadcast: Vec<usize>,
    pub next: Vec<usize>,
    pub reorder: Vec<BTreeMap<usize, usize>>,
    pub hold: Vec<usize>,
    pub events: Vec<usize>,
    pub delivered: Vec<usize>,
    pub max_held: usize,
    pub counts: [usize; 5],
    pub received: i64,
    pub sent: i64,
    pub minimum: i64,
}

impl State {
    pub fn new(balance: i64, n: usize) -> Self {
        Self { balance, lamport: 0, vector: vec![0; n], broadcast: vec![0; n],
            next: vec![1; n], reorder: vec![BTreeMap::new(); n], hold: Vec::new(),
            events: Vec::new(), delivered: Vec::new(), max_held: 0, counts: [0; 5],
            received: 0, sent: 0, minimum: balance }
    }
}

pub fn balance_at(initial: i64, state: &State, events: &[Event], cut: usize) -> i64 {
    if cut == 0 { initial } else { events[state.events[cut - 1]].balance }
}
