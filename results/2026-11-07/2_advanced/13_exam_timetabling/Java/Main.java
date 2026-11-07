import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collection;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import java.util.TreeSet;
import java.util.stream.IntStream;

record OrderConstraint(String later, String earlier) {}
record AttemptRecord(int size, int deadEnds, String failedCourse) {}
record AssignmentRecord(String course, int slot, int saturation) {}
record Insertion(String course, int slot, int increase) {}
record PenaltyPair(String first, String second, int relation, int shared) {}
record StudentPair(int relation, int lowSlot, String lowCourse, int highSlot, String highCourse) {}
record StudentPenalty(int[] counts, int total) {}
record Trial(String verdict, Map<String, Integer> assignment, int total) {}
record RoomGroup(Room room, List<Placement> placements) {}

final class ExamCalendar {
    final int days, periods, limit, frontCount, deadline, ratio, slotCount;
    final int[] lengths, weights;
    final Set<Integer> closed = new TreeSet<>();
    final Map<String, Set<Integer>> unavailable = new TreeMap<>();
    final Map<String, Integer> fixed = new TreeMap<>();
    final List<OrderConstraint> orders = new ArrayList<>();
    final Map<String, List<String>> arrows = new HashMap<>();

    ExamCalendar(List<String> lines) {
        List<int[]> settings = lines.subList(0, 6).stream()
            .map(line -> Arrays.stream(line.split(" ")).skip(1).mapToInt(Integer::parseInt).toArray())
            .toList();
        days = settings.get(0)[0];
        lengths = settings.get(1);
        periods = lengths.length;
        limit = settings.get(2)[0];
        weights = settings.get(3);
        frontCount = settings.get(4)[0];
        deadline = settings.get(4)[1];
        ratio = settings.get(5)[0];
        slotCount = days * periods;
    }

    List<Integer> slots() {
        return IntStream.rangeClosed(1, slotCount).boxed().toList();
    }

    int slotAt(String dayText, String periodText) {
        int day = Integer.parseInt(dayText), period = Integer.parseInt(periodText);
        return day >= 1 && day <= days && period >= 1 && period <= periods
            ? (day - 1) * periods + period : 0;
    }

    int dayOf(int slot) {
        return (slot - 1) / periods + 1;
    }

    String name(int slot) {
        return "D" + dayOf(slot) + "P" + ((slot - 1) % periods + 1);
    }

    int length(int slot) {
        return lengths[(slot - 1) % periods];
    }

    int relation(int first, int second) {
        int low = Math.min(first, second), high = Math.max(first, second);
        if (dayOf(low) == dayOf(high)) {
            if (high - low == 1) return 0;
            if (high - low >= 2) return 1;
        } else if (high - low == 1) return 2;
        return -1;
    }
}

final class Breakdown {
    final int[] counts;
    final int late, total;

    Breakdown(int[] counts, int late, int[] weights) {
        this.counts = counts;
        this.late = late;
        total = IntStream.range(0, 3).map(i -> counts[i] * weights[i]).sum() + late * weights[3];
    }

    String text() {
        return "back_to_back " + counts[0] + " same_day " + counts[1] + " overnight " + counts[2]
            + " front_load " + late + " penalty " + total;
    }
}

final class Scheduler {
    static final List<String> RELATIONS = List.of("back_to_back", "same_day", "overnight");
    static final List<String> EXCHANGE_VERDICTS = List.of("fixed", "invalid", "worse", "applied");
    static final List<String> SWAP_VERDICTS = List.of("fixed", "invalid", "rooms", "worse", "applied");
    final Map<String, Course> courses;
    final Map<String, List<String>> studentCourses;
    final List<Room> rooms;
    final ExamCalendar calendar;
    final List<String> errors, empty, oversized, schedulable, frontLoad;
    final int largestRoom;
    final ConflictGraph graph;
    final List<Edge> edges;
    List<Integer> openSlots = new ArrayList<>();
    Set<Integer> fixedSlots = new HashSet<>();
    Map<String, Integer> assignment = new TreeMap<>();
    int penalty;
    final List<AttemptRecord> attempts = new ArrayList<>();
    final List<AssignmentRecord> assignmentOrder = new ArrayList<>();
    final List<String> excluded = new ArrayList<>();
    final List<Insertion> insertions = new ArrayList<>();
    final Map<String, List<String>> reasons = new TreeMap<>();
    Breakdown initial, exchanged;
    final List<String> exchangeLog = new ArrayList<>(), swapLog = new ArrayList<>();
    final Map<String, Placement> placements = new TreeMap<>();
    final Map<Integer, List<Placement>> slotPlacements = new TreeMap<>();

