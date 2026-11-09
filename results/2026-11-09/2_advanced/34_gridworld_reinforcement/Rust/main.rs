mod dynamic_programming;
mod environment;
mod monte_carlo;
mod report;
mod td_learning;

use dynamic_programming::{action_values, bellman, evaluate, first_max, greedy, in_place, policy_iteration, value_iteration};
use environment::{Random, World};
use report::{average, cell, cells, fixed, grid};
use std::collections::{BTreeMap, BTreeSet, VecDeque};
use std::fs;

const METHODS: [&str; 5] = ["mc", "sarsa", "q_learning", "expected_sarsa", "dyna_q"];
const POLICIES: [&str; 7] = ["value_iteration", "policy_iteration", "mc", "sarsa", "q_learning", "expected_sarsa", "dyna_q"];
const ENDINGS: [&str; 3] = ["goal", "pit", "timeout"];

struct Settings {
    fields: BTreeMap<String, Vec<i64>>,
}

impl Settings {
    fn read() -> Self {
        let text = fs::read_to_string("input/params.txt").unwrap();
        let fields = text.lines().map(|line| {
            let mut parts = line.split_whitespace();
            (parts.next().unwrap().into(), parts.map(|part| part.parse().unwrap()).collect())
        }).collect();
        Self { fields }
    }

    fn number(&self, key: &str) -> i64 { self.fields[key][0] }

    fn schedule(&self, key: &str, episode: i64) -> i64 {
        self.fields[key].chunks(2).filter(|pair| pair[0] <= episode).last().unwrap()[1]
    }

    fn phases(&self) -> Vec<(usize, usize)> {
        let starts: BTreeSet<_> = ["ALPHA", "EPSILON"].iter().flat_map(|key| self.fields[*key].chunks(2).map(|pair| pair[0] as usize)).collect();
        let starts: Vec<_> = starts.into_iter().collect();
        starts.iter().enumerate().map(|(i, &start)| (start, starts.get(i + 1).map_or(self.number("EPISODES") as usize, |next| next - 1))).collect()
    }
}

struct Episode {
    total: i64,
    steps: usize,
    ending: &'static str,
    path: Vec<usize>,
}

struct Learner {
    q: Vec<[i64; 4]>,
    visits: Vec<[i64; 4]>,
    episodes: Vec<Episode>,
    blocks: Vec<(usize, i64, usize)>,
}

fn agree(world: &World, a: &[usize], b: &[usize]) -> usize {
    world.states.iter().filter(|&&x| a[x] == b[x]).count()
}

fn maximum(q: &[i64; 4]) -> i64 { q[first_max(q)] }

fn visit_total(visits: &[[i64; 4]], x: usize) -> i64 { visits[x].iter().sum() }

fn errors(world: &World, q: &[[i64; 4]], values: &[i64]) -> Vec<i64> {
    let mut result = vec![0; world.cells.len()];
    for &x in &world.states { result[x] = (maximum(&q[x]) - values[x]).abs(); }
    result
}

fn worst(world: &World, values: &[i64]) -> usize {
    let mut index = world.states[0];
    for &x in &world.states { if values[x] > values[index] { index = x; } }
    index
}

