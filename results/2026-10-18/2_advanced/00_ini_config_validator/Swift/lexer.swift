import Foundation

// This byte cannot occur in the input and preserves an escaped dollar until expansion.
let literalDollar: UInt8 = 1

struct Segment {
    var text: String
    let quoted: Bool
}

struct LogicalLine {
    let number: Int
    var segments: [Segment] = []
    var error: (code: String, message: String)?
}

func logicalLines(_ text: String) -> [LogicalLine] {
    let physical = fileLines(text)
    var lines: [LogicalLine] = []
    var index = 0
    while index < physical.count {
        var line = LogicalLine(number: index + 1)
        var source = Array(physical[index].utf8)
        index += 1
        var position = 0
        var quoted = false
        var current: [UInt8] = []
        while position < source.count {
            let byte = source[position]
            if byte == 92 && position + 1 == source.count {
                source = Array(physical[index].utf8.drop(while: { $0 == 32 }))
                index += 1
                position = 0
            } else if quoted && byte == 92 {
                let next = source[position + 1]
                switch next {
                case 92, 34: current.append(next)
                case 110: current.append(10)
                case 116: current.append(9)
                case 36: current.append(literalDollar)
                default:
                    if line.error == nil {
                        line.error = ("E_ESCAPE", "invalid escape sequence \\" + asciiText([next]))
                    }
                }
                position += 2
            } else if byte == 34 {
                line.segments.append(Segment(text: asciiText(current), quoted: quoted))
                current = []
                quoted.toggle()
                position += 1
            } else if !quoted && (byte == 59 || byte == 35) {
                break
            } else {
                current.append(byte)
                position += 1
            }
        }
        if quoted && line.error == nil {
            line.error = ("E_UNTERMINATED", "unterminated string")
        }
        line.segments.append(Segment(text: asciiText(current), quoted: quoted))
        lines.append(line)
    }
    return lines
}
