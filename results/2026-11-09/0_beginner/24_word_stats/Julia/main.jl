using Printf

words = split("we planted beans and carrots in the garden behind our old house")
println("words: ", length(words))
println("longest: ", argmax(length, words))
println("shortest: ", argmin(length, words))
total = sum(length, words)
@printf("average length: %.2f\n", total / length(words))
