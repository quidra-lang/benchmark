pub fn symbol(c: u8) -> usize { match c { b'$' => 0, b'#' => 1, b'A' => 2, b'C' => 3, b'G' => 4, _ => 5 } }

fn counting(order: &[usize], keys: &[usize], size: usize) -> Vec<usize> {
    let mut counts = vec![0; size];
    for &i in order { counts[keys[i]] += 1; }
    let mut total = 0;
    for count in &mut counts { let previous = *count; *count = total; total += previous; }
    let mut result = vec![0; order.len()];
    for &i in order { let key = keys[i]; result[counts[key]] = i; counts[key] += 1; }
    result
}

pub struct SuffixArray { pub order: Vec<usize>, pub classes: Vec<usize> }

pub fn build(text: &[u8]) -> SuffixArray {
    let n = text.len(); let positions: Vec<_> = (0..n).collect(); let codes: Vec<_> = text.iter().map(|&c| symbol(c)).collect();
    let mut order = counting(&positions, &codes, 6); let mut rank = vec![0; n]; let mut classes = 1;
    for i in 0..n { if i > 0 && codes[order[i]] != codes[order[i-1]] { classes += 1; } rank[order[i]] = classes-1; }
    let mut history = vec![classes]; let mut h = 1;
    while classes < n {
        let second: Vec<_> = (0..n).map(|i| if i+h < n { rank[i+h]+1 } else { 0 }).collect();
        order = counting(&counting(&positions, &second, classes+1), &rank, classes);
        let mut next = vec![0; n]; let mut count = 1;
        for i in 0..n {
            if i > 0 && (rank[order[i]], second[order[i]]) != (rank[order[i-1]], second[order[i-1]]) { count += 1; }
            next[order[i]] = count-1;
        }
        rank = next; classes = count; history.push(classes); h *= 2;
    }
    SuffixArray { order, classes: history }
}

pub struct Check { pub ordered: usize, pub sum: usize, pub maximum: usize, pub row: usize }
pub fn check(text: &[u8], order: &[usize]) -> Check {
    let mut result = Check { ordered: 0, sum: 0, maximum: 0, row: 1 };
    for i in 1..order.len() {
        let (a, b) = (order[i-1], order[i]); let mut equal = 0;
        while text[a+equal] == text[b+equal] { equal += 1; }
        result.ordered += usize::from(symbol(text[a+equal]) < symbol(text[b+equal])); result.sum += equal;
        if equal > result.maximum { result.maximum = equal; result.row = i; }
    }
    result
}
pub fn direct(text: &[u8]) -> Vec<usize> { let mut order: Vec<_> = (0..text.len()).collect(); order.sort_by(|&a, &b| text[a..].cmp(&text[b..])); order }
