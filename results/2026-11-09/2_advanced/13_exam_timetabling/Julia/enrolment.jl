mutable struct Course
    id::String
    duration::Int
    name::String
    students::Vector{String}
end

enrolment_count(course::Course) = length(course.students)
read_records(path) = [(number + 1, split(line, ',')) for (number, line) in enumerate(readlines(path)[2:end])]

function load_courses(path, errors)
    courses = Dict{String,Course}()
    for (number, fields) in read_records(path)
        id, duration, name = fields
        if haskey(courses, id)
            push!(errors, "courses.csv line $number: duplicate course $id")
        else
            courses[id] = Course(id, parse(Int, duration), name, String[])
        end
    end
    courses
end

function load_enrolments(path, courses, errors)
    accepted = Set{Tuple{String,String}}()
    students = Dict{String,Vector{String}}()
    for (number, fields) in read_records(path)
        student, id = fields
        if !haskey(courses, id)
            push!(errors, "enrolments.csv line $number: unknown course $id")
        elseif (student, id) in accepted
            push!(errors, "enrolments.csv line $number: duplicate enrolment $student $id")
        else
            push!(accepted, (student, id))
            push!(courses[id].students, student)
            push!(get!(students, student, String[]), id)
        end
    end
    foreach(course -> sort!(course.students), values(courses))
    foreach(sort!, values(students))
    students
end
