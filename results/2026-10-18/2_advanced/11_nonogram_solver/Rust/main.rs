mod clues;
mod line_solver;
mod propagation;
mod render;
mod search;

use std::collections::HashSet;
use std::fs;
use std::io;
use line_solver::{Clues, Given, Grid, EMPTY, FILLED, UNKNOWN};
use propagation::{Propagation, determined};
use search::Search;

fn read_blocks(name: &str) -> io::Result<Vec<Vec<String>>> {
    let mut blocks = Vec::new();
    let mut current: Option<Vec<String>> = None;
    for line in fs::read_to_string(format!("input/{name}"))?.lines() {
        if let Some(block) = current.as_mut() {
            if line == "END" { blocks.push(current.take().unwrap()); } else { block.push(line.to_owned()); }
        } else if !line.is_empty() && !line.starts_with('#') { current = Some(vec![line.to_owned()]); }
    }
    Ok(blocks)
}

fn write_lines(name: &str, lines: &[String]) -> io::Result<()> { fs::write(format!("output/{name}"), lines.join("\n") + "\n") }
fn paragraphs(blocks: Vec<Vec<String>>) -> Vec<String> {
    let mut lines = Vec::new();
    for block in blocks { if !lines.is_empty() { lines.push(String::new()); } lines.extend(block); }
    lines
}
fn valid_name(name: &str) -> bool { (1..=20).contains(&name.len()) && name.bytes().all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == b'_') }
fn number_list(numbers: &[usize]) -> String { if numbers.is_empty() { "-".into() } else { numbers.iter().map(usize::to_string).collect::<Vec<_>>().join(",") } }
fn cell_text(row: usize, column: usize) -> String { format!("{},{}", row + 1, column + 1) }
fn differences(first: &Grid, second: &Grid) -> Vec<(usize, usize)> {
    let mut cells = Vec::new();
    for (r, row) in first.iter().enumerate() { for (c, &state) in row.iter().enumerate() { if state != second[r][c] { cells.push((r, c)); } } }
    cells
}

struct Puzzle {
    name: String, width: usize, height: usize, row_lines: Vec<String>, column_lines: Vec<String>,
    given_lines: Vec<(usize, usize, u8)>, answer: Option<Grid>, rows: Clues, columns: Clues, givens: Vec<Given>,
}
impl Puzzle {
    fn new(lines: Vec<String>) -> Self {
        let name = lines[0][7..].to_owned();
        let size: Vec<_> = lines[1].split(' ').collect();
        let width = size[1].parse().unwrap();
        let height = size[2].parse().unwrap();
        let split = lines.iter().position(|s| s == "COLUMNS").unwrap();
        let row_lines = lines[3..split].to_vec();
        let mut column_lines = Vec::new();
        let mut position = split + 1;
        while position < lines.len() && clues::is_line(&lines[position]) { column_lines.push(lines[position].clone()); position += 1; }
        let mut given_lines = Vec::new();
        while position < lines.len() && lines[position].starts_with("GIVEN ") {
            let fields: Vec<_> = lines[position].split(' ').collect();
            given_lines.push((fields[1].parse().unwrap(), fields[2].parse().unwrap(), fields[3].as_bytes()[0])); position += 1;
        }
        let answer = if position < lines.len() { Some(lines[position + 1..].iter().map(|s| s.as_bytes().to_vec()).collect()) } else { None };
        Self { name, width, height, row_lines, column_lines, given_lines, answer, rows: Vec::new(), columns: Vec::new(), givens: Vec::new() }
    }
    fn validate(&mut self, names: &HashSet<String>) -> Option<String> {
        if !valid_name(&self.name) { return Some("bad name".into()); }
        if names.contains(&self.name) { return Some("duplicate name".into()); }
        if !(1..=30).contains(&self.width) || !(1..=30).contains(&self.height) { return Some("bad size".into()); }
        if self.row_lines.len() != self.height { return Some(format!("row count {} expected {}", self.row_lines.len(), self.height)); }
        if self.column_lines.len() != self.width { return Some(format!("column count {} expected {}", self.column_lines.len(), self.width)); }
        for row in [true, false] {
            let (kind, texts, length, target) = if row { ("row", &self.row_lines, self.width, &mut self.rows) } else { ("column", &self.column_lines, self.height, &mut self.columns) };
            for (i, text) in texts.iter().enumerate() {
                let Some(clue) = clues::parse(text) else { return Some(format!("bad clue {kind} {}", i + 1)); };
                if clues::span(&clue) > length { return Some(format!("{kind} {} too long", i + 1)); }
                target.push(clue);
            }
        }
        let a: usize = self.rows.iter().flatten().sum();
        let b: usize = self.columns.iter().flatten().sum();
        if a != b { return Some(format!("total mismatch rows={a} columns={b}")); }
        let mut taken = HashSet::new();
        for (i, &(r, c, value)) in self.given_lines.iter().enumerate() {
            if r < 1 || r > self.height || c < 1 || c > self.width || ![FILLED, EMPTY].contains(&value) { return Some(format!("bad given {}", i + 1)); }
            if !taken.insert((r, c)) { return Some(format!("duplicate given {}", i + 1)); }
            self.givens.push(Given { row: r - 1, column: c - 1, value });
        }
        if let Some(answer) = &self.answer {
            if answer.len() != self.height || answer.iter().any(|row| row.len() != self.width || row.iter().any(|v| ![FILLED, EMPTY, UNKNOWN].contains(v))) { return Some("bad answer".into()); }
        }
        None
    }
}

