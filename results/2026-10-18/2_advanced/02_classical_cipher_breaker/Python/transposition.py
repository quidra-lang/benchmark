def rail_number(position, rails):
    cycle = 2 * rails - 2
    offset = position % cycle
    return min(offset, cycle - offset)


def rail_order(length, rails):
    numbers = [rail_number(position, rails) for position in range(length)]
    return [
        position
        for rail in range(rails)
        for position in range(length)
        if numbers[position] == rail
    ]


def rail_fence_encrypt(text, rails):
    return "".join(text[position] for position in rail_order(len(text), rails))


def rail_fence_decrypt(text, rails):
    result = [""] * len(text)
    for index, position in enumerate(rail_order(len(text), rails)):
        result[position] = text[index]
    return "".join(result)


def column_ranks(key):
    order = sorted(range(len(key)), key=lambda column: (key[column], column))
    ranks = [0] * len(key)
    for rank, column in enumerate(order, 1):
        ranks[column] = rank
    return ranks


def rank_string(key):
    return "".join(str(rank) for rank in column_ranks(key))


def columns_by_rank(key):
    ranks = rank_string(key)
    return [ranks.index(str(rank)) for rank in range(1, len(ranks) + 1)]


def column_length(length, width, column):
    return length // width + (1 if column < length % width else 0)


def columnar_encrypt(text, key):
    width = len(key)
    return "".join(text[column::width] for column in columns_by_rank(key))


def columnar_decrypt(text, key):
    width = len(key)
    columns = [""] * width
    start = 0
    for column in columns_by_rank(key):
        end = start + column_length(len(text), width, column)
        columns[column] = text[start:end]
        start = end
    return "".join(columns[position % width][position // width] for position in range(len(text)))
