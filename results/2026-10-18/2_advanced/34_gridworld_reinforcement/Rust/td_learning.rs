use crate::dynamic_programming::first_max;
use crate::environment::{Random, World};

pub fn choose(random: &mut Random, q: &[i64; 4], epsilon: i64) -> usize {
    if random.next() % 1000 < epsilon { (random.next() % 4) as usize } else { first_max(q) }
}

pub fn target(reward: i64, terminal: bool, future: i64, gamma: i64) -> i64 {
    10000 * reward + if terminal { 0 } else { (gamma * future).div_euclid(100) }
}

pub fn expected(q: &[i64; 4], epsilon: i64) -> i64 {
    (epsilon * q.iter().sum::<i64>() + 4 * (1000 - epsilon) * q[first_max(q)]).div_euclid(4000)
}

pub fn update(q: &mut [i64; 4], action: usize, target: i64, alpha: i64) {
    q[action] += (alpha * (target - q[action])).div_euclid(100);
}

pub struct DynaModel {
    model: Vec<Option<(i64, usize)>>,
    observed: Vec<(usize, usize)>,
}

impl DynaModel {
    pub fn new(size: usize) -> Self {
        Self { model: vec![None; size * 4], observed: Vec::new() }
    }

    pub fn record(&mut self, cell: usize, action: usize, reward: i64, next: usize) {
        if self.model[cell * 4 + action].is_none() { self.observed.push((cell, action)); }
        self.model[cell * 4 + action] = Some((reward, next));
    }

    pub fn plan(&self, world: &World, random: &mut Random, q: &mut [[i64; 4]], gamma: i64, alpha: i64, steps: i64) {
        for _ in 0..steps {
            let (cell, action) = self.observed[(random.next() as usize) % self.observed.len()];
            let (reward, next) = self.model[cell * 4 + action].unwrap();
            let future = q[next][first_max(&q[next])];
            let value = target(reward, world.terminal(next), future, gamma);
            update(&mut q[cell], action, value, alpha);
        }
    }
}
