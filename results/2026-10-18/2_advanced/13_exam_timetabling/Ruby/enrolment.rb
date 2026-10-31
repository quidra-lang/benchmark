module Enrolment
  Course = Struct.new(:id, :duration, :name, :students, keyword_init: true) do
    def count
      students.length
    end
  end
  Data = Struct.new(:courses, :students, :enrolments, keyword_init: true)

  def self.read(errors)
    courses = {}
    File.readlines('input/courses.csv', chomp: true).drop(1).each_with_index do |line, index|
      id, duration, name = line.split(',')
      if courses.key?(id)
        errors << "courses.csv line #{index + 2}: duplicate course #{id}"
      else
        courses[id] = Course.new(id: id, duration: duration.to_i, name: name, students: [])
      end
    end
    students = {}
    count = 0
    File.readlines('input/enrolments.csv', chomp: true).drop(1).each_with_index do |line, index|
      student, course = line.split(',')
      message = if !courses.key?(course)
                  "unknown course #{course}"
                elsif courses[course].students.include?(student)
                  "duplicate enrolment #{student} #{course}"
                end
      if message
        errors << "enrolments.csv line #{index + 2}: #{message}"
        next
      end
      courses[course].students << student
      (students[student] ||= []) << course
      count += 1
    end
    courses.each_value { |course| course.students.sort! }
    students.each_value(&:sort!)
    Data.new(courses: courses, students: students, enrolments: count)
  end
end
