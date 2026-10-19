import { readFileSync } from 'node:fs';

type AccountType = 'ASSET' | 'LIABILITY' | 'EQUITY' | 'REVENUE' | 'EXPENSE' | 'CONTRA_ASSET';
type Side = 'DR' | 'CR';
type Category = 'journal' | 'recurring' | 'reversal' | 'closing' | 'reopen' | 'depreciation' | 'interest' | 'writeoff';
type BlockKind = 'journal' | 'template';
type OutputPart = string | number | bigint;

interface CalendarDate { year: number; month: number; day: number }
interface Account { code: string; type: AccountType; name: string; active: boolean }
interface PostingLine { side: Side; account: string; amount: bigint; partner: string | null }
interface Entry {
    id: string;
    day: number;
    category: Category;
    memo: string;
    lines: PostingLine[];
    sequence: number;
    reversedBy: string | null;
    reverses: string | null;
}
interface Template { name: string; memo: string; lines: PostingLine[]; uses: number }
type DraftBlock = { key: string; memo: string; lines: PostingLine[] } &
    ({ kind: 'journal'; date: string } | { kind: 'template'; date: null });
interface CloseRecord { day: number; id: string | null }
interface OpenItem { entry: Entry; original: bigint; remaining: bigint }
interface Settlement { items: OpenItem[]; unapplied: bigint }

const MONTH_LENGTHS = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
const LAST_DAY = 36524;
const INCOME_TYPES = new Set<AccountType>(['REVENUE', 'EXPENSE']);
const CLOSING_TYPES = new Set<Category>(['closing', 'reopen']);
const AGING_LABELS = ['0-30', '31-60', '61-90', '91+'];

class CommandError extends Error {}

function leap(year: number): boolean {
    return year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
}

function monthLength(year: number, month: number): number {
    return month === 2 && leap(year) ? 29 : MONTH_LENGTHS[month - 1];
}

function dayNumber(year: number, month: number, day: number): number {
    let result = day - 1;
    for (let y = 2000; y < year; y++) result += leap(y) ? 366 : 365;
    for (let m = 1; m < month; m++) result += monthLength(year, m);
    return result;
}

function calendar(number: number): CalendarDate {
    let year = 2000;
    while (number >= (leap(year) ? 366 : 365)) {
        number -= leap(year) ? 366 : 365;
        year++;
    }
    let month = 1;
    while (number >= monthLength(year, month)) {
        number -= monthLength(year, month);
        month++;
    }
    return {year, month, day: number + 1};
}

function padded(value: number, width = 2): string {
    return String(value).padStart(width, '0');
}

function dateText(number: number): string {
    const {year, month, day} = calendar(number);
    return `${padded(year, 4)}-${padded(month)}-${padded(day)}`;
}

function checkedDate(text: string): number {
    const year = Number(text.slice(0, 4));
    const month = Number(text.slice(5, 7));
    const day = Number(text.slice(8, 10));
    if (year < 2000 || year > 2099 || month < 1 || month > 12 || day < 1 || day > monthLength(year, month)) {
        throw new CommandError(`invalid date ${text}`);
    }
    return dayNumber(year, month, day);
}

function checkedRange(first: string, last: string): [number, number] {
    const start = checkedDate(first);
    const end = checkedDate(last);
    if (start > end) throw new CommandError(`invalid range ${first} ${last}`);
    return [start, end];
}

function monthsAfter(number: number, count: number): number {
    const original = calendar(number);
    const total = original.month - 1 + count;
    const year = original.year + Math.floor(total / 12);
    const month = total % 12 + 1;
    return dayNumber(year, month, Math.min(original.day, monthLength(year, month)));
}

function cents(text: string): bigint {
    const [whole, fraction] = text.split('.');
    return BigInt(whole) * 100n + BigInt(fraction);
}

function money(value: bigint): string {
    const sign = value < 0n ? '-' : '';
    const magnitude = value < 0n ? -value : value;
    return `${sign}${magnitude / 100n}.${String(magnitude % 100n).padStart(2, '0')}`;
}

function accountClass(type: AccountType): AccountType {
    return type === 'CONTRA_ASSET' ? 'ASSET' : type;
}

