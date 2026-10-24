use std::collections::BTreeMap;
use std::io::{self, Read};

const COMMANDS: [(&str, usize); 24] = [
    ("NEW", 4), ("PRESET", 2), ("LAYOUT", 2), ("SAFETY", 1), ("RESTART", 0),
    ("REVEAL", 2), ("FLAG", 2), ("UNFLAG", 2), ("QUESTION", 2), ("CHORD", 2),
    ("UNDO", 0), ("SHOW", 0), ("STATUS", 0), ("CELL", 2), ("HISTORY", 1),
    ("REPLAY", 1), ("HINT", 0), ("AUTO", 0), ("ANALYZE", 0), ("PROB", 2),
    ("FRONTIER", 0), ("SOLVE", 0), ("BOARDINFO", 0), ("STATS", 0),
];
type CommandResult<T = ()> = Result<T, String>;

#[derive(Clone, Copy, PartialEq, Eq)]
enum State { Ready, Playing, Won, Lost }

impl State {
    fn name(self) -> &'static str {
        match self { Self::Ready => "ready", Self::Playing => "playing", Self::Won => "won", Self::Lost => "lost" }
    }
    fn finished(self) -> bool { matches!(self, Self::Won | Self::Lost) }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Mark { None, Flag, Question }

#[derive(Clone, Copy)]
enum Safety { Block, Cell, None }

#[derive(Clone, Copy)]
enum MoveKind { Reveal, Flag, Unflag, Question, Chord, AutoReveal, AutoFlag, Guess }

impl MoveKind {
    fn name(self) -> &'static str {
        match self {
            Self::Reveal => "reveal", Self::Flag => "flag", Self::Unflag => "unflag",
            Self::Question => "question", Self::Chord => "chord", Self::AutoReveal => "auto-reveal",
            Self::AutoFlag => "auto-flag", Self::Guess => "guess",
        }
    }
}

#[derive(Clone, Copy)]
struct Move { kind: MoveKind, cell: usize }

struct Snapshot { name: String, revealed: Vec<bool>, marks: Vec<Mark>, moves: usize }

struct Game {
    width: usize,
    height: usize,
    mine_count: i32,
    seed: i64,
    determined: bool,
    mine: Vec<bool>,
    numbers: Vec<usize>,
    neighbors: Vec<Vec<usize>>,
    revealed: Vec<bool>,
    marks: Vec<Mark>,
    state: State,
    exploded: Option<usize>,
    moves: Vec<Move>,
    undo: Vec<Snapshot>,
}

impl Game {
    fn new(width: usize, height: usize, mines: i32, seed: i64) -> Self {
        let cells = width * height;
        let neighbors = (0..cells).map(|cell| {
            let (x, y) = ((cell % width) as isize, (cell / width) as isize);
            let mut list = Vec::new();
            for dy in -1..=1 {
                for dx in -1..=1 {
                    if (dx != 0 || dy != 0) && (0..width as isize).contains(&(x + dx)) && (0..height as isize).contains(&(y + dy)) {
                        list.push((y + dy) as usize * width + (x + dx) as usize);
                    }
                }
            }
            list
        }).collect();
        Self {
            width, height, mine_count: mines, seed, determined: false,
            mine: vec![false; cells], numbers: vec![0; cells], neighbors,
            revealed: vec![false; cells], marks: vec![Mark::None; cells],
            state: State::Ready, exploded: None, moves: Vec::new(), undo: Vec::new(),
        }
    }

    fn cells(&self) -> usize { self.width * self.height }
    fn safe_cells(&self) -> usize { self.cells() - self.mine_count as usize }
    fn coord(&self, cell: usize) -> String { format!("{},{}", cell % self.width, cell / self.width) }
    fn unknown(&self, cell: usize) -> bool { !self.revealed[cell] && self.marks[cell] != Mark::Flag }
    fn remaining(&self) -> i32 { self.mine_count - self.marks.iter().filter(|&&m| m == Mark::Flag).count() as i32 }
    fn opened(&self) -> usize { self.revealed.iter().filter(|&&open| open).count() }

