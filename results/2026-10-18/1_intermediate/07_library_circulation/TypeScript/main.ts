import { readFileSync } from "node:fs";

type Rules = { limit: number; period: number; fine: number; cap: number; reservations: number; fee: number };
type Copy = { isbn: string; no: number; state: string; member: string; loanDay: number; due: number; renewals: number; expiry: number };
type Title = { isbn: string; name: string; price: number; copies: Copy[]; queue: string[]; borrowed: number };
type Item = { no: number; day: number; kind: string; isbn: string; amount: number; unpaid: number };
type Member = { id: string; type: string; name: string; loans: Map<string, Copy>; holds: Map<string, Copy>; items: Item[]; history: string[] };

class Invalid extends Error {}

function fail(reason: string): never {
    throw new Invalid(reason);
}

function amount(text: string): number {
    const [whole, fraction] = text.split(".");
    return Number(whole) * 100 + Number(fraction);
}

function money(value: number): string {
    return Math.floor(value / 100) + "." + String(value % 100).padStart(2, "0");
}

function lex(a: string, b: string): number {
    return a < b ? -1 : a > b ? 1 : 0;
}

function isbn(text: string): string {
    const raw = text.replace(/-/g, "");
    if (/^[0-9]{9}[0-9X]$/.test(raw)) {
        const sum = raw.split("").reduce((total, c, i) => total + (10 - i) * (c === "X" ? 10 : Number(c)), 0);
        if (sum % 11 !== 0) {
            fail("invalid isbn");
        }
        const prefix = "978" + raw.slice(0, 9);
        const checksum = prefix.split("").reduce((total, c, i) => total + Number(c) * (i % 2 === 0 ? 1 : 3), 0);
        return prefix + (10 - checksum % 10) % 10;
    }
    if (/^(978|979)[0-9]{10}$/.test(raw)) {
        const sum = raw.split("").reduce((total, c, i) => total + Number(c) * (i % 2 === 0 ? 1 : 3), 0);
        if (sum % 10 === 0) {
            return raw;
        }
    }
    return fail("invalid isbn");
}

const rules: Record<string, Rules> = {
    STUDENT: { limit: 3, period: 14, fine: 25, cap: 1000, reservations: 2, fee: 50 },
    STAFF: { limit: 10, period: 28, fine: 10, cap: 2000, reservations: 5, fee: 100 }
};

function holdings(title: Title): number {
    return title.copies.filter(copy => ["AVAILABLE", "LOANED", "HOLD"].includes(copy.state)).length;
}

function copyOrder(a: Copy, b: Copy): number {
    return lex(a.isbn, b.isbn) || a.no - b.no;
}

function loanOrder(a: Copy, b: Copy): number {
    return a.due - b.due || lex(a.isbn, b.isbn);
}

function holdOrder(a: Copy, b: Copy): number {
    return a.expiry - b.expiry || lex(a.isbn, b.isbn);
}

class Library {
    day = 1;
    closed = new Set<number>();
    titles = new Map<string, Title>();
    members = new Map<string, Member>();
    counts: Record<string, number> = { borrowed: 0, returned: 0, renewed: 0, lost: 0, FINE: 0, FEE: 0, PRICE: 0, paid: 0, waived: 0 };

    member(id: string): Member {
        const member = this.members.get(id);
        if (!member) {
            fail("unknown member");
        }
        return member;
    }

    title(token: string): Title {
        const title = this.titles.get(isbn(token));
        if (!title) {
            fail("unknown book");
        }
        return title;
    }

    common(id: string, token: string): [Member, Title] {
        const member = this.member(id);
        const title = this.title(token);
        return [member, title];
    }

    allCopies(): Copy[] {
        return [...this.titles.values()].flatMap(title => title.copies);
    }

    balance(member: Member): number {
        return member.items.reduce((sum, item) => sum + item.unpaid, 0);
    }

    reservations(member: Member): number {
        return member.holds.size + [...this.titles.values()].filter(title => title.queue.includes(member.id)).length;
    }

