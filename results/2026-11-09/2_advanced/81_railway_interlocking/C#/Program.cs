using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
public static class Program {
    public record Instruction(string command, List<string> arguments) {}
    public record OccupiedPart(string section, int start, int low, int high) {}
    public record Timing(string name, string location, int scheduled, int? actual) {}
    public sealed class Request {
        public int number, time;
        public string route, reason;
        public Request(int number, string route, int time) {
            this.number = number;
            this.route = route;
            this.time = time;
        }
    }
    public sealed class Simulation {
        public Layout layout;
        public Interlocking interlocking;
        public Dictionary<string, Interlocking.Route> routes;
        public Dictionary<string, Trains.Train> trains;
        public Dictionary<int, List<Trains.Request>> plannedRequests = new();
        public Dictionary<int, List<Instruction>> events = new();
        public int end, throwTime, overlapTime, time, requestCount, dropped;
        public HashSet<int> snapshotTimes = new();
        public List<Request> queue = new();
        public List<string> logLines = new(), snapshots = new();
        public Safety safety = new Safety();
        public Simulation() {
            layout = new Layout();
            interlocking = new Interlocking(layout);
            routes = interlocking.routes;
            Trains.Plans plans = Trains.ReadTrains();
            trains = plans.trains;
            foreach (Trains.Request request in plans.requests)
                plannedRequests.GetOrAdd(request.time, () => new List<Trains.Request>())
                    .Add(request);
            foreach (string line in File
                         .ReadAllLines(Path.Combine("input/events.txt"), System.Text.Encoding.ASCII)
                         .ToList()) {
                string[] f = line.Split(" ");
                events.GetOrAdd(int.Parse(f[0]), () => new List<Instruction>())
                    .Add(new Instruction(f[1], new(f.ToList().GetRange(2, f.Length - 2))));
            }
            List<string> settings =
                File.ReadAllLines(Path.Combine("input/params.txt"), System.Text.Encoding.ASCII)
                    .ToList();
            end = int.Parse(settings[0].Split(" ")[1]);
            throwTime = int.Parse(settings[1].Split(" ")[1]);
            overlapTime = int.Parse(settings[2].Split(" ")[1]);
            string[] times = settings[3].Split(" ");
            for (int i = 1; i < times.Length; i++)
                snapshotTimes.Add(int.Parse(times[i]));
        }
        public void Log(string content) { logLines.Add(time + " " + content); }
        public bool Occupied(string name) {
            Layout.Section section = layout.sections[name];
            return section.occupants.Count != 0 || section.failed;
        }
        public void StartThrow(Layout.Point point, string target) {
            point.moving = true;
            point.target = target;
            point.completion = time + throwTime;
            Log("MOVE " + point.name + " " + target + " until " + point.completion);
        }
        public void CompleteThrows() {
            foreach (Layout.Point point in layout.points.Values)
                if (point.moving && object.Equals(point.completion, time)) {
                    point.position = point.target;
                    point.moving = false;
                    point.completion = null;
                    Log("POINT " + point.name + " " + point.position);
                    point.throwsCount++;
                }
        }
        public void ReleaseApproaches() {
            foreach (Interlocking.Route route in routes.Values)
                if (object.Equals(route.state, "APPROACH") &&
                    object.Equals(route.releaseTime, time)) {
                    interlocking.Release(route);
                    Log("TIMEOUT " + route.name);
                }
        }
        public void AddRequest(string name, string requester) {
            Request request = new Request(++requestCount, name, time);
            Log("REQUEST q" + request.number + " " + name + " " + requester);
            routes[name].requests++;
            queue.Add(request);
        }
        public void Cancel(string name) {
            List<Request> removed = new();
            foreach (Request request in queue)
                if (request.route.Equals(name))
                    removed.Add(request);
            if (removed.Count != 0) {
                foreach (Request request in removed) {
                    Log("DROP q" + request.number + " " + name);
                    dropped++;
                }
                queue.RemoveAll(request => request.route.Equals(name));
                return;
            }
            Interlocking.Route route = routes[name];
            if (object.Equals(route.state, "LOCKED")) {
                route.cancels++;
                Layout.Signal signal = layout.signals[route.start];
                if (!signal.aspect.Equals("RED") && Occupied(signal.section)) {
                    route.state = "APPROACH";
                    route.releaseTime = time + route.approachTime;
                    Log("CANCEL " + name + " approach until " + route.releaseTime);
                } else {
                    interlocking.Release(route);
                    Log("CANCEL " + name + " released");
                }
            } else
                Log("CANCEL " + name + " " + (route.state == null ? "none" : "refused"));
        }
        public void IndividualThrow(string name, string target) {
            Layout.Point point = layout.points[name];
            string result = point.locks.Count != 0          ? "locked"
                            : point.failed                  ? "failed"
                            : point.moving                  ? "moving"
                            : Occupied(point.common)        ? "occupied"
                            : point.position.Equals(target) ? "none"
                                                            : "start";
            Log("THROW " + name + " " + target + " " + result);
            if (result.Equals("start"))
                StartThrow(point, target);
        }
        public void PointFailure(string command, string name) {
            Layout.Point point = layout.points[name];
            point.failed = command.Equals("POINTFAIL");
            if (point.failed && point.moving)
                point.completion = null;
            Log(command + " " + name);
            if (!point.failed && point.moving)
                StartThrow(point, point.target);
        }
        public void ExecuteEvents() {
            foreach (Instruction instruction in events.GetValueOrDefault(time, new())) {
                string command = instruction.command;
                List<string> a = instruction.arguments;
                switch (command) {
                case "REQUEST":
                    AddRequest(a[0], "OPERATOR");
                    break;
                case "CANCEL":
                    Cancel(a[0]);
                    break;
                case "THROW":
                    IndividualThrow(a[0], a[1]);
                    break;
                case "TCFAIL":
                case "TCFIX":
                    layout.sections[a[0]].failed = command.Equals("TCFAIL");
                    Log(command + " " + a[0]);
                    break;
                default:
                    PointFailure(command, a[0]);
                    break;
                }
            }
        }
        public bool OppositeLock(IEnumerable<string> names, Interlocking.Route route) {
            foreach (string name in names)
                if (!routes[name].direction.Equals(route.direction))
                    return true;
            return false;
        }
        public string RequestReason(Interlocking.Route route) {
            if (route.state != null)
                return "busy";
            foreach (string name in route.conflicts)
                if (object.Equals(routes[name].state, "LOCKED") ||
                    object.Equals(routes[name].state, "APPROACH"))
                    return "conflict " + name;
            foreach (string name in route.sections) {
                Layout.Section section = layout.sections[name];
                if (Occupied(name))
                    return "occupied " + name;
                if (section.routeLock != null || OppositeLock(section.overlapLocks, route))
                    return "locked " + name;
            }
            foreach (string name in route.overlap) {
                Layout.Section section = layout.sections[name];
                if (Occupied(name))
                    return "occupied " + name;
                HashSet<string> locks = new HashSet<string>(section.overlapLocks);
                if (section.routeLock != null)
                    locks.Add(section.routeLock);
                if (OppositeLock(locks, route))
                    return "locked " + name;
            }
            foreach (Interlocking.Requirement requirement in route.requirements) {
                string name = requirement.point, target = requirement.position;
                Layout.Point point = layout.points[name];
                foreach (Interlocking.PointLock lock in point.locks)
                    if (!lock.position.Equals(target))
                        return "point " + name + " locked";
                if (!point.moving && point.position.Equals(target) ||
                    point.moving && point.target.Equals(target))
                    continue;
                if (point.failed)
                    return "point " + name + " failed";
                if (point.moving)
                    return "point " + name + " moving";
                if (Occupied(point.common))
                    return "point " + name + " occupied";
            }
            return null;
        }
        public void JudgeRequests() {
            List<Request> waiting = new();
            foreach (Request request in queue) {
                Interlocking.Route route = routes[request.route];
                string reason = RequestReason(route);
                if (reason != null) {
                    if (!reason.Equals(request.reason)) {
                        Log("WAIT q" + request.number + " " + route.name + " " + reason);
                        request.reason = reason;
                    }
                    waiting.Add(request);
                    continue;
                }
                interlocking.Lock(route);
                int wait = time - request.time;
                Log("GRANT q" + request.number + " " + route.name + " wait " + wait);
                route.grants++;
                route.wait += wait;
                route.maxwait = Math.Max(route.maxwait, wait);
                foreach (Interlocking.Requirement requirement in route.requirements) {
                    Layout.Point point = layout.points[requirement.point];
                    if (!point.moving && !point.position.Equals(requirement.position))
                        StartThrow(point, requirement.position);
                }
            }
            queue = waiting;
        }
        public void DecideSignals() {
            foreach (Signals.Aspect decision in Signals.Aspects(interlocking, Occupied))
                if (!decision.signal.aspect.Equals(decision.aspect)) {
                    decision.signal.aspect = decision.aspect;
                    Log("SIGNAL " + decision.signal.name + " " + decision.aspect);
                }
        }
        public List<OccupiedPart> OccupiedParts(Trains.Train train) {
            List<OccupiedPart> parts = new();
            if (train.state.Equals("RUNNING")) {
                int tail = train.head - train.length;
                foreach (Trains.PathPart path in train.path) {
                    int end = path.start + layout.sections[path.section].length;
                    if (path.start < train.head && end > tail)
                        parts.Add(new OccupiedPart(path.section, path.start,
                                                   Math.Max(tail, path.start),
                                                   Math.Min(train.head, end)));
                }
            }
            return parts;
        }
        public Trains.PathPart HeadSection(Trains.Train train) {
            for (int i = train.path.Count - 1; i >= 0; i--)
                if (train.path[i].start < train.head)
                    return train.path[i];
            return train.path[0];
        }
        public bool Enter(Trains.Train train, HashSet<string> enteredBoundaries) {
            if (train.state.Equals("EXITED"))
                return false;
            if (train.state.Equals("RUNNING"))
                return true;
            Layout.Boundary boundary = layout.boundaries[train.entry];
            if (time < train.entryTime || Occupied(boundary.section) ||
                enteredBoundaries.Contains(train.entry))
                return false;
            train.state = "RUNNING";
            train.direction = boundary.end.Equals("L") ? "UP" : "DOWN";
            train.path =
                new(new List<Trains.PathPart> { new Trains.PathPart(boundary.section, 0) });
            train.head = 0;
            train.speed = train.entrySpeed;
            train.entered = time;
            enteredBoundaries.Add(train.entry);
            Log("ENTER " + train.name + " " + train.entry);
            return true;
        }
        public void Reverse(Trains.Train train, Trains.Stop stop) {
            Trains.PathPart head = HeadSection(train);
            int end = head.start + layout.sections[head.section].length;
            List<OccupiedPart> occupied = OccupiedParts(train);
            List<Trains.PathPart> path = new();
            for (int i = occupied.Count - 1; i >= 0; i--) {
                OccupiedPart part = occupied[i];
                path.Add(new Trains.PathPart(
                    part.section, end - (part.start + layout.sections[part.section].length)));
            }
            train.path = path;
            train.head = end - (train.head - train.length);
            train.direction = train.direction.Equals("UP") ? "DOWN" : "UP";
            Log("REVERSE " + train.name + " " + stop.section);
        }
        public bool FinishDwell(Trains.Train train) {
            if (!train.dwelling)
                return true;
            Trains.Stop stop = train.NextStop();
            if (time < stop.arrival.Value + stop.dwell || time < stop.scheduledDeparture)
                return false;
            train.dwelling = false;
            train.awaitingDeparture = stop;
            train.stopIndex++;
            if (stop.kind.Equals("TURN"))
                Reverse(train, stop);
            return true;
        }
        public int? LimitDistance(Trains.Train train) {
            if (train.boundary != null)
                return null;
            Trains.PathPart head = HeadSection(train);
            string name = head.section;
            int distance = head.start + layout.sections[name].length - train.head;
            while (true) {
                Layout.Signal signal =
                    layout.signalsAt.GetValueOrDefault(new Layout.Key(name, train.direction));
                if (signal != null && signal.aspect.Equals("RED"))
                    return distance;
                Trains.Stop stop = train.NextStop();
                if (stop != null && stop.section.Equals(name))
                    return distance;
                Layout.Beyond beyond = layout.GetBeyond(name, train.direction);
                if (beyond.kind.Equals("boundary"))
                    return null;
                if (beyond.kind.Equals("buffer") || beyond.kind.Equals("impassable"))
                    return distance;
                distance += layout.sections[beyond.name].length;
                name = beyond.name;
            }
        }
        public void PassSignal(Trains.Train train, Layout.Signal signal) {
            Interlocking.Route active = null;
            foreach (Interlocking.Route route in routes.Values)
                if (route.start.Equals(signal.name) && (object.Equals(route.state, "LOCKED") ||
                                                        object.Equals(route.state, "APPROACH"))) {
                    active = route;
                    break;
                }
            Log("PASS " + train.name + " " + signal.name + " " + signal.aspect + " " +
                (active == null ? "-" : active.name));
            signal.passes++;
            train.passes++;
            if (active != null) {
                active.state = "USED";
                active.uses++;
            }
            if (signal.aspect.Equals("RED")) {
                Log("SPAD " + train.name + " " + signal.name);
                safety.Check(time, "SIGNAL_PASSING", train.name + " " + signal.name);
                train.emergency = true;
            } else
                safety.Check(time, "SIGNAL_PASSING", null);
        }
        public void Move(Trains.Train train, int distance) {
            Trains.PathPart head = HeadSection(train);
            string name = head.section;
            int start = head.start, remaining = distance;
            while (remaining > 0) {
                if (train.boundary != null) {
                    train.head += remaining;
                    break;
                }
                int end = start + layout.sections[name].length;
                if (train.head + remaining <= end) {
                    train.head += remaining;
                    break;
                }
                remaining -= end - train.head;
                train.head = end;
                Layout.Signal signal =
                    layout.signalsAt.GetValueOrDefault(new Layout.Key(name, train.direction));
                if (signal != null)
                    PassSignal(train, signal);
                Trains.Stop stop = train.awaitingDeparture;
                if (stop != null && stop.section.Equals(name)) {
                    Log("DEPART " + train.name + " " + name);
                    stop.departure = time;
                    train.awaitingDeparture = null;
                }
                Layout.Beyond beyond = layout.GetBeyond(name, train.direction);
                if (beyond.kind.Equals("boundary")) {
                    train.boundary = beyond.name;
                    train.boundaryCoordinate = end;
                } else {
                    name = beyond.name;
                    start = end;
                    train.path.Add(new Trains.PathPart(name, start));
                }
            }
        }
        public void AfterMovement(Trains.Train train, int speed, int previousSpeed) {
            train.speed = speed;
            train.distance += speed;
            train.maximumSpeed = Math.Max(train.maximumSpeed, speed);
            if (speed == 0)
                train.emergency = false;
            Trains.PathPart head = HeadSection(train);
            Trains.Stop stop = train.NextStop();
            bool arrived = stop != null && speed == 0 && head.section.Equals(stop.section) &&
                           train.head == head.start + layout.sections[head.section].length;
            if (arrived) {
                train.dwelling = true;
                stop.arrival = time;
                Log("ARRIVE " + train.name + " " + head.section);
            }
            if (speed == 0 && !arrived) {
                train.standing++;
                if (previousSpeed > 0)
                    Log("HOLD " + train.name + " " + head.section);
            }
            if (train.boundary != null && train.head - train.length >= train.boundaryCoordinate) {
                train.state = "EXITED";
                train.exited = time;
                Log("EXIT " + train.name + " " + train.boundary);
            }
        }
        public void RunTrains() {
            HashSet<string> enteredBoundaries = new();
            foreach (Trains.Train train in trains.Values) {
                if (!Enter(train, enteredBoundaries) || !FinishDwell(train))
                    continue;
                int? distance = LimitDistance(train);
                int previousSpeed = train.speed, speed = Trains.SelectSpeed(train, distance);
                Move(train, speed);
                AfterMovement(train, speed, previousSpeed);
            }
        }
        public void RecomputeOccupancy() {
            foreach (Layout.Section section in layout.sections.Values)
                section.occupants.Clear();
            foreach (Trains.Train train in trains.Values)
                foreach (OccupiedPart part in OccupiedParts(train)) {
                    List<string> occupants = layout.sections[part.section].occupants;
                    if (!occupants.Contains(train.name))
                        occupants.Add(train.name);
                }
        }
        public void SectionalRelease() {
            foreach (Interlocking.Route route in routes.Values) {
                if (!object.Equals(route.state, "USED"))
                    continue;
                List<string> remaining = new();
                foreach (string name in route.sections)
                    if (object.Equals(layout.sections[name].routeLock, route.name))
                        remaining.Add(name);
                foreach (string name in remaining)
                    if (Occupied(name))
                        route.passed.Add(name);
                foreach (string name in remaining) {
                    if (!route.passed.Contains(name) || Occupied(name))
                        break;
                    interlocking.UnlockSection(route, name);
                    Log("RELEASE " + route.name + " " + name);
                }
                bool any = false;
                foreach (string name in route.sections)
                    if (object.Equals(layout.sections[name].routeLock, route.name))
                        any = true;
                if (!any) {
                    interlocking.Release(route);
                    Log("DONE " + route.name);
                } else if (route.overlap.Count != 0 && route.overlapLocked) {
                    route.overlapCounter =
                        Occupied(route.sections[^1]) ? route.overlapCounter + 1 : 0;
                    if (route.overlapCounter >= overlapTime) {
                        interlocking.UnlockOverlap(route);
                        Log("OVERLAP " + route.name);
                    }
                }
            }
        }
        public void RecordStatistics() {
            foreach (Interlocking.Route route in routes.Values)
                if (route.state != null)
                    route.lockedSeconds++;
            foreach (Layout.Point point in layout.points.Values) {
                if (point.locks.Count != 0)
                    point.lockedSeconds++;
                if (point.moving)
                    point.movingSeconds++;
            }
            foreach (Layout.Section section in layout.sections.Values) {
                if (Occupied(section.name))
                    section.occupiedSeconds++;
                if (section.routeLock != null || section.overlapLocks.Count != 0)
                    section.lockedSeconds++;
                section.trains.UnionWith(section.occupants);
            }
            foreach (Layout.Signal signal in layout.signals.Values)
                signal.seconds.AddCount(signal.aspect, 1);
        }
        public List<string> Diagram() {
            int height = 0, width = 0;
            foreach (Layout.Section section in layout.sections.Values) {
                height = Math.Max(height, section.row + 1);
                width = Math.Max(width, section.last + 1);
            }
            foreach (Layout.Point point in layout.points.Values) {
                height = Math.Max(height, point.row + 1);
                width = Math.Max(width, point.column + 1);
            }
            foreach (Layout.Signal signal in layout.signals.Values) {
                height = Math.Max(height, signal.row + 1);
                width = Math.Max(width, signal.column + 1);
            }
            foreach (Layout.Buffer buffer in layout.buffers.Values) {
                height = Math.Max(height, buffer.row + 1);
                width = Math.Max(width, buffer.column + 1);
            }
            foreach (Layout.Label label in layout.labels) {
                height = Math.Max(height, label.row + 1);
                width = Math.Max(width, label.column + label.text.Length);
            }
            char[][] grid = Enumerable.Range(0, height)
                                .Select(
                                    _ => new char[width])
                                .ToArray();
            foreach (char[] row in grid)
                Array.Fill(row, ' ');
            foreach (Layout.Label label in layout.labels)
                for (int i = 0; i < label.text.Length; i++)
                    grid[label.row][label.column + i] = label.text[i];
            foreach (Layout.Section section in layout.sections.Values) {
                char character = section.failed                    ? '#'
                                 : section.routeLock != null       ? '='
                                 : section.overlapLocks.Count != 0 ? '~'
                                                                   : '-';
                for (int column = section.first; column <= section.last; column++)
                    grid[section.row][column] = character;
            }
            foreach (Trains.Train train in trains.Values)
                foreach (OccupiedPart part in OccupiedParts(train)) {
                    Layout.Section section = layout.sections[part.section];
                    int length = section.length, cells = section.last - section.first + 1, left,
                        right;
                    if (train.direction.Equals("UP")) {
                        left = part.low - part.start;
                        right = part.high - part.start;
                    } else {
                        left = length - (part.high - part.start);
                        right = length - (part.low - part.start);
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
            foreach (Layout.Buffer buffer in layout.buffers.Values)
                grid[buffer.row][buffer.column] = '|';
            foreach (Layout.Point point in layout.points.Values)
                grid[point.row][point.column] = point.Detected() ? point.position[0] : '?';
            foreach (Layout.Signal signal in layout.signals.Values)
                grid[signal.row][signal.column] = signal.aspect.Equals("RED")      ? 'X'
                                                  : signal.aspect.Equals("YELLOW") ? 'Y'
                                                                                   : 'G';
            List<string> lines = new();
            foreach (char[] row in grid) {
                int end = row.Length;
                while (end > 0 && row[end - 1] == ' ')
                    end--;
                lines.Add(new string(row, 0, end));
            }
            return lines;
        }
        public List<string> Snapshot() {
            List<string> lines = new(new List<string> { "SNAPSHOT " + time });
            lines.AddRange(Diagram());
            foreach (Trains.Train train in trains.Values)
                if (train.state.Equals("RUNNING")) {
                    List<string> sections = new();
                    foreach (OccupiedPart part in OccupiedParts(train))
                        sections.Add(part.section);
                    string body = string.Join(",", sections);
                    lines.Add("TRAIN " + train.symbol + " " + train.name + " " + train.direction +
                              " " + train.speed + (body.Length == 0 ? "" : " " + body));
                }
            List<string> active = new();
            foreach (Interlocking.Route route in routes.Values)
                if (route.state != null)
                    active.Add(route.name + "/" + route.state);
            lines.Add("ROUTES " + (active.Count == 0 ? "-" : string.Join(" ", active)));
            return lines;
        }
        public List<Timing> TrainRows() {
            List<Timing> rows = new();
            foreach (Trains.Train train in trains.Values) {
                rows.Add(
                    new Timing(train.name, "enter:" + train.entry, train.entryTime, train.entered));
                foreach (Trains.Stop stop in train.stops) {
                    rows.Add(new Timing(train.name, "arr:" + stop.section, stop.scheduledArrival,
                                        stop.arrival));
                    rows.Add(new Timing(train.name, "dep:" + stop.section, stop.scheduledDeparture,
                                        stop.departure));
                }
                rows.Add(new Timing(train.name, "exit:" + train.exit, train.scheduledExit,
                                    train.exited));
            }
            return rows;
        }
        public List<string> TrainReport(List<Timing> rows) {
            List<string> lines = new(new List<string> { "train,location,scheduled,actual,delay" });
            foreach (Timing row in rows)
                lines.Add(row.name + "," + row.location + "," + row.scheduled + "," +
                          (row.actual == null
                               ? "-,-"
                               : row.actual + "," + (row.actual.Value - row.scheduled)));
            return lines;
        }
        public string Punctuality(List<Timing> rows) {
            int onTime = 0, late = 0, missing = 0, totalDelay = 0, maximum = 0;
            foreach (Timing row in rows) {
                if (row.actual == null) {
                    missing++;
                    continue;
                }
                int delay = row.actual.Value - row.scheduled;
                if (delay <= 0)
                    onTime++;
                else {
                    late++;
                    totalDelay += delay;
                    maximum = Math.Max(maximum, delay);
                }
            }
            return "PUNCTUALITY on_time " + onTime + " late " + late + " missing " + missing +
                   " total_delay " + totalDelay + " max_delay " + maximum;
        }
        public List<string> Summary(List<Timing> rows) {
            List<string> lines = new();
            int grants = 0;
            foreach (Interlocking.Route route in routes.Values) {
                lines.Add("ROUTE " + route.name + " " + route.start + "-" + route.finish +
                          " requests " + route.requests + " grants " + route.grants + " uses " +
                          route.uses + " cancels " + route.cancels + " wait " + route.wait +
                          " maxwait " + route.maxwait + " locked " + route.lockedSeconds);
                grants += route.grants;
            }
            foreach (Layout.Point point in layout.points.Values)
                lines.Add("POINT " + point.name + " throws " + point.throwsCount + " locked " +
                          point.lockedSeconds + " moving " + point.movingSeconds + " final " +
                          (point.Detected() ? point.position : "?"));
            foreach (Layout.Section section in layout.sections.Values)
                lines.Add("SECTION " + section.name + " occupied " + section.occupiedSeconds +
                          " locked " + section.lockedSeconds + " trains " + section.trains.Count);
            foreach (Layout.Signal signal in layout.signals.Values)
                lines.Add(
                    "SIGNAL " + signal.name + " red " + signal.seconds.GetValueOrDefault("RED", 0) +
                    " yellow " + signal.seconds.GetValueOrDefault("YELLOW", 0) + " green " +
                    signal.seconds.GetValueOrDefault("GREEN", 0) + " passes " + signal.passes);
            int exited = 0, running = 0, waiting = 0;
            foreach (Trains.Train train in trains.Values) {
                lines.Add("TRAIN " + train.name + " " + train.symbol + " " + train.state +
                          " distance " + train.distance + " maxspeed " + train.maximumSpeed +
                          " standing " + train.standing + " passes " + train.passes);
                if (train.state.Equals("EXITED"))
                    exited++;
                else if (train.state.Equals("RUNNING"))
                    running++;
                else
                    waiting++;
            }
            lines.Add("TRAINS total " + trains.Count + " exited " + exited + " running " + running +
                      " waiting " + waiting);
            lines.Add(Punctuality(rows));
            lines.Add("REQUESTS total " + requestCount + " granted " + grants + " dropped " +
                      dropped + " pending " + queue.Count);
            return lines;
        }
        public void WriteReports() {
            List<Timing> rows = TrainRows();
            Dictionary<string, List<string>> reports = new();
            reports["events.txt"] = logLines;
            reports["snapshots.txt"] = snapshots;
            reports["train_log.csv"] = TrainReport(rows);
            reports["safety.txt"] = safety.Report();
            reports["summary.txt"] = Summary(rows);
            Directory.CreateDirectory(Path.Combine("output"));
            foreach (KeyValuePair<string, List<string>> report in reports)
                File.WriteAllText(Path.Combine("output", report.Key),
                                  report.Value.Count == 0 ? ""
                                                          : string.Join("\n", report.Value) + "\n",
                                  System.Text.Encoding.ASCII);
        }
        public void Run() {
            for (time = 0; time <= end; time++) {
                CompleteThrows();
                ReleaseApproaches();
                foreach (Trains.Request request in plannedRequests.GetValueOrDefault(time, new()))
                    AddRequest(request.route, request.train);
                ExecuteEvents();
                JudgeRequests();
                DecideSignals();
                RunTrains();
                RecomputeOccupancy();
                SectionalRelease();
                safety.Inspect(time, layout, routes);
                RecordStatistics();
                if (snapshotTimes.Contains(time))
                    snapshots.AddRange(Snapshot());
            }
            WriteReports();
        }
    }
    public static void Main(string[] args) { new Simulation().Run(); }
}
public static class MapHelpers {
    public static V GetOrAdd<K, V>(this IDictionary<K, V> map, K key, Func<V> factory) {
        if (!map.TryGetValue(key, out V value)) {
            value = factory();
            map[key] = value;
        }
        return value;
    }
    public static void AddCount<K>(this IDictionary<K, int> map, K key, int amount) {
        map.TryGetValue(key, out int value);
        map[key] = value + amount;
    }
}
