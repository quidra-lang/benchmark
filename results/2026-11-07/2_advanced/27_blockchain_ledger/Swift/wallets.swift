import Foundation
struct Wallet {
    let name: String;
    let secret: String;
    let address: String
    init(_ name: String, _ secret: String) {
        self.name = name;
        self.secret = secret;
        address = String(digest("addr:"+secret).prefix(16))
    }
}
func sign(_ secret: String, _ index: Int, _ body: String) -> String {
    String(digest("\(secret):\(index):\(body)").prefix(16))
}
func readWallets() throws -> [Wallet] {
    try String(contentsOfFile: "input/wallets.txt", encoding: .utf8).split(separator: "\n").map {
        let p = $0.split(separator: " ").map(String.init);
        return Wallet(p[0], p[1])
    }
}