function normalSign(type: AccountType): bigint {
    return type === 'ASSET' || type === 'EXPENSE' ? 1n : -1n;
}

function lineDifference(line: PostingLine): bigint {
    return line.side === 'DR' ? line.amount : -line.amount;
}

function sideTotal(lines: readonly PostingLine[], side: Side): bigint {
    let result = 0n;
    for (const line of lines) if (line.side === side) result += line.amount;
    return result;
}

function postingOrder(a: Entry, b: Entry): number {
    return a.day - b.day || a.sequence - b.sequence;
}

class Totals {
    private readonly values = new Map<string, [bigint, bigint]>();

    constructor(entries: readonly Entry[]) {
        for (const entry of entries) {
            for (const line of entry.lines) {
                const pair: [bigint, bigint] = this.values.get(line.account) ?? [0n, 0n];
                pair[line.side === 'DR' ? 0 : 1] += line.amount;
                this.values.set(line.account, pair);
            }
        }
    }

    debit(code: string): bigint { return this.values.get(code)?.[0] ?? 0n; }
    credit(code: string): bigint { return this.values.get(code)?.[1] ?? 0n; }
    difference(code: string): bigint { return this.debit(code) - this.credit(code); }
}

class Books {
    readonly accounts = new Map<string, Account>();
    readonly entries: Entry[] = [];
    readonly entryIndex = new Map<string, Entry>();
    readonly templates = new Map<string, Template>();
    block: DraftBlock | null = null;
    readonly closes: CloseRecord[] = [];
    closeCount = 0;
    depreciationCount = 0;
    interestCount = 0;
    writeoffCount = 0;
    readonly output: string[] = [];

    emit(...parts: OutputPart[]): void { this.output.push(parts.join(' ')); }
    indented(indent: number, ...parts: OutputPart[]): void { this.output.push(' '.repeat(indent) + parts.join(' ')); }
    codes(): string[] { return [...this.accounts.keys()].sort(); }
    closedThrough(): number | null { return this.closes.at(-1)?.day ?? null; }

    ancestors(code: string): string[] {
        const result: string[] = [];
        for (let length = 1; length < code.length; length++) {
            const prefix = code.slice(0, length);
            if (this.accounts.has(prefix)) result.push(prefix);
        }
        return result;
    }

    parent(code: string): string { return this.ancestors(code).at(-1) ?? 'none'; }
    topLevel(code: string): string { return this.ancestors(code)[0] ?? code; }

    account(code: string, type: AccountType | null = null): Account {
        const account = this.accounts.get(code);
        if (account === undefined) throw new CommandError(`unknown account ${code}`);
        if (type !== null && account.type !== type) throw new CommandError(`wrong type ${code} ${type}`);
        return account;
    }

    active(codes: readonly string[]): void {
        for (const code of codes) {
            if (!this.accounts.get(code)!.active) throw new CommandError(`inactive account ${code}`);
        }
    }

    checkClosed(day: number): void {
        const closed = this.closedThrough();
        if (closed !== null && day <= closed) throw new CommandError(`period closed ${dateText(day)}`);
    }

    entry(id: string): Entry {
        const entry = this.entryIndex.get(id);
        if (entry === undefined) throw new CommandError(`unknown entry ${id}`);
        return entry;
    }

    selected(first = 0, last = LAST_DAY, omitClosing = false): Entry[] {
        return this.entries.filter(entry => entry.day >= first && entry.day <= last &&
            (!omitClosing || !CLOSING_TYPES.has(entry.category)));
    }

    totals(first = 0, last = LAST_DAY, omitClosing = false): Totals {
        return new Totals(this.selected(first, last, omitClosing));
    }

    balance(code: string, day = LAST_DAY): bigint {
        return this.totals(0, day).difference(code) * normalSign(this.accounts.get(code)!.type);
    }

    dailySum(code: string, first: number, last: number): bigint {
        let result = 0n;
        const sign = normalSign(this.accounts.get(code)!.type);
        for (const entry of this.entries) {
            if (entry.day > last) continue;
            const days = BigInt(last - Math.max(first, entry.day) + 1);
            for (const line of entry.lines) {
                if (line.account === code) result += sign * lineDifference(line) * days;
            }
        }
        return result;
    }

