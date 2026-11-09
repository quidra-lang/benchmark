#nullable enable
using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Collections.Generic;

sealed record OrderConstraint(string Later, string Earlier);
sealed record AttemptRecord(int Size, int DeadEnds, string? FailedCourse);
sealed record AssignmentRecord(string Course, int Slot, int Saturation);
sealed record Insertion(string Course, int Slot, int Increase);
sealed record PenaltyPair(string First, string Second, int Relation, int Shared);
sealed record StudentPair(int Relation, int LowSlot, string LowCourse, int HighSlot, string HighCourse);
sealed record StudentPenalty(int[] Counts, int Total);
sealed record Trial(string Verdict, Dictionary<string, int>? Assignment = null, int Total = 0);
sealed record RoomGroup(Room Room, List<Placement> Placements);

sealed class ExamCalendar
{
    public int Days { get; }
    public int Periods => Lengths.Length;
    public int Limit { get; }
    public int FrontCount { get; }
    public int Deadline { get; }
    public int Ratio { get; }
    public int SlotCount => Days * Periods;
    public int[] Lengths { get; }
    public int[] Weights { get; }
    public SortedSet<int> Closed { get; } = new();
    public Dictionary<string, SortedSet<int>> Unavailable { get; } = new(StringComparer.Ordinal);
    public SortedDictionary<string, int> Fixed { get; } = new(StringComparer.Ordinal);
    public List<OrderConstraint> Orders { get; } = new();
    public Dictionary<string, List<string>> Arrows { get; } = new(StringComparer.Ordinal);

    public ExamCalendar(string[] lines)
    {
        int[][] settings = lines.Take(6).Select(line => line.Split(' ').Skip(1).Select(int.Parse).ToArray()).ToArray();
        Days = settings[0][0];
        Lengths = settings[1];
        Limit = settings[2][0];
        Weights = settings[3];
        FrontCount = settings[4][0];
        Deadline = settings[4][1];
        Ratio = settings[5][0];
    }

    public IEnumerable<int> Slots() => Enumerable.Range(1, SlotCount);

    public int SlotAt(string dayText, string periodText)
    {
        int day = int.Parse(dayText), period = int.Parse(periodText);
        return day >= 1 && day <= Days && period >= 1 && period <= Periods ? (day - 1) * Periods + period : 0;
    }

    public int DayOf(int slot) => (slot - 1) / Periods + 1;
    public string Name(int slot) => $"D{DayOf(slot)}P{(slot - 1) % Periods + 1}";
    public int Length(int slot) => Lengths[(slot - 1) % Periods];

    public int Relation(int first, int second)
    {
        int low = Math.Min(first, second), high = Math.Max(first, second);
        if (DayOf(low) == DayOf(high))
        {
            if (high - low == 1) return 0;
            if (high - low >= 2) return 1;
        }
        else if (high - low == 1) return 2;
        return -1;
    }
}

sealed class Breakdown
{
    public int[] Counts { get; }
    public int Late { get; }
    public int Total { get; }

    public Breakdown(int[] counts, int late, int[] weights)
    {
        Counts = counts;
        Late = late;
        Total = Enumerable.Range(0, 3).Sum(i => counts[i] * weights[i]) + late * weights[3];
    }

    public string Text() => $"back_to_back {Counts[0]} same_day {Counts[1]} overnight {Counts[2]} front_load {Late} penalty {Total}";
}

sealed class Scheduler
{
    private static readonly string[] Relations = { "back_to_back", "same_day", "overnight" };
    private static readonly string[] ExchangeVerdicts = { "fixed", "invalid", "worse", "applied" };
    private static readonly string[] SwapVerdicts = { "fixed", "invalid", "rooms", "worse", "applied" };
    private readonly SortedDictionary<string, Course> courses;
    private readonly SortedDictionary<string, List<string>> studentCourses;
    private readonly List<Room> rooms;
    private readonly ExamCalendar calendar;
    private readonly List<string> errors, empty, oversized, schedulable, frontLoad;
    private readonly int largestRoom;
    private readonly ConflictGraph graph;
    private readonly List<Edge> edges;
    private List<int> openSlots = new();
    private HashSet<int> fixedSlots = new();
    private Dictionary<string, int> assignment = new(StringComparer.Ordinal);
    private int penalty;
    private readonly List<AttemptRecord> attempts = new();
    private readonly List<AssignmentRecord> assignmentOrder = new();
    private readonly List<string> excluded = new();
    private readonly List<Insertion> insertions = new();
    private readonly Dictionary<string, List<string>> reasons = new(StringComparer.Ordinal);
    private Breakdown initial = null!, exchanged = null!;
    private readonly List<string> exchangeLog = new(), swapLog = new();
    private readonly Dictionary<string, Placement> placements = new(StringComparer.Ordinal);
    private readonly Dictionary<int, List<Placement>> slotPlacements = new();

