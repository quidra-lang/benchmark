#include "timetable.hpp"

static int ceilDiv(int a, int b) { return (a + b - 1) / b; }
static Lines words(const std::string& line) {
    std::istringstream stream(line); Lines result; std::string word;
    while (stream >> word) result.push_back(word);
    return result;
}
struct Calendar {
    int days, periods, slots, limit, frontCount, deadline, ratio;
    Indices lengths, weights, open;
    std::set<int> closed, fixedSlots;
    std::vector<std::pair<int, int>> orders;
    explicit Calendar(const Lines& lines) {
        std::array<Indices, 6> settings;
        for (int i = 0; i < 6; ++i) { Lines fields = words(lines[i]); for (std::size_t j = 1; j < fields.size(); ++j) settings[i].push_back(std::stoi(fields[j])); }
        days = settings[0][0]; lengths = settings[1]; periods = static_cast<int>(lengths.size()); slots = days * periods;
        limit = settings[2][0]; weights = settings[3]; frontCount = settings[4][0]; deadline = settings[4][1]; ratio = settings[5][0];
    }
    int day(int slot) const { return (slot - 1) / periods + 1; }
    int length(int slot) const { return lengths[(slot - 1) % periods]; }
    std::string name(int slot) const { return text('D', day(slot), 'P', (slot - 1) % periods + 1); }
    int slotAt(const std::string& dayText, const std::string& periodText) const {
        int d = std::stoi(dayText), p = std::stoi(periodText);
        return d >= 1 && d <= days && p >= 1 && p <= periods ? (d - 1) * periods + p : 0;
    }
    int relation(int first, int second) const {
        int low = std::min(first, second), high = std::max(first, second);
        if (day(low) == day(high)) { if (high - low == 1) return 0; if (high - low >= 2) return 1; }
        else if (high - low == 1) return 2;
        return -1;
    }
};
std::string Breakdown::str() const { return text("back_to_back ", counts[0], " same_day ", counts[1], " overnight ", counts[2], " front_load ", late, " penalty ", total); }

