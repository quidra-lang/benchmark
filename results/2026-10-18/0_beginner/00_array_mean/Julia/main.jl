using Printf

numbers = [48, 73, 56, 91, 35, 62, 84]
mean = sum(numbers) / length(numbers)
@printf("%.2f\n", mean)
