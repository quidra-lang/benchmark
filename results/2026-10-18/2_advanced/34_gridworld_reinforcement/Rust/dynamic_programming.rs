use crate::environment::World;

pub fn first_max(values: &[i64; 4]) -> usize {
    let mut best = 0;
    for action in 1..4 { if values[action] > values[best] { best = action; } }
    best
}

pub fn bellman(world: &World, values: &[i64], cell: usize, action: usize, gamma: i64) -> i64 {
    world.transitions(cell, action).iter().map(|&(next, weight)| {
        let future = if world.terminal(next) { 0 } else { (gamma * values[next]).div_euclid(100) };
        weight * (10000 * world.rewards[next] + future)
    }).sum::<i64>().div_euclid(world.q)
}

pub fn action_values(world: &World, values: &[i64], gamma: i64) -> Vec<[i64; 4]> {
    let mut q = vec![[0; 4]; world.cells.len()];
    for &cell in &world.states {
        q[cell] = std::array::from_fn(|action| bellman(world, values, cell, action, gamma));
    }
    q
}

pub fn greedy(q: &[[i64; 4]]) -> Vec<usize> {
    q.iter().map(first_max).collect()
}

pub fn value_iteration(world: &World, gamma: i64, theta: i64) -> (Vec<i64>, Vec<i64>) {
    let mut values = vec![0; world.cells.len()];
    let mut changes = Vec::new();
    loop {
        let q = action_values(world, &values, gamma);
        let mut next = values.clone();
        let mut delta = 0;
        for &cell in &world.states {
            next[cell] = q[cell][first_max(&q[cell])];
            delta = delta.max((next[cell] - values[cell]).abs());
        }
        values = next;
        changes.push(delta);
        if delta <= theta { return (values, changes); }
    }
}

pub fn evaluate(world: &World, policy: &[usize], mut values: Vec<i64>, gamma: i64, theta: i64) -> (Vec<i64>, i64) {
    let mut sweeps = 0;
    loop {
        let mut delta = 0;
        for &cell in &world.states {
            let value = bellman(world, &values, cell, policy[cell], gamma);
            delta = delta.max((value - values[cell]).abs());
            values[cell] = value;
        }
        sweeps += 1;
        if delta <= theta { return (values, sweeps); }
    }
}

pub fn in_place(world: &World, gamma: i64, theta: i64) -> i64 {
    let mut values = vec![0; world.cells.len()];
    let mut sweeps = 0;
    loop {
        let mut delta = 0;
        for &cell in &world.states {
            let value = (0..4).map(|action| bellman(world, &values, cell, action, gamma)).max().unwrap();
            delta = delta.max((value - values[cell]).abs());
            values[cell] = value;
        }
        sweeps += 1;
        if delta <= theta { return sweeps; }
    }
}

pub fn policy_iteration(world: &World, gamma: i64, theta: i64) -> (Vec<i64>, Vec<usize>, Vec<(i64, usize, i64)>) {
    let mut values = vec![0; world.cells.len()];
    let mut policy = vec![0; world.cells.len()];
    let mut rounds = Vec::new();
    loop {
        let (new_values, sweeps) = evaluate(world, &policy, values, gamma, theta);
        values = new_values;
        let next = greedy(&action_values(world, &values, gamma));
        let changed = world.states.iter().filter(|&&x| next[x] != policy[x]).count();
        rounds.push((sweeps, changed, values[world.start]));
        policy = next;
        if changed == 0 { return (values, policy, rounds); }
    }
}
