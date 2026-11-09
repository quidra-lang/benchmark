function describe_hand(original)
    cards = split(original)
    alphabet = "23456789TJQKA"
    ranks = [findfirst(==(card[1]), alphabet)+1 for card in cards]
    frequencies = [count(==(rank), ranks) for rank = 2:14]
    distinct = [rank for rank = 2:14 if frequencies[rank-1] > 0]
    wheel = distinct == [2, 3, 4, 5, 14]
    straight = length(distinct) == 5 && (distinct[end]-distinct[1] == 4 || wheel)
    flush = all(card[2] == cards[1][2] for card in cards)
    counts = sort([frequencies[rank-1] for rank in distinct]; rev = true)
    if straight && flush
        strength = 9
    elseif counts[1] == 4
        strength = 8
    elseif counts == [3, 2]
        strength = 7
    elseif flush
        strength = 6
    elseif straight
        strength = 5
    elseif counts[1] == 3
        strength = 4
    elseif counts == [2, 2, 1]
        strength = 3
    elseif counts[1] == 2
        strength = 2
    else
        strength = 1
    end
    categories = [
        "high card",
        "one pair",
        "two pair",
        "three of a kind",
        "straight",
        "flush",
        "full house",
        "four of a kind",
        "straight flush",
    ]
    sequence =
        wheel && straight ? [5, 4, 3, 2, 1] :
        sort(distinct; by = rank -> (-frequencies[rank-1], -rank))
    return (
        original = original,
        strength = strength,
        sequence = sequence,
        category = categories[strength],
    )
end

hands = describe_hand.([
    "9C 9D 5H QH 2C",
    "4D AH 3C 5S 2H",
    "KS 8S 2S JS 6S",
    "7H 7D KC 7S KD",
    "3H 6C 4S 2D 5C",
    "JD TC 4H 8C AS",
    "QC 6D QS 3S 6H",
    "9H KH 9S 8H 3D",
])
sort!(hands; by = hand -> (-hand.strength, Tuple(-rank for rank in hand.sequence)))
for (position, hand) in enumerate(hands)
    println(position, ". ", hand.original, ": ", hand.category)
end
