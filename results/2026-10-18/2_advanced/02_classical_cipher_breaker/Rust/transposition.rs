pub fn rail_number(position: usize, rails: usize) -> usize {
    let cycle = 2 * rails - 2;
    let offset = position % cycle;
    offset.min(cycle - offset)
}

pub fn rail_fence(text: &str, rails: usize, decrypt: bool) -> String {
    let mut positions: Vec<usize> = (0..text.len()).collect();
    positions.sort_by_key(|&position| (rail_number(position, rails), position));
    let input = text.as_bytes();
    if decrypt {
        let mut output = vec![0; input.len()];
        for (index, position) in positions.into_iter().enumerate() {
            output[position] = input[index];
        }
        String::from_utf8(output).unwrap()
    } else {
        positions.into_iter().map(|position| input[position] as char).collect()
    }
}

pub fn column_ranks(key: &str) -> Vec<usize> {
    let mut order: Vec<usize> = (0..key.len()).collect();
    order.sort_by_key(|&column| (key.as_bytes()[column], column));
    let mut ranks = vec![0; key.len()];
    for (rank, column) in order.into_iter().enumerate() {
        ranks[column] = rank + 1;
    }
    ranks
}

pub fn rank_string(key: &str) -> String {
    column_ranks(key).into_iter().map(|rank| (b'0' + rank as u8) as char).collect()
}

pub fn columnar(text: &str, key: &str, decrypt: bool) -> String {
    let ranks = rank_string(key);
    let mut order: Vec<usize> = (0..key.len()).collect();
    order.sort_by_key(|&column| ranks.as_bytes()[column]);
    let positions: Vec<usize> = order.into_iter().flat_map(|column| (column..text.len()).step_by(key.len())).collect();
    let input = text.as_bytes();
    if decrypt {
        let mut output = vec![0; input.len()];
        for (index, position) in positions.into_iter().enumerate() {
            output[position] = input[index];
        }
        String::from_utf8(output).unwrap()
    } else {
        positions.into_iter().map(|position| input[position] as char).collect()
    }
}