    post(id: string, day: number, category: Category, memo: string, lines: readonly PostingLine[]): Entry {
        const entry: Entry = {id, day, category, memo, lines: lines.slice(), sequence: this.entries.length + 1,
            reversedBy: null, reverses: null};
        this.entries.push(entry);
        this.entryIndex.set(id, entry);
        return entry;
    }

    reverseEntry(entry: Entry, id: string, day: number, category: Category, memo: string): Entry {
        const lines = entry.lines.map<PostingLine>(line => ({...line, side: line.side === 'DR' ? 'CR' : 'DR'}));
        const reversed = this.post(id, day, category, memo, lines);
        entry.reversedBy = id;
        reversed.reverses = entry.id;
        return reversed;
    }

    partners(code: string, day: number): string[] {
        const partners = new Set<string>();
        for (const entry of this.entries) {
            if (entry.day > day) continue;
            for (const line of entry.lines) {
                if (line.account === code && line.partner !== null) partners.add(line.partner);
            }
        }
        return [...partners].sort();
    }

    openItems(code: string, partner: string, day: number): Settlement {
        const sign = normalSign(this.accounts.get(code)!.type);
        const items: OpenItem[] = [];
        let unapplied = 0n, head = 0;
        for (const entry of this.selected(0, day).sort(postingOrder)) {
            for (const line of entry.lines) {
                if (line.account !== code || line.partner !== partner) continue;
                const value = sign * lineDifference(line);
                if (value > 0n) {
                    const used = value < unapplied ? value : unapplied;
                    unapplied -= used;
                    if (value > used) items.push({entry, original: value, remaining: value - used});
                } else if (value < 0n) {
                    let remaining = -value;
                    while (remaining > 0n && head < items.length) {
                        const item = items[head];
                        const used = remaining < item.remaining ? remaining : item.remaining;
                        item.remaining -= used;
                        remaining -= used;
                        if (item.remaining === 0n) head++;
                    }
                    unapplied += remaining;
                }
            }
        }
        return {items: items.slice(head), unapplied};
    }

    registerAccount(code: string, type: AccountType, name: string): void {
        if (this.accounts.has(code)) throw new CommandError(`duplicate account ${code}`);
        for (const other of this.codes()) {
            if ((code.startsWith(other) || other.startsWith(code)) &&
                    accountClass(type) !== accountClass(this.accounts.get(other)!.type)) {
                throw new CommandError(`class mismatch ${code} ${other}`);
            }
        }
        this.accounts.set(code, {code, type, name, active: true});
        this.emit('ACCOUNT', code, type, name, 'parent', this.parent(code));
    }

    deactivate(code: string): void {
        const account = this.account(code);
        if (!account.active) throw new CommandError(`already inactive ${code}`);
        const balance = this.balance(code);
        if (balance !== 0n) throw new CommandError(`nonzero balance ${code} ${money(balance)}`);
        account.active = false;
        this.emit('DEACTIVATE', code, account.name);
    }

    openBlock(kind: BlockKind, key: string, date: string | null, memo: string): void {
        if (this.block !== null) this.emit('DISCARD', this.block.key, 'lines', this.block.lines.length);
        this.block = kind === 'journal'
            ? {kind, key, date: date!, memo, lines: []}
            : {kind, key, date: null, memo, lines: []};
    }

    addLine(side: Side, code: string, amount: string, partner: string | null = null): void {
        if (this.block === null) throw new CommandError('no open entry');
        this.block.lines.push({side, account: code, amount: cents(amount), partner});
    }

