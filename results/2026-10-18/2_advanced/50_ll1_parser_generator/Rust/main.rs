mod grammar_parser;
mod transform;
mod first_follow;
mod table;
mod driver;

use grammar_parser::{Grammar, nonterminal, notation, production};
use first_follow::Sets;
use table::{Production, Table};
use driver::{Action, Parse};
use std::{collections::{BTreeMap, BTreeSet, VecDeque}, fs, io};

fn terminals(grammar: &Grammar) -> BTreeSet<String> {
    grammar.rules.values().flat_map(|r| r.iter().flat_map(|rhs| rhs.iter().filter(|s| !nonterminal(s)).cloned())).collect()
}

fn terminal_order(values: &BTreeSet<String>) -> Vec<String> {
    let mut result: Vec<String> = values.iter().filter(|s| s.as_str() != "$").cloned().collect();
    if values.contains("$") { result.push("$".into()); }
    result
}

fn heading(head: &str, items: &[String]) -> String {
    if items.is_empty() { head.into() } else { format!("{} {}", head, items.join(" ")) }
}

fn numbers(indices: &[usize]) -> Vec<String> {
    indices.iter().map(|i| (i + 1).to_string()).collect()
}

fn reachable(grammar: &Grammar) -> BTreeSet<String> {
    let mut seen = BTreeSet::from([grammar.start.clone()]);
    let mut queue = VecDeque::from([grammar.start.clone()]);
    while let Some(a) = queue.pop_front() {
        for rhs in &grammar.rules[&a] {
            for symbol in rhs {
                if nonterminal(symbol) && seen.insert(symbol.clone()) { queue.push_back(symbol.clone()); }
            }
        }
    }
    seen
}

fn retain(grammar: &mut Grammar, keep: &BTreeSet<String>) {
    grammar.order.retain(|a| keep.contains(a));
    grammar.rules.retain(|a, _| keep.contains(a));
}

fn clean(mut grammar: Grammar, diagnostics: &mut Vec<String>) -> Grammar {
    let mut undefined: Vec<String> = grammar.rules.values().flat_map(|r| r.iter().flat_map(|rhs| rhs.iter()
        .filter(|s| nonterminal(s) && !grammar.rules.contains_key(*s)).cloned())).collect::<BTreeSet<_>>().into_iter().collect();
    undefined.sort_by(|a, b| a[1..a.len() - 1].cmp(&b[1..b.len() - 1]));
    for a in &undefined { diagnostics.push(format!("undefined nonterminal {}", a)); }
    let missing: BTreeSet<String> = undefined.into_iter().collect();
    for a in &grammar.order {
        grammar.rules.get_mut(a).unwrap().retain(|rhs| {
            if let Some(symbol) = rhs.iter().find(|s| missing.contains(*s)) {
                diagnostics.push(format!("removed {} (undefined {})", production(a, rhs), symbol));
                false
            } else { true }
        });
    }
    let mut productive = BTreeSet::new();
    loop {
        let mut changed = false;
        for a in &grammar.order {
            if grammar.rules[a].iter().any(|r| r.iter().all(|s| !nonterminal(s) || productive.contains(s))) {
                changed |= productive.insert(a.clone());
            }
        }
        if !changed { break; }
    }
    let removed: BTreeSet<String> = grammar.order.iter().filter(|a| !productive.contains(*a)).cloned().collect();
    for a in &grammar.order {
        if removed.contains(a) { diagnostics.push(format!("unproductive nonterminal {}", a)); }
    }
    retain(&mut grammar, &productive);
    for a in &grammar.order {
        grammar.rules.get_mut(a).unwrap().retain(|rhs| {
            if let Some(symbol) = rhs.iter().find(|s| removed.contains(*s)) {
                diagnostics.push(format!("removed {} (unproductive {})", production(a, rhs), symbol));
                false
            } else { true }
        });
    }
    let keep = reachable(&grammar);
    for a in &grammar.order {
        if !keep.contains(a) { diagnostics.push(format!("unreachable nonterminal {}", a)); }
    }
    retain(&mut grammar, &keep);
    grammar
}

