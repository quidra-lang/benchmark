import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
public final class Main {
    record Instruction(String command, List<String> arguments) {}
    record OccupiedPart(String section, int start, int low, int high) {}
    record Timing(String name, String location, int scheduled, Integer actual) {}
    static final class Request {
        int number, time;
        String route, reason;
        Request(int number, String route, int time) {
            this.number = number;
            this.route = route;
            this.time = time;
        }
    }
    static final class Simulation {
        Layout layout = new Layout();
        Interlocking interlocking = new Interlocking(layout);
        Map<String, Interlocking.Route> routes = interlocking.routes;
        Map<String, Trains.Train> trains;
        Map<Integer, List<Trains.Request>> plannedRequests = new HashMap<>();
        Map<Integer, List<Instruction>> events = new HashMap<>();
        int end, throwTime, overlapTime, time, requestCount, dropped;
        Set<Integer> snapshotTimes = new HashSet<>();
        List<Request> queue = new ArrayList<>();
        List<String> logLines = new ArrayList<>(), snapshots = new ArrayList<>();
        Safety safety = new Safety();
        Simulation() throws Exception {
            Trains.Plans plans = Trains.readTrains();
            trains = plans.trains();
            for (Trains.Request request : plans.requests())
                plannedRequests.computeIfAbsent(request.time(), key -> new ArrayList<>())
                    .add(request);
            for (String line :
                 Files.readAllLines(Path.of("input/events.txt"), StandardCharsets.US_ASCII)) {
                String[] f = line.split(" ");
                events.computeIfAbsent(Integer.parseInt(f[0]), key -> new ArrayList<>())
                    .add(new Instruction(f[1],
                                         new ArrayList<>(Arrays.asList(f).subList(2, f.length))));
            }
            List<String> params =
                Files.readAllLines(Path.of("input/params.txt"), StandardCharsets.US_ASCII);
            end = Integer.parseInt(params.get(0).split(" ")[1]);
            throwTime = Integer.parseInt(params.get(1).split(" ")[1]);
            overlapTime = Integer.parseInt(params.get(2).split(" ")[1]);
            String[] times = params.get(3).split(" ");
            for (int i = 1; i < times.length; i++)
                snapshotTimes.add(Integer.parseInt(times[i]));
        }
        void log(String content) { logLines.add(time + " " + content); }
        boolean occupied(String name) {
            Layout.Section section = layout.sections.get(name);
            return !section.occupants.isEmpty() || section.failed;
        }
        void startThrow(Layout.Point point, String target) {
            point.moving = true;
            point.target = target;
            point.completion = time + throwTime;
            log("MOVE " + point.name + " " + target + " until " + point.completion);
        }
        void completeThrows() {
            for (Layout.Point point : layout.points.values())
                if (point.moving && Objects.equals(point.completion, time)) {
                    point.position = point.target;
                    point.moving = false;
                    point.completion = null;
                    log("POINT " + point.name + " " + point.position);
                    point.throwsCount++;
                }
        }
        void releaseApproaches() {
            for (Interlocking.Route route : routes.values())
                if (Objects.equals(route.state, "APPROACH") &&
                    Objects.equals(route.releaseTime, time)) {
                    interlocking.release(route);
                    log("TIMEOUT " + route.name);
                }
        }
        void addRequest(String name, String requester) {
            Request request = new Request(++requestCount, name, time);
            log("REQUEST q" + request.number + " " + name + " " + requester);
            routes.get(name).requests++;
            queue.add(request);
        }
        void cancel(String name) {
            List<Request> removed = new ArrayList<>();
            for (Request request : queue)
                if (request.route.equals(name))
                    removed.add(request);
            if (!removed.isEmpty()) {
                for (Request request : removed) {
                    log("DROP q" + request.number + " " + name);
                    dropped++;
                }
                queue.removeIf(request -> request.route.equals(name));
                return;
            }
            Interlocking.Route route = routes.get(name);
            if (Objects.equals(route.state, "LOCKED")) {
                route.cancels++;
                Layout.Signal signal = layout.signals.get(route.start);
                if (!signal.aspect.equals("RED") && occupied(signal.section)) {
                    route.state = "APPROACH";
                    route.releaseTime = time + route.approachTime;
                    log("CANCEL " + name + " approach until " + route.releaseTime);
                } else {
                    interlocking.release(route);
                    log("CANCEL " + name + " released");
                }
            } else
                log("CANCEL " + name + " " + (route.state == null ? "none" : "refused"));
        }
        void individualThrow(String name, String target) {
            Layout.Point point = layout.points.get(name);
            String result = !point.locks.isEmpty()          ? "locked"
                            : point.failed                  ? "failed"
                            : point.moving                  ? "moving"
                            : occupied(point.common)        ? "occupied"
                            : point.position.equals(target) ? "none"
                                                            : "start";
            log("THROW " + name + " " + target + " " + result);
            if (result.equals("start"))
                startThrow(point, target);
        }
        void pointFailure(String command, String name) {
            Layout.Point point = layout.points.get(name);
            point.failed = command.equals("POINTFAIL");
            if (point.failed && point.moving)
                point.completion = null;
            log(command + " " + name);
            if (!point.failed && point.moving)
                startThrow(point, point.target);
        }
        void executeEvents() {
            for (Instruction instruction : events.getOrDefault(time, List.of())) {
                String command = instruction.command();
                List<String> a = instruction.arguments();
                switch (command) {
                case "REQUEST":
                    addRequest(a.get(0), "OPERATOR");
                    break;
                case "CANCEL":
                    cancel(a.get(0));
                    break;
                case "THROW":
                    individualThrow(a.get(0), a.get(1));
                    break;
                case "TCFAIL":
                case "TCFIX":
                    layout.sections.get(a.get(0)).failed = command.equals("TCFAIL");
                    log(command + " " + a.get(0));
                    break;
                default:
                    pointFailure(command, a.get(0));
                    break;
                }
            }
        }
        boolean oppositeLock(Collection<String> names, Interlocking.Route route) {
            for (String name : names)
                if (!routes.get(name).direction.equals(route.direction))
                    return true;
            return false;
        }
        String requestReason(Interlocking.Route route) {
            if (route.state != null)
                return "busy";
            for (String name : route.conflicts)
                if (Objects.equals(routes.get(name).state, "LOCKED") ||
                    Objects.equals(routes.get(name).state, "APPROACH"))
                    return "conflict " + name;
            for (String name : route.sections) {
                Layout.Section section = layout.sections.get(name);
                if (occupied(name))
                    return "occupied " + name;
                if (section.routeLock != null || oppositeLock(section.overlapLocks, route))
                    return "locked " + name;
            }
            for (String name : route.overlap) {
                Layout.Section section = layout.sections.get(name);
                if (occupied(name))
                    return "occupied " + name;
                Set<String> locks = new HashSet<>(section.overlapLocks);
                if (section.routeLock != null)
                    locks.add(section.routeLock);
                if (oppositeLock(locks, route))
                    return "locked " + name;
            }
            for (Interlocking.Requirement requirement : route.requirements) {
                String name = requirement.point(), target = requirement.position();
                Layout.Point point = layout.points.get(name);
                for (Interlocking.PointLock lock : point.locks)
                    if (!lock.position().equals(target))
                        return "point " + name + " locked";
                if (!point.moving && point.position.equals(target) ||
                    point.moving && point.target.equals(target))
                    continue;
                if (point.failed)
                    return "point " + name + " failed";
                if (point.moving)
                    return "point " + name + " moving";
                if (occupied(point.common))
                    return "point " + name + " occupied";
            }
            return null;
        }
        void judgeRequests() {
            List<Request> waiting = new ArrayList<>();
            for (Request request : queue) {
                Interlocking.Route route = routes.get(request.route);
                String reason = requestReason(route);
                if (reason != null) {
                    if (!reason.equals(request.reason)) {
                        log("WAIT q" + request.number + " " + route.name + " " + reason);
                        request.reason = reason;
                    }
                    waiting.add(request);
                    continue;
                }
                interlocking.lock(route);
                int wait = time - request.time;
                log("GRANT q" + request.number + " " + route.name + " wait " + wait);
                route.grants++;
                route.wait += wait;
                route.maxwait = Math.max(route.maxwait, wait);
                for (Interlocking.Requirement requirement : route.requirements) {
                    Layout.Point point = layout.points.get(requirement.point());
                    if (!point.moving && !point.position.equals(requirement.position()))
                        startThrow(point, requirement.position());
                }
            }
            queue = waiting;
        }
        void decideSignals() {
            for (Signals.Aspect decision : Signals.aspects(interlocking, this::occupied))
                if (!decision.signal().aspect.equals(decision.aspect())) {
                    decision.signal().aspect = decision.aspect();
                    log("SIGNAL " + decision.signal().name + " " + decision.aspect());
                }
        }
        List<OccupiedPart> occupiedParts(Trains.Train train) {
            List<OccupiedPart> parts = new ArrayList<>();
            if (train.state.equals("RUNNING")) {
                int tail = train.head - train.length;
                for (Trains.PathPart path : train.path) {
                    int end = path.start() + layout.sections.get(path.section()).length;
                    if (path.start() < train.head && end > tail)
                        parts.add(new OccupiedPart(path.section(), path.start(),
                                                   Math.max(tail, path.start()),
                                                   Math.min(train.head, end)));
                }
            }
            return parts;
        }
        Trains.PathPart headSection(Trains.Train train) {
            for (int i = train.path.size() - 1; i >= 0; i--)
                if (train.path.get(i).start() < train.head)
                    return train.path.get(i);
            return train.path.getFirst();
        }
        boolean enter(Trains.Train train, Set<String> enteredBoundaries) {
            if (train.state.equals("EXITED"))
                return false;
            if (train.state.equals("RUNNING"))
                return true;
            Layout.Boundary boundary = layout.boundaries.get(train.entry);
            if (time < train.entryTime || occupied(boundary.section()) ||
                enteredBoundaries.contains(train.entry))
                return false;
            train.state = "RUNNING";
            train.direction = boundary.end().equals("L") ? "UP" : "DOWN";
            train.path = new ArrayList<>(List.of(new Trains.PathPart(boundary.section(), 0)));
            train.head = 0;
            train.speed = train.entrySpeed;
            train.entered = time;
            enteredBoundaries.add(train.entry);
            log("ENTER " + train.name + " " + train.entry);
            return true;
        }
        void reverse(Trains.Train train, Trains.Stop stop) {
            Trains.PathPart head = headSection(train);
            int end = head.start() + layout.sections.get(head.section()).length;
            List<OccupiedPart> occupied = occupiedParts(train);
            List<Trains.PathPart> path = new ArrayList<>();
            for (int i = occupied.size() - 1; i >= 0; i--) {
                OccupiedPart part = occupied.get(i);
                path.add(new Trains.PathPart(
                    part.section(),
                    end - (part.start() + layout.sections.get(part.section()).length)));
            }
            train.path = path;
            train.head = end - (train.head - train.length);
            train.direction = train.direction.equals("UP") ? "DOWN" : "UP";
            log("REVERSE " + train.name + " " + stop.section);
        }
        boolean finishDwell(Trains.Train train) {
            if (!train.dwelling)
                return true;
            Trains.Stop stop = train.nextStop();
            if (time < stop.arrival + stop.dwell || time < stop.scheduledDeparture)
                return false;
            train.dwelling = false;
            train.awaitingDeparture = stop;
            train.stopIndex++;
            if (stop.kind.equals("TURN"))
                reverse(train, stop);
            return true;
        }
        Integer limitDistance(Trains.Train train) {
            if (train.boundary != null)
                return null;
            Trains.PathPart head = headSection(train);
            String name = head.section();
            int distance = head.start() + layout.sections.get(name).length - train.head;
            while (true) {
                Layout.Signal signal = layout.signalsAt.get(new Layout.Key(name, train.direction));
                if (signal != null && signal.aspect.equals("RED"))
                    return distance;
                Trains.Stop stop = train.nextStop();
                if (stop != null && stop.section.equals(name))
                    return distance;
                Layout.Beyond beyond = layout.beyond(name, train.direction);
                if (beyond.kind().equals("boundary"))
                    return null;
                if (beyond.kind().equals("buffer") || beyond.kind().equals("impassable"))
                    return distance;
                distance += layout.sections.get(beyond.name()).length;
                name = beyond.name();
            }
        }
        void passSignal(Trains.Train train, Layout.Signal signal) {
            Interlocking.Route active = null;
            for (Interlocking.Route route : routes.values())
                if (route.start.equals(signal.name) && (Objects.equals(route.state, "LOCKED") ||
                                                        Objects.equals(route.state, "APPROACH"))) {
                    active = route;
                    break;
                }
            log("PASS " + train.name + " " + signal.name + " " + signal.aspect + " " +
                (active == null ? "-" : active.name));
            signal.passes++;
            train.passes++;
            if (active != null) {
                active.state = "USED";
                active.uses++;
            }
            if (signal.aspect.equals("RED")) {
                log("SPAD " + train.name + " " + signal.name);
                safety.check(time, "SIGNAL_PASSING", train.name + " " + signal.name);
                train.emergency = true;
            } else
                safety.check(time, "SIGNAL_PASSING", null);
        }
        void move(Trains.Train train, int distance) {
            Trains.PathPart head = headSection(train);
            String name = head.section();
            int start = head.start(), remaining = distance;
            while (remaining > 0) {
                if (train.boundary != null) {
                    train.head += remaining;
                    break;
                }
                int end = start + layout.sections.get(name).length;
                if (train.head + remaining <= end) {
                    train.head += remaining;
                    break;
                }
                remaining -= end - train.head;
                train.head = end;
                Layout.Signal signal = layout.signalsAt.get(new Layout.Key(name, train.direction));
                if (signal != null)
                    passSignal(train, signal);
                Trains.Stop stop = train.awaitingDeparture;
                if (stop != null && stop.section.equals(name)) {
                    log("DEPART " + train.name + " " + name);
                    stop.departure = time;
                    train.awaitingDeparture = null;
                }
                Layout.Beyond beyond = layout.beyond(name, train.direction);
                if (beyond.kind().equals("boundary")) {
                    train.boundary = beyond.name();
                    train.boundaryCoordinate = end;
                } else {
                    name = beyond.name();
                    start = end;
                    train.path.add(new Trains.PathPart(name, start));
                }
            }
        }
        void afterMovement(Trains.Train train, int speed, int previousSpeed) {
            train.speed = speed;
            train.distance += speed;
            train.maximumSpeed = Math.max(train.maximumSpeed, speed);
            if (speed == 0)
                train.emergency = false;
            Trains.PathPart head = headSection(train);
            Trains.Stop stop = train.nextStop();
            boolean arrived =
                stop != null && speed == 0 && head.section().equals(stop.section) &&
                train.head == head.start() + layout.sections.get(head.section()).length;
            if (arrived) {
                train.dwelling = true;
                stop.arrival = time;
                log("ARRIVE " + train.name + " " + head.section());
            }
            if (speed == 0 && !arrived) {
                train.standing++;
                if (previousSpeed > 0)
                    log("HOLD " + train.name + " " + head.section());
            }
            if (train.boundary != null && train.head - train.length >= train.boundaryCoordinate) {
                train.state = "EXITED";
                train.exited = time;
                log("EXIT " + train.name + " " + train.boundary);
            }
        }
        void runTrains() {
            Set<String> enteredBoundaries = new HashSet<>();
            for (Trains.Train train : trains.values()) {
                if (!enter(train, enteredBoundaries) || !finishDwell(train))
                    continue;
                Integer distance = limitDistance(train);
                int previousSpeed = train.speed, speed = Trains.selectSpeed(train, distance);
                move(train, speed);
                afterMovement(train, speed, previousSpeed);
            }
        }
        void recomputeOccupancy() {
            for (Layout.Section section : layout.sections.values())
                section.occupants.clear();
            for (Trains.Train train : trains.values())
                for (OccupiedPart part : occupiedParts(train)) {
                    List<String> occupants = layout.sections.get(part.section()).occupants;
                    if (!occupants.contains(train.name))
                        occupants.add(train.name);
                }
        }
        void sectionalRelease() {
            for (Interlocking.Route route : routes.values()) {
                if (!Objects.equals(route.state, "USED"))
                    continue;
                List<String> remaining = new ArrayList<>();
                for (String name : route.sections)
                    if (Objects.equals(layout.sections.get(name).routeLock, route.name))
                        remaining.add(name);
                for (String name : remaining)
                    if (occupied(name))
                        route.passed.add(name);
                for (String name : remaining) {
                    if (!route.passed.contains(name) || occupied(name))
                        break;
                    interlocking.unlockSection(route, name);
                    log("RELEASE " + route.name + " " + name);
                }
                boolean any = false;
                for (String name : route.sections)
                    if (Objects.equals(layout.sections.get(name).routeLock, route.name))
                        any = true;
                if (!any) {
                    interlocking.release(route);
                    log("DONE " + route.name);
                } else if (!route.overlap.isEmpty() && route.overlapLocked) {
                    route.overlapCounter =
                        occupied(route.sections.getLast()) ? route.overlapCounter + 1 : 0;
                    if (route.overlapCounter >= overlapTime) {
                        interlocking.unlockOverlap(route);
                        log("OVERLAP " + route.name);
                    }
                }
            }
        }
        void recordStatistics() {
            for (Interlocking.Route route : routes.values())
                if (route.state != null)
                    route.lockedSeconds++;
            for (Layout.Point point : layout.points.values()) {
                if (!point.locks.isEmpty())
                    point.lockedSeconds++;
                if (point.moving)
                    point.movingSeconds++;
            }
            for (Layout.Section section : layout.sections.values()) {
                if (occupied(section.name))
                    section.occupiedSeconds++;
                if (section.routeLock != null || !section.overlapLocks.isEmpty())
                    section.lockedSeconds++;
                section.trains.addAll(section.occupants);
            }
            for (Layout.Signal signal : layout.signals.values())
                signal.seconds.merge(signal.aspect, 1, Integer::sum);
        }
        List<String> diagram() {
            int height = 0, width = 0;
            for (Layout.Section section : layout.sections.values()) {
                height = Math.max(height, section.row + 1);
                width = Math.max(width, section.last + 1);
            }
            for (Layout.Point point : layout.points.values()) {
                height = Math.max(height, point.row + 1);
                width = Math.max(width, point.column + 1);
            }
            for (Layout.Signal signal : layout.signals.values()) {
                height = Math.max(height, signal.row + 1);
                width = Math.max(width, signal.column + 1);
            }
            for (Layout.Buffer buffer : layout.buffers.values()) {
                height = Math.max(height, buffer.row() + 1);
                width = Math.max(width, buffer.column() + 1);
            }
            for (Layout.Label label : layout.labels) {
                height = Math.max(height, label.row() + 1);
                width = Math.max(width, label.column() + label.text().length());
            }
            char[][] grid = new char[height][width];
            for (char[] row : grid)
                Arrays.fill(row, ' ');
            for (Layout.Label label : layout.labels)
                for (int i = 0; i < label.text().length(); i++)
                    grid[label.row()][label.column() + i] = label.text().charAt(i);
            for (Layout.Section section : layout.sections.values()) {
                char character = section.failed                    ? '#'
                                 : section.routeLock != null       ? '='
                                 : !section.overlapLocks.isEmpty() ? '~'
                                                                   : '-';
                for (int column = section.first; column <= section.last; column++)
                    grid[section.row][column] = character;
            }
            for (Trains.Train train : trains.values())
                for (OccupiedPart part : occupiedParts(train)) {
                    Layout.Section section = layout.sections.get(part.section());
                    int length = section.length, cells = section.last - section.first + 1, left,
                        right;
                    if (train.direction.equals("UP")) {
                        left = part.low() - part.start();
                        right = part.high() - part.start();
                    } else {
                        left = length - (part.high() - part.start());
                        right = length - (part.low() - part.start());
                    }
                    for (int cell = 0; cell < cells; cell++)
                        if (left * cells < (cell + 1) * length && right * cells > cell * length) {
                            int column = section.first + cell;
                            char previous = grid[section.row][column];
                            grid[section.row][column] =
                                previous >= 'a' && previous <= 'z' || previous == '*'
                                    ? '*'
                                    : train.symbol;
                        }
                }
            for (Layout.Buffer buffer : layout.buffers.values())
                grid[buffer.row()][buffer.column()] = '|';
            for (Layout.Point point : layout.points.values())
                grid[point.row][point.column] = point.detected() ? point.position.charAt(0) : '?';
            for (Layout.Signal signal : layout.signals.values())
                grid[signal.row][signal.column] = signal.aspect.equals("RED")      ? 'X'
                                                  : signal.aspect.equals("YELLOW") ? 'Y'
                                                                                   : 'G';
            List<String> lines = new ArrayList<>();
            for (char[] row : grid) {
                int end = row.length;
                while (end > 0 && row[end - 1] == ' ')
                    end--;
                lines.add(new String(row, 0, end));
            }
            return lines;
        }
        List<String> snapshot() {
            List<String> lines = new ArrayList<>(List.of("SNAPSHOT " + time));
            lines.addAll(diagram());
            for (Trains.Train train : trains.values())
                if (train.state.equals("RUNNING")) {
                    List<String> sections = new ArrayList<>();
                    for (OccupiedPart part : occupiedParts(train))
                        sections.add(part.section());
                    String body = String.join(",", sections);
                    lines.add("TRAIN " + train.symbol + " " + train.name + " " + train.direction +
                              " " + train.speed + (body.isEmpty() ? "" : " " + body));
                }
            List<String> active = new ArrayList<>();
            for (Interlocking.Route route : routes.values())
                if (route.state != null)
                    active.add(route.name + "/" + route.state);
            lines.add("ROUTES " + (active.isEmpty() ? "-" : String.join(" ", active)));
            return lines;
        }
        List<Timing> trainRows() {
            List<Timing> rows = new ArrayList<>();
            for (Trains.Train train : trains.values()) {
                rows.add(
                    new Timing(train.name, "enter:" + train.entry, train.entryTime, train.entered));
                for (Trains.Stop stop : train.stops) {
                    rows.add(new Timing(train.name, "arr:" + stop.section, stop.scheduledArrival,
                                        stop.arrival));
                    rows.add(new Timing(train.name, "dep:" + stop.section, stop.scheduledDeparture,
                                        stop.departure));
                }
                rows.add(new Timing(train.name, "exit:" + train.exit, train.scheduledExit,
                                    train.exited));
            }
            return rows;
        }
        List<String> trainReport(List<Timing> rows) {
            List<String> lines = new ArrayList<>(List.of("train,location,scheduled,actual,delay"));
            for (Timing row : rows)
                lines.add(row.name() + "," + row.location() + "," + row.scheduled() + "," +
                          (row.actual() == null
                               ? "-,-"
                               : row.actual() + "," + (row.actual() - row.scheduled())));
            return lines;
        }
        String punctuality(List<Timing> rows) {
            int onTime = 0, late = 0, missing = 0, totalDelay = 0, maximum = 0;
            for (Timing row : rows) {
                if (row.actual() == null) {
                    missing++;
                    continue;
                }
                int delay = row.actual() - row.scheduled();
                if (delay <= 0)
                    onTime++;
                else {
                    late++;
                    totalDelay += delay;
                    maximum = Math.max(maximum, delay);
                }
            }
            return "PUNCTUALITY on_time " + onTime + " late " + late + " missing " + missing +
                " total_delay " + totalDelay + " max_delay " + maximum;
        }
        List<String> summary(List<Timing> rows) {
            List<String> lines = new ArrayList<>();
            int grants = 0;
            for (Interlocking.Route route : routes.values()) {
                lines.add("ROUTE " + route.name + " " + route.start + "-" + route.finish +
                          " requests " + route.requests + " grants " + route.grants + " uses " +
                          route.uses + " cancels " + route.cancels + " wait " + route.wait +
                          " maxwait " + route.maxwait + " locked " + route.lockedSeconds);
                grants += route.grants;
            }
            for (Layout.Point point : layout.points.values())
                lines.add("POINT " + point.name + " throws " + point.throwsCount + " locked " +
                          point.lockedSeconds + " moving " + point.movingSeconds + " final " +
                          (point.detected() ? point.position : "?"));
            for (Layout.Section section : layout.sections.values())
                lines.add("SECTION " + section.name + " occupied " + section.occupiedSeconds +
                          " locked " + section.lockedSeconds + " trains " + section.trains.size());
            for (Layout.Signal signal : layout.signals.values())
                lines.add("SIGNAL " + signal.name + " red " +
                          signal.seconds.getOrDefault("RED", 0) + " yellow " +
                          signal.seconds.getOrDefault("YELLOW", 0) + " green " +
                          signal.seconds.getOrDefault("GREEN", 0) + " passes " + signal.passes);
            int exited = 0, running = 0, waiting = 0;
            for (Trains.Train train : trains.values()) {
                lines.add("TRAIN " + train.name + " " + train.symbol + " " + train.state +
                          " distance " + train.distance + " maxspeed " + train.maximumSpeed +
                          " standing " + train.standing + " passes " + train.passes);
                if (train.state.equals("EXITED"))
                    exited++;
                else if (train.state.equals("RUNNING"))
                    running++;
                else
                    waiting++;
            }
            lines.add("TRAINS total " + trains.size() + " exited " + exited + " running " +
                      running + " waiting " + waiting);
            lines.add(punctuality(rows));
            lines.add("REQUESTS total " + requestCount + " granted " + grants + " dropped " +
                      dropped + " pending " + queue.size());
            return lines;
        }
        void writeReports() throws Exception {
            List<Timing> rows = trainRows();
            Map<String, List<String>> reports = new LinkedHashMap<>();
            reports.put("events.txt", logLines);
            reports.put("snapshots.txt", snapshots);
            reports.put("train_log.csv", trainReport(rows));
            reports.put("safety.txt", safety.report());
            reports.put("summary.txt", summary(rows));
            Files.createDirectories(Path.of("output"));
            for (Map.Entry<String, List<String>> report : reports.entrySet())
                Files.writeString(
                    Path.of("output", report.getKey()),
                    report.getValue().isEmpty() ? "" : String.join("\n", report.getValue()) + "\n",
                    StandardCharsets.US_ASCII);
        }
        void run() throws Exception {
            for (time = 0; time <= end; time++) {
                completeThrows();
                releaseApproaches();
                for (Trains.Request request : plannedRequests.getOrDefault(time, List.of()))
                    addRequest(request.route(), request.train());
                executeEvents();
                judgeRequests();
                decideSignals();
                runTrains();
                recomputeOccupancy();
                sectionalRelease();
                safety.inspect(time, layout, routes);
                recordStatistics();
                if (snapshotTimes.contains(time))
                    snapshots.addAll(snapshot());
            }
            writeReports();
        }
    }
    public static void main(String[] args) throws Exception { new Simulation().run(); }
}
