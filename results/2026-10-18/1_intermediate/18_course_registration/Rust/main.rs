use std::collections::{BTreeMap, BTreeSet};
use std::io::{self, Read};

const DAYS: [&str; 7] = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"];

fn number(text: &str) -> i32 { text.parse().unwrap() }

fn time(minutes: i32) -> String { format!("{:02}:{:02}", minutes / 60, minutes % 60) }

fn rate(enrolled: usize, capacity: usize) -> String {
    if capacity == 0 { "n/a".into() } else { format!("{}%", enrolled * 100 / capacity) }
}

#[derive(Clone)]
struct Slot { day: usize, start: i32, end: i32, text: String }

impl Slot {
    fn parse(text: &str) -> Result<Self, String> {
        let invalid = || format!("invalid slot {text}");
        let day = DAYS.iter().position(|day| *day == &text[..2]).ok_or_else(invalid)?;
        let (start_hour, start_minute) = (number(&text[2..4]), number(&text[4..6]));
        let (end_hour, end_minute) = (number(&text[7..9]), number(&text[9..11]));
        let (start, end) = (start_hour * 60 + start_minute, end_hour * 60 + end_minute);
        if start_hour > 23 || end_hour > 23 || start_minute > 59 || end_minute > 59 || start >= end {
            return Err(invalid());
        }
        Ok(Self { day, start, end, text: text.into() })
    }

    fn overlaps(&self, other: &Self) -> bool {
        self.day == other.day && self.start < other.end && other.start < self.end
    }
}

enum Prerequisite {
    None,
    Course(String),
    Year(i32),
    And(Vec<Prerequisite>),
    Or(Vec<Prerequisite>),
}

impl Prerequisite {
    fn combine(children: Vec<Self>, conjunction: bool) -> Self {
        let mut flattened = Vec::new();
        for child in children {
            match child {
                Self::And(nested) if conjunction => flattened.extend(nested),
                Self::Or(nested) if !conjunction => flattened.extend(nested),
                other => flattened.push(other),
            }
        }
        if flattened.len() == 1 { flattened.pop().unwrap() }
        else if conjunction { Self::And(flattened) } else { Self::Or(flattened) }
    }

    fn parse(code: &str, text: &str) -> Result<Self, String> {
        if text == "-" { return Ok(Self::None); }
        let mut parser = Parser { text: text.as_bytes(), position: 0 };
        let expression = parser.expression().map_err(|_| format!("invalid prereq {code}"))?;
        if parser.position != text.len() { return Err(format!("invalid prereq {code}")); }
        if expression.contains(code) { return Err(format!("self prereq {code}")); }
        Ok(expression)
    }

    fn contains(&self, course: &str) -> bool {
        match self {
            Self::Course(code) => code == course,
            Self::And(children) | Self::Or(children) => children.iter().any(|child| child.contains(course)),
            _ => false,
        }
    }

    fn satisfied(&self, student: &Student) -> bool {
        match self {
            Self::None => true,
            Self::Course(course) => student.passed(course).is_some(),
            Self::Year(year) => student.year >= *year,
            Self::And(children) => children.iter().all(|child| child.satisfied(student)),
            Self::Or(children) => children.iter().any(|child| child.satisfied(student)),
        }
    }

    fn canonical(&self) -> String {
        match self {
            Self::None => "-".into(),
            Self::Course(course) => course.clone(),
            Self::Year(year) => format!("Y{year}"),
            Self::And(children) => children.iter().map(|child| {
                let text = child.canonical();
                if matches!(child, Self::Or(_)) { format!("({text})") } else { text }
            }).collect::<Vec<_>>().join("&"),
            Self::Or(children) => children.iter().map(Self::canonical).collect::<Vec<_>>().join("|"),
        }
    }
}

struct Parser<'a> { text: &'a [u8], position: usize }

