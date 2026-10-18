using System;
using System.Linq;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

class Program {
    static readonly string[] Classes = { "F","J","Y" };
    record Seat(string Id, int Row, char Letter, int Block, string Cabin, string Kind);
    class Cabin {
        public string name = "";
        public int first, last;
        public List<string> blocks = new();
        public List<Seat> seats = new();
    }
    class Aircraft {
        public string model = "";
        public int BaseRow, limit;
        public Dictionary<string,Cabin> cabins = new(StringComparer.Ordinal);
        public Dictionary<string,Seat> seats = new(StringComparer.Ordinal);
        public HashSet<int> exits = new();
        public HashSet<string> blocked = new(StringComparer.Ordinal);
    }
    class Flight {
        public string name = "";
        public Aircraft aircraft = null!;
        public bool closed;
        public Dictionary<string,int> limits = new(StringComparer.Ordinal);
        public HashSet<string> blocked = new(StringComparer.Ordinal);
        public Dictionary<string,Passenger> occupied = new(StringComparer.Ordinal);
        public List<Booking> bookings = new();
        public List<Passenger> volunteers = new();
    }
    class Booking {
        public string pnr = "";
        public Flight flight = null!;
        public bool Checked;
        public List<Passenger> passengers = new();
    }
    class Passenger {
        public string name = "", type = "", pref = null!, cabin = "";
        public int order;
        public Booking booking = null!;
        public Passenger lap = null!, parent = null!;
        public Seat seat = null!;
        public bool NeedsSeat() => type != "INFANT";
        public string Result() => !NeedsSeat() ? "LAP" : seat == null ? "UNASSIGNED" : seat.Id;
    }
    class Problem : Exception {
        public Problem(string message) : base(message) {}
    }
    static void Fail(string message) { throw new Problem(message); }
    readonly Dictionary<string,Aircraft> aircraft = new(StringComparer.Ordinal);
    readonly Dictionary<string,Flight> flights = new(StringComparer.Ordinal);
    readonly List<Flight> flightOrder = new();
    readonly Dictionary<string,Booking> bookings = new(StringComparer.Ordinal);
    readonly HashSet<string> used = new(StringComparer.Ordinal);
    readonly Dictionary<string,string> tiers = new(StringComparer.Ordinal);
    Aircraft defining = null!;
    int nextOrder;
    string Tier(Passenger p) { return tiers.GetValueOrDefault(p.name,"NONE"); }
    int TierRank(Passenger p) { return new List<string> { "PLATINUM","GOLD","SILVER","NONE" }.IndexOf(Tier(p)); }
    Flight GetFlight(string name, bool open) {
        Flight f = flights.GetValueOrDefault(name);
        if (f == null) Fail("unknown flight "+name);
        if (open && f.closed) Fail("flight "+name+" is closed");
        return f;
    }
    Booking GetBooking(string pnr, bool open) {
        Booking b = bookings.GetValueOrDefault(pnr);
        if (b == null || b.passengers.Count == 0) Fail("unknown PNR "+pnr);
        if (open && b.flight.closed) Fail("flight "+b.flight.name+" is closed");
        return b;
    }
    Passenger GetPassenger(Booking b, string name) {
        return b.passengers.FirstOrDefault(p => p.name == name) ?? throw new Problem("no passenger "+name+" in "+b.pnr);
    }
    static List<Passenger> Passengers(Flight f) {
        return f.bookings.SelectMany(b => b.passengers).ToList();
    }
    static int Booked(Flight f, string cabin) {
        return Passengers(f).Count(p => p.NeedsSeat() && p.cabin == cabin);
    }
    static int Seats(Aircraft a, string cabin, HashSet<string> blocked) {
        return a.cabins[cabin].seats.Count(s => !blocked.Contains(s.Id));
    }
    static void RequireCabin(Flight f, string cabin) {
        if (!f.aircraft.cabins.ContainsKey(cabin)) Fail("no cabin "+cabin+" on "+f.name);
    }
    static bool SameBlock(Seat a, Seat b) { return a.Row == b.Row && a.Block == b.Block; }
    static bool ExitAllowed(Passenger p, Seat s) {
        return !p.booking.flight.aircraft.exits.Contains(s.Row) || !p.type.Equals("CHILD") && p.lap == null;
    }
    static bool InfantAllowed(Passenger p, Seat s, HashSet<Passenger> vacated, Dictionary<Passenger,Seat> proposed) {
        if (p.lap == null) return true;
        Flight f = p.booking.flight;
        string letters = f.aircraft.cabins[s.Cabin].blocks[s.Block];
        foreach (char letter in letters.ToCharArray()) {
            Passenger other = f.occupied.GetValueOrDefault(s.Row+Convert.ToString(letter));
            if (other != null && other != p && other.lap != null && !vacated.Contains(other)) return false;
        }
        foreach (var entry in proposed) {
            if (entry.Key != p && entry.Key.lap != null && SameBlock(entry.Value,s)) return false;
        }
        return true;
    }
    static bool Fits(Passenger p, Seat s, HashSet<Passenger> vacated, Dictionary<Passenger,Seat> proposed) {
        Flight f = p.booking.flight;
        Passenger occupant = f.occupied.GetValueOrDefault(s.Id);
        return !f.blocked.Contains(s.Id) && (occupant == null || vacated.Contains(occupant)) &&
            ExitAllowed(p,s) && InfantAllowed(p,s,vacated,proposed);
    }
    static void PlaceSeat(Passenger p, Seat target) {
        Flight f = p.booking.flight;
        if (p.seat != null) f.occupied.Remove(p.seat.Id);
        p.seat = target;
        if (target != null) f.occupied[target.Id] = p;
    }
    static Seat Select(Passenger p, string cabin) {
        var candidates = p.booking.flight.aircraft.cabins[cabin].seats
            .Where(s => Fits(p,s,new HashSet<Passenger>(),new Dictionary<Passenger,Seat>())).ToList();
        return candidates.FirstOrDefault(s => s.Kind == p.pref) ?? candidates.FirstOrDefault();
    }
    static void Reassign(Flight f, List<string> output) {
        foreach (Passenger p in Passengers(f)) {
            if (p.NeedsSeat() && p.seat == null) {
                Seat target = Select(p,p.cabin);
                if (target != null) {
                    PlaceSeat(p,target);
                    output.Add("REASSIGNED "+p.booking.pnr+" "+p.name+" "+target.Id);
                }
            }
        }
    }
    static bool Candidate(List<Passenger> people, List<Seat> positions) {
        var proposed = people.Zip(positions).ToDictionary(pair => pair.First,pair => pair.Second);
        if (!people.All(p => Fits(p,proposed[p],new HashSet<Passenger>(),proposed))) return false;
        foreach (Passenger p in people) PlaceSeat(p,proposed[p]);
        return true;
    }
    static string Assign(Booking b, string cabinName) {
        List<Passenger> people = b.passengers.Where(p => p.NeedsSeat()).ToList();
        if (people.Count == 1) {
            PlaceSeat(people.First(),Select(people.First(),cabinName));
            return "SINGLE";
        }
        Cabin cabin = b.flight.aircraft.cabins[cabinName];
        Aircraft a = b.flight.aircraft;
        int k = people.Count;
        for (int stage = 1; stage <= 3; stage++) {
            int lastH = stage == 3 ? k : 2;
            for (int h = 2; h <= lastH; h++) {
                int width = (k+h-1)/h;
                for (int row = cabin.first; row <= cabin.last; row++) {
                    List<string> blocks = stage == 2 ? new List<string> { string.Join("",cabin.blocks) } : cabin.blocks;
                    foreach (string block in blocks) {
                        int span = stage == 3 ? width : k;
                        for (int x = 0; x+span <= block.Length; x++) {
                            List<Seat> positions = new();
                            for (int j = 0; j < k; j++) {
                                int r = row+(stage == 3 ? j/width : 0);
                                if (r > cabin.last) break;
                                positions.Add(a.seats[r+Convert.ToString(block[x+(stage == 3 ? j%width : j)])]);
                            }
                            if (positions.Count == k && Candidate(people,positions)) return stage == 1 ? "BLOCK" : stage == 2 ? "ROW" : "STACK";
                        }
                    }
                }
            }
        }
        foreach (Passenger p in people) PlaceSeat(p,Select(p,cabinName));
        return "SPLIT";
    }
    static List<Passenger> RemovalTargets(Passenger p) {
        return p.lap == null ? new List<Passenger> { p } : new List<Passenger> { p,p.lap };
    }
    static void Remove(List<Passenger> targets) {
        foreach (Passenger p in targets) {
            PlaceSeat(p,null);
            p.booking.flight.volunteers.Remove(p);
            p.booking.passengers.Remove(p);
            if (p.parent != null) p.parent.lap = null;
        }
    }
    static Comparison<Passenger> SeatOrder() {
        return (a,b) => a.seat.Row != b.seat.Row ? a.seat.Row.CompareTo(b.seat.Row) : a.seat.Letter.CompareTo(b.seat.Letter);
    }
    static string Load(int seated, int count) {
        int q = seated*1000/count;
        return q/10+"."+q%10+"%";
    }
    int BoardingRank(Passenger p) {
        if (p.booking.passengers.Any(q => !q.NeedsSeat())) return 0;
        if (!p.cabin.Equals("Y")) return 1;
        if (TierRank(p) <= 1) return 2;
        return 3;
    }
    static int Zone(Passenger p) { return (p.seat.Row-p.booking.flight.aircraft.cabins["Y"].first)/5+1; }
    List<string> Execute(string line) {
        string[] t = line.Split(' ');
        string command = t[0];
        List<string> output = new();
        switch (command) {
            case "AIRCRAFT": {
                defining = new Aircraft();
                defining.model = t[1];
                defining.BaseRow = int.Parse(t[2]);
                defining.limit = int.Parse(t[3]);
                break;
            }
            case "CABIN": {
                Cabin c = new Cabin();
                c.name = t[1];
                c.first = int.Parse(t[2]);
                c.last = int.Parse(t[3]);
                c.blocks = t.Skip(4).ToList();
                for (int row = c.first; row <= c.last; row++) {
                    for (int block = 0; block < c.blocks.Count; block++) {
                        string letters = c.blocks[block];
                        for (int i = 0; i < letters.Length; i++) {
                            bool window = block == 0 && i == 0 || block == c.blocks.Count-1 && i == letters.Length-1;
                            string kind = window ? "W" : i == 0 || i == letters.Length-1 ? "A" : "M";
                            Seat s = new Seat(row+Convert.ToString(letters[i]),row,letters[i],block,c.name,kind);
                            c.seats.Add(s);
                            defining.seats[s.Id] = s;
                        }
                    }
                }
                defining.cabins[c.name] = c;
                break;
            }
            case "EXIT": {
                for (int i = 1; i < t.Length; i++) defining.exits.Add(int.Parse(t[i]));
                break;
            }
            case "BLOCKED": {
                defining.blocked.UnionWith(t.Skip(1));
                break;
            }
            case "END": {
                aircraft[defining.model] = defining;
                string result = "AIRCRAFT "+defining.model;
                foreach (string c in Classes) {
                    if (defining.cabins.ContainsKey(c)) result += " "+c+" "+Seats(defining,c,defining.blocked);
                }
                output.Add(result);
                defining = null;
                break;
            }
            case "FLIGHT": {
                if (flights.ContainsKey(t[1])) Fail("duplicate flight "+t[1]);
                Aircraft a = aircraft.GetValueOrDefault(t[2]);
                if (a == null) Fail("unknown aircraft "+t[2]);
                Flight f = new Flight();
                f.name = t[1];
                f.aircraft = a;
                f.blocked = new HashSet<string>(a.blocked,StringComparer.Ordinal);
                string result = "FLIGHT "+f.name+" "+a.model;
                foreach (string c in Classes) {
                    if (a.cabins.ContainsKey(c)) {
                        int count = Seats(a,c,a.blocked), limit = count*(100+int.Parse(t[3]))/100;
                        f.limits[c] = limit;
                        result += " "+c+" "+count+"/"+limit;
                    }
                }
                flights[f.name] = f;
                flightOrder.Add(f);
                output.Add(result);
                break;
            }
            case "BOOK": {
                if (used.Contains(t[1])) Fail("duplicate PNR "+t[1]);
                Flight f = GetFlight(t[2],true);
                RequireCabin(f,t[3]);
                Booking b = new Booking();
                b.pnr = t[1];
                b.flight = f;
                HashSet<string> seen = new(StringComparer.Ordinal);
                List<Passenger> adults = new(), infants = new();
                for (int i = 4; i < t.Length; i++) {
                    string[] parts = t[i].Split(':');
                    if (!seen.Add(parts[0])) Fail("duplicate name "+parts[0]+" in "+b.pnr);
                    Passenger p = new Passenger();
                    p.name = parts[0];
                    p.type = parts[1];
                    p.pref = parts.Length == 3 ? parts[2] : null;
                    p.cabin = t[3];
                    p.booking = b;
                    b.passengers.Add(p);
                    if (p.type.Equals("ADULT")) adults.Add(p);
                    if (p.type.Equals("INFANT")) infants.Add(p);
                }
                var present = Passengers(f).Select(p => p.name).ToHashSet(StringComparer.Ordinal);
                foreach (Passenger p in b.passengers) {
                    if (present.Contains(p.name)) Fail(p.name+" already on "+f.name);
                }
                if (adults.Count == 0) Fail("no adult in "+b.pnr);
                if (infants.Count > adults.Count) Fail("too many infants in "+b.pnr);
                int count = b.passengers.Count(p => p.NeedsSeat());
                if (Booked(f,t[3])+count > f.limits[t[3]]) Fail("limit exceeded for "+f.name+" "+t[3]);
                for (int i = 0; i < infants.Count; i++) {
                    adults[i].lap = infants[i];
                    infants[i].parent = adults[i];
                }
                foreach (Passenger p in b.passengers) p.order = nextOrder++;
                string method = Assign(b,t[3]);
                f.bookings.Add(b);
                bookings[b.pnr] = b;
                used.Add(b.pnr);
                List<string> results = b.passengers.Select(p => p.name+":"+p.Result()).ToList();
                output.Add("BOOKED "+b.pnr+" "+f.name+" "+t[3]+" "+method+" "+string.Join(" ",results));
                break;
            }
            case "SEAT": {
                Booking b = GetBooking(t[1],true);
                Passenger p = GetPassenger(b,t[2]);
                if (!p.NeedsSeat()) Fail("infant "+p.name+" has no seat");
                Seat target = b.flight.aircraft.seats.GetValueOrDefault(t[3]);
                if (target == null || !target.Cabin.Equals(p.cabin)) Fail("no seat "+t[3]+" in cabin "+p.cabin);
                if (b.flight.blocked.Contains(t[3])) Fail("seat "+t[3]+" is blocked");
                if (b.flight.occupied.ContainsKey(t[3])) Fail("seat "+t[3]+" is occupied");
                if (!ExitAllowed(p,target)) Fail("exit row "+target.Row+" not allowed for "+p.name);
                if (!InfantAllowed(p,target,new HashSet<Passenger> {  },new Dictionary<Passenger,Seat>())) Fail("infant limit reached at "+t[3]);
                string old = p.Result();
                PlaceSeat(p,target);
                output.Add("MOVED "+b.pnr+" "+p.name+" "+old+" -> "+t[3]);
                Reassign(b.flight,output);
                break;
            }
            case "SWAP": {
                Booking a = GetBooking(t[1],true);
                Passenger p = GetPassenger(a,t[2]);
                Booking b = GetBooking(t[3],true);
                Passenger q = GetPassenger(b,t[4]);
                if (p == q) Fail("cannot swap "+p.name+" with itself");
                foreach (Passenger x in new List<Passenger> { p,q }) {
                    if (!x.NeedsSeat()) Fail("infant "+x.name+" has no seat");
                }
                if (a.flight != b.flight) Fail(a.pnr+" and "+b.pnr+" are on different flights");
                if (!p.cabin.Equals(q.cabin)) Fail(p.name+" and "+q.name+" are in different cabins");
                foreach (Passenger x in new List<Passenger> { p,q }) {
                    if (x.seat == null) Fail(x.name+" has no seat");
                }
                HashSet<Passenger> vacated = new() { p,q };
                Dictionary<Passenger,Seat> proposed = new Dictionary<Passenger,Seat> { [p] = q.seat, [q] = p.seat };
                if (!Fits(p,q.seat,vacated,proposed) || !Fits(q,p.seat,vacated,proposed)) Fail("swap of "+p.name+" and "+q.name+" breaks seating rules");
                Seat ps = p.seat, qs = q.seat;
                PlaceSeat(p,null);
                PlaceSeat(q,null);
                PlaceSeat(p,qs);
                PlaceSeat(q,ps);
                output.Add("SWAPPED "+a.pnr+" "+p.name+" "+p.Result()+" "+b.pnr+" "+q.name+" "+q.Result());
                Reassign(a.flight,output);
                break;
            }
            case "CANCEL": {
                Booking b = GetBooking(t[1],true);
                List<Passenger> targets;
                if (t.Length == 2) targets = new List<Passenger>(b.passengers);
                else {
                    Passenger p = GetPassenger(b,t[2]);
                    List<Passenger> selected = RemovalTargets(p);
                    targets = b.passengers.Where(selected.Contains).ToList();
                    List<Passenger> remaining = b.passengers.Where(q => !selected.Contains(q)).ToList();
                    if (remaining.Count != 0 && !remaining.Any(q => q.type == "ADULT")) Fail(b.pnr+" would have no adult");
                }
                string names = string.Join(" ",targets.Select(p => p.name).ToList());
                Remove(targets);
                output.Add("CANCELLED "+b.pnr+" "+names);
                Reassign(b.flight,output);
                break;
            }
            case "STATUS": {
                tiers[t[1]] = t[2];
                output.Add("STATUS "+t[1]+" "+t[2]);
                break;
            }
            case "CHECKIN": {
                Booking b = GetBooking(t[1],true);
                if (b.Checked) Fail(b.pnr+" already checked in");
                b.Checked = true;
                output.Add("CHECKIN "+b.pnr+" "+b.passengers.Count);
                break;
            }
            case "VOLUNTEER": {
                Booking b = GetBooking(t[1],true);
                Passenger p = GetPassenger(b,t[2]);
                if (!p.type.Equals("ADULT") || p.lap != null) Fail(p.name+" cannot volunteer");
                if (p.seat == null) Fail(p.name+" has no seat");
                if (b.flight.volunteers.Contains(p)) Fail(p.name+" already volunteered");
                b.flight.volunteers.Add(p);
                output.Add("VOLUNTEER "+b.pnr+" "+p.name+" "+p.Result());
                break;
            }
            case "UPGRADE": {
                Flight f = GetFlight(t[1],true);
                List<string> classes = Classes.Where(f.aircraft.cabins.ContainsKey).ToList();
                int count = 0;
                for (int i = 0; i+1 < classes.Count; i++) {
                    string higher = classes[i], lower = classes[i+1];
                    List<Passenger> targets = Passengers(f).Where(p => p.cabin == lower && p.type == "ADULT" && p.lap == null && Tier(p) != "NONE")
                        .OrderBy(TierRank).ThenBy(p => p.order).ToList();
                    foreach (Passenger p in targets) {
                        if (Booked(f,higher) >= f.limits[higher]) break;
                        Seat target = Select(p,higher);
                        if (target == null) break;
                        string old = p.Result();
                        p.cabin = higher;
                        PlaceSeat(p,target);
                        output.Add("UPGRADED "+p.booking.pnr+" "+p.name+" "+lower+" "+old+" -> "+higher+" "+target.Id);
                        count++;
                    }
                }
                Reassign(f,output);
                output.Add("UPGRADE "+f.name+" "+count);
                break;
            }
            case "CLOSE": {
                Flight f = GetFlight(t[1],true);
                foreach (Booking b in f.bookings) {
                    if (b.passengers.Count != 0 && !b.Checked) {
                        output.Add("NOSHOW "+b.pnr+" "+b.passengers.Count);
                        Remove(new List<Passenger>(b.passengers));
                    }
                }
                Reassign(f,output);
                int count = 0, compensation = 0;
                foreach (string c in Classes) {
                    if (!f.aircraft.cabins.ContainsKey(c)) continue;
                    List<Passenger> volunteers = f.volunteers.Where(p => p.seat != null && p.cabin == c).ToList();
                    foreach (Passenger p in volunteers) {
                        bool useful = Passengers(f).Any(q => q.NeedsSeat() && q.seat == null && q.cabin == c && Fits(q,p.seat,new HashSet<Passenger> { p },new Dictionary<Passenger,Seat>()));
                        if (useful) {
                            int value = c.Equals("F") ? 500 : c.Equals("J") ? 300 : 150;
                            output.Add("DENIED VOLUNTARY "+p.booking.pnr+" "+p.name+" "+c+" "+value);
                            count++;
                            compensation += value;
                            Remove(RemovalTargets(p));
                            Reassign(f,output);
                        }
                    }
                }
                foreach (Passenger p in Passengers(f)) {
                    if (p.NeedsSeat() && p.seat == null) {
                        int value = p.cabin.Equals("F") ? 1000 : p.cabin.Equals("J") ? 600 : 300;
                        if (p.type.Equals("CHILD")) value /= 2;
                        output.Add("DENIED INVOLUNTARY "+p.booking.pnr+" "+p.name+" "+p.cabin+" "+value);
                        count++;
                        compensation += value;
                        Remove(RemovalTargets(p));
                    }
                }
                f.closed = true;
                output.Add("CLOSED "+f.name+" denied "+count+" compensation "+compensation);
                break;
            }
            case "BLOCK":
            case "UNBLOCK": {
                Flight f = GetFlight(t[1],true);
                Seat target = f.aircraft.seats.GetValueOrDefault(t[2]);
                if (target == null) Fail("no seat "+t[2]+" on "+f.name);
                bool blocked = f.blocked.Contains(t[2]);
                if (command.Equals("BLOCK") && blocked) Fail("seat "+t[2]+" is blocked");
                if (command.Equals("UNBLOCK") && !blocked) Fail("seat "+t[2]+" is not blocked");
                output.Add(command+" "+f.name+" "+t[2]);
                if (command.Equals("BLOCK")) {
                    f.blocked.Add(t[2]);
                    Passenger p = f.occupied.GetValueOrDefault(t[2]);
                    if (p != null) {
                        PlaceSeat(p,null);
                        PlaceSeat(p,Select(p,p.cabin));
                        output.Add("DISPLACED "+p.booking.pnr+" "+p.name+" "+t[2]+" -> "+p.Result());
                    }
                } else f.blocked.Remove(t[2]);
                Reassign(f,output);
                break;
            }
            case "MAP": {
                Flight f = GetFlight(t[1],false);
                output.Add("MAP "+f.name);
                foreach (string name in Classes) {
                    Cabin c = f.aircraft.cabins.GetValueOrDefault(name);
                    if (c == null) continue;
                    output.Add("CABIN "+name);
                    output.Add("   "+string.Join(" ",c.blocks));
                    for (int row = c.first; row <= c.last; row++) {
                        List<string> blocks = new();
                        foreach (string block in c.blocks) {
                            StringBuilder result = new StringBuilder();
                            foreach (char letter in block.ToCharArray()) {
                                string id = row+Convert.ToString(letter);
                                result.Append(f.blocked.Contains(id) ? '#' : f.occupied.ContainsKey(id) ? 'X' : f.aircraft.exits.Contains(row) ? 'E' : '.');
                            }
                            blocks.Add(result.ToString());
                        }
                        output.Add($"{row,2} "+string.Join(" ",blocks));
                    }
                }
                break;
            }
            case "MANIFEST": {
                Flight f = GetFlight(t[1],false);
                List<Passenger> all = Passengers(f);
                List<Passenger> seated = all.Where(p => p.seat != null).OrderBy(p => p.seat.Row).ThenBy(p => p.seat.Letter).ToList();
                List<Passenger> unassigned = all.Where(p => p.NeedsSeat() && p.seat == null).ToList();
                output.Add("MANIFEST "+f.name+" seated "+seated.Count+" unassigned "+unassigned.Count+" infants "+all.Count(p => !p.NeedsSeat()));
                foreach (Passenger p in seated.Concat(unassigned)) {
                    string result = (p.seat == null ? "---" : p.seat.Id)+" "+p.cabin+" "+p.booking.pnr+" "+p.name+" "+p.type;
                    if (p.lap != null) result += " +"+p.lap.name;
                    if (!Tier(p).Equals("NONE")) result += " "+Tier(p);
                    if (p.booking.Checked) result += " CHECKED";
                    if (f.volunteers.Contains(p)) result += " VOL";
                    output.Add(result);
                }
                break;
            }
            case "LOADFACTOR": {
                Flight f = GetFlight(t[1],false);
                output.Add("LOADFACTOR "+f.name);
                int totalSeated = 0, totalSeats = 0;
                foreach (string c in Classes) {
                    if (!f.aircraft.cabins.ContainsKey(c)) continue;
                    int count = Seats(f.aircraft,c,f.blocked);
                    int seated = Passengers(f).Count(p => p.cabin == c && p.seat != null);
                    output.Add(c+" "+seated+"/"+count+" "+Load(seated,count)+" booked "+Booked(f,c)+"/"+f.limits[c]);
                    totalSeated += seated;
                    totalSeats += count;
                }
                output.Add("ALL "+totalSeated+"/"+totalSeats+" "+Load(totalSeated,totalSeats));
                break;
            }
            case "BALANCE": {
                Flight f = GetFlight(t[1],false);
                int weight = 0, moment = 0;
                foreach (Passenger p in Passengers(f)) {
                    if (p.seat == null) continue;
                    int w = (p.type.Equals("ADULT") ? 80 : 40)+(p.lap == null ? 0 : 10);
                    weight += w;
                    moment += w*(p.seat.Row-f.aircraft.BaseRow);
                }
                int limit = f.aircraft.limit;
                output.Add("BALANCE "+f.name+" weight "+weight+" moment "+moment+" limit "+limit+" "+(moment < -limit ? "NOSE-HEAVY" : moment > limit ? "TAIL-HEAVY" : "OK"));
                break;
            }
            case "BOARDING": {
                Flight f = GetFlight(t[1],false);
                List<Passenger> ordered = Passengers(f).Where(p => p.seat != null).ToList();
                ordered.Sort((a,b) => {
                    int ar = BoardingRank(a), br = BoardingRank(b);
                    if (ar != br) return ar.CompareTo(br);
                    if (ar < 3) return SeatOrder()(a,b);
                    if (Zone(a) != Zone(b)) return Zone(b).CompareTo(Zone(a));
                    int ak = "WMA".IndexOf(a.seat.Kind), bk = "WMA".IndexOf(b.seat.Kind);
                    if (ak != bk) return ak.CompareTo(bk);
                    if (a.seat.Row != b.seat.Row) return b.seat.Row.CompareTo(a.seat.Row);
                    return a.seat.Letter.CompareTo(b.seat.Letter);
                });
                output.Add("BOARDING "+f.name+" "+ordered.Count);
                for (int i = 0; i < ordered.Count; i++) {
                    Passenger p = ordered[i];
                    int rank = BoardingRank(p);
                    string group = rank == 0 ? "PRE" : rank == 1 ? "CABIN" : rank == 2 ? "TIER" : "ZONE"+Zone(p);
                    output.Add((i+1)+" "+group+" "+p.Result()+" "+p.booking.pnr+" "+p.name);
                }
                break;
            }
            case "AVAIL": {
                Flight f = GetFlight(t[1],false);
                RequireCabin(f,t[2]);
                var free = f.aircraft.cabins[t[2]].seats.Where(s => !f.blocked.Contains(s.Id) && !f.occupied.ContainsKey(s.Id)).ToList();
                output.Add("AVAIL "+f.name+" "+t[2]+" free "+free.Count+
                    " W "+free.Count(s => s.Kind == "W")+" M "+free.Count(s => s.Kind == "M")+
                    " A "+free.Count(s => s.Kind == "A")+" EXIT "+free.Count(s => f.aircraft.exits.Contains(s.Row)));
                break;
            }
            case "INFO": {
                Booking b = GetBooking(t[1],false);
                output.Add("INFO "+b.pnr+" "+b.flight.name+" "+b.passengers.Count+" "+(b.Checked ? "CHECKED" : "NOT-CHECKED"));
                foreach (Passenger p in b.passengers) output.Add(p.name+" "+p.type+" "+p.cabin+" "+p.Result());
                break;
            }
            case "FIND": {
                List<string> found = new();
                foreach (Flight f in flightOrder) {
                    foreach (Passenger p in Passengers(f)) {
                        if (p.name.Equals(t[1])) found.Add(f.name+" "+p.booking.pnr+" "+p.cabin+" "+p.Result()+" "+(f.closed ? "CLOSED" : "OPEN"));
                    }
                }
                output.Add("FIND "+t[1]+" "+tiers.GetValueOrDefault(t[1],"NONE")+" "+found.Count);
                output.AddRange(found);
                break;
            }
        }
        return output;
    }
    static void Main() {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        var app = new Program();
        int count = int.Parse(Console.ReadLine()!,CultureInfo.InvariantCulture);
        for (int i = 0; i < count; i++) {
            try {
                foreach (string line in app.Execute(Console.ReadLine()!)) Console.WriteLine(line);
            } catch (Problem problem) {
                Console.WriteLine("ERROR "+problem.Message);
            }
        }
    }
}
