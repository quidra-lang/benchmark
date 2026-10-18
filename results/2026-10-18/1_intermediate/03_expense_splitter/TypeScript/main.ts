import { readFileSync } from "node:fs";

type Person = { name: string; value: number };
type Member = { active: boolean; day: number };
type Expense = {
    id: string; day: number; record: number; amount: number; currency: string;
    category: string; mode: string; payers: Person[]; participants: Person[];
    total: number; shares: number[]; contributions: number[];
    interval: number; next: number; copies: number;
};
type Settlement = { from: string; to: string; amount: number; currency: string; total: number; day: number; record: number };
type Transfer = { from: string; to: string; amount: number };

class Invalid extends Error {}

function fail(message: string): never {
    throw new Invalid(message);
}

function amount(value: string): number {
    const [whole, cents] = value.split(".");
    return Number(whole) * 100 + Number(cents);
}

function money(value: number): string {
    return ratio(value, 100) + "." + String(value % 100).padStart(2, "0");
}

function signed(value: number): string {
    return value > 0 ? "+" + money(value) : value < 0 ? "-" + money(-value) : "0.00";
}

function ratio(a: number, b: number): number {
    return Number(BigInt(a) / BigInt(b));
}

function percent(part: number, whole: number): string {
    const value = Number(BigInt(part) * 10000n / BigInt(whole));
    return money(value) + "%";
}

function rateText(rate: number): string {
    return ratio(rate, 10000) + "." + String(rate % 10000).padStart(4, "0");
}

function lex(a: string, b: string): number {
    return a < b ? -1 : a > b ? 1 : 0;
}

function distribute(total: number, weights: number[]): number[] {
    const sum = weights.reduce((a, b) => a + b, 0);
    const portions = weights.map(weight => Number(BigInt(total) * BigInt(weight) / BigInt(sum)));
    const order = weights.map((weight, i) => ({ i, remainder: BigInt(total) * BigInt(weight) % BigInt(sum) }));
    order.sort((a, b) => a.remainder === b.remainder ? a.i - b.i : a.remainder > b.remainder ? -1 : 1);
    const remaining = total - portions.reduce((a, b) => a + b, 0);
    for (let i = 0; i < remaining; i++) {
        portions[order[i].i]++;
    }
    return portions;
}

function equal(total: number, count: number): number[] {
    const q = ratio(total, count);
    return Array.from({ length: count }, (_, i) => q + (i < total % count ? 1 : 0));
}

function note(item: { amount: number; currency: string }): string {
    return item.currency ? " [" + money(item.amount) + " " + item.currency + "]" : "";
}

function involved(expense: Expense, name: string): boolean {
    return [...expense.payers, ...expense.participants].some(person => person.name === name);
}

function net(expense: Expense, name: string): number {
    let value = 0;
    expense.payers.forEach((person, i) => {
        if (person.name === name) {
            value += expense.contributions[i];
        }
    });
    expense.participants.forEach((person, i) => {
        if (person.name === name) {
            value -= expense.shares[i];
        }
    });
    return value;
}

function chronological(a: { day: number; record: number }, b: { day: number; record: number }): number {
    return a.day - b.day || a.record - b.record;
}

function greedy(balances: Map<string, number>): Transfer[] {
    const values = new Map(balances);
    const result: Transfer[] = [];
    while (true) {
        const debtors = [...values].filter(([, value]) => value < 0).sort((a, b) => a[1] - b[1] || lex(a[0], b[0]));
        const creditors = [...values].filter(([, value]) => value > 0).sort((a, b) => b[1] - a[1] || lex(a[0], b[0]));
        if (!debtors.length) {
            return result;
        }
        const [from, debt] = debtors[0];
        const [to, credit] = creditors[0];
        const value = Math.min(-debt, credit);
        result.push({ from, to, amount: value });
        values.set(from, debt + value);
        values.set(to, credit - value);
    }
}

function transferText(transfer: Transfer, indent: string): string {
    return indent + transfer.from + " -> " + transfer.to + " " + money(transfer.amount);
}

class Splitter {
    day = 1;
    serial = 0;
    members = new Map<string, Member>();
    currencies = new Map<string, number>();
    expenses: Expense[] = [];
    settlements: Settlement[] = [];
    budgets = new Map<string, number>();
    used = new Set<string>();

    names(active: boolean = false): string[] {
        return [...this.members.keys()].filter(name => !active || this.members.get(name)!.active).sort(lex);
    }

