fn main() {
    let words = ["listen", "stone", "night", "silent", "notes", "apple", "thing", "enlist", "earth",
        "onset", "heart", "tones"];
    let keys: Vec<Vec<u8>> = words.iter().map(|w| {
        let mut k = w.as_bytes().to_vec();
        k.sort();
        k
    }).collect();
    let mut used = [false; 12];
    for i in 0..12 {
        if !used[i] {
            let mut group = Vec::new();
            for j in i..12 {
                if !used[j] && keys[j] == keys[i] {
                    group.push(words[j]);
                    used[j] = true;
                }
            }
            println!("{}", group.join(" "));
        }
    }
}
