import java.util.*;
public final class Main {
    static final String HEADER =
        "event,time,kind,status,convergence_time,updates,withdrawals,drops,best_changes,routes_changed,max_exploration";
    record SessionKey(int owner, int link) {}
    record OwnerPrefix(int owner, Topology.Prefix prefix) implements Comparable<OwnerPrefix> {
        public int compareTo(OwnerPrefix other) {
            int c = Integer.compare(owner, other.owner);
            return c != 0 ? c : prefix.compareTo(other.prefix);
        }
    }
    record Imported(Decision.Route route, Policy.Rule rule) {}
    record Advertised(Decision.Attribute content, Policy.Rule rule) {}
    record BestLine(int time, int owner, Topology.Prefix prefix, Decision.Route route) {}
    record Divergence(int first, int repeat, List<BestLine> cycle) {}
    static final class Session {
        int owner, sent, received;
        Topology.Link link;
        Map<Topology.Prefix, Decision.Attribute> incoming = new TreeMap<>(), outgoing =
                                                                                 new TreeMap<>();
        Set<Topology.Prefix> pending = new TreeSet<>();
        Integer timer;
        Session(int owner, Topology.Link link) {
            this.owner = owner;
            this.link = link;
        }
    }
    static final class Router {
        int owner, changes;
        Map<Topology.Prefix, Decision.Route> origination = new TreeMap<>(), rib = new TreeMap<>();
        List<Session> sessions = new ArrayList<>();
        Router(int owner, List<Topology.Link> links) {
            this.owner = owner;
            for (Topology.Link link : links)
                sessions.add(new Session(owner, link));
        }
    }
    static final class Period {
        int number, updates, withdrawals, drops, bestChanges, routesChanged, convergenceTime,
            deliveryTimes;
        Simulator.Event event;
        Map<Integer, Map<Topology.Prefix, Decision.Route>> before = new TreeMap<>();
        Map<OwnerPrefix, Integer> exploration = new TreeMap<>();
        List<BestLine> bestLines = new ArrayList<>();
        Map<String, Integer> states = new HashMap<>();
        Divergence divergence;
        String status;
        Period(int number, Simulator.Event event, Map<Integer, Router> routers) {
            this.number = number;
            this.event = event;
            for (Router router : routers.values())
                before.put(router.owner, new TreeMap<>(router.rib));
        }
        void finish(Map<Integer, Router> routers) {
            for (Router router : routers.values()) {
                Set<Topology.Prefix> prefixes = new TreeSet<>(before.get(router.owner).keySet());
                prefixes.addAll(router.rib.keySet());
                for (Topology.Prefix prefix : prefixes)
                    if (!Objects.equals(before.get(router.owner).get(prefix),
                                        router.rib.get(prefix)))
                        routesChanged++;
            }
        }
        String csv() {
            return number + "," + event.time() + "," + event.kind() + "," + status + "," +
                convergenceTime + "," + updates + "," + withdrawals + "," + drops + "," +
                bestChanges + "," + routesChanged + "," +
                exploration.values().stream().mapToInt(Integer::intValue).max().orElse(0);
        }
    }
    record Hop(int owner, Topology.Prefix prefix, Topology.Link link) {}
    record Forwarding(String result, List<Integer> visits, List<Hop> hops) {
        int count() { return (int)hops.stream().filter(hop -> hop.link() != null).count(); }
        int arrival() { return hops.getLast().owner(); }
    }
    record TraceStatus(String result, List<Integer> visits) {}
    static final class TraceRecord {
        int index, start;
        Integer end;
        TraceStatus status;
        TraceRecord(int index, int start, TraceStatus status) {
            this.index = index;
            this.start = start;
            this.status = status;
        }
    }
    record RingKey(Topology.Prefix prefix, List<Integer> path) {}
    static final class RingRecord {
        Topology.Prefix prefix;
        List<Integer> path;
        int start;
        Integer end;
        RingRecord(Topology.Prefix prefix, List<Integer> path, int start) {
            this.prefix = prefix;
            this.path = path;
            this.start = start;
        }
    }
    static List<Integer> collapse(List<Integer> path) {
        List<Integer> result = new ArrayList<>();
        for (int owner : path)
            if (result.isEmpty() || result.getLast() != owner)
                result.add(owner);
        return result;
    }
    static int valleyPosition(String pattern) {
        int p = 0;
        while (p < pattern.length() && pattern.charAt(p) == 'U')
            p++;
        if (p < pattern.length() && pattern.charAt(p) == 'P')
            p++;
        while (p < pattern.length() && pattern.charAt(p) == 'D')
            p++;
        return p;
    }
    static String messageText(Simulator.Message message) {
        return "#" + message.serial() + " " + message.sender() + "->" + message.receiver() + " " +
            message.link().name + " " + message.prefix();
    }
    static final class Simulation {
        Topology network;
        Policy policies;
        Map<String, Integer> defaults;
        int stepcap, time;
        List<Simulator.Trace> traces;
        Map<Integer, Router> routers = new TreeMap<>();
        List<Session> sessions = new ArrayList<>();
        Map<SessionKey, Session> bySession = new HashMap<>();
        Simulator.MessageQueue messages = new Simulator.MessageQueue();
        List<String> logs = new ArrayList<>();
        List<Period> periods = new ArrayList<>();
        Set<Topology.Prefix> changedPrefixes = new TreeSet<>();
        List<TraceRecord> traceRecords = new ArrayList<>();
        Map<Integer, TraceRecord> ongoingTraces = new HashMap<>();
        List<RingRecord> ringRecords = new ArrayList<>();
        Map<RingKey, RingRecord> ongoingRings = new HashMap<>();
        Period period;
        Simulation(Topology network, Policy policies, Simulator.Params params) {
            this.network = network;
            this.policies = policies;
            defaults = params.defaults();
            stepcap = params.stepcap();
            traces = params.traces();
            for (int owner : network.routerIds.keySet()) {
                Router router = new Router(owner, network.atAs.get(owner));
                routers.put(owner, router);
                for (Session session : router.sessions) {
                    sessions.add(session);
                    bySession.put(new SessionKey(owner, session.link.number), session);
                }
            }
        }
        void log(String content) { logs.add(time + " " + content); }
        Imported importRoute(Session session, Topology.Prefix prefix,
                             Decision.Attribute attribute) {
            Policy.Rule rule = policies.applied("IMPORT", session.owner, session.link, prefix,
                                                attribute.path(), attribute.communities());
            int localPref = defaults.get(session.link.role(session.owner));
            if (rule != null && rule.has("DENY"))
                return new Imported(null, rule);
            int med = attribute.med();
            List<Policy.Community> communities = attribute.communities();
            if (rule != null) {
                localPref = rule.value("LOCALPREF", localPref);
                med = rule.value("MED", med);
                communities = Policy.edit(communities, rule);
            }
            return new Imported(new Decision.Route(attribute.path(), attribute.origin(), med,
                                                   communities, localPref, session.link),
                                rule);
        }
        List<Decision.Route> candidates(int owner, Topology.Prefix prefix) {
            List<Decision.Route> routes = new ArrayList<>();
            for (Session session : routers.get(owner).sessions) {
                Decision.Attribute attribute = session.incoming.get(prefix);
                if (attribute != null) {
                    Decision.Route route = importRoute(session, prefix, attribute).route();
                    if (route != null)
                        routes.add(route);
                }
            }
            return routes;
        }
        Advertised advertised(Session session, Topology.Prefix prefix) {
            int owner = session.owner;
            Topology.Link link = session.link;
            Decision.Route route = routers.get(owner).rib.get(prefix);
            if (route == null || !route.local() && route.neighbor() == link.other(owner) ||
                route.communities().contains(Policy.NO_EXPORT))
                return new Advertised(null, null);
            Policy.Rule rule =
                policies.applied("EXPORT", owner, link, prefix, route.path(), route.communities());
            if (rule != null && rule.has("DENY"))
                return new Advertised(null, rule);
            boolean allowed = rule != null && rule.has("ALLOW");
            if (!allowed && !route.local() && !route.link().role(owner).equals("customer") &&
                !link.role(owner).equals("customer"))
                return new Advertised(null, rule);
            int prepend = rule == null ? 0 : rule.value("PREPEND", 0),
                med = rule == null ? 0 : rule.value("MED", 0);
            List<Policy.Community> communities =
                rule == null ? route.communities() : Policy.edit(route.communities(), rule);
            List<Integer> path = new ArrayList<>(Collections.nCopies(1 + prepend, owner));
            path.addAll(route.path());
            return new Advertised(new Decision.Attribute(path, route.origin(), med, communities),
                                  rule);
        }
        void redecide(int owner, Topology.Prefix prefix) {
            Router router = routers.get(owner);
            Decision.Route route = router.origination.get(prefix);
            if (route == null) {
                List<Decision.Route> candidates = candidates(owner, prefix);
                if (!candidates.isEmpty())
                    route = Decision.best(candidates, network.routerIds).route();
            }
            if (Objects.equals(router.rib.get(prefix), route))
                return;
            if (route == null)
                router.rib.remove(prefix);
            else
                router.rib.put(prefix, route);
            log("BEST " + owner + " " + prefix + " " + Report.route(route));
            router.changes++;
            period.bestChanges++;
            period.exploration.merge(new OwnerPrefix(owner, prefix), 1, Integer::sum);
            period.bestLines.add(new BestLine(time, owner, prefix, route));
            changedPrefixes.add(prefix);
            for (Session session : router.sessions)
                if (session.link.up) {
                    session.pending.add(prefix);
                    if (session.timer == null)
                        processPending(session);
                }
        }
        void processPending(Session session) {
            int sent = 0;
            for (Topology.Prefix prefix : session.pending) {
                Advertised advertised = advertised(session, prefix);
                Decision.Attribute content = advertised.content();
                if (Objects.equals(session.outgoing.get(prefix), content))
                    continue;
                if (content == null)
                    session.outgoing.remove(prefix);
                else
                    session.outgoing.put(prefix, content);
                Simulator.Message message =
                    messages.send(time, session.owner, session.link.other(session.owner),
                                  session.link, prefix, content);
                String suffix =
                    content == null ? "WITHDRAW" : "ANNOUNCE " + Report.attribute(content);
                log("SEND " + messageText(message) + " " + suffix);
                session.sent++;
                sent++;
                period.updates++;
                if (content == null)
                    period.withdrawals++;
                if (advertised.rule() != null)
                    advertised.rule().hits++;
            }
            session.pending.clear();
            session.timer = sent > 0 && session.link.mrai >= 1 ? time + session.link.mrai : null;
        }
        void receive(Simulator.Message message) {
            Session session =
                bySession.get(new SessionKey(message.receiver(), message.link().number));
            Topology.Prefix prefix = message.prefix();
            Decision.Attribute content = message.content();
            session.received++;
            period.convergenceTime = time - period.event.time();
            String result;
            if (content == null) {
                session.incoming.remove(prefix);
                result = "WITHDRAW";
            } else if (content.path().contains(message.receiver())) {
                session.incoming.remove(prefix);
                result = "ANNOUNCE loop";
            } else {
                session.incoming.put(prefix, content);
                Imported imported = importRoute(session, prefix, content);
                Policy.Rule rule = imported.rule();
                if (rule != null)
                    rule.hits++;
                result = imported.route() == null ? "ANNOUNCE deny " + rule.name
                         : rule == null           ? "ANNOUNCE accept"
                                                  : "ANNOUNCE accept " + rule.name;
            }
            log("RECV " + messageText(message) + " " + result);
            redecide(message.receiver(), prefix);
        }
        void originate(int owner, Topology.Prefix prefix, String origin,
                       List<Policy.Community> communities) {
            routers.get(owner).origination.put(prefix,
                                               Decision.Route.originated(origin, communities));
            redecide(owner, prefix);
        }
        void linkDown(Topology.Link link) {
            link.up = false;
            link.downCount++;
            for (Simulator.Message message : messages.removeLink(link)) {
                log("DROP " + messageText(message));
                period.drops++;
            }
            Map<Integer, List<Topology.Prefix>> remembered = new TreeMap<>();
            for (int owner :
                 new int[] {Math.min(link.first, link.second), Math.max(link.first, link.second)}) {
                Session session = bySession.get(new SessionKey(owner, link.number));
                remembered.put(owner, new ArrayList<>(session.incoming.keySet()));
                session.incoming.clear();
                session.outgoing.clear();
                session.pending.clear();
                session.timer = null;
            }
            for (var entry : remembered.entrySet())
                for (Topology.Prefix prefix : entry.getValue())
                    redecide(entry.getKey(), prefix);
        }
        void linkUp(Topology.Link link) {
            link.up = true;
            for (int owner :
                 new int[] {Math.min(link.first, link.second), Math.max(link.first, link.second)}) {
                Session session = bySession.get(new SessionKey(owner, link.number));
                session.pending = new TreeSet<>(routers.get(owner).rib.keySet());
                processPending(session);
            }
        }
        void changePolicy(Policy.Rule rule, boolean active) {
            rule.active = active;
            Router router = routers.get(rule.owner);
            if (rule.direction.equals("IMPORT")) {
                Set<Topology.Prefix> prefixes = new TreeSet<>();
                for (Session session : router.sessions)
                    prefixes.addAll(session.incoming.keySet());
                for (Topology.Prefix prefix : prefixes)
                    redecide(rule.owner, prefix);
            } else
                for (Session session : router.sessions)
                    if (session.link.up) {
                        session.pending.addAll(router.rib.keySet());
                        session.pending.addAll(session.outgoing.keySet());
                        if (session.timer == null)
                            processPending(session);
                    }
        }
        void executeEvent(Simulator.Event event) {
            log("EVENT " + period.number + " " + event.text());
            String[] f = event.fields();
            switch (event.kind()) {
            case "INITIAL":
                for (Topology.Initial initial : network.initial)
                    originate(initial.owner(), initial.prefix(), initial.origin(),
                              initial.communities());
                break;
            case "ANNOUNCE":
                originate(Integer.parseInt(f[1]), Topology.prefix(f[2]), f[3],
                          Policy.communities(Arrays.asList(f).subList(4, f.length)));
                break;
            case "WITHDRAW": {
                int owner = Integer.parseInt(f[1]);
                Topology.Prefix prefix = Topology.prefix(f[2]);
                routers.get(owner).origination.remove(prefix);
                redecide(owner, prefix);
                break;
            }
            case "LINK_DOWN":
                linkDown(network.byName.get(f[2]));
                break;
            case "LINK_UP":
                linkUp(network.byName.get(f[2]));
                break;
            default:
                changePolicy(policies.byName.get(f[2]), event.kind().equals("POLICY_ON"));
                break;
            }
        }
        String globalState() {
            StringBuilder state = new StringBuilder();
            for (Session session : sessions) {
                state.append("I[");
                for (var entry : session.incoming.entrySet())
                    state.append(entry.getKey())
                        .append('=')
                        .append(Report.attribute(entry.getValue()))
                        .append(';');
                state.append("]O[");
                for (var entry : session.outgoing.entrySet())
                    state.append(entry.getKey())
                        .append('=')
                        .append(Report.attribute(entry.getValue()))
                        .append(';');
                state.append("]P[");
                for (Topology.Prefix prefix : session.pending)
                    state.append(prefix).append(';');
                state.append("]T")
                    .append(session.timer == null ? "-" : Integer.toString(session.timer - time))
                    .append('|');
            }
            state.append("Q[");
            for (Simulator.Message message : messages.ordered())
                state.append(message.arrival() - time)
                    .append(',')
                    .append(message.receiver())
                    .append(',')
                    .append(message.sender())
                    .append(',')
                    .append(message.link().number)
                    .append(',')
                    .append(message.prefix())
                    .append('=')
                    .append(message.content() == null ? "WITHDRAW"
                                                      : Report.attribute(message.content()))
                    .append(';');
            return state.append(']').toString();
        }
        void detectDivergence() {
            if (period.divergence != null || period.deliveryTimes > stepcap)
                return;
            String state = globalState();
            Integer first = period.states.get(state);
            if (first == null)
                period.states.put(state, time);
            else {
                List<BestLine> cycle = new ArrayList<>();
                for (BestLine line : period.bestLines)
                    if (first < line.time() && line.time() <= time)
                        cycle.add(line);
                period.divergence = new Divergence(first, time, cycle);
            }
        }
        boolean quiet() {
            return messages.nextTime() == null &&
                sessions.stream().allMatch(session -> session.pending.isEmpty());
        }
        int nextMoment(Integer boundary) {
            int next = boundary == null ? Integer.MAX_VALUE : boundary;
            Integer delivery = messages.nextTime();
            if (delivery != null)
                next = Math.min(next, delivery);
            for (Session session : sessions)
                if (session.timer != null)
                    next = Math.min(next, session.timer);
            return next;
        }
        void runPeriod(int number, Simulator.Event event, Integer boundary) {
            period = new Period(number, event, routers);
            periods.add(period);
            time = event.time();
            changedPrefixes.clear();
            executeEvent(event);
            boolean quiet;
            while (true) {
                boolean delivered = false;
                while (Objects.equals(messages.nextTime(), time)) {
                    receive(messages.take());
                    delivered = true;
                }
                for (Session session : sessions)
                    if (Objects.equals(session.timer, time)) {
                        session.timer = null;
                        if (!session.pending.isEmpty())
                            processPending(session);
                    }
                if (!changedPrefixes.isEmpty())
                    forwardingChecks();
                if (delivered) {
                    period.deliveryTimes++;
                    detectDivergence();
                }
                quiet = quiet();
                if (boundary == null) {
                    if (quiet || period.divergence != null || period.deliveryTimes >= stepcap)
                        break;
                } else if (time == boundary)
                    break;
                time = nextMoment(boundary);
                changedPrefixes.clear();
            }
            period.status = period.divergence != null ? "DIVERGENT"
                            : quiet                   ? "CONVERGED"
                            : boundary == null        ? "CAPPED"
                                                      : "UNSETTLED";
            period.finish(routers);
            period.states.clear();
        }
        void run(List<Simulator.Event> events) {
            for (int i = 0; i < events.size(); i++)
                runPeriod(i, events.get(i),
                          i + 1 < events.size() ? events.get(i + 1).time() - 1 : null);
        }
        Forwarding trace(int source, long address) {
            List<Integer> visits = new ArrayList<>();
            visits.add(source);
            Set<Integer> visited = new HashSet<>(visits);
            List<Hop> hops = new ArrayList<>();
            int owner = source;
            while (true) {
                Topology.Prefix selected = null;
                for (Topology.Prefix prefix : routers.get(owner).rib.keySet())
                    if (prefix.contains(address) &&
                        (selected == null || prefix.length() > selected.length()))
                        selected = prefix;
                if (selected == null)
                    return new Forwarding(hops.isEmpty() ? "UNREACHABLE" : "BLACKHOLE", visits,
                                          hops);
                Decision.Route route = routers.get(owner).rib.get(selected);
                hops.add(new Hop(owner, selected, route.link()));
                if (route.local())
                    return new Forwarding("DELIVERED", visits, hops);
                owner = route.link().other(owner);
                visits.add(owner);
                if (!visited.add(owner))
                    return new Forwarding("LOOP", visits, hops);
            }
        }
        Set<List<Integer>> prefixLoops(Topology.Prefix prefix) {
            Map<Integer, Integer> arrows = new HashMap<>();
            for (Router router : routers.values()) {
                Decision.Route route = router.rib.get(prefix);
                if (route != null && !route.local())
                    arrows.put(router.owner, route.link().other(router.owner));
            }
            Set<Integer> finished = new HashSet<>();
            Set<List<Integer>> loops = new HashSet<>();
            for (int start : network.routerIds.keySet()) {
                if (finished.contains(start))
                    continue;
                List<Integer> path = new ArrayList<>();
                Map<Integer, Integer> positions = new HashMap<>();
                int current = start;
                while (arrows.containsKey(current) && !finished.contains(current) &&
                       !positions.containsKey(current)) {
                    positions.put(current, path.size());
                    path.add(current);
                    current = arrows.get(current);
                }
                if (positions.containsKey(current)) {
                    List<Integer> cycle = path.subList(positions.get(current), path.size());
                    int first = cycle.indexOf(Collections.min(cycle));
                    List<Integer> rotated = new ArrayList<>(cycle.subList(first, cycle.size()));
                    rotated.addAll(cycle.subList(0, first));
                    loops.add(List.copyOf(rotated));
                }
                finished.addAll(path);
            }
            return loops;
        }
        void forwardingChecks() {
            for (Topology.Prefix prefix : changedPrefixes) {
                Set<List<Integer>> loops = prefixLoops(prefix);
                Iterator<Map.Entry<RingKey, RingRecord>> iterator =
                    ongoingRings.entrySet().iterator();
                while (iterator.hasNext()) {
                    var entry = iterator.next();
                    if (entry.getKey().prefix().equals(prefix) &&
                        !loops.contains(entry.getKey().path())) {
                        entry.getValue().end = time;
                        iterator.remove();
                    }
                }
                List<List<Integer>> ordered = new ArrayList<>(loops);
                ordered.sort(Comparator.comparingInt(path -> path.getFirst()));
                for (List<Integer> loop : ordered) {
                    RingKey key = new RingKey(prefix, loop);
                    if (!ongoingRings.containsKey(key)) {
                        RingRecord record = new RingRecord(prefix, loop, time);
                        ringRecords.add(record);
                        ongoingRings.put(key, record);
                    }
                }
            }
            for (int index = 0; index < traces.size(); index++) {
                Simulator.Trace trace = traces.get(index);
                Forwarding path = trace(trace.source(), trace.value());
                TraceStatus status =
                    path.result().equals("LOOP") || path.result().equals("BLACKHOLE")
                        ? new TraceStatus(path.result(), List.copyOf(path.visits()))
                        : null;
                TraceRecord record = ongoingTraces.get(index);
                if (record != null && !record.status.equals(status)) {
                    record.end
                    = time;
                    ongoingTraces.remove(index);
                }
                if (status != null && !ongoingTraces.containsKey(index)) {
                    TraceRecord created = new TraceRecord(index, time, status);
                    traceRecords.add(created);
                    ongoingTraces.put(index, created);
                }
            }
        }
        List<String> ribLines() {
            List<String> lines = new ArrayList<>();
            for (Router router : routers.values()) {
                int local = (int)router.rib.values().stream().filter(Decision.Route::local).count(),
                    sent = router.sessions.stream().mapToInt(session -> session.sent).sum(),
                    received = router.sessions.stream().mapToInt(session -> session.received).sum();
                lines.add("AS " + router.owner + " routes " + router.rib.size() + " local " +
                          local + " sent " + sent + " received " + received + " changes " +
                          router.changes);
                for (Session session : router.sessions) {
                    int accepted = 0;
                    for (var entry : session.incoming.entrySet())
                        if (importRoute(session, entry.getKey(), entry.getValue()).route() != null)
                            accepted++;
                    Topology.Link link = session.link;
                    lines.add("SESSION " + link.name + " " + link.other(router.owner) + " " +
                              link.role(router.owner) + " " + (link.up ? "UP" : "DOWN") + " in " +
                              session.incoming.size() + " accepted " + accepted + " out " +
                              session.outgoing.size() + " sent " + session.sent + " received " +
                              session.received + " flaps " + link.downCount);
                }
                for (var entry : router.rib.entrySet()) {
                    Topology.Prefix prefix = entry.getKey();
                    Decision.Route route = entry.getValue();
                    List<Decision.Route> candidates = candidates(router.owner, prefix);
                    String line =
                        prefix + " " + Report.route(route) + " candidates " + candidates.size();
                    if (!route.local())
                        line += " reason " + Decision.best(candidates, network.routerIds).reason();
                    lines.add(line);
                    candidates.removeIf(route::equals);
                    while (!candidates.isEmpty()) {
                        Decision.Route alternate =
                            Decision.best(candidates, network.routerIds).route();
                        lines.add("ALT " + Report.route(alternate));
                        candidates.remove(alternate);
                    }
                }
            }
            return lines;
        }
        List<String> traceLines(Simulator.Trace trace) {
            Forwarding path = trace(trace.source(), trace.value());
            List<String> lines = new ArrayList<>();
            lines.add("TRACE " + trace.source() + " " + trace.address() + " " + path.result() +
                      " hops " + path.count());
            for (Hop hop : path.hops()) {
                String beginning = "HOP " + hop.owner() + " " + hop.prefix();
                lines.add(beginning + (hop.link() == null
                                           ? " LOCAL"
                                           : " next " + hop.link().other(hop.owner()) + " link " +
                                                 hop.link().name));
            }
            if (path.result().equals("LOOP"))
                lines.add("HOP " + path.visits().getLast() + " REVISIT");
            else if (path.result().equals("BLACKHOLE") || path.result().equals("UNREACHABLE"))
                lines.add("HOP " + path.visits().getLast() + " NOROUTE");
            if (path.hops().isEmpty())
                lines.add("CONTROL NONE");
            else {
                Decision.Route route =
                    routers.get(trace.source()).rib.get(path.hops().getFirst().prefix());
                String notation = route.local() ? "LOCAL" : Report.path(route.path());
                boolean match =
                    path.result().equals("DELIVERED") &&
                    collapse(route.path()).equals(path.visits().subList(1, path.visits().size()));
                lines.add("CONTROL " + notation + " " + (match ? "MATCH" : "MISMATCH"));
            }
            if (path.count() > 0) {
                StringBuilder pattern = new StringBuilder();
                for (Hop hop : path.hops())
                    if (hop.link() != null)
                        pattern.append(hop.link().direction(hop.owner()));
                String value = pattern.toString();
                lines.add("PATTERN " + value + " " +
                          (valleyPosition(value) == value.length() ? "VALLEYFREE" : "VALLEY"));
            }
            return lines;
        }
        List<String> pathLines() {
            List<String> lines = new ArrayList<>();
            for (Simulator.Trace trace : traces)
                lines.addAll(traceLines(trace));
            Set<Topology.Prefix> prefixes = new TreeSet<>();
            for (Router router : routers.values())
                prefixes.addAll(router.origination.keySet());
            String names = String.join(",", prefixes.stream().map(Object::toString).toList());
            lines.add("PREFIXES" + (names.isEmpty() ? "" : " " + names));
            for (int source : network.routerIds.keySet()) {
                StringBuilder symbols = new StringBuilder();
                for (Topology.Prefix prefix : prefixes) {
                    Forwarding path = trace(source, prefix.address());
                    char symbol;
                    if (path.result().equals("DELIVERED"))
                        symbol = path.count() == 0 ? '*'
                                 : routers.get(path.arrival()).origination.containsKey(prefix)
                                     ? '+'
                                     : 'X';
                    else
                        symbol = switch (path.result()) {
                            case "LOOP" -> 'L';
                            case "BLACKHOLE" -> 'B';
                            default -> 'U';
                        };
                    symbols.append(symbol);
                }
                lines.add("REACH " + source + (symbols.isEmpty() ? "" : " " + symbols));
            }
            return lines;
        }
        List<String> auditLines() {
            List<String> lines = new ArrayList<>();
            int loops = 0, blackholes = 0;
            traceRecords.sort(Comparator.comparingInt((TraceRecord record) -> record.start)
                                  .thenComparingInt(record -> record.index));
            for (TraceRecord record : traceRecords) {
                Simulator.Trace trace = traces.get(record.index);
                String result = record.status.result();
                List<Integer> visits = record.status.visits();
                if (result.equals("LOOP"))
                    loops++;
                else
                    blackholes++;
                String line = result + " " + trace.source() + " " + trace.address() + " from " +
                              record.start + " to " + (record.end == null ? "END" : record.end);
                if (result.equals("BLACKHOLE"))
                    line += " at " + visits.getLast();
                lines.add(line + " path " + Report.path(visits));
            }
            ringRecords.sort(Comparator.comparingInt((RingRecord record) -> record.start)
                                 .thenComparing(record -> record.prefix)
                                 .thenComparingInt(record -> record.path.getFirst()));
            for (RingRecord record : ringRecords)
                lines.add("RING " + record.prefix + " from " + record.start + " to " +
                          (record.end == null ? "END" : record.end) + " path " +
                          Report.path(record.path));
            int routes = 0, valleys = 0;
            for (Router router : routers.values())
                for (var entry : router.rib.entrySet()) {
                    Decision.Route route = entry.getValue();
                    if (route.local())
                        continue;
                    routes++;
                    List<Integer> full = new ArrayList<>();
                    full.add(router.owner);
                    full.addAll(route.path());
                    List<Integer> path = collapse(full);
                    StringBuilder pattern = new StringBuilder();
                    for (int i = 0; i + 1 < path.size(); i++)
                        pattern.append(network.connecting(path.get(i), path.get(i + 1))
                                           .direction(path.get(i)));
                    String word = pattern.toString();
                    int violation = valleyPosition(word);
                    if (violation != word.length()) {
                        valleys++;
                        lines.add("VALLEY " + router.owner + " " + entry.getKey() + " path " +
                                  Report.path(route.path()) + " pattern " + word + " leaker " +
                                  path.get(violation));
                    }
                }
            for (Policy.Rule rule : policies.rules)
                lines.add("RULE " + rule.name + " " + rule.direction + " " +
                          (rule.active ? "ON" : "OFF") + " hits " + rule.hits);
            int divergent = 0;
            for (Period period : periods) {
                if (period.divergence == null)
                    continue;
                divergent++;
                Divergence divergence = period.divergence;
                lines.add("DIVERGENT event " + period.number + " first " + divergence.first() +
                          " repeat " + divergence.repeat() + " period " +
                          (divergence.repeat() - divergence.first()));
                Map<OwnerPrefix, Integer> oscillations = new TreeMap<>();
                for (BestLine line : divergence.cycle()) {
                    lines.add("CYCLE " + line.time() + " " + line.owner() + " " + line.prefix() +
                              " " + Report.route(line.route()));
                    oscillations.merge(new OwnerPrefix(line.owner(), line.prefix()), 1,
                                       Integer::sum);
                }
                for (var entry : oscillations.entrySet())
                    lines.add("OSCILLATE " + entry.getKey().owner() + " " +
                              entry.getKey().prefix() + " changes " + entry.getValue());
            }
            lines.add("SUMMARY loops " + loops + " blackholes " + blackholes + " rings " +
                      ringRecords.size() + " routes " + routes + " valleys " + valleys +
                      " divergent " + divergent + " end " + time);
            return lines;
        }
        void writeOutputs() throws Exception {
            Report.write("updates.txt", logs);
            List<String> csv = new ArrayList<>();
            csv.add(HEADER);
            for (Period period : periods)
                csv.add(period.csv());
            Report.write("convergence.csv", csv);
            Report.write("ribs.txt", ribLines());
            Report.write("paths.txt", pathLines());
            Report.write("audit.txt", auditLines());
        }
    }
    public static void main(String[] args) throws Exception {
        Topology network = new Topology();
        Policy policies = new Policy();
        Simulation simulation = new Simulation(network, policies, Simulator.params());
        simulation.run(Simulator.events());
        simulation.writeOutputs();
    }
}
