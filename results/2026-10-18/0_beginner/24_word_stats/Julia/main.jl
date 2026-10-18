using Printf
function main()
    words = split("we planted beans and carrots in the garden behind our old house")
    longest = shortest = words[1]
    total = 0
    for word in words
        total += length(word)
        if length(word) > length(longest)
            longest = word
        end
        if length(word) < length(shortest)
            shortest = word
        end
    end
    average = total / length(words)
    println("words: ", length(words))
    println("longest: ", longest)
    println("shortest: ", shortest)
    @printf("average length: %.2f\n", floor(average * 100 + 0.5) / 100)
end
main()
