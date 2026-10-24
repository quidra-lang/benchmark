fn main() {
    let sentence = "every program starts with a single line";
    println!("{}", sentence.chars().rev().collect::<String>());
    println!("{}", sentence.split(' ').rev().collect::<Vec<_>>().join(" "));
}