    postDraft(): void {
        if (this.block === null) throw new CommandError('no open entry');
        const block = this.block;
        this.block = null;
        let day: number | null = null;
        if (block.kind === 'journal') {
            if (this.entryIndex.has(block.key)) throw new CommandError(`duplicate entry ${block.key}`);
            day = checkedDate(block.date);
            this.checkClosed(day);
        } else if (this.templates.has(block.key)) {
            throw new CommandError(`duplicate template ${block.key}`);
        }
        if (block.lines.length < 2) throw new CommandError(`too few lines ${block.key}`);
        for (const line of block.lines) {
            const account = this.account(line.account);
            if (block.kind === 'journal' && !account.active) throw new CommandError(`inactive account ${line.account}`);
            if (line.amount === 0n) throw new CommandError(`zero amount ${line.account}`);
        }
        const debit = sideTotal(block.lines, 'DR');
        const credit = sideTotal(block.lines, 'CR');
        if (debit !== credit) throw new CommandError(`unbalanced ${block.key} debit ${money(debit)} credit ${money(credit)}`);
        if (block.kind === 'journal') {
            this.post(block.key, day!, 'journal', block.memo, block.lines);
            this.emit('POST', block.key, dateText(day!), 'lines', block.lines.length, 'amount', money(debit));
        } else {
            this.templates.set(block.key, {name: block.key, memo: block.memo, lines: block.lines, uses: 0});
            this.emit('TEMPLATE', block.key, 'lines', block.lines.length, 'amount', money(debit));
        }
    }

    draft(): void {
        if (this.block === null) throw new CommandError('no open entry');
        const block = this.block;
        const debit = sideTotal(block.lines, 'DR'), credit = sideTotal(block.lines, 'CR');
        this.emit('DRAFT', block.kind, block.key, 'lines', block.lines.length,
            'debit', money(debit), 'credit', money(credit), 'difference', money(debit - credit));
    }

    reverse(id: string, date: string): void {
        const entry = this.entry(id);
        if (['reversal', 'closing', 'reopen'].includes(entry.category)) throw new CommandError(`cannot reverse ${id}`);
        if (entry.reversedBy !== null) throw new CommandError(`already reversed ${id}`);
        const day = checkedDate(date);
        if (day < entry.day) throw new CommandError(`reverse before entry ${id} ${dateText(entry.day)}`);
        this.checkClosed(day);
        this.active(entry.lines.map(line => line.account));
        const reversed = this.reverseEntry(entry, `${id}-R`, day, 'reversal', entry.memo);
        this.emit('REVERSE', id, 'entry', reversed.id, date, 'amount', money(sideTotal(reversed.lines, 'DR')));
    }

    recur(name: string, date: string, count: number): void {
        const template = this.templates.get(name);
        if (template === undefined) throw new CommandError(`unknown template ${name}`);
        const start = checkedDate(date);
        if (count === 0) throw new CommandError('invalid count');
        this.checkClosed(start);
        this.active(template.lines.map(line => line.account));
        this.emit('RECUR', name, 'count', count);
        for (let i = 0; i < count; i++) {
            const entry = this.post(`${name}-${++template.uses}`, monthsAfter(start, i), 'recurring', template.memo, template.lines);
            this.indented(2, 'POST', entry.id, dateText(entry.day), 'lines', entry.lines.length,
                'amount', money(sideTotal(entry.lines, 'DR')));
        }
    }

    depreciate(date: string, asset: string, contra: string, expense: string, life: number): void {
        const day = checkedDate(date);
        this.checkClosed(day);
        this.account(asset, 'ASSET');
        this.account(contra, 'CONTRA_ASSET');
        this.account(expense, 'EXPENSE');
        this.active([contra, expense]);
        const cost = this.balance(asset, day), accumulated = this.balance(contra, day);
        const installment = cost / BigInt(life);
        const amount = cost > 0n ? (installment < cost - accumulated ? installment : cost - accumulated) : 0n;
        if (amount <= 0n) throw new CommandError(`nothing to depreciate ${asset}`);
        const entry = this.post(`DEP-${++this.depreciationCount}`, day, 'depreciation', 'depreciation', [
            {side: 'DR', account: expense, amount, partner: null},
            {side: 'CR', account: contra, amount, partner: null},
        ]);
        this.emit('DEPRECIATE', asset, 'entry', entry.id, date, 'amount', money(amount),
            'accumulated', money(accumulated + amount), 'book', money(cost - accumulated - amount));
    }

