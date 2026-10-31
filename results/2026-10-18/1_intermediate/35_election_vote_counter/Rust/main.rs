use std::collections::BTreeMap;
use std::fmt::{self, Display};
use std::io::{self, BufRead, Write};

const LIMIT: usize = 7;
type Field = u8;
type Row = [i32; LIMIT];
type Matrix = [Row; LIMIT];
type Relation = [[bool; LIMIT]; LIMIT];

struct Ballot {
    votes: i32,
    ranking: Vec<usize>,
}

#[derive(Clone, Copy, Default)]
struct Tallies {
    first: Row,
    last: Row,
    borda: Row,
    approval: Matrix,
    nonblank: i32,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum MinimaxKind { Winning, Margin, Opposition }

#[derive(Clone, Copy, PartialEq, Eq)]
enum Method {
    Plurality, Runoff, Irv, Coombs, Bucklin, Borda, Baldwin, Nanson, Black, Veto,
    Condorcet, Copeland, Minimax(MinimaxKind), Schulze, RankedPairs, Kemeny,
    Approval(usize), Stv(usize),
}

impl Method {
    fn parse(words: &[&str]) -> Self {
        match words[0] {
            "PLURALITY" => Self::Plurality,
            "RUNOFF" => Self::Runoff,
            "IRV" => Self::Irv,
            "COOMBS" => Self::Coombs,
            "BUCKLIN" => Self::Bucklin,
            "BORDA" => Self::Borda,
            "BALDWIN" => Self::Baldwin,
            "NANSON" => Self::Nanson,
            "BLACK" => Self::Black,
            "VETO" => Self::Veto,
            "CONDORCET" => Self::Condorcet,
            "COPELAND" => Self::Copeland,
            "MINIMAX" => Self::Minimax(match words[1] {
                "WINNING" => MinimaxKind::Winning,
                "MARGIN" => MinimaxKind::Margin,
                "OPPOSITION" => MinimaxKind::Opposition,
                _ => unreachable!(),
            }),
            "SCHULZE" => Self::Schulze,
            "RANKEDPAIRS" => Self::RankedPairs,
            "KEMENY" => Self::Kemeny,
            "APPROVAL" => Self::Approval(words[1].parse().unwrap()),
            "STV" => Self::Stv(words[1].parse().unwrap()),
            _ => unreachable!(),
        }
    }

    fn rankable(self) -> bool { !matches!(self, Self::Condorcet | Self::Stv(_)) }
}

impl Display for Method {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let name = match self {
            Self::Plurality => "PLURALITY", Self::Runoff => "RUNOFF", Self::Irv => "IRV",
            Self::Coombs => "COOMBS", Self::Bucklin => "BUCKLIN", Self::Borda => "BORDA",
            Self::Baldwin => "BALDWIN", Self::Nanson => "NANSON", Self::Black => "BLACK",
            Self::Veto => "VETO", Self::Condorcet => "CONDORCET", Self::Copeland => "COPELAND",
            Self::Minimax(MinimaxKind::Winning) => "MINIMAX WINNING",
            Self::Minimax(MinimaxKind::Margin) => "MINIMAX MARGIN",
            Self::Minimax(MinimaxKind::Opposition) => "MINIMAX OPPOSITION",
            Self::Schulze => "SCHULZE", Self::RankedPairs => "RANKEDPAIRS", Self::Kemeny => "KEMENY",
            Self::Approval(k) => return write!(f, "APPROVAL {k}"),
            Self::Stv(seats) => return write!(f, "STV {seats}"),
        };
        f.write_str(name)
    }
}

const SUMMARY: [Method; 15] = [
    Method::Plurality, Method::Runoff, Method::Irv, Method::Coombs, Method::Bucklin,
    Method::Borda, Method::Baldwin, Method::Nanson, Method::Black, Method::Veto,
    Method::Copeland, Method::Minimax(MinimaxKind::Winning), Method::Schulze,
    Method::RankedPairs, Method::Kemeny,
];

struct Outcome {
    order: Vec<usize>,
    lines: Vec<String>,
}

struct Parcel {
    value: i32,
    owner: Option<usize>,
}

struct Election {
    number: usize,
    names: Vec<String>,
    active: Field,
    tiebreak: Vec<usize>,
    priority: [usize; LIMIT],
    groups: Vec<Ballot>,
    entry_ends: Vec<usize>,
    total: i32,
    cache: [Option<Tallies>; 1 << LIMIT],
    pairs: Option<Matrix>,
}

