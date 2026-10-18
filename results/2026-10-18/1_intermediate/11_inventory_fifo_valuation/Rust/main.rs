use std::collections::BTreeMap;
use std::io::{self, Read};

const CATEGORIES: [&str; 8] = [
    "received", "returned", "adjusted-in", "adjusted-out",
    "shipped", "written-down", "expired", "recalled",
];

fn number(text: &str) -> i64 {
    text.parse().unwrap()
}

fn cents(text: &str) -> i64 {
    text.replace('.', "").parse().unwrap()
}

fn money(mut amount: i64) -> String {
    let sign = if amount < 0 {
        amount = -amount;
        "-"
    } else {
        ""
    };
    format!("{sign}{}.{:02}", amount / 100, amount % 100)
}

fn signed_quantity(value: i64) -> String {
    format!("{}{value}", if value > 0 { "+" } else { "" })
}

fn signed_money(value: i64) -> String {
    format!("{}{}", if value > 0 { "+" } else { "" }, money(value))
}

fn margin(profit: i64, revenue: i64) -> String {
    if revenue == 0 {
        return "n/a".into();
    }
    let tenths = profit.abs() * 1000 / revenue;
    format!("{}{}.{:01}%",
        if profit < 0 && tenths > 0 { "-" } else { "" },
        tenths / 10, tenths % 10)
}

macro_rules! line {
    ($inv:expr, $indent:expr, $($part:expr),+ $(,)?) => {{
        let parts = [$($part.to_string(),)+];
        $inv.output.push(format!("{}{}", " ".repeat($indent), parts.join(" ")));
    }};
}

#[derive(Clone)]
struct CardEntry {
    day: i64,
    kind: String,
    warehouse: String,
    quantity: i64,
    value: i64,
}

struct Item {
    code: String,
    name: String,
    level: i64,
    last_cost: Option<i64>,
    card: Vec<CardEntry>,
}

struct Lot {
    number: usize,
    item: String,
    warehouse: String,
    kind: String,
    day: i64,
    initial_quantity: i64,
    initial_cost: i64,
    removed: i64,
}

struct StockLot {
    quantity: i64,
    cost: i64,
}

#[derive(Clone)]
struct Part {
    lot: usize,
    quantity: i64,
    cost: i64,
}

struct Order {
    number: usize,
    warehouse: String,
    item: String,
    day: i64,
    price: i64,
    ordered: i64,
    shipped: i64,
    backorder: i64,
    cancelled: i64,
    returned: i64,
    revenue: i64,
    cogs: i64,
    issues: Vec<Part>,
}

#[derive(Default)]
struct Total {
    quantity: i64,
    value: i64,
}

#[derive(Default)]
struct Sale {
    quantity: i64,
    revenue: i64,
    cogs: i64,
}

struct Inventory {
    day: i64,
    stock: BTreeMap<String, BTreeMap<String, BTreeMap<usize, StockLot>>>,
    items: BTreeMap<String, Item>,
    lots: Vec<Lot>,
    orders: Vec<Order>,
    totals: BTreeMap<&'static str, Total>,
    output: Vec<String>,
}

impl Inventory {
    fn new() -> Self {
        let totals = CATEGORIES.iter().map(|&name| (name, Total::default())).collect();
        Self {
            day: 1,
            stock: BTreeMap::new(),
            items: BTreeMap::new(),
            lots: Vec::new(),
            orders: Vec::new(),
            totals,
            output: Vec::new(),
        }
    }

    fn warehouse(&self, code: &str) -> Result<(), String> {
        if self.stock.contains_key(code) {
            Ok(())
        } else {
            Err(format!("unknown warehouse {code}"))
        }
    }

    fn item(&self, code: &str) -> Result<(), String> {
        if self.items.contains_key(code) {
            Ok(())
        } else {
            Err(format!("unknown item {code}"))
        }
    }

    fn pair(&self, warehouse: &str, code: &str) -> Result<(), String> {
        self.warehouse(warehouse)?;
        self.item(code)
    }

