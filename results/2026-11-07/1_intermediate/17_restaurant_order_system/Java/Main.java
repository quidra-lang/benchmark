import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Comparator;
import java.util.Deque;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.StringJoiner;
import java.util.TreeMap;

public final class Main {
    private static final List<String> STATIONS = List.of("GRILL", "FRY", "COLD", "BAR");
    private static final List<String> COURSES = List.of("DRINK", "STARTER", "MAIN", "DESSERT");

    private static long cents(String amount) {
        int point = amount.indexOf('.');
        return Long.parseLong(amount.substring(0, point)) * 100
                + Long.parseLong(amount.substring(point + 1));
    }

    private static String money(long amount) {
        return amount / 100 + "." + String.format(Locale.ROOT, "%02d", amount % 100);
    }

    private static String clock(int elapsed) {
        int minutes = elapsed + 660;
        return String.format(Locale.ROOT, "%02d:%02d", minutes / 60, minutes % 60);
    }

    private static long rounded(long amount, int rate) {
        return (amount * rate + 50) / 100;
    }

    private static final class CommandError extends RuntimeException {
        CommandError(String message) {
            super(message);
        }
    }

    private static final class Table {
        final int number;
        final int seats;
        Check check;

        Table(int number, int seats) {
            this.number = number;
            this.seats = seats;
        }
    }

    private static final class Server {
        final String name;
        int load;
        int parties;
        long sales;
        long tips;

        Server(String name) {
            this.name = name;
        }
    }

    private static final class MenuItem {
        final String name;
        String station;
        int prep;
        long price;
        String course;
        Integer stock;

        MenuItem(String name, String station, int prep, long price, String course) {
            this.name = name;
            this.station = station;
            this.prep = prep;
            this.price = price;
            this.course = course;
        }
    }

    private static final class Check {
        final String party;
        final int size;
        Table table;
        final Server server;
        final int since;
        final List<OrderLine> lines = new ArrayList<>();
        long paid;
        int discount;
        boolean closed;

        Check(String party, int size, Table table, Server server, int since) {
            this.party = party;
            this.size = size;
            this.table = table;
            this.server = server;
            this.since = since;
        }

        List<OrderLine> active() {
            List<OrderLine> selected = new ArrayList<>();
            for (OrderLine line : lines) {
                if (!line.state.equals("VOID")) {
                    selected.add(line);
                }
            }
            return selected;
        }

        long[] amounts() {
            long subtotal = 0;
            for (OrderLine line : lines) {
                if (!line.state.equals("VOID")) {
                    subtotal += line.amount();
                }
            }
            long discountAmount = rounded(subtotal, discount);
            long afterDiscount = subtotal - discountAmount;
            long service = size >= 6 ? rounded(afterDiscount, 18) : 0;
            long tax = rounded(afterDiscount, 8);
            long total = afterDiscount + service + tax;
            return new long[]{subtotal, discountAmount, service, tax, total, total - paid};
        }
    }

    private static final class OrderLine {
        final int number;
        final Check check;
        int seat;
        final String name;
        final int quantity;
        final String station;
        final int prep;
        final long price;
        final String course;
        String state = "ORDERED";
        String comp;
        int fire;
        int ready;
        boolean started;

        OrderLine(int number, Check check, int seat, MenuItem item, int quantity, long price) {
            this.number = number;
            this.check = check;
            this.seat = seat;
            this.name = item.name;
            this.quantity = quantity;
            this.station = item.station;
            this.prep = item.prep;
            this.price = price;
            this.course = item.course;
        }

        long amount() {
            return comp == null ? price * quantity : 0;
        }

        String tag() {
            return "#" + number;
        }
    }

    private static final class Station {
        final String name;
        final int capacity;
        boolean up = true;
        final Deque<OrderLine> queue = new ArrayDeque<>();
        final List<OrderLine> cooking = new ArrayList<>();
        int tickets;
        long ticketTotal;
        int ticketMax;
        int remakes;

        Station(String name) {
            this.name = name;
            this.capacity = name.equals("BAR") ? 2 : 1;
        }
    }

    private static final class Waiting {
        final String party;
        final int size;
        final int joined;

