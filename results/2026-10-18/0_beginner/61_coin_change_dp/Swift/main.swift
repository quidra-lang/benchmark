import Foundation


let coins = [1, 5, 6, 9]
for amount in [8, 11, 15, 22, 33, 40] {
    var minimum = [Int](repeating: amount + 1, count: amount + 1)
    var ways = [Int](repeating: 0, count: amount + 1)
    minimum[0] = 0
    ways[0] = 1
    for value in 1...amount {
        for coin in coins where coin <= value {
            minimum[value] = min(minimum[value], minimum[value - coin] + 1)
        }
    }
    for coin in coins where coin <= amount {
        for value in coin...amount { ways[value] += ways[value - coin] }
    }
    var remaining = amount, greedy = 0
    for coin in coins.reversed() {
        while remaining >= coin {
            remaining -= coin
            greedy += 1
        }
    }
    print("\(amount): min=\(minimum[amount]) greedy=\(greedy) ways=\(ways[amount])")
}
