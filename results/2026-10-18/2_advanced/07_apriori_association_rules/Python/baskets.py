class Product:
    def __init__(self, name, category, price):
        self.name = name
        self.category = category
        self.price = price


class Transaction:
    def __init__(self, tid, customer, day):
        self.tid = tid
        self.customer = customer
        self.day = day
        self.counts = {}

    def add(self, product):
        duplicate = product in self.counts
        self.counts[product] = self.counts.get(product, 0) + 1
        return duplicate

    def is_empty(self):
        return not self.counts

    def products(self):
        return frozenset(self.counts)

    def units(self):
        return sum(self.counts.values())


def read_records(path):
    with open(path) as handle:
        lines = handle.read().splitlines()
    return [line.split(",") for line in lines[1:]]


def extended_basket(products, taxonomy):
    return products | {taxonomy[product] for product in products}


def contains(items, itemset):
    return items.issuperset(itemset)
