"""Fu items, score limits and integer-rounded payments."""

from tiles import block, yaochuu


def triplet_fu(kinds, concealed, kan):
    if kan:
        kind, value = ("closed_kan", 16) if concealed else ("open_kan", 8)
    else:
        kind, value = ("closed_triplet", 4) if concealed else ("open_triplet", 2)
    return kind + " " + block(kinds), value * (2 if yaochuu(kinds[0]) else 1)


def fu_breakdown(form, pair, triplets, wait, closed, method, seat, round_wind, pinfu):
    if form == "chiitoitsu":
        return [("chiitoitsu", 25)], 25, 25
    items = [("base", 20)]
    if closed and method == "ron":
        items.append(("closed_ron", 10))
    if method == "tsumo" and not pinfu:
        items.append(("tsumo", 2))
    pair_value = 2 * ((pair >= 31) + (pair == seat) + (pair == round_wind))
    if pair_value:
        items.append(("pair " + block((pair, pair)), pair_value))
    for kinds, concealed, kan in triplets:
        items.append(triplet_fu(kinds, concealed, kan))
    if wait in ("kanchan", "penchan", "tanki"):
        items.append(("wait " + wait, 2))
    total = sum(value for _, value in items)
    if not closed and total == 20:
        items.append(("open_pinfu", 10))
        total += 10
    return items, total, (total + 9) // 10 * 10


def limit(han, fu, rules):
    if han >= 13 and rules["kazoe_yakuman"]:
        return "kazoe_yakuman", 8000
    if han >= 11:
        return "sanbaiman", 6000
    if han >= 8:
        return "baiman", 4000
    if han >= 6:
        return "haneman", 3000
    base = fu * 2 ** (han + 2)
    if han == 5 or base >= 2000 or rules["kiriage"] and base == 1920:
        return "mangan", 2000
    return "none", base


def round_hundred(value):
    return (value + 99) // 100 * 100


def payments(base, dealer, method):
    if method == "ron":
        ron = round_hundred(base * (6 if dealer else 4))
        return ron, 0, 0, ron
    if dealer:
        nondealer = round_hundred(base * 2)
        return 0, 0, nondealer, nondealer * 3
    dealer_payment = round_hundred(base * 2)
    nondealer = round_hundred(base)
    return 0, dealer_payment, nondealer, dealer_payment + 2 * nondealer
