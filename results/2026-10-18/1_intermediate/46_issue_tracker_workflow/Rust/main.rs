use std::collections::{BTreeMap, BTreeSet};
use std::io::{self, Read};

const TYPES: &[&str] = &["BUG", "TASK", "STORY"];
const PRIORITIES: &[&str] = &["LOW", "MEDIUM", "HIGH", "CRITICAL"];
const ALL_STATES: &[&str] = &["OPEN", "TRIAGED", "IN_PROGRESS", "REVIEW", "RESOLVED", "CLOSED", "REOPENED", "DONE", "BACKLOG", "READY"];
const EQUALITY: &[&str] = &["=", "!="];
const ORDERED: &[&str] = &["=", "!=", "<", "<=", ">", ">="];

fn workflow(kind: &str) -> &'static [&'static str] {
    match kind {
        "BUG" => &["OPEN", "TRIAGED", "IN_PROGRESS", "REVIEW", "RESOLVED", "CLOSED", "REOPENED"],
        "TASK" => &["OPEN", "IN_PROGRESS", "DONE"],
        "STORY" => &["BACKLOG", "READY", "IN_PROGRESS", "REVIEW", "DONE"],
        _ => unreachable!(),
    }
}

fn can_move(kind: &str, from: &str, to: &str) -> bool {
    let edges: &[&str] = match kind {
        "BUG" => &["OPEN>TRIAGED", "TRIAGED>IN_PROGRESS", "IN_PROGRESS>REVIEW", "REVIEW>IN_PROGRESS", "REVIEW>RESOLVED", "RESOLVED>CLOSED", "RESOLVED>REOPENED", "CLOSED>REOPENED", "REOPENED>IN_PROGRESS"],
        "TASK" => &["OPEN>IN_PROGRESS", "IN_PROGRESS>OPEN", "IN_PROGRESS>DONE"],
        "STORY" => &["BACKLOG>READY", "READY>BACKLOG", "READY>IN_PROGRESS", "IN_PROGRESS>REVIEW", "REVIEW>IN_PROGRESS", "REVIEW>DONE"],
        _ => unreachable!(),
    };
    edges.contains(&format!("{from}>{to}").as_str())
}

fn yes_no(value: bool) -> &'static str { if value { "yes" } else { "no" } }
fn display_number(value: Option<i32>) -> String { value.map(|n| n.to_string()).unwrap_or_else(|| "-".to_owned()) }
fn number_list(numbers: &BTreeSet<i32>) -> String {
    if numbers.is_empty() { "-".to_owned() } else { numbers.iter().map(i32::to_string).collect::<Vec<_>>().join(",") }
}

struct Issue {
    number: i32,
    kind: String,
    priority: String,
    title: String,
    state: String,
    assignee: Option<String>,
    reviewer: Option<String>,
    estimate: Option<i32>,
    sprint: Option<String>,
    comments: i32,
    blocks: BTreeSet<i32>,
    blockers: BTreeSet<i32>,
    duplicate: Option<i32>,
    duplicates: BTreeSet<i32>,
    history: Vec<String>,
}

impl Issue {
    fn new(number: i32, kind: &str, priority: &str, title: String) -> Self {
        Self {
            number, kind: kind.to_owned(), priority: priority.to_owned(), title,
            state: workflow(kind)[0].to_owned(), assignee: None, reviewer: None,
            estimate: None, sprint: None, comments: 0, blocks: BTreeSet::new(),
            blockers: BTreeSet::new(), duplicate: None, duplicates: BTreeSet::new(), history: Vec::new(),
        }
    }
    fn done(&self) -> bool { matches!(self.state.as_str(), "RESOLVED" | "CLOSED" | "DONE") }
    fn points(&self) -> i32 { self.estimate.unwrap_or(0) }
    fn level(&self) -> i32 { PRIORITIES.iter().position(|&p| p == self.priority).unwrap() as i32 }
}

struct Sprint {
    name: String,
    phase: String,
    start: Option<i32>,
    end: Option<i32>,
    velocity: i32,
    records: BTreeMap<i32, i32>,
}