class Scheduler {
    std::vector<Course> courses;
    std::vector<Student> students;
    std::vector<Room> rooms;
    Calendar calendar;
    Lines errors;
    ConflictGraph graph;
    int largestRoom, penalty = 0;
    Indices empty, oversized, schedulable, frontLoad;
    Assignment fixed, assignment;
    std::set<int> excluded;
    std::vector<AttemptRecord> attempts;
    std::vector<Choice> choices;
    std::vector<Insertion> insertions;
    std::map<int, Lines> reasons;
    Breakdown initial, exchanged, final;
    Lines exchangeLog, swapLog;
    std::vector<std::vector<Placement>> packed;
    std::vector<Placement> placements;
    Indices contributions;
    std::vector<StudentStats> statistics;
public:
    Scheduler(std::vector<Course> courseData, std::vector<Student> studentData, std::vector<Room> roomData, const Lines& calendarLines, Lines errorData)
        : courses(std::move(courseData)), students(std::move(studentData)), rooms(std::move(roomData)), calendar(calendarLines), errors(std::move(errorData)), graph(courses, students),
          largestRoom(rooms.back().capacity), fixed(courses.size()), assignment(courses.size()), packed(calendar.slots + 1), placements(courses.size()), contributions(courses.size()), statistics(students.size()) {
        for (int c = 0; c < static_cast<int>(courses.size()); ++c) {
            if (!courses[c].size()) empty.push_back(c);
            else if (courses[c].size() > largestRoom) oversized.push_back(c);
            else schedulable.push_back(c);
        }
        frontLoad = packingOrder(courses, schedulable);
        frontLoad.resize(std::min(frontLoad.size(), static_cast<std::size_t>(calendar.frontCount)));
        validateCalendar(calendarLines);
    }
    bool isSchedulable(int c) const { return courses[c].size() > 0 && courses[c].size() <= largestRoom; }
    Indices byDegree(Indices group) const {
        std::sort(group.begin(), group.end(), [&](int a, int b) { return graph.degrees[a] != graph.degrees[b] ? graph.degrees[a] > graph.degrees[b] : a < b; }); return group;
    }
    Indices coursesAt(const Assignment& current, int slot) const {
        Indices result; for (int c = 0; c < static_cast<int>(courses.size()); ++c) if (current[c] == slot) result.push_back(c); return result;
    }
    int blockedStudent(int c, int slot) const {
        for (int student : courses[c].students) if (students[student].unavailable.count(slot)) return student; return -1;
    }
    bool suitable(int c, int slot) const { return calendar.length(slot) >= courses[c].duration && blockedStudent(c, slot) < 0; }
    int orderConflict(int c, int slot, const Assignment& current) const {
        int result = -1;
        for (const std::pair<int, int>& order : calendar.orders) {
            int a = order.first, b = order.second, other = -1;
            if (a == c && current[b] && slot <= current[b]) other = b;
            else if (b == c && current[a] && slot >= current[a]) other = a;
            if (other >= 0 && (result < 0 || other < result)) result = other;
        }
        return result;
    }
    bool ordersSatisfied(const Assignment& current) const {
        for (const std::pair<int, int>& order : calendar.orders)
            if (current[order.first] && current[order.second] && current[order.first] <= current[order.second]) return false;
        return true;
    }
    Indices candidateSlots(int c, const Assignment& current) const {
        Indices result;
        for (int slot : calendar.open) {
            if (!suitable(c, slot) || orderConflict(c, slot, current) >= 0) continue;
            bool clash = false; for (int n : graph.vertices) if (graph.shared[c][n] && current[n] == slot) clash = true;
            if (clash) continue;
            Indices group = coursesAt(current, slot); group.push_back(c);
            if (pack(rooms, courses, std::move(group))) result.push_back(slot);
        }
        return result;
    }
    std::optional<std::string> acceptClosed(const Lines& fields) {
        int slot = calendar.slotAt(fields[1], fields[2]);
        if (!slot) return text("slot ", fields[1], ' ', fields[2], " outside calendar");
        if (!calendar.closed.insert(slot).second) return text("duplicate closed ", calendar.name(slot));
        return std::nullopt;
    }
    std::optional<std::string> acceptUnavailable(const Lines& fields) {
        int student = findStudent(students, fields[1]);
        if (student < 0) return "unknown student " + fields[1];
        int slot = calendar.slotAt(fields[2], fields[3]);
        if (!slot) return text("slot ", fields[2], ' ', fields[3], " outside calendar");
        if (!students[student].unavailable.insert(slot).second) return text("duplicate unavailable ", fields[1], ' ', calendar.name(slot));
        return std::nullopt;
    }
    std::optional<std::string> acceptFixed(const Lines& fields) {
        const std::string& id = fields[1]; int c = findCourse(courses, id);
        if (c < 0) return "unknown course " + id;
        if (!isSchedulable(c)) return text("course ", id, " not schedulable");
        int slot = calendar.slotAt(fields[2], fields[3]);
        if (!slot) return text("slot ", fields[2], ' ', fields[3], " outside calendar");
        if (calendar.closed.count(slot)) return text("slot ", calendar.name(slot), " closed");
        if (!suitable(c, slot)) return text("slot ", calendar.name(slot), " unsuitable for ", id);
        if (fixed[c]) return "duplicate fixed " + id;
        Indices group = coursesAt(fixed, slot);
        for (int other : group) if (graph.shared[c][other]) return text("conflict ", id, ' ', courses[other].id);
        group.push_back(c);
        if (!pack(rooms, courses, std::move(group))) return "rooms full " + calendar.name(slot);
        fixed[c] = slot; return std::nullopt;
    }
    std::optional<std::string> acceptAfter(const Lines& fields) {
        const std::string& later = fields[1]; const std::string& earlier = fields[2];
        int a = findCourse(courses, later), b = findCourse(courses, earlier);
        if (a < 0) return "unknown course " + later;
        if (b < 0) return "unknown course " + earlier;
        if (!isSchedulable(a)) return text("course ", later, " not schedulable");
        if (!isSchedulable(b)) return text("course ", earlier, " not schedulable");
        if (a == b) return text("bad order ", later, ' ', earlier);
        if (std::find(calendar.orders.begin(), calendar.orders.end(), std::make_pair(a, b)) != calendar.orders.end()) return text("duplicate order ", later, ' ', earlier);
        if (reachable(calendar.orders, b, a)) return text("cycle ", later, ' ', earlier);
        if (fixed[a] && fixed[b] && fixed[a] <= fixed[b]) return text("fixed order ", later, ' ', earlier);
        calendar.orders.emplace_back(a, b); return std::nullopt;
    }
    void validateCalendar(const Lines& lines) {
        for (int i = 6; i < static_cast<int>(lines.size()); ++i) {
            Lines fields = words(lines[i]); std::optional<std::string> message;
            if (fields[0] == "closed") message = acceptClosed(fields);
            else if (fields[0] == "unavailable") message = acceptUnavailable(fields);
            else if (fields[0] == "fixed") message = acceptFixed(fields);
            else message = acceptAfter(fields);
            if (message) add(errors, "calendar.txt line ", i + 1, ": ", *message);
        }
        for (int slot = 1; slot <= calendar.slots; ++slot) if (!calendar.closed.count(slot)) calendar.open.push_back(slot);
        for (int slot : fixed) if (slot) calendar.fixedSlots.insert(slot);
    }
    void buildTimetable() {
        for (;;) {
            Indices pending; for (int c : schedulable) if (!fixed[c] && !excluded.count(c)) pending.push_back(c);
            assignment = fixed;
            Attempt attempt(graph, pending, calendar.limit, [&](int c, const Assignment& current) { return candidateSlots(c, current); });
            bool success = attempt.search(assignment);
            attempts.push_back({static_cast<int>(pending.size()), attempt.deadEnds, success ? -1 : attempt.deadEndCourse});
            if (success) { choices = std::move(attempt.choices); break; }
            excluded.insert(attempt.deadEndCourse);
        }
    }
    Breakdown breakdown(const Assignment& current) const {
        Breakdown result;
        for (int a : graph.vertices) if (current[a]) for (int b : graph.vertices) if (a < b && current[b] && graph.shared[a][b]) {
            int kind = calendar.relation(current[a], current[b]); if (kind >= 0) result.counts[kind] += graph.shared[a][b];
        }
        for (int c : frontLoad) if (current[c] > calendar.deadline) ++result.late;
        result.total = result.late * calendar.weights[3];
        for (int kind = 0; kind < 3; ++kind) result.total += result.counts[kind] * calendar.weights[kind];
        return result;
    }
    std::string blockingReason(int c, int slot) const {
        if (calendar.closed.count(slot)) return "closed";
        if (calendar.length(slot) < courses[c].duration) return "too_short";
        int student = blockedStudent(c, slot); if (student >= 0) return "unavailable " + students[student].id;
        int clash = -1;
        for (int n : graph.vertices) if (assignment[n] == slot && graph.shared[c][n] && (clash < 0 || graph.shared[c][n] > graph.shared[c][clash])) clash = n;
        if (clash >= 0) return text("conflict ", courses[clash].id, " shared ", graph.shared[c][clash]);
        int other = orderConflict(c, slot, assignment); if (other >= 0) return "order " + courses[other].id;
        return "rooms";
    }
    void insertExcluded() {
        for (int c : excluded) {
            Indices candidates = candidateSlots(c, assignment);
            if (candidates.empty()) { for (int slot = 1; slot <= calendar.slots; ++slot) reasons[c].push_back(blockingReason(c, slot)); continue; }
            int before = breakdown(assignment).total, bestSlot = 0, bestTotal = 0;
            for (int slot : candidates) {
                Assignment trial = assignment; trial[c] = slot; int total = breakdown(trial).total;
                if (!bestSlot || total < bestTotal) { bestSlot = slot; bestTotal = total; }
            }
            assignment[c] = bestSlot; insertions.push_back({c, bestSlot, bestTotal - before});
        }
        initial = breakdown(assignment); penalty = initial.total;
    }
    bool validTrial(const Assignment& trial) const {
        for (int c = 0; c < static_cast<int>(courses.size()); ++c) if (trial[c] != assignment[c] && !suitable(c, trial[c])) return false;
        return ordersSatisfied(trial);
    }
    void exchangeSlots() {
        int round = 0, serial = 0;
        for (;;) {
            std::array<int, 4> tally{}; int pairs = 0; Lines records; ++round;
            for (int home : calendar.open) for (int target : calendar.open) if (target > home) {
                ++pairs;
                if (calendar.fixedSlots.count(home) || calendar.fixedSlots.count(target)) { ++tally[0]; continue; }
                Assignment trial = assignment;
                for (int& slot : trial) { if (slot == home) slot = target; else if (slot == target) slot = home; }
                if (!validTrial(trial)) { ++tally[1]; continue; }
                int total = breakdown(trial).total;
                if (total >= penalty) { ++tally[2]; continue; }
                ++tally[3]; add(records, "EXCHANGE ", ++serial, ' ', calendar.name(home), ' ', calendar.name(target), " penalty ", penalty, " -> ", total);
                assignment = std::move(trial); penalty = total;
            }
            add(exchangeLog, "ROUND ", round, " pairs ", pairs, " fixed ", tally[0], " invalid ", tally[1], " worse ", tally[2], " applied ", tally[3]);
            exchangeLog.insert(exchangeLog.end(), records.begin(), records.end());
            if (!tally[3]) break;
        }
        exchanged = breakdown(assignment);
    }
    void swapChains() {
        int pass = 0, serial = 0;
        for (;;) {
            std::array<int, 5> tally{}; int candidates = 0; Lines records; ++pass;
            Indices movable; for (int c = 0; c < static_cast<int>(courses.size()); ++c) if (assignment[c] && !fixed[c]) movable.push_back(c);
            for (int c : movable) {
                int home = assignment[c];
                for (int target : calendar.open) {
                    if (target == home) continue;
                    ++candidates; Indices chain = graph.kempeChain(assignment, c, home, target);
                    if (std::any_of(chain.begin(), chain.end(), [&](int member) { return fixed[member] != 0; })) { ++tally[0]; continue; }
                    Assignment trial = assignment; for (int member : chain) trial[member] = assignment[member] == home ? target : home;
                    if (!validTrial(trial)) { ++tally[1]; continue; }
                    if (!pack(rooms, courses, coursesAt(trial, home)) || !pack(rooms, courses, coursesAt(trial, target))) { ++tally[2]; continue; }
                    int total = breakdown(trial).total;
                    if (total >= penalty) { ++tally[3]; continue; }
                    ++tally[4]; add(records, "SWAP ", ++serial, ' ', courses[c].id, ' ', calendar.name(home), ' ', calendar.name(target), " chain ", chain.size(), " penalty ", penalty, " -> ", total);
                    for (int member : chain) add(records, "  MOVE ", courses[member].id, ' ', calendar.name(assignment[member]), " -> ", calendar.name(trial[member]));
                    assignment = std::move(trial); penalty = total; break;
                }
            }
            add(swapLog, "PASS ", pass, " candidates ", candidates, " fixed ", tally[0], " invalid ", tally[1], " rooms ", tally[2], " worse ", tally[3], " applied ", tally[4]);
            swapLog.insert(swapLog.end(), records.begin(), records.end());
            if (!tally[4]) break;
        }
        final = breakdown(assignment);
    }
    void assignRooms() {
        for (int slot : calendar.open) {
            packed[slot] = pack(rooms, courses, coursesAt(assignment, slot)).value();
            for (const Placement& p : packed[slot]) placements[p.course] = p;
        }
    }
    void computeStatistics() {
        for (int a : graph.vertices) if (assignment[a]) for (int b : graph.vertices) if (a < b && assignment[b] && graph.shared[a][b]) {
            int kind = calendar.relation(assignment[a], assignment[b]);
            if (kind >= 0) { int value = calendar.weights[kind] * graph.shared[a][b]; contributions[a] += value; contributions[b] += value; }
        }
        for (int c : frontLoad) if (assignment[c] > calendar.deadline) contributions[c] += calendar.weights[3];
        for (int student = 0; student < static_cast<int>(students.size()); ++student) {
            StudentStats& stats = statistics[student];
            for (int c : students[student].courses) if (assignment[c]) stats.assigned.push_back(c);
            std::sort(stats.assigned.begin(), stats.assigned.end(), [&](int a, int b) { return assignment[a] < assignment[b]; });
            for (std::size_t i = 0; i < stats.assigned.size(); ++i) for (std::size_t j = i + 1; j < stats.assigned.size(); ++j) {
                int kind = calendar.relation(assignment[stats.assigned[i]], assignment[stats.assigned[j]]); if (kind >= 0) ++stats.counts[kind];
            }
            for (int kind = 0; kind < 3; ++kind) stats.total += stats.counts[kind] * calendar.weights[kind];
        }
    }
    int assignedCount() const { return static_cast<int>(std::count_if(assignment.begin(), assignment.end(), [](int slot) { return slot != 0; })); }
    Indices unscheduled() const { Indices result; for (int c = 0; c < static_cast<int>(courses.size()); ++c) if (courses[c].size() && !assignment[c]) result.push_back(c); return result; }
    std::pair<int, int> slotLoad(int slot) const {
        int count = 0; for (const Placement& p : packed[slot]) count += courses[p.course].size(); return {static_cast<int>(packed[slot].size()), count};
    }
    std::vector<std::pair<int, Indices>> roomGroups(int slot) const {
        std::vector<std::pair<int, Indices>> result;
        for (int r = 0; r < static_cast<int>(rooms.size()); ++r) {
            Indices group; for (int i = 0; i < static_cast<int>(packed[slot].size()); ++i) if (packed[slot][i].room == r) group.push_back(i);
            if (!group.empty()) result.emplace_back(r, std::move(group));
        }
        return result;
    }
    int invigilators(int slot) const {
        int total = 0;
        for (const std::pair<int, Indices>& group : roomGroups(slot)) {
            int count = 0; for (int i : group.second) count += courses[packed[slot][i].course].size(); total += ceilDiv(count, calendar.ratio);
        }
        return total;
    }
    Lines timetableLines() const {
        Lines lines;
        add(lines, "TIMETABLE days ", calendar.days, " periods ", calendar.periods, " open ", calendar.open.size(), " courses ", courses.size(), " scheduled ", assignedCount(), " unscheduled ", unscheduled().size(), " empty ", empty.size());
        Lines header; for (int p = 1; p <= calendar.periods; ++p) header.push_back(text('P', p)); header.push_back("TOTAL");
        lines.push_back(fixedWidth("DAY", header, 4, 10));
        for (int day = 1; day <= calendar.days; ++day) {
            Lines cells; int exams = 0, count = 0;
            for (int p = 1; p <= calendar.periods; ++p) {
                int slot = (day - 1) * calendar.periods + p;
                if (calendar.closed.count(slot)) { cells.push_back("closed"); continue; }
                std::pair<int, int> load = slotLoad(slot); cells.push_back(text(load.first, '/', load.second)); exams += load.first; count += load.second;
            }
            cells.push_back(text(exams, '/', count)); lines.push_back(fixedWidth(text('D', day), cells, 4, 10));
        }
        int totalInvigilators = 0;
        for (int slot = 1; slot <= calendar.slots; ++slot) {
            std::string prefix = text("SLOT ", slot, ' ', calendar.name(slot), " minutes ", calendar.length(slot));
            if (calendar.closed.count(slot)) { lines.push_back(prefix + " closed"); continue; }
            std::pair<int, int> load = slotLoad(slot); std::vector<std::pair<int, Indices>> groups = roomGroups(slot); int seats = 0;
            for (const std::pair<int, Indices>& group : groups) seats += rooms[group.first].capacity;
            int supervisors = invigilators(slot); totalInvigilators += supervisors;
            add(lines, prefix, " exams ", load.first, " students ", load.second, " rooms ", groups.size(), " seats ", seats, " invigilators ", supervisors);
            for (const Placement& p : packed[slot]) {
                const Course& course = courses[p.course];
                add(lines, "  ", course.id, ' ', course.duration, "min students ", course.size(), " room ", rooms[p.room].id, " seats ", p.first, '-', p.last, fixed[p.course] ? " fixed" : "", ' ', course.name);
            }
        }
        for (int r = 0; r < static_cast<int>(rooms.size()); ++r) {
            int slots = 0, exams = 0, seated = 0;
            for (int slot : calendar.open) {
                bool used = false;
                for (const Placement& p : packed[slot]) if (p.room == r) { used = true; ++exams; seated += courses[p.course].size(); }
                if (used) ++slots;
            }
            add(lines, "ROOM ", rooms[r].id, " capacity ", rooms[r].capacity, " slots ", slots, " exams ", exams, " seated ", seated, " utilization ", roundedPercent(seated, rooms[r].capacity * static_cast<int>(calendar.open.size())));
        }
        add(lines, "INVIGILATORS total ", totalInvigilators, " ratio ", calendar.ratio); return lines;
    }
    Lines roomLines() const {
        Lines lines{"slot,room,course,students,first_seat,last_seat"};
        for (int slot : calendar.open) for (const std::pair<int, Indices>& group : roomGroups(slot)) for (int index : group.second) {
            const Placement& p = packed[slot][index];
            add(lines, calendar.name(slot), ',', rooms[p.room].id, ',', courses[p.course].id, ',', courses[p.course].size(), ',', p.first, ',', p.last);
        }
        return lines;
    }
    void studentStatistics(Lines& lines) const {
        std::map<int, int> histogram, gaps, dayLoads; Indices ranking;
        for (int student = 0; student < static_cast<int>(students.size()); ++student) {
            const StudentStats& stats = statistics[student]; ++histogram[stats.total]; ranking.push_back(student); std::map<int, int> perDay;
            for (std::size_t i = 0; i < stats.assigned.size(); ++i) {
                int slot = assignment[stats.assigned[i]]; ++perDay[calendar.day(slot)]; if (i) ++gaps[slot - assignment[stats.assigned[i - 1]]];
            }
            if (!perDay.empty()) { int maximum = 0; for (const std::pair<const int, int>& entry : perDay) maximum = std::max(maximum, entry.second); ++dayLoads[maximum]; }
        }
        for (const std::pair<const int, int>& entry : histogram) add(lines, "HISTOGRAM ", entry.first, ' ', entry.second);
        for (const std::pair<const int, int>& entry : gaps) add(lines, "GAP ", entry.first, ' ', entry.second);
        for (const std::pair<const int, int>& entry : dayLoads) add(lines, "DAYLOAD ", entry.first, ' ', entry.second);
        std::sort(ranking.begin(), ranking.end(), [&](int a, int b) { return statistics[a].total != statistics[b].total ? statistics[a].total > statistics[b].total : a < b; });
        for (std::size_t i = 0; i < std::min<std::size_t>(5, ranking.size()); ++i) {
            int student = ranking[i]; const StudentStats& stats = statistics[student];
            if (stats.total) add(lines, "WORST ", students[student].id, " penalty ", stats.total, " back_to_back ", stats.counts[0], " same_day ", stats.counts[1], " overnight ", stats.counts[2]);
        }
    }
    Lines penaltyLines() const {
        Lines lines;
        add(lines, "WEIGHTS back_to_back ", calendar.weights[0], " same_day ", calendar.weights[1], " overnight ", calendar.weights[2], " front_load ", calendar.weights[3]);
        add(lines, "FRONT_LOAD courses ", frontLoad.size(), " last_slot ", calendar.name(calendar.deadline));
        add(lines, "INITIAL ", initial.str()); lines.insert(lines.end(), exchangeLog.begin(), exchangeLog.end());
        add(lines, "EXCHANGED ", exchanged.str()); lines.insert(lines.end(), swapLog.begin(), swapLog.end());
        add(lines, "FINAL ", final.str()); add(lines, "SAVED ", initial.total - final.total);
        std::vector<std::array<int, 3>> daily(calendar.days + 1);
        for (int a : graph.vertices) if (assignment[a]) for (int b : graph.vertices) if (a < b && assignment[b] && graph.shared[a][b]) {
            int kind = calendar.relation(assignment[a], assignment[b]); if (kind >= 0) daily[calendar.day(std::min(assignment[a], assignment[b]))][kind] += graph.shared[a][b];
        }
        for (int day = 1; day <= calendar.days; ++day) add(lines, "DAY D", day, " back_to_back ", daily[day][0], " same_day ", daily[day][1], " overnight ", daily[day][2]);
        for (int c : frontLoad) if (assignment[c] > calendar.deadline) add(lines, "LATE ", courses[c].id, ' ', calendar.name(assignment[c]), " students ", courses[c].size());
        Indices ranked; for (int c = 0; c < static_cast<int>(courses.size()); ++c) if (assignment[c]) ranked.push_back(c);
        std::sort(ranked.begin(), ranked.end(), [&](int a, int b) { return contributions[a] != contributions[b] ? contributions[a] > contributions[b] : a < b; });
        for (std::size_t i = 0; i < std::min<std::size_t>(10, ranked.size()); ++i) { int c = ranked[i]; if (contributions[c]) add(lines, "COURSE ", courses[c].id, ' ', calendar.name(assignment[c]), " penalty ", contributions[c]); }
        studentStatistics(lines); return lines;
    }
    Lines scheduleLines(const Lines& queries) const {
        const std::array<std::string, 3> classes{"BACK_TO_BACK", "SAME_DAY", "OVERNIGHT"}; Lines lines;
        for (const std::string& query : queries) {
            int student = findStudent(students, query);
            if (student < 0) { add(lines, "STUDENT ", query, " not found"); continue; }
            const Student& record = students[student]; const StudentStats& stats = statistics[student];
            add(lines, "STUDENT ", query, " exams ", record.courses.size(), " scheduled ", stats.assigned.size(), " penalty ", stats.total);
            for (int c : stats.assigned) {
                const Course& course = courses[c]; const Placement& p = placements[c];
                int seat = p.first + static_cast<int>(std::find(course.students.begin(), course.students.end(), student) - course.students.begin());
                add(lines, "  ", calendar.name(assignment[c]), ' ', course.id, " room ", rooms[p.room].id, " seat ", seat, ' ', course.name);
            }
            for (int c : record.courses) if (!assignment[c]) add(lines, "  UNSCHEDULED ", courses[c].id, ' ', courses[c].name);
            for (std::size_t i = 0; i < stats.assigned.size(); ++i) for (std::size_t j = i + 1; j < stats.assigned.size(); ++j) {
                int a = stats.assigned[i], b = stats.assigned[j], kind = calendar.relation(assignment[a], assignment[b]);
                if (kind >= 0) add(lines, "  ", classes[kind], ' ', calendar.name(assignment[a]), ' ', courses[a].id, ' ', calendar.name(assignment[b]), ' ', courses[b].id);
            }
            for (int slot : record.unavailable) add(lines, "  UNAVAILABLE ", calendar.name(slot));
        }
        return lines;
    }
    Lines statusLines() const {
        Lines lines{"course,status,slot,students,minutes,degree,penalty"};
        for (int c = 0; c < static_cast<int>(courses.size()); ++c) {
            const Course& course = courses[c];
            std::string status = fixed[c] ? "fixed" : assignment[c] ? "scheduled" : course.size() > largestRoom ? "too_large" : !course.size() ? "empty" : "no_slot";
            add(lines, course.id, ',', status, ',', assignment[c] ? calendar.name(assignment[c]) : "-", ',', course.size(), ',', course.duration, ',', graph.degrees[c], ',', contributions[c]);
        }
        return lines;
    }
    Lines reportLines() const {
        Lines lines; int enrolments = 0; for (const Student& student : students) enrolments += static_cast<int>(student.courses.size());
        add(lines, "INPUT courses ", courses.size(), " enrolments ", enrolments, " rooms ", rooms.size(), " students ", students.size(), " errors ", errors.size());
        for (const std::string& error : errors) add(lines, "ERROR ", error);
        int edges = 0, shared = 0;
        for (int a : graph.vertices) for (int b : graph.vertices) if (a < b && graph.shared[a][b]) { ++edges; shared += graph.shared[a][b]; }
        int vertices = static_cast<int>(graph.vertices.size()), density = vertices >= 2 ? 2000 * edges / (vertices * (vertices - 1)) : 0;
        add(lines, "GRAPH courses ", vertices, " edges ", edges, " shared ", shared, " density ", density);
        Indices ranked = byDegree(graph.vertices);
        for (std::size_t i = 0; i < std::min<std::size_t>(5, ranked.size()); ++i) {
            int c = ranked[i]; add(lines, "DEGREE ", courses[c].id, " neighbours ", graph.degrees[c], " shared ", std::accumulate(graph.shared[c].begin(), graph.shared[c].end(), 0), " students ", courses[c].size());
        }
        std::vector<Indices> groups = graph.components(); add(lines, "COMPONENTS ", groups.size());
        for (std::size_t i = 0; i < groups.size(); ++i) add(lines, "COMPONENT ", i + 1, " size ", groups[i].size(), " first ", courses[groups[i].front()].id);
        Indices clique = graph.clique(schedulable); std::string cliqueText = text("CLIQUE size ", clique.size());
        for (int c : clique) cliqueText += " " + courses[c].id; lines.push_back(cliqueText);
        int most = 0, attaining = 0, demand = 0, capacity = 0;
        for (const Student& student : students) { int load = static_cast<int>(student.courses.size()); if (load > most) { most = load; attaining = 0; } if (load == most) ++attaining; }
        for (int c : schedulable) demand += courses[c].size(); for (const Room& room : rooms) capacity += room.capacity;
        add(lines, "LOAD max_exams ", most, " students ", attaining); add(lines, "SEATS demand ", demand, " capacity ", capacity, " min_slots ", ceilDiv(demand, capacity));
        add(lines, "HEURISTIC largest_degree slots ", greedyNumbering(graph, byDegree(schedulable)));
        add(lines, "HEURISTIC largest_enrolment slots ", greedyNumbering(graph, packingOrder(courses, schedulable)));
        ranked = packingOrder(courses, graph.vertices); ranked.resize(std::min<std::size_t>(8, ranked.size())); Lines cells;
        for (int c : ranked) cells.push_back(courses[c].id); lines.push_back(fixedWidth("MATRIX", cells, 9, 9));
        for (int row : ranked) {
            cells.clear(); for (int column : ranked) cells.push_back(row == column ? "-" : text(graph.shared[row][column]));
            lines.push_back(fixedWidth(courses[row].id, cells, 9, 9));
        }
        for (int c : empty) add(lines, "EMPTY ", courses[c].id);
        for (int c : oversized) add(lines, "TOO_LARGE ", courses[c].id, " students ", courses[c].size(), " largest_room ", largestRoom);
        for (int slot : calendar.closed) add(lines, "CLOSED ", calendar.name(slot));
        for (int c = 0; c < static_cast<int>(courses.size()); ++c) if (fixed[c]) add(lines, "FIXED ", courses[c].id, ' ', calendar.name(fixed[c]));
        for (const std::pair<int, int>& order : calendar.orders) add(lines, "AFTER ", courses[order.first].id, ' ', courses[order.second].id);
        for (std::size_t i = 0; i < attempts.size(); ++i) {
            const AttemptRecord& attempt = attempts[i];
            add(lines, "ATTEMPT ", i + 1, " courses ", attempt.courses, " backtracks ", attempt.deadEnds, ' ', attempt.failedCourse < 0 ? "success" : "failed " + courses[attempt.failedCourse].id);
        }
        for (std::size_t i = 0; i < choices.size(); ++i) { const Choice& choice = choices[i]; add(lines, "ORDER ", i + 1, ' ', courses[choice.course].id, ' ', calendar.name(choice.slot), " saturation ", choice.saturation, " degree ", graph.degrees[choice.course]); }
        for (const Insertion& insertion : insertions) add(lines, "INSERTED ", courses[insertion.course].id, ' ', calendar.name(insertion.slot), " penalty ", insertion.increase);
        for (int c : unscheduled()) {
            add(lines, "UNSCHEDULED ", courses[c].id, " reason ", courses[c].size() > largestRoom ? "too_large" : "no_slot", " students ", courses[c].size());
            std::map<int, Lines>::const_iterator found = reasons.find(c);
            if (found != reasons.end()) for (int slot = 1; slot <= calendar.slots; ++slot) add(lines, "  ", calendar.name(slot), ' ', found->second[slot - 1]);
        }
        int used = 0; for (int slot : calendar.open) if (!packed[slot].empty()) ++used;
        add(lines, "SUMMARY scheduled ", assignedCount(), " unscheduled ", unscheduled().size(), " slots_used ", used, " penalty ", penalty); return lines;
    }
    void run(const Lines& queries) {
        buildTimetable(); insertExcluded(); exchangeSlots(); swapChains(); assignRooms(); computeStatistics();
        writeFiles({{"timetable.txt", timetableLines()}, {"rooms.csv", roomLines()}, {"penalties.txt", penaltyLines()}, {"student_schedules.txt", scheduleLines(queries)}, {"course_status.csv", statusLines()}, {"report.txt", reportLines()}});
    }
};
int main() {
    Lines errors; std::vector<Course> courses = loadCourses(errors);
    std::vector<Student> students = loadEnrolments(courses, errors); std::vector<Room> rooms = loadRooms(errors);
    Lines calendar = readLines("input/calendar.txt"), queries = readLines("input/queries.txt");
    Scheduler scheduler(std::move(courses), std::move(students), std::move(rooms), calendar, std::move(errors)); scheduler.run(queries);
}
