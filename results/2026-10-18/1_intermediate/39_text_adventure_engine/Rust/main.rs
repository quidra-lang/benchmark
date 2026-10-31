use std::collections::{BTreeMap, BTreeSet};
use std::io::{self, BufWriter, Read, Write};

const DIRECTIONS: [&str; 6] = ["north", "south", "east", "west", "up", "down"];
type Reply<T> = Result<T, String>;
fn fail<T>(message: impl Into<String>) -> Reply<T> { Err(message.into()) }
fn direction(word: &str) -> Option<usize> {
    DIRECTIONS.iter().position(|name| word == *name || word == &name[..1])
}
fn words(line: &str) -> Vec<String> {
    line.split_ascii_whitespace().map(str::to_ascii_lowercase)
        .filter(|word| !matches!(word.as_str(), "the" | "a" | "an")).collect()
}
fn all(phrase: &[String]) -> bool { phrase.len() == 1 && phrase[0] == "all" }

#[derive(Clone, Copy, PartialEq, Eq)]
enum Place { Nowhere, Floor(usize), Player, Inside(usize) }
#[derive(Clone, Copy, PartialEq, Eq)]
enum ContainerState { Open, Closed, Locked }
impl ContainerState {
    fn name(self) -> &'static str { match self { Self::Open => "open", Self::Closed => "closed", Self::Locked => "locked" } }
}
#[derive(Clone, Copy)]
struct Exit { destination: usize, key: Option<usize>, locked: bool }
#[derive(Clone, Copy, PartialEq, Eq)]
enum EndStatus { Won, Dead }
#[derive(Clone)]
struct State {
    room: usize,
    places: Vec<Place>,
    containers: Vec<ContainerState>,
    fuel: Vec<i32>,
    lit: Vec<bool>,
    exits: Vec<[Option<Exit>; 6]>,
    flags: BTreeSet<String>,
    visited: Vec<bool>,
    bonus: i32,
    moves: i32,
    darkness: i32,
    ended: Option<EndStatus>,
}
impl State {
    fn new(rooms: usize, items: usize) -> Self {
        Self { room: 0, places: vec![Place::Nowhere; items], containers: vec![ContainerState::Open; items],
            fuel: vec![0; items], lit: vec![false; items], exits: vec![[None; 6]; rooms], flags: BTreeSet::new(),
            visited: vec![false; rooms], bonus: 0, moves: 0, darkness: 0, ended: None }
    }
}
#[derive(Default)]
struct Room { name: String, dark: bool, description: Vec<String> }
#[derive(Default)]
struct Item {
    name: String, nouns: BTreeSet<String>, name_words: BTreeSet<String>, details: Vec<String>,
    weight: i32, treasure: Option<i32>, light: bool, capacity: Option<i32>, key: Option<usize>, fixed: bool,
}
#[derive(Clone, Copy, PartialEq, Eq)]
enum Trigger { Enter(usize), Use(usize, usize) }
enum Effect { Message(String), Open(usize, usize, usize), Move(usize, Place), Flag(String, bool), Points(i32) }
struct Rule { trigger: Trigger, condition: Option<(String, bool)>, effect: Effect }