        Waiting(String party, int size, int joined) {
            this.party = party;
            this.size = size;
            this.joined = joined;
        }
    }

    private static final class Restaurant {
        private int time;
        private final Map<Integer, Table> tables = new TreeMap<>();
        private final List<Server> servers = new ArrayList<>();
        private final Set<String> serverNames = new HashSet<>();
        private List<Waiting> waiting = new ArrayList<>();
        private final Map<String, Check> seated = new HashMap<>();
        private final Map<String, MenuItem> menu = new HashMap<>();
        private final List<OrderLine> lines = new ArrayList<>();
        private final Map<String, Station> stations = new LinkedHashMap<>();
        private int happyRate;
        private Integer happyUntil;
        private int guests;
        private int parties;
        private int closed;
        private long stayTotal;
        private final long[] sales = new long[4];
        private final long[] totals = new long[5];
        private final Map<String, Long> payments = new HashMap<>();
        private long tips;
        private int comps;
        private long compAmount;
        private int voids;
        private final Map<String, Long> served = new HashMap<>();
        private final List<String> output = new ArrayList<>();

        Restaurant() {
            for (String name : STATIONS) {
                stations.put(name, new Station(name));
            }
            payments.put("CASH", 0L);
            payments.put("CARD", 0L);
        }

        private void emit(Object... parts) {
            StringJoiner joiner = new StringJoiner(" ");
            for (Object part : parts) {
                joiner.add(String.valueOf(part));
            }
            output.add(joiner.toString());
        }

        private static void fail(String message) {
            throw new CommandError(message);
        }

        private Table table(String text, boolean occupied) {
            Table table = tables.get(Integer.parseInt(text));
            if (table == null) {
                fail("unknown table " + text);
            }
            if (occupied && table.check == null) {
                fail("table " + text + " is free");
            }
            return table;
        }

        private OrderLine line(String text) {
            int number = Integer.parseInt(text);
            if (number < 1 || number > lines.size()) {
                fail("unknown line " + text);
            }
            return lines.get(number - 1);
        }

        private void unlocked(Check check) {
            if (check.paid != 0) {
                fail("check for table " + check.table.number + " is locked");
            }
        }

        private void modification(OrderLine order) {
            if (order.state.equals("VOID")) {
                fail(order.tag() + " is void");
            }
            if (order.check.closed) {
                fail(order.tag() + " is on a closed check");
            }
            unlocked(order.check);
        }

        private void allServed(Check check) {
            int count = 0;
            for (OrderLine line : check.lines) {
                if (!line.state.equals("VOID") && !line.state.equals("SERVED")) {
                    count++;
                }
            }
            if (count != 0) {
                fail("table " + check.table.number + " has " + count + " unserved items");
            }
        }

        private Table selectTable(int size) {
            Table best = null;
            for (Table table : tables.values()) {
                if (table.check == null && table.seats >= size &&
                        (best == null || table.seats < best.seats ||
                         (table.seats == best.seats && table.number < best.number))) {
                    best = table;
                }
            }
            return best;
        }

        private Check seatParty(String party, int size, Table table) {
            Server server = null;
            for (Server candidate : servers) {
                if (server == null || candidate.load < server.load) {
                    server = candidate;
                }
            }
            Check check = new Check(party, size, table, server, time);
            table.check = check;
            seated.put(party, check);
            server.load++;
            server.parties++;
            guests += size;
            parties++;
            return check;
        }

        private void processWaitlist() {
            List<Waiting> remaining = new ArrayList<>();
            for (Waiting entry : waiting) {
                Table table = selectTable(entry.size);
                if (table == null) {
                    remaining.add(entry);
                } else {
                    Check check = seatParty(entry.party, entry.size, table);
                    emit("SEATED", entry.party, entry.size, "table", table.number,
                         "server", check.server.name, "waited", time - entry.joined);
                }
            }
            waiting = remaining;
        }