    Scheduler(Map<String, Course> courses, Map<String, List<String>> studentCourses,
              List<Room> rooms, ExamCalendar calendar, List<String> errors) {
        this.courses = courses;
        this.studentCourses = studentCourses;
        this.rooms = rooms;
        this.calendar = calendar;
        this.errors = errors;
        largestRoom = rooms.stream().mapToInt(Room::capacity).max().orElseThrow();
        List<String> ids = courses.keySet().stream().sorted().toList();
        empty = ids.stream().filter(id -> courses.get(id).size() == 0).toList();
        oversized = ids.stream().filter(id -> courses.get(id).size() > largestRoom).toList();
        schedulable = ids.stream().filter(id -> !empty.contains(id) && !oversized.contains(id)).toList();
        List<String> vertices = ids.stream().filter(id -> courses.get(id).size() > 0).toList();
        graph = new ConflictGraph(vertices, studentCourses.values());
        edges = graph.edges();
        frontLoad = bySize(schedulable).stream().limit(calendar.frontCount).toList();
    }

    static int ceilDiv(int numerator, int denominator) {
        return (numerator + denominator - 1) / denominator;
    }

    List<String> bySize(Collection<String> ids) {
        return ids.stream().sorted(Comparator.<String>comparingInt(id -> courses.get(id).size())
            .reversed().thenComparing(Comparator.naturalOrder())).toList();
    }

    List<String> byDegree(Collection<String> ids) {
        return ids.stream().sorted(Comparator.<String>comparingInt(graph::degree).reversed()
            .thenComparing(Comparator.naturalOrder())).toList();
    }

    List<String> blockedStudents(Course course, int slot) {
        return course.students.stream().filter(student ->
            calendar.unavailable.getOrDefault(student, Set.of()).contains(slot)).toList();
    }

    boolean suitable(Course course, int slot) {
        return calendar.length(slot) >= course.duration && blockedStudents(course, slot).isEmpty();
    }

    boolean packs(Collection<String> ids) {
        return Rooms.pack(rooms, ids.stream().map(courses::get).toList()) != null;
    }

    String outside(String day, String period) {
        return "slot " + day + " " + period + " outside calendar";
    }

    void validateCalendar(List<String> lines) {
        for (int i = 6; i < lines.size(); i++) {
            String[] fields = lines.get(i).split(" ");
            String message = switch (fields[0]) {
                case "closed" -> acceptClosed(fields[1], fields[2]);
                case "unavailable" -> acceptUnavailable(fields[1], fields[2], fields[3]);
                case "fixed" -> acceptFixed(fields[1], fields[2], fields[3]);
                case "after" -> acceptAfter(fields[1], fields[2]);
                default -> throw new IllegalArgumentException(fields[0]);
            };
            if (message != null) errors.add("calendar.txt line " + (i + 1) + ": " + message);
        }
        openSlots = calendar.slots().stream().filter(slot -> !calendar.closed.contains(slot)).toList();
        fixedSlots = new HashSet<>(calendar.fixed.values());
    }

    String acceptClosed(String day, String period) {
        int slot = calendar.slotAt(day, period);
        if (slot == 0) return outside(day, period);
        if (calendar.closed.contains(slot)) return "duplicate closed " + calendar.name(slot);
        calendar.closed.add(slot);
        return null;
    }

    String acceptUnavailable(String student, String day, String period) {
        if (!studentCourses.containsKey(student)) return "unknown student " + student;
        int slot = calendar.slotAt(day, period);
        if (slot == 0) return outside(day, period);
        Set<Integer> blocked = calendar.unavailable.computeIfAbsent(student, ignored -> new TreeSet<>());
        if (!blocked.add(slot)) return "duplicate unavailable " + student + " " + calendar.name(slot);
        return null;
    }

    String acceptFixed(String id, String day, String period) {
        if (!courses.containsKey(id)) return "unknown course " + id;
        if (!schedulable.contains(id)) return "course " + id + " not schedulable";
        int slot = calendar.slotAt(day, period);
        if (slot == 0) return outside(day, period);
        String name = calendar.name(slot);
        if (calendar.closed.contains(slot)) return "slot " + name + " closed";
        if (!suitable(courses.get(id), slot)) return "slot " + name + " unsuitable for " + id;
        if (calendar.fixed.containsKey(id)) return "duplicate fixed " + id;
        List<String> group = new ArrayList<>(coursesAt(calendar.fixed, slot));
        List<String> clashes = group.stream().filter(graph.neighbours(id)::containsKey).toList();
        if (!clashes.isEmpty()) return "conflict " + id + " " + clashes.getFirst();
        group.add(id);
        if (!packs(group)) return "rooms full " + name;
        calendar.fixed.put(id, slot);
        return null;
    }

