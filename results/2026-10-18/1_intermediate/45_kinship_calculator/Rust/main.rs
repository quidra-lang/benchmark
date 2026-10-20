use std::collections::{BTreeMap, BTreeSet, HashMap, VecDeque};
use std::fmt;
use std::io::{self, Read};
use std::ops::Add;

#[derive(Clone, Copy, PartialEq, Eq)]
struct Fraction {
    numerator: u64,
    denominator: u64,
}

impl Fraction {
    fn new(numerator: u64, denominator: u64) -> Self {
        let (mut a, mut b) = (numerator, denominator);
        while b != 0 {
            (a, b) = (b, a % b);
        }
        Self {
            numerator: numerator / a,
            denominator: denominator / a,
        }
    }

    fn half(self) -> Self {
        Self::new(self.numerator, self.denominator * 2)
    }
}

impl Add for Fraction {
    type Output = Self;

    fn add(self, other: Self) -> Self {
        let denominator = self.denominator.max(other.denominator);
        Self::new(
            self.numerator * (denominator / self.denominator)
                + other.numerator * (denominator / other.denominator),
            denominator,
        )
    }
}

impl fmt::Display for Fraction {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}/{}", self.numerator, self.denominator)
    }
}

#[derive(Clone)]
struct Person {
    sex: char,
    birth: i32,
    name: String,
    death: Option<i32>,
    parents: BTreeSet<String>,
}

impl Person {
    fn life(&self) -> String {
        format!(
            "{}-{}",
            self.birth,
            self.death.map(|year| year.to_string()).unwrap_or_default()
        )
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Status {
    Current,
    Divorced,
    Widowed,
}

impl Status {
    fn as_str(self) -> &'static str {
        match self {
            Self::Current => "current",
            Self::Divorced => "divorced",
            Self::Widowed => "widowed",
        }
    }
}

#[derive(Clone)]
struct Marriage {
    first: String,
    second: String,
    start: i32,
    end: Option<i32>,
    status: Status,
    died: Option<String>,
}

impl Marriage {
    fn contains(&self, id: &str) -> bool {
        self.first == id || self.second == id
    }

    fn other(&self, id: &str) -> &str {
        if self.first == id { &self.second } else { &self.first }
    }
}

#[derive(Clone, Default)]
struct State {
    people: BTreeMap<String, Person>,
    marriages: Vec<Marriage>,
}

struct UndoRecord {
    command: String,
    state: State,
}

fn pair(a: &str, b: &str) -> (String, String) {
    if a <= b { (a.to_owned(), b.to_owned()) } else { (b.to_owned(), a.to_owned()) }
}

fn gender<'a>(sex: char, male: &'a str, female: &'a str, neutral: &'a str) -> &'a str {
    match sex {
        'M' => male,
        'F' => female,
        _ => neutral,
    }
}

fn grand_prefix(generation: usize) -> String {
    if generation == 1 {
        String::new()
    } else {
        "great-".repeat(generation - 2) + "grand"
    }
}

fn ordinal(number: usize) -> String {
    let names = [
        "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth",
        "ninth", "tenth",
    ];
    if number <= 10 {
        return names[number - 1].to_owned();
    }
    let suffix = if (11..=13).contains(&(number % 100)) {
        "th"
    } else {
        match number % 10 {
            1 => "st",
            2 => "nd",
            3 => "rd",
            _ => "th",
        }
    };
    format!("{number}{suffix}")
}

fn term(da: usize, db: usize, sex: char) -> String {
    if da == 0 && db == 0 {
        return "self".to_owned();
    }
    if da == 0 {
        return grand_prefix(db) + gender(sex, "father", "mother", "parent");
    }
    if db == 0 {
        return grand_prefix(da) + gender(sex, "son", "daughter", "child");
    }
    if da == 1 && db == 1 {
        return gender(sex, "brother", "sister", "sibling").to_owned();
    }
    if da == 1 {
        return grand_prefix(db - 1) + gender(sex, "uncle", "aunt", "pibling");
    }
    if db == 1 {
        return grand_prefix(da - 1) + gender(sex, "nephew", "niece", "nibling");
    }
    let ending = match da.abs_diff(db) {
        0 => String::new(),
        1 => " once removed".to_owned(),
        2 => " twice removed".to_owned(),
        n => format!(" {n} times removed"),
    };
    format!("{} cousin{ending}", ordinal(da.min(db) - 1))
}

struct Apex {
    id: String,
    da: usize,
    db: usize,
    shares: usize,
}

