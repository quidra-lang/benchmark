import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;

final class Course {
    final String id;
    final int duration;
    final String name;
    final List<String> students = new ArrayList<>();

    Course(String id, int duration, String name) {
        this.id = id;
        this.duration = duration;
        this.name = name;
    }

    int size() {
        return students.size();
    }
}

final class Enrolment {
    static List<String[]> records(String path) throws IOException {
        List<String> lines = Files.readAllLines(Path.of(path), StandardCharsets.US_ASCII);
        return lines.subList(1, lines.size()).stream().map(line -> line.split(",", -1)).toList();
    }

    static Map<String, Course> loadCourses(String path, List<String> errors) throws IOException {
        Map<String, Course> courses = new TreeMap<>();
        int line = 1;
        for (String[] fields : records(path)) {
            line++;
            String id = fields[0];
            if (courses.containsKey(id))
                errors.add("courses.csv line " + line + ": duplicate course " + id);
            else
                courses.put(id, new Course(id, Integer.parseInt(fields[1]), fields[2]));
        }
        return courses;
    }

    static Map<String, List<String>> loadEnrolments(
        String path, Map<String, Course> courses, List<String> errors
    ) throws IOException {
        Set<String> accepted = new HashSet<>();
        Map<String, List<String>> students = new TreeMap<>();
        int line = 1;
        for (String[] fields : records(path)) {
            line++;
            String student = fields[0], id = fields[1];
            String key = student + "|" + id;
            if (!courses.containsKey(id))
                errors.add("enrolments.csv line " + line + ": unknown course " + id);
            else if (accepted.contains(key))
                errors.add("enrolments.csv line " + line + ": duplicate enrolment " + student + " " + id);
            else {
                accepted.add(key);
                courses.get(id).students.add(student);
                students.computeIfAbsent(student, ignored -> new ArrayList<>()).add(id);
            }
        }
        courses.values().forEach(course -> course.students.sort(String::compareTo));
        students.values().forEach(ids -> ids.sort(String::compareTo));
        return students;
    }
}
