use crate::agglomerative::Merge;

pub fn ordered_children(merges: &[Merge], n: usize) -> Vec<(usize, usize)> {
    let mut minimum: Vec<usize> = (0..n).collect();
    let mut children = Vec::new();
    for merge in merges {
        children.push(if minimum[merge.a] < minimum[merge.b] { (merge.a, merge.b) } else { (merge.b, merge.a) });
        minimum.push(minimum[merge.a].min(minimum[merge.b]));
    }
    children
}

pub fn leaf_order(children: &[(usize, usize)], n: usize) -> Vec<usize> {
    let mut order = Vec::new();
    let mut pending = vec![n + children.len() - 1];
    while let Some(node) = pending.pop() {
        if node < n { order.push(node); }
        else { let (upper, lower) = children[node - n]; pending.push(lower); pending.push(upper); }
    }
    order
}

pub fn column(height: f64, maximum: f64, width: usize) -> usize {
    let position = (height / maximum * width as f64).floor();
    if position > width as f64 { width + 1 } else { position as usize }
}

pub fn dendrogram_rows(merges: &[Merge], children: &[(usize, usize)], order: &[usize], ids: &[String], labels: &[String], maximum: f64, cuts: &[usize], width: usize) -> Vec<String> {
    let n = order.len();
    let mut grid = vec![vec![0usize; width + 1]; n];
    let mut anchors = vec![0; 2 * n - 1];
    for (row, &leaf) in order.iter().enumerate() { anchors[leaf] = row; }
    for &x in cuts {
        if x <= width { for row in &mut grid { row[x] = row[x].max(1); } }
    }
    let columns: Vec<usize> = merges.iter().map(|merge| column(merge.height, maximum, width)).collect();
    for (step, &(upper, lower)) in children.iter().enumerate() {
        let x = columns[step];
        grid[anchors[upper]][x] = 4;
        grid[anchors[lower]][x] = 4;
        for row in anchors[upper] + 1..anchors[lower] { grid[row][x] = grid[row][x].max(3); }
        for child in [upper, lower] {
            let start = if child < n { 0 } else { columns[child - n] + 1 };
            for position in start..x { grid[anchors[child]][position] = grid[anchors[child]][position].max(2); }
        }
        anchors[n + step] = (anchors[upper] + anchors[lower]) / 2;
    }
    let id_width = ids.iter().map(String::len).max().unwrap();
    let label_width = labels.iter().map(String::len).max().unwrap();
    let marks = b" :-|+";
    let mut rows = Vec::new();
    for (row, &leaf) in order.iter().enumerate() {
        let cells: String = grid[row].iter().map(|&level| marks[level] as char).collect();
        rows.push(format!("{:<id_width$} {:<label_width$} {cells}", ids[leaf], labels[leaf]).trim_end().to_owned());
    }
    let scale: String = (0..=width).map(|x| if x % 10 == 0 { '+' } else { '-' }).collect();
    rows.push(" ".repeat(id_width + label_width + 2) + &scale);
    rows
}