    member(name: string, active: boolean = true): void {
        const value = this.members.get(name);
        if (!value) {
            fail("unknown member " + name);
        }
        if (active && !value.active) {
            fail("inactive member " + name);
        }
    }

    getExpense(id: string, frozen: boolean = false): Expense {
        const expense = this.expenses.find(item => item.id === id);
        if (!expense) {
            fail("unknown expense " + id);
        }
        if (frozen) {
            for (const person of [...expense.payers, ...expense.participants]) {
                if (!this.members.get(person.name)!.active) {
                    fail("inactive member " + person.name);
                }
            }
        }
        return expense;
    }

    convert(value: number, currency: string): number {
        if (!currency) {
            return value;
        }
        const rate = this.currencies.get(currency);
        if (rate === undefined) {
            fail("unknown currency " + currency);
        }
        return Number((BigInt(value) * BigInt(rate) + 5000n) / 10000n);
    }

    specification(value: string): { amount: number; currency: string; total: number } {
        const [text, currency = ""] = value.split("@");
        const original = amount(text);
        const total = this.convert(original, currency);
        if (!original || !total) {
            fail("invalid amount");
        }
        return { amount: original, currency, total };
    }

    prepare(id: string, payer: string, spec: string, category: string, mode: string,
            parts: string[], previous?: Expense): Expense {
        this.member(payer);
        const converted = this.specification(spec);
        const participants: Person[] = [];
        if (mode === "EQUAL" && parts[0] === "ALL") {
            participants.push(...this.names(true).map(name => ({ name, value: 0 })));
        } else {
            const seen = new Set<string>();
            for (const part of parts) {
                const [name, value] = part.split(":");
                this.member(name);
                if (seen.has(name)) {
                    fail("duplicate member " + name);
                }
                seen.add(name);
                const specified = value === undefined ? 0 :
                    mode === "EXACT" || mode === "ADJUST" ? amount(value) : Number(value);
                participants.push({ name, value: specified });
            }
        }
        const a = converted.amount;
        const weights = participants.map(person => person.value);
        const sum = weights.reduce((x, y) => x + y, 0);
        if ((mode === "EXACT" && sum !== a) || (mode === "PERCENT" && sum !== 10000) ||
            (mode === "SHARES" && sum === 0) || (mode === "ADJUST" && sum > a)) {
            fail("splits do not add up");
        }
        let portions: number[];
        if (mode === "EQUAL") {
            portions = equal(a, participants.length);
        } else if (mode === "EXACT") {
            portions = weights;
        } else if (mode === "ADJUST") {
            portions = equal(a - sum, participants.length).map((value, i) => value + weights[i]);
        } else {
            portions = distribute(a, weights);
        }
        return {
            id, day: previous?.day ?? this.day, record: previous?.record ?? 0,
            ...converted, category, mode, payers: [{ name: payer, value: a }], participants,
            shares: distribute(converted.total, portions), contributions: [converted.total],
            interval: previous?.interval ?? 0, next: previous?.next ?? 0, copies: previous?.copies ?? 0
        };
    }

    balances(): Map<string, number> {
        const values = new Map<string, number>(this.names().map((name): [string, number] => [name, 0]));
        for (const expense of this.expenses) {
            expense.payers.forEach((person, i) => values.set(person.name, values.get(person.name)! + expense.contributions[i]));
            expense.participants.forEach((person, i) => values.set(person.name, values.get(person.name)! - expense.shares[i]));
        }
        for (const payment of this.settlements) {
            values.set(payment.from, values.get(payment.from)! + payment.total);
            values.set(payment.to, values.get(payment.to)! - payment.total);
        }
        return values;
    }

    spent(category: string): number {
        return this.expenses.filter(expense => expense.category === category).reduce((sum, expense) => sum + expense.total, 0);
    }

    warning(expense: Expense): string[] {
        const budget = this.budgets.get(expense.category);
        const spent = this.spent(expense.category);
        return budget !== undefined && spent > budget ?
            ["  WARNING " + expense.category + " over budget by " + money(spent - budget)] : [];
    }

