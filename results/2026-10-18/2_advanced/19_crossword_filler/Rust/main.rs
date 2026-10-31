mod grid;
mod slots;
mod word_index;
mod filler;
mod render;

use std::cmp::Reverse;
use std::collections::{BTreeMap, BTreeSet};
use std::{fs, io};
use filler::{Attempt, GridState};
use grid::Grid;
use render::{decimal, grid_lines, list_line, number_lines};
use slots::{Layout, Slot, find_short_run};
use word_index::{WordIndex, clue_line_error, is_valid_integer, is_valid_word, matches, word_line_error};

const LETTER_POINTS: [i64; 26] = [1, 3, 3, 2, 1, 4, 2, 4, 1, 8, 5, 1, 3, 1, 1, 3, 10, 1, 1, 1, 1, 4, 4, 8, 4, 10];
fn read_lines(name: &str) -> io::Result<Vec<String>> { Ok(fs::read_to_string(format!("input/{name}"))?.lines().map(str::to_owned).collect()) }
fn ignored(line: &str) -> bool { line.is_empty() || line.starts_with('#') }
fn joined(items: &[String], separator: &str) -> String { if items.is_empty() { "-".to_owned() } else { items.join(separator) } }
fn paragraphs(blocks: Vec<Vec<String>>) -> Vec<String> {
    let mut lines = Vec::new();
    for block in blocks { if !lines.is_empty() { lines.push(String::new()); } lines.extend(block); }
    lines
}

#[derive(Clone)]
struct Settings { budget: usize, minimum: i64, symmetry: String, relax: i64, weak: i64 }
fn read_settings(lines: &[String]) -> Settings {
    let values: BTreeMap<_, _> = lines.iter().filter(|line| !ignored(line)).map(|line| line.split_once(' ').unwrap()).collect();
    Settings { budget: values["node_budget"].parse().unwrap(), minimum: values["min_score"].parse().unwrap(),
        symmetry: values["symmetry"].to_owned(), relax: values["relax_step"].parse().unwrap(), weak: values["weak_score"].parse().unwrap() }
}

