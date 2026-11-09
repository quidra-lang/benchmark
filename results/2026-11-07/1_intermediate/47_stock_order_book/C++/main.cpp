#include <cstdlib>
#include <utility>
#include <algorithm>
#include <iostream>
#include <map>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>
using namespace std;
using Integer = long long;
string num(Integer n) {
    return to_string(n);
}
string average(Integer value, Integer quantity) {
    Integer c = value * 100 / quantity;
    return num(c / 100) + "." + (c % 100 < 10 ? "0" : "") + num(c % 100);
}
void require(bool bad, const string &message) {
    if (bad)
        throw runtime_error(message);
}
struct Order {
    string id, trader, type, side, condition, status = "PENDING";
    Integer quantity, remaining, price = -1, trigger = -1, peak = -1, visible = 0, filled = 0,
                                 value = 0, priority = 0;
    vector<string> history{"ACCEPT"};
    bool resting() const {
        return status == "OPEN" || status == "PARTIAL";
    }
    bool active() const {
        return resting() || status == "PENDING";
    }
    bool matches(Integer p) const {
        return price < 0 || (side == "BUY" ? p <= price : p >= price);
    }
    bool triggered(Integer p) const {
        return side == "BUY" ? p >= trigger : p <= trigger;
    }
    string line() const {
        return "ORDER " + id + " " + status + " " + num(filled) + "/" + num(quantity);
    }
    string details() const {
        return id + " " + trader + " " + type + " " + side + " " + (price < 0 ? "-" : num(price)) +
               " " + status + " " + num(filled) + "/" + num(quantity) + " avg " +
               (filled ? average(value, filled) : "-") +
               (trigger < 0 ? "" : " trigger " + num(trigger));
    }
};
struct Trader {
    Integer bought = 0, sold = 0, cash = 0, fees = 0, limit = -1;
    Integer net() const {
        return bought - sold;
    }
    Integer volume() const {
        return bought + sold;
    }
    Integer pnl(Integer mark) const {
        return cash + net() * mark;
    }
    string position(const string &name, Integer mark) const {
        return "POSITION " + name + " bought " + num(bought) + " sold " + num(sold) + " net " +
               num(net()) + " cash " + num(cash) + " fees " + num(fees) + " pnl " + num(pnl(mark));
    }
};
struct Trade {
    Integer price, quantity, buyFee, sellFee;
    int buy, sell, taker;
};
struct Level {
    Integer price, quantity;
    int count;
};
class Engine {
    vector<Order> orders;
    map<string, int> ids;
    map<string, Trader> traders;
    vector<Trade> trades;
    Integer priority = 1, band = 0, tick = 1, lot = 1, makerFee = 0, takerFee = 0;
    bool halted = false;
    string other(const string &side) const {
        return side == "BUY" ? "SELL" : "BUY";
    }
    Integer last() const {
        return trades.empty() ? -1 : trades.back().price;
    }
    Integer mark() const {
        return max<Integer>(0, last());
    }
    int order(const string &id) const {
        auto it = ids.find(id);
        require(it == ids.end(), "unknown order");
        return it->second;
    }
    Trader &trader(const string &name) {
        auto it = traders.find(name);
        require(it == traders.end(), "unknown trader");
        return it->second;
    }
    vector<int> book(const string &side) const {
        vector<int> selected;
        for (int i = 0; i < (int)orders.size(); ++i)
            if (orders[i].side == side && orders[i].resting())
                selected.push_back(i);
        sort(selected.begin(), selected.end(), [&](int a, int b) {
            if (orders[a].price != orders[b].price)
                return side == "BUY" ? orders[a].price > orders[b].price
                                     : orders[a].price < orders[b].price;
            return orders[a].priority < orders[b].priority;
        });
        return selected;
    }
    vector<Level> levels(const string &side) const {
        vector<Level> result;
        for (int i : book(side)) {
            const Order &o = orders[i];
            if (!result.empty() && result.back().price == o.price) {
                result.back().quantity += o.visible;
                ++result.back().count;
            } else
                result.push_back({o.price, o.visible, 1});
        }
        return result;
    }
    Integer exposure(const string &name, const string &side, int excluded = -1) {
        Integer n = side == "BUY" ? trader(name).net() : -trader(name).net();
        for (int i = 0; i < (int)orders.size(); ++i)
            if (i != excluded && orders[i].trader == name && orders[i].side == side &&
                orders[i].active())
                n += orders[i].remaining;
        return n;
    }
    void risk(const string &name, const string &side, Integer quantity, int excluded = -1) {
        auto it = traders.find(name);
        if (it != traders.end() && it->second.limit >= 0)
            require(exposure(name, side, excluded) + quantity > it->second.limit, "risk limit");
    }
    void checkBand(Integer price) const {
        require(band > 0 && last() >= 0 && abs(price - last()) > band, "outside band");
    }
    string tradeLine(int i) const {
        const Trade &t = trades[i];
        const Order &b = orders[t.buy];
        const Order &s = orders[t.sell];
        return "TRADE " + num(i + 1) + " " + num(t.price) + " " + num(t.quantity) + " " + b.id +
               " " + b.trader + " " + s.id + " " + s.trader;
    }
    void match(int index) {
        Order &o = orders[index];
        while (o.remaining) {
            vector<int> opposite = book(other(o.side));
            if (opposite.empty())
                break;
            int mi = opposite.front();
            Order &m = orders[mi];
            if (!o.matches(m.price))
                break;
            if (o.trader == m.trader) {
                cout << "STP " << m.id << ' ' << m.remaining << '\n';
                m.history.push_back("STP " + num(m.remaining));
                m.remaining = 0;
                m.status = "CANCELLED";
                continue;
            }
            Integer q = min(o.remaining, m.visible), p = m.price, tf = q * takerFee,
                    mf = q * makerFee;
            int buy = o.side == "BUY" ? index : mi, sell = o.side == "SELL" ? index : mi;
            Trade t{p, q, o.side == "BUY" ? tf : mf, o.side == "SELL" ? tf : mf, buy, sell, index};
            trades.push_back(t);
            for (int i : {index, mi}) {
                Order &f = orders[i];
                f.remaining -= q;
                f.filled += q;
                f.value += p * q;
                f.history.push_back("FILL " + num(trades.size()) + " " + num(p) + " " + num(q));
            }
            m.visible -= q;
            Trader &bt = traders[orders[buy].trader];
            Trader &st = traders[orders[sell].trader];
            bt.bought += q;
            bt.cash -= p * q + t.buyFee;
            bt.fees += t.buyFee;
            st.sold += q;
            st.cash += p * q - t.sellFee;
            st.fees += t.sellFee;
            cout << tradeLine((int)trades.size() - 1) << '\n';
            m.status = m.remaining ? "PARTIAL" : "FILLED";
            if (m.remaining && !m.visible) {
                m.priority = priority++;
                m.visible = min(m.peak, m.remaining);
                string h = num(m.visible) + " " + num(m.remaining - m.visible);
                m.history.push_back("REFRESH " + h);
                cout << "REFRESH " << m.id << ' ' << h << '\n';
            }
        }
    }
    void post(int i, bool replaced = false) {
        Order &o = orders[i];
        if (!o.remaining)
            o.status = "FILLED";
        else if (replaced || o.type == "ICEBERG" || o.type == "STOPLIMIT" ||
                 (o.type == "LIMIT" && o.condition != "IOC")) {
            o.priority = priority++;
            o.visible = o.peak < 0 ? o.remaining : min(o.peak, o.remaining);
            o.status = o.filled ? "PARTIAL" : "OPEN";
            o.history.push_back("REST " + num(o.price) + " " + num(o.visible));
        } else {
            o.history.push_back("EXPIRE " + num(o.remaining));
            o.remaining = 0;
            o.status = "CANCELLED";
        }
        cout << o.line() << '\n';
    }
    void trigger() {
        while (!trades.empty()) {
            vector<int> selected;
            for (int i = 0; i < (int)orders.size(); ++i)
                if (orders[i].status == "PENDING" && orders[i].triggered(last()))
                    selected.push_back(i);
            if (selected.empty())
                break;
            for (int i : selected)
                orders[i].status = "TRIGGERING";
            for (int i : selected) {
                cout << "TRIGGER " << orders[i].id << '\n';
                orders[i].history.push_back("TRIGGER");
                match(i);
                post(i);
            }
        }
    }
    void cancel(int i) {
        Order &o = orders[i];
        o.history.push_back("CANCEL " + num(o.remaining));
        o.remaining = 0;
        o.status = "CANCELLED";
        cout << o.line() << '\n';
    }
    string bar(int first, int end) const {
        Integer high = trades[first].price, low = high, volume = 0;
        for (int i = first; i < end; ++i) {
            high = max(high, trades[i].price);
            low = min(low, trades[i].price);
            volume += trades[i].quantity;
        }
        return "open " + num(trades[first].price) + " high " + num(high) + " low " + num(low) +
               " close " + num(trades[end - 1].price) + " volume " + num(volume);
    }

