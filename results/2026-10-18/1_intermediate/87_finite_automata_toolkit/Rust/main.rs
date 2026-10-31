use std::collections::{BTreeMap, BTreeSet, VecDeque};
use std::io::{self, Read};

#[derive(Clone)]
struct Automaton {
    dfa: bool,
    states: Vec<String>,
    alphabet: Vec<char>,
    start: usize,
    accepting: BTreeSet<usize>,
    transitions: BTreeSet<(usize, char, usize)>,
}
impl Automaton {
    fn summary(&self, name: &str) -> String {
        format!(
            "{} {}: alphabet={} states={} accepting={} transitions={}",
            if self.dfa { "DFA" } else { "NFA" },
            name,
            self.alphabet.iter().collect::<String>(),
            self.states.len(),
            self.accepting.len(),
            self.transitions.len()
        )
    }
    fn generated(dfa: bool, prefix: &str, size: usize, alphabet: &[char], start: usize) -> Self {
        Self {
            dfa,
            states: (0..size).map(|i| format!("{}{}", prefix, i)).collect(),
            alphabet: alphabet.to_vec(),
            start,
            accepting: BTreeSet::new(),
            transitions: BTreeSet::new(),
        }
    }
    fn direct(&self, p: usize, c: char) -> BTreeSet<usize> {
        self.transitions
            .range((p, c, 0)..=(p, c, usize::MAX))
            .map(|(_, _, q)| *q)
            .collect()
    }
    fn delta(&self, p: usize, c: char) -> usize {
        self.transitions
            .range((p, c, 0)..=(p, c, usize::MAX))
            .next()
            .unwrap()
            .2
    }
    fn closure(&self, states: &BTreeSet<usize>) -> BTreeSet<usize> {
        let mut result = states.clone();
        let mut queue: VecDeque<usize> = states.iter().copied().collect();
        while let Some(p) = queue.pop_front() {
            for q in self.direct(p, 'e') {
                if result.insert(q) {
                    queue.push_back(q);
                }
            }
        }
        result
    }
    fn initial(&self) -> BTreeSet<usize> {
        self.closure(&BTreeSet::from([self.start]))
    }
    fn destination(&self, states: &BTreeSet<usize>, c: char) -> BTreeSet<usize> {
        let next = states.iter().flat_map(|p| self.direct(*p, c)).collect();
        self.closure(&next)
    }
    fn accepted(&self, states: &BTreeSet<usize>) -> bool {
        !states.is_disjoint(&self.accepting)
    }
    fn set_text(&self, states: &BTreeSet<usize>) -> String {
        format!(
            "{{{}}}",
            states
                .iter()
                .map(|i| self.states[*i].as_str())
                .collect::<Vec<_>>()
                .join(",")
        )
    }
    fn list_text(&self, states: &BTreeSet<usize>) -> String {
        if states.is_empty() {
            "none".into()
        } else {
            states
                .iter()
                .map(|i| self.states[*i].as_str())
                .collect::<Vec<_>>()
                .join(",")
        }
    }
    fn determinize(&self) -> (Self, Vec<String>) {
        let mut sets = vec![self.initial()];
        let mut index = BTreeMap::from([(sets[0].clone(), 0)]);
        let mut transitions = BTreeSet::new();
        let mut i = 0;
        while i < sets.len() {
            for &c in &self.alphabet {
                let next = self.destination(&sets[i], c);
                let j = if let Some(&j) = index.get(&next) {
                    j
                } else {
                    let j = sets.len();
                    index.insert(next.clone(), j);
                    sets.push(next);
                    j
                };
                transitions.insert((i, c, j));
            }
            i += 1;
        }
        let mut result = Self::generated(true, "D", sets.len(), &self.alphabet, 0);
        result.transitions = transitions;
        result.accepting = sets
            .iter()
            .enumerate()
            .filter(|(_, s)| self.accepted(s))
            .map(|(i, _)| i)
            .collect();
        let details = sets
            .iter()
            .enumerate()
            .map(|(i, s)| format!("  D{} = {}", i, self.set_text(s)))
            .collect();
        (result, details)
    }
    fn reachable(&self, reverse: bool) -> BTreeSet<usize> {
        let mut result = if reverse {
            self.accepting.clone()
        } else {
            BTreeSet::from([self.start])
        };
        let mut queue: VecDeque<usize> = result.iter().copied().collect();
        while let Some(s) = queue.pop_front() {
            for &(p, _, q) in &self.transitions {
                if (if reverse { q } else { p }) == s {
                    let next = if reverse { p } else { q };
                    if result.insert(next) {
                        queue.push_back(next);
                    }
                }
            }
        }
        result
    }
    fn minimize(&self) -> (Self, Vec<String>) {
        let reachable = self.reachable(false);
        let unreachable = (0..self.states.len())
            .filter(|i| !reachable.contains(i))
            .collect();
        let mut details = vec![format!("  unreachable: {}", self.list_text(&unreachable))];
        let mut blocks: Vec<BTreeSet<usize>> = [true, false]
            .iter()
            .map(|accept| {
                reachable
                    .iter()
                    .copied()
                    .filter(|s| self.accepting.contains(s) == *accept)
                    .collect::<BTreeSet<_>>()
            })
            .filter(|b| !b.is_empty())
            .collect();
        blocks.sort_by_key(|b| *b.first().unwrap());
        let partition = |blocks: &[BTreeSet<usize>]| {
            blocks
                .iter()
                .map(|b| self.set_text(b))
                .collect::<Vec<_>>()
                .join(" ")
        };
        details.push(format!("  round 0: {}", partition(&blocks)));
        let mut round = 1;
        loop {
            let mut group = vec![0; self.states.len()];
            for (i, b) in blocks.iter().enumerate() {
                for &s in b {
                    group[s] = i;
                }
            }
            let mut split: BTreeMap<Vec<usize>, BTreeSet<usize>> = BTreeMap::new();
            for &s in &reachable {
                let mut key = vec![group[s]];
                key.extend(self.alphabet.iter().map(|c| group[self.delta(s, *c)]));
                split.entry(key).or_default().insert(s);
            }
            let mut next: Vec<BTreeSet<usize>> = split.into_values().collect();
            next.sort_by_key(|b| *b.first().unwrap());
            if next.len() == blocks.len() {
                break;
            }
            blocks = next;
            details.push(format!("  round {}: {}", round, partition(&blocks)));
            round += 1;
        }
        let mut group = vec![0; self.states.len()];
        for (i, b) in blocks.iter().enumerate() {
            for &s in b {
                group[s] = i;
            }
        }
        let mut sequence = vec![group[self.start]];
        let mut names = BTreeMap::from([(sequence[0], 0)]);
        let mut transitions = BTreeSet::new();
        let mut i = 0;
        while i < sequence.len() {
            let s = *blocks[sequence[i]].first().unwrap();
            for &c in &self.alphabet {
                let b = group[self.delta(s, c)];
                let j = if let Some(&j) = names.get(&b) {
                    j
                } else {
                    let j = sequence.len();
                    names.insert(b, j);
                    sequence.push(b);
                    j
                };
                transitions.insert((i, c, j));
            }
            i += 1;
        }
        let mut result = Self::generated(true, "M", sequence.len(), &self.alphabet, 0);
        result.transitions = transitions;
        for (i, &b) in sequence.iter().enumerate() {
            if self.accepted(&blocks[b]) {
                result.accepting.insert(i);
            }
            details.push(format!("  M{} = {}", i, self.set_text(&blocks[b])));
        }
        (result, details)
    }
    fn product(&self, other: &Self, command: &str) -> (Self, Vec<String>) {
        let mut pairs = vec![(self.start, other.start)];
        let mut index = BTreeMap::from([(pairs[0], 0)]);
        let mut transitions = BTreeSet::new();
        let mut i = 0;
        while i < pairs.len() {
            for &c in &self.alphabet {
                let pair = (self.delta(pairs[i].0, c), other.delta(pairs[i].1, c));
                let j = if let Some(&j) = index.get(&pair) {
                    j
                } else {
                    let j = pairs.len();
                    index.insert(pair, j);
                    pairs.push(pair);
                    j
                };
                transitions.insert((i, c, j));
            }
            i += 1;
        }
        let mut result = Self::generated(true, "P", pairs.len(), &self.alphabet, 0);
        result.transitions = transitions;
        let mut details = Vec::new();
        for (i, &(p, q)) in pairs.iter().enumerate() {
            let a = self.accepting.contains(&p);
            let b = other.accepting.contains(&q);
            if match command {
                "UNION" => a || b,
                "INTERSECT" => a && b,
                _ => a && !b,
            } {
                result.accepting.insert(i);
            }
            details.push(format!(
                "  P{} = ({},{})",
                i, self.states[p], other.states[q]
            ));
        }
        (result, details)
    }
    fn smallest(&self) -> Option<String> {
        let mut queue = VecDeque::from([(self.start, String::new())]);
        let mut seen = BTreeSet::from([self.start]);
        while let Some((s, word)) = queue.pop_front() {
            if self.accepting.contains(&s) {
                return Some(word);
            }
            for &c in &self.alphabet {
                let q = self.delta(s, c);
                if seen.insert(q) {
                    queue.push_back((q, word.clone() + &c.to_string()));
                }
            }
        }
        None
    }
    fn language(&self, counting: bool) -> Option<i64> {
        let live = self.reachable(true);
        let mut color = vec![0; self.states.len()];
        let mut counts = vec![0; self.states.len()];

        fn visit(
            a: &Automaton,
            s: usize,
            live: &BTreeSet<usize>,
            color: &mut [u8],
            counts: &mut [i64],
            counting: bool,
        ) -> Option<i64> {
            if !live.contains(&s) {
                return Some(0);
            }
            if color[s] == 1 {
                return None;
            }
            if color[s] == 2 {
                return Some(counts[s]);
            }
            color[s] = 1;
            let mut count = if a.accepting.contains(&s) { 1 } else { 0 };
            for &c in &a.alphabet {
                let n = visit(a, a.delta(s, c), live, color, counts, counting)?;
                if counting {
                    count += n;
                }
            }
            color[s] = 2;
            counts[s] = if counting { count } else { 1 };
            Some(counts[s])
        }
        visit(self, self.start, &live, &mut color, &mut counts, counting)
    }
    fn count(&self, n: usize) -> i64 {
        let mut counts = vec![0; self.states.len()];
        counts[self.start] = 1;
        for _ in 0..n {
            let mut next = vec![0; counts.len()];
            for (s, &count) in counts.iter().enumerate() {
                for &c in &self.alphabet {
                    next[self.delta(s, c)] += count;
                }
            }
            counts = next;
        }
        self.accepting.iter().map(|s| counts[*s]).sum()
    }
    fn enumerate(&self, limit: usize) -> String {
        let mut queue = VecDeque::from([(self.start, String::new())]);
        let mut count = 0;
        let mut first = Vec::new();
        while let Some((s, word)) = queue.pop_front() {
            if self.accepting.contains(&s) {
                count += 1;
                if first.len() < 50 {
                    first.push(display_word(&word));
                }
            }
            if word.len() < limit {
                for &c in &self.alphabet {
                    queue.push_back((self.delta(s, c), word.clone() + &c.to_string()));
                }
            }
        }
        format!(
            "{}{}{}",
            count,
            if first.is_empty() {
                String::new()
            } else {
                " ".to_string() + &first.join(" ")
            },
            if count > 50 { " ..." } else { "" }
        )
    }
    fn synchronize(&self) -> String {
        let initial = (0..self.states.len()).collect::<BTreeSet<_>>();
        let mut seen = BTreeSet::from([initial.clone()]);
        let mut queue = VecDeque::from([(initial, String::new())]);
        while let Some((set, word)) = queue.pop_front() {
            if set.len() == 1 {
                return format!(
                    "SYNCHRONIZING {} -> {}",
                    display_word(&word),
                    self.states[*set.first().unwrap()]
                );
            }
            for &c in &self.alphabet {
                let next: BTreeSet<usize> = set.iter().map(|s| self.delta(*s, c)).collect();
                if seen.insert(next.clone()) {
                    queue.push_back((next, word.clone() + &c.to_string()));
                }
            }
        }
        "NOT SYNCHRONIZING".into()
    }
    fn table(&self) -> Vec<String> {
        let mut symbols = self.alphabet.clone();
        if !self.dfa && self.transitions.iter().any(|(_, c, _)| *c == 'e') {
            symbols.push('e');
        }
        let mut rows = vec![
            std::iter::once(String::new())
                .chain(symbols.iter().map(char::to_string))
                .collect::<Vec<_>>(),
        ];
        for p in 0..self.states.len() {
            let mut row = vec![format!(
                "{}{}{}",
                if p == self.start { "->" } else { "  " },
                if self.accepting.contains(&p) {
                    "*"
                } else {
                    " "
                },
                self.states[p]
            )];
            for &c in &symbols {
                let set = self.direct(p, c);
                row.push(if self.dfa {
                    self.states[*set.first().unwrap()].clone()
                } else if set.is_empty() {
                    "-".into()
                } else {
                    self.set_text(&set)
                });
            }
            rows.push(row);
        }
        let widths: Vec<usize> = (0..rows[0].len())
            .map(|i| rows.iter().map(|r| r[i].len()).max().unwrap())
            .collect();
        rows.iter()
            .map(|r| {
                r.iter()
                    .enumerate()
                    .map(|(i, s)| format!("{:<width$}", s, width = widths[i]))
                    .collect::<Vec<_>>()
                    .join("  ")
                    .trim_end()
                    .into()
            })
            .collect()
    }
    fn show(&self, name: &str) -> String {
        let accepting = if self.accepting.is_empty() {
            "-".into()
        } else {
            self.list_text(&self.accepting)
        };
        let mut words = vec![
            if self.dfa { "DFA".into() } else { "NFA".into() },
            name.into(),
            self.states.join(","),
            self.alphabet.iter().collect(),
            self.states[self.start].clone(),
            accepting,
        ];
        let mut symbols = self.alphabet.clone();
        symbols.push('e');
        for p in 0..self.states.len() {
            for &c in &symbols {
                for q in self.direct(p, c) {
                    words.push(format!("{}:{}:{}", self.states[p], c, self.states[q]));
                }
            }
        }
        words.join(" ")
    }
}
fn display_word(word: &str) -> String {
    if word.is_empty() {
        "e".into()
    } else {
        word.into()
    }
}
enum Regex {
    Symbol(char),
    Sequence(Vec<Regex>),
    Alternatives(Vec<Regex>),
    Postfix(char, Box<Regex>),
}
struct RegexParser {
    text: Vec<char>,
    at: usize,
}
impl RegexParser {
    fn peek(&self) -> char {
        self.text.get(self.at).copied().unwrap_or('\0')
    }
    fn error(&self) -> String {
        format!("syntax error at {}", self.at + 1)
    }
    fn atom(&mut self) -> Result<Regex, String> {
        let c = self.peek();
        if c.is_ascii_lowercase() || c.is_ascii_digit() {
            self.at += 1;
            return Ok(Regex::Symbol(c));
        }
        if c == '(' {
            self.at += 1;
            let r = self.alternation()?;
            if self.peek() != ')' {
                return Err(self.error());
            }
            self.at += 1;
            return Ok(r);
        }
        Err(self.error())
    }
    fn factor(&mut self) -> Result<Regex, String> {
        let mut r = self.atom()?;
        while ['*', '+', '?'].contains(&self.peek()) {
            let c = self.peek();
            self.at += 1;
            r = Regex::Postfix(c, Box::new(r));
        }
        Ok(r)
    }
    fn sequence(&mut self) -> Result<Regex, String> {
        let mut list = vec![self.factor()?];
        while self.peek().is_ascii_lowercase() || self.peek().is_ascii_digit() || self.peek() == '('
        {
            list.push(self.factor()?);
        }
        Ok(if list.len() == 1 {
            list.pop().unwrap()
        } else {
            Regex::Sequence(list)
        })
    }
    fn alternation(&mut self) -> Result<Regex, String> {
        let mut list = vec![self.sequence()?];
        while self.peek() == '|' {
            self.at += 1;
            list.push(self.sequence()?);
        }
        Ok(if list.len() == 1 {
            list.pop().unwrap()
        } else {
            Regex::Alternatives(list)
        })
    }
}
fn regex_automaton(alphabet: &[char], text: &str) -> Result<Automaton, String> {
    for c in text.chars() {
        if (c.is_ascii_lowercase() || c.is_ascii_digit()) && c != 'e' && !alphabet.contains(&c) {
            return Err(format!("unknown symbol {}", c));
        }
    }
    let mut parser = RegexParser {
        text: text.chars().collect(),
        at: 0,
    };
    let tree = parser.alternation()?;
    if parser.at != parser.text.len() {
        return Err(parser.error());
    }
    fn build(
        r: &Regex,
        size: &mut usize,
        transitions: &mut BTreeSet<(usize, char, usize)>,
    ) -> (usize, usize) {
        fn state(size: &mut usize) -> usize {
            let s = *size;
            *size += 1;
            s
        }
        match r {
            Regex::Symbol(c) => {
                let s = state(size);
                let f = state(size);
                transitions.insert((s, *c, f));
                (s, f)
            }
            Regex::Sequence(list) => {
                let parts: Vec<(usize, usize)> =
                    list.iter().map(|r| build(r, size, transitions)).collect();
                for pair in parts.windows(2) {
                    transitions.insert((pair[0].1, 'e', pair[1].0));
                }
                (parts[0].0, parts.last().unwrap().1)
            }
            Regex::Alternatives(list) => {
                let s = state(size);
                let parts: Vec<(usize, usize)> =
                    list.iter().map(|r| build(r, size, transitions)).collect();
                let f = state(size);
                for (a, b) in parts {
                    transitions.insert((s, 'e', a));
                    transitions.insert((b, 'e', f));
                }
                (s, f)
            }
            Regex::Postfix(op, r) => {
                let s = state(size);
                let (a, b) = build(r, size, transitions);
                let f = state(size);
                transitions.insert((s, 'e', a));
                transitions.insert((b, 'e', f));
                if *op != '?' {
                    transitions.insert((b, 'e', a));
                }
                if *op != '+' {
                    transitions.insert((s, 'e', f));
                }
                (s, f)
            }
        }
    }
    let mut size = 0;
    let mut transitions = BTreeSet::new();
    let (s, f) = build(&tree, &mut size, &mut transitions);
    let mut a = Automaton::generated(false, "N", size, alphabet, s);
    a.accepting.insert(f);
    a.transitions = transitions;
    Ok(a)
}
struct Toolkit {
    table: Vec<(String, Automaton)>,
}
impl Toolkit {
    fn find(&self, name: &str) -> Result<usize, String> {
        self.table
            .iter()
            .position(|(n, _)| n == name)
            .ok_or_else(|| format!("unknown automaton {}", name))
    }
    fn fresh(&self, name: &str) -> Result<(), String> {
        if self.table.iter().any(|(n, _)| n == name) {
            Err(format!("{} already exists", name))
        } else {
            Ok(())
        }
    }
    fn register(&mut self, name: &str, a: Automaton, mut details: Vec<String>) -> Vec<String> {
        let mut out = vec![a.summary(name)];
        out.append(&mut details);
        self.table.push((name.into(), a));
        out
    }
    fn define(&mut self, dfa: bool, args: &[&str]) -> Result<Vec<String>, String> {
        if args.len() < 5 {
            return Err("wrong number of arguments".into());
        }
        self.fresh(args[0])?;
        let mut states = Vec::new();
        for name in args[1].split(',') {
            if states.contains(&name.to_string()) {
                return Err(format!("duplicate state {}", name));
            }
            states.push(name.to_string());
        }
        let state = |name: &str| {
            states
                .iter()
                .position(|s| s == name)
                .ok_or_else(|| format!("unknown state {}", name))
        };
        let start = state(args[3])?;
        let mut accepting = BTreeSet::new();
        if args[4] != "-" {
            for name in args[4].split(',') {
                let s = state(name)?;
                if !accepting.insert(s) {
                    return Err(format!("duplicate state {}", name));
                }
            }
        }
        let alphabet: Vec<char> = args[2]
            .chars()
            .collect::<BTreeSet<_>>()
            .into_iter()
            .collect();
        let mut transitions = BTreeSet::new();
        for word in &args[5..] {
            let parts: Vec<&str> = word.split(':').collect();
            let p = state(parts[0])?;
            let c = parts[1].chars().next().unwrap();
            if c == 'e' && dfa {
                return Err("epsilon transition in DFA".into());
            }
            if c != 'e' && !alphabet.contains(&c) {
                return Err(format!("unknown symbol {}", c));
            }
            let q = state(parts[2])?;
            if transitions.contains(&(p, c, q)) {
                return Err(format!("duplicate transition {}", word));
            }
            if dfa && transitions.iter().any(|(s, a, _)| *s == p && *a == c) {
                return Err(format!("conflicting transition {}", word));
            }
            transitions.insert((p, c, q));
        }
        if dfa {
            for p in 0..states.len() {
                for &c in &alphabet {
                    if !transitions.iter().any(|(s, a, _)| *s == p && *a == c) {
                        return Err(format!("missing transition {}:{}", states[p], c));
                    }
                }
            }
        }
        Ok(self.register(
            args[0],
            Automaton {
                dfa,
                states,
                alphabet,
                start,
                accepting,
                transitions,
            },
            Vec::new(),
        ))
    }
    fn command(&mut self, line: &str) -> Result<Vec<String>, String> {
        let words: Vec<&str> = line.split(' ').collect();
        let c = words[0];
        let args = &words[1..];
        let count = match c {
            "DFA" | "NFA" => return self.define(c == "DFA", args),
            "REGEX" => {
                if args.len() != 3 {
                    return Err("wrong number of arguments".into());
                }
                self.fresh(args[0])?;
                let alphabet = args[1]
                    .chars()
                    .collect::<BTreeSet<_>>()
                    .into_iter()
                    .collect::<Vec<_>>();
                let a = regex_automaton(&alphabet, args[2])?;
                return Ok(self.register(args[0], a, Vec::new()));
            }
            "ACCEPT" | "CLOSURE" | "TODFA" | "EPSFREE" | "MINIMIZE" | "EQUIV" | "COMPLEMENT"
            | "REVERSE" | "STAR" | "ENUM" | "COUNT" => 2,
            "UNION" | "INTERSECT" | "DIFF" | "CONCAT" => 3,
            "EMPTY" | "FINITE" | "INFO" | "TABLE" | "SHOW" | "SYNC" | "DELETE" => 1,
            "LIST" => 0,
            _ => return Err(format!("unknown command {}", c)),
        };
        if args.len() != count {
            return Err("wrong number of arguments".into());
        }
        if c == "LIST" {
            return Ok(if self.table.is_empty() {
                vec!["(none)".into()]
            } else {
                self.table.iter().map(|(n, a)| a.summary(n)).collect()
            });
        }
        let first = self.find(args[0])?;
        let two = ["EQUIV", "UNION", "INTERSECT", "DIFF", "CONCAT"].contains(&c);
        let second = if two { Some(self.find(args[1])?) } else { None };
        let creates = [
            "TODFA",
            "EPSFREE",
            "MINIMIZE",
            "UNION",
            "INTERSECT",
            "DIFF",
            "COMPLEMENT",
            "REVERSE",
            "CONCAT",
            "STAR",
        ]
        .contains(&c);
        if creates {
            self.fresh(args[args.len() - 1])?;
        }
        let a = self.table[first].1.clone();
        let b = second.map(|i| self.table[i].1.clone());
        if [
            "MINIMIZE",
            "COMPLEMENT",
            "UNION",
            "INTERSECT",
            "DIFF",
            "SYNC",
        ]
        .contains(&c)
        {
            if !a.dfa {
                return Err(format!("{} is not a DFA", args[0]));
            }
            if two && !b.as_ref().unwrap().dfa {
                return Err(format!("{} is not a DFA", args[1]));
            }
        }
        if two && a.alphabet != b.as_ref().unwrap().alphabet {
            return Err("alphabets differ".into());
        }
        if c == "DELETE" {
            self.table.remove(first);
            return Ok(vec![format!("deleted {}", args[0])]);
        }
        if c == "ACCEPT" {
            let word = if args[1] == "e" { "" } else { args[1] };
            for ch in word.chars() {
                if !a.alphabet.contains(&ch) {
                    return Err(format!("unknown symbol {}", ch));
                }
            }
            let mut set = a.initial();
            let format_set = |s: &BTreeSet<usize>| {
                if a.dfa {
                    a.states[*s.first().unwrap()].clone()
                } else {
                    a.set_text(s)
                }
            };
            let mut path = format_set(&set);
            for ch in word.chars() {
                set = a.destination(&set, ch);
                path += &format!(" -{}-> {}", ch, format_set(&set));
            }
            return Ok(vec![format!(
                "{} {}",
                if a.accepted(&set) { "ACCEPT" } else { "REJECT" },
                path
            )]);
        }
        if c == "CLOSURE" {
            let mut set = BTreeSet::new();
            for name in args[1].split(',') {
                set.insert(
                    a.states
                        .iter()
                        .position(|s| s == name)
                        .ok_or_else(|| format!("unknown state {}", name))?,
                );
            }
            return Ok(vec![a.set_text(&a.closure(&set))]);
        }
        if c == "TABLE" {
            return Ok(a.table());
        }
        if c == "SHOW" {
            return Ok(vec![a.show(args[0])]);
        }
        if c == "SYNC" {
            return Ok(vec![a.synchronize()]);
        }
        if c == "EQUIV" {
            let x = a.determinize().0;
            let z = b.unwrap().determinize().0;
            let mut queue = VecDeque::from([((x.start, z.start), String::new())]);
            let mut seen = BTreeSet::from([(x.start, z.start)]);
            while let Some(((p, q), word)) = queue.pop_front() {
                let xp = x.accepting.contains(&p);
                let zq = z.accepting.contains(&q);
                if xp != zq {
                    return Ok(vec![format!(
                        "NOT EQUIVALENT: {} is accepted only by {}",
                        display_word(&word),
                        if xp { args[0] } else { args[1] }
                    )]);
                }
                for &ch in &x.alphabet {
                    let pair = (x.delta(p, ch), z.delta(q, ch));
                    if seen.insert(pair) {
                        queue.push_back((pair, word.clone() + &ch.to_string()));
                    }
                }
            }
            return Ok(vec!["EQUIVALENT".into()]);
        }
        if ["ENUM", "COUNT", "EMPTY", "FINITE", "INFO"].contains(&c) {
            let d = a.determinize().0;
            return Ok(match c {
                "ENUM" => vec![d.enumerate(args[1].parse().unwrap())],
                "COUNT" => vec![d.count(args[1].parse().unwrap()).to_string()],
                "EMPTY" => vec![d.smallest().map_or("EMPTY".into(), |w| {
                    format!("NOT EMPTY {}", display_word(&w))
                })],
                "FINITE" => vec![
                    d.language(true)
                        .map_or("INFINITE".into(), |n| format!("FINITE {}", n)),
                ],
                _ => {
                    let deterministic = !a.transitions.iter().any(|(_, ch, _)| *ch == 'e')
                        && (0..a.states.len())
                            .all(|s| a.alphabet.iter().all(|ch| a.direct(s, *ch).len() <= 1));
                    let complete = (0..a.states.len())
                        .all(|s| a.alphabet.iter().all(|ch| !a.direct(s, *ch).is_empty()));
                    let language = match d.language(false) {
                        None => "infinite",
                        Some(0) => "empty",
                        Some(_) => "finite",
                    };
                    vec![
                        a.summary(args[0]),
                        format!(
                            "  epsilon transitions: {}",
                            a.transitions.iter().filter(|(_, ch, _)| *ch == 'e').count()
                        ),
                        format!("  reachable: {}", a.list_text(&a.reachable(false))),
                        format!("  live: {}", a.list_text(&a.reachable(true))),
                        format!(
                            "  deterministic: {}",
                            if deterministic { "yes" } else { "no" }
                        ),
                        format!("  complete: {}", if complete { "yes" } else { "no" }),
                        format!("  language: {}", language),
                        format!("  minimal DFA states: {}", d.minimize().0.states.len()),
                    ]
                }
            });
        }
        let (result, details) = match c {
            "TODFA" => a.determinize(),
            "MINIMIZE" => a.minimize(),
            "UNION" | "INTERSECT" | "DIFF" => a.product(b.as_ref().unwrap(), c),
            "COMPLEMENT" => {
                let mut r = a.clone();
                r.accepting = (0..r.states.len())
                    .filter(|s| !a.accepting.contains(s))
                    .collect();
                (r, Vec::new())
            }
            "EPSFREE" => {
                let mut r = a.clone();
                r.dfa = false;
                r.transitions.clear();
                r.accepting.clear();
                for p in 0..a.states.len() {
                    let closure = a.closure(&BTreeSet::from([p]));
                    if a.accepted(&closure) {
                        r.accepting.insert(p);
                    }
                    for &ch in &a.alphabet {
                        for q in a.destination(&closure, ch) {
                            r.transitions.insert((p, ch, q));
                        }
                    }
                }
                (r, Vec::new())
            }
            "REVERSE" | "STAR" => {
                let mut r = Automaton::generated(false, "N", a.states.len() + 1, &a.alphabet, 0);
                if c == "REVERSE" {
                    for &(p, ch, q) in &a.transitions {
                        r.transitions.insert((q + 1, ch, p + 1));
                    }
                    for &p in &a.accepting {
                        r.transitions.insert((0, 'e', p + 1));
                    }
                    r.accepting.insert(a.start + 1);
                } else {
                    for &(p, ch, q) in &a.transitions {
                        r.transitions.insert((p + 1, ch, q + 1));
                    }
                    r.transitions.insert((0, 'e', a.start + 1));
                    r.accepting.insert(0);
                    for &p in &a.accepting {
                        r.transitions.insert((p + 1, 'e', a.start + 1));
                        r.accepting.insert(p + 1);
                    }
                }
                (r, Vec::new())
            }
            "CONCAT" => {
                let b = b.unwrap();
                let offset = a.states.len();
                let mut r =
                    Automaton::generated(false, "N", offset + b.states.len(), &a.alphabet, a.start);
                r.transitions = a.transitions.clone();
                for &(p, ch, q) in &b.transitions {
                    r.transitions.insert((p + offset, ch, q + offset));
                }
                for &p in &a.accepting {
                    r.transitions.insert((p, 'e', b.start + offset));
                }
                r.accepting = b.accepting.iter().map(|p| p + offset).collect();
                (r, Vec::new())
            }
            _ => unreachable!(),
        };
        Ok(self.register(args[args.len() - 1], result, details))
    }
}
fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut lines = input.lines();
    let count: usize = lines.next().unwrap().parse().unwrap();
    let mut toolkit = Toolkit { table: Vec::new() };
    for line in lines.take(count) {
        if line.starts_with('#') {
            continue;
        }
        match toolkit.command(line) {
            Ok(out) => {
                for line in out {
                    println!("{}", line);
                }
            }
            Err(e) => println!("error: {}", e),
        }
    }
}