fn bit(a: usize) -> Field { 1 << a }
fn members(field: Field) -> Vec<usize> { (0..LIMIT).filter(|&a| field & bit(a) != 0).collect() }
fn mask(list: &[usize]) -> Field { list.iter().fold(0, |field, &a| field | bit(a)) }
fn effective(list: &[usize], field: Field) -> Vec<usize> {
    list.iter().copied().filter(|&a| field & bit(a) != 0).collect()
}
fn tie_mark(tie: bool) -> &'static str { if tie { " (tie)" } else { "" } }
fn money(value: i32) -> String { format!("{}.{:02}", value / 100, value % 100) }
fn sum(field: Field, scores: &Row) -> i32 { members(field).iter().map(|&a| scores[a]).sum() }
fn majority(field: Field, scores: &Row) -> bool {
    let total = sum(field, scores);
    members(field).iter().any(|&a| 2 * scores[a] > total)
}
fn closure(field: Field, relation: &mut Relation) {
    let list = members(field);
    for &k in &list { for &a in &list { for &b in &list {
        let reachable = relation[a][b] || (relation[a][k] && relation[k][b]);
        relation[a][b] = reachable;
    } } }
}

impl Election {
    fn new(number: usize, names: Vec<String>) -> Self {
        let active = bit(names.len()) - 1;
        let mut tiebreak = members(active);
        tiebreak.sort_by(|&a, &b| names[a].cmp(&names[b]));
        let mut priority = [0; LIMIT];
        for (i, &a) in tiebreak.iter().enumerate() { priority[a] = i; }
        Self {
            number, names, active, tiebreak, priority, groups: Vec::new(), entry_ends: Vec::new(),
            total: 0, cache: [None; 1 << LIMIT], pairs: None,
        }
    }

    fn candidate(&self, name: &str) -> Result<usize, String> {
        self.names.iter().position(|item| item == name).ok_or_else(|| format!("unknown candidate {name}"))
    }

    fn checked_names(&self, names: &[&str]) -> Result<Vec<usize>, String> {
        let mut result = Vec::new();
        for &name in names {
            let a = self.candidate(name)?;
            if result.contains(&a) { return Err(format!("duplicate candidate {name}")); }
            result.push(a);
        }
        Ok(result)
    }

    fn names_text(&self, list: &[usize], separator: &str) -> String {
        list.iter().map(|&a| self.names[a].as_str()).collect::<Vec<_>>().join(separator)
    }

    fn values(&self, field: Field, scores: &Row, cents: bool) -> String {
        members(field).iter().map(|&a| {
            format!("{} {}", self.names[a], if cents { money(scores[a]) } else { scores[a].to_string() })
        }).collect::<Vec<_>>().join(", ")
    }

    fn ordered(&self, field: Field, scores: &Row, descending: bool) -> Vec<usize> {
        let mut order = members(field);
        order.sort_by(|&a, &b| {
            let comparison = if descending { scores[b].cmp(&scores[a]) } else { scores[a].cmp(&scores[b]) };
            comparison.then_with(|| self.priority[a].cmp(&self.priority[b]))
        });
        order
    }

    fn finish(&self, order: Vec<usize>, tie: bool, mut lines: Vec<String>) -> Outcome {
        lines.push(format!("winner: {}{}", self.names[order[0]], tie_mark(tie)));
        Outcome { order, lines }
    }

    fn invalidate(&mut self) {
        self.cache.fill(None);
        self.pairs = None;
    }

    fn finish_entry(&mut self) {
        self.entry_ends.push(self.groups.len());
        self.invalidate();
    }

    fn tallies(&mut self, field: Field) -> Tallies {
        if let Some(result) = self.cache[usize::from(field)] { return result; }
        let mut result = Tallies::default();
        let candidates = members(field);
        let m = candidates.len();
        for group in &self.groups {
            let ranking = effective(&group.ranking, field);
            let ranked = mask(&ranking);
            if let Some(&first) = ranking.first() {
                result.first[first] += group.votes;
                result.nonblank += group.votes;
            }
            if ranking.len() == m { result.last[ranking[m - 1]] += group.votes; }
            else {
                for &a in &candidates { if ranked & bit(a) == 0 { result.last[a] += group.votes; } }
            }
            for (j, &a) in ranking.iter().enumerate() {
                result.borda[a] += group.votes * (m - j - 1) as i32;
                for depth in j..m { result.approval[depth][a] += group.votes; }
            }
        }
        self.cache[usize::from(field)] = Some(result);
        result
    }

