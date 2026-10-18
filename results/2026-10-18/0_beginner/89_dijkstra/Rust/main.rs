fn main() {
    let mut graph = [[0; 7]; 7];
    for[a, b, w] in [[0, 1, 7], [0, 2, 3], [0, 3, 9], [1, 2, 2], [2, 4, 6], [1, 3, 3], [3, 4, 4], [3,
        5, 5], [4, 5, 3], [4, 6, 8], [5, 6, 4]] {
        graph[a][b] = w;
        graph[b][a] = w;
    }
    let mut distance = [1000000; 7];
    let mut parent = [None; 7];
    let mut done = [false; 7];
    distance[0] = 0;
    for _ in 0..7 {
        let u = (0..7).filter(|&v| !done[v]).min_by_key(|&v| (distance[v], v)).unwrap();
        done[u] = true;
        for v in 0..7 {
            if graph[u][v] > 0 && distance[u] + graph[u][v] < distance[v] {
                distance[v] = distance[u] + graph[u][v];
                parent[v] = Some(u);
            }
        }
    }
    for v in 0..7 {
        let mut path = Vec::new();
        let mut current = Some(v);
        while let Some(u) = current {
            path.push(((b'A' + u as u8) as char).to_string());
            current = parent[u];
        }
        path.reverse();
        println!("{}: distance={} path={}", (b'A' + v as u8) as char, distance[v], path.join("-"));
    }
}
