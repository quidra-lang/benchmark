use std::fs;
pub struct Settings {
    pub nodes: usize,
    pub minimum: usize,
    pub maximum: usize,
    pub heartbeat: usize,
    pub batch: usize,
    pub quorum: usize,
    pub seed: i64,
    pub end: usize,
    pub retry: usize,
    pub attempts: usize,
    pub sample: usize
}
#[derive(Clone)] pub enum Control {
    Crash(usize),
    Restart(usize),
    Partition(Vec<Vec<usize>>),
    Heal,
    Transfer(usize,usize)
}
pub struct Request {
    pub at: usize,
    pub original: usize,
    pub command: String,
    pub scheduled: usize,
    pub destination: usize,
    pub attempts: usize,
    pub redirects: usize,
    pub accepted: Option<(usize,usize)>,
    pub abandoned: bool
}
pub struct Input {
    pub settings: Settings,
    pub controls: Vec<(usize,Control)>,
    pub requests: Vec<Request>
}
pub fn read() -> Input {
    let lines: Vec<Vec<i64>> = fs::read_to_string("input/cluster.txt").unwrap().lines().map(|l| l.split_whitespace().skip(1).map(|s| s.parse().unwrap()).collect()).collect();
    let settings = Settings {
        nodes: lines[0][0] as usize,
        minimum: lines[1][0] as usize,
        maximum: lines[1][1] as usize,
        heartbeat: lines[2][0] as usize,
        batch: lines[3][0] as usize,
        quorum: lines[4][0] as usize,
        seed: lines[5][0],
        end: lines[6][0] as usize,
        retry: lines[7][0] as usize,
        attempts: lines[8][0] as usize,
        sample: lines[9][0] as usize
    };
    let mut controls = Vec::new();
    let mut requests = Vec::new();
    for line in fs::read_to_string("input/script.txt").unwrap().lines() {
        let w: Vec<_> = line.split_whitespace().collect();
        let at = w[0].parse().unwrap();
        let node = |i: usize| w[i].parse::<usize>().unwrap()-1;
        if w[1] == "REQUEST" {
            requests.push(Request {
                at,
                original: node(2),
                command: w[3..].join(" "),
                scheduled: at,
                destination: node(2),
                attempts: 0,
                redirects: 0,
                accepted: None,
                abandoned: false
            });
        } else {
            let control = match w[1] {
                "CRASH" => Control::Crash(node(2)),"RESTART" => Control::Restart(node(2)),"PARTITION" => Control::Partition(w[2..].iter().map(|g| g.split(',').map(|n| n.parse::<usize>().unwrap()-1).collect()).collect()),"HEAL" => Control::Heal,_ => Control::Transfer(node(2),node(3))
            };
            controls.push((at,control));
        }
    }
    Input {
        settings,
        controls,
        requests
    }
}