    fn pairwise(&mut self) -> Matrix {
        if let Some(matrix) = self.pairs { return matrix; }
        let mut matrix = [[0; LIMIT]; LIMIT];
        for group in &self.groups {
            let mut positions = [LIMIT; LIMIT];
            for (i, &a) in group.ranking.iter().enumerate() { positions[a] = i; }
            for a in 0..self.names.len() { for b in 0..self.names.len() {
                if positions[a] < positions[b] { matrix[a][b] += group.votes; }
            } }
        }
        self.pairs = Some(matrix);
        matrix
    }

    fn condorcet(&mut self, field: Field, loser: bool) -> Option<usize> {
        let matrix = self.pairwise();
        let list = members(field);
        list.iter().copied().find(|&a| list.iter().all(|&b| {
            a == b || if loser { matrix[a][b] < matrix[b][a] } else { matrix[a][b] > matrix[b][a] }
        }))
    }

    fn look_back(&self, field: Field, history: &[Row]) -> (usize, bool) {
        let current = history.last().unwrap();
        let mut choices = members(field);
        let minimum = choices.iter().map(|&a| current[a]).min().unwrap();
        choices.retain(|&a| current[a] == minimum);
        let tie = choices.len() > 1;
        for scores in history.iter().rev().skip(1) {
            let minimum = choices.iter().map(|&a| scores[a]).min().unwrap();
            choices.retain(|&a| scores[a] == minimum);
        }
        (*choices.iter().max_by_key(|&&a| self.priority[a]).unwrap(), tie)
    }

    fn elimination(&mut self, field: Field, coombs: bool, exhausted: bool) -> Outcome {
        let mut remaining = field;
        let mut removed = Vec::new();
        let mut history = Vec::new();
        let mut lines = Vec::new();
        loop {
            let scores = self.tallies(remaining);
            let round = lines.len() + 1;
            let mut line = if exhausted {
                let active = sum(remaining, &scores.first);
                format!("round {round}: active {active}, exhausted {}", self.total - active)
            } else { format!("round {round}: {}", self.values(remaining, &scores.first, false)) };
            if remaining.count_ones() == 1 || majority(remaining, &scores.first) {
                lines.push(line);
                let mut order = self.ordered(remaining, &scores.first, true);
                order.extend(removed.into_iter().rev());
                return if exhausted { Outcome { order, lines } } else { self.finish(order, false, lines) };
            }
            let (eliminated, tie) = if coombs {
                let list = members(remaining);
                let maximum = list.iter().map(|&a| scores.last[a]).max().unwrap();
                let choices: Vec<_> = list.into_iter().filter(|&a| scores.last[a] == maximum).collect();
                let least = self.ordered(mask(&choices), &scores.first, true);
                line.push_str(&format!("; last {}", self.values(remaining, &scores.last, false)));
                (*least.last().unwrap(), choices.len() > 1)
            } else {
                history.push(scores.first);
                self.look_back(remaining, &history)
            };
            if !exhausted { line.push_str(&format!("; eliminated {}{}", self.names[eliminated], tie_mark(tie))); }
            lines.push(line);
            removed.push(eliminated);
            remaining &= !bit(eliminated);
        }
    }

    fn runoff(&mut self, field: Field) -> Outcome {
        let first = self.tallies(field);
        let mut order = self.ordered(field, &first.first, true);
        let mut lines = vec![format!("round 1: {}", self.values(field, &first.first, false))];
        let mut tie = false;
        if !majority(field, &first.first) {
            let (a, b) = (order[0], order[1]);
            let finalists = bit(a) | bit(b);
            let advancement_tie = order.len() >= 3 && first.first[b] == first.first[order[2]];
            let second = self.tallies(finalists);
            tie = second.first[a] == second.first[b];
            if second.first[b] > second.first[a] { order.swap(0, 1); }
            lines.push(format!("finalists: {}{}", self.names_text(&members(finalists), ", "), tie_mark(advancement_tie)));
            lines.push(format!("round 2: {}", self.values(finalists, &second.first, false)));
        }
        self.finish(order, tie, lines)
    }

