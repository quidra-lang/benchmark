import sys
from collections import Counter


class Invalid(Exception):
    pass


RULES = {
    "STUDENT": {
        "limit": 3, "period": 14, "fine": 25, "cap": 1000,
        "reservations": 2, "fee": 50,
    },
    "STAFF": {
        "limit": 10, "period": 28, "fine": 10, "cap": 2000,
        "reservations": 5, "fee": 100,
    },
}


def amount(text):
    whole, fraction = text.split(".")
    return int(whole) * 100 + int(fraction)


def money(value):
    return f"{value // 100}.{value % 100:02d}"


def normalize_isbn(text):
    raw = text.replace("-", "")
    if (
        len(raw) == 10
        and raw[:9].isdigit()
        and raw[-1] in "0123456789X"
    ):
        total = sum(
            (10 - i) * (10 if c == "X" else int(c))
            for i, c in enumerate(raw)
        )
        if total % 11:
            raise Invalid("invalid isbn")
        prefix = "978" + raw[:9]
        checksum = sum(
            int(c) * (1 if i % 2 == 0 else 3)
            for i, c in enumerate(prefix)
        )
        return prefix + str((10 - checksum % 10) % 10)
    if (
        len(raw) == 13 and raw[:3] in ("978", "979")
        and raw.isdigit()
    ):
        total = sum(
            int(c) * (1 if i % 2 == 0 else 3)
            for i, c in enumerate(raw)
        )
        if total % 10 == 0:
            return raw
    raise Invalid("invalid isbn")


def holdings(title):
    return sum(
        copy["state"] in ("AVAILABLE", "LOANED", "HOLD")
        for copy in title["copies"]
    )


def copy_order(copy):
    return copy["isbn"], copy["no"]


def loan_order(copy):
    return copy["due"], copy["isbn"]


def hold_order(copy):
    return copy["expiry"], copy["isbn"]


