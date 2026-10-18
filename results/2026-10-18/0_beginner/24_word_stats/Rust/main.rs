fn main() {
    let words: Vec< &str >= "we planted beans and carrots in the garden behind our old house".split(' ').collect();
    let (mut longest, mut shortest) = (words[0], words[0]);
    let mut total = 0;
    for w in &words {
        total += w.len();
        if w.len()> longest.len() {
            longest = w;
        }
        if w.len() < shortest.len() {
            shortest = w;
        }
    }
    let avg = total as f64 / words.len() as f64;
    let q = (avg * 100.0 + 0.5) as i32;
    println!("words: {}\nlongest: {}\nshortest: {}\naverage length: {}.{:02}", words.len(), longest,
        shortest, q / 100, q % 100);
}
