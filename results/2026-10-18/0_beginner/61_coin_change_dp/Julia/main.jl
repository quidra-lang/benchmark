function main()
    coins = [1,5,6,9]
    for amount in [8,11,15,22,33,40]
        minimums = fill(amount+1,amount+1)
        minimums[1] = 0
        for value in 1:amount, coin in coins
            if coin <= value
                minimums[value+1] = min(minimums[value+1],minimums[value-coin+1]+1)
            end
        end
        ways = zeros(Int,amount+1)
        ways[1] = 1
        for coin in coins, value in coin:amount
            ways[value+1] += ways[value-coin+1]
        end
        remaining, greedy = amount, 0
        for coin in reverse(coins)
            greedy += div(remaining,coin)
            remaining %= coin
        end
        println(amount,": min=",minimums[end]," greedy=",greedy," ways=",ways[end])
    end
end
main()