    debts(): Map<string, number> {
        const result = new Map<string, number>();
        const add = (from: string, to: string, value: number): void => {
            const key = from + ":" + to;
            result.set(key, (result.get(key) ?? 0) + value);
        };
        for (const expense of this.expenses) {
            const names = this.names().filter(name => involved(expense, name));
            const borrowers = names.map(name => ({ name, value: net(expense, name) })).filter(person => person.value < 0);
            const lenders = names.map(name => ({ name, value: net(expense, name) })).filter(person => person.value > 0);
            let i = 0;
            let j = 0;
            while (i < borrowers.length && j < lenders.length) {
                const value = Math.min(-borrowers[i].value, lenders[j].value);
                add(borrowers[i].name, lenders[j].name, value);
                borrowers[i].value += value;
                lenders[j].value -= value;
                if (!borrowers[i].value) {
                    i++;
                }
                if (!lenders[j].value) {
                    j++;
                }
            }
        }
        for (const payment of this.settlements) {
            add(payment.from, payment.to, -payment.total);
        }
        return result;
    }

    summary(lines: string[]): string[] {
        return lines.length === 1 ? [...lines, "  (none)"] : lines;
    }

    optimal(): string[] {
        const balances = this.balances();
        const names = this.names().filter(name => balances.get(name) !== 0);
        if (names.length > 12) {
            fail("too many members");
        }
        const full = (1 << names.length) - 1;
        const sums = new Array<number>(full + 1).fill(0);
        for (let mask = 1; mask <= full; mask++) {
            const bit = mask & -mask;
            const index = names.findIndex((_, i) => bit === (1 << i));
            sums[mask] = sums[mask ^ bit] + balances.get(names[index])!;
        }
        const memo = new Map<number, number>([[0, 0]]);
        const best = (mask: number): number => {
            const known = memo.get(mask);
            if (known !== undefined) {
                return known;
            }
            const first = mask & -mask;
            let maximum = 0;
            for (let sub = mask; sub; sub = (sub - 1) & mask) {
                if ((sub & first) && sums[sub] === 0) {
                    maximum = Math.max(maximum, 1 + best(mask ^ sub));
                }
            }
            memo.set(mask, maximum);
            return maximum;
        };
        const list = (mask: number): string[] => names.filter((_, i) => mask & (1 << i));
        const compare = (a: number, b: number): number => {
            const left = list(a);
            const right = list(b);
            for (let i = 0; i < Math.min(left.length, right.length); i++) {
                const c = lex(left[i], right[i]);
                if (c) {
                    return c;
                }
            }
            return left.length - right.length;
        };
        const groups: string[][] = [];
        let mask = full;
        while (mask) {
            const candidates: number[] = [];
            const first = mask & -mask;
            for (let sub = mask; sub; sub = (sub - 1) & mask) {
                if ((sub & first) && sums[sub] === 0 && 1 + best(mask ^ sub) === best(mask)) {
                    candidates.push(sub);
                }
            }
            candidates.sort(compare);
            groups.push(list(candidates[0]));
            mask ^= candidates[0];
        }
        const output = ["SIMPLIFY OPTIMAL transfers " + (names.length - groups.length) + " groups " + groups.length];
        for (const group of groups) {
            output.push("  group " + group.join(" "));
            const subset = new Map<string, number>(group.map((name): [string, number] => [name, balances.get(name)!]));
            output.push(...greedy(subset).map(transfer => transferText(transfer, "    ")));
        }
        return output;
    }