    String acceptAfter(String later, String earlier) {
        for (String id : List.of(later, earlier))
            if (!courses.containsKey(id)) return "unknown course " + id;
        for (String id : List.of(later, earlier))
            if (!schedulable.contains(id)) return "course " + id + " not schedulable";
        if (later.equals(earlier)) return "bad order " + later + " " + earlier;
        OrderConstraint order = new OrderConstraint(later, earlier);
        if (calendar.orders.contains(order)) return "duplicate order " + later + " " + earlier;
        if (ConflictGraph.reachable(calendar.arrows, earlier, later)) return "cycle " + later + " " + earlier;
        if (calendar.fixed.containsKey(later) && calendar.fixed.containsKey(earlier)
                && calendar.fixed.get(later) <= calendar.fixed.get(earlier))
            return "fixed order " + later + " " + earlier;
        calendar.orders.add(order);
        calendar.arrows.computeIfAbsent(later, ignored -> new ArrayList<>()).add(earlier);
        return null;
    }

    List<String> coursesAt(Map<String, Integer> slots, int slot) {
        return slots.keySet().stream().filter(id -> slots.get(id) == slot).sorted().toList();
    }

    List<String> orderConflicts(String id, int slot, Map<String, Integer> slots) {
        List<String> conflicts = new ArrayList<>();
        for (OrderConstraint order : calendar.orders) {
            if (order.later().equals(id) && slots.containsKey(order.earlier())
                    && slot <= slots.get(order.earlier())) conflicts.add(order.earlier());
            else if (order.earlier().equals(id) && slots.containsKey(order.later())
                    && slot >= slots.get(order.later())) conflicts.add(order.later());
        }
        return conflicts;
    }

    boolean ordersSatisfied(Map<String, Integer> slots) {
        return calendar.orders.stream().allMatch(order ->
            !slots.containsKey(order.later()) || !slots.containsKey(order.earlier())
                || slots.get(order.later()) > slots.get(order.earlier()));
    }

    List<Integer> candidateSlots(String id, Map<String, Integer> slots) {
        List<Integer> candidates = new ArrayList<>();
        for (int slot : openSlots) {
            if (!suitable(courses.get(id), slot)) continue;
            if (graph.neighbours(id).keySet().stream().anyMatch(other ->
                    slots.containsKey(other) && slots.get(other) == slot)) continue;
            if (!orderConflicts(id, slot, slots).isEmpty()) continue;
            List<String> group = new ArrayList<>(coursesAt(slots, slot));
            group.add(id);
            if (packs(group)) candidates.add(slot);
        }
        return candidates;
    }

    void buildTimetable() {
        while (true) {
            List<String> pending = schedulable.stream().filter(id ->
                !calendar.fixed.containsKey(id) && !excluded.contains(id)).toList();
            Map<String, Integer> slots = new TreeMap<>(calendar.fixed);
            Attempt attempt = new Attempt(pending, graph, calendar.limit, this::candidateSlots);
            boolean succeeded = attempt.search(slots);
            attempts.add(new AttemptRecord(pending.size(), attempt.deadEnds,
                succeeded ? null : attempt.deadEndCourse));
            if (succeeded) {
                assignment = slots;
                for (Chosen chosen : attempt.chosen)
                    assignmentOrder.add(new AssignmentRecord(chosen.course(),
                        slots.get(chosen.course()), chosen.saturation()));
                return;
            }
            excluded.add(attempt.deadEndCourse);
        }
    }

    List<PenaltyPair> penaltyPairs(Map<String, Integer> slots) {
        List<PenaltyPair> pairs = new ArrayList<>();
        for (Edge edge : edges)
            if (slots.containsKey(edge.first()) && slots.containsKey(edge.second())) {
                int relation = calendar.relation(slots.get(edge.first()), slots.get(edge.second()));
                if (relation >= 0) pairs.add(new PenaltyPair(edge.first(), edge.second(), relation, edge.shared()));
            }
        return pairs;
    }

    List<String> lateCourses(Map<String, Integer> slots) {
        return frontLoad.stream().filter(id -> slots.containsKey(id) && slots.get(id) > calendar.deadline).toList();
    }

    Breakdown breakdown(Map<String, Integer> slots) {
        int[] counts = new int[3];
        for (PenaltyPair pair : penaltyPairs(slots)) counts[pair.relation()] += pair.shared();
        return new Breakdown(counts, lateCourses(slots).size(), calendar.weights);
    }

    Map<String, Integer> contributions() {
        Map<String, Integer> result = new TreeMap<>();
        assignment.keySet().forEach(id -> result.put(id, 0));
        for (PenaltyPair pair : penaltyPairs(assignment)) {
            int value = calendar.weights[pair.relation()] * pair.shared();
            result.merge(pair.first(), value, Integer::sum);
            result.merge(pair.second(), value, Integer::sum);
        }
        for (String id : lateCourses(assignment)) result.merge(id, calendar.weights[3], Integer::sum);
        return result;
    }

