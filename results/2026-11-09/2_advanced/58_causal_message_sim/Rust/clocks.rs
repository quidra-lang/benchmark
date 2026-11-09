pub fn local(l: &mut usize, v: &mut [usize], p: usize) {
    *l += 1;
    v[p] += 1;
}

pub fn receive(l: &mut usize, v: &mut [usize], p: usize, sent_l: usize, sent_v: &[usize]) {
    *l = (*l).max(sent_l) + 1;
    for (x, y) in v.iter_mut().zip(sent_v) {
        *x = (*x).max(*y);
    }
    v[p] += 1;
}

pub fn le(a: &[usize], b: &[usize]) -> bool {
    a.iter().zip(b).all(|(x, y)| x <= y)
}

pub fn relation(a: &[usize], b: &[usize]) -> &'static str {
    if a != b && le(a, b) { "->" } else if a != b && le(b, a) { "<-" } else { "||" }
}

pub fn deliverable(stamp: &[usize], counter: &[usize], source: usize) -> bool {
    stamp[source] == counter[source] + 1 && stamp.iter().zip(counter).enumerate()
        .all(|(i, (s, b))| i == source || s <= b)
}

pub fn missing(stamp: &[usize], counter: &[usize], source: usize) -> Vec<usize> {
    stamp.iter().zip(counter).enumerate().filter_map(|(i, (s, b))|
        if *s > *b + usize::from(i == source) { Some(i) } else { None }).collect()
}

pub fn text(v: &[usize]) -> String {
    v.iter().map(usize::to_string).collect::<Vec<_>>().join(",")
}