    fn order_index(&self, text: &str) -> Result<usize, String> {
        let id = number(text);
        if id < 1 || id > self.orders.len() as i64 {
            Err(format!("unknown order {text}"))
        } else {
            Ok(id as usize - 1)
        }
    }

    fn lot_index(&self, text: &str) -> Result<usize, String> {
        let id = number(text);
        if id < 1 || id > self.lots.len() as i64 {
            Err(format!("unknown lot {text}"))
        } else {
            Ok(id as usize - 1)
        }
    }

    fn stock_lots(&self, w: &str, code: &str) -> Option<&BTreeMap<usize, StockLot>> {
        self.stock.get(w).and_then(|items| items.get(code))
    }

    fn fifo(&self, w: &str, code: &str) -> Vec<usize> {
        let mut ids = self.stock_lots(w, code)
            .map(|stocks| stocks.keys().copied().collect::<Vec<_>>())
            .unwrap_or_default();
        ids.sort_by_key(|&id| (self.lots[id - 1].day, id));
        ids
    }

    fn quantity(&self, w: &str, code: &str) -> i64 {
        self.stock_lots(w, code)
            .map(|stocks| stocks.values().map(|s| s.quantity).sum())
            .unwrap_or(0)
    }

    fn total_quantity(&self, code: &str) -> i64 {
        self.stock.keys().map(|w| self.quantity(w, code)).sum()
    }

    fn backorder(&self, code: &str) -> i64 {
        self.orders.iter().filter(|o| o.item == code).map(|o| o.backorder).sum()
    }

    fn all_stocks(&self) -> Total {
        let mut result = Total::default();
        for items in self.stock.values() {
            for lots in items.values() {
                for stock in lots.values() {
                    result.quantity += stock.quantity;
                    result.value += stock.quantity * stock.cost;
                }
            }
        }
        result
    }

    fn require_stock(&self, w: &str, code: &str, q: i64) -> Result<(), String> {
        let held = self.quantity(w, code);
        if held < q {
            Err(format!("insufficient stock {w} {code} {held}"))
        } else {
            Ok(())
        }
    }

    fn card_entry(&mut self, code: &str, kind: &str, w: &str, q: i64, value: i64) {
        self.items.get_mut(code).unwrap().card.push(CardEntry {
            day: self.day,
            kind: kind.into(),
            warehouse: w.into(),
            quantity: q,
            value,
        });
    }

    fn accumulate(&mut self, category: &'static str, q: i64, value: i64) {
        let total = self.totals.get_mut(category).unwrap();
        total.quantity += q;
        total.value += value;
    }

    fn add_stock(&mut self, w: &str, id: usize, q: i64, cost: i64) {
        let code = self.lots[id - 1].item.clone();
        let stocks = self.stock.get_mut(w).unwrap().entry(code).or_default();
        if let Some(stock) = stocks.get_mut(&id) {
            stock.quantity += q;
        } else {
            stocks.insert(id, StockLot { quantity: q, cost });
        }
    }

    fn create_lot(&mut self, w: &str, code: &str,
                  day: i64, q: i64, cost: i64, kind: &str) -> usize {
        let id = self.lots.len() + 1;
        self.lots.push(Lot {
            number: id,
            item: code.into(),
            warehouse: w.into(),
            kind: kind.into(),
            day,
            initial_quantity: q,
            initial_cost: cost,
            removed: 0,
        });
        self.add_stock(w, id, q, cost);
        id
    }

    fn issue(&mut self, w: &str, code: &str, mut q: i64) -> (Vec<Part>, i64) {
        let mut parts = Vec::new();
        let mut cost = 0;
        for id in self.fifo(w, code) {
            if q == 0 {
                break;
            }
            let stocks = self.stock.get_mut(w).unwrap().get_mut(code).unwrap();
            let current = stocks.get_mut(&id).unwrap();
            let taken = q.min(current.quantity);
            parts.push(Part { lot: id, quantity: taken, cost: current.cost });
            cost += taken * current.cost;
            current.quantity -= taken;
            q -= taken;
            if current.quantity == 0 {
                stocks.remove(&id);
            }
        }
        (parts, cost)
    }