impl Sprint {
    fn new(name: &str) -> Self {
        Self { name: name.to_owned(), phase: "PLANNED".to_owned(), start: None, end: None, velocity: 0, records: BTreeMap::new() }
    }
}

#[derive(Clone, PartialEq, Eq)]
enum QueryValue {
    None,
    Number(i32),
    Text(String),
}

#[derive(Clone)]
struct Condition {
    field: String,
    operation: String,
    value: QueryValue,
}

impl Condition {
    fn matches(&self, tracker: &Tracker, issue: &Issue) -> bool {
        let actual = tracker.field_value(issue, &self.field);
        match self.operation.as_str() {
            "=" => actual == self.value,
            "!=" => actual != self.value,
            "~" => match (&actual, &self.value) { (QueryValue::Text(a), QueryValue::Text(b)) => a.contains(b.as_str()), _ => false },
            operation => match (&actual, &self.value) {
                (QueryValue::Number(a), QueryValue::Number(b)) => match operation {
                    "<" => a < b, "<=" => a <= b, ">" => a > b, _ => a >= b,
                },
                _ => false,
            },
        }
    }
}

enum QueryNode {
    Condition(Condition),
    Not(Box<QueryNode>),
    And(Box<QueryNode>, Box<QueryNode>),
    Or(Box<QueryNode>, Box<QueryNode>),
}

impl QueryNode {
    fn matches(&self, tracker: &Tracker, issue: &Issue) -> bool {
        match self {
            Self::Condition(condition) => condition.matches(tracker, issue),
            Self::Not(node) => !node.matches(tracker, issue),
            Self::And(a, b) => a.matches(tracker, issue) && b.matches(tracker, issue),
            Self::Or(a, b) => a.matches(tracker, issue) || b.matches(tracker, issue),
        }
    }
}

struct QueryParser<'a> {
    tokens: &'a [String],
    conditions: Vec<Option<Condition>>,
    position: usize,
}

impl QueryParser<'_> {
    fn accept(&mut self, token: &str) -> bool {
        if self.tokens.get(self.position).is_some_and(|t| t == token) {
            self.position += 1;
            true
        } else { false }
    }
    fn expression(&mut self) -> QueryNode {
        let mut node = self.term();
        while self.accept("OR") { node = QueryNode::Or(Box::new(node), Box::new(self.term())); }
        node
    }
    fn term(&mut self) -> QueryNode {
        let mut node = self.factor();
        while self.accept("AND") { node = QueryNode::And(Box::new(node), Box::new(self.factor())); }
        node
    }
    fn factor(&mut self) -> QueryNode {
        if self.accept("NOT") { return QueryNode::Not(Box::new(self.factor())); }
        if self.accept("(") {
            let node = self.expression();
            self.accept(")");
            return node;
        }
        let condition = self.conditions[self.position].take().unwrap();
        self.position += 1;
        QueryNode::Condition(condition)
    }
}

fn query_tokens(text: &str) -> Vec<String> {
    let mut tokens = Vec::new();
    let mut current = String::new();
    for character in text.chars() {
        if matches!(character, ' ' | '(' | ')') {
            if !current.is_empty() { tokens.push(std::mem::take(&mut current)); }
            if character != ' ' { tokens.push(character.to_string()); }
        } else { current.push(character); }
    }
    if !current.is_empty() { tokens.push(current); }
    tokens
}

#[derive(Default)]
struct Tracker {
    day: i32,
    users: BTreeSet<String>,
    issues: BTreeMap<i32, Issue>,
    sprints: Vec<Sprint>,
    sprint_indices: BTreeMap<String, usize>,
}

