fn main() {
    for phrase in ["Never odd or even", "Race a car", "Was it a car or a cat I saw?", "Hello, World!",
        "Step on no pets.", "No lemon, no melon"] {
        let clean: Vec<u8 >= phrase.bytes().filter(|c| c.is_ascii_alphabetic()).map(|c| c.to_ascii_lowercase()).collect();
        let yes = clean.iter().eq(clean.iter().rev());
        println!("{} -> {}", phrase, if yes {
            "yes"
        } else {
            "no"
        });
    }
}
