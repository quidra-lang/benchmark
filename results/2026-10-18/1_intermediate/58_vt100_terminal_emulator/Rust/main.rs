use std::collections::BTreeSet;
use std::io::{self, BufRead};

#[derive(Clone, Debug, PartialEq, Eq)]
struct Attributes { flags: u8, fg: String, bg: String }
impl Default for Attributes {
    fn default() -> Self { Self { flags: 0, fg: "default".into(), bg: "default".into() } }
}
#[derive(Clone)]
struct Cell { ch: char, attr: Attributes }
impl Default for Cell {
    fn default() -> Self { Self { ch: ' ', attr: Attributes::default() } }
}
#[derive(Clone)]
struct Saved { row: usize, col: usize, attr: Attributes, origin: bool, g0: bool, g1: bool, gl: bool }
#[derive(Clone, Copy, PartialEq, Eq)]
enum Parser { Ground, Escape, EscapeIntermediate, CsiEntry, CsiParam, CsiIntermediate, CsiIgnore, Osc }
const IRM: usize = 0;
const LNM: usize = 1;
const CKM: usize = 2;
const SCNM: usize = 3;
const ORIGIN: usize = 4;
const WRAP: usize = 5;
const VISIBLE: usize = 6;
const KEYPAD: usize = 7;
const BRACKETED: usize = 8;
struct Terminal {
    w: usize, h: usize, screens: [Vec<Vec<Cell>>; 2], screen: usize,
    row: usize, col: usize, top: usize, bottom: usize, shape: usize,
    pending: bool, attr: Attributes, modes: [bool; 9], g0: bool, g1: bool, gl: bool,
    tabs: BTreeSet<usize>, saved: [Option<Saved>; 2], back: Vec<String>, title: Option<String>, last: Option<char>,
    parser: Parser, marker: String, parameters: String, intermediate: String, osc: String,
    bytes: usize, printed: usize, sequences: usize, bells: usize, replies: usize, dumps: usize, ignored: [usize; 4],
}
impl Terminal {
    fn new(w: usize, h: usize) -> Self {
        let mut t = Self {
            w, h, screens: [vec![], vec![]], screen: 0, row: 1, col: 1, top: 1, bottom: h, shape: 1,
            pending: false, attr: Attributes::default(), modes: [false; 9], g0: false, g1: false, gl: false,
            tabs: BTreeSet::new(), saved: [None, None], back: vec![], title: None, last: None,
            parser: Parser::Ground, marker: String::new(), parameters: String::new(), intermediate: String::new(), osc: String::new(),
            bytes: 0, printed: 0, sequences: 0, bells: 0, replies: 0, dumps: 0, ignored: [0; 4],
        };
        t.reset(); t
    }
    fn blank_row(&self) -> Vec<Cell> { vec![Cell::default(); self.w] }
    fn blank_screen(&self) -> Vec<Vec<Cell>> { vec![self.blank_row(); self.h] }
    fn reset(&mut self) {
        self.screens = [self.blank_screen(), self.blank_screen()];
        self.screen = 0; self.row = 1; self.col = 1; self.top = 1; self.bottom = self.h; self.shape = 1;
        self.pending = false; self.attr = Attributes::default(); self.modes = [false; 9];
        self.modes[WRAP] = true; self.modes[VISIBLE] = true;
        self.g0 = false; self.g1 = false; self.gl = false;
        self.tabs = (9..=self.w).step_by(8).collect(); self.saved = [None, None];
        self.back.clear(); self.title = None; self.last = None;
        self.parser = Parser::Ground; self.marker.clear(); self.parameters.clear(); self.intermediate.clear(); self.osc.clear();
    }
    fn row_text(cells: &[Cell]) -> String {
        cells.iter().map(|c| c.ch).collect::<String>().trim_end_matches(' ').to_string()
    }
    fn erase(&mut self, row: usize, first: usize, last: usize) {
        for c in first..=last { self.screens[self.screen][row-1][c-1] = Cell::default(); }
    }
    fn scroll(&mut self, up: bool, count: usize) {
        for _ in 0..count {
            if up {
                if self.screen == 0 && self.top == 1 {
                    self.back.push(Self::row_text(&self.screens[0][self.top-1]));
                    if self.back.len() > 100 { self.back.remove(0); }
                }
                for r in self.top..self.bottom {
                    self.screens[self.screen][r-1] = self.screens[self.screen][r].clone();
                }
                self.screens[self.screen][self.bottom-1] = self.blank_row();
            } else {
                for r in (self.top+1..=self.bottom).rev() {
                    self.screens[self.screen][r-1] = self.screens[self.screen][r-2].clone();
                }
                self.screens[self.screen][self.top-1] = self.blank_row();
            }
        }
    }
    fn line_feed(&mut self) {
        if self.row == self.bottom { self.scroll(true, 1); }
        else if self.row < self.h { self.row += 1; }
    }
    fn tab(&mut self, reverse: bool) {
        self.col = if reverse { self.tabs.range(..self.col).next_back().copied().unwrap_or(1) }
            else { self.tabs.range(self.col+1..).next().copied().unwrap_or(self.w) };
    }
    fn address(&self, n: usize) -> usize {
        if self.modes[ORIGIN] { (self.top+n-1).min(self.bottom) } else { n.min(self.h) }
    }
    fn home(&mut self) { self.row = self.address(1); self.col = 1; }
    fn save(&mut self) {
        self.saved[self.screen] = Some(Saved { row: self.row, col: self.col, attr: self.attr.clone(),
            origin: self.modes[ORIGIN], g0: self.g0, g1: self.g1, gl: self.gl });
    }
    fn restore(&mut self) {
        if let Some(s) = self.saved[self.screen].clone() {
            self.row = s.row; self.col = s.col; self.attr = s.attr;
            self.modes[ORIGIN] = s.origin; self.g0 = s.g0; self.g1 = s.g1; self.gl = s.gl;
        } else {
            self.row = 1; self.col = 1; self.attr = Attributes::default();
            self.modes[ORIGIN] = false; self.g0 = false; self.g1 = false; self.gl = false;
        }
        self.pending = false;
    }
    fn write(&mut self, ch: char) {
        self.printed += 1; self.last = Some(ch);
        if self.pending { self.pending = false; self.col = 1; self.line_feed(); }
        let row = &mut self.screens[self.screen][self.row-1];
        if self.modes[IRM] { for c in (self.col..self.w).rev() { row[c] = row[c-1].clone(); } }
        row[self.col-1] = Cell { ch, attr: self.attr.clone() };
        if self.col < self.w { self.col += 1; } else if self.modes[WRAP] { self.pending = true; }
    }
    fn print(&mut self, mut ch: char) {
        if if self.gl { self.g1 } else { self.g0 } {
            ch = match ch { '`' => '*', 'a' => '#', 'q' => '-', 'x' => '|', '~' => 'o',
                'j' | 'k' | 'l' | 'm' | 'n' | 't' | 'u' | 'v' | 'w' => '+', _ => ch };
        }
        self.write(ch);
    }
    fn control(&mut self, b: u8) {
        if (8..=13).contains(&b) { self.pending = false; }
        match b {
            7 => self.bells += 1,
            8 => self.col = self.col.saturating_sub(1).max(1),
            9 => self.tab(false),
            10..=12 => { self.line_feed(); if self.modes[LNM] { self.col = 1; } }
            13 => self.col = 1, 14 => self.gl = true, 15 => self.gl = false, _ => (),
        }
    }
    fn palette(n: usize) -> String {
        let names = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"];
        if n < 8 { names[n].into() } else if n < 16 { format!("bright-{}", names[n-8]) } else { n.to_string() }
    }
    fn sgr(&mut self, p: &[usize]) -> bool {
        let mut a = self.attr.clone();
        let mut i = 0;
        while i < p.len() {
            let v = p[i];
            match v {
                0 => a = Attributes::default(),
                1..=5 => a.flags |= 1 << (v-1),
                7..=9 => a.flags |= 1 << (v-2),
                22 => a.flags &= !3,
                23..=25 => a.flags &= !(1 << (v-21)),
                27..=29 => a.flags &= !(1 << (v-22)),
                30..=37 => a.fg = Self::palette(v-30),
                90..=97 => a.fg = Self::palette(v-82),
                40..=47 => a.bg = Self::palette(v-40),
                100..=107 => a.bg = Self::palette(v-92),
                39 => a.fg = "default".into(), 49 => a.bg = "default".into(),
                38 | 48 => {
                    let color;
                    if i+2 < p.len() && p[i+1] == 5 && p[i+2] <= 255 {
                        color = Self::palette(p[i+2]); i += 2;
                    } else if i+4 < p.len() && p[i+1] == 2 && p[i+2..=i+4].iter().all(|&v| v <= 255) {
                        color = format!("#{:02x}{:02x}{:02x}", p[i+2], p[i+3], p[i+4]); i += 4;
                    } else { return false; }
                    if v == 38 { a.fg = color; } else { a.bg = color; }
                }
                _ => return false,
            }
            i += 1;
        }
        self.attr = a; true
    }
    fn mode_index(p: usize, dec: bool) -> Option<usize> {
        if dec { match p { 1 => Some(CKM), 5 => Some(SCNM), 6 => Some(ORIGIN), 7 => Some(WRAP),
            25 => Some(VISIBLE), 2004 => Some(BRACKETED), _ => None } }
        else { match p { 4 => Some(IRM), 20 => Some(LNM), _ => None } }
    }
    fn set_modes(&mut self, p: &[usize], dec: bool, on: bool) -> bool {
        if p.iter().any(|&v| Self::mode_index(v, dec).is_none() && !(dec && [47, 1047, 1048, 1049].contains(&v))) { return false; }
        for &v in p {
            if let Some(index) = Self::mode_index(v, dec) {
                self.modes[index] = on;
                if index == ORIGIN { self.pending = false; self.home(); }
                if index == WRAP && !on { self.pending = false; }
            } else if v == 1048 {
                if on { self.save(); } else { self.restore(); }
            } else {
                self.pending = false;
                if on && self.screen == 0 {
                    if v == 1049 { self.save(); }
                    self.screen = 1;
                    if v == 1049 { self.screens[1] = self.blank_screen(); }
                } else if !on && self.screen == 1 {
                    if v == 1047 { self.screens[1] = self.blank_screen(); }
                    self.screen = 0;
                    if v == 1049 { self.restore(); }
                }
            }
        }
        true
    }
    fn execute_osc(&mut self) {
        if self.osc.starts_with("0;") || self.osc.starts_with("2;") {
            self.title = Some(self.osc[2..].into()); self.sequences += 1;
        } else { self.ignored[0] += 1; }
    }
    fn escape(&mut self, final_byte: char) {
        let key = format!("{}{}", self.intermediate, final_byte);
        match key.as_str() {
            "7" => self.save(), "8" => self.restore(),
            "D" | "E" => { self.pending = false; if final_byte == 'E' { self.col = 1; } self.line_feed(); }
            "M" => { self.pending = false; if self.row == self.top { self.scroll(false, 1); } else { self.row = self.row.saturating_sub(1).max(1); } }
            "H" => { self.tabs.insert(self.col); }
            "c" => self.reset(), "=" => self.modes[KEYPAD] = true, ">" => self.modes[KEYPAD] = false,
            "\\" => (), "(0" => self.g0 = true, "(B" => self.g0 = false, ")0" => self.g1 = true, ")B" => self.g1 = false,
            "#8" => {
                self.screens[self.screen] = vec![vec![Cell { ch: 'E', attr: Attributes::default() }; self.w]; self.h];
                self.top = 1; self.bottom = self.h; self.modes[ORIGIN] = false;
                self.row = 1; self.col = 1; self.pending = false;
            }
            _ => { self.ignored[0] += 1; return; }
        }
        self.sequences += 1;
    }
    fn reply(&mut self, s: String) { self.replies += 1; println!("REPLY {s}"); }
    fn csi(&mut self, final_byte: char) {
        let fields: Vec<&str> = if self.parameters.is_empty() { vec![] } else { self.parameters.split(';').collect() };
        if fields.len() >= 17 { self.ignored[3] += 1; return; }
        let mut p: Vec<usize> = fields.iter().map(|s| s.bytes().fold(0usize, |v, b| (v*10+(b-b'0') as usize).min(9999))).collect();
        if p.is_empty() { p.push(0); }
        let first = p[0]; let second = p.get(1).copied().unwrap_or(0); let n = first.max(1);
        let key = format!("{}{}{}", self.marker, self.intermediate, final_byte);
        let k = key.as_str();
        if (k == "J" && first > 3) || (k == "K" && first > 2) || (k == "g" && first != 0 && first != 3)
            || (k == " q" && first > 6) || (k == "n" && first != 5 && first != 6) || (k == "?n" && first != 6)
            || ((k == "c" || k == ">c") && first != 0) || (k == "t" && first != 18) {
            self.ignored[0] += 1; return;
        }
        if k.len() == 1 && "ABCDEFGHIJKLMPSTXZ`adef@".contains(final_byte) { self.pending = false; }
        let mut supported = true;
        match k {
            "A" | "F" => { self.row = self.row.saturating_sub(n).max(if self.row >= self.top { self.top } else { 1 }); if k == "F" { self.col = 1; } }
            "B" | "e" | "E" => { self.row = (self.row+n).min(if self.row <= self.bottom { self.bottom } else { self.h }); if k == "E" { self.col = 1; } }
            "C" | "a" => self.col = (self.col+n).min(self.w),
            "D" => self.col = self.col.saturating_sub(n).max(1),
            "G" | "`" => self.col = n.min(self.w),
            "H" | "f" => { self.row = self.address(n); self.col = second.max(1).min(self.w); }
            "d" => self.row = self.address(n),
            "I" | "Z" => for _ in 0..n { self.tab(k == "Z"); },
            "J" => {
                if first == 3 { self.back.clear(); }
                else { for r in 1..=self.h {
                    if first == 2 || (first == 0 && r > self.row) || (first == 1 && r < self.row) { self.erase(r, 1, self.w); }
                    else if r == self.row { self.erase(r, if first == 0 { self.col } else { 1 }, if first == 1 { self.col } else { self.w }); }
                } }
            }
            "K" => self.erase(self.row, if first == 0 { self.col } else { 1 }, if first == 1 { self.col } else { self.w }),
            "X" => self.erase(self.row, self.col, (self.col+n-1).min(self.w)),
            "@" | "P" => {
                let amount = n.min(self.w-self.col+1);
                let cells = &mut self.screens[self.screen][self.row-1];
                if k == "@" {
                    for c in (self.col-1+amount..self.w).rev() { cells[c] = cells[c-amount].clone(); }
                    self.erase(self.row, self.col, self.col+amount-1);
                } else {
                    for c in self.col-1..self.w-amount { cells[c] = cells[c+amount].clone(); }
                    self.erase(self.row, self.w-amount+1, self.w);
                }
            }
            "L" | "M" => {
                if self.row >= self.top && self.row <= self.bottom {
                    let amount = n.min(self.bottom-self.row+1);
                    if k == "L" {
                        for r in (self.row+amount..=self.bottom).rev() { self.screens[self.screen][r-1] = self.screens[self.screen][r-amount-1].clone(); }
                        for r in self.row..self.row+amount { self.screens[self.screen][r-1] = self.blank_row(); }
                    } else {
                        for r in self.row..=self.bottom-amount { self.screens[self.screen][r-1] = self.screens[self.screen][r+amount-1].clone(); }
                        for r in self.bottom-amount+1..=self.bottom { self.screens[self.screen][r-1] = self.blank_row(); }
                    }
                    self.col = 1;
                }
            }
            "S" | "T" => self.scroll(k == "S", n.min(self.bottom-self.top+1)),
            "b" => if let Some(ch) = self.last { for _ in 0..n { self.write(ch); } },
            "g" => { if first == 0 { self.tabs.remove(&self.col); } else { self.tabs.clear(); } }
            "m" => supported = self.sgr(&p),
            "h" | "l" | "?h" | "?l" => supported = self.set_modes(&p, k.starts_with('?'), final_byte == 'h'),
            " q" => self.shape = n,
            "r" => {
                let top = if first == 0 { 1 } else { first };
                let bottom = if second == 0 { self.h } else { second.min(self.h) };
                if top >= bottom { self.ignored[3] += 1; return; }
                self.pending = false; self.top = top; self.bottom = bottom; self.home();
            }
            "s" => self.save(), "u" => self.restore(),
            "!p" => {
                self.pending = false;
                for i in [IRM, CKM, ORIGIN, KEYPAD] { self.modes[i] = false; }
                self.modes[WRAP] = true; self.modes[VISIBLE] = true; self.top = 1; self.bottom = self.h;
                self.attr = Attributes::default(); self.g0 = false; self.g1 = false; self.gl = false; self.saved[self.screen] = None;
            }
            "n" | "?n" => {
                let row = if self.modes[ORIGIN] { self.row.saturating_sub(self.top).saturating_add(1).max(1) } else { self.row };
                let answer = if k == "?n" { format!("^[[?{row};{};1R", self.col) }
                    else if first == 5 { "^[[0n".into() } else { format!("^[[{row};{}R", self.col) };
                self.reply(answer);
            }
            "c" => self.reply("^[[?1;2c".into()), ">c" => self.reply("^[[>0;95;0c".into()),
            "t" => self.reply(format!("^[[8;{};{}t", self.h, self.w)),
            "$p" | "?$p" => {
                let dec = k.starts_with('?');
                let status = if let Some(i) = Self::mode_index(first, dec) { if self.modes[i] { 1 } else { 2 } }
                    else if dec && [47, 1047, 1049].contains(&first) { if self.screen == 1 { 1 } else { 2 } } else { 0 };
                self.reply(format!("^[[{}{first};{status}$y", if dec { "?" } else { "" }));
            }
            _ => supported = false,
        }
        if supported { self.sequences += 1; } else { self.ignored[0] += 1; }
    }
    fn feed(&mut self, b: u8) {
        self.bytes += 1;
        if b == 27 {
            if self.parser == Parser::Osc { self.execute_osc(); } else if self.parser != Parser::Ground { self.ignored[2] += 1; }
            self.marker.clear(); self.parameters.clear(); self.intermediate.clear(); self.osc.clear(); self.parser = Parser::Escape; return;
        }
        if b == 24 || b == 26 {
            if self.parser != Parser::Ground { self.ignored[2] += 1; }
            self.parser = Parser::Ground; return;
        }
        if b < 32 {
            if self.parser == Parser::Osc { if b == 7 { self.execute_osc(); self.parser = Parser::Ground; } }
            else { self.control(b); }
            return;
        }
        let c = b as char;
        if self.parser == Parser::CsiEntry {
            self.parser = Parser::CsiParam;
            if (60..=63).contains(&b) { self.marker.push(c); return; }
        }
        match self.parser {
            Parser::Ground => self.print(c), Parser::Osc => self.osc.push(c),
            Parser::Escape => {
                if b <= 47 { self.intermediate.push(c); self.parser = Parser::EscapeIntermediate; }
                else if c == '[' { self.parser = Parser::CsiEntry; }
                else if c == ']' { self.parser = Parser::Osc; }
                else { self.escape(c); self.parser = Parser::Ground; }
            }
            Parser::EscapeIntermediate => {
                if b <= 47 { self.intermediate.push(c); } else { self.escape(c); self.parser = Parser::Ground; }
            }
            Parser::CsiParam => {
                if b.is_ascii_digit() || c == ';' { self.parameters.push(c); }
                else if b <= 47 { self.intermediate.push(c); self.parser = Parser::CsiIntermediate; }
                else if b < 64 { self.parser = Parser::CsiIgnore; }
                else { self.csi(c); self.parser = Parser::Ground; }
            }
            Parser::CsiIntermediate => {
                if b <= 47 { self.intermediate.push(c); }
                else if b < 64 { self.parser = Parser::CsiIgnore; }
                else { self.csi(c); self.parser = Parser::Ground; }
            }
            Parser::CsiIgnore => if b >= 64 { self.ignored[1] += 1; self.parser = Parser::Ground; },
            Parser::CsiEntry => unreachable!(),
        }
    }
    fn dump(&self, label: &str) {
        println!("{label} {} cursor {},{} scrollback {}{}", if self.screen == 0 { "main" } else { "alt" }, self.row, self.col, self.back.len(), if self.pending { " pending" } else { "" });
        for row in &self.screens[self.screen] { println!("|{}", Self::row_text(row)); }
    }
    fn key(&self, name: &str) -> String {
        let navigation = ["UP", "DOWN", "RIGHT", "LEFT", "HOME", "END"];
        if let Some(i) = navigation.iter().position(|&s| s == name) {
            return format!("{}{}", if self.modes[CKM] { "^[O" } else { "^[[" }, b"ABCDHF"[i] as char);
        }
        if let Some(suffix) = name.strip_prefix('F') {
            let f: usize = suffix.parse().unwrap();
            return if f <= 4 { format!("^[O{}", (b'P'+f as u8-1) as char) }
                else { format!("^[[{}~", [15,17,18,19,20,21,23,24][f-5]) };
        }
        if name.starts_with("KP") && name.len() == 3 {
            let digit = name.as_bytes()[2];
            return if self.modes[KEYPAD] { format!("^[O{}", (b'p'+digit-b'0') as char) } else { (digit as char).to_string() };
        }
        match name {
            "INSERT" => "^[[2~", "DELETE" => "^[[3~", "PAGEUP" => "^[[5~", "PAGEDOWN" => "^[[6~",
            "TAB" => "^I", "BACKSPACE" => "^?", "ESCAPE" => "^[", "KPENTER" if self.modes[KEYPAD] => "^[OM",
            _ => if self.modes[LNM] { "^M^J" } else { "^M" },
        }.into()
    }
    fn directive(&mut self, line: &str) {
        if line == "%%DUMP" { self.dumps += 1; self.dump(&format!("DUMP {}", self.dumps)); }
        else if let Some(name) = line.strip_prefix("%%KEY ") { println!("KEY {name} {}", self.key(name)); }
        else if let Some(text) = line.strip_prefix("%%PASTE ") {
            let s = text.replace('^', "^^");
            println!("PASTE {}", if self.modes[BRACKETED] { format!("^[[200~{s}^[[201~") } else { s });
        }
    }
    fn attr_text(a: &Attributes) -> String {
        let mut parts: Vec<String> = ["bold", "dim", "italic", "underline", "blink", "reverse", "hidden", "strike"]
            .iter().enumerate().filter(|(i, _)| a.flags & (1u8 << *i) != 0).map(|(_, &s)| s.into()).collect();
        if a.fg != "default" { parts.push(format!("fg={}", a.fg)); }
        if a.bg != "default" { parts.push(format!("bg={}", a.bg)); }
        parts.join(" ")
    }
    fn finish(&mut self) {
        if self.parser != Parser::Ground { self.ignored[2] += 1; }
        self.dump("FINAL");
        match &self.title { Some(s) => println!("TITLE \"{s}\""), None => println!("TITLE none") }
        let mut changed = vec![];
        let names = ["IRM", "LNM", "DECCKM", "DECSCNM", "DECOM", "DECAWM", "DECTCEM", "DECKPAM", "BRACKETED"];
        for (i, name) in names.iter().enumerate() {
            if self.modes[i] != (i == WRAP || i == VISIBLE) { changed.push(format!("{name}={}", if self.modes[i] { "on" } else { "off" })); }
        }
        if self.g0 { changed.push("G0=graphics".into()); }
        if self.g1 { changed.push("G1=graphics".into()); }
        if self.gl { changed.push("GL=G1".into()); }
        if self.shape != 1 { changed.push(format!("CURSOR={}", self.shape)); }
        println!("MODES {}", if changed.is_empty() { "default".into() } else { changed.join(" ") });
        println!("REGION {}-{}", self.top, self.bottom);
        println!("TABS {}", if self.tabs.is_empty() { "none".into() } else { self.tabs.iter().map(usize::to_string).collect::<Vec<_>>().join(",") });
        println!("SCROLLBACK {}", self.back.len());
        for s in self.back.iter().skip(self.back.len().saturating_sub(5)) { println!("|{s}"); }
        let mut runs = vec![];
        for r in 0..self.h {
            let mut c = 0;
            while c < self.w {
                let attr = &self.screens[self.screen][r][c].attr;
                let mut end = c+1;
                while end < self.w && self.screens[self.screen][r][end].attr == *attr { end += 1; }
                if *attr != Attributes::default() { runs.push(format!("row {} col {}-{end} {}", r+1, c+1, Self::attr_text(attr))); }
                c = end;
            }
        }
        println!("ATTRS {}", runs.len()); for s in runs { println!("{s}"); }
        println!("BELL {}\nREPLIES {}\nSTATS bytes={} printed={} sequences={}", self.bells, self.replies, self.bytes, self.printed, self.sequences);
        println!("IGNORED {} unsupported={} malformed={} canceled={} invalid={}", self.ignored.iter().sum::<usize>(), self.ignored[0], self.ignored[1], self.ignored[2], self.ignored[3]);
    }
}
fn main() {
    let stdin = io::stdin(); let mut lines = stdin.lock().lines();
    let first = lines.next().unwrap().unwrap();
    let size: Vec<usize> = first.split_whitespace().map(|s| s.parse().unwrap()).collect();
    let mut terminal = Terminal::new(size[0], size[1]);
    for line in lines {
        let line = line.unwrap();
        if line == "%%END" { terminal.finish(); break; }
        if line.starts_with("%%") { terminal.directive(&line); continue; }
        let bytes = line.as_bytes(); let mut i = 0;
        while i < bytes.len() {
            let mut b = bytes[i];
            if b == b'^' { i += 1; b = bytes[i]; if b != b'^' { b -= 64; } }
            terminal.feed(b); i += 1;
        }
    }
}
