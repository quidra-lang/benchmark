for n = 1, 30 do
    if n % 15 == 0 then
        io.write("FizzBuzz\n")
    elseif n % 3 == 0 then
        io.write("Fizz\n")
    elseif n % 5 == 0 then
        io.write("Buzz\n")
    else
        io.write(string.format("%d\n", n))
    end
end
