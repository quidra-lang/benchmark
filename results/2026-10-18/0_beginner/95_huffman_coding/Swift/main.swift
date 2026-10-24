class Node {
    let weight: Int, minimum: Int
    let symbol: Character?
    let left: Node?, right: Node?
    init(_ weight: Int, _ minimum: Int, _ symbol: Character?, _ left: Node? = nil, _ right: Node? = nil) {
        self.weight = weight
        self.minimum = minimum
        self.symbol = symbol
        self.left = left
        self.right = right
    }
}
func codes(_ node: Node, _ prefix: String, _ result: inout [Character:String]) {
    if let symbol = node.symbol { result[symbol] = prefix }
    else {
        codes(node.left!,prefix + "0",&result)
        codes(node.right!,prefix + "1",&result)
    }
}
let text = "she sells sea shells by the sea shore"
var frequencies = [Character:Int]()
for ch in text { frequencies[ch, default: 0] += 1 }
var trees = frequencies.map { ch,count in Node(count,Int(ch.asciiValue!),ch) }
while trees.count > 1 {
    trees.sort { $0.weight == $1.weight ? $0.minimum < $1.minimum : $0.weight < $1.weight }
    let left = trees.removeFirst(), right = trees.removeFirst()
    trees.append(Node(left.weight + right.weight,min(left.minimum,right.minimum),nil,left,right))
}
var mapping = [Character:String]()
codes(trees[0],"",&mapping)
for ch in frequencies.keys.sorted() {
    let code = mapping[ch]!, count = frequencies[ch]!
    print("'\(ch)' freq=\(count) code=\(code)")
}
print("encoded bits: \(frequencies.reduce(0) { $0 + $1.value * mapping[$1.key]!.count })")
print("fixed 8-bit: \(text.count * 8)")
