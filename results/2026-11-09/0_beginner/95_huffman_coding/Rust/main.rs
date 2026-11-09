struct Node {
    weight: usize,
    minimum: usize,
    left: Option<usize>,
    right: Option<usize>,
    symbol: Option<usize>,
}

fn pop(roots: &mut Vec<usize>, nodes: &[Node]) -> usize {
    let position = roots
        .iter()
        .enumerate()
        .min_by_key(|pair| {
            let v = *pair.1;
            (nodes[v].weight, nodes[v].minimum)
        })
        .unwrap()
        .0;
    roots.remove(position)
}

fn assign(nodes: &[Node], root: usize, prefix: String, codes: &mut [String]) {
    if let Some(symbol) = nodes[root].symbol {
        codes[symbol] = prefix;
        return;
    }
    assign(
        nodes,
        nodes[root].left.unwrap(),
        prefix.clone() + "0",
        codes,
    );
    assign(nodes, nodes[root].right.unwrap(), prefix + "1", codes);
}

fn main() {
    let text = "she sells sea shells by the sea shore";
    let mut freq = [0; 128];
    for c in text.bytes() {
        freq[c as usize] += 1;
    }
    let mut nodes = Vec::new();
    let mut roots = Vec::new();
    for c in 0..128 {
        if freq[c] > 0 {
            roots.push(nodes.len());
            nodes.push(Node {
                weight: freq[c],
                minimum: c,
                left: None,
                right: None,
                symbol: Some(c),
            });
        }
    }
    while roots.len() > 1 {
        let left = pop(&mut roots, &nodes);
        let right = pop(&mut roots, &nodes);
        roots.push(nodes.len());
        nodes.push(Node {
            weight: nodes[left].weight + nodes[right].weight,
            minimum: nodes[left].minimum.min(nodes[right].minimum),
            left: Some(left),
            right: Some(right),
            symbol: None,
        });
    }
    let mut codes = vec![String::new(); 128];
    assign(&nodes, roots[0], String::new(), &mut codes);
    let mut bits = 0;
    for c in 0..128 {
        if freq[c] > 0 {
            println!("'{}' freq={} code={}", c as u8 as char, freq[c], codes[c]);
            bits += freq[c] * codes[c].len();
        }
    }
    println!("encoded bits: {}\nfixed 8-bit: {}", bits, text.len() * 8);
}
