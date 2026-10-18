fn main() {
    let mut maze: Vec<Vec<u8>> = ["#############", "#S..#.......#", "#.#.#.###.#.#", "#.#...#...#.#",
        "#.###.#.###.#", "#...#...#...#", "###.#####.#.#", "#.......#..G#", "#############"].iter().map(|r| r.as_bytes().to_vec()).collect();
    let mut parent = [None; 117];
    let mut distance = [0; 117];
    let (mut start, mut goal) = (0, 0);
    for i in 0..117 {
        if maze[i / 13][i % 13] == b'S' {
            start = i;
        }
        if maze[i / 13][i % 13] == b'G' {
            goal = i;
        }
    }
    let mut queue = std::collections::VecDeque::from([start]);
    parent[start] = Some(start);
    while let Some(v) = queue.pop_front() {
        let (r, c) = ((v / 13) as i32, (v % 13) as i32);
        for (dr, dc) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
            let (rr, cc) = (r + dr, c + dc);
            if !(0..9).contains(&rr) || !(0..13).contains(&cc) || maze[rr as usize][cc as usize] == b'#' {
                continue;
            }
            let w = rr as usize * 13 + cc as usize;
            if parent[w].is_none() {
                parent[w] = Some(v);
                distance[w] = distance[v] + 1;
                queue.push_back(w);
            }
        }
    }
    let mut v = goal;
    while v != start {
        if maze[v / 13][v % 13] == b'.' {
            maze[v / 13][v % 13] = b'*';
        }
        v = parent[v].unwrap();
    }
    println!("steps: {}", distance[goal]);
    for row in maze {
        println!("{}", String::from_utf8(row).unwrap());
    }
}