fn logical_solve(rows: &Clues, columns: &Clues, givens: &[Given], precise: bool) -> (Grid, Propagation) {
    let mut grid = vec![vec![UNKNOWN; columns.len()]; rows.len()];
    for given in givens { grid[given.row][given.column] = given.value; }
    let result = propagation::run(&mut grid, rows, columns, precise, vec![true; rows.len()], vec![true; columns.len()]);
    (grid, result)
}
fn solving_result(grid: &Grid, propagation: &Propagation) -> String {
    if let Some(step) = &propagation.conflict { format!("contradiction at={}", step.label()) }
    else if determined(grid) == grid.len() * grid[0].len() { "solved".into() } else { "stuck".into() }
}
struct Analysis {
    simple_grid: Grid, logic_grid: Grid, simple: Propagation, logic: Propagation,
    simple_result: String, logic_result: String, status: &'static str, difficulty: &'static str,
    search: Option<Search>, solutions: Vec<Grid>, line_solves: usize, guesses: usize, max_depth: usize,
}
impl Analysis {
    fn new(rows: &Clues, columns: &Clues, givens: &[Given]) -> Self {
        let (simple_grid, simple) = logical_solve(rows, columns, givens, false);
        let (logic_grid, logic) = logical_solve(rows, columns, givens, true);
        let simple_result = solving_result(&simple_grid, &simple);
        let logic_result = solving_result(&logic_grid, &logic);
        let mut difficulty = "-";
        let mut search = None;
        let mut solutions = Vec::new();
        let status;
        if logic.conflict.is_some() { status = "contradiction"; }
        else if logic_result == "solved" { status = "unique"; solutions.push(logic_grid.clone()); difficulty = if simple_result == "solved" { "easy" } else { "medium" }; }
        else {
            let found = Search::new(&logic_grid, rows, columns);
            solutions = found.solutions.clone(); status = ["none", "unique", "multiple"][solutions.len()];
            if status == "unique" { difficulty = "hard"; }
            search = Some(found);
        }
        let line_solves = logic.steps.len() + search.as_ref().map_or(0, |s| s.line_solves);
        let guesses = search.as_ref().map_or(0, |s| s.guesses.len());
        let max_depth = search.as_ref().map_or(0, |s| s.max_depth);
        Self { simple_grid, logic_grid, simple, logic, simple_result, logic_result, status, difficulty, search, solutions, line_solves, guesses, max_depth }
    }
}