    fn fulfil(&mut self, index: usize, q: i64, kind: &str) -> i64 {
        if q == 0 {
            return 0;
        }
        let (w, code, price) = {
            let order = &self.orders[index];
            (order.warehouse.clone(), order.item.clone(), order.price)
        };
        let (parts, cost) = self.issue(&w, &code, q);
        {
            let order = &mut self.orders[index];
            order.shipped += q;
            order.backorder -= q;
            order.revenue += q * price;
            order.cogs += cost;
            order.issues.extend(parts);
        }
        self.accumulate("shipped", q, cost);
        self.card_entry(&code, kind, &w, -q, -cost);
        cost
    }

    fn allocate(&mut self, w: &str, code: &str) {
        let mut available = self.quantity(w, code);
        for index in 0..self.orders.len() {
            if available == 0 {
                break;
            }
            let current = &self.orders[index];
            if current.warehouse != w || current.item != code || current.backorder == 0 {
                continue;
            }
            let q = available.min(current.backorder);
            let revenue = q * current.price;
            let cost = self.fulfil(index, q, "fill");
            available -= q;
            line!(self, 2, "FILL", "order", self.orders[index].number, "qty", q,
                  "revenue", money(revenue), "cogs", money(cost),
                  "profit", money(revenue - cost), "backorder", self.orders[index].backorder);
        }
    }

    fn remove_parts(&mut self, parts: &[Part]) {
        for part in parts {
            self.lots[part.lot - 1].removed += part.quantity;
        }
    }

    fn sales(&self) -> BTreeMap<String, Sale> {
        let mut rows = BTreeMap::<String, Sale>::new();
        for order in &self.orders {
            let row = rows.entry(order.item.clone()).or_default();
            row.quantity += order.shipped - order.returned;
            row.revenue += order.revenue;
            row.cogs += order.cogs;
        }
        rows
    }

    fn margin_line(&mut self, label: &str, row: &Sale) {
        let profit = row.revenue - row.cogs;
        line!(self, 2, label, "sold", row.quantity, "revenue", money(row.revenue),
              "cogs", money(row.cogs), "profit", money(profit),
              "margin", margin(profit, row.revenue));
    }

    fn aging_line(&mut self, label: &str, buckets: &[i64; 4], monetary: bool) {
        let labels = ["0-30", "31-60", "61-90", "91+"];
        let mut text = label.to_string();
        for i in 0..4 {
            let value = if monetary { money(buckets[i]) } else { buckets[i].to_string() };
            text.push_str(&format!(" {} {}", labels[i], value));
        }
        line!(self, 2, text);
    }

