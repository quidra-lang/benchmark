import java.io.*;
import java.util.*;

public class Main {
    static final List<String> CLASSES = List.of("F","J","Y");
    record Seat(String id, int row, char letter, int block, String cabin, String kind) {}
    static class Cabin {
        String name;
        int first, last;
        List<String> blocks;
        List<Seat> seats = new ArrayList<>();
    }
    static class Aircraft {
        String model;
        int base, limit;
        Map<String,Cabin> cabins = new LinkedHashMap<>();
        Map<String,Seat> seats = new LinkedHashMap<>();
        Set<Integer> exits = new HashSet<>();
        Set<String> blocked = new HashSet<>();
    }
    static class Flight {
        String name;
        Aircraft aircraft;
        boolean closed;
        Map<String,Integer> limits = new HashMap<>();
        Set<String> blocked;
        Map<String,Passenger> occupied = new HashMap<>();
        List<Booking> bookings = new ArrayList<>();
        List<Passenger> volunteers = new ArrayList<>();
    }
    static class Booking {
        String pnr;
        Flight flight;
        boolean checked;
        List<Passenger> passengers = new ArrayList<>();
    }
    static class Passenger {
        String name, type, pref, cabin;
        int order;
        Booking booking;
        Passenger lap, parent;
        Seat seat;
        boolean needsSeat() { return !type.equals("INFANT"); }
        String result() { return !needsSeat() ? "LAP" : seat == null ? "UNASSIGNED" : seat.id(); }
    }
    static class Problem extends RuntimeException {
        Problem(String message) { super(message); }
    }
    static void fail(String message) { throw new Problem(message); }
    final Map<String,Aircraft> aircraft = new HashMap<>();
    final Map<String,Flight> flights = new LinkedHashMap<>();
    final Map<String,Booking> bookings = new HashMap<>();
    final Set<String> used = new HashSet<>();
    final Map<String,String> tiers = new HashMap<>();
    Aircraft defining;
    int nextOrder;
    String tier(Passenger p) { return tiers.getOrDefault(p.name,"NONE"); }
    int tierRank(Passenger p) { return List.of("PLATINUM","GOLD","SILVER","NONE").indexOf(tier(p)); }
    Flight flight(String name, boolean open) {
        Flight f = flights.get(name);
        if (f == null) fail("unknown flight "+name);
        if (open && f.closed) fail("flight "+name+" is closed");
        return f;
    }
    Booking booking(String pnr, boolean open) {
        Booking b = bookings.get(pnr);
        if (b == null || b.passengers.isEmpty()) fail("unknown PNR "+pnr);
        if (open && b.flight.closed) fail("flight "+b.flight.name+" is closed");
        return b;
    }
    Passenger passenger(Booking b, String name) {
        return b.passengers.stream().filter(p -> p.name.equals(name)).findFirst()
            .orElseThrow(() -> new Problem("no passenger "+name+" in "+b.pnr));
    }
    static List<Passenger> passengers(Flight f) {
        return f.bookings.stream().flatMap(b -> b.passengers.stream()).toList();
    }
    static int booked(Flight f, String cabin) {
        return (int)passengers(f).stream().filter(p -> p.needsSeat() && p.cabin.equals(cabin)).count();
    }
    static int seats(Aircraft a, String cabin, Set<String> blocked) {
        return (int)a.cabins.get(cabin).seats.stream().filter(s -> !blocked.contains(s.id())).count();
    }
    static void requireCabin(Flight f, String cabin) {
        if (!f.aircraft.cabins.containsKey(cabin)) fail("no cabin "+cabin+" on "+f.name);
    }
    static boolean sameBlock(Seat a, Seat b) { return a.row() == b.row() && a.block() == b.block(); }
    static boolean exitAllowed(Passenger p, Seat s) {
        return !p.booking.flight.aircraft.exits.contains(s.row()) || !p.type.equals("CHILD") && p.lap == null;
    }
    static boolean infantAllowed(Passenger p, Seat s, Set<Passenger> vacated, Map<Passenger,Seat> proposed) {
        if (p.lap == null) return true;
        Flight f = p.booking.flight;
        String letters = f.aircraft.cabins.get(s.cabin()).blocks.get(s.block());
        for (char letter : letters.toCharArray()) {
            Passenger other = f.occupied.get(s.row()+String.valueOf(letter));
            if (other != null && other != p && other.lap != null && !vacated.contains(other)) return false;
        }
        for (var entry : proposed.entrySet()) {
            if (entry.getKey() != p && entry.getKey().lap != null && sameBlock(entry.getValue(),s)) return false;
        }
        return true;
    }
    static boolean fits(Passenger p, Seat s, Set<Passenger> vacated, Map<Passenger,Seat> proposed) {
        Flight f = p.booking.flight;
        Passenger occupant = f.occupied.get(s.id());
        return !f.blocked.contains(s.id()) && (occupant == null || vacated.contains(occupant)) &&
            exitAllowed(p,s) && infantAllowed(p,s,vacated,proposed);
    }
    static void seat(Passenger p, Seat target) {
        Flight f = p.booking.flight;
        if (p.seat != null) f.occupied.remove(p.seat.id());
        p.seat = target;
        if (target != null) f.occupied.put(target.id(),p);
    }
    static Seat select(Passenger p, String cabin) {
        Seat first = null;
        for (Seat s : p.booking.flight.aircraft.cabins.get(cabin).seats) {
            if (!fits(p,s,Set.of(),Map.of())) continue;
            if (first == null) first = s;
            if (p.pref != null && s.kind().equals(p.pref)) return s;
        }
        return first;
    }
    static void reassign(Flight f, List<String> out) {
        for (Passenger p : passengers(f)) {
            if (p.needsSeat() && p.seat == null) {
                Seat target = select(p,p.cabin);
                if (target != null) {
                    seat(p,target);
                    out.add("REASSIGNED "+p.booking.pnr+" "+p.name+" "+target.id());
                }
            }
        }
    }
    static boolean candidate(List<Passenger> people, List<Seat> positions) {
        Map<Passenger,Seat> proposed = new HashMap<>();
        for (int i = 0; i < people.size(); i++) proposed.put(people.get(i),positions.get(i));
        for (Passenger p : people) {
            if (!fits(p,proposed.get(p),Set.of(),proposed)) return false;
        }
        for (Passenger p : people) seat(p,proposed.get(p));
        return true;
    }
    static String assign(Booking b, String cabinName) {
        List<Passenger> people = b.passengers.stream().filter(Passenger::needsSeat).toList();
        if (people.size() == 1) {
            seat(people.getFirst(),select(people.getFirst(),cabinName));
            return "SINGLE";
        }
        Cabin cabin = b.flight.aircraft.cabins.get(cabinName);
        Aircraft a = b.flight.aircraft;
        int k = people.size();
        for (int stage = 1; stage <= 3; stage++) {
            int lastH = stage == 3 ? k : 2;
            for (int h = 2; h <= lastH; h++) {
                int width = (k+h-1)/h;
                for (int row = cabin.first; row <= cabin.last; row++) {
                    List<String> blocks = stage == 2 ? List.of(String.join("",cabin.blocks)) : cabin.blocks;
                    for (String block : blocks) {
                        int span = stage == 3 ? width : k;
                        for (int x = 0; x+span <= block.length(); x++) {
                            List<Seat> positions = new ArrayList<>();
                            for (int j = 0; j < k; j++) {
                                int r = row+(stage == 3 ? j/width : 0);
                                if (r > cabin.last) break;
                                positions.add(a.seats.get(r+String.valueOf(block.charAt(x+(stage == 3 ? j%width : j)))));
                            }
                            if (positions.size() == k && candidate(people,positions)) return stage == 1 ? "BLOCK" : stage == 2 ? "ROW" : "STACK";
                        }
                    }
                }
            }
        }
        for (Passenger p : people) seat(p,select(p,cabinName));
        return "SPLIT";
    }
    static List<Passenger> removalTargets(Passenger p) {
        return p.lap == null ? List.of(p) : List.of(p,p.lap);
    }
    static void remove(List<Passenger> targets) {
        for (Passenger p : targets) {
            seat(p,null);
            p.booking.flight.volunteers.remove(p);
            p.booking.passengers.remove(p);
            if (p.parent != null) p.parent.lap = null;
        }
    }
    static Comparator<Passenger> seatOrder() {
        return Comparator.comparingInt((Passenger p) -> p.seat.row()).thenComparingInt(p -> p.seat.letter());
    }
    static String load(int seated, int count) {
        int q = seated*1000/count;
        return q/10+"."+q%10+"%";
    }
    int boardingRank(Passenger p) {
        if (p.booking.passengers.stream().anyMatch(q -> !q.needsSeat())) return 0;
        if (!p.cabin.equals("Y")) return 1;
        if (tierRank(p) <= 1) return 2;
        return 3;
    }
    static int zone(Passenger p) { return (p.seat.row()-p.booking.flight.aircraft.cabins.get("Y").first)/5+1; }
    List<String> execute(String line) {
        String[] t = line.split(" ");
        String command = t[0];
        List<String> out = new ArrayList<>();
        switch (command) {
            case "AIRCRAFT": {
                defining = new Aircraft();
                defining.model = t[1];
                defining.base = Integer.parseInt(t[2]);
                defining.limit = Integer.parseInt(t[3]);
                break;
            }
            case "CABIN": {
                Cabin c = new Cabin();
                c.name = t[1];
                c.first = Integer.parseInt(t[2]);
                c.last = Integer.parseInt(t[3]);
                c.blocks = Arrays.asList(t).subList(4,t.length);
                for (int row = c.first; row <= c.last; row++) {
                    for (int block = 0; block < c.blocks.size(); block++) {
                        String letters = c.blocks.get(block);
                        for (int i = 0; i < letters.length(); i++) {
                            boolean window = block == 0 && i == 0 || block == c.blocks.size()-1 && i == letters.length()-1;
                            String kind = window ? "W" : i == 0 || i == letters.length()-1 ? "A" : "M";
                            Seat s = new Seat(row+String.valueOf(letters.charAt(i)),row,letters.charAt(i),block,c.name,kind);
                            c.seats.add(s);
                            defining.seats.put(s.id(),s);
                        }
                    }
                }
                defining.cabins.put(c.name,c);
                break;
            }
            case "EXIT": {
                for (int i = 1; i < t.length; i++) defining.exits.add(Integer.parseInt(t[i]));
                break;
            }
            case "BLOCKED": {
                defining.blocked.addAll(Arrays.asList(t).subList(1,t.length));
                break;
            }
            case "END": {
                aircraft.put(defining.model,defining);
                String result = "AIRCRAFT "+defining.model;
                for (String c : CLASSES) {
                    if (defining.cabins.containsKey(c)) result += " "+c+" "+seats(defining,c,defining.blocked);
                }
                out.add(result);
                defining = null;
                break;
            }
            case "FLIGHT": {
                if (flights.containsKey(t[1])) fail("duplicate flight "+t[1]);
                Aircraft a = aircraft.get(t[2]);
                if (a == null) fail("unknown aircraft "+t[2]);
                Flight f = new Flight();
                f.name = t[1];
                f.aircraft = a;
                f.blocked = new HashSet<>(a.blocked);
                String result = "FLIGHT "+f.name+" "+a.model;
                for (String c : CLASSES) {
                    if (a.cabins.containsKey(c)) {
                        int count = seats(a,c,a.blocked), limit = count*(100+Integer.parseInt(t[3]))/100;
                        f.limits.put(c,limit);
                        result += " "+c+" "+count+"/"+limit;
                    }
                }
                flights.put(f.name,f);
                out.add(result);
                break;
            }
            case "BOOK": {
                if (used.contains(t[1])) fail("duplicate PNR "+t[1]);
                Flight f = flight(t[2],true);
                requireCabin(f,t[3]);
                Booking b = new Booking();
                b.pnr = t[1];
                b.flight = f;
                Set<String> seen = new HashSet<>();
                List<Passenger> adults = new ArrayList<>(), infants = new ArrayList<>();
                for (int i = 4; i < t.length; i++) {
                    String[] parts = t[i].split(":");
                    if (!seen.add(parts[0])) fail("duplicate name "+parts[0]+" in "+b.pnr);
                    Passenger p = new Passenger();
                    p.name = parts[0];
                    p.type = parts[1];
                    p.pref = parts.length == 3 ? parts[2] : null;
                    p.cabin = t[3];
                    p.booking = b;
                    b.passengers.add(p);
                    if (p.type.equals("ADULT")) adults.add(p);
                    if (p.type.equals("INFANT")) infants.add(p);
                }
                Set<String> present = new HashSet<>();
                for (Passenger p : passengers(f)) present.add(p.name);
                for (Passenger p : b.passengers) {
                    if (present.contains(p.name)) fail(p.name+" already on "+f.name);
                }
                if (adults.isEmpty()) fail("no adult in "+b.pnr);
                if (infants.size() > adults.size()) fail("too many infants in "+b.pnr);
                int count = (int)b.passengers.stream().filter(Passenger::needsSeat).count();
                if (booked(f,t[3])+count > f.limits.get(t[3])) fail("limit exceeded for "+f.name+" "+t[3]);
                for (int i = 0; i < infants.size(); i++) {
                    adults.get(i).lap = infants.get(i);
                    infants.get(i).parent = adults.get(i);
                }
                for (Passenger p : b.passengers) p.order = nextOrder++;
                String method = assign(b,t[3]);
                f.bookings.add(b);
                bookings.put(b.pnr,b);
                used.add(b.pnr);
                List<String> results = b.passengers.stream().map(p -> p.name+":"+p.result()).toList();
                out.add("BOOKED "+b.pnr+" "+f.name+" "+t[3]+" "+method+" "+String.join(" ",results));
                break;
            }
            case "SEAT": {
                Booking b = booking(t[1],true);
                Passenger p = passenger(b,t[2]);
                if (!p.needsSeat()) fail("infant "+p.name+" has no seat");
                Seat target = b.flight.aircraft.seats.get(t[3]);
                if (target == null || !target.cabin().equals(p.cabin)) fail("no seat "+t[3]+" in cabin "+p.cabin);
                if (b.flight.blocked.contains(t[3])) fail("seat "+t[3]+" is blocked");
                if (b.flight.occupied.containsKey(t[3])) fail("seat "+t[3]+" is occupied");
                if (!exitAllowed(p,target)) fail("exit row "+target.row()+" not allowed for "+p.name);
                if (!infantAllowed(p,target,Set.of(),Map.of())) fail("infant limit reached at "+t[3]);
                String old = p.result();
                seat(p,target);
                out.add("MOVED "+b.pnr+" "+p.name+" "+old+" -> "+t[3]);
                reassign(b.flight,out);
                break;
            }
            case "SWAP": {
                Booking a = booking(t[1],true);
                Passenger p = passenger(a,t[2]);
                Booking b = booking(t[3],true);
                Passenger q = passenger(b,t[4]);
                if (p == q) fail("cannot swap "+p.name+" with itself");
                for (Passenger x : List.of(p,q)) {
                    if (!x.needsSeat()) fail("infant "+x.name+" has no seat");
                }
                if (a.flight != b.flight) fail(a.pnr+" and "+b.pnr+" are on different flights");
                if (!p.cabin.equals(q.cabin)) fail(p.name+" and "+q.name+" are in different cabins");
                for (Passenger x : List.of(p,q)) {
                    if (x.seat == null) fail(x.name+" has no seat");
                }
                Set<Passenger> vacated = Set.of(p,q);
                Map<Passenger,Seat> proposed = Map.of(p,q.seat,q,p.seat);
                if (!fits(p,q.seat,vacated,proposed) || !fits(q,p.seat,vacated,proposed)) fail("swap of "+p.name+" and "+q.name+" breaks seating rules");
                Seat ps = p.seat, qs = q.seat;
                seat(p,null);
                seat(q,null);
                seat(p,qs);
                seat(q,ps);
                out.add("SWAPPED "+a.pnr+" "+p.name+" "+p.result()+" "+b.pnr+" "+q.name+" "+q.result());
                reassign(a.flight,out);
                break;
            }
            case "CANCEL": {
                Booking b = booking(t[1],true);
                List<Passenger> targets;
                if (t.length == 2) targets = new ArrayList<>(b.passengers);
                else {
                    Passenger p = passenger(b,t[2]);
                    List<Passenger> selected = removalTargets(p);
                    targets = b.passengers.stream().filter(selected::contains).toList();
                    List<Passenger> remaining = b.passengers.stream().filter(q -> !selected.contains(q)).toList();
                    if (!remaining.isEmpty() && remaining.stream().noneMatch(q -> q.type.equals("ADULT"))) fail(b.pnr+" would have no adult");
                }
                String names = String.join(" ",targets.stream().map(p -> p.name).toList());
                remove(targets);
                out.add("CANCELLED "+b.pnr+" "+names);
                reassign(b.flight,out);
                break;
            }
            case "STATUS": {
                tiers.put(t[1],t[2]);
                out.add("STATUS "+t[1]+" "+t[2]);
                break;
            }
            case "CHECKIN": {
                Booking b = booking(t[1],true);
                if (b.checked) fail(b.pnr+" already checked in");
                b.checked = true;
                out.add("CHECKIN "+b.pnr+" "+b.passengers.size());
                break;
            }
            case "VOLUNTEER": {
                Booking b = booking(t[1],true);
                Passenger p = passenger(b,t[2]);
                if (!p.type.equals("ADULT") || p.lap != null) fail(p.name+" cannot volunteer");
                if (p.seat == null) fail(p.name+" has no seat");
                if (b.flight.volunteers.contains(p)) fail(p.name+" already volunteered");
                b.flight.volunteers.add(p);
                out.add("VOLUNTEER "+b.pnr+" "+p.name+" "+p.result());
                break;
            }
            case "UPGRADE": {
                Flight f = flight(t[1],true);
                List<String> classes = CLASSES.stream().filter(f.aircraft.cabins::containsKey).toList();
                int count = 0;
                for (int i = 0; i+1 < classes.size(); i++) {
                    String higher = classes.get(i), lower = classes.get(i+1);
                    List<Passenger> targets = passengers(f).stream().filter(p -> p.cabin.equals(lower) && p.type.equals("ADULT") && p.lap == null && !tier(p).equals("NONE"))
                        .sorted(Comparator.comparingInt(this::tierRank).thenComparingInt(p -> p.order)).toList();
                    for (Passenger p : targets) {
                        if (booked(f,higher) >= f.limits.get(higher)) break;
                        Seat target = select(p,higher);
                        if (target == null) break;
                        String old = p.result();
                        p.cabin = higher;
                        seat(p,target);
                        out.add("UPGRADED "+p.booking.pnr+" "+p.name+" "+lower+" "+old+" -> "+higher+" "+target.id());
                        count++;
                    }
                }
                reassign(f,out);
                out.add("UPGRADE "+f.name+" "+count);
                break;
            }
            case "CLOSE": {
                Flight f = flight(t[1],true);
                for (Booking b : f.bookings) {
                    if (!b.passengers.isEmpty() && !b.checked) {
                        out.add("NOSHOW "+b.pnr+" "+b.passengers.size());
                        remove(new ArrayList<>(b.passengers));
                    }
                }
                reassign(f,out);
                int count = 0, compensation = 0;
                for (String c : CLASSES) {
                    if (!f.aircraft.cabins.containsKey(c)) continue;
                    List<Passenger> volunteers = f.volunteers.stream().filter(p -> p.seat != null && p.cabin.equals(c)).toList();
                    for (Passenger p : volunteers) {
                        boolean useful = passengers(f).stream().anyMatch(q -> q.needsSeat() && q.seat == null && q.cabin.equals(c) && fits(q,p.seat,Set.of(p),Map.of()));
                        if (useful) {
                            int value = c.equals("F") ? 500 : c.equals("J") ? 300 : 150;
                            out.add("DENIED VOLUNTARY "+p.booking.pnr+" "+p.name+" "+c+" "+value);
                            count++;
                            compensation += value;
                            remove(removalTargets(p));
                            reassign(f,out);
                        }
                    }
                }
                for (Passenger p : passengers(f)) {
                    if (p.needsSeat() && p.seat == null) {
                        int value = p.cabin.equals("F") ? 1000 : p.cabin.equals("J") ? 600 : 300;
                        if (p.type.equals("CHILD")) value /= 2;
                        out.add("DENIED INVOLUNTARY "+p.booking.pnr+" "+p.name+" "+p.cabin+" "+value);
                        count++;
                        compensation += value;
                        remove(removalTargets(p));
                    }
                }
                f.closed = true;
                out.add("CLOSED "+f.name+" denied "+count+" compensation "+compensation);
                break;
            }
            case "BLOCK", "UNBLOCK": {
                Flight f = flight(t[1],true);
                Seat target = f.aircraft.seats.get(t[2]);
                if (target == null) fail("no seat "+t[2]+" on "+f.name);
                boolean blocked = f.blocked.contains(t[2]);
                if (command.equals("BLOCK") && blocked) fail("seat "+t[2]+" is blocked");
                if (command.equals("UNBLOCK") && !blocked) fail("seat "+t[2]+" is not blocked");
                out.add(command+" "+f.name+" "+t[2]);
                if (command.equals("BLOCK")) {
                    f.blocked.add(t[2]);
                    Passenger p = f.occupied.get(t[2]);
                    if (p != null) {
                        seat(p,null);
                        seat(p,select(p,p.cabin));
                        out.add("DISPLACED "+p.booking.pnr+" "+p.name+" "+t[2]+" -> "+p.result());
                    }
                } else f.blocked.remove(t[2]);
                reassign(f,out);
                break;
            }
            case "MAP": {
                Flight f = flight(t[1],false);
                out.add("MAP "+f.name);
                for (String name : CLASSES) {
                    Cabin c = f.aircraft.cabins.get(name);
                    if (c == null) continue;
                    out.add("CABIN "+name);
                    out.add("   "+String.join(" ",c.blocks));
                    for (int row = c.first; row <= c.last; row++) {
                        List<String> blocks = new ArrayList<>();
                        for (String block : c.blocks) {
                            StringBuilder result = new StringBuilder();
                            for (char letter : block.toCharArray()) {
                                String id = row+String.valueOf(letter);
                                result.append(f.blocked.contains(id) ? '#' : f.occupied.containsKey(id) ? 'X' : f.aircraft.exits.contains(row) ? 'E' : '.');
                            }
                            blocks.add(result.toString());
                        }
                        out.add((row < 10 ? " " : "")+row+" "+String.join(" ",blocks));
                    }
                }
                break;
            }
            case "MANIFEST": {
                Flight f = flight(t[1],false);
                List<Passenger> all = passengers(f);
                List<Passenger> seated = all.stream().filter(p -> p.seat != null).sorted(seatOrder()).toList();
                List<Passenger> unassigned = all.stream().filter(p -> p.needsSeat() && p.seat == null).toList();
                out.add("MANIFEST "+f.name+" seated "+seated.size()+" unassigned "+unassigned.size()+" infants "+all.stream().filter(p -> !p.needsSeat()).count());
                List<Passenger> ordered = new ArrayList<>(seated);
                ordered.addAll(unassigned);
                for (Passenger p : ordered) {
                    String result = (p.seat == null ? "---" : p.seat.id())+" "+p.cabin+" "+p.booking.pnr+" "+p.name+" "+p.type;
                    if (p.lap != null) result += " +"+p.lap.name;
                    if (!tier(p).equals("NONE")) result += " "+tier(p);
                    if (p.booking.checked) result += " CHECKED";
                    if (f.volunteers.contains(p)) result += " VOL";
                    out.add(result);
                }
                break;
            }
            case "LOADFACTOR": {
                Flight f = flight(t[1],false);
                out.add("LOADFACTOR "+f.name);
                int totalSeated = 0, totalSeats = 0;
                for (String c : CLASSES) {
                    if (!f.aircraft.cabins.containsKey(c)) continue;
                    int count = seats(f.aircraft,c,f.blocked);
                    int seated = (int)passengers(f).stream().filter(p -> p.cabin.equals(c) && p.seat != null).count();
                    out.add(c+" "+seated+"/"+count+" "+load(seated,count)+" booked "+booked(f,c)+"/"+f.limits.get(c));
                    totalSeated += seated;
                    totalSeats += count;
                }
                out.add("ALL "+totalSeated+"/"+totalSeats+" "+load(totalSeated,totalSeats));
                break;
            }
            case "BALANCE": {
                Flight f = flight(t[1],false);
                int weight = 0, moment = 0;
                for (Passenger p : passengers(f)) {
                    if (p.seat == null) continue;
                    int w = (p.type.equals("ADULT") ? 80 : 40)+(p.lap == null ? 0 : 10);
                    weight += w;
                    moment += w*(p.seat.row()-f.aircraft.base);
                }
                int limit = f.aircraft.limit;
                out.add("BALANCE "+f.name+" weight "+weight+" moment "+moment+" limit "+limit+" "+(moment < -limit ? "NOSE-HEAVY" : moment > limit ? "TAIL-HEAVY" : "OK"));
                break;
            }
            case "BOARDING": {
                Flight f = flight(t[1],false);
                List<Passenger> ordered = new ArrayList<>(passengers(f).stream().filter(p -> p.seat != null).toList());
                ordered.sort((a,b) -> {
                    int ar = boardingRank(a), br = boardingRank(b);
                    if (ar != br) return Integer.compare(ar,br);
                    if (ar < 3) return seatOrder().compare(a,b);
                    if (zone(a) != zone(b)) return Integer.compare(zone(b),zone(a));
                    int ak = "WMA".indexOf(a.seat.kind()), bk = "WMA".indexOf(b.seat.kind());
                    if (ak != bk) return Integer.compare(ak,bk);
                    if (a.seat.row() != b.seat.row()) return Integer.compare(b.seat.row(),a.seat.row());
                    return Character.compare(a.seat.letter(),b.seat.letter());
                });
                out.add("BOARDING "+f.name+" "+ordered.size());
                for (int i = 0; i < ordered.size(); i++) {
                    Passenger p = ordered.get(i);
                    int rank = boardingRank(p);
                    String group = rank == 0 ? "PRE" : rank == 1 ? "CABIN" : rank == 2 ? "TIER" : "ZONE"+zone(p);
                    out.add((i+1)+" "+group+" "+p.result()+" "+p.booking.pnr+" "+p.name);
                }
                break;
            }
            case "AVAIL": {
                Flight f = flight(t[1],false);
                requireCabin(f,t[2]);
                int free = 0, window = 0, middle = 0, aisle = 0, exit = 0;
                for (Seat s : f.aircraft.cabins.get(t[2]).seats) {
                    if (f.blocked.contains(s.id()) || f.occupied.containsKey(s.id())) continue;
                    free++;
                    if (s.kind().equals("W")) window++;
                    if (s.kind().equals("M")) middle++;
                    if (s.kind().equals("A")) aisle++;
                    if (f.aircraft.exits.contains(s.row())) exit++;
                }
                out.add("AVAIL "+f.name+" "+t[2]+" free "+free+" W "+window+" M "+middle+" A "+aisle+" EXIT "+exit);
                break;
            }
            case "INFO": {
                Booking b = booking(t[1],false);
                out.add("INFO "+b.pnr+" "+b.flight.name+" "+b.passengers.size()+" "+(b.checked ? "CHECKED" : "NOT-CHECKED"));
                for (Passenger p : b.passengers) out.add(p.name+" "+p.type+" "+p.cabin+" "+p.result());
                break;
            }
            case "FIND": {
                List<String> found = new ArrayList<>();
                for (Flight f : flights.values()) {
                    for (Passenger p : passengers(f)) {
                        if (p.name.equals(t[1])) found.add(f.name+" "+p.booking.pnr+" "+p.cabin+" "+p.result()+" "+(f.closed ? "CLOSED" : "OPEN"));
                    }
                }
                out.add("FIND "+t[1]+" "+tiers.getOrDefault(t[1],"NONE")+" "+found.size());
                out.addAll(found);
                break;
            }
        }
        return out;
    }
    public static void main(String[] args) throws IOException {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in));
        PrintWriter output = new PrintWriter(new BufferedWriter(new OutputStreamWriter(System.out)));
        Main app = new Main();
        int n = Integer.parseInt(input.readLine());
        for (int i = 0; i < n; i++) {
            try {
                app.execute(input.readLine()).forEach(output::println);
            } catch (Problem problem) {
                output.println("ERROR "+problem.getMessage());
            }
        }
        output.flush();
    }
}