class Library:
    def __init__(self):
        self.day = 1
        self.closed = set()
        self.titles = {}
        self.members = {}
        self.counts = {
            "borrowed": 0, "returned": 0, "renewed": 0, "lost": 0,
            "FINE": 0, "FEE": 0, "PRICE": 0, "paid": 0, "waived": 0,
        }

    def member(self, identifier):
        if identifier not in self.members:
            raise Invalid("unknown member")
        return self.members[identifier]

    def title(self, token):
        identifier = normalize_isbn(token)
        if identifier not in self.titles:
            raise Invalid("unknown book")
        return self.titles[identifier]

    def common(self, identifier, token):
        member = self.member(identifier)
        title = self.title(token)
        return member, title

    def all_copies(self):
        return [
            copy for title in self.titles.values()
            for copy in title["copies"]
        ]

    def balance(self, member):
        return sum(item["unpaid"] for item in member["items"])

    def reservations(self, member):
        queued = sum(
            member["id"] in title["queue"] for title in self.titles.values()
        )
        return len(member["holds"]) + queued

    def open_day(self, day):
        while day in self.closed:
            day += 1
        return day

    def late(self, copy):
        days = max(0, self.day - copy["due"])
        rule = RULES[self.members[copy["member"]]["type"]]
        return days, min(days * rule["fine"], rule["cap"])

    def charge(self, member, kind, title, value):
        if not value:
            return
        member["items"].append({
            "no": len(member["items"]) + 1,
            "day": self.day,
            "kind": kind,
            "isbn": title["isbn"],
            "amount": value,
            "unpaid": value,
        })
        self.counts[kind] += value

    def release(self, title, copy):
        if not title["queue"]:
            copy["state"] = "AVAILABLE"
            copy["member"] = None
            return []
        identifier = title["queue"].pop(0)
        copy["state"] = "HOLD"
        copy["member"] = identifier
        copy["expiry"] = self.open_day(self.day + 3)
        self.members[identifier]["holds"][title["isbn"]] = copy
        return [
            f"HOLD {title['isbn']} copy {copy['no']}"
            f" {identifier} until {copy['expiry']}"
        ]

    def end_loan(self, title, copy, result):
        member = self.members[copy["member"]]
        days, fine = self.late(copy)
        del member["loans"][title["isbn"]]
        self.charge(member, "FINE", title, fine)
        member["history"].append(
            f"{result} {title['isbn']} copy {copy['no']}"
            f" from {copy['loan_day']} to {self.day}"
            f" late {days} fine {money(fine)}"
        )
        return days, fine

    def loss(self, title, copy, heading):
        member = self.members[copy["member"]]
        days, fine = self.end_loan(title, copy, "LOST")
        member["history"][-1] += " price " + money(title["price"])
        self.charge(member, "PRICE", title, title["price"])
        copy["state"] = "LOST"
        copy["member"] = None
        self.counts["lost"] += 1
        output = [
            f"{heading} {member['id']} {title['isbn']} copy {copy['no']}"
            f" late {days} fine {money(fine)} price {money(title['price'])}"
            f" balance {money(self.balance(member))}"
        ]
        if not holdings(title) and title["queue"]:
            output.extend(
                f"DROPPED {title['isbn']} {identifier}"
                for identifier in title["queue"]
            )
            title["queue"].clear()
        return output

    def renewal_reason(self, title, copy):
        if copy["due"] < self.day:
            return "loan overdue"
        if copy["renewals"] == 2:
            return "renewal limit"
        if title["queue"]:
            return "title reserved"
        return None

    def renew(self, member, title, copy):
        copy["due"] = self.open_day(self.day + RULES[member["type"]]["period"])
        copy["renewals"] += 1
        self.counts["renewed"] += 1
        return (
            f"RENEW {member['id']} {title['isbn']} copy {copy['no']}"
            f" due {copy['due']} renewals {copy['renewals']}"
        )

    def advance(self, day):
        if day <= self.day:
            raise Invalid("invalid day")
        output = [f"DAY {day}"]
        while self.day < day:
            self.day += 1
            losses = [
                copy for copy in self.all_copies()
                if copy["state"] == "LOANED" and copy["due"] + 365 <= self.day
            ]
            losses.sort(key=lambda copy: (copy["member"], copy["isbn"]))
            for copy in losses:
                output.extend(self.loss(self.titles[copy["isbn"]], copy, "AUTOLOST"))
            expired = [
                copy for copy in self.all_copies()
                if copy["state"] == "HOLD" and copy["expiry"] < self.day
            ]
            for copy in sorted(expired, key=copy_order):
                title = self.titles[copy["isbn"]]
                member = self.members[copy["member"]]
                fee = RULES[member["type"]]["fee"]
                self.charge(member, "FEE", title, fee)
                del member["holds"][copy["isbn"]]
                output.append(
                    f"EXPIRED {copy['isbn']} copy {copy['no']}"
                    f" {member['id']} fee {money(fee)}"
                )
                output.extend(self.release(title, copy))
        return output

    def close_day(self, day):
        if day <= self.day:
            raise Invalid("invalid day")
        if day in self.closed:
            raise Invalid("already closed")
        self.closed.add(day)
        output = [f"CLOSED {day}"]
        for copy in sorted(self.all_copies(), key=copy_order):
            if copy["state"] == "LOANED" and copy["due"] == day:
                copy["due"] = self.open_day(day)
                output.append(
                    f"MOVED {copy['isbn']} copy {copy['no']}"
                    f" {copy['member']} due {copy['due']}"
                )
            elif copy["state"] == "HOLD" and copy["expiry"] == day:
                copy["expiry"] = self.open_day(day)
                output.append(
                    f"MOVED {copy['isbn']} copy {copy['no']}"
                    f" {copy['member']} until {copy['expiry']}"
                )
        return output

    def add_book(self, args):
        identifier = normalize_isbn(args[0])
        name = " ".join(args[3:])
        title = self.titles.get(identifier)
        if title and title["name"] != name:
            raise Invalid("title mismatch")
        if title is None:
            title = {
                "isbn": identifier, "name": name, "price": amount(args[2]),
                "copies": [], "queue": [], "borrowed": 0,
            }
            self.titles[identifier] = title
        title["price"] = amount(args[2])
        added = []
        for _ in range(int(args[1])):
            copy = {
                "isbn": identifier, "no": len(title["copies"]) + 1,
                "state": "AVAILABLE", "member": None, "loan_day": 0,
                "due": 0, "renewals": 0, "expiry": 0,
            }
            title["copies"].append(copy)
            added.append(copy)
        output = [
            f"ADDBOOK {identifier} added {len(added)} total {holdings(title)}"
        ]
        for copy in added:
            output.extend(self.release(title, copy))
        return output

    def add_member(self, args):
        identifier, kind = args[:2]
        if identifier in self.members:
            raise Invalid("duplicate member")
        if kind not in RULES:
            raise Invalid("unknown type")
        self.members[identifier] = {
            "id": identifier, "type": kind, "name": " ".join(args[2:]),
            "loans": {}, "holds": {}, "items": [], "history": [],
        }
        return [
            f"ADDMEMBER {identifier} {kind}"
            f" loans {RULES[kind]['limit']} days {RULES[kind]['period']}"
        ]

    def circulate(self, name, args):
        member, title = self.common(args[0], args[1])
        identifier = title["isbn"]
        loan = member["loans"].get(identifier)
        hold = member["holds"].get(identifier)
        rule = RULES[member["type"]]
        if name == "BORROW":
            if self.day in self.closed:
                raise Invalid("library closed")
            if loan is not None:
                raise Invalid("already borrowed")
            if self.balance(member) > 500:
                raise Invalid("member blocked")
            if any(copy["due"] < self.day for copy in member["loans"].values()):
                raise Invalid("overdue loans")
            if len(member["loans"]) >= rule["limit"]:
                raise Invalid("loan limit")
            copy = hold
            if copy is None:
                copy = next(
                    (copy for copy in title["copies"] if copy["state"] == "AVAILABLE"),
                    None,
                )
            if copy is None:
                if any(copy["state"] == "HOLD" for copy in title["copies"]):
                    raise Invalid("all copies on hold")
                raise Invalid("no copy available")
            member["holds"].pop(identifier, None)
            copy.update(
                state="LOANED", member=member["id"], loan_day=self.day,
                due=self.open_day(self.day + rule["period"]), renewals=0,
            )
            member["loans"][identifier] = copy
            title["borrowed"] += 1
            self.counts["borrowed"] += 1
            return [
                f"BORROW {member['id']} {identifier}"
                f" copy {copy['no']} due {copy['due']}"
            ]
        if name in ("RETURN", "LOST", "RENEW"):
            if loan is None:
                raise Invalid("not borrowed")
            if name == "LOST":
                return self.loss(title, loan, "LOST")
            if name == "RETURN":
                days, fine = self.end_loan(title, loan, "RETURNED")
                self.counts["returned"] += 1
                output = [
                    f"RETURN {member['id']} {identifier} copy {loan['no']}"
                    f" late {days} fine {money(fine)}"
                    f" balance {money(self.balance(member))}"
                ]
                return output + self.release(title, loan)
            if self.balance(member) > 500:
                raise Invalid("member blocked")
            reason = self.renewal_reason(title, loan)
            if reason:
                raise Invalid(reason)
            return [self.renew(member, title, loan)]
        queued = member["id"] in title["queue"]
        if name == "CANCEL":
            if not queued and hold is None:
                raise Invalid("not reserved")
            if queued:
                title["queue"].remove(member["id"])
                return [f"CANCEL {member['id']} {identifier} queue"]
            del member["holds"][identifier]
            output = [f"CANCEL {member['id']} {identifier} hold copy {hold['no']}"]
            return output + self.release(title, hold)
        if loan is not None:
            raise Invalid("already borrowed")
        if queued or hold is not None:
            raise Invalid("already reserved")
        if self.balance(member) > 500:
            raise Invalid("member blocked")
        if self.reservations(member) >= rule["reservations"]:
            raise Invalid("reservation limit")
        if not holdings(title):
            raise Invalid("no copies")
        if any(copy["state"] == "AVAILABLE" for copy in title["copies"]):
            raise Invalid("copy available")
        title["queue"].append(member["id"])
        position = len(title["queue"])
        days = sorted(
            copy["due"] for copy in title["copies"] if copy["state"] == "LOANED"
        )
        estimate = days[position - 1] if position <= len(days) else "none"
        return [
            f"RESERVE {member['id']} {identifier}"
            f" position {position} estimate {estimate}"
        ]

    def renew_all(self, identifier):
        member = self.member(identifier)
        if not member["loans"]:
            raise Invalid("no loans")
        if self.balance(member) > 500:
            raise Invalid("member blocked")
        output = []
        renewed = 0
        skipped = 0
        for copy in sorted(member["loans"].values(), key=lambda copy: copy["isbn"]):
            title = self.titles[copy["isbn"]]
            reason = self.renewal_reason(title, copy)
            if reason:
                output.append(f"SKIP {copy['isbn']} {reason}")
                skipped += 1
            else:
                output.append(self.renew(member, title, copy))
                renewed += 1
        output.append(
            f"RENEWALL {identifier} renewed {renewed} skipped {skipped}"
        )
        return output

    def charges(self, name, args):
        member = self.member(args[0])
        if name == "PAYFINE":
            if not self.balance(member):
                raise Invalid("no fines")
            remaining = amount(args[1])
            items = []
            for item in member["items"]:
                applied = min(remaining, item["unpaid"])
                if applied:
                    item["unpaid"] -= applied
                    remaining -= applied
                    items.append(
                        f"ITEM {item['no']} {item['kind']} paid {money(applied)}"
                        f" remaining {money(item['unpaid'])}"
                    )
                if not remaining:
                    break
            paid = amount(args[1]) - remaining
            self.counts["paid"] += paid
            return [
                f"PAYFINE {member['id']} paid {money(paid)} change {money(remaining)}"
                f" balance {money(self.balance(member))}",
                *items,
            ]
        if name == "WAIVE":
            number = int(args[1])
            if not 1 <= number <= len(member["items"]):
                raise Invalid("unknown item")
            item = member["items"][number - 1]
            if not item["unpaid"]:
                raise Invalid("item settled")
            value = item["unpaid"]
            item["unpaid"] = 0
            self.counts["waived"] += value
            return [
                f"WAIVE {member['id']} item {number} {item['kind']}"
                f" amount {money(value)} balance {money(self.balance(member))}"
            ]
        items = [item for item in member["items"] if item["unpaid"]]
        output = [
            f"FINES {member['id']} items {len(items)}"
            f" balance {money(self.balance(member))}"
        ]
        output.extend(
            f"{item['no']} day {item['day']} {item['kind']} {item['isbn']}"
            f" amount {money(item['amount'])} remaining {money(item['unpaid'])}"
            for item in items
        )
        return output

    def member_lines(self, member):
        value = self.balance(member)
        state = "BLOCKED" if value > 500 else "OK"
        rule = RULES[member["type"]]
        output = [
            f"MEMBER {member['id']} {member['type']} {member['name']}",
            f"STATUS loans {len(member['loans'])}/{rule['limit']}"
            f" reservations {self.reservations(member)}/{rule['reservations']}"
            f" balance {money(value)} {state}",
        ]
        for copy in sorted(member["loans"].values(), key=loan_order):
            days, fine = self.late(copy)
            suffix = f" late {days} fine {money(fine)}" if days else ""
            output.append(
                f"LOAN {copy['isbn']} copy {copy['no']} due {copy['due']}"
                f" renewals {copy['renewals']}{suffix}"
            )
        for copy in sorted(member["holds"].values(), key=hold_order):
            output.append(
                f"HOLD {copy['isbn']} copy {copy['no']} until {copy['expiry']}"
            )
        for title in sorted(self.titles.values(), key=lambda title: title["isbn"]):
            if member["id"] in title["queue"]:
                position = title["queue"].index(member["id"]) + 1
                output.append(f"QUEUE {title['isbn']} position {position}")
        return output

    def notices(self):
        output = []
        for identifier, member in sorted(self.members.items()):
            loans = sorted(member["loans"].values(), key=loan_order)
            for copy in loans:
                if copy["due"] < self.day:
                    output.append(
                        f"OVERDUE {identifier} {copy['isbn']} due {copy['due']}"
                    )
            for copy in loans:
                if self.day <= copy["due"] <= self.day + 2:
                    output.append(
                        f"DUESOON {identifier} {copy['isbn']} due {copy['due']}"
                    )
            for copy in sorted(member["holds"].values(), key=hold_order):
                output.append(
                    f"PICKUP {identifier} {copy['isbn']} until {copy['expiry']}"
                )
        return [f"NOTICES {len(output)}", *output]

    def book_lines(self, title):
        output = [
            f"BOOK {title['isbn']} {title['name']}",
            f"PRICE {money(title['price'])} copies {holdings(title)}"
            f" borrowed {title['borrowed']}",
        ]
        for copy in title["copies"]:
            line = f"COPY {copy['no']} {copy['state']}"
            if copy["state"] == "LOANED":
                line += f" {copy['member']} due {copy['due']}"
            elif copy["state"] == "HOLD":
                line += f" {copy['member']} until {copy['expiry']}"
            output.append(line)
        queue = " ".join(title["queue"])
        output.append(f"QUEUE {len(title['queue'])}" + (" " + queue if queue else ""))
        return output

    def inventory(self):
        states = Counter(copy["state"] for copy in self.all_copies())
        total = states["AVAILABLE"] + states["LOANED"] + states["HOLD"]
        output = [
            f"INVENTORY titles {len(self.titles)} copies {total}"
            f" available {states['AVAILABLE']} loaned {states['LOANED']}"
            f" hold {states['HOLD']} lost {states['LOST']}"
            f" withdrawn {states['WITHDRAWN']}"
        ]
        for title in sorted(self.titles.values(), key=lambda title: title["isbn"]):
            count = Counter(copy["state"] for copy in title["copies"])
            output.append(
                f"{title['isbn']} copies {holdings(title)}"
                f" available {count['AVAILABLE']} loaned {count['LOANED']}"
                f" hold {count['HOLD']} queue {len(title['queue'])}"
            )
        return output

    def statistics(self):
        counts = self.counts
        active = sum(copy["state"] == "LOANED" for copy in self.all_copies())
        outstanding = sum(self.balance(member) for member in self.members.values())
        output = [
            f"STATS day {self.day} titles {len(self.titles)}"
            f" members {len(self.members)} closed {len(self.closed)}",
            f"LOANS borrowed {counts['borrowed']} returned {counts['returned']}"
            f" renewed {counts['renewed']} lost {counts['lost']} active {active}",
            f"MONEY fines {money(counts['FINE'])} fees {money(counts['FEE'])}"
            f" charges {money(counts['PRICE'])} paid {money(counts['paid'])}"
            f" waived {money(counts['waived'])} outstanding {money(outstanding)}",
        ]
        top = sorted(
            (title for title in self.titles.values() if title["borrowed"]),
            key=lambda title: (-title["borrowed"], title["isbn"]),
        )[:3]
        output.extend(
            f"TOP {i} {title['isbn']} {title['borrowed']} {title['name']}"
            for i, title in enumerate(top, 1)
        )
        return output

    def inspect(self, name, args):
        if name == "SEARCH":
            keyword = " ".join(args).lower()
            titles = sorted(
                (
                    title for title in self.titles.values()
                    if keyword in title["name"].lower()
                ),
                key=lambda title: (title["name"].lower(), title["isbn"]),
            )
            output = [f"SEARCH {len(titles)}"]
            for title in titles:
                available = sum(
                    copy["state"] == "AVAILABLE" for copy in title["copies"]
                )
                output.append(
                    f"{title['isbn']} {available}/{holdings(title)} {title['name']}"
                )
            return output
        if name == "OVERDUE":
            copies = sorted(
                (
                    copy for copy in self.all_copies()
                    if copy["state"] == "LOANED" and copy["due"] < self.day
                ),
                key=lambda copy: (copy["due"], copy["member"], copy["isbn"]),
            )
            output = [f"OVERDUE {len(copies)}"]
            for copy in copies:
                days, fine = self.late(copy)
                output.append(
                    f"{copy['member']} {copy['isbn']} copy {copy['no']}"
                    f" due {copy['due']} late {days} fine {money(fine)}"
                )
            return output
        if name == "NOTICES":
            return self.notices()
        if name == "MEMBER":
            return self.member_lines(self.member(args[0]))
        if name == "MEMBERS":
            output = [f"MEMBERS {len(self.members)}"]
            for identifier, member in sorted(self.members.items()):
                value = self.balance(member)
                state = "BLOCKED" if value > 500 else "OK"
                output.append(
                    f"{identifier} {member['type']} loans {len(member['loans'])}"
                    f" reservations {self.reservations(member)}"
                    f" balance {money(value)} {state}"
                )
            return output
        if name == "BOOK":
            return self.book_lines(self.title(args[0]))
        if name == "INVENTORY":
            return self.inventory()
        if name == "HISTORY":
            member = self.member(args[0])
            return [
                f"HISTORY {member['id']} {len(member['history'])}",
                *member["history"],
            ]
        return self.statistics()

    def command(self, line):
        name, *args = line.split()
        if name == "DAY":
            return self.advance(int(args[0]))
        if name == "CLOSED":
            return self.close_day(int(args[0]))
        if name == "ADDBOOK":
            return self.add_book(args)
        if name == "ADDMEMBER":
            return self.add_member(args)
        if name == "WITHDRAW":
            title = self.title(args[0])
            number = int(args[1])
            if not 1 <= number <= len(title["copies"]):
                raise Invalid("unknown copy")
            copy = title["copies"][number - 1]
            if copy["state"] != "AVAILABLE":
                raise Invalid("copy not available")
            copy["state"] = "WITHDRAWN"
            return [
                f"WITHDRAW {title['isbn']} copy {copy['no']}"
                f" total {holdings(title)}"
            ]
        if name in ("BORROW", "RETURN", "RENEW", "RESERVE", "CANCEL", "LOST"):
            return self.circulate(name, args)
        if name == "RENEWALL":
            return self.renew_all(args[0])
        if name in ("PAYFINE", "WAIVE", "FINES"):
            return self.charges(name, args)
        return self.inspect(name, args)


def main():
    lines = sys.stdin.read().splitlines()
    library = Library()
    output = []
    for line in lines[1:int(lines[0]) + 1]:
        try:
            output.extend(library.command(line))
        except Invalid as error:
            output.append("ERROR " + str(error))
    sys.stdout.write("\n".join(output) + "\n")


if __name__ == "__main__":
    main()