fn clue_statistics(rows: &Clues, columns: &Clues) -> String {
    let row_blocks: usize = rows.iter().map(Vec::len).sum();
    let column_blocks: usize = columns.iter().map(Vec::len).sum();
    let filled: usize = rows.iter().flatten().sum();
    let maximum = rows.iter().chain(columns).flatten().copied().max().unwrap_or(0);
    let fixed = rows.iter().filter(|clue| clue.is_empty() || clues::span(clue) == columns.len()).count()
        + columns.iter().filter(|clue| clue.is_empty() || clues::span(clue) == rows.len()).count();
    format!("row_blocks={row_blocks} column_blocks={column_blocks} filled={filled} max_block={maximum} fixed_lines={fixed}")
}
fn step_statistics(propagation: &Propagation) -> String {
    let (mut productive, mut idle, mut best) = (0, 0, 0);
    let mut at = "-".to_owned();
    for step in &propagation.steps {
        if step.contradiction { continue; }
        if step.gain > 0 { productive += 1; } else { idle += 1; }
        if step.gain > best { best = step.gain; at = step.label(); }
    }
    format!("productive={productive} idle={idle} best={best} at={at}")
}
fn unknown_summary(grid: &Grid, row: bool) -> String {
    (0..if row { grid.len() } else { grid[0].len() }).filter_map(|index| {
        let count = propagation::cells(grid, row, index).iter().filter(|&&v| v == UNKNOWN).count();
        if count == 0 { None } else { Some(format!("{}:{count}", index + 1)) }
    }).collect::<Vec<_>>().join(" ")
}
fn features(grid: &Grid) -> String {
    let (height, width) = (grid.len(), grid[0].len());
    let mut seen = vec![vec![false; width]; height];
    let (mut filled, mut components, mut largest) = (0, 0, 0);
    let (mut min_row, mut min_column, mut max_row, mut max_column) = (height, width, 0, 0);
    for r in 0..height {
        for c in 0..width {
            if grid[r][c] != FILLED { continue; }
            filled += 1; min_row = min_row.min(r); min_column = min_column.min(c); max_row = max_row.max(r); max_column = max_column.max(c);
            if seen[r][c] { continue; }
            components += 1;
            let mut pending = vec![(r, c)]; seen[r][c] = true;
            let mut size = 0;
            while let Some((rr, cc)) = pending.pop() {
                size += 1;
                for (dr, dc) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                    let (nr, nc) = (rr as isize + dr, cc as isize + dc);
                    if nr >= 0 && nr < height as isize && nc >= 0 && nc < width as isize {
                        let (nr, nc) = (nr as usize, nc as usize);
                        if grid[nr][nc] == FILLED && !seen[nr][nc] { seen[nr][nc] = true; pending.push((nr, nc)); }
                    }
                }
            }
            largest = largest.max(size);
        }
    }
    let mut symmetries = Vec::new();
    for (name, flip_rows, flip_columns) in [("lr", false, true), ("ud", true, false), ("rot180", true, true)] {
        if (0..height).all(|r| (0..width).all(|c| grid[r][c] == grid[if flip_rows { height - 1 - r } else { r }][if flip_columns { width - 1 - c } else { c }])) { symmetries.push(name); }
    }
    let bbox = if filled == 0 { "-".into() } else { format!("{},{},{},{}", min_row + 1, min_column + 1, max_row + 1, max_column + 1) };
    format!("filled={filled} components={components} largest={largest} bbox={bbox} symmetry={}", if symmetries.is_empty() { "none".into() } else { symmetries.join(",") })
}

fn evaluate_givens(puzzle: &Puzzle, analysis: &Analysis) -> Option<String> {
    if puzzle.givens.is_empty() || analysis.status == "multiple" { return None; }
    let unique = analysis.status == "unique";
    let mut accepted = Vec::new();
    for i in 0..puzzle.givens.len() {
        let mut others = puzzle.givens.clone(); others.remove(i);
        let status = Analysis::new(&puzzle.rows, &puzzle.columns, &others).status;
        if status == "unique" || !unique && status == "multiple" { accepted.push(i + 1); }
    }
    Some(format!("givens {}={}", if unique { "redundant" } else { "blame" }, number_list(&accepted)))
}