        private void closeCheck(Check check) {
            long[] amounts = check.amounts();
            for (OrderLine line : check.active()) {
                sales[COURSES.indexOf(line.course)] += line.amount();
            }
            for (int i = 0; i < totals.length; i++) {
                totals[i] += amounts[i];
            }
            int stayed = time - check.since;
            closed++;
            stayTotal += stayed;
            check.server.sales += amounts[4];
            check.server.load--;
            check.closed = true;
            check.table.check = null;
            seated.remove(check.party);
            emit("FREE", "table", check.table.number, check.party, "stayed", stayed);
            processWaitlist();
        }

        private void startStation(String name, int at) {
            Station station = stations.get(name);
            while (station.up && !station.queue.isEmpty() &&
                   station.cooking.size() < station.capacity) {
                OrderLine line = station.queue.removeFirst();
                line.state = "COOKING";
                line.started = true;
                line.ready = at + line.prep;
                station.cooking.add(line);
            }
        }

        private void startAll(int at) {
            for (String name : STATIONS) {
                startStation(name, at);
            }
        }

        private Map<Integer, Long> seatSubtotals(Check check) {
            Map<Integer, Long> values = new TreeMap<>();
            for (OrderLine line : check.active()) {
                values.merge(line.seat, line.amount(), Long::sum);
            }
            return values;
        }

        private Map<Integer, Long> allocate(Map<Integer, Long> values, int rate) {
            Map<Integer, Long> amounts = new TreeMap<>();
            long sum = 0;
            long total = 0;
            List<Integer> ranking = new ArrayList<>(values.keySet());
            for (Map.Entry<Integer, Long> entry : values.entrySet()) {
                long subtotal = entry.getValue();
                long truncated = subtotal * rate / 100;
                amounts.put(entry.getKey(), truncated);
                sum += subtotal;
                total += truncated;
            }
            ranking.sort((a, b) -> {
                long left = values.get(a) * rate % 100;
                long right = values.get(b) * rate % 100;
                return left != right ? Long.compare(right, left) : Integer.compare(a, b);
            });
            long extra = rounded(sum, rate) - total;
            for (int i = 0; i < extra; i++) {
                int seat = ranking.get(i);
                amounts.put(seat, amounts.get(seat) + 1);
            }
            return amounts;
        }

        private void cmdTable(String[] a) {
            int number = Integer.parseInt(a[0]);
            int seats = Integer.parseInt(a[1]);
            if (tables.containsKey(number)) {
                fail("table " + number + " already exists");
            }
            tables.put(number, new Table(number, seats));
            emit("TABLE", number, "seats", seats);
            processWaitlist();
        }

        private void cmdStaff(String[] a) {
            if (!serverNames.add(a[0])) {
                fail(a[0] + " is already on duty");
            }
            servers.add(new Server(a[0]));
            emit("STAFF", a[0]);
        }

        private void cmdSeat(String[] a) {
            String party = a[0];
            int size = Integer.parseInt(a[1]);
            Check existing = seated.get(party);
            if (existing != null) {
                fail(party + " is already seated at table " + existing.table.number);
            }
            for (Waiting entry : waiting) {
                if (entry.party.equals(party)) {
                    fail(party + " is already waiting");
                }
            }
            boolean capacity = false;
            for (Table table : tables.values()) {
                if (table.seats >= size) {
                    capacity = true;
                }
            }
            if (!capacity) {
                fail("no table for party of " + size);
            }
            if (servers.isEmpty()) {
                fail("no server on duty");
            }
            Table table = selectTable(size);
            if (table == null) {
                waiting.add(new Waiting(party, size, time));
                emit("WAIT", party, size, "position", waiting.size());
            } else {
                Check check = seatParty(party, size, table);
                emit("SEAT", party, size, "table", table.number, "server", check.server.name);
            }
        }

        private void cmdCancel(String[] a) {
            for (int i = 0; i < waiting.size(); i++) {
                Waiting entry = waiting.get(i);
                if (entry.party.equals(a[0])) {
                    waiting.remove(i);
                    emit("CANCEL", entry.party, entry.size, "waited", time - entry.joined);
                    return;
                }
            }
            fail(a[0] + " is not waiting");
        }