impl Tracker {
    fn require_issue(&self, text: &str) -> Result<i32, String> {
        let number = text.parse().unwrap();
        if self.issues.contains_key(&number) { Ok(number) } else { Err("unknown issue".to_owned()) }
    }
    fn require_user(&self, text: &str) -> Result<Option<String>, String> {
        if text == "-" { Ok(None) }
        else if self.users.contains(text) { Ok(Some(text.to_owned())) }
        else { Err("unknown user".to_owned()) }
    }
    fn require_sprint(&self, name: &str) -> Result<usize, String> {
        self.sprint_indices.get(name).copied().ok_or_else(|| "unknown sprint".to_owned())
    }
    fn require_not_done(&self, number: i32) -> Result<(), String> {
        if self.issues[&number].done() { Err("issue done".to_owned()) } else { Ok(()) }
    }
    fn record(&mut self, number: i32, content: String) {
        self.issues.get_mut(&number).unwrap().history.push(format!("day {} {content}", self.day));
    }
    fn unfinished_blockers(&self, number: i32) -> Vec<i32> {
        self.issues[&number].blockers.iter().copied().filter(|n| !self.issues[n].done()).collect()
    }
    fn blocked(&self, number: i32) -> bool { !self.issues[&number].done() && !self.unfinished_blockers(number).is_empty() }
    fn wip(&self, user: Option<&str>) -> usize {
        self.issues.values().filter(|i| i.assignee.as_deref() == user && i.state == "IN_PROGRESS").count()
    }
    fn active_sprint(&self) -> Option<usize> { self.sprints.iter().position(|s| s.phase == "ACTIVE") }
    fn members(&self, index: usize) -> Vec<i32> {
        self.issues.values().filter(|i| i.sprint.as_deref() == Some(self.sprints[index].name.as_str())).map(|i| i.number).collect()
    }
    fn remaining(&self, index: usize) -> i32 {
        self.members(index).iter().filter(|n| !self.issues[*n].done()).map(|n| self.issues[n].points()).sum()
    }
    fn summary(&self, index: usize) -> String {
        let members = self.members(index);
        let points: i32 = members.iter().map(|n| self.issues[n].points()).sum();
        format!("issues {} points {points}", members.len())
    }
    fn notify(&self, before: &BTreeMap<i32, bool>) -> Vec<String> {
        before.iter().filter_map(|(&number, &old)| {
            let after = self.blocked(number);
            (after != old).then(|| format!("{} {number}", if after { "BLOCKED" } else { "UNBLOCKED" }))
        }).collect()
    }
    fn change_state(&mut self, number: i32, target: &str) -> Vec<String> {
        let before = self.issues[&number].blocks.iter().map(|&n| (n, self.blocked(n))).collect();
        let old = self.issues[&number].state.clone();
        self.record(number, format!("MOVE {old} {target}"));
        self.issues.get_mut(&number).unwrap().state = target.to_owned();
        let mut lines = vec![format!("MOVE {number} {old} {target}")];
        lines.extend(self.notify(&before));
        lines
    }
    fn reaches(&self, start: i32, goal: i32) -> bool {
        let mut pending = vec![start];
        let mut seen = BTreeSet::new();
        while let Some(number) = pending.pop() {
            if number == goal { return true; }
            if seen.insert(number) { pending.extend(self.issues[&number].blocks.iter().copied()); }
        }
        false
    }

    fn field_value(&self, issue: &Issue, field: &str) -> QueryValue {
        match field {
            "id" => QueryValue::Number(issue.number),
            "type" => QueryValue::Text(issue.kind.clone()),
            "status" => QueryValue::Text(issue.state.clone()),
            "priority" => QueryValue::Number(issue.level()),
            "assignee" => issue.assignee.clone().map(QueryValue::Text).unwrap_or(QueryValue::None),
            "reviewer" => issue.reviewer.clone().map(QueryValue::Text).unwrap_or(QueryValue::None),
            "estimate" => issue.estimate.map(QueryValue::Number).unwrap_or(QueryValue::None),
            "sprint" => issue.sprint.clone().map(QueryValue::Text).unwrap_or(QueryValue::None),
            "comments" => QueryValue::Number(issue.comments),
            "blocked" => QueryValue::Text(yes_no(self.blocked(issue.number)).to_owned()),
            "done" => QueryValue::Text(yes_no(issue.done()).to_owned()),
            _ => QueryValue::Text(issue.title.to_ascii_lowercase()),
        }
    }