impl Parser<'_> {
    fn take(&mut self, symbol: u8) -> bool {
        if self.text.get(self.position) == Some(&symbol) { self.position += 1; true } else { false }
    }

    fn expression(&mut self) -> Result<Prerequisite, ()> {
        let mut children = vec![self.term()?];
        while self.take(b'|') { children.push(self.term()?); }
        Ok(Prerequisite::combine(children, false))
    }

    fn term(&mut self) -> Result<Prerequisite, ()> {
        let mut children = vec![self.factor()?];
        while self.take(b'&') { children.push(self.factor()?); }
        Ok(Prerequisite::combine(children, true))
    }

    fn factor(&mut self) -> Result<Prerequisite, ()> {
        if self.take(b'(') {
            let expression = self.expression()?;
            if !self.take(b')') { return Err(()); }
            return Ok(expression);
        }
        let start = self.position;
        while self.text.get(self.position).is_some_and(|byte| byte.is_ascii_alphanumeric()) { self.position += 1; }
        let word = &self.text[start..self.position];
        if word.len() == 2 && word[0] == b'Y' && (b'1'..=b'9').contains(&word[1]) {
            return Ok(Prerequisite::Year((word[1] - b'0') as i32));
        }
        let letters = word.iter().take_while(|byte| byte.is_ascii_uppercase()).count();
        if (2..=4).contains(&letters) && word.len() == letters + 3 && word[letters..].iter().all(u8::is_ascii_digit) {
            Ok(Prerequisite::Course(String::from_utf8(word.to_vec()).unwrap()))
        } else { Err(()) }
    }
}

struct Grade { letter: char, credits: i32 }

impl Grade {
    fn points(&self) -> i32 {
        match self.letter { 'A' => 4, 'B' => 3, 'C' => 2, 'D' => 1, _ => 0 }
    }
}

struct Student {
    year: i32,
    limit: i32,
    grades: BTreeMap<String, Grade>,
    enrolled: BTreeSet<String>,
    history: Vec<(usize, String)>,
}

impl Student {
    fn passed(&self, course: &str) -> Option<char> {
        self.grades.get(course).filter(|grade| matches!(grade.letter, 'A' | 'B' | 'C')).map(|grade| grade.letter)
    }

    fn earned(&self) -> i32 {
        self.grades.values().filter(|grade| grade.letter != 'F').map(|grade| grade.credits).sum()
    }

    fn gpa(&self) -> String {
        if self.grades.is_empty() { return "n/a".into(); }
        let credits: i32 = self.grades.values().map(|grade| grade.credits).sum();
        let points: i32 = self.grades.values().map(|grade| grade.points() * grade.credits).sum();
        let value = (200 * points + credits) / (2 * credits);
        format!("{}.{:02}", value / 100, value % 100)
    }
}

struct Course {
    credits: i32,
    capacity: usize,
    slots: Vec<Slot>,
    prereq: Prerequisite,
    open: bool,
    enrolled: BTreeSet<String>,
    waitlist: Vec<String>,
}

impl Course {
    fn weekly(&self) -> i32 { self.slots.iter().map(|slot| slot.end - slot.start).sum() }

    fn status(&self) -> &'static str { if self.open { "open" } else { "closed" } }

    fn free_seat(&self) -> bool { self.enrolled.len() < self.capacity }

    fn conflicts(&self, other: &Self) -> bool {
        self.slots.iter().any(|slot| other.slots.iter().any(|other| slot.overlaps(other)))
    }
}

struct Reason { word: &'static str, extra: String }

impl Reason {
    fn new(word: &'static str) -> Self { Self { word, extra: String::new() } }

    fn text(&self) -> String { format!("{}{}", self.word, self.extra) }

    fn error(&self, student: &str, course: &str) -> String { format!("{} {student} {course}{}", self.word, self.extra) }
}

enum Judgment { Enroll, Waitlist(usize), Reject(Reason) }

impl Judgment {
    fn text(&self) -> String {
        match self {
            Self::Enroll => "enroll".into(),
            Self::Waitlist(position) => format!("waitlist {position}"),
            Self::Reject(reason) => reason.text(),
        }
    }
}

#[derive(Default)]
struct Registrar {
    courses: BTreeMap<String, Course>,
    students: BTreeMap<String, Student>,
    command_number: usize,
}

impl Registrar {
    fn student(&self, id: &str) -> Result<&Student, String> {
        self.students.get(id).ok_or_else(|| format!("unknown student {id}"))
    }

    fn course(&self, code: &str) -> Result<&Course, String> {
        self.courses.get(code).ok_or_else(|| format!("unknown course {code}"))
    }

    fn credits(&self, student: &str, excluded: Option<&str>) -> i32 {
        self.students[student].enrolled.iter().filter(|code| Some(code.as_str()) != excluded)
            .map(|code| self.courses[code].credits).sum()
    }

    fn waitlists(&self, student: &str) -> usize {
        self.courses.values().filter(|course| course.waitlist.iter().any(|id| id == student)).count()
    }