    public Scheduler(SortedDictionary<string, Course> courses, SortedDictionary<string, List<string>> studentCourses,
        List<Room> rooms, ExamCalendar calendar, List<string> errors)
    {
        this.courses = courses;
        this.studentCourses = studentCourses;
        this.rooms = rooms;
        this.calendar = calendar;
        this.errors = errors;
        largestRoom = rooms.Max(room => room.Capacity);
        empty = courses.Keys.Where(id => courses[id].Size == 0).ToList();
        oversized = courses.Keys.Where(id => courses[id].Size > largestRoom).ToList();
        schedulable = courses.Keys.Where(id => !empty.Contains(id) && !oversized.Contains(id)).ToList();
        graph = new ConflictGraph(courses.Keys.Where(id => courses[id].Size > 0), studentCourses.Values);
        edges = graph.Edges();
        frontLoad = BySize(schedulable).Take(calendar.FrontCount).ToList();
    }

    private static int CeilDiv(int numerator, int denominator) => (numerator + denominator - 1) / denominator;
    private List<string> BySize(IEnumerable<string> ids) => ids.OrderByDescending(id => courses[id].Size)
        .ThenBy(id => id, StringComparer.Ordinal).ToList();
    private List<string> ByDegree(IEnumerable<string> ids) => ids.OrderByDescending(graph.Degree)
        .ThenBy(id => id, StringComparer.Ordinal).ToList();

    private List<string> BlockedStudents(Course course, int slot) => course.Students.Where(student =>
        calendar.Unavailable.TryGetValue(student, out var blocked) && blocked.Contains(slot)).ToList();

    private bool Suitable(Course course, int slot) => calendar.Length(slot) >= course.Duration && BlockedStudents(course, slot).Count == 0;
    private bool Packs(IEnumerable<string> ids) => Rooms.Pack(rooms, ids.Select(id => courses[id])) is not null;
    private static string Outside(string day, string period) => $"slot {day} {period} outside calendar";

    public void ValidateCalendar(string[] lines)
    {
        for (int i = 6; i < lines.Length; i++)
        {
            string[] fields = lines[i].Split(' ');
            string? message = fields[0] switch
            {
                "closed" => AcceptClosed(fields[1], fields[2]),
                "unavailable" => AcceptUnavailable(fields[1], fields[2], fields[3]),
                "fixed" => AcceptFixed(fields[1], fields[2], fields[3]),
                "after" => AcceptAfter(fields[1], fields[2]),
                _ => throw new InvalidDataException(fields[0])
            };
            if (message is not null) errors.Add($"calendar.txt line {i + 1}: {message}");
        }
        openSlots = calendar.Slots().Where(slot => !calendar.Closed.Contains(slot)).ToList();
        fixedSlots = calendar.Fixed.Values.ToHashSet();
    }

    private string? AcceptClosed(string day, string period)
    {
        int slot = calendar.SlotAt(day, period);
        if (slot == 0) return Outside(day, period);
        if (!calendar.Closed.Add(slot)) return $"duplicate closed {calendar.Name(slot)}";
        return null;
    }

    private string? AcceptUnavailable(string student, string day, string period)
    {
        if (!studentCourses.ContainsKey(student)) return $"unknown student {student}";
        int slot = calendar.SlotAt(day, period);
        if (slot == 0) return Outside(day, period);
        if (!calendar.Unavailable.ContainsKey(student)) calendar.Unavailable[student] = new SortedSet<int>();
        if (!calendar.Unavailable[student].Add(slot)) return $"duplicate unavailable {student} {calendar.Name(slot)}";
        return null;
    }

    private string? AcceptFixed(string id, string day, string period)
    {
        if (!courses.ContainsKey(id)) return $"unknown course {id}";
        if (!schedulable.Contains(id)) return $"course {id} not schedulable";
        int slot = calendar.SlotAt(day, period);
        if (slot == 0) return Outside(day, period);
        string name = calendar.Name(slot);
        if (calendar.Closed.Contains(slot)) return $"slot {name} closed";
        if (!Suitable(courses[id], slot)) return $"slot {name} unsuitable for {id}";
        if (calendar.Fixed.ContainsKey(id)) return $"duplicate fixed {id}";
        List<string> group = CoursesAt(calendar.Fixed, slot);
        string? clash = group.FirstOrDefault(graph.Neighbours(id).ContainsKey);
        if (clash is not null) return $"conflict {id} {clash}";
        group.Add(id);
        if (!Packs(group)) return $"rooms full {name}";
        calendar.Fixed[id] = slot;
        return null;
    }

