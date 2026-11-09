import Foundation

struct ModeItem {
    let sign: Character
    let character: Character
    let argument: String?
}

func channelItems(_ mode: String, arguments: [String]) -> [ModeItem] {
    var items: [ModeItem] = [], sign: Character = "+", position = 0
    for character in mode {
        if character == "+" || character == "-" {
            sign = character
            continue
        }
        var argument: String?
        if "ovbk".contains(character) || (character == "l" && sign == "+") {
            if position < arguments.count {
                argument = arguments[position]
                position += 1
            }
        }
        if character == "k" && sign == "-" {
            argument = "*"
        } else if character == "l" && sign == "+" {
            if let value = argument, digits(value), value.count <= 4, Int(value)! >= 1 {
                argument = value
            } else {
                argument = nil
            }
        }
        items.append(ModeItem(sign: sign, character: character, argument: argument))
    }
    return items
}

func changeString(_ changes: [ModeItem]) -> String {
    var mode = "", arguments: [String] = [], previous: Character?
    for change in changes {
        if previous != change.sign {
            mode.append(change.sign)
            previous = change.sign
        }
        mode.append(change.character)
        if let argument = change.argument { arguments.append(argument) }
    }
    return mode + arguments.map { " " + $0 }.joined()
}
