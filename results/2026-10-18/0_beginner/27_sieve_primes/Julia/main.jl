function main()
    limit = 200
    prime = trues(limit+1)
    prime[1:2] .= false
    for p = 2:limit
        if prime[p+1]
            for multiple = (2*p):p:limit
                prime[multiple+1] = false
            end
        end
    end
    primes = [n for n = 2:limit if prime[n+1]]
    println("count: ", length(primes))
    for first = 1:10:length(primes)
        println(join(primes[first:min(first+9, end)], " "))
    end
end

main()
