import Foundation

func maskMatches(_ mask: String, _ value: String) -> Bool {
    let pattern = Array(ircFold(mask).utf8), text = Array(ircFold(value).utf8)
    var p = 0, t = 0, star: Int? = nil, restart = 0
    while t < text.count {
        if p < pattern.count && pattern[p] == 42 {
            star = p
            p += 1
            restart = t
        } else if p < pattern.count && (pattern[p] == 63 || pattern[p] == text[t]) {
            p += 1
            t += 1
        } else if let saved = star {
            restart += 1
            t = restart
            p = saved + 1
        } else {
            return false
        }
    }
    while p < pattern.count && pattern[p] == 42 { p += 1 }
    return p == pattern.count
}

func normalizeMask(_ argument: String) -> String {
    if argument.contains("!") && argument.contains("@") { return argument }
    if argument.contains("@") { return "*!" + argument }
    if argument.contains("!") { return argument + "@*" }
    if argument.contains(".") { return "*!*@" + argument }
    return argument + "!*@*"
}