    fn copy(&self, keep_moves: bool) -> Self {
        Self {
            width: self.width, height: self.height, mine_count: self.mine_count, seed: self.seed,
            determined: self.determined, mine: self.mine.clone(), numbers: self.numbers.clone(), neighbors: self.neighbors.clone(),
            revealed: self.revealed.clone(), marks: self.marks.clone(), state: self.state, exploded: self.exploded,
            moves: if keep_moves { self.moves.clone() } else { Vec::new() }, undo: Vec::new(),
        }
    }

    fn restart(&mut self) {
        self.revealed.fill(false);
        self.marks.fill(Mark::None);
        self.moves.clear();
        self.undo.clear();
        self.exploded = None;
        self.state = if self.determined { State::Playing } else { State::Ready };
    }

    fn number_board(&mut self) {
        self.numbers = self.neighbors.iter().map(|list| list.iter().filter(|&&cell| self.mine[cell]).count()).collect();
    }

    fn place_mines(&mut self, first: usize, safety: Safety) {
        let (sx, sy) = (first % self.width, first / self.width);
        let mut candidates: Vec<_> = (0..self.cells()).filter(|&cell| match safety {
            Safety::None => true,
            Safety::Cell => cell != first,
            Safety::Block => (cell % self.width).abs_diff(sx) >= 2 || (cell / self.width).abs_diff(sy) >= 2,
        }).collect();
        let mut state = self.seed;
        for _ in 0..self.mine_count {
            state = 48271 * state % 2147483647;
            let selected = candidates.remove((state % candidates.len() as i64) as usize);
            self.mine[selected] = true;
        }
        self.number_board();
        self.determined = true;
        self.state = State::Playing;
    }

    fn reveal(&mut self, cell: usize, safety: Safety) -> usize {
        if !self.determined { self.place_mines(cell, safety); }
        if self.mine[cell] { self.state = State::Lost; self.exploded = Some(cell); return 0; }
        let mut queue = vec![cell];
        self.revealed[cell] = true;
        self.marks[cell] = Mark::None;
        let mut head = 0;
        while head < queue.len() {
            let current = queue[head];
            head += 1;
            if self.numbers[current] != 0 { continue; }
            for &next in &self.neighbors[current] {
                if !self.unknown(next) { continue; }
                self.revealed[next] = true;
                self.marks[next] = Mark::None;
                queue.push(next);
            }
        }
        queue.len()
    }

    fn chord(&mut self, cell: usize, safety: Safety) -> usize {
        let mut opened = 0;
        for i in 0..self.neighbors[cell].len() {
            let next = self.neighbors[cell][i];
            if self.unknown(next) { opened += self.reveal(next, safety); }
            if self.state == State::Lost { break; }
        }
        opened
    }

    fn check_win(&mut self) {
        if self.state != State::Playing || self.opened() != self.safe_cells() { return; }
        self.state = State::Won;
        for cell in 0..self.cells() { if self.mine[cell] { self.marks[cell] = Mark::Flag; } }
    }

    fn show(&self) {
        for y in 0..self.height {
            let row: String = (y * self.width..(y + 1) * self.width).map(|cell| {
                if self.state == State::Lost && self.mine[cell] {
                    if self.exploded == Some(cell) { '!' } else if self.marks[cell] == Mark::Flag { 'F' } else { '*' }
                } else if self.state == State::Lost && self.marks[cell] == Mark::Flag { 'X' }
                else if self.revealed[cell] { if self.numbers[cell] == 0 { '.' } else { (b'0' + self.numbers[cell] as u8) as char } }
                else { match self.marks[cell] { Mark::None => '#', Mark::Flag => 'F', Mark::Question => '?' } }
            }).collect();
            println!("{row}");
        }
    }

    fn ending_output(&self) {
        match self.state {
            State::Lost => { println!("boom {}", self.coord(self.exploded.unwrap())); self.show(); }
            State::Won => println!("win moves {}", self.moves.len()),
            _ => {}
        }
    }

