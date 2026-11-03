# Task B selection: 96_poker_hand_rank / Rust

## Common answer requirements

Classify the two specified hands, explain ace-low recognition and comparison-key rewrite, compare strengths lexicographically and identify original-text preservation in output.

## Answer and source dependencies

4D AH 3C 5S 2H maps to ranks {2,3,4,5,14}. Its mixed suits exclude a flush; the wheel special case makes it a straight despite the ace’s high numeric encoding, and rewrites its comparison sequence to [5,4,3,2,1]. 3H 6C 4S 2D 5C has distinct consecutive ranks {2,3,4,5,6}, mixed suits and no multiplicities, so is an ordinary straight with sequence [6,5,4,3,2]. The categories tie; descending lexicographic rank comparison examines 6 versus 5 first, placing the six-high straight ahead. The evaluator carries the original hand string separately from its numeric key, or sorts indices into the original strings. Printing reads that original field/index, so neither the ace normalization nor rank sorting reorders the displayed cards.



## Scope and dependency evidence checked after independent review

Independent excerpt-first review recorded missing literal-input/evaluator association and missing boundaries separating card counting, distinct ranks, category choice, wheel replacement, sorting and printing. The retained declarations and literal terminators connect the two actual inputs to evaluate/describe; Java record Hand, Kotlin data class Hand, and Swift Hand struct establish constructor-to-original-text-field mapping. The first hand has distinct ranks2,3,4,5,14 and becomes wheel straight with comparison sequence5,4,3,2,1. The second has2,3,4,5,6 and sequence6,5,4,3,2. Suits differ, rank multiplicities are all one, so both are straight (not flush or multiplicity categories). Equal straight categories compare6 against5, placing the second first. Original input text is stored separately or kept in a parallel original array and is used unchanged in output.

Source: `main.rs`. Selected original locations: L1,L2,L3,L4,L5,L7,L8,L9,L10,L11,L12,L13,L14,L15,L16,L17,L18,L19,L20,L21,L22,L23,L24,L25,L26,L27,L28,L29,L30,L31,L32,L33,L34,L36,L38,L40,L42,L43,L44,L45,L46,L47,L48,L49,L50,L51,L52,L55,L57,L60,L64,L65,L66,L67,L68,L69,L70,L71,L72,L73,L74,L79,L80,L81,L82.

