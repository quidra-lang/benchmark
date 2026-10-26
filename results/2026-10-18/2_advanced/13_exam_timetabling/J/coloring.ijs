saturation =: 4 : 0
    values =. (neighbours x){y
    #~.values#~values>0
)
search =: 3 : 0
    remaining =. Pending#~0=Pending{Assignment
    if. 0=#remaining do. 1 return. end.
    saturations =. 0$0
    for_course. remaining do. saturations =. saturations,course saturation Assignment end.
    order =. /:(-saturations),.(-remaining{Degrees),.remaining
    course =. (0{order){remaining
    Chosen =: Chosen,course,course saturation Assignment
    candidates =. course candidate_slots Assignment
    for_slot. candidates do.
        Assignment =: slot course}Assignment
        if. search '' do. 1 return. end.
        Assignment =: 0 course}Assignment
        if. Aborted do. 0 return. end.
    end.
    Chosen =: }:Chosen
    DeadEnds =: DeadEnds+1
    DeadEndCourse =: course
    Aborted =: DeadEnds>Limit
    0
)
greedy_numbering =: 3 : 0
    numbers =. CourseCount$0
    for_course. y do.
        taken =. (neighbours course){numbers
        value =. 1
        while. value e.taken do. value =. value+1 end.
        numbers =. value course}numbers
    end.
    >./numbers
)