    private string? AcceptAfter(string later, string earlier)
    {
        foreach (string id in new[] { later, earlier })
            if (!courses.ContainsKey(id)) return $"unknown course {id}";
        foreach (string id in new[] { later, earlier })
            if (!schedulable.Contains(id)) return $"course {id} not schedulable";
        if (later == earlier) return $"bad order {later} {earlier}";
        var order = new OrderConstraint(later, earlier);
        if (calendar.Orders.Contains(order)) return $"duplicate order {later} {earlier}";
        if (ConflictGraph.Reachable(calendar.Arrows, earlier, later)) return $"cycle {later} {earlier}";
        if (calendar.Fixed.ContainsKey(later) && calendar.Fixed.ContainsKey(earlier)
            && calendar.Fixed[later] <= calendar.Fixed[earlier]) return $"fixed order {later} {earlier}";
        calendar.Orders.Add(order);
        if (!calendar.Arrows.ContainsKey(later)) calendar.Arrows[later] = new List<string>();
        calendar.Arrows[later].Add(earlier);
        return null;
    }

    private static List<string> CoursesAt(IReadOnlyDictionary<string, int> slots, int slot) =>
        slots.Keys.Where(id => slots[id] == slot).OrderBy(id => id, StringComparer.Ordinal).ToList();

    private List<string> OrderConflicts(string id, int slot, IReadOnlyDictionary<string, int> slots)
    {
        var conflicts = new List<string>();
        foreach (OrderConstraint order in calendar.Orders)
        {
            if (order.Later == id && slots.TryGetValue(order.Earlier, out int earlier) && slot <= earlier)
                conflicts.Add(order.Earlier);
            else if (order.Earlier == id && slots.TryGetValue(order.Later, out int later) && slot >= later)
                conflicts.Add(order.Later);
        }
        return conflicts;
    }

    private bool OrdersSatisfied(IReadOnlyDictionary<string, int> slots) => calendar.Orders.All(order =>
        !slots.ContainsKey(order.Later) || !slots.ContainsKey(order.Earlier) || slots[order.Later] > slots[order.Earlier]);

    private List<int> CandidateSlots(string id, Dictionary<string, int> slots)
    {
        var candidates = new List<int>();
        foreach (int slot in openSlots)
        {
            if (!Suitable(courses[id], slot)) continue;
            if (graph.Neighbours(id).Keys.Any(other => slots.TryGetValue(other, out int assigned) && assigned == slot)) continue;
            if (OrderConflicts(id, slot, slots).Count > 0) continue;
            List<string> group = CoursesAt(slots, slot);
            group.Add(id);
            if (Packs(group)) candidates.Add(slot);
        }
        return candidates;
    }

    public void BuildTimetable()
    {
        while (true)
        {
            List<string> pending = schedulable.Where(id => !calendar.Fixed.ContainsKey(id) && !excluded.Contains(id)).ToList();
            var slots = new Dictionary<string, int>(calendar.Fixed, StringComparer.Ordinal);
            var attempt = new Attempt(pending, graph, calendar.Limit, CandidateSlots);
            bool succeeded = attempt.Search(slots);
            attempts.Add(new AttemptRecord(pending.Count, attempt.DeadEnds, succeeded ? null : attempt.DeadEndCourse));
            if (succeeded)
            {
                assignment = slots;
                foreach (Chosen chosen in attempt.Chosen)
                    assignmentOrder.Add(new AssignmentRecord(chosen.Course, slots[chosen.Course], chosen.Saturation));
                return;
            }
            excluded.Add(attempt.DeadEndCourse!);
        }
    }

    private List<PenaltyPair> PenaltyPairs(IReadOnlyDictionary<string, int> slots)
    {
        var pairs = new List<PenaltyPair>();
        foreach (Edge edge in edges)
            if (slots.ContainsKey(edge.First) && slots.ContainsKey(edge.Second))
            {
                int relation = calendar.Relation(slots[edge.First], slots[edge.Second]);
                if (relation >= 0) pairs.Add(new PenaltyPair(edge.First, edge.Second, relation, edge.Shared));
            }
        return pairs;
    }

    private List<string> LateCourses(IReadOnlyDictionary<string, int> slots) =>
        frontLoad.Where(id => slots.ContainsKey(id) && slots[id] > calendar.Deadline).ToList();

    private Breakdown Breakdown(IReadOnlyDictionary<string, int> slots)
    {
        var counts = new int[3];
        foreach (PenaltyPair pair in PenaltyPairs(slots)) counts[pair.Relation] += pair.Shared;
        return new Breakdown(counts, LateCourses(slots).Count, calendar.Weights);
    }

    private Dictionary<string, int> Contributions()
    {
        var result = assignment.Keys.ToDictionary(id => id, _ => 0, StringComparer.Ordinal);
        foreach (PenaltyPair pair in PenaltyPairs(assignment))
        {
            int value = calendar.Weights[pair.Relation] * pair.Shared;
            result[pair.First] += value;
            result[pair.Second] += value;
        }
        foreach (string id in LateCourses(assignment)) result[id] += calendar.Weights[3];
        return result;
    }

