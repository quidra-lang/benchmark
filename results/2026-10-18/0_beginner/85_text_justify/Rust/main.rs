fn main() {
    let paragraph = "Good software is written for people first and for machines second. A clear program explains its purpose through careful names, small functions and honest tests. When a team agrees on shared rules for internationalization, documentation and code review, every newcomer can read the code quickly, change it safely and ship new improvements with confidence instead of fear, week after week.";
    let words: Vec<&str> = paragraph.split(' ').collect();
    let mut start = 0;
    while start < words.len() {
        let (mut end, mut letters) = (start, 0);
        while end < words.len() && letters + words[end].len() + end - start <= 30 {
            letters += words[end].len();
            end += 1;
        }
        let gaps = end - start - 1;
        let last = end == words.len();
        let mut line = String::new();
        for i in start..end {
            line.push_str(words[i]);
            if i + 1 < end {
                let spaces = if last || gaps == 0 {
                    1
                } else {
                    (30 - letters) / gaps + usize::from(i - start < (30 - letters) % gaps)
                };
                line.push_str(&" ".repeat(spaces));
            }
        }
        line.push_str(&" ".repeat(30 - line.len()));
        println!("|{}|", line);
        start = end;
    }
}