    openDay(day: number): number {
        while (this.closed.has(day)) {
            day++;
        }
        return day;
    }

    late(copy: Copy): number[] {
        const days = Math.max(0, this.day - copy.due);
        const rule = rules[this.members.get(copy.member)!.type];
        return [days, Math.min(days * rule.fine, rule.cap)];
    }

    charge(member: Member, kind: string, title: Title, value: number): void {
        if (!value) {
            return;
        }
        member.items.push({ no: member.items.length + 1, day: this.day, kind, isbn: title.isbn, amount: value, unpaid: value });
        this.counts[kind] += value;
    }

    release(title: Title, copy: Copy): string[] {
        if (!title.queue.length) {
            copy.state = "AVAILABLE";
            copy.member = "";
            return [];
        }
        const id = title.queue.shift()!;
        copy.state = "HOLD";
        copy.member = id;
        copy.expiry = this.openDay(this.day + 3);
        this.members.get(id)!.holds.set(title.isbn, copy);
        return ["HOLD " + title.isbn + " copy " + copy.no + " " + id + " until " + copy.expiry];
    }

    endLoan(title: Title, copy: Copy, result: string): number[] {
        const member = this.members.get(copy.member)!;
        const [late, fine] = this.late(copy);
        member.loans.delete(title.isbn);
        this.charge(member, "FINE", title, fine);
        member.history.push(result + " " + title.isbn + " copy " + copy.no + " from " + copy.loanDay +
            " to " + this.day + " late " + late + " fine " + money(fine));
        return [late, fine];
    }

    loss(title: Title, copy: Copy, heading: string): string[] {
        const member = this.members.get(copy.member)!;
        const [late, fine] = this.endLoan(title, copy, "LOST");
        member.history[member.history.length - 1] += " price " + money(title.price);
        this.charge(member, "PRICE", title, title.price);
        copy.state = "LOST";
        copy.member = "";
        this.counts.lost++;
        const output = [heading + " " + member.id + " " + title.isbn + " copy " + copy.no + " late " + late +
            " fine " + money(fine) + " price " + money(title.price) + " balance " + money(this.balance(member))];
        if (!holdings(title) && title.queue.length) {
            output.push(...title.queue.map(id => "DROPPED " + title.isbn + " " + id));
            title.queue = [];
        }
        return output;
    }

    renewalReason(title: Title, copy: Copy): string {
        if (copy.due < this.day) {
            return "loan overdue";
        }
        if (copy.renewals === 2) {
            return "renewal limit";
        }
        return title.queue.length ? "title reserved" : "";
    }

    renew(member: Member, title: Title, copy: Copy): string {
        copy.due = this.openDay(this.day + rules[member.type].period);
        copy.renewals++;
        this.counts.renewed++;
        return "RENEW " + member.id + " " + title.isbn + " copy " + copy.no + " due " + copy.due + " renewals " + copy.renewals;
    }

    advance(day: number): string[] {
        if (day <= this.day) {
            fail("invalid day");
        }
        const output = ["DAY " + day];
        while (this.day < day) {
            this.day++;
            const losses = this.allCopies().filter(copy => copy.state === "LOANED" && copy.due + 365 <= this.day)
                .sort((a, b) => lex(a.member, b.member) || lex(a.isbn, b.isbn));
            for (const copy of losses) {
                output.push(...this.loss(this.titles.get(copy.isbn)!, copy, "AUTOLOST"));
            }
            const expired = this.allCopies().filter(copy => copy.state === "HOLD" && copy.expiry < this.day).sort(copyOrder);
            for (const copy of expired) {
                const title = this.titles.get(copy.isbn)!;
                const member = this.members.get(copy.member)!;
                const fee = rules[member.type].fee;
                this.charge(member, "FEE", title, fee);
                member.holds.delete(copy.isbn);
                output.push("EXPIRED " + copy.isbn + " copy " + copy.no + " " + member.id + " fee " + money(fee));
                output.push(...this.release(title, copy));
            }
        }
        return output;
    }

