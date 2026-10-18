fn main() {
    let coins = [1, 5, 6, 9];
    let mut minimum = [0_i32; 41];
    let mut ways = [0; 41];
    ways[0] = 1;
    for amount in 1..=40 {
        minimum[amount] = 1000;
        for coin in coins {
            if coin <= amount {
                minimum[amount] = minimum[amount].min(minimum[amount - coin] + 1);
            }
        }
    }
    for coin in coins {
        for amount in coin..=40 {
            ways[amount] += ways[amount - coin];
        }
    }
    for target in [8, 11, 15, 22, 33, 40] {
        let (mut remaining, mut greedy) = (target, 0);
        for coin in coins.iter().rev() {
            greedy += remaining / coin;
            remaining %= coin;
        }
        println!("{}: min={} greedy={} ways={}", target, minimum[target], greedy, ways[target]);
    }
}
