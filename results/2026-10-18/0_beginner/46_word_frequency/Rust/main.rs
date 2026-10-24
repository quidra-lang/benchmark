fn main() {
    let text = "The cat sat on the mat. The dog sat on the rug, and the cat watched the dog. A bird sang on the fence, and the Dog barked at the bird. The cat slept in the sun, the bird flew away, and the dog sat by the door.";
    let mut counts = std::collections::BTreeMap::new();
    let lower = text.to_ascii_lowercase();
    for w in lower.split(|c: char| !c.is_ascii_alphabetic()).filter(|w| !w.is_empty()) {
        *counts.entry(w).or_default() += 1;
    }
    let mut entries: Vec<(&str, i32)> = counts.into_iter().collect();
    entries.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(b.0)));
    for (w, c) in entries.iter().take(5) {
        println!("{}: {}", w, c);
    }
    println!("distinct words: {}", entries.len());
}
