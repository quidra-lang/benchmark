#include "timetable.hpp"

int findCourse(const std::vector<Course>& courses, const std::string& id) {
    for (int i = 0; i < static_cast<int>(courses.size()); ++i) if (courses[i].id == id) return i;
    return -1;
}
int findStudent(const std::vector<Student>& students, const std::string& id) {
    for (int i = 0; i < static_cast<int>(students.size()); ++i) if (students[i].id == id) return i;
    return -1;
}
std::vector<Course> loadCourses(Lines& errors) {
    std::vector<Course> courses; Lines lines = readLines("input/courses.csv");
    for (int i = 1; i < static_cast<int>(lines.size()); ++i) {
        const std::string& line = lines[i]; std::size_t first = line.find(','), second = line.find(',', first + 1);
        std::string id = line.substr(0, first);
        if (findCourse(courses, id) >= 0) add(errors, "courses.csv line ", i + 1, ": duplicate course ", id);
        else courses.push_back({id, line.substr(second + 1), std::stoi(line.substr(first + 1, second - first - 1)), {}});
    }
    std::sort(courses.begin(), courses.end(), [](const Course& a, const Course& b) { return a.id < b.id; });
    return courses;
}
std::vector<Student> loadEnrolments(std::vector<Course>& courses, Lines& errors) {
    Lines lines = readLines("input/enrolments.csv"); std::map<std::string, std::set<int>> records;
    for (int i = 1; i < static_cast<int>(lines.size()); ++i) {
        const std::string& line = lines[i]; std::size_t comma = line.find(',');
        std::string student = line.substr(0, comma), courseId = line.substr(comma + 1); int course = findCourse(courses, courseId);
        if (course < 0) add(errors, "enrolments.csv line ", i + 1, ": unknown course ", courseId);
        else if (!records[student].insert(course).second) add(errors, "enrolments.csv line ", i + 1, ": duplicate enrolment ", student, ' ', courseId);
    }
    std::vector<Student> students;
    for (const std::pair<const std::string, std::set<int>>& entry : records) {
        int student = static_cast<int>(students.size());
        students.push_back({entry.first, Indices(entry.second.begin(), entry.second.end()), {}});
        for (int course : entry.second) courses[course].students.push_back(student);
    }
    return students;
}
