use std::collections::VecDeque;

pub fn strong_components(adjacency: &[Vec<usize>]) -> Vec<Vec<usize>> {
    let count = adjacency.len();
    let mut order = vec![None; count];
    let mut low = vec![0; count];
    let mut on_stack = vec![false; count];
    let mut stack = Vec::new();
    let mut components = Vec::new();
    let mut counter = 0;
    for root in 0..count {
        if order[root].is_some() { continue; }
        order[root] = Some(counter);
        low[root] = counter;
        counter += 1;
        stack.push(root);
        on_stack[root] = true;
        let mut work = vec![(root, 0)];
        while let Some(&(node, position)) = work.last() {
            if position < adjacency[node].len() {
                work.last_mut().unwrap().1 += 1;
                let child = adjacency[node][position];
                if order[child].is_none() {
                    order[child] = Some(counter);
                    low[child] = counter;
                    counter += 1;
                    stack.push(child);
                    on_stack[child] = true;
                    work.push((child, 0));
                } else if on_stack[child] {
                    low[node] = low[node].min(order[child].unwrap());
                }
                continue;
            }
            work.pop();
            if let Some(&(parent, _)) = work.last() { low[parent] = low[parent].min(low[node]); }
            if low[node] == order[node].unwrap() {
                let mut component = Vec::new();
                loop {
                    let member = stack.pop().unwrap();
                    on_stack[member] = false;
                    component.push(member);
                    if member == node { break; }
                }
                components.push(component);
            }
        }
    }
    components
}

pub fn reachable(adjacency: &[Vec<usize>], starts: &[usize]) -> Vec<bool> {
    let mut seen = vec![false; adjacency.len()];
    let mut stack = Vec::new();
    for &start in starts {
        if !seen[start] { seen[start] = true; stack.push(start); }
    }
    while let Some(node) = stack.pop() {
        for &neighbor in &adjacency[node] {
            if !seen[neighbor] { seen[neighbor] = true; stack.push(neighbor); }
        }
    }
    seen
}

pub fn bfs_distances(adjacency: &[Vec<usize>], starts: &[usize]) -> Vec<i32> {
    let mut distance = vec![-1; adjacency.len()];
    let mut queue = VecDeque::new();
    for &start in starts {
        if distance[start] == -1 { distance[start] = 0; queue.push_back(start); }
    }
    while let Some(node) = queue.pop_front() {
        for &neighbor in &adjacency[node] {
            if distance[neighbor] == -1 {
                distance[neighbor] = distance[node] + 1;
                queue.push_back(neighbor);
            }
        }
    }
    distance
}

pub fn weak_components(neighbors: &[Vec<usize>]) -> Vec<usize> {
    let mut labels = vec![usize::MAX; neighbors.len()];
    let mut count = 0;
    for start in 0..neighbors.len() {
        if labels[start] != usize::MAX { continue; }
        labels[start] = count;
        let mut stack = vec![start];
        while let Some(node) = stack.pop() {
            for &neighbor in &neighbors[node] {
                if labels[neighbor] == usize::MAX { labels[neighbor] = count; stack.push(neighbor); }
            }
        }
        count += 1;
    }
    labels
}
