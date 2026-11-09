LF =: 10{a.
DAYS =: ;:'MO TU WE TH FR SA SU'
CourseNames =: Courses =: StudentNames =: Students =: 0$a:
CommandNumber =: 0
CF =: ;:'code credits capacity slots canonical expression references open enrolled waiting'
SF =: ;:'id year limit grades history'
split =: 4 : '<;._1 x,y'
number =: 3 : 0
    ,'0' 8!:2 y
)
join =: 4 : 0
    result =. ''
    for_i. i.#y do.
        if. i do. result =. result,x end.
        result =. result,i{::y
    end.
    result
)
words =: 3 : 0
    parts =. 0$a:
    for_part. y do.
        value =. >part
        if. 2~:3!:0 value do. value =. number value end.
        parts =. parts,<value
    end.
    ' ' join parts
)
write =: 4 : 0
    ((x#' '),(words y),LF) 1!:2 4
    i.0
)
emit =: 0&write
fail =: 3 : 'emit (<''ERROR''),y'
floor_ratio =: 4 : '<.(x:x)%x:y'
padded =: 4 : 0
    text =. number y
    ((0>.x-#text)#'0'),text
)
clock =: 3 : '(2 padded y floor_ratio 60),'':'',2 padded 60|y'
time_range =: 3 : '(clock 0{y),''-'',clock 1{y'
fraction =: 3 : '(number 0{y),''/'',number 1{y'
rate =: 3 : 0
    if. 0=1{y do. 'n/a' else. (number (100*0{y) floor_ratio 1{y),'%' end.
)
cg =: 4 : '(CF i.<x){::y'
sg =: 4 : '(SF i.<x){::y'
cs =: 4 : 0
    'key value' =. x
    (<value) (CF i.<key)}y
)
ss =: 4 : 0
    'key value' =. x
    (<value) (SF i.<key)}y
)
save_course =: 4 : 'Courses =: (<y) x}Courses'
save_student =: 4 : 'Students =: (<y) x}Students'
status =: 3 : '(''open'' cg y){::;:''closed open'''
valid_course_word =: 3 : 0
    if. -. (#y)e.5 6 7 do. 0 return. end.
    (*./(_3}.y)e.'ABCDEFGHIJKLMNOPQRSTUVWXYZ')*.*./(_3{.y)e.'0123456789'
)
valid_year_word =: 3 : 0
    if. 2~:#y do. 0 return. end.
    ('Y'={.y)*.({:y)e.'123456789'
)
precedence =: 3 : 0
    if. y-:'|' do. 1 elseif. y-:'&' do. 2 else. 3 end.
)
canonical =: 3 : 0
    stack =. 0$a:
    for_token. y do.
        token =. >token
        if. (<token)e.'|';'&' do.
            'rp right' =. >{:stack
            stack =. }:stack
            'lp left' =. >{:stack
            stack =. }:stack
            p =. precedence token
            if. lp<p do. left =. '(',left,')' end.
            if. rp<p do. right =. '(',right,')' end.
            stack =. stack,<p;left,token,right
        else. stack =. stack,<3;token end.
    end.
    1{::>{:stack
)
parse_prereq =: 3 : 0
    invalid =. 0;'';(0$a:);<0$a:
    if. y-:'-' do. 1;'-';(0$a:);<0$a: return. end.
    tokens =. 0$a:
    references =. 0$a:
    i =. 0
    while. i<#y do.
        ch =. i{y
        if. ch e.'&|()' do.
            tokens =. tokens,<,ch
            i =. i+1
        else.
            start =. i
            while. i<#y do.
                if. (i{y)e.'&|()' do. break. end.
                i =. i+1
            end.
            token =. (i-start){.start}.y
            if. valid_course_word token do. references =. references,<token
            elseif. -.valid_year_word token do. invalid return. end.
            tokens =. tokens,<token
        end.
    end.
    output =. operators =. 0$a:
    expecting =. 1
    for_token. tokens do.
        text =. >token
        select. text
        case. '(' do.
            if. -.expecting do. invalid return. end.
            operators =. operators,token
        case. ')' do.
            if. expecting do. invalid return. end.
            while. #operators do.
                if. ({:operators)-:<'(' do. break. end.
                output =. output,{:operators
                operators =. }:operators
            end.
            if. 0=#operators do. invalid return. end.
            operators =. }:operators
        case. '&';'|' do.
            if. expecting do. invalid return. end.
            while. #operators do.
                top =. >{:operators
                if. top-:'(' do. break. end.
                if. (precedence top)<precedence text do. break. end.
                output =. output,{:operators
                operators =. }:operators
            end.
            operators =. operators,token
            expecting =. 1
        case. do.
            if. -.expecting do. invalid return. end.
            output =. output,token
            expecting =. 0
        end.
    end.
    if. expecting do. invalid return. end.
    if. (<'(')e.operators do. invalid return. end.
    output =. output,|.operators
    1;(canonical output);output;<~.references
)
passed_grade =: 4 : 0
    for_record. 'grades' sg x{::Students do.
        'code grade credits' =. >record
        if. (code-:y)*.(,grade)e.'ABC' do. grade return. end.
    end.
    ''
)
satisfies =: 4 : 0
    if. 0=#y do. 1 return. end.
    stack =. i.0
    for_token. y do.
        token =. >token
        if. (<token)e.'|';'&' do.
            right =. {:stack
            stack =. }:stack
            left =. {:stack
            stack =. }:stack
            if. token-:'|' do. result =. left+.right
            else. result =. left*.right end.
        elseif. valid_year_word token do.
            result =. ('year' sg x{::Students)>:0".}.token
        else. result =. 0<#x passed_grade token end.
        stack =. stack,result
    end.
    {.stack
)
overlaps =: 4 : 0
    ((0{x)=0{y)*.((1{x)<2{y)*.(1{y)<2{x
)
conflicts =: 4 : 0
    for_a. 'slots' cg x{::Courses do.
        for_b. 'slots' cg y{::Courses do.
            if. a overlaps b do. 1 return. end.
        end.
    end.
    0
)
enrolled_courses =: 3 : 0
    result =. i.0
    for_c. /:CourseNames do.
        if. y e.'enrolled' cg c{::Courses do. result =. result,c end.
    end.
    result
)
waiting_courses =: 3 : 0
    result =. i.0
    for_c. /:CourseNames do.
        if. y e.'waiting' cg c{::Courses do. result =. result,c end.
    end.
    result
)
enrolled_credits =: 3 : 0
    total =. 0
    for_c. enrolled_courses y do. total =. total+'credits' cg c{::Courses end.
    total
)
grade_summary =: 3 : 0
    records =. 'grades' sg y{::Students
    earned =. points =. credits =. 0
    for_record. records do.
        'code grade credit' =. >record
        points =. points+credit*(4-'ABCDF'i.{.grade)
        credits =. credits+credit
        if. -.grade-:'F' do. earned =. earned+credit end.
    end.
    gpa =. 'n/a'
    if. #records do.
        value =. ((200*points)+credits) floor_ratio 2*credits
        gpa =. (number value floor_ratio 100),'.',2 padded 100|value
    end.
    earned;gpa
)
add_history =: 4 : 0
    s =. x{::Students
    history =. ('history' sg s),<CommandNumber;y
    x save_student ('history';<history) ss s
    i.0
)
fit_reason =: 3 : 0
    's c excluded' =. y
    credits =. 'credits' cg c{::Courses
    for_other. (enrolled_courses s)-.excluded do.
        if. c conflicts other do. 'time conflict';other{::CourseNames return. end.
        credits =. credits+'credits' cg other{::Courses
    end.
    limit =. 'limit' sg s{::Students
    if. credits>limit do. 'credit limit';credits;limit else. 0$a: end.
)
eligibility =: 3 : 0
    's c excluded' =. y
    course =. c{::Courses
    if. -.'open' cg course do. ,<'course closed' return. end.
    if. s e.'enrolled' cg course do. ,<'already enrolled' return. end.
    if. s e.'waiting' cg course do. ,<'already waitlisted' return. end.
    grade =. s passed_grade c{::CourseNames
    if. #grade do. 'already completed';grade return. end.
    if. -.s satisfies 'expression' cg course do. ,<'prereq not met' return. end.
    fit_reason y
)
wait_position =: 4 : 0
    year =. 'year' sg x{::Students
    position =. 1
    for_s. 'waiting' cg y{::Courses do.
        position =. position+('year' sg s{::Students)>:year
    end.
    position
)
judgment =: 4 : 0
    reason =. eligibility x,y,_1
    if. #reason do. reason return. end.
    course =. y{::Courses
    if. (#'enrolled' cg course)<'capacity' cg course do. ,<'enroll' return. end.
    if. 3<:#waiting_courses x do. ,<'waitlist limit' return. end.
    'waitlist';x wait_position y
)
enrollment_line =: 4 : 0
    's c' =. y
    course =. c{::Courses
    student =. s{::Students
    (x;(s{::StudentNames);(c{::CourseNames);'enrolled';(fraction (#'enrolled' cg course),'capacity' cg course);'credits';fraction (enrolled_credits s),'limit' sg student)
)
promote =: 3 : 0
    for_c. /:CourseNames do.
        while. 1 do.
            course =. c{::Courses
            if. -.'open' cg course do. break. end.
            if. (#'enrolled' cg course)>:'capacity' cg course do. break. end.
            candidate =. _1
            for_s. 'waiting' cg course do.
                if. 0=#fit_reason s,c,_1 do. candidate =. s
                    break. end.
            end.
            if. candidate=_1 do. break. end.
            course =. ('enrolled';('enrolled' cg course),candidate) cs ('waiting';('waiting' cg course)-.candidate) cs course
            c save_course course
            candidate add_history 'promote ',c{::CourseNames
            2 write 'PROMOTE' enrollment_line candidate,c
        end.
    end.
    i.0
)
schedule_rows =: 3 : 0
    rows =. 0 4$0
    for_c. enrolled_courses y do.
        for_slot. 'slots' cg c{::Courses do. rows =. rows,1 4$slot,c end.
    end.
    /:~rows
)
show_schedule =: 3 : 0
    courses =. enrolled_courses y
    rows =. schedule_rows y
    weekly =. +/(2{"1 rows)-1{"1 rows
    emit 'SCHEDULE';(y{::StudentNames);'courses';(#courses);'credits';(enrolled_credits y);'weekly';clock weekly
    for_day. i.7 do.
        slots =. rows#~day=0{"1 rows
        if. 0=#slots do. continue. end.
        line =. day{DAYS
        for_slot. slots do.
            line =. line,(time_range 1 2{slot);(3{slot){::CourseNames
        end.
        2 write line
    end.
    tba =. 0$a:
    for_c. courses do.
        if. 0=#'slots' cg c{::Courses do. tba =. tba,c{CourseNames end.
    end.
    if. #tba do. 2 write (<'TBA'),tba end.
    i.0
)
show_free =: 4 : 0
    free =. 840$1
    rows =. schedule_rows x
    for_row. rows#~y=0{"1 rows do.
        start =. 480>.1{row
        finish =. 1320<.2{row
        if. start<finish do. free =. 0 ((start-480)+i.finish-start)}free end.
    end.
    line =. 'FREE';(x{::StudentNames);(y{::DAYS);'total';clock +/free
    start =. _1
    for_i. i.841 do.
        available =. 0
        if. i<840 do. available =. i{free end.
        if. available do.
            if. start=_1 do. start =. 480+i end.
        elseif. start>:0 do.
            line =. line,<time_range start,480+i
            start =. _1
        end.
    end.
    emit line
)
show_info =: 3 : 0
    course =. y{::Courses
    code =. y{::CourseNames
    emit 'INFO';code;(status course);'credits';('credits' cg course);'capacity';('capacity' cg course);'prereq';'canonical' cg course
    slots =. /:~'slots' cg course
    if. 0=#slots do. 2 write <'meet TBA' end.
    for_slot. slots do. 2 write 'meet';((0{slot){::DAYS);time_range 1 2{slot end.
    required =. 0$a:
    for_c. /:CourseNames do.
        if. (<code)e.'references' cg c{::Courses do. required =. required,c{CourseNames end.
    end.
    if. 0=#required do. required =. ,<'none' end.
    2 write (<'required by'),required
)
show_audit =: 3 : 0
    student =. y{::Students
    emit 'AUDIT';(y{::StudentNames);'year';('year' sg student);'limit';'limit' sg student
    records =. 'grades' sg student
    names =. 0$a:
    for_record. records do. names =. names,0{>record end.
    for_i. /:names do. 2 write (<'record'),i{::records end.
    'earned gpa' =. grade_summary y
    2 write 'earned';earned;'gpa';gpa
    for_c. enrolled_courses y do. 2 write 'enrolled';(c{::CourseNames);'credits' cg c{::Courses end.
    credits =. enrolled_credits y
    2 write 'credits';credits;'remaining';('limit' sg student)-credits
    for_c. waiting_courses y do.
        waiting =. 'waiting' cg c{::Courses
        2 write 'waitlist';(c{::CourseNames);1+waiting i.y
    end.
)
course_totals =: 3 : 0
    result =. 3$0
    for_c. y do.
        course =. c{::Courses
        result =. result+(#'enrolled' cg course),('capacity' cg course),#'waiting' cg course
    end.
    result
)
show_report =: 3 : 0
    'enrolled capacity waiting' =. course_totals i.#Courses
    emit 'REPORT courses';(#Courses);'enrolled';(fraction enrolled,capacity);'rate';(rate enrolled,capacity);'waitlisted';waiting
    departments =. 0$a:
    for_c. /:CourseNames do.
        course =. c{::Courses
        n =. #'enrolled' cg course
        cap =. 'capacity' cg course
        2 write (c{::CourseNames);(status course);(fraction n,cap);(rate n,cap);'waitlist';#'waiting' cg course
        departments =. departments,<_3}.c{::CourseNames
    end.
    for_department. /:~ ~.departments do.
        members =. i.0
        for_c. i.#Courses do.
            if. department-:<_3}.c{::CourseNames do. members =. members,c end.
        end.
        'enrolled capacity waiting' =. course_totals members
        2 write 'dept';(>department);'courses';(#members);'enrolled';(fraction enrolled,capacity);'rate';(rate enrolled,capacity);'waitlisted';waiting
    end.
)
execute =: 3 : 0
    fields =. ' ' split y
    command =. 0{::fields
    args =. }.fields
    select. command
    case. 'COURSE' do.
        'code credits capacity timetable prereq' =. args
        if. (<code)e.CourseNames do. fail 'duplicate course';code return. end.
        texts =. 0$a:
        if. -.timetable-:'-' do. texts =. ',' split timetable end.
        slots =. 0 3$0
        for_text. texts do.
            text =. >text
            day =. DAYS i.<2{.text
            hh =. 0".2{.2}.text
            mm =. 0".2{.4}.text
            eh =. 0".2{.7}.text
            em =. 0".2{.9}.text
            start =. (60*hh)+mm
            finish =. (60*eh)+em
            if. (day=7)+.(hh>23)+.(mm>59)+.(eh>23)+.(em>59)+.start>:finish do. fail 'invalid slot';text return. end.
            slots =. slots,1 3$day,start,finish
        end.
        for_i. i.#slots do.
            for_j. (i+1)}.i.#slots do.
                if. (i{slots) overlaps j{slots do. fail 'overlapping slots';(i{::texts);j{::texts return. end.
            end.
        end.
        'valid normalized expression references' =. parse_prereq prereq
        if. -.valid do. fail 'invalid prereq';code return. end.
        if. (<code)e.references do. fail 'self prereq';code return. end.
        credits =. 0".credits
        capacity =. 0".capacity
        course =. code;credits;capacity;slots;normalized;expression;references;1;(i.0);i.0
        CourseNames =: CourseNames,<code
        Courses =: Courses,<course
        weekly =. +/(2{"1 slots)-1{"1 slots
        emit 'COURSE';code;'credits';credits;'capacity';capacity;'meetings';(#slots);'weekly';(clock weekly);'prereq';normalized
        i.0 return.
    case. 'STUDENT' do.
        'name year limit text' =. args
        if. (<name)e.StudentNames do. fail 'duplicate student';name return. end.
        records =. names =. 0$a:
        if. -.text-:'-' do.
            for_record. ',' split text do.
                'code grade credits' =. ':' split >record
                if. -.grade e.'ABCDF' do. fail 'invalid grade';name;code;grade return. end.
                if. (<code)e.names do. fail 'duplicate record';name;code return. end.
                records =. records,<code;grade;0".credits
                names =. names,<code
            end.
        end.
        s =. #Students
        student =. name;(0".year);(0".limit);records;<0$a:
        StudentNames =: StudentNames,<name
        Students =: Students,<student
        'earned gpa' =. grade_summary s
        emit 'STUDENT';name;'year';year;'limit';limit;'records';(#records);'earned';earned;'gpa';gpa
        i.0 return.
    case. 'STUDENTS' do.
        emit 'STUDENTS';#Students
        for_s. /:StudentNames do.
            student =. s{::Students
            2 write (s{::StudentNames);'year';('year' sg student);'credits';(fraction (enrolled_credits s),'limit' sg student);'courses';(#enrolled_courses s);'waitlists';#waiting_courses s
        end.
        i.0 return.
    case. 'REPORT' do. show_report '' return.
    end.
    if. (<command)e.;:'ENROLL CHECK OPTIONS DROP SWAP LIMIT SCHEDULE FREE AUDIT HISTORY' do.
        name =. 0{::args
        s =. StudentNames i.<name
        if. s=#Students do. fail 'unknown student';name return. end.
        student =. s{::Students
        select. command
        case. 'OPTIONS' do.
            emit 'OPTIONS';name;'courses';#Courses
            for_c. /:CourseNames do. 2 write (c{CourseNames),s judgment c end.
            i.0 return.
        case. 'SCHEDULE' do. show_schedule s return.
        case. 'FREE' do.
            day =. 1{::args
            d =. DAYS i.<day
            if. d=7 do. fail 'invalid day';day return. end.
            s show_free d
            i.0 return.
        case. 'AUDIT' do. show_audit s return.
        case. 'HISTORY' do.
            history =. 'history' sg student
            emit 'HISTORY';name;'events';#history
            for_event. history do. 2 write >event end.
            i.0 return.
        case. 'LIMIT' do.
            limit =. 0".1{::args
            credits =. enrolled_credits s
            if. limit<credits do. fail 'limit below enrolled';name;credits return. end.
            old =. 'limit' sg student
            s save_student ('limit';limit) ss student
            emit 'LIMIT';name;old;'->';limit
            promote ''
            i.0 return.
        end.
        code =. 1{::args
        c =. CourseNames i.<code
        if. c=#Courses do. fail 'unknown course';code return. end.
        course =. c{::Courses
        select. command
        case. 'CHECK' do. emit ('CHECK';name;code),s judgment c
        case. 'ENROLL' do.
            result =. s judgment c
            kind =. 0{::result
            if. kind-:'enroll' do.
                c save_course ('enrolled';('enrolled' cg course),s) cs course
                s add_history 'enroll ',code
                emit 'ENROLL' enrollment_line s,c
            elseif. kind-:'waitlist' do.
                position =. 1{::result
                waiting =. 'waiting' cg course
                waiting =. ((position-1){.waiting),s,(position-1)}.waiting
                c save_course ('waiting';waiting) cs course
                s add_history words 'waitlist';code;position
                emit 'ENROLL';name;code;'waitlist';position
            else. fail (0{result),(name;code),}.result end.
        case. 'DROP' do.
            if. s e.'enrolled' cg course do.
                c save_course ('enrolled';('enrolled' cg course)-.s) cs course
                s add_history 'drop ',code
                emit 'DROP' enrollment_line s,c
            elseif. s e.'waiting' cg course do.
                c save_course ('waiting';('waiting' cg course)-.s) cs course
                s add_history 'drop ',code,' waitlist'
                emit 'DROP';name;code;'waitlist removed'
            else. fail 'not registered';name;code return. end.
            promote ''
        case. 'SWAP' do.
            target =. 2{::args
            b =. CourseNames i.<target
            if. b=#Courses do. fail 'unknown course';target return. end.
            if. -.s e.'enrolled' cg course do. fail 'not enrolled';name;code return. end.
            if. c=b do. fail 'same course';code return. end.
            reason =. eligibility s,b,c
            if. #reason do. fail (0{reason),(name;target),}.reason return. end.
            dest =. b{::Courses
            if. (#'enrolled' cg dest)>:'capacity' cg dest do. fail 'course full';target return. end.
            c save_course ('enrolled';('enrolled' cg course)-.s) cs course
            b save_course ('enrolled';('enrolled' cg dest),s) cs dest
            s add_history words 'swap';code;target
            emit 'SWAP';name;code;'->';target;'credits';fraction (enrolled_credits s),'limit' sg student
            promote ''
        end.
        i.0 return.
    end.
    code =. 0{::args
    c =. CourseNames i.<code
    if. c=#Courses do. fail 'unknown course';code return. end.
    course =. c{::Courses
    select. command
    case. 'CLOSE';'OPEN' do.
        open =. command-:'OPEN'
        if. open='open' cg course do.
            reason =. 'already closed'
            if. open do. reason =. 'already open' end.
            fail reason;code return.
        end.
        c save_course ('open';open) cs course
        emit command;code;'enrolled';(fraction (#'enrolled' cg course),'capacity' cg course);'waitlist';#'waiting' cg course
        if. open do. promote '' end.
    case. 'CAPACITY' do.
        capacity =. 0".1{::args
        enrolled =. #'enrolled' cg course
        if. capacity<enrolled do. fail 'capacity below enrollment';code;enrolled return. end.
        old =. 'capacity' cg course
        c save_course ('capacity';capacity) cs course
        emit 'CAPACITY';code;old;'->';capacity
        promote ''
    case. 'PREREQ' do.
        'valid normalized expression references' =. parse_prereq 1{::args
        if. -.valid do. fail 'invalid prereq';code return. end.
        if. (<code)e.references do. fail 'self prereq';code return. end.
        course =. ('canonical';normalized) cs ('expression';<expression) cs ('references';<references) cs course
        emit 'PREREQ';code;normalized
        remaining =. i.0
        for_s. 'waiting' cg course do.
            if. s satisfies expression do. remaining =. remaining,s
            else.
                s add_history 'unlist ',code
                2 write 'UNLIST';(s{::StudentNames);code
            end.
        end.
        c save_course ('waiting';remaining) cs course
    case. 'CANCEL' do.
        enrolled =. 'enrolled' cg course
        waiting =. 'waiting' cg course
        emit 'CANCEL';code;'enrolled';(#enrolled);'waitlist';#waiting
        for_s. enrolled do. s add_history 'cancel ',code end.
        for_s. waiting do. s add_history 'cancel ',code,' waitlist' end.
        keep =. (i.#Courses)-.c
        Courses =: keep{Courses
        CourseNames =: keep{CourseNames
        promote ''
    case. 'ROSTER' do.
        enrolled =. 'enrolled' cg course
        waiting =. 'waiting' cg course
        emit 'ROSTER';code;(status course);'enrolled';(fraction (#enrolled),'capacity' cg course);'waitlist';#waiting
        for_s. (/:enrolled{StudentNames){enrolled do. 2 write 'enrolled';(s{::StudentNames);'year';'year' sg s{::Students end.
        for_i. i.#waiting do.
            s =. i{waiting
            2 write 'waitlist';(i+1);(s{::StudentNames);'year';'year' sg s{::Students
        end.
    case. 'INFO' do. show_info c
    end.
    i.0
)
main =: 3 : 0
    lines =. <;._2 (1!:1 3),LF
    for_line. (0".0{::lines){.}.lines do.
        CommandNumber =: CommandNumber+1
        execute >line
    end.
    i.0
)
main ''
