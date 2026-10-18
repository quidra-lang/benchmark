import sys
from collections import defaultdict
from functools import cache


class Invalid(Exception):
    pass


def amount(text):
    whole, cents = text.split(".")
    return int(whole) * 100 + int(cents)


def money(value):
    return f"{value // 100}.{value % 100:02d}"


def signed(value):
    if value > 0:
        return "+" + money(value)
    if value < 0:
        return "-" + money(-value)
    return "0.00"


def percentage(part, whole):
    return money(part * 10000 // whole) + "%"


def rate_text(rate):
    return f"{rate // 10000}.{rate % 10000:04d}"


def equal_distribution(total, count):
    quotient, remainder = divmod(total, count)
    return [quotient + (i < remainder) for i in range(count)]


def distribute(total, weights):
    whole = sum(weights)
    portions = [total * weight // whole for weight in weights]
    order = sorted(
        range(len(weights)),
        key=lambda i: (-(total * weights[i] % whole), i),
    )
    remainder = total - sum(portions)
    for i in order[:remainder]:
        portions[i] += 1
    return portions


def currency_note(item):
    if not item["currency"]:
        return ""
    return f" [{money(item['amount'])} {item['currency']}]"


def involved(expense, name):
    return any(
        person == name
        for person, _ in expense["payers"] + expense["participants"]
    )


def net(expense, name):
    paid = sum(
        contribution
        for (person, _), contribution in zip(
            expense["payers"], expense["contributions"]
        )
        if person == name
    )
    share = sum(
        value
        for (person, _), value in zip(expense["participants"], expense["shares"])
        if person == name
    )
    return paid - share


def chronological(item):
    return item["day"], item["record"]


def greedy(balances):
    remaining = balances.copy()
    transfers = []
    while True:
        debtors = [name for name in remaining if remaining[name] < 0]
        if not debtors:
            return transfers
        creditors = [name for name in remaining if remaining[name] > 0]
        sender = min(debtors, key=lambda name: (remaining[name], name))
        receiver = min(creditors, key=lambda name: (-remaining[name], name))
        value = min(-remaining[sender], remaining[receiver])
        transfers.append((sender, receiver, value))
        remaining[sender] += value
        remaining[receiver] -= value


def transfer_line(transfer, indent):
    sender, receiver, value = transfer
    return f"{indent}{sender} -> {receiver} {money(value)}"


class Splitter:
    def __init__(self):
        self.day = 1
        self.serial = 0
        self.members = {}
        self.currencies = {}
        self.expenses = {}
        self.settlements = []
        self.budgets = {}
        self.used = set()

    def next_record(self):
        self.serial += 1
        return self.serial

    def names(self, active=False):
        return sorted(
            name for name, member in self.members.items()
            if not active or member["active"]
        )

    def member(self, name, active=True):
        if name not in self.members:
            raise Invalid("unknown member " + name)
        if active and not self.members[name]["active"]:
            raise Invalid("inactive member " + name)

    def get_expense(self, reference, frozen=False):
        if reference not in self.expenses:
            raise Invalid("unknown expense " + reference)
        expense = self.expenses[reference]
        if frozen:
            for name, _ in expense["payers"] + expense["participants"]:
                if not self.members[name]["active"]:
                    raise Invalid("inactive member " + name)
        return expense

    def convert(self, value, currency):
        if not currency:
            return value
        if currency not in self.currencies:
            raise Invalid("unknown currency " + currency)
        return (value * self.currencies[currency] + 5000) // 10000

    def specification(self, token):
        parts = token.split("@")
        original = amount(parts[0])
        currency = parts[1] if len(parts) == 2 else ""
        total = self.convert(original, currency)
        if original == 0 or total == 0:
            raise Invalid("invalid amount")
        return {"amount": original, "currency": currency, "total": total}

    def portions(self, expense):
        weights = [value for _, value in expense["participants"]]
        original = expense["amount"]
        mode = expense["mode"]
        if mode == "EQUAL":
            return equal_distribution(original, len(weights))
        if mode == "EXACT":
            return weights
        if mode == "ADJUST":
            base = equal_distribution(original - sum(weights), len(weights))
            return [value + extra for value, extra in zip(base, weights)]
        return distribute(original, weights)

    def prepare(self, args, previous=None):
        reference, payer, specification, category, mode = args[:5]
        self.member(payer)
        converted = self.specification(specification)
        participants = []
        if mode == "EQUAL" and args[5] == "ALL":
            participants = [(name, 0) for name in self.names(active=True)]
        else:
            seen = set()
            for part in args[5:]:
                pieces = part.split(":")
                name = pieces[0]
                self.member(name)
                if name in seen:
                    raise Invalid("duplicate member " + name)
                seen.add(name)
                value = 0
                if len(pieces) == 2:
                    if mode in ("EXACT", "ADJUST"):
                        value = amount(pieces[1])
                    else:
                        value = int(pieces[1])
                participants.append((name, value))
        total_values = sum(value for _, value in participants)
        original = converted["amount"]
        invalid = (
            mode == "EXACT" and total_values != original
            or mode == "PERCENT" and total_values != 10000
            or mode == "SHARES" and total_values == 0
            or mode == "ADJUST" and total_values > original
        )
        if invalid:
            raise Invalid("splits do not add up")
        expense = {
            "id": reference,
            "day": previous["day"] if previous else self.day,
            "record": previous["record"] if previous else 0,
            **converted,
            "category": category,
            "mode": mode,
            "payers": [(payer, original)],
            "participants": participants,
            "contributions": [converted["total"]],
            "interval": previous["interval"] if previous else 0,
            "next": previous["next"] if previous else 0,
            "copies": previous["copies"] if previous else 0,
        }
        expense["shares"] = distribute(expense["total"], self.portions(expense))
        return expense

    def balances(self):
        values = dict.fromkeys(self.members, 0)
        for expense in self.expenses.values():
            for (name, _), value in zip(
                expense["payers"], expense["contributions"]
            ):
                values[name] += value
            for (name, _), value in zip(
                expense["participants"], expense["shares"]
            ):
                values[name] -= value
        for payment in self.settlements:
            values[payment["from"]] += payment["total"]
            values[payment["to"]] -= payment["total"]
        return values

    def spent(self, category):
        return sum(
            expense["total"] for expense in self.expenses.values()
            if expense["category"] == category
        )

    def warning(self, expense):
        category = expense["category"]
        spent = self.spent(category)
        budget = self.budgets.get(category)
        if budget is not None and spent > budget:
            return [f"  WARNING {category} over budget by {money(spent - budget)}"]
        return []

    def debts(self):
        totals = defaultdict(int)
        for expense in self.expenses.values():
            people = [
                (name, net(expense, name))
                for name in self.names() if involved(expense, name)
            ]
            borrowers = [[name, -value] for name, value in people if value < 0]
            lenders = [[name, value] for name, value in people if value > 0]
            i = 0
            j = 0
            while i < len(borrowers) and j < len(lenders):
                value = min(borrowers[i][1], lenders[j][1])
                totals[borrowers[i][0], lenders[j][0]] += value
                borrowers[i][1] -= value
                lenders[j][1] -= value
                if borrowers[i][1] == 0:
                    i += 1
                if lenders[j][1] == 0:
                    j += 1
        for payment in self.settlements:
            totals[payment["from"], payment["to"]] -= payment["total"]
        return totals

    def advance_day(self, token):
        day = int(token)
        if day <= self.day:
            raise Invalid("invalid day " + token)
        output = [f"DAY {day}"]
        while True:
            pending = [
                expense for expense in self.expenses.values()
                if expense["interval"] and expense["next"] <= day
            ]
            if not pending:
                break
            template = min(pending, key=lambda item: (item["next"], item["record"]))
            active = all(
                self.members[name]["active"]
                for name, _ in template["payers"] + template["participants"]
            )
            total = self.convert(template["amount"], template["currency"])
            if not active or total == 0:
                template["interval"] = 0
                output.append("  CANCEL " + template["id"])
                continue
            template["copies"] += 1
            reference = f"{template['id']}#{template['copies'] + 1}"
            copy = {
                **template,
                "id": reference,
                "day": template["next"],
                "record": self.next_record(),
                "payers": template["payers"].copy(),
                "participants": template["participants"].copy(),
                "total": total,
                "shares": distribute(total, self.portions(template)),
                "contributions": distribute(
                    total, [value for _, value in template["payers"]]
                ),
                "interval": 0,
                "next": 0,
                "copies": 0,
            }
            self.expenses[reference] = copy
            self.used.add(reference)
            template["next"] += template["interval"]
            output.append(f"  RECUR {reference} {money(total)}")
            output.extend(self.warning(copy))
        self.day = day
        return output

    def record_expense(self, name, args):
        previous = None
        if name == "EXPENSE":
            if args[0] in self.used:
                raise Invalid("duplicate id " + args[0])
        else:
            previous = self.get_expense(args[0], frozen=True)
        expense = self.prepare(args, previous)
        if previous is None:
            expense["record"] = self.next_record()
            self.used.add(expense["id"])
        self.expenses[expense["id"]] = expense
        shares = " + ".join(
            f"{person} {money(value)}"
            for (person, _), value in zip(
                expense["participants"], expense["shares"]
            )
        )
        output = [
            f"{name} {expense['id']} {money(expense['total'])}"
            f"{currency_note(expense)} = {shares}"
        ]
        return output + self.warning(expense)

    def change_payers(self, args):
        expense = self.get_expense(args[0], frozen=True)
        payers = []
        seen = set()
        for token in args[1:]:
            name, value = token.split(":")
            self.member(name)
            if name in seen:
                raise Invalid("duplicate member " + name)
            seen.add(name)
            payers.append((name, amount(value)))
        if sum(value for _, value in payers) != expense["amount"]:
            raise Invalid("payers do not add up")
        expense["payers"] = payers
        expense["contributions"] = distribute(
            expense["total"], [value for _, value in payers]
        )
        display = " + ".join(
            f"{person} {money(value)}"
            for (person, _), value in zip(payers, expense["contributions"])
        )
        return [
            f"PAYERS {expense['id']} {money(expense['total'])}"
            f"{currency_note(expense)} = {display}"
        ]

    def history(self, name):
        self.member(name, active=False)
        items = []
        for expense in self.expenses.values():
            if involved(expense, name):
                items.append({
                    "day": expense["day"], "record": expense["record"],
                    "label": expense["id"], "change": net(expense, name),
                })
        for payment in self.settlements:
            if name in (payment["from"], payment["to"]):
                change = payment["total"]
                if name == payment["to"]:
                    change = -change
                items.append({
                    "day": payment["day"], "record": payment["record"],
                    "label": f"{payment['from']}->{payment['to']}",
                    "change": change,
                })
        running = 0
        output = ["HISTORY " + name]
        for item in sorted(items, key=chronological):
            running += item["change"]
            output.append(
                f"  day {item['day']} {item['label']} {signed(item['change'])}"
                f" balance {signed(running)}"
            )
        return output

    def matrix(self):
        names = self.names(active=True)
        if not names:
            return ["MATRIX", "  (none)"]
        debts = self.debts()
        cells = [
            [
                "-" if row == column else money(max(
                    0, debts[row, column] - debts[column, row]
                ))
                for column in names
            ]
            for row in names
        ]
        name_width = max(map(len, names))
        width = max(map(len, names + [cell for row in cells for cell in row]))
        output = [
            "MATRIX",
            " " * name_width + "".join("  " + name.rjust(width) for name in names),
        ]
        for name, row in zip(names, cells):
            output.append(
                name.ljust(name_width)
                + "".join("  " + cell.rjust(width) for cell in row)
            )
        return output

    def categories(self):
        output = ["CATEGORY"]
        categories = {expense["category"] for expense in self.expenses.values()}
        total = sum(expense["total"] for expense in self.expenses.values())
        for category in sorted(categories, key=lambda item: (-self.spent(item), item)):
            spent = self.spent(category)
            output.append(f"  {category} {money(spent)} {percentage(spent, total)}")
            shares = defaultdict(int)
            for expense in self.expenses.values():
                if expense["category"] == category:
                    for (name, _), value in zip(
                        expense["participants"], expense["shares"]
                    ):
                        shares[name] += value
            ordered = sorted(shares, key=lambda name: (-shares[name], name))
            for name in ordered:
                value = shares[name]
                if value:
                    output.append(
                        f"    {name} {money(value)} {percentage(value, spent)}"
                    )
        return output

    def totals(self):
        output = ["TOTALS"]
        for name in self.names():
            paid = 0
            share = 0
            for expense in self.expenses.values():
                paid += sum(
                    value for (person, _), value in zip(
                        expense["payers"], expense["contributions"]
                    ) if person == name
                )
                share += sum(
                    value for (person, _), value in zip(
                        expense["participants"], expense["shares"]
                    ) if person == name
                )
            sent = sum(
                payment["total"] for payment in self.settlements
                if payment["from"] == name
            )
            received = sum(
                payment["total"] for payment in self.settlements
                if payment["to"] == name
            )
            output.append(
                f"  {name} paid {money(paid)} share {money(share)}"
                f" sent {money(sent)} received {money(received)}"
            )
        currencies = sorted({
            expense["currency"] for expense in self.expenses.values()
            if expense["currency"]
        })
        for currency in currencies:
            selected = [
                expense for expense in self.expenses.values()
                if expense["currency"] == currency
            ]
            original = sum(expense["amount"] for expense in selected)
            total = sum(expense["total"] for expense in selected)
            output.append(
                f"  currency {currency} expenses {len(selected)}"
                f" amount {money(original)} base {money(total)}"
            )
        total = sum(expense["total"] for expense in self.expenses.values())
        settled = sum(payment["total"] for payment in self.settlements)
        output.append(
            f"  expenses {len(self.expenses)} total {money(total)}"
            f" settlements {len(self.settlements)} total {money(settled)}"
        )
        return output

    def expense_list(self, line, args):
        if args[0] == "MEMBER":
            self.member(args[1], active=False)
        selected = []
        for expense in self.expenses.values():
            matches = (
                args[0] == "ALL"
                or args[0] == "CATEGORY" and expense["category"] == args[1]
                or args[0] == "MEMBER" and involved(expense, args[1])
                or args[0] == "DAYS"
                and int(args[1]) <= expense["day"] <= int(args[2])
            )
            if matches:
                selected.append(expense)
        output = [line]
        for expense in sorted(selected, key=chronological):
            payers = ",".join(name for name, _ in expense["payers"])
            output.append(
                f"  day {expense['day']} {expense['id']} {expense['category']}"
                f" {money(expense['total'])} by {payers}"
            )
        output.append(
            f"  count {len(selected)}"
            f" total {money(sum(expense['total'] for expense in selected))}"
        )
        return output

    def show(self, reference):
        expense = self.get_expense(reference)
        output = [
            "SHOW " + reference,
            f"  day {expense['day']} category {expense['category']}"
            f" mode {expense['mode']} total {money(expense['total'])}"
            + currency_note(expense),
        ]
        for (name, _), value in zip(expense["payers"], expense["contributions"]):
            output.append(f"  paid {name} {money(value)}")
        units = sum(value for _, value in expense["participants"])
        for (name, specified), value in zip(
            expense["participants"], expense["shares"]
        ):
            suffix = ""
            if expense["mode"] == "EXACT":
                suffix = " " + money(specified)
            elif expense["mode"] == "PERCENT":
                suffix = " " + money(specified) + "%"
            elif expense["mode"] == "SHARES":
                suffix = f" {specified}/{units}"
            elif expense["mode"] == "ADJUST":
                suffix = " +" + money(specified)
            output.append(f"  share {name} {money(value)}{suffix}")
        if expense["interval"]:
            output.append(
                f"  recurring interval {expense['interval']} next {expense['next']}"
            )
        return output

    def optimal(self):
        balances = self.balances()
        names = [name for name in self.names() if balances[name]]
        if len(names) > 12:
            raise Invalid("too many members")
        full = (1 << len(names)) - 1
        sums = [0] * (full + 1)
        for mask in range(1, full + 1):
            bit = mask & -mask
            index = bit.bit_length() - 1
            sums[mask] = sums[mask ^ bit] + balances[names[index]]

        @cache
        def best(mask):
            if not mask:
                return 0
            first = mask & -mask
            maximum = 0
            sub = mask
            while sub:
                if sub & first and sums[sub] == 0:
                    maximum = max(maximum, 1 + best(mask ^ sub))
                sub = (sub - 1) & mask
            return maximum

        def group_names(mask):
            return [name for i, name in enumerate(names) if mask & (1 << i)]

        groups = []
        mask = full
        while mask:
            first = mask & -mask
            candidates = []
            sub = mask
            while sub:
                if (
                    sub & first and sums[sub] == 0
                    and 1 + best(mask ^ sub) == best(mask)
                ):
                    candidates.append(sub)
                sub = (sub - 1) & mask
            chosen = min(candidates, key=group_names)
            groups.append(group_names(chosen))
            mask ^= chosen
        output = [
            f"SIMPLIFY OPTIMAL transfers {len(names) - len(groups)}"
            f" groups {len(groups)}"
        ]
        for group in groups:
            output.append("  group " + " ".join(group))
            transfers = greedy({name: balances[name] for name in group})
            output.extend(transfer_line(transfer, "    ") for transfer in transfers)
        return output

    def command(self, line):
        name, *args = line.split()
        output = []
        if name == "DAY":
            return self.advance_day(args[0])
        if name in ("EXPENSE", "EDIT"):
            return self.record_expense(name, args)
        if name == "PAYERS":
            return self.change_payers(args)
        if name == "MEMBER":
            old = self.members.get(args[0])
            if old and old["active"]:
                raise Invalid("duplicate member " + args[0])
            self.members[args[0]] = {"active": True, "day": self.day}
            output.append(f"MEMBER {args[0]} {'rejoined' if old else 'joined'}")
        elif name == "LEAVE":
            self.member(args[0])
            if self.balances()[args[0]] != 0:
                raise Invalid("member has a balance " + args[0])
            self.members[args[0]] = {"active": False, "day": self.day}
            output.append("LEAVE " + args[0])
        elif name == "CURRENCY":
            old = self.currencies.get(args[0])
            value = int(args[1])
            self.currencies[args[0]] = value
            suffix = "" if old is None else " was " + rate_text(old)
            output.append(f"CURRENCY {args[0]} {rate_text(value)}{suffix}")
        elif name == "DELETE":
            self.get_expense(args[0], frozen=True)
            del self.expenses[args[0]]
            output.append("DELETE " + args[0])
        elif name == "RECURRING":
            expense = self.get_expense(args[0])
            interval = int(args[1])
            expense["interval"] = interval
            expense["next"] = self.day + interval
            suffix = (
                f" interval {interval} next {expense['next']}"
                if interval else " stopped"
            )
            output.append("RECURRING " + args[0] + suffix)
        elif name == "SETTLE":
            self.member(args[0])
            self.member(args[1])
            if args[0] == args[1]:
                raise Invalid("same member " + args[0])
            converted = self.specification(args[2])
            payment = {
                "from": args[0], "to": args[1], **converted,
                "day": self.day, "record": self.next_record(),
            }
            self.settlements.append(payment)
            output.append(
                f"SETTLE {args[0]} -> {args[1]} {money(payment['total'])}"
                + currency_note(payment)
            )
        elif name == "BUDGET":
            value = amount(args[1])
            if value:
                self.budgets[args[0]] = value
            else:
                self.budgets.pop(args[0], None)
            output.append(f"BUDGET {args[0]} " + (money(value) if value else "removed"))
        elif name == "BALANCES":
            balances = self.balances()
            output = ["BALANCES"] + [
                f"  {person} {signed(balances[person])}"
                for person in self.names(active=True)
            ]
        elif name == "OWES":
            self.member(args[0], active=False)
            debts = self.debts()
            output = ["OWES " + args[0]]
            for person in self.names():
                if person == args[0]:
                    continue
                value = debts[args[0], person] - debts[person, args[0]]
                if value > 0:
                    output.append(f"  {args[0]} owes {person} {money(value)}")
                elif value < 0:
                    output.append(f"  {person} owes {args[0]} {money(-value)}")
        elif name == "HISTORY":
            output = self.history(args[0])
        elif name == "MATRIX":
            output = self.matrix()
        elif name == "CATEGORY":
            output = self.categories()
        elif name == "BUDGETS":
            output = ["BUDGETS"]
            for category, budget in sorted(self.budgets.items()):
                spent = self.spent(category)
                suffix = (
                    " left " + money(budget - spent) if spent <= budget
                    else " over " + money(spent - budget)
                )
                output.append(
                    f"  {category} spent {money(spent)} budget {money(budget)}"
                    f" used {percentage(spent, budget)}{suffix}"
                )
        elif name == "TOTALS":
            output = self.totals()
        elif name == "MEMBERS":
            output = ["MEMBERS"]
            for person in self.names():
                member = self.members[person]
                count = sum(involved(expense, person) for expense in self.expenses.values())
                status = "active" if member["active"] else "left"
                output.append(
                    f"  {person} {status} day {member['day']} expenses {count}"
                )
        elif name == "EXPENSES":
            output = self.expense_list(line, args)
        elif name == "PERIODS":
            width = int(args[0])
            groups = defaultdict(list)
            for expense in self.expenses.values():
                groups[(expense["day"] - 1) // width].append(expense)
            output = [f"PERIODS {width}"]
            for index, group in sorted(groups.items()):
                total = sum(expense["total"] for expense in group)
                output.append(
                    f"  days {index * width + 1}-{index * width + width}"
                    f" expenses {len(group)} total {money(total)}"
                )
        elif name == "SHOW":
            output = self.show(args[0])
        elif name == "SIMPLIFY":
            if args[0] == "OPTIMAL":
                return self.optimal()
            transfers = greedy(self.balances())
            output = [f"SIMPLIFY GREEDY transfers {len(transfers)}"]
            output.extend(transfer_line(transfer, "  ") for transfer in transfers)
        none_commands = {
            "BALANCES", "OWES", "HISTORY", "CATEGORY", "BUDGETS", "MEMBERS", "PERIODS"
        }
        if name in none_commands and len(output) == 1:
            output.append("  (none)")
        return output


def main():
    lines = sys.stdin.read().splitlines()
    splitter = Splitter()
    output = []
    for line in lines[1:int(lines[0]) + 1]:
        try:
            output.extend(splitter.command(line))
        except Invalid as error:
            output.append("ERROR " + str(error))
    sys.stdout.write("\n".join(output) + "\n")


if __name__ == "__main__":
    main()