fn recursion_diagnostics(grammar: &Grammar) -> Vec<String> {
    let mut diagnostics = Vec::new();
    for a in &grammar.order {
        let mut queue = VecDeque::from([a.clone()]);
        let mut visited = BTreeSet::from([a.clone()]);
        let mut parents = BTreeMap::new();
        let mut found = None;
        while let Some(x) = queue.pop_front() {
            for rhs in &grammar.rules[&x] {
                if let Some(y) = rhs.first() {
                    if y == a { found = Some(x.clone()); break; }
                    if nonterminal(y) && visited.insert(y.clone()) { parents.insert(y.clone(), x.clone()); queue.push_back(y.clone()); }
                }
            }
            if found.is_some() { break; }
        }
        if let Some(mut x) = found {
            let mut path = vec![x.clone()];
            while x != *a { x = parents[&x].clone(); path.push(x.clone()); }
            path.reverse();
            path.push(a.clone());
            diagnostics.push(format!("left recursion: {}", path.join(" -> ")));
        }
    }
    diagnostics
}

fn grammar_listing(grammar: &Grammar, numbered: bool) -> Vec<String> {
    let count: usize = grammar.rules.values().map(Vec::len).sum();
    let digits = count.to_string().len();
    let mut lines = vec![format!("start={} nonterminals={} terminals={} productions={} empty={} unit={}", grammar.start, grammar.order.len(), terminals(grammar).len(), count,
        grammar.rules.values().flat_map(|r| r.iter()).filter(|r| r.is_empty()).count(),
        grammar.rules.values().flat_map(|r| r.iter()).filter(|r| r.len() == 1 && nonterminal(&r[0])).count())];
    let mut number = 0;
    for a in &grammar.order {
        for (i, rhs) in grammar.rules[a].iter().enumerate() {
            number += 1;
            let line = if i == 0 { production(a, rhs) } else { format!("{} | {}", " ".repeat(a.len()), notation(rhs)) };
            lines.push(if numbered { format!("{:>width$}  {}", number, line, width = digits) } else { line });
        }
    }
    lines
}

fn stage(lines: &mut Vec<String>, title: &str, log: &[String], grammar: &Grammar, numbered: bool) {
    lines.push(format!("== {} ==", title));
    if log.is_empty() { lines.push("none".into()); } else { lines.extend(log.iter().cloned()); }
    lines.extend(grammar_listing(grammar, numbered));
    lines.push(String::new());
}

fn lengths(rhs: &[String], values: &BTreeMap<String, (usize, usize)>) -> Option<(usize, usize)> {
    let mut length = 0;
    let mut height = 0;
    for symbol in rhs {
        if nonterminal(symbol) {
            let &(l, h) = values.get(symbol)?;
            length += l;
            height = height.max(h);
        } else { length += 1; }
    }
    Some((length, height + 1))
}

fn sentence(rhs: &[String], shortest: &BTreeMap<String, Vec<String>>) -> Option<Vec<String>> {
    let mut result = Vec::new();
    for symbol in rhs {
        if nonterminal(symbol) { result.extend(shortest.get(symbol)?.iter().cloned()); }
        else { result.push(symbol.clone()); }
    }
    Some(result)
}

