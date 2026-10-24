ranks = "A23456789TJQK"
deck = [rank + suit for suit in "SHDC" for rank in ranks]
state = 2026
for i in range(len(deck) - 1, 0, -1):
    state = state * 48271 % 2147483647
    j = state % (i + 1)
    deck[i], deck[j] = deck[j], deck[i]
for start in range(0, len(deck), 13):
    print(*deck[start:start + 13])
