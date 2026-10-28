import Foundation
func digest(_ text: String) -> String {
    [(1000003, 11), (1500007, 23), (2750159, 37), (4194301, 53)].map {
        base, initial in
        var h = initial
        for c in text.utf8.map(Int.init)+[text.utf8.count, 0, 0] {
            h = (h*base+c)%2147483647
        }
        return String(format: "%08x", h)
    }.joined()
}
func merkleRoot(_ hashes: [String]) -> String {
    var level = hashes
    while level.count>1 {
        if level.count%2 == 1 {
            level.append(level.last!)
        }
        level = stride(from: 0, to: level.count, by: 2).map {
            digest(level[$0]+level[$0+1])
        }
    }
    return level[0]
}
func short(_ s: String) -> String {
    String(s.prefix(8))
}