    interest(code: string, offset: string, first: string, last: string, rate: number): void {
        const account = this.account(code);
        if (account.type !== 'ASSET' && account.type !== 'LIABILITY') throw new CommandError(`not interest bearing ${code}`);
        this.account(offset, account.type === 'ASSET' ? 'REVENUE' : 'EXPENSE');
        const [start, end] = checkedRange(first, last);
        this.checkClosed(end);
        this.active([code, offset]);
        const sum = this.dailySum(code, start, end);
        const amount = sum * BigInt(rate) / 3650000n;
        if (amount <= 0n) throw new CommandError(`no interest ${code}`);
        const debit = account.type === 'ASSET' ? code : offset;
        const credit = account.type === 'ASSET' ? offset : code;
        const entry = this.post(`INT-${++this.interestCount}`, end, 'interest', 'interest', [
            {side: 'DR', account: debit, amount, partner: null},
            {side: 'CR', account: credit, amount, partner: null},
        ]);
        const days = end - start + 1;
        this.emit('INTEREST', code, 'entry', entry.id, last, 'days', days,
            'average', money(sum / BigInt(days)), 'amount', money(amount));
    }

    writeoff(date: string, receivable: string, expense: string, age: number): void {
        const day = checkedDate(date);
        this.checkClosed(day);
        this.account(receivable, 'ASSET');
        this.account(expense, 'EXPENSE');
        this.active([receivable, expense]);
        const targets: {partner: string; amount: bigint}[] = [];
        let amount = 0n;
        for (const partner of this.partners(receivable, day)) {
            const {items} = this.openItems(receivable, partner, day);
            let value = 0n;
            for (const item of items) if (day - item.entry.day > age) value += item.remaining;
            if (value > 0n) { targets.push({partner, amount: value}); amount += value; }
        }
        if (amount === 0n) throw new CommandError(`nothing to write off ${receivable}`);
        const lines: PostingLine[] = [{side: 'DR', account: expense, amount, partner: null},
            ...targets.map<PostingLine>(target => ({side: 'CR', account: receivable, ...target}))];
        const entry = this.post(`WO-${++this.writeoffCount}`, day, 'writeoff', 'writeoff', lines);
        this.emit('WRITEOFF', receivable, 'entry', entry.id, date, 'partners', targets.length, 'amount', money(amount));
        for (const target of targets) this.indented(2, target.partner, money(target.amount));
    }

    close(date: string, equity: string): void {
        const day = checkedDate(date);
        this.checkClosed(day);
        this.account(equity, 'EQUITY');
        this.active([equity]);
        const totals = this.totals(0, day);
        const codes = this.codes().filter(code => INCOME_TYPES.has(this.accounts.get(code)!.type) && totals.difference(code) !== 0n);
        this.active(codes);
        const lines: PostingLine[] = [];
        let income = 0n;
        for (const code of codes) {
            const difference = totals.difference(code);
            lines.push({side: difference > 0n ? 'CR' : 'DR', account: code,
                amount: difference > 0n ? difference : -difference, partner: null});
            income -= difference;
        }
        if (income !== 0n) lines.push({side: income > 0n ? 'CR' : 'DR', account: equity,
            amount: income > 0n ? income : -income, partner: null});
        this.closeCount++;
        let id: string | null = null;
        if (lines.length > 0) {
            id = `CLOSE-${this.closeCount}`;
            this.post(id, day, 'closing', 'closing', lines);
        }
        this.closes.push({day, id});
        if (id === null) this.emit('CLOSE', date, 'no entry');
        else this.emit('CLOSE', date, 'entry', id, 'lines', lines.length, 'net income', money(income));
    }

    reopen(): void {
        const record = this.closes.at(-1);
        if (record === undefined) throw new CommandError('nothing to reopen');
        let id: string | null = null;
        if (record.id !== null) {
            const entry = this.entryIndex.get(record.id)!;
            this.active(entry.lines.map(line => line.account));
            id = `${entry.id}-R`;
            this.reverseEntry(entry, id, record.day, 'reopen', 'reopen');
        }
        this.closes.pop();
        const closed = this.closedThrough();
        this.emit('REOPEN', dateText(record.day), ...(id === null ? ['no', 'entry'] : ['entry', id]),
            'closed', closed === null ? 'none' : dateText(closed));
    }