    private string BlockingReason(string id, int slot)
    {
        Course course = courses[id];
        if (calendar.Closed.Contains(slot)) return "closed";
        if (calendar.Length(slot) < course.Duration) return "too_short";
        List<string> blocked = BlockedStudents(course, slot);
        if (blocked.Count > 0) return $"unavailable {blocked[0]}";
        IReadOnlyDictionary<string, int> neighbours = graph.Neighbours(id);
        string? clash = neighbours.Keys.Where(other => assignment.TryGetValue(other, out int assigned) && assigned == slot)
            .OrderByDescending(other => neighbours[other]).ThenBy(other => other, StringComparer.Ordinal).FirstOrDefault();
        if (clash is not null) return $"conflict {clash} shared {neighbours[clash]}";
        List<string> conflicts = OrderConflicts(id, slot, assignment);
        if (conflicts.Count > 0) return $"order {conflicts.OrderBy(other => other, StringComparer.Ordinal).First()}";
        return "rooms";
    }

    public void InsertExcluded()
    {
        foreach (string id in excluded.OrderBy(id => id, StringComparer.Ordinal))
        {
            List<int> slots = CandidateSlots(id, assignment);
            if (slots.Count == 0)
            {
                reasons[id] = calendar.Slots().Select(slot => BlockingReason(id, slot)).ToList();
                continue;
            }
            int before = Breakdown(assignment).Total, best = 0, bestTotal = int.MaxValue;
            foreach (int slot in slots)
            {
                var trial = new Dictionary<string, int>(assignment, StringComparer.Ordinal) { [id] = slot };
                int total = Breakdown(trial).Total;
                if (total < bestTotal)
                {
                    best = slot;
                    bestTotal = total;
                }
            }
            assignment[id] = best;
            insertions.Add(new Insertion(id, best, bestTotal - before));
        }
        initial = Breakdown(assignment);
        penalty = initial.Total;
    }

    private List<string> Unscheduled() => oversized.Concat(excluded.Where(id => !assignment.ContainsKey(id)))
        .OrderBy(id => id, StringComparer.Ordinal).ToList();

    private bool ValidTrial(Dictionary<string, int> trial, List<string> moved) =>
        moved.All(id => Suitable(courses[id], trial[id])) && OrdersSatisfied(trial);

    private List<string> MovedCourses(Dictionary<string, int> trial) => trial.Keys.Where(id => trial[id] != assignment[id])
        .OrderBy(id => id, StringComparer.Ordinal).ToList();

    private Trial ExchangeTrial(int first, int second)
    {
        if (fixedSlots.Contains(first) || fixedSlots.Contains(second)) return new Trial("fixed");
        var trial = new Dictionary<string, int>(assignment, StringComparer.Ordinal);
        foreach (var entry in assignment)
        {
            if (entry.Value == first) trial[entry.Key] = second;
            else if (entry.Value == second) trial[entry.Key] = first;
        }
        if (!ValidTrial(trial, MovedCourses(trial))) return new Trial("invalid");
        int total = Breakdown(trial).Total;
        return total >= penalty ? new Trial("worse") : new Trial("applied", trial, total);
    }

    private static Dictionary<string, int> Tally(string[] verdicts) =>
        verdicts.ToDictionary(verdict => verdict, _ => 0, StringComparer.Ordinal);

    private static string VerdictCounts(Dictionary<string, int> tally, string[] verdicts) =>
        string.Join(" ", verdicts.Select(verdict => $"{verdict} {tally[verdict]}"));

    public void ExchangeSlots()
    {
        int round = 0, serial = 0;
        while (true)
        {
            round++;
            Dictionary<string, int> tally = Tally(ExchangeVerdicts);
            var records = new List<string>();
            int pairs = 0;
            for (int i = 0; i < openSlots.Count; i++)
                for (int j = i + 1; j < openSlots.Count; j++)
                {
                    int first = openSlots[i], second = openSlots[j];
                    pairs++;
                    Trial trial = ExchangeTrial(first, second);
                    tally[trial.Verdict]++;
                    if (trial.Verdict == "applied")
                    {
                        records.Add($"EXCHANGE {++serial} {calendar.Name(first)} {calendar.Name(second)} penalty {penalty} -> {trial.Total}");
                        assignment = trial.Assignment!;
                        penalty = trial.Total;
                    }
                }
            exchangeLog.Add($"ROUND {round} pairs {pairs} {VerdictCounts(tally, ExchangeVerdicts)}");
            exchangeLog.AddRange(records);
            if (tally["applied"] == 0) break;
        }
        exchanged = Breakdown(assignment);
    }

    private Trial SwapTrial(string id, int home, int target)
    {
        List<string> chain = graph.KempeChain(assignment, id, home, target);
        if (chain.Any(calendar.Fixed.ContainsKey)) return new Trial("fixed");
        var trial = new Dictionary<string, int>(assignment, StringComparer.Ordinal);
        foreach (string member in chain) trial[member] = assignment[member] == home ? target : home;
        if (!ValidTrial(trial, chain)) return new Trial("invalid");
        if (!Packs(CoursesAt(trial, home)) || !Packs(CoursesAt(trial, target))) return new Trial("rooms");
        int total = Breakdown(trial).Total;
        return total >= penalty ? new Trial("worse") : new Trial("applied", trial, total);
    }