struct WordList {
    line_count: usize,
    index: WordIndex,
    invalid: Vec<(usize, &'static str)>,
    duplicates: Vec<(usize, String, usize)>,
}
impl WordList {
    fn new(lines: &[String]) -> Self {
        let mut scores = BTreeMap::new();
        let mut first_lines = BTreeMap::new();
        let (mut invalid, mut duplicates) = (Vec::new(), Vec::new());
        for (number, line) in lines.iter().enumerate() {
            if let Some(reason) = word_line_error(line) { invalid.push((number + 1, reason)); continue; }
            let (word, score) = line.split_once(' ').unwrap();
            if let Some(&first) = first_lines.get(word) { duplicates.push((number + 1, word.to_owned(), first)); }
            else { scores.insert(word.to_owned(), score.parse().unwrap()); first_lines.insert(word.to_owned(), number + 1); }
        }
        Self { line_count: lines.len(), index: WordIndex::new(scores), invalid, duplicates }
    }
    fn report(&self) -> Vec<String> {
        let index = &self.index;
        let mut lines = vec![format!("WORDLIST lines={} valid={} invalid={} duplicates={}", self.line_count, index.words.len(), self.invalid.len(), self.duplicates.len())];
        for &(number, reason) in &self.invalid { lines.push(format!("invalid {number} {reason}")); }
        for (number, word, first) in &self.duplicates { lines.push(format!("duplicate {number} {word} first={first}")); }
        for (length, words) in &index.by_length {
            let total = words.iter().map(|&id| index.words[id].score).sum();
            let best = &index.words[words[0]];
            lines.push(format!("length {length} words={} average={} best={}:{}", words.len(), decimal(total, words.len(), 2), best.text, best.score));
        }
        let bands: Vec<_> = [(1, 20), (21, 40), (41, 60), (61, 80), (81, 100)].iter().map(|&(low, high)| {
            format!("{low}-{high}={}", index.words.iter().filter(|word| low <= word.score && word.score <= high).count())
        }).collect();
        lines.push(format!("bands {}", bands.join(" ")));
        lines.push(format!("top {}", index.words.iter().take(5).map(|word| format!("{}:{}", word.text, word.score)).collect::<Vec<_>>().join(" ")));
        let mut rare: Vec<_> = (b'A'..=b'Z').map(|letter| (index.words.iter().filter(|word| word.letters.contains(&letter)).count(), letter)).collect();
        rare.sort_unstable();
        lines.push(format!("rare_letters {}", rare.iter().take(5).map(|(count, letter)| format!("{}:{count}", *letter as char)).collect::<Vec<_>>().join(" ")));
        lines
    }
}

struct Clue { text: String, uses: usize }
struct ClueBook {
    entries: usize,
    added: usize,
    invalid: Vec<(usize, &'static str)>,
    unknown: Vec<(usize, String)>,
    clues: Vec<Vec<Clue>>,
}
impl ClueBook {
    fn new(lines: &[String], index: &WordIndex) -> Self {
        let mut result = Self { entries: 0, added: 0, invalid: Vec::new(), unknown: Vec::new(), clues: (0..index.words.len()).map(|_| Vec::new()).collect() };
        for (number, line) in lines.iter().enumerate() {
            if ignored(line) { continue; }
            result.entries += 1;
            if let Some(reason) = clue_line_error(line) { result.invalid.push((number + 1, reason)); continue; }
            let (word, text) = line.split_once('|').unwrap();
            if let Some(&id) = index.lookup.get(word) { result.clues[id].push(Clue { text: text.to_owned(), uses: 0 }); result.added += 1; }
            else { result.unknown.push((number + 1, word.to_owned())); }
        }
        result
    }
    fn choose(&mut self, id: usize) -> Option<String> {
        let number = self.clues[id].iter().enumerate().min_by_key(|(number, clue)| (clue.uses, *number)).map(|(number, _)| number)?;
        self.clues[id][number].uses += 1;
        Some(self.clues[id][number].text.clone())
    }
    fn report(&self, index: &WordIndex) -> Vec<String> {
        let mut lines = vec![format!("CLUES entries={} valid={} invalid={} unknown={} words={}", self.entries, self.added, self.invalid.len(), self.unknown.len(), self.clues.iter().filter(|clues| !clues.is_empty()).count())];
        for &(number, reason) in &self.invalid { lines.push(format!("clue_invalid {number} {reason}")); }
        for (number, word) in &self.unknown { lines.push(format!("clue_unknown {number} {word}")); }
        let used = self.clues.iter().flatten().filter(|clue| clue.uses > 0).count();
        let repeated = self.clues.iter().flatten().filter(|clue| clue.uses >= 2).count();
        lines.push(format!("CLUE_USE used={used} unused={} repeated={repeated}", self.added - used));
        for (word, &id) in &index.lookup {
            for (number, clue) in self.clues[id].iter().enumerate() {
                if clue.uses >= 2 { lines.push(format!("repeated {word} clue={} uses={}", number + 1, clue.uses)); }
            }
        }
        lines
    }
}

struct Block { name: String, options: Vec<String>, rows: Vec<String> }
fn split_blocks(lines: Vec<String>) -> Vec<Block> {
    let mut blocks = Vec::new();
    let mut current: Option<Block> = None;
    for line in lines {
        if let Some(block) = &mut current {
            if line == "END" { blocks.push(current.take().unwrap()); }
            else if line.contains(' ') { block.options.push(line); }
            else { block.rows.push(line); }
        } else if let Some(name) = line.strip_prefix("TEMPLATE ") {
            current = Some(Block { name: name.to_owned(), options: Vec::new(), rows: Vec::new() });
        }
    }
    blocks
}
struct Prepared { settings: Settings, layout: Layout, initial: GridState, theme_slots: BTreeSet<usize> }
fn prepare(block: &Block, defaults: &Settings, names: &BTreeSet<String>, index: &WordIndex) -> Result<Prepared, String> {
    if !(1..=20).contains(&block.name.len()) || !block.name.bytes().all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit() || byte == b'_') { return Err("bad name".to_owned()); }
    if names.contains(&block.name) { return Err("duplicate name".to_owned()); }
    let mut settings = defaults.clone();
    let (mut seen, mut themes) = (BTreeSet::new(), Vec::new());
    for (number, line) in block.options.iter().enumerate() {
        let (key, value) = line.split_once(' ').unwrap();
        let valid = if key == "theme" {
            if is_valid_word(value) && !themes.contains(&value.to_owned()) { themes.push(value.to_owned()); true } else { false }
        } else if seen.contains(key) { false } else {
            match key {
                "node_budget" if is_valid_integer(value, 1, 100000) => { settings.budget = value.parse().unwrap(); true }
                "min_score" if is_valid_integer(value, 1, 100) => { settings.minimum = value.parse().unwrap(); true }
                "symmetry" if ["rot180", "mirror", "none"].contains(&value) => { settings.symmetry = value.to_owned(); true }
                _ => false,
            }
        };
        if !valid { return Err(format!("bad option {}", number + 1)); }
        seen.insert(key.to_owned());
    }
    if !(3..=15).contains(&block.rows.len()) { return Err("bad height".to_owned()); }
    let width = block.rows[0].len();
    for (number, row) in block.rows.iter().enumerate() {
        if !(3..=15).contains(&row.len()) || row.len() != width || !row.bytes().all(|byte| byte == b'.' || byte == b'#' || byte.is_ascii_uppercase()) { return Err(format!("bad row {}", number + 1)); }
    }
    let grid = Grid::new(&block.rows);
    if settings.symmetry != "none" {
        if let Some(cell) = grid.asymmetric_cell(&settings.symmetry) { return Err(format!("asymmetric at {}", grid.location(cell))); }
    }
    let components = grid.component_count();
    if components != 1 { return Err(format!("disconnected components={components}")); }
    if let Some((cell, direction)) = find_short_run(&grid) { return Err(format!("short slot at {} {direction}", grid.location(cell))); }
    let layout = Layout::new(grid);
    if let Some(cell) = layout.orphan_cell() { return Err(format!("orphan cell {}", layout.grid.location(cell))); }
    let mut initial = GridState::new(layout.grid.cells.clone(), layout.slots.len());
    let mut theme_slots = BTreeSet::new();
    for (number, theme) in themes.iter().enumerate() {
        let Some(&id) = index.lookup.get(theme) else { return Err(format!("unknown theme {}", number + 1)); };
        let fitting = layout.slots.iter().find(|slot| initial.words[slot.index].is_none() && slot.length() == theme.len() && matches(&index.words[id].letters, &initial.pattern(slot)));
        let Some(slot) = fitting else { return Err(format!("theme {} does not fit", number + 1)); };
        initial.assign(slot, id, index);
        theme_slots.insert(slot.index);
    }
    Ok(Prepared { settings, layout, initial, theme_slots })
}

struct Completed {
    prepared: Prepared,
    attempts: Vec<Attempt>,
    state: GridState,
    chosen: Vec<Option<String>>,
}
impl Completed {
    fn run(prepared: Prepared, index: &WordIndex, clues: &mut ClueBook) -> Self {
        let mut attempts = Vec::new();
        let mut minimum = prepared.settings.minimum;
        loop {
            let mut attempt = Attempt::new(&prepared.initial, minimum, prepared.settings.budget);
            attempt.run(&prepared.layout, index);
            let stop = attempt.outcome == "filled" || prepared.settings.relax == 0 || minimum <= 1;
            attempts.push(attempt);
            if stop { break; }
            minimum = (minimum - prepared.settings.relax).max(1);
        }
        let state = attempts.last().unwrap().final_state().clone();
        let mut chosen = vec![None; prepared.layout.slots.len()];
        for across in [true, false] {
            for slot in prepared.layout.slots.iter().filter(|slot| slot.across == across) {
                if let Some(word) = state.words[slot.index] { chosen[slot.index] = clues.choose(word); }
            }
        }
        Self { prepared, attempts, state, chosen }
    }
    fn final_attempt(&self) -> &Attempt { self.attempts.last().unwrap() }
    fn filled(&self) -> bool { self.final_attempt().outcome == "filled" }
    fn total_score(&self, index: &WordIndex) -> i64 { self.state.words.iter().map(|word| index.words[word.unwrap()].score).sum() }
    fn entry(&self, slot: &Slot, index: &WordIndex) -> String {
        let word = &index.words[self.state.words[slot.index].unwrap()];
        format!("{}:{}:{}", slot.label, word.text, word.score)
    }
    fn clue_paragraph(&self, name: &str, index: &WordIndex) -> Vec<String> {
        let mut lines = vec![format!("TEMPLATE {name}")];
        let (mut clued, mut missing, mut unfilled) = (0, 0, 0);
        for (heading, across) in [("ACROSS", true), ("DOWN", false)] {
            let slots: Vec<_> = self.prepared.layout.slots.iter().filter(|slot| slot.across == across).collect();
            if !slots.is_empty() { lines.push(heading.to_owned()); }
            for slot in slots {
                if let Some(id) = self.state.words[slot.index] {
                    let clue = if let Some(clue) = &self.chosen[slot.index] { clued += 1; clue.as_str() } else { missing += 1; "(no clue)" };
                    lines.push(list_line(slot, clue, &index.words[id].text, &index.words[id].score.to_string(), self.prepared.theme_slots.contains(&slot.index)));
                } else {
                    unfilled += 1;
                    let pattern = String::from_utf8(self.state.pattern(slot)).unwrap();
                    lines.push(list_line(slot, "(unfilled)", &pattern, "-", false));
                }
            }
        }
        lines.push(format!("clued={clued} missing={missing} unfilled={unfilled}"));
        lines
    }
    fn stats_paragraph(&self, name: &str, index: &WordIndex) -> Vec<String> {
        let p = &self.prepared;
        let layout = &p.layout;
        let grid = &layout.grid;
        let slots = &layout.slots;
        let whites = grid.white_cells();
        let blacks = grid.cells.len() - whites.len();
        let givens = whites.iter().filter(|&&cell| grid.cells[cell] != b'.').count();
        let symmetries: Vec<_> = ["rot180", "mirror"].iter().filter(|&&symmetry| grid.asymmetric_cell(symmetry).is_none()).map(|symmetry| (*symmetry).to_owned()).collect();
        let symmetry = if symmetries.is_empty() { "none".to_owned() } else { symmetries.join(",") };
        let mut lengths = BTreeMap::new();
        for slot in slots { *lengths.entry(slot.length()).or_insert(0usize) += 1; }
        let across = slots.iter().filter(|slot| slot.across).count();
        let unchecked = whites.iter().filter(|&&cell| layout.owner_count(cell) == 1).count();
        let length_text = lengths.iter().map(|(length, count)| format!("{length}:{count}")).collect::<Vec<_>>().join(",");
        let length_sum = slots.iter().map(|slot| slot.length() as i64).sum();
        let mut lines = vec![format!("TEMPLATE {name}"),
            format!("grid size={}x{} blocks={blacks} white={} density={} givens={givens} required={} symmetry={symmetry}", grid.width, grid.height, whites.len(), decimal(100 * blacks as i64, grid.cells.len(), 1), p.settings.symmetry),
            format!("slots across={across} down={} total={} lengths={length_text} avg_length={} longest={} unchecked={unchecked}", slots.len() - across, slots.len(), decimal(length_sum, slots.len(), 2), lengths.keys().last().unwrap())];
        if !p.theme_slots.is_empty() {
            let themes: Vec<_> = slots.iter().filter(|slot| p.theme_slots.contains(&slot.index)).map(|slot| self.entry(slot, index)).collect();
            lines.push(format!("themes {}", themes.join(" ")));
        }
        let supply: Vec<_> = lengths.keys().map(|length| {
            let count = index.by_length.get(length).map_or(0, |words| words.iter().filter(|&&id| index.words[id].score >= p.settings.minimum).count());
            format!("{length}:{count}")
        }).collect();
        lines.push(format!("coverage {}", supply.join(" ")));
        let mut tightest: Vec<_> = slots.iter().filter(|slot| !p.theme_slots.contains(&slot.index)).map(|slot|
            (index.candidates(&p.initial.pattern(slot), p.settings.minimum, &p.initial.used).len(), slot.index)).collect();
        tightest.sort_unstable();
        let tightest: Vec<_> = tightest.iter().take(3).map(|(count, number)| format!("{}:{count}", slots[*number].label)).collect();
        lines.push(format!("tightest {}", joined(&tightest, " ")));
        for (number, attempt) in self.attempts.iter().enumerate() {
            lines.push(format!("attempt {} min_score={} budget={} outcome={} nodes={} backtracks={} prunes={} dead_ends={} max_depth={}", number + 1,
                attempt.minimum, attempt.budget, attempt.outcome, attempt.nodes, attempt.backtracks, attempt.prunes, attempt.dead_ends, attempt.max_depth));
        }
        let final_attempt = self.final_attempt();
        lines.push(format!("trace {}", joined(&final_attempt.trace, " ")));
        let mut hotspots: Vec<_> = (0..slots.len()).filter(|&number| final_attempt.failures[number] > 0).collect();
        hotspots.sort_by_key(|&number| (Reverse(final_attempt.failures[number]), number));
        let hotspots: Vec<_> = hotspots.iter().take(3).map(|&number| format!("{}:{}", slots[number].label, final_attempt.failures[number])).collect();
        lines.push(format!("hotspots {}", joined(&hotspots, " ")));
        if self.filled() {
            let order: Vec<_> = final_attempt.sequence.iter().map(|&number| slots[number].label.clone()).collect();
            lines.push(format!("order {}", joined(&order, " ")));
            let total = self.total_score(index);
            let weakest = slots.iter().min_by_key(|slot| (index.words[self.state.words[slot.index].unwrap()].score, slot.index)).unwrap();
            let weak: Vec<_> = slots.iter().filter(|slot| index.words[self.state.words[slot.index].unwrap()].score < p.settings.weak).map(|slot| self.entry(slot, index)).collect();
            lines.push(format!("quality total={total} average={} weakest={} weak={}", decimal(total, slots.len(), 2), self.entry(weakest, index), joined(&weak, ",")));
            let letters: BTreeSet<_> = whites.iter().map(|&cell| self.state.letters[cell]).collect();
            let missing: String = (b'A'..=b'Z').filter(|letter| !letters.contains(letter)).map(char::from).collect();
            let points: i64 = whites.iter().map(|&cell| LETTER_POINTS[(self.state.letters[cell] - b'A') as usize]).sum();
            let mut worst: Option<(i64, usize, usize, usize)> = None;
            for &cell in &whites {
                if let (Some(a), Some(d)) = (layout.across_slot[cell], layout.down_slot[cell]) {
                    let sum = index.words[self.state.words[a].unwrap()].score + index.words[self.state.words[d].unwrap()].score;
                    if worst.is_none_or(|(previous, _, _, _)| sum < previous) { worst = Some((sum, cell, a, d)); }
                }
            }
            let crossing = worst.map(|(sum, cell, a, d)| format!("{} {}:{}+{}:{}={sum}", grid.location(cell), slots[a].label,
                index.words[self.state.words[a].unwrap()].text, slots[d].label, index.words[self.state.words[d].unwrap()].text)).unwrap_or_else(|| "-".to_owned());
            lines.push(format!("letters distinct={} pangram={} missing={} scrabble={} worst_crossing={crossing}", letters.len(), if missing.is_empty() { "yes" } else { "no" },
                if missing.is_empty() { "-" } else { &missing }, decimal(points, whites.len(), 2)));
        } else {
            let assigned = self.state.words.iter().filter(|word| word.is_some()).count();
            let lettered = whites.iter().filter(|&&cell| self.state.letters[cell] != b'.').count();
            let blocked: Vec<_> = slots.iter().filter(|slot| self.state.words[slot.index].is_none()
                && index.candidates(&self.state.pattern(slot), final_attempt.minimum, &self.state.used).is_empty()).map(|slot| slot.label.clone()).collect();
            lines.push(format!("partial assigned={assigned}/{} letters={lettered}/{} blocked={}", slots.len(), whites.len(), joined(&blocked, ",")));
        }
        lines
    }
}

struct Template { name: String, result: Result<Completed, String> }
impl Template {
    fn grid_paragraph(&self) -> Vec<String> {
        let mut lines = vec![format!("TEMPLATE {}", self.name)];
        match &self.result {
            Err(reason) => lines.push(format!("error {reason}")),
            Ok(completed) => {
                let final_attempt = completed.final_attempt();
                lines.push(format!("outcome={} attempts={} min_score={}", final_attempt.outcome, completed.attempts.len(), final_attempt.minimum));
                lines.extend(grid_lines(&completed.prepared.layout.grid, &completed.state.letters));
                lines.push("numbers".to_owned());
                lines.extend(number_lines(&completed.prepared.layout));
            }
        }
        lines
    }
}

fn overall_paragraphs(templates: &[Template], index: &WordIndex) -> Vec<Vec<String>> {
    let valid: Vec<_> = templates.iter().filter_map(|template| template.result.as_ref().ok().map(|result| (template.name.as_str(), result))).collect();
    let filled: Vec<_> = valid.iter().copied().filter(|(_, result)| result.filled()).collect();
    let mut ranked = filled.clone();
    ranked.sort_by(|(a_name, a), (b_name, b)| {
        let left = a.total_score(index) * b.prepared.layout.slots.len() as i64;
        let right = b.total_score(index) * a.prepared.layout.slots.len() as i64;
        right.cmp(&left).then(a_name.cmp(b_name))
    });
    let mut ranking = vec!["RANKING".to_owned()];
    for (position, (name, result)) in ranked.iter().enumerate() {
        let total = result.total_score(index);
        let entries = result.prepared.layout.slots.len();
        ranking.push(format!("rank {} {name} average={} total={total} entries={entries}", position + 1, decimal(total, entries, 2)));
    }
    let mut appearances: BTreeMap<usize, Vec<&str>> = BTreeMap::new();
    for &(name, result) in &filled {
        for word in &result.state.words { appearances.entry(word.unwrap()).or_default().push(name); }
    }
    let mut reused: Vec<_> = appearances.iter().filter(|(_, names)| names.len() >= 2).collect();
    reused.sort_by_key(|(id, names)| (Reverse(names.len()), index.words[**id].text.as_str()));
    let mut reuse = vec!["REUSE".to_owned()];
    for (&id, names) in reused { reuse.push(format!("reused {} {} {}", index.words[id].text, names.len(), names.join(","))); }
    let attempts: usize = valid.iter().map(|(_, result)| result.attempts.len()).sum();
    let nodes: usize = valid.iter().flat_map(|(_, result)| result.attempts.iter()).map(|attempt| attempt.nodes).sum();
    let unfillable = valid.iter().filter(|(_, result)| result.final_attempt().outcome == "unfillable").count();
    let budget = valid.iter().filter(|(_, result)| result.final_attempt().outcome == "budget").count();
    let summary = vec![format!("SUMMARY templates={} invalid={} filled={} unfillable={unfillable} budget={budget} attempts={attempts} nodes={nodes}",
        templates.len(), templates.len() - valid.len(), filled.len())];
    vec![ranking, reuse, summary]
}

fn main() -> io::Result<()> {
    let settings = read_settings(&read_lines("params.txt")?);
    let word_list = WordList::new(&read_lines("words.txt")?);
    let index = &word_list.index;
    let mut clues = ClueBook::new(&read_lines("clues.txt")?, index);
    let mut templates = Vec::new();
    let mut names = BTreeSet::new();
    for block in split_blocks(read_lines("templates.txt")?) {
        let result = prepare(&block, &settings, &names, index).map(|prepared| Completed::run(prepared, index, &mut clues));
        names.insert(block.name.clone());
        templates.push(Template { name: block.name, result });
    }
    let grid = paragraphs(templates.iter().map(Template::grid_paragraph).collect());
    let clue_lines = paragraphs(templates.iter().filter_map(|template| template.result.as_ref().ok().map(|result| result.clue_paragraph(&template.name, index))).collect());
    let mut stats: Vec<_> = templates.iter().filter_map(|template| template.result.as_ref().ok().map(|result| result.stats_paragraph(&template.name, index))).collect();
    stats.extend(overall_paragraphs(&templates, index));
    let stats = paragraphs(stats);
    let mut words = word_list.report();
    words.extend(clues.report(index));
    fs::create_dir_all("output")?;
    for (name, lines) in [("grid.txt", grid), ("clues.txt", clue_lines), ("search_stats.txt", stats), ("wordlist.txt", words)] {
        let text = if lines.is_empty() { String::new() } else { lines.join("\n") + "\n" };
        fs::write(format!("output/{name}"), text)?;
    }
    Ok(())
}