struct Context<'a> {
    state: &'a State,
    ancestors: BTreeMap<String, BTreeMap<String, usize>>,
    children: BTreeMap<String, BTreeSet<String>>,
    latest: BTreeMap<(String, String), usize>,
    spouses: BTreeMap<String, String>,
    partners: BTreeMap<String, BTreeSet<String>>,
    kinship: HashMap<(String, String), Fraction>,
}

impl<'a> Context<'a> {
    fn new(state: &'a State) -> Self {
        let mut ancestors = BTreeMap::new();
        let mut children: BTreeMap<String, BTreeSet<String>> = state
            .people.keys().map(|id| (id.clone(), BTreeSet::new())).collect();
        for (id, person) in &state.people {
            for parent in &person.parents {
                children.get_mut(parent).unwrap().insert(id.clone());
            }
            let mut distances = BTreeMap::from([(id.clone(), 0)]);
            let mut queue = VecDeque::from([id.clone()]);
            while let Some(current) = queue.pop_front() {
                let distance = distances[&current] + 1;
                for parent in &state.people[&current].parents {
                    if !distances.contains_key(parent) {
                        distances.insert(parent.clone(), distance);
                        queue.push_back(parent.clone());
                    }
                }
            }
            ancestors.insert(id.clone(), distances);
        }
        let mut latest = BTreeMap::new();
        let mut spouses = BTreeMap::new();
        for (i, marriage) in state.marriages.iter().enumerate() {
            latest.insert(pair(&marriage.first, &marriage.second), i);
            if marriage.status == Status::Current {
                spouses.insert(marriage.first.clone(), marriage.second.clone());
                spouses.insert(marriage.second.clone(), marriage.first.clone());
            }
        }
        let mut partners: BTreeMap<String, BTreeSet<String>> = state
            .people.keys().map(|id| (id.clone(), BTreeSet::new())).collect();
        for &i in latest.values() {
            let marriage = &state.marriages[i];
            if marriage.status != Status::Divorced {
                partners.get_mut(&marriage.first).unwrap().insert(marriage.second.clone());
                partners.get_mut(&marriage.second).unwrap().insert(marriage.first.clone());
            }
        }
        Self { state, ancestors, children, latest, spouses, partners, kinship: HashMap::new() }
    }

    fn check(&self, ids: &[&str]) -> Result<(), String> {
        for &id in ids {
            if !self.state.people.contains_key(id) {
                return Err(format!("UNKNOWN PERSON {id}"));
            }
        }
        Ok(())
    }

    fn age_order(&self, mut ids: Vec<String>) -> Vec<String> {
        ids.sort_by(|a, b| (self.state.people[a].birth, a).cmp(&(self.state.people[b].birth, b)));
        ids
    }

    fn person_list(&self, ids: Vec<String>) -> String {
        let sorted = self.age_order(ids);
        if sorted.is_empty() { "-".to_owned() } else { sorted.join(" ") }
    }

    fn siblings(&self, a: &str, b: &str) -> bool {
        a != b && !self.state.people[a].parents.is_disjoint(&self.state.people[b].parents)
    }

    fn descendants(&self, id: &str) -> BTreeMap<String, usize> {
        self.ancestors.iter().filter_map(|(person, distances)| {
            if person == id { None } else { distances.get(id).map(|&g| (person.clone(), g)) }
        }).collect()
    }

    fn apex(&self, a: &str, b: &str) -> Option<Apex> {
        let aa = &self.ancestors[a];
        let ab = &self.ancestors[b];
        if let Some(&db) = ab.get(a) {
            return Some(Apex { id: a.to_owned(), da: 0, db, shares: 0 });
        }
        if let Some(&da) = aa.get(b) {
            return Some(Apex { id: b.to_owned(), da, db: 0, shares: 0 });
        }
        let (sum, da, id) = aa.iter().filter_map(|(id, &da)| {
            ab.get(id).map(|&db| (da + db, da, id.clone()))
        }).min()?;
        let db = sum - da;
        let shares = aa.iter().filter(|(id, distance)| **distance == da && ab.get(*id) == Some(&db)).count();
        Some(Apex { id, da, db, shares })
    }

    fn blood_term(&self, a: &str, b: &str, sex: char) -> Option<String> {
        if a == b { return None; }
        let apex = self.apex(a, b)?;
        let prefix = if apex.shares == 1 { "half-" } else if apex.shares >= 4 { "double " } else { "" };
        Some(prefix.to_owned() + &term(apex.da, apex.db, sex))
    }

