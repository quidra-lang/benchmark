use std::cmp::Ordering;
use std::collections::{HashMap, VecDeque};
use std::fmt;
use std::io::{self, Read, Write};
use std::iter::Sum;
use std::ops::{Add, Div, Mul, Sub};

#[derive(Clone, Copy, PartialEq, Eq)]
struct Fraction {
    numerator: i64,
    denominator: i64,
}

fn gcd(mut a: i64, mut b: i64) -> i64 {
    a = a.abs();
    b = b.abs();
    while b != 0 {
        (a, b) = (b, a % b);
    }
    a
}

impl Fraction {
    const ZERO: Self = Self { numerator: 0, denominator: 1 };
    const ONE: Self = Self { numerator: 1, denominator: 1 };

    fn new(mut numerator: i64, mut denominator: i64) -> Self {
        if denominator < 0 {
            numerator = -numerator;
            denominator = -denominator;
        }
        let divisor = gcd(numerator, denominator);
        Self { numerator: numerator / divisor, denominator: denominator / divisor }
    }

    fn integer(value: i64) -> Self {
        Self { numerator: value, denominator: 1 }
    }

    fn abs(self) -> Self {
        Self { numerator: self.numerator.abs(), ..self }
    }

    fn value(self) -> String {
        let whole = self.numerator / self.denominator;
        let decimal = self.numerator % self.denominator * 1_000_000 / self.denominator;
        format!("{self}({whole}.{decimal:06})")
    }
}

impl Add for Fraction {
    type Output = Self;
    fn add(self, other: Self) -> Self {
        Self::new(self.numerator * other.denominator + other.numerator * self.denominator,
                  self.denominator * other.denominator)
    }
}

impl Sub for Fraction {
    type Output = Self;
    fn sub(self, other: Self) -> Self {
        Self::new(self.numerator * other.denominator - other.numerator * self.denominator,
                  self.denominator * other.denominator)
    }
}

impl Mul for Fraction {
    type Output = Self;
    fn mul(self, other: Self) -> Self {
        Self::new(self.numerator * other.numerator, self.denominator * other.denominator)
    }
}

impl Div for Fraction {
    type Output = Self;
    fn div(self, other: Self) -> Self {
        Self::new(self.numerator * other.denominator, self.denominator * other.numerator)
    }
}

impl Ord for Fraction {
    fn cmp(&self, other: &Self) -> Ordering {
        (self.numerator * other.denominator).cmp(&(other.numerator * self.denominator))
    }
}

impl PartialOrd for Fraction {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl Sum for Fraction {
    fn sum<I: Iterator<Item = Self>>(values: I) -> Self {
        values.fold(Self::ZERO, |total, value| total + value)
    }
}

impl fmt::Display for Fraction {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(formatter, "{}/{}", self.numerator, self.denominator)
    }
}

const ZERO: Fraction = Fraction::ZERO;
const ONE: Fraction = Fraction::ONE;
type Matrix = Vec<Vec<Fraction>>;

fn probability(text: &str) -> Result<Fraction, String> {
    let mut parts = text.split('/');
    let numerator: i64 = parts.next().unwrap().parse().unwrap();
    let denominator: i64 = parts.next().unwrap_or("1").parse().unwrap();
    if denominator == 0 || numerator > denominator {
        return Err("BAD PROBABILITY".into());
    }
    Ok(Fraction::new(numerator, denominator))
}

fn number(text: &str) -> usize {
    text.parse().unwrap()
}

fn matrix(rows: usize, columns: usize) -> Matrix {
    vec![vec![ZERO; columns]; rows]
}

fn identity(size: usize) -> Matrix {
    let mut result = matrix(size, size);
    for (i, row) in result.iter_mut().enumerate() {
        row[i] = ONE;
    }
    result
}

fn matrix_product(left: &Matrix, right: &Matrix) -> Matrix {
    let mut result = matrix(left.len(), right[0].len());
    for (i, row) in result.iter_mut().enumerate() {
        for (j, value) in row.iter_mut().enumerate() {
            *value = (0..right.len()).map(|k| left[i][k] * right[k][j]).sum();
        }
    }
    result
}

fn eliminate(mut equations: Matrix) -> Matrix {
    let size = equations.len();
    for column in 0..size {
        let pivot_row = (column..size).find(|&row| equations[row][column] != ZERO).unwrap();
        equations.swap(column, pivot_row);
        let pivot = equations[column][column];
        for value in &mut equations[column] {
            *value = *value / pivot;
        }
        let normalized = equations[column].clone();
        for (row_number, row) in equations.iter_mut().enumerate() {
            if row_number == column || row[column] == ZERO {
                continue;
            }
            let factor = row[column];
            for (j, value) in row.iter_mut().enumerate() {
                *value = *value - factor * normalized[j];
            }
        }
    }
    equations
}