    fn conflict(&self, student: &str, target: &str, excluded: Option<&str>) -> Option<&str> {
        self.students[student].enrolled.iter().filter(|code| Some(code.as_str()) != excluded)
            .find(|code| self.courses[*code].conflicts(&self.courses[target])).map(String::as_str)
    }

    fn eligible(&self, id: &str, code: &str, excluded: Option<&str>) -> Result<(), Reason> {
        let student = &self.students[id];
        let course = &self.courses[code];
        if !course.open { return Err(Reason::new("course closed")); }
        if course.enrolled.contains(id) { return Err(Reason::new("already enrolled")); }
        if course.waitlist.iter().any(|waiting| waiting == id) { return Err(Reason::new("already waitlisted")); }
        if let Some(grade) = student.passed(code) { return Err(Reason { word: "already completed", extra: format!(" {grade}") }); }
        if !course.prereq.satisfied(student) { return Err(Reason::new("prereq not met")); }
        if let Some(conflict) = self.conflict(id, code, excluded) { return Err(Reason { word: "time conflict", extra: format!(" {conflict}") }); }
        let total = self.credits(id, excluded) + course.credits;
        if total > student.limit { return Err(Reason { word: "credit limit", extra: format!(" {total} {}", student.limit) }); }
        Ok(())
    }

    fn judge(&self, student: &str, course: &str) -> Judgment {
        if let Err(reason) = self.eligible(student, course, None) { return Judgment::Reject(reason); }
        if self.courses[course].free_seat() { return Judgment::Enroll; }
        if self.waitlists(student) >= 3 { return Judgment::Reject(Reason::new("waitlist limit")); }
        let year = self.students[student].year;
        Judgment::Waitlist(1 + self.courses[course].waitlist.iter().filter(|id| self.students[*id].year >= year).count())
    }

    fn history(&mut self, student: &str, event: String) {
        self.students.get_mut(student).unwrap().history.push((self.command_number, event));
    }

    fn enroll(&mut self, student: &str, course: &str) {
        self.students.get_mut(student).unwrap().enrolled.insert(course.into());
        self.courses.get_mut(course).unwrap().enrolled.insert(student.into());
    }

    fn remove_enrollment(&mut self, student: &str, course: &str) {
        self.students.get_mut(student).unwrap().enrolled.remove(course);
        self.courses.get_mut(course).unwrap().enrolled.remove(student);
    }

    fn enrollment_line(&self, prefix: &str, student: &str, code: &str) {
        let course = &self.courses[code];
        println!("{prefix} {student} {code} enrolled {}/{} credits {}/{}", course.enrolled.len(), course.capacity,
                 self.credits(student, None), self.students[student].limit);
    }

    fn promote(&mut self) {
        let courses: Vec<String> = self.courses.keys().cloned().collect();
        for code in courses {
            loop {
                let course = &self.courses[&code];
                if !course.open || !course.free_seat() { break; }
                let candidate = course.waitlist.iter().position(|id| self.conflict(id, &code, None).is_none()
                    && self.credits(id, None) + course.credits <= self.students[id].limit);
                let Some(position) = candidate else { break; };
                let student = self.courses.get_mut(&code).unwrap().waitlist.remove(position);
                self.enroll(&student, &code);
                self.history(&student, format!("promote {code}"));
                self.enrollment_line("  PROMOTE", &student, &code);
            }
        }
    }

    fn meetings(&self, student: &str) -> Vec<(usize, i32, i32, &str)> {
        let mut meetings = Vec::new();
        for code in &self.students[student].enrolled {
            for slot in &self.courses[code].slots { meetings.push((slot.day, slot.start, slot.end, code.as_str())); }
        }
        meetings.sort_by_key(|meeting| (meeting.0, meeting.1));
        meetings
    }

    fn schedule(&self, id: &str) {
        let student = &self.students[id];
        let weekly = student.enrolled.iter().map(|code| self.courses[code].weekly()).sum();
        println!("SCHEDULE {id} courses {} credits {} weekly {}", student.enrolled.len(), self.credits(id, None), time(weekly));
        let meetings = self.meetings(id);
        for (day, name) in DAYS.iter().enumerate() {
            let slots: Vec<String> = meetings.iter().filter(|meeting| meeting.0 == day)
                .map(|(_, start, end, code)| format!("{}-{} {code}", time(*start), time(*end))).collect();
            if !slots.is_empty() { println!("  {name} {}", slots.join(" ")); }
        }
        let tba: Vec<&str> = student.enrolled.iter().filter(|code| self.courses[*code].slots.is_empty()).map(String::as_str).collect();
        if !tba.is_empty() { println!("  TBA {}", tba.join(" ")); }
    }