    command(line: string): string[] {
        const [name, ...args] = line.split(" ");
        const output: string[] = [];
        if (name === "DAY") {
            const day = Number(args[0]);
            if (day <= this.day) {
                fail("invalid day " + args[0]);
            }
            output.push("DAY " + day);
            while (true) {
                const pending = this.expenses.filter(expense => expense.interval > 0 && expense.next <= day)
                    .sort((a, b) => a.next - b.next || a.record - b.record);
                if (!pending.length) {
                    break;
                }
                const template = pending[0];
                const active = [...template.payers, ...template.participants].every(person => this.members.get(person.name)!.active);
                const total = this.convert(template.amount, template.currency);
                if (!active || !total) {
                    template.interval = 0;
                    output.push("  CANCEL " + template.id);
                    continue;
                }
                template.copies++;
                const id = template.id + "#" + (template.copies + 1);
                const copy = {
                    ...template, id, day: template.next, record: ++this.serial,
                    payers: template.payers.map(person => ({ ...person })),
                    participants: template.participants.map(person => ({ ...person })),
                    total, shares: this.originalShares(template, total),
                    contributions: distribute(total, template.payers.map(person => person.value)),
                    interval: 0, next: 0, copies: 0
                };
                this.expenses.push(copy);
                this.used.add(id);
                template.next += template.interval;
                output.push("  RECUR " + id + " " + money(total), ...this.warning(copy));
            }
            this.day = day;
        } else if (name === "MEMBER") {
            const old = this.members.get(args[0]);
            if (old?.active) {
                fail("duplicate member " + args[0]);
            }
            this.members.set(args[0], { active: true, day: this.day });
            output.push("MEMBER " + args[0] + (old ? " rejoined" : " joined"));
        } else if (name === "LEAVE") {
            this.member(args[0]);
            if (this.balances().get(args[0]) !== 0) {
                fail("member has a balance " + args[0]);
            }
            this.members.set(args[0], { active: false, day: this.day });
            output.push("LEAVE " + args[0]);
        } else if (name === "CURRENCY") {
            const old = this.currencies.get(args[0]);
            const value = Number(args[1]);
            this.currencies.set(args[0], value);
            output.push("CURRENCY " + args[0] + " " + rateText(value) + (old === undefined ? "" : " was " + rateText(old)));
        } else if (name === "EXPENSE" || name === "EDIT") {
            let previous: Expense | undefined;
            if (name === "EXPENSE") {
                if (this.used.has(args[0])) {
                    fail("duplicate id " + args[0]);
                }
            } else {
                previous = this.getExpense(args[0], true);
            }
            const expense = this.prepare(args[0], args[1], args[2], args[3], args[4], args.slice(5), previous);
            if (previous) {
                this.expenses[this.expenses.indexOf(previous)] = expense;
            } else {
                expense.record = ++this.serial;
                this.expenses.push(expense);
                this.used.add(expense.id);
            }
            output.push(name + " " + expense.id + " " + money(expense.total) + note(expense) + " = " +
                expense.participants.map((person, i) => person.name + " " + money(expense.shares[i])).join(" + "),
                ...this.warning(expense));
        } else if (name === "PAYERS") {
            const expense = this.getExpense(args[0], true);
            const payers: Person[] = [];
            const seen = new Set<string>();
            for (const part of args.slice(1)) {
                const [payer, value] = part.split(":");
                this.member(payer);
                if (seen.has(payer)) {
                    fail("duplicate member " + payer);
                }
                seen.add(payer);
                payers.push({ name: payer, value: amount(value) });
            }
            if (payers.reduce((sum, person) => sum + person.value, 0) !== expense.amount) {
                fail("payers do not add up");
            }
            expense.payers = payers;
            expense.contributions = distribute(expense.total, payers.map(person => person.value));
            output.push("PAYERS " + expense.id + " " + money(expense.total) + note(expense) + " = " +
                payers.map((person, i) => person.name + " " + money(expense.contributions[i])).join(" + "));
        } else if (name === "DELETE") {
            const expense = this.getExpense(args[0], true);
            this.expenses.splice(this.expenses.indexOf(expense), 1);
            output.push("DELETE " + args[0]);
        } else if (name === "RECURRING") {
            const expense = this.getExpense(args[0]);
            const interval = Number(args[1]);
            expense.interval = interval;
            expense.next = this.day + interval;
            output.push("RECURRING " + args[0] + (interval ? " interval " + interval + " next " + expense.next : " stopped"));
        } else if (name === "SETTLE") {
            this.member(args[0]);
            this.member(args[1]);
            if (args[0] === args[1]) {
                fail("same member " + args[0]);
            }
            const converted = this.specification(args[2]);
            const payment = { from: args[0], to: args[1], ...converted, day: this.day, record: ++this.serial };
            this.settlements.push(payment);
            output.push("SETTLE " + payment.from + " -> " + payment.to + " " + money(payment.total) + note(payment));
        } else if (name === "BUDGET") {
            const value = amount(args[1]);
            if (value) {
                this.budgets.set(args[0], value);
            } else {
                this.budgets.delete(args[0]);
            }
            output.push("BUDGET " + args[0] + (value ? " " + money(value) : " removed"));
        } else if (name === "BALANCES") {
            const balances = this.balances();
            output.push("BALANCES", ...this.names(true).map(person => "  " + person + " " + signed(balances.get(person)!)));
        } else if (name === "OWES" || name === "MATRIX") {
            if (name === "OWES") {
                this.member(args[0], false);
            }
            const debts = this.debts();
            const debt = (a: string, b: string): number => (debts.get(a + ":" + b) ?? 0) - (debts.get(b + ":" + a) ?? 0);
            output.push(name === "OWES" ? "OWES " + args[0] : "MATRIX");
            if (name === "OWES") {
                for (const person of this.names().filter(person => person !== args[0])) {
                    const value = debt(args[0], person);
                    if (value > 0) {
                        output.push("  " + args[0] + " owes " + person + " " + money(value));
                    } else if (value < 0) {
                        output.push("  " + person + " owes " + args[0] + " " + money(-value));
                    }
                }
            } else {
                const names = this.names(true);
                if (!names.length) {
                    output.push("  (none)");
                } else {
                    const cells = names.map(a => names.map(b => a === b ? "-" : money(Math.max(0, debt(a, b)))));
                    const l = Math.max(...names.map(person => person.length));
                    const w = Math.max(...names.map(person => person.length), ...cells.flat().map(cell => cell.length));
                    output.push(" ".repeat(l) + names.map(person => "  " + person.padStart(w, " ")).join(""));
                    names.forEach((person, i) => output.push(person.padEnd(l, " ") + cells[i].map(cell => "  " + cell.padStart(w, " ")).join("")));
                }
            }
        } else if (name === "HISTORY") {
            this.member(args[0], false);
            const person = args[0];
            const items = this.expenses.filter(expense => involved(expense, person)).map(expense => ({
                day: expense.day, record: expense.record, label: expense.id, change: net(expense, person)
            }));
            for (const payment of this.settlements.filter(item => item.from === person || item.to === person)) {
                items.push({
                    day: payment.day, record: payment.record, label: payment.from + "->" + payment.to,
                    change: payment.from === person ? payment.total : -payment.total
                });
            }
            items.sort(chronological);
            let running = 0;
            output.push("HISTORY " + person);
            for (const item of items) {
                running += item.change;
                output.push("  day " + item.day + " " + item.label + " " + signed(item.change) + " balance " + signed(running));
            }
        } else if (name === "CATEGORY") {
            output.push("CATEGORY");
            const categories = [...new Set(this.expenses.map(expense => expense.category))];
            categories.sort((a, b) => this.spent(b) - this.spent(a) || lex(a, b));
            const total = this.expenses.reduce((sum, expense) => sum + expense.total, 0);
            for (const category of categories) {
                const spent = this.spent(category);
                output.push("  " + category + " " + money(spent) + " " + percent(spent, total));
                const totals = new Map<string, number>();
                for (const expense of this.expenses.filter(expense => expense.category === category)) {
                    expense.participants.forEach((person, i) => totals.set(person.name, (totals.get(person.name) ?? 0) + expense.shares[i]));
                }
                const people = [...totals].filter(([, value]) => value > 0).sort((a, b) => b[1] - a[1] || lex(a[0], b[0]));
                output.push(...people.map(([person, value]) => "    " + person + " " + money(value) + " " + percent(value, spent)));
            }
        } else if (name === "BUDGETS") {
            output.push("BUDGETS");
            for (const category of [...this.budgets.keys()].sort(lex)) {
                const budget = this.budgets.get(category)!;
                const spent = this.spent(category);
                output.push("  " + category + " spent " + money(spent) + " budget " + money(budget) + " used " +
                    percent(spent, budget) + (spent <= budget ? " left " + money(budget - spent) : " over " + money(spent - budget)));
            }
        } else if (name === "TOTALS") {
            output.push("TOTALS");
            for (const person of this.names()) {
                let paid = 0;
                let share = 0;
                for (const expense of this.expenses) {
                    expense.payers.forEach((payer, i) => {
                        if (payer.name === person) {
                            paid += expense.contributions[i];
                        }
                    });
                    expense.participants.forEach((participant, i) => {
                        if (participant.name === person) {
                            share += expense.shares[i];
                        }
                    });
                }
                const sent = this.settlements.filter(payment => payment.from === person).reduce((sum, payment) => sum + payment.total, 0);
                const received = this.settlements.filter(payment => payment.to === person).reduce((sum, payment) => sum + payment.total, 0);
                output.push("  " + person + " paid " + money(paid) + " share " + money(share) + " sent " + money(sent) + " received " + money(received));
            }
            const currencies = [...new Set(this.expenses.map(expense => expense.currency).filter(Boolean))].sort(lex);
            for (const currency of currencies) {
                const selected = this.expenses.filter(expense => expense.currency === currency);
                output.push("  currency " + currency + " expenses " + selected.length + " amount " +
                    money(selected.reduce((sum, expense) => sum + expense.amount, 0)) + " base " +
                    money(selected.reduce((sum, expense) => sum + expense.total, 0)));
            }
            output.push("  expenses " + this.expenses.length + " total " + money(this.expenses.reduce((sum, expense) => sum + expense.total, 0)) +
                " settlements " + this.settlements.length + " total " + money(this.settlements.reduce((sum, payment) => sum + payment.total, 0)));
        } else if (name === "MEMBERS") {
            output.push("MEMBERS");
            for (const person of this.names()) {
                const member = this.members.get(person)!;
                output.push("  " + person + (member.active ? " active day " : " left day ") + member.day +
                    " expenses " + this.expenses.filter(expense => involved(expense, person)).length);
            }
        } else if (name === "EXPENSES") {
            if (args[0] === "MEMBER") {
                this.member(args[1], false);
            }
            const selected = this.expenses.filter(expense => args[0] === "ALL" ||
                (args[0] === "CATEGORY" && expense.category === args[1]) ||
                (args[0] === "MEMBER" && involved(expense, args[1])) ||
                (args[0] === "DAYS" && expense.day >= Number(args[1]) && expense.day <= Number(args[2]))).sort(chronological);
            output.push(line);
            for (const expense of selected) {
                output.push("  day " + expense.day + " " + expense.id + " " + expense.category + " " +
                    money(expense.total) + " by " + expense.payers.map(person => person.name).join(","));
            }
            output.push("  count " + selected.length + " total " + money(selected.reduce((sum, expense) => sum + expense.total, 0)));
        } else if (name === "PERIODS") {
            const k = Number(args[0]);
            const groups = new Map<number, Expense[]>();
            for (const expense of this.expenses) {
                const index = ratio(expense.day - 1, k);
                if (!groups.has(index)) {
                    groups.set(index, []);
                }
                groups.get(index)!.push(expense);
            }
            output.push("PERIODS " + k);
            for (const index of [...groups.keys()].sort((a, b) => a - b)) {
                const group = groups.get(index)!;
                output.push("  days " + (index * k + 1) + "-" + (index * k + k) + " expenses " + group.length +
                    " total " + money(group.reduce((sum, expense) => sum + expense.total, 0)));
            }
        } else if (name === "SHOW") {
            const expense = this.getExpense(args[0]);
            output.push("SHOW " + expense.id, "  day " + expense.day + " category " + expense.category +
                " mode " + expense.mode + " total " + money(expense.total) + note(expense));
            expense.payers.forEach((person, i) => output.push("  paid " + person.name + " " + money(expense.contributions[i])));
            const units = expense.participants.reduce((sum, person) => sum + person.value, 0);
            expense.participants.forEach((person, i) => {
                let suffix = "";
                if (expense.mode === "EXACT") {
                    suffix = " " + money(person.value);
                } else if (expense.mode === "PERCENT") {
                    suffix = " " + money(person.value) + "%";
                } else if (expense.mode === "SHARES") {
                    suffix = " " + person.value + "/" + units;
                } else if (expense.mode === "ADJUST") {
                    suffix = " +" + money(person.value);
                }
                output.push("  share " + person.name + " " + money(expense.shares[i]) + suffix);
            });
            if (expense.interval) {
                output.push("  recurring interval " + expense.interval + " next " + expense.next);
            }
        } else if (args[0] === "OPTIMAL") {
            return this.optimal();
        } else {
            const transfers = greedy(this.balances());
            output.push("SIMPLIFY GREEDY transfers " + transfers.length, ...transfers.map(transfer => transferText(transfer, "  ")));
        }
        return ["BALANCES", "OWES", "HISTORY", "CATEGORY", "BUDGETS", "MEMBERS", "PERIODS"].includes(name) ?
            this.summary(output) : output;
    }

    originalShares(expense: Expense, total: number): number[] {
        const weights = expense.participants.map(person => person.value);
        const sum = weights.reduce((a, b) => a + b, 0);
        let portions: number[];
        if (expense.mode === "EQUAL") {
            portions = equal(expense.amount, weights.length);
        } else if (expense.mode === "EXACT") {
            portions = weights;
        } else if (expense.mode === "ADJUST") {
            portions = equal(expense.amount - sum, weights.length).map((value, i) => value + weights[i]);
        } else {
            portions = distribute(expense.amount, weights);
        }
        return distribute(total, portions);
    }
}

const lines = readFileSync(0, "utf8").split("\n");
const splitter = new Splitter();
const output: string[] = [];
for (let i = 1; i <= Number(lines[0]); i++) {
    try {
        output.push(...splitter.command(lines[i]));
    } catch (error) {
        if (!(error instanceof Invalid)) {
            throw error;
        }
        output.push("ERROR " + error.message);
    }
}
process.stdout.write(output.join("\n") + "\n");
