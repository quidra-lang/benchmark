import Foundation
struct Bid {
    let id: Int, bidder: Int, bundle: Int, amount: Int, xor: Bool
}
struct BidLine {
    let name: String, language: String, bids: [String]
}
struct Auction {
    let name: String, offered: [String]
    var lines: [BidLine] = []
}
struct Participant {
    let name: String, value: Int, bid: Int
}
struct Group {
    let lot: Bool, name: String, args: [String]
    var people: [Participant] = []
}
struct Params {
    let run: [String], bundle: Int, bids: Int, core: Int, increment: Int, cap: Int
    let seed: Int, english: Int, dutchStart: Int, dutchDecrement: Int
}
struct Input {
    let names: [String], reserves: [Int], auctions: [Auction], groups: [Group], params: Params
    static func lines(_ file: String) -> [[String]] {
        try! String(contentsOfFile: "input/" + file, encoding: .ascii).split(separator: "\n").map {
            $0.split(separator: " ").map(String.init)
        }
    }
    static func read() -> Self {
        let items = lines("items.txt")
        var auctions: [Auction] = [], groups: [Group] = []
        for a in lines("bids.txt") {
            if a[0] == "auction" {
                auctions.append(Auction(name: a[1], offered: Array(a.dropFirst(2))))
            }
            else {
                auctions[auctions.count - 1].lines.append(BidLine(name: a[1], language: a[2], bids: Array(a.dropFirst(3))))
            }
        }
        for a in lines("single_item.txt") {
            if a[0] == "lot" || a[0] == "slots" {
                groups.append(Group(lot: a[0] == "lot", name: a[1], args: Array(a.dropFirst(2))))
            }
            else {
                groups[groups.count - 1].people.append(Participant(name: a[1], value: Int(a[2])!, bid: Int(a[3])!))
            }
        }
        let a = lines("params.txt")
        let params = Params(run: Array(a[0].dropFirst()), bundle: Int(a[1][1])!, bids: Int(a[2][1])!, core: Int(a[3][1])!, increment: Int(a[4][1])!, cap: Int(a[5][1])!, seed: Int(a[6][1])!, english: Int(a[7][1])!, dutchStart: Int(a[8][1])!, dutchDecrement: Int(a[9][1])!)
        return Input(names: items.map {
            $0[0]
        }, reserves: items.map {
            Int($0[1])!
        }, auctions: auctions, groups: groups, params: params)
    }
}