        private void cmdMove(String[] a) {
            Table source = table(a[0], false);
            Table destination = table(a[1], false);
            if (source.check == null) {
                fail("table " + a[0] + " is free");
            }
            if (destination.check != null) {
                fail("table " + a[1] + " is occupied");
            }
            Check check = source.check;
            if (destination.seats < check.size) {
                fail("table " + a[1] + " is too small for " + check.party);
            }
            source.check = null;
            destination.check = check;
            check.table = destination;
            emit("MOVE", check.party, "table", a[0], "->", a[1]);
            processWaitlist();
        }

        private void cmdMenu(String[] a) {
            if (!STATIONS.contains(a[1])) {
                fail("unknown station " + a[1]);
            }
            if (!COURSES.contains(a[4])) {
                fail("unknown course " + a[4]);
            }
            MenuItem item = menu.get(a[0]);
            String action = item == null ? "ADD" : "UPDATE";
            if (item == null) {
                item = new MenuItem(a[0], a[1], Integer.parseInt(a[2]), cents(a[3]), a[4]);
                menu.put(a[0], item);
            } else {
                item.station = a[1];
                item.prep = Integer.parseInt(a[2]);
                item.price = cents(a[3]);
                item.course = a[4];
            }
            emit("MENU", action, a[0], a[1], a[2], a[3], a[4]);
        }

        private void cmdStock(String[] a) {
            MenuItem item = menu.get(a[0]);
            if (item == null) {
                fail("unknown item " + a[0]);
            }
            item.stock = Integer.parseInt(a[1]);
            emit("STOCK", a[0], a[1]);
        }

        private void cmdHappy(String[] a) {
            happyRate = Integer.parseInt(a[0]);
            happyUntil = time + Integer.parseInt(a[1]);
            emit("HAPPY", a[0] + "%", "until", clock(happyUntil));
        }

        private void cmdItems(String[] a) {
            emit("ITEMS", menu.size());
            List<MenuItem> items = new ArrayList<>(menu.values());
            items.sort(Comparator.comparingInt((MenuItem item) -> COURSES.indexOf(item.course))
                                 .thenComparing(item -> item.name));
            for (MenuItem item : items) {
                emit(item.course, item.name, item.station, item.prep, money(item.price),
                     item.stock == null ? "-" : item.stock);
            }
        }

        private void cmdOrder(String[] a) {
            Check check = table(a[0], true).check;
            unlocked(check);
            int seat = Integer.parseInt(a[1]);
            int quantity = Integer.parseInt(a[3]);
            if (seat > check.size) {
                fail("seat " + a[1] + " out of range for table " + a[0]);
            }
            MenuItem item = menu.get(a[2]);
            if (item == null) {
                fail("unknown item " + a[2]);
            }
            if (item.stock != null && item.stock < quantity) {
                fail("only " + item.stock + " " + item.name + " left");
            }
            boolean happy = item.course.equals("DRINK") && happyUntil != null && time < happyUntil;
            long price = item.price - (happy ? rounded(item.price, happyRate) : 0);
            OrderLine order = new OrderLine(lines.size() + 1, check, seat, item, quantity, price);
            lines.add(order);
            check.lines.add(order);
            String result = "ORDER " + order.tag() + " table " + a[0] + " seat " + a[1] +
                            " " + item.name + " x" + quantity + " " + money(order.amount());
            if (happy) {
                result += " HAPPY";
            }
            emit(result);
            if (item.stock != null) {
                item.stock -= quantity;
                if (item.stock == 0) {
                    emit("SOLDOUT", item.name);
                }
            }
        }

        private void cmdFire(String[] a) {
            Check check = table(a[0], true).check;
            if (!COURSES.contains(a[1])) {
                fail("unknown course " + a[1]);
            }
            List<OrderLine> selected = new ArrayList<>();
            for (OrderLine line : check.lines) {
                if (line.course.equals(a[1]) && line.state.equals("ORDERED")) {
                    selected.add(line);
                }
            }
            if (selected.isEmpty()) {
                fail("nothing to fire for " + a[1] + " at table " + a[0]);
            }
            int index = COURSES.indexOf(a[1]);
            if (index >= 2) {
                for (int earlier = 1; earlier < index; earlier++) {
                    for (OrderLine line : check.lines) {
                        if (line.course.equals(COURSES.get(earlier)) &&
                            line.state.equals("ORDERED")) {
                            fail("fire " + COURSES.get(earlier) + " first");
                        }
                    }
                }
            }
            StringBuilder result = new StringBuilder("FIRE table " + a[0] + " " + a[1]);
            for (OrderLine line : selected) {
                line.state = "QUEUED";
                line.fire = time;
                stations.get(line.station).queue.addLast(line);
                result.append(" ").append(line.tag());
            }
            emit(result.toString());
            startAll(time);
        }