    fn constraints(&self) -> Vec<Constraint> {
        let mut result = Vec::new();
        for cell in 0..self.cells() {
            if !self.revealed[cell] || self.numbers[cell] == 0 { continue; }
            let flags = self.neighbors[cell].iter().filter(|&&next| self.marks[next] == Mark::Flag).count();
            let unknown: Vec<_> = self.neighbors[cell].iter().copied().filter(|&next| self.unknown(next)).collect();
            if !unknown.is_empty() { result.push(Constraint { cell, remaining: self.numbers[cell] as i32 - flags as i32, unknown }); }
        }
        result
    }

    fn deduce(&self) -> Deduction {
        let constraints = self.constraints();
        let mut result = Deduction::default();
        for safe in [true, false] {
            for c in &constraints {
                let target = if safe { 0 } else { c.unknown.len() as i32 };
                if c.remaining != target { continue; }
                for &cell in &c.unknown { result.add(safe, cell, Reason::Single(c.cell)); }
            }
            if !result.empty() { return result; }
        }
        let mut at = vec![None; self.cells()];
        for (i, c) in constraints.iter().enumerate() { at[c.cell] = Some(i); }
        for a in &constraints {
            let (ax, ay) = (a.cell % self.width, a.cell / self.width);
            // A nonempty subset pair shares a neighbor, so its centers are within two cells.
            for y in ay.saturating_sub(2)..=(ay + 2).min(self.height - 1) {
                for x in ax.saturating_sub(2)..=(ax + 2).min(self.width - 1) {
                    let Some(index) = at[y * self.width + x] else { continue; };
                    let b = &constraints[index];
                    if a.unknown.len() >= b.unknown.len() || !a.unknown.iter().all(|cell| b.unknown.contains(cell)) { continue; }
                    let difference = b.remaining - a.remaining;
                    if difference != 0 && difference != (b.unknown.len() - a.unknown.len()) as i32 { continue; }
                    for &cell in &b.unknown {
                        if !a.unknown.contains(&cell) { result.add(difference == 0, cell, Reason::Subset(a.cell, b.cell)); }
                    }
                }
            }
        }
        if !result.empty() { return result; }
        if self.state == State::Playing && self.remaining() == 0 {
            for cell in 0..self.cells() { if self.unknown(cell) { result.add(true, cell, Reason::Count); } }
        }
        result
    }

    fn hint(&self) {
        let result = self.deduce();
        if let Some((&cell, reason)) = result.safe.iter().next() {
            println!("hint safe {} by {}", self.coord(cell), reason.text(self));
        } else if let Some((&cell, reason)) = result.mines.iter().next() {
            println!("hint mine {} by {}", self.coord(cell), reason.text(self));
        } else { println!("hint none"); }
    }

    fn auto_play(&mut self, safety: Safety) -> AutoResult {
        let mut total = AutoResult::default();
        while self.state == State::Playing {
            let result = self.deduce();
            if result.empty() { break; }
            total.rounds += 1;
            for &cell in result.safe.keys() {
                if self.revealed[cell] { continue; }
                self.moves.push(Move { kind: MoveKind::AutoReveal, cell });
                total.opened += self.reveal(cell, safety);
                self.check_win();
                if self.state.finished() { return total; }
            }
            for &cell in result.mines.keys() {
                if !self.unknown(cell) { continue; }
                self.marks[cell] = Mark::Flag;
                total.flagged += 1;
                self.moves.push(Move { kind: MoveKind::AutoFlag, cell });
            }
        }
        total
    }