    String blockingReason(String id, int slot) {
        Course course = courses.get(id);
        if (calendar.closed.contains(slot)) return "closed";
        if (calendar.length(slot) < course.duration) return "too_short";
        List<String> blocked = blockedStudents(course, slot);
        if (!blocked.isEmpty()) return "unavailable " + blocked.getFirst();
        Map<String, Integer> neighbours = graph.neighbours(id);
        String clash = neighbours.keySet().stream().filter(other ->
                assignment.containsKey(other) && assignment.get(other) == slot)
            .min(Comparator.<String>comparingInt(neighbours::get).reversed()
                .thenComparing(Comparator.naturalOrder())).orElse(null);
        if (clash != null) return "conflict " + clash + " shared " + neighbours.get(clash);
        List<String> conflicts = orderConflicts(id, slot, assignment);
        if (!conflicts.isEmpty()) return "order " + conflicts.stream().min(String::compareTo).orElseThrow();
        return "rooms";
    }

    void insertExcluded() {
        for (String id : excluded.stream().sorted().toList()) {
            List<Integer> slots = candidateSlots(id, assignment);
            if (slots.isEmpty()) {
                reasons.put(id, calendar.slots().stream().map(slot -> blockingReason(id, slot)).toList());
                continue;
            }
            int before = breakdown(assignment).total, best = 0, bestTotal = Integer.MAX_VALUE;
            for (int slot : slots) {
                Map<String, Integer> trial = new TreeMap<>(assignment);
                trial.put(id, slot);
                int total = breakdown(trial).total;
                if (total < bestTotal) {
                    best = slot;
                    bestTotal = total;
                }
            }
            assignment.put(id, best);
            insertions.add(new Insertion(id, best, bestTotal - before));
        }
        initial = breakdown(assignment);
        penalty = initial.total;
    }

    List<String> unscheduled() {
        List<String> result = new ArrayList<>(oversized);
        excluded.stream().filter(id -> !assignment.containsKey(id)).forEach(result::add);
        result.sort(String::compareTo);
        return result;
    }

    boolean validTrial(Map<String, Integer> trial, List<String> moved) {
        return moved.stream().allMatch(id -> suitable(courses.get(id), trial.get(id))) && ordersSatisfied(trial);
    }

    List<String> movedCourses(Map<String, Integer> trial) {
        return trial.keySet().stream().filter(id -> !trial.get(id).equals(assignment.get(id))).sorted().toList();
    }

    Trial exchangeTrial(int first, int second) {
        if (fixedSlots.contains(first) || fixedSlots.contains(second)) return new Trial("fixed", null, 0);
        Map<String, Integer> trial = new TreeMap<>(assignment);
        assignment.forEach((id, slot) -> {
            if (slot == first) trial.put(id, second);
            else if (slot == second) trial.put(id, first);
        });
        if (!validTrial(trial, movedCourses(trial))) return new Trial("invalid", null, 0);
        int total = breakdown(trial).total;
        return total >= penalty ? new Trial("worse", null, 0) : new Trial("applied", trial, total);
    }

    String verdictCounts(Map<String, Integer> tally, List<String> verdicts) {
        return String.join(" ", verdicts.stream().map(verdict -> verdict + " " + tally.get(verdict)).toList());
    }

    Map<String, Integer> tally(List<String> verdicts) {
        Map<String, Integer> result = new HashMap<>();
        verdicts.forEach(verdict -> result.put(verdict, 0));
        return result;
    }

    void exchangeSlots() {
        int round = 0, serial = 0;
        while (true) {
            round++;
            Map<String, Integer> tally = tally(EXCHANGE_VERDICTS);
            List<String> records = new ArrayList<>();
            int pairs = 0;
            for (int i = 0; i < openSlots.size(); i++)
                for (int j = i + 1; j < openSlots.size(); j++) {
                    int first = openSlots.get(i), second = openSlots.get(j);
                    pairs++;
                    Trial trial = exchangeTrial(first, second);
                    tally.merge(trial.verdict(), 1, Integer::sum);
                    if (trial.verdict().equals("applied")) {
                        records.add("EXCHANGE " + (++serial) + " " + calendar.name(first) + " "
                            + calendar.name(second) + " penalty " + penalty + " -> " + trial.total());
                        assignment = trial.assignment();
                        penalty = trial.total();
                    }
                }
            exchangeLog.add("ROUND " + round + " pairs " + pairs + " " + verdictCounts(tally, EXCHANGE_VERDICTS));
            exchangeLog.addAll(records);
            if (tally.get("applied") == 0) break;
        }
        exchanged = breakdown(assignment);
    }

    Trial swapTrial(String id, int home, int target) {
        List<String> chain = graph.kempeChain(assignment, id, home, target);
        if (chain.stream().anyMatch(calendar.fixed::containsKey)) return new Trial("fixed", null, 0);
        Map<String, Integer> trial = new TreeMap<>(assignment);
        for (String member : chain) trial.put(member, assignment.get(member) == home ? target : home);
        if (!validTrial(trial, chain)) return new Trial("invalid", null, 0);
        if (!packs(coursesAt(trial, home)) || !packs(coursesAt(trial, target))) return new Trial("rooms", null, 0);
        int total = breakdown(trial).total;
        return total >= penalty ? new Trial("worse", null, 0) : new Trial("applied", trial, total);
    }