    command(line: string): string[] {
        const [name, ...args] = line.split(" ");
        if (name === "DAY") {
            return this.advance(Number(args[0]));
        }
        if (name === "CLOSED") {
            const day = Number(args[0]);
            if (day <= this.day) {
                fail("invalid day");
            }
            if (this.closed.has(day)) {
                fail("already closed");
            }
            this.closed.add(day);
            const output = ["CLOSED " + day];
            for (const copy of this.allCopies().sort(copyOrder)) {
                if (copy.state === "LOANED" && copy.due === day) {
                    copy.due = this.openDay(day);
                    output.push("MOVED " + copy.isbn + " copy " + copy.no + " " + copy.member + " due " + copy.due);
                } else if (copy.state === "HOLD" && copy.expiry === day) {
                    copy.expiry = this.openDay(day);
                    output.push("MOVED " + copy.isbn + " copy " + copy.no + " " + copy.member + " until " + copy.expiry);
                }
            }
            return output;
        }
        if (name === "ADDBOOK") {
            const id = isbn(args[0]);
            const bookName = args.slice(3).join(" ");
            let title = this.titles.get(id);
            if (title && title.name !== bookName) {
                fail("title mismatch");
            }
            if (!title) {
                title = { isbn: id, name: bookName, price: amount(args[2]), copies: [], queue: [], borrowed: 0 };
                this.titles.set(id, title);
            }
            title.price = amount(args[2]);
            const added: Copy[] = [];
            for (let i = 0; i < Number(args[1]); i++) {
                const copy = { isbn: id, no: title.copies.length + 1, state: "AVAILABLE", member: "", loanDay: 0, due: 0, renewals: 0, expiry: 0 };
                title.copies.push(copy);
                added.push(copy);
            }
            const output = ["ADDBOOK " + id + " added " + added.length + " total " + holdings(title)];
            for (const copy of added) {
                output.push(...this.release(title, copy));
            }
            return output;
        }
        if (name === "ADDMEMBER") {
            if (this.members.has(args[0])) {
                fail("duplicate member");
            }
            if (!Object.hasOwn(rules, args[1])) {
                fail("unknown type");
            }
            this.members.set(args[0], {
                id: args[0], type: args[1], name: args.slice(2).join(" "),
                loans: new Map<string, Copy>(), holds: new Map<string, Copy>(), items: [], history: []
            });
            return ["ADDMEMBER " + args[0] + " " + args[1] + " loans " + rules[args[1]].limit + " days " + rules[args[1]].period];
        }
        if (name === "WITHDRAW") {
            const title = this.title(args[0]);
            const number = Number(args[1]);
            if (number < 1 || number > title.copies.length) {
                fail("unknown copy");
            }
            const copy = title.copies[number - 1];
            if (copy.state !== "AVAILABLE") {
                fail("copy not available");
            }
            copy.state = "WITHDRAWN";
            return ["WITHDRAW " + title.isbn + " copy " + copy.no + " total " + holdings(title)];
        }
        if (["BORROW", "RETURN", "RENEW", "RESERVE", "CANCEL", "LOST"].includes(name)) {
            return this.circulate(name, args);
        }
        if (name === "RENEWALL") {
            const member = this.member(args[0]);
            if (!member.loans.size) {
                fail("no loans");
            }
            if (this.balance(member) > 500) {
                fail("member blocked");
            }
            const copies = [...member.loans.values()].sort((a, b) => lex(a.isbn, b.isbn));
            const output: string[] = [];
            let renewed = 0;
            let skipped = 0;
            for (const copy of copies) {
                const title = this.titles.get(copy.isbn)!;
                const reason = this.renewalReason(title, copy);
                if (reason) {
                    output.push("SKIP " + copy.isbn + " " + reason);
                    skipped++;
                } else {
                    output.push(this.renew(member, title, copy));
                    renewed++;
                }
            }
            output.push("RENEWALL " + member.id + " renewed " + renewed + " skipped " + skipped);
            return output;
        }
        if (["PAYFINE", "WAIVE", "FINES"].includes(name)) {
            return this.charges(name, args);
        }
        return this.inspect(name, args);
    }

