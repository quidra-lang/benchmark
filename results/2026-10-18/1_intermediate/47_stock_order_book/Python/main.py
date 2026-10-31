import sys


ORDER_COMMANDS = ("LIMIT", "MARKET", "STOP", "STOPLIMIT", "ICEBERG", "CANCEL", "REPLACE")
OPPOSITE = {"BUY": "SELL", "SELL": "BUY"}
ACTIVE_STATUSES = ("PENDING", "OPEN", "PARTIAL")
RESTING_STATUSES = ("OPEN", "PARTIAL")


class CommandError(Exception):
    pass


def two_decimals(value):
    return f"{value // 100}.{value % 100:02d}"


def positive(text, reason):
    value = int(text)
    if value == 0:
        raise CommandError(reason)
    return value


def bar_values(trades):
    prices = [trade.price for trade in trades]
    volume = sum(trade.quantity for trade in trades)
    return prices[0], max(prices), min(prices), prices[-1], volume


class Order:
    def __init__(
        self, order_id, trader, kind, side, quantity,
        price=None, trigger=None, peak=None, condition=None,
    ):
        self.order_id = order_id
        self.trader = trader
        self.kind = kind
        self.side = side
        self.condition = condition
        self.price = price
        self.trigger = trigger
        self.peak = peak
        self.quantity = quantity
        self.remaining = quantity
        self.visible = 0
        self.filled = 0
        self.value = 0
        self.priority = 0
        self.number = 0
        self.status = "OPEN"
        self.history = ["ACCEPT"]

    def is_active(self):
        return self.status in ACTIVE_STATUSES

    def is_resting(self):
        return self.status in RESTING_STATUSES

    def stays_on_book(self):
        if self.kind == "LIMIT":
            return self.condition != "IOC"
        return self.kind in ("ICEBERG", "STOPLIMIT")

    def matches(self, price):
        if self.price is None:
            return True
        if self.side == "BUY":
            return price <= self.price
        return price >= self.price

    def triggered_by(self, last_price):
        if self.side == "BUY":
            return last_price >= self.trigger
        return last_price <= self.trigger

    def fill(self, number, price, quantity):
        self.remaining -= quantity
        self.filled += quantity
        self.value += quantity * price
        self.history.append(f"FILL {number} {price} {quantity}")

    def order_line(self):
        return f"ORDER {self.order_id} {self.status} {self.filled}/{self.quantity}"

    def details(self):
        price = "-" if self.price is None else self.price
        average = "-" if self.filled == 0 else two_decimals(self.value * 100 // self.filled)
        text = (
            f"{self.order_id} {self.trader} {self.kind} {self.side} {price} {self.status} "
            f"{self.filled}/{self.quantity} avg {average}"
        )
        if self.trigger is not None:
            text += f" trigger {self.trigger}"
        return text


class Trader:
    def __init__(self, name):
        self.name = name
        self.bought = 0
        self.sold = 0
        self.cash = 0
        self.fees = 0
        self.limit = None

    def net(self):
        return self.bought - self.sold

    def volume(self):
        return self.bought + self.sold

    def pnl(self, last_price):
        return self.cash + self.net() * last_price

    def buy(self, quantity, price):
        self.bought += quantity
        self.cash -= quantity * price

    def sell(self, quantity, price):
        self.sold += quantity
        self.cash += quantity * price

    def pay(self, fee):
        self.cash -= fee
        self.fees += fee

    def position_line(self, last_price):
        return (
            f"POSITION {self.name} bought {self.bought} sold {self.sold} net {self.net()} "
            f"cash {self.cash} fees {self.fees} pnl {self.pnl(last_price)}"
        )


class Trade:
    def __init__(self, number, price, quantity, buy, sell, taker, buy_fee, sell_fee):
        self.number = number
        self.price = price
        self.quantity = quantity
        self.buy_id = buy.order_id
        self.buy_trader = buy.trader
        self.sell_id = sell.order_id
        self.sell_trader = sell.trader
        self.taker_id = taker.order_id
        self.buy_fee = buy_fee
        self.sell_fee = sell_fee

    def taker_side(self):
        return "BUY" if self.taker_id == self.buy_id else "SELL"

    def line(self):
        return (
            f"TRADE {self.number} {self.price} {self.quantity} "
            f"{self.buy_id} {self.buy_trader} {self.sell_id} {self.sell_trader}"
        )


class Level:
    def __init__(self, price):
        self.price = price
        self.quantity = 0
        self.count = 0


class Book:
    def __init__(self, side):
        self.side = side
        self.orders = []

    def sort_key(self, order):
        price = -order.price if self.side == "BUY" else order.price
        return price, order.priority

    def best(self):
        return min(self.orders, key=self.sort_key, default=None)

    def add(self, order):
        self.orders.append(order)

    def remove(self, order):
        self.orders.remove(order)

    def levels(self):
        levels = []
        for order in sorted(self.orders, key=self.sort_key):
            if not levels or levels[-1].price != order.price:
                levels.append(Level(order.price))
            levels[-1].quantity += order.visible
            levels[-1].count += 1
        return levels

    def available(self, incoming):
        return sum(
            order.remaining for order in self.orders
            if order.trader != incoming.trader and incoming.matches(order.price)
        )


class MatchingEngine:
    def __init__(self):
        self.books = {"BUY": Book("BUY"), "SELL": Book("SELL")}
        self.orders = {}
        self.pending = []
        self.trades = []
        self.traders = {}
        self.maker_fee = 0
        self.taker_fee = 0
        self.band = 0
        self.tick = 1
        self.lot = 1
        self.halted = False
        self.priority_counter = 0
        self.output = []

    def emit(self, *parts):
        self.output.append(" ".join(str(part) for part in parts))

    def last_price(self):
        return self.trades[-1].price if self.trades else None

    def mark_price(self):
        last = self.last_price()
        return 0 if last is None else last

    def next_priority(self):
        self.priority_counter += 1
        return self.priority_counter

    def register(self, name):
        if name not in self.traders:
            self.traders[name] = Trader(name)
        return self.traders[name]

    def active_orders(self, name):
        return [
            order for order in self.orders.values()
            if order.trader == name and order.is_active()
        ]

    def exposure(self, name, side, excluded=None):
        net = self.traders[name].net()
        total = net if side == "BUY" else -net
        for order in self.active_orders(name):
            if order.side == side and order is not excluded:
                total += order.remaining
        return total

    def outside_band(self, price):
        last = self.last_price()
        return self.band > 0 and last is not None and abs(price - last) > self.band

    def require_order(self, order_id):
        if order_id not in self.orders:
            raise CommandError("unknown order")
        return self.orders[order_id]

    def require_trader(self, name):
        if name not in self.traders:
            raise CommandError("unknown trader")
        return self.traders[name]

    def require_new(self, order_id, prices, quantity):
        if self.halted:
            raise CommandError("halted")
        if order_id in self.orders:
            raise CommandError("duplicate id")
        if any(price == 0 for price in prices):
            raise CommandError("invalid price")
        if quantity == 0:
            raise CommandError("invalid quantity")
        if any(price % self.tick != 0 for price in prices):
            raise CommandError("invalid tick")
        if quantity % self.lot != 0:
            raise CommandError("invalid lot")

    def require_band(self, price):
        if self.outside_band(price):
            raise CommandError("outside band")

    def require_risk(self, name, side, quantity, excluded=None):
        trader = self.traders.get(name)
        if trader is None or trader.limit is None:
            return
        if self.exposure(name, side, excluded) + quantity > trader.limit:
            raise CommandError("risk limit")

    def require_trigger(self, order):
        last = self.last_price()
        if last is not None and order.triggered_by(last):
            raise CommandError("invalid trigger")

    def accept(self, order):
        self.register(order.trader)
        order.number = len(self.orders) + 1
        self.orders[order.order_id] = order

    def trade(self, taker, maker):
        quantity = min(taker.remaining, maker.visible)
        price = maker.price
        taker_fee = quantity * self.taker_fee
        maker_fee = quantity * self.maker_fee
        if taker.side == "BUY":
            buy, sell = taker, maker
            buy_fee, sell_fee = taker_fee, maker_fee
        else:
            buy, sell = maker, taker
            buy_fee, sell_fee = maker_fee, taker_fee
        trade = Trade(len(self.trades) + 1, price, quantity, buy, sell, taker, buy_fee, sell_fee)
        self.trades.append(trade)
        taker.fill(trade.number, price, quantity)
        maker.fill(trade.number, price, quantity)
        maker.visible -= quantity
        self.traders[buy.trader].buy(quantity, price)
        self.traders[sell.trader].sell(quantity, price)
        self.traders[taker.trader].pay(taker_fee)
        self.traders[maker.trader].pay(maker_fee)
        self.emit(trade.line())

    def refresh(self, order):
        order.priority = self.next_priority()
        order.visible = min(order.peak, order.remaining)
        hidden = order.remaining - order.visible
        order.history.append(f"REFRESH {order.visible} {hidden}")
        self.emit("REFRESH", order.order_id, order.visible, hidden)

    def match_order(self, order):
        book = self.books[OPPOSITE[order.side]]
        while order.remaining > 0:
            resting = book.best()
            if resting is None or not order.matches(resting.price):
                return
            if resting.trader == order.trader:
                self.emit("STP", resting.order_id, resting.remaining)
                resting.history.append(f"STP {resting.remaining}")
                book.remove(resting)
                resting.remaining = 0
                resting.status = "CANCELLED"
                continue
            self.trade(order, resting)
            if resting.remaining == 0:
                book.remove(resting)
                resting.status = "FILLED"
            else:
                resting.status = "PARTIAL"
                if resting.visible == 0:
                    self.refresh(resting)

    def place(self, order):
        order.priority = self.next_priority()
        if order.peak is None:
            order.visible = order.remaining
        else:
            order.visible = min(order.peak, order.remaining)
        self.books[order.side].add(order)
        order.status = "PARTIAL" if order.filled > 0 else "OPEN"
        order.history.append(f"REST {order.price} {order.visible}")

    def post_process(self, order):
        if order.remaining == 0:
            order.status = "FILLED"
        elif order.stays_on_book():
            self.place(order)
        else:
            order.history.append(f"EXPIRE {order.remaining}")
            order.remaining = 0
            order.status = "CANCELLED"
        self.emit(order.order_line())

    def trigger_stops(self):
        while self.trades:
            last = self.last_price()
            selected = [order for order in self.pending if order.triggered_by(last)]
            if not selected:
                return
            self.pending = [order for order in self.pending if not order.triggered_by(last)]
            for order in selected:
                self.emit("TRIGGER", order.order_id)
                order.history.append("TRIGGER")
                self.match_order(order)
                self.post_process(order)

    def submit(self, order):
        self.accept(order)
        if order.condition != "POSTONLY":
            self.match_order(order)
        self.post_process(order)
        self.trigger_stops()

    def queue_stop(self, order):
        self.accept(order)
        order.status = "PENDING"
        self.pending.append(order)
        self.emit(order.order_line())

    def cancel_order(self, order):
        if order.status == "PENDING":
            self.pending.remove(order)
        else:
            self.books[order.side].remove(order)
        order.history.append(f"CANCEL {order.remaining}")
        order.remaining = 0
        order.status = "CANCELLED"
        self.emit(order.order_line())

    def limit(self, arguments):
        order_id, trader, side = arguments[:3]
        price, quantity = int(arguments[3]), int(arguments[4])
        condition = arguments[5] if len(arguments) == 6 else None
        order = Order(order_id, trader, "LIMIT", side, quantity, price=price, condition=condition)
        self.require_new(order_id, (price,), quantity)
        self.require_band(price)
        self.require_risk(trader, side, quantity)
        opposite = self.books[OPPOSITE[side]]
        best = opposite.best()
        if condition == "POSTONLY" and best is not None and order.matches(best.price):
            raise CommandError("would cross")
        if condition == "FOK" and opposite.available(order) < quantity:
            raise CommandError("unfillable")
        self.submit(order)

    def market(self, arguments):
        order_id, trader, side = arguments[:3]
        quantity = int(arguments[3])
        order = Order(order_id, trader, "MARKET", side, quantity)
        self.require_new(order_id, (), quantity)
        self.require_risk(trader, side, quantity)
        self.submit(order)

    def stop(self, arguments):
        order_id, trader, side = arguments[:3]
        trigger, quantity = int(arguments[3]), int(arguments[4])
        order = Order(order_id, trader, "STOP", side, quantity, trigger=trigger)
        self.require_new(order_id, (trigger,), quantity)
        self.require_trigger(order)
        self.require_risk(trader, side, quantity)
        self.queue_stop(order)

    def stop_limit(self, arguments):
        order_id, trader, side = arguments[:3]
        trigger, price, quantity = (int(value) for value in arguments[3:])
        order = Order(
            order_id, trader, "STOPLIMIT", side, quantity, price=price, trigger=trigger
        )
        self.require_new(order_id, (trigger, price), quantity)
        self.require_trigger(order)
        self.require_band(price)
        self.require_risk(trader, side, quantity)
        self.queue_stop(order)

    def iceberg(self, arguments):
        order_id, trader, side = arguments[:3]
        price, quantity, peak = (int(value) for value in arguments[3:])
        order = Order(order_id, trader, "ICEBERG", side, quantity, price=price, peak=peak)
        self.require_new(order_id, (price,), quantity)
        if peak == 0 or peak > quantity or peak % self.lot != 0:
            raise CommandError("invalid peak")
        self.require_band(price)
        self.require_risk(trader, side, quantity)
        self.submit(order)

    def cancel(self, arguments):
        order = self.require_order(arguments[0])
        if not order.is_active():
            raise CommandError("not open")
        self.cancel_order(order)

    def replace(self, arguments):
        order_id = arguments[0]
        price, quantity = int(arguments[1]), int(arguments[2])
        if self.halted:
            raise CommandError("halted")
        order = self.require_order(order_id)
        if not order.is_resting():
            raise CommandError("not open")
        if price == 0:
            raise CommandError("invalid price")
        if quantity == 0:
            raise CommandError("invalid quantity")
        moved = price != order.price
        if moved and price % self.tick != 0:
            raise CommandError("invalid tick")
        if quantity % self.lot != 0:
            raise CommandError("invalid lot")
        if not moved and quantity == order.remaining:
            raise CommandError("no change")
        if moved:
            self.require_band(price)
        if quantity > order.remaining:
            self.require_risk(order.trader, order.side, quantity, order)
        order.quantity = order.filled + quantity
        if not moved and quantity < order.remaining:
            order.remaining = quantity
            order.visible = min(order.visible, quantity)
            order.history.append(f"REPLACE {price} {quantity} kept")
            self.emit("REPLACE", order_id, "kept")
            self.emit(order.order_line())
            return
        self.books[order.side].remove(order)
        order.price = price
        order.remaining = quantity
        order.history.append(f"REPLACE {price} {quantity} lost")
        self.emit("REPLACE", order_id, "lost")
        self.match_order(order)
        self.post_process(order)
        self.trigger_stops()

    def cancel_all(self, arguments):
        name = arguments[0]
        self.require_trader(name)
        orders = self.active_orders(name)
        self.emit("CANCELALL", name, len(orders))
        for order in orders:
            self.cancel_order(order)

    def halt(self, arguments):
        if self.halted:
            raise CommandError("already halted")
        self.halted = True
        self.emit("HALT")

    def resume(self, arguments):
        if not self.halted:
            raise CommandError("not halted")
        self.halted = False
        self.emit("RESUME")

    def set_risk(self, arguments):
        name, limit = arguments[0], int(arguments[1])
        self.register(name).limit = limit
        self.emit(
            "RISK", name, limit, "exposure",
            "buy", self.exposure(name, "BUY"), "sell", self.exposure(name, "SELL"),
        )

    def set_fee(self, arguments):
        maker, taker = int(arguments[0]), int(arguments[1])
        if maker + taker < 0:
            raise CommandError("invalid fee")
        self.maker_fee = maker
        self.taker_fee = taker
        self.emit("FEE", "maker", maker, "taker", taker)

    def set_band(self, arguments):
        self.band = int(arguments[0])
        self.emit("BAND", self.band)

    def set_tick(self, arguments):
        self.tick = positive(arguments[0], "invalid size")
        self.emit("TICK", self.tick)

    def set_lot(self, arguments):
        self.lot = positive(arguments[0], "invalid size")
        self.emit("LOT", self.lot)

    def show_book(self, arguments):
        depth = positive(arguments[0], "invalid depth")
        bids = self.books["BUY"].levels()
        asks = self.books["SELL"].levels()
        self.emit("BOOK", "bids", len(bids), "asks", len(asks))
        for level in reversed(asks[:depth]):
            self.emit("ASK", level.price, level.quantity, level.count)
        for level in bids[:depth]:
            self.emit("BID", level.price, level.quantity, level.count)

    def show_orders(self, arguments):
        name = arguments[0]
        self.require_trader(name)
        orders = self.active_orders(name)
        self.emit("ORDERS", name, len(orders))
        for order in orders:
            self.emit(order.details())

    def status(self, arguments):
        order = self.require_order(arguments[0])
        self.emit("STATUS", order.details())

    def history(self, arguments):
        order = self.require_order(arguments[0])
        self.emit("HISTORY", order.order_id, len(order.history))
        for line in order.history:
            self.emit(line)

    def position(self, arguments):
        trader = self.require_trader(arguments[0])
        self.emit(trader.position_line(self.mark_price()))

    def fills(self, arguments):
        name = arguments[0]
        self.require_trader(name)
        trades = [
            trade for trade in self.trades
            if trade.buy_trader == name or trade.sell_trader == name
        ]
        self.emit("FILLS", name, len(trades))
        net = 0
        for trade in trades:
            if trade.buy_trader == name:
                side, order_id, fee = "BUY", trade.buy_id, trade.buy_fee
                net += trade.quantity
            else:
                side, order_id, fee = "SELL", trade.sell_id, trade.sell_fee
                net -= trade.quantity
            role = "TAKER" if trade.taker_id == order_id else "MAKER"
            self.emit(
                trade.number, side, trade.price, trade.quantity, order_id, role,
                "fee", fee, "net", net,
            )

    def last(self, arguments):
        if not self.trades:
            self.emit("LAST", "none")
            return
        trade = self.trades[-1]
        self.emit("LAST", trade.price, trade.quantity)

    def vwap(self, arguments):
        if not self.trades:
            self.emit("VWAP", "none")
            return
        volume = sum(trade.quantity for trade in self.trades)
        amount = sum(trade.price * trade.quantity for trade in self.trades)
        self.emit(
            "VWAP", two_decimals(amount * 100 // volume),
            "volume", volume, "trades", len(self.trades),
        )

    def spread(self, arguments):
        bid = self.books["BUY"].best()
        ask = self.books["SELL"].best()
        if bid is None or ask is None:
            bid_text = "none" if bid is None else bid.price
            ask_text = "none" if ask is None else ask.price
            self.emit("SPREAD", "bid", bid_text, "ask", ask_text)
            return
        total = bid.price + ask.price
        midpoint = f"{total // 2}.{5 if total % 2 else 0}"
        self.emit(
            "SPREAD", "bid", bid.price, "ask", ask.price,
            "spread", ask.price - bid.price, "mid", midpoint,
        )

    def impact(self, arguments):
        side = arguments[0]
        quantity = positive(arguments[1], "invalid quantity")
        levels = self.books[OPPOSITE[side]].levels()
        remainder = quantity
        cost = 0
        worst = 0
        used = 0
        for level in levels:
            if remainder == 0:
                break
            taken = min(remainder, level.quantity)
            remainder -= taken
            cost += taken * level.price
            worst = level.price
            used += 1
        if remainder > 0:
            total = sum(level.quantity for level in levels)
            self.emit("IMPACT", side, quantity, "insufficient", total)
        else:
            self.emit(
                "IMPACT", side, quantity, "avg", two_decimals(cost * 100 // quantity),
                "worst", worst, "levels", used,
            )

    def show_trades(self, arguments):
        count = positive(arguments[0], "invalid count")
        shown = min(count, len(self.trades))
        self.emit("TRADES", shown, "of", len(self.trades))
        for trade in self.trades[len(self.trades) - shown:]:
            self.emit(trade.line())

    def bars(self, arguments):
        size = positive(arguments[0], "invalid count")
        groups = [self.trades[start:start + size] for start in range(0, len(self.trades), size)]
        self.emit("BARS", len(groups))
        for number, group in enumerate(groups, 1):
            first, high, low, close, volume = bar_values(group)
            self.emit(
                number, "open", first, "high", high, "low", low,
                "close", close, "volume", volume,
            )

    def rank(self, arguments):
        mark = self.mark_price()
        traders = sorted(
            self.traders.values(),
            key=lambda trader: (-trader.pnl(mark), -trader.volume(), trader.name),
        )
        self.emit("RANK", len(traders))
        for number, trader in enumerate(traders, 1):
            self.emit(number, trader.name, "pnl", trader.pnl(mark), "volume", trader.volume())

    def flow(self, arguments):
        bought = sum(trade.quantity for trade in self.trades if trade.taker_side() == "BUY")
        sold = sum(trade.quantity for trade in self.trades if trade.taker_side() == "SELL")
        self.emit("FLOW", "buy", bought, "sell", sold, "net", bought - sold)

    def summary(self, arguments):
        if self.trades:
            first, high, low, close, volume = bar_values(self.trades)
            fees = sum(trade.buy_fee + trade.sell_fee for trade in self.trades)
            self.emit(
                "SUMMARY", "trades", len(self.trades), "volume", volume,
                "open", first, "high", high, "low", low, "close", close, "fees", fees,
            )
        else:
            self.emit("SUMMARY", "trades", 0)
        mark = self.mark_price()
        for name in sorted(self.traders):
            self.emit(self.traders[name].position_line(mark))

    def execute(self, line):
        command, *arguments = line.split()
        handlers = {
            "LIMIT": self.limit,
            "MARKET": self.market,
            "STOP": self.stop,
            "STOPLIMIT": self.stop_limit,
            "ICEBERG": self.iceberg,
            "CANCEL": self.cancel,
            "REPLACE": self.replace,
            "CANCELALL": self.cancel_all,
            "HALT": self.halt,
            "RESUME": self.resume,
            "RISK": self.set_risk,
            "FEE": self.set_fee,
            "BAND": self.set_band,
            "TICK": self.set_tick,
            "LOT": self.set_lot,
            "BOOK": self.show_book,
            "ORDERS": self.show_orders,
            "STATUS": self.status,
            "HISTORY": self.history,
            "POSITION": self.position,
            "FILLS": self.fills,
            "LAST": self.last,
            "VWAP": self.vwap,
            "SPREAD": self.spread,
            "IMPACT": self.impact,
            "TRADES": self.show_trades,
            "BARS": self.bars,
            "RANK": self.rank,
            "FLOW": self.flow,
            "SUMMARY": self.summary,
        }
        try:
            handlers[command](arguments)
        except CommandError as error:
            if command in ORDER_COMMANDS:
                self.emit("REJECT", arguments[0], error)
            else:
                self.emit("ERROR", error)


def main():
    engine = MatchingEngine()
    count = int(sys.stdin.readline())
    for _ in range(count):
        engine.execute(sys.stdin.readline().rstrip("\n"))
    sys.stdout.write("\n".join(engine.output) + "\n")


if __name__ == "__main__":
    main()