#[derive(Clone)]
struct Chain {
    states: Vec<String>,
    transition: Matrix,
}

impl Chain {
    fn new(states: Vec<String>) -> Self {
        let transition = matrix(states.len(), states.len());
        Self { states, transition }
    }

    fn state(&self, name: &str) -> Result<usize, String> {
        self.states.iter().position(|state| state == name)
            .ok_or_else(|| format!("UNKNOWN STATE {name}"))
    }

    fn row_sum(&self, row: usize, selected: &[usize]) -> Fraction {
        selected.iter().map(|&j| self.transition[row][j]).sum()
    }

    fn targets(&self, names: &[&str]) -> Result<Vec<usize>, String> {
        let mut selected = vec![false; self.states.len()];
        for &name in names {
            let index = self.state(name)?;
            if selected[index] {
                return Err(format!("DUPLICATE STATE {name}"));
            }
            selected[index] = true;
        }
        Ok((0..selected.len()).filter(|&i| selected[i]).collect())
    }

    fn display(&self, values: &Matrix, label: &str) -> Vec<String> {
        let mut lines = vec![format!("STATES {}", self.states.join(" "))];
        for (i, row) in values.iter().enumerate() {
            let text: Vec<String> = row.iter().map(ToString::to_string).collect();
            lines.push(format!("{label} {} {}", self.states[i], text.join(" ")));
        }
        lines
    }

    fn absorbing(&self) -> Vec<usize> {
        (0..self.states.len()).filter(|&i| self.transition[i][i] == ONE).collect()
    }
}

struct Class {
    states: Vec<usize>,
    closed: bool,
    period: usize,
}

struct Graph {
    reachable: Vec<Vec<bool>>,
    classes: Vec<Class>,
    class_of: Vec<usize>,
    levels: Vec<usize>,
}

impl Graph {
    fn new(chain: &Chain) -> Self {
        let size = chain.states.len();
        let mut reachable = vec![vec![false; size]; size];
        for (i, row) in reachable.iter_mut().enumerate() {
            for (j, value) in row.iter_mut().enumerate() {
                *value = i == j || chain.transition[i][j] > ZERO;
            }
        }
        for k in 0..size {
            for i in 0..size {
                for j in 0..size {
                    if reachable[i][k] && reachable[k][j] {
                        reachable[i][j] = true;
                    }
                }
            }
        }
        let mut classes = Vec::new();
        let mut class_of = vec![usize::MAX; size];
        let mut levels = vec![0; size];
        for root in 0..size {
            if class_of[root] != usize::MAX {
                continue;
            }
            let states: Vec<usize> = (0..size).filter(|&i| reachable[root][i] && reachable[i][root]).collect();
            for &state in &states {
                class_of[state] = classes.len();
            }
            let mut closed = true;
            let mut visited = vec![false; size];
            let mut queue = VecDeque::from([root]);
            visited[root] = true;
            while let Some(current) = queue.pop_front() {
                for next in 0..size {
                    if chain.transition[current][next] == ZERO {
                        continue;
                    }
                    if !states.contains(&next) {
                        closed = false;
                    } else if !visited[next] {
                        visited[next] = true;
                        levels[next] = levels[current] + 1;
                        queue.push_back(next);
                    }
                }
            }
            let mut period = 0;
            for &i in &states {
                for &j in &states {
                    if chain.transition[i][j] > ZERO {
                        period = gcd(period, levels[i] as i64 + 1 - levels[j] as i64);
                    }
                }
            }
            classes.push(Class { states, closed, period: period as usize });
        }
        Self { reachable, classes, class_of, levels }
    }

    fn reaches(&self, source: usize, targets: &[usize]) -> bool {
        targets.iter().any(|&target| self.reachable[source][target])
    }
}

fn stationary(chain: &Chain, states: &[usize]) -> Vec<Fraction> {
    let count = states.len();
    let mut equations = matrix(count, count + 1);
    for i in 0..count - 1 {
        for j in 0..count {
            equations[i][j] = chain.transition[states[j]][states[i]] - if i == j { ONE } else { ZERO };
        }
    }
    equations[count - 1].fill(ONE);
    let solved = eliminate(equations);
    let mut distribution = vec![ZERO; chain.states.len()];
    for (i, &state) in states.iter().enumerate() {
        distribution[state] = solved[i][count];
    }
    distribution
}

