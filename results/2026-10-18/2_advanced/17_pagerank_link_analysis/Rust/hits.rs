fn norm(values: &[f64], nodes: &[usize]) -> f64 {
    let mut squares = 0.0;
    for &node in nodes { squares += values[node] * values[node]; }
    squares.sqrt()
}

pub fn hits(count: usize, nodes: &[usize], links: &[(usize, usize)], iterations: usize) -> (Vec<f64>, Vec<f64>) {
    let mut sources = vec![Vec::new(); count];
    let mut targets = vec![Vec::new(); count];
    let mut sorted = links.to_vec();
    sorted.sort_unstable();
    for (source, target) in sorted { sources[target].push(source); targets[source].push(target); }
    let mut authority = vec![0.0; count];
    let mut hub = vec![0.0; count];
    for &node in nodes { authority[node] = 1.0; hub[node] = 1.0; }
    for _ in 0..iterations {
        let mut incoming = vec![0.0; count];
        let mut outgoing = vec![0.0; count];
        for &node in nodes { for &source in &sources[node] { incoming[node] += hub[source]; } }
        for &node in nodes { for &target in &targets[node] { outgoing[node] += incoming[target]; } }
        let authority_norm = norm(&incoming, nodes);
        let hub_norm = norm(&outgoing, nodes);
        for &node in nodes { authority[node] = incoming[node] / authority_norm; hub[node] = outgoing[node] / hub_norm; }
    }
    (authority, hub)
}
