import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.StringJoiner;
import java.util.TreeMap;
import java.util.TreeSet;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class Main {
    private static final List<String> DAYS =
        List.of("MO", "TU", "WE", "TH", "FR", "SA", "SU");
    private static final Map<String, Integer> GRADE_POINTS =
        Map.of("A", 4, "B", 3, "C", 2, "D", 1, "F", 0);

    private static String time(int minutes) {
        return String.format("%02d:%02d", minutes / 60, minutes % 60);
    }

    private static String rate(int count, int capacity) {
        return capacity == 0 ? "n/a" : (count * 100 / capacity) + "%";
    }

    private static class CommandError extends RuntimeException {
        CommandError(String message) {
            super(message);
        }
    }

    private record Slot(String day, int start, int end, String raw) {
        boolean overlaps(Slot other) {
            return day.equals(other.day) && start < other.end && other.start < end;
        }
    }

    private static List<Slot> parseSlots(String timetable) {
        if (timetable.equals("-")) {
            return new ArrayList<>();
        }
        List<Slot> slots = new ArrayList<>();
        for (String raw : timetable.split(",")) {
            String day = raw.substring(0, 2);
            int sh = Integer.parseInt(raw.substring(2, 4));
            int sm = Integer.parseInt(raw.substring(4, 6));
            int eh = Integer.parseInt(raw.substring(7, 9));
            int em = Integer.parseInt(raw.substring(9, 11));
            int start = 60 * sh + sm;
            int end = 60 * eh + em;
            if (!DAYS.contains(day) || sh > 23 || sm > 59 ||
                eh > 23 || em > 59 || start >= end) {
                throw new CommandError("invalid slot " + raw);
            }
            slots.add(new Slot(day, start, end, raw));
        }
        for (int i = 0; i < slots.size(); ++i) {
            for (int j = i + 1; j < slots.size(); ++j) {
                if (slots.get(i).overlaps(slots.get(j))) {
                    throw new CommandError(
                        "overlapping slots " + slots.get(i).raw() + " " + slots.get(j).raw()
                    );
                }
            }
        }
        return slots;
    }

    private static final class Expression {
        final String kind;
        final String word;
        final List<Expression> children;

        Expression(String kind, String word, List<Expression> children) {
            this.kind = kind;
            this.word = word;
            this.children = children;
        }

        static Expression word(String word) {
            return new Expression("word", word, List.of());
        }

        static Expression combine(String kind, List<Expression> nodes) {
            List<Expression> children = new ArrayList<>();
            for (Expression node : nodes) {
                if (node.kind.equals(kind)) {
                    children.addAll(node.children);
                } else {
                    children.add(node);
                }
            }
            return children.size() == 1 ? children.get(0)
                : new Expression(kind, "", children);
        }

        String canonical() {
            if (kind.equals("word")) {
                return word;
            }
            StringJoiner joiner = new StringJoiner(kind.equals("and") ? "&" : "|");
            for (Expression child : children) {
                String text = child.canonical();
                if (kind.equals("and") && child.kind.equals("or")) {
                    text = "(" + text + ")";
                }
                joiner.add(text);
            }
            return joiner.toString();
        }

        boolean contains(String code) {
            if (kind.equals("word")) {
                return word.equals(code);
            }
            for (Expression child : children) {
                if (child.contains(code)) {
                    return true;
                }
            }
            return false;
        }

        boolean satisfied(Student student) {
            if (kind.equals("word")) {
                return word.length() == 2 && word.charAt(0) == 'Y'
                    ? student.year >= word.charAt(1) - '0'
                    : student.passed(word) != null;
            }
            if (kind.equals("and")) {
                for (Expression child : children) {
                    if (!child.satisfied(student)) {
                        return false;
                    }
                }
                return true;
            }
            for (Expression child : children) {
                if (child.satisfied(student)) {
                    return true;
                }
            }
            return false;
        }
    }

    private static final class PrerequisiteParser {
        private static final Pattern TOKEN = Pattern.compile("[A-Z0-9]+|[&|()]");
        private static final Pattern WORD =
            Pattern.compile("(?:[A-Z]{2,4}[0-9]{3}|Y[1-9])");

        private final String course;
        private final List<String> tokens = new ArrayList<>();
        private int position;

        PrerequisiteParser(String course, String text) {
            this.course = course;
            Matcher matcher = TOKEN.matcher(text);
            while (matcher.find()) {
                tokens.add(matcher.group());
            }
            if (!String.join("", tokens).equals(text)) {
                invalid();
            }
            for (String token : tokens) {
                if (List.of("&", "|", "(", ")").contains(token)) {
                    continue;
                }
                if (!WORD.matcher(token).matches()) {
                    invalid();
                }
            }
        }

        private void invalid() {
            throw new CommandError("invalid prereq " + course);
        }

        private String peek() {
            return position < tokens.size() ? tokens.get(position) : null;
        }

        private Expression factor() {
            String token = peek();
            ++position;
            if ("(".equals(token)) {
                Expression node = expression();
                if (!")".equals(peek())) {
                    invalid();
                }
                ++position;
                return node;
            }
            if (token == null || List.of("&", "|", ")").contains(token)) {
                invalid();
            }
            return Expression.word(token);
        }

        private Expression term() {
            List<Expression> nodes = new ArrayList<>();
            nodes.add(factor());
            while ("&".equals(peek())) {
                ++position;
                nodes.add(factor());
            }
            return Expression.combine("and", nodes);
        }

        private Expression expression() {
            List<Expression> nodes = new ArrayList<>();
            nodes.add(term());
            while ("|".equals(peek())) {
                ++position;
                nodes.add(term());
            }
            return Expression.combine("or", nodes);
        }

        Expression parse() {
            Expression node = expression();
            if (position != tokens.size()) {
                invalid();
            }
            if (node.contains(course)) {
                throw new CommandError("self prereq " + course);
            }
            return node;
        }

        static Expression from(String course, String text) {
            return text.equals("-") ? null : new PrerequisiteParser(course, text).parse();
        }
    }

    private record Grade(String course, String grade, int credits) {}
    private record History(int number, String event) {}

    private static final class Course {
        final String code;
        final int credits;
        int capacity;
        final List<Slot> slots;
        Expression prerequisite;
        boolean open = true;
        final Set<String> enrolled = new TreeSet<>();
        final List<String> waiting = new ArrayList<>();

        Course(String code, int credits, int capacity, List<Slot> slots, Expression prerequisite) {
            this.code = code;
            this.credits = credits;
            this.capacity = capacity;
            this.slots = slots;
            this.prerequisite = prerequisite;
        }

        String status() {
            return open ? "open" : "closed";
        }

        int weekly() {
            int minutes = 0;
            for (Slot slot : slots) {
                minutes += slot.end() - slot.start();
            }
            return minutes;
        }

        String department() {
            return code.substring(0, code.length() - 3);
        }

        String prerequisiteText() {
            return prerequisite == null ? "-" : prerequisite.canonical();
        }
    }

    private static final class Student {
        final String id;
        final int year;
        int limit;
        final List<Grade> grades;
        final Set<String> taking = new TreeSet<>();
        final List<History> history = new ArrayList<>();

        Student(String id, int year, int limit, List<Grade> grades) {
            this.id = id;
            this.year = year;
            this.limit = limit;
            this.grades = grades;
        }

        String passed(String code) {
            for (Grade grade : grades) {
                if (grade.course().equals(code) &&
                    List.of("A", "B", "C").contains(grade.grade())) {
                    return grade.grade();
                }
            }
            return null;
        }

        int earned() {
            int total = 0;
            for (Grade grade : grades) {
                if (!grade.grade().equals("F")) {
                    total += grade.credits();
                }
            }
            return total;
        }

        String gpa() {
            if (grades.isEmpty()) {
                return "n/a";
            }
            int points = 0;
            int credits = 0;
            for (Grade grade : grades) {
                points += GRADE_POINTS.get(grade.grade()) * grade.credits();
                credits += grade.credits();
            }
            int hundredths = (200 * points + credits) / (2 * credits);
            return String.format("%d.%02d", hundredths / 100, hundredths % 100);
        }
    }

    private static final class Decision {
        final String word;
        final List<String> extra;

        Decision(String word, String... extra) {
            this.word = word;
            this.extra = List.of(extra);
        }

        String text() {
            return word + (extra.isEmpty() ? "" : " " + String.join(" ", extra));
        }
    }

    private record Meeting(String code, Slot slot) {}

    private static final class Registrar {
        private final Map<String, Course> courses = new TreeMap<>();
        private final Map<String, Student> students = new TreeMap<>();
        private final List<String> output = new ArrayList<>();
        private int commandNumber;

        private void emit(int indent, Object... parts) {
            StringJoiner text = new StringJoiner(" ", " ".repeat(indent), "");
            for (Object part : parts) {
                text.add(part.toString());
            }
            output.add(text.toString());
        }

        private Student student(String id) {
            Student result = students.get(id);
            if (result == null) {
                throw new CommandError("unknown student " + id);
            }
            return result;
        }

        private Course course(String code) {
            Course result = courses.get(code);
            if (result == null) {
                throw new CommandError("unknown course " + code);
            }
            return result;
        }

        private List<Course> taking(Student student, String excluded) {
            List<Course> result = new ArrayList<>();
            for (String code : student.taking) {
                if (!code.equals(excluded)) {
                    result.add(courses.get(code));
                }
            }
            return result;
        }

        private int credits(Student student, String excluded) {
            int sum = 0;
            for (Course course : taking(student, excluded)) {
                sum += course.credits;
            }
            return sum;
        }

        private List<Course> waitlists(Student student) {
            List<Course> result = new ArrayList<>();
            for (Course course : courses.values()) {
                if (course.waiting.contains(student.id)) {
                    result.add(course);
                }
            }
            return result;
        }

        private Course conflict(Student student, Course target, String excluded) {
            for (Course course : taking(student, excluded)) {
                for (Slot a : course.slots) {
                    for (Slot b : target.slots) {
                        if (a.overlaps(b)) {
                            return course;
                        }
                    }
                }
            }
            return null;
        }

        private Decision eligible(Student student, Course course, String excluded) {
            if (!course.open) return new Decision("course closed");
            if (course.enrolled.contains(student.id)) return new Decision("already enrolled");
            if (course.waiting.contains(student.id)) return new Decision("already waitlisted");

            String grade = student.passed(course.code);
            if (grade != null) return new Decision("already completed", grade);
            if (course.prerequisite != null && !course.prerequisite.satisfied(student))
                return new Decision("prereq not met");

            Course conflict = conflict(student, course, excluded);
            if (conflict != null) return new Decision("time conflict", conflict.code);

            int requested = credits(student, excluded) + course.credits;
            if (requested > student.limit)
                return new Decision(
                    "credit limit", Integer.toString(requested), Integer.toString(student.limit)
                );
            return new Decision("OK");
        }

        private int waitPosition(Student student, Course course) {
            int position = 1;
            for (String id : course.waiting) {
                if (students.get(id).year >= student.year) {
                    ++position;
                }
            }
            return position;
        }

        private Decision judgment(Student student, Course course) {
            Decision decision = eligible(student, course, null);
            if (!decision.word.equals("OK")) return decision;
            if (course.enrolled.size() < course.capacity) return new Decision("enroll");
            if (waitlists(student).size() >= 3) return new Decision("waitlist limit");
            return new Decision("waitlist", Integer.toString(waitPosition(student, course)));
        }

        private void reject(Student student, Course course, Decision decision) {
            throw new CommandError(
                decision.word + " " + student.id + " " + course.code +
                (decision.extra.isEmpty() ? "" : " " + String.join(" ", decision.extra))
            );
        }

        private void record(Student student, String event) {
            student.history.add(new History(commandNumber, event));
        }

        private void enroll(Student student, Course course) {
            course.enrolled.add(student.id);
            student.taking.add(course.code);
        }

        private void withdraw(Student student, Course course) {
            course.enrolled.remove(student.id);
            student.taking.remove(course.code);
        }

        private void enrollmentLine(String label, Student student, Course course, int indent) {
            emit(indent, label, student.id, course.code, "enrolled",
                course.enrolled.size() + "/" + course.capacity, "credits",
                credits(student, null) + "/" + student.limit);
        }

        private void promote() {
            for (Course course : courses.values()) {
                if (!course.open) continue;
                while (course.enrolled.size() < course.capacity) {
                    int selected = -1;
                    for (int i = 0; i < course.waiting.size(); ++i) {
                        Student student = students.get(course.waiting.get(i));
                        if (conflict(student, course, null) == null &&
                            credits(student, null) + course.credits <= student.limit) {
                            selected = i;
                            break;
                        }
                    }
                    if (selected < 0) break;
                    Student student = students.get(course.waiting.remove(selected));
                    enroll(student, course);
                    record(student, "promote " + course.code);
                    enrollmentLine("PROMOTE", student, course, 2);
                }
            }
        }

        private void schedule(Student student) {
            List<Course> taking = taking(student, null);
            int weekly = taking.stream().mapToInt(Course::weekly).sum();
            emit(0, "SCHEDULE", student.id, "courses", taking.size(), "credits",
                credits(student, null), "weekly", time(weekly));

            for (String day : DAYS) {
                List<Meeting> meetings = new ArrayList<>();
                for (Course course : taking) {
                    for (Slot slot : course.slots) {
                        if (slot.day().equals(day)) {
                            meetings.add(new Meeting(course.code, slot));
                        }
                    }
                }
                meetings.sort(Comparator.comparingInt(m -> m.slot().start()));
                if (!meetings.isEmpty()) {
                    List<Object> line = new ArrayList<>();
                    line.add(day);
                    for (Meeting meeting : meetings) {
                        line.add(time(meeting.slot().start()) + "-" + time(meeting.slot().end()));
                        line.add(meeting.code());
                    }
                    emit(2, line.toArray());
                }
            }

            List<Object> tba = new ArrayList<>();
            tba.add("TBA");
            for (Course course : taking) {
                if (course.slots.isEmpty()) {
                    tba.add(course.code);
                }
            }
            if (tba.size() > 1) {
                emit(2, tba.toArray());
            }
        }

        private void command(String command, String[] a) {
            switch (command) {
                case "COURSE" -> {
                    if (courses.containsKey(a[0]))
                        throw new CommandError("duplicate course " + a[0]);
                    List<Slot> slots = parseSlots(a[3]);
                    Expression prerequisite = PrerequisiteParser.from(a[0], a[4]);
                    Course course = new Course(
                        a[0], Integer.parseInt(a[1]), Integer.parseInt(a[2]), slots, prerequisite
                    );
                    courses.put(course.code, course);
                    emit(0, "COURSE", course.code, "credits", course.credits,
                        "capacity", course.capacity, "meetings", slots.size(),
                        "weekly", time(course.weekly()), "prereq", course.prerequisiteText());
                }

                case "STUDENT" -> {
                    if (students.containsKey(a[0]))
                        throw new CommandError("duplicate student " + a[0]);
                    List<Grade> grades = new ArrayList<>();
                    Set<String> seen = new HashSet<>();
                    if (!a[3].equals("-")) {
                        for (String raw : a[3].split(",")) {
                            String[] entry = raw.split(":");
                            String code = entry[0], grade = entry[1];
                            if (!GRADE_POINTS.containsKey(grade))
                                throw new CommandError(
                                    "invalid grade " + a[0] + " " + code + " " + grade
                                );
                            if (!seen.add(code))
                                throw new CommandError("duplicate record " + a[0] + " " + code);
                            grades.add(new Grade(code, grade, Integer.parseInt(entry[2])));
                        }
                    }
                    Student student = new Student(
                        a[0], Integer.parseInt(a[1]), Integer.parseInt(a[2]), grades
                    );
                    students.put(student.id, student);
                    emit(0, "STUDENT", student.id, "year", student.year,
                        "limit", student.limit, "records", grades.size(),
                        "earned", student.earned(), "gpa", student.gpa());
                }

                case "ENROLL", "CHECK" -> {
                    Student student = student(a[0]);
                    Course course = course(a[1]);
                    Decision decision = judgment(student, course);
                    if (command.equals("CHECK")) {
                        emit(0, "CHECK", student.id, course.code, decision.text());
                    } else if (decision.word.equals("enroll")) {
                        enroll(student, course);
                        record(student, "enroll " + course.code);
                        enrollmentLine("ENROLL", student, course, 0);
                    } else if (decision.word.equals("waitlist")) {
                        int position = Integer.parseInt(decision.extra.get(0));
                        course.waiting.add(position - 1, student.id);
                        record(student, "waitlist " + course.code + " " + position);
                        emit(0, "ENROLL", student.id, course.code, "waitlist", position);
                    } else {
                        reject(student, course, decision);
                    }
                }

                case "OPTIONS" -> {
                    Student student = student(a[0]);
                    emit(0, "OPTIONS", student.id, "courses", courses.size());
                    for (Course course : courses.values()) {
                        emit(2, course.code, judgment(student, course).text());
                    }
                }

                case "DROP" -> {
                    Student student = student(a[0]);
                    Course course = course(a[1]);
                    if (course.enrolled.contains(student.id)) {
                        withdraw(student, course);
                        record(student, "drop " + course.code);
                        enrollmentLine("DROP", student, course, 0);
                    } else if (course.waiting.remove(student.id)) {
                        record(student, "drop " + course.code + " waitlist");
                        emit(0, "DROP", student.id, course.code, "waitlist", "removed");
                    } else {
                        throw new CommandError("not registered " + student.id + " " + course.code);
                    }
                    promote();
                }

                case "SWAP" -> {
                    Student student = student(a[0]);
                    Course old = course(a[1]);
                    Course target = course(a[2]);
                    if (!old.enrolled.contains(student.id))
                        throw new CommandError("not enrolled " + student.id + " " + old.code);
                    if (old == target)
                        throw new CommandError("same course " + old.code);
                    Decision decision = eligible(student, target, old.code);
                    if (!decision.word.equals("OK")) reject(student, target, decision);
                    if (target.enrolled.size() >= target.capacity)
                        throw new CommandError("course full " + target.code);
                    withdraw(student, old);
                    enroll(student, target);
                    record(student, "swap " + old.code + " " + target.code);
                    emit(0, "SWAP", student.id, old.code, "->", target.code,
                        "credits", credits(student, null) + "/" + student.limit);
                    promote();
                }

                case "CLOSE", "OPEN" -> {
                    Course course = course(a[0]);
                    boolean opening = command.equals("OPEN");
                    if (course.open == opening)
                        throw new CommandError(
                            "already " + (opening ? "open " : "closed ") + course.code
                        );
                    course.open = opening;
                    emit(0, command, course.code, "enrolled",
                        course.enrolled.size() + "/" + course.capacity,
                        "waitlist", course.waiting.size());
                    if (opening) promote();
                }

                case "CAPACITY" -> {
                    Course course = course(a[0]);
                    int capacity = Integer.parseInt(a[1]);
                    if (capacity < course.enrolled.size())
                        throw new CommandError(
                            "capacity below enrollment " + course.code + " " + course.enrolled.size()
                        );
                    int previous = course.capacity;
                    course.capacity = capacity;
                    emit(0, "CAPACITY", course.code, previous, "->", capacity);
                    promote();
                }

                case "LIMIT" -> {
                    Student student = student(a[0]);
                    int limit = Integer.parseInt(a[1]);
                    int enrolled = credits(student, null);
                    if (limit < enrolled)
                        throw new CommandError("limit below enrolled " + student.id + " " + enrolled);
                    int previous = student.limit;
                    student.limit = limit;
                    emit(0, "LIMIT", student.id, previous, "->", limit);
                    promote();
                }

                case "PREREQ" -> {
                    Course course = course(a[0]);
                    Expression prerequisite = PrerequisiteParser.from(course.code, a[1]);
                    course.prerequisite = prerequisite;
                    emit(0, "PREREQ", course.code, course.prerequisiteText());
                    List<String> remaining = new ArrayList<>();
                    for (String id : course.waiting) {
                        Student student = students.get(id);
                        if (prerequisite == null || prerequisite.satisfied(student)) {
                            remaining.add(id);
                        } else {
                            record(student, "unlist " + course.code);
                            emit(2, "UNLIST", student.id, course.code);
                        }
                    }
                    course.waiting.clear();
                    course.waiting.addAll(remaining);
                }

                case "CANCEL" -> {
                    Course course = course(a[0]);
                    emit(0, "CANCEL", course.code, "enrolled",
                        course.enrolled.size(), "waitlist", course.waiting.size());
                    for (String id : course.enrolled) {
                        Student student = students.get(id);
                        student.taking.remove(course.code);
                        record(student, "cancel " + course.code);
                    }
                    for (String id : course.waiting)
                        record(students.get(id), "cancel " + course.code + " waitlist");
                    courses.remove(course.code);
                    promote();
                }

                case "ROSTER" -> {
                    Course course = course(a[0]);
                    emit(0, "ROSTER", course.code, course.status(), "enrolled",
                        course.enrolled.size() + "/" + course.capacity,
                        "waitlist", course.waiting.size());
                    for (String id : course.enrolled)
                        emit(2, "enrolled", id, "year", students.get(id).year);
                    for (int position = 0; position < course.waiting.size(); ++position) {
                        String id = course.waiting.get(position);
                        emit(2, "waitlist", position + 1, id, "year", students.get(id).year);
                    }
                }

                case "SCHEDULE" -> schedule(student(a[0]));

                case "FREE" -> {
                    Student student = student(a[0]);
                    String day = a[1];
                    if (!DAYS.contains(day)) throw new CommandError("invalid day " + day);
                    List<Slot> meetings = new ArrayList<>();
                    for (Course course : taking(student, null))
                        for (Slot slot : course.slots)
                            if (slot.day().equals(day) && slot.start() < 1320 && slot.end() > 480)
                                meetings.add(slot);
                    meetings.sort(Comparator.comparingInt(Slot::start));
                    List<int[]> ranges = new ArrayList<>();
                    int cursor = 480;
                    for (Slot slot : meetings) {
                        int start = Math.max(slot.start(), 480);
                        if (start > cursor) ranges.add(new int[] { cursor, start });
                        cursor = Math.max(cursor, Math.min(slot.end(), 1320));
                    }
                    if (cursor < 1320) ranges.add(new int[] { cursor, 1320 });
                    int free = ranges.stream().mapToInt(interval -> interval[1] - interval[0]).sum();
                    List<Object> line = new ArrayList<>();
                    line.addAll(Arrays.asList("FREE", student.id, day, "total", time(free)));
                    for (int[] interval : ranges)
                        line.add(time(interval[0]) + "-" + time(interval[1]));
                    emit(0, line.toArray());
                }

                case "INFO" -> {
                    Course course = course(a[0]);
                    emit(0, "INFO", course.code, course.status(), "credits", course.credits,
                        "capacity", course.capacity, "prereq", course.prerequisiteText());
                    List<Slot> slots = new ArrayList<>(course.slots);
                    slots.sort(Comparator.comparingInt((Slot slot) -> DAYS.indexOf(slot.day()))
                        .thenComparingInt(Slot::start));
                    if (slots.isEmpty()) emit(2, "meet", "TBA");
                    for (Slot slot : slots)
                        emit(2, "meet", slot.day(),
                            time(slot.start()) + "-" + time(slot.end()));
                    List<Object> required = new ArrayList<>();
                    required.add("required");
                    required.add("by");
                    for (Course other : courses.values()) {
                        if (other.prerequisite != null &&
                            other.prerequisite.contains(course.code)) {
                            required.add(other.code);
                        }
                    }
                    if (required.size() == 2) required.add("none");
                    emit(2, required.toArray());
                }

                case "AUDIT" -> {
                    Student student = student(a[0]);
                    emit(0, "AUDIT", student.id, "year", student.year, "limit", student.limit);
                    List<Grade> grades = new ArrayList<>(student.grades);
                    grades.sort(Comparator.comparing(Grade::course));
                    for (Grade grade : grades)
                        emit(2, "record", grade.course(), grade.grade(), grade.credits());
                    emit(2, "earned", student.earned(), "gpa", student.gpa());
                    for (Course course : taking(student, null))
                        emit(2, "enrolled", course.code, course.credits);
                    int credits = credits(student, null);
                    emit(2, "credits", credits, "remaining", student.limit - credits);
                    for (Course course : waitlists(student))
                        emit(2, "waitlist", course.code, course.waiting.indexOf(student.id) + 1);
                }

                case "HISTORY" -> {
                    Student student = student(a[0]);
                    emit(0, "HISTORY", student.id, "events", student.history.size());
                    for (History history : student.history)
                        emit(2, history.number(), history.event());
                }

                case "STUDENTS" -> {
                    emit(0, "STUDENTS", students.size());
                    for (Student student : students.values())
                        emit(2, student.id, "year", student.year,
                            "credits", credits(student, null) + "/" + student.limit,
                            "courses", student.taking.size(), "waitlists", waitlists(student).size());
                }

                case "REPORT" -> {
                    int enrolled = 0;
                    int capacity = 0;
                    int waiting = 0;
                    Map<String, List<Course>> departments = new TreeMap<>();
                    for (Course course : courses.values()) {
                        enrolled += course.enrolled.size();
                        capacity += course.capacity;
                        waiting += course.waiting.size();
                        departments.computeIfAbsent(course.department(), key -> new ArrayList<>())
                            .add(course);
                    }
                    emit(0, "REPORT", "courses", courses.size(), "enrolled",
                        enrolled + "/" + capacity, "rate", rate(enrolled, capacity),
                        "waitlisted", waiting);
                    for (Course course : courses.values()) {
                        emit(2, course.code, course.status(),
                            course.enrolled.size() + "/" + course.capacity,
                            rate(course.enrolled.size(), course.capacity),
                            "waitlist", course.waiting.size());
                    }
                    for (var entry : departments.entrySet()) {
                        List<Course> group = entry.getValue();
                        int count = group.stream().mapToInt(c -> c.enrolled.size()).sum();
                        int seats = group.stream().mapToInt(c -> c.capacity).sum();
                        int queue = group.stream().mapToInt(c -> c.waiting.size()).sum();
                        emit(2, "dept", entry.getKey(), "courses", group.size(),
                            "enrolled", count + "/" + seats, "rate", rate(count, seats),
                            "waitlisted", queue);
                    }
                }
            }
        }

        void execute(String line) {
            ++commandNumber;
            String[] tokens = line.split(" ");
            try {
                command(tokens[0], Arrays.copyOfRange(tokens, 1, tokens.length));
            } catch (CommandError error) {
                emit(0, "ERROR", error.getMessage());
            }
        }

        String output() {
            return output.isEmpty() ? "" : String.join("\n", output) + "\n";
        }
    }

    public static void main(String[] args) throws Exception {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in));
        int count = Integer.parseInt(input.readLine());
        Registrar registrar = new Registrar();
        for (int i = 0; i < count; ++i) {
            registrar.execute(input.readLine());
        }
        System.out.print(registrar.output());
    }
}
