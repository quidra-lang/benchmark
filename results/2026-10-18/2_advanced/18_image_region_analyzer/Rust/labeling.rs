use crate::morphology::occupied;

pub struct Labeling {
    pub labels: Vec<Vec<usize>>,
    pub count: usize,
    pub provisional: usize,
}

fn find(parents: &mut [usize], mut label: usize) -> usize {
    while parents[label] != label {
        let parent = parents[label];
        parents[label] = parents[parent];
        label = parents[label];
    }
    label
}

fn union(parents: &mut [usize], first: usize, second: usize) {
    let first = find(parents, first);
    let second = find(parents, second);
    if first != second { parents[first.max(second)] = first.min(second); }
}

pub fn label_components(mask: &[Vec<bool>], connectivity: usize) -> Labeling {
    let (height, width) = (mask.len(), mask[0].len());
    let previous = if connectivity == 4 { vec![(-1, 0), (0, -1)] } else { vec![(-1, 0), (-1, -1), (0, -1), (1, -1)] };
    let mut provisional = vec![vec![0; width]; height];
    let mut parents = vec![0];
    for y in 0..height { for x in 0..width {
        if !mask[y][x] { continue; }
        let mut neighbors = Vec::new();
        for &(dx, dy) in &previous {
            let (nx, ny) = (x as i64 + dx, y as i64 + dy);
            if occupied(mask, nx, ny) { neighbors.push(provisional[ny as usize][nx as usize]); }
        }
        if neighbors.is_empty() { provisional[y][x] = parents.len(); parents.push(parents.len()); }
        else {
            provisional[y][x] = neighbors[0];
            for &other in &neighbors[1..] { union(&mut parents, neighbors[0], other); }
        }
    } }
    let mut numbers = vec![0; parents.len()];
    let mut labels = vec![vec![0; width]; height];
    let mut count = 0;
    for y in 0..height { for x in 0..width {
        if provisional[y][x] == 0 { continue; }
        let root = find(&mut parents, provisional[y][x]);
        if numbers[root] == 0 { count += 1; numbers[root] = count; }
        labels[y][x] = numbers[root];
    } }
    Labeling { labels, count, provisional: parents.len() - 1 }
}

pub fn bit_quad_euler(mask: &[Vec<bool>], connectivity: usize) -> i64 {
    let (mut singles, mut triples, mut diagonals) = (0, 0, 0);
    for y in -1..mask.len() as i64 { for x in -1..mask[0].len() as i64 {
        let tl = occupied(mask, x, y);
        let tr = occupied(mask, x + 1, y);
        let bl = occupied(mask, x, y + 1);
        let br = occupied(mask, x + 1, y + 1);
        let count = [tl, tr, bl, br].iter().filter(|&&value| value).count();
        if count == 1 { singles += 1; }
        else if count == 3 { triples += 1; }
        else if count == 2 && ((tl && br) || (tr && bl)) { diagonals += 1; }
    } }
    (singles - triples + if connectivity == 8 { -2 * diagonals } else { 2 * diagonals }) / 4
}
