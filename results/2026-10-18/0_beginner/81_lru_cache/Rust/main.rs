fn main() {
    let mut cache = Vec::new();
    let (mut hits, mut misses) = (0, 0);
    for key in "BACBDABEADDCAEB".chars() {
        let position = cache.iter().position(|&c| c == key);
        let hit = position.is_some();
        let mut evicted = None;
        if let Some(i) = position {
            hits += 1;
            cache.remove(i);
        } else {
            misses += 1;
            if cache.len() == 3 {
                evicted = cache.pop();
            }
        }
        cache.insert(0, key);
        print!("{}: {}", key, if hit {
            "hit"
        } else {
            "miss"
        });
        if let Some(c) = evicted {
            print!(", evict {}", c);
        }
        print!(" [");
        for (i, c) in cache.iter().enumerate() {
            if i > 0 {
                print!(" ");
            }
            print!("{}", c);
        }
        println!("]");
    }
    println!("hits: {} misses: {}", hits, misses);
}