    fn free(&self, id: &str, day: usize) {
        let mut busy = [false; 840];
        for (meeting_day, start, end, _) in self.meetings(id) {
            if meeting_day == day {
                for minute in start.max(480)..end.min(1320) { busy[(minute - 480) as usize] = true; }
            }
        }
        let mut position = 0;
        let mut total = 0;
        let mut ranges = Vec::new();
        while position < busy.len() {
            if busy[position] { position += 1; continue; }
            let start = position;
            while position < busy.len() && !busy[position] { position += 1; }
            total += (position - start) as i32;
            ranges.push(format!("{}-{}", time(start as i32 + 480), time(position as i32 + 480)));
        }
        println!("FREE {id} {} total {}{}", DAYS[day], time(total),
                 if ranges.is_empty() { String::new() } else { format!(" {}", ranges.join(" ")) });
    }

    fn info(&self, code: &str) {
        let course = &self.courses[code];
        println!("INFO {code} {} credits {} capacity {} prereq {}", course.status(), course.credits, course.capacity, course.prereq.canonical());
        let mut slots: Vec<&Slot> = course.slots.iter().collect();
        slots.sort_by_key(|slot| (slot.day, slot.start));
        for slot in &slots { println!("  meet {} {}-{}", DAYS[slot.day], time(slot.start), time(slot.end)); }
        if slots.is_empty() { println!("  meet TBA"); }
        let dependents: Vec<&str> = self.courses.iter().filter(|(_, course)| course.prereq.contains(code)).map(|(code, _)| code.as_str()).collect();
        println!("  required by {}", if dependents.is_empty() { "none".into() } else { dependents.join(" ") });
    }

    fn audit(&self, id: &str) {
        let student = &self.students[id];
        println!("AUDIT {id} year {} limit {}", student.year, student.limit);
        for (code, grade) in &student.grades { println!("  record {code} {} {}", grade.letter, grade.credits); }
        println!("  earned {} gpa {}", student.earned(), student.gpa());
        for code in &student.enrolled { println!("  enrolled {code} {}", self.courses[code].credits); }
        let credits = self.credits(id, None);
        println!("  credits {credits} remaining {}", student.limit - credits);
        for (code, course) in &self.courses {
            if let Some(position) = course.waitlist.iter().position(|student| student == id) { println!("  waitlist {code} {}", position + 1); }
        }
    }

    fn report(&self) {
        let mut departments: BTreeMap<&str, [usize; 4]> = BTreeMap::new();
        let mut total = [0; 4];
        for (code, course) in &self.courses {
            let department = &code[..code.len() - 3];
            let counts = [1, course.enrolled.len(), course.capacity, course.waitlist.len()];
            let row = departments.entry(department).or_default();
            for index in 0..4 { row[index] += counts[index]; total[index] += counts[index]; }
        }
        println!("REPORT courses {} enrolled {}/{} rate {} waitlisted {}", total[0], total[1], total[2], rate(total[1], total[2]), total[3]);
        for (code, course) in &self.courses {
            println!("  {code} {} {}/{} {} waitlist {}", course.status(), course.enrolled.len(), course.capacity,
                     rate(course.enrolled.len(), course.capacity), course.waitlist.len());
        }
        for (department, counts) in departments {
            println!("  dept {department} courses {} enrolled {}/{} rate {} waitlisted {}", counts[0], counts[1], counts[2],
                     rate(counts[1], counts[2]), counts[3]);
        }
    }

