function main()
    state = 12345
    counts = zeros(Int, 13)
    for trial in 1:1000
        state = (state * 48271) % 2147483647
        first_die = state % 6 + 1
        state = (state * 48271) % 2147483647
        second_die = state % 6 + 1
        counts[first_die+second_die+1] += 1
    end
    best = 2
    for total in 2:12
        println(total, ": ", counts[total+1])
        if counts[total+1] > counts[best+1]
            best = total
        end
    end
    println("most frequent: ", best)
end
main()