    fn condition(&self, token: &str) -> Result<Condition, String> {
        let length = token.bytes().take_while(|b| b.is_ascii_lowercase()).count();
        let field = &token[..length];
        let rest = &token[length..];
        let operation = [">=", "<=", "!=", "=", "<", ">", "~"].iter().copied().find(|op| rest.starts_with(*op));
        let Some(operation) = operation else { return Err(format!("syntax near {token}")); };
        let text = &rest[operation.len()..];
        if field.is_empty() || text.is_empty() { return Err(format!("syntax near {token}")); }
        let allowed = match field {
            "id" | "priority" | "estimate" | "comments" => ORDERED,
            "type" | "status" | "assignee" | "reviewer" | "sprint" | "blocked" | "done" => EQUALITY,
            "title" => &["~"],
            _ => return Err(format!("unknown field {field}")),
        };
        if !allowed.contains(&operation) { return Err(format!("bad operator {token}")); }
        let value = if text == "-" && matches!(field, "assignee" | "reviewer" | "estimate" | "sprint") && EQUALITY.contains(&operation) {
            QueryValue::None
        } else if matches!(field, "id" | "estimate" | "comments") && (1..=6).contains(&text.len()) && text.bytes().all(|b| b.is_ascii_digit()) {
            QueryValue::Number(text.parse().unwrap())
        } else if field == "priority" && PRIORITIES.contains(&text) {
            QueryValue::Number(PRIORITIES.iter().position(|&p| p == text).unwrap() as i32)
        } else if (field == "type" && TYPES.contains(&text)) || (field == "status" && ALL_STATES.contains(&text))
            || (matches!(field, "assignee" | "reviewer") && self.users.contains(text))
            || (field == "sprint" && self.sprint_indices.contains_key(text))
            || (matches!(field, "blocked" | "done") && matches!(text, "yes" | "no")) {
            QueryValue::Text(text.to_owned())
        } else if field == "title" {
            QueryValue::Text(text.to_ascii_lowercase())
        } else { return Err(format!("bad value {token}")); };
        Ok(Condition { field: field.to_owned(), operation: operation.to_owned(), value })
    }

    fn query(&self, text: &str) -> Result<Vec<String>, String> {
        let tokens = query_tokens(text);
        let mut conditions = Vec::new();
        let mut expecting_operand = true;
        let mut depth = 0;
        for token in &tokens {
            let mut condition = None;
            if expecting_operand {
                match token.as_str() {
                    "(" => depth += 1,
                    "AND" | "OR" | ")" => return Err(format!("syntax near {token}")),
                    "NOT" => {},
                    _ => { condition = Some(self.condition(token)?); expecting_operand = false; }
                }
            } else {
                match token.as_str() {
                    "AND" | "OR" => expecting_operand = true,
                    ")" if depth > 0 => depth -= 1,
                    _ => return Err(format!("syntax near {token}")),
                }
            }
            conditions.push(condition);
        }
        if expecting_operand || depth != 0 { return Err("syntax at end".to_owned()); }
        let tree = QueryParser { tokens: &tokens, conditions, position: 0 }.expression();
        let mut matches: Vec<_> = self.issues.values().filter(|i| tree.matches(self, i)).collect();
        matches.sort_by_key(|i| (-i.level(), i.number));
        let mut lines = vec![format!("QUERY {}", matches.len())];
        lines.extend(matches.into_iter().map(|i| format!("{} {} {} {} {} {} {}", i.number, i.kind, i.priority, i.state, i.assignee.as_deref().unwrap_or("-"), display_number(i.estimate), i.title)));
        Ok(lines)
    }

