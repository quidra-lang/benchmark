from decimal import Decimal, ROUND_HALF_UP

words = "we planted beans and carrots in the garden behind our old house".split(" ")
average = Decimal(sum(map(len, words))) / len(words)
print(f"words: {len(words)}")
print(f"longest: {max(words, key=len)}")
print(f"shortest: {min(words, key=len)}")
print(f"average length: {average.quantize(Decimal('0.01'), rounding=ROUND_HALF_UP)}")