    void swapChains() {
        int pass = 0, serial = 0;
        while (true) {
            pass++;
            Map<String, Integer> tally = tally(SWAP_VERDICTS);
            List<String> records = new ArrayList<>();
            int candidates = 0;
            List<String> movable = assignment.keySet().stream()
                .filter(id -> !calendar.fixed.containsKey(id)).sorted().toList();
            for (String id : movable) {
                int home = assignment.get(id);
                for (int target : openSlots) {
                    if (target == home) continue;
                    candidates++;
                    Trial trial = swapTrial(id, home, target);
                    tally.merge(trial.verdict(), 1, Integer::sum);
                    if (!trial.verdict().equals("applied")) continue;
                    List<String> chain = movedCourses(trial.assignment());
                    records.add("SWAP " + (++serial) + " " + id + " " + calendar.name(home) + " "
                        + calendar.name(target) + " chain " + chain.size() + " penalty " + penalty + " -> " + trial.total());
                    for (String member : chain)
                        records.add("  MOVE " + member + " " + calendar.name(assignment.get(member))
                            + " -> " + calendar.name(trial.assignment().get(member)));
                    assignment = trial.assignment();
                    penalty = trial.total();
                    break;
                }
            }
            swapLog.add("PASS " + pass + " candidates " + candidates + " " + verdictCounts(tally, SWAP_VERDICTS));
            swapLog.addAll(records);
            if (tally.get("applied") == 0) return;
        }
    }

    void assignRooms() {
        for (int slot : openSlots) {
            List<Placement> placed = Rooms.pack(rooms, coursesAt(assignment, slot).stream().map(courses::get).toList());
            slotPlacements.put(slot, placed);
            for (Placement placement : placed) placements.put(placement.course().id, placement);
        }
    }

    List<RoomGroup> roomGroups(int slot) {
        List<RoomGroup> groups = new ArrayList<>();
        for (Room room : rooms) {
            List<Placement> placed = slotPlacements.get(slot).stream().filter(p -> p.room().equals(room)).toList();
            if (!placed.isEmpty()) groups.add(new RoomGroup(room, placed));
        }
        return groups;
    }

    int invigilators(int slot) {
        return roomGroups(slot).stream().mapToInt(group -> ceilDiv(
            group.placements().stream().mapToInt(p -> p.course().size()).sum(), calendar.ratio)).sum();
    }

    int[] slotLoad(int slot) {
        List<String> ids = coursesAt(assignment, slot);
        return new int[] {ids.size(), ids.stream().mapToInt(id -> courses.get(id).size()).sum()};
    }

    List<String> assignedCourses(String student) {
        return studentCourses.get(student).stream().filter(assignment::containsKey)
            .sorted(Comparator.<String>comparingInt(assignment::get).thenComparing(Comparator.naturalOrder())).toList();
    }

    List<StudentPair> studentPairs(String student) {
        List<String> ids = assignedCourses(student);
        List<StudentPair> pairs = new ArrayList<>();
        for (int i = 0; i < ids.size(); i++)
            for (int j = i + 1; j < ids.size(); j++) {
                String low = ids.get(i), high = ids.get(j);
                int relation = calendar.relation(assignment.get(low), assignment.get(high));
                if (relation >= 0) pairs.add(new StudentPair(relation, assignment.get(low), low, assignment.get(high), high));
            }
        return pairs;
    }

    StudentPenalty studentPenalty(String student) {
        int[] counts = new int[3];
        for (StudentPair pair : studentPairs(student)) counts[pair.relation()]++;
        int total = IntStream.range(0, 3).map(i -> counts[i] * calendar.weights[i]).sum();
        return new StudentPenalty(counts, total);
    }

