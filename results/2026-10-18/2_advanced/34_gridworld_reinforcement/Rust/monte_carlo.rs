pub struct Averages {
    sums: Vec<[i64; 4]>,
    counts: Vec<[i64; 4]>,
}

impl Averages {
    pub fn new(size: usize) -> Self {
        Self { sums: vec![[0; 4]; size], counts: vec![[0; 4]; size] }
    }

    pub fn update(&mut self, q: &mut [[i64; 4]], history: &[(usize, usize, i64)], gamma: i64) {
        let mut first = vec![None; q.len() * 4];
        for (i, &(cell, action, _)) in history.iter().enumerate() {
            first[cell * 4 + action].get_or_insert(i);
        }
        let mut value = 0;
        for (i, &(cell, action, reward)) in history.iter().enumerate().rev() {
            value = 10000 * reward + (gamma * value).div_euclid(100);
            if first[cell * 4 + action] == Some(i) {
                self.sums[cell][action] += value;
                self.counts[cell][action] += 1;
                q[cell][action] = self.sums[cell][action].div_euclid(self.counts[cell][action]);
            }
        }
    }
}

pub fn discounted(rewards: &[i64], gamma: i64) -> i64 {
    rewards.iter().rev().fold(0, |value, &reward| 10000 * reward + (gamma * value).div_euclid(100))
}