- L1: `struct Hand {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L2: `    text: String,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L3: `    category: usize,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L4: `    key: Vec<usize>,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L5: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L7: `fn evaluate(text: &str) -> Hand {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L8: `    let ranks = b"23456789TJQKA";` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L9: `    let bytes = text.as_bytes();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L10: `    let mut counts = [0; 15];` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L11: `    let mut flush = true;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L12: `    for i in 0..5 {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L13: `        let rank = ranks.iter().position(|&c| c == bytes[i * 3]).unwrap() + 2;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L14: `        counts[rank] += 1;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L15: `        if bytes[i * 3 + 1] != bytes[1] {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L16: `            flush = false;` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L17: `        }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L18: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L19: `    let mut key: Vec<usize> = (2..=14).filter(|&r| counts[r] > 0).rev().collect();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L20: `    let maximum = *counts.iter().max().unwrap();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L21: `    let pairs = counts.iter().filter(|&&c| c == 2).count();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L22: `    let wheel = key.len() == 5 && [14, 2, 3, 4, 5].iter().all(|&r| counts[r] > 0);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L23: `    let straight = key.len() == 5 && (key[0] - key[4] == 4 || wheel);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L24: `    let category = if straight && flush {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L25: `        8` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L26: `    } else if maximum == 4 {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L27: `        7` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L28: `    } else if maximum == 3 && pairs == 1 {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L29: `        6` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L30: `    } else if flush {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L31: `        5` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L32: `    } else if straight {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L33: `        4` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L34: `    } else if maximum == 3 {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L36: `    } else if pairs == 2 {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L38: `    } else if pairs == 1 {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L40: `    } else {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L42: `    };` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L43: `    key.sort_by(|a, b| counts[*b].cmp(&counts[*a]).then(b.cmp(a)));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L44: `    if wheel && straight {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L45: `        key = (1..=5).rev().collect();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L46: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L47: `    Hand {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L48: `        text: text.to_string(),` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L49: `        category,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L50: `        key,` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L51: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L52: `}` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L55: `    let mut hands: Vec<Hand> = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L57: `        "4D AH 3C 5S 2H",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L60: `        "3H 6C 4S 2D 5C",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L64: `    ]` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L65: `    .iter()` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L66: `    .map(|s| evaluate(s))` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L67: `    .collect();` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L68: `    hands.sort_by(|a, b| b.category.cmp(&a.category).then(b.key.cmp(&a.key)));` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L69: `    let categories = [` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L70: `        "high card",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L71: `        "one pair",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L72: `        "two pair",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L73: `        "three of a kind",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L74: `        "straight",` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L79: `    ];` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.
- L80: `    for (i, h) in hands.iter().enumerate() {` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L81: `        println!("{}. {}: {}", i + 1, h.text, categories[h.category]);` — Supplies the concrete value, binding, branch, mutation, comparison, or call used in the answer and dependency analysis above.
- L82: `    }` — Establishes the loop, branch, helper, or expression boundary needed for the dependency ordering explained above.

## Minimization and language semantics

The final selected excerpt measures **947 tokens** with `metric/tokenizer.py` `tokenize`. The previous reviewed candidate measured 804 tokens. The contiguous original span L1–L82 costs 1120 tokens; the complete original source costs 1122 tokens. The broader span and full source are sufficient context alternatives but include statements not required by the answer.

Complete lines remain verbatim and in original order, without repeating source locations. Ordinary arithmetic, collection operations and standard-library contracts retain their documented semantics. User-defined behavior is established by selected operations and argument/field associations. Scope delimiters are retained where they separate relevant processing; indentation is not used as a scope guarantee in brace/end languages. No Task A program was compiled or executed. This is a minimized sufficient reviewed candidate, not a proof of global mathematical minimality.

Measured deletion alternatives identify the removed source dependency or boundary:

- Without L1: 941 tokens; removes `struct Hand {` from the dependency chain described above.
- Without L2: 940 tokens; removes `text: String,` from the dependency chain described above.
- Without L3: 940 tokens; removes `category: usize,` from the dependency chain described above.
- Without L4: 937 tokens; removes `key: Vec<usize>,` from the dependency chain described above.
- Without L5: 945 tokens; removes `}` from the dependency chain described above.
- Without L7: 930 tokens; removes `fn evaluate(text: &str) -> Hand {` from the dependency chain described above.
- Without L8: 926 tokens; removes `let ranks = b"23456789TJQKA";` from the dependency chain described above.
- Without L9: 931 tokens; removes `let bytes = text.as_bytes();` from the dependency chain described above.
- Without L10: 929 tokens; removes `let mut counts = [0; 15];` from the dependency chain described above.
- Without L11: 935 tokens; removes `let mut flush = true;` from the dependency chain described above.
- Without L12: 934 tokens; removes `for i in 0..5 {` from the dependency chain described above.
- Without L13: 903 tokens; removes `let rank = ranks.iter().position(|&c| c == bytes[i * 3]).unwrap() + 2;` from the dependency chain described above.
- Without L14: 935 tokens; removes `counts[rank] += 1;` from the dependency chain described above.
- Without L15: 921 tokens; removes `if bytes[i * 3 + 1] != bytes[1] {` from the dependency chain described above.
- Without L16: 937 tokens; removes `flush = false;` from the dependency chain described above.
- Without L17: 943 tokens; removes `}` from the dependency chain described above.
- Without L18: 944 tokens; removes `}` from the dependency chain described above.
- Without L19: 899 tokens; removes `let mut key: Vec<usize> = (2..=14).filter(|&r| counts[r] > 0).rev().collect();` from the dependency chain described above.
- Without L20: 924 tokens; removes `let maximum = *counts.iter().max().unwrap();` from the dependency chain described above.
- Without L21: 915 tokens; removes `let pairs = counts.iter().filter(|&&c| c == 2).count();` from the dependency chain described above.
- Without L22: 890 tokens; removes `let wheel = key.len() == 5 && [14, 2, 3, 4, 5].iter().all(|&r| counts[r] > 0);` from the dependency chain described above.
- Without L23: 905 tokens; removes `let straight = key.len() == 5 && (key[0] - key[4] == 4 || wheel);` from the dependency chain described above.
- Without L24: 930 tokens; removes `let category = if straight && flush {` from the dependency chain described above.
- Without L25: 943 tokens; removes `8` from the dependency chain described above.
- Without L26: 932 tokens; removes `} else if maximum == 4 {` from the dependency chain described above.
- Without L27: 943 tokens; removes `7` from the dependency chain described above.
- Without L28: 924 tokens; removes `} else if maximum == 3 && pairs == 1 {` from the dependency chain described above.
- Without L29: 943 tokens; removes `6` from the dependency chain described above.
- Without L30: 936 tokens; removes `} else if flush {` from the dependency chain described above.
- Without L31: 943 tokens; removes `5` from the dependency chain described above.
- Without L32: 936 tokens; removes `} else if straight {` from the dependency chain described above.
- Without L33: 943 tokens; removes `4` from the dependency chain described above.
- Without L34: 932 tokens; removes `} else if maximum == 3 {` from the dependency chain described above.
- Without L36: 932 tokens; removes `} else if pairs == 2 {` from the dependency chain described above.
- Without L38: 932 tokens; removes `} else if pairs == 1 {` from the dependency chain described above.
- Without L40: 940 tokens; removes `} else {` from the dependency chain described above.
- Without L42: 943 tokens; removes `};` from the dependency chain described above.
- Without L43: 906 tokens; removes `key.sort_by(|a, b| counts[*b].cmp(&counts[*a]).then(b.cmp(a)));` from the dependency chain described above.
- Without L44: 936 tokens; removes `if wheel && straight {` from the dependency chain described above.
- Without L45: 926 tokens; removes `key = (1..=5).rev().collect();` from the dependency chain described above.
- Without L46: 944 tokens; removes `}` from the dependency chain described above.
- Without L47: 942 tokens; removes `Hand {` from the dependency chain described above.
- Without L48: 933 tokens; removes `text: text.to_string(),` from the dependency chain described above.
- Without L49: 942 tokens; removes `category,` from the dependency chain described above.
- Without L50: 942 tokens; removes `key,` from the dependency chain described above.
- Without L51: 944 tokens; removes `}` from the dependency chain described above.
- Without L52: 945 tokens; removes `}` from the dependency chain described above.
- Without L55: 930 tokens; removes `let mut hands: Vec<Hand> = [` from the dependency chain described above.
- Without L57: 928 tokens; removes `"4D AH 3C 5S 2H",` from the dependency chain described above.
- Without L60: 927 tokens; removes `"3H 6C 4S 2D 5C",` from the dependency chain described above.
- Without L64: 944 tokens; removes `]` from the dependency chain described above.
- Without L65: 941 tokens; removes `.iter()` from the dependency chain described above.
- Without L66: 933 tokens; removes `.map(|s| evaluate(s))` from the dependency chain described above.
- Without L67: 940 tokens; removes `.collect();` from the dependency chain described above.
- Without L68: 904 tokens; removes `hands.sort_by(|a, b| b.category.cmp(&a.category).then(b.key.cmp(&a.key)));` from the dependency chain described above.
- Without L69: 938 tokens; removes `let categories = [` from the dependency chain described above.
- Without L70: 938 tokens; removes `"high card",` from the dependency chain described above.
- Without L71: 938 tokens; removes `"one pair",` from the dependency chain described above.
- Without L72: 938 tokens; removes `"two pair",` from the dependency chain described above.
- Without L73: 934 tokens; removes `"three of a kind",` from the dependency chain described above.
- Without L74: 940 tokens; removes `"straight",` from the dependency chain described above.
- Without L79: 943 tokens; removes `];` from the dependency chain described above.
- Without L80: 923 tokens; removes `for (i, h) in hands.iter().enumerate() {` from the dependency chain described above.
- Without L81: 909 tokens; removes `println!("{}. {}: {}", i + 1, h.text, categories[h.category]);` from the dependency chain described above.
- Without L82: 944 tokens; removes `}` from the dependency chain described above.