    public void SwapChains()
    {
        int pass = 0, serial = 0;
        while (true)
        {
            pass++;
            Dictionary<string, int> tally = Tally(SwapVerdicts);
            var records = new List<string>();
            int candidates = 0;
            List<string> movable = assignment.Keys.Where(id => !calendar.Fixed.ContainsKey(id))
                .OrderBy(id => id, StringComparer.Ordinal).ToList();
            foreach (string id in movable)
            {
                int home = assignment[id];
                foreach (int target in openSlots)
                {
                    if (target == home) continue;
                    candidates++;
                    Trial trial = SwapTrial(id, home, target);
                    tally[trial.Verdict]++;
                    if (trial.Verdict != "applied") continue;
                    List<string> chain = MovedCourses(trial.Assignment!);
                    records.Add($"SWAP {++serial} {id} {calendar.Name(home)} {calendar.Name(target)} chain {chain.Count} penalty {penalty} -> {trial.Total}");
                    foreach (string member in chain)
                        records.Add($"  MOVE {member} {calendar.Name(assignment[member])} -> {calendar.Name(trial.Assignment![member])}");
                    assignment = trial.Assignment!;
                    penalty = trial.Total;
                    break;
                }
            }
            swapLog.Add($"PASS {pass} candidates {candidates} {VerdictCounts(tally, SwapVerdicts)}");
            swapLog.AddRange(records);
            if (tally["applied"] == 0) return;
        }
    }

    public void AssignRooms()
    {
        foreach (int slot in openSlots)
        {
            List<Placement> placed = Rooms.Pack(rooms, CoursesAt(assignment, slot).Select(id => courses[id]))!;
            slotPlacements[slot] = placed;
            foreach (Placement placement in placed) placements[placement.Course.Id] = placement;
        }
    }

    private List<RoomGroup> RoomGroups(int slot)
    {
        var groups = new List<RoomGroup>();
        foreach (Room room in rooms)
        {
            List<Placement> placed = slotPlacements[slot].Where(p => p.Room == room).ToList();
            if (placed.Count > 0) groups.Add(new RoomGroup(room, placed));
        }
        return groups;
    }

    private int Invigilators(int slot) => RoomGroups(slot).Sum(group =>
        CeilDiv(group.Placements.Sum(p => p.Course.Size), calendar.Ratio));

    private (int Exams, int Students) SlotLoad(int slot)
    {
        List<string> ids = CoursesAt(assignment, slot);
        return (ids.Count, ids.Sum(id => courses[id].Size));
    }

    private List<string> AssignedCourses(string student) => studentCourses[student].Where(assignment.ContainsKey)
        .OrderBy(id => assignment[id]).ThenBy(id => id, StringComparer.Ordinal).ToList();

    private List<StudentPair> StudentPairs(string student)
    {
        List<string> ids = AssignedCourses(student);
        var pairs = new List<StudentPair>();
        for (int i = 0; i < ids.Count; i++)
            for (int j = i + 1; j < ids.Count; j++)
            {
                string low = ids[i], high = ids[j];
                int relation = calendar.Relation(assignment[low], assignment[high]);
                if (relation >= 0) pairs.Add(new StudentPair(relation, assignment[low], low, assignment[high], high));
            }
        return pairs;
    }

    private StudentPenalty StudentPenalty(string student)
    {
        var counts = new int[3];
        foreach (StudentPair pair in StudentPairs(student)) counts[pair.Relation]++;
        return new StudentPenalty(counts, Enumerable.Range(0, 3).Sum(i => counts[i] * calendar.Weights[i]));
    }