struct Hitting {
    probabilities: Vec<Fraction>,
    times: Vec<Option<Fraction>>,
}

fn hitting(chain: &Chain, graph: &Graph, targets: &[usize], with_times: bool) -> Hitting {
    let size = chain.states.len();
    let mut probabilities = vec![ZERO; size];
    let mut times = vec![None; size];
    for &i in targets {
        probabilities[i] = ONE;
        times[i] = Some(ZERO);
    }
    let unknown: Vec<usize> = (0..size).filter(|i| !targets.contains(i) && graph.reaches(*i, targets)).collect();
    if !unknown.is_empty() {
        let count = unknown.len();
        let mut equations = matrix(count, count + 1);
        for i in 0..count {
            for j in 0..count {
                equations[i][j] = (if i == j { ONE } else { ZERO }) - chain.transition[unknown[i]][unknown[j]];
            }
            equations[i][count] = chain.row_sum(unknown[i], targets);
        }
        let solved = eliminate(equations);
        for (i, &state) in unknown.iter().enumerate() {
            probabilities[state] = solved[i][count];
        }
    }
    if with_times {
        let certain: Vec<usize> = unknown.into_iter().filter(|&i| probabilities[i] == ONE).collect();
        if !certain.is_empty() {
            let count = certain.len();
            let mut equations = matrix(count, count + 1);
            for i in 0..count {
                for j in 0..count {
                    equations[i][j] = (if i == j { ONE } else { ZERO }) - chain.transition[certain[i]][certain[j]];
                }
                equations[i][count] = ONE;
            }
            let solved = eliminate(equations);
            for (i, &state) in certain.iter().enumerate() {
                times[state] = Some(solved[i][count]);
            }
        }
    }
    Hitting { probabilities, times }
}

struct Absorption {
    transient: Vec<usize>,
    absorbing: Vec<usize>,
    fundamental: Matrix,
    means: Vec<Fraction>,
    variances: Vec<Fraction>,
    probabilities: Matrix,
}

fn absorption(chain: &Chain) -> Absorption {
    let absorbing = chain.absorbing();
    let transient: Vec<usize> = (0..chain.states.len()).filter(|i| !absorbing.contains(i)).collect();
    let count = transient.len();
    let mut equations = matrix(count, 2 * count);
    for i in 0..count {
        for j in 0..count {
            equations[i][j] = (if i == j { ONE } else { ZERO }) - chain.transition[transient[i]][transient[j]];
        }
        equations[i][count + i] = ONE;
    }
    let solved = eliminate(equations);
    let fundamental: Matrix = solved.iter().map(|row| row[count..].to_vec()).collect();
    let means: Vec<Fraction> = fundamental.iter().map(|row| row.iter().copied().sum()).collect();
    let mut variances = vec![ZERO; count];
    let mut probabilities = matrix(count, absorbing.len());
    for i in 0..count {
        let second: Fraction = (0..count).map(|j| {
            (Fraction::integer(2) * fundamental[i][j] - if i == j { ONE } else { ZERO }) * means[j]
        }).sum();
        variances[i] = second - means[i] * means[i];
        for (j, &target) in absorbing.iter().enumerate() {
            probabilities[i][j] = (0..count).map(|k| fundamental[i][k] * chain.transition[transient[k]][target]).sum();
        }
    }
    Absorption { transient, absorbing, fundamental, means, variances, probabilities }
}

fn names(chain: &Chain, indices: &[usize], separator: &str) -> String {
    indices.iter().map(|&i| chain.states[i].as_str()).collect::<Vec<_>>().join(separator)
}

fn fraction_list(values: &[Fraction]) -> String {
    values.iter().map(ToString::to_string).collect::<Vec<_>>().join(" ")
}

