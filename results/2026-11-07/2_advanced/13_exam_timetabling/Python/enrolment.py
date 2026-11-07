class Course:
    def __init__(self, course_id, duration, name):
        self.id = course_id
        self.duration = duration
        self.name = name
        self.students = []

    def size(self):
        return len(self.students)


def read_records(path):
    with open(path) as file:
        lines = file.read().splitlines()
    return [(number, line.split(",")) for number, line in enumerate(lines[1:], 2)]


def load_courses(path, errors):
    courses = {}
    for number, (course_id, duration, name) in read_records(path):
        if course_id in courses:
            errors.append(f"courses.csv line {number}: duplicate course {course_id}")
        else:
            courses[course_id] = Course(course_id, int(duration), name)
    return courses


def load_enrolments(path, courses, errors):
    accepted = set()
    student_courses = {}
    for number, (student, course_id) in read_records(path):
        if course_id not in courses:
            errors.append(f"enrolments.csv line {number}: unknown course {course_id}")
        elif (student, course_id) in accepted:
            errors.append(
                f"enrolments.csv line {number}: duplicate enrolment {student} {course_id}"
            )
        else:
            accepted.add((student, course_id))
            courses[course_id].students.append(student)
            student_courses.setdefault(student, []).append(course_id)
    for course in courses.values():
        course.students.sort()
    for course_ids in student_courses.values():
        course_ids.sort()
    return student_courses