  public:
    void execute(const string &line) {
        istringstream input(line);
        vector<string> a;
        string c, word;
        input >> c;
        while (input >> word)
            a.push_back(word);
        try {
            command(c, a);
        } catch (const runtime_error &e) {
            if (c == "LIMIT" || c == "MARKET" || c == "STOP" || c == "STOPLIMIT" ||
                c == "ICEBERG" || c == "CANCEL" || c == "REPLACE")
                cout << "REJECT " << a[0] << ' ' << e.what() << '\n';
            else
                cout << "ERROR " << e.what() << '\n';
        }
    }
    void command(const string &c, const vector<string> &a) {
        if (c == "LIMIT" || c == "MARKET" || c == "STOP" || c == "STOPLIMIT" || c == "ICEBERG") {
            Order o;
            o.id = a[0];
            o.trader = a[1];
            o.type = c;
            o.side = a[2];
            o.price = c == "MARKET" || c == "STOP" ? -1 : stoll(a[c == "STOPLIMIT" ? 4 : 3]);
            o.trigger = c == "STOP" || c == "STOPLIMIT" ? stoll(a[3]) : -1;
            o.quantity = o.remaining = stoll(a[c == "MARKET" ? 3 : c == "STOPLIMIT" ? 5 : 4]);
            if (c == "ICEBERG")
                o.peak = stoll(a[5]);
            if (c == "LIMIT" && a.size() == 6)
                o.condition = a[5];
            require(halted, "halted");
            require(ids.count(o.id), "duplicate id");
            require(o.price == 0 || o.trigger == 0, "invalid price");
            require(!o.quantity, "invalid quantity");
            require((o.price >= 0 && o.price % tick) || (o.trigger >= 0 && o.trigger % tick),
                    "invalid tick");
            require(o.quantity % lot, "invalid lot");
            if (c == "ICEBERG")
                require(o.peak == 0 || o.peak > o.quantity || o.peak % lot, "invalid peak");
            if (o.trigger >= 0)
                require(last() >= 0 && o.triggered(last()), "invalid trigger");
            if (o.price >= 0)
                checkBand(o.price);
            risk(o.trader, o.side, o.quantity);
            vector<int> opposite = book(other(o.side));
            require(o.condition == "POSTONLY" && !opposite.empty() &&
                        o.matches(orders[opposite[0]].price),
                    "would cross");
            if (o.condition == "FOK") {
                Integer available = 0;
                for (int i : opposite)
                    if (orders[i].trader != o.trader && o.matches(orders[i].price))
                        available += orders[i].remaining;
                require(available < o.quantity, "unfillable");
            }
            traders.try_emplace(o.trader);
            int i = (int)orders.size();
            ids[o.id] = i;
            orders.push_back(o);
            if (o.trigger >= 0)
                cout << o.line() << '\n';
            else {
                if (o.condition != "POSTONLY")
                    match(i);
                post(i);
                trigger();
            }
            return;
        }
        const string id = a.empty() ? "" : a[0];
        if (c == "CANCEL") {
            int i = order(id);
            require(!orders[i].active(), "not open");
            cancel(i);
        } else if (c == "REPLACE") {
            require(halted, "halted");
            int i = order(id);
            Order &o = orders[i];
            require(!o.resting(), "not open");
            Integer p = stoll(a[1]), q = stoll(a[2]);
            bool moved = p != o.price;
            require(!p, "invalid price");
            require(!q, "invalid quantity");
            require(moved && p % tick, "invalid tick");
            require(q % lot, "invalid lot");
            require(!moved && q == o.remaining, "no change");
            if (moved)
                checkBand(p);
            if (q > o.remaining)
                risk(o.trader, o.side, q, i);
            bool kept = !moved && q < o.remaining;
            o.quantity = o.filled + q;
            o.remaining = q;
            o.price = p;
            o.history.push_back("REPLACE " + num(p) + " " + num(q) + (kept ? " kept" : " lost"));
            cout << "REPLACE " << id << (kept ? " kept\n" : " lost\n");
            if (kept) {
                o.visible = min(o.visible, q);
                cout << o.line() << '\n';
            } else {
                o.status = "EXECUTING";
                match(i);
                post(i, true);
                trigger();
            }
        } else if (c == "CANCELALL") {
            trader(id);
            vector<int> selected;
            for (int i = 0; i < (int)orders.size(); ++i)
                if (orders[i].trader == id && orders[i].active())
                    selected.push_back(i);
            cout << c << ' ' << id << ' ' << selected.size() << '\n';
            for (int i : selected)
                cancel(i);
        } else if (c == "HALT") {
            require(halted, "already halted");
            halted = true;
            cout << c << '\n';
        } else if (c == "RESUME") {
            require(!halted, "not halted");
            halted = false;
            cout << c << '\n';
        } else if (c == "RISK") {
            traders[id].limit = stoll(a[1]);
            cout << c << ' ' << id << ' ' << a[1] << " exposure buy " << exposure(id, "BUY")
                 << " sell " << exposure(id, "SELL") << '\n';
        } else if (c == "FEE") {
            Integer m = stoll(a[0]), t = stoll(a[1]);
            require(m + t < 0, "invalid fee");
            makerFee = m;
            takerFee = t;
            cout << "FEE maker " << m << " taker " << t << '\n';
        } else if (c == "BAND") {
            band = stoll(id);
            cout << c << ' ' << id << '\n';
        } else if (c == "TICK" || c == "LOT") {
            Integer value = stoll(id);
            require(!value, "invalid size");
            (c == "TICK" ? tick : lot) = value;
            cout << c << ' ' << value << '\n';
        } else if (c == "BOOK") {
            int n = stoi(id);
            require(!n, "invalid depth");
            vector<Level> bids = levels("BUY"), asks = levels("SELL");
            cout << "BOOK bids " << bids.size() << " asks " << asks.size() << '\n';
            for (int i = min(n, (int)asks.size()) - 1; i >= 0; --i)
                cout << "ASK " << asks[i].price << ' ' << asks[i].quantity << ' ' << asks[i].count
                     << '\n';
            for (int i = 0; i < min(n, (int)bids.size()); ++i)
                cout << "BID " << bids[i].price << ' ' << bids[i].quantity << ' ' << bids[i].count
                     << '\n';
        } else if (c == "ORDERS") {
            trader(id);
            vector<int> selected;
            for (int i = 0; i < (int)orders.size(); ++i)
                if (orders[i].trader == id && orders[i].active())
                    selected.push_back(i);
            cout << c << ' ' << id << ' ' << selected.size() << '\n';
            for (int i : selected)
                cout << orders[i].details() << '\n';
        } else if (c == "STATUS") {
            const Order &current = orders[order(id)];
            cout << "STATUS " << current.details() << '\n';
        } else if (c == "HISTORY") {
            const Order &o = orders[order(id)];
            cout << c << ' ' << id << ' ' << o.history.size() << '\n';
            for (const string &h : o.history)
                cout << h << '\n';
        } else if (c == "POSITION")
            cout << trader(id).position(id, mark()) << '\n';
        else if (c == "FILLS") {
            trader(id);
            vector<int> selected;
            for (int i = 0; i < (int)trades.size(); ++i)
                if (orders[trades[i].buy].trader == id || orders[trades[i].sell].trader == id)
                    selected.push_back(i);
            cout << c << ' ' << id << ' ' << selected.size() << '\n';
            Integer net = 0;
            for (int i : selected) {
                const Trade &t = trades[i];
                bool buy = orders[t.buy].trader == id;
                int oi = buy ? t.buy : t.sell;
                net += buy ? t.quantity : -t.quantity;
                cout << i + 1 << ' ' << (buy ? "BUY" : "SELL") << ' ' << t.price << ' '
                     << t.quantity << ' ' << orders[oi].id << ' '
                     << (oi == t.taker ? "TAKER" : "MAKER") << " fee "
                     << (buy ? t.buyFee : t.sellFee) << " net " << net << '\n';
            }
        } else if (c == "LAST") {
            if (trades.empty())
                cout << "LAST none\n";
            else
                cout << "LAST " << last() << ' ' << trades.back().quantity << '\n';
        } else if (c == "VWAP") {
            if (trades.empty())
                cout << "VWAP none\n";
            else {
                Integer volume = 0, value = 0;
                for (const Trade &t : trades) {
                    volume += t.quantity;
                    value += t.quantity * t.price;
                }
                cout << "VWAP " << average(value, volume) << " volume " << volume << " trades "
                     << trades.size() << '\n';
            }
        } else if (c == "SPREAD") {
            vector<int> b = book("BUY"), s = book("SELL");
            cout << "SPREAD bid " << (b.empty() ? "none" : num(orders[b[0]].price)) << " ask "
                 << (s.empty() ? "none" : num(orders[s[0]].price));
            if (!b.empty() && !s.empty()) {
                Integer bp = orders[b[0]].price, sp = orders[s[0]].price;
                cout << " spread " << sp - bp << " mid " << (sp + bp) / 2
                     << ((sp + bp) % 2 ? ".5" : ".0");
            }
            cout << '\n';
        } else if (c == "IMPACT") {
            Integer q = stoll(a[1]);
            require(!q, "invalid quantity");
            vector<Level> ls = levels(other(id));
            Integer r = q, value = 0, worst = 0, total = 0;
            int used = 0;
            for (const Level &l : ls) {
                total += l.quantity;
                if (!r)
                    continue;
                Integer n = min(r, l.quantity);
                r -= n;
                value += n * l.price;
                worst = l.price;
                ++used;
            }
            cout << c << ' ' << id << ' ' << q;
            if (r)
                cout << " insufficient " << total;
            else
                cout << " avg " << average(value, q) << " worst " << worst << " levels " << used;
            cout << '\n';
        } else if (c == "TRADES") {
            int k = stoi(id);
            require(!k, "invalid count");
            int n = min(k, (int)trades.size());
            cout << "TRADES " << n << " of " << trades.size() << '\n';
            for (int i = (int)trades.size() - n; i < (int)trades.size(); ++i)
                cout << tradeLine(i) << '\n';
        } else if (c == "BARS") {
            int k = stoi(id);
            require(!k, "invalid count");
            cout << "BARS " << (trades.size() + k - 1) / k << '\n';
            for (int i = 0; i < (int)trades.size(); i += k)
                cout << i / k + 1 << ' ' << bar(i, min(i + k, (int)trades.size())) << '\n';
        } else if (c == "RANK") {
            vector<string> names;
            for (const auto &entry : traders)
                names.push_back(entry.first);
            sort(names.begin(), names.end(), [&](const string &a, const string &b) {
                const Trader &x = traders[a];
                const Trader &y = traders[b];
                if (x.pnl(mark()) != y.pnl(mark()))
                    return x.pnl(mark()) > y.pnl(mark());
                if (x.volume() != y.volume())
                    return x.volume() > y.volume();
                return a < b;
            });
            cout << "RANK " << names.size() << '\n';
            for (int i = 0; i < (int)names.size(); ++i)
                cout << i + 1 << ' ' << names[i] << " pnl " << traders[names[i]].pnl(mark())
                     << " volume " << traders[names[i]].volume() << '\n';
        } else if (c == "FLOW") {
            Integer b = 0, s = 0;
            for (const Trade &t : trades)
                (orders[t.taker].side == "BUY" ? b : s) += t.quantity;
            cout << "FLOW buy " << b << " sell " << s << " net " << b - s << '\n';
        } else if (c == "SUMMARY") {
            if (trades.empty())
                cout << "SUMMARY trades 0\n";
            else {
                Integer fees = 0;
                for (const Trade &t : trades)
                    fees += t.buyFee + t.sellFee;
                string values = bar(0, (int)trades.size());
                size_t at = values.rfind(" volume ");
                cout << "SUMMARY trades " << trades.size() << " volume " << values.substr(at + 8)
                     << ' ' << values.substr(0, at) << " fees " << fees << '\n';
            }
            for (const auto &entry : traders)
                cout << entry.second.position(entry.first, mark()) << '\n';
        }
    }
};
int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int n;
    cin >> n;
    string line;
    getline(cin, line);
    Engine engine;
    while (n--) {
        getline(cin, line);
        engine.execute(line);
    }
}