    fn solve(&mut self, safety: Safety) -> AutoResult {
        let mut total = AutoResult::default();
        while !self.state.finished() {
            let step = self.auto_play(safety);
            total.rounds += step.rounds;
            total.flagged += step.flagged;
            total.opened += step.opened;
            if self.state.finished() { break; }
            let mut frontier = Frontier::new(self);
            for id in 0..frontier.components.len() { frontier.count(id); }
            let unknown = (0..self.cells()).filter(|&cell| self.unknown(cell)).count() as i64;
            let remaining = i64::from(self.remaining().max(0));
            let mut choice = None;
            let (mut best_numerator, mut best_denominator) = (0, 1);
            for cell in 0..self.cells() {
                if !self.unknown(cell) { continue; }
                let (numerator, denominator) = if let Some(id) = frontier.component_of[cell] {
                    (frontier.ways[cell], frontier.components[id].configs)
                } else { (remaining, unknown) };
                if denominator == 0 { continue; }
                if choice.is_none() || numerator * best_denominator < best_numerator * denominator {
                    choice = Some(cell);
                    best_numerator = numerator;
                    best_denominator = denominator;
                }
            }
            let Some(cell) = choice else { break; };
            total.guesses += 1;
            self.moves.push(Move { kind: MoveKind::Guess, cell });
            total.opened += self.reveal(cell, safety);
            self.check_win();
        }
        total
    }

    fn probability(&self, cell: usize) {
        let mut frontier = Frontier::new(self);
        let Some(id) = frontier.component_of[cell] else { println!("prob {} unconstrained", self.coord(cell)); return; };
        frontier.count(id);
        let component = &frontier.components[id];
        if component.configs == 0 { println!("prob {} inconsistent", self.coord(cell)); }
        else {
            println!("prob {} {} size {} configs {}", self.coord(cell), fraction(frontier.ways[cell], component.configs), component.cells.len(), component.configs);
        }
    }

    fn frontier_report(&self) {
        let mut frontier = Frontier::new(self);
        let total: usize = frontier.components.iter().map(|c| c.cells.len()).sum();
        println!("frontier {} components {}", total, frontier.components.len());
        for id in 0..frontier.components.len() {
            frontier.count(id);
            let component = &frontier.components[id];
            print!("component {} size {}", self.coord(component.cells[0]), component.cells.len());
            if component.configs == 0 { println!(" inconsistent"); }
            else { println!(" configs {} min {} max {}", component.configs, component.minimum, component.maximum); }
        }
    }

    fn replay(&self, count: usize, safety: Safety) {
        let mut copy = self.copy(false);
        copy.restart();
        for movement in &self.moves[..count] {
            let cell = movement.cell;
            match movement.kind {
                MoveKind::Reveal | MoveKind::AutoReveal | MoveKind::Guess => { copy.reveal(cell, safety); }
                MoveKind::Chord => { copy.chord(cell, safety); }
                MoveKind::Flag | MoveKind::AutoFlag => copy.marks[cell] = Mark::Flag,
                MoveKind::Unflag => copy.marks[cell] = Mark::None,
                MoveKind::Question => copy.marks[cell] = if copy.marks[cell] == Mark::Question { Mark::None } else { Mark::Question },
            }
            copy.check_win();
        }
        println!("replay {count}/{}", self.moves.len());
        copy.show();
    }

    fn board_info(&self) {
        let mut visited = vec![false; self.cells()];
        let (mut openings, mut largest, mut isolated) = (0, 0_usize, 0);
        for cell in 0..self.cells() {
            if self.mine[cell] { continue; }
            if self.numbers[cell] != 0 {
                if !self.neighbors[cell].iter().any(|&next| !self.mine[next] && self.numbers[next] == 0) { isolated += 1; }
            } else if !visited[cell] {
                openings += 1;
                let mut covered = vec![false; self.cells()];
                let mut queue = vec![cell];
                visited[cell] = true;
                covered[cell] = true;
                let mut head = 0;
                while head < queue.len() {
                    let current = queue[head];
                    head += 1;
                    for &next in &self.neighbors[current] {
                        covered[next] = true;
                        if self.numbers[next] == 0 && !visited[next] { visited[next] = true; queue.push(next); }
                    }
                }
                largest = largest.max(covered.iter().filter(|&&cell| cell).count());
            }
        }
        println!("3bv {} openings {} largest {} mines {} safe {}", openings + isolated, openings, largest, self.mine_count, self.safe_cells());
    }

