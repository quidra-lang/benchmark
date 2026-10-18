fn dfs(v: usize,
graph: &[[bool; 9]; 9],
seen: &mut [bool; 9],
order: &mut Vec<usize>) {
    seen[v] = true;
    order.push(v);
    for w in 0..9 {
        if graph[v][w] && !seen[w] {
            dfs(w, graph, seen, order);
        }
    }
}

fn main() {
    let mut graph = [[false; 9]; 9];
    for[a, b] in [[5, 0], [3, 8], [7, 2], [1, 6], [0, 2], [5, 3], [7, 5], [6, 4], [8, 7]] {
        graph[a][b] = true;
        graph[b][a] = true;
    }
    let mut seen = [false; 9];
    let mut order = Vec::new();
    dfs(0, &graph, &mut seen, &mut order);
    print!("DFS:");
    for v in order {
        print!(" {}", v);
    }
    println!();
    seen.fill(false);
    let mut queue = std::collections::VecDeque::from([0]);
    seen[0] = true;
    print!("BFS:");
    while let Some(v) = queue.pop_front() {
        print!(" {}", v);
        for w in 0..9 {
            if graph[v][w] && !seen[w] {
                seen[w] = true;
                queue.push_back(w);
            }
        }
    }
    println!();
    seen.fill(false);
    let mut components = Vec::new();
    for v in 0..9 {
        if !seen[v] {
            let mut component = Vec::new();
            dfs(v, &graph, &mut seen, &mut component);
            component.sort();
            components.push(component);
        }
    }
    println!("components: {}", components.len());
    for (i, component) in components.iter().enumerate() {
        print!("component {}:", i + 1);
        for v in component {
            print!(" {}", v);
        }
        println!();
    }
}
