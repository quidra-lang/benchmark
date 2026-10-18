class Params:
    def __init__(self, values):
        self.reference_day = int(values["REFERENCE_DAY"][0])
        self.snapshot_day = int(values["SNAPSHOT_DAY"][0])
        self.outcome_days = int(values["OUTCOME_DAYS"][0])
        self.k_min = int(values["K_RANGE"][0])
        self.k_max = int(values["K_RANGE"][1])
        self.methods = values["METHODS"]
        self.restarts = int(values["RESTARTS"][0])
        self.max_iterations = int(values["MAX_ITERATIONS"][0])
        self.seed = int(values["SEED"][0])
        self.subsamples = int(values["SUBSAMPLES"][0])
        self.subsample_percent = int(values["SUBSAMPLE_PERCENT"][0])
        self.outlier_sd = float(values["OUTLIER_SD"][0])
        self.overdue_factor = int(values["OVERDUE_FACTOR"][0])
        self.order_bins = [int(value) for value in values["ORDER_BINS"]]
        self.top_categories = int(values["TOP_CATEGORIES"][0])
        self.top_customers = int(values["TOP_CUSTOMERS"][0])
        self.period_days = int(values["PERIOD_DAYS"][0])
        self.periods = int(values["PERIODS"][0])


class Row:
    def __init__(self, line):
        customer, day, order_id, category, amount = line.split(",")
        self.customer = customer
        self.day = int(day)
        self.order_id = order_id
        self.category = category
        self.amount = int(amount)


class TransactionData:
    def __init__(self):
        self.row_count = 0
        self.duplicates = 0
        self.free = 0
        self.valid_rows = []
        self.customers = set()


class Order:
    def __init__(self, row):
        self.order_id = row.order_id
        self.customer = row.customer
        self.day = row.day
        self.net = 0
        self.rows = []

    def add(self, row):
        self.day = min(self.day, row.day)
        self.net += row.amount
        self.rows.append(row)

    def is_valid(self):
        return self.net > 0


def read_lines(path):
    with open(path) as handle:
        return handle.read().splitlines()


def read_params(path):
    values = {}
    for line in read_lines(path):
        keyword, *words = line.split(" ")
        values[keyword] = words
    return Params(values)


def read_transactions(path):
    data = TransactionData()
    seen = set()
    for line in read_lines(path)[1:]:
        row = Row(line)
        data.row_count += 1
        data.customers.add(row.customer)
        if line in seen:
            data.duplicates += 1
        elif row.amount == 0:
            data.free += 1
        else:
            data.valid_rows.append(row)
        seen.add(line)
    return data


def group_orders(rows, first_day, last_day):
    orders = {}
    for row in rows:
        if first_day <= row.day <= last_day:
            if row.order_id not in orders:
                orders[row.order_id] = Order(row)
            orders[row.order_id].add(row)
    return list(orders.values())


def orders_by_customer(orders):
    grouped = {}
    for order in orders:
        grouped.setdefault(order.customer, []).append(order)
    return grouped