    fn relationship(&self, a: &str, b: &str, sex: char) -> Vec<String> {
        if a == b { return vec!["self".to_owned()]; }
        let pa = &self.state.people[a].parents;
        let pb = &self.state.people[b].parents;
        let partners_a = &self.partners[a];
        let partners_b = &self.partners[b];
        let mut result = Vec::new();
        if let Some(blood) = self.blood_term(a, b, sex) { result.push(blood); }
        if let Some(&i) = self.latest.get(&pair(a, b)) {
            let marriage = &self.state.marriages[i];
            let name = match marriage.status {
                Status::Current => gender(sex, "husband", "wife", "spouse"),
                Status::Divorced => gender(sex, "ex-husband", "ex-wife", "ex-spouse"),
                Status::Widowed if marriage.died.as_deref() == Some(a) => gender(sex, "late husband", "late wife", "late spouse"),
                Status::Widowed => gender(sex, "widower", "widow", "surviving spouse"),
            };
            result.push(name.to_owned());
        } else if !self.children[a].is_disjoint(&self.children[b]) {
            result.push("co-parent".to_owned());
        }
        if !pb.contains(a) && !pb.is_disjoint(partners_a) {
            result.push(gender(sex, "stepfather", "stepmother", "stepparent").to_owned());
        }
        if !pa.contains(b) && !pa.is_disjoint(partners_b) {
            result.push(gender(sex, "stepson", "stepdaughter", "stepchild").to_owned());
        }
        if pa.is_disjoint(pb) && pa.iter().any(|p| !self.partners[p].is_disjoint(pb)) {
            result.push(gender(sex, "stepbrother", "stepsister", "stepsibling").to_owned());
        }
        if !self.ancestors[b].contains_key(a)
            && self.ancestors[b].iter().any(|(g, &distance)| distance == 2 && partners_a.contains(g))
        {
            result.push(gender(sex, "stepgrandfather", "stepgrandmother", "stepgrandparent").to_owned());
        }
        if !self.ancestors[a].contains_key(b)
            && self.ancestors[a].iter().any(|(g, &distance)| distance == 2 && partners_b.contains(g))
        {
            result.push(gender(sex, "stepgrandson", "stepgranddaughter", "stepgrandchild").to_owned());
        }
        if partners_b.iter().any(|p| self.state.people[p].parents.contains(a)) {
            result.push(gender(sex, "father-in-law", "mother-in-law", "parent-in-law").to_owned());
        }
        if partners_a.iter().any(|p| self.state.people[p].parents.contains(b)) {
            result.push(gender(sex, "son-in-law", "daughter-in-law", "child-in-law").to_owned());
        }
        if partners_b.iter().any(|p| self.siblings(a, p)) || partners_a.iter().any(|p| self.siblings(p, b)) {
            result.push(gender(sex, "brother-in-law", "sister-in-law", "sibling-in-law").to_owned());
        }
        result
    }

    fn relationship_string(&self, a: &str, b: &str) -> String {
        let terms = self.relationship(a, b, self.state.people[a].sex);
        if terms.is_empty() { "no relation".to_owned() } else { terms.join(", ") }
    }

    fn phi(&mut self, a: &str, b: &str) -> Fraction {
        let key = pair(a, b);
        if let Some(&value) = self.kinship.get(&key) { return value; }
        let value = if a == b {
            (Fraction::new(1, 1) + self.inbreeding(a)).half()
        } else {
            let (x, y) = if self.state.people[a].birth >= self.state.people[b].birth { (a, b) } else { (b, a) };
            let parents: Vec<_> = self.state.people[x].parents.iter().cloned().collect();
            let mut sum = Fraction::new(0, 1);
            for parent in parents { sum = sum + self.phi(&parent, y); }
            sum.half()
        };
        self.kinship.insert(key, value);
        value
    }

    fn inbreeding(&mut self, id: &str) -> Fraction {
        let parents: Vec<_> = self.state.people[id].parents.iter().cloned().collect();
        if parents.len() == 2 { self.phi(&parents[0], &parents[1]) } else { Fraction::new(0, 1) }
    }

    fn upward_path(&self, from: &str, apex: &str) -> Vec<String> {
        let mut result = vec![from.to_owned()];
        while result.last().unwrap() != apex {
            let current = result.last().unwrap();
            let distance = self.ancestors[current][apex] - 1;
            let parent = self.state.people[current].parents.iter().find(|p| self.ancestors[*p].get(apex) == Some(&distance)).unwrap().clone();
            result.push(parent);
        }
        result
    }

