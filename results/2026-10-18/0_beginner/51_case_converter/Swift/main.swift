import Foundation


for id in ["user_name","maxRetryCount","ShoppingCartItem","background-color","get_last_login_time","isEmailAddressValid"] {
    var words = [String](), current = ""
    for ch in id {
        if ch == "_" || ch == "-" || (ch >= "A" && ch <= "Z") { if !current.isEmpty { words.append(current.lowercased()); current = "" } }
        if ch != "_" && ch != "-" { current.append(ch) }
    }
    if !current.isEmpty { words.append(current.lowercased()) }
    let capitals = words.map { $0.prefix(1).uppercased() + $0.dropFirst() }
    let camel = words[0] + capitals.dropFirst().joined()
    print("\(id): snake=\(words.joined(separator: "_")), camel=\(camel), pascal=\(capitals.joined()), kebab=\(words.joined(separator: "-"))")
}
