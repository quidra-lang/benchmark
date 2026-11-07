import sys


CATEGORIES = (
    "received", "returned", "adjusted-in", "adjusted-out",
    "shipped", "written-down", "expired", "recalled",
)


def cents(text):
    whole, fraction = text.split(".")
    return 100 * int(whole) + int(fraction)


def money(value):
    sign = "-" if value < 0 else ""
    value = abs(value)
    return f"{sign}{value // 100}.{value % 100:02d}"


def signed_quantity(value):
    return "+" + str(value) if value > 0 else str(value)


def signed_money(value):
    return "+" + money(value) if value > 0 else money(value)


def margin(profit, revenue):
    if revenue == 0:
        return "n/a"
    tenths = abs(profit) * 1000 // revenue
    sign = "-" if profit < 0 and tenths else ""
    return f"{sign}{tenths // 10}.{tenths % 10}%"


class CommandError(Exception):
    pass


class Item:
    def __init__(self, code, level, name):
        self.code = code
        self.level = level
        self.name = name
        self.last_cost = None
        self.card = []


class Lot:
    def __init__(self, number, item, day, quantity, cost, warehouse, kind):
        self.number = number
        self.item = item
        self.day = day
        self.initial_quantity = quantity
        self.initial_cost = cost
        self.warehouse = warehouse
        self.kind = kind
        self.removed = 0


class StockLot:
    def __init__(self, lot, quantity, cost):
        self.lot = lot
        self.quantity = quantity
        self.cost = cost

    def value(self):
        return self.quantity * self.cost


class Order:
    def __init__(self, number, warehouse, item, day, quantity, price):
        self.number = number
        self.warehouse = warehouse
        self.item = item
        self.day = day
        self.price = price
        self.ordered = quantity
        self.shipped = 0
        self.backorder = quantity
        self.cancelled = 0
        self.returned = 0
        self.revenue = 0
        self.cogs = 0
        self.issues = []