    fn process(&mut self, command: &str, cell: usize, value: i64, safety: Safety) -> CommandResult {
        if matches!(command, "REVEAL" | "FLAG" | "UNFLAG" | "QUESTION" | "PROB") {
            if self.revealed[cell] { return Err("already revealed".into()); }
            if matches!(command, "REVEAL" | "PROB") && self.marks[cell] == Mark::Flag { return Err("flagged".into()); }
            if command == "FLAG" && self.marks[cell] == Mark::Flag { return Err("already flagged".into()); }
            if command == "UNFLAG" && self.marks[cell] != Mark::Flag { return Err("not flagged".into()); }
        }
        match command {
            "RESTART" => { self.restart(); println!("restart {}x{} mines {}", self.width, self.height, self.mine_count); }
            "REVEAL" => {
                self.moves.push(Move { kind: MoveKind::Reveal, cell });
                let opened = self.reveal(cell, safety);
                if self.state != State::Lost { println!("revealed {opened}"); self.check_win(); }
                self.ending_output();
            }
            "FLAG" => {
                self.marks[cell] = Mark::Flag;
                self.moves.push(Move { kind: MoveKind::Flag, cell });
                println!("flagged {} left {}", self.coord(cell), self.remaining());
            }
            "UNFLAG" => {
                self.marks[cell] = Mark::None;
                self.moves.push(Move { kind: MoveKind::Unflag, cell });
                println!("unflagged {} left {}", self.coord(cell), self.remaining());
            }
            "QUESTION" => {
                self.moves.push(Move { kind: MoveKind::Question, cell });
                self.marks[cell] = if self.marks[cell] == Mark::Question { Mark::None } else { Mark::Question };
                println!("{} {} left {}", if self.marks[cell] == Mark::None { "unmarked" } else { "questioned" }, self.coord(cell), self.remaining());
            }
            "CHORD" => {
                if !self.revealed[cell] { return Err("not revealed".into()); }
                if self.numbers[cell] == 0 { return Err("no number".into()); }
                let flags = self.neighbors[cell].iter().filter(|&&next| self.marks[next] == Mark::Flag).count();
                if flags != self.numbers[cell] { return Err(format!("flags {flags} of {}", self.numbers[cell])); }
                if !self.neighbors[cell].iter().any(|&next| self.unknown(next)) { return Err("nothing to reveal".into()); }
                self.moves.push(Move { kind: MoveKind::Chord, cell });
                let opened = self.chord(cell, safety);
                if self.state != State::Lost { println!("chorded {opened}"); self.check_win(); }
                self.ending_output();
            }
            "UNDO" => {
                let snapshot = self.undo.pop().ok_or_else(|| "nothing to undo".to_string())?;
                self.revealed = snapshot.revealed;
                self.marks = snapshot.marks;
                // Successful operations only append, so the saved prefix is still intact.
                self.moves.truncate(snapshot.moves);
                println!("undo {} moves {}", snapshot.name, self.moves.len());
            }
            "SHOW" => self.show(),
            "STATUS" => println!("status {} left {} moves {} revealed {}/{}", self.state.name(), self.remaining(), self.moves.len(), self.opened(), self.safe_cells()),
            "CELL" => {
                if self.revealed[cell] {
                    let flags = self.neighbors[cell].iter().filter(|&&next| self.marks[next] == Mark::Flag).count();
                    let unknown = self.neighbors[cell].iter().filter(|&&next| self.unknown(next)).count();
                    println!("cell {} number {} flags {} unknown {}", self.coord(cell), self.numbers[cell], flags, unknown);
                } else {
                    let opened = self.neighbors[cell].iter().filter(|&&next| self.revealed[next]).count();
                    let mark = match self.marks[cell] { Mark::None => "none", Mark::Flag => "flag", Mark::Question => "question" };
                    println!("cell {} hidden mark {} open {}", self.coord(cell), mark, opened);
                }
            }
            "HISTORY" => {
                println!("history {}", self.moves.len());
                let count = value.min(self.moves.len() as i64) as usize;
                for i in self.moves.len() - count..self.moves.len() {
                    let movement = self.moves[i];
                    println!("{} {} {}", i + 1, movement.kind.name(), self.coord(movement.cell));
                }
            }
            "REPLAY" => {
                if value > self.moves.len() as i64 { return Err(format!("no move {value}")); }
                self.replay(value as usize, safety);
            }
            "HINT" => self.hint(),
            "AUTO" | "SOLVE" => {
                let result = if command == "AUTO" { self.auto_play(safety) } else { self.solve(safety) };
                if command == "SOLVE" { println!("solve guesses {} rounds {} flagged {} revealed {}", result.guesses, result.rounds, result.flagged, result.opened); }
                else { println!("auto rounds {} flagged {} revealed {}", result.rounds, result.flagged, result.opened); }
                self.ending_output();
            }
            "ANALYZE" => {
                let mut copy = self.copy(true);
                let result = copy.auto_play(safety);
                match copy.state {
                    State::Lost => println!("analyze boom {} rounds {}", copy.coord(copy.exploded.unwrap()), result.rounds),
                    State::Won => println!("analyze clear rounds {}", result.rounds),
                    _ => println!("analyze stuck rounds {} revealed {}/{}", result.rounds, copy.opened(), copy.safe_cells()),
                }
            }
            "PROB" => self.probability(cell),
            "FRONTIER" => self.frontier_report(),
            "BOARDINFO" => self.board_info(),
            _ => unreachable!(),
        }
        Ok(())
    }
}