fn shortest_examples(grammar: &Grammar, table: &Table) -> (BTreeMap<String, Vec<String>>, Vec<Vec<String>>) {
    let mut values = BTreeMap::new();
    loop {
        let mut changed = false;
        for a in &grammar.order {
            for rhs in &grammar.rules[a] {
                if let Some(value) = lengths(rhs, &values) {
                    if values.get(a).map_or(true, |&old| value < old) { values.insert(a.clone(), value); changed = true; }
                }
            }
        }
        if !changed { break; }
    }
    let mut shortest = BTreeMap::new();
    while shortest.len() < grammar.order.len() {
        for a in &grammar.order {
            if shortest.contains_key(a) { continue; }
            let rhs = grammar.rules[a].iter().find(|r| lengths(r, &values) == Some(values[a])).unwrap();
            if let Some(words) = sentence(rhs, &shortest) { shortest.insert(a.clone(), words); }
        }
    }
    let mut sizes: BTreeMap<String, (usize, usize)> = BTreeMap::from([(grammar.start.clone(), (0, 0))]);
    loop {
        let mut changed = false;
        for p in &table.productions {
            if let Some(&(c, depth)) = sizes.get(&p.lhs) {
                for (k, symbol) in p.rhs.iter().enumerate() {
                    if nonterminal(symbol) && symbol != &grammar.start {
                        let before = lengths(&p.rhs[..k], &values).unwrap().0;
                        let after = lengths(&p.rhs[k + 1..], &values).unwrap().0;
                        let pair = (c + before + after, depth + 1);
                        if sizes.get(symbol).map_or(true, |&old| pair < old) { sizes.insert(symbol.clone(), pair); changed = true; }
                    }
                }
            }
        }
        if !changed { break; }
    }
    let mut choices = BTreeMap::new();
    for a in &grammar.order {
        if a == &grammar.start { continue; }
        'outer: for (number, p) in table.productions.iter().enumerate() {
            for (k, symbol) in p.rhs.iter().enumerate() {
                if symbol == a {
                    let pair = (sizes[&p.lhs].0 + lengths(&p.rhs[..k], &values).unwrap().0 + lengths(&p.rhs[k + 1..], &values).unwrap().0,
                        sizes[&p.lhs].1 + 1);
                    if pair == sizes[a] { choices.insert(a.clone(), (number, k)); break 'outer; }
                }
            }
        }
    }
    let mut contexts: BTreeMap<String, (Vec<String>, Vec<String>)> = BTreeMap::from([(grammar.start.clone(), (Vec::new(), Vec::new()))]);
    while contexts.len() < grammar.order.len() {
        for a in &grammar.order {
            if contexts.contains_key(a) { continue; }
            let (number, k) = choices[a];
            let p = &table.productions[number];
            if let Some((before, after)) = contexts.get(&p.lhs) {
                let mut u = before.clone();
                u.extend(sentence(&p.rhs[..k], &shortest).unwrap());
                let mut v = sentence(&p.rhs[k + 1..], &shortest).unwrap();
                v.extend(after.iter().cloned());
                contexts.insert(a.clone(), (u, v));
            }
        }
    }
    let examples = table.productions.iter().map(|p| {
        let (u, v) = &contexts[&p.lhs];
        let mut result = u.clone();
        result.extend(sentence(&p.rhs, &shortest).unwrap());
        result.extend(v.iter().cloned());
        result
    }).collect();
    (shortest, examples)
}

fn conflict_path(number: usize, terminal: &str, grammar: &Grammar, table: &Table, sets: &Sets) -> Vec<usize> {
    if table.reasons[number][terminal] {
        let mut queue = VecDeque::from([number]);
        let mut visited = BTreeSet::from([number]);
        let mut parents = BTreeMap::new();
        while let Some(q) = queue.pop_front() {
            for symbol in &table.productions[q].rhs {
                if symbol == terminal {
                    let mut path = Vec::new();
                    let mut current = q;
                    while current != number { path.push(current); current = parents[&current]; }
                    path.reverse();
                    return path;
                }
                if nonterminal(symbol) {
                    for (p, production) in table.productions.iter().enumerate() {
                        if &production.lhs == symbol && visited.insert(p) { parents.insert(p, q); queue.push_back(p); }
                    }
                }
                if !nonterminal(symbol) || !sets.nullable.contains(symbol) { break; }
            }
        }
    } else {
        let a = table.productions[number].lhs.clone();
        let mut queue = VecDeque::from([a.clone()]);
        let mut paths: BTreeMap<String, Vec<usize>> = BTreeMap::from([(a, Vec::new())]);
        while let Some(b) = queue.pop_front() {
            let path = paths[&b].clone();
            if b == grammar.start && terminal == "$" { return path; }
            for (q, p) in table.productions.iter().enumerate() {
                for (k, symbol) in p.rhs.iter().enumerate() {
                    if symbol != &b { continue; }
                    let (first, nullable) = sets.sequence(&p.rhs[k + 1..]);
                    let mut next = path.clone();
                    next.push(q);
                    if first.contains(terminal) { return next; }
                    if nullable && !paths.contains_key(&p.lhs) { paths.insert(p.lhs.clone(), next); queue.push_back(p.lhs.clone()); }
                }
            }
        }
    }
    unreachable!()
}

