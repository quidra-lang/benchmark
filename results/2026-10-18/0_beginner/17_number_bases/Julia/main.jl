for n in [0, 10, 255, 1000, 43981, 65535]
    hex = uppercase(string(n; base = 16))
    println("$n: bin=$(string(n; base = 2)) oct=$(string(n; base = 8)) hex=$hex")
end