    fn sprint_command(&mut self, words: &[&str]) -> Result<Vec<String>, String> {
        let (action, name) = (words[1], words[2]);
        if action == "NEW" {
            if self.sprint_indices.contains_key(name) { return Err("sprint exists".to_owned()); }
            self.sprint_indices.insert(name.to_owned(), self.sprints.len());
            self.sprints.push(Sprint::new(name));
            return Ok(vec![format!("SPRINT NEW {name}")]);
        }
        let index = self.require_sprint(name)?;
        if matches!(action, "ADD" | "REMOVE") {
            let number = self.require_issue(words[3])?;
            if self.sprints[index].phase == "ENDED" { return Err("sprint ended".to_owned()); }
            if action == "ADD" {
                self.require_not_done(number)?;
                let issue = &self.issues[&number];
                if let Some(old) = &issue.sprint {
                    if self.sprints[self.sprint_indices[old]].phase != "ENDED" { return Err(format!("in sprint {old}")); }
                }
                if issue.state == "BACKLOG" { return Err("not ready".to_owned()); }
                self.issues.get_mut(&number).unwrap().sprint = Some(name.to_owned());
            } else {
                if self.issues[&number].sprint.as_deref() != Some(name) { return Err("not in sprint".to_owned()); }
                self.require_not_done(number)?;
                self.issues.get_mut(&number).unwrap().sprint = None;
            }
            self.record(number, format!("SPRINT {action} {name}"));
            return Ok(vec![format!("SPRINT {action} {name} {number} {}", self.summary(index))]);
        }
        if action == "START" {
            if self.sprints[index].phase != "PLANNED" { return Err("sprint not planned".to_owned()); }
            if let Some(active) = self.active_sprint() { return Err(format!("sprint active {}", self.sprints[active].name)); }
            if self.members(index).is_empty() { return Err("sprint empty".to_owned()); }
            self.sprints[index].phase = "ACTIVE".to_owned();
            self.sprints[index].start = Some(self.day);
            let remaining = self.remaining(index);
            self.sprints[index].records.insert(self.day, remaining);
            return Ok(vec![format!("SPRINT START {name} day {} {} remaining {remaining}", self.day, self.summary(index))]);
        }
        if self.sprints[index].phase != "ACTIVE" { return Err("sprint not active".to_owned()); }
        let remaining = self.remaining(index);
        self.sprints[index].records.insert(self.day, remaining);
        let (finished, returned): (Vec<_>, Vec<_>) = self.members(index).into_iter().partition(|n| self.issues[n].done());
        let velocity: i32 = finished.iter().map(|n| self.issues[n].points()).sum();
        self.sprints[index].velocity = velocity;
        self.sprints[index].phase = "ENDED".to_owned();
        self.sprints[index].end = Some(self.day);
        let mut lines = vec![format!("SPRINT END {name} day {} velocity {velocity} done {} returned {}", self.day, finished.len(), returned.len())];
        for number in returned {
            self.issues.get_mut(&number).unwrap().sprint = None;
            self.record(number, format!("SPRINT RETURN {name}"));
            lines.push(format!("RETURNED {number}"));
        }
        Ok(lines)
    }