    fn bucklin(&mut self, field: Field) -> Outcome {
        let scores = self.tallies(field);
        let majority = scores.nonblank / 2 + 1;
        let mut lines = vec![format!("majority: {majority}")];
        let mut order = members(field);
        let mut final_depth = 0;
        for depth in 0..order.len() {
            final_depth = depth;
            lines.push(format!("round {}: {}", depth + 1, self.values(field, &scores.approval[depth], false)));
            if order.iter().any(|&a| scores.approval[depth][a] >= majority) { break; }
        }
        order.sort_by(|&a, &b| {
            for depth in (0..=final_depth).rev() {
                let comparison = scores.approval[depth][b].cmp(&scores.approval[depth][a]);
                if !comparison.is_eq() { return comparison; }
            }
            self.priority[a].cmp(&self.priority[b])
        });
        let tie = scores.approval[final_depth][order[0]] == scores.approval[final_depth][order[1]];
        self.finish(order, tie, lines)
    }

    fn borda_elimination(&mut self, field: Field, nanson: bool) -> Outcome {
        let mut remaining = field;
        let mut tail = Vec::new();
        let mut lines = Vec::new();
        let mut history = Vec::new();
        while remaining.count_ones() >= 2 {
            let scores = self.tallies(remaining).borda;
            let mut line = format!("round {}: {}", lines.len() + 1, self.values(remaining, &scores, false));
            let mut removed = if nanson {
                let total = sum(remaining, &scores);
                let below: Vec<_> = members(remaining).into_iter().filter(|&a| scores[a] * (remaining.count_ones() as i32) < total).collect();
                if below.is_empty() { lines.push(line); break; }
                line.push_str(&format!("; eliminated {}", self.names_text(&below, ", ")));
                self.ordered(mask(&below), &scores, true)
            } else {
                history.push(scores);
                let (a, tie) = self.look_back(remaining, &history);
                line.push_str(&format!("; eliminated {}{}", self.names[a], tie_mark(tie)));
                vec![a]
            };
            lines.push(line);
            remaining &= !mask(&removed);
            removed.extend(tail);
            tail = removed;
        }
        let mut order = self.ordered(remaining, &[0; LIMIT], true);
        let tie = nanson && order.len() > 1;
        order.extend(tail);
        self.finish(order, tie, lines)
    }

    fn pair_lines(&self, field: Field, matrix: &Matrix) -> Vec<String> {
        let list = members(field);
        let mut lines = Vec::new();
        for (i, &a) in list.iter().enumerate() { for &b in &list[i + 1..] {
            let result = if matrix[a][b] == matrix[b][a] { "tie" }
                else { &self.names[if matrix[a][b] > matrix[b][a] { a } else { b }] };
            lines.push(format!("{} vs {}: {}-{} ({result})", self.names[a], self.names[b], matrix[a][b], matrix[b][a]));
        } }
        lines
    }

    fn condorcet_report(&mut self, field: Field) -> Outcome {
        let win = self.condorcet(field, false);
        let lose = self.condorcet(field, true);
        let matrix = self.pairwise();
        let mut weak = [[false; LIMIT]; LIMIT];
        let mut strong = weak;
        let list = members(field);
        for &a in &list { for &b in &list {
            weak[a][b] = matrix[a][b] >= matrix[b][a];
            strong[a][b] = matrix[a][b] > matrix[b][a];
        } }
        closure(field, &mut weak);
        closure(field, &mut strong);
        let smith: Vec<_> = list.iter().copied().filter(|&a| list.iter().all(|&b| weak[a][b])).collect();
        let schwartz: Vec<_> = list.iter().copied().filter(|&a| list.iter().all(|&b| !strong[b][a] || strong[a][b])).collect();
        Outcome { order: Vec::new(), lines: vec![
            format!("winner: {}", win.map(|a| self.names[a].as_str()).unwrap_or("NONE")),
            format!("loser: {}", lose.map(|a| self.names[a].as_str()).unwrap_or("NONE")),
            format!("smith: {}", self.names_text(&smith, ", ")),
            format!("schwartz: {}", self.names_text(&schwartz, ", ")),
        ] }
    }

    fn topological(&self, field: Field, relation: &Relation) -> (Vec<usize>, bool) {
        let mut remaining = field;
        let mut order = Vec::new();
        let mut tie = false;
        while remaining != 0 {
            let list = members(remaining);
            let choices: Vec<_> = list.iter().copied().filter(|&a| list.iter().all(|&b| a == b || !relation[b][a])).collect();
            if order.is_empty() { tie = choices.len() > 1; }
            let a = *choices.iter().min_by_key(|&&a| self.priority[a]).unwrap();
            order.push(a);
            remaining &= !bit(a);
        }
        (order, tie)
    }

