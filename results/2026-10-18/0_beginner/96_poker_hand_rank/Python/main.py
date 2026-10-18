from collections import Counter

hands = [
    "9C 9D 5H QH 2C", "4D AH 3C 5S 2H", "KS 8S 2S JS 6S", "7H 7D KC 7S KD",
    "3H 6C 4S 2D 5C", "JD TC 4H 8C AS", "QC 6D QS 3S 6H", "9H KH 9S 8H 3D",
]
categories = ["high card", "one pair", "two pair", "three of a kind", "straight",
              "flush", "full house", "four of a kind", "straight flush"]
ranked = []
for hand in hands:
    cards = hand.split()
    counts = Counter("23456789TJQKA".index(card[0]) + 2 for card in cards)
    ranks = sorted(counts)
    wheel = ranks == [2, 3, 4, 5, 14]
    straight = len(ranks) == 5 and (ranks[-1] - ranks[0] == 4 or wheel)
    flush = len({card[1] for card in cards}) == 1
    pattern = sorted(counts.values(), reverse=True)
    if straight and flush:
        strength = 8
    elif pattern[0] == 4:
        strength = 7
    elif pattern == [3, 2]:
        strength = 6
    elif flush:
        strength = 5
    elif straight:
        strength = 4
    elif pattern[0] == 3:
        strength = 3
    elif pattern == [2, 2, 1]:
        strength = 2
    elif pattern[0] == 2:
        strength = 1
    else:
        strength = 0
    sequence = sorted(counts, key=lambda rank: (counts[rank], rank), reverse=True)
    if wheel and straight:
        sequence = [5, 4, 3, 2, 1]
    ranked.append((strength, sequence, hand))
ranked.sort(key=lambda record: (record[0], record[1]), reverse=True)
for position, (strength, _, hand) in enumerate(ranked, 1):
    print(f"{position}. {hand}: {categories[strength]}")
