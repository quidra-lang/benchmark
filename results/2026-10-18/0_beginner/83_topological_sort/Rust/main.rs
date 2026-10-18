fn solve(names: &[&str],
edges: &[(&str, &str)],
show_cycle: bool) {
    let n = names.len();
    let mut graph = vec![vec![false; n]; n];
    let mut indegree = vec![0; n];
    let mut taken = vec![false; n];
    for (a, b) in edges {
        let a = names.iter().position(|name| name == a).unwrap();
        let b = names.iter().position(|name| name == b).unwrap();
        graph[a][b] = true;
        indegree[b] += 1;
    }
    let mut order = Vec::new();
    loop {
        let best = (0..n).filter(|&v| !taken[v] && indegree[v] == 0).min_by_key(|&v| names[v]);
        let Some(v) = best else {
            break;
        };
        order.push(names[v]);
        taken[v] = true;
        for w in 0..n {
            if graph[v][w] {
                indegree[w] -= 1;
            }
        }
    }
    println!("order: {}", order.join(" -> "));
    if show_cycle {
        let mut remaining: Vec<&str> = (0..n).filter(|&v| !taken[v]).map(|v| names[v]).collect();
        remaining.sort();
        println!("cycle: {}", remaining.join(" "));
    }
}

fn main() {
    solve(&["physics", "algebra", "graphics", "programming", "statistics", "calculus", "databases",
        "algorithms"], &[("calculus", "physics"), ("algebra", "calculus"), ("programming", "algorithms"),
        ("algebra", "statistics"), ("algorithms", "databases"), ("statistics", "databases"), ("calculus",
        "graphics"), ("algorithms", "graphics"), ("physics", "graphics")], false);
    solve(&["music", "ecology", "art", "geology", "biology", "chemistry"], &[("music", "art"), ("art",
        "ecology"), ("biology", "chemistry"), ("chemistry", "ecology"), ("ecology", "geology"), ("geology",
        "chemistry")], true);
}
