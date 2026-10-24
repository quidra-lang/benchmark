MAX_DIFFICULTY = 2
MEDIAN_SPAN = 3


class BlockRecord:
    def __init__(self, block, parent, utxo, transaction_fees, source):
        self.block = block
        self.parent = parent
        self.utxo = utxo
        self.transaction_fees = transaction_fees
        self.fees = sum(transaction_fees)
        self.source = source
        self.height = block.height
        self.hash = block.hash
        if parent is None:
            self.cumulative_work = 1
        else:
            self.cumulative_work = parent.cumulative_work + 16 ** block.difficulty


def reward(height, initial, interval):
    amount = initial
    for _ in range(height // interval):
        amount //= 2
    return amount


def ancestor(record, height):
    while record.height > height:
        record = record.parent
    return record


def chain_to(record):
    records = []
    while record is not None:
        records.append(record)
        record = record.parent
    records.reverse()
    return records


def fork_point(first, second):
    height = min(first.height, second.height)
    first = ancestor(first, height)
    second = ancestor(second, height)
    while first is not second:
        first = first.parent
        second = second.parent
    return first


def median_time(record):
    times = []
    while record is not None and len(times) < MEDIAN_SPAN:
        times.append(record.block.timestamp)
        record = record.parent
    times.sort()
    return times[(len(times) - 1) // 2]


def required_difficulty(parent, initial, interval, target):
    height = parent.height + 1
    difficulty = parent.block.difficulty
    if height == 1:
        return initial
    if height % interval != 0:
        return difficulty
    first = ancestor(parent, height - interval)
    span = parent.block.timestamp - first.block.timestamp
    expected = target * (interval - 1)
    if 2 * span < expected:
        return min(difficulty + 1, MAX_DIFFICULTY)
    if span > 2 * expected:
        return max(difficulty - 1, 0)
    return difficulty
