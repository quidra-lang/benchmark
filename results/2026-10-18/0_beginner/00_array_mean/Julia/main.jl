using Printf

numbers = [48, 73, 56, 91, 35, 62, 84]
mean = sum(numbers) / length(numbers)
rounded = floor(mean * 100 + 0.5) / 100
@printf("%.2f\n", rounded)