struct Constraint { cell: usize, remaining: i32, unknown: Vec<usize> }

#[derive(Clone, Copy)]
enum Reason { Single(usize), Subset(usize, usize), Count }

impl Reason {
    fn text(self, game: &Game) -> String {
        match self {
            Self::Single(cell) => format!("single {}", game.coord(cell)),
            Self::Subset(a, b) => format!("subset {} {}", game.coord(a), game.coord(b)),
            Self::Count => "count".into(),
        }
    }
}

#[derive(Default)]
struct Deduction { safe: BTreeMap<usize, Reason>, mines: BTreeMap<usize, Reason> }

impl Deduction {
    fn empty(&self) -> bool { self.safe.is_empty() && self.mines.is_empty() }
    fn add(&mut self, safe: bool, cell: usize, reason: Reason) {
        let side = if safe { &mut self.safe } else { &mut self.mines };
        side.entry(cell).or_insert(reason);
    }
}

#[derive(Default)]
struct AutoResult { rounds: usize, flagged: usize, opened: usize, guesses: usize }

#[derive(Default)]
struct Component { cells: Vec<usize>, configs: i64, minimum: usize, maximum: usize }

struct Frontier {
    constraints: Vec<Constraint>,
    component_of: Vec<Option<usize>>,
    components: Vec<Component>,
    ways: Vec<i64>,
}

fn root(parent: &mut [usize], mut cell: usize) -> usize {
    while parent[cell] != cell { parent[cell] = parent[parent[cell]]; cell = parent[cell]; }
    cell
}

impl Frontier {
    fn new(game: &Game) -> Self {
        let constraints = game.constraints();
        let mut parent: Vec<_> = (0..game.cells()).collect();
        let mut present = vec![false; game.cells()];
        for c in &constraints {
            for &cell in &c.unknown {
                present[cell] = true;
                let left = root(&mut parent, cell);
                let right = root(&mut parent, c.unknown[0]);
                parent[left] = right;
            }
        }
        let mut ids = vec![None; game.cells()];
        let mut component_of = vec![None; game.cells()];
        let mut components = Vec::<Component>::new();
        for cell in 0..game.cells() {
            if !present[cell] { continue; }
            let representative = root(&mut parent, cell);
            let id = if let Some(id) = ids[representative] { id } else {
                let id = components.len();
                ids[representative] = Some(id);
                components.push(Component::default());
                id
            };
            component_of[cell] = Some(id);
            components[id].cells.push(cell);
        }
        Self { constraints, component_of, components, ways: vec![0; game.cells()] }
    }

