use std::collections::{BTreeMap, HashMap};
use std::io::{self, Read};
fn check(good: bool, reason: &str) -> Result<(), String> {
    if good {
        Ok(())
    } else {
        Err(reason.into())
    }
}
fn decimal(x: i64) -> String {
    format!("{}.{:02}", x / 100, x % 100)
}
fn opposite(s: &str) -> &str {
    if s == "BUY" {
        "SELL"
    } else {
        "BUY"
    }
}
#[derive(Clone)]
struct Order {
    id: String,
    trader: String,
    kind: String,
    side: String,
    condition: String,
    status: String,
    price: Option<i64>,
    trigger: Option<i64>,
    peak: Option<i64>,
    quantity: i64,
    remaining: i64,
    visible: i64,
    filled: i64,
    value: i64,
    priority: i64,
    history: Vec<String>,
}
impl Order {
    fn active(&self) -> bool {
        matches!(self.status.as_str(), "OPEN" | "PARTIAL" | "PENDING")
    }
    fn resting(&self) -> bool {
        matches!(self.status.as_str(), "OPEN" | "PARTIAL")
    }
    fn matches(&self, p: i64) -> bool {
        self.price.is_none_or(|x| if self.side == "BUY" {
            p <= x
        } else {
            p >= x
        })
    }
    fn triggered(&self, p: i64) -> bool {
        if self.side == "BUY" {
            p >= self.trigger.unwrap()
        } else {
            p <= self.trigger.unwrap()
        }
    }
    fn line(&self) -> String {
        format!("ORDER {} {} {}/{}", self.id, self.status, self.filled, self.quantity)
    }
    fn details(&self) -> String {
        let mut s = format!("{} {} {} {} {} {} {}/{} avg {}", self.id, self.trader, self.kind, self.side, self.price.map_or("-".into(), |p| p.to_string()), self.status, self.filled, self.quantity, if self.filled == 0 {
            "-".into()
        } else {
            decimal(self.value * 100 / self.filled)
        });
        if let Some(r) = self.trigger {
            s += &format!(" trigger {}", r);
        }
        s
    }
    fn fill(&mut self, n: usize, p: i64, q: i64) {
        self.remaining -= q;
        self.filled += q;
        self.value += p * q;
        self.history.push(format!("FILL {} {} {}", n, p, q));
    }
}
#[derive(Default)]
struct Trader {
    bought: i64,
    sold: i64,
    cash: i64,
    fees: i64,
    limit: Option<i64>,
}
impl Trader {
    fn net(&self) -> i64 {
        self.bought - self.sold
    }
    fn volume(&self) -> i64 {
        self.bought + self.sold
    }
    fn pnl(&self, p: i64) -> i64 {
        self.cash + self.net() * p
    }
    fn position(&self, name: &str, p: i64) -> String {
        format!("POSITION {} bought {} sold {} net {} cash {} fees {} pnl {}", name, self.bought, self.sold, self.net(), self.cash, self.fees, self.pnl(p))
    }
}
#[derive(Clone)]
struct Trade {
    number: usize,
    price: i64,
    quantity: i64,
    buy: usize,
    sell: usize,
    taker: usize,
    buy_fee: i64,
    sell_fee: i64,
}
struct Engine {
    orders: Vec<Order>,
    ids: HashMap<String, usize>,
    traders: BTreeMap<String, Trader>,
    book: Vec<usize>,
    pending: Vec<usize>,
    trades: Vec<Trade>,
    output: Vec<String>,
    maker: i64,
    taker: i64,
    band: i64,
    tick: i64,
    lot: i64,
    priority: i64,
    halted: bool,
}
impl Engine {
    fn new() -> Self {
        Self {
            orders: vec![], ids: HashMap::new(), traders: BTreeMap::new(), book: vec![], pending: vec![], trades: vec![], output: vec![], maker: 0, taker: 0, band: 0, tick: 1, lot: 1, priority: 0, halted: false
        }
    }
    fn mark(&self) -> i64 {
        self.trades.last().map_or(0, |t| t.price)
    }
    fn order(&self, id: &str) -> Result<usize, String> {
        self.ids.get(id).copied().ok_or("unknown order".into())
    }
    fn trader(&self, name: &str) -> Result<&Trader, String> {
        self.traders.get(name).ok_or("unknown trader".into())
    }
    fn active(&self, name: &str) -> Vec<usize> {
        self.orders.iter().enumerate().filter(|(_, o)| o.trader == name && o.active()).map(|(i, _)| i).collect()
    }
    fn exposure(&self, name: &str, side: &str, exclude: Option<usize>) -> i64 {
        (if side == "BUY" {
            self.traders[name].net()
        } else {
            -self.traders[name].net()
        }
        ) + self.active(name).into_iter().filter(|&i| Some(i) != exclude && self.orders[i].side == side).map(|i| self.orders[i].remaining).sum::<i64>()
    }
    fn risk(&self, name: &str, side: &str, q: i64, exclude: Option<usize>) -> Result<(), String> {
        if let Some(m) = self.traders.get(name).and_then(|t| t.limit) {
            check(self.exposure(name, side, exclude) + q <= m, "risk limit")?;
        }
        Ok(())
    }
    fn band(&self, p: i64) -> Result<(), String> {
        check(self.band == 0 || self.trades.is_empty() || (p - self.mark()).abs() <= self.band, "outside band")
    }
    fn sorted(&self, side: &str) -> Vec<usize> {
        let mut v: Vec<usize> = self.book.iter().copied().filter(|&i| self.orders[i].side == side).collect();
        v.sort_by_key(|&i| {
            let o = &self.orders[i];
            (if side == "BUY" {
                -o.price.unwrap()
            } else {
                o.price.unwrap()
            }, o.priority)
        });
        v
    }
    fn levels(&self, side: &str) -> Vec<(i64, i64, usize)> {
        let mut v: Vec<(i64, i64, usize)> = vec![];
        for i in self.sorted(side) {
            let o = &self.orders[i];
            let p = o.price.unwrap();
            if v.last().is_none_or(|l| l.0 != p) {
                v.push((p, 0, 0));
            }
            let l = v.last_mut().unwrap();
            l.1 += o.visible;
            l.2 += 1;
        }
        v
    }
    fn trade_line(&self, t: &Trade) -> String {
        let b = &self.orders[t.buy];
        let s = &self.orders[t.sell];
        format!("TRADE {} {} {} {} {} {} {}", t.number, t.price, t.quantity, b.id, b.trader, s.id, s.trader)
    }
    fn match_order(&mut self, x: usize) {
        while self.orders[x].remaining > 0 {
            let Some(y) = self.sorted(opposite(&self.orders[x].side)).first().copied() else {
                break;
            };
            let p = self.orders[y].price.unwrap();
            if !self.orders[x].matches(p) {
                break;
            }
            if self.orders[x].trader == self.orders[y].trader {
                let o = &mut self.orders[y];
                self.output.push(format!("STP {} {}", o.id, o.remaining));
                o.history.push(format!("STP {}", o.remaining));
                o.remaining = 0;
                o.status = "CANCELLED".into();
                self.book.retain(|&i| i != y);
                continue;
            }
            let q = self.orders[x].remaining.min(self.orders[y].visible);
            let (buy, sell) = if self.orders[x].side == "BUY" {
                (x, y)
            } else {
                (y, x)
            };
            let bf = q * if buy == x {
                self.taker
            } else {
                self.maker
            };
            let sf = q * if sell == x {
                self.taker
            } else {
                self.maker
            };
            let t = Trade {
                number: self.trades.len() + 1, price: p, quantity: q, buy, sell, taker: x, buy_fee: bf, sell_fee: sf
            };
            self.orders[x].fill(t.number, p, q);
            self.orders[y].fill(t.number, p, q);
            self.orders[y].visible -= q;
            let b = self.traders.get_mut(&self.orders[buy].trader).unwrap();
            b.bought += q;
            b.cash -= p * q + bf;
            b.fees += bf;
            let s = self.traders.get_mut(&self.orders[sell].trader).unwrap();
            s.sold += q;
            s.cash += p * q - sf;
            s.fees += sf;
            self.output.push(self.trade_line(&t));
            self.trades.push(t);
            let o = &mut self.orders[y];
            if o.remaining == 0 {
                self.book.retain(|&i| i != y);
                o.status = "FILLED".into();
            } else {
                o.status = "PARTIAL".into();
                if o.visible == 0 {
                    self.priority += 1;
                    o.priority = self.priority;
                    o.visible = o.peak.unwrap().min(o.remaining);
                    o.history.push(format!("REFRESH {} {}", o.visible, o.remaining - o.visible));
                    self.output.push(format!("REFRESH {} {} {}", o.id, o.visible, o.remaining - o.visible));
                }
            }
        }
    }
    fn post(&mut self, i: usize, force_rest: bool) {
        let o = &mut self.orders[i];
        if o.remaining == 0 {
            o.status = "FILLED".into();
        } else if force_rest || matches!(o.kind.as_str(), "ICEBERG" | "STOPLIMIT") || o.kind == "LIMIT" && o.condition != "IOC" {
            self.priority += 1;
            o.priority = self.priority;
            o.visible = o.peak.unwrap_or(o.remaining).min(o.remaining);
            o.status = if o.filled == 0 {
                "OPEN"
            } else {
                "PARTIAL"
            }
            .into();
            self.book.push(i);
            o.history.push(format!("REST {} {}", o.price.unwrap(), o.visible));
        } else {
            o.history.push(format!("EXPIRE {}", o.remaining));
            o.remaining = 0;
            o.status = "CANCELLED".into();
        }
        self.output.push(o.line());
    }
    fn trigger(&mut self) {
        while !self.trades.is_empty() {
            let selected: Vec<usize> = self.pending.iter().copied().filter(|&i| self.orders[i].triggered(self.mark())).collect();
            if selected.is_empty() {
                break;
            }
            self.pending.retain(|i| !selected.contains(i));
            for i in selected {
                self.output.push(format!("TRIGGER {}", self.orders[i].id));
                self.orders[i].history.push("TRIGGER".into());
                self.match_order(i);
                self.post(i, false);
            }
        }
    }
    fn cancel(&mut self, i: usize) {
        self.book.retain(|&j| i != j);
        self.pending.retain(|&j| i != j);
        let o = &mut self.orders[i];
        o.history.push(format!("CANCEL {}", o.remaining));
        o.remaining = 0;
        o.status = "CANCELLED".into();
        self.output.push(o.line());
    }
    fn bar(&self, ts: &[Trade]) -> String {
        format!("open {} high {} low {} close {} volume {}", ts[0].price, ts.iter().map(|t| t.price).max().unwrap(), ts.iter().map(|t| t.price).min().unwrap(), ts.last().unwrap().price, ts.iter().map(|t| t.quantity).sum::<i64>())
    }
    fn command(&mut self, w: &[&str]) -> Result<(), String> {
        let c = w[0];
        let num = |i: usize| w[i].parse::<i64>().unwrap();
        if matches!(c, "LIMIT" | "MARKET" | "STOP" | "STOPLIMIT" | "ICEBERG") {
            let q = num(if c == "MARKET" {
                4
            } else if c == "STOPLIMIT" {
                6
            } else {
                5
            });
            let mut o = Order {
                id: w[1].into(), trader: w[2].into(), kind: c.into(), side: w[3].into(), condition: if c == "LIMIT" && w.len() == 7 {
                    w[6].into()
                } else {
                    String::new()
                }, status: "OPEN".into(), price: None, trigger: None, peak: None, quantity: q, remaining: q, visible: 0, filled: 0, value: 0, priority: 0, history: vec!["ACCEPT".into()]
            };
            if matches!(c, "LIMIT" | "ICEBERG") {
                o.price = Some(num(4));
            }
            if matches!(c, "STOP" | "STOPLIMIT") {
                o.trigger = Some(num(4));
            }
            if c == "STOPLIMIT" {
                o.price = Some(num(5));
            }
            if c == "ICEBERG" {
                o.peak = Some(num(6));
            }
            let prices: Vec<i64> = [o.price, o.trigger].into_iter().flatten().collect();
            check(!self.halted, "halted")?;
            check(!self.ids.contains_key(&o.id), "duplicate id")?;
            check(prices.iter().all(|&p| p > 0), "invalid price")?;
            check(q > 0, "invalid quantity")?;
            check(prices.iter().all(|p| p % self.tick == 0), "invalid tick")?;
            check(q % self.lot == 0, "invalid lot")?;
            if let Some(k) = o.peak {
                check(k > 0 && k <= q && k % self.lot == 0, "invalid peak")?;
            }
            if o.trigger.is_some() {
                check(self.trades.is_empty() || !o.triggered(self.mark()), "invalid trigger")?;
            }
            if let Some(p) = o.price {
                self.band(p)?;
            }
            self.risk(&o.trader, &o.side, q, None)?;
            let opposite = self.sorted(opposite(&o.side));
            if o.condition == "POSTONLY" {
                check(opposite.first().is_none_or(|&i| !o.matches(self.orders[i].price.unwrap())), "would cross")?;
            }
            if o.condition == "FOK" {
                check(opposite.iter().filter(|&&i| self.orders[i].trader != o.trader && o.matches(self.orders[i].price.unwrap())).map(|&i| self.orders[i].remaining).sum::<i64>() >= q, "unfillable")?;
            }
            let i = self.orders.len();
            self.traders.entry(o.trader.clone()).or_default();
            self.ids.insert(o.id.clone(), i);
            self.orders.push(o);
            if self.orders[i].trigger.is_some() {
                self.orders[i].status = "PENDING".into();
                self.pending.push(i);
                self.output.push(self.orders[i].line());
            } else {
                if self.orders[i].condition != "POSTONLY" {
                    self.match_order(i);
                }
                self.post(i, false);
                self.trigger();
            }
            return Ok(());
        }
        match c {
            "CANCEL" => {
                let i = self.order(w[1])?;
                check(self.orders[i].active(), "not open")?;
                self.cancel(i);
            }
            "REPLACE" => {
                check(!self.halted, "halted")?;
                let i = self.order(w[1])?;
                let o = &self.orders[i];
                check(o.resting(), "not open")?;
                let p = num(2);
                let q = num(3);
                let moved = Some(p) != o.price;
                check(p > 0, "invalid price")?;
                check(q > 0, "invalid quantity")?;
                check(!moved || p % self.tick == 0, "invalid tick")?;
                check(q % self.lot == 0, "invalid lot")?;
                check(moved || q != o.remaining, "no change")?;
                if moved {
                    self.band(p)?;
                }
                if q > o.remaining {
                    self.risk(&o.trader, &o.side, q, Some(i))?;
                }
                let kept = !moved && q < o.remaining;
                let o = &mut self.orders[i];
                o.quantity = o.filled + q;
                o.remaining = q;
                if kept {
                    o.visible = o.visible.min(q);
                    o.history.push(format!("REPLACE {} {} kept", p, q));
                    self.output.push(format!("REPLACE {} kept", o.id));
                    self.output.push(o.line());
                } else {
                    o.price = Some(p);
                    o.history.push(format!("REPLACE {} {} lost", p, q));
                    self.output.push(format!("REPLACE {} lost", o.id));
                    self.book.retain(|&j| j != i);
                    self.match_order(i);
                    self.post(i, true);
                    self.trigger();
                }
            }
            "CANCELALL" => {
                self.trader(w[1])?;
                let v = self.active(w[1]);
                self.output.push(format!("CANCELALL {} {}", w[1], v.len()));
                for i in v {
                    self.cancel(i);
                }
            }
            "HALT" => {
                check(!self.halted, "already halted")?;
                self.halted = true;
                self.output.push(c.into());
            }
            "RESUME" => {
                check(self.halted, "not halted")?;
                self.halted = false;
                self.output.push(c.into());
            }
            "RISK" => {
                self.traders.entry(w[1].into()).or_default().limit = Some(num(2));
                self.output.push(format!("RISK {} {} exposure buy {} sell {}", w[1], num(2), self.exposure(w[1], "BUY", None), self.exposure(w[1], "SELL", None)));
            }
            "FEE" => {
                check(num(1) + num(2) >= 0, "invalid fee")?;
                self.maker = num(1);
                self.taker = num(2);
                self.output.push(format!("FEE maker {} taker {}", self.maker, self.taker));
            }
            "BAND" => {
                self.band = num(1);
                self.output.push(format!("BAND {}", self.band));
            }
            "TICK" | "LOT" => {
                check(num(1) > 0, "invalid size")?;
                if c == "TICK" {
                    self.tick = num(1);
                } else {
                    self.lot = num(1);
                }
                self.output.push(format!("{} {}", c, num(1)));
            }
            "BOOK" => {
                check(num(1) > 0, "invalid depth")?;
                let n = num(1) as usize;
                let bids = self.levels("BUY");
                let asks = self.levels("SELL");
                self.output.push(format!("BOOK bids {} asks {}", bids.len(), asks.len()));
                for &(p, q, k) in asks.iter().take(n).collect::<Vec<_>>().into_iter().rev() {
                    self.output.push(format!("ASK {} {} {}", p, q, k));
                }
                for (p, q, k) in bids.into_iter().take(n) {
                    self.output.push(format!("BID {} {} {}", p, q, k));
                }
            }
            "ORDERS" => {
                self.trader(w[1])?;
                let v = self.active(w[1]);
                self.output.push(format!("ORDERS {} {}", w[1], v.len()));
                for i in v {
                    self.output.push(self.orders[i].details());
                }
            }
            "STATUS" => {
                let i = self.order(w[1])?;
                self.output.push(format!("STATUS {}", self.orders[i].details()));
            }
            "HISTORY" => {
                let i = self.order(w[1])?;
                let o = &self.orders[i];
                self.output.push(format!("HISTORY {} {}", o.id, o.history.len()));
                self.output.extend(o.history.clone());
            }
            "POSITION" => {
                let s = self.trader(w[1])?.position(w[1], self.mark());
                self.output.push(s);
            }
            "FILLS" => {
                self.trader(w[1])?;
                let ts: Vec<Trade> = self.trades.iter().filter(|t| self.orders[t.buy].trader == w[1] || self.orders[t.sell].trader == w[1]).cloned().collect();
                self.output.push(format!("FILLS {} {}", w[1], ts.len()));
                let mut net = 0;
                for t in ts {
                    let buy = self.orders[t.buy].trader == w[1];
                    let i = if buy {
                        t.buy
                    } else {
                        t.sell
                    };
                    net += if buy {
                        t.quantity
                    } else {
                        -t.quantity
                    };
                    self.output.push(format!("{} {} {} {} {} {} fee {} net {}", t.number, if buy {
                        "BUY"
                    } else {
                        "SELL"
                    }, t.price, t.quantity, self.orders[i].id, if t.taker == i {
                        "TAKER"
                    } else {
                        "MAKER"
                    }, if buy {
                        t.buy_fee
                    } else {
                        t.sell_fee
                    }, net));
                }
            }
            "LAST" => self.output.push(self.trades.last().map_or("LAST none".into(), |t| format!("LAST {} {}", t.price, t.quantity))),
            "VWAP" => {
                let v: i64 = self.trades.iter().map(|t| t.quantity).sum();
                let a: i64 = self.trades.iter().map(|t| t.quantity * t.price).sum();
                self.output.push(if v == 0 {
                    "VWAP none".into()
                } else {
                    format!("VWAP {} volume {} trades {}", decimal(a * 100 / v), v, self.trades.len())
                });
            }
            "SPREAD" => {
                let b = self.sorted("BUY").first().map(|&i| self.orders[i].price.unwrap());
                let a = self.sorted("SELL").first().map(|&i| self.orders[i].price.unwrap());
                let mut s = format!("SPREAD bid {} ask {}", b.map_or("none".into(), |p| p.to_string()), a.map_or("none".into(), |p| p.to_string()));
                if let (Some(b), Some(a)) = (b, a) {
                    s += &format!(" spread {} mid {}.{}", a - b, (a + b) / 2, if (a + b) % 2 == 0 {
                        0
                    } else {
                        5
                    });
                }
                self.output.push(s);
            }
            "IMPACT" => {
                let q = num(2);
                check(q > 0, "invalid quantity")?;
                let ls = self.levels(opposite(w[1]));
                let (mut rem, mut cost, mut worst, mut used) = (q, 0, 0, 0);
                for &(p, v, _) in &ls {
                    if rem == 0 {
                        break;
                    }
                    let u = rem.min(v);
                    rem -= u;
                    cost += u * p;
                    worst = p;
                    used += 1;
                }
                self.output.push(if rem > 0 {
                    format!("IMPACT {} {} insufficient {}", w[1], q, ls.iter().map(|l| l.1).sum::<i64>())
                } else {
                    format!("IMPACT {} {} avg {} worst {} levels {}", w[1], q, decimal(cost * 100 / q), worst, used)
                });
            }
            "TRADES" => {
                check(num(1) > 0, "invalid count")?;
                let n = (num(1) as usize).min(self.trades.len());
                self.output.push(format!("TRADES {} of {}", n, self.trades.len()));
                for t in &self.trades[self.trades.len()-n..] {
                    self.output.push(self.trade_line(t));
                }
            }
            "BARS" => {
                check(num(1) > 0, "invalid count")?;
                let k = num(1) as usize;
                self.output.push(format!("BARS {}", self.trades.len().div_ceil(k)));
                for (i, ts) in self.trades.chunks(k).enumerate() {
                    self.output.push(format!("{} {}", i + 1, self.bar(ts)));
                }
            }
            "RANK" => {
                let mut names: Vec<String> = self.traders.keys().cloned().collect();
                names.sort_by_key(|n| (-self.traders[n].pnl(self.mark()), -self.traders[n].volume(), n.clone()));
                self.output.push(format!("RANK {}", names.len()));
                for (i, n) in names.iter().enumerate() {
                    self.output.push(format!("{} {} pnl {} volume {}", i + 1, n, self.traders[n].pnl(self.mark()), self.traders[n].volume()));
                }
            }
            "FLOW" => {
                let b: i64 = self.trades.iter().filter(|t| t.taker == t.buy).map(|t| t.quantity).sum();
                let s: i64 = self.trades.iter().filter(|t| t.taker == t.sell).map(|t| t.quantity).sum();
                self.output.push(format!("FLOW buy {} sell {} net {}", b, s, b - s));
            }
            "SUMMARY" => {
                self.output.push(if self.trades.is_empty() {
                    "SUMMARY trades 0".into()
                } else {
                    format!("SUMMARY trades {} volume {} open {} high {} low {} close {} fees {}", self.trades.len(), self.trades.iter().map(|t| t.quantity).sum::<i64>(), self.trades[0].price, self.trades.iter().map(|t| t.price).max().unwrap(), self.trades.iter().map(|t| t.price).min().unwrap(), self.mark(), self.trades.iter().map(|t| t.buy_fee + t.sell_fee).sum::<i64>())
                });
                for (n, t) in &self.traders {
                    self.output.push(t.position(n, self.mark()));
                }
            }
            _ => unreachable!(),
        }
        Ok(())
    }
}
fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut lines = input.lines();
    let n: usize = lines.next().unwrap().parse().unwrap();
    let mut e = Engine::new();
    for line in lines.take(n) {
        let w: Vec<&str> = line.split(' ').collect();
        if let Err(reason) = e.command(&w) {
            let prefix = if matches!(w[0], "LIMIT" | "MARKET" | "STOP" | "STOPLIMIT" | "ICEBERG" | "CANCEL" | "REPLACE") {
                format!("REJECT {} ", w[1])
            } else {
                "ERROR ".into()
            };
            e.output.push(prefix + &reason);
        }
    }
    println!("{}", e.output.join("\n"));
}