    public List<string> TimetableLines()
    {
        var lines = new List<string>
        {
            $"TIMETABLE days {calendar.Days} periods {calendar.Periods} open {openSlots.Count} courses {courses.Count} scheduled {assignment.Count} unscheduled {Unscheduled().Count} empty {empty.Count}"
        };
        List<string> header = Enumerable.Range(1, calendar.Periods).Select(period => $"P{period}").ToList();
        header.Add("TOTAL");
        lines.Add(Report.FixedWidthLine("DAY", header, 4, 10));
        for (int day = 1; day <= calendar.Days; day++)
        {
            var cells = new List<string>();
            int dayExams = 0, dayStudents = 0;
            for (int period = 1; period <= calendar.Periods; period++)
            {
                int slot = (day - 1) * calendar.Periods + period;
                if (calendar.Closed.Contains(slot)) cells.Add("closed");
                else
                {
                    var load = SlotLoad(slot);
                    cells.Add($"{load.Exams}/{load.Students}");
                    dayExams += load.Exams;
                    dayStudents += load.Students;
                }
            }
            cells.Add($"{dayExams}/{dayStudents}");
            lines.Add(Report.FixedWidthLine($"D{day}", cells, 4, 10));
        }
        foreach (int slot in calendar.Slots())
        {
            string prefix = $"SLOT {slot} {calendar.Name(slot)} minutes {calendar.Length(slot)}";
            if (calendar.Closed.Contains(slot))
            {
                lines.Add(prefix + " closed");
                continue;
            }
            var load = SlotLoad(slot);
            List<RoomGroup> groups = RoomGroups(slot);
            int seats = groups.Sum(group => group.Room.Capacity);
            lines.Add($"{prefix} exams {load.Exams} students {load.Students} rooms {groups.Count} seats {seats} invigilators {Invigilators(slot)}");
            foreach (Placement placement in slotPlacements[slot])
            {
                Course course = placement.Course;
                string marker = calendar.Fixed.ContainsKey(course.Id) ? " fixed" : "";
                lines.Add($"  {course.Id} {course.Duration}min students {course.Size} room {placement.Room.Id} seats {placement.FirstSeat}-{placement.LastSeat}{marker} {course.Name}");
            }
        }
        foreach (Room room in rooms)
        {
            int used = 0, exams = 0, seated = 0;
            foreach (int slot in openSlots)
                foreach (RoomGroup group in RoomGroups(slot))
                    if (group.Room == room)
                    {
                        used++;
                        exams += group.Placements.Count;
                        seated += group.Placements.Sum(p => p.Course.Size);
                    }
            int utilization = Report.RoundedPercent(seated, room.Capacity * openSlots.Count);
            lines.Add($"ROOM {room.Id} capacity {room.Capacity} slots {used} exams {exams} seated {seated} utilization {utilization}");
        }
        lines.Add($"INVIGILATORS total {openSlots.Sum(Invigilators)} ratio {calendar.Ratio}");
        return lines;
    }

    public List<string> RoomLines()
    {
        var lines = new List<string> { "slot,room,course,students,first_seat,last_seat" };
        foreach (int slot in openSlots)
            foreach (RoomGroup group in RoomGroups(slot))
                foreach (Placement p in group.Placements)
                    lines.Add($"{calendar.Name(slot)},{group.Room.Id},{p.Course.Id},{p.Course.Size},{p.FirstSeat},{p.LastSeat}");
        return lines;
    }

    public List<string> PenaltyLines()
    {
        int[] weights = calendar.Weights;
        Breakdown final = Breakdown(assignment);
        var lines = new List<string>
        {
            $"WEIGHTS back_to_back {weights[0]} same_day {weights[1]} overnight {weights[2]} front_load {weights[3]}",
            $"FRONT_LOAD courses {frontLoad.Count} last_slot {calendar.Name(calendar.Deadline)}",
            $"INITIAL {initial.Text()}"
        };
        lines.AddRange(exchangeLog);
        lines.Add($"EXCHANGED {exchanged.Text()}");
        lines.AddRange(swapLog);
        lines.Add($"FINAL {final.Text()}");
        lines.Add($"SAVED {initial.Total - final.Total}");
        var daily = new int[calendar.Days + 1, 3];
        foreach (PenaltyPair pair in PenaltyPairs(assignment))
        {
            int day = calendar.DayOf(Math.Min(assignment[pair.First], assignment[pair.Second]));
            daily[day, pair.Relation] += pair.Shared;
        }
        for (int day = 1; day <= calendar.Days; day++)
            lines.Add($"DAY D{day} back_to_back {daily[day, 0]} same_day {daily[day, 1]} overnight {daily[day, 2]}");
        foreach (string id in LateCourses(assignment))
            lines.Add($"LATE {id} {calendar.Name(assignment[id])} students {courses[id].Size}");
        Dictionary<string, int> contribution = Contributions();
        List<string> ranked = contribution.Keys.OrderByDescending(id => contribution[id])
            .ThenBy(id => id, StringComparer.Ordinal).Take(10).ToList();
        foreach (string id in ranked)
            if (contribution[id] > 0) lines.Add($"COURSE {id} {calendar.Name(assignment[id])} penalty {contribution[id]}");
        lines.AddRange(StudentStatistics());
        return lines;
    }

