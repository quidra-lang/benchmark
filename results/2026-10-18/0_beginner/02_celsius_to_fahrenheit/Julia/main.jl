using Printf

for celsius in [-40, -15, -3, 0, 22, 37, 100]
    fahrenheit = celsius * 9 / 5 + 32
    rounded = copysign(floor(abs(fahrenheit) * 10 + 0.5) / 10, fahrenheit)
    @printf("%d C = %.1f F\n", celsius, rounded)
end