fn read_rule(input: &[String], mut at: usize, trigger: Trigger, rooms: &BTreeMap<String, usize>, items: &BTreeMap<String, usize>) -> Rule {
    let condition = if matches!(input[at].as_str(), "IF" | "UNLESS") {
        let condition = Some((input[at + 1].clone(), input[at] == "IF")); at += 2; condition
    } else { None };
    let effect = match input[at].as_str() {
        "MESSAGE" => Effect::Message(input[at + 1..].join(" ")),
        "OPEN" => Effect::Open(rooms[&input[at + 1]], direction(&input[at + 2]).unwrap(), rooms[&input[at + 3]]),
        "REMOVE" => Effect::Move(items[&input[at + 1]], Place::Nowhere),
        "ADD" => Effect::Move(items[&input[at + 1]], Place::Floor(rooms[&input[at + 2]])),
        "SET" | "CLEAR" => Effect::Flag(input[at + 1].clone(), input[at] == "SET"),
        "POINTS" => Effect::Points(input[at + 1].parse().unwrap()),
        _ => unreachable!(),
    };
    Rule { trigger, condition, effect }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Verb { Go, Look, Examine, Take, Drop, Put, Inventory, Open, Close, Unlock, Lock, Use, Light, Extinguish, Wait, Score, Save, Restore, Verbose, Brief }
impl Verb {
    fn parse(word: &str) -> Option<Self> {
        Some(match word {
            "go" | "walk" | "run" => Self::Go, "look" | "l" => Self::Look,
            "examine" | "x" | "inspect" | "read" => Self::Examine, "take" | "get" | "grab" => Self::Take,
            "drop" | "discard" => Self::Drop, "put" | "insert" | "place" => Self::Put,
            "inventory" | "inv" | "i" => Self::Inventory, "open" => Self::Open, "close" | "shut" => Self::Close,
            "unlock" => Self::Unlock, "lock" => Self::Lock, "use" | "apply" => Self::Use,
            "light" | "ignite" => Self::Light, "extinguish" | "douse" | "snuff" => Self::Extinguish,
            "wait" | "z" => Self::Wait, "score" => Self::Score, "save" => Self::Save,
            "restore" | "load" => Self::Restore, "verbose" => Self::Verbose, "brief" => Self::Brief,
            _ => return None,
        })
    }
    fn name(self) -> &'static str {
        match self {
            Self::Go => "go", Self::Look => "look", Self::Examine => "examine", Self::Take => "take", Self::Drop => "drop",
            Self::Put => "put", Self::Inventory => "inventory", Self::Open => "open", Self::Close => "close", Self::Unlock => "unlock",
            Self::Lock => "lock", Self::Use => "use", Self::Light => "light", Self::Extinguish => "extinguish", Self::Wait => "wait",
            Self::Score => "score", Self::Save => "save", Self::Restore => "restore", Self::Verbose => "verbose", Self::Brief => "brief",
        }
    }
    fn no_arguments(self) -> bool {
        matches!(self, Self::Look | Self::Inventory | Self::Wait | Self::Score | Self::Save | Self::Restore | Self::Verbose | Self::Brief)
    }
    fn action(self) -> bool {
        matches!(self, Self::Go | Self::Take | Self::Drop | Self::Put | Self::Open | Self::Close | Self::Unlock | Self::Lock | Self::Use | Self::Light | Self::Extinguish | Self::Wait)
    }
}