        private void cmdTick(String[] a) {
            int target = time + Integer.parseInt(a[0]);
            emit("TICK", clock(target));
            while (true) {
                Integer next = null;
                for (Station station : stations.values()) {
                    for (OrderLine line : station.cooking) {
                        if (next == null || line.ready < next) {
                            next = line.ready;
                        }
                    }
                }
                if (next == null || next > target) {
                    break;
                }
                int completion = next;
                for (String name : STATIONS) {
                    Station station = stations.get(name);
                    List<OrderLine> finished = new ArrayList<>();
                    for (OrderLine line : station.cooking) {
                        if (line.ready == completion) {
                            finished.add(line);
                        }
                    }
                    finished.sort(Comparator.comparingInt(line -> line.number));
                    for (OrderLine line : finished) {
                        station.cooking.remove(line);
                        line.state = "READY";
                        int ticket = completion - line.fire;
                        station.tickets++;
                        station.ticketTotal += ticket;
                        station.ticketMax = Math.max(station.ticketMax, ticket);
                        emit("READY", clock(completion), name, line.tag(), line.name,
                             "x" + line.quantity, "table", line.check.table.number,
                             "seat", line.seat);
                    }
                }
                startAll(completion);
            }
            time = target;
        }

        private void cmdServe(String[] a) {
            Check check = table(a[0], true).check;
            List<OrderLine> selected = new ArrayList<>();
            for (OrderLine line : check.lines) {
                if (line.state.equals("READY")) {
                    selected.add(line);
                }
            }
            if (selected.isEmpty()) {
                fail("nothing ready for table " + a[0]);
            }
            StringBuilder result = new StringBuilder("SERVE table " + a[0]);
            for (OrderLine line : selected) {
                line.state = "SERVED";
                served.merge(line.name, (long) line.quantity, Long::sum);
                result.append(" ").append(line.tag());
            }
            emit(result.toString());
        }

        private void cmdRush(String[] a) {
            OrderLine line = line(a[0]);
            if (!line.state.equals("QUEUED")) {
                fail(line.tag() + " is not queued");
            }
            Station station = stations.get(line.station);
            station.queue.remove(line);
            station.queue.addFirst(line);
            emit("RUSH", line.tag(), line.station);
        }

        private void cmdRemake(String[] a) {
            OrderLine line = line(a[0]);
            if (line.check.closed) {
                fail(line.tag() + " is on a closed check");
            }
            if (!line.state.equals("READY") && !line.state.equals("SERVED")) {
                fail(line.tag() + " is not ready or served");
            }
            Station station = stations.get(line.station);
            line.state = "QUEUED";
            line.fire = time;
            station.queue.addFirst(line);
            station.remakes++;
            emit("REMAKE", line.tag(), line.name, line.station);
            startStation(line.station, time);
        }

        private void cmdVoid(String[] a) {
            OrderLine line = line(a[0]);
            if (line.state.equals("VOID")) {
                fail(line.tag() + " is already void");
            }
            if (line.started) {
                fail(line.tag() + " has already started");
            }
            if (line.state.equals("QUEUED")) {
                stations.get(line.station).queue.remove(line);
            }
            line.state = "VOID";
            MenuItem item = menu.get(line.name);
            if (item.stock != null) {
                item.stock += line.quantity;
            }
            voids++;
            emit("VOID", line.tag(), line.name, "x" + line.quantity);
        }