    fn count(&mut self, id: usize) {
        let cells = &self.components[id].cells;
        let mut local = vec![0; self.component_of.len()];
        for (i, &cell) in cells.iter().enumerate() { local[cell] = i; }
        let constraints = self.constraints.iter().filter(|c| self.component_of[c.unknown[0]] == Some(id))
            .map(|c| (c.unknown.iter().fold(0, |mask, &cell| mask | (1_u32 << local[cell])), c.remaining)).collect();
        let mut search = Search { size: cells.len(), constraints, configs: 0, minimum: cells.len() + 1, maximum: 0, ways: vec![0; cells.len()] };
        search.visit(0, 0);
        for (i, &cell) in cells.iter().enumerate() { self.ways[cell] = search.ways[i]; }
        let component = &mut self.components[id];
        component.configs = search.configs;
        component.minimum = search.minimum;
        component.maximum = search.maximum;
    }
}

struct Search { size: usize, constraints: Vec<(u32, i32)>, configs: i64, minimum: usize, maximum: usize, ways: Vec<i64> }

impl Search {
    fn visit(&mut self, depth: usize, mines: u32) {
        let assigned = (1_u32 << depth) - 1;
        for &(mask, target) in &self.constraints {
            let used = (mask & mines).count_ones() as i32;
            let left = (mask & !assigned).count_ones() as i32;
            if used > target || used + left < target { return; }
        }
        if depth == self.size {
            let count = mines.count_ones() as usize;
            self.configs += 1;
            self.minimum = self.minimum.min(count);
            self.maximum = self.maximum.max(count);
            for i in 0..self.size { if mines & (1 << i) != 0 { self.ways[i] += 1; } }
        } else {
            self.visit(depth + 1, mines);
            self.visit(depth + 1, mines | (1 << depth));
        }
    }
}

fn fraction(numerator: i64, denominator: i64) -> String {
    let (mut a, mut b) = (numerator, denominator);
    while b != 0 { (a, b) = (b, a % b); }
    format!("{}/{}", numerator / a, denominator / a)
}

fn number_word(word: &str) -> CommandResult<i64> {
    if word.len() > 10 || (word.len() > 1 && word.starts_with('0')) || !word.bytes().all(|b| b.is_ascii_digit()) {
        Err("bad arguments".into())
    } else { Ok(word.parse().unwrap()) }
}

#[derive(Default)]
struct Statistics { played: usize, won: usize, lost: usize, streak: usize, best: usize, fastest: Option<usize> }

impl Statistics {
    fn finish(&mut self, game: &Game) {
        self.played += 1;
        if game.state == State::Won {
            self.won += 1;
            self.streak += 1;
            self.best = self.best.max(self.streak);
            self.fastest = Some(self.fastest.map_or(game.moves.len(), |old| old.min(game.moves.len())));
        } else { self.lost += 1; self.streak = 0; }
    }

    fn show(&self) {
        let rate = if self.played == 0 { "-".into() } else { format!("{}%", 100 * self.won / self.played) };
        let fastest = self.fastest.map_or_else(|| "-".into(), |n| n.to_string());
        println!("stats played {} won {} lost {} rate {} streak {} best {} fastest {}", self.played, self.won, self.lost, rate, self.streak, self.best, fastest);
    }
}

struct Table { game: Option<Game>, safety: Safety, stats: Statistics }

impl Table {
    fn layout(&mut self, width: usize, height: usize, rows: &[&str]) -> CommandResult {
        for (i, row) in rows.iter().enumerate() {
            if row.len() != width || !row.bytes().all(|b| b == b'*' || b == b'.') { return Err(format!("bad row {}", i + 1)); }
        }
        let mine: Vec<_> = rows.iter().flat_map(|row| row.bytes().map(|b| b == b'*')).collect();
        let count = mine.iter().filter(|&&cell| cell).count();
        if count == 0 || count == width * height { return Err(format!("bad mine count {count}")); }
        let mut game = Game::new(width, height, count as i32, 0);
        game.mine = mine;
        game.determined = true;
        game.state = State::Playing;
        game.number_board();
        self.game = Some(game);
        println!("layout {width}x{height} mines {count}");
        Ok(())
    }