    fn command(&mut self, line: &str) -> Result<Vec<String>, String> {
        let words: Vec<_> = line.split(' ').collect();
        let command = words[0];
        match command {
            "DAY" => {
                let day = words[1].parse().unwrap();
                if day < self.day { return Err("day backwards".to_owned()); }
                self.day = day;
                Ok(vec![format!("DAY {day}")])
            }
            "USER" => {
                if !self.users.insert(words[1].to_owned()) { return Err("user exists".to_owned()); }
                Ok(vec![format!("USER {}", words[1])])
            }
            "CREATE" => {
                let number = words[1].parse().unwrap();
                let (kind, priority) = (words[2], words[3]);
                if self.issues.contains_key(&number) { return Err("issue exists".to_owned()); }
                if !TYPES.contains(&kind) { return Err("bad type".to_owned()); }
                if !PRIORITIES.contains(&priority) { return Err("bad priority".to_owned()); }
                let issue = Issue::new(number, kind, priority, words[4..].join(" "));
                let state = issue.state.clone();
                self.issues.insert(number, issue);
                self.record(number, format!("CREATE {kind} {priority}"));
                Ok(vec![format!("CREATE {number} {kind} {priority} {state}")])
            }
            "PRIORITY" => {
                let number = self.require_issue(words[1])?;
                let priority = words[2];
                if !PRIORITIES.contains(&priority) { return Err("bad priority".to_owned()); }
                self.require_not_done(number)?;
                let old = self.issues[&number].priority.clone();
                if old == priority { return Err("no change".to_owned()); }
                self.issues.get_mut(&number).unwrap().priority = priority.to_owned();
                self.record(number, format!("PRIORITY {old} {priority}"));
                Ok(vec![format!("PRIORITY {number} {old} {priority}")])
            }
            "ASSIGN" | "REVIEWER" => {
                let number = self.require_issue(words[1])?;
                let user = self.require_user(words[2])?;
                self.require_not_done(number)?;
                let issue = &self.issues[&number];
                if command == "ASSIGN" {
                    if user == issue.assignee { return Err("no change".to_owned()); }
                    if user.is_none() && matches!(issue.state.as_str(), "IN_PROGRESS" | "REVIEW") { return Err("assignee required".to_owned()); }
                    if issue.state == "IN_PROGRESS" && self.wip(user.as_deref()) >= 3 { return Err(format!("wip limit {}", words[2])); }
                    if issue.state == "REVIEW" && user == issue.reviewer { return Err("reviewer is assignee".to_owned()); }
                    self.issues.get_mut(&number).unwrap().assignee = user;
                } else {
                    if user == issue.reviewer { return Err("no change".to_owned()); }
                    if issue.state == "REVIEW" && user.is_none() { return Err("reviewer required".to_owned()); }
                    if issue.state == "REVIEW" && user == issue.assignee { return Err("reviewer is assignee".to_owned()); }
                    self.issues.get_mut(&number).unwrap().reviewer = user;
                }
                self.record(number, format!("{command} {}", words[2]));
                Ok(vec![format!("{command} {number} {}", words[2])])
            }
            "ESTIMATE" => {
                let number = self.require_issue(words[1])?;
                let points = words[2].parse().unwrap();
                if ![0, 1, 2, 3, 5, 8, 13, 21].contains(&points) { return Err("bad estimate".to_owned()); }
                self.require_not_done(number)?;
                let old = self.issues[&number].estimate;
                if old == Some(points) { return Err("no change".to_owned()); }
                self.issues.get_mut(&number).unwrap().estimate = Some(points);
                self.record(number, format!("ESTIMATE {} {points}", display_number(old)));
                Ok(vec![format!("ESTIMATE {number} {} {points}", display_number(old))])
            }
            "COMMENT" => {
                let number = self.require_issue(words[1])?;
                self.require_user(words[2])?;
                self.issues.get_mut(&number).unwrap().comments += 1;
                self.record(number, format!("COMMENT {} {}", words[2], words[3..].join(" ")));
                Ok(vec![format!("COMMENT {number} {}", self.issues[&number].comments)])
            }
            "MOVE" => {
                let number = self.require_issue(words[1])?;
                let target = words[2];
                let issue = &self.issues[&number];
                if let Some(duplicate) = issue.duplicate { return Err(format!("duplicate of {duplicate}")); }
                if !workflow(&issue.kind).contains(&target) { return Err("bad state".to_owned()); }
                if !can_move(&issue.kind, &issue.state, target) { return Err(format!("cannot move {} to {target}", issue.state)); }
                if target == "IN_PROGRESS" {
                    if issue.kind == "STORY" && self.active_sprint().is_none_or(|i| issue.sprint.as_deref() != Some(self.sprints[i].name.as_str())) {
                        return Err("not in active sprint".to_owned());
                    }
                    let user = issue.assignee.as_deref().ok_or("no assignee")?;
                    if self.wip(Some(user)) >= 3 { return Err(format!("wip limit {user}")); }
                }
                if target == "REVIEW" {
                    if issue.reviewer.is_none() { return Err("no reviewer".to_owned()); }
                    if issue.reviewer == issue.assignee { return Err("reviewer is assignee".to_owned()); }
                }
                if matches!(target, "DONE" | "RESOLVED") {
                    if let Some(blocker) = self.unfinished_blockers(number).first() { return Err(format!("blocked by {blocker}")); }
                }
                if target == "READY" && issue.estimate.is_none() { return Err("no estimate".to_owned()); }
                Ok(self.change_state(number, target))
            }
            "LINK" | "UNLINK" => {
                let relation = words[2];
                let unlink = command == "UNLINK";
                if relation != "BLOCKS" && (unlink || relation != "DUPLICATES") { return Err("bad link".to_owned()); }
                let a = self.require_issue(words[1])?;
                let b = self.require_issue(words[3])?;
                if unlink {
                    if !self.issues[&a].blocks.contains(&b) { return Err("no link".to_owned()); }
                } else {
                    if a == b { return Err("self link".to_owned()); }
                    if relation == "BLOCKS" {
                        if self.issues[&a].blocks.contains(&b) { return Err("link exists".to_owned()); }
                        if self.reaches(b, a) { return Err("cycle".to_owned()); }
                        self.require_not_done(b)?;
                    } else {
                        if self.issues[&a].kind != self.issues[&b].kind { return Err("type mismatch".to_owned()); }
                        self.require_not_done(a)?;
                        if self.issues[&b].duplicate.is_some() { return Err("target is duplicate".to_owned()); }
                        let target_state = if self.issues[&a].kind == "BUG" { "CLOSED" } else { "DONE" };
                        self.issues.get_mut(&a).unwrap().duplicate = Some(b);
                        self.issues.get_mut(&b).unwrap().duplicates.insert(a);
                        self.record(a, format!("LINK DUPLICATES {b}"));
                        self.record(b, format!("LINK DUPLICATED_BY {a}"));
                        let mut lines = vec![format!("LINK {a} DUPLICATES {b}")];
                        lines.extend(self.change_state(a, target_state));
                        if let Some(old) = self.issues[&a].sprint.clone() {
                            if self.sprints[self.sprint_indices[&old]].phase != "ENDED" {
                                self.issues.get_mut(&a).unwrap().sprint = None;
                                self.record(a, format!("SPRINT REMOVE {old}"));
                            }
                        }
                        return Ok(lines);
                    }
                }
                let before = BTreeMap::from([(b, self.blocked(b))]);
                if unlink {
                    self.issues.get_mut(&a).unwrap().blocks.remove(&b);
                    self.issues.get_mut(&b).unwrap().blockers.remove(&a);
                } else {
                    self.issues.get_mut(&a).unwrap().blocks.insert(b);
                    self.issues.get_mut(&b).unwrap().blockers.insert(a);
                }
                self.record(a, format!("{command} BLOCKS {b}"));
                self.record(b, format!("{command} BLOCKED_BY {a}"));
                let mut lines = vec![format!("{command} {a} BLOCKS {b}")];
                lines.extend(self.notify(&before));
                Ok(lines)
            }
            "SPRINT" => self.sprint_command(&words),
            "QUERY" => self.query(&words[1..].join(" ")),
            "SHOW" => {
                let number = self.require_issue(words[1])?;
                let issue = &self.issues[&number];
                Ok(vec![
                    format!("ISSUE {number} {} {} {} blocked {}", issue.kind, issue.priority, issue.state, yes_no(self.blocked(number))),
                    format!("TITLE {}", issue.title),
                    format!("PEOPLE assignee {} reviewer {}", issue.assignee.as_deref().unwrap_or("-"), issue.reviewer.as_deref().unwrap_or("-")),
                    format!("PLAN estimate {} sprint {} comments {}", display_number(issue.estimate), issue.sprint.as_deref().unwrap_or("-"), issue.comments),
                    format!("LINKS blocks {} blocked_by {} duplicate_of {} duplicated_by {}", number_list(&issue.blocks), number_list(&issue.blockers), display_number(issue.duplicate), number_list(&issue.duplicates)),
                ])
            }
            "HISTORY" => {
                let number = self.require_issue(words[1])?;
                let issue = &self.issues[&number];
                let mut lines = vec![format!("HISTORY {number} {}", issue.history.len())];
                lines.extend(issue.history.iter().cloned());
                Ok(lines)
            }
            "BOARD" => {
                let mut lines = vec!["BOARD".to_owned()];
                for &kind in TYPES {
                    let mut line = kind.to_owned();
                    for &state in workflow(kind) {
                        let count = self.issues.values().filter(|i| i.kind == kind && i.state == state).count();
                        line.push_str(&format!(" {state} {count}"));
                    }
                    lines.push(line);
                }
                let done = self.issues.values().filter(|i| i.done()).count();
                lines.push(format!("TOTAL {} open {} done {done}", self.issues.len(), self.issues.len() - done));
                Ok(lines)
            }
            "WORKLOAD" => {
                let mut lines = vec![format!("WORKLOAD {}", self.users.len())];
                for user in &self.users {
                    let assigned: Vec<_> = self.issues.values().filter(|i| !i.done() && i.assignee.as_ref() == Some(user)).collect();
                    let progress = assigned.iter().filter(|i| i.state == "IN_PROGRESS").count();
                    let review = assigned.iter().filter(|i| i.state == "REVIEW").count();
                    let reviewing = self.issues.values().filter(|i| i.reviewer.as_ref() == Some(user) && i.state == "REVIEW").count();
                    let points: i32 = assigned.iter().map(|i| i.points()).sum();
                    lines.push(format!("{user} assigned {} in_progress {progress} review {review} reviewing {reviewing} points {points}", assigned.len()));
                }
                Ok(lines)
            }
            "SPRINTS" => {
                let mut lines = vec![format!("SPRINTS {}", self.sprints.len())];
                for (index, sprint) in self.sprints.iter().enumerate() {
                    lines.push(match sprint.phase.as_str() {
                        "PLANNED" => format!("{} PLANNED {}", sprint.name, self.summary(index)),
                        "ACTIVE" => format!("{} ACTIVE start {} {} remaining {}", sprint.name, sprint.start.unwrap(), self.summary(index), self.remaining(index)),
                        _ => format!("{} ENDED start {} end {} velocity {}", sprint.name, sprint.start.unwrap(), sprint.end.unwrap(), sprint.velocity),
                    });
                }
                Ok(lines)
            }
            "BURNDOWN" => {
                let index = self.require_sprint(words[1])?;
                let sprint = &self.sprints[index];
                if sprint.phase == "PLANNED" { return Err("sprint not started".to_owned()); }
                let start = sprint.start.unwrap();
                let last = if sprint.phase == "ACTIVE" { self.day } else { sprint.end.unwrap() };
                let mut lines = vec![format!("BURNDOWN {} {} days {}", sprint.name, sprint.phase, last - start + 1)];
                let mut points = 0;
                for day in start..=last {
                    if let Some(&recorded) = sprint.records.get(&day) { points = recorded; }
                    lines.push(format!("day {day} {points}"));
                }
                Ok(lines)
            }
            _ => unreachable!(),
        }
    }

    fn execute(&mut self, line: &str) -> Vec<String> {
        let lines = self.command(line).unwrap_or_else(|error| vec![format!("ERROR {error}")]);
        if let Some(index) = self.active_sprint() {
            let points = self.remaining(index);
            self.sprints[index].records.insert(self.day, points);
        }
        lines
    }
}

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut lines = input.lines();
    let count: usize = lines.next().unwrap().parse().unwrap();
    let mut tracker = Tracker { day: 1, ..Tracker::default() };
    let mut output = Vec::new();
    for line in lines.take(count) { output.extend(tracker.execute(line)); }
    if !output.is_empty() { println!("{}", output.join("\n")); }
}