fn learn(world: &World, settings: &Settings, method: &str, optimal: &[i64], policy: &[usize]) -> Learner {
    let size = world.cells.len();
    let mut learner = Learner { q: vec![[0; 4]; size], visits: vec![[0; 4]; size], episodes: Vec::new(), blocks: Vec::new() };
    let mut random = Random(settings.number("SEED"));
    let mut model = td_learning::DynaModel::new(size);
    let mut averages = monte_carlo::Averages::new(size);
    let gamma = settings.number("GAMMA");
    for number in 1..=settings.number("EPISODES") {
        let alpha = settings.schedule("ALPHA", number);
        let epsilon = settings.schedule("EPSILON", number);
        let mut episode = Episode { total: 0, steps: 0, ending: "timeout", path: vec![world.start] };
        let mut history = Vec::new();
        let mut x = world.start;
        let mut action = if method == "sarsa" { td_learning::choose(&mut random, &learner.q[x], epsilon) } else { 0 };
        for _ in 0..settings.number("STEP_LIMIT") {
            if method != "sarsa" { action = td_learning::choose(&mut random, &learner.q[x], epsilon); }
            let (next, reward) = world.step(&mut random, x, action);
            learner.visits[x][action] += 1;
            episode.total += reward;
            episode.steps += 1;
            episode.path.push(next);
            let terminal = world.terminal(next);
            let mut next_action = action;
            if method == "mc" {
                history.push((x, action, reward));
            } else {
                let future = if terminal { 0 } else if method == "sarsa" {
                    next_action = td_learning::choose(&mut random, &learner.q[next], epsilon);
                    learner.q[next][next_action]
                } else if method == "expected_sarsa" { td_learning::expected(&learner.q[next], epsilon) }
                else { maximum(&learner.q[next]) };
                let target = td_learning::target(reward, terminal, future, gamma);
                td_learning::update(&mut learner.q[x], action, target, alpha);
                if method == "dyna_q" {
                    model.record(x, action, reward, next);
                    model.plan(world, &mut random, &mut learner.q, gamma, alpha, settings.number("PLANNING_STEPS"));
                }
            }
            if terminal {
                episode.ending = world.ending(next);
                break;
            }
            x = next;
            action = next_action;
        }
        if method == "mc" { averages.update(&mut learner.q, &history, gamma); }
        learner.episodes.push(episode);
        if number % settings.number("BLOCK_SIZE") == 0 {
            let error = errors(world, &learner.q, optimal);
            let error = world.states.iter().map(|&x| error[x]).sum::<i64>().div_euclid(world.states.len() as i64);
            let coverage = world.states.iter().filter(|&&x| visit_total(&learner.visits, x) > 0).count();
            learner.blocks.push((agree(world, &greedy(&learner.q), policy), error, coverage));
        }
    }
    learner
}

fn nominal_path(world: &World, policy: &[usize], origin: usize, limit: usize) -> (Vec<usize>, &'static str) {
    let mut path = vec![origin];
    loop {
        let next = world.moves[*path.last().unwrap()][policy[*path.last().unwrap()]];
        let repeated = path.contains(&next);
        path.push(next);
        if world.terminal(next) { return (path, world.ending(next)); }
        if repeated { return (path, "loop"); }
        if path.len() - 1 >= limit { return (path, "limit"); }
    }
}

fn distances(world: &World) -> Vec<Option<usize>> {
    let mut distances = vec![None; world.cells.len()];
    distances[world.start] = Some(0);
    let mut queue = VecDeque::from([world.start]);
    while let Some(x) = queue.pop_front() {
        if world.terminal(x) { continue; }
        for action in 0..4 {
            for (next, _) in world.transitions(x, action) {
                if distances[next].is_none() {
                    distances[next] = Some(distances[x].unwrap() + 1);
                    queue.push_back(next);
                }
            }
        }
    }
    distances
}

fn absorption(world: &World, policy: &[usize], limit: i64) -> [i64; 4] {
    let mut values = vec![[0; 3]; world.cells.len()];
    for _ in 0..limit {
        let mut next_values = values.clone();
        for &x in &world.states {
            let mut sums = [0; 3];
            for (next, weight) in world.transitions(x, policy[x]) {
                let target = match world.cells[next] { b'G' => [100000000, 0, 0], b'P' => [0, 100000000, 0], _ => values[next] };
                for i in 0..3 { sums[i] += weight * target[i]; }
            }
            next_values[x] = [sums[0] / world.q, sums[1] / world.q, 100000000 + sums[2] / world.q];
        }
        values = next_values;
    }
    let [goal, pit, steps] = values[world.start];
    [goal / 10000, pit / 10000, (100000000 - goal - pit) / 10000, steps / 10000]
}