fn build(words: &[&str]) -> Result<(Chain, Vec<String>), String> {
    let order = number(words[2]);
    let tokens = &words[3..];
    if order != 1 && order != 2 {
        return Err("BAD ORDER".into());
    }
    if tokens.len() <= order {
        return Err("TOO FEW TOKENS".into());
    }
    let mut states = Vec::new();
    let mut observations = Vec::new();
    for i in 0..tokens.len() - order + 1 {
        let name = if order == 1 { tokens[i].to_owned() } else { format!("{}.{}", tokens[i], tokens[i + 1]) };
        let index = if let Some(index) = states.iter().position(|state| state == &name) {
            index
        } else {
            if states.len() == 10 {
                return Err("TOO MANY STATES".into());
            }
            states.push(name);
            states.len() - 1
        };
        observations.push(index);
    }
    let mut chain = Chain::new(states);
    let size = chain.states.len();
    let mut counts = vec![vec![0_i64; size]; size];
    let mut totals = vec![0_i64; size];
    for pair in observations.windows(2) {
        counts[pair[0]][pair[1]] += 1;
        totals[pair[0]] += 1;
    }
    let mut lines = vec![format!("BUILD {} order={order} states={size} transitions={}", words[1], observations.len() - 1)];
    for i in 0..size {
        if totals[i] == 0 {
            chain.transition[i][i] = ONE;
            lines.push(format!("FROM {} total=0 absorbing", chain.states[i]));
        } else {
            let mut line = format!("FROM {} total={}", chain.states[i], totals[i]);
            for j in 0..size {
                chain.transition[i][j] = Fraction::new(counts[i][j], totals[i]);
                if counts[i][j] > 0 {
                    line.push_str(&format!(" {}:{}", chain.states[j], counts[i][j]));
                }
            }
            lines.push(line);
        }
    }
    Ok((chain, lines))
}

fn gambler(words: &[&str]) -> Result<(Chain, Vec<String>), String> {
    let goal = number(words[2]);
    let start = number(words[3]);
    if goal == 0 || goal > 9 {
        return Err("BAD SIZE".into());
    }
    if start > goal {
        return Err("BAD START".into());
    }
    let chance = probability(words[4])?;
    if chance == ZERO || chance == ONE {
        return Err("BAD PROBABILITY".into());
    }
    let mut chain = Chain::new((0..=goal).map(|i| format!("s{i}")).collect());
    chain.transition[0][0] = ONE;
    chain.transition[goal][goal] = ONE;
    for i in 1..goal {
        chain.transition[i][i + 1] = chance;
        chain.transition[i][i - 1] = ONE - chance;
    }
    let result = absorption(&chain);
    let mut ruin = vec![ZERO; goal + 1];
    let mut duration = vec![ZERO; goal + 1];
    ruin[0] = ONE;
    for (i, &state) in result.transient.iter().enumerate() {
        ruin[state] = result.probabilities[i][0];
        duration[state] = result.means[i];
    }
    let mut lines = vec![format!("GAMBLER {} g={goal} p={chance} start=s{start} ruin={} duration={}", words[1], ruin[start].value(), duration[start].value())];
    for i in 0..=goal {
        lines.push(format!("CAPITAL s{i} ruin={} win={} duration={}", ruin[i].value(), (ONE - ruin[i]).value(), duration[i].value()));
    }
    Ok((chain, lines))
}

fn classify(name: &str, chain: &Chain, graph: &Graph) -> String {
    let size = chain.states.len();
    let absorbing = chain.absorbing();
    let is_absorbing = !absorbing.is_empty() && (0..size).all(|i| graph.reaches(i, &absorbing));
    let edges: Vec<Vec<bool>> = chain.transition.iter().map(|row| row.iter().map(|&p| p > ZERO).collect()).collect();
    let mut current = edges.clone();
    let mut exponent = None;
    for step in 1..=(size - 1) * (size - 1) + 1 {
        if current.iter().all(|row| row.iter().all(|&value| value)) {
            exponent = Some(step);
            break;
        }
        current = (0..size).map(|i| (0..size).map(|j| (0..size).any(|k| current[i][k] && edges[k][j])).collect()).collect();
    }
    let yes_no = |value| if value { "yes" } else { "no" };
    format!("CLASSIFY {name} absorbing_states={} absorbing={} ergodic={} regular={} exponent={}",
            absorbing.len(), yes_no(is_absorbing), yes_no(graph.classes.len() == 1), yes_no(exponent.is_some()),
            exponent.map_or_else(|| "-".into(), |value| value.to_string()))
}

