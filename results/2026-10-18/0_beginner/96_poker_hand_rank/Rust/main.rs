struct Hand {
    text: String,
    category: usize,
    key: Vec<usize>,
}

fn evaluate(text: &str) -> Hand {
    let ranks = b"23456789TJQKA";
    let bytes = text.as_bytes();
    let mut counts = [0; 15];
    let mut flush = true;
    for i in 0..5 {
        let rank = ranks.iter().position(|&c| c == bytes[i * 3]).unwrap() + 2;
        counts[rank] += 1;
        if bytes[i * 3 + 1] != bytes[1] {
            flush = false;
        }
    }
    let mut key: Vec<usize> = (2..=14).filter(|&r| counts[r] > 0).rev().collect();
    let maximum = *counts.iter().max().unwrap();
    let pairs = counts.iter().filter(|&&c| c == 2).count();
    let wheel = key.len() == 5 && [14, 2, 3, 4, 5].iter().all(|&r| counts[r] > 0);
    let straight = key.len() == 5 && (key[0] - key[4] == 4 || wheel);
    let category = if straight && flush {
        8
    } else if maximum == 4 {
        7
    } else if maximum == 3 && pairs == 1 {
        6
    } else if flush {
        5
    } else if straight {
        4
    } else if maximum == 3 {
        3
    } else if pairs == 2 {
        2
    } else if pairs == 1 {
        1
    } else {
        0
    };
    key.sort_by(|a, b| counts[*b].cmp(&counts[*a]).then(b.cmp(a)));
    if wheel && straight {
        key = (1..=5).rev().collect();
    }
    Hand {
        text: text.to_string(),
        category,
        key,
    }
}

fn main() {
    let mut hands: Vec<Hand> = [
        "9C 9D 5H QH 2C",
        "4D AH 3C 5S 2H",
        "KS 8S 2S JS 6S",
        "7H 7D KC 7S KD",
        "3H 6C 4S 2D 5C",
        "JD TC 4H 8C AS",
        "QC 6D QS 3S 6H",
        "9H KH 9S 8H 3D",
    ]
    .iter()
    .map(|s| evaluate(s))
    .collect();
    hands.sort_by(|a, b| b.category.cmp(&a.category).then(b.key.cmp(&a.key)));
    let categories = [
        "high card",
        "one pair",
        "two pair",
        "three of a kind",
        "straight",
        "flush",
        "full house",
        "four of a kind",
        "straight flush",
    ];
    for (i, h) in hands.iter().enumerate() {
        println!("{}. {}: {}", i + 1, h.text, categories[h.category]);
    }
}