    fn tree_visit(&self, id: &str, depth: usize, visited: &mut BTreeSet<String>, lines: &mut Vec<String>) {
        let indent = " ".repeat(2 * (depth + 1));
        if !visited.insert(id.to_owned()) {
            lines.push(format!("{indent}{id} (see above)"));
            return;
        }
        let person = &self.state.people[id];
        let spouse = self.spouses.get(id).map(|s| format!(" = {s}")).unwrap_or_default();
        lines.push(format!("{indent}{id} {} {}{spouse}", person.name, person.life()));
        for child in self.age_order(self.children[id].iter().cloned().collect()) {
            self.tree_visit(&child, depth + 1, visited, lines);
        }
    }

    fn pedigree_enter(&self, id: &str, number: usize, generation: usize, depth: usize,
                      entered: &mut BTreeSet<String>, lines: &mut Vec<String>) {
        entered.insert(id.to_owned());
        let person = &self.state.people[id];
        lines.push(format!("{}{number} {id} {} {}", " ".repeat(2 * (generation + 1)), person.name, person.life()));
        if generation < depth {
            let mut parents: Vec<_> = person.parents.iter().cloned().collect();
            parents.sort_by_key(|p| {
                let rank = match self.state.people[p].sex { 'M' => 0, 'F' => 1, _ => 2 };
                (rank, p.clone())
            });
            for (i, parent) in parents.iter().enumerate() {
                self.pedigree_enter(parent, 2 * number + i, generation + 1, depth, entered, lines);
            }
        }
    }

    fn longest_lineage(&self, id: &str, memo: &mut BTreeMap<String, usize>) -> usize {
        if let Some(&length) = memo.get(id) { return length; }
        let length = 1 + self.state.people[id].parents.iter().map(|p| self.longest_lineage(p, memo)).max().unwrap_or(0);
        memo.insert(id.to_owned(), length);
        length
    }
}

#[derive(Default)]
struct Family {
    state: State,
    history: Vec<UndoRecord>,
}

impl Family {
    fn remember(&mut self, command: &str) {
        self.history.push(UndoRecord { command: command.to_owned(), state: self.state.clone() });
    }