fn behaviour(world: &World, settings: &Settings, policy: &[usize]) -> (i64, i64) {
    let epsilon = settings.schedule("EPSILON", settings.number("EPISODES"));
    let mut values = vec![0; world.cells.len()];
    let mut sweeps = 0;
    loop {
        let mut delta = 0;
        for &x in &world.states {
            let sum: i64 = (0..4).map(|action| {
                let weight = epsilon + if action == policy[x] { 4 * (1000 - epsilon) } else { 0 };
                weight * bellman(world, &values, x, action, settings.number("GAMMA"))
            }).sum();
            let value = sum.div_euclid(4000);
            delta = delta.max((value - values[x]).abs());
            values[x] = value;
        }
        sweeps += 1;
        if delta <= settings.number("THETA") { return (values[world.start], sweeps); }
    }
}

struct Rollouts {
    returns: Vec<i64>,
    discounted: i64,
    steps: i64,
    endings: [usize; 3],
    terminals: Vec<usize>,
}

fn rollouts(world: &World, settings: &Settings, policy: &[usize]) -> Rollouts {
    let mut result = Rollouts { returns: Vec::new(), discounted: 0, steps: 0, endings: [0; 3], terminals: vec![0; world.terminals.len()] };
    let mut random = Random(settings.number("ROLLOUT_SEED"));
    for _ in 0..settings.number("ROLLOUTS") {
        let mut x = world.start;
        let mut rewards = Vec::new();
        for _ in 0..settings.number("STEP_LIMIT") {
            let (next, reward) = world.step(&mut random, x, policy[x]);
            rewards.push(reward);
            x = next;
            if world.terminal(x) { break; }
        }
        result.returns.push(rewards.iter().sum());
        result.discounted += monte_carlo::discounted(&rewards, settings.number("GAMMA"));
        result.steps += rewards.len() as i64;
        let ending = ENDINGS.iter().position(|&e| e == world.ending(x)).unwrap();
        result.endings[ending] += 1;
        if let Some(index) = world.terminals.iter().position(|&t| t == x) { result.terminals[index] += 1; }
    }
    result
}

fn ending_counts(episodes: &[Episode]) -> [usize; 3] {
    std::array::from_fn(|i| episodes.iter().filter(|episode| episode.ending == ENDINGS[i]).count())
}

fn append_part(lines: &mut Vec<String>, part: Vec<String>) {
    if !lines.is_empty() { lines.push(String::new()); }
    lines.extend(part);
}

