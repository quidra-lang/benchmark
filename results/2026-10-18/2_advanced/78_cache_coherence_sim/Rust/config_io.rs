use std::fs;
pub struct Scenario {
    pub name: String,
    pub protocol: String,
    pub l1_policy: String,
    pub l2_policy: String
}
pub struct Region {
    pub name: String,
    pub first: usize,
    pub last: usize
}
pub struct Config {
    pub cores: usize,
    pub line: usize,
    pub l1: [usize;3],
    pub l2: [usize;3],
    pub latency: [usize;4],
    pub scenarios: Vec<Scenario>,
    pub primary: usize,
    pub interval: usize,
    pub top: usize,
    pub regions: Vec<Region>,
    pub watched: Vec<usize>
}
pub fn decimal(value: &str) -> bool {
    !value.is_empty() && value.bytes().all(|b| b.is_ascii_digit()) && (value.len() == 1 || !value.starts_with('0'))
}
pub fn hexadecimal(value: &str) -> bool {
    value.len() == 8 && value.bytes().all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
}
pub fn address(value: usize) -> String {
    format!("{:08x}",value)
}
pub fn read() -> (Config,Vec<String>) {
    let mut config = Config {
        cores: 0,
        line: 0,
        l1: [0;3],
        l2: [0;3],
        latency: [0;4],
        scenarios: Vec::new(),
        primary: 0,
        interval: 0,
        top: 0,
        regions: Vec::new(),
        watched: Vec::new()
    };
    let mut primary = String::new();
    for line in fs::read_to_string("input/config.txt").unwrap().lines() {
        let w: Vec<_> = line.split_whitespace().collect();
        let number = |i: usize| w[i].parse::<usize>().unwrap();
        match w[0] {
            "CORES" => config.cores = number(1),"LINE" => config.line = number(1),"L1" => config.l1 = [number(1),number(2),0],"L2" => config.l2 = [number(1),number(2),0],"LATENCY" => config.latency = [number(1),number(2),number(3),number(4)],"SCENARIO" => config.scenarios.push(Scenario {
                name: w[1].to_owned(),
                protocol: w[2].to_owned(),
                l1_policy: w[3].to_owned(),
                l2_policy: w[4].to_owned()
            }),"PRIMARY" => primary = w[1].to_owned(),"INTERVAL" => config.interval = number(1),"TOP" => config.top = number(1),"REGION" => config.regions.push(Region {
                name: w[1].to_owned(),
                first: usize::from_str_radix(w[2],16).unwrap(),
                last: usize::from_str_radix(w[3],16).unwrap()
            }),_ => config.watched.push(usize::from_str_radix(w[1],16).unwrap())
        }
    }
    config.l1[2] = config.l1[0]/(config.line*config.l1[1]);
    config.l2[2] = config.l2[0]/(config.line*config.l2[1]);
    config.primary = config.scenarios.iter().position(|s| s.name == primary).unwrap();
    let trace = fs::read_to_string("input/trace.txt").unwrap().lines().map(str::to_owned).collect();
    (config,trace)
}
pub fn write(name: &str, lines: &[String]) {
    fs::create_dir_all("output").unwrap();
    let text = if lines.is_empty() {
        String::new()
    } else {
        lines.join("\n")+"\n"
    };
    fs::write(format!("output/{}",name),text).unwrap();
}