    fn command(&mut self, tokens: &[&str]) -> Result<(), String> {
        let a = &tokens[1..];
        match tokens[0] {
            "COURSE" => {
                if self.courses.contains_key(a[0]) { return Err(format!("duplicate course {}", a[0])); }
                let slots: Vec<Slot> = if a[3] == "-" { Vec::new() }
                    else { a[3].split(',').map(Slot::parse).collect::<Result<_, _>>()? };
                for first in 0..slots.len() {
                    for second in first + 1..slots.len() {
                        if slots[first].overlaps(&slots[second]) {
                            return Err(format!("overlapping slots {} {}", slots[first].text, slots[second].text));
                        }
                    }
                }
                let prereq = Prerequisite::parse(a[0], a[4])?;
                let course = Course { credits: number(a[1]), capacity: number(a[2]) as usize,
                                      slots, prereq, open: true, enrolled: BTreeSet::new(), waitlist: Vec::new() };
                println!("COURSE {} credits {} capacity {} meetings {} weekly {} prereq {}", a[0], course.credits,
                         course.capacity, course.slots.len(), time(course.weekly()), course.prereq.canonical());
                self.courses.insert(a[0].into(), course);
            }
            "STUDENT" => {
                if self.students.contains_key(a[0]) { return Err(format!("duplicate student {}", a[0])); }
                let mut grades = BTreeMap::new();
                if a[3] != "-" {
                    for record in a[3].split(',') {
                        let parts: Vec<&str> = record.split(':').collect();
                        let letter = parts[1].chars().next().unwrap();
                        if !['A', 'B', 'C', 'D', 'F'].contains(&letter) {
                            return Err(format!("invalid grade {} {} {letter}", a[0], parts[0]));
                        }
                        if grades.contains_key(parts[0]) { return Err(format!("duplicate record {} {}", a[0], parts[0])); }
                        grades.insert(parts[0].to_string(), Grade { letter, credits: number(parts[2]) });
                    }
                }
                let student = Student { year: number(a[1]), limit: number(a[2]), grades,
                                        enrolled: BTreeSet::new(), history: Vec::new() };
                println!("STUDENT {} year {} limit {} records {} earned {} gpa {}", a[0], student.year,
                         student.limit, student.grades.len(), student.earned(), student.gpa());
                self.students.insert(a[0].into(), student);
            }
            "ENROLL" | "CHECK" => {
                self.student(a[0])?;
                self.course(a[1])?;
                let judgment = self.judge(a[0], a[1]);
                if tokens[0] == "CHECK" { println!("CHECK {} {} {}", a[0], a[1], judgment.text()); }
                else {
                    match judgment {
                        Judgment::Reject(reason) => return Err(reason.error(a[0], a[1])),
                        Judgment::Enroll => {
                            self.enroll(a[0], a[1]);
                            self.history(a[0], format!("enroll {}", a[1]));
                            self.enrollment_line("ENROLL", a[0], a[1]);
                        }
                        Judgment::Waitlist(position) => {
                            self.courses.get_mut(a[1]).unwrap().waitlist.insert(position - 1, a[0].into());
                            self.history(a[0], format!("waitlist {} {position}", a[1]));
                            println!("ENROLL {} {} waitlist {position}", a[0], a[1]);
                        }
                    }
                }
            }
            "OPTIONS" => {
                self.student(a[0])?;
                println!("OPTIONS {} courses {}", a[0], self.courses.len());
                for code in self.courses.keys() { println!("  {code} {}", self.judge(a[0], code).text()); }
            }
            "DROP" => {
                self.student(a[0])?;
                let course = self.course(a[1])?;
                if course.enrolled.contains(a[0]) {
                    self.remove_enrollment(a[0], a[1]);
                    self.history(a[0], format!("drop {}", a[1]));
                    self.enrollment_line("DROP", a[0], a[1]);
                } else if let Some(position) = course.waitlist.iter().position(|id| id == a[0]) {
                    self.courses.get_mut(a[1]).unwrap().waitlist.remove(position);
                    self.history(a[0], format!("drop {} waitlist", a[1]));
                    println!("DROP {} {} waitlist removed", a[0], a[1]);
                } else { return Err(format!("not registered {} {}", a[0], a[1])); }
                self.promote();
            }
            "SWAP" => {
                self.student(a[0])?;
                self.course(a[1])?;
                self.course(a[2])?;
                if !self.courses[a[1]].enrolled.contains(a[0]) { return Err(format!("not enrolled {} {}", a[0], a[1])); }
                if a[1] == a[2] { return Err(format!("same course {}", a[1])); }
                self.eligible(a[0], a[2], Some(a[1])).map_err(|reason| reason.error(a[0], a[2]))?;
                if !self.courses[a[2]].free_seat() { return Err(format!("course full {}", a[2])); }
                self.remove_enrollment(a[0], a[1]);
                self.enroll(a[0], a[2]);
                self.history(a[0], format!("swap {} {}", a[1], a[2]));
                println!("SWAP {} {} -> {} credits {}/{}", a[0], a[1], a[2], self.credits(a[0], None), self.students[a[0]].limit);
                self.promote();
            }
            "CLOSE" | "OPEN" => {
                let course = self.course(a[0])?;
                let open = tokens[0] == "OPEN";
                if course.open == open { return Err(format!("already {} {}", course.status(), a[0])); }
                let course = self.courses.get_mut(a[0]).unwrap();
                course.open = open;
                println!("{} {} enrolled {}/{} waitlist {}", tokens[0], a[0], course.enrolled.len(), course.capacity, course.waitlist.len());
                if open { self.promote(); }
            }
            "CAPACITY" => {
                let course = self.course(a[0])?;
                let capacity = number(a[1]) as usize;
                if capacity < course.enrolled.len() { return Err(format!("capacity below enrollment {} {}", a[0], course.enrolled.len())); }
                let course = self.courses.get_mut(a[0]).unwrap();
                let old = course.capacity;
                course.capacity = capacity;
                println!("CAPACITY {} {old} -> {capacity}", a[0]);
                self.promote();
            }
            "LIMIT" => {
                self.student(a[0])?;
                let limit = number(a[1]);
                let credits = self.credits(a[0], None);
                if limit < credits { return Err(format!("limit below enrolled {} {credits}", a[0])); }
                let student = self.students.get_mut(a[0]).unwrap();
                let old = student.limit;
                student.limit = limit;
                println!("LIMIT {} {old} -> {limit}", a[0]);
                self.promote();
            }
            "PREREQ" => {
                self.course(a[0])?;
                let prereq = Prerequisite::parse(a[0], a[1])?;
                let removed: Vec<String> = self.courses[a[0]].waitlist.iter()
                    .filter(|id| !prereq.satisfied(&self.students[*id])).cloned().collect();
                println!("PREREQ {} {}", a[0], prereq.canonical());
                let course = self.courses.get_mut(a[0]).unwrap();
                course.prereq = prereq;
                course.waitlist.retain(|student| !removed.contains(student));
                for student in removed {
                    self.history(&student, format!("unlist {}", a[0]));
                    println!("  UNLIST {student} {}", a[0]);
                }
            }
            "CANCEL" => {
                self.course(a[0])?;
                let course = self.courses.remove(a[0]).unwrap();
                println!("CANCEL {} enrolled {} waitlist {}", a[0], course.enrolled.len(), course.waitlist.len());
                for student in course.enrolled {
                    self.students.get_mut(&student).unwrap().enrolled.remove(a[0]);
                    self.history(&student, format!("cancel {}", a[0]));
                }
                for student in course.waitlist { self.history(&student, format!("cancel {} waitlist", a[0])); }
                self.promote();
            }
            "ROSTER" => {
                let course = self.course(a[0])?;
                println!("ROSTER {} {} enrolled {}/{} waitlist {}", a[0], course.status(), course.enrolled.len(), course.capacity, course.waitlist.len());
                for id in &course.enrolled { println!("  enrolled {id} year {}", self.students[id].year); }
                for (index, id) in course.waitlist.iter().enumerate() { println!("  waitlist {} {id} year {}", index + 1, self.students[id].year); }
            }
            "SCHEDULE" => { self.student(a[0])?; self.schedule(a[0]); }
            "FREE" => {
                self.student(a[0])?;
                let day = DAYS.iter().position(|day| *day == a[1]).ok_or_else(|| format!("invalid day {}", a[1]))?;
                self.free(a[0], day);
            }
            "INFO" => { self.course(a[0])?; self.info(a[0]); }
            "AUDIT" => { self.student(a[0])?; self.audit(a[0]); }
            "HISTORY" => {
                let student = self.student(a[0])?;
                println!("HISTORY {} events {}", a[0], student.history.len());
                for (command, event) in &student.history { println!("  {command} {event}"); }
            }
            "STUDENTS" => {
                println!("STUDENTS {}", self.students.len());
                for (id, student) in &self.students {
                    println!("  {id} year {} credits {}/{} courses {} waitlists {}", student.year,
                             self.credits(id, None), student.limit, student.enrolled.len(), self.waitlists(id));
                }
            }
            "REPORT" => self.report(),
            _ => unreachable!(),
        }
        Ok(())
    }
}

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut lines = input.lines();
    let count: usize = lines.next().unwrap().parse().unwrap();
    let mut registrar = Registrar::default();
    for (index, line) in lines.take(count).enumerate() {
        registrar.command_number = index + 1;
        let tokens: Vec<&str> = line.split_ascii_whitespace().collect();
        if let Err(error) = registrar.command(&tokens) { println!("ERROR {error}"); }
    }
}
