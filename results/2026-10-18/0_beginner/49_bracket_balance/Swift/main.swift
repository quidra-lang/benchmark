for text in ["(a + b) * [c - d]", "{x = [1, 2, (3 + 4)]}", "f(a[i] + g(b)}", "(1 + 2)) * 3", "if (a < b) { c = d[0]; }", "((a + b] * c", "[{(x * y) - z}"] {
    var stack = [Character](), error = -1
    let openings = Array("([{"), closings = Array(")]}")
    for (i,ch) in text.enumerated() {
        if openings.contains(ch) { stack.append(ch) }
        else if let close = closings.firstIndex(of: ch) {
            if stack.last != openings[close] {
                error = i
                break
            }
            stack.removeLast()
        }
    }
    if error < 0 && !stack.isEmpty { error = text.count }
    print(text + " -> " + (error < 0 ? "balanced" : "error at index \(error)"))
}