    fn schulze(&mut self, field: Field) -> Outcome {
        let matrix = self.pairwise();
        let list = members(field);
        let mut paths = [[0; LIMIT]; LIMIT];
        for &a in &list { for &b in &list {
            if matrix[a][b] > matrix[b][a] { paths[a][b] = matrix[a][b]; }
        } }
        for &via in &list { for &a in &list { for &b in &list {
            if a != via && b != via && a != b { paths[a][b] = paths[a][b].max(paths[a][via].min(paths[via][b])); }
        } } }
        let mut relation = [[false; LIMIT]; LIMIT];
        for &a in &list { for &b in &list { relation[a][b] = paths[a][b] > paths[b][a]; } }
        let (order, tie) = self.topological(field, &relation);
        let mut lines = self.pair_lines(field, &paths);
        lines.push(format!("ranking: {}", self.names_text(&order, " > ")));
        self.finish(order, tie, lines)
    }

    fn ranked_pairs(&mut self, field: Field) -> Outcome {
        let matrix = self.pairwise();
        let list = members(field);
        let mut pairs = Vec::new();
        for &a in &list { for &b in &list { if matrix[a][b] > matrix[b][a] { pairs.push((a, b)); } } }
        pairs.sort_by_key(|&(a, b)| (-matrix[a][b], matrix[b][a], self.priority[a], self.priority[b]));
        let mut locked = [[false; LIMIT]; LIMIT];
        let mut reached = locked;
        let mut lines = Vec::new();
        for (a, b) in pairs {
            let action = if reached[b][a] { "skip" } else { "lock" };
            lines.push(format!("{action} {}>{} {}-{}", self.names[a], self.names[b], matrix[a][b], matrix[b][a]));
            if !reached[b][a] {
                locked[a][b] = true;
                reached[a][b] = true;
                closure(field, &mut reached);
            }
        }
        let (order, tie) = self.topological(field, &locked);
        self.finish(order, tie, lines)
    }

    fn kemeny(&mut self, field: Field) -> Outcome {
        let matrix = self.pairwise();
        let mut best = [0; 1 << LIMIT];
        let mut ways = [0; 1 << LIMIT];
        let mut heads = [0; 1 << LIMIT];
        ways[0] = 1;
        for subset in 1..=usize::from(field) {
            let current = subset as Field;
            if current & !field != 0 { continue; }
            best[subset] = -1;
            let list = members(current);
            for &a in &list {
                let rest = usize::from(current & !bit(a));
                let score = best[rest] + list.iter().filter(|&&b| b != a).map(|&b| matrix[a][b]).sum::<i32>();
                if score > best[subset] { best[subset] = score; ways[subset] = 0; heads[subset] = 0; }
                if score == best[subset] {
                    let count = ways[rest];
                    ways[subset] += count;
                    heads[subset] |= bit(a);
                }
            }
        }
        let mut order = Vec::new();
        let mut remaining = field;
        while remaining != 0 {
            let choices = heads[usize::from(remaining)];
            let a = *self.tiebreak.iter().find(|&&a| choices & bit(a) != 0).unwrap();
            order.push(a);
            remaining &= !bit(a);
        }
        let index = usize::from(field);
        let lines = vec![format!("score: {}", best[index]), format!("optimal: {}", ways[index]), format!("ranking: {}", self.names_text(&order, " > "))];
        self.finish(order, heads[index].count_ones() > 1, lines)
    }

