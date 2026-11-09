const std = @import("std");
const R = @import("report.zig");
pub const Indices = struct {
    values: [100]usize = undefined,
    len: usize = 0,
    pub fn add(self: *Indices, value: usize) void { self.values[self.len] = value; self.len += 1; }
    pub fn slice(self: *const Indices) []const usize { return self.values[0..self.len]; }
    pub fn contains(self: *const Indices, value: usize) bool { for (self.slice()) |item| { if (item == value) return true; } return false; }
    pub fn sort(self: *Indices) void { std.mem.sort(usize, self.values[0..self.len], {}, std.sort.asc(usize)); }
};
pub const Course = struct {
    id: []const u8, name: []const u8, duration: i64,
    students: std.ArrayList(usize) = .empty,
    pub fn size(self: Course) i64 { return R.n(self.students.items.len); }
};
pub const Student = struct { id: []const u8, courses: Indices = .{}, unavailable: [36]bool = [_]bool{false} ** 36 };
pub fn findCourse(courses: []const Course, id: []const u8) ?usize {
    for (courses, 0..) |course, i| { if (R.eq(course.id, id)) return i; }
    return null;
}
pub fn findStudent(students: []const Student, id: []const u8) ?usize {
    for (students, 0..) |student, i| { if (R.eq(student.id, id)) return i; }
    return null;
}
fn courseLess(_: void, a: Course, b: Course) bool { return std.mem.order(u8, a.id, b.id) == .lt; }
fn studentLess(_: void, a: Student, b: Student) bool { return std.mem.order(u8, a.id, b.id) == .lt; }
pub fn loadCourses(source: []const u8, errors: *R.Lines) []Course {
    var courses: std.ArrayList(Course) = .empty;
    for (R.lines(source)[1..], 2..) |line, line_number| {
        const fields = R.split(line, ',');
        if (findCourse(courses.items, fields[0]) != null) errors.add("courses.csv line {d}: duplicate course {s}", .{ line_number, fields[0] })
        else R.append(Course, &courses, .{ .id = fields[0], .name = fields[2], .duration = R.number(fields[1]) });
    }
    std.mem.sort(Course, courses.items, {}, courseLess);
    return courses.items;
}
pub fn loadEnrolments(source: []const u8, courses: []Course, errors: *R.Lines) []Student {
    var students: std.ArrayList(Student) = .empty;
    for (R.lines(source)[1..], 2..) |line, line_number| {
        const fields = R.split(line, ',');
        const course = findCourse(courses, fields[1]) orelse {
            errors.add("enrolments.csv line {d}: unknown course {s}", .{ line_number, fields[1] });
            continue;
        };
        var student = findStudent(students.items, fields[0]);
        if (student) |index| {
            if (students.items[index].courses.contains(course)) {
                errors.add("enrolments.csv line {d}: duplicate enrolment {s} {s}", .{ line_number, fields[0], fields[1] });
                continue;
            }
        } else {
            student = students.items.len;
            R.append(Student, &students, .{ .id = fields[0] });
        }
        students.items[student.?].courses.add(course);
    }
    std.mem.sort(Student, students.items, {}, studentLess);
    for (students.items, 0..) |*student, index| {
        student.courses.sort();
        for (student.courses.slice()) |course| R.append(usize, &courses[course].students, index);
    }
    return students.items;
}
pub fn ordered(courses: []const Course, group: Indices, values: ?[]const i64) Indices {
    var result = group;
    var i: usize = 1;
    while (i < result.len) : (i += 1) {
        const chosen = result.values[i];
        var j = i;
        while (j > 0) {
            const previous = result.values[j - 1];
            const a = if (values) |v| v[chosen] else courses[chosen].size();
            const b = if (values) |v| v[previous] else courses[previous].size();
            if (a < b or (a == b and chosen > previous)) break;
            result.values[j] = previous;
            j -= 1;
        }
        result.values[j] = chosen;
    }
    return result;
}