    fn execute(&mut self, words: &[&str]) -> CommandResult {
        let command = words[0];
        let &(_, arguments) = COMMANDS.iter().find(|&&(name, _)| name == command).ok_or_else(|| format!("unknown command {command}"))?;
        if words.len() != arguments + 1 { return Err("bad arguments".into()); }
        let mut values = Vec::new();
        let mut safety = self.safety;
        if command == "PRESET" {
            let (width, height, mines) = match words[1] {
                "beginner" => (9, 9, 10), "intermediate" => (16, 16, 40), "expert" => (30, 16, 99),
                _ => return Err("bad arguments".into()),
            };
            values = vec![width, height, mines, number_word(words[2])?];
        } else if command == "SAFETY" {
            safety = match words[1] {
                "block" => Safety::Block, "cell" => Safety::Cell, "none" => Safety::None,
                _ => return Err("bad arguments".into()),
            };
        } else { for word in &words[1..] { values.push(number_word(word)?); } }
        if matches!(command, "NEW" | "PRESET") {
            let (width, height, mines, seed) = (values[0], values[1], values[2], values[3]);
            if !(1..=30).contains(&width) || !(1..=30).contains(&height) || mines < 1 || mines > width * height - 9 || !(1..=2147483646).contains(&seed) {
                return Err("bad value".into());
            }
            self.game = Some(Game::new(width as usize, height as usize, mines as i32, seed));
            println!("new {width}x{height} mines {mines}");
            return Ok(());
        }
        if command == "HISTORY" && values[0] == 0 { return Err("bad value".into()); }
        if command == "SAFETY" { self.safety = safety; println!("safety {}", words[1]); return Ok(()); }
        if command == "STATS" { self.stats.show(); return Ok(()); }
        let game = self.game.as_mut().ok_or_else(|| "no game".to_string())?;
        let has_cell = matches!(command, "REVEAL" | "FLAG" | "UNFLAG" | "QUESTION" | "CHORD" | "CELL" | "PROB");
        if has_cell && (values[0] >= game.width as i64 || values[1] >= game.height as i64) { return Err("out of range".into()); }
        let needs_unfinished = matches!(command, "REVEAL" | "FLAG" | "UNFLAG" | "QUESTION" | "CHORD" | "UNDO" | "HINT" | "AUTO" | "ANALYZE" | "PROB" | "FRONTIER" | "SOLVE");
        if needs_unfinished && game.state.finished() { return Err("game over".into()); }
        if matches!(command, "ANALYZE" | "BOARDINFO") && !game.determined { return Err("not started".into()); }
        let records_undo = matches!(command, "REVEAL" | "FLAG" | "UNFLAG" | "QUESTION" | "CHORD" | "AUTO" | "SOLVE");
        let snapshot = records_undo.then(|| Snapshot {
            name: command.to_ascii_lowercase(), revealed: game.revealed.clone(), marks: game.marks.clone(), moves: game.moves.len(),
        });
        let was_finished = game.state.finished();
        let cell = if has_cell { values[1] as usize * game.width + values[0] as usize } else { 0 };
        game.process(command, cell, values.first().copied().unwrap_or(0), safety)?;
        if let Some(snapshot) = snapshot { if game.moves.len() > snapshot.moves { game.undo.push(snapshot); } }
        if !was_finished && game.state.finished() { self.stats.finish(game); }
        Ok(())
    }
}

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut lines = input.lines();
    let count: usize = lines.next().unwrap().parse().unwrap();
    let mut table = Table { game: None, safety: Safety::Block, stats: Statistics::default() };
    for _ in 0..count {
        let words: Vec<_> = lines.next().unwrap().split(' ').collect();
        let result = if words[0] == "LAYOUT" {
            let width = words[1].parse().unwrap();
            let height = words[2].parse().unwrap();
            let rows: Vec<_> = (0..height).map(|_| lines.next().unwrap()).collect();
            table.layout(width, height, &rows)
        } else { table.execute(&words) };
        if let Err(error) = result { println!("error: {error}"); }
    }
}
