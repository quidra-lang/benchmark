import Foundation

let paragraph = "Good software is written for people first and for machines second. A clear program explains its purpose " +
    "through careful names, small functions and honest tests. When a team agrees on shared rules for " +
    "internationalization, documentation and code review, every newcomer can read the code quickly, change it " +
    "safely and ship new improvements with confidence instead of fear, week after week."
var lines = [[String]](), current = [String](), letters = 0
for raw in paragraph.split(separator: " ") {
    let word = String(raw)
    if !current.isEmpty && letters + current.count + word.count > 30 {
        lines.append(current)
        current = []
        letters = 0
    }
    current.append(word)
    letters += word.count
}
if !current.isEmpty { lines.append(current) }
for (i,words) in lines.enumerated() {
    var text = ""
    if i == lines.count - 1 || words.count == 1 {
        text = words.joined(separator: " ").padding(toLength: 30, withPad: " ", startingAt: 0)
    } else {
        let spaces = 30 - words.reduce(0) { $0 + $1.count }, gaps = words.count - 1
        text = words[0]
        for j in 1..<words.count {
            text += String(repeating: " ", count: spaces / gaps + (j - 1 < spaces % gaps ? 1 : 0))
            text += words[j]
        }
    }
    print("|\(text)|")
}
