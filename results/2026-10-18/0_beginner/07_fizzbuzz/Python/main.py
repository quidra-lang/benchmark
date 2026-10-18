for n in range(1, 31):
    text = ("Fizz" if n % 3 == 0 else "") + ("Buzz" if n % 5 == 0 else "")
    print(text or n)