    ledger(code: string, first: string, last: string): void {
        const account = this.account(code);
        const [start, end] = checkedRange(first, last);
        const sign = normalSign(account.type);
        let running = this.balance(code, start - 1), debit = 0n, credit = 0n;
        this.emit('LEDGER', code, account.name, first, last);
        this.indented(2, 'opening', money(running));
        for (const entry of this.selected(start, end).sort(postingOrder)) {
            for (const line of entry.lines) {
                if (line.account !== code) continue;
                running += sign * lineDifference(line);
                if (line.side === 'DR') debit += line.amount;
                else credit += line.amount;
                this.indented(2, dateText(entry.day), entry.id, line.side, money(line.amount),
                    'balance', money(running), entry.memo);
            }
        }
        const days = end - start + 1;
        this.indented(2, 'ending', money(running), 'debits', money(debit), 'credits', money(credit),
            'days', days, 'average', money(this.dailySum(code, start, end) / BigInt(days)));
    }

    activity(code: string, year: number): void {
        const account = this.account(code);
        let debit = 0n, credit = 0n;
        this.emit('ACTIVITY', code, account.name, year);
        for (let month = 1; month <= 12; month++) {
            const first = dayNumber(year, month, 1);
            const last = dayNumber(year, month, monthLength(year, month));
            const totals = this.totals(first, last);
            debit += totals.debit(code);
            credit += totals.credit(code);
            this.indented(2, `${year}-${padded(month)}`, 'debit', money(totals.debit(code)),
                'credit', money(totals.credit(code)), 'balance', money(this.balance(code, last)));
        }
        this.indented(2, 'total debit', money(debit), 'credit', money(credit));
    }

    trial(date: string): void {
        const totals = this.totals(0, checkedDate(date));
        let debit = 0n, credit = 0n;
        this.emit('TRIAL', date);
        for (const code of this.codes()) {
            const value = totals.difference(code);
            if (value === 0n) continue;
            if (value > 0n) {
                debit += value;
                this.indented(2, code, this.accounts.get(code)!.name, 'debit', money(value));
            } else {
                credit -= value;
                this.indented(2, code, this.accounts.get(code)!.name, 'credit', money(-value));
            }
        }
        this.indented(2, 'total debit', money(debit), 'credit', money(credit));
    }

    section(heading: string, types: readonly AccountType[], sign: bigint, totals: Totals, earnings: bigint | null = null): bigint {
        const groups = new Map<string, {code: string; value: bigint}[]>();
        let amount = earnings ?? 0n;
        for (const code of this.codes()) {
            if (!types.includes(this.accounts.get(code)!.type)) continue;
            const value = sign * totals.difference(code);
            amount += value;
            const top = this.topLevel(code);
            if (!groups.has(top)) groups.set(top, []);
            groups.get(top)!.push({code, value});
        }
        this.indented(2, heading, money(amount));
        for (const top of [...groups.keys()].sort()) {
            const group = groups.get(top)!;
            if (!group.some(account => account.value !== 0n)) continue;
            const subtotal = group.reduce((sum, account) => sum + account.value, 0n);
            this.indented(4, top, this.accounts.get(top)!.name, money(subtotal));
            for (const account of group) {
                if (account.value !== 0n) this.indented(6, account.code, this.accounts.get(account.code)!.name, money(account.value));
            }
        }
        if (earnings !== null) this.indented(4, 'current earnings', money(earnings));
        return amount;
    }

    income(first: string, last: string): void {
        const [start, end] = checkedRange(first, last);
        const totals = this.totals(start, end, true);
        this.emit('INCOME', first, last);
        const revenue = this.section('REVENUE', ['REVENUE'], -1n, totals);
        const expense = this.section('EXPENSE', ['EXPENSE'], 1n, totals);
        this.indented(2, 'NET INCOME', money(revenue - expense));
    }

    balanceSheet(date: string): void {
        const totals = this.totals(0, checkedDate(date));
        let earnings = 0n;
        for (const code of this.codes()) {
            if (INCOME_TYPES.has(this.accounts.get(code)!.type)) earnings -= totals.difference(code);
        }
        this.emit('BALANCE', date);
        const assets = this.section('ASSETS', ['ASSET', 'CONTRA_ASSET'], 1n, totals);
        const liabilities = this.section('LIABILITIES', ['LIABILITY'], -1n, totals);
        const equity = this.section('EQUITY', ['EQUITY'], -1n, totals, earnings);
        if (assets === liabilities + equity) this.indented(2, 'check ok');
        else this.indented(2, 'check mismatch', money(assets - liabilities - equity));
    }

