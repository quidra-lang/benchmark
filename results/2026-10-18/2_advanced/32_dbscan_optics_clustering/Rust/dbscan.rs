use std::collections::VecDeque;

pub fn cluster(neighborhoods: &[Vec<usize>], min_pts: usize) -> (Vec<i32>, Vec<bool>) {
    let core: Vec<bool> = neighborhoods.iter().map(|n| n.len() >= min_pts).collect();
    let mut labels = vec![-2; neighborhoods.len()];
    let mut label = 0;
    for i in 0..labels.len() {
        if labels[i] != -2 { continue; }
        if !core[i] {
            labels[i] = -1;
            continue;
        }
        labels[i] = label;
        let mut queue = VecDeque::from(neighborhoods[i].clone());
        while let Some(j) = queue.pop_front() {
            if labels[j] == -1 {
                labels[j] = label;
            } else if labels[j] == -2 {
                labels[j] = label;
                if core[j] { queue.extend(&neighborhoods[j]); }
            }
        }
        label += 1;
    }
    (labels, core)
}
