use crate::protocol;
pub struct Item {
    pub plus: bool,
    pub character: u8,
    pub argument: Option<String>
}
pub fn items(mode: &str, arguments: &[String]) -> Vec<Item> {
    let mut plus = true;
    let mut cursor = 0;
    let mut result = Vec::new();
    for character in mode.bytes() {
        if character == b'+' || character == b'-' {
            plus = character == b'+';
            continue;
        }
        let take = b"ovbk".contains(&character) || (character == b'l' && plus);
        let mut argument = if take && cursor < arguments.len() {
            let a = arguments[cursor].clone();
            cursor += 1;
            Some(a)
        } else {
            None
        };
        if character == b'k' && !plus {
            argument = Some("*".to_owned());
        }
        if character == b'l' && plus {
            argument = argument.filter(|a| protocol::digits(a) && a.len() <= 4 && a.parse::<usize>().unwrap() >= 1);
        }
        result.push(Item {
            plus,
            character,
            argument
        });
    }
    result
}
pub fn changes(changes: &[Item]) -> String {
    let mut result = String::new();
    let mut previous = None;
    for change in changes {
        if previous != Some(change.plus) {
            result.push(if change.plus {
                '+'
            } else {
                '-'
            });
            previous = Some(change.plus);
        }
        result.push(change.character as char);
    }
    for change in changes {
        if let Some(argument) = &change.argument {
            result.push(' ');
            result.push_str(argument);
        }
    }
    result
}
