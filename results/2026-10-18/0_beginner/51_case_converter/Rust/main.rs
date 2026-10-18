fn main() {
    for id in ["user_name", "maxRetryCount", "ShoppingCartItem", "background-color", "get_last_login_time",
        "isEmailAddressValid"] {
        let mut words = Vec::new();
        let mut word = String::new();
        for c in id.chars() {
            if c == '_' || c == '-' || c.is_ascii_uppercase() {
                if !word.is_empty() {
                    words.push(std::mem::take(&mut word));
                }
                if c == '_' || c == '-' {
                    continue;
                }
            }
            word.push(c.to_ascii_lowercase());
        }
        if !word.is_empty() {
            words.push(word);
        }
        let caps: Vec<String> = words.iter().map(|w| w[..1].to_ascii_uppercase() + &w[1..]).collect();
        let camel = words[0].clone() + &caps[1..].concat();
        println!("{}: snake={}, camel={}, pascal={}, kebab={}", id, words.join("_"), camel, caps.concat(),
            words.join("-"));
    }
}
