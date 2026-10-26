fn main() {
    let words: Vec<&str> = "we planted beans and carrots in the garden behind our old house"
        .split(' ')
        .collect();
    let longest = words.iter().rev().max_by_key(|word| word.len()).unwrap();
    let shortest = words.iter().min_by_key(|word| word.len()).unwrap();
    let total: usize = words.iter().map(|word| word.len()).sum();
    println!(
        "words: {}\nlongest: {}\nshortest: {}\naverage length: {:.2}",
        words.len(),
        longest,
        shortest,
        total as f64 / words.len() as f64
    );
}