        private void cmdStation(String[] a) {
            Station station = stations.get(a[0]);
            if (station == null) {
                fail("unknown station " + a[0]);
            }
            if (a[1].equals("DOWN") && !station.up) {
                fail("station " + a[0] + " is already down");
            }
            if (a[1].equals("UP") && station.up) {
                fail("station " + a[0] + " is not down");
            }
            station.up = a[1].equals("UP");
            if (station.up) {
                startStation(a[0], time);
            }
            emit("STATION", a[0], a[1]);
        }

        private void cmdComp(String[] a) {
            OrderLine line = line(a[0]);
            modification(line);
            if (line.comp != null) {
                fail(line.tag() + " is already comped");
            }
            long amount = line.amount();
            emit("COMP", line.tag(), line.name, money(amount), a[1]);
            comps++;
            compAmount += amount;
            line.comp = a[1];
        }

        private void cmdTransfer(String[] a) {
            OrderLine line = line(a[0]);
            modification(line);
            int seat = Integer.parseInt(a[1]);
            if (seat > line.check.size) {
                fail("seat " + seat + " out of range for table " + line.check.table.number);
            }
            if (seat == line.seat) {
                fail(line.tag() + " is already on seat " + seat);
            }
            emit("TRANSFER", line.tag(), "seat", line.seat, "->", seat);
            line.seat = seat;
        }

        private void cmdDiscount(String[] a) {
            Check check = table(a[0], true).check;
            unlocked(check);
            check.discount = Integer.parseInt(a[1]);
            emit("DISCOUNT", "table", a[0], a[1] + "%");
        }

        private void cmdBill(String[] a) {
            Check check = table(a[0], true).check;
            emit("BILL", "table", a[0], check.party, "guests", check.size);
            Map<Integer, Long> subtotals = seatSubtotals(check);
            for (Map.Entry<Integer, Long> entry : subtotals.entrySet()) {
                int seat = entry.getKey();
                emit("SEAT", seat, money(entry.getValue()));
                for (OrderLine line : check.lines) {
                    if (line.state.equals("VOID") || line.seat != seat) {
                        continue;
                    }
                    String text = line.tag() + " " + line.name + " x" + line.quantity +
                                  " " + money(line.amount());
                    if (line.comp != null) {
                        text += " COMP " + line.comp;
                    }
                    emit(text);
                }
            }
            long[] amounts = check.amounts();
            emit("SUBTOTAL", money(amounts[0]));
            if (check.discount != 0) {
                emit("DISCOUNT", check.discount + "%", money(amounts[1]));
            }
            if (check.size >= 6) {
                emit("SERVICE", money(amounts[2]));
            }
            emit("TAX", money(amounts[3]));
            emit("TOTAL", money(amounts[4]));
            if (check.paid != 0) {
                emit("PAID", money(check.paid));
                emit("DUE", money(amounts[5]));
            }
        }

        private void cmdSplit(String[] a) {
            Check check = table(a[0], true).check;
            long due = check.amounts()[5];
            if (due == 0) {
                fail("nothing to split for table " + a[0]);
            }
            if (a[1].equals("EVEN")) {
                int count = Integer.parseInt(a[2]);
                if (count > check.size) {
                    fail("cannot split table " + a[0] + " " + count + " ways");
                }
                emit("SPLIT", "table", a[0], "EVEN", count, "due", money(due));
                for (int payer = 1; payer <= count; payer++) {
                    emit("PAYER", payer, money(due / count + (payer <= due % count ? 1 : 0)));
                }
                return;
            }
            if (check.paid != 0) {
                fail("table " + a[0] + " has payments");
            }
            Map<Integer, Long> subtotals = seatSubtotals(check);
            Map<Integer, Long> discounts = allocate(subtotals, check.discount);
            Map<Integer, Long> after = new TreeMap<>();
            for (Map.Entry<Integer, Long> entry : subtotals.entrySet()) {
                int seat = entry.getKey();
                after.put(seat, entry.getValue() - discounts.get(seat));
            }
            Map<Integer, Long> services = check.size >= 6 ? allocate(after, 18) : new TreeMap<>();
            if (check.size < 6) {
                for (int seat : subtotals.keySet()) {
                    services.put(seat, 0L);
                }
            }
            Map<Integer, Long> taxes = allocate(after, 8);
            emit("SPLIT", "table", a[0], "BYSEAT", "total", money(check.amounts()[4]));
            for (Map.Entry<Integer, Long> entry : subtotals.entrySet()) {
                int seat = entry.getKey();
                long total = after.get(seat) + services.get(seat) + taxes.get(seat);
                emit("SEAT", seat, "subtotal", money(entry.getValue()),
                     "discount", money(discounts.get(seat)), "service", money(services.get(seat)),
                     "tax", money(taxes.get(seat)), "total", money(total));
            }
        }