    List<String> timetableLines() {
        List<String> lines = new ArrayList<>();
        lines.add("TIMETABLE days " + calendar.days + " periods " + calendar.periods + " open " + openSlots.size()
            + " courses " + courses.size() + " scheduled " + assignment.size() + " unscheduled " + unscheduled().size()
            + " empty " + empty.size());
        List<String> header = new ArrayList<>();
        for (int period = 1; period <= calendar.periods; period++) header.add("P" + period);
        header.add("TOTAL");
        lines.add(Report.fixedWidthLine("DAY", header, 4, 10));
        for (int day = 1; day <= calendar.days; day++) {
            List<String> cells = new ArrayList<>();
            int dayExams = 0, dayStudents = 0;
            for (int period = 1; period <= calendar.periods; period++) {
                int slot = (day - 1) * calendar.periods + period;
                if (calendar.closed.contains(slot)) cells.add("closed");
                else {
                    int[] load = slotLoad(slot);
                    cells.add(load[0] + "/" + load[1]);
                    dayExams += load[0];
                    dayStudents += load[1];
                }
            }
            cells.add(dayExams + "/" + dayStudents);
            lines.add(Report.fixedWidthLine("D" + day, cells, 4, 10));
        }
        for (int slot : calendar.slots()) {
            String prefix = "SLOT " + slot + " " + calendar.name(slot) + " minutes " + calendar.length(slot);
            if (calendar.closed.contains(slot)) {
                lines.add(prefix + " closed");
                continue;
            }
            int[] load = slotLoad(slot);
            List<RoomGroup> groups = roomGroups(slot);
            int seats = groups.stream().mapToInt(group -> group.room().capacity()).sum();
            lines.add(prefix + " exams " + load[0] + " students " + load[1] + " rooms " + groups.size()
                + " seats " + seats + " invigilators " + invigilators(slot));
            for (Placement placement : slotPlacements.get(slot)) {
                Course course = placement.course();
                String marker = calendar.fixed.containsKey(course.id) ? " fixed" : "";
                lines.add("  " + course.id + " " + course.duration + "min students " + course.size() + " room "
                    + placement.room().id() + " seats " + placement.firstSeat() + "-" + placement.lastSeat() + marker + " " + course.name);
            }
        }
        for (Room room : rooms) {
            int used = 0, exams = 0, seated = 0;
            for (int slot : openSlots)
                for (RoomGroup group : roomGroups(slot))
                    if (group.room().equals(room)) {
                        used++;
                        exams += group.placements().size();
                        seated += group.placements().stream().mapToInt(p -> p.course().size()).sum();
                    }
            int utilization = Report.roundedPercent(seated, room.capacity() * openSlots.size());
            lines.add("ROOM " + room.id() + " capacity " + room.capacity() + " slots " + used + " exams " + exams
                + " seated " + seated + " utilization " + utilization);
        }
        int total = openSlots.stream().mapToInt(this::invigilators).sum();
        lines.add("INVIGILATORS total " + total + " ratio " + calendar.ratio);
        return lines;
    }

    List<String> roomLines() {
        List<String> lines = new ArrayList<>(List.of("slot,room,course,students,first_seat,last_seat"));
        for (int slot : openSlots)
            for (RoomGroup group : roomGroups(slot))
                for (Placement p : group.placements())
                    lines.add(calendar.name(slot) + "," + group.room().id() + "," + p.course().id + ","
                        + p.course().size() + "," + p.firstSeat() + "," + p.lastSeat());
        return lines;
    }

    List<String> penaltyLines() {
        int[] weights = calendar.weights;
        Breakdown last = breakdown(assignment);
        List<String> lines = new ArrayList<>(List.of("WEIGHTS back_to_back " + weights[0] + " same_day " + weights[1]
            + " overnight " + weights[2] + " front_load " + weights[3],
            "FRONT_LOAD courses " + frontLoad.size() + " last_slot " + calendar.name(calendar.deadline),
            "INITIAL " + initial.text()));
        lines.addAll(exchangeLog);
        lines.add("EXCHANGED " + exchanged.text());
        lines.addAll(swapLog);
        lines.add("FINAL " + last.text());
        lines.add("SAVED " + (initial.total - last.total));
        int[][] daily = new int[calendar.days + 1][3];
        for (PenaltyPair pair : penaltyPairs(assignment)) {
            int day = calendar.dayOf(Math.min(assignment.get(pair.first()), assignment.get(pair.second())));
            daily[day][pair.relation()] += pair.shared();
        }
        for (int day = 1; day <= calendar.days; day++)
            lines.add("DAY D" + day + " back_to_back " + daily[day][0] + " same_day " + daily[day][1] + " overnight " + daily[day][2]);
        for (String id : lateCourses(assignment))
            lines.add("LATE " + id + " " + calendar.name(assignment.get(id)) + " students " + courses.get(id).size());
        Map<String, Integer> contribution = contributions();
        List<String> ranked = contribution.keySet().stream().sorted(Comparator.<String>comparingInt(contribution::get)
            .reversed().thenComparing(Comparator.naturalOrder())).limit(10).toList();
        for (String id : ranked)
            if (contribution.get(id) > 0)
                lines.add("COURSE " + id + " " + calendar.name(assignment.get(id)) + " penalty " + contribution.get(id));
        lines.addAll(studentStatistics());
        return lines;
    }