    fn stv(&mut self, field: Field, seats: usize) -> Outcome {
        let mut parcels: Vec<_> = self.groups.iter().map(|group| Parcel {
            value: if group.ranking.iter().any(|&a| field & bit(a) != 0) { 100 } else { 0 },
            owner: None,
        }).collect();
        let quota = self.tallies(field).nonblank * 100 / (seats as i32 + 1) + 1;
        let mut lines = vec![format!("quota: {}", money(quota))];
        let mut continuing = field;
        let mut elected = Vec::new();
        let mut history = Vec::new();
        loop {
            let mut scores = [0; LIMIT];
            let mut exhausted = 0;
            for (parcel, group) in parcels.iter_mut().zip(&self.groups) {
                parcel.owner = None;
                if parcel.value == 0 { continue; }
                parcel.owner = group.ranking.iter().copied().find(|&a| continuing & bit(a) != 0);
                let value = group.votes * parcel.value;
                if let Some(a) = parcel.owner { scores[a] += value; }
                else { exhausted += value; }
            }
            history.push(scores);
            let mut line = format!("round {}: {}; exhausted {}", history.len(), self.values(continuing, &scores, true), money(exhausted));
            let order = self.ordered(continuing, &scores, true);
            if order.len() == seats - elected.len() {
                line.push_str(&format!("; elected {}", self.names_text(&order, ", ")));
                elected.extend(order);
                lines.push(line);
                break;
            }
            let a = order[0];
            if scores[a] >= quota {
                let surplus = scores[a] - quota;
                elected.push(a);
                continuing &= !bit(a);
                for parcel in &mut parcels {
                    if parcel.owner == Some(a) { parcel.value = parcel.value * surplus / scores[a]; }
                }
                line.push_str(&format!("; elected {} (surplus {})", self.names[a], money(surplus)));
                lines.push(line);
                if elected.len() == seats { break; }
            } else {
                let (excluded, tie) = self.look_back(continuing, &history);
                continuing &= !bit(excluded);
                line.push_str(&format!("; excluded {}{}", self.names[excluded], tie_mark(tie)));
                lines.push(line);
            }
        }
        lines.push(format!("elected: {}", self.names_text(&elected, ", ")));
        Outcome { order: Vec::new(), lines }
    }

    fn tally(&mut self, field: Field, method: Method) -> Outcome {
        match method {
            Method::Runoff => return self.runoff(field),
            Method::Irv | Method::Coombs => return self.elimination(field, method == Method::Coombs, false),
            Method::Bucklin => return self.bucklin(field),
            Method::Baldwin | Method::Nanson => return self.borda_elimination(field, method == Method::Nanson),
            Method::Schulze => return self.schulze(field),
            Method::RankedPairs => return self.ranked_pairs(field),
            Method::Kemeny => return self.kemeny(field),
            Method::Condorcet => return self.condorcet_report(field),
            Method::Stv(seats) => return self.stv(field, seats),
            _ => {}
        }
        let base = self.tallies(field);
        let mut lines = Vec::new();
        let mut condorcet_winner = None;
        let (scores, label, descending) = match method {
            Method::Plurality => (base.first, Some("votes"), true),
            Method::Borda | Method::Black => {
                if method == Method::Black {
                    condorcet_winner = self.condorcet(field, false);
                    lines.push(format!("condorcet: {}", condorcet_winner.map(|a| self.names[a].as_str()).unwrap_or("NONE")));
                }
                (base.borda, Some("scores"), true)
            }
            Method::Veto => (base.last, Some("vetoes"), false),
            Method::Approval(k) => (base.approval[k.min(field.count_ones() as usize) - 1], Some("approvals"), true),
            Method::Copeland => {
                let matrix = self.pairwise();
                let list = members(field);
                let mut scores = [0; LIMIT];
                let mut descriptions = Vec::new();
                for &a in &list {
                    let (mut wins, mut draws, mut losses) = (0, 0, 0);
                    for &b in &list { if a != b {
                        match matrix[a][b].cmp(&matrix[b][a]) {
                            std::cmp::Ordering::Greater => wins += 1,
                            std::cmp::Ordering::Equal => draws += 1,
                            std::cmp::Ordering::Less => losses += 1,
                        }
                    } }
                    scores[a] = 2 * wins + draws;
                    descriptions.push(format!("{} {}.{} ({wins}-{draws}-{losses})", self.names[a], scores[a] / 2, scores[a] % 2 * 5));
                }
                lines.push(format!("scores: {}", descriptions.join(", ")));
                (scores, None, true)
            }
            Method::Minimax(kind) => {
                let matrix = self.pairwise();
                let list = members(field);
                let mut scores = [0; LIMIT];
                for &a in &list { for &b in &list { if a != b {
                    let (opposition, support) = (matrix[b][a], matrix[a][b]);
                    let value = if kind == MinimaxKind::Opposition { opposition }
                        else if opposition > support { if kind == MinimaxKind::Margin { opposition - support } else { opposition } }
                        else { 0 };
                    scores[a] = scores[a].max(value);
                } } }
                (scores, Some("scores"), false)
            }
            _ => unreachable!(),
        };
        let mut order = self.ordered(field, &scores, descending);
        let mut tie = scores[order[0]] == scores[order[1]];
        if let Some(a) = condorcet_winner {
            order.remove(order.iter().position(|&b| b == a).unwrap());
            order.insert(0, a);
            tie = false;
        }
        if let Some(label) = label { lines.push(format!("{label}: {}", self.values(field, &scores, false))); }
        self.finish(order, tie, lines)
    }

