import Foundation

let ids = [
    "user_name", "maxRetryCount", "ShoppingCartItem", "background-color", "get_last_login_time",
    "isEmailAddressValid",
]
for id in ids {
    let words = id.replacingOccurrences(of: "[_-]|(?=[A-Z])", with: " ", options: .regularExpression)
        .split(separator: " ").map { $0.lowercased() }
    let capitals = words.map { $0.prefix(1).uppercased() + $0.dropFirst() }
    let camel = words[0] + capitals.dropFirst().joined()
    print("\(id): snake=\(words.joined(separator: "_")), camel=\(camel), pascal=\(capitals.joined()), kebab=\(words.joined(separator: "-"))")
}
