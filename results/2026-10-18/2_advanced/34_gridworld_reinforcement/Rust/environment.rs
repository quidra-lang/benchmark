use std::fs;

#[derive(Clone)]
pub struct World {
    pub height: usize,
    pub width: usize,
    pub cells: Vec<u8>,
    pub states: Vec<usize>,
    pub terminals: Vec<usize>,
    pub start: usize,
    pub rewards: Vec<i64>,
    pub moves: Vec<[usize; 4]>,
    pub q: i64,
    pub floor_slip: i64,
    pub ice_slip: i64,
}

impl World {
    pub fn read(path: &str, step_reward: i64, slip: &[i64]) -> Self {
        let text = fs::read_to_string(path).unwrap();
        let lines: Vec<_> = text.lines().collect();
        let height = lines[0].split_whitespace().nth(1).unwrap().parse().unwrap();
        let width = lines[1].split_whitespace().nth(1).unwrap().parse().unwrap();
        let cells: Vec<_> = lines[2..2 + height].iter().flat_map(|line| line.bytes()).collect();
        let states = cells.iter().enumerate().filter(|(_, c)| b".S~".contains(c)).map(|(i, _)| i).collect();
        let terminals: Vec<_> = cells.iter().enumerate().filter(|(_, c)| b"GP".contains(c)).map(|(i, _)| i).collect();
        let start = cells.iter().position(|&c| c == b'S').unwrap();
        let wind: Vec<_> = lines[height + 2][5..].bytes().map(|b| usize::from(b - b'0')).collect();
        let terminal_rewards: Vec<i64> = lines[height + 3].split_whitespace().skip(1).map(|s| s.parse().unwrap()).collect();
        let mut rewards = vec![step_reward; cells.len()];
        for (&cell, reward) in terminals.iter().zip(terminal_rewards) { rewards[cell] = reward; }
        let mut world = Self {
            height, width, cells, states, terminals, start, rewards, moves: vec![[0; 4]; height * width],
            q: slip[0], floor_slip: slip[1], ice_slip: slip[2],
        };
        for &x in &world.states {
            let offsets = [-(width as isize), 1, width as isize, -1];
            for (direction, offset) in offsets.iter().enumerate() {
                let next = (x as isize + offset) as usize;
                let mut y = if world.cells[next] == b'#' { x } else { next };
                if !world.terminal(y) {
                    for _ in 0..wind[x % width] {
                        if world.cells[y - width] == b'#' { break; }
                        y -= width;
                        if world.terminal(y) { break; }
                    }
                }
                world.moves[x][direction] = y;
            }
        }
        world
    }

    pub fn terminal(&self, cell: usize) -> bool {
        b"GP".contains(&self.cells[cell])
    }

    pub fn ending(&self, cell: usize) -> &'static str {
        match self.cells[cell] { b'G' => "goal", b'P' => "pit", _ => "timeout" }
    }

    pub fn slip(&self, cell: usize) -> i64 {
        if self.cells[cell] == b'~' { self.ice_slip } else { self.floor_slip }
    }

    pub fn transitions(&self, cell: usize, action: usize) -> Vec<(usize, i64)> {
        let p = self.slip(cell);
        [(action, self.q - 2 * p), ((action + 1) % 4, p), ((action + 3) % 4, p)]
            .into_iter().filter(|&(_, weight)| weight > 0).map(|(d, weight)| (self.moves[cell][d], weight)).collect()
    }

    pub fn step(&self, random: &mut Random, cell: usize, action: usize) -> (usize, i64) {
        let t = random.next() % self.q;
        let p = self.slip(cell);
        let direction = if t < self.q - 2 * p { action } else if t < self.q - p { (action + 1) % 4 } else { (action + 3) % 4 };
        let next = self.moves[cell][direction];
        (next, self.rewards[next])
    }
}

pub struct Random(pub i64);

impl Random {
    pub fn next(&mut self) -> i64 {
        self.0 = self.0 * 48271 % 2147483647;
        self.0
    }
}
