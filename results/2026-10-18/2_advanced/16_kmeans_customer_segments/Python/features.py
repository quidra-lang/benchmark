from math import sqrt

from transactions import orders_by_customer


FEATURE_NAMES = ("recency", "frequency", "monetary", "basket", "categories", "tenure")
SQRT_FEATURES = (False, True, True, True, False, False)


class Customer:
    def __init__(self, customer_id, orders, day):
        self.id = customer_id
        self.orders = orders
        self.recency = day - max(order.day for order in orders)
        self.frequency = len(orders)
        self.spend = sum(order.net for order in orders)
        self.monetary = self.spend / 100
        self.basket = self.monetary / self.frequency
        self.category_spend = {}
        for order in orders:
            for row in order.rows:
                spend = self.category_spend.get(row.category, 0)
                self.category_spend[row.category] = spend + row.amount
        self.categories = sum(1 for spend in self.category_spend.values() if spend > 0)
        self.tenure = day - min(order.day for order in orders)

    def values(self):
        return [
            float(self.recency), float(self.frequency), self.monetary,
            self.basket, float(self.categories), float(self.tenure),
        ]

    def transformed(self):
        return [
            sqrt(value) if root else value for value, root in zip(self.values(), SQRT_FEATURES)
        ]


def eligible_customers(orders, day):
    grouped = orders_by_customer([order for order in orders if order.is_valid()])
    return [Customer(customer_id, grouped[customer_id], day) for customer_id in sorted(grouped)]


def ordered_sum(values):
    total = 0.0
    for value in values:
        total += value
    return total


def mean(values):
    return ordered_sum(values) / len(values)


def sample_sd(values):
    average = mean(values)
    total = 0.0
    for value in values:
        difference = value - average
        total += difference * difference
    return sqrt(total / (len(values) - 1))


def standardization(rows):
    columns = [[row[feature] for row in rows] for feature in range(len(FEATURE_NAMES))]
    return [mean(column) for column in columns], [sample_sd(column) for column in columns]


def standardize(values, means, sds):
    return [
        0.0 if sd == 0 else (value - average) / sd
        for value, average, sd in zip(values, means, sds)
    ]


def correlation(points, first, second):
    total = 0.0
    for point in points:
        total += point[first] * point[second]
    return total / (len(points) - 1)