class Inventory:
    def __init__(self):
        self.day = 1
        self.stock = {}
        self.items = {}
        self.lots = []
        self.orders = []
        self.totals = {category: [0, 0] for category in CATEGORIES}
        self.output = []

    def emit(self, *parts, indent=0):
        self.output.append(" " * indent + " ".join(str(part) for part in parts))

    def warehouse(self, code):
        if code not in self.stock:
            raise CommandError(f"unknown warehouse {code}")
        return code

    def item(self, code):
        if code not in self.items:
            raise CommandError(f"unknown item {code}")
        return self.items[code]

    def pair(self, warehouse, item):
        self.warehouse(warehouse)
        return self.item(item)

    def order(self, text):
        number = int(text)
        if not 1 <= number <= len(self.orders):
            raise CommandError(f"unknown order {text}")
        return self.orders[number - 1]

    def lot(self, text):
        number = int(text)
        if not 1 <= number <= len(self.lots):
            raise CommandError(f"unknown lot {text}")
        return self.lots[number - 1]

    def require_quantity(self, quantity):
        if quantity == 0:
            raise CommandError("invalid quantity")

    def holdings(self, warehouse, item):
        return self.stock[warehouse].get(item, {})

    def quantity(self, warehouse, item):
        return sum(stock.quantity for stock in self.holdings(warehouse, item).values())

    def stock_value(self, warehouse, item):
        return sum(stock.value() for stock in self.holdings(warehouse, item).values())

    def total_quantity(self, item):
        return sum(self.quantity(warehouse, item) for warehouse in self.stock)

    def total_backorder(self, item):
        return sum(order.backorder for order in self.orders if order.item == item)

    def require_stock(self, warehouse, item, quantity):
        available = self.quantity(warehouse, item)
        if available < quantity:
            raise CommandError(f"insufficient stock {warehouse} {item} {available}")

    def card_entry(self, item, kind, warehouse, quantity, value):
        self.items[item].card.append((self.day, kind, warehouse, quantity, value))

    def accumulate(self, category, quantity, value):
        self.totals[category][0] += quantity
        self.totals[category][1] += value

    def add_stock(self, warehouse, lot, quantity, cost):
        holdings = self.stock[warehouse].setdefault(lot.item, {})
        if lot.number in holdings:
            holdings[lot.number].quantity += quantity
        else:
            holdings[lot.number] = StockLot(lot, quantity, cost)

    def create_lot(self, warehouse, item, day, quantity, cost, kind):
        lot = Lot(len(self.lots) + 1, item, day, quantity, cost, warehouse, kind)
        self.lots.append(lot)
        self.add_stock(warehouse, lot, quantity, cost)
        return lot

    def fifo(self, warehouse, item):
        return sorted(self.holdings(warehouse, item).values(), key=lambda stock: (stock.lot.day, stock.lot.number))

    def issue(self, warehouse, item, quantity):
        parts = []
        cost = 0
        holdings = self.holdings(warehouse, item)
        for stock in self.fifo(warehouse, item):
            if quantity == 0:
                break
            taken = min(quantity, stock.quantity)
            parts.append((stock.lot, taken, stock.cost))
            cost += taken * stock.cost
            stock.quantity -= taken
            quantity -= taken
            if stock.quantity == 0:
                del holdings[stock.lot.number]
        return parts, cost

    def fulfil(self, order, quantity, kind):
        if quantity == 0:
            return 0
        parts, cost = self.issue(order.warehouse, order.item, quantity)
        order.shipped += quantity
        order.backorder -= quantity
        order.revenue += quantity * order.price
        order.cogs += cost
        order.issues.extend((lot.number, taken, unit_cost) for lot, taken, unit_cost in parts)
        self.accumulate("shipped", quantity, cost)
        self.card_entry(order.item, kind, order.warehouse, -quantity, -cost)
        return cost

    def allocate(self, warehouse, item):
        available = self.quantity(warehouse, item)
        for order in self.orders:
            if available == 0:
                break
            if order.warehouse != warehouse or order.item != item or order.backorder == 0:
                continue
            filled = min(available, order.backorder)
            cost = self.fulfil(order, filled, "fill")
            revenue = filled * order.price
            available -= filled
            self.emit(
                "FILL", "order", order.number, "qty", filled,
                "revenue", money(revenue), "cogs", money(cost),
                "profit", money(revenue - cost), "backorder", order.backorder, indent=2,
            )

    def remove_parts(self, parts):
        for lot, quantity, _ in parts:
            lot.removed += quantity

    def advance_day(self, arguments):
        day = int(arguments[0])
        if day <= self.day:
            raise CommandError(f"invalid day {arguments[0]}")
        self.day = day
        self.emit("DAY", day)

    def register_warehouse(self, arguments):
        code = arguments[0]
        if code in self.stock:
            raise CommandError(f"duplicate warehouse {code}")
        self.stock[code] = {}
        self.emit("WAREHOUSE", code)

    def register_item(self, arguments):
        code, level, name = arguments
        if code in self.items:
            item = self.items[code]
            item.level = int(level)
            item.name = name
            action = "updated"
        else:
            self.items[code] = Item(code, int(level), name)
            action = "added"
        self.emit("ITEM", code, action, name, "level", int(level))

    def receive(self, arguments):
        warehouse, item, quantity, cost, day = arguments
        product = self.pair(warehouse, item)
        quantity, cost, day = int(quantity), cents(cost), int(day)
        self.require_quantity(quantity)
        if day > self.day:
            raise CommandError(f"future day {arguments[4]}")
        lot = self.create_lot(warehouse, item, day, quantity, cost, "receive")
        product.last_cost = cost
        self.accumulate("received", quantity, quantity * cost)
        self.card_entry(item, "receive", warehouse, quantity, quantity * cost)
        self.emit(
            "RECEIVE", warehouse, item, "lot", lot.number, "qty", quantity,
            "cost", money(cost), "day", day, "value", money(quantity * cost),
        )
        self.allocate(warehouse, item)

    def ship(self, arguments):
        warehouse, item, quantity, price = arguments
        self.pair(warehouse, item)
        quantity, price = int(quantity), cents(price)
        self.require_quantity(quantity)
        order = Order(len(self.orders) + 1, warehouse, item, self.day, quantity, price)
        self.orders.append(order)
        filled = min(quantity, self.quantity(warehouse, item))
        cost = self.fulfil(order, filled, "ship")
        self.emit(
            "SHIP", "order", order.number, warehouse, item, "shipped", filled,
            "revenue", money(order.revenue), "cogs", money(cost),
            "profit", money(order.revenue - cost), "backorder", order.backorder,
        )

    def cancel(self, arguments):
        order = self.order(arguments[0])
        if order.backorder == 0:
            raise CommandError(f"no backorder {arguments[0]}")
        order.cancelled += order.backorder
        order.backorder = 0
        self.emit("CANCEL", "order", order.number, "qty", order.cancelled)

    def transfer(self, arguments):
        source, destination, item, quantity = arguments
        self.warehouse(source)
        self.warehouse(destination)
        if source == destination:
            raise CommandError(f"same warehouse {source}")
        self.item(item)
        quantity = int(quantity)
        self.require_quantity(quantity)
        self.require_stock(source, item, quantity)
        parts, cost = self.issue(source, item, quantity)
        for lot, taken, unit_cost in parts:
            self.add_stock(destination, lot, taken, unit_cost)
        self.card_entry(item, "transfer-out", source, -quantity, -cost)
        self.card_entry(item, "transfer-in", destination, quantity, cost)
        self.emit(
            "TRANSFER", source, "->", destination, item, "qty", quantity,
            "value", money(cost), "lots", len(parts),
        )
        self.allocate(destination, item)

    def adjust(self, arguments):
        warehouse, item, change = arguments[:3]
        self.pair(warehouse, item)
        quantity = int(change[1:])
        self.require_quantity(quantity)
        if change[0] == "+":
            cost = cents(arguments[3])
            lot = self.create_lot(warehouse, item, self.day, quantity, cost, "adjust")
            self.accumulate("adjusted-in", quantity, quantity * cost)
            self.card_entry(item, "adjust", warehouse, quantity, quantity * cost)
            self.emit("ADJUST", warehouse, item, "+" + str(quantity), "lot", lot.number, "value", money(quantity * cost))
            self.allocate(warehouse, item)
        else:
            self.require_stock(warehouse, item, quantity)
            parts, cost = self.issue(warehouse, item, quantity)
            self.remove_parts(parts)
            self.accumulate("adjusted-out", quantity, cost)
            self.card_entry(item, "adjust", warehouse, -quantity, -cost)
            self.emit("ADJUST", warehouse, item, "-" + str(quantity), "value", money(cost))

    def return_stock(self, arguments):
        order = self.order(arguments[0])
        quantity, cost = int(arguments[1]), cents(arguments[2])
        self.require_quantity(quantity)
        available = order.shipped - order.returned
        if quantity > available:
            raise CommandError(f"return exceeds shipped {arguments[0]} {available}")
        warehouse, item = order.warehouse, order.item
        lot = self.create_lot(warehouse, item, self.day, quantity, cost, "return")
        order.returned += quantity
        order.revenue -= quantity * order.price
        order.cogs -= quantity * cost
        self.accumulate("returned", quantity, quantity * cost)
        self.card_entry(item, "return", warehouse, quantity, quantity * cost)
        self.emit(
            "RETURN", "order", order.number, warehouse, item, "qty", quantity,
            "lot", lot.number, "refund", money(quantity * order.price), "value", money(quantity * cost),
        )
        self.allocate(warehouse, item)

    def count(self, arguments):
        warehouse, item, actual = arguments
        product = self.pair(warehouse, item)
        actual = int(actual)
        held = self.quantity(warehouse, item)
        if actual == held:
            self.emit("COUNT", warehouse, item, "qty", actual, "ok")
        elif actual < held:
            shortage = held - actual
            parts, cost = self.issue(warehouse, item, shortage)
            self.remove_parts(parts)
            self.accumulate("adjusted-out", shortage, cost)
            self.card_entry(item, "count", warehouse, -shortage, -cost)
            self.emit("COUNT", warehouse, item, "qty", held, "->", actual, "shortage", shortage, "value", money(cost))
        else:
            surplus = actual - held
            cost = product.last_cost if product.last_cost is not None else 0
            lot = self.create_lot(warehouse, item, self.day, surplus, cost, "count")
            self.accumulate("adjusted-in", surplus, surplus * cost)
            self.card_entry(item, "count", warehouse, surplus, surplus * cost)
            self.emit(
                "COUNT", warehouse, item, "qty", held, "->", actual,
                "surplus", surplus, "lot", lot.number, "value", money(surplus * cost),
            )
            self.allocate(warehouse, item)

    def market(self, arguments):
        item, price = arguments
        self.item(item)
        price = cents(price)
        lots_changed = 0
        quantity = 0
        loss = 0
        for warehouse in sorted(self.stock):
            warehouse_loss = 0
            for stock in self.holdings(warehouse, item).values():
                if stock.cost > price:
                    decrease = stock.quantity * (stock.cost - price)
                    warehouse_loss += decrease
                    lots_changed += 1
                    quantity += stock.quantity
                    stock.cost = price
            if warehouse_loss:
                self.card_entry(item, "writedown", warehouse, 0, -warehouse_loss)
                loss += warehouse_loss
        self.accumulate("written-down", quantity, loss)
        self.emit("MARKET", item, "price", money(price), "lots", lots_changed, "qty", quantity, "loss", money(loss))

    def recall(self, arguments):
        lot = self.lot(arguments[0])
        held = [
            (warehouse, self.holdings(warehouse, lot.item)[lot.number])
            for warehouse in sorted(self.stock) if lot.number in self.holdings(warehouse, lot.item)
        ]
        if not held:
            raise CommandError(f"nothing to recall {arguments[0]}")
        quantity = sum(stock.quantity for _, stock in held)
        value = sum(stock.value() for _, stock in held)
        for warehouse, stock in held:
            del self.holdings(warehouse, lot.item)[lot.number]
            self.card_entry(lot.item, "recall", warehouse, -stock.quantity, -stock.value())
        lot.removed += quantity
        self.accumulate("recalled", quantity, value)
        self.emit("RECALL", "lot", lot.number, lot.item, "qty", quantity, "value", money(value))
        for warehouse, stock in held:
            self.emit(warehouse, "qty", stock.quantity, "value", money(stock.value()), indent=2)

    def expire(self, arguments):
        days = int(arguments[0])
        self.emit("EXPIRE", days)
        total_quantity = 0
        total_value = 0
        for item in sorted(self.items):
            for warehouse in sorted(self.stock):
                holdings = self.holdings(warehouse, item)
                expired = [stock for stock in holdings.values() if self.day - stock.lot.day > days]
                if not expired:
                    continue
                quantity = sum(stock.quantity for stock in expired)
                value = sum(stock.value() for stock in expired)
                for stock in expired:
                    stock.lot.removed += stock.quantity
                    del holdings[stock.lot.number]
                self.accumulate("expired", quantity, value)
                self.card_entry(item, "expire", warehouse, -quantity, -value)
                total_quantity += quantity
                total_value += value
                self.emit(item, warehouse, "lots", len(expired), "qty", quantity, "value", money(value), indent=2)
        self.emit("total", "qty", total_quantity, "value", money(total_value), indent=2)

    def target_warehouses(self, arguments):
        if arguments:
            return [self.warehouse(arguments[0])]
        return sorted(self.stock)

    def value(self, arguments):
        warehouses = self.target_warehouses(arguments)
        self.emit("VALUE", *arguments)
        total_quantity = 0
        total_value = 0
        for item in sorted(self.items):
            rows = [
                (warehouse, self.quantity(warehouse, item), self.stock_value(warehouse, item))
                for warehouse in warehouses
            ]
            quantity = sum(row[1] for row in rows)
            value = sum(row[2] for row in rows)
            if quantity == 0:
                continue
            self.emit(item, "qty", quantity, "value", money(value), "avg", money(value // quantity), indent=2)
            if not arguments:
                for warehouse, held, amount in rows:
                    if held:
                        self.emit(warehouse, "qty", held, "value", money(amount), indent=4)
            total_quantity += quantity
            total_value += value
        self.emit("total", "qty", total_quantity, "value", money(total_value), indent=2)

    def show_lots(self, arguments):
        warehouse, item = arguments
        self.pair(warehouse, item)
        self.emit("LOTS", warehouse, item)
        stocks = self.fifo(warehouse, item)
        orders = [order for order in self.orders if order.warehouse == warehouse and order.item == item and order.backorder]
        for stock in stocks:
            self.emit(
                "lot", stock.lot.number, "day", stock.lot.day, "qty", stock.quantity,
                "cost", money(stock.cost), "value", money(stock.value()), "age", self.day - stock.lot.day, indent=2,
            )
        for order in orders:
            self.emit("backorder", "order", order.number, "qty", order.backorder, indent=2)
        if not stocks and not orders:
            self.emit("(none)", indent=2)

    def reorder(self, arguments):
        self.emit("REORDER")
        found = False
        for code in sorted(self.items):
            item = self.items[code]
            quantity = self.total_quantity(code)
            backorder = self.total_backorder(code)
            if quantity - backorder <= item.level:
                self.emit(code, item.name, "onhand", quantity, "backorder", backorder, "level", item.level, indent=2)
                found = True
        if not found:
            self.emit("(none)", indent=2)

    def show_items(self, arguments):
        self.emit("ITEMS")
        for code in sorted(self.items):
            item = self.items[code]
            cost = "none" if item.last_cost is None else money(item.last_cost)
            self.emit(
                code, item.name, "level", item.level, "onhand", self.total_quantity(code),
                "backorder", self.total_backorder(code), "cost", cost, indent=2,
            )
        if not self.items:
            self.emit("(none)", indent=2)

    def sales_summaries(self):
        summaries = {}
        for order in self.orders:
            summary = summaries.setdefault(order.item, [0, 0, 0])
            summary[0] += order.shipped - order.returned
            summary[1] += order.revenue
            summary[2] += order.cogs
        return summaries

    def margin_line(self, label, quantity, revenue, cogs):
        self.emit(
            label, "sold", quantity, "revenue", money(revenue), "cogs", money(cogs),
            "profit", money(revenue - cogs), "margin", margin(revenue - cogs, revenue), indent=2,
        )

    def show_margin(self, arguments):
        self.emit("MARGIN")
        summaries = self.sales_summaries()
        for item in sorted(summaries):
            self.margin_line(item, *summaries[item])
        totals = [sum(row[index] for row in summaries.values()) for index in range(3)]
        self.margin_line("total", *totals)

    def top(self, arguments):
        count = int(arguments[0])
        self.emit("TOP", count)
        summaries = self.sales_summaries()
        order = sorted(summaries, key=lambda item: (-(summaries[item][1] - summaries[item][2]), -summaries[item][1], item))
        for rank, item in enumerate(order[:count], 1):
            _, revenue, cogs = summaries[item]
            self.emit(rank, item, "profit", money(revenue - cogs), "revenue", money(revenue), "margin", margin(revenue - cogs, revenue), indent=2)
        if not order:
            self.emit("(none)", indent=2)

    def aging_line(self, label, buckets, monetary=False):
        parts = [label]
        for name, value in zip(("0-30", "31-60", "61-90", "91+"), buckets):
            parts.extend((name, money(value) if monetary else value))
        self.emit(*parts, indent=2)

    def aging(self, arguments):
        warehouses = self.target_warehouses(arguments)
        self.emit("AGING", *arguments, "day", self.day)
        total_quantities = [0, 0, 0, 0]
        total_values = [0, 0, 0, 0]
        for item in sorted(self.items):
            quantities = [0, 0, 0, 0]
            for warehouse in warehouses:
                for stock in self.holdings(warehouse, item).values():
                    age = self.day - stock.lot.day
                    bucket = 0 if age <= 30 else 1 if age <= 60 else 2 if age <= 90 else 3
                    quantities[bucket] += stock.quantity
                    total_quantities[bucket] += stock.quantity
                    total_values[bucket] += stock.value()
            if sum(quantities):
                self.aging_line(item, quantities)
        self.aging_line("total", total_quantities)
        self.aging_line("value", total_values, True)

    def backorders(self, arguments):
        self.emit("BACKORDERS")
        orders = [order for order in self.orders if order.backorder]
        for order in orders:
            self.emit(
                "order", order.number, order.warehouse, order.item, "qty", order.backorder,
                "day", order.day, "price", money(order.price), indent=2,
            )
        if not orders:
            self.emit("(none)", indent=2)

    def show_order(self, arguments):
        order = self.order(arguments[0])
        self.emit("ORDER", order.number, order.warehouse, order.item, "day", order.day, "price", money(order.price))
        self.emit(
            "ordered", order.ordered, "shipped", order.shipped, "backorder", order.backorder,
            "cancelled", order.cancelled, "returned", order.returned, indent=2,
        )
        for number, quantity, cost in order.issues:
            self.emit("lot", number, "qty", quantity, "cost", money(cost), indent=2)
        self.emit("revenue", money(order.revenue), "cogs", money(order.cogs), "profit", money(order.revenue - order.cogs), indent=2)

    def trace(self, arguments):
        lot = self.lot(arguments[0])
        self.emit(
            "TRACE", "lot", lot.number, lot.item, lot.kind, lot.warehouse,
            "day", lot.day, "qty", lot.initial_quantity, "cost", money(lot.initial_cost),
        )
        for warehouse in sorted(self.stock):
            stock = self.holdings(warehouse, lot.item).get(lot.number)
            if stock is not None:
                self.emit("held", warehouse, "qty", stock.quantity, "cost", money(stock.cost), indent=2)
        for order in self.orders:
            quantity = sum(quantity for number, quantity, _ in order.issues if number == lot.number)
            if quantity:
                self.emit("order", order.number, "qty", quantity, indent=2)
        if lot.removed:
            self.emit("removed", "qty", lot.removed, indent=2)

    def card(self, arguments):
        item = self.item(arguments[0])
        self.emit("CARD", item.code, item.name)
        quantity = 0
        value = 0
        for day, kind, warehouse, quantity_change, value_change in item.card:
            quantity += quantity_change
            value += value_change
            self.emit(
                "day", day, kind, warehouse, signed_quantity(quantity_change), signed_money(value_change),
                "balance", quantity, money(value), indent=2,
            )
        if not item.card:
            self.emit("(none)", indent=2)

    def status(self, arguments):
        self.emit("STATUS")
        for warehouse in sorted(self.stock):
            pairs = self.stock[warehouse]
            stocks = [stock for holdings in pairs.values() for stock in holdings.values()]
            self.emit(
                warehouse, "skus", sum(bool(holdings) for holdings in pairs.values()),
                "qty", sum(stock.quantity for stock in stocks), "value", money(sum(stock.value() for stock in stocks)),
                "backorder", sum(order.backorder for order in self.orders if order.warehouse == warehouse), indent=2,
            )
        if not self.stock:
            self.emit("(none)", indent=2)

    def summary(self, arguments):
        self.emit("SUMMARY")
        for category in CATEGORIES:
            quantity, value = self.totals[category]
            self.emit(category, "qty", quantity, "value", money(value), indent=2)
        stocks = [stock for pairs in self.stock.values() for holdings in pairs.values() for stock in holdings.values()]
        self.emit("on-hand", "qty", sum(stock.quantity for stock in stocks), "value", money(sum(stock.value() for stock in stocks)), indent=2)
        self.emit(
            "orders", len(self.orders), "open", sum(order.backorder > 0 for order in self.orders),
            "backorder", sum(order.backorder for order in self.orders), indent=2,
        )

    def execute(self, line):
        command, *arguments = line.split()
        handlers = {
            "DAY": self.advance_day,
            "WAREHOUSE": self.register_warehouse,
            "ITEM": self.register_item,
            "RECEIVE": self.receive,
            "SHIP": self.ship,
            "CANCEL": self.cancel,
            "TRANSFER": self.transfer,
            "ADJUST": self.adjust,
            "RETURN": self.return_stock,
            "COUNT": self.count,
            "MARKET": self.market,
            "RECALL": self.recall,
            "EXPIRE": self.expire,
            "VALUE": self.value,
            "LOTS": self.show_lots,
            "REORDER": self.reorder,
            "ITEMS": self.show_items,
            "MARGIN": self.show_margin,
            "TOP": self.top,
            "AGING": self.aging,
            "BACKORDERS": self.backorders,
            "ORDER": self.show_order,
            "TRACE": self.trace,
            "CARD": self.card,
            "STATUS": self.status,
            "SUMMARY": self.summary,
        }
        try:
            handlers[command](arguments)
        except CommandError as error:
            self.emit("ERROR", error)


def main():
    inventory = Inventory()
    count = int(sys.stdin.readline())
    for _ in range(count):
        inventory.execute(sys.stdin.readline().rstrip("\n"))
    sys.stdout.write("\n".join(inventory.output) + "\n")


if __name__ == "__main__":
    main()