    List<String> studentStatistics() {
        Map<Integer, Integer> histogram = new TreeMap<>(), gaps = new TreeMap<>(), dayLoads = new TreeMap<>();
        Map<String, StudentPenalty> statistics = new TreeMap<>();
        for (String student : studentCourses.keySet()) {
            StudentPenalty result = studentPenalty(student);
            statistics.put(student, result);
            histogram.merge(result.total(), 1, Integer::sum);
            List<Integer> slots = assignedCourses(student).stream().map(assignment::get).toList();
            for (int i = 1; i < slots.size(); i++) gaps.merge(slots.get(i) - slots.get(i - 1), 1, Integer::sum);
            if (!slots.isEmpty()) {
                Map<Integer, Integer> perDay = new HashMap<>();
                for (int slot : slots) perDay.merge(calendar.dayOf(slot), 1, Integer::sum);
                int maximum = perDay.values().stream().mapToInt(Integer::intValue).max().orElseThrow();
                dayLoads.merge(maximum, 1, Integer::sum);
            }
        }
        List<String> lines = new ArrayList<>();
        histogram.forEach((value, count) -> lines.add("HISTOGRAM " + value + " " + count));
        gaps.forEach((value, count) -> lines.add("GAP " + value + " " + count));
        dayLoads.forEach((value, count) -> lines.add("DAYLOAD " + value + " " + count));
        List<String> ranking = statistics.keySet().stream().sorted(Comparator.<String>comparingInt(student -> statistics.get(student).total())
            .reversed().thenComparing(Comparator.naturalOrder())).limit(5).toList();
        for (String student : ranking) {
            StudentPenalty result = statistics.get(student);
            if (result.total() > 0)
                lines.add("WORST " + student + " penalty " + result.total() + " back_to_back " + result.counts()[0]
                    + " same_day " + result.counts()[1] + " overnight " + result.counts()[2]);
        }
        return lines;
    }

    List<String> scheduleLines(List<String> queries) {
        List<String> lines = new ArrayList<>();
        for (String student : queries) {
            if (!studentCourses.containsKey(student)) {
                lines.add("STUDENT " + student + " not found");
                continue;
            }
            List<String> ids = studentCourses.get(student), assigned = assignedCourses(student);
            lines.add("STUDENT " + student + " exams " + ids.size() + " scheduled " + assigned.size()
                + " penalty " + studentPenalty(student).total());
            for (String id : assigned) {
                Placement placement = placements.get(id);
                Course course = placement.course();
                int seat = placement.firstSeat() + course.students.indexOf(student);
                lines.add("  " + calendar.name(assignment.get(id)) + " " + id + " room " + placement.room().id()
                    + " seat " + seat + " " + course.name);
            }
            for (String id : ids)
                if (!assignment.containsKey(id)) lines.add("  UNSCHEDULED " + id + " " + courses.get(id).name);
            for (StudentPair pair : studentPairs(student))
                lines.add("  " + RELATIONS.get(pair.relation()).toUpperCase(java.util.Locale.ROOT) + " "
                    + calendar.name(pair.lowSlot()) + " " + pair.lowCourse() + " "
                    + calendar.name(pair.highSlot()) + " " + pair.highCourse());
            for (int slot : calendar.unavailable.getOrDefault(student, Set.of()).stream().sorted().toList())
                lines.add("  UNAVAILABLE " + calendar.name(slot));
        }
        return lines;
    }

    List<String> statusLines() {
        Map<String, Integer> contribution = contributions();
        List<String> lines = new ArrayList<>(List.of("course,status,slot,students,minutes,degree,penalty"));
        for (String id : courses.keySet().stream().sorted().toList()) {
            Course course = courses.get(id);
            String status = calendar.fixed.containsKey(id) ? "fixed" : assignment.containsKey(id) ? "scheduled"
                : oversized.contains(id) ? "too_large" : empty.contains(id) ? "empty" : "no_slot";
            String slot = assignment.containsKey(id) ? calendar.name(assignment.get(id)) : "-";
            lines.add(id + "," + status + "," + slot + "," + course.size() + "," + course.duration + ","
                + graph.degree(id) + "," + contribution.getOrDefault(id, 0));
        }
        return lines;
    }

    List<String> graphLines() {
        int vertices = graph.vertices.size(), edgeCount = edges.size();
        int shared = edges.stream().mapToInt(Edge::shared).sum();
        int density = vertices >= 2 ? 2000 * edgeCount / (vertices * (vertices - 1)) : 0;
        List<String> lines = new ArrayList<>(List.of("GRAPH courses " + vertices + " edges " + edgeCount
            + " shared " + shared + " density " + density));
        for (String id : byDegree(graph.vertices).stream().limit(5).toList())
            lines.add("DEGREE " + id + " neighbours " + graph.degree(id) + " shared " + graph.sharedTotal(id)
                + " students " + courses.get(id).size());
        List<List<String>> components = graph.components();
        lines.add("COMPONENTS " + components.size());
        for (int i = 0; i < components.size(); i++) {
            List<String> component = components.get(i);
            lines.add("COMPONENT " + (i + 1) + " size " + component.size() + " first " + component.getFirst());
        }
        List<String> clique = graph.greedyClique(schedulable);
        lines.add("CLIQUE size " + clique.size() + (clique.isEmpty() ? "" : " " + String.join(" ", clique)));
        return lines;
    }

