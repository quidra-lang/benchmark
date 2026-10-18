phrases = ["Never odd or even", "Race a car", "Was it a car or a cat I saw?", "Hello, World!", "Step on no pets.", "No lemon, no melon"]
for phrase in phrases
    clean = filter(c -> 'a' <= c <= 'z', lowercase(phrase))
    println(phrase, " -> ", clean == reverse(clean) ? "yes" : "no")
end
