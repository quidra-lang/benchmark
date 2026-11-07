pub type Interval = (i64, i64, char);
pub fn scale(makespan: i64, width: i64) -> (i64, usize) {
    let mut magnitude = 1;
    loop {
        for step in [1, 2, 5] {
            let q = step*magnitude;
            let n = (makespan+q-1)/q;
            if n <= width {
                return(q, n as usize)
            }
        }
        magnitude *= 10;
    }
}
pub fn time_row(q: i64, n: usize) -> String {
    let mut s = "time".to_owned();
    for c in (0..n).step_by(10) {
        if s.len()<6+c {
            s.push_str(&" ".repeat(6+c-s.len()));
        }
        s.push_str(&(c as i64*q).to_string());
    }
    s
}
pub fn rule_row(n: usize) -> String {
    format!("      {}", (0..n).map(|c|if c%10 == 0 {
        '+'
    }else {
        '-'
    }).collect::<String>())
}
pub fn frame(label: &str, marks: String) -> String {
    format!("{label:<4} |{marks}|")
}
pub fn chart_row(label: &str, intervals: &[Interval], q: i64, n: usize) -> String {
    let mut sorted = intervals.to_vec();
    sorted.sort_by_key(|p|p.0);
    let marks = (0..n).map(|c| {
        let lo = c as i64*q; let mut best = 0; let mut mark = '.'; for &(s, e, m)in &sorted {
            let overlap = e.min(lo+q)-s.max(lo); if overlap>best {
                best = overlap; mark = m
            }
        }
        mark
    }).collect();
    frame(label, marks)
}
pub fn busy_row(rows: &[Vec<Interval>], q: i64, n: usize) -> String {
    frame("busy", (0..n).map(|c| {
        let t = c as i64*q; let busy = rows.iter().filter(|r|r.iter().any(|&(s, e, _)|s <= t && t<e)).count(); if busy == 10 {
            'X'
        }else {
            char::from(b'0'+busy as u8)
        }
    }).collect())
}
