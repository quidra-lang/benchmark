import Foundation


var cache = [Character](), hits = 0, misses = 0
for key in "BACBDABEADDCAEB" {
    var status: String
    if let index = cache.firstIndex(of: key) {
        hits += 1
        status = "hit"
        cache.remove(at: index)
    } else {
        misses += 1
        status = "miss"
        if cache.count == 3 { status += ", evict \(cache.removeLast())" }
    }
    cache.insert(key, at: 0)
    print("\(key): \(status) [\(cache.map(String.init).joined(separator: " "))]")
}
print("hits: \(hits) misses: \(misses)")
