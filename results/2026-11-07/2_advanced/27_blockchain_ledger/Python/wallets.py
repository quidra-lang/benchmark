from hashing import digest


ADDRESS_LENGTH = 16
SIGNATURE_LENGTH = 16


class Wallet:
    def __init__(self, name, secret):
        self.name = name
        self.secret = secret
        self.address = address_of(secret)


def address_of(secret):
    return digest("addr:" + secret)[:ADDRESS_LENGTH]


def sign(secret, index, body):
    return digest(f"{secret}:{index}:{body}")[:SIGNATURE_LENGTH]


def read_wallets(path):
    wallets = []
    with open(path) as handle:
        for line in handle.read().splitlines():
            name, secret = line.split()
            wallets.append(Wallet(name, secret))
    return wallets