fn table_report(grammar: &Grammar, table: &Table, sets: &Sets, previous_conflicts: usize) -> Vec<String> {
    let mut lines = vec!["== predict sets ==".into()];
    for (i, p) in table.productions.iter().enumerate() {
        lines.push(format!("{}: {}", i + 1, production(&p.lhs, &p.rhs)));
        lines.push(heading("  predict:", &terminal_order(&table.reasons[i].keys().cloned().collect())));
    }
    lines.extend([String::new(), "== parse table ==".into()]);
    let mut terminals = table.terminals.clone();
    terminals.push("$".into());
    let mut rows = vec![std::iter::once(String::new()).chain(terminals.iter().cloned()).collect::<Vec<_>>()];
    for a in &grammar.order {
        let mut row = vec![a.clone()];
        for t in &terminals {
            row.push(table.cells.get(&(a.clone(), t.clone())).map_or(".".into(), |cell| numbers(cell).join("/")));
        }
        rows.push(row);
    }
    let widths: Vec<usize> = (0..rows[0].len()).map(|j| rows.iter().map(|r| r[j].len()).max().unwrap()).collect();
    for row in rows {
        let mut line = format!("{:<width$}", row[0], width = widths[0]);
        for j in 1..row.len() { line += &format!("  {:>width$}", row[j], width = widths[j]); }
        lines.push(line);
    }
    lines.extend([String::new(), "== conflicts ==".into()]);
    if table.conflicts() == 0 { lines.push("none".into()); }
    for a in &grammar.order {
        for t in &terminals {
            if let Some(cell) = table.cells.get(&(a.clone(), t.clone())) {
                if cell.len() < 2 { continue; }
                lines.push(format!("conflict {} on {}: {}, chosen {}", a, t, table.conflict_kind(t, cell), table.chosen(a, t).unwrap() + 1));
                for &number in cell {
                    let p = &table.productions[number];
                    let reason = if table.reasons[number][t] { "FIRST" } else { "FOLLOW" };
                    let path = conflict_path(number, t, grammar, table, sets);
                    let via = if path.is_empty() { String::new() } else { format!(" via {}", numbers(&path).join(" ")) };
                    lines.push(format!("  {}: {} ({}{})", number + 1, production(&p.lhs, &p.rhs), reason, via));
                }
            }
        }
    }
    lines.extend([format!("LL(1): {}", if table.conflicts() == 0 { "yes" } else { "no" }), format!("conflicts before transformation: {}", previous_conflicts)]);
    lines
}

#[derive(Clone)]
struct TreeNode {
    symbol: String,
    mark: Option<String>,
    children: Vec<TreeNode>,
}

impl TreeNode {
    fn from_arena(index: usize, nodes: &[driver::Node]) -> Self {
        let node = &nodes[index];
        Self { symbol: node.symbol.clone(), mark: node.mark.clone(), children: node.children.iter().map(|&i| Self::from_arena(i, nodes)).collect() }
    }

    fn compact(&self) -> Self {
        let mut children = Vec::new();
        for child in &self.children {
            if child.symbol == "%empty" { continue; }
            let child = child.compact();
            if child.mark.is_none() && nonterminal(&child.symbol) && child.children.is_empty() { continue; }
            if child.mark.is_none() && nonterminal(&child.symbol) && child.symbol.contains('\'') { children.extend(child.children); }
            else { children.push(child); }
        }
        if children.len() == 1 && self.mark.is_none() { return children.remove(0); }
        Self { symbol: self.symbol.clone(), mark: self.mark.clone(), children }
    }