fn execute(chains: &mut HashMap<String, Chain>, words: &[&str]) -> Result<Vec<String>, String> {
    let verb = words[0];
    let name = words[1];
    match verb {
        "CHAIN" => {
            let states = &words[2..];
            if states.len() > 10 {
                return Err("TOO MANY STATES".into());
            }
            for (i, state) in states.iter().enumerate() {
                if states[..i].contains(state) {
                    return Err(format!("DUPLICATE STATE {state}"));
                }
            }
            let chain = Chain::new(states.iter().map(|state| (*state).to_owned()).collect());
            chains.insert(name.to_owned(), chain);
            return Ok(vec![format!("CHAIN {name} states={}", states.len())]);
        }
        "BUILD" | "GAMBLER" => {
            let (chain, lines) = if verb == "BUILD" { build(words)? } else { gambler(words)? };
            chains.insert(name.to_owned(), chain);
            return Ok(lines);
        }
        _ => {}
    }
    let mut chain = chains.get(name).cloned().ok_or_else(|| format!("UNKNOWN CHAIN {name}"))?;
    let size = chain.states.len();
    let all: Vec<usize> = (0..size).collect();
    match verb {
        "P" | "ROW" => {
            let row = chain.state(words[2])?;
            let line = if verb == "P" {
                let column = chain.state(words[3])?;
                chain.transition[row][column] = probability(words[4])?;
                format!("P {name} {} {} {} rowsum={}", words[2], words[3], chain.transition[row][column], chain.row_sum(row, &all))
            } else {
                if words.len() - 3 != size {
                    return Err("BAD LENGTH".into());
                }
                chain.transition[row] = words[3..].iter().map(|text| probability(text)).collect::<Result<_, _>>()?;
                format!("ROW {name} {} rowsum={}", words[2], chain.row_sum(row, &all))
            };
            chains.insert(name.to_owned(), chain);
            return Ok(vec![line]);
        }
        "SHOW" => {
            let mut lines = vec![format!("MATRIX {name} states={size}")];
            lines.extend(chain.display(&chain.transition, "ROW"));
            return Ok(lines);
        }
        "CHECK" => {
            let mut bad = Vec::new();
            for i in 0..size {
                let sum = chain.row_sum(i, &all);
                if sum != ONE {
                    bad.push(format!("BADROW {} sum={sum}", chain.states[i]));
                }
            }
            let mut lines = vec![if bad.is_empty() { format!("CHECK {name} ok") } else { format!("CHECK {name} bad={}", bad.len()) }];
            lines.extend(bad);
            return Ok(lines);
        }
        _ => {}
    }
    for i in 0..size {
        if chain.row_sum(i, &all) != ONE {
            return Err(format!("NOT STOCHASTIC {}", chain.states[i]));
        }
    }
    let graph = Graph::new(&chain);
    let mut lines = Vec::new();
    match verb {
        "CLASSES" => {
            lines.push(format!("CLASSES {name} count={}", graph.classes.len()));
            for (i, class) in graph.classes.iter().enumerate() {
                let kind = if class.closed { "RECURRENT" } else { "TRANSIENT" };
                lines.push(format!("CLASS {} {kind} period={} size={} {}", i + 1, class.period, class.states.len(), names(&chain, &class.states, " ")));
                if class.period >= 2 {
                    for remainder in 0..class.period {
                        let states: Vec<usize> = class.states.iter().copied().filter(|&state| graph.levels[state] % class.period == remainder).collect();
                        lines.push(format!("CYCLIC {remainder} {}", names(&chain, &states, " ")));
                    }
                }
            }
        }
        "CLASSIFY" => lines.push(classify(name, &chain, &graph)),
        "STEP" => {
            let mut distribution = vec![ZERO; size];
            if words[2].as_bytes()[0].is_ascii_digit() {
                let values: Vec<&str> = words[2].split(',').collect();
                if values.len() != size {
                    return Err("BAD LENGTH".into());
                }
                distribution = values.iter().map(|text| probability(text)).collect::<Result<_, _>>()?;
                if distribution.iter().copied().sum::<Fraction>() != ONE {
                    return Err("BAD DISTRIBUTION".into());
                }
            } else {
                distribution[chain.state(words[2])?] = ONE;
            }
            let steps = number(words[3]);
            for _ in 0..steps {
                distribution = (0..size).map(|j| (0..size).map(|i| distribution[i] * chain.transition[i][j]).sum()).collect();
            }
            lines.push(format!("STEP {name} k={steps}"));
            for (i, value) in distribution.iter().enumerate() {
                lines.push(format!("PROB {} {}", chain.states[i], value.value()));
            }
        }
        "POWER" => {
            let steps = number(words[2]);
            let mut power = identity(size);
            for _ in 0..steps {
                power = matrix_product(&power, &chain.transition);
            }
            lines.push(format!("POWER {name} k={steps}"));
            lines.extend(chain.display(&power, "ROW"));
        }
        "STATIONARY" => {
            lines.push(format!("STATIONARY {name} count={}", graph.classes.iter().filter(|class| class.closed).count()));
            let mut number = 0;
            for (i, class) in graph.classes.iter().enumerate() {
                if class.closed {
                    number += 1;
                    let distribution = stationary(&chain, &class.states);
                    lines.push(format!("DIST {number} class={} size={}", i + 1, class.states.len()));
                    for &state in &class.states {
                        lines.push(format!("PI {} {}", chain.states[state], distribution[state].value()));
                    }
                }
            }
        }
        "RECURRENCE" => {
            let state = chain.state(words[2])?;
            let class = &graph.classes[graph.class_of[state]];
            if !class.closed {
                return Err(format!("TRANSIENT STATE {}", words[2]));
            }
            let chance = stationary(&chain, &class.states)[state];
            lines.push(format!("RECURRENCE {name} {} pi={} mean={} period={}", words[2], chance.value(), (ONE / chance).value(), class.period));
        }
        "ABSORB" => {
            let absorbing = chain.absorbing();
            if absorbing.is_empty() {
                return Err("NO ABSORBING STATE".into());
            }
            for i in 0..size {
                if !graph.reaches(i, &absorbing) {
                    return Err(format!("NOT ABSORBING {}", chain.states[i]));
                }
            }
            let result = absorption(&chain);
            lines.push(format!("ABSORB {name} transient={} absorbing={}", result.transient.len(), result.absorbing.len()));
            if !result.transient.is_empty() {
                lines.push(format!("TRANSIENT {}", names(&chain, &result.transient, " ")));
                lines.push(format!("ABSORBING {}", names(&chain, &result.absorbing, " ")));
                for (i, &state) in result.transient.iter().enumerate() {
                    lines.push(format!("N {} {}", chain.states[state], fraction_list(&result.fundamental[i])));
                }
                for (i, &state) in result.transient.iter().enumerate() {
                    lines.push(format!("STEPS {} mean={} var={}", chain.states[state], result.means[i].value(), result.variances[i].value()));
                }
                for (i, &state) in result.transient.iter().enumerate() {
                    lines.push(format!("B {} {}", chain.states[state], fraction_list(&result.probabilities[i])));
                }
            }
        }
        "HITTING" | "RESTRICT" => {
            let first = if verb == "HITTING" { 2 } else { 3 };
            let targets = chain.targets(&words[first..])?;
            if verb == "HITTING" {
                let result = hitting(&chain, &graph, &targets, true);
                lines.push(format!("HITTING {name} targets={}", names(&chain, &targets, ",")));
                for i in 0..size {
                    let time = result.times[i].map_or_else(|| "inf".into(), Fraction::value);
                    lines.push(format!("HIT {} prob={} time={time}", chain.states[i], result.probabilities[i].value()));
                }
            } else {
                for &i in &targets {
                    if (0..size).any(|j| !targets.contains(&j) && chain.transition[i][j] > ZERO) {
                        return Err(format!("NOT CLOSED {}", chain.states[i]));
                    }
                }
                let mut result = Chain::new(targets.iter().map(|&i| chain.states[i].clone()).collect());
                for (i, &source) in targets.iter().enumerate() {
                    for (j, &target) in targets.iter().enumerate() {
                        result.transition[i][j] = chain.transition[source][target];
                    }
                }
                lines.push(format!("RESTRICT {name} {} states={}", words[2], targets.len()));
                lines.extend(result.display(&result.transition, "ROW"));
                chains.insert(words[2].to_owned(), result);
            }
        }
        "FIRSTPASSAGE" => {
            let source = chain.state(words[2])?;
            let target = chain.state(words[3])?;
            let steps = number(words[4]);
            if steps == 0 {
                return Err("BAD STEPS".into());
            }
            let mut previous: Vec<Fraction> = (0..size).map(|i| chain.transition[i][target]).collect();
            let mut cumulative = ZERO;
            let mut records = Vec::new();
            for t in 1..=steps {
                if t > 1 {
                    previous = (0..size).map(|i| (0..size).filter(|&j| j != target).map(|j| chain.transition[i][j] * previous[j]).sum()).collect();
                }
                cumulative = cumulative + previous[source];
                records.push(format!("FP {t} {} cum={}", previous[source].value(), cumulative.value()));
            }
            lines.push(format!("FIRSTPASSAGE {name} {} {} k={steps} total={}", words[2], words[3], cumulative.value()));
            lines.extend(records);
        }
        "PATHPROB" => {
            let path: Vec<usize> = words[2..].iter().map(|name| chain.state(name)).collect::<Result<_, _>>()?;
            let mut chance = ONE;
            let mut zero_at = None;
            for (i, pair) in path.windows(2).enumerate() {
                chance = chance * chain.transition[pair[0]][pair[1]];
                if chance == ZERO && zero_at.is_none() {
                    zero_at = Some(i + 1);
                }
            }
            let suffix = zero_at.map_or_else(String::new, |step| format!(" zero_at={step}"));
            lines.push(format!("PATHPROB {name} steps={} prob={}{suffix}", path.len() - 1, chance.value()));
        }
        "MOSTLIKELY" => {
            let source = chain.state(words[2])?;
            let steps = number(words[3]);
            if steps == 0 {
                return Err("BAD STEPS".into());
            }
            let mut best = matrix(steps + 1, size);
            let mut choice = vec![vec![0; size]; steps];
            best[steps].fill(ONE);
            for t in (0..steps).rev() {
                for i in 0..size {
                    for j in 0..size {
                        let candidate = chain.transition[i][j] * best[t + 1][j];
                        if candidate > best[t][i] {
                            best[t][i] = candidate;
                            choice[t][i] = j;
                        }
                    }
                }
            }
            let mut path = vec![source];
            let mut current = source;
            for row in choice {
                current = row[current];
                path.push(current);
            }
            lines.push(format!("MOSTLIKELY {name} {} k={steps} prob={}", words[2], best[0][source].value()));
            lines.push(format!("PATH {}", names(&chain, &path, " ")));
        }
        "LUMP" => {
            let mut blocks = Vec::new();
            let mut seen = vec![false; size];
            for text in words[3].split('|') {
                let mut block = Vec::new();
                for state in text.split(',') {
                    let index = chain.state(state)?;
                    if seen[index] {
                        return Err("BAD PARTITION".into());
                    }
                    seen[index] = true;
                    block.push(index);
                }
                block.sort_unstable();
                blocks.push(block);
            }
            if seen.iter().any(|&value| !value) {
                return Err("BAD PARTITION".into());
            }
            blocks.sort_unstable_by_key(|block| block[0]);
            let mut result = Chain::new(blocks.iter().map(|block| chain.states[block[0]].clone()).collect());
            for (i, source) in blocks.iter().enumerate() {
                for (j, target) in blocks.iter().enumerate() {
                    let expected = chain.row_sum(source[0], target);
                    result.transition[i][j] = expected;
                    for &state in source {
                        let actual = chain.row_sum(state, target);
                        if actual != expected {
                            return Ok(vec![format!("LUMP {name} not lumpable block={} target={} {}={} {}={}",
                                chain.states[source[0]], chain.states[target[0]], chain.states[source[0]], expected.value(), chain.states[state], actual.value())]);
                        }
                    }
                }
            }
            lines.push(format!("LUMP {name} {} blocks={}", words[2], blocks.len()));
            lines.extend(result.display(&result.transition, "ROW"));
            chains.insert(words[2].to_owned(), result);
        }
        "REWARD" => {
            if words.len() - 3 != size {
                return Err("BAD LENGTH".into());
            }
            let gamma = probability(words[2])?;
            if gamma == ONE {
                return Err("BAD DISCOUNT".into());
            }
            let rewards: Vec<Fraction> = words[3..].iter().map(|value| Fraction::integer(value.parse().unwrap())).collect();
            let mut equations = matrix(size, size + 1);
            for i in 0..size {
                for j in 0..size {
                    equations[i][j] = (if i == j { ONE } else { ZERO }) - gamma * chain.transition[i][j];
                }
                equations[i][size] = rewards[i];
            }
            let solved = eliminate(equations);
            let mut gain = vec![ZERO; size];
            for class in &graph.classes {
                if !class.closed {
                    continue;
                }
                let distribution = stationary(&chain, &class.states);
                let average: Fraction = class.states.iter().map(|&i| distribution[i] * rewards[i]).sum();
                let hit = hitting(&chain, &graph, &class.states, false);
                for i in 0..size {
                    gain[i] = gain[i] + hit.probabilities[i] * average;
                }
            }
            lines.push(format!("REWARD {name} gamma={gamma}"));
            for i in 0..size {
                lines.push(format!("VALUE {} discounted={} gain={}", chain.states[i], solved[i][size].value(), gain[i].value()));
            }
        }
        "SIMULATE" => {
            let mut current = chain.state(words[2])?;
            let steps = number(words[3]);
            if steps == 0 {
                return Err("BAD STEPS".into());
            }
            let seed: i64 = words[4].parse().unwrap();
            if seed == 0 || seed >= 2_147_483_647 {
                return Err("BAD SEED".into());
            }
            let mut random = seed;
            let mut path = vec![current];
            let mut visits = vec![0; size];
            visits[current] += 1;
            for _ in 0..steps {
                let common = chain.transition[current].iter().fold(1, |value, p| value / gcd(value, p.denominator) * p.denominator);
                random = 48_271 * random % 2_147_483_647;
                let draw = random % common;
                let mut cumulative = ZERO;
                for j in 0..size {
                    cumulative = cumulative + chain.transition[current][j];
                    if cumulative.numerator * (common / cumulative.denominator) > draw {
                        current = j;
                        break;
                    }
                }
                path.push(current);
                visits[current] += 1;
            }
            lines.push(format!("SIMULATE {name} {} steps={steps} seed={seed} end={}", words[2], chain.states[current]));
            lines.push(format!("PATH {}", names(&chain, &path, " ")));
            for (i, count) in visits.iter().enumerate() {
                lines.push(format!("VISIT {} {count}", chain.states[i]));
            }
        }
        "PASSAGE" | "REVERSIBLE" | "REVERSE" | "MIXING" => {
            let mut steps = 0;
            let mut epsilon = ZERO;
            if verb == "MIXING" {
                steps = number(words[2]);
                if steps == 0 {
                    return Err("BAD STEPS".into());
                }
                epsilon = probability(words[3])?;
            }
            if graph.classes.len() != 1 {
                return Err("NOT IRREDUCIBLE".into());
            }
            let distribution = stationary(&chain, &all);
            match verb {
                "PASSAGE" => {
                    let mut passage = matrix(size, size);
                    for j in 0..size {
                        let hit = hitting(&chain, &graph, &[j], true);
                        for i in 0..size {
                            passage[i][j] = if i == j { ONE / distribution[j] } else { hit.times[i].unwrap() };
                        }
                    }
                    let kemeny: Fraction = (1..size).map(|j| distribution[j] * passage[0][j]).sum();
                    lines.push(format!("PASSAGE {name} kemeny={}", kemeny.value()));
                    lines.extend(chain.display(&passage, "M"));
                }
                "REVERSIBLE" => {
                    let mut violations = Vec::new();
                    for i in 0..size {
                        for j in i + 1..size {
                            let forward = distribution[i] * chain.transition[i][j];
                            let backward = distribution[j] * chain.transition[j][i];
                            if forward != backward {
                                violations.push(format!("VIOLATION {} {} {} {}", chain.states[i], chain.states[j], forward.value(), backward.value()));
                            }
                        }
                    }
                    lines.push(if violations.is_empty() { format!("REVERSIBLE {name} yes") } else { format!("REVERSIBLE {name} no violations={}", violations.len()) });
                    lines.extend(violations);
                }
                "REVERSE" => {
                    let mut result = Chain::new(chain.states.clone());
                    for i in 0..size {
                        for j in 0..size {
                            result.transition[i][j] = distribution[j] * chain.transition[j][i] / distribution[i];
                        }
                    }
                    let reversible = if result.transition == chain.transition { "yes" } else { "no" };
                    lines.push(format!("REVERSE {name} {} reversible={reversible}", words[2]));
                    lines.extend(result.display(&result.transition, "ROW"));
                    chains.insert(words[2].to_owned(), result);
                }
                _ => {
                    let mut power = identity(size);
                    let mut records = Vec::new();
                    let mut mixing = None;
                    for t in 1..=steps {
                        power = matrix_product(&power, &chain.transition);
                        let mut distance = ZERO;
                        let mut worst = 0;
                        for i in 0..size {
                            let total: Fraction = (0..size).map(|j| (power[i][j] - distribution[j]).abs()).sum();
                            let candidate = total / Fraction::integer(2);
                            if candidate > distance {
                                distance = candidate;
                                worst = i;
                            }
                        }
                        if mixing.is_none() && distance <= epsilon {
                            mixing = Some(t);
                        }
                        records.push(format!("TV {t} {} from={}", distance.value(), chain.states[worst]));
                    }
                    let time = mixing.map_or_else(|| "none".into(), |value| value.to_string());
                    lines.push(format!("MIXING {name} k={steps} eps={epsilon} time={time}"));
                    lines.extend(records);
                }
            }
        }
        _ => unreachable!(),
    }
    Ok(lines)
}

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut lines = input.lines();
    let count = number(lines.next().unwrap());
    let mut chains = HashMap::new();
    let mut output = io::BufWriter::new(io::stdout().lock());
    for line in lines.take(count) {
        let words: Vec<&str> = line.split_whitespace().collect();
        match execute(&mut chains, &words) {
            Ok(result) => {
                for text in result {
                    writeln!(output, "{text}").unwrap();
                }
            }
            Err(problem) => writeln!(output, "ERROR {problem}").unwrap(),
        }
    }
}