fn values_report(world: &World, settings: &Settings, optimal: &[i64], q_star: &[[i64; 4]], policy: &[usize], changes: &[i64], pi_values: &[i64], pi_policy: &[usize], rounds: &[(i64, usize, i64)]) -> Vec<String> {
    let distance = distances(world);
    let count = |symbol| world.cells.iter().filter(|&&c| c == symbol).count();
    let mut lines = vec![format!("world rows {} cols {} states {} walls {} floor {} ice {} goals {} pits {}", world.height, world.width, world.states.len(), count(b'#'), count(b'.') + count(b'S'), count(b'~'), count(b'G'), count(b'P')),
        format!("start {} reachable {}", cell(world, world.start), world.states.iter().filter(|&&x| distance[x].is_some()).count())];
    for &x in &world.terminals {
        lines.push(format!("terminal {} {} reward {} distance {}", cell(world, x), world.ending(x), world.rewards[x], distance[x].map_or_else(|| "-".into(), |v| v.to_string())));
    }
    let mut part = vec![format!("value_iteration gamma {} theta {} iterations {}", settings.number("GAMMA"), fixed(settings.number("THETA")), changes.len())];
    part.extend(changes.iter().enumerate().map(|(i, &delta)| format!("iteration {} max_change {}", i + 1, fixed(delta))));
    append_part(&mut lines, part);
    let mut part = vec!["optimal_values".into()];
    part.extend(grid(world, true, |x| fixed(optimal[x])));
    append_part(&mut lines, part);
    let tied: Vec<_> = world.states.iter().copied().filter(|&x| q_star[x].iter().filter(|&&v| v == maximum(&q_star[x])).count() > 1).collect();
    let mut part = vec!["optimal_action_counts".into()];
    part.extend(grid(world, false, |x| q_star[x].iter().filter(|&&v| v == maximum(&q_star[x])).count().to_string()));
    append_part(&mut lines, part);
    let mut part = vec![format!("ties {}", tied.len())];
    for x in tied {
        let actions: String = (0..4).filter(|&a| q_star[x][a] == maximum(&q_star[x])).map(|a| b"NESW"[a] as char).collect();
        part.push(format!("tie {} {}", cell(world, x), actions));
    }
    let mut symmetry = [0; 3];
    for &x in &world.states {
        let column = x % world.width;
        let mirror = x / world.width * world.width + world.width - 1 - column;
        if column < world.width - 1 - column && b".S~".contains(&world.cells[mirror]) {
            symmetry[0] += 1;
            symmetry[1] += usize::from(optimal[x] == optimal[mirror]);
            symmetry[2] += usize::from(policy[mirror] == [0, 3, 2, 1][policy[x]]);
        }
    }
    part.push(format!("symmetry pairs {} equal_values {} mirrored_actions {}", symmetry[0], symmetry[1], symmetry[2]));
    append_part(&mut lines, part);
    let mut part = vec![format!("policy_iteration rounds {}", rounds.len())];
    part.extend(rounds.iter().enumerate().map(|(i, &(sweeps, changed, value))| format!("round {} sweeps {} changed {} value_start {}", i + 1, sweeps, changed, fixed(value))));
    append_part(&mut lines, part);
    let mut part = vec!["policy_iteration_values".into()];
    part.extend(grid(world, true, |x| fixed(pi_values[x])));
    append_part(&mut lines, part);
    let difference: Vec<_> = pi_values.iter().zip(optimal).map(|(&a, &b)| (a - b).abs()).collect();
    let worst = worst(world, &difference);
    let inplace = in_place(world, settings.number("GAMMA"), settings.number("THETA"));
    let n = world.states.len() as i64;
    append_part(&mut lines, vec![format!("comparison policy_differences {} max_value_difference {} at {}", world.states.len() - agree(world, policy, pi_policy), fixed(difference[worst]), cell(world, worst)),
        format!("backups value_iteration {} in_place_iterations {} in_place {} policy_iteration {}", changes.len() as i64 * n * 4, inplace, inplace * n * 4, rounds.iter().map(|r| r.0).sum::<i64>() * n + rounds.len() as i64 * n * 4)]);
    let mut gamma_part = vec!["gamma_sweep".into()];
    for &gamma in &settings.fields["GAMMA_SWEEP"] {
        gamma_part.push(sensitivity(world, settings, policy, gamma, format!("gamma {gamma}")));
    }
    append_part(&mut lines, gamma_part);
    let mut slip_part = vec!["slip_sweep".into()];
    for pair in settings.fields["SLIP_SWEEP"].chunks(2) {
        let mut changed = world.clone();
        changed.floor_slip = pair[0];
        changed.ice_slip = pair[1];
        slip_part.push(sensitivity(&changed, settings, policy, settings.number("GAMMA"), format!("slip {} {}", pair[0], pair[1])));
    }
    append_part(&mut lines, slip_part);
    lines
}

fn sensitivity(world: &World, settings: &Settings, optimal_policy: &[usize], gamma: i64, prefix: String) -> String {
    let (values, changes) = value_iteration(world, gamma, settings.number("THETA"));
    let policy = greedy(&action_values(world, &values, gamma));
    let (path, ending) = nominal_path(world, &policy, world.start, settings.number("STEP_LIMIT") as usize);
    format!("{} iterations {} value_start {} path {} steps {} last {} differences {}", prefix, changes.len(), fixed(values[world.start]), ending, path.len() - 1, cell(world, *path.last().unwrap()), world.states.len() - agree(world, &policy, optimal_policy))
}