    fn label(&self) -> String {
        self.mark.as_ref().map_or(self.symbol.clone(), |m| format!("{} ({})", self.symbol, m))
    }

    fn lines(&self) -> Vec<String> {
        fn descendants(node: &TreeNode, prefix: &str, last: bool, lines: &mut Vec<String>) {
            lines.push(format!("{}{}{}", prefix, if last { "`-- " } else { "|-- " }, node.label()));
            let next = format!("{}{}", prefix, if last { "    " } else { "|   " });
            for (j, child) in node.children.iter().enumerate() { descendants(child, &next, j + 1 == node.children.len(), lines); }
        }
        let mut lines = vec![self.label()];
        for (j, child) in self.children.iter().enumerate() { descendants(child, "", j + 1 == self.children.len(), &mut lines); }
        lines
    }
}

fn action_text(action: &Action, table: &Table) -> String {
    match action {
        Action::Accept => "accept".into(),
        Action::Match(a) => format!("match {}", a),
        Action::Predict(p) => format!("predict {}: {}", p + 1, production(&table.productions[*p].lhs, &table.productions[*p].rhs)),
        Action::Skip(a) => format!("error: skip {}", a),
        Action::Pop(a) => format!("error: pop {}", a),
        Action::Missing(a) => format!("error: missing {}", a),
    }
}

fn trace_table(parse: &Parse, table: &Table) -> Vec<String> {
    let mut rows = vec![vec!["step".into(), "stack".into(), "input".into(), "action".into()]];
    for (j, trace) in parse.trace.iter().enumerate() {
        rows.push(vec![(j + 1).to_string(), notation(&trace.stack), notation(&trace.input), action_text(&trace.action, table)]);
    }
    let widths: Vec<usize> = (0..3).map(|j| rows.iter().map(|r| r[j].len()).max().unwrap()).collect();
    rows.iter().map(|r| format!("{:<a$}  {:<b$}  {:<c$}  {}", r[0], r[1], r[2], r[3], a = widths[0], b = widths[1], c = widths[2])).collect()
}

fn error_messages(parse: &Parse, table: &Table) -> Vec<String> {
    let mut errors = Vec::new();
    for (j, trace) in parse.trace.iter().enumerate() {
        let recovery = match &trace.action {
            Action::Skip(a) => format!("skipped \"{}\"", a),
            Action::Pop(x) => format!("popped {}", x),
            Action::Missing(x) => format!("inserted \"{}\"", x),
            _ => continue,
        };
        let a = &trace.input[0];
        let x = trace.stack.last().unwrap();
        let unexpected = if a == "$" { "end of input".into() } else { format!("\"{}\" at token {}", a, trace.position) };
        let display = |t: &str| if t == "$" { "$".into() } else { format!("\"{}\"", t) };
        let expected = if nonterminal(x) {
            let set: BTreeSet<String> = table.cells.keys().filter(|(lhs, _)| lhs == x).map(|(_, t)| t.clone()).collect();
            terminal_order(&set).iter().map(|t| display(t)).collect::<Vec<_>>().join(" ")
        } else { display(x) };
        errors.push(format!("step {}: unexpected {}; expected {}; {}", j + 1, unexpected, expected, recovery));
    }
    errors
}

fn in_language(grammar: &Grammar, tokens: &[String]) -> bool {
    let n = tokens.len();
    let mut spans: BTreeMap<String, Vec<BTreeSet<usize>>> = grammar.order.iter().map(|a| (a.clone(), vec![BTreeSet::new(); n + 1])).collect();
    loop {
        let mut changed = false;
        for a in &grammar.order {
            for rhs in &grammar.rules[a] {
                for start in 0..=n {
                    let mut ends = BTreeSet::from([start]);
                    for symbol in rhs {
                        let mut next = BTreeSet::new();
                        for position in ends {
                            if nonterminal(symbol) { next.extend(spans[symbol][position].iter().copied()); }
                            else if position < n && &tokens[position] == symbol { next.insert(position + 1); }
                        }
                        ends = next;
                        if ends.is_empty() { break; }
                    }
                    let target = &mut spans.get_mut(a).unwrap()[start];
                    for end in ends { changed |= target.insert(end); }
                }
            }
        }
        if !changed { break; }
    }
    spans[&grammar.start][0].contains(&n)
}

