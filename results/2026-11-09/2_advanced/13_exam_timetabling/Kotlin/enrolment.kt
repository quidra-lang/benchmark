import java.io.File

class Course(val id: String, val duration: Int, val name: String) {
    val students = mutableListOf<String>()
    val size: Int get() = students.size
}

object Enrolment {
    fun records(path: String): List<List<String>> =
        File(path).readLines(Charsets.US_ASCII).drop(1).map { it.split(',') }

    fun loadCourses(path: String, errors: MutableList<String>): Map<String, Course> {
        val courses = sortedMapOf<String, Course>()
        for ((index, fields) in records(path).withIndex()) {
            val (id, duration, name) = fields
            if (id in courses) errors += "courses.csv line ${index + 2}: duplicate course $id"
            else courses[id] = Course(id, duration.toInt(), name)
        }
        return courses
    }

    fun loadEnrolments(path: String, courses: Map<String, Course>, errors: MutableList<String>): Map<String, List<String>> {
        val accepted = mutableSetOf<Pair<String, String>>()
        val students = sortedMapOf<String, MutableList<String>>()
        for ((index, fields) in records(path).withIndex()) {
            val (student, id) = fields
            if (id !in courses) errors += "enrolments.csv line ${index + 2}: unknown course $id"
            else if (!accepted.add(student to id))
                errors += "enrolments.csv line ${index + 2}: duplicate enrolment $student $id"
            else {
                courses.getValue(id).students += student
                students.getOrPut(student) { mutableListOf() } += id
            }
        }
        courses.values.forEach { it.students.sort() }
        students.values.forEach { it.sort() }
        return students
    }
}