        private void cmdPay(String[] a) {
            Check check = table(a[0], true).check;
            if (!payments.containsKey(a[1])) {
                fail("unknown method " + a[1]);
            }
            allServed(check);
            long due = check.amounts()[5];
            if (due == 0) {
                fail("nothing to pay for table " + a[0]);
            }
            long value = cents(a[2]);
            long applied = Math.min(value, due);
            check.paid += applied;
            payments.merge(a[1], applied, Long::sum);
            if (value < due) {
                emit("PAY", "table", a[0], a[1], a[2], "remaining", money(due - value));
            } else {
                long excess = value - due;
                emit("PAY", "table", a[0], a[1], a[2],
                     a[1].equals("CASH") ? "change" : "tip", money(excess));
                if (a[1].equals("CARD")) {
                    tips += excess;
                    check.server.tips += excess;
                }
                closeCheck(check);
            }
        }

        private void cmdClose(String[] a) {
            Check check = table(a[0], true).check;
            allServed(check);
            long due = check.amounts()[5];
            if (due != 0) {
                fail("table " + a[0] + " still owes " + money(due));
            }
            closeCheck(check);
        }

        private void cmdStatus(String[] a) {
            Check check = table(a[0], true).check;
            emit("STATUS", "table", a[0], check.party, "guests", check.size,
                 "since", clock(check.since));
            for (OrderLine line : check.lines) {
                String text = line.tag() + " seat " + line.seat + " " + line.name + " x" +
                              line.quantity + " " + line.course + " " + line.state;
                if (line.state.equals("COOKING")) {
                    text += " until " + clock(line.ready);
                }
                if (line.comp != null) {
                    text += " COMP " + line.comp;
                }
                emit(text);
            }
        }

        private void cmdKitchen(String[] a) {
            emit("KITCHEN", clock(time));
            for (String name : STATIONS) {
                Station station = stations.get(name);
                List<OrderLine> cooking = new ArrayList<>(station.cooking);
                cooking.sort(Comparator.comparingInt((OrderLine line) -> line.ready)
                                       .thenComparingInt(line -> line.number));
                StringJoiner cookingText = new StringJoiner(" ");
                for (OrderLine line : cooking) {
                    cookingText.add(line.tag() + "@" + clock(line.ready));
                }
                StringJoiner queueText = new StringJoiner(" ");
                for (OrderLine line : station.queue) {
                    queueText.add(line.tag());
                }
                emit(name, station.up ? "up" : "down", "cooking",
                     cooking.isEmpty() ? "-" : cookingText.toString(), "queue",
                     station.queue.isEmpty() ? "-" : queueText.toString());
            }
        }

        private void cmdFloor(String[] a) {
            int occupied = 0;
            for (Table table : tables.values()) {
                if (table.check != null) {
                    occupied++;
                }
            }
            emit("FLOOR", clock(time), "free", tables.size() - occupied,
                 "seated", occupied, "waiting", waiting.size());
            for (Table table : tables.values()) {
                if (table.check == null) {
                    emit("table", table.number, "seats", table.seats, "free");
                    continue;
                }
                Check check = table.check;
                String text = "table " + table.number + " seats " + table.seats + " " +
                              check.party + " guests " + check.size + " server " +
                              check.server.name + " since " + clock(check.since) +
                              " items " + check.active().size() +
                              " total " + money(check.amounts()[4]);
                if (check.paid != 0) {
                    text += " paid " + money(check.paid);
                }
                emit(text);
            }
            int position = 0;
            for (Waiting entry : waiting) {
                emit("WAITING", ++position, entry.party, entry.size,
                     "since", clock(entry.joined));
            }
        }