fn write(name: &str, lines: &[String]) -> io::Result<()> {
    fs::write(format!("output/{}", name), lines.join("\n") + "\n")
}

fn main() -> io::Result<()> {
    let parsed = grammar_parser::parse(&fs::read_to_string("input/grammar.bnf")?);
    let mut diagnostics = parsed.diagnostics;
    if parsed.declaration_seen {
        for (word, &line) in &parsed.words {
            if !parsed.declared.contains(word) { diagnostics.push(format!("undeclared terminal {} at line {}", word, line)); }
        }
    }
    let cleaned = clean(parsed.grammar, &mut diagnostics);
    diagnostics.extend(recursion_diagnostics(&cleaned));
    let (eliminated, elimination_log) = transform::eliminate(&cleaned);
    let (factored, factor_log) = transform::factor(&eliminated);
    let mut grammar = factored.clone();
    let keep = reachable(&grammar);
    let mut removal_log = Vec::new();
    for a in &grammar.order {
        if !keep.contains(a) { removal_log.push(format!("remove unreachable {}", a)); diagnostics.push(format!("unreachable after transformation {}", a)); }
    }
    retain(&mut grammar, &keep);
    let known = terminals(&grammar);
    if parsed.declaration_seen {
        for token in parsed.declared.difference(&known) { diagnostics.push(format!("unused token {}", token)); }
    }
    let sets = first_follow::compute(&grammar);
    let table = Table::build(&grammar, &sets);
    let old_sets = first_follow::compute(&cleaned);
    let old_table = Table::build(&cleaned, &old_sets);
    let (shortest, examples) = shortest_examples(&grammar, &table);
    let mut grammar_lines = vec!["== cleaned grammar ==".into()];
    grammar_lines.extend(grammar_listing(&cleaned, false));
    grammar_lines.push(String::new());
    stage(&mut grammar_lines, "left recursion elimination", &elimination_log, &eliminated, false);
    stage(&mut grammar_lines, "left factoring", &factor_log, &factored, false);
    stage(&mut grammar_lines, "final grammar", &removal_log, &grammar, true);
    grammar_lines.push("== cross reference ==".into());
    for symbol in grammar.order.iter().chain(table.terminals.iter()) {
        let label = if nonterminal(symbol) { symbol.clone() } else { format!("\"{}\"", symbol) };
        let used: Vec<usize> = table.productions.iter().enumerate().filter(|(_, p)| p.rhs.contains(symbol)).map(|(i, _)| i).collect();
        grammar_lines.push(if used.is_empty() { format!("{} not used", label) } else { heading(&format!("{} used in", label), &numbers(&used)) });
    }
    let mut set_lines = vec![format!("passes: nullable={} first={} follow={}", sets.passes[0], sets.passes[1], sets.passes[2]), String::new()];
    for a in &grammar.order {
        set_lines.extend([a.clone(), format!("  nullable: {}", if sets.nullable.contains(a) { "yes" } else { "no" }),
            heading("  first:", &terminal_order(&sets.first[a])), heading("  follow:", &terminal_order(&sets.follow[a])), heading("  shortest:", &shortest[a])]);
    }
    let table_lines = table_report(&grammar, &table, &sets, old_table.conflicts());
    let inputs: Vec<Vec<String>> = fs::read_to_string("input/inputs.txt")?.lines().map(|s| s.split_whitespace().map(str::to_owned).collect()).collect();
    let mut parse_lines = Vec::new();
    let mut used = BTreeSet::new();
    let (mut accepted, mut language_count) = (0, 0);
    let mut mismatches = Vec::new();
    let (mut unknown_total, mut skips, mut pops, mut missing) = (0usize, 0usize, 0usize, 0usize);
    for (number, original) in inputs.iter().enumerate() {
        let mut input = Vec::new();
        let mut errors = Vec::new();
        for (position, token) in original.iter().enumerate() {
            if known.contains(token) { input.push((token.clone(), position + 1)); }
            else { errors.push(format!("unknown \"{}\" at token {}; removed", token, position + 1)); unknown_total += 1; }
        }
        input.push(("$".into(), original.len() + 1));
        let parse = driver::parse(&grammar.start, &input, &table, &sets);
        errors.extend(error_messages(&parse, &table));
        skips += parse.skips;
        pops += parse.pops;
        missing += parse.missing;
        used.extend(parse.left.iter().copied());
        let language = in_language(&cleaned, original);
        let success = errors.is_empty();
        if success { accepted += 1; }
        if language { language_count += 1; }
        if success != language { mismatches.push(number); }
        parse_lines.extend([format!("== input {} ==", number + 1), heading("tokens:", original)]);
        parse_lines.extend(trace_table(&parse, &table));
        parse_lines.extend([heading("left parse:", &numbers(&parse.left)), format!("stats: steps={} predicts={} matches={} max_stack={}", parse.trace.len(), parse.left.len(), parse.matches, parse.max_stack)]);
        if !errors.is_empty() { parse_lines.push("errors:".into()); parse_lines.extend(errors.iter().map(|s| format!("  {}", s))); }
        parse_lines.push(if success { "result: accepted".into() } else { format!("result: rejected (errors: {})", errors.len()) });
        parse_lines.push(format!("language: {}", if language { "yes" } else { "no" }));
        if success {
            parse_lines.extend(["derivation:".into(), format!("  {}", grammar.start)]);
            let mut sequence = vec![grammar.start.clone()];
            for &number in &parse.left {
                let p = &table.productions[number];
                let index = sequence.iter().position(|s| nonterminal(s)).unwrap();
                sequence.splice(index..index + 1, p.rhs.iter().cloned());
                parse_lines.push(format!("  => {}", notation(&sequence)));
            }
        }
        let tree = TreeNode::from_arena(0, &parse.tree);
        parse_lines.push("tree:".into());
        parse_lines.extend(tree.lines());
        parse_lines.push("compact tree:".into());
        parse_lines.extend(tree.compact().lines());
        parse_lines.push(String::new());
    }
    let unused: Vec<usize> = (0..table.productions.len()).filter(|p| !used.contains(p)).collect();
    parse_lines.extend(["== summary ==".into(), format!("inputs={} accepted={} rejected={} in_language={}", inputs.len(), accepted, inputs.len() - accepted, language_count),
        heading("mismatches:", &numbers(&mismatches)), format!("recovery: unknown={} skip={} pop={} missing={}", unknown_total, skips, pops, missing),
        format!("coverage: {} of {} productions used", used.len(), table.productions.len()), heading("unused:", &numbers(&unused))]);
    for &number in &unused {
        let p = &table.productions[number];
        let mut input: Vec<(String, usize)> = examples[number].iter().enumerate().map(|(i, t)| (t.clone(), i + 1)).collect();
        input.push(("$".into(), examples[number].len() + 1));
        let parse = driver::parse(&grammar.start, &input, &table, &sets);
        let errors = parse.skips + parse.pops + parse.missing;
        parse_lines.extend([format!("  {}: {}", number + 1, production(&p.lhs, &p.rhs)), heading("    example:", &examples[number]),
            if errors == 0 { "    result: accepted".into() } else { format!("    result: rejected (errors: {})", errors) },
            format!("    used: {}", if parse.left.contains(&number) { "yes" } else { "no" })]);
    }
    diagnostics.push(if table.conflicts() == 0 { "result: LL(1)".into() } else { format!("result: not LL(1) (conflicts: {})", table.conflicts()) });
    fs::create_dir_all("output")?;
    for (name, lines) in [("grammar.txt", grammar_lines), ("sets.txt", set_lines), ("table.txt", table_lines), ("parses.txt", parse_lines), ("diagnostics.txt", diagnostics)] {
        write(name, &lines)?;
    }
    Ok(())
}