    rollup(prefix: string, date: string): void {
        const day = checkedDate(date);
        const codes = this.codes().filter(code => code.startsWith(prefix));
        this.emit('ROLLUP', prefix, date);
        if (codes.length === 0) { this.indented(2, '(none)'); return; }
        const totals = this.totals(0, day);
        let debit = 0n, credit = 0n;
        for (const code of codes) {
            const account = this.accounts.get(code)!;
            const sign = normalSign(account.type);
            const depth = this.ancestors(code).filter(ancestor => ancestor.startsWith(prefix)).length;
            let subtotal = 0n;
            for (const descendant of codes) if (descendant.startsWith(code)) subtotal += totals.difference(descendant);
            this.indented(2 * (1 + depth), code, account.name, 'own', money(sign * totals.difference(code)),
                'total', money(sign * subtotal));
            debit += totals.debit(code);
            credit += totals.credit(code);
        }
        this.indented(2, 'postings debit', money(debit), 'credit', money(credit));
    }

    agingColumns(buckets: readonly bigint[], unapplied: bigint): string[] {
        const columns: string[] = [];
        for (let i = 0; i < buckets.length; i++) columns.push(AGING_LABELS[i], money(buckets[i]));
        columns.push('unapplied', money(unapplied), 'balance', money(buckets.reduce((sum, value) => sum + value, 0n) - unapplied));
        return columns;
    }

    aging(code: string, date: string): void {
        const account = this.account(code);
        const day = checkedDate(date);
        const totals = [0n, 0n, 0n, 0n];
        let totalUnapplied = 0n;
        this.emit('AGING', code, account.name, date);
        for (const partner of this.partners(code, day)) {
            const {items, unapplied} = this.openItems(code, partner, day);
            if (items.length === 0 && unapplied === 0n) continue;
            const buckets = [0n, 0n, 0n, 0n];
            for (const item of items) {
                const age = day - item.entry.day;
                buckets[age <= 30 ? 0 : age <= 60 ? 1 : age <= 90 ? 2 : 3] += item.remaining;
            }
            this.indented(2, partner, ...this.agingColumns(buckets, unapplied));
            for (let i = 0; i < 4; i++) totals[i] += buckets[i];
            totalUnapplied += unapplied;
        }
        this.indented(2, 'total', ...this.agingColumns(totals, totalUnapplied));
    }

    items(code: string, partner: string, date: string): void {
        const account = this.account(code);
        const day = checkedDate(date);
        const {items, unapplied} = this.openItems(code, partner, day);
        this.emit('ITEMS', code, account.name, partner, date);
        let balance = -unapplied;
        for (const item of items) {
            this.indented(2, dateText(item.entry.day), item.entry.id, 'amount', money(item.original),
                'open', money(item.remaining), 'age', day - item.entry.day);
            balance += item.remaining;
        }
        this.indented(2, 'unapplied', money(unapplied), 'balance', money(balance));
    }

    entryReport(id: string): void {
        const entry = this.entry(id);
        this.emit('ENTRY', id, dateText(entry.day), entry.category, entry.memo);
        for (const line of entry.lines) {
            const parts = [line.side, line.account, this.accounts.get(line.account)!.name, money(line.amount)];
            if (line.partner !== null) parts.push(line.partner);
            this.indented(2, ...parts);
        }
        this.indented(2, 'total', money(sideTotal(entry.lines, 'DR')));
        if (entry.reverses !== null) this.indented(2, 'reverses', entry.reverses);
        if (entry.reversedBy !== null) this.indented(2, 'reversed by', entry.reversedBy);
    }

    daybook(first: string, last: string): void {
        const [start, end] = checkedRange(first, last);
        const entries = this.selected(start, end).sort(postingOrder);
        let total = 0n;
        this.emit('DAYBOOK', first, last);
        for (const entry of entries) {
            const amount = sideTotal(entry.lines, 'DR');
            this.indented(2, dateText(entry.day), entry.id, entry.category, money(amount), entry.memo);
            total += amount;
        }
        this.indented(2, 'total entries', entries.length, 'amount', money(total));
    }