struct Grading { result: &'static str, lines: Vec<String> }
impl Grading {
    fn new(puzzle: &Puzzle, analysis: &Analysis) -> Self {
        let Some(answer) = &puzzle.answer else { return Self { result: "-", lines: Vec::new() }; };
        let known = determined(answer);
        let partial = known < puzzle.width * puzzle.height;
        let mut rows = Vec::new();
        let mut columns = Vec::new();
        let mut givens = Vec::new();
        let mut mismatches = Vec::new();
        for row in [true, false] {
            for index in 0..if row { puzzle.height } else { puzzle.width } {
                let cells = propagation::cells(answer, row, index);
                let clue = if row { &puzzle.rows[index] } else { &puzzle.columns[index] };
                if line_solver::has_placement(&cells, clue) { continue; }
                if row { rows.push(index + 1); } else { columns.push(index + 1); }
                mismatches.push(format!("mismatch {} expected={} {}", propagation::label(row, index), clues::text(clue, ","),
                    if partial { format!("cells={}", render::state_string(&cells)) } else { format!("got={}", clues::text(&clues::run(&cells), ",")) }));
            }
        }
        let mut taken = HashSet::new();
        for (i, given) in puzzle.givens.iter().enumerate() {
            taken.insert((given.row, given.column));
            let state = answer[given.row][given.column];
            if state != UNKNOWN && state != given.value { givens.push(i + 1); }
        }
        let mismatch = !rows.is_empty() || !columns.is_empty() || !givens.is_empty();
        let result = if partial { "partial" } else if mismatch { "wrong" } else { "correct" };
        let mut text = format!("answer result={result} known={known} rows={} columns={} givens={}", number_list(&rows), number_list(&columns), number_list(&givens));
        if partial {
            let mut extendable = false;
            if !mismatch {
                let mut combined = puzzle.givens.clone();
                for (r, row) in answer.iter().enumerate() {
                    for (c, &value) in row.iter().enumerate() {
                        if value != UNKNOWN && !taken.contains(&(r, c)) { combined.push(Given { row: r, column: c, value }); }
                    }
                }
                extendable = ["unique", "multiple"].contains(&Analysis::new(&puzzle.rows, &puzzle.columns, &combined).status);
            }
            text.push_str(if extendable { " extendable=yes" } else { " extendable=no" });
        }
        if analysis.status == "unique" {
            let differs = answer.iter().enumerate().map(|(r, row)| row.iter().enumerate().filter(|&(c, &state)| state != UNKNOWN && state != analysis.solutions[0][r][c]).count()).sum::<usize>();
            text.push_str(&format!(" differs={differs}"));
        }
        let mut lines = vec![text]; lines.extend(mismatches);
        Self { result, lines }
    }
}

struct Report { puzzle: Puzzle, analysis: Analysis, grading: Grading }
impl Report {
    fn new(puzzle: Puzzle) -> Self {
        let analysis = Analysis::new(&puzzle.rows, &puzzle.columns, &puzzle.givens);
        let grading = Grading::new(&puzzle, &analysis);
        Self { puzzle, analysis, grading }
    }
    fn score(&self) -> usize { self.analysis.line_solves + 25 * self.analysis.guesses }
    fn paragraph(&self) -> Vec<String> {
        let (p, a) = (&self.puzzle, &self.analysis);
        let mut lines = vec![format!("PUZZLE {}", p.name), format!("size={}x{} givens={} status={} difficulty={}", p.width, p.height, p.givens.len(), a.status, a.difficulty),
            format!("clues {}", clue_statistics(&p.rows, &p.columns)),
            format!("simple known={} line_solves={} result={}", determined(&a.simple_grid), a.simple.steps.len(), a.simple_result),
            format!("logic known={} line_solves={} result={}", determined(&a.logic_grid), a.logic.steps.len(), a.logic_result),
            format!("steps {}", step_statistics(&a.logic))];
        if p.width * p.height <= 49 { lines.push(format!("trace {}", a.logic.record())); }
        if a.logic_result == "stuck" { lines.push(format!("stuck rows={} columns={}", unknown_summary(&a.logic_grid, true), unknown_summary(&a.logic_grid, false))); }
        if a.status == "contradiction" {
            let step = a.logic.conflict.as_ref().unwrap();
            lines.push(format!("conflict line={} clue={} cells={}", step.label(), clues::text(if step.row { &p.rows[step.index] } else { &p.columns[step.index] }, ","), render::state_string(&propagation::cells(&a.logic_grid, step.row, step.index))));
        }
        if let Some(search) = &a.search {
            lines.push(format!("search guesses={} max_depth={} backtracks={} solutions={} line_solves={}", search.guesses.len(), search.max_depth, search.backtracks, search.solutions.len(), search.line_solves));
            for g in &search.guesses { lines.push(format!("guess {} depth={} cell={} value={} solves={} known={} result={}", g.number, g.depth, cell_text(g.row, g.column), g.value as char, g.solves, g.known, g.result)); }
        }
        if a.status == "multiple" {
            let cells = differences(&a.solutions[0], &a.solutions[1]);
            lines.push(format!("differ count={} cells={}", cells.len(), cells.iter().map(|&(r, c)| cell_text(r, c)).collect::<Vec<_>>().join(" ")));
        }
        let mut grids = Vec::new();
        if a.status == "contradiction" { grids.push(("partial", &a.logic_grid)); }
        else {
            if a.simple_result == "stuck" { grids.push(("simple", &a.simple_grid)); }
            if a.logic_result == "stuck" { grids.push(("logic", &a.logic_grid)); }
            if a.status == "multiple" { grids.push(("first", &a.solutions[0])); grids.push(("second", &a.solutions[1])); }
        }
        lines.extend(render::grid_display(&grids));
        if a.status == "unique" { lines.push("sheet".into()); lines.extend(render::answer_sheet(&p.rows, &p.columns, &a.solutions[0])); lines.push(format!("picture {}", features(&a.solutions[0]))); }
        if let Some(evaluation) = evaluate_givens(p, a) { lines.push(evaluation); }
        lines.extend(self.grading.lines.clone()); lines
    }
    fn stats(&self) -> String {
        let (p, a) = (&self.puzzle, &self.analysis);
        format!("{},{},{},{},{},{},{},{},{},{},{},{},{}", p.name, a.status, a.difficulty, p.width, p.height, p.givens.len(), determined(&a.simple_grid), determined(&a.logic_grid), a.line_solves, a.guesses, a.max_depth, a.solutions.len(), self.grading.result)
    }
}

struct AnalysisSummary { status: &'static str, difficulty: &'static str, line_solves: usize, guesses: usize }
impl AnalysisSummary {
    fn new(analysis: &Analysis) -> Self { Self { status: analysis.status, difficulty: analysis.difficulty, line_solves: analysis.line_solves, guesses: analysis.guesses } }
}
struct Generation { grid: Grid, rows: Clues, columns: Clues, givens: Vec<Given>, log: Vec<String>, initial: AnalysisSummary, final_analysis: Analysis }
impl Generation {
    fn append(grid: &Grid, givens: &mut Vec<Given>, row: usize, column: usize) -> String {
        let value = grid[row][column]; givens.push(Given { row, column, value });
        format!("cell={} value={}", cell_text(row, column), value as char)
    }
    fn new(grid: Grid) -> Self {
        let rows = grid.iter().map(|row| clues::run(row)).collect();
        let columns = (0..grid[0].len()).map(|c| clues::run(&propagation::cells(&grid, false, c))).collect();
        let mut givens = Vec::new();
        let mut log = Vec::new();
        let mut analysis = Analysis::new(&rows, &columns, &givens);
        let initial = AnalysisSummary::new(&analysis);
        while analysis.status == "multiple" {
            let (r, c) = differences(&analysis.solutions[0], &analysis.solutions[1])[0];
            let added = Self::append(&grid, &mut givens, r, c);
            analysis = Analysis::new(&rows, &columns, &givens);
            log.push(format!("# hint {} {added} status={}", givens.len(), analysis.status));
        }
        for given in givens.clone() {
            let others: Vec<_> = givens.iter().copied().filter(|g| *g != given).collect();
            if Analysis::new(&rows, &columns, &others).status == "unique" { givens = others; log.push(format!("# drop cell={}", cell_text(given.row, given.column))); }
        }
        analysis = Analysis::new(&rows, &columns, &givens);
        let mut number = 0;
        while analysis.difficulty == "hard" {
            let (r, c) = search::guess_cell(&analysis.logic_grid);
            let added = Self::append(&grid, &mut givens, r, c);
            analysis = Analysis::new(&rows, &columns, &givens); number += 1;
            log.push(format!("# logic hint {number} {added} difficulty={}", analysis.difficulty));
        }
        Self { grid, rows, columns, givens, log, initial, final_analysis: analysis }
    }
    fn paragraph(&self, name: &str, reports: &[Report]) -> Vec<String> {
        let duplicate = reports.iter().find(|r| r.puzzle.rows == self.rows && r.puzzle.columns == self.columns).map_or("-", |r| r.puzzle.name.as_str());
        let (a, f) = (&self.initial, &self.final_analysis);
        let mut lines = vec![format!("# picture {name} size={}x{} {}", self.columns.len(), self.rows.len(), features(&self.grid)),
            format!("# clues {} duplicate_of={duplicate}", clue_statistics(&self.rows, &self.columns)),
            format!("# plain status={} difficulty={} line_solves={} guesses={}", a.status, a.difficulty, a.line_solves, a.guesses)];
        lines.extend(self.log.clone());
        lines.push(format!("# final status={} difficulty={} hints={} line_solves={} guesses={}", f.status, f.difficulty, self.givens.len(), f.line_solves, f.guesses));
        lines.extend([format!("PUZZLE {name}"), format!("SIZE {} {}", self.columns.len(), self.rows.len()), "ROWS".into()]);
        lines.extend(self.rows.iter().map(|clue| clues::text(clue, " "))); lines.push("COLUMNS".into()); lines.extend(self.columns.iter().map(|clue| clues::text(clue, " ")));
        let mut givens = self.givens.clone(); givens.sort_by_key(|g| (g.row, g.column));
        for given in givens { lines.push(format!("GIVEN {} {} {}", given.row + 1, given.column + 1, given.value as char)); }
        lines.push("END".into()); lines
    }
}

fn process_puzzles(blocks: Vec<Vec<String>>) -> io::Result<Vec<Report>> {
    let total = blocks.len();
    let mut names = HashSet::new();
    let mut reports = Vec::new();
    let mut output = Vec::new();
    let mut stats = vec!["puzzle,status,difficulty,width,height,givens,simple_known,logic_known,line_solves,guesses,max_depth,solutions,answer".into()];
    for block in blocks {
        let mut puzzle = Puzzle::new(block);
        let error = puzzle.validate(&names); names.insert(puzzle.name.clone());
        if let Some(error) = error { output.push(vec![format!("PUZZLE {}", puzzle.name), format!("error {error}")]); stats.push(format!("{},invalid{}", puzzle.name, ",-".repeat(11))); }
        else { let report = Report::new(puzzle); output.push(report.paragraph()); stats.push(report.stats()); reports.push(report); }
    }
    let mut ranked: Vec<_> = reports.iter().filter(|r| r.analysis.status == "unique").collect();
    let difficulty = |level: &str| -> u8 { match level { "easy" => 0, "medium" => 1, _ => 2 } };
    ranked.sort_by(|a, b| difficulty(a.analysis.difficulty).cmp(&difficulty(b.analysis.difficulty)).then(a.score().cmp(&b.score())).then(a.puzzle.name.cmp(&b.puzzle.name)));
    let mut ranking = vec!["RANKING".into()];
    for (i, r) in ranked.iter().enumerate() { ranking.push(format!("rank {} {} {} score={} size={}x{}", i + 1, r.puzzle.name, r.analysis.difficulty, r.score(), r.puzzle.width, r.puzzle.height)); }
    output.push(ranking);
    let status = |s| reports.iter().filter(|r| r.analysis.status == s).count();
    let level = |s| reports.iter().filter(|r| r.analysis.difficulty == s).count();
    let solves: usize = reports.iter().map(|r| r.analysis.line_solves).sum();
    let guesses: usize = reports.iter().map(|r| r.analysis.guesses).sum();
    output.push(vec![format!("SUMMARY puzzles={total} invalid={} contradiction={} none={} unique={} multiple={} easy={} medium={} hard={} line_solves={solves} guesses={guesses}", total - reports.len(), status("contradiction"), status("none"), status("unique"), status("multiple"), level("easy"), level("medium"), level("hard"))]);
    write_lines("solutions.txt", &paragraphs(output))?; write_lines("stats.csv", &stats)?; Ok(reports)
}

fn process_pictures(blocks: Vec<Vec<String>>, reports: &[Report]) -> io::Result<()> {
    let total = blocks.len();
    let mut names = HashSet::new();
    let mut output = Vec::new();
    let (mut valid, mut unique, mut logic, mut hinted, mut hints) = (0, 0, 0, 0, 0);
    for block in blocks {
        let name = &block[0][8..];
        let grid: Grid = block[1..].iter().map(|line| line.as_bytes().to_vec()).collect();
        let error = if !valid_name(name) { Some("bad name".into()) }
            else if names.contains(name) { Some("duplicate name".into()) }
            else if !(1..=30).contains(&grid.len()) { Some("bad height".into()) }
            else { grid.iter().position(|row| !(1..=30).contains(&row.len()) || row.len() != grid[0].len() || row.iter().any(|v| ![FILLED, EMPTY].contains(v))).map(|i| format!("bad row {}", i + 1)) };
        names.insert(name.to_owned());
        if let Some(error) = error { output.push(vec![format!("# picture {name} error {error}")]); continue; }
        let generated = Generation::new(grid); valid += 1;
        if generated.initial.status == "unique" { unique += 1; }
        if ["easy", "medium"].contains(&generated.initial.difficulty) { logic += 1; }
        if !generated.givens.is_empty() { hinted += 1; }
        hints += generated.givens.len(); output.push(generated.paragraph(name, reports));
    }
    output.push(vec![format!("# SUMMARY pictures={total} invalid={} unique={unique} line_logic={logic} hinted={hinted} hints={hints}", total - valid)]);
    write_lines("generated.txt", &paragraphs(output))
}

fn main() -> io::Result<()> {
    fs::create_dir_all("output")?;
    let reports = process_puzzles(read_blocks("puzzles.txt")?)?;
    process_pictures(read_blocks("pictures.txt")?, &reports)
}
