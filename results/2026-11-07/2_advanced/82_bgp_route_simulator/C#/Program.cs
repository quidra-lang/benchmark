using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
public static class Program {
    public const string HEADER =
        "event,time,kind,status,convergence_time,updates,withdrawals,drops,best_changes,routes_changed,max_exploration";
    public record SessionKey(int owner, int link) {}
    public record OwnerPrefix(int owner, Topology.Prefix prefix) : IComparable<OwnerPrefix> {
        public int CompareTo(OwnerPrefix other) {
            int c = (owner).CompareTo(other.owner);
            return c != 0 ? c : prefix.CompareTo(other.prefix);
        }
    }
    public record Imported(Decision.Route route, Policy.Rule rule) {}
    public record Advertised(Decision.Attribute content, Policy.Rule rule) {}
    public record BestLine(int time, int owner, Topology.Prefix prefix, Decision.Route route) {}
    public record Divergence(int first, int repeat, List<BestLine> cycle) {}
    public sealed class Session {
        public int owner, sent, received;
        public Topology.Link link;
        public SortedDictionary<Topology.Prefix, Decision.Attribute> incoming = new(),
                                                                     outgoing = new();
        public SortedSet<Topology.Prefix> pending = new();
        public int? timer;
        public Session(int owner, Topology.Link link) {
            this.owner = owner;
            this.link = link;
        }
    }
    public sealed class Router {
        public int owner, changes;
        public SortedDictionary<Topology.Prefix, Decision.Route> origination = new(), rib = new();
        public List<Session> sessions = new();
        public Router(int owner, List<Topology.Link> links) {
            this.owner = owner;
            foreach (Topology.Link link in links)
                sessions.Add(new Session(owner, link));
        }
    }
    public sealed class Period {
        public int number, updates, withdrawals, drops, bestChanges, routesChanged, convergenceTime,
            deliveryTimes;
        public Simulator.Event eventRecord;
        public Dictionary<int, SortedDictionary<Topology.Prefix, Decision.Route>> before = new();
        public SortedDictionary<OwnerPrefix, int> exploration = new();
        public List<BestLine> bestLines = new();
        public Dictionary<string, int> states = new();
        public Divergence divergence;
        public string status;
        public Period(int number, Simulator.Event eventRecord,
                      SortedDictionary<int, Router> routers) {
            this.number = number;
            this.eventRecord = eventRecord;
            foreach (Router router in routers.Values)
                before[router.owner] = new(router.rib);
        }
        public void Finish(SortedDictionary<int, Router> routers) {
            foreach (Router router in routers.Values) {
                SortedSet<Topology.Prefix> prefixes = new(before[router.owner].Keys);
                prefixes.UnionWith(router.rib.Keys);
                foreach (Topology.Prefix prefix in prefixes)
                    if (!object.Equals(before[router.owner].GetValueOrDefault(prefix),
                                       router.rib.GetValueOrDefault(prefix)))
                        routesChanged++;
            }
        }
        public string Csv() {
            return number + "," + eventRecord.time + "," + eventRecord.kind + "," + status + "," +
                   convergenceTime + "," + updates + "," + withdrawals + "," + drops + "," +
                   bestChanges + "," + routesChanged + "," +
                   exploration.Values.DefaultIfEmpty(0).Max();
        }
    }
    public record Hop(int owner, Topology.Prefix prefix, Topology.Link link) {}
    public record Forwarding(string result, List<int> visits, List<Hop> hops) {
        public int Count() { return hops.Count(hop => hop.link != null); }
        public int Arrival() { return hops[^1].owner; }
    }
    public record TraceStatus(string result, List<int> visits) {}
    public sealed class TraceRecord {
        public int index, start;
        public int? end;
        public TraceStatus status;
        public TraceRecord(int index, int start, TraceStatus status) {
            this.index = index;
            this.start = start;
            this.status = status;
        }
    }
    public record RingKey(Topology.Prefix prefix, string path) {}
    public sealed class RingRecord {
        public Topology.Prefix prefix;
        public List<int> path;
        public int start;
        public int? end;
        public RingRecord(Topology.Prefix prefix, List<int> path, int start) {
            this.prefix = prefix;
            this.path = path;
            this.start = start;
        }
    }
    public static bool SameStatus(TraceStatus a, TraceStatus b) =>
        ReferenceEquals(a, b) || a != null && b != null && a.result == b.result
                                     && a.visits.SequenceEqual(b.visits);
    public static List<int> Collapse(List<int> path) {
        List<int> result = new();
        foreach (int owner in path)
            if (result.Count == 0 || result[^1] != owner)
                result.Add(owner);
        return result;
    }
    public static int ValleyPosition(string pattern) {
        int p = 0;
        while (p < pattern.Length && pattern[p] == 'U')
            p++;
        if (p < pattern.Length && pattern[p] == 'P')
            p++;
        while (p < pattern.Length && pattern[p] == 'D')
            p++;
        return p;
    }
    public static string MessageText(Simulator.Message message) {
        return "#" + message.serial + " " + message.sender + "->" + message.receiver + " " +
               message.link.name + " " + message.prefix;
    }
    public sealed class Simulation {
        public Topology network;
        public Policy policies;
        public Dictionary<string, int> defaults;
        public int stepcap, time;
        public List<Simulator.Trace> traces;
        public SortedDictionary<int, Router> routers = new();
        public List<Session> sessions = new();
        public Dictionary<SessionKey, Session> bySession = new();
        public Simulator.MessageQueue messages = new Simulator.MessageQueue();
        public List<string> logs = new();
        public List<Period> periods = new();
        public SortedSet<Topology.Prefix> changedPrefixes = new();
        public List<TraceRecord> traceRecords = new();
        public Dictionary<int, TraceRecord> ongoingTraces = new();
        public List<RingRecord> ringRecords = new();
        public Dictionary<RingKey, RingRecord> ongoingRings = new();
        public Period period;
        public Simulation(Topology network, Policy policies, Simulator.Params settings) {
            this.network = network;
            this.policies = policies;
            defaults = settings.defaults;
            stepcap = settings.stepcap;
            traces = settings.traces;
            foreach (int owner in network.routerIds.Keys) {
                Router router = new Router(owner, network.atAs[owner]);
                routers[owner] = router;
                foreach (Session session in router.sessions) {
                    sessions.Add(session);
                    bySession[new SessionKey(owner, session.link.number)] = session;
                }
            }
        }
        public void Log(string content) { logs.Add(time + " " + content); }
        public Imported ImportRoute(Session session, Topology.Prefix prefix,
                                    Decision.Attribute attribute) {
            Policy.Rule rule = policies.Applied("IMPORT", session.owner, session.link, prefix,
                                                attribute.path, attribute.communities);
            int localPref = defaults[session.link.Role(session.owner)];
            if (rule != null && rule.Has("DENY"))
                return new Imported(null, rule);
            int med = attribute.med;
            List<Policy.Community> communities = attribute.communities;
            if (rule != null) {
                localPref = rule.Value("LOCALPREF", localPref);
                med = rule.Value("MED", med);
                communities = Policy.Edit(communities, rule);
            }
            return new Imported(new Decision.Route(attribute.path, attribute.origin, med,
                                                   communities, localPref, session.link),
                                rule);
        }
        public List<Decision.Route> Candidates(int owner, Topology.Prefix prefix) {
            List<Decision.Route> routes = new();
            foreach (Session session in routers[owner].sessions) {
                Decision.Attribute attribute = session.incoming.GetValueOrDefault(prefix);
                if (attribute != null) {
                    Decision.Route route = ImportRoute(session, prefix, attribute).route;
                    if (route != null)
                        routes.Add(route);
                }
            }
            return routes;
        }
        public Advertised Advertised(Session session, Topology.Prefix prefix) {
            int owner = session.owner;
            Topology.Link link = session.link;
            Decision.Route route = routers[owner].rib.GetValueOrDefault(prefix);
            if (route == null || !route.Local() && route.Neighbor() == link.Other(owner) ||
                route.communities.Contains(Policy.NO_EXPORT))
                return new Advertised(null, null);
            Policy.Rule rule =
                policies.Applied("EXPORT", owner, link, prefix, route.path, route.communities);
            if (rule != null && rule.Has("DENY"))
                return new Advertised(null, rule);
            bool allowed = rule != null && rule.Has("ALLOW");
            if (!allowed && !route.Local() && !route.link.Role(owner).Equals("customer") &&
                !link.Role(owner).Equals("customer"))
                return new Advertised(null, rule);
            int prepend = rule == null ? 0 : rule.Value("PREPEND", 0),
                med = rule == null ? 0 : rule.Value("MED", 0);
            List<Policy.Community> communities =
                rule == null ? route.communities : Policy.Edit(route.communities, rule);
            List<int> path = new(Enumerable.Repeat(owner, 1 + prepend));
            path.AddRange(route.path);
            return new Advertised(new Decision.Attribute(path, route.origin, med, communities),
                                  rule);
        }
        public void Redecide(int owner, Topology.Prefix prefix) {
            Router router = routers[owner];
            Decision.Route route = router.origination.GetValueOrDefault(prefix);
            if (route == null) {
                List<Decision.Route> candidates = Candidates(owner, prefix);
                if (candidates.Count != 0)
                    route = Decision.Best(candidates, network.routerIds).route;
            }
            if (object.Equals(router.rib.GetValueOrDefault(prefix), route))
                return;
            if (route == null)
                router.rib.Remove(prefix);
            else
                router.rib[prefix] = route;
            Log("BEST " + owner + " " + prefix + " " + Report.RouteText(route));
            router.changes++;
            period.bestChanges++;
            period.exploration.AddCount(new OwnerPrefix(owner, prefix), 1);
            period.bestLines.Add(new BestLine(time, owner, prefix, route));
            changedPrefixes.Add(prefix);
            foreach (Session session in router.sessions)
                if (session.link.up) {
                    session.pending.Add(prefix);
                    if (session.timer == null)
                        ProcessPending(session);
                }
        }
        public void ProcessPending(Session session) {
            int sent = 0;
            foreach (Topology.Prefix prefix in session.pending) {
                Advertised advertised = Advertised(session, prefix);
                Decision.Attribute content = advertised.content;
                if (object.Equals(session.outgoing.GetValueOrDefault(prefix), content))
                    continue;
                if (content == null)
                    session.outgoing.Remove(prefix);
                else
                    session.outgoing[prefix] = content;
                Simulator.Message message =
                    messages.Send(time, session.owner, session.link.Other(session.owner),
                                  session.link, prefix, content);
                string suffix =
                    content == null ? "WITHDRAW" : "ANNOUNCE " + Report.AttributeText(content);
                Log("SEND " + MessageText(message) + " " + suffix);
                session.sent++;
                sent++;
                period.updates++;
                if (content == null)
                    period.withdrawals++;
                if (advertised.rule != null)
                    advertised.rule.hits++;
            }
            session.pending.Clear();
            session.timer = sent > 0 && session.link.mrai >= 1 ? time + session.link.mrai : null;
        }
        public void Receive(Simulator.Message message) {
            Session session = bySession[new SessionKey(message.receiver, message.link.number)];
            Topology.Prefix prefix = message.prefix;
            Decision.Attribute content = message.content;
            session.received++;
            period.convergenceTime = time - period.eventRecord.time;
            string result;
            if (content == null) {
                session.incoming.Remove(prefix);
                result = "WITHDRAW";
            } else if (content.path.Contains(message.receiver)) {
                session.incoming.Remove(prefix);
                result = "ANNOUNCE loop";
            } else {
                session.incoming[prefix] = content;
                Imported imported = ImportRoute(session, prefix, content);
                Policy.Rule rule = imported.rule;
                if (rule != null)
                    rule.hits++;
                result = imported.route == null ? "ANNOUNCE deny " + rule.name
                         : rule == null         ? "ANNOUNCE accept"
                                                : "ANNOUNCE accept " + rule.name;
            }
            Log("RECV " + MessageText(message) + " " + result);
            Redecide(message.receiver, prefix);
        }
        public void Originate(int owner, Topology.Prefix prefix, string origin,
                              List<Policy.Community> communities) {
            routers[owner].origination[prefix] = Decision.Route.Originated(origin, communities);
            Redecide(owner, prefix);
        }
        public void LinkDown(Topology.Link link) {
            link.up = false;
            link.downCount++;
            foreach (Simulator.Message message in messages.RemoveLink(link)) {
                Log("DROP " + MessageText(message));
                period.drops++;
            }
            SortedDictionary<int, List<Topology.Prefix>> remembered = new();
            foreach (int owner in new int[] { Math.Min(link.first, link.second),
                                              Math.Max(link.first, link.second) }) {
                Session session = bySession[new SessionKey(owner, link.number)];
                remembered[owner] = new(session.incoming.Keys);
                session.incoming.Clear();
                session.outgoing.Clear();
                session.pending.Clear();
                session.timer = null;
            }
            foreach (var entry in remembered)
                foreach (Topology.Prefix prefix in entry.Value)
                    Redecide(entry.Key, prefix);
        }
        public void LinkUp(Topology.Link link) {
            link.up = true;
            foreach (int owner in new int[] { Math.Min(link.first, link.second),
                                              Math.Max(link.first, link.second) }) {
                Session session = bySession[new SessionKey(owner, link.number)];
                session.pending = new(routers[owner].rib.Keys);
                ProcessPending(session);
            }
        }
        public void ChangePolicy(Policy.Rule rule, bool active) {
            rule.active = active;
            Router router = routers[rule.owner];
            if (rule.direction.Equals("IMPORT")) {
                SortedSet<Topology.Prefix> prefixes = new();
                foreach (Session session in router.sessions)
                    prefixes.UnionWith(session.incoming.Keys);
                foreach (Topology.Prefix prefix in prefixes)
                    Redecide(rule.owner, prefix);
            } else
                foreach (Session session in router.sessions)
                    if (session.link.up) {
                        session.pending.UnionWith(router.rib.Keys);
                        session.pending.UnionWith(session.outgoing.Keys);
                        if (session.timer == null)
                            ProcessPending(session);
                    }
        }
        public void ExecuteEvent(Simulator.Event eventRecord) {
            Log("EVENT " + period.number + " " + eventRecord.text);
            string[] f = eventRecord.fields;
            switch (eventRecord.kind) {
            case "INITIAL":
                foreach (Topology.Initial initial in network.initial)
                    Originate(initial.owner, initial.prefix, initial.origin, initial.communities);
                break;
            case "ANNOUNCE":
                Originate(int.Parse(f[1]), Topology.ParsePrefix(f[2]), f[3],
                          Policy.Communities(f.Skip(4)));
                break;
            case "WITHDRAW": {
                int owner = int.Parse(f[1]);
                Topology.Prefix prefix = Topology.ParsePrefix(f[2]);
                routers[owner].origination.Remove(prefix);
                Redecide(owner, prefix);
                break;
            }
            case "LINK_DOWN":
                LinkDown(network.byName[f[2]]);
                break;
            case "LINK_UP":
                LinkUp(network.byName[f[2]]);
                break;
            default:
                ChangePolicy(policies.byName[f[2]], eventRecord.kind.Equals("POLICY_ON"));
                break;
            }
        }
        public string GlobalState() {
            StringBuilder state = new StringBuilder();
            foreach (Session session in sessions) {
                state.Append("I[");
                foreach (var entry in session.incoming)
                    state.Append(entry.Key)
                        .Append('=')
                        .Append(Report.AttributeText(entry.Value))
                        .Append(';');
                state.Append("]O[");
                foreach (var entry in session.outgoing)
                    state.Append(entry.Key)
                        .Append('=')
                        .Append(Report.AttributeText(entry.Value))
                        .Append(';');
                state.Append("]P[");
                foreach (Topology.Prefix prefix in session.pending)
                    state.Append(prefix).Append(';');
                state.Append("]T")
                    .Append(session.timer == null ? "-" : Convert.ToString(session.timer - time))
                    .Append('|');
            }
            state.Append("Q[");
            foreach (Simulator.Message message in messages.Ordered())
                state.Append(message.arrival - time)
                    .Append(',')
                    .Append(message.receiver)
                    .Append(',')
                    .Append(message.sender)
                    .Append(',')
                    .Append(message.link.number)
                    .Append(',')
                    .Append(message.prefix)
                    .Append('=')
                    .Append(message.content == null ? "WITHDRAW"
                                                    : Report.AttributeText(message.content))
                    .Append(';');
            return state.Append(']').ToString();
        }
        public void DetectDivergence() {
            if (period.divergence != null || period.deliveryTimes > stepcap)
                return;
            string state = GlobalState();
            if (!period.states.TryGetValue(state, out int first))
                period.states[state] = time;
            else {
                List<BestLine> cycle = new();
                foreach (BestLine line in period.bestLines)
                    if (first < line.time && line.time <= time)
                        cycle.Add(line);
                period.divergence = new Divergence(first, time, cycle);
            }
        }
        public bool Quiet() {
            return messages.NextTime() == null &&
                   sessions.All(session => session.pending.Count == 0);
        }
        public int NextMoment(int? boundary) {
            int next = boundary ?? int.MaxValue;
            int? delivery = messages.NextTime();
            if (delivery != null)
                next = Math.Min(next, delivery.Value);
            foreach (Session session in sessions)
                if (session.timer != null)
                    next = Math.Min(next, session.timer.Value);
            return next;
        }
        public void RunPeriod(int number, Simulator.Event eventRecord, int? boundary) {
            period = new Period(number, eventRecord, routers);
            periods.Add(period);
            time = eventRecord.time;
            changedPrefixes.Clear();
            ExecuteEvent(eventRecord);
            bool quiet;
            while (true) {
                bool delivered = false;
                while (object.Equals(messages.NextTime(), time)) {
                    Receive(messages.Take());
                    delivered = true;
                }
                foreach (Session session in sessions)
                    if (object.Equals(session.timer, time)) {
                        session.timer = null;
                        if (session.pending.Count != 0)
                            ProcessPending(session);
                    }
                if (changedPrefixes.Count != 0)
                    ForwardingChecks();
                if (delivered) {
                    period.deliveryTimes++;
                    DetectDivergence();
                }
                quiet = Quiet();
                if (boundary == null) {
                    if (quiet || period.divergence != null || period.deliveryTimes >= stepcap)
                        break;
                } else if (time == boundary)
                    break;
                time = NextMoment(boundary);
                changedPrefixes.Clear();
            }
            period.status = period.divergence != null ? "DIVERGENT"
                            : quiet                   ? "CONVERGED"
                            : boundary == null        ? "CAPPED"
                                                      : "UNSETTLED";
            period.Finish(routers);
            period.states.Clear();
        }
        public void Run(List<Simulator.Event> events) {
            for (int i = 0; i < events.Count; i++)
                RunPeriod(i, events[i], i + 1 < events.Count ? events[i + 1].time - 1 : null);
        }
        public Forwarding Trace(int source, long address) {
            List<int> visits = new();
            visits.Add(source);
            SortedSet<int> visited = new(visits);
            List<Hop> hops = new();
            int owner = source;
            while (true) {
                Topology.Prefix selected = null;
                foreach (Topology.Prefix prefix in routers[owner].rib.Keys)
                    if (prefix.Contains(address) &&
                        (selected == null || prefix.length > selected.length))
                        selected = prefix;
                if (selected == null)
                    return new Forwarding(hops.Count == 0 ? "UNREACHABLE" : "BLACKHOLE", visits,
                                          hops);
                Decision.Route route = routers[owner].rib[selected];
                hops.Add(new Hop(owner, selected, route.link));
                if (route.Local())
                    return new Forwarding("DELIVERED", visits, hops);
                owner = route.link.Other(owner);
                visits.Add(owner);
                if (!visited.Add(owner))
                    return new Forwarding("LOOP", visits, hops);
            }
        }
        public Dictionary<string, List<int>> PrefixLoops(Topology.Prefix prefix) {
            Dictionary<int, int> arrows = new();
            foreach (Router router in routers.Values) {
                Decision.Route route = router.rib.GetValueOrDefault(prefix);
                if (route != null && !route.Local())
                    arrows[router.owner] = route.link.Other(router.owner);
            }
            HashSet<int> finished = new();
            Dictionary<string, List<int>> loops = new(StringComparer.Ordinal);
            foreach (int start in network.routerIds.Keys) {
                if (finished.Contains(start))
                    continue;
                List<int> path = new();
                Dictionary<int, int> positions = new();
                int current = start;
                while (arrows.ContainsKey(current) && !finished.Contains(current) &&
                       !positions.ContainsKey(current)) {
                    positions[current] = path.Count;
                    path.Add(current);
                    current = arrows[current];
                }
                if (positions.TryGetValue(current, out int position)) {
                    List<int> cycle = path.Skip(position).ToList();
                    int first = cycle.IndexOf(cycle.Min());
                    List<int> rotated = cycle.Skip(first).Concat(cycle.Take(first)).ToList();
                    loops[Report.PathText(rotated)] = rotated;
                }
                finished.UnionWith(path);
            }
            return loops;
        }
        public void ForwardingChecks() {
            foreach (Topology.Prefix prefix in changedPrefixes) {
                Dictionary<string, List<int>> loops = PrefixLoops(prefix);
                foreach (var entry in ongoingRings.ToList())
                    if (entry.Key.prefix.Equals(prefix) && !loops.ContainsKey(entry.Key.path)) {
                        entry.Value.end = time;
                        ongoingRings.Remove(entry.Key);
                    }
                foreach (List<int> loop in loops.Values.OrderBy(path => path[0])) {
                    RingKey key = new(prefix, Report.PathText(loop));
                    if (!ongoingRings.ContainsKey(key)) {
                        RingRecord record = new(prefix, loop, time);
                        ringRecords.Add(record);
                        ongoingRings[key] = record;
                    }
                }
            }
            for (int index = 0; index < traces.Count; index++) {
                Simulator.Trace trace = traces[index];
                Forwarding path = Trace(trace.source, trace.value);
                TraceStatus status = path.result.Equals("LOOP") || path.result.Equals("BLACKHOLE")
                                         ? new TraceStatus(path.result, new List<int>(path.visits))
                                         : null;
                TraceRecord record = ongoingTraces.GetValueOrDefault(index);
                if (record != null && !SameStatus(record.status, status)) {
                    record.end = time;
                    ongoingTraces.Remove(index);
                }
                if (status != null && !ongoingTraces.ContainsKey(index)) {
                    TraceRecord created = new TraceRecord(index, time, status);
                    traceRecords.Add(created);
                    ongoingTraces[index] = created;
                }
            }
        }
        public List<string> RibLines() {
            List<string> lines = new();
            foreach (Router router in routers.Values) {
                int local = router.rib.Values.Count(route => route.Local()),
                    sent = router.sessions.Sum(session => session.sent),
                    received = router.sessions.Sum(session => session.received);
                lines.Add("AS " + router.owner + " routes " + router.rib.Count + " local " + local +
                          " sent " + sent + " received " + received + " changes " + router.changes);
                foreach (Session session in router.sessions) {
                    int accepted = 0;
                    foreach (var entry in session.incoming)
                        if (ImportRoute(session, entry.Key, entry.Value).route != null)
                            accepted++;
                    Topology.Link link = session.link;
                    lines.Add("SESSION " + link.name + " " + link.Other(router.owner) + " " +
                              link.Role(router.owner) + " " + (link.up ? "UP" : "DOWN") + " in " +
                              session.incoming.Count + " accepted " + accepted + " out " +
                              session.outgoing.Count + " sent " + session.sent + " received " +
                              session.received + " flaps " + link.downCount);
                }
                foreach (var entry in router.rib) {
                    Topology.Prefix prefix = entry.Key;
                    Decision.Route route = entry.Value;
                    List<Decision.Route> candidates = Candidates(router.owner, prefix);
                    string line =
                        prefix + " " + Report.RouteText(route) + " candidates " + candidates.Count;
                    if (!route.Local())
                        line += " reason " + Decision.Best(candidates, network.routerIds).reason;
                    lines.Add(line);
                    candidates.RemoveAll(candidate => route.Equals(candidate));
                    while (candidates.Count != 0) {
                        Decision.Route alternate =
                            Decision.Best(candidates, network.routerIds).route;
                        lines.Add("ALT " + Report.RouteText(alternate));
                        candidates.Remove(alternate);
                    }
                }
            }
            return lines;
        }
        public List<string> TraceLines(Simulator.Trace trace) {
            Forwarding path = Trace(trace.source, trace.value);
            List<string> lines = new();
            lines.Add("TRACE " + trace.source + " " + trace.address + " " + path.result + " hops " +
                      path.Count());
            foreach (Hop hop in path.hops) {
                string beginning = "HOP " + hop.owner + " " + hop.prefix;
                lines.Add(beginning + (hop.link == null ? " LOCAL"
                                                        : " next " + hop.link.Other(hop.owner) +
                                                              " link " + hop.link.name));
            }
            if (path.result.Equals("LOOP"))
                lines.Add("HOP " + path.visits[^1] + " REVISIT");
            else if (path.result.Equals("BLACKHOLE") || path.result.Equals("UNREACHABLE"))
                lines.Add("HOP " + path.visits[^1] + " NOROUTE");
            if (path.hops.Count == 0)
                lines.Add("CONTROL NONE");
            else {
                Decision.Route route = routers[trace.source].rib[path.hops[0].prefix];
                string notation = route.Local() ? "LOCAL" : Report.PathText(route.path);
                bool match = path.result.Equals("DELIVERED") &&
                             Collapse(route.path)
                                 .SequenceEqual(path.visits.GetRange(1, path.visits.Count - 1));
                lines.Add("CONTROL " + notation + " " + (match ? "MATCH" : "MISMATCH"));
            }
            if (path.Count() > 0) {
                StringBuilder pattern = new StringBuilder();
                foreach (Hop hop in path.hops)
                    if (hop.link != null)
                        pattern.Append(hop.link.Direction(hop.owner));
                string value = pattern.ToString();
                lines.Add("PATTERN " + value + " " +
                          (ValleyPosition(value) == value.Length ? "VALLEYFREE" : "VALLEY"));
            }
            return lines;
        }
        public List<string> PathLines() {
            List<string> lines = new();
            foreach (Simulator.Trace trace in traces)
                lines.AddRange(TraceLines(trace));
            SortedSet<Topology.Prefix> prefixes = new();
            foreach (Router router in routers.Values)
                prefixes.UnionWith(router.origination.Keys);
            string names = string.Join(",", prefixes);
            lines.Add("PREFIXES" + (names.Length == 0 ? "" : " " + names));
            foreach (int source in network.routerIds.Keys) {
                StringBuilder symbols = new StringBuilder();
                foreach (Topology.Prefix prefix in prefixes) {
                    Forwarding path = Trace(source, prefix.address);
                    char symbol;
                    if (path.result.Equals("DELIVERED"))
                        symbol = path.Count() == 0                                         ? '*'
                                 : routers[path.Arrival()].origination.ContainsKey(prefix) ? '+'
                                                                                           : 'X';
                    else
                        symbol = path.result switch { "LOOP" => 'L', "BLACKHOLE" => 'B',
                                                      _ => 'U' };
                    symbols.Append(symbol);
                }
                lines.Add("REACH " + source + (symbols.Length == 0 ? "" : " " + symbols));
            }
            return lines;
        }
        public List<string> AuditLines() {
            List<string> lines = new();
            int loops = 0, blackholes = 0;
            traceRecords.Sort((a, b) => {
                int c = a.start.CompareTo(b.start);
                return c != 0 ? c : a.index.CompareTo(b.index);
            });
            foreach (TraceRecord record in traceRecords) {
                Simulator.Trace trace = traces[record.index];
                string result = record.status.result;
                List<int> visits = record.status.visits;
                if (result.Equals("LOOP"))
                    loops++;
                else
                    blackholes++;
                string line = result + " " + trace.source + " " + trace.address + " from " +
                              record.start + " to " + (record.end?.ToString() ?? "END");
                if (result.Equals("BLACKHOLE"))
                    line += " at " + visits[^1];
                lines.Add(line + " path " + Report.PathText(visits));
            }
            ringRecords.Sort((a, b) => {
                int c = a.start.CompareTo(b.start);
                if (c == 0)
                    c = a.prefix.CompareTo(b.prefix);
                return c != 0 ? c : a.path[0].CompareTo(b.path[0]);
            });
            foreach (RingRecord record in ringRecords)
                lines.Add("RING " + record.prefix + " from " + record.start + " to " +
                          (record.end?.ToString() ?? "END") + " path " +
                          Report.PathText(record.path));
            int routes = 0, valleys = 0;
            foreach (Router router in routers.Values)
                foreach (var entry in router.rib) {
                    Decision.Route route = entry.Value;
                    if (route.Local())
                        continue;
                    routes++;
                    List<int> full = new();
                    full.Add(router.owner);
                    full.AddRange(route.path);
                    List<int> path = Collapse(full);
                    StringBuilder pattern = new StringBuilder();
                    for (int i = 0; i + 1 < path.Count; i++)
                        pattern.Append(network.Connecting(path[i], path[i + 1]).Direction(path[i]));
                    string word = pattern.ToString();
                    int violation = ValleyPosition(word);
                    if (violation != word.Length) {
                        valleys++;
                        lines.Add("VALLEY " + router.owner + " " + entry.Key + " path " +
                                  Report.PathText(route.path) + " pattern " + word + " leaker " +
                                  path[violation]);
                    }
                }
            foreach (Policy.Rule rule in policies.rules)
                lines.Add("RULE " + rule.name + " " + rule.direction + " " +
                          (rule.active ? "ON" : "OFF") + " hits " + rule.hits);
            int divergent = 0;
            foreach (Period period in periods) {
                if (period.divergence == null)
                    continue;
                divergent++;
                Divergence divergence = period.divergence;
                lines.Add("DIVERGENT event " + period.number + " first " + divergence.first +
                          " repeat " + divergence.repeat + " period " +
                          (divergence.repeat - divergence.first));
                SortedDictionary<OwnerPrefix, int> oscillations = new();
                foreach (BestLine line in divergence.cycle) {
                    lines.Add("CYCLE " + line.time + " " + line.owner + " " + line.prefix + " " +
                              Report.RouteText(line.route));
                    oscillations.AddCount(new OwnerPrefix(line.owner, line.prefix), 1);
                }
                foreach (var entry in oscillations)
                    lines.Add("OSCILLATE " + entry.Key.owner + " " + entry.Key.prefix +
                              " changes " + entry.Value);
            }
            lines.Add("SUMMARY loops " + loops + " blackholes " + blackholes + " rings " +
                      ringRecords.Count + " routes " + routes + " valleys " + valleys +
                      " divergent " + divergent + " end " + time);
            return lines;
        }
        public void WriteOutputs() {
            Report.Write("updates.txt", logs);
            List<string> csv = new();
            csv.Add(HEADER);
            foreach (Period period in periods)
                csv.Add(period.Csv());
            Report.Write("convergence.csv", csv);
            Report.Write("ribs.txt", RibLines());
            Report.Write("paths.txt", PathLines());
            Report.Write("audit.txt", AuditLines());
        }
    }
    public static void Main(string[] args) {
        CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
        Topology network = new Topology();
        Policy policies = new Policy();
        Simulation simulation = new Simulation(network, policies, Simulator.ReadParams());
        simulation.Run(Simulator.Events());
        simulation.WriteOutputs();
    }
}
public static class CountHelpers {
    public static void AddCount<K>(this IDictionary<K, int> values, K key, int amount) {
        values.TryGetValue(key, out int value);
        values[key] = value + amount;
    }
}