    listAccounts(): void {
        this.emit('ACCOUNTS');
        const codes = this.codes();
        if (codes.length === 0) { this.indented(2, '(none)'); return; }
        const totals = this.totals();
        for (const code of codes) {
            const account = this.accounts.get(code)!;
            this.indented(2, code, account.type, account.name, 'parent', this.parent(code),
                'balance', money(normalSign(account.type) * totals.difference(code)), account.active ? 'active' : 'inactive');
        }
    }

    listTemplates(): void {
        this.emit('TEMPLATES');
        const names = [...this.templates.keys()].sort();
        if (names.length === 0) { this.indented(2, '(none)'); return; }
        for (const name of names) {
            const template = this.templates.get(name)!;
            this.indented(2, name, template.memo, 'lines', template.lines.length,
                'amount', money(sideTotal(template.lines, 'DR')), 'used', template.uses);
        }
    }

    status(): void {
        const closed = this.closedThrough();
        let inactive = 0;
        for (const account of this.accounts.values()) if (!account.active) inactive++;
        this.emit('STATUS accounts', this.accounts.size, 'inactive', inactive, 'entries', this.entries.length,
            'templates', this.templates.size, 'closed', closed === null ? 'none' : dateText(closed),
            'open', this.block?.key ?? 'none');
    }

    command(words: readonly string[]): void {
        const [command, ...args] = words;
        switch (command) {
            case 'ACCOUNT': this.registerAccount(args[0], args[1] as AccountType, args[2]); break;
            case 'DEACTIVATE': this.deactivate(args[0]); break;
            case 'JOURNAL': this.openBlock('journal', args[0], args[1], args[2]); break;
            case 'TEMPLATE': this.openBlock('template', args[0], null, args[1]); break;
            case 'DR': case 'CR': this.addLine(command, args[0], args[1], args[2] ?? null); break;
            case 'POST': this.postDraft(); break;
            case 'DRAFT': this.draft(); break;
            case 'REVERSE': this.reverse(args[0], args[1]); break;
            case 'RECUR': this.recur(args[0], args[1], Number(args[2])); break;
            case 'DEPRECIATE': this.depreciate(args[0], args[1], args[2], args[3], Number(args[4])); break;
            case 'INTEREST': this.interest(args[0], args[1], args[2], args[3], Number(args[4])); break;
            case 'WRITEOFF': this.writeoff(args[0], args[1], args[2], Number(args[3])); break;
            case 'CLOSE': this.close(args[0], args[1]); break;
            case 'REOPEN': this.reopen(); break;
            case 'LEDGER': this.ledger(args[0], args[1], args[2]); break;
            case 'ACTIVITY': this.activity(args[0], Number(args[1])); break;
            case 'TRIAL': this.trial(args[0]); break;
            case 'INCOME': this.income(args[0], args[1]); break;
            case 'BALANCE': this.balanceSheet(args[0]); break;
            case 'ROLLUP': this.rollup(args[0], args[1]); break;
            case 'AGING': this.aging(args[0], args[1]); break;
            case 'ITEMS': this.items(args[0], args[1], args[2]); break;
            case 'ENTRY': this.entryReport(args[0]); break;
            case 'DAYBOOK': this.daybook(args[0], args[1]); break;
            case 'ACCOUNTS': this.listAccounts(); break;
            case 'TEMPLATES': this.listTemplates(); break;
            case 'STATUS': this.status(); break;
            default: throw new Error(`unexpected command ${command}`);
        }
    }
}

const input = readFileSync(0, 'utf8').split(/\r?\n/);
const count = Number(input[0]);
const books = new Books();
for (let i = 1; i <= count; i++) {
    try {
        books.command(input[i].split(' '));
    } catch (error) {
        if (!(error instanceof CommandError)) throw error;
        books.emit('ERROR', error.message);
    }
}
if (books.output.length > 0) process.stdout.write(books.output.join('\n') + '\n');
