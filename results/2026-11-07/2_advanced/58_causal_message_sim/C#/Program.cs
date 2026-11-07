using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Program {
    public static TValue GetOrAdd<TKey, TValue>(this IDictionary<TKey, TValue> values, TKey key,
                                                Func<TValue> create) {
        if (values.TryGetValue(key, out TValue value))
            return value;
        value = create();
        values.Add(key, value);
        return value;
    }
    public static readonly string[] TYPES = { "LOCAL", "NOFUNDS", "SEND", "BCAST", "RECV" };
    public sealed class Params {
        public int seed, end, cutTime;
        public List<string[]> comparisons = new();
        public List<int[]> cuts = new();
        public List<int> thresholds = new();
    }
    public static Params ReadParams() {
        Params p = new Params();
        foreach (string line in File.ReadAllLines(Path.Combine("input/params.txt")).ToList()) {
            string[] w = line.Split(' ');
            switch (w[0]) {
            case "SEED":
                p.seed = int.Parse(w[1]);
                break;
            case "END":
                p.end = int.Parse(w[1]);
                break;
            case "CUTCOUNT":
                p.cutTime = int.Parse(w[1]);
                break;
            case "COMPARE":
                p.comparisons.Add(new string[] { w[1], w[2] });
                break;
            case "PREDICATE":
                p.thresholds.Add(int.Parse(w[1]));
                break;
            case "CUT": {
                int[] cut = new int[w.Length - 1];
                for (int i = 0; i < cut.Length; i++)
                    cut[i] = int.Parse(w[i + 1]);
                p.cuts.Add(cut);
                break;
            }
            }
        }
        return p;
    }
    public sealed class Event {
        public int number, local, process, time, kind, lamport, balance;
        public int[] vector;
        public string details;
        public Message message;
        public Packet copy;
    }
    public sealed class Message {
        public int id, source, amount;
        public bool broadcast;
        public string tag;
        public int[] stamp;
        public Event send;
        public List<Packet> copies = new();
        public string MessageName() {
            return "m" + id;
        }
        public string MessageKind() {
            return broadcast ? "BCAST" : "P2P";
        }
    }
    public sealed class Packet {
        public Message message;
        public Snapshot.State snapshot;
        public int source, destination, sequence, dispatch, arrival, delivery = -1;
        public bool fifo, causal;
        public int[] missing = new int[0];
        public Event recv;
    }
    public record Item(int time, int process, int serial, Processes.Action action, Packet packet) {
    }
    public record Glyph(int time, int process, int kind, Message message, Packet copy, string snapshot) {
    }
    public sealed class Simulation {
        public Params settings;
        public bool raw;
        public Network network;
        public List<string> names;
        public List<Processes.State> processes;
        public Network.Generator random;
        public int current, serial;
        public List<Message> messages = new();
        public List<Packet> copies = new();
        public List<Event> events = new();
        public List<Snapshot.State> snapshots = new();
        public Dictionary<string, Snapshot.State> snapshotNames = new();
        public List<Glyph> timeline = new();
        public SortedSet<Item> queue = new SortedSet<Item>(Comparer<Item>.Create((a, b) => {
            int c = (a.time).CompareTo(b.time);
            if (c == 0)
                c = (a.process).CompareTo(b.process);
            return c != 0 ? c : (a.serial).CompareTo(b.serial);
        }));
        public Simulation(Params settings, bool raw) {
            this.settings = settings;
            this.raw = raw;
            network = new Network();
            names = network.names;
            processes = Processes.Read(names);
            random = new Network.Generator(settings.seed);
            foreach (Processes.Planned p in Processes.Expand(processes, settings.end))
                Enqueue(p.time, p.process, p.action, null);
        }
        public void Enqueue(int time, int process, Processes.Action action, Packet packet) {
            queue.Add(new Item(time, process, ++serial, action, packet));
        }
        public int Initial() {
            int total = 0;
            foreach (Processes.State p in processes)
                total += p.initial;
            return total;
        }
        public Event RecordEvent(Processes.State p, int kind, string details, Message message, Packet copy) {
            Clocks.Advance(p, kind == 4 ? message.send : null);
            Event e = new Event();
            e.number = events.Count + 1;
            e.local = p.events.Count + 1;
            e.process = p.index;
            e.time = current;
            e.kind = kind;
            e.lamport = p.lamport;
            e.vector = p.vector.ToArray();
            e.balance = p.balance;
            e.details = details;
            e.message = message;
            e.copy = copy;
            p.events.Add(e);
            p.counts[kind]++;
            p.minimum = Math.Min(p.minimum, p.balance);
            events.Add(e);
            timeline.Add(new Glyph(current, p.index, kind, message, copy, null));
            return e;
        }
        public void Dispatch(int source, int destination, Packet packet) {
            network.channels[source][destination].Dispatch(packet, current, random);
            Enqueue(packet.arrival, destination, null, packet);
        }
        public void Send(Processes.State p, Processes.Action action, int sender) {
            bool broadcast = action.kind.Equals("BROADCAST"), transfer = action.kind.Equals("TRANSFER");
            int destination = broadcast                          ? -1
                              : action.argument.Equals("SENDER") ? sender
                                                                 : names.IndexOf(action.argument);
            int amount = transfer ? int.Parse(action.value) : 0;
            if (transfer && amount > p.balance) {
                p.refused++;
                RecordEvent(p, 1, "to " + names[destination] + " amount " + amount + " balance " + p.balance,
                            null, null);
                return;
            }
            if (transfer) {
                p.balance -= amount;
                p.outgoing += amount;
            }
            if (broadcast)
                p.broadcast[p.index]++;
            Message message = new Message();
            message.id = messages.Count + 1;
            message.source = p.index;
            message.amount = amount;
            message.broadcast = broadcast;
            message.tag = transfer ? "transfer" : broadcast ? action.argument : action.value;
            message.stamp = broadcast ? p.broadcast.ToArray() : null;
            messages.Add(message);
            string details = message.MessageName() + (broadcast ? "" : " to " + names[destination]) +
                             " tag " + message.tag;
            if (transfer)
                details += " amount " + amount + " balance " + p.balance;
            message.send = RecordEvent(p, broadcast ? 3 : 2, details, message, null);
            for (int q = 0; q < names.Count; q++)
                if (broadcast ? q != p.index : q == destination) {
                    Packet c = new Packet();
                    c.message = message;
                    message.copies.Add(c);
                    copies.Add(c);
                    Dispatch(p.index, q, c);
                }
        }
        public void Action(int process, Processes.Action action, int sender) {
            Processes.State p = processes[process];
            if (action.kind.Equals("LOCAL"))
                RecordEvent(p, 0, action.argument, null, null);
            else if (action.kind.Equals("SNAPSHOT")) {
                Snapshot.State snapshot = snapshotNames.GetValueOrDefault(action.argument);
                if (snapshot == null) {
                    snapshot = new Snapshot.State(action.argument, current, names.Count);
                    snapshotNames[snapshot.name] = snapshot;
                    snapshots.Add(snapshot);
                }
                if (snapshot.records[process] != null)
                    snapshot.ignored.Add(new Snapshot.Ignored(process, current));
                else
                    RecordSnapshot(snapshot, process, "initiate");
            } else
                Send(p, action, sender);
        }
        public void RecordSnapshot(Snapshot.State snapshot, int process, string reason) {
            snapshot.RecordState(processes[process], current, reason);
            timeline.Add(new Glyph(current, process, 5, null, null, snapshot.name));
            for (int q = 0; q < names.Count; q++)
                if (q != process) {
                    Packet packet = new Packet();
                    packet.snapshot = snapshot;
                    Dispatch(process, q, packet);
                    snapshot.sent[process][q] = current;
                }
        }
        public void Deliver(Packet c) {
            Processes.State p = processes[c.destination];
            Message m = c.message;
            if (m.broadcast)
                p.broadcast[c.source]++;
            p.balance += m.amount;
            p.incoming += m.amount;
            string details = m.MessageName() + " from " + names[c.source] + " tag " + m.tag;
            if (m.amount > 0)
                details += " amount " + m.amount + " balance " + p.balance;
            c.recv = RecordEvent(p, 4, details, m, c);
            c.delivery = current;
            p.delivered.Add(c);
            foreach (Processes.Rule rule in p.rules)
                if (rule.tag.Equals(m.tag))
                    Action(p.index, rule.action, c.source);
        }
        public void Release(Processes.State p) {
            while (true) {
                int chosen = -1;
                for (int i = 0; i < p.hold.Count; i++)
                    if (Clocks.Deliverable(p.hold[i], p)) {
                        chosen = i;
                        break;
                    }
                if (chosen < 0)
                    return;
                Packet c = p.hold[chosen];
                p.hold.RemoveAt(chosen);
                Deliver(c);
            }
        }
        public void Accept(Packet c) {
            Processes.State p = processes[c.destination];
            p.next[c.source]++;
            if (c.message == null) {
                Snapshot.State s = c.snapshot;
                if (s.records[p.index] == null)
                    RecordSnapshot(s, p.index, "marker " + names[c.source]);
                s.Accept(c.source, p.index, current);
                return;
            }
            foreach (Snapshot.State s in snapshots)
                if (s.records[p.index] != null && s.accepted[c.source][p.index] < 0)
                    s.channels[c.source][p.index].Add(c);
            if (!c.message.broadcast || raw)
                Deliver(c);
            else if (Clocks.Deliverable(c, p)) {
                Deliver(c);
                Release(p);
            } else {
                c.causal = true;
                c.missing = Clocks.Missing(c, p);
                p.hold.Add(c);
            }
        }
        public void Arrive(Packet c) {
            Processes.State p = processes[c.destination];
            Dictionary<int, Packet> buffer = p.reorder[c.source];
            if (raw)
                Accept(c);
            else if (c.sequence != p.next[c.source]) {
                c.fifo = true;
                buffer[c.sequence] = c;
                network.channels[c.source][c.destination].buffered++;
            } else {
                Accept(c);
                while (buffer.ContainsKey(p.next[c.source])) {
                    Packet following = buffer[p.next[c.source]];
                    buffer.Remove(p.next[c.source]);
                    Accept(following);
                }
            }
            p.maxHeld = Math.Max(p.maxHeld, p.Held());
        }
        public Simulation Run() {
            while (queue.Count != 0 && queue.Min.time <= settings.end) {
                Item item = queue.Min;
                queue.Remove(item);
                current = item.time;
                if (item.action != null)
                    Action(item.process, item.action, -1);
                else
                    Arrive(item.packet);
            }
            return this;
        }
    }
    public static string Yes(bool condition) {
        return condition ? "yes" : "no";
    }
    public static string EventName(Simulation s, Event e) {
        return s.names[e.process] + "." + e.local;
    }
    public static string Label(Simulation s, Packet c) {
        return c.message.MessageName() + "->" + s.names[c.destination];
    }
    public static string Names(Simulation s, int[] chosen) {
        List<string> names = new();
        foreach (int i in chosen)
            names.Add(s.names[i]);
        return string.Join(",", names);
    }
    public static List<int> History(Processes.State p) {
        List<int> ids = new();
        foreach (Event e in p.events)
            if (e.kind == 3 || e.kind == 4 && e.message.broadcast)
                ids.Add(e.message.id);
        return ids;
    }
    public static string Messages(List<Packet> copies, string empty, bool amounts) {
        List<string> values = new();
        foreach (Packet c in copies)
            values.Add(c.message.MessageName() +
                       (amounts && c.message.amount > 0 ? ":" + c.message.amount : ""));
        return values.Count == 0 ? empty : string.Join(" ", values);
    }
    public static int Delivered(Simulation s) {
        int count = 0;
        foreach (Packet c in s.copies)
            if (c.recv != null)
                count++;
        return count;
    }
    public static List<string> Trace(Simulation s) {
        List<string> lines = new();
        foreach (Event e in s.events)
            lines.Add(e.number + " t=" + e.time + " " + EventName(s, e) + " " + TYPES[e.kind] + " " +
                      e.details + " L=" + e.lamport + " V=" + Clocks.Vector(e.vector));
        int count = Delivered(s);
        lines.Add("SUMMARY events " + s.events.Count + " messages " + s.messages.Count + " copies " +
                  s.copies.Count + " delivered " + count + " undelivered " + (s.copies.Count - count) +
                  " draws " + s.random.draws);
        foreach (Processes.State p in s.processes)
            lines.Add("FINAL " + s.names[p.index] + " events " + p.events.Count + " L=" + p.lamport +
                      " V=" + Clocks.Vector(p.vector) + " B=" + Clocks.Vector(p.broadcast) + " balance " +
                      p.balance + " in " + p.incoming + " out " + p.outgoing + " refused " + p.refused +
                      " min " + p.minimum);
        foreach (Processes.State p in s.processes)
            lines.Add("COUNTS " + s.names[p.index] + " local " + p.counts[0] + " nofunds " + p.counts[1] +
                      " send " + p.counts[2] + " bcast " + p.counts[3] + " recv " + p.counts[4]);
        return lines;
    }
    public static string WaitMode(Simulation s, Packet c) {
        return c.causal ? (c.fifo ? "fifo+causal " : "causal ") + Names(s, c.missing)
               : c.fifo ? "fifo"
                        : "direct";
    }
    public static string CopyInfo(Simulation s, Packet c) {
        return c.message.MessageName() + " from " + s.names[c.source] + " " + c.message.MessageKind() +
               " tag " + c.message.tag + " sent " + c.message.send.time;
    }
    public static List<string> Deliveries(Simulation s) {
        List<string> lines = new();
        foreach (Processes.State p in s.processes) {
            lines.Add("PROCESS " + s.names[p.index]);
            int[] modes = new int[4];
            int wait = 0, maximum = 0, number = 0;
            foreach (Packet c in p.delivered) {
                int delay = c.delivery - c.arrival;
                wait += delay;
                maximum = Math.Max(maximum, delay);
                modes[(c.fifo ? 1 : 0) + (c.causal ? 2 : 0)]++;
                lines.Add((++number) + " " + CopyInfo(s, c) + " arrived " + c.arrival + " delivered " +
                          c.delivery + " wait " + delay + " " + WaitMode(s, c));
            }
            foreach (Packet c in s.copies)
                if (c.destination == p.index && c.arrival <= s.settings.end && c.recv == null) {
                    string place = p.reorder[c.source].ContainsKey(c.sequence)
                                       ? "fifo"
                                       : "causal " + Names(s, c.missing);
                    lines.Add("HELD " + CopyInfo(s, c) + " arrived " + c.arrival + " " + place);
                }
            foreach (Packet c in s.copies)
                if (c.destination == p.index && c.arrival > s.settings.end)
                    lines.Add("TRANSIT " + CopyInfo(s, c) + " arrival " + c.arrival);
            lines.Add("TOTAL delivered " + p.delivered.Count + " direct " + modes[0] + " fifo " + modes[1] +
                      " causal " + modes[2] + " both " + modes[3] + " wait " + wait + " max_wait " + maximum +
                      " max_held " + p.maxHeld);
            List<string> ids = new();
            foreach (int id in History(p))
                ids.Add("m" + id);
            lines.Add("BCASTS " + (ids.Count == 0 ? "none" : string.Join(" ", ids)));
        }
        int n = s.names.Count;
        for (int i = 0; i < n; i++)
            for (int j = 0; j < n; j++)
                if (i != j) {
                    Network.Channel c = s.network.channels[i][j];
                    lines.Add("CHANNEL " + s.names[i] + "->" + s.names[j] + " " +
                              (c.fifo ? "FIFO" : "NONFIFO") + " " + c.Delay() + " messages " + c.messages +
                              " markers " + c.markers + " buffered " + c.buffered + " max_delay " +
                              c.maxDelay + " entries " + c.entries);
                }
        SortedDictionary<string, int[]> tags = new(StringComparer.Ordinal);
        List<Message> broadcasts = new();
        foreach (Packet c in s.copies) {
            int[] values = tags.GetOrAdd(c.message.tag, () => new int[4]);
            values[0]++;
            if (c.recv != null) {
                int latency = c.delivery - c.message.send.time;
                values[1]++;
                values[2] += latency;
                values[3] = Math.Max(values[3], latency);
            }
        }
        foreach (string tag in tags.Keys) {
            int[] a = tags[tag];
            lines.Add("TAG " + tag + " copies " + a[0] + " delivered " + a[1] + " latency " + a[2] + " max " +
                      a[3]);
        }
        foreach (Message m in s.messages)
            if (m.broadcast) {
                broadcasts.Add(m);
                int stable = 0;
                bool complete = true;
                foreach (Packet c in m.copies) {
                    if (c.recv == null)
                        complete = false;
                    else
                        stable = Math.Max(stable, c.delivery);
                }
                lines.Add("STABLE " + m.MessageName() + " " + s.names[m.source] + " tag " + m.tag + " sent " +
                          m.send.time + " stable " + (complete ? Convert.ToString(stable) : "none"));
            }
        int disagreements = 0;
        for (int i = 0; i < broadcasts.Count; i++)
            for (int j = i + 1; j < broadcasts.Count; j++) {
                Message a = broadcasts[i], b = broadcasts[j];
                List<string> earlier = new(), later = new();
                foreach (Processes.State p in s.processes) {
                    List<int> ids = History(p);
                    int x = ids.IndexOf(a.id), y = ids.IndexOf(b.id);
                    if (x >= 0 && y >= 0)
                        (x < y ? earlier : later).Add(s.names[p.index]);
                }
                if (earlier.Count != 0 && later.Count != 0) {
                    disagreements++;
                    lines.Add("DISAGREE " + a.MessageName() + " " + b.MessageName() + " " +
                              string.Join(",", earlier) + " " + string.Join(",", later));
                }
            }
        lines.Add("DISAGREEMENTS " + disagreements);
        return lines;
    }

    public static string Verdict(Simulation s, Snapshot.Cut details) {
        List<string> labels = new();
        foreach (Packet c in details.orphans)
            labels.Add(Label(s, c));
        return labels.Count == 0 ? "yes" : "no " + string.Join(" ", labels);
    }
    public static List<string> Snapshots(Simulation normal, Simulation raw) {
        List<string> lines = new();
        foreach (Simulation sim in new Simulation[] { normal, raw })
            foreach (Snapshot.State snap in sim.snapshots) {
                int[] cut = snap.Cut();
                Snapshot.Cut details = Snapshot.Inspect(cut, sim);
                int balances = 0, channelMoney = 0, n = sim.names.Count;
                List<Packet> channelCopies = new(), pending = new();
                for (int i = 0; i < n; i++) {
                    balances += snap.records[i].balance;
                    pending.AddRange(snap.records[i].pending);
                    for (int j = 0; j < n; j++)
                        if (i != j)
                            channelCopies.AddRange(snap.channels[i][j]);
                }
                foreach (Packet c in channelCopies)
                    channelMoney += c.message.amount;
                int money = balances + channelMoney;
                if (sim.raw) {
                    lines.Add("RAW " + snap.name + " completed " + snap.complete + " cut " +
                              Clocks.Vector(cut) + " consistent " + Verdict(sim, details) + " money " +
                              money + " conserved " + Yes(money == sim.Initial()));
                    continue;
                }
                lines.Add("SNAPSHOT " + snap.name + " started " + snap.start + " completed " + snap.complete);
                for (int i = 0; i < n; i++) {
                    Snapshot.LocalRecord rec = snap.records[i];
                    lines.Add("RECORD " + sim.names[i] + " t=" + rec.time + " " + rec.reason + " balance " +
                              rec.balance + " L=" + rec.lamport + " V=" + Clocks.Vector(rec.vector) +
                              " pending " + Messages(rec.pending, "none", false));
                }
                for (int i = 0; i < n; i++)
                    for (int j = 0; j < n; j++)
                        if (i != j)
                            lines.Add("CHANNEL " + sim.names[i] + "->" + sim.names[j] + " marker " +
                                      snap.sent[i][j] + " " + snap.accepted[i][j] + " state " +
                                      Messages(snap.channels[i][j], "empty", true));
                foreach (Snapshot.Ignored ignored in snap.ignored)
                    lines.Add("IGNORED " + sim.names[ignored.process] + " t=" + ignored.time);
                bool vector = true;
                foreach (Snapshot.LocalRecord rec in snap.records)
                    if (!Clocks.LessEqual(rec.vector, cut))
                        vector = false;
                lines.Add("CUT " + Clocks.Vector(cut) + " consistent " + Verdict(sim, details) + " vector " +
                          Yes(vector));
                List<Packet> all = new(channelCopies);
                all.AddRange(pending);
                lines.Add("TRANSIT channels " + channelCopies.Count + " pending " + pending.Count + " cut " +
                          details.transit.Count + " match " + Yes(Snapshot.Match(all, details.transit)));
                lines.Add("MONEY balances " + balances + " channels " + channelMoney + " total " + money +
                          " initial " + sim.Initial() + " conserved " + Yes(money == sim.Initial()));
            }
        return lines;
    }
    public static string Ranges(Simulation sim, List<Event> path) {
        List<string> parts = new();
        int first = 0;
        while (first < path.Count) {
            int last = first;
            while (last + 1 < path.Count && path[last + 1].process == path[last].process &&
                   path[last + 1].local == path[last].local + 1)
                last++;
            Event a = path[first], b = path[last];
            parts.Add(EventName(sim, a) + (first == last ? "" : "-" + b.local));
            first = last + 1;
        }
        return parts.Count == 0 ? "-" : string.Join(" ", parts);
    }
    public static List<Event> Chain(Simulation sim) {
        Event current = sim.events[0];
        foreach (Event e in sim.events)
            if (e.lamport > current.lamport)
                current = e;
        List<Event> reversed = new();
        reversed.Add(current);
        while (current.lamport > 1) {
            if (current.kind == 4 && current.message.send.lamport == current.lamport - 1)
                current = current.message.send;
            else
                current = sim.processes[current.process].events[current.local - 2];
            reversed.Add(current);
        }
        reversed.Reverse();
        return reversed;
    }
    public static string RelationLine(Simulation s, Analysis.Relation r, bool violation) {
        Packet a = r.first, b = r.second;
        return (violation ? "VIOLATION " : "RACE ") + s.names[r.process] + " " + a.message.MessageName() +
               " " + s.names[a.source] + (violation ? " overtook " : " ") + b.message.MessageName() + " " +
               s.names[b.source];
    }
    public static int FifoCount(List<Analysis.Relation> relations) {
        int count = 0;
        foreach (Analysis.Relation r in relations)
            if (r.first.source == r.second.source)
                count++;
        return count;
    }
    public static List<string> AnalysisLines(Simulation sim, Simulation raw) {
        List<string> lines = new();
        Dictionary<string, Event> indexed = new();
        foreach (Event e in sim.events)
            indexed[EventName(sim, e)] = e;
        List<List<int>> edges = Analysis.Graph(sim);
        foreach (string[] pair in sim.settings.comparisons) {
            Event a = indexed[pair[0]], b = indexed[pair[1]];
            string relation = Clocks.Relation(a.vector, b.vector);
            List<int> path = Analysis.Path(a.number - 1, b.number - 1, edges);
            string graph = "->";
            if (path == null) {
                path = Analysis.Path(b.number - 1, a.number - 1, edges);
                graph = path == null ? "||" : "<-";
            }
            lines.Add("COMPARE " + pair[0] + " " + relation + " " + pair[1] + " L=" + a.lamport + "," +
                      b.lamport + " graph " + graph + " agree " + Yes(relation.Equals(graph)));
            if (path != null) {
                List<Event> events = new();
                foreach (int number in path)
                    events.Add(sim.events[number]);
                int messages = 0;
                for (int i = 1; i < events.Count; i++)
                    if (events[i].process != events[i - 1].process)
                        messages++;
                lines.Add("PATH length " + events.Count + " messages " + messages + " " +
                          Ranges(sim, events));
            }
            foreach (Event e in new Event[] { a, b }) {
                int[] future = new int[sim.names.Count];
                for (int q = 0; q < future.Length; q++)
                    foreach (Event f in sim.processes[q].events)
                        if (f.vector[e.process] < e.local)
                            future[q]++;
                lines.Add("WINDOW " + EventName(sim, e) + " past " + Clocks.Vector(e.vector) + " future " +
                          Clocks.Vector(future));
            }
        }
        Analysis.Concurrency c = Analysis.ComputeConcurrency(sim);
        int n = sim.events.Count;
        lines.Add("CONCURRENCY events " + n + " pairs " + (n * (n - 1) / 2) + " ordered " + c.ordered +
                  " concurrent " + c.concurrent + " same_lamport " + c.same + " inversions " + c.inversions);
        for (int i = 0; i < sim.names.Count; i++)
            for (int j = i + 1; j < sim.names.Count; j++)
                lines.Add("PAIR " + sim.names[i] + " " + sim.names[j] + " " + c.pairs[i][j]);
        List<Event> longest = Chain(sim);
        lines.Add("CHAIN length " + longest.Count + " " + Ranges(sim, longest));
        List<Analysis.Relation> races = Analysis.Relations(sim, true),
                                violations = Analysis.Relations(sim, false),
                                rawViolations = Analysis.Relations(raw, false);
        foreach (Analysis.Relation r in races)
            lines.Add(RelationLine(sim, r, false));
        lines.Add("RACES " + races.Count);
        foreach (Analysis.Relation r in violations)
            lines.Add(RelationLine(sim, r, true));
        lines.Add("VIOLATIONS causal " + violations.Count + " fifo " + FifoCount(violations));
        lines.Add("RAW events " + raw.events.Count + " delivered " + Delivered(raw) + " causal " +
                  rawViolations.Count + " fifo " + FifoCount(rawViolations));
        foreach (int[] cut in sim.settings.cuts) {
            Snapshot.Cut details = Snapshot.Inspect(cut, sim);
            List<string> orphans = new();
            foreach (Packet packet in details.orphans)
                orphans.Add(Label(sim, packet));
            string text =
                orphans.Count == 0 ? " consistent" : " inconsistent orphans " + string.Join(" ", orphans);
            lines.Add("CUT " + Clocks.Vector(cut) + text + " transit " + details.transit.Count + " money " +
                      details.money + " initial " + sim.Initial());
        }
        Analysis.Enumeration enumeration =
            Analysis.Enumerate(sim, sim.settings.cutTime, sim.settings.thresholds);
        lines.Add("CUTCOUNT t=" + sim.settings.cutTime + " events " + Clocks.Vector(enumeration.limits) +
                  " product " + enumeration.product + " consistent " + enumeration.consistent);
        List<string> levels = new();
        foreach (int value in enumeration.levels)
            levels.Add(Convert.ToString(value));
        lines.Add("LEVELS " + string.Join(" ", levels));
        for (int i = 0; i < sim.settings.thresholds.Count; i++) {
            Analysis.Predicate p = enumeration.predicates[i];
            lines.Add("PREDICATE transit>=" + sim.settings.thresholds[i] + " cuts " + p.cuts + " possibly " +
                      Yes(p.cuts > 0) + " definitely " + Yes(p.definitely));
        }
        return lines;
    }
    public static void Overwrite(StringBuilder line, int at, string text) {
        while (line.Length < at + text.Length)
            line.Append(' ');
        for (int i = 0; i < text.Length; i++)
            line[at + i] = text[i];
    }
    public static string Trim(StringBuilder line) {
        int end = line.Length;
        while (end > 0 && line[end - 1] == ' ')
            end--;
        return line.ToString(0, end);
    }
    public static string Header(Simulation sim, string letter) {
        StringBuilder line = new StringBuilder("    " + letter + " ");
        for (int i = 0; i < sim.names.Count; i++)
            Overwrite(line, 8 * i + 6, sim.names[i]);
        return Trim(line);
    }
    public static string DrawGlyph(Simulation sim, Glyph glyph, int value) {
        int last = 8 * sim.names.Count - 2;
        StringBuilder line = new StringBuilder(value.ToString(CultureInfo.InvariantCulture).PadLeft(5) + " " +
                                               new string(' ', last - 5));
        for (int i = 0; i < sim.names.Count; i++)
            line[8 * i + 6] = '|';
        int own = 8 * glyph.process + 6;
        char[] symbols = { '*', 'x', 'S', 'B', 'R', '#' };
        line[own] = symbols[glyph.kind];
        if (glyph.kind == 5)
            Overwrite(line, own + 1, glyph.snapshot);
        else if (glyph.kind == 2 || glyph.kind == 3)
            Overwrite(line, own + 1, glyph.message.MessageName());
        else if (glyph.kind == 4) {
            int source = 8 * glyph.copy.source + 6, low = Math.Min(own, source), high = Math.Max(own, source);
            for (int i = low + 1; i < high; i++)
                line[i] = (i - 6) % 8 == 0 ? '+' : '-';
            line[source < own ? high - 1 : low + 1] = source < own ? '>' : '<';
            Overwrite(line, low + 2, glyph.message.MessageName());
        }
        return Trim(line);
    }
    public static List<string> Diagram(Simulation sim) {
        List<string> lines = new();
        lines.Add(Header(sim, "t"));
        foreach (Glyph g in sim.timeline)
            lines.Add(DrawGlyph(sim, g, g.time));
        lines.Add(Header(sim, "L"));
        List<Event> events = new(sim.events);
        events.Sort((a, b) => {
            int c = (a.lamport).CompareTo(b.lamport);
            return c != 0 ? c : (a.process).CompareTo(b.process);
        });
        foreach (Event e in events)
            lines.Add(
                DrawGlyph(sim, new Glyph(e.time, e.process, e.kind, e.message, e.copy, null), e.lamport));
        return lines;
    }
    public static void Write(string name, List<string> lines) {
        Directory.CreateDirectory(Path.Combine("output"));
        File.WriteAllText(Path.Combine("output", name), string.Join("\n", lines) + "\n");
    }
    public static void Main(string[] args) {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        Params settings = ReadParams();
        Simulation normal = new Simulation(settings, false).Run(), raw = new Simulation(settings, true).Run();
        Write("trace.txt", Trace(normal));
        Write("deliveries.txt", Deliveries(normal));
        Write("snapshots.txt", Snapshots(normal, raw));
        Write("analysis.txt", AnalysisLines(normal, raw));
        Write("diagram.txt", Diagram(normal));
    }
}