    private List<string> StudentStatistics()
    {
        var histogram = new SortedDictionary<int, int>();
        var gaps = new SortedDictionary<int, int>();
        var dayLoads = new SortedDictionary<int, int>();
        var statistics = new Dictionary<string, StudentPenalty>(StringComparer.Ordinal);
        foreach (string student in studentCourses.Keys)
        {
            StudentPenalty result = StudentPenalty(student);
            statistics[student] = result;
            histogram[result.Total] = histogram.GetValueOrDefault(result.Total) + 1;
            List<int> slots = AssignedCourses(student).Select(id => assignment[id]).ToList();
            for (int i = 1; i < slots.Count; i++)
            {
                int gap = slots[i] - slots[i - 1];
                gaps[gap] = gaps.GetValueOrDefault(gap) + 1;
            }
            if (slots.Count > 0)
            {
                int maximum = slots.GroupBy(calendar.DayOf).Max(group => group.Count());
                dayLoads[maximum] = dayLoads.GetValueOrDefault(maximum) + 1;
            }
        }
        var lines = histogram.Select(entry => $"HISTOGRAM {entry.Key} {entry.Value}").ToList();
        lines.AddRange(gaps.Select(entry => $"GAP {entry.Key} {entry.Value}"));
        lines.AddRange(dayLoads.Select(entry => $"DAYLOAD {entry.Key} {entry.Value}"));
        List<string> ranking = statistics.Keys.OrderByDescending(student => statistics[student].Total)
            .ThenBy(student => student, StringComparer.Ordinal).Take(5).ToList();
        foreach (string student in ranking)
        {
            StudentPenalty result = statistics[student];
            if (result.Total > 0)
                lines.Add($"WORST {student} penalty {result.Total} back_to_back {result.Counts[0]} same_day {result.Counts[1]} overnight {result.Counts[2]}");
        }
        return lines;
    }

    public List<string> ScheduleLines(string[] queries)
    {
        var lines = new List<string>();
        foreach (string student in queries)
        {
            if (!studentCourses.ContainsKey(student))
            {
                lines.Add($"STUDENT {student} not found");
                continue;
            }
            List<string> ids = studentCourses[student], assigned = AssignedCourses(student);
            lines.Add($"STUDENT {student} exams {ids.Count} scheduled {assigned.Count} penalty {StudentPenalty(student).Total}");
            foreach (string id in assigned)
            {
                Placement placement = placements[id];
                Course course = placement.Course;
                int seat = placement.FirstSeat + course.Students.IndexOf(student);
                lines.Add($"  {calendar.Name(assignment[id])} {id} room {placement.Room.Id} seat {seat} {course.Name}");
            }
            foreach (string id in ids)
                if (!assignment.ContainsKey(id)) lines.Add($"  UNSCHEDULED {id} {courses[id].Name}");
            foreach (StudentPair pair in StudentPairs(student))
                lines.Add($"  {Relations[pair.Relation].ToUpperInvariant()} {calendar.Name(pair.LowSlot)} {pair.LowCourse} {calendar.Name(pair.HighSlot)} {pair.HighCourse}");
            if (calendar.Unavailable.TryGetValue(student, out var blocked))
                foreach (int slot in blocked) lines.Add($"  UNAVAILABLE {calendar.Name(slot)}");
        }
        return lines;
    }

    public List<string> StatusLines()
    {
        Dictionary<string, int> contribution = Contributions();
        var lines = new List<string> { "course,status,slot,students,minutes,degree,penalty" };
        foreach (string id in courses.Keys)
        {
            Course course = courses[id];
            string status = calendar.Fixed.ContainsKey(id) ? "fixed" : assignment.ContainsKey(id) ? "scheduled"
                : oversized.Contains(id) ? "too_large" : empty.Contains(id) ? "empty" : "no_slot";
            string slot = assignment.ContainsKey(id) ? calendar.Name(assignment[id]) : "-";
            lines.Add($"{id},{status},{slot},{course.Size},{course.Duration},{graph.Degree(id)},{contribution.GetValueOrDefault(id)}");
        }
        return lines;
    }

    private List<string> GraphLines()
    {
        int vertices = graph.Vertices.Count, edgeCount = edges.Count, shared = edges.Sum(edge => edge.Shared);
        int density = vertices >= 2 ? 2000 * edgeCount / (vertices * (vertices - 1)) : 0;
        var lines = new List<string> { $"GRAPH courses {vertices} edges {edgeCount} shared {shared} density {density}" };
        foreach (string id in ByDegree(graph.Vertices).Take(5))
            lines.Add($"DEGREE {id} neighbours {graph.Degree(id)} shared {graph.SharedTotal(id)} students {courses[id].Size}");
        List<List<string>> components = graph.Components();
        lines.Add($"COMPONENTS {components.Count}");
        for (int i = 0; i < components.Count; i++)
            lines.Add($"COMPONENT {i + 1} size {components[i].Count} first {components[i][0]}");
        List<string> clique = graph.GreedyClique(schedulable);
        lines.Add($"CLIQUE size {clique.Count}" + (clique.Count > 0 ? " " + string.Join(" ", clique) : ""));
        return lines;
    }

