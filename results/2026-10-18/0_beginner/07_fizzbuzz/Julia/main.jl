for n in 1:30
    if n % 15 == 0
        println("FizzBuzz")
    elseif n % 3 == 0
        println("Fizz")
    elseif n % 5 == 0
        println("Buzz")
    else
        println(n)
    end
end