    List<String> capacityLines() {
        List<Integer> loads = studentCourses.values().stream().map(List::size).toList();
        int maximum = loads.stream().mapToInt(Integer::intValue).max().orElseThrow();
        long count = loads.stream().filter(load -> load == maximum).count();
        int demand = schedulable.stream().mapToInt(id -> courses.get(id).size()).sum();
        int capacity = rooms.stream().mapToInt(Room::capacity).sum();
        List<String> lines = new ArrayList<>(List.of("LOAD max_exams " + maximum + " students " + count,
            "SEATS demand " + demand + " capacity " + capacity + " min_slots " + ceilDiv(demand, capacity),
            "HEURISTIC largest_degree slots " + Coloring.greedyNumbering(byDegree(schedulable), graph),
            "HEURISTIC largest_enrolment slots " + Coloring.greedyNumbering(bySize(schedulable), graph)));
        List<String> table = bySize(graph.vertices).stream().limit(8).toList();
        lines.add(Report.fixedWidthLine("MATRIX", table, 9, 9));
        for (String row : table) {
            List<String> cells = table.stream().map(column -> row.equals(column) ? "-"
                : Integer.toString(graph.neighbours(row).getOrDefault(column, 0))).toList();
            lines.add(Report.fixedWidthLine(row, cells, 9, 9));
        }
        return lines;
    }

    List<String> reportLines() {
        int enrolments = studentCourses.values().stream().mapToInt(List::size).sum();
        List<String> lines = new ArrayList<>(List.of("INPUT courses " + courses.size() + " enrolments " + enrolments
            + " rooms " + rooms.size() + " students " + studentCourses.size() + " errors " + errors.size()));
        for (String error : errors) lines.add("ERROR " + error);
        lines.addAll(graphLines());
        lines.addAll(capacityLines());
        for (String id : empty) lines.add("EMPTY " + id);
        for (String id : oversized)
            lines.add("TOO_LARGE " + id + " students " + courses.get(id).size() + " largest_room " + largestRoom);
        for (int slot : calendar.closed) lines.add("CLOSED " + calendar.name(slot));
        for (String id : calendar.fixed.keySet()) lines.add("FIXED " + id + " " + calendar.name(calendar.fixed.get(id)));
        for (OrderConstraint order : calendar.orders) lines.add("AFTER " + order.later() + " " + order.earlier());
        for (int i = 0; i < attempts.size(); i++) {
            AttemptRecord attempt = attempts.get(i);
            String result = attempt.failedCourse() == null ? "success" : "failed " + attempt.failedCourse();
            lines.add("ATTEMPT " + (i + 1) + " courses " + attempt.size() + " backtracks " + attempt.deadEnds() + " " + result);
        }
        for (int i = 0; i < assignmentOrder.size(); i++) {
            AssignmentRecord chosen = assignmentOrder.get(i);
            lines.add("ORDER " + (i + 1) + " " + chosen.course() + " " + calendar.name(chosen.slot())
                + " saturation " + chosen.saturation() + " degree " + graph.degree(chosen.course()));
        }
        for (Insertion insertion : insertions)
            lines.add("INSERTED " + insertion.course() + " " + calendar.name(insertion.slot()) + " penalty " + insertion.increase());
        for (String id : unscheduled()) {
            String reason = oversized.contains(id) ? "too_large" : "no_slot";
            lines.add("UNSCHEDULED " + id + " reason " + reason + " students " + courses.get(id).size());
            List<String> recorded = reasons.getOrDefault(id, List.of());
            for (int i = 0; i < recorded.size(); i++) lines.add("  " + calendar.name(i + 1) + " " + recorded.get(i));
        }
        lines.add("SUMMARY scheduled " + assignment.size() + " unscheduled " + unscheduled().size()
            + " slots_used " + new HashSet<>(assignment.values()).size() + " penalty " + penalty);
        return lines;
    }
}

public final class Main {
    public static void main(String[] args) throws IOException {
        List<String> errors = new ArrayList<>();
        Map<String, Course> courses = Enrolment.loadCourses("input/courses.csv", errors);
        Map<String, List<String>> students = Enrolment.loadEnrolments("input/enrolments.csv", courses, errors);
        List<Room> rooms = Rooms.load("input/rooms.csv", errors);
        List<String> calendarLines = Files.readAllLines(Path.of("input/calendar.txt"), StandardCharsets.US_ASCII);
        Scheduler scheduler = new Scheduler(courses, students, rooms, new ExamCalendar(calendarLines), errors);
        scheduler.validateCalendar(calendarLines);
        scheduler.buildTimetable();
        scheduler.insertExcluded();
        scheduler.exchangeSlots();
        scheduler.swapChains();
        scheduler.assignRooms();
        List<String> queries = Files.readAllLines(Path.of("input/queries.txt"), StandardCharsets.US_ASCII);
        Report.writeFiles("output", Map.of("timetable.txt", scheduler.timetableLines(),
            "rooms.csv", scheduler.roomLines(), "penalties.txt", scheduler.penaltyLines(),
            "student_schedules.txt", scheduler.scheduleLines(queries),
            "course_status.csv", scheduler.statusLines(), "report.txt", scheduler.reportLines()));
    }
}