    private List<string> CapacityLines()
    {
        List<int> loads = studentCourses.Values.Select(ids => ids.Count).ToList();
        int maximum = loads.Max(), demand = schedulable.Sum(id => courses[id].Size), capacity = rooms.Sum(room => room.Capacity);
        var lines = new List<string>
        {
            $"LOAD max_exams {maximum} students {loads.Count(load => load == maximum)}",
            $"SEATS demand {demand} capacity {capacity} min_slots {CeilDiv(demand, capacity)}",
            $"HEURISTIC largest_degree slots {Coloring.GreedyNumbering(ByDegree(schedulable), graph)}",
            $"HEURISTIC largest_enrolment slots {Coloring.GreedyNumbering(BySize(schedulable), graph)}"
        };
        List<string> table = BySize(graph.Vertices).Take(8).ToList();
        lines.Add(Report.FixedWidthLine("MATRIX", table, 9, 9));
        foreach (string row in table)
        {
            List<string> cells = table.Select(column => row == column ? "-" : graph.Neighbours(row).GetValueOrDefault(column).ToString()).ToList();
            lines.Add(Report.FixedWidthLine(row, cells, 9, 9));
        }
        return lines;
    }

    public List<string> ReportLines()
    {
        int enrolments = studentCourses.Values.Sum(ids => ids.Count);
        var lines = new List<string>
        {
            $"INPUT courses {courses.Count} enrolments {enrolments} rooms {rooms.Count} students {studentCourses.Count} errors {errors.Count}"
        };
        lines.AddRange(errors.Select(error => $"ERROR {error}"));
        lines.AddRange(GraphLines());
        lines.AddRange(CapacityLines());
        lines.AddRange(empty.Select(id => $"EMPTY {id}"));
        foreach (string id in oversized) lines.Add($"TOO_LARGE {id} students {courses[id].Size} largest_room {largestRoom}");
        foreach (int slot in calendar.Closed) lines.Add($"CLOSED {calendar.Name(slot)}");
        foreach (var entry in calendar.Fixed) lines.Add($"FIXED {entry.Key} {calendar.Name(entry.Value)}");
        foreach (OrderConstraint order in calendar.Orders) lines.Add($"AFTER {order.Later} {order.Earlier}");
        for (int i = 0; i < attempts.Count; i++)
        {
            AttemptRecord attempt = attempts[i];
            string result = attempt.FailedCourse is null ? "success" : $"failed {attempt.FailedCourse}";
            lines.Add($"ATTEMPT {i + 1} courses {attempt.Size} backtracks {attempt.DeadEnds} {result}");
        }
        for (int i = 0; i < assignmentOrder.Count; i++)
        {
            AssignmentRecord chosen = assignmentOrder[i];
            lines.Add($"ORDER {i + 1} {chosen.Course} {calendar.Name(chosen.Slot)} saturation {chosen.Saturation} degree {graph.Degree(chosen.Course)}");
        }
        foreach (Insertion insertion in insertions)
            lines.Add($"INSERTED {insertion.Course} {calendar.Name(insertion.Slot)} penalty {insertion.Increase}");
        foreach (string id in Unscheduled())
        {
            string reason = oversized.Contains(id) ? "too_large" : "no_slot";
            lines.Add($"UNSCHEDULED {id} reason {reason} students {courses[id].Size}");
            if (reasons.TryGetValue(id, out List<string>? recorded))
                for (int i = 0; i < recorded.Count; i++) lines.Add($"  {calendar.Name(i + 1)} {recorded[i]}");
        }
        lines.Add($"SUMMARY scheduled {assignment.Count} unscheduled {Unscheduled().Count} slots_used {assignment.Values.Distinct().Count()} penalty {penalty}");
        return lines;
    }
}

static class Program
{
    public static void Main()
    {
        var errors = new List<string>();
        SortedDictionary<string, Course> courses = Enrolment.LoadCourses("input/courses.csv", errors);
        SortedDictionary<string, List<string>> students = Enrolment.LoadEnrolments("input/enrolments.csv", courses, errors);
        List<Room> rooms = Rooms.Load("input/rooms.csv", errors);
        string[] calendarLines = File.ReadAllLines("input/calendar.txt", Encoding.ASCII);
        var scheduler = new Scheduler(courses, students, rooms, new ExamCalendar(calendarLines), errors);
        scheduler.ValidateCalendar(calendarLines);
        scheduler.BuildTimetable();
        scheduler.InsertExcluded();
        scheduler.ExchangeSlots();
        scheduler.SwapChains();
        scheduler.AssignRooms();
        string[] queries = File.ReadAllLines("input/queries.txt", Encoding.ASCII);
        Report.WriteFiles("output", new Dictionary<string, List<string>>(StringComparer.Ordinal)
        {
            ["timetable.txt"] = scheduler.TimetableLines(),
            ["rooms.csv"] = scheduler.RoomLines(),
            ["penalties.txt"] = scheduler.PenaltyLines(),
            ["student_schedules.txt"] = scheduler.ScheduleLines(queries),
            ["course_status.csv"] = scheduler.StatusLines(),
            ["report.txt"] = scheduler.ReportLines()
        });
    }
}