struct Adventure {
    rooms: Vec<Room>, items: Vec<Item>, rules: Vec<Rule>, vocabulary: BTreeSet<String>,
    trophy: usize, max_weight: i32, state: State, saved: Option<State>, pronoun: Option<usize>,
    previous: Option<String>, verbose: bool, output: Vec<String>,
}
impl Adventure {
    fn new(definitions: &[Vec<String>]) -> Self {
        let room_names: Vec<String> = definitions.iter().filter(|line| line[0] == "ROOM").map(|line| line[1].clone()).collect();
        let mut item_names: Vec<String> = definitions.iter().filter(|line| line[0] == "ITEM").map(|line| line[1].clone()).collect();
        item_names.sort();
        let room_ids: BTreeMap<String, usize> = room_names.iter().enumerate().map(|(i, name)| (name.clone(), i)).collect();
        let item_ids: BTreeMap<String, usize> = item_names.iter().enumerate().map(|(i, name)| (name.clone(), i)).collect();
        let mut rooms: Vec<Room> = room_names.iter().map(|_| Room::default()).collect();
        let mut items: Vec<Item> = item_names.iter().map(|id| Item { nouns: BTreeSet::from([id.clone()]), ..Item::default() }).collect();
        let mut state = State::new(rooms.len(), items.len());
        let mut rules = Vec::new();
        let (mut trophy, mut max_weight) = (0, 0);
        for w in definitions {
            match w[0].as_str() {
                "ROOM" => {
                    let room = &mut rooms[room_ids[&w[1]]]; room.dark = w[2] == "DARK";
                    let at = if room.dark { 3 } else { 2 }; room.name = w[at..].join(" ");
                }
                "DESC" => rooms[room_ids[&w[1]]].description.push(w[2..].join(" ")),
                "EXIT" => {
                    let locked = w.len() > 4;
                    state.exits[room_ids[&w[1]]][direction(&w[2]).unwrap()] = Some(Exit { destination: room_ids[&w[3]], key: if locked { Some(item_ids[&w[5]]) } else { None }, locked });
                }
                "ITEM" => {
                    let x = item_ids[&w[1]];
                    state.places[x] = match w[2].as_str() { "PLAYER" => Place::Player, "NOWHERE" => Place::Nowhere, _ => Place::Floor(room_ids[&w[2]]) };
                    let item = &mut items[x]; item.weight = w[3].parse().unwrap(); let mut at = 4;
                    if w[at] == "TREASURE" { item.treasure = Some(w[at + 1].parse().unwrap()); at += 2; }
                    if w[at] == "LIGHT" { item.light = true; state.fuel[x] = w[at + 1].parse().unwrap(); at += 2; }
                    if w[at] == "CONTAINER" {
                        item.capacity = Some(w[at + 1].parse().unwrap()); at += 2;
                        if w[at] == "CLOSED" { state.containers[x] = ContainerState::Closed; at += 1; }
                        if w[at] == "LOCKED" { item.key = Some(item_ids[&w[at + 1]]); state.containers[x] = ContainerState::Locked; at += 2; }
                    }
                    if w[at] == "FIXED" { item.fixed = true; at += 1; }
                    item.name = w[at..].join(" "); item.name_words.extend(w[at..].iter().cloned());
                }
                "INSIDE" => state.places[item_ids[&w[1]]] = Place::Inside(item_ids[&w[2]]),
                "ALIAS" => { items[item_ids[&w[1]]].nouns.insert(w[2].clone()); }
                "DETAIL" => items[item_ids[&w[1]]].details.push(w[2..].join(" ")),
                "RULE" => rules.push(read_rule(w, 3, Trigger::Use(item_ids[&w[1]], item_ids[&w[2]]), &room_ids, &item_ids)),
                "ENTER" => rules.push(read_rule(w, 2, Trigger::Enter(room_ids[&w[1]]), &room_ids, &item_ids)),
                "TROPHY" => trophy = room_ids[&w[1]], "START" => state.room = room_ids[&w[1]],
                "MAXWEIGHT" => max_weight = w[1].parse().unwrap(), _ => unreachable!(),
            }
        }
        state.visited[state.room] = true;
        let vocabulary = items.iter().flat_map(|item| item.nouns.iter().chain(item.name_words.iter())).cloned().collect();
        Self { rooms, items, rules, vocabulary, trophy, max_weight, state, saved: None, pronoun: None, previous: None, verbose: false, output: Vec::new() }
    }
    fn say(&mut self, text: impl Into<String>) { self.output.push(text.into()); }
    fn floor(&self) -> Place { Place::Floor(self.state.room) }
    fn direct(&self, place: Place) -> Vec<usize> {
        self.state.places.iter().enumerate().filter_map(|(i, &at)| (at == place).then_some(i)).collect()
    }
    fn reachable(&self, item: usize, root: Place) -> bool {
        let mut place = self.state.places[item];
        while let Place::Inside(container) = place {
            if self.state.containers[container] != ContainerState::Open { return false; }
            place = self.state.places[container];
        }
        place == root
    }
    fn carried(&self, item: usize) -> bool { self.reachable(item, Place::Player) }
    fn room_item(&self, item: usize) -> bool { self.reachable(item, self.floor()) }
    fn is_lit(&self) -> bool {
        !self.rooms[self.state.room].dark || (0..self.items.len()).any(|i| self.state.lit[i] && (self.carried(i) || self.room_item(i)))
    }
    fn total_weight(&self, item: usize) -> i32 { self.items[item].weight + self.place_weight(Place::Inside(item)) }
    fn place_weight(&self, place: Place) -> i32 { self.direct(place).into_iter().map(|i| self.total_weight(i)).sum() }
    fn within(&self, item: usize, ancestor: usize) -> bool {
        let mut place = self.state.places[item];
        while let Place::Inside(container) = place {
            if container == ancestor { return true; }
            place = self.state.places[container];
        }
        false
    }
    fn stored(&self, item: usize) -> bool {
        let mut place = self.state.places[item];
        while let Place::Inside(container) = place { place = self.state.places[container]; }
        place == Place::Floor(self.trophy)
    }
    fn treasures(&self) -> (i32, usize, usize) {
        let (mut points, mut stored, mut total) = (0, 0, 0);
        for (i, item) in self.items.iter().enumerate() {
            if let Some(value) = item.treasure { total += 1; if self.stored(i) { stored += 1; points += value; } }
        }
        (points, stored, total)
    }
    fn score(&self) -> i32 { self.treasures().0 + self.state.bonus }
    fn display_name(&self, item: usize) -> String {
        let mut annotations = Vec::new();
        if self.items[item].capacity.is_some() { annotations.push(self.state.containers[item].name()); }
        if self.state.lit[item] { annotations.push("lit"); }
        if annotations.is_empty() { self.items[item].name.clone() }
        else { format!("{} ({})", self.items[item].name, annotations.join(", ")) }
    }
    fn item_tree(&mut self, place: Place, depth: usize) {
        for item in self.direct(place) {
            self.say(format!("{}{}", "  ".repeat(depth), self.display_name(item)));
            if self.items[item].capacity.is_some() && self.state.containers[item] == ContainerState::Open { self.item_tree(Place::Inside(item), depth + 1); }
        }
    }
    fn describe(&mut self, full: bool) {
        if !self.is_lit() { self.say("It is pitch dark."); return; }
        self.say(self.rooms[self.state.room].name.clone());
        if full { self.output.extend(self.rooms[self.state.room].description.iter().cloned()); }
        let exits: Vec<String> = (0..6).filter_map(|d| self.state.exits[self.state.room][d].map(|exit| format!("{}{}", DIRECTIONS[d], if exit.locked { " (locked)" } else { "" }))).collect();
        self.say(format!("Exits: {}", if exits.is_empty() { "none".into() } else { exits.join(", ") }));
        if !self.direct(self.floor()).is_empty() { self.say("You see:"); self.item_tree(self.floor(), 1); }
    }
    fn resolve(&mut self, phrase: &[String]) -> Reply<usize> {
        let lit = self.is_lit();
        if phrase.len() == 1 && phrase[0] == "it" {
            let item = self.pronoun.ok_or("I don't know what \"it\" refers to.")?;
            if !self.carried(item) && !(lit && self.room_item(item)) { return fail("You can't see any such thing."); }
            return Ok(item);
        }
        for word in phrase { if !self.vocabulary.contains(word) { return fail(format!("I don't know the word \"{word}\".")); } }
        let matches: Vec<usize> = (0..self.items.len()).filter(|&i| (self.carried(i) || lit && self.room_item(i)) &&
            self.items[i].nouns.contains(phrase.last().unwrap()) && phrase[..phrase.len() - 1].iter().all(|word| self.items[i].name_words.contains(word))).collect();
        if matches.is_empty() { return fail("You can't see any such thing."); }
        if matches.len() > 1 { return fail(format!("Which do you mean: {}?", matches.iter().map(|&i| self.items[i].name.as_str()).collect::<Vec<_>>().join(", "))); }
        self.pronoun = Some(matches[0]); Ok(matches[0])
    }
    fn run_rules(&mut self, trigger: Trigger) -> (usize, bool) {
        let (mut executed, mut message) = (0, false);
        for rule in &self.rules {
            if rule.trigger != trigger || rule.condition.as_ref().is_some_and(|(flag, expected)| self.state.flags.contains(flag) != *expected) { continue; }
            executed += 1;
            match &rule.effect {
                Effect::Message(text) => { self.output.push(text.clone()); message = true; }
                Effect::Open(room, d, destination) => self.state.exits[*room][*d] = Some(Exit { destination: *destination, key: None, locked: false }),
                Effect::Move(item, place) => self.state.places[*item] = *place,
                Effect::Flag(flag, on) => { if *on { self.state.flags.insert(flag.clone()); } else { self.state.flags.remove(flag); } }
                Effect::Points(points) => self.state.bonus += *points,
            }
        }
        (executed, message)
    }
    fn turn(&mut self, baseline: bool) {
        self.state.moves += 1;
        let nearby: Vec<bool> = (0..self.items.len()).map(|i| self.carried(i) || self.room_item(i)).collect();
        for (i, nearby) in nearby.into_iter().enumerate() {
            if self.state.lit[i] {
                self.state.fuel[i] -= 1;
                if self.state.fuel[i] == 0 { self.state.lit[i] = false; if nearby { self.say(format!("The {} goes out.", self.items[i].name)); } }
            }
        }
        let lit = self.is_lit();
        if baseline && !lit { self.say("It is now pitch dark."); } else if !baseline && lit { self.describe(true); }
        self.state.darkness = if lit { 0 } else { self.state.darkness + 1 };
        if self.state.darkness == 2 { self.say("You hear something moving in the dark."); }
        if self.state.darkness == 3 { self.state.ended = Some(EndStatus::Dead); }
        let (points, stored, total) = self.treasures();
        if self.state.ended.is_none() && total > 0 && stored == total { self.state.ended = Some(EndStatus::Won); }
        if let Some(ended) = self.state.ended {
            self.say(if ended == EndStatus::Dead { "*** You have died ***" } else { "*** You have won ***" });
            self.say(format!("You scored {} points in {} moves.", points + self.state.bonus, self.state.moves));
        }
    }
    fn require_container(&self, item: usize) -> Reply<()> {
        if self.items[item].capacity.is_none() { return fail(format!("The {} is not a container.", self.items[item].name)); }
        if self.state.containers[item] != ContainerState::Open { return fail(format!("The {} is closed.", self.items[item].name)); }
        Ok(())
    }
    fn put_item(&mut self, item: usize, container: usize) -> Reply<()> {
        if self.within(container, item) { return fail(format!("The {} is inside the {}.", self.items[container].name, self.items[item].name)); }
        if self.state.places[item] == Place::Inside(container) { return fail(format!("The {} is already in the {}.", self.items[item].name, self.items[container].name)); }
        let weight = self.place_weight(Place::Inside(container)) + if self.within(item, container) { 0 } else { self.total_weight(item) };
        if weight > self.items[container].capacity.unwrap() { return fail(format!("The {} doesn't fit in the {}.", self.items[item].name, self.items[container].name)); }
        self.state.places[item] = Place::Inside(container); Ok(())
    }
    fn take(&mut self, target: &[String], from: &[String]) -> Reply<bool> {
        if !self.is_lit() { return fail("It is pitch dark."); }
        let container = if from.is_empty() { None } else { let item = self.resolve(from)?; self.require_container(item)?; Some(item) };
        let source = container.map_or(self.floor(), Place::Inside);
        if all(target) {
            let candidates: Vec<usize> = self.direct(source).into_iter().filter(|&i| !self.items[i].fixed).collect();
            if candidates.is_empty() { return fail(container.map_or("There is nothing here to take.".to_owned(), |i| format!("There is nothing in the {} to take.", self.items[i].name))); }
            let mut taken = false;
            for item in candidates {
                if !self.carried(item) && self.place_weight(Place::Player) + self.total_weight(item) > self.max_weight { self.say(format!("{}: You can't carry any more.", self.items[item].name)); }
                else { self.state.places[item] = Place::Player; self.say(format!("{}: Taken.", self.items[item].name)); taken = true; }
            }
            return Ok(taken);
        }
        let item = self.resolve(target)?;
        if let Some(container) = container { if self.state.places[item] != source { return fail(format!("The {} is not in the {}.", self.items[item].name, self.items[container].name)); } }
        if self.state.places[item] == Place::Player { return fail(format!("You already have the {}.", self.items[item].name)); }
        if self.items[item].fixed { return fail(format!("The {} is fixed in place.", self.items[item].name)); }
        if !self.carried(item) && self.place_weight(Place::Player) + self.total_weight(item) > self.max_weight { return fail("You can't carry any more."); }
        self.state.places[item] = Place::Player; self.say("Taken."); Ok(true)
    }
    fn drop_items(&mut self, target: &[String]) -> Reply<()> {
        if all(target) {
            let candidates = self.direct(Place::Player);
            if candidates.is_empty() { return fail("You are empty-handed."); }
            for item in candidates { self.state.places[item] = self.floor(); self.say(format!("{}: Dropped.", self.items[item].name)); }
        } else {
            let item = self.resolve(target)?;
            if !self.carried(item) { return fail(format!("You aren't carrying the {}.", self.items[item].name)); }
            self.state.places[item] = self.floor(); self.say("Dropped.");
        }
        Ok(())
    }
    fn put(&mut self, first: &[String], second: &[String]) -> Reply<bool> {
        let item = if all(first) { None } else { Some(self.resolve(first)?) };
        let container = self.resolve(second)?;
        if let Some(item) = item {
            if !self.carried(item) { return fail(format!("You aren't carrying the {}.", self.items[item].name)); }
            if item == container { return fail(format!("You can't put the {} inside itself.", self.items[item].name)); }
        }
        self.require_container(container)?;
        if let Some(item) = item {
            self.put_item(item, container)?; self.say(format!("You put the {} in the {}.", self.items[item].name, self.items[container].name)); return Ok(true);
        }
        let candidates: Vec<usize> = self.direct(Place::Player).into_iter().filter(|&i| i != container).collect();
        if candidates.is_empty() { return fail(format!("You have nothing to put in the {}.", self.items[container].name)); }
        let mut moved = false;
        for item in candidates {
            let message = match self.put_item(item, container) { Ok(()) => { moved = true; "Done.".into() }, Err(reason) => reason };
            self.say(format!("{}: {message}", self.items[item].name));
        }
        Ok(moved)
    }
    fn key_check(&mut self, key: usize, phrase: &[String]) -> Reply<()> {
        if phrase.is_empty() {
            if !self.carried(key) { return fail("You don't have the right key."); }
            self.say(format!("(with the {})", self.items[key].name));
        } else {
            let item = self.resolve(phrase)?;
            if !self.carried(item) { return fail(format!("You aren't carrying the {}.", self.items[item].name)); }
            if item != key { return fail(format!("The {} doesn't fit.", self.items[item].name)); }
        }
        Ok(())
    }
    fn change_lock(&mut self, target: &[String], key_phrase: &[String], locking: bool) -> Reply<()> {
        let d = if target.len() == 1 { direction(&target[0]) } else { None };
        let status = if locking { "already locked" } else { "not locked" };
        if let Some(d) = d {
            let exit = self.state.exits[self.state.room][d].ok_or_else(|| format!("There is no exit {}.", DIRECTIONS[d]))?;
            let key = exit.key.ok_or_else(|| format!("The way {} has no lock.", DIRECTIONS[d]))?;
            if exit.locked == locking { return fail(format!("The way {} is {status}.", DIRECTIONS[d])); }
            self.key_check(key, key_phrase)?;
            self.state.exits[self.state.room][d] = Some(Exit { locked: locking, ..exit });
            if let Some(opposite) = self.state.exits[exit.destination][d ^ 1] {
                if opposite.destination == self.state.room && opposite.key == exit.key {
                    self.state.exits[exit.destination][d ^ 1] = Some(Exit { locked: locking, ..opposite });
                }
            }
        } else {
            let item = self.resolve(target)?;
            if self.items[item].capacity.is_none() || self.items[item].key.is_none() { return fail(format!("The {} has no lock.", self.items[item].name)); }
            if (self.state.containers[item] == ContainerState::Locked) == locking { return fail(format!("The {} is {status}.", self.items[item].name)); }
            if locking && self.state.containers[item] == ContainerState::Open { return fail(format!("You must close the {} first.", self.items[item].name)); }
            self.key_check(self.items[item].key.unwrap(), key_phrase)?;
            self.state.containers[item] = if locking { ContainerState::Locked } else { ContainerState::Closed };
        }
        self.say(if locking { "Locked." } else { "Unlocked." }); Ok(())
    }
    fn examine(&mut self, item: usize) {
        if self.items[item].details.is_empty() { self.say(format!("You see nothing special about the {}.", self.items[item].name)); }
        else { self.output.extend(self.items[item].details.iter().cloned()); }
        if self.items[item].light { self.say(format!("It is {} (fuel {}).", if self.state.lit[item] { "lit" } else { "unlit" }, self.state.fuel[item])); }
        if self.items[item].capacity.is_some() {
            match self.state.containers[item] {
                ContainerState::Locked => self.say("It is locked."), ContainerState::Closed => self.say("It is closed."),
                ContainerState::Open => {
                    if self.direct(Place::Inside(item)).is_empty() { self.say("It is empty."); }
                    else { self.say("It contains:"); self.item_tree(Place::Inside(item), 1); }
                }
            }
        }
        if let Some(points) = self.items[item].treasure { self.say(format!("It is a treasure worth {points} points.")); }
        self.say(format!("It weighs {}.", self.total_weight(item)));
    }
    fn execute(&mut self, verb: Verb, first: &[String], second: &[String], d: Option<usize>, baseline: &mut bool) -> Reply<bool> {
        match verb {
            Verb::Go => {
                let d = d.unwrap(); let exit = self.state.exits[self.state.room][d].ok_or("You can't go that way.")?;
                if exit.locked { return fail(format!("The way {} is locked.", DIRECTIONS[d])); }
                self.state.room = exit.destination; *baseline = self.is_lit();
                self.describe(self.verbose || !self.state.visited[self.state.room]); self.state.visited[self.state.room] = true;
                self.run_rules(Trigger::Enter(self.state.room));
            }
            Verb::Look => self.describe(true),
            Verb::Examine => { let item = self.resolve(first)?; self.examine(item); }
            Verb::Take => return self.take(first, second), Verb::Drop => self.drop_items(first)?, Verb::Put => return self.put(first, second),
            Verb::Inventory => {
                if self.direct(Place::Player).is_empty() { self.say("You are empty-handed."); }
                else { self.say("You are carrying:"); self.item_tree(Place::Player, 1); self.say(format!("Total weight: {}/{}", self.place_weight(Place::Player), self.max_weight)); }
            }
            Verb::Open => {
                let item = self.resolve(first)?;
                if self.items[item].capacity.is_none() { return fail(format!("You can't open the {}.", self.items[item].name)); }
                if self.state.containers[item] == ContainerState::Open { return fail(format!("The {} is already open.", self.items[item].name)); }
                if self.state.containers[item] == ContainerState::Locked { return fail(format!("The {} is locked.", self.items[item].name)); }
                self.state.containers[item] = ContainerState::Open;
                let direct = self.direct(Place::Inside(item));
                if direct.is_empty() { self.say("Opened."); }
                else { self.say(format!("Opening the {} reveals {}.", self.items[item].name, direct.iter().map(|&i| self.items[i].name.as_str()).collect::<Vec<_>>().join(", "))); }
            }
            Verb::Close => {
                let item = self.resolve(first)?;
                if self.items[item].capacity.is_none() { return fail(format!("You can't close the {}.", self.items[item].name)); }
                if self.state.containers[item] != ContainerState::Open { return fail(format!("The {} is already closed.", self.items[item].name)); }
                self.state.containers[item] = ContainerState::Closed; self.say("Closed.");
            }
            Verb::Unlock | Verb::Lock => self.change_lock(first, second, verb == Verb::Lock)?,
            Verb::Use => {
                let a = self.resolve(first)?; let b = self.resolve(second)?;
                if !self.carried(a) { return fail(format!("You aren't carrying the {}.", self.items[a].name)); }
                let (executed, message) = self.run_rules(Trigger::Use(a, b));
                if executed == 0 { return fail("Nothing happens."); }
                if !message { self.say("Done."); }
            }
            Verb::Light | Verb::Extinguish => {
                let item = self.resolve(first)?; let lighting = verb == Verb::Light;
                if !self.items[item].light { return fail(format!("You can't {} the {}.", verb.name(), self.items[item].name)); }
                if self.state.lit[item] == lighting { return fail(format!("The {} is {}.", self.items[item].name, if lighting { "already lit" } else { "not lit" })); }
                if lighting && self.state.fuel[item] == 0 { return fail(format!("The {} has no fuel.", self.items[item].name)); }
                self.state.lit[item] = lighting; self.say(format!("The {} is now {}.", self.items[item].name, if lighting { "lit" } else { "out" }));
            }
            Verb::Wait => self.say("Time passes."),
            Verb::Score => {
                let (points, stored, total) = self.treasures();
                self.say(format!("You have scored {} points (treasure {points}, bonus {}) in {} moves.", points + self.state.bonus, self.state.bonus, self.state.moves));
                self.say(format!("Treasures stored: {stored} of {total}."));
            }
            Verb::Save => { self.saved = Some(self.state.clone()); self.say("Game saved."); }
            Verb::Restore => { self.state = self.saved.as_ref().ok_or("There is no saved game.")?.clone(); self.say("Game restored."); self.describe(true); }
            Verb::Verbose => { self.verbose = true; self.say("Verbose mode."); }
            Verb::Brief => { self.verbose = false; self.say("Brief mode."); }
        }
        Ok(true)
    }
    fn interpret(&mut self, mut input: Vec<String>) -> Reply<()> {
        if input.is_empty() { return fail("I beg your pardon?"); }
        if direction(&input[0]).is_some() { input.insert(0, "go".into()); }
        let mut verb = Verb::parse(&input[0]).ok_or_else(|| format!("I don't know the verb \"{}\".", input[0]))?;
        if self.state.ended.is_some() && verb != Verb::Restore { return fail("The game is over."); }
        let mut first = &input[1..]; let mut second = &input[0..0]; let mut d = None;
        if verb == Verb::Look && !first.is_empty() {
            if first[0] != "at" { return fail("I don't understand that."); }
            verb = Verb::Examine; first = &first[1..];
        }
        if verb.no_arguments() {
            if !first.is_empty() { return fail("I don't understand that."); }
        } else {
            if first.is_empty() { return fail(if verb == Verb::Go { "Which way do you want to go?".to_owned() } else { format!("What do you want to {}?", verb.name()) }); }
            if verb == Verb::Go {
                d = if first.len() == 1 { direction(&first[0]) } else { None };
                if d.is_none() { return fail("I don't understand that."); }
            } else {
                let split = first.iter().position(|word| match verb {
                    Verb::Put => matches!(word.as_str(), "in" | "into"), Verb::Use => matches!(word.as_str(), "on" | "with"),
                    Verb::Lock | Verb::Unlock => word == "with", Verb::Take => word == "from", _ => false,
                });
                if let Some(at) = split {
                    if at == 0 || at + 1 == first.len() { return fail("I don't understand that."); }
                    second = &first[at + 1..]; first = &first[..at];
                } else if matches!(verb, Verb::Put | Verb::Use) { return fail("I don't understand that."); }
            }
        }
        let mut baseline = self.is_lit();
        if self.execute(verb, first, second, d, &mut baseline)? && verb.action() { self.turn(baseline); }
        Ok(())
    }
    fn dispatch_line(&mut self, line: &str) -> Reply<()> {
        let mut input = words(line);
        if input.first().is_some_and(|word| matches!(word.as_str(), "again" | "g")) {
            if input.len() != 1 { return fail("I don't understand that."); }
            input = words(self.previous.as_deref().ok_or("There is nothing to repeat.")?);
        } else { self.previous = Some(line.to_owned()); }
        self.interpret(input)
    }
    fn process(&mut self, line: &str) -> Vec<String> {
        self.output = vec![format!("> {line}")];
        if let Err(reason) = self.dispatch_line(line) { self.say(reason); }
        std::mem::take(&mut self.output)
    }
}

fn main() {
    let mut input = String::new(); io::stdin().read_to_string(&mut input).unwrap();
    let mut lines = input.lines();
    let definitions: Vec<Vec<String>> = lines.by_ref().take_while(|line| *line != "BEGIN")
        .map(|line| line.split(' ').map(str::to_owned).collect()).collect();
    let mut game = Adventure::new(&definitions);
    let stdout = io::stdout(); let mut output = BufWriter::new(stdout.lock());
    game.describe(true);
    for row in std::mem::take(&mut game.output) { writeln!(output, "{row}").unwrap(); }
    for line in lines.take_while(|line| *line != "QUIT") {
        for row in game.process(line) { writeln!(output, "{row}").unwrap(); }
    }
    writeln!(output, "Final score: {} points in {} moves.", game.score(), game.state.moves).unwrap();
}
