from hashing import digest, merkle_root
from transactions import parse_transaction


class Block:
    def __init__(self, height, previous, merkle, timestamp, difficulty, nonce, transactions):
        self.height = height
        self.previous = previous
        self.merkle = merkle
        self.timestamp = timestamp
        self.difficulty = difficulty
        self.nonce = nonce
        self.transactions = transactions
        self.hash = digest(header_text(height, previous, merkle, timestamp, difficulty, nonce))

    def size(self):
        return sum(transaction.size for transaction in self.transactions[1:])

    def txids(self):
        return [transaction.txid for transaction in self.transactions]


def header_text(height, previous, merkle, timestamp, difficulty, nonce):
    return f"{height}|{previous}|{merkle}|{timestamp}|{difficulty}|{nonce}"


def meets_difficulty(block_hash, difficulty):
    return block_hash.startswith("0" * difficulty)


def parse_block_event(fields, texts):
    height, previous, merkle, timestamp, difficulty, nonce = fields[3:9]
    transactions = [parse_transaction(text) for text in texts]
    return Block(
        int(height), previous, merkle, int(timestamp), int(difficulty), int(nonce), transactions
    )


def mine_block(height, previous, transactions, timestamp, difficulty):
    merkle = merkle_root([transaction.txid for transaction in transactions])
    nonce = 0
    while not meets_difficulty(
        digest(header_text(height, previous, merkle, timestamp, difficulty, nonce)), difficulty
    ):
        nonce += 1
    return Block(height, previous, merkle, timestamp, difficulty, nonce, transactions)


def context_free_error(block, max_size):
    if not meets_difficulty(block.hash, block.difficulty):
        return "bad-pow"
    if merkle_root(block.txids()) != block.merkle:
        return "bad-merkle"
    first = block.transactions[0]
    if not first.is_coinbase() or first.coinbase_height != block.height:
        return "bad-structure"
    if any(transaction.is_coinbase() for transaction in block.transactions[1:]):
        return "bad-structure"
    if block.size() > max_size:
        return "too-large"
    return None