    circulate(name: string, args: string[]): string[] {
        const [member, title] = this.common(args[0], args[1]);
        const loan = member.loans.get(title.isbn);
        const hold = member.holds.get(title.isbn);
        const rule = rules[member.type];
        if (name === "BORROW") {
            if (this.closed.has(this.day)) {
                fail("library closed");
            }
            if (loan) {
                fail("already borrowed");
            }
            if (this.balance(member) > 500) {
                fail("member blocked");
            }
            if ([...member.loans.values()].some(copy => copy.due < this.day)) {
                fail("overdue loans");
            }
            if (member.loans.size >= rule.limit) {
                fail("loan limit");
            }
            const copy = hold ?? title.copies.find(copy => copy.state === "AVAILABLE");
            if (!copy) {
                fail(title.copies.some(copy => copy.state === "HOLD") ? "all copies on hold" : "no copy available");
            }
            member.holds.delete(title.isbn);
            copy.state = "LOANED";
            copy.member = member.id;
            copy.loanDay = this.day;
            copy.due = this.openDay(this.day + rule.period);
            copy.renewals = 0;
            member.loans.set(title.isbn, copy);
            title.borrowed++;
            this.counts.borrowed++;
            return ["BORROW " + member.id + " " + title.isbn + " copy " + copy.no + " due " + copy.due];
        }
        if (name === "RETURN" || name === "LOST" || name === "RENEW") {
            if (!loan) {
                fail("not borrowed");
            }
            if (name === "LOST") {
                return this.loss(title, loan, "LOST");
            }
            if (name === "RETURN") {
                const [late, fine] = this.endLoan(title, loan, "RETURNED");
                this.counts.returned++;
                return ["RETURN " + member.id + " " + title.isbn + " copy " + loan.no + " late " + late +
                    " fine " + money(fine) + " balance " + money(this.balance(member)), ...this.release(title, loan)];
            }
            if (this.balance(member) > 500) {
                fail("member blocked");
            }
            const reason = this.renewalReason(title, loan);
            if (reason) {
                fail(reason);
            }
            return [this.renew(member, title, loan)];
        }
        const queued = title.queue.includes(member.id);
        if (name === "CANCEL") {
            if (!queued && !hold) {
                fail("not reserved");
            }
            if (queued) {
                title.queue.splice(title.queue.indexOf(member.id), 1);
                return ["CANCEL " + member.id + " " + title.isbn + " queue"];
            }
            member.holds.delete(title.isbn);
            return ["CANCEL " + member.id + " " + title.isbn + " hold copy " + hold!.no, ...this.release(title, hold!)];
        }
        if (loan) {
            fail("already borrowed");
        }
        if (queued || hold) {
            fail("already reserved");
        }
        if (this.balance(member) > 500) {
            fail("member blocked");
        }
        if (this.reservations(member) >= rule.reservations) {
            fail("reservation limit");
        }
        if (!holdings(title)) {
            fail("no copies");
        }
        if (title.copies.some(copy => copy.state === "AVAILABLE")) {
            fail("copy available");
        }
        title.queue.push(member.id);
        const days = title.copies.filter(copy => copy.state === "LOANED").map(copy => copy.due).sort((a, b) => a - b);
        const position = title.queue.length;
        return ["RESERVE " + member.id + " " + title.isbn + " position " + position + " estimate " + (days[position - 1] ?? "none")];
    }