    fn ballots_report(&self) -> Vec<String> {
        let mut counts = BTreeMap::<String, i32>::new();
        for group in &self.groups {
            let ranking = effective(&group.ranking, self.active);
            let notation = if ranking.is_empty() { "-".to_owned() } else { self.names_text(&ranking, ">") };
            *counts.entry(notation).or_default() += group.votes;
        }
        let blank = counts.get("-").copied().unwrap_or(0);
        let mut groups: Vec<_> = counts.into_iter().collect();
        groups.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.cmp(&b.0)));
        let mut lines = vec![format!("total {}, blank {blank}, distinct {}", self.total, groups.len())];
        lines.extend(groups.into_iter().map(|(notation, votes)| format!("{votes} {notation}")));
        lines
    }
}

#[derive(Default)]
struct Lab {
    election: Option<Election>,
    number: usize,
}

impl Lab {
    fn execute(&mut self, line: &str) -> Result<Vec<String>, String> {
        let words: Vec<_> = line.split(' ').collect();
        let command = words[0];
        if command == "CANDIDATES" {
            let names = &words[1..];
            if names.len() == 1 { return Err("too few candidates".into()); }
            for (i, &name) in names.iter().enumerate() {
                if names[..i].contains(&name) { return Err(format!("duplicate candidate {name}")); }
            }
            self.number += 1;
            self.election = Some(Election::new(self.number, names.iter().map(|name| (*name).to_owned()).collect()));
            return Ok(vec![format!("election {}: {} candidates", self.number, names.len())]);
        }
        let e = self.election.as_mut().ok_or_else(|| "no election".to_owned())?;
        match command {
            "BALLOT" => {
                let ranking = if words[2] == "-" { Vec::new() }
                    else { e.checked_names(&words[2].split('>').collect::<Vec<_>>())? };
                let votes = words[1].parse().unwrap();
                e.groups.push(Ballot { votes, ranking });
                e.total += votes;
                e.finish_entry();
                return Ok(Vec::new());
            }
            "RANDOM" => {
                let count: usize = words[1].parse().unwrap();
                let mut state: i64 = words[2].parse().unwrap();
                for _ in 0..count {
                    let mut ranking = members(e.active);
                    for i in (1..ranking.len()).rev() {
                        state = 48271 * state % 2147483647;
                        ranking.swap(i, (state % (i as i64 + 1)) as usize);
                    }
                    state = 48271 * state % 2147483647;
                    ranking.truncate((state % ranking.len() as i64) as usize + 1);
                    e.groups.push(Ballot { votes: 1, ranking });
                }
                e.total += count as i32;
                e.finish_entry();
                return Ok(Vec::new());
            }
            "UNDO" => {
                e.entry_ends.pop().ok_or_else(|| "nothing to undo".to_owned())?;
                let end = e.entry_ends.last().copied().unwrap_or(0);
                e.total -= e.groups[end..].iter().map(|group| group.votes).sum::<i32>();
                e.groups.truncate(end);
                e.invalidate();
                return Ok(Vec::new());
            }
            "WITHDRAW" | "RESTORE" => {
                let a = e.candidate(words[1])?;
                let active = e.active & bit(a) != 0;
                if command == "WITHDRAW" {
                    if !active { return Err(format!("already withdrawn {}", words[1])); }
                    if e.active.count_ones() <= 2 { return Err("too few candidates".into()); }
                    e.active &= !bit(a);
                } else {
                    if active { return Err(format!("not withdrawn {}", words[1])); }
                    e.active |= bit(a);
                }
                return Ok(Vec::new());
            }
            "TIEBREAK" => {
                let order = e.checked_names(&words[1..])?;
                if order.len() != e.names.len() { return Err("incomplete tiebreak".into()); }
                for (i, &a) in order.iter().enumerate() { e.priority[a] = i; }
                e.tiebreak = order;
                return Ok(Vec::new());
            }
            "STATUS" => {
                let withdrawn = members((bit(e.names.len()) - 1) & !e.active);
                return Ok(vec![format!("[{line}]"), format!("election {}", e.number),
                    format!("active: {}", e.names_text(&members(e.active), ", ")),
                    format!("withdrawn: {}", if withdrawn.is_empty() { "none".into() } else { e.names_text(&withdrawn, ", ") }),
                    format!("tiebreak: {}", e.names_text(&e.tiebreak, ", ")),
                    format!("ballots: {} in {} entries", e.total, e.entry_ends.len()),
                ]);
            }
            _ => {}
        }
        if e.entry_ends.is_empty() { return Err("no ballots".into()); }
        let requested = if matches!(command, "RANKING" | "SPOILERS") {
            let method = Method::parse(&words[1..]);
            if !method.rankable() { return Err("not rankable".into()); }
            if command == "SPOILERS" && e.active.count_ones() < 3 { return Err("too few candidates".into()); }
            Some(method)
        } else { None };
        let mut compared = [0; 2];
        if command == "COMPARE" {
            for i in 0..2 {
                compared[i] = e.candidate(words[i + 1])?;
                if e.active & bit(compared[i]) == 0 { return Err(format!("withdrawn candidate {}", words[i + 1])); }
            }
            if compared[0] == compared[1] { return Err("same candidate".into()); }
        }
        if command == "STV" && words[1].parse::<u32>().unwrap() >= e.active.count_ones() { return Err("too many seats".into()); }
        let mut lines = vec![format!("[{line}]")];
        match command {
            "RANKING" | "SPOILERS" => {
                let method = requested.unwrap();
                let result = e.tally(e.active, method);
                if command == "RANKING" { lines.push(e.names_text(&result.order, " > ")); }
                else {
                    let win = result.order[0];
                    lines.push(format!("winner: {}", e.names[win]));
                    for a in members(e.active) { if a != win {
                        let other = e.tally(e.active & !bit(a), method).order[0];
                        lines.push(format!("without {}: {}{}", e.names[a], e.names[other], if other != win { " (changed)" } else { "" }));
                    } }
                }
            }
            "BALLOTS" => lines.extend(e.ballots_report()),
            "PROFILE" => {
                let scores = e.tallies(e.active);
                let size = e.active.count_ones() as usize;
                for a in members(e.active) {
                    let counts: Vec<_> = (0..size).map(|j| {
                        (scores.approval[j][a] - if j == 0 { 0 } else { scores.approval[j - 1][a] }).to_string()
                    }).collect();
                    lines.push(format!("{}: {} unranked {}", e.names[a], counts.join(" "), e.total - scores.approval[size - 1][a]));
                }
            }
            "PAIRWISE" => {
                let matrix = e.pairwise();
                lines.extend(e.pair_lines(e.active, &matrix));
            }
            "EXHAUSTED" => lines.extend(e.elimination(e.active, false, true).lines),
            "SUMMARY" | "COMPARE" => {
                let mut wins = [0; LIMIT];
                let mut ahead = [Vec::new(), Vec::new()];
                for method in SUMMARY {
                    let result = e.tally(e.active, method);
                    if command == "SUMMARY" {
                        let win = result.order[0];
                        wins[win] += 1;
                        lines.push(format!("{method}: {}", e.names[win]));
                    } else {
                        let first = result.order.iter().position(|&a| a == compared[0]).unwrap();
                        let second = result.order.iter().position(|&a| a == compared[1]).unwrap();
                        let side = if first < second { 0 } else { 1 };
                        ahead[side].push(method.to_string());
                    }
                }
                if command == "SUMMARY" { lines.push(format!("wins: {}", e.values(e.active, &wins, false))); }
                else {
                    let matrix = e.pairwise();
                    let [a, b] = compared;
                    lines.push(format!("{} {}, {} {}, neither {}", e.names[a], matrix[a][b], e.names[b], matrix[b][a], e.total - matrix[a][b] - matrix[b][a]));
                    for i in 0..2 {
                        lines.push(format!("{} ahead: {}", e.names[compared[i]], if ahead[i].is_empty() { "none".into() } else { ahead[i].join(", ") }));
                    }
                }
            }
            _ => lines.extend(e.tally(e.active, Method::parse(&words)).lines),
        }
        Ok(lines)
    }
}

fn main() {
    let stdin = io::stdin();
    let mut input = stdin.lock().lines();
    let count: usize = input.next().unwrap().unwrap().parse().unwrap();
    let stdout = io::stdout();
    let mut output = io::BufWriter::new(stdout.lock());
    let mut lab = Lab::default();
    for _ in 0..count {
        let line = input.next().unwrap().unwrap();
        match lab.execute(&line) {
            Ok(lines) => for row in lines { writeln!(output, "{row}").unwrap(); },
            Err(reason) => writeln!(output, "ERROR {reason}").unwrap(),
        }
    }
}
