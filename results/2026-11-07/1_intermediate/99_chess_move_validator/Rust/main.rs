use std::io::{self, Read};
#[derive(Clone)]
struct Position {
    b: [u8; 64],
    white: bool,
    rights: u8,
    ep: Option<usize>,
    half: u32,
    full: u32,
}
#[derive(Clone, Copy, PartialEq, Eq)]
struct Move {
    s: usize,
    t: usize,
    promotion: u8,
}
fn square(s: &str) -> Option<usize> {
    let b = s.as_bytes();
    if b.len() == 2 && (b'a'..=b'h').contains(&b[0]) && (b'1'..=b'8').contains(&b[1]) {
        Some((b[1] - b'1') as usize * 8 + (b[0] - b'a') as usize)
    } else {
        None
    }
}
fn name(s: usize) -> String {
    format!(
        "{}{}",
        (b'a' + (s % 8) as u8) as char,
        (b'1' + (s / 8) as u8) as char
    )
}
fn number(s: &str, lo: u32, hi: u32) -> Option<u32> {
    if s.is_empty() || !s.bytes().all(|c| c.is_ascii_digit()) || (s.len() > 1 && s.starts_with('0'))
    {
        return None;
    }
    s.parse::<u32>().ok().filter(|&n| n >= lo && n <= hi)
}
fn color(p: u8, w: bool) -> bool {
    p != 0 && p.is_ascii_uppercase() == w
}
impl Position {
    fn attack(&self, s: usize, t: usize) -> bool {
        if s == t {
            return false;
        }
        let p = self.b[s];
        if p == 0 {
            return false;
        }
        let dx = t as i32 % 8 - s as i32 % 8;
        let dy = t as i32 / 8 - s as i32 / 8;
        let a = dx.abs();
        let b = dy.abs();
        let k = p.to_ascii_uppercase();
        match k {
            b'P' => return b == 1 && a == 1 && dy == if p.is_ascii_uppercase() { 1 } else { -1 },
            b'N' => return a * b == 2,
            b'K' => return a <= 1 && b <= 1,
            b'R' if dx != 0 && dy != 0 => return false,
            b'B' if a != b => return false,
            b'Q' if dx != 0 && dy != 0 && a != b => return false,
            _ => {}
        }
        let step = dy.signum() * 8 + dx.signum();
        let mut i = s as i32 + step;
        while i != t as i32 {
            if self.b[i as usize] != 0 {
                return false;
            }
            i += step
        }
        true
    }
    fn attacked(&self, t: usize, w: bool) -> bool {
        (0..64).any(|s| color(self.b[s], w) && self.attack(s, t))
    }
    fn check(&self, w: bool) -> bool {
        self.b
            .iter()
            .position(|&p| p == if w { b'K' } else { b'k' })
            .map(|s| self.attacked(s, !w))
            .unwrap_or(true)
    }
    fn castle(&self, m: Move) -> bool {
        self.b[m.s].to_ascii_uppercase() == b'K' && m.s.abs_diff(m.t) == 2
    }
    fn ep_move(&self, m: Move) -> bool {
        self.b[m.s].to_ascii_uppercase() == b'P' && m.s % 8 != m.t % 8 && self.b[m.t] == 0
    }
    fn capture(&self, m: Move) -> bool {
        self.b[m.t] != 0 || self.ep_move(m)
    }
    fn after(&self, m: Move) -> Self {
        let mut q = self.clone();
        let p = self.b[m.s];
        if self.ep_move(m) {
            q.b[(m.t as i32 + if self.white { -8 } else { 8 }) as usize] = 0
        }
        if self.castle(m) {
            let r = m.s / 8 * 8;
            let (s, t) = if m.t > m.s {
                (r + 7, r + 5)
            } else {
                (r, r + 3)
            };
            q.b[t] = q.b[s];
            q.b[s] = 0
        }
        q.b[m.t] = if m.promotion == 0 {
            p
        } else if self.white {
            m.promotion
        } else {
            m.promotion.to_ascii_lowercase()
        };
        q.b[m.s] = 0;
        q.half = if p.to_ascii_uppercase() == b'P' || self.capture(m) {
            0
        } else {
            self.half + 1
        };
        if p.to_ascii_uppercase() == b'K' {
            q.rights &= if self.white { 12 } else { 3 }
        }
        for (s, bit) in [(0, 2), (7, 1), (56, 8), (63, 4)] {
            if m.s == s || m.t == s {
                q.rights &= !bit
            }
        }
        q.ep = if p.to_ascii_uppercase() == b'P' && m.s.abs_diff(m.t) == 16 {
            Some((m.s + m.t) / 2)
        } else {
            None
        };
        q.full += if self.white { 0 } else { 1 };
        q.white = !self.white;
        q
    }
    fn pseudo(&self) -> Vec<Move> {
        let mut v = Vec::new();
        for s in 0..64 {
            let p = self.b[s];
            if !color(p, self.white) {
                continue;
            }
            for t in 0..64 {
                if color(self.b[t], self.white) {
                    continue;
                }
                let valid = if p.to_ascii_uppercase() == b'P' {
                    let d = if self.white { 8i32 } else { -8 };
                    let one = s as i32 + d;
                    let two = one + d;
                    (t as i32 == one && self.b[t] == 0)
                        || (s / 8 == if self.white { 1 } else { 6 }
                            && t as i32 == two
                            && self.b[one as usize] == 0
                            && self.b[t] == 0)
                        || (self.attack(s, t) && (self.b[t] != 0 || self.ep == Some(t)))
                } else {
                    self.attack(s, t)
                };
                if valid {
                    if p.to_ascii_uppercase() == b'P' && (t / 8 == 0 || t / 8 == 7) {
                        for promotion in *b"QRBN" {
                            v.push(Move { s, t, promotion })
                        }
                    } else {
                        v.push(Move { s, t, promotion: 0 })
                    }
                }
            }
        }
        v
    }
    fn castle_move(&self, king: bool) -> Move {
        let s = if self.white { 4 } else { 60 };
        Move {
            s,
            t: if king { s + 2 } else { s - 2 },
            promotion: 0,
        }
    }
    fn castle_reason(&self, k: bool) -> Option<&'static str> {
        let bit = if self.white {
            if k { 1 } else { 2 }
        } else if k {
            4
        } else {
            8
        };
        if self.rights & bit == 0 {
            return Some("no castling right");
        }
        let r = if self.white { 0 } else { 56 };
        if (if k { vec![5, 6] } else { vec![1, 2, 3] })
            .into_iter()
            .any(|f| self.b[r + f] != 0)
        {
            return Some("path blocked");
        }
        if self.check(self.white) {
            return Some("in check");
        }
        if self.attacked(r + if k { 5 } else { 3 }, !self.white) {
            return Some("through check");
        }
        if self.after(self.castle_move(k)).check(self.white) {
            return Some("into check");
        }
        None
    }
    fn legal(&self) -> Vec<Move> {
        let mut v: Vec<_> = self
            .pseudo()
            .into_iter()
            .filter(|&m| !self.after(m).check(self.white))
            .collect();
        for k in [true, false] {
            if self.castle_reason(k).is_none() {
                v.push(self.castle_move(k))
            }
        }
        v
    }
    fn disamb(&self, m: Move, legal: &[Move]) -> String {
        let others: Vec<_> = legal
            .iter()
            .filter(|n| n.s != m.s && n.t == m.t && self.b[n.s] == self.b[m.s] && !self.castle(**n))
            .collect();
        if others.is_empty() {
            String::new()
        } else if others.iter().all(|n| n.s % 8 != m.s % 8) {
            ((b'a' + (m.s % 8) as u8) as char).to_string()
        } else if others.iter().all(|n| n.s / 8 != m.s / 8) {
            ((b'1' + (m.s / 8) as u8) as char).to_string()
        } else {
            name(m.s)
        }
    }
    fn mark(&self, m: Move) -> &'static str {
        let q = self.after(m);
        if !q.check(q.white) {
            ""
        } else if q.legal().is_empty() {
            "#"
        } else {
            "+"
        }
    }
    fn san(&self, m: Move, legal: &[Move]) -> String {
        let mut s = if self.castle(m) {
            if m.t > m.s {
                "O-O".to_string()
            } else {
                "O-O-O".to_string()
            }
        } else if self.b[m.s].to_ascii_uppercase() == b'P' {
            format!(
                "{}{}{}",
                if self.capture(m) {
                    format!("{}x", (b'a' + (m.s % 8) as u8) as char)
                } else {
                    String::new()
                },
                name(m.t),
                if m.promotion != 0 {
                    format!("={}", m.promotion as char)
                } else {
                    String::new()
                }
            )
        } else {
            format!(
                "{}{}{}{}",
                self.b[m.s].to_ascii_uppercase() as char,
                self.disamb(m, legal),
                if self.capture(m) { "x" } else { "" },
                name(m.t)
            )
        };
        s.push_str(self.mark(m));
        s
    }
    fn read_uci(&self, s: &str) -> Result<Move, &'static str> {
        let b = s.as_bytes();
        if !(b.len() == 4 || b.len() == 5) {
            return Err("syntax");
        }
        let from = square(&s[..2]).ok_or("syntax")?;
        let to = square(&s[2..4]).ok_or("syntax")?;
        let promotion = if b.len() == 5 {
            if !b"qrbn".contains(&b[4]) {
                return Err("syntax");
            }
            b[4].to_ascii_uppercase()
        } else {
            0
        };
        let legal = self.legal();
        if legal.is_empty() {
            return Err("game over");
        }
        if !color(self.b[from], self.white) {
            return Err("no piece");
        }
        let found: Vec<_> = legal
            .into_iter()
            .filter(|m| m.s == from && m.t == to)
            .collect();
        if found.is_empty() {
            return Err(if self.pseudo().iter().any(|m| m.s == from && m.t == to) {
                "leaves king in check"
            } else {
                "no such move"
            });
        }
        if found[0].promotion != 0 && promotion == 0 {
            return Err("missing promotion");
        }
        if found[0].promotion == 0 && promotion != 0 {
            return Err("invalid promotion");
        }
        Ok(Move {
            s: from,
            t: to,
            promotion,
        })
    }
    fn read_san(&self, w: &str) -> Result<Move, &'static str> {
        let mut u = w;
        let mark = if u.ends_with('+') || u.ends_with('#') {
            let m = &u[u.len() - 1..];
            u = &u[..u.len() - 1];
            m
        } else {
            ""
        };
        let castle = if u == "O-O" {
            Some(true)
        } else if u == "O-O-O" {
            Some(false)
        } else {
            None
        };
        let mut promotion = 0;
        let mut to = 0;
        let mut capture = false;
        let mut kind = b'P';
        let mut file = None;
        let mut rank = None;
        let mut dis = String::new();
        if castle.is_none() {
            if u.len() >= 2 && u.as_bytes()[u.len() - 2] == b'=' {
                promotion = u.as_bytes()[u.len() - 1];
                if !b"QRBN".contains(&promotion) {
                    return Err("syntax");
                }
                u = &u[..u.len() - 2]
            }
            if u.len() < 2 {
                return Err("syntax");
            }
            to = square(&u[u.len() - 2..]).ok_or("syntax")?;
            u = &u[..u.len() - 2];
            if u.ends_with('x') {
                capture = true;
                u = &u[..u.len() - 1]
            }
            if u.as_bytes().first().is_some_and(|p| b"KQRBN".contains(p)) {
                kind = u.as_bytes()[0];
                u = &u[1..];
                if promotion != 0 {
                    return Err("syntax");
                }
                dis = u.to_string();
                if u.as_bytes()
                    .first()
                    .is_some_and(|c| (b'a'..=b'h').contains(c))
                {
                    file = Some((u.as_bytes()[0] - b'a') as usize);
                    u = &u[1..]
                }
                if u.as_bytes()
                    .first()
                    .is_some_and(|c| (b'1'..=b'8').contains(c))
                {
                    rank = Some((u.as_bytes()[0] - b'1') as usize);
                    u = &u[1..]
                }
                if !u.is_empty() {
                    return Err("syntax");
                }
            } else if capture {
                if u.len() != 1 || !(b'a'..=b'h').contains(&u.as_bytes()[0]) {
                    return Err("syntax");
                }
                file = Some((u.as_bytes()[0] - b'a') as usize)
            } else if !u.is_empty() {
                return Err("syntax");
            }
        }
        let legal = self.legal();
        if legal.is_empty() {
            return Err("game over");
        }
        let m = if let Some(k) = castle {
            if let Some(r) = self.castle_reason(k) {
                return Err(r);
            }
            self.castle_move(k)
        } else {
            let matches = |m: &&Move| {
                self.b[m.s].to_ascii_uppercase() == kind
                    && m.t == to
                    && !self.castle(**m)
                    && file.is_none_or(|f| m.s % 8 == f)
                    && rank.is_none_or(|r| m.s / 8 == r)
                    && (kind != b'P' || (m.s % 8 != m.t % 8) == capture)
            };
            let found: Vec<_> = legal.iter().filter(matches).copied().collect();
            if found.is_empty() {
                return Err(if self.pseudo().iter().filter(matches).next().is_some() {
                    "leaves king in check"
                } else {
                    "no such move"
                });
            }
            if found.iter().any(|m| m.s != found[0].s) {
                return Err("ambiguous");
            }
            let mut m = found[0];
            if self.capture(m) != capture {
                return Err("capture mark");
            }
            if m.promotion != 0 && promotion == 0 {
                return Err("missing promotion");
            }
            if m.promotion == 0 && promotion != 0 {
                return Err("invalid promotion");
            }
            if kind != b'P' && self.disamb(m, &legal) != dis {
                return Err("disambiguation");
            }
            m.promotion = promotion;
            m
        };
        if self.mark(m) != mark {
            return Err("check mark");
        }
        Ok(m)
    }
    fn fen(&self) -> String {
        let mut ranks = Vec::new();
        for r in (0..8).rev() {
            let mut s = String::new();
            let mut n = 0;
            for f in 0..8 {
                let p = self.b[r * 8 + f];
                if p == 0 {
                    n += 1
                } else {
                    if n > 0 {
                        s.push((b'0' + n) as char);
                        n = 0
                    }
                    s.push(p as char)
                }
            }
            if n > 0 {
                s.push((b'0' + n) as char)
            }
            ranks.push(s)
        }
        let rights: String = b"KQkq"
            .iter()
            .enumerate()
            .filter(|(i, _)| self.rights & (1 << i) != 0)
            .map(|(_, c)| *c as char)
            .collect();
        format!(
            "{} {} {} {} {} {}",
            ranks.join("/"),
            if self.white { "w" } else { "b" },
            if rights.is_empty() { "-" } else { &rights },
            self.ep.map(name).unwrap_or("-".into()),
            self.half,
            self.full
        )
    }
    fn key(&self) -> String {
        let mut p = self.clone();
        if !self.legal().iter().any(|&m| self.ep_move(m)) {
            p.ep = None
        }
        p.fen()
            .split_whitespace()
            .take(4)
            .collect::<Vec<_>>()
            .join(" ")
    }
}
fn load(a: &[&str]) -> Result<Position, &'static str> {
    if a.len() != 6 {
        return Err("fields");
    }
    let mut p = Position {
        b: [0; 64],
        white: true,
        rights: 0,
        ep: None,
        half: 0,
        full: 1,
    };
    let ranks: Vec<_> = a[0].split('/').collect();
    if ranks.len() != 8 {
        return Err("placement");
    }
    for (r, s) in ranks.iter().enumerate() {
        let mut f = 0;
        let mut digit = false;
        for c in s.bytes() {
            if (b'1'..=b'8').contains(&c) {
                if digit {
                    return Err("placement");
                }
                f += (c - b'0') as usize;
                digit = true
            } else if b"KQRBNPkqrbnp".contains(&c) {
                if f >= 8 {
                    return Err("placement");
                }
                p.b[(7 - r) * 8 + f] = c;
                f += 1;
                digit = false
            } else {
                return Err("placement");
            }
            if f > 8 {
                return Err("placement");
            }
        }
        if f != 8 {
            return Err("placement");
        }
    }
    if p.b.iter().filter(|&&c| c == b'K').count() != 1
        || p.b.iter().filter(|&&c| c == b'k').count() != 1
    {
        return Err("kings");
    }
    if (0..8)
        .chain(56..64)
        .any(|s| p.b[s].to_ascii_uppercase() == b'P')
    {
        return Err("pawns");
    }
    p.white = match a[1] {
        "w" => true,
        "b" => false,
        _ => return Err("side"),
    };
    if a[2] != "-" {
        let mut last = None;
        for c in a[2].bytes() {
            let i = b"KQkq".iter().position(|&x| x == c).ok_or("castling")?;
            if last.is_some_and(|j| j >= i) {
                return Err("castling");
            }
            last = Some(i);
            let (k, r) = if i < 2 {
                (4, if i == 0 { 7 } else { 0 })
            } else {
                (60, if i == 2 { 63 } else { 56 })
            };
            if p.b[k] != if i < 2 { b'K' } else { b'k' }
                || p.b[r] != if i < 2 { b'R' } else { b'r' }
            {
                return Err("castling");
            }
            p.rights |= 1 << i
        }
    }
    if a[3] != "-" {
        let t = square(a[3]).ok_or("en passant")?;
        let (r, empty, pawn, c) = if p.white {
            (5, 8, -8, b'p')
        } else {
            (2, -8, 8, b'P')
        };
        if t / 8 != r
            || p.b[t] != 0
            || p.b[(t as i32 + empty) as usize] != 0
            || p.b[(t as i32 + pawn) as usize] != c
        {
            return Err("en passant");
        }
        p.ep = Some(t)
    }
    p.half = number(a[4], 0, 999).ok_or("clocks")?;
    p.full = number(a[5], 1, 999).ok_or("clocks")?;
    if p.ep.is_some() && p.half != 0 {
        return Err("clocks");
    }
    if p.check(!p.white) {
        return Err("check");
    }
    Ok(p)
}
fn perft(p: &Position, d: u32, stats: bool) -> [u64; 7] {
    if d == 0 {
        return [1, 0, 0, 0, 0, 0, 0];
    }
    let mut a = [0; 7];
    for m in p.legal() {
        let q = p.after(m);
        if d == 1 {
            a[0] += 1;
            if stats {
                a[1] += p.capture(m) as u64;
                a[2] += p.ep_move(m) as u64;
                a[3] += p.castle(m) as u64;
                a[4] += (m.promotion != 0) as u64;
                if q.check(q.white) {
                    a[5] += 1;
                    a[6] += q.legal().is_empty() as u64
                }
            }
        } else {
            let b = perft(&q, d - 1, stats);
            for i in 0..7 {
                a[i] += b[i]
            }
        }
    }
    a
}
struct Record {
    before: Position,
    san: String,
    uci: String,
    captured: char,
}
fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let initial = load(&[
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR",
        "w",
        "KQkq",
        "-",
        "0",
        "1",
    ])
    .unwrap();
    let mut p = initial.clone();
    let mut start = p.clone();
    let mut loaded = false;
    let mut history: Vec<Record> = Vec::new();
    for line in input.lines().skip(1) {
        let w: Vec<_> = line.split_whitespace().collect();
        if w.is_empty() {
            continue;
        }
        let c = w[0];
        let a = &w[1..];
        if ![
            "NEW", "LOAD", "FEN", "BOARD", "MOVE", "UCI", "LEGAL", "STATUS", "UNDO", "PERFT",
            "DIVIDE", "ATTACKS", "PINS", "HISTORY", "PGN",
        ]
        .contains(&c)
        {
            println!("ERROR unknown command");
            continue;
        }
        let valid = match c {
            "LOAD" => true,
            "MOVE" | "UCI" => !a.is_empty(),
            "LEGAL" => a.is_empty() || (a.len() == 1 && square(a[0]).is_some()),
            "UNDO" => a.len() == 1 && number(a[0], 1, 9999).is_some(),
            "PERFT" | "DIVIDE" => a.len() == 1 && number(a[0], 1, 3).is_some(),
            "ATTACKS" => a.len() == 1 && square(a[0]).is_some(),
            _ => a.is_empty(),
        };
        if !valid {
            println!("ERROR bad arguments");
            continue;
        }
        match c {
            "NEW" => {
                p = initial.clone();
                start = p.clone();
                loaded = false;
                history.clear();
                println!("OK")
            }
            "LOAD" => match load(a) {
                Ok(q) => {
                    p = q;
                    start = p.clone();
                    loaded = true;
                    history.clear();
                    println!("OK")
                }
                Err(r) => println!("ERROR bad fen ({})", r),
            },
            "FEN" => println!("{}", p.fen()),
            "BOARD" => {
                for r in (0..8).rev() {
                    println!(
                        "{} {}",
                        r + 1,
                        (0..8)
                            .map(|f| if p.b[r * 8 + f] == 0 {
                                ".".into()
                            } else {
                                (p.b[r * 8 + f] as char).to_string()
                            })
                            .collect::<Vec<String>>()
                            .join(" ")
                    )
                }
                println!("  a b c d e f g h")
            }
            "MOVE" | "UCI" => {
                let mut played = Vec::new();
                let mut error = None;
                for (i, w) in a.iter().enumerate() {
                    match if c == "MOVE" {
                        p.read_san(w)
                    } else {
                        p.read_uci(w)
                    } {
                        Err(r) => {
                            error = Some(format!("ILLEGAL move {}: {} ({})", i + 1, w, r));
                            break;
                        }
                        Ok(m) => {
                            let san = p.san(m, &p.legal());
                            let uci = format!(
                                "{}{}{}",
                                name(m.s),
                                name(m.t),
                                if m.promotion == 0 {
                                    String::new()
                                } else {
                                    (m.promotion.to_ascii_lowercase() as char).to_string()
                                }
                            );
                            let captured = if p.b[m.t] != 0 {
                                p.b[m.t].to_ascii_lowercase() as char
                            } else if p.ep_move(m) {
                                'p'
                            } else {
                                '-'
                            };
                            played.push(san.clone());
                            history.push(Record {
                                before: p.clone(),
                                san,
                                uci,
                                captured,
                            });
                            p = p.after(m)
                        }
                    }
                }
                if c == "UCI" && !played.is_empty() {
                    println!("san {}", played.join(" "))
                }
                if let Some(e) = error {
                    println!("{}", e)
                } else if c == "MOVE" {
                    println!("OK")
                }
            }
            "LEGAL" => {
                let legal = p.legal();
                let mut sans: Vec<_> = legal
                    .iter()
                    .filter(|m| a.is_empty() || Some(m.s) == square(a[0]))
                    .map(|&m| p.san(m, &legal))
                    .collect();
                sans.sort();
                println!(
                    "legal {}{}",
                    sans.len(),
                    if sans.is_empty() {
                        String::new()
                    } else {
                        format!(" {}", sans.join(" "))
                    }
                )
            }
            "UNDO" => {
                let n = a[0].parse::<usize>().unwrap();
                if n > history.len() {
                    println!("ERROR cannot undo")
                } else {
                    p = history[history.len() - n].before.clone();
                    history.truncate(history.len() - n);
                    println!("OK")
                }
            }
            "PERFT" => {
                let d = a[0].parse().unwrap();
                let v = perft(&p, d, true);
                println!(
                    "perft {} nodes {} captures {} ep {} castles {} promotions {} checks {} mates {}",
                    d, v[0], v[1], v[2], v[3], v[4], v[5], v[6]
                )
            }
            "DIVIDE" => {
                let d = a[0].parse::<u32>().unwrap();
                let legal = p.legal();
                let mut rows: Vec<_> = legal
                    .iter()
                    .map(|&m| (p.san(m, &legal), perft(&p.after(m), d - 1, false)[0]))
                    .collect();
                rows.sort_by(|a, b| a.0.cmp(&b.0));
                let mut total = 0;
                for (s, n) in rows {
                    println!("{} {}", s, n);
                    total += n
                }
                println!("total {}", total)
            }
            "ATTACKS" => {
                let t = square(a[0]).unwrap();
                let lists: Vec<Vec<String>> = [true, false]
                    .iter()
                    .map(|&w| {
                        (0..64)
                            .filter(|&s| color(p.b[s], w) && p.attack(s, t))
                            .map(name)
                            .collect()
                    })
                    .collect();
                println!(
                    "attacks {} white {}{} black {}{}",
                    a[0],
                    lists[0].len(),
                    lists[0]
                        .iter()
                        .map(|s| format!(" {}", s))
                        .collect::<String>(),
                    lists[1].len(),
                    lists[1]
                        .iter()
                        .map(|s| format!(" {}", s))
                        .collect::<String>()
                )
            }
            "PINS" => {
                let k =
                    p.b.iter()
                        .position(|&x| x == if p.white { b'K' } else { b'k' })
                        .unwrap();
                let mut pins = Vec::new();
                for (dx, dy) in [
                    (1, 0),
                    (-1, 0),
                    (0, 1),
                    (0, -1),
                    (1, 1),
                    (1, -1),
                    (-1, 1),
                    (-1, -1),
                ] {
                    let (mut x, mut y) = (k as i32 % 8 + dx, k as i32 / 8 + dy);
                    let mut first = None;
                    while (0..8).contains(&x) && (0..8).contains(&y) {
                        let s = (y * 8 + x) as usize;
                        if p.b[s] != 0 {
                            if let Some(f) = first {
                                let kind = p.b[s].to_ascii_uppercase();
                                if color(p.b[s], !p.white)
                                    && (kind == b'Q'
                                        || kind == if dx == 0 || dy == 0 { b'R' } else { b'B' })
                                {
                                    pins.push((f, s))
                                }
                                break;
                            } else if color(p.b[s], p.white) {
                                first = Some(s)
                            } else {
                                break;
                            }
                        }
                        x += dx;
                        y += dy
                    }
                }
                pins.sort();
                println!(
                    "pins {}{}",
                    pins.len(),
                    pins.iter()
                        .map(|&(s, t)| format!(" {}-{}", name(s), name(t)))
                        .collect::<String>()
                )
            }
            "HISTORY" => {
                println!("history {}", history.len());
                for (i, r) in history.iter().enumerate() {
                    println!("{} {} {} {}", i + 1, r.uci, r.san, r.captured)
                }
            }
            "STATUS" | "PGN" => {
                let key = p.key();
                let rep = history.iter().filter(|r| r.before.key() == key).count() + 1;
                let check = p.check(p.white);
                let none = p.legal().is_empty();
                let state = if none {
                    if check { "checkmate" } else { "stalemate" }
                } else if check {
                    "check"
                } else {
                    "normal"
                };
                let mut draws = Vec::new();
                if p.half >= 100 {
                    draws.push("fifty")
                }
                if rep >= 3 {
                    draws.push("threefold")
                }
                let other: Vec<_> = (0..64)
                    .filter(|&s| p.b[s] != 0 && p.b[s].to_ascii_uppercase() != b'K')
                    .collect();
                if !other
                    .iter()
                    .any(|&s| b"PRQ".contains(&p.b[s].to_ascii_uppercase()))
                    && (other.len() <= 1
                        || (other.iter().all(|&s| p.b[s].to_ascii_uppercase() == b'B')
                            && other.iter().all(|&s| {
                                (s % 8 + s / 8) % 2 == (other[0] % 8 + other[0] / 8) % 2
                            })))
                {
                    draws.push("insufficient")
                }
                if c == "STATUS" {
                    println!(
                        "status {} {} rep {}{}",
                        if p.white { "white" } else { "black" },
                        state,
                        rep,
                        draws.iter().map(|s| format!(" {}", s)).collect::<String>()
                    )
                } else {
                    let result = if state == "checkmate" {
                        if p.white { "0-1" } else { "1-0" }
                    } else if state == "stalemate" || !draws.is_empty() {
                        "1/2-1/2"
                    } else {
                        "*"
                    };
                    println!("[Result \"{}\"]", result);
                    if loaded {
                        println!("[SetUp \"1\"]\n[FEN \"{}\"]", start.fen())
                    }
                    let mut words = Vec::new();
                    for (i, r) in history.iter().enumerate() {
                        if r.before.white {
                            words.push(format!("{}.", r.before.full))
                        } else if i == 0 {
                            words.push(format!("{}...", r.before.full))
                        }
                        words.push(r.san.clone())
                    }
                    words.push(result.into());
                    println!("{}", words.join(" "))
                }
            }
            _ => {}
        }
    }
}
