use std::fs;

#[derive(Clone)]
pub struct Channel {
    pub fifo: bool,
    pub a: i64,
    pub b: i64,
}

pub struct Topology {
    pub names: Vec<String>,
    pub channels: Vec<Option<Channel>>,
}

impl Topology {
    pub fn read() -> Self {
        let input = fs::read_to_string("input/topology.txt").unwrap();
        let mut lines = input.lines();
        let names: Vec<String> = lines.next().unwrap().split_whitespace().skip(1)
            .map(str::to_owned).collect();
        let n = names.len();
        let mut channels = vec![None; n * n];
        for line in lines {
            let w: Vec<_> = line.split_whitespace().collect();
            let s = names.iter().position(|x| x == w[1]).unwrap();
            let d = names.iter().position(|x| x == w[2]).unwrap();
            let a = w[4].parse().unwrap();
            channels[s * n + d] = Some(Channel {
                fifo: w[3] == "FIFO", a,
                b: if w.len() == 6 { w[5].parse().unwrap() } else { a },
            });
        }
        Self { names, channels }
    }
}

pub struct Generator {
    pub state: i64,
    pub draws: usize,
}

impl Generator {
    pub fn next(&mut self) -> i64 {
        self.state = self.state * 48271 % 2147483647;
        self.draws += 1;
        self.state
    }
}

pub struct State {
    pub sequence: usize,
    pub last_arrival: i64,
    pub copies: usize,
    pub markers: usize,
    pub buffered: usize,
    pub max_delay: i64,
    pub previous: Vec<usize>,
    pub entries: usize,
}

impl State {
    pub fn new(n: usize) -> Self {
        Self { sequence: 0, last_arrival: 0, copies: 0, markers: 0,
            buffered: 0, max_delay: 0, previous: vec![0; n], entries: 0 }
    }

    pub fn dispatch(&mut self, channel: &Channel, rng: &mut Generator, time: i64,
                    vector: Option<&[usize]>) -> (usize, i64) {
        self.sequence += 1;
        let delay = if channel.a == channel.b { channel.a }
            else { channel.a + rng.next() % (channel.b - channel.a + 1) };
        let mut arrival = time + delay;
        if channel.fifo { arrival = arrival.max(self.last_arrival); }
        self.last_arrival = self.last_arrival.max(arrival);
        self.max_delay = self.max_delay.max(arrival - time);
        if let Some(v) = vector {
            self.copies += 1;
            self.entries += v.iter().zip(&self.previous).filter(|(a, b)| a != b).count();
            self.previous.copy_from_slice(v);
        } else {
            self.markers += 1;
        }
        (self.sequence, arrival)
    }
}

#[derive(Clone, Copy)]
pub enum Kind { Copy(usize), Marker(usize) }

#[derive(Clone)]
pub struct Packet {
    pub source: usize,
    pub destination: usize,
    pub sequence: usize,
    pub dispatch: i64,
    pub arrival: i64,
    pub kind: Kind,
}