    charges(name: string, args: string[]): string[] {
        const member = this.member(args[0]);
        if (name === "PAYFINE") {
            if (!this.balance(member)) {
                fail("no fines");
            }
            let remaining = amount(args[1]);
            const items: string[] = [];
            for (const item of member.items) {
                const applied = Math.min(remaining, item.unpaid);
                if (applied) {
                    item.unpaid -= applied;
                    remaining -= applied;
                    items.push("ITEM " + item.no + " " + item.kind + " paid " + money(applied) + " remaining " + money(item.unpaid));
                }
                if (!remaining) {
                    break;
                }
            }
            const paid = amount(args[1]) - remaining;
            this.counts.paid += paid;
            return ["PAYFINE " + member.id + " paid " + money(paid) + " change " + money(remaining) + " balance " + money(this.balance(member)), ...items];
        }
        if (name === "WAIVE") {
            const no = Number(args[1]);
            if (no < 1 || no > member.items.length) {
                fail("unknown item");
            }
            const item = member.items[no - 1];
            if (!item.unpaid) {
                fail("item settled");
            }
            const value = item.unpaid;
            item.unpaid = 0;
            this.counts.waived += value;
            return ["WAIVE " + member.id + " item " + no + " " + item.kind + " amount " + money(value) + " balance " + money(this.balance(member))];
        }
        const items = member.items.filter(item => item.unpaid);
        return ["FINES " + member.id + " items " + items.length + " balance " + money(this.balance(member)),
            ...items.map(item => item.no + " day " + item.day + " " + item.kind + " " + item.isbn +
                " amount " + money(item.amount) + " remaining " + money(item.unpaid))];
    }