fn policies_report(world: &World, settings: &Settings, policies: &[Vec<usize>], learners: &[Learner]) -> Vec<String> {
    let mut lines = Vec::new();
    for (i, policy) in policies.iter().enumerate() {
        let mut part = vec![POLICIES[i].into()];
        part.extend(grid(world, false, |x| (b"^>v<"[policy[x]] as char).to_string()));
        let (path, ending) = nominal_path(world, policy, world.start, settings.number("STEP_LIMIT") as usize);
        part.push(format!("path {} steps {} {}", ending, path.len() - 1, cells(world, &path)));
        let counts: [usize; 4] = std::array::from_fn(|a| world.states.iter().filter(|&&x| policy[x] == a).count());
        let risk = world.states.iter().filter(|&&x| world.transitions(x, policy[x]).iter().any(|&(next, _)| world.cells[next] == b'P')).count();
        part.push(format!("actions N {} E {} S {} W {} risk {}", counts[0], counts[1], counts[2], counts[3], risk));
        part.push("basins".into());
        part.extend(grid(world, false, |x| {
            let (path, _) = nominal_path(world, policy, x, settings.number("STEP_LIMIT") as usize);
            let last = *path.last().unwrap();
            world.terminals.iter().position(|&t| t == last).map_or_else(|| "*".into(), |j| ((b'a' + j as u8) as char).to_string())
        }));
        if i >= 2 {
            part.push("visits".into());
            part.extend(grid(world, false, |x| {
                let total = visit_total(&learners[i - 2].visits, x);
                if total == 0 { "0".into() } else { total.to_string().len().to_string() }
            }));
        }
        append_part(&mut lines, part);
    }
    lines
}

fn main() {
    let settings = Settings::read();
    let world = World::read("input/world.txt", settings.number("STEP_REWARD"), &settings.fields["SLIP"]);
    let gamma = settings.number("GAMMA");
    let theta = settings.number("THETA");
    let (optimal, changes) = value_iteration(&world, gamma, theta);
    let q_star = action_values(&world, &optimal, gamma);
    let optimal_policy = greedy(&q_star);
    let (pi_values, pi_policy, rounds) = policy_iteration(&world, gamma, theta);
    let learners: Vec<_> = METHODS.iter().map(|method| learn(&world, &settings, method, &optimal, &optimal_policy)).collect();
    let mut policies = vec![optimal_policy.clone(), pi_policy.clone()];
    policies.extend(learners.iter().map(|learner| greedy(&learner.q)));
    fs::create_dir_all("output").unwrap();
    report::write("values.txt", &values_report(&world, &settings, &optimal, &q_star, &optimal_policy, &changes, &pi_values, &pi_policy, &rounds));
    report::write("policies.txt", &policies_report(&world, &settings, &policies, &learners));
    let mut q_lines = vec!["method,row,col,action,value,visits".into()];
    q_lines.extend(report::q_rows(&world, "value_iteration", &q_star, None));
    for (method, learner) in METHODS.iter().zip(&learners) { q_lines.extend(report::q_rows(&world, method, &learner.q, Some(&learner.visits))); }
    report::write("q_tables.csv", &q_lines);
    let mut curve_lines = vec!["method,block,mean_return,mean_steps,goals,pits,timeouts,agree,value_error,coverage".into()];
    let block_size = settings.number("BLOCK_SIZE") as usize;
    for (method, learner) in METHODS.iter().zip(&learners) {
        for (index, &(agreement, error, coverage)) in learner.blocks.iter().enumerate() {
            let episodes = &learner.episodes[index * block_size..(index + 1) * block_size];
            let endings = ending_counts(episodes);
            curve_lines.push(format!("{},{},{},{},{},{},{},{},{},{}", method, index + 1, average(episodes.iter().map(|e| e.total).sum(), block_size), average(episodes.iter().map(|e| e.steps as i64).sum(), block_size), endings[0], endings[1], endings[2], agreement, fixed(error), coverage));
        }
    }
    report::write("learning_curves.csv", &curve_lines);
    report::write("evaluation.txt", &evaluation_report(&world, &settings, &optimal, &q_star, &policies, &learners));
}

