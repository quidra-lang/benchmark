from hashing import digest
from wallets import sign


class Transaction:
    def __init__(self, text, inputs, outputs, signatures, coinbase_height):
        self.text = text
        self.txid = digest(text)
        self.size = len(text)
        self.inputs = inputs
        self.outputs = outputs
        self.signatures = signatures
        self.coinbase_height = coinbase_height

    def is_coinbase(self):
        return self.coinbase_height is not None

    def body(self):
        return self.text[:self.text.index(";sig=")]

    def output_total(self):
        return sum(amount for _, amount in self.outputs)


class Coin:
    def __init__(self, address, amount, height, coinbase):
        self.address = address
        self.amount = amount
        self.height = height
        self.coinbase = coinbase

    def is_mature(self, height, maturity):
        return not self.coinbase or self.height == 0 or height >= self.height + maturity


def field_value(part):
    return part.partition("=")[2]


def parse_pair(text):
    key, amount = text.split(":")
    return key, int(amount)


def parse_transaction(text):
    parts = text.split(";")
    outputs = [parse_pair(item) for item in field_value(parts[1]).split(",")]
    if parts[0].startswith("cb="):
        return Transaction(text, [], outputs, [], int(field_value(parts[0])))
    inputs = [parse_pair(item) for item in field_value(parts[0]).split(",")]
    signatures = field_value(parts[2]).split(",")
    return Transaction(text, inputs, outputs, signatures, None)


def pairs_text(pairs):
    return ",".join(f"{key}:{number}" for key, number in pairs)


def create_transaction(inputs, outputs, secret):
    body = f"in={pairs_text(inputs)};out={pairs_text(outputs)}"
    signatures = [sign(secret, index, body) for index in range(len(inputs))]
    text = body + ";sig=" + ",".join(signatures)
    return Transaction(text, list(inputs), list(outputs), signatures, None)


def create_coinbase(height, outputs):
    text = f"cb={height};out={pairs_text(outputs)}"
    return Transaction(text, [], list(outputs), [], height)


def check_transaction(transaction, utxo, spent, height, owners, maturity):
    for address, amount in transaction.outputs:
        if address not in owners or amount == 0:
            return "bad-output", 0
    body = transaction.body()
    seen = set()
    total = 0
    for index, reference in enumerate(transaction.inputs):
        if reference in spent or reference in seen:
            return "double-spend", 0
        if reference not in utxo:
            return "missing-input", 0
        coin = utxo[reference]
        if not coin.is_mature(height, maturity):
            return "immature", 0
        if transaction.signatures[index] != sign(owners[coin.address].secret, index, body):
            return "bad-sig", 0
        seen.add(reference)
        total += coin.amount
    if total < transaction.output_total():
        return "overspend", 0
    return None, total - transaction.output_total()


def apply_transaction(utxo, transaction, height):
    for reference in transaction.inputs:
        del utxo[reference]
    for index, (address, amount) in enumerate(transaction.outputs):
        utxo[(transaction.txid, index)] = Coin(address, amount, height, transaction.is_coinbase())