    inspect(name: string, args: string[]): string[] {
        if (name === "SEARCH") {
            const keyword = args.join(" ").toLowerCase();
            const titles = [...this.titles.values()].filter(title => title.name.toLowerCase().includes(keyword))
                .sort((a, b) => lex(a.name.toLowerCase(), b.name.toLowerCase()) || lex(a.isbn, b.isbn));
            return ["SEARCH " + titles.length, ...titles.map(title => title.isbn + " " +
                title.copies.filter(copy => copy.state === "AVAILABLE").length + "/" + holdings(title) + " " + title.name)];
        }
        if (name === "OVERDUE") {
            const copies = this.allCopies().filter(copy => copy.state === "LOANED" && copy.due < this.day)
                .sort((a, b) => a.due - b.due || lex(a.member, b.member) || lex(a.isbn, b.isbn));
            return ["OVERDUE " + copies.length, ...copies.map(copy => {
                const [late, fine] = this.late(copy);
                return copy.member + " " + copy.isbn + " copy " + copy.no + " due " + copy.due + " late " + late + " fine " + money(fine);
            })];
        }
        if (name === "NOTICES") {
            const output: string[] = [];
            for (const id of [...this.members.keys()].sort(lex)) {
                const member = this.members.get(id)!;
                const loans = [...member.loans.values()].sort(loanOrder);
                for (const copy of loans.filter(copy => copy.due < this.day)) {
                    output.push("OVERDUE " + id + " " + copy.isbn + " due " + copy.due);
                }
                for (const copy of loans.filter(copy => copy.due >= this.day && copy.due <= this.day + 2)) {
                    output.push("DUESOON " + id + " " + copy.isbn + " due " + copy.due);
                }
                for (const copy of [...member.holds.values()].sort(holdOrder)) {
                    output.push("PICKUP " + id + " " + copy.isbn + " until " + copy.expiry);
                }
            }
            return ["NOTICES " + output.length, ...output];
        }
        if (name === "HISTORY") {
            const member = this.member(args[0]);
            return ["HISTORY " + member.id + " " + member.history.length, ...member.history];
        }
        if (name === "MEMBER" || name === "MEMBERS") {
            const members = name === "MEMBER" ? [this.member(args[0])] :
                [...this.members.values()].sort((a, b) => lex(a.id, b.id));
            const output: string[] = name === "MEMBERS" ? ["MEMBERS " + members.length] : [];
            for (const member of members) {
                const balance = this.balance(member);
                const state = balance > 500 ? "BLOCKED" : "OK";
                if (name === "MEMBERS") {
                    output.push(member.id + " " + member.type + " loans " + member.loans.size + " reservations " +
                        this.reservations(member) + " balance " + money(balance) + " " + state);
                    continue;
                }
                const rule = rules[member.type];
                output.push("MEMBER " + member.id + " " + member.type + " " + member.name,
                    "STATUS loans " + member.loans.size + "/" + rule.limit + " reservations " +
                    this.reservations(member) + "/" + rule.reservations + " balance " + money(balance) + " " + state);
                for (const copy of [...member.loans.values()].sort(loanOrder)) {
                    const [late, fine] = this.late(copy);
                    output.push("LOAN " + copy.isbn + " copy " + copy.no + " due " + copy.due + " renewals " + copy.renewals +
                        (late ? " late " + late + " fine " + money(fine) : ""));
                }
                for (const copy of [...member.holds.values()].sort(holdOrder)) {
                    output.push("HOLD " + copy.isbn + " copy " + copy.no + " until " + copy.expiry);
                }
                for (const title of [...this.titles.values()].sort((a, b) => lex(a.isbn, b.isbn))) {
                    const index = title.queue.indexOf(member.id);
                    if (index >= 0) {
                        output.push("QUEUE " + title.isbn + " position " + (index + 1));
                    }
                }
            }
            return output;
        }
        if (name === "BOOK") {
            const title = this.title(args[0]);
            const output = ["BOOK " + title.isbn + " " + title.name, "PRICE " + money(title.price) +
                " copies " + holdings(title) + " borrowed " + title.borrowed];
            for (const copy of title.copies) {
                let line = "COPY " + copy.no + " " + copy.state;
                if (copy.state === "LOANED") {
                    line += " " + copy.member + " due " + copy.due;
                } else if (copy.state === "HOLD") {
                    line += " " + copy.member + " until " + copy.expiry;
                }
                output.push(line);
            }
            output.push("QUEUE " + title.queue.length + (title.queue.length ? " " + title.queue.join(" ") : ""));
            return output;
        }
        if (name === "INVENTORY") {
            const states: Record<string, number> = { AVAILABLE: 0, LOANED: 0, HOLD: 0, LOST: 0, WITHDRAWN: 0 };
            for (const copy of this.allCopies()) {
                states[copy.state]++;
            }
            const total = states.AVAILABLE + states.LOANED + states.HOLD;
            const output = ["INVENTORY titles " + this.titles.size + " copies " + total + " available " + states.AVAILABLE +
                " loaned " + states.LOANED + " hold " + states.HOLD + " lost " + states.LOST + " withdrawn " + states.WITHDRAWN];
            for (const title of [...this.titles.values()].sort((a, b) => lex(a.isbn, b.isbn))) {
                const count = (state: string): number => title.copies.filter(copy => copy.state === state).length;
                output.push(title.isbn + " copies " + holdings(title) + " available " + count("AVAILABLE") +
                    " loaned " + count("LOANED") + " hold " + count("HOLD") + " queue " + title.queue.length);
            }
            return output;
        }
        const c = this.counts;
        const outstanding = [...this.members.values()].reduce((sum, member) => sum + this.balance(member), 0);
        const output = ["STATS day " + this.day + " titles " + this.titles.size + " members " + this.members.size + " closed " + this.closed.size,
            "LOANS borrowed " + c.borrowed + " returned " + c.returned + " renewed " + c.renewed + " lost " + c.lost +
                " active " + this.allCopies().filter(copy => copy.state === "LOANED").length,
            "MONEY fines " + money(c.FINE) + " fees " + money(c.FEE) + " charges " + money(c.PRICE) +
                " paid " + money(c.paid) + " waived " + money(c.waived) + " outstanding " + money(outstanding)];
        const top = [...this.titles.values()].filter(title => title.borrowed > 0)
            .sort((a, b) => b.borrowed - a.borrowed || lex(a.isbn, b.isbn)).slice(0, 3);
        output.push(...top.map((title, i) => "TOP " + (i + 1) + " " + title.isbn + " " + title.borrowed + " " + title.name));
        return output;
    }
}

const lines = readFileSync(0, "utf8").split("\n");
const library = new Library();
const output: string[] = [];
for (let i = 1; i <= Number(lines[0]); i++) {
    try {
        output.push(...library.command(lines[i]));
    } catch (error) {
        if (!(error instanceof Invalid)) {
            throw error;
        }
        output.push("ERROR " + error.message);
    }
}
process.stdout.write(output.join("\n") + "\n");