fn evaluation_report(world: &World, settings: &Settings, optimal: &[i64], q_star: &[[i64; 4]], policies: &[Vec<usize>], learners: &[Learner]) -> Vec<String> {
    let count = world.states.len();
    let gamma = settings.number("GAMMA");
    let theta = settings.number("THETA");
    let zero = vec![0; world.cells.len()];
    let mut lines = vec![format!("summary states {} start {} rollouts {} step_limit {}", count, cell(world, world.start), settings.number("ROLLOUTS"), settings.number("STEP_LIMIT"))];
    let mut part = vec!["policies".into(), "policy agree optimal_actions value_start sweeps max_gap at".into()];
    let mut improved_lines = vec!["improvement".into(), "policy changed value_start agree".into()];
    let mut absorption_lines = vec!["absorption".into(), "policy p_goal p_pit p_timeout expected_steps".into()];
    let mut rollout_results = Vec::new();
    for (name, policy) in POLICIES.iter().zip(policies) {
        let (values, sweeps) = evaluate(world, policy, zero.clone(), gamma, theta);
        let gaps: Vec<_> = optimal.iter().zip(&values).map(|(&a, &b)| a - b).collect();
        let at = worst(world, &gaps);
        let optimal_actions = world.states.iter().filter(|&&x| q_star[x][policy[x]] == maximum(&q_star[x])).count();
        part.push(format!("{} {} {} {} {} {} {}", name, agree(world, policy, &policies[0]), optimal_actions, fixed(values[world.start]), sweeps, fixed(gaps[at]), cell(world, at)));
        let improved = greedy(&action_values(world, &values, gamma));
        let (improved_values, _) = evaluate(world, &improved, zero.clone(), gamma, theta);
        improved_lines.push(format!("{} {} {} {}", name, count - agree(world, policy, &improved), fixed(improved_values[world.start]), agree(world, &improved, &policies[0])));
        let absorption = absorption(world, policy, settings.number("STEP_LIMIT"));
        absorption_lines.push(format!("{} {}", name, absorption.iter().map(|&v| fixed(v)).collect::<Vec<_>>().join(" ")));
        rollout_results.push(rollouts(world, settings, policy));
    }
    append_part(&mut lines, part);
    append_part(&mut lines, improved_lines);
    append_part(&mut lines, absorption_lines);
    let epsilon = settings.schedule("EPSILON", settings.number("EPISODES"));
    let mut part = vec!["behaviour".into(), "method epsilon value_start sweeps".into()];
    for (i, method) in METHODS.iter().enumerate() {
        let (value, sweeps) = behaviour(world, settings, &policies[i + 2]);
        part.push(format!("{method} {epsilon} {} {sweeps}", fixed(value)));
    }
    append_part(&mut lines, part);
    let mut part = vec!["q_errors".into(), "method mean_abs max_abs at unvisited tied".into()];
    let mut action_errors = vec!["q_action_errors".into(), "method N E S W".into()];
    for (method, learner) in METHODS.iter().zip(learners) {
        let error = errors(world, &learner.q, optimal);
        let at = worst(world, &error);
        let mean = world.states.iter().map(|&x| error[x]).sum::<i64>().div_euclid(count as i64);
        let unvisited = world.states.iter().filter(|&&x| visit_total(&learner.visits, x) == 0).count();
        let tied = world.states.iter().filter(|&&x| learner.q[x].iter().filter(|&&v| v == maximum(&learner.q[x])).count() >= 2).count();
        part.push(format!("{} {} {} {} {} {}", method, fixed(mean), fixed(error[at]), cell(world, at), unvisited, tied));
        let mut action_line = method.to_string();
        for action in 0..4 {
            let visited: Vec<_> = world.states.iter().copied().filter(|&x| learner.visits[x][action] > 0).collect();
            let error = if visited.is_empty() { "-".into() } else {
                fixed(visited.iter().map(|&x| (learner.q[x][action] - q_star[x][action]).abs()).sum::<i64>().div_euclid(visited.len() as i64))
            };
            action_line.push_str(&format!(" {error}"));
        }
        action_errors.push(action_line);
    }
    append_part(&mut lines, part);
    append_part(&mut lines, action_errors);
    let mut part = vec!["rollouts".into(), "policy mean_return mean_discounted mean_steps goals pits timeouts min median max".into()];
    let mut terminal_lines = vec!["terminals".into(), format!("policy {}", cells(world, &world.terminals))];
    for (name, result) in POLICIES.iter().zip(&rollout_results) {
        let mut sorted = result.returns.clone();
        sorted.sort();
        part.push(format!("{} {} {} {} {} {} {} {} {} {}", name, average(result.returns.iter().sum(), sorted.len()), fixed(result.discounted.div_euclid(sorted.len() as i64)), average(result.steps, sorted.len()), result.endings[0], result.endings[1], result.endings[2], sorted[0], sorted[(sorted.len() - 1) / 2], sorted.last().unwrap()));
        terminal_lines.push(format!("{} {}", name, result.terminals.iter().map(usize::to_string).collect::<Vec<_>>().join(" ")));
    }
    append_part(&mut lines, part);
    append_part(&mut lines, terminal_lines);
    let mut part = vec!["agreement".into(), format!("policy {}", POLICIES.join(" "))];
    for (name, policy) in POLICIES.iter().zip(policies) {
        part.push(format!("{} {}", name, policies.iter().map(|other| agree(world, policy, other).to_string()).collect::<Vec<_>>().join(" ")));
    }
    append_part(&mut lines, part);
    let mut training_lines = vec!["training".into(), "method steps goals pits timeouts best_block best_mean last_mean reach".into()];
    let mut visited_lines = vec!["visited".into()];
    let mut last_lines = vec!["last_episodes".into()];
    let mut phase_lines = vec!["phases".into()];
    let block_size = settings.number("BLOCK_SIZE") as usize;
    let vi_return: i64 = rollout_results[0].returns.iter().sum();
    for (method, learner) in METHODS.iter().zip(learners) {
        let blocks: Vec<i64> = learner.episodes.chunks(block_size).map(|episodes| episodes.iter().map(|e| e.total).sum()).collect();
        let mut best = 0;
        for i in 1..blocks.len() { if blocks[i] > blocks[best] { best = i; } }
        let reach = blocks.iter().position(|&total| 10 * settings.number("ROLLOUTS") * total >= 9 * block_size as i64 * vi_return).map_or_else(|| "-".into(), |i| (i + 1).to_string());
        let endings = ending_counts(&learner.episodes);
        training_lines.push(format!("{} {} {} {} {} {} {} {} {}", method, learner.episodes.iter().map(|e| e.steps).sum::<usize>(), endings[0], endings[1], endings[2], best + 1, average(blocks[best], block_size), average(*blocks.last().unwrap(), block_size), reach));
        let mut visited = world.states.clone();
        visited.sort_by_key(|&x| (-visit_total(&learner.visits, x), x));
        visited_lines.push(format!("{} {}", method, visited[..3].iter().map(|&x| format!("{}:{}", cell(world, x), visit_total(&learner.visits, x))).collect::<Vec<_>>().join(" ")));
        let last = learner.episodes.last().unwrap();
        last_lines.push(format!("{} return {} steps {} end {} {}", method, last.total, last.steps, last.ending, cells(world, &last.path)));
        for (start, end) in settings.phases() {
            let episodes = &learner.episodes[start - 1..end];
            phase_lines.push(format!("{} {}-{} alpha {} epsilon {} mean_return {} mean_steps {} goals {}", method, start, end, settings.schedule("ALPHA", start as i64), settings.schedule("EPSILON", start as i64), average(episodes.iter().map(|e| e.total).sum(), episodes.len()), average(episodes.iter().map(|e| e.steps as i64).sum(), episodes.len()), ending_counts(episodes)[0]));
        }
    }
    append_part(&mut lines, training_lines);
    append_part(&mut lines, visited_lines);
    append_part(&mut lines, last_lines);
    append_part(&mut lines, phase_lines);
    lines
}
