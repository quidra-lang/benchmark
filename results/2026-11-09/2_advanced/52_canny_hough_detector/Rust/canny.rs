use std::collections::VecDeque;

pub fn neighbors(index: usize, width: usize, height: usize) -> Vec<usize> {
    let (x, y) = ((index % width) as i64, (index / width) as i64);
    let mut result = Vec::new();
    for dy in -1..=1 {
        for dx in -1..=1 {
            let (a, b) = (x + dx, y + dy);
            if (dx != 0 || dy != 0) && a >= 0 && b >= 0 && a < width as i64 && b < height as i64 { result.push(b as usize * width + a as usize); }
        }
    }
    result
}

pub fn directions(gx: &[i64], gy: &[i64]) -> Vec<i64> {
    gx.iter().zip(gy).map(|(&x, &y)| {
        let (ax, ay) = (x.abs(), y.abs());
        if 29 * ay <= 12 * ax { 0 } else if 29 * ay >= 70 * ax { 90 }
        else if x * y < 0 { 45 } else { 135 }
    }).collect()
}

pub fn suppress(magnitude: &[i64], directions: &[i64], width: usize, height: usize) -> Vec<i64> {
    let mut values = vec![0; magnitude.len()];
    for y in 1..height - 1 {
        for x in 1..width - 1 {
            let i = y * width + x;
            let (a, b) = match directions[i] {
                0 => (i - 1, i + 1),
                45 => (i - width + 1, i + width - 1),
                90 => (i - width, i + width),
                _ => (i - width - 1, i + width + 1),
            };
            if magnitude[i] > magnitude[a] && magnitude[i] >= magnitude[b] { values[i] = magnitude[i]; }
        }
    }
    values
}

pub fn hysteresis(nms: &[i64], width: usize, height: usize, low: i64, high: i64) -> Vec<bool> {
    let mut edges: Vec<bool> = nms.iter().map(|&n| n >= high).collect();
    let mut queue: VecDeque<usize> = (0..edges.len()).filter(|&i| edges[i]).collect();
    while let Some(i) = queue.pop_front() {
        for j in neighbors(i, width, height) {
            if !edges[j] && nms[j] >= low { edges[j] = true; queue.push_back(j); }
        }
    }
    edges
}

pub fn components(edges: &[bool], width: usize, height: usize) -> Vec<Vec<usize>> {
    let mut visited = vec![false; edges.len()];
    let mut result = Vec::new();
    for i in 0..edges.len() {
        if !edges[i] || visited[i] { continue; }
        visited[i] = true;
        let mut component = Vec::new();
        let mut queue = VecDeque::from([i]);
        while let Some(j) = queue.pop_front() {
            component.push(j);
            for k in neighbors(j, width, height) {
                if edges[k] && !visited[k] { visited[k] = true; queue.push_back(k); }
            }
        }
        component.sort();
        result.push(component);
    }
    result
}