    fn command(&mut self, cmd: &str, a: &[&str]) -> Result<(), String> {
        match cmd {
            "DAY" => {
                let day = number(a[0]);
                if day <= self.day {
                    return Err(format!("invalid day {}", a[0]));
                }
                self.day = day;
                line!(self, 0, "DAY", day);
            }
            "WAREHOUSE" => {
                let w = a[0];
                if self.stock.contains_key(w) {
                    return Err(format!("duplicate warehouse {w}"));
                }
                self.stock.insert(w.into(), BTreeMap::new());
                line!(self, 0, "WAREHOUSE", w);
            }
            "ITEM" => {
                let (code, level, name) = (a[0], number(a[1]), a[2]);
                let action;
                if let Some(entry) = self.items.get_mut(code) {
                    entry.level = level;
                    entry.name = name.into();
                    action = "updated";
                } else {
                    self.items.insert(code.into(), Item {
                        code: code.into(),
                        name: name.into(),
                        level,
                        last_cost: None,
                        card: Vec::new(),
                    });
                    action = "added";
                }
                line!(self, 0, "ITEM", code, action, name, "level", level);
            }
            "RECEIVE" => {
                let (w, code) = (a[0], a[1]);
                self.pair(w, code)?;
                let (q, cost, day) = (number(a[2]), cents(a[3]), number(a[4]));
                if q == 0 {
                    return Err("invalid quantity".into());
                }
                if day > self.day {
                    return Err(format!("future day {}", a[4]));
                }
                let id = self.create_lot(w, code, day, q, cost, "receive");
                self.items.get_mut(code).unwrap().last_cost = Some(cost);
                self.accumulate("received", q, q * cost);
                self.card_entry(code, "receive", w, q, q * cost);
                line!(self, 0, "RECEIVE", w, code, "lot", id, "qty", q, "cost",
                      money(cost), "day", day, "value", money(q * cost));
                self.allocate(w, code);
            }
            "SHIP" => {
                let (w, code) = (a[0], a[1]);
                self.pair(w, code)?;
                let q = number(a[2]);
                if q == 0 {
                    return Err("invalid quantity".into());
                }
                let id = self.orders.len() + 1;
                self.orders.push(Order {
                    number: id,
                    warehouse: w.into(),
                    item: code.into(),
                    day: self.day,
                    price: cents(a[3]),
                    ordered: q,
                    shipped: 0,
                    backorder: q,
                    cancelled: 0,
                    returned: 0,
                    revenue: 0,
                    cogs: 0,
                    issues: Vec::new(),
                });
                let shipped = q.min(self.quantity(w, code));
                let cost = self.fulfil(id - 1, shipped, "ship");
                let current = &self.orders[id - 1];
                line!(self, 0, "SHIP", "order", id, w, code, "shipped", shipped,
                      "revenue", money(current.revenue), "cogs", money(cost),
                      "profit", money(current.revenue - cost), "backorder", current.backorder);
            }
            "CANCEL" => {
                let index = self.order_index(a[0])?;
                let current = &mut self.orders[index];
                if current.backorder == 0 {
                    return Err(format!("no backorder {}", a[0]));
                }
                current.cancelled += current.backorder;
                current.backorder = 0;
                line!(self, 0, "CANCEL", "order", current.number, "qty", current.cancelled);
            }
            "TRANSFER" => {
                let (source, destination, code) = (a[0], a[1], a[2]);
                self.warehouse(source)?;
                self.warehouse(destination)?;
                if source == destination {
                    return Err(format!("same warehouse {source}"));
                }
                self.item(code)?;
                let q = number(a[3]);
                if q == 0 {
                    return Err("invalid quantity".into());
                }
                self.require_stock(source, code, q)?;
                let (parts, cost) = self.issue(source, code, q);
                for part in &parts {
                    self.add_stock(destination, part.lot, part.quantity, part.cost);
                }
                self.card_entry(code, "transfer-out", source, -q, -cost);
                self.card_entry(code, "transfer-in", destination, q, cost);
                line!(self, 0, "TRANSFER", source, "->", destination, code,
                      "qty", q, "value", money(cost), "lots", parts.len());
                self.allocate(destination, code);
            }
            "ADJUST" => {
                let (w, code, change) = (a[0], a[1], a[2]);
                self.pair(w, code)?;
                let q = number(&change[1..]);
                if q == 0 {
                    return Err("invalid quantity".into());
                }
                if change.starts_with('+') {
                    let cost = cents(a[3]);
                    let id = self.create_lot(w, code, self.day, q, cost, "adjust");
                    self.accumulate("adjusted-in", q, q * cost);
                    self.card_entry(code, "adjust", w, q, q * cost);
                    line!(self, 0, "ADJUST", w, code, format!("+{q}"),
                          "lot", id, "value", money(q * cost));
                    self.allocate(w, code);
                } else {
                    self.require_stock(w, code, q)?;
                    let (parts, cost) = self.issue(w, code, q);
                    self.remove_parts(&parts);
                    self.accumulate("adjusted-out", q, cost);
                    self.card_entry(code, "adjust", w, -q, -cost);
                    line!(self, 0, "ADJUST", w, code, format!("-{q}"), "value", money(cost));
                }
            }
            "RETURN" => {
                let index = self.order_index(a[0])?;
                let (q, cost) = (number(a[1]), cents(a[2]));
                if q == 0 {
                    return Err("invalid quantity".into());
                }
                let current = &self.orders[index];
                let available = current.shipped - current.returned;
                if q > available {
                    return Err(format!("return exceeds shipped {} {available}", a[0]));
                }
                let (w, code, price, id) = (
                    current.warehouse.clone(), current.item.clone(),
                    current.price, current.number,
                );
                let lot = self.create_lot(&w, &code, self.day, q, cost, "return");
                let refund = q * price;
                {
                    let order = &mut self.orders[index];
                    order.returned += q;
                    order.revenue -= refund;
                    order.cogs -= q * cost;
                }
                self.accumulate("returned", q, q * cost);
                self.card_entry(&code, "return", &w, q, q * cost);
                line!(self, 0, "RETURN", "order", id, &w, &code, "qty", q,
                      "lot", lot, "refund", money(refund), "value", money(q * cost));
                self.allocate(&w, &code);
            }
            "COUNT" => {
                let (w, code) = (a[0], a[1]);
                self.pair(w, code)?;
                let (actual, held) = (number(a[2]), self.quantity(w, code));
                if actual == held {
                    line!(self, 0, "COUNT", w, code, "qty", actual, "ok");
                } else if actual < held {
                    let q = held - actual;
                    let (parts, cost) = self.issue(w, code, q);
                    self.remove_parts(&parts);
                    self.accumulate("adjusted-out", q, cost);
                    self.card_entry(code, "count", w, -q, -cost);
                    line!(self, 0, "COUNT", w, code, "qty", held, "->", actual,
                          "shortage", q, "value", money(cost));
                } else {
                    let q = actual - held;
                    let cost = self.items[code].last_cost.unwrap_or(0);
                    let lot = self.create_lot(w, code, self.day, q, cost, "count");
                    self.accumulate("adjusted-in", q, q * cost);
                    self.card_entry(code, "count", w, q, q * cost);
                    line!(self, 0, "COUNT", w, code, "qty", held, "->", actual,
                          "surplus", q, "lot", lot, "value", money(q * cost));
                    self.allocate(w, code);
                }
            }
            "MARKET" => {
                let code = a[0];
                self.item(code)?;
                let price = cents(a[1]);
                let mut changed = 0;
                let mut q = 0;
                let mut loss = 0;
                let warehouses: Vec<String> = self.stock.keys().cloned().collect();
                for w in warehouses {
                    let mut warehouse_loss = 0;
                    if let Some(stocks) = self.stock.get_mut(&w).and_then(|v| v.get_mut(code)) {
                        for stock in stocks.values_mut() {
                            if stock.cost > price {
                                warehouse_loss += stock.quantity * (stock.cost - price);
                                changed += 1;
                                q += stock.quantity;
                                stock.cost = price;
                            }
                        }
                    }
                    if warehouse_loss > 0 {
                        self.card_entry(code, "writedown", &w, 0, -warehouse_loss);
                    }
                    loss += warehouse_loss;
                }
                self.accumulate("written-down", q, loss);
                line!(self, 0, "MARKET", code, "price", money(price),
                      "lots", changed, "qty", q, "loss", money(loss));
            }
            "RECALL" => {
                let index = self.lot_index(a[0])?;
                let (id, code) = (self.lots[index].number, self.lots[index].item.clone());
                let mut held = Vec::<(String, i64, i64)>::new();
                for w in self.stock.keys() {
                    if let Some(stock) = self.stock_lots(w, &code).and_then(|s| s.get(&id)) {
                        held.push((w.clone(), stock.quantity, stock.cost));
                    }
                }
                if held.is_empty() {
                    return Err(format!("nothing to recall {}", a[0]));
                }
                let mut q = 0;
                let mut value = 0;
                for (w, quantity, cost) in &held {
                    q += quantity;
                    value += quantity * cost;
                    self.stock.get_mut(w).unwrap().get_mut(&code).unwrap().remove(&id);
                    self.card_entry(&code, "recall", w, -*quantity, -(quantity * cost));
                }
                self.lots[index].removed += q;
                self.accumulate("recalled", q, value);
                line!(self, 0, "RECALL", "lot", id, &code, "qty", q, "value", money(value));
                for (w, quantity, cost) in held {
                    line!(self, 2, w, "qty", quantity, "value", money(quantity * cost));
                }
            }
            "EXPIRE" => {
                let days = number(a[0]);
                line!(self, 0, "EXPIRE", days);
                let mut total_q = 0;
                let mut total_value = 0;
                let codes: Vec<String> = self.items.keys().cloned().collect();
                let warehouses: Vec<String> = self.stock.keys().cloned().collect();
                for code in codes {
                    for w in &warehouses {
                        let expired: Vec<usize> = self.stock_lots(w, &code)
                            .map(|stocks| stocks.keys().copied()
                                .filter(|&id| self.day - self.lots[id - 1].day > days).collect())
                            .unwrap_or_default();
                        if expired.is_empty() {
                            continue;
                        }
                        let mut q = 0;
                        let mut value = 0;
                        for id in &expired {
                            let stock = self.stock.get_mut(w).unwrap()
                                .get_mut(&code).unwrap().remove(id).unwrap();
                            q += stock.quantity;
                            value += stock.quantity * stock.cost;
                            self.lots[id - 1].removed += stock.quantity;
                        }
                        self.accumulate("expired", q, value);
                        self.card_entry(&code, "expire", w, -q, -value);
                        total_q += q;
                        total_value += value;
                        line!(self, 2, &code, w, "lots", expired.len(), "qty",
                              q, "value", money(value));
                    }
                }
                line!(self, 2, "total", "qty", total_q, "value", money(total_value));
            }
            "VALUE" | "AGING" => {
                let warehouses: Vec<String> = if a.is_empty() {
                    self.stock.keys().cloned().collect()
                } else {
                    self.warehouse(a[0])?;
                    vec![a[0].to_string()]
                };
                if cmd == "VALUE" {
                    if a.is_empty() {
                        line!(self, 0, "VALUE");
                    } else {
                        line!(self, 0, "VALUE", a[0]);
                    }
                } else if a.is_empty() {
                    line!(self, 0, "AGING", "day", self.day);
                } else {
                    line!(self, 0, "AGING", a[0], "day", self.day);
                }
                let mut total_q = 0;
                let mut total_value = 0;
                let mut bucket_q = [0i64; 4];
                let mut bucket_v = [0i64; 4];
                let codes: Vec<String> = self.items.keys().cloned().collect();
                for code in codes {
                    let mut q = 0;
                    let mut value = 0;
                    let mut values = Vec::<(i64, i64)>::new();
                    let mut item_buckets = [0i64; 4];
                    for w in &warehouses {
                        let mut held_q = 0;
                        let mut held_value = 0;
                        if let Some(stocks) = self.stock_lots(w, &code) {
                            for (&id, stock) in stocks {
                                held_q += stock.quantity;
                                held_value += stock.quantity * stock.cost;
                                if cmd == "AGING" {
                                    let age = self.day - self.lots[id - 1].day;
                                    let bucket = if age <= 30 { 0 } else if age <= 60 { 1 }
                                                 else if age <= 90 { 2 } else { 3 };
                                    item_buckets[bucket] += stock.quantity;
                                    bucket_q[bucket] += stock.quantity;
                                    bucket_v[bucket] += stock.quantity * stock.cost;
                                }
                            }
                        }
                        q += held_q;
                        value += held_value;
                        values.push((held_q, held_value));
                    }
                    if q == 0 {
                        continue;
                    }
                    if cmd == "VALUE" {
                        line!(self, 2, &code, "qty", q, "value", money(value),
                              "avg", money(value / q));
                        if a.is_empty() {
                            for (i, (held_q, held_value)) in values.iter().enumerate() {
                                if *held_q > 0 {
                                    line!(self, 4, &warehouses[i], "qty", held_q,
                                          "value", money(*held_value));
                                }
                            }
                        }
                    } else {
                        self.aging_line(&code, &item_buckets, false);
                    }
                    total_q += q;
                    total_value += value;
                }
                if cmd == "VALUE" {
                    line!(self, 2, "total", "qty", total_q, "value", money(total_value));
                } else {
                    self.aging_line("total", &bucket_q, false);
                    self.aging_line("value", &bucket_v, true);
                }
            }
            "LOTS" => {
                let (w, code) = (a[0], a[1]);
                self.pair(w, code)?;
                line!(self, 0, "LOTS", w, code);
                let ids = self.fifo(w, code);
                let pending: Vec<usize> = self.orders.iter().enumerate()
                    .filter(|(_, o)| o.warehouse == w && o.item == code && o.backorder > 0)
                    .map(|(i, _)| i).collect();
                for id in &ids {
                    let stock = &self.stock_lots(w, code).unwrap()[id];
                    line!(self, 2, "lot", id, "day", self.lots[id - 1].day,
                          "qty", stock.quantity, "cost", money(stock.cost),
                          "value", money(stock.quantity * stock.cost),
                          "age", self.day - self.lots[id - 1].day);
                }
                for index in &pending {
                    let order = &self.orders[*index];
                    line!(self, 2, "backorder", "order", order.number, "qty", order.backorder);
                }
                if ids.is_empty() && pending.is_empty() {
                    line!(self, 2, "(none)");
                }
            }
            "REORDER" | "ITEMS" => {
                line!(self, 0, cmd);
                let mut found = false;
                let codes: Vec<String> = self.items.keys().cloned().collect();
                for code in codes {
                    let entry = &self.items[&code];
                    let q = self.total_quantity(&code);
                    let pending = self.backorder(&code);
                    if cmd == "REORDER" {
                        if q - pending > entry.level {
                            continue;
                        }
                        line!(self, 2, &code, &entry.name, "onhand", q,
                              "backorder", pending, "level", entry.level);
                    } else {
                        let cost = entry.last_cost.map(money).unwrap_or_else(|| "none".into());
                        line!(self, 2, &code, &entry.name, "level", entry.level,
                              "onhand", q, "backorder", pending, "cost", cost);
                    }
                    found = true;
                }
                if !found {
                    line!(self, 2, "(none)");
                }
            }
            "MARGIN" | "TOP" => {
                let rows = self.sales();
                if cmd == "MARGIN" {
                    line!(self, 0, "MARGIN");
                    let mut total = Sale::default();
                    for (code, row) in &rows {
                        self.margin_line(code, row);
                        total.quantity += row.quantity;
                        total.revenue += row.revenue;
                        total.cogs += row.cogs;
                    }
                    self.margin_line("total", &total);
                } else {
                    let k = number(a[0]) as usize;
                    line!(self, 0, "TOP", k);
                    let mut codes: Vec<&String> = rows.keys().collect();
                    codes.sort_by(|a, b| {
                        let x = &rows[*a];
                        let y = &rows[*b];
                        (y.revenue - y.cogs).cmp(&(x.revenue - x.cogs))
                            .then(y.revenue.cmp(&x.revenue))
                            .then(a.cmp(b))
                    });
                    for (rank, &code) in codes.iter().take(k).enumerate() {
                        let row = &rows[code];
                        let profit = row.revenue - row.cogs;
                        line!(self, 2, rank + 1, code, "profit", money(profit),
                              "revenue", money(row.revenue), "margin", margin(profit, row.revenue));
                    }
                    if codes.is_empty() {
                        line!(self, 2, "(none)");
                    }
                }
            }
            "BACKORDERS" => {
                line!(self, 0, "BACKORDERS");
                let mut found = false;
                for order in &self.orders {
                    if order.backorder > 0 {
                        line!(self, 2, "order", order.number, &order.warehouse, &order.item,
                              "qty", order.backorder, "day", order.day, "price", money(order.price));
                        found = true;
                    }
                }
                if !found {
                    line!(self, 2, "(none)");
                }
            }
            "ORDER" => {
                let index = self.order_index(a[0])?;
                let order = &self.orders[index];
                line!(self, 0, "ORDER", order.number, &order.warehouse, &order.item,
                      "day", order.day, "price", money(order.price));
                line!(self, 2, "ordered", order.ordered, "shipped", order.shipped,
                      "backorder", order.backorder, "cancelled", order.cancelled,
                      "returned", order.returned);
                for part in &order.issues {
                    line!(self, 2, "lot", part.lot, "qty", part.quantity, "cost", money(part.cost));
                }
                line!(self, 2, "revenue", money(order.revenue), "cogs",
                      money(order.cogs), "profit", money(order.revenue - order.cogs));
            }
            "TRACE" => {
                let index = self.lot_index(a[0])?;
                let lot = &self.lots[index];
                line!(self, 0, "TRACE", "lot", lot.number, &lot.item, &lot.kind,
                      &lot.warehouse, "day", lot.day, "qty", lot.initial_quantity,
                      "cost", money(lot.initial_cost));
                for w in self.stock.keys() {
                    if let Some(stock) = self.stock_lots(w, &lot.item).and_then(|s| s.get(&lot.number)) {
                        line!(self, 2, "held", w, "qty", stock.quantity, "cost", money(stock.cost));
                    }
                }
                for order in &self.orders {
                    let q: i64 = order.issues.iter().filter(|p| p.lot == lot.number)
                        .map(|p| p.quantity).sum();
                    if q > 0 {
                        line!(self, 2, "order", order.number, "qty", q);
                    }
                }
                if lot.removed > 0 {
                    line!(self, 2, "removed", "qty", lot.removed);
                }
            }
            "CARD" => {
                self.item(a[0])?;
                let entry = &self.items[a[0]];
                line!(self, 0, "CARD", &entry.code, &entry.name);
                let mut q = 0;
                let mut value = 0;
                for card in &entry.card {
                    q += card.quantity;
                    value += card.value;
                    line!(self, 2, "day", card.day, &card.kind, &card.warehouse,
                          signed_quantity(card.quantity), signed_money(card.value),
                          "balance", q, money(value));
                }
                if entry.card.is_empty() {
                    line!(self, 2, "(none)");
                }
            }
            "STATUS" => {
                line!(self, 0, "STATUS");
                for (w, contents) in &self.stock {
                    let mut skus = 0;
                    let mut q = 0;
                    let mut value = 0;
                    for stocks in contents.values() {
                        if !stocks.is_empty() {
                            skus += 1;
                        }
                        for stock in stocks.values() {
                            q += stock.quantity;
                            value += stock.quantity * stock.cost;
                        }
                    }
                    let pending: i64 = self.orders.iter()
                        .filter(|o| o.warehouse == *w).map(|o| o.backorder).sum();
                    line!(self, 2, w, "skus", skus, "qty", q,
                          "value", money(value), "backorder", pending);
                }
                if self.stock.is_empty() {
                    line!(self, 2, "(none)");
                }
            }
            "SUMMARY" => {
                line!(self, 0, "SUMMARY");
                for category in CATEGORIES {
                    let total = &self.totals[category];
                    line!(self, 2, category, "qty", total.quantity, "value", money(total.value));
                }
                let total = self.all_stocks();
                line!(self, 2, "on-hand", "qty", total.quantity, "value", money(total.value));
                let open = self.orders.iter().filter(|o| o.backorder > 0).count();
                let pending: i64 = self.orders.iter().map(|o| o.backorder).sum();
                line!(self, 2, "orders", self.orders.len(), "open", open, "backorder", pending);
            }
            _ => {}
        }
        Ok(())
    }

    fn execute(&mut self, line_text: &str) {
        let mut parts = line_text.split_whitespace();
        let cmd = parts.next().unwrap_or("");
        let arguments: Vec<&str> = parts.collect();
        if let Err(reason) = self.command(cmd, &arguments) {
            line!(self, 0, "ERROR", reason);
        }
    }
}

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let mut lines = input.lines();
    let n: usize = lines.next().unwrap_or("0").parse().unwrap();
    let mut inventory = Inventory::new();
    for line in lines.take(n) {
        inventory.execute(line);
    }
    if !inventory.output.is_empty() {
        println!("{}", inventory.output.join("\n"));
    }
}
