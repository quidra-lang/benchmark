read_records =: 3 : 0
    records =. 0$a:
    for_line. }.read_lines y do. records =. records,<',' split >line end.
    records
)
load_courses =: 3 : 0
    ids =. names =. 0$a:
    durations =. 0$0
    records =. read_records 'courses.csv'
    for_index. i.#records do.
        fields =. index{::records
        id =. 0{::fields
        if. (<id)e.ids do.
            Errors =: Errors,<'courses.csv line |: duplicate course |' format (<index+2),<id
        else.
            ids =. ids,<id
            durations =. durations,num 1{::fields
            names =. names,2{fields
        end.
    end.
    order =. ascii_order ids
    CourseIds =: order{ids
    Durations =: order{durations
    CourseNames =: order{names
    CourseCount =: #CourseIds
    i.0
)
load_enrolments =: 3 : 0
    students =. 0$a:
    courses =. 0$0
    accepted =. 0$a:
    records =. read_records 'enrolments.csv'
    for_index. i.#records do.
        fields =. index{::records
        student =. 0{::fields
        id =. 1{::fields
        course =. CourseIds i.<id
        key =. student,':',id
        if. course=CourseCount do.
            Errors =: Errors,<'enrolments.csv line |: unknown course |' format (<index+2),<id
        elseif. (<key)e.accepted do.
            Errors =: Errors,<'enrolments.csv line |: duplicate enrolment | |' format (<index+2),(<student),<id
        else.
            accepted =. accepted,<key
            students =. students,<student
            courses =. courses,course
        end.
    end.
    StudentIds =: ascii_sort ~.students
    StudentCount =: #StudentIds
    StudentCourses =: 0$a:
    for_student. StudentIds do. StudentCourses =: StudentCourses,</:~courses#~students=student end.
    Rosters =: 0$a:
    for_course. i.CourseCount do.
        roster =. StudentIds i.(courses=course)#students
        Rosters =: Rosters,</:~roster
    end.
    Sizes =: #&>Rosters
    i.0
)
