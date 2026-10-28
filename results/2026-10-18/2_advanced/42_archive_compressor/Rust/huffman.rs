use std::cmp::Reverse;
use std::collections::BinaryHeap;

fn lengths(frequencies: &[usize]) -> Vec<usize> {
    let mut nodes: Vec<(Option<usize>, Option<(usize, usize)>)> = Vec::new();
    let mut queue = BinaryHeap::new();
    for (symbol, &frequency) in frequencies.iter().enumerate().filter(|(_, f)| **f > 0) {
        let node = nodes.len();
        nodes.push((Some(symbol), None));
        queue.push(Reverse((frequency, symbol, node)));
    }
    let mut lengths = vec![0; frequencies.len()];
    if queue.is_empty() { return lengths; }
    if queue.len() == 1 { let Reverse((_, symbol, _)) = queue.pop().unwrap(); lengths[symbol] = 1; return lengths; }
    while queue.len() > 1 {
        let Reverse((a, sa, na)) = queue.pop().unwrap();
        let Reverse((b, sb, nb)) = queue.pop().unwrap();
        let node = nodes.len();
        nodes.push((None, Some((na, nb))));
        queue.push(Reverse((a + b, sa.min(sb), node)));
    }
    let Reverse((_, _, root)) = queue.pop().unwrap();
    let mut stack = vec![(root, 0)];
    while let Some((node, depth)) = stack.pop() {
        if let Some(symbol) = nodes[node].0 { lengths[symbol] = depth; }
        if let Some((a, b)) = nodes[node].1 { stack.push((a, depth + 1)); stack.push((b, depth + 1)); }
    }
    lengths
}

pub fn limited(frequencies: &[usize], maximum: usize) -> (Vec<usize>, usize) {
    let mut frequencies = frequencies.to_vec();
    let mut halvings = 0;
    loop {
        let lengths = lengths(&frequencies);
        if *lengths.iter().max().unwrap() <= maximum { return (lengths, halvings); }
        for frequency in &mut frequencies { *frequency = (*frequency + 1) / 2; }
        halvings += 1;
    }
}

pub fn canonical(lengths: &[usize]) -> Vec<(usize, usize)> {
    let mut symbols: Vec<_> = lengths.iter().enumerate().filter(|(_, length)| **length > 0).map(|(symbol, &length)| (length, symbol)).collect();
    symbols.sort_unstable();
    let mut codes = vec![(0, 0); lengths.len()];
    let (mut code, mut previous) = (0, 0);
    for (i, &(length, symbol)) in symbols.iter().enumerate() {
        if i != 0 { code = (code + 1) << (length - previous); }
        codes[symbol] = (code, length);
        previous = length;
    }
    codes
}
