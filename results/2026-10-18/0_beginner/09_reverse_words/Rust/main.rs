fn main() {
    let sentence = "every program starts with a single line";
    let reversed_characters: String = sentence.chars().rev().collect();
    println!("{}", reversed_characters);
    let reversed_words: Vec<&str> = sentence.split(' ').rev().collect();
    println!("{}", reversed_words.join(" "));
}
