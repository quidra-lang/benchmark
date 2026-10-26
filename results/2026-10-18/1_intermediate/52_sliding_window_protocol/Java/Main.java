import java.io.*;
import java.util.*;

public class Main {
    static final String[] KEYS = {
        "PROTOCOL",    "FRAMES",    "WINDOW",    "SEQBITS",  "TIMEOUT",  "DELAY",
        "INTERVAL",    "MAXTICKS",  "DUPACK",    "NAK",      "BACKOFF",  "CONGESTION",
        "UNSAFE",      "TRACE",     "RANDOM",    "LOSEDATA", "LOSECTRL", "CORRUPTDATA",
        "CORRUPTCTRL", "DELAYDATA", "DELAYCTRL", "SNAPSHOT"};
    static final List<String> output = new ArrayList<>();
    static String fixed(long numerator, long denominator, int digits) {
        long scale = digits == 2 ? 100 : 10;
        long v = denominator == 0 ? 0 : numerator * scale / denominator;
        return v / scale + "." + String.format(Locale.ROOT, "%0" + digits + "d", v % scale);
    }
    static int mod(int a, int b) {
        return Math.floorMod(a, b);
    }
    static String tick(int t) {
        return t < 0 ? "-" : Integer.toString(t);
    }
    static class Scenario {
        String name, protocol = "", error, trace = "ALL";
        Map<String, List<String>> values = new HashMap<>();
        int n, w, k, timeout, delay, interval = 0, limit = 1000, dupack = 0;
        boolean nak, backoff, congestion, unsafe, random;
        long seed;
        int loss, corruption;
        Map<String, Set<Integer>> lists = new HashMap<>();
        Map<String, Map<Integer, Integer>> delays = new HashMap<>();
        int completion = -1, end, delivered, data;
        Scenario(String name) {
            this.name = name;
        }
        int number(String key) {
            return Integer.parseInt(values.get(key).get(0));
        }
        boolean on(String key) {
            return values.containsKey(key) && values.get(key).get(0).equals("ON");
        }
        void line(String[] words) {
            if (error != null)
                return;
            String key = words[0];
            int position = Arrays.asList(KEYS).indexOf(key);
            if (position < 0) {
                error = "unknown key " + key;
                return;
            }
            if (values.containsKey(key)) {
                error = "duplicate key " + key;
                return;
            }
            int count = words.length - 1;
            if (key.equals("RANDOM") ? count != 3 : position >= 15 ? count < 1 : count != 1) {
                error = "wrong number of values for " + key;
                return;
            }
            values.put(key, Arrays.asList(words).subList(1, words.length));
        }
        boolean valid(String key) {
            List<String> v = values.get(key);
            if (key.equals("PROTOCOL"))
                return List.of("SW", "GBN", "SR").contains(v.get(0));
            if (List.of("NAK", "BACKOFF", "CONGESTION", "UNSAFE").contains(key))
                return List.of("ON", "OFF").contains(v.get(0));
            if (key.equals("TRACE"))
                return List.of("ALL", "SENDER", "RECEIVER", "NONE").contains(v.get(0));
            if (key.equals("RANDOM")) {
                long s = Long.parseLong(v.get(0));
                long p = Long.parseLong(v.get(1)), c = Long.parseLong(v.get(2));
                return s >= 1 && s <= 2147483646L && p >= 0 && c >= 0 && p + c <= 100;
            }
            int pos = Arrays.asList(KEYS).indexOf(key);
            if (pos >= 15) {
                Set<Integer> found = new HashSet<>();
                Map<Integer, Integer> extra = new HashMap<>();
                boolean delayed = key.startsWith("DELAY");
                for (String item : v) {
                    String[] pair = item.split(":");
                    int a = Integer.parseInt(pair[0]);
                    if (a < (key.equals("SNAPSHOT") ? 0 : 1) ||
                        a > (key.equals("SNAPSHOT") ? 2000 : 9999) || !found.add(a))
                        return false;
                    if (delayed) {
                        int e = Integer.parseInt(pair[1]);
                        if (e < 1 || e > 50)
                            return false;
                        extra.put(a, e);
                    }
                }
                lists.put(key, found);
                if (delayed)
                    delays.put(key, extra);
                return true;
            }
            int a = number(key), lo = 1, hi = 0;
            switch (key) {
            case "FRAMES":
                hi = 60;
                break;
            case "WINDOW":
                hi = 32;
                break;
            case "SEQBITS":
                hi = 6;
                break;
            case "TIMEOUT":
                hi = 50;
                break;
            case "DELAY", "DUPACK":
                hi = 10;
                break;
            case "INTERVAL":
                lo = 0;
                hi = 10;
                break;
            case "MAXTICKS":
                hi = 2000;
                break;
            }
            return a >= lo && a <= hi;
        }
        void check() {
            if (error != null)
                return;
            for (int i = 0; i < 6; i++)
                if (!values.containsKey(KEYS[i])) {
                    error = "missing key " + KEYS[i];
                    return;
                }
            for (String key : KEYS)
                if (values.containsKey(key) && !valid(key)) {
                    error = "bad value for " + key;
                    return;
                }
            protocol = values.get("PROTOCOL").get(0);
            n = number("FRAMES");
            w = number("WINDOW");
            k = number("SEQBITS");
            timeout = number("TIMEOUT");
            delay = number("DELAY");
            if (values.containsKey("INTERVAL"))
                interval = number("INTERVAL");
            if (values.containsKey("MAXTICKS"))
                limit = number("MAXTICKS");
            if (values.containsKey("DUPACK"))
                dupack = number("DUPACK");
            nak = on("NAK");
            backoff = on("BACKOFF");
            congestion = on("CONGESTION");
            unsafe = on("UNSAFE");
            if (values.containsKey("TRACE"))
                trace = values.get("TRACE").get(0);
            random = values.containsKey("RANDOM");
            if (random) {
                List<String> v = values.get("RANDOM");
                seed = Long.parseLong(v.get(0));
                loss = Integer.parseInt(v.get(1));
                corruption = Integer.parseInt(v.get(2));
            }
            if (protocol.equals("SR") && dupack != 0) {
                error = "DUPACK not supported for SR";
                return;
            }
            int upper = protocol.equals("SW")    ? 1
                        : protocol.equals("GBN") ? (1 << k) - 1
                                                 : 1 << (k - 1);
            if (w > upper && !(unsafe && !protocol.equals("SW"))) {
                error = "window " + w + " exceeds limit " + upper + " for " + protocol;
                return;
            }
            for (String kind : List.of("DATA", "CTRL")) {
                TreeSet<Integer> both = new TreeSet<>(lists.getOrDefault("LOSE" + kind, Set.of()));
                both.retainAll(lists.getOrDefault("CORRUPT" + kind, Set.of()));
                if (!both.isEmpty()) {
                    error = (kind.equals("DATA") ? "data" : "control") + " #" + both.first() +
                            " both lost and corrupted";
                    return;
                }
            }
        }
        boolean contains(String key, int i) {
            return lists.getOrDefault(key, Set.of()).contains(i);
        }
        int extra(String key, int i) {
            return delays.getOrDefault(key, Map.of()).getOrDefault(i, 0);
        }
    }
    record Event(int arrival, int number, int value, int outcome, String kind) {}
    static class Simulation {
        Scenario s;
        int t, M, base, high, next, timer = -1, C, duplicates, r;
        boolean sr, nakSent;
        int cwnd = 1, threshold, growth;
        int control, naks, resent, timeouts, fast, lostData, lostControl, corruptData,
            corruptControl;
        int errors, discarded, maxBuffer, latency;
        long random;
        int[] tx, first, delivery, acked, timers;
        boolean[] marks;
        List<Integer> queue = new ArrayList<>();
        Map<Integer, Integer> buffer = new HashMap<>();
        List<Event> dataEvents = new ArrayList<>(), controlEvents = new ArrayList<>();
        Simulation(Scenario s) {
            this.s = s;
            M = 1 << s.k;
            C = s.timeout;
            threshold = s.w;
            random = s.seed;
            sr = s.protocol.equals("SR");
            tx = new int[s.n];
            first = new int[s.n];
            delivery = new int[s.n];
            acked = new int[s.n];
            timers = new int[s.n];
            marks = new boolean[s.n];
            Arrays.fill(first, -1);
            Arrays.fill(delivery, -1);
            Arrays.fill(acked, -1);
            Arrays.fill(timers, -1);
        }
        void emit(String side, String text) {
            if (side.equals("ALWAYS") || s.trace.equals("ALL") || s.trace.equals(side))
                output.add(t + " " + text);
        }
        int effective() {
            return s.congestion ? Math.min(s.w, cwnd) : s.w;
        }
        int outcome(String kind, int number) {
            int result = 0;
            if (s.random) {
                random = random * 48271L % 2147483647L;
                int v = (int)(random % 100);
                result = v < s.loss ? 1 : v < s.loss + s.corruption ? 2 : 0;
            }
            String suffix = kind.equals("data") ? "DATA" : "CTRL";
            if (s.contains("LOSE" + suffix, number))
                result = 1;
            if (s.contains("CORRUPT" + suffix, number))
                result = 2;
            return result;
        }
        void control(boolean nak, int a) {
            int id = ++control;
            if (nak)
                naks++;
            String kind = nak ? "nak" : "ack";
            emit("RECEIVER", kind.toUpperCase(Locale.ROOT) + " a=" + a + " #" + id);
            controlEvents.add(
                new Event(t + s.delay + s.extra("DELAYCTRL", id), id, a, outcome(kind, id), kind));
        }
        void deliver(int payload) {
            if (payload == r) {
                emit("RECEIVER", "DELIVER f=" + r);
                if (delivery[payload] < 0)
                    delivery[payload] = t;
                s.delivered++;
                latency += t - first[payload];
            } else {
                emit("RECEIVER", "DELIVER f=" + r + " wrong=" + payload);
                errors++;
            }
            r++;
            nakSent = false;
        }
        void discard(int seq) {
            discarded++;
            emit("RECEIVER", "DISCARD seq=" + seq);
        }
        void receive(Event e) {
            int seq = e.value() % M;
            emit("RECEIVER", "RECV seq=" + seq + " #" + e.number());
            if (!sr) {
                if (seq == r % M) {
                    deliver(e.value());
                    control(false, seq);
                } else {
                    discard(seq);
                    if (s.nak && !nakSent) {
                        control(true, r % M);
                        nakSent = true;
                    } else if (r > 0)
                        control(false, (r - 1) % M);
                }
            } else {
                int offset = mod(seq - r, M);
                if (offset < s.w) {
                    int position = r + offset;
                    if (buffer.containsKey(position)) {
                        discard(seq);
                        control(false, seq);
                    } else if (offset == 0) {
                        deliver(e.value());
                        while (buffer.containsKey(r))
                            deliver(buffer.remove(r));
                        control(false, seq);
                    } else {
                        buffer.put(position, e.value());
                        maxBuffer = Math.max(maxBuffer, buffer.size());
                        emit("RECEIVER", "BUFFER f=" + position);
                        control(false, seq);
                        if (s.nak && !nakSent) {
                            control(true, r % M);
                            nakSent = true;
                        }
                    }
                } else {
                    discard(seq);
                    if (mod(r - seq, M) <= s.w)
                        control(false, seq);
                }
            }
        }
        void goBack() {
            next = base;
            timer = -1;
            duplicates = 0;
        }
        void increase(int count) {
            if (!s.congestion)
                return;
            for (int i = 0; i < count && cwnd < s.w; i++) {
                if (cwnd < threshold)
                    cwnd++;
                else if (++growth == cwnd) {
                    cwnd++;
                    growth = 0;
                }
            }
        }
        void decrease(boolean timeout) {
            if (!s.congestion)
                return;
            threshold = Math.max(cwnd / 2, 1);
            cwnd = timeout ? 1 : threshold;
            growth = 0;
        }
        void cwndLine(int oldC, int oldS) {
            if (s.congestion && (oldC != cwnd || oldS != threshold))
                emit("SENDER", "CWND " + cwnd + " ssthresh=" + threshold);
        }
        void acknowledge(Event e) {
            int oldC = cwnd, oldS = threshold, oldBase = base;
            int a = e.value(), f = base + mod(a - base, M);
            boolean nak = e.kind().equals("nak"), accepted = false;
            if (sr) {
                if (f < high && !marks[f]) {
                    accepted = true;
                    timers[f] = -1;
                    if (nak) {
                        if (!queue.contains(f))
                            queue.add(f);
                    } else {
                        marks[f] = true;
                        if (acked[f] < 0)
                            acked[f] = t;
                        queue.remove(Integer.valueOf(f));
                        while (base < high && marks[base])
                            base++;
                        increase(1);
                    }
                }
            } else if (nak ? f <= high : f < high) {
                accepted = true;
                base = nak ? f : f + 1;
                increase(base - oldBase);
                for (int i = oldBase; i < base; i++)
                    if (acked[i] < 0)
                        acked[i] = t;
                if (nak)
                    goBack();
                else if (next < base)
                    next = base;
            }
            if (base > oldBase) {
                C = s.timeout;
                duplicates = 0;
            }
            if (accepted && !sr && !nak)
                timer = base == next ? -1 : t + C;
            String label = nak ? "NAK" : "ACK";
            emit("SENDER", (accepted ? "GOT" : "OLD") + label + " a=" + a + " #" + e.number() +
                               (accepted ? " base=" + base : ""));
            if (accepted && nak)
                decrease(false);
            if (!accepted && !nak && !sr && s.dupack > 0 && base >= 1 && a == (base - 1) % M) {
                duplicates++;
                if (duplicates == s.dupack) {
                    fast++;
                    emit("SENDER", "FASTRETX f=" + base);
                    goBack();
                    decrease(false);
                }
            }
            cwndLine(oldC, oldS);
        }
        void timeout(int f) {
            int oldC = cwnd, oldS = threshold;
            timeouts++;
            emit("SENDER", "TIMEOUT f=" + f);
            if (sr) {
                timers[f] = -1;
                queue.add(f);
            } else
                goBack();
            if (s.backoff)
                C = Math.min(C * 2, 8 * s.timeout);
            decrease(true);
            cwndLine(oldC, oldS);
        }
        void send(int f) {
            int id = ++s.data;
            boolean again = tx[f]++ > 0;
            if (again)
                resent++;
            else
                first[f] = t;
            emit("SENDER", (again ? "RESEND" : "SEND") + " f=" + f + " seq=" + f % M + " #" + id);
            dataEvents.add(new Event(t + s.delay + s.extra("DELAYDATA", id), id, f,
                                     outcome("data", id), "data"));
        }
        void arrivals(List<Event> events, boolean data) {
            List<Event> ready = events.stream()
                                    .filter(e -> e.arrival() == t)
                                    .sorted(Comparator.comparingInt(Event::number))
                                    .toList();
            events.removeAll(ready);
            for (Event e : ready) {
                if (e.outcome() != 0) {
                    boolean lost = e.outcome() == 1;
                    if (data) {
                        if (lost)
                            lostData++;
                        else
                            corruptData++;
                    } else {
                        if (lost)
                            lostControl++;
                        else
                            corruptControl++;
                    }
                    emit(data ? "RECEIVER" : "SENDER",
                         (lost ? "LOST" : "CORRUPT") + " " + e.kind() + " #" + e.number());
                } else if (data)
                    receive(e);
                else
                    acknowledge(e);
            }
        }
        void snapshot() {
            StringBuilder x = new StringBuilder(), y = new StringBuilder();
            for (int f = 0; f < s.n; f++) {
                boolean ack = sr ? marks[f] : f < base;
                boolean retransmit = sr ? queue.contains(f) : next <= f && f < high;
                boolean sent = sr ? f < high : f < next;
                x.append(ack                      ? 'A'
                         : retransmit             ? 'R'
                         : sent                   ? 'O'
                         : f < base + effective() ? 'W'
                                                  : '.');
                y.append(f < r                         ? 'D'
                         : sr && buffer.containsKey(f) ? 'B'
                         : (sr ? f < r + s.w : f == r) ? 'W'
                                                       : '.');
            }
            emit("ALWAYS", "SNAPSHOT sender=" + x + " receiver=" + y);
        }
        void run() {
            for (t = 0; t <= s.limit; t++) {
                arrivals(dataEvents, true);
                arrivals(controlEvents, false);
                boolean done = base == s.n;
                if (!done) {
                    if (sr) {
                        for (int f = base; f < high; f++)
                            if (timers[f] == t)
                                timeout(f);
                    } else if (timer == t)
                        timeout(base);
                    if (sr) {
                        int f = -1;
                        if (!queue.isEmpty())
                            f = queue.remove(0);
                        else if (high < s.n && high < base + effective() && high * s.interval <= t)
                            f = high++;
                        if (f >= 0) {
                            send(f);
                            timers[f] = t + C;
                        }
                    } else if (next < s.n && next < base + effective() &&
                               (next < high || next * s.interval <= t)) {
                        send(next);
                        high = Math.max(high, ++next);
                        if (timer < 0)
                            timer = t + C;
                    }
                }
                if (s.contains("SNAPSHOT", t))
                    snapshot();
                if (done || t == s.limit) {
                    s.end = t;
                    if (done)
                        s.completion = t;
                    emit("ALWAYS", done ? "DONE" : "ABORT");
                    break;
                }
            }
            for (int f = 0; f < s.n; f++)
                output.add("frame " + f + ": seq=" + f % M + " tx=" + tx[f] +
                           " first=" + tick(first[f]) + " delivered=" + tick(delivery[f]) +
                           " acked=" + tick(acked[f]));
            output.add("totals: data=" + s.data + " resent=" + resent + " control=" + control +
                       " nak=" + naks + " timeouts=" + timeouts + " fastretx=" + fast);
            output.add("channel: lost_data=" + lostData + " lost_ctrl=" + lostControl +
                       " corrupt_data=" + corruptData + " corrupt_ctrl=" + corruptControl);
            output.add("receiver: delivered=" + s.delivered + " errors=" + errors +
                       " discarded=" + discarded + " max_buffer=" + maxBuffer);
            output.add("result: completion=" + tick(s.completion) + " goodput=" +
                       (s.completion < 0 ? "-" : fixed(s.delivered, s.completion, 2)) +
                       " efficiency=" + fixed(s.delivered * 100L, s.data, 1) +
                       "% utilization=" + fixed(s.data * 100L, s.end + 1, 1) +
                       "% latency=" + (s.delivered == 0 ? "-" : fixed(latency, s.delivered, 2)));
        }
    }
    public static void main(String[] args) throws Exception {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in));
        int count = Integer.parseInt(input.readLine());
        List<Scenario> scenarios = new ArrayList<>();
        for (int q = 0; q < count; q++) {
            Scenario s = new Scenario(input.readLine().split(" ")[1]);
            String line;
            while (!(line = input.readLine()).equals("END"))
                s.line(line.split(" "));
            s.check();
            scenarios.add(s);
            output.add("== " + s.name + " ==");
            if (s.error != null) {
                output.add("error: " + s.error);
                continue;
            }
            output.add("config: " + s.protocol + " n=" + s.n + " w=" + s.w + " k=" + s.k +
                       " T=" + s.timeout + " d=" + s.delay);
            output.add("options: interval=" + s.interval + " limit=" + s.limit +
                       " dupack=" + (s.dupack == 0 ? "off" : s.dupack) +
                       " nak=" + (s.nak ? "on" : "off") + " backoff=" + (s.backoff ? "on" : "off") +
                       " congestion=" + (s.congestion ? "on" : "off") +
                       " unsafe=" + (s.unsafe ? "on" : "off") +
                       " trace=" + s.trace.toLowerCase(Locale.ROOT) + " random=" +
                       (s.random ? s.seed + "/" + s.loss + "/" + s.corruption : "off"));
            new Simulation(s).run();
        }
        output.add("== ranking ==");
        List<Scenario> completed =
            new ArrayList<>(scenarios.stream().filter(s -> s.completion >= 0).toList());
        completed.sort((a, b) -> {
            int c =
                Long.compare((long)b.delivered * a.completion, (long)a.delivered * b.completion);
            return c != 0 ? c
                          : Long.compare((long)b.delivered * a.data, (long)a.delivered * b.data);
        });
        for (int i = 0; i < completed.size(); i++) {
            Scenario s = completed.get(i);
            output.add((i + 1) + ". " + s.name + " " + s.protocol +
                       " goodput=" + fixed(s.delivered, s.completion, 2) +
                       " efficiency=" + fixed(s.delivered * 100L, s.data, 1) + "%");
        }
        for (Scenario s : scenarios)
            if (s.completion < 0)
                output.add("- " + s.name + (s.error != null ? " invalid" : " aborted"));
        output.add("== protocols ==");
        for (String p : List.of("SW", "GBN", "SR")) {
            int runs = 0, d = 0, t = 0, x = 0;
            for (Scenario s : completed)
                if (s.protocol.equals(p)) {
                    runs++;
                    d += s.delivered;
                    t += s.completion;
                    x += s.data;
                }
            if (runs > 0)
                output.add(p + ": runs=" + runs + " goodput=" + fixed(d, t, 2) +
                           " efficiency=" + fixed(d * 100L, x, 1) + "%");
        }
        System.out.print(String.join("\n", output) + "\n");
    }
}