    fn command(&mut self, line: &str) -> Result<Vec<String>, String> {
        let words: Vec<_> = line.split(' ').collect();
        let command = words[0];
        let mut ctx = Context::new(&self.state);
        match command {
            "PERSON" => {
                let id = words[1];
                if self.state.people.contains_key(id) { return Err(format!("DUPLICATE PERSON {id}")); }
                drop(ctx);
                self.remember(line);
                self.state.people.insert(id.to_owned(), Person {
                    sex: words[2].chars().next().unwrap(), birth: words[3].parse().unwrap(),
                    name: words[4].to_owned(), death: None, parents: BTreeSet::new(),
                });
                Ok(vec![format!("ADDED {id} {} {} {}", words[4], words[2], words[3])])
            }
            "DEATH" => {
                let id = words[1];
                let year: i32 = words[2].parse().unwrap();
                ctx.check(&[id])?;
                let person = &self.state.people[id];
                if person.death.is_some() { return Err(format!("ALREADY DECEASED {id}")); }
                if year < person.birth || self.state.marriages.iter().any(|m| m.contains(id) && (m.start > year || m.end.is_some_and(|end| end > year))) {
                    return Err(format!("BAD YEAR {id}"));
                }
                if let Some(child) = ctx.children[id].iter().find(|c| self.state.people[*c].birth > year + 1) {
                    return Err(format!("AFTER DEATH {child} {id}"));
                }
                let spouse = ctx.spouses.get(id).cloned();
                let index = spouse.as_ref().map(|s| ctx.latest[&pair(id, s)]);
                drop(ctx);
                self.remember(line);
                self.state.people.get_mut(id).unwrap().death = Some(year);
                if let Some(i) = index {
                    let marriage = &mut self.state.marriages[i];
                    marriage.end = Some(year);
                    marriage.status = Status::Widowed;
                    marriage.died = Some(id.to_owned());
                }
                Ok(vec![format!("DIED {id} {year}{}", spouse.map(|s| format!(" spouse={s}")).unwrap_or_default())])
            }
            "REMOVE" => {
                let id = words[1];
                ctx.check(&[id])?;
                drop(ctx);
                self.remember(line);
                self.state.people.remove(id);
                for person in self.state.people.values_mut() { person.parents.remove(id); }
                self.state.marriages.retain(|m| !m.contains(id));
                Ok(vec![format!("REMOVED {id}")])
            }
            "PARENT" => {
                let (child, parent) = (words[1], words[2]);
                ctx.check(&[child, parent])?;
                if child == parent { return Err(format!("SAME PERSON {child}")); }
                if self.state.people[child].parents.contains(parent) { return Err(format!("ALREADY PARENT {child} {parent}")); }
                if self.state.people[child].parents.len() == 2 { return Err(format!("TOO MANY PARENTS {child}")); }
                if ctx.ancestors[parent].contains_key(child) { return Err(format!("CYCLE {child} {parent}")); }
                if self.state.people[parent].birth + 12 > self.state.people[child].birth { return Err(format!("AGE GAP {child} {parent}")); }
                if self.state.people[parent].death.is_some_and(|death| death + 1 < self.state.people[child].birth) {
                    return Err(format!("AFTER DEATH {child} {parent}"));
                }
                let title = gender(self.state.people[parent].sex, "father", "mother", "parent");
                drop(ctx);
                self.remember(line);
                self.state.people.get_mut(child).unwrap().parents.insert(parent.to_owned());
                Ok(vec![format!("LINKED {child} {parent} {title}")])
            }
            "UNPARENT" => {
                let (child, parent) = (words[1], words[2]);
                ctx.check(&[child, parent])?;
                if !self.state.people[child].parents.contains(parent) { return Err(format!("NOT PARENT {child} {parent}")); }
                drop(ctx);
                self.remember(line);
                self.state.people.get_mut(child).unwrap().parents.remove(parent);
                Ok(vec![format!("UNLINKED {child} {parent}")])
            }
            "SPOUSE" => {
                let (a, b) = (words[1], words[2]);
                let year: i32 = words[3].parse().unwrap();
                ctx.check(&[a, b])?;
                if a == b { return Err(format!("SAME PERSON {a}")); }
                for id in [a, b] {
                    if self.state.people[id].death.is_some() { return Err(format!("DECEASED {id}")); }
                }
                for id in [a, b] {
                    if ctx.spouses.contains_key(id) { return Err(format!("ALREADY MARRIED {id}")); }
                }
                if ctx.ancestors[a].contains_key(b) || ctx.ancestors[b].contains_key(a) || ctx.siblings(a, b) {
                    return Err(format!("CLOSE KIN {a} {b}"));
                }
                for id in [a, b] {
                    if year < self.state.people[id].birth + 16 { return Err(format!("TOO YOUNG {id}")); }
                }
                for id in [a, b] {
                    if self.state.marriages.iter().any(|m| m.contains(id) && m.end.is_some_and(|end| end >= year)) {
                        return Err(format!("BAD YEAR {id}"));
                    }
                }
                drop(ctx);
                self.remember(line);
                self.state.marriages.push(Marriage {
                    first: a.to_owned(), second: b.to_owned(), start: year, end: None,
                    status: Status::Current, died: None,
                });
                Ok(vec![format!("MARRIED {a} {b} {year}")])
            }
            "DIVORCE" => {
                let (a, b) = (words[1], words[2]);
                let year: i32 = words[3].parse().unwrap();
                ctx.check(&[a, b])?;
                if ctx.spouses.get(a).map(String::as_str) != Some(b) { return Err(format!("NOT MARRIED {a} {b}")); }
                let index = ctx.latest[&pair(a, b)];
                if year <= self.state.marriages[index].start { return Err(format!("BAD YEAR {a}")); }
                drop(ctx);
                self.remember(line);
                self.state.marriages[index].end = Some(year);
                self.state.marriages[index].status = Status::Divorced;
                Ok(vec![format!("DIVORCED {a} {b} {year}")])
            }
            "UNDO" => {
                drop(ctx);
                let previous = self.history.pop().ok_or("NOTHING TO UNDO")?;
                self.state = previous.state;
                Ok(vec![format!("UNDONE {}", previous.command)])
            }
            "INFO" => {
                let id = words[1];
                ctx.check(&[id])?;
                let person = &self.state.people[id];
                let mut lines = vec![
                    format!("INFO {id} {} {} {}", person.name, person.sex, person.life()),
                    format!("  parents: {}", ctx.person_list(person.parents.iter().cloned().collect())),
                ];
                for marriage in &self.state.marriages {
                    if marriage.contains(id) {
                        lines.push(format!("  marriage: {} {}-{} {}", marriage.other(id), marriage.start,
                            marriage.end.map(|year| year.to_string()).unwrap_or_default(), marriage.status.as_str()));
                    }
                }
                lines.push(format!("  children: {}", ctx.person_list(ctx.children[id].iter().cloned().collect())));
                let siblings = self.state.people.keys().filter(|p| ctx.siblings(p, id)).cloned().collect();
                lines.push(format!("  siblings: {}", ctx.person_list(siblings)));
                lines.push(format!("  inbreeding: {}", ctx.inbreeding(id)));
                Ok(lines)
            }
            "RELATION" => {
                let (a, b) = (words[1], words[2]);
                ctx.check(&[a, b])?;
                Ok(vec![format!("RELATION {a} {b}: {}", ctx.relationship_string(a, b))])
            }
            "RELATIVES" | "WHO" => {
                let id = words[1];
                ctx.check(&[id])?;
                let query = words[2..].join(" ");
                let mut lines = Vec::new();
                for (person, value) in &self.state.people {
                    if person == id { continue; }
                    let terms = ctx.relationship(person, id, value.sex);
                    if command == "RELATIVES" {
                        if !terms.is_empty() { lines.push(format!("  {person}: {}", terms.join(", "))); }
                    } else {
                        let neutral = ctx.relationship(person, id, 'X');
                        if let Some(i) = terms.iter().zip(&neutral).position(|(actual, generic)| *actual == query || *generic == query) {
                            lines.push(format!("  {person}: {}", terms[i]));
                        }
                    }
                }
                let header = if command == "WHO" { format!("WHO {id} {query} {}", lines.len()) }
                    else { format!("RELATIVES {id} {}", lines.len()) };
                lines.insert(0, header);
                Ok(lines)
            }
            "PATH" => {
                let (a, b) = (words[1], words[2]);
                ctx.check(&[a, b])?;
                if let Some(apex) = ctx.apex(a, b) {
                    let mut path = ctx.upward_path(a, &apex.id);
                    let mut right = ctx.upward_path(b, &apex.id);
                    right.pop();
                    path.extend(right.into_iter().rev());
                    Ok(vec![format!("PATH {a} {b} {}: {}", apex.da + apex.db, path.join(" "))])
                } else {
                    Ok(vec![format!("PATH {a} {b} none")])
                }
            }
            "COMMON" => {
                let (a, b) = (words[1], words[2]);
                ctx.check(&[a, b])?;
                let aa = &ctx.ancestors[a];
                let ab = &ctx.ancestors[b];
                let common: BTreeSet<_> = aa.keys().filter(|p| ab.contains_key(*p)).cloned().collect();
                let mut nearest: Vec<_> = common.iter().filter(|p| ctx.children[*p].is_disjoint(&common)).cloned().collect();
                nearest.sort_by_key(|p| (aa[p] + ab[p], p.clone()));
                let mut lines = vec![format!("COMMON {a} {b} {}", nearest.len())];
                lines.extend(nearest.iter().map(|p| format!("  {p} {} {}", aa[p], ab[p])));
                Ok(lines)
            }
            "ANCESTORS" | "DESCENDANTS" => {
                let id = words[1];
                ctx.check(&[id])?;
                let mut distances = if command == "ANCESTORS" { ctx.ancestors[id].clone() } else { ctx.descendants(id) };
                distances.remove(id);
                let mut entries: Vec<_> = distances.into_iter().map(|(person, g)| (g, person)).collect();
                entries.sort();
                let mut lines = vec![format!("{command} {id} {}", entries.len())];
                for (g, person) in entries {
                    let sex = self.state.people[&person].sex;
                    let title = if command == "ANCESTORS" { term(0, g, sex) } else { term(g, 0, sex) };
                    lines.push(format!("  {g} {person} {title}"));
                }
                Ok(lines)
            }
            "COUSINS" => {
                let id = words[1];
                let degree: usize = words[2].parse().unwrap();
                ctx.check(&[id])?;
                let mut matches = Vec::new();
                for person in self.state.people.keys() {
                    if person == id { continue; }
                    if let Some(apex) = ctx.apex(person, id) {
                        if apex.da >= 2 && apex.db >= 2 && apex.da.min(apex.db) - 1 == degree {
                            matches.push((apex.da.abs_diff(apex.db), person.clone()));
                        }
                    }
                }
                matches.sort();
                let mut lines = vec![format!("COUSINS {id} {degree} {}", matches.len())];
                for (_, person) in matches {
                    lines.push(format!("  {person} {}", ctx.blood_term(&person, id, self.state.people[&person].sex).unwrap()));
                }
                Ok(lines)
            }
            "SIBLINGS" => {
                let id = words[1];
                ctx.check(&[id])?;
                let parents = &self.state.people[id].parents;
                let mut matches = BTreeMap::new();
                let mut order = 1;
                for (person, value) in &self.state.people {
                    if person == id { continue; }
                    let common = parents.intersection(&value.parents).count();
                    let kind = match common {
                        2 => "full",
                        1 => "half",
                        _ if parents.iter().any(|p| !ctx.partners[p].is_disjoint(&value.parents)) => "step",
                        _ => continue,
                    };
                    matches.insert(person.clone(), kind);
                    if common > 0 && (value.birth, person.as_str()) < (self.state.people[id].birth, id) { order += 1; }
                }
                let mut lines = vec![format!("SIBLINGS {id} {} order={order}", matches.len())];
                for person in ctx.age_order(matches.keys().cloned().collect()) {
                    lines.push(format!("  {person} {} {}", matches[&person], self.state.people[&person].birth));
                }
                Ok(lines)
            }
            "GENERATIONS" => {
                let id = words[1];
                ctx.check(&[id])?;
                let mut groups: BTreeMap<usize, Vec<&Person>> = BTreeMap::new();
                for (person, g) in ctx.descendants(id) { groups.entry(g).or_default().push(&self.state.people[&person]); }
                let mut lines = vec![format!("GENERATIONS {id} {}", groups.len())];
                for (g, people) in groups {
                    let living = people.iter().filter(|p| p.death.is_none()).count();
                    let low = people.iter().map(|p| p.birth).min().unwrap();
                    let high = people.iter().map(|p| p.birth).max().unwrap();
                    lines.push(format!("  {g} {} {living} {low}-{high}", people.len()));
                }
                Ok(lines)
            }
            "TREE" => {
                let id = words[1];
                ctx.check(&[id])?;
                let mut lines = vec![format!("TREE {id} {}", ctx.descendants(id).len())];
                ctx.tree_visit(id, 0, &mut BTreeSet::new(), &mut lines);
                Ok(lines)
            }
            "PEDIGREE" => {
                let id = words[1];
                let depth: usize = words[2].parse().unwrap();
                ctx.check(&[id])?;
                let mut lines = Vec::new();
                let mut entered = BTreeSet::new();
                ctx.pedigree_enter(id, 1, 0, depth, &mut entered, &mut lines);
                lines.insert(0, format!("PEDIGREE {id} {depth} entries={} distinct={}", lines.len(), entered.len()));
                Ok(lines)
            }
            "TIMELINE" => {
                let id = words[1];
                ctx.check(&[id])?;
                let person = &self.state.people[id];
                let mut events = vec![(person.birth, 0, String::new(), "born".to_owned())];
                for marriage in &self.state.marriages {
                    if !marriage.contains(id) { continue; }
                    let other = marriage.other(id);
                    events.push((marriage.start, 1, other.to_owned(), format!("married {other}")));
                    if marriage.status == Status::Divorced {
                        events.push((marriage.end.unwrap(), 3, other.to_owned(), format!("divorced {other}")));
                    }
                    if marriage.status == Status::Widowed && marriage.died.as_deref() == Some(other) {
                        events.push((marriage.end.unwrap(), 4, other.to_owned(), format!("widowed {other}")));
                    }
                }
                for child in &ctx.children[id] {
                    events.push((self.state.people[child].birth, 2, child.clone(), format!("child {child}")));
                }
                for (relatives, label) in [(&person.parents, "parent"), (&ctx.children[id], "child")] {
                    for other in relatives {
                        if let Some(death) = self.state.people[other].death {
                            if death >= person.birth && person.death.is_none_or(|end| death <= end) {
                                events.push((death, 5, other.clone(), format!("lost {label} {other}")));
                            }
                        }
                    }
                }
                if let Some(death) = person.death { events.push((death, 6, String::new(), "died".to_owned())); }
                events.sort_by(|a, b| (&a.0, &a.1, &a.2).cmp(&(&b.0, &b.1, &b.2)));
                let mut lines = vec![format!("TIMELINE {id} {}", events.len())];
                lines.extend(events.into_iter().map(|(year, _, _, text)| format!("  {year} {text}")));
                Ok(lines)
            }
            "CENSUS" => {
                let year: i32 = words[1].parse().unwrap();
                let residents = ctx.age_order(self.state.people.iter().filter_map(|(id, person)| {
                    (person.birth <= year && person.death.is_none_or(|death| death > year)).then(|| id.clone())
                }).collect());
                let mut lines = vec![format!("CENSUS {year} {}", residents.len())];
                for id in residents {
                    let status = if let Some(marriage) = self.state.marriages.iter().rev().find(|m| m.contains(&id) && m.start <= year) {
                        if marriage.end.is_none_or(|end| end > year) { format!("married {}", marriage.other(&id)) }
                        else { marriage.status.as_str().to_owned() }
                    } else { "single".to_owned() };
                    lines.push(format!("  {id} {} {status}", year - self.state.people[&id].birth));
                }
                Ok(lines)
            }
            "KINSHIP" => {
                let (a, b) = (words[1], words[2]);
                ctx.check(&[a, b])?;
                Ok(vec![format!("KINSHIP {a} {b} {}", ctx.phi(a, b))])
            }
            "FIND" => {
                let id = words[1];
                let route = words[2];
                ctx.check(&[id])?;
                let mut found = BTreeSet::from([id.to_owned()]);
                for step in route.split('.') {
                    let sex = match step {
                        "father" | "son" | "brother" | "husband" => Some('M'),
                        "mother" | "daughter" | "sister" | "wife" => Some('F'),
                        _ => None,
                    };
                    let mut next = BTreeSet::new();
                    for person in found {
                        let candidates: Vec<String> = match step {
                            "parent" | "father" | "mother" => self.state.people[&person].parents.iter().cloned().collect(),
                            "child" | "son" | "daughter" => ctx.children[&person].iter().cloned().collect(),
                            "sibling" | "brother" | "sister" => self.state.people.keys().filter(|p| ctx.siblings(&person, p)).cloned().collect(),
                            _ => ctx.spouses.get(&person).cloned().into_iter().collect(),
                        };
                        for candidate in candidates {
                            if sex.is_none_or(|s| self.state.people[&candidate].sex == s) { next.insert(candidate); }
                        }
                    }
                    found = next;
                }
                found.remove(id);
                let mut lines = vec![format!("FIND {id} {route} {}", found.len())];
                lines.extend(found.into_iter().map(|person| format!("  {person}: {}", ctx.relationship_string(&person, id))));
                Ok(lines)
            }
            "TERM" => {
                let da: usize = words[1].parse().unwrap();
                let db: usize = words[2].parse().unwrap();
                let sex = words[3].chars().next().unwrap();
                Ok(vec![format!("TERM {da} {db} {sex} {}", term(da, db, sex))])
            }
            "STATS" => {
                let mut memo = BTreeMap::new();
                let generations = self.state.people.keys().map(|id| ctx.longest_lineage(id, &mut memo)).max().unwrap_or(0);
                let living = self.state.people.values().filter(|p| p.death.is_none()).count();
                let links: usize = self.state.people.values().map(|p| p.parents.len()).sum();
                let couples = self.state.marriages.iter().filter(|m| m.status == Status::Current).count();
                let founders = self.state.people.values().filter(|p| p.parents.is_empty()).count();
                Ok(vec![format!("STATS persons={} living={living} links={links} couples={couples} founders={founders} generations={generations}", self.state.people.len())])
            }
            "AUDIT" => {
                let mut lines = Vec::new();
                for marriage in &self.state.marriages {
                    if let Some(blood) = ctx.blood_term(&marriage.first, &marriage.second, self.state.people[&marriage.first].sex) {
                        lines.push(format!("  marriage {} {} {blood}", marriage.first, marriage.second));
                    }
                }
                for id in self.state.people.keys() {
                    let coefficient = ctx.inbreeding(id);
                    if coefficient.numerator != 0 { lines.push(format!("  inbred {id} {coefficient}")); }
                }
                lines.insert(0, format!("AUDIT {}", lines.len()));
                Ok(lines)
            }
            _ => unreachable!(),
        }
    }
}

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut lines = input.lines();
    let count: usize = lines.next().unwrap().parse().unwrap();
    let mut family = Family::default();
    let mut output = Vec::new();
    for line in lines.take(count) {
        match family.command(line) {
            Ok(lines) => output.extend(lines),
            Err(reason) => output.push(format!("ERROR {reason}")),
        }
    }
    if !output.is_empty() { println!("{}", output.join("\n")); }
}