        private void cmdReport(String[] a) {
            emit("REPORT", clock(time));
            emit("COVERS", guests, "parties", parties);
            emit("TURNS", closed, "avg_stay", closed != 0 ? stayTotal / closed : "-");
            emit("SALES", "DRINK", money(sales[0]), "STARTER", money(sales[1]),
                 "MAIN", money(sales[2]), "DESSERT", money(sales[3]));
            emit("TOTALS", "subtotal", money(totals[0]), "discount", money(totals[1]),
                 "service", money(totals[2]), "tax", money(totals[3]),
                 "total", money(totals[4]));
            emit("PAYMENTS", "cash", money(payments.get("CASH")),
                 "card", money(payments.get("CARD")), "tips", money(tips));
            emit("COMPS", comps, money(compAmount), "VOIDS", voids);
            List<Map.Entry<String, Long>> top = new ArrayList<>(served.entrySet());
            top.sort((left, right) -> {
                int comparison = Long.compare(right.getValue(), left.getValue());
                return comparison != 0 ? comparison : left.getKey().compareTo(right.getKey());
            });
            for (int i = 0; i < Math.min(3, top.size()); i++) {
                emit("TOP", i + 1, top.get(i).getKey(), top.get(i).getValue());
            }
            for (String name : STATIONS) {
                Station station = stations.get(name);
                emit(name, "tickets", station.tickets, "avg",
                     station.tickets == 0 ? "-" : station.ticketTotal / station.tickets,
                     "max", station.tickets == 0 ? "-" : station.ticketMax,
                     "remakes", station.remakes);
            }
            for (Server server : servers) {
                emit("SERVER", server.name, "tables", server.load, "parties",
                     server.parties, "sales", money(server.sales), "tips", money(server.tips));
            }
        }

        void execute(String input) {
            String[] parts = input.trim().split(" ");
            if (parts.length == 0) {
                return;
            }
            String command = parts[0];
            String[] args = Arrays.copyOfRange(parts, 1, parts.length);
            try {
                switch (command) {
                    case "TABLE" -> cmdTable(args);
                    case "STAFF" -> cmdStaff(args);
                    case "SEAT" -> cmdSeat(args);
                    case "CANCEL" -> cmdCancel(args);
                    case "MOVE" -> cmdMove(args);
                    case "MENU" -> cmdMenu(args);
                    case "STOCK" -> cmdStock(args);
                    case "HAPPY" -> cmdHappy(args);
                    case "ITEMS" -> cmdItems(args);
                    case "ORDER" -> cmdOrder(args);
                    case "FIRE" -> cmdFire(args);
                    case "TICK" -> cmdTick(args);
                    case "SERVE" -> cmdServe(args);
                    case "RUSH" -> cmdRush(args);
                    case "REMAKE" -> cmdRemake(args);
                    case "VOID" -> cmdVoid(args);
                    case "STATION" -> cmdStation(args);
                    case "COMP" -> cmdComp(args);
                    case "TRANSFER" -> cmdTransfer(args);
                    case "DISCOUNT" -> cmdDiscount(args);
                    case "BILL" -> cmdBill(args);
                    case "SPLIT" -> cmdSplit(args);
                    case "PAY" -> cmdPay(args);
                    case "CLOSE" -> cmdClose(args);
                    case "STATUS" -> cmdStatus(args);
                    case "KITCHEN" -> cmdKitchen(args);
                    case "FLOOR" -> cmdFloor(args);
                    case "REPORT" -> cmdReport(args);
                    default -> { }
                }
            } catch (CommandError error) {
                emit("ERROR", error.getMessage());
            }
        }

        String output() {
            return String.join("\n", output) + "\n";
        }
    }

    public static void main(String[] args) throws IOException {
        BufferedReader reader = new BufferedReader(new InputStreamReader(System.in));
        int count = Integer.parseInt(reader.readLine());
        Restaurant restaurant = new Restaurant();
        for (int i = 0; i < count; i++) {
            restaurant.execute(reader.readLine());
        }
        System.out.print(restaurant.output());
    }
}
