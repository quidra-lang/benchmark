using Printf

for radius in [3, 7, 12, 25, 41]
    pi_value = 3.141592653589793
    area = pi_value * radius * radius
    circumference = 2 * pi_value * radius
    @printf("r=%d area=%.3f circumference=%.3f\n", radius, area, circumference)
end
