#include <algorithm>
#include <array>
#include <cctype>
#include <cstdint>
#include <deque>
#include <iomanip>
#include <iostream>
#include <map>
#include <set>
#include <sstream>
#include <string>
#include <vector>
using namespace std;

const vector<string> keys = {"PROTOCOL", "FRAMES", "WINDOW", "SEQBITS", "TIMEOUT", "DELAY", "INTERVAL", "MAXTICKS", "DUPACK", "NAK", "BACKOFF", "CONGESTION", "UNSAFE", "TRACE", "RANDOM", "LOSEDATA", "LOSECTRL", "CORRUPTDATA", "CORRUPTCTRL", "DELAYDATA", "DELAYCTRL", "SNAPSHOT"};
vector<string> output;
vector<string> words(const string& line) {
    istringstream input(line);
    vector<string> result;
    string word;
    while (input >> word) result.push_back(word);
    return result;
}
string fixedValue(int64_t numerator, int64_t denominator, int digits) {
    int64_t scale = digits == 2 ? 100 : 10;
    int64_t value = denominator == 0 ? 0 : numerator * scale / denominator;
    ostringstream text;
    text << value / scale << '.' << setw(digits) << setfill('0') << value % scale;
    return text.str();
}
int mod(int a, int b) { return (a % b + b) % b; }
string tickValue(int t) { return t < 0 ? "-" : to_string(t); }
string onOff(bool value) { return value ? "on" : "off"; }
struct Scenario {
    string name, protocol, error, trace = "ALL";
    map<string, vector<string>> values;
    map<string, set<int>> lists;
    map<string, map<int, int>> delays;
    int n = 0, w = 0, k = 0, timeout = 0, delay = 0, interval = 0, limit = 1000, dupack = 0;
    bool nak = false, backoff = false, congestion = false, unsafe = false, random = false;
    int64_t seed = 0;
    int loss = 0, corruption = 0;
    int completion = -1, end = 0, delivered = 0, data = 0;
    int number(const string& key) const { return stoi(values.at(key)[0]); }
    bool on(const string& key) const { return values.count(key) && values.at(key)[0] == "ON"; }
    void line(const vector<string>& tokens) {
        if (!error.empty()) return;
        string key = tokens[0];
        auto it = find(keys.begin(), keys.end(), key);
        if (it == keys.end()) { error = "unknown key " + key; return; }
        if (values.count(key)) { error = "duplicate key " + key; return; }
        int position = int(it - keys.begin()), count = int(tokens.size()) - 1;
        if (key == "RANDOM" ? count != 3 : position >= 15 ? count < 1 : count != 1) {
            error = "wrong number of values for " + key;
            return;
        }
        values[key] = vector<string>(tokens.begin() + 1, tokens.end());
    }
    bool valid(const string& key) {
        const vector<string>& v = values.at(key);
        if (key == "PROTOCOL") return v[0] == "SW" || v[0] == "GBN" || v[0] == "SR";
        if (key == "NAK" || key == "BACKOFF" || key == "CONGESTION" || key == "UNSAFE") return v[0] == "ON" || v[0] == "OFF";
        if (key == "TRACE") return v[0] == "ALL" || v[0] == "SENDER" || v[0] == "RECEIVER" || v[0] == "NONE";
        if (key == "RANDOM") {
            int64_t s = stoll(v[0]), p = stoll(v[1]), c = stoll(v[2]);
            return s >= 1 && s <= 2147483646LL && p >= 0 && c >= 0 && p + c <= 100;
        }
        int position = int(find(keys.begin(), keys.end(), key) - keys.begin());
        if (position >= 15) {
            set<int> found;
            map<int, int> extra;
            bool delayed = key == "DELAYDATA" || key == "DELAYCTRL";
            for (const string& item : v) {
                size_t colon = item.find(':');
                int a = stoi(item.substr(0, colon));
                bool snapshot = key == "SNAPSHOT";
                if (a < (snapshot ? 0 : 1) || a > (snapshot ? 2000 : 9999) || !found.insert(a).second) return false;
                if (delayed) {
                    int e = stoi(item.substr(colon + 1));
                    if (e < 1 || e > 50) return false;
                    extra[a] = e;
                }
            }
            lists[key] = found;
            if (delayed) delays[key] = extra;
            return true;
        }
        int a = number(key), lo = 1, hi = 0;
        if (key == "FRAMES") hi = 60;
        else if (key == "WINDOW") hi = 32;
        else if (key == "SEQBITS") hi = 6;
        else if (key == "TIMEOUT") hi = 50;
        else if (key == "DELAY" || key == "DUPACK") hi = 10;
        else if (key == "INTERVAL") { lo = 0; hi = 10; }
        else if (key == "MAXTICKS") hi = 2000;
        return a >= lo && a <= hi;
    }
    void check() {
        if (!error.empty()) return;
        for (int i = 0; i < 6; i++) {
            if (!values.count(keys[i])) { error = "missing key " + keys[i]; return; }
        }
        for (const string& key : keys) {
            if (values.count(key) && !valid(key)) { error = "bad value for " + key; return; }
        }
        protocol = values["PROTOCOL"][0];
        n = number("FRAMES"); w = number("WINDOW"); k = number("SEQBITS"); timeout = number("TIMEOUT"); delay = number("DELAY");
        if (values.count("INTERVAL")) interval = number("INTERVAL");
        if (values.count("MAXTICKS")) limit = number("MAXTICKS");
        if (values.count("DUPACK")) dupack = number("DUPACK");
        nak = on("NAK"); backoff = on("BACKOFF"); congestion = on("CONGESTION"); unsafe = on("UNSAFE");
        if (values.count("TRACE")) trace = values["TRACE"][0];
        random = values.count("RANDOM");
        if (random) { seed = stoll(values["RANDOM"][0]); loss = stoi(values["RANDOM"][1]); corruption = stoi(values["RANDOM"][2]); }
        if (protocol == "SR" && dupack != 0) { error = "DUPACK not supported for SR"; return; }
        int upper = protocol == "SW" ? 1 : protocol == "GBN" ? (1 << k) - 1 : 1 << (k - 1);
        if (w > upper && !(unsafe && protocol != "SW")) { error = "window " + to_string(w) + " exceeds limit " + to_string(upper) + " for " + protocol; return; }
        for (const string& kind : {"DATA", "CTRL"}) {
            for (int i : lists["LOSE" + kind]) {
                if (lists["CORRUPT" + kind].count(i)) {
                    error = string(kind == "DATA" ? "data" : "control") + " #" + to_string(i) + " both lost and corrupted";
                    return;
                }
            }
        }
    }
    bool contains(const string& key, int i) const {
        auto it = lists.find(key);
        return it != lists.end() && it->second.count(i);
    }
    int extra(const string& key, int i) const {
        auto it = delays.find(key);
        if (it == delays.end()) return 0;
        auto found = it->second.find(i);
        return found == it->second.end() ? 0 : found->second;
    }
};
struct Event { int arrival, number, value, outcome; string kind; };
class Simulation {
    Scenario& s;
    int t = 0, M, base = 0, high = 0, next = 0, timer = -1, C, duplicates = 0, r = 0;
    bool sr, nakSent = false;
    int cwnd = 1, threshold, growth = 0;
    int controlCount = 0, naks = 0, resent = 0, timeouts = 0, fast = 0;
    int lostData = 0, lostControl = 0, corruptData = 0, corruptControl = 0;
    int errors = 0, discarded = 0, maxBuffer = 0, latency = 0;
    int64_t random;
    vector<int> tx, first, delivery, acked, timers;
    vector<bool> marks;
    deque<int> queue;
    map<int, int> buffer;
    vector<Event> dataEvents, controlEvents;
    void emit(const string& side, const string& text) {
        if (side == "ALWAYS" || s.trace == "ALL" || s.trace == side) output.push_back(to_string(t) + " " + text);
    }
    int effective() const { return s.congestion ? min(s.w, cwnd) : s.w; }
    int outcome(const string& kind, int number) {
        int result = 0;
        if (s.random) {
            random = random * 48271LL % 2147483647LL;
            int v = int(random % 100);
            result = v < s.loss ? 1 : v < s.loss + s.corruption ? 2 : 0;
        }
        string suffix = kind == "data" ? "DATA" : "CTRL";
        if (s.contains("LOSE" + suffix, number)) result = 1;
        if (s.contains("CORRUPT" + suffix, number)) result = 2;
        return result;
    }
    void control(bool nak, int a) {
        int id = ++controlCount;
        if (nak) naks++;
        string kind = nak ? "nak" : "ack";
        emit("RECEIVER", string(nak ? "NAK" : "ACK") + " a=" + to_string(a) + " #" + to_string(id));
        controlEvents.push_back({t + s.delay + s.extra("DELAYCTRL", id), id, a, outcome(kind, id), kind});
    }
    void deliver(int payload) {
        if (payload == r) {
            emit("RECEIVER", "DELIVER f=" + to_string(r));
            if (delivery[payload] < 0) delivery[payload] = t;
            s.delivered++; latency += t - first[payload];
        } else {
            emit("RECEIVER", "DELIVER f=" + to_string(r) + " wrong=" + to_string(payload)); errors++;
        }
        r++; nakSent = false;
    }
    void discard(int seq) { discarded++; emit("RECEIVER", "DISCARD seq=" + to_string(seq)); }
    void receive(const Event& e) {
        int seq = e.value % M;
        emit("RECEIVER", "RECV seq=" + to_string(seq) + " #" + to_string(e.number));
        if (!sr) {
            if (seq == r % M) { deliver(e.value); control(false, seq); }
            else {
                discard(seq);
                if (s.nak && !nakSent) { control(true, r % M); nakSent = true; }
                else if (r > 0) control(false, (r - 1) % M);
            }
        } else {
            int offset = mod(seq - r, M);
            if (offset < s.w) {
                int position = r + offset;
                if (buffer.count(position)) { discard(seq); control(false, seq); }
                else if (offset == 0) {
                    deliver(e.value);
                    while (buffer.count(r)) { int payload = buffer[r]; buffer.erase(r); deliver(payload); }
                    control(false, seq);
                } else {
                    buffer[position] = e.value; maxBuffer = max(maxBuffer, int(buffer.size()));
                    emit("RECEIVER", "BUFFER f=" + to_string(position)); control(false, seq);
                    if (s.nak && !nakSent) { control(true, r % M); nakSent = true; }
                }
            } else {
                discard(seq);
                if (mod(r - seq, M) <= s.w) control(false, seq);
            }
        }
    }
    void goBack() { next = base; timer = -1; duplicates = 0; }
    void increase(int count) {
        if (!s.congestion) return;
        for (int i = 0; i < count && cwnd < s.w; i++) {
            if (cwnd < threshold) cwnd++;
            else if (++growth == cwnd) { cwnd++; growth = 0; }
        }
    }
    void decrease(bool timeout) {
        if (!s.congestion) return;
        threshold = max(cwnd / 2, 1); cwnd = timeout ? 1 : threshold; growth = 0;
    }
    void cwndLine(int oldC, int oldS) {
        if (s.congestion && (oldC != cwnd || oldS != threshold)) emit("SENDER", "CWND " + to_string(cwnd) + " ssthresh=" + to_string(threshold));
    }
    void acknowledge(const Event& e) {
        int oldC = cwnd, oldS = threshold, oldBase = base;
        int a = e.value, f = base + mod(a - base, M);
        bool nak = e.kind == "nak", accepted = false;
        if (sr) {
            if (f < high && !marks[f]) {
                accepted = true; timers[f] = -1;
                if (nak) { if (find(queue.begin(), queue.end(), f) == queue.end()) queue.push_back(f); }
                else {
                    marks[f] = true; if (acked[f] < 0) acked[f] = t;
                    queue.erase(remove(queue.begin(), queue.end(), f), queue.end());
                    while (base < high && marks[base]) base++;
                    increase(1);
                }
            }
        } else if (nak ? f <= high : f < high) {
            accepted = true; base = nak ? f : f + 1;
            increase(base - oldBase);
            for (int i = oldBase; i < base; i++) if (acked[i] < 0) acked[i] = t;
            if (nak) goBack();
            else if (next < base) next = base;
        }
        if (base > oldBase) { C = s.timeout; duplicates = 0; }
        if (accepted && !sr && !nak) timer = base == next ? -1 : t + C;
        string label = nak ? "NAK" : "ACK";
        emit("SENDER", string(accepted ? "GOT" : "OLD") + label + " a=" + to_string(a) + " #" + to_string(e.number) + (accepted ? " base=" + to_string(base) : ""));
        if (accepted && nak) decrease(false);
        if (!accepted && !nak && !sr && s.dupack > 0 && base >= 1 && a == (base - 1) % M) {
            duplicates++;
            if (duplicates == s.dupack) {
                fast++; emit("SENDER", "FASTRETX f=" + to_string(base)); goBack(); decrease(false);
            }
        }
        cwndLine(oldC, oldS);
    }
    void timeout(int f) {
        int oldC = cwnd, oldS = threshold;
        timeouts++; emit("SENDER", "TIMEOUT f=" + to_string(f));
        if (sr) { timers[f] = -1; queue.push_back(f); } else goBack();
        if (s.backoff) C = min(C * 2, 8 * s.timeout);
        decrease(true); cwndLine(oldC, oldS);
    }
    void send(int f) {
        int id = ++s.data;
        bool again = tx[f]++ > 0;
        if (again) resent++; else first[f] = t;
        emit("SENDER", string(again ? "RESEND" : "SEND") + " f=" + to_string(f) + " seq=" + to_string(f % M) + " #" + to_string(id));
        dataEvents.push_back({t + s.delay + s.extra("DELAYDATA", id), id, f, outcome("data", id), "data"});
    }
    void arrivals(vector<Event>& events, bool data) {
        vector<Event> ready;
        for (const Event& e : events) if (e.arrival == t) ready.push_back(e);
        events.erase(remove_if(events.begin(), events.end(), [&](const Event& e) { return e.arrival == t; }), events.end());
        sort(ready.begin(), ready.end(), [](const Event& a, const Event& b) { return a.number < b.number; });
        for (const Event& e : ready) {
            if (e.outcome != 0) {
                bool lost = e.outcome == 1;
                if (data) { if (lost) lostData++; else corruptData++; }
                else { if (lost) lostControl++; else corruptControl++; }
                emit(data ? "RECEIVER" : "SENDER", string(lost ? "LOST" : "CORRUPT") + " " + e.kind + " #" + to_string(e.number));
            } else if (data) receive(e); else acknowledge(e);
        }
    }
    void snapshot() {
        string x, y;
        for (int f = 0; f < s.n; f++) {
            bool ack = sr ? marks[f] : f < base;
            bool retransmit = sr ? find(queue.begin(), queue.end(), f) != queue.end() : next <= f && f < high;
            bool sent = sr ? f < high : f < next;
            x += ack ? 'A' : retransmit ? 'R' : sent ? 'O' : f < base + effective() ? 'W' : '.';
            y += f < r ? 'D' : sr && buffer.count(f) ? 'B' : (sr ? f < r + s.w : f == r) ? 'W' : '.';
        }
        emit("ALWAYS", "SNAPSHOT sender=" + x + " receiver=" + y);
    }
public:
    explicit Simulation(Scenario& scenario) : s(scenario), M(1 << s.k), C(s.timeout), sr(s.protocol == "SR"), threshold(s.w), random(s.seed), tx(s.n), first(s.n, -1), delivery(s.n, -1), acked(s.n, -1), timers(s.n, -1), marks(s.n) {}
    void run() {
        for (t = 0; t <= s.limit; t++) {
            arrivals(dataEvents, true); arrivals(controlEvents, false);
            bool done = base == s.n;
            if (!done) {
                if (sr) { for (int f = base; f < high; f++) if (timers[f] == t) timeout(f); }
                else if (timer == t) timeout(base);
                if (sr) {
                    int f = -1;
                    if (!queue.empty()) { f = queue.front(); queue.pop_front(); }
                    else if (high < s.n && high < base + effective() && high * s.interval <= t) f = high++;
                    if (f >= 0) { send(f); timers[f] = t + C; }
                } else if (next < s.n && next < base + effective() && (next < high || next * s.interval <= t)) {
                    send(next); high = max(high, ++next);
                    if (timer < 0) timer = t + C;
                }
            }
            if (s.contains("SNAPSHOT", t)) snapshot();
            if (done || t == s.limit) {
                s.end = t; if (done) s.completion = t;
                emit("ALWAYS", done ? "DONE" : "ABORT"); break;
            }
        }
        for (int f = 0; f < s.n; f++) output.push_back("frame " + to_string(f) + ": seq=" + to_string(f % M) + " tx=" + to_string(tx[f]) + " first=" + tickValue(first[f]) + " delivered=" + tickValue(delivery[f]) + " acked=" + tickValue(acked[f]));
        output.push_back("totals: data=" + to_string(s.data) + " resent=" + to_string(resent) + " control=" + to_string(controlCount) + " nak=" + to_string(naks) + " timeouts=" + to_string(timeouts) + " fastretx=" + to_string(fast));
        output.push_back("channel: lost_data=" + to_string(lostData) + " lost_ctrl=" + to_string(lostControl) + " corrupt_data=" + to_string(corruptData) + " corrupt_ctrl=" + to_string(corruptControl));
        output.push_back("receiver: delivered=" + to_string(s.delivered) + " errors=" + to_string(errors) + " discarded=" + to_string(discarded) + " max_buffer=" + to_string(maxBuffer));
        output.push_back("result: completion=" + tickValue(s.completion) + " goodput=" + (s.completion < 0 ? "-" : fixedValue(s.delivered, s.completion, 2)) + " efficiency=" + fixedValue(s.delivered * 100LL, s.data, 1) + "% utilization=" + fixedValue(s.data * 100LL, s.end + 1, 1) + "% latency=" + (s.delivered == 0 ? "-" : fixedValue(latency, s.delivered, 2)));
    }
};
int main() {
    int count;
    cin >> count;
    string line;
    getline(cin, line);
    vector<Scenario> scenarios;
    for (int q = 0; q < count; q++) {
        getline(cin, line);
        Scenario s; s.name = words(line)[1];
        while (getline(cin, line) && line != "END") s.line(words(line));
        s.check(); output.push_back("== " + s.name + " ==");
        if (!s.error.empty()) output.push_back("error: " + s.error);
        else {
            output.push_back("config: " + s.protocol + " n=" + to_string(s.n) + " w=" + to_string(s.w) + " k=" + to_string(s.k) + " T=" + to_string(s.timeout) + " d=" + to_string(s.delay));
            string trace = s.trace;
            transform(trace.begin(), trace.end(), trace.begin(), [](unsigned char c) { return char(tolower(c)); });
            output.push_back("options: interval=" + to_string(s.interval) + " limit=" + to_string(s.limit) + " dupack=" + (s.dupack == 0 ? "off" : to_string(s.dupack)) + " nak=" + onOff(s.nak) + " backoff=" + onOff(s.backoff) + " congestion=" + onOff(s.congestion) + " unsafe=" + onOff(s.unsafe) + " trace=" + trace + " random=" + (s.random ? to_string(s.seed) + "/" + to_string(s.loss) + "/" + to_string(s.corruption) : "off"));
            Simulation(s).run();
        }
        scenarios.push_back(s);
    }
    output.push_back("== ranking ==");
    vector<int> completed;
    for (int i = 0; i < int(scenarios.size()); i++) if (scenarios[i].completion >= 0) completed.push_back(i);
    stable_sort(completed.begin(), completed.end(), [&](int i, int j) {
        const Scenario& a = scenarios[i]; const Scenario& b = scenarios[j];
        int64_t left = int64_t(a.delivered) * b.completion, right = int64_t(b.delivered) * a.completion;
        if (left != right) return left > right;
        return int64_t(a.delivered) * b.data > int64_t(b.delivered) * a.data;
    });
    for (int i = 0; i < int(completed.size()); i++) {
        const Scenario& s = scenarios[completed[i]];
        output.push_back(to_string(i + 1) + ". " + s.name + " " + s.protocol + " goodput=" + fixedValue(s.delivered, s.completion, 2) + " efficiency=" + fixedValue(s.delivered * 100LL, s.data, 1) + "%");
    }
    for (const Scenario& s : scenarios) if (s.completion < 0) output.push_back("- " + s.name + (s.error.empty() ? " aborted" : " invalid"));
    output.push_back("== protocols ==");
    for (const string& p : {"SW", "GBN", "SR"}) {
        int runs = 0, d = 0, t = 0, x = 0;
        for (int i : completed) {
            const Scenario& s = scenarios[i];
            if (s.protocol == p) { runs++; d += s.delivered; t += s.completion; x += s.data; }
        }
        if (runs > 0) output.push_back(p + ": runs=" + to_string(runs) + " goodput=" + fixedValue(d, t, 2) + " efficiency=" + fixedValue(d * 100LL, x, 1) + "%");
    }
    for (const string& text : output) cout << text << '\n';
}
