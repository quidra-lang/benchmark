import Foundation

func decode(_ text: String) -> String {
    text.replacingOccurrences(of: "+", with: " ").removingPercentEncoding!
}
let queries = ["name=Alice+Smith&age=30&city=New%20York",
    "q=c%2B%2B+tutorial&page=2&sort=desc&page=3",
    "msg=50%25+off%21&debug&lang=en&ref=&lang=ja",
    "redirect=https%3a%2f%2fexample.com%2Fhome&token=abc==&item10=pen&item2=fish%26chips"]
for (index,query) in queries.enumerated() {
    var values = [String:[String]]()
    for item in query.split(separator: "&") {
        let parts = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        let key = decode(String(parts[0]))
        let value = decode(parts.count > 1 ? String(parts[1]) : "")
        values[key, default: []].append(value)
    }
    print("query \(index + 1):")
    for key in values.keys.sorted() {
        let quoted = values[key]!.map { "\"\($0)\"" }.joined(separator: ", ")
        print("  \(key): \(quoted)")
    }
}
