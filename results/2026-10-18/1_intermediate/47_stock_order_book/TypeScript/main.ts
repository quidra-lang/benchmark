import { readFileSync } from 'node:fs';
class CommandError extends Error {
}
const opposite = (side: string) => side === 'BUY' ? 'SELL' : 'BUY';
const fixed = (c: number) => `${Math.floor(c / 100)}.${String(c % 100).padStart(2, '0')}`;
const average = (value: number, quantity: number) => fixed(Math.floor(value * 100 / quantity));
const check = (bad: boolean, message: string) => {
    if (bad) throw new CommandError(message);
};
class Order {
    filled = 0;
    value = 0;
    visible = 0;
    priority = 0;
    status = 'PENDING';
    history = ['ACCEPT'];
    id: string;
    trader: string;
    type: string;
    side: string;
    quantity: number;
    remaining: number;
    price: number;
    trigger: number;
    peak: number;
    condition: string;
    constructor(id: string, trader: string, type: string, side: string, quantity: number, price = -1, trigger = -1, peak = -1,
        condition = '') {
        this.id = id;
        this.trader = trader;
        this.type = type;
        this.side = side;
        this.quantity = this.remaining = quantity;
        this.price = price;
        this.trigger = trigger;
        this.peak = peak;
        this.condition = condition;
    }
    resting() {
        return this.status === 'OPEN' || this.status === 'PARTIAL';
    }
    active() {
        return this.resting() || this.status === 'PENDING';
    }
    matches(price: number) {
        return this.price < 0 || (this.side === 'BUY' ? price <= this.price : price >= this.price);
    }
    triggered(price: number) {
        return this.side === 'BUY' ? price >= this.trigger : price <= this.trigger;
    }
    line() {
        return `ORDER ${this.id} ${this.status} ${this.filled}/${this.quantity}`;
    }
    details() {
        return `${this.id} ${this.trader} ${this.type} ${this.side} ${this.price < 0 ? '-' : this.price} ${this.status} ${this.filled}/${this.quantity} avg ${this.filled ? average(this.value, this.filled) : '-'}` +
        (this.trigger < 0 ? '' : ` trigger ${this.trigger}`);
    }
}
class Trader {
    bought = 0;
    sold = 0;
    cash = 0;
    fees = 0;
    limit = -1;
    name: string;
    constructor(name: string) {
        this.name = name;
    }
    net() {
        return this.bought - this.sold;
    }
    volume() {
        return this.bought + this.sold;
    }
    pnl(mark: number) {
        return this.cash + this.net() * mark;
    }
    position(mark: number) {
        return `POSITION ${this.name} bought ${this.bought} sold ${this.sold} net ${this.net()} cash ${this.cash} fees ${this.fees} pnl ${this.pnl(mark)}`;
    }
}
interface Trade {
    number: number;
    price: number;
    quantity: number;
    buy: Order;
    sell: Order;
    taker: Order;
    buyFee: number;
    sellFee: number;
}
interface Level {
    price: number;
    quantity: number;
    count: number;
}
class Engine {
    orders = new Map<string, Order>();
    traders = new Map<string, Trader>();
    trades: Trade[] = [];
    output: string[] = [];
    priority = 1;
    halted = false;
    band = 0;
    tick = 1;
    lot = 1;
    makerFee = 0;
    takerFee = 0;
    emit(...parts: (string | number)[]) {
        this.output.push(parts.join(' '));
    }
    all() {
        return [...this.orders.values()];
    }
    register(name: string) {
        let t = this.traders.get(name);
        if (!t) {
            t = new Trader(name);
            this.traders.set(name, t);
        }
        return t;
    }
    trader(name: string) {
        const t = this.traders.get(name);
        if (!t) throw new CommandError('unknown trader');
        return t;
    }
    order(id: string) {
        const o = this.orders.get(id);
        if (!o) throw new CommandError('unknown order');
        return o;
    }
    book(side: string) {
        return this.all().filter(o => o.side === side && o.resting()).sort((a, b) => (side === 'BUY' ? b.price - a.price : a.price - b.price) || a.priority - b.priority);
    }
    levels(side: string) {
        const levels: Level[] = [];
        for (const o of this.book(side)) {
            const last = levels[levels.length - 1];
            if (last && last.price === o.price) {
                last.quantity += o.visible;
                ++last.count;
            }
            else levels.push({
                price: o.price, quantity: o.visible, count: 1
            });
        }
        return levels;
    }
    last() {
        return this.trades.length ? this.trades[this.trades.length - 1].price : -1;
    }
    exposure(name: string, side: string, excluded: Order | null = null) {
        const t = this.trader(name);
        return (side === 'BUY' ? t.net() : -t.net()) + this.all().filter(o => o.trader === name && o.side === side && o.active() && o !== excluded).reduce((n,
        o) => n + o.remaining, 0);
    }
    risk(name: string, side: string, quantity: number, excluded: Order | null = null) {
        const t = this.traders.get(name);
        check(!!t && t.limit >= 0 && this.exposure(name, side, excluded) + quantity > t.limit, 'risk limit');
    }
    checkBand(price: number) {
        check(this.band > 0 && this.last() >= 0 && Math.abs(price - this.last()) > this.band, 'outside band');
    }
    tradeLine(t: Trade) {
        return `TRADE ${t.number} ${t.price} ${t.quantity} ${t.buy.id} ${t.buy.trader} ${t.sell.id} ${t.sell.trader}`;
    }
    match(o: Order) {
        while (o.remaining) {
            const m = this.book(opposite(o.side))[0];
            if (!m || !o.matches(m.price)) break;
            if (m.trader === o.trader) {
                this.emit('STP', m.id, m.remaining);
                m.history.push(`STP ${m.remaining}`);
                m.remaining = 0;
                m.status = 'CANCELLED';
                continue;
            }
            const q = Math.min(o.remaining, m.visible), p = m.price;
            const buy = o.side === 'BUY' ? o : m, sell = o.side === 'SELL' ? o : m;
            const tf = q * this.takerFee, mf = q * this.makerFee;
            const t = {
                number: this.trades.length + 1, price: p, quantity: q, buy, sell, taker: o,
                buyFee: o.side === 'BUY' ? tf : mf, sellFee: o.side === 'SELL' ? tf : mf
            };
            this.trades.push(t);
            for (const a of [o, m]) {
                a.remaining -= q;
                a.filled += q;
                a.value += p * q;
                a.history.push(`FILL ${t.number} ${p} ${q}`);
            }
            m.visible -= q;
            const bt = this.trader(buy.trader), st = this.trader(sell.trader);
            bt.bought += q;
            bt.cash -= p * q + t.buyFee;
            bt.fees += t.buyFee;
            st.sold += q;
            st.cash += p * q - t.sellFee;
            st.fees += t.sellFee;
            this.emit(this.tradeLine(t));
            m.status = m.remaining ? 'PARTIAL' : 'FILLED';
            if (m.remaining && !m.visible) {
                m.priority = this.priority++;
                m.visible = Math.min(m.peak, m.remaining);
                m.history.push(`REFRESH ${m.visible} ${m.remaining - m.visible}`);
                this.emit('REFRESH', m.id, m.visible, m.remaining - m.visible);
            }
        }
    }
    post(o: Order, replaced = false) {
        if (!o.remaining) o.status = 'FILLED';
        else if (replaced || o.type === 'ICEBERG' || o.type === 'STOPLIMIT' || (o.type === 'LIMIT' && o.condition !== 'IOC')) {
            o.priority = this.priority++;
            o.visible = o.peak < 0 ? o.remaining : Math.min(o.peak, o.remaining);
            o.status = o.filled ? 'PARTIAL' : 'OPEN';
            o.history.push(`REST ${o.price} ${o.visible}`);
        } else {
            o.history.push(`EXPIRE ${o.remaining}`);
            o.remaining = 0;
            o.status = 'CANCELLED';
        }
        this.emit(o.line());
    }
    trigger() {
        while (this.trades.length) {
            const selected = this.all().filter(o => o.status === 'PENDING' && o.triggered(this.last()));
            if (!selected.length) break;
            for (const o of selected) o.status = 'TRIGGERING';
            for (const o of selected) {
                this.emit('TRIGGER', o.id);
                o.history.push('TRIGGER');
                this.match(o);
                this.post(o);
            }
        }
    }
    cancel(o: Order) {
        o.history.push(`CANCEL ${o.remaining}`);
        o.remaining = 0;
        o.status = 'CANCELLED';
        this.emit(o.line());
    }
    bar(trades: Trade[]) {
        return `open ${trades[0].price} high ${trades.reduce((best, t) => Math.max(best, t.price), trades[0].price)} low ${trades.reduce((best, t) => Math.min(best, t.price), trades[0].price)} close ${trades[trades.length - 1].price} volume ${trades.reduce((n, t) => n + t.quantity, 0)}`;
    }
    execute(line: string) {
        const [c, ...a] = line.split(' ');
        try {
            this.command(c, a);
        }
        catch (e) {
            if (!(e instanceof CommandError)) throw e;
            this.emit(...(['LIMIT', 'MARKET', 'STOP', 'STOPLIMIT', 'ICEBERG', 'CANCEL', 'REPLACE'].includes(c) ? ['REJECT', a[0],
            e.message] : ['ERROR', e.message]));
        }
    }
    command(c: string, a: string[]) {
        const [id, name, side] = a;
        if (['LIMIT', 'MARKET', 'STOP', 'STOPLIMIT', 'ICEBERG'].includes(c)) {
            const p = c === 'MARKET' || c === 'STOP' ? -1 : Number(a[c === 'STOPLIMIT' ? 4 : 3]);
            const r = c === 'STOP' || c === 'STOPLIMIT' ? Number(a[3]) : -1;
            const q = Number(a[c === 'MARKET' ? 3 : c === 'STOPLIMIT' ? 5 : 4]);
            const peak = c === 'ICEBERG' ? Number(a[5]) : -1, condition = c === 'LIMIT' ? a[5] ?? '' : '';
            const prices = [p, r].filter(x => x >= 0);
            check(this.halted, 'halted');
            check(this.orders.has(id), 'duplicate id');
            check(prices.includes(0), 'invalid price');
            check(!q, 'invalid quantity');
            check(prices.some(x => x % this.tick !== 0), 'invalid tick');
            check(q % this.lot !== 0, 'invalid lot');
            if (c === 'ICEBERG') check(peak === 0 || peak > q || peak % this.lot !== 0, 'invalid peak');
            const o = new Order(id, name, c, side, q, p, r, peak, condition);
            if (r >= 0) check(this.last() >= 0 && o.triggered(this.last()), 'invalid trigger');
            if (p >= 0) this.checkBand(p);
            this.risk(name, side, q);
            const book = this.book(opposite(side));
            check(condition === 'POSTONLY' && !!book[0] && o.matches(book[0].price), 'would cross');
            check(condition === 'FOK' && book.filter(m => m.trader !== name && o.matches(m.price)).reduce((n, m) => n + m.remaining,
            0) < q, 'unfillable');
            this.register(name);
            this.orders.set(id, o);
            if (r >= 0) this.emit(o.line());
            else {
                if (condition !== 'POSTONLY') this.match(o);
                this.post(o);
                this.trigger();
            }
            return;
        }
        switch (c) {
            case 'CANCEL': {
                const o = this.order(id);
                check(!o.active(), 'not open');
                this.cancel(o);
                break;
            }
            case 'REPLACE': {
                check(this.halted, 'halted');
                const o = this.order(id);
                check(!o.resting(), 'not open');
                const p = Number(name), q = Number(side), moved = p !== o.price;
                check(!p, 'invalid price');
                check(!q, 'invalid quantity');
                check(moved && p % this.tick !== 0, 'invalid tick');
                check(q % this.lot !== 0, 'invalid lot');
                check(!moved && q === o.remaining, 'no change');
                if (moved) this.checkBand(p);
                if (q > o.remaining) this.risk(o.trader, o.side, q, o);
                const kept = !moved && q < o.remaining;
                o.quantity = o.filled + q;
                o.remaining = q;
                o.price = p;
                o.history.push(`REPLACE ${p} ${q} ${kept ? 'kept' : 'lost'}`);
                this.emit('REPLACE', id, kept ? 'kept' : 'lost');
                if (kept) {
                    o.visible = Math.min(o.visible, q);
                    this.emit(o.line());
                }
                else {
                    o.status = 'EXECUTING';
                    this.match(o);
                    this.post(o, true);
                    this.trigger();
                }
                break;
            }
            case 'CANCELALL': {
                this.trader(id);
                const os = this.all().filter(o => o.trader === id && o.active());
                this.emit(c, id, os.length);
                for (const o of os) this.cancel(o);
                break;
            }
            case 'HALT': check(this.halted, 'already halted');
            this.halted = true;
            this.emit(c);
            break;
            case 'RESUME': check(!this.halted, 'not halted');
            this.halted = false;
            this.emit(c);
            break;
            case 'RISK': this.register(id).limit = Number(name);
            this.emit(c, id, name, 'exposure buy', this.exposure(id, 'BUY'), 'sell', this.exposure(id, 'SELL'));
            break;
            case 'FEE': {
                const maker = Number(id), taker = Number(name);
                check(maker + taker < 0, 'invalid fee');
                this.makerFee = maker;
                this.takerFee = taker;
                this.emit(c, 'maker', maker, 'taker', taker);
                break;
            }
            case 'BAND': this.band = Number(id);
            this.emit(c, id);
            break;
            case 'TICK': case 'LOT': check(Number(id) === 0, 'invalid size');
            if (c === 'TICK') this.tick = Number(id);
            else this.lot = Number(id);
            this.emit(c, id);
            break;
            case 'BOOK': {
                const n = Number(id);
                check(!n, 'invalid depth');
                const bids = this.levels('BUY'), asks = this.levels('SELL');
                this.emit(c, 'bids', bids.length, 'asks', asks.length);
                for (const l of asks.slice(0, n).reverse()) this.emit('ASK', l.price, l.quantity, l.count);
                for (const l of bids.slice(0, n)) this.emit('BID', l.price, l.quantity, l.count);
                break;
            }
            case 'ORDERS': {
                this.trader(id);
                const os = this.all().filter(o => o.trader === id && o.active());
                this.emit(c, id, os.length);
                for (const o of os) this.emit(o.details());
                break;
            }
            case 'STATUS': this.emit(c, this.order(id).details());
            break;
            case 'HISTORY': {
                const o = this.order(id);
                this.emit(c, id, o.history.length);
                for (const h of o.history) this.emit(h);
                break;
            }
            case 'POSITION': this.emit(this.trader(id).position(Math.max(0, this.last())));
            break;
            case 'FILLS': {
                this.trader(id);
                const ts = this.trades.filter(t => t.buy.trader === id || t.sell.trader === id);
                this.emit(c, id, ts.length);
                let net = 0;
                for (const t of ts) {
                    const buy = t.buy.trader === id, o = buy ? t.buy : t.sell;
                    net += buy ? t.quantity : -t.quantity;
                    this.emit(t.number, buy ? 'BUY' : 'SELL', t.price, t.quantity, o.id, o === t.taker ? 'TAKER' : 'MAKER', 'fee', buy ? t.buyFee : t.sellFee,
                    'net', net);
                }
                break;
            }
            case 'LAST': {
                const t = this.trades[this.trades.length - 1];
                if (t) this.emit(c, t.price, t.quantity);
                else this.emit(c, 'none');
                break;
            }
            case 'VWAP': if (!this.trades.length) this.emit(c, 'none');
            else {
                const v = this.trades.reduce((n, t) => n + t.quantity, 0);
                this.emit(c, average(this.trades.reduce((n, t) => n + t.price * t.quantity, 0), v), 'volume', v, 'trades', this.trades.length);
            }
            break;
            case 'SPREAD': {
                const b = this.book('BUY')[0], s = this.book('SELL')[0];
                if (b && s) this.emit(c, 'bid', b.price, 'ask', s.price, 'spread', s.price - b.price, 'mid', `${Math.floor((b.price + s.price) / 2)}.${(b.price + s.price) % 2 ? 5 : 0}`);
                else this.emit(c, 'bid', b ? b.price : 'none', 'ask', s ? s.price : 'none');
                break;
            }
            case 'IMPACT': {
                const q = Number(name);
                check(!q, 'invalid quantity');
                const ls = this.levels(opposite(id));
                let r = q, cost = 0, worst = 0, used = 0;
                for (const l of ls) {
                    if (!r) break;
                    const n = Math.min(r, l.quantity);
                    r -= n;
                    cost += n * l.price;
                    worst = l.price;
                    ++used;
                }
                if (r) this.emit(c, id, q, 'insufficient', ls.reduce((n, l) => n + l.quantity, 0));
                else this.emit(c, id, q, 'avg', average(cost, q), 'worst', worst, 'levels', used);
                break;
            }
            case 'TRADES': {
                const n = Number(id);
                check(!n, 'invalid count');
                const ts = this.trades.slice(Math.max(0, this.trades.length - n));
                this.emit(c, ts.length, 'of', this.trades.length);
                for (const t of ts) this.emit(this.tradeLine(t));
                break;
            }
            case 'BARS': {
                const n = Number(id);
                check(!n, 'invalid count');
                this.emit(c, Math.ceil(this.trades.length / n));
                for (let i = 0; i < this.trades.length; i += n) this.emit(i / n + 1, this.bar(this.trades.slice(i, i + n)));
                break;
            }
            case 'RANK': {
                const mark = Math.max(0, this.last()), ts = [...this.traders.values()].sort((a, b) => b.pnl(mark) - a.pnl(mark) || b.volume() - a.volume() || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
                this.emit(c, ts.length);
                ts.forEach((t, i) => this.emit(i + 1, t.name, 'pnl', t.pnl(mark), 'volume', t.volume()));
                break;
            }
            case 'FLOW': {
                const b = this.trades.filter(t => t.taker.side === 'BUY').reduce((n, t) => n + t.quantity, 0), s = this.trades.filter(t => t.taker.side === 'SELL').reduce((n,
                t) => n + t.quantity, 0);
                this.emit(c, 'buy', b, 'sell', s, 'net', b - s);
                break;
            }
            case 'SUMMARY': if (this.trades.length) this.emit(c, 'trades', this.trades.length, 'volume', this.trades.reduce((n,
            t) => n + t.quantity, 0), this.bar(this.trades).split(' ').slice(0, -2).join(' '), 'fees', this.trades.reduce((n,
            t) => n + t.buyFee + t.sellFee, 0));
            else this.emit(c, 'trades', 0);
            for (const name of [...this.traders.keys()].sort()) this.emit(this.trader(name).position(Math.max(0, this.last())));
            break;
        }
    }
}
const lines = readFileSync(0, 'utf8').trimEnd().split('\n');
const engine = new Engine();
for (let i = 1; i <= Number(lines[0]); ++i) engine.execute(lines[i].replace(/\r$/, ''));
process.stdout.write(engine.output.join('\n') + '\n');
