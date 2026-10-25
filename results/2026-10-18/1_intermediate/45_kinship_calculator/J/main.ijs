LF =: 10{a.
Scale =: 137438953472
SexLetters =: 'MFX'
Ids =: Names =: Parents =: 0$a:
Sex =: Birth =: Death =: Active =: i.0
Marriages =: 0 6$0
HistoryStates =: HistoryLines =: 0$a:
Modifying =: ;:'PERSON DEATH REMOVE PARENT UNPARENT SPOUSE DIVORCE'
TermKeys =: ;:'parent child sibling pibling nibling spouse late survivor ex stepparent stepchild stepsibling stepgrandparent stepgrandchild parent-in-law child-in-law sibling-in-law'
TermValues =: <;._2 (0 : 0)
father
mother
parent
son
daughter
child
brother
sister
sibling
uncle
aunt
pibling
nephew
niece
nibling
husband
wife
spouse
late husband
late wife
late spouse
widower
widow
surviving spouse
ex-husband
ex-wife
ex-spouse
stepfather
stepmother
stepparent
stepson
stepdaughter
stepchild
stepbrother
stepsister
stepsibling
stepgrandfather
stepgrandmother
stepgrandparent
stepgrandson
stepgranddaughter
stepgrandchild
father-in-law
mother-in-law
parent-in-law
son-in-law
daughter-in-law
child-in-law
brother-in-law
sister-in-law
sibling-in-law
)
Ordinals =: ;:'first second third fourth fifth sixth seventh eighth ninth tenth'
StepNames =: ;:'parent father mother child son daughter sibling brother sister spouse husband wife'
StepKinds =: 0 0 0 1 1 1 2 2 2 3 3 3
StepSexes =: _1 0 1 _1 0 1 _1 0 1 _1 0 1
Error =: ''

split =: 4 : '<;._1 x,y'
number =: 3 : ',''0'' 8!:2 y'
join =: 4 : 0
    result =. ''
    for_i. i.#y do.
        if. i do. result =. result,x end.
        result =. result,i{::y
    end.
    result
)
words =: 3 : 0
    fields =. 0$a:
    for_item. y do.
        item =. >item
        if. 2~:3!:0 item do. item =. number item end.
        fields =. fields,<item
    end.
    ' ' join fields
)
emit =: 3 : 'Output =: Output,<y'
say =: 3 : 'emit words y'
fail =: 3 : 0
    Error =: y
    throw.
)
save_state =: 3 : '(<Ids),(<Names),(<Sex),(<Birth),(<Death),(<Parents),(<Active),<Marriages'
restore =: 3 : '''Ids Names Sex Birth Death Parents Active Marriages'' =: y'
registered =: 3 : 'I.Active'
id_order =: 3 : '(/:s:y{Ids){y'
age_order =: 3 : 0
    ordered =. id_order y
    (/:ordered{Birth){ordered
)
find_person =: 3 : 0
    matches =. I.Active*.(Ids=<y)
    if. #matches do. {.matches else. _1 end.
)
person =: 3 : 0
    index =. find_person y
    if. index<0 do. fail 'UNKNOWN PERSON ',y end.
    index
)
parents =: 3 : 'y{::Parents'
children =: 3 : 'y{::Kids'
rebuild_children =: 3 : 0
    Kids =: (#Ids)$<i.0
    for_child. registered '' do.
        for_parent. parents child do.
            Kids =: (<(parent{::Kids),child) parent}Kids
        end.
    end.
)
common_parents =: 4 : '+/(parents x)e.parents y'
are_siblings =: 4 : '(x~:y)*.0<x common_parents y'
siblings =: 3 : 0
    result =. i.0
    for_x. registered '' do.
        if. x are_siblings y do. result =. result,x end.
    end.
    result
)
person_list =: 3 : 0
    if. 0=#y do. '-' else. ' ' join (age_order y){Ids end.
)
life_years =: 3 : 0
    text =. (number y{Birth),'-'
    if. (y{Death)>:0 do. text =. text,number y{Death end.
    text
)
records_of =: 3 : 'I.(y=0{"1 Marriages)+.y=1{"1 Marriages'
current_record =: 3 : 0
    records =. records_of y
    records =. records#~0=4{"1 records{Marriages
    if. #records do. {.records else. _1 end.
)
other =: 4 : 0
    row =. x{Marriages
    if. y=0{row do. 1{row else. 0{row end.
)
spouse =: 3 : 0
    record =. current_record y
    if. record<0 do. _1 else. record other y end.
)
last_record =: 4 : 0
    a =. 0{"1 Marriages
    b =. 1{"1 Marriages
    rows =. I.((a=x)*.b=y)+.((a=y)*.b=x)
    if. #rows do. {:rows else. _1 end.
)
partners =: 3 : 0
    seen =. result =. i.0
    for_record. |.records_of y do.
        who =. record other y
        if. who e.seen do. continue. end.
        seen =. seen,who
        if. 1~:4{record{Marriages do. result =. result,who end.
    end.
    result
)
step_related =: 4 : 0
    for_parent. x do.
        if. +./y e.partners parent do. 1 return. end.
    end.
    0
)

distances =: 4 : 0
    result =. (#Ids)#_1
    result =. 0 y}result
    queue =. ,y
    at =. 0
    while. at<#queue do.
        node =. at{queue
        at =. at+1
        if. x do. adjacent =. parents node else. adjacent =. children node end.
        for_next. adjacent do.
            if. (next{result)<0 do.
                result =. (1+node{result) next}result
                queue =. queue,next
            end.
        end.
    end.
    result
)
is_ancestor =: 4 : '(x~:y)*.0<x{1 distances y'
grandparents =: 3 : 'I.2=1 distances y'
apex =: 4 : 0
    upa =. 1 distances x
    upb =. 1 distances y
    if. (x{upb)>:0 do. x,0,(x{upb),0 return. end.
    if. (y{upa)>:0 do. y,(y{upa),0,0 return. end.
    shared =. I.(upa>:0)*.upb>:0
    if. 0=#shared do. i.0 return. end.
    ranks =. (id_order shared)i.shared
    order =. /:((shared{upa)+shared{upb),.(shared{upa),.ranks
    c =. ({.order){shared
    da =. c{upa
    db =. c{upb
    shares =. +/((shared{upa)=da)*.(shared{upb)=db
    c,da,db,shares
)
gendered =: 4 : '(y+3*TermKeys i.<x){::TermValues'
generation_prefix =: 3 : 0
    if. y=1 do. '' else. ((6*(y-2))$'great-'),'grand' end.
)
ordinal =: 3 : 0
    if. y<:10 do. (y-1){::Ordinals return. end.
    suffix =. 'th'
    if. -.(100|y)e.11 12 13 do.
        select. 10|y
        case. 1 do. suffix =. 'st'
        case. 2 do. suffix =. 'nd'
        case. 3 do. suffix =. 'rd'
        end.
    end.
    (number y),suffix
)
kinship_term =: 3 : 0
    'da db sex' =. y
    if. (da=0)*.db=0 do. 'self' return. end.
    if. da=0 do. (generation_prefix db),'parent' gendered sex return. end.
    if. db=0 do. (generation_prefix da),'child' gendered sex return. end.
    if. (da=1)*.db=1 do. 'sibling' gendered sex return. end.
    if. da=1 do. (generation_prefix db-1),'pibling' gendered sex return. end.
    if. db=1 do. (generation_prefix da-1),'nibling' gendered sex return. end.
    text =. (ordinal (da<.db)-1),' cousin'
    removed =. |da-db
    select. removed
    case. 0 do. text =. text
    case. 1 do. text =. text,' once removed'
    case. 2 do. text =. text,' twice removed'
    case. do. text =. text,' ',(number removed),' times removed'
    end.
    text
)
blood_term =: 4 : 0
    prefix =. ''
    if. (3{y)=1 do. prefix =. 'half-'
    elseif. (3{y)>:4 do. prefix =. 'double ' end.
    prefix,kinship_term (1 2{y),x
)
relationship =: 3 : 0
    'a b sex' =. y
    if. a=b do. <'self' return. end.
    terms =. 0$a:
    ap =. a apex b
    if. #ap do. terms =. terms,<sex blood_term ap end.
    record =. a last_record b
    if. record<0 do.
        for_child. registered '' do.
            if. *./(a,b)e.parents child do.
                terms =. terms,<'co-parent'
                break.
            end.
        end.
    else.
        row =. record{Marriages
        select. 4{row
        case. 0 do. terms =. terms,<'spouse' gendered sex
        case. 1 do. terms =. terms,<'ex' gendered sex
        case. 2 do.
            if. a=5{row do. kind =. 'late' else. kind =. 'survivor' end.
            terms =. terms,<kind gendered sex
        end.
    end.
    pa =. parents a
    pb =. parents b
    qa =. partners a
    qb =. partners b
    if. (-.a e.pb)*.+./pb e.qa do. terms =. terms,<'stepparent' gendered sex end.
    if. (-.b e.pa)*.+./pa e.qb do. terms =. terms,<'stepchild' gendered sex end.
    if. (0=a common_parents b)*.pa step_related pb do.
        terms =. terms,<'stepsibling' gendered sex
    end.
    if. (-.a is_ancestor b)*.+./(grandparents b)e.qa do.
        terms =. terms,<'stepgrandparent' gendered sex
    end.
    if. (-.b is_ancestor a)*.+./(grandparents a)e.qb do.
        terms =. terms,<'stepgrandchild' gendered sex
    end.
    for_q. qb do.
        if. a e.parents q do.
            terms =. terms,<'parent-in-law' gendered sex
            break.
        end.
    end.
    for_q. qa do.
        if. b e.parents q do.
            terms =. terms,<'child-in-law' gendered sex
            break.
        end.
    end.
    related =. 0
    for_q. qb do. related =. related+.a are_siblings q end.
    for_q. qa do. related =. related+.q are_siblings b end.
    if. related do. terms =. terms,<'sibling-in-law' gendered sex end.
    terms
)
relationship_text =: 4 : 0
    terms =. relationship x,y,x{Sex
    if. #terms do. ', ' join terms else. 'no relation' end.
)

reset_phi =: 3 : 'Phi =: ((#Ids),#Ids)$_1'
phi =: 4 : 0
    value =. (<x,y){Phi
    if. value>:0 do. value return. end.
    if. x=y do.
        value =. <.(Scale+inbreeding x)%2
    else.
        if. (x{Birth)>:y{Birth do. young =. x [ older =. y
        else. young =. y [ older =. x end.
        total =. 0
        for_parent. parents young do. total =. total+parent phi older end.
        value =. <.total%2
    end.
    Phi =: value (<x,y)}Phi
    Phi =: value (<y,x)}Phi
    value
)
inbreeding =: 3 : 0
    ps =. parents y
    if. 2=#ps do. ({.ps)phi{:ps else. 0 end.
)
fraction_text =: 3 : 0
    divisor =. y+.Scale
    (number <.y%divisor),'/',number <.Scale%divisor
)
upward_path =: 4 : 0
    result =. ,x
    while. (x{y)>0 do.
        ps =. parents x
        candidates =. ps#~(ps{y)=_1+x{y
        x =. {.id_order candidates
        result =. result,x
    end.
    result
)
census_status =: 4 : 0
    rs =. records_of x
    rs =. rs#~y>:2{"1 rs{Marriages
    if. 0=#rs do. 'single' return. end.
    record =. {:rs
    row =. record{Marriages
    if. ((3{row)<0)+.(3{row)>y do.
        'married ',(record other x){::Ids
    elseif. (4{row)=1 do. 'divorced'
    else. 'widowed' end.
)
step_targets =: 4 : 0
    select. x
    case. 0 do. parents y
    case. 1 do. children y
    case. 2 do. siblings y
    case. 3 do.
        who =. spouse y
        if. who<0 do. i.0 else. ,who end.
    end.
)
tree_visit =: 3 : 0
    'who depth' =. y
    indent =. (2*(depth+1))#' '
    if. who{TreeSeen do.
        emit indent,(who{::Ids),' (see above)'
        return.
    end.
    TreeSeen =: 1 who}TreeSeen
    text =. indent,(who{::Ids),' ',(who{::Names),' ',life_years who
    partner =. spouse who
    if. partner>:0 do. text =. text,' = ',partner{::Ids end.
    emit text
    for_child. age_order children who do. tree_visit child,depth+1 end.
)
pedigree_enter =: 3 : 0
    'who k generation depth' =. y
    indent =. (2*(generation+1))#' '
    text =. indent,(number k),' ',(who{::Ids),' ',(who{::Names),' ',life_years who
    PedLines =: PedLines,<text
    PedSeen =: 1 who}PedSeen
    if. generation<depth do.
        ps =. id_order parents who
        ps =. (/:ps{Sex){ps
        for_i. i.#ps do.
            pedigree_enter (i{ps),((2*k)+i),(generation+1),depth
        end.
    end.
)

modify =: 4 : 0
    select. x
    case. 'PERSON' do.
        ident =. 0{::y
        if. (find_person ident)>:0 do. fail 'DUPLICATE PERSON ',ident end.
        sex =. SexLetters i.{.1{::y
        year =. 0".2{::y
        name =. 3{::y
        Ids =: Ids,<ident
        Names =: Names,<name
        Sex =: Sex,sex
        Birth =: Birth,year
        Death =: Death,_1
        Parents =: Parents,<i.0
        Active =: Active,1
        say 'ADDED';ident;name;(sex{SexLetters);year
    case. 'DEATH' do.
        who =. person 0{::y
        ident =. who{::Ids
        year =. 0".1{::y
        if. (who{Death)>:0 do. fail 'ALREADY DECEASED ',ident end.
        if. year<who{Birth do. fail 'BAD YEAR ',ident end.
        for_record. records_of who do.
            row =. record{Marriages
            if. (year<2{row)+.year<3{row do. fail 'BAD YEAR ',ident end.
        end.
        late =. children who
        late =. id_order late#~(late{Birth)>year+1
        if. #late do. fail 'AFTER DEATH ',(({.late){::Ids),' ',ident end.
        Death =: year who}Death
        record =. current_record who
        text =. 'DIED ',ident,' ',number year
        if. record>:0 do.
            row =. record{Marriages
            row =. year 3}row
            row =. 2 4}row
            row =. who 5}row
            Marriages =: row record}Marriages
            text =. text,' spouse=',(record other who){::Ids
        end.
        emit text
    case. 'REMOVE' do.
        who =. person 0{::y
        ident =. who{::Ids
        for_child. registered '' do.
            ps =. parents child
            Parents =: (<ps#~ps~:who) child}Parents
        end.
        Parents =: (<i.0) who}Parents
        keep =. I.-.((who=0{"1 Marriages)+.who=1{"1 Marriages)
        Marriages =: keep{Marriages
        Active =: 0 who}Active
        emit 'REMOVED ',ident
    case. 'PARENT' do.
        child =. person 0{::y
        parent =. person 1{::y
        childid =. child{::Ids
        parentid =. parent{::Ids
        pair =. childid,' ',parentid
        if. child=parent do. fail 'SAME PERSON ',childid end.
        if. parent e.parents child do. fail 'ALREADY PARENT ',pair end.
        if. 2=#parents child do. fail 'TOO MANY PARENTS ',childid end.
        if. child is_ancestor parent do. fail 'CYCLE ',pair end.
        if. (12+parent{Birth)>child{Birth do. fail 'AGE GAP ',pair end.
        if. ((parent{Death)>:0)*.(1+parent{Death)<child{Birth do. fail 'AFTER DEATH ',pair end.
        Parents =: (<(parents child),parent) child}Parents
        emit 'LINKED ',pair,' ','parent' gendered parent{Sex
    case. 'UNPARENT' do.
        child =. person 0{::y
        parent =. person 1{::y
        pair =. (child{::Ids),' ',parent{::Ids
        ps =. parents child
        if. -.parent e.ps do. fail 'NOT PARENT ',pair end.
        Parents =: (<ps#~ps~:parent) child}Parents
        emit 'UNLINKED ',pair
    case. 'SPOUSE' do.
        a =. person 0{::y
        b =. person 1{::y
        year =. 0".2{::y
        pair =. (a{::Ids),' ',b{::Ids
        if. a=b do. fail 'SAME PERSON ',a{::Ids end.
        for_who. a,b do.
            if. (who{Death)>:0 do. fail 'DECEASED ',who{::Ids end.
        end.
        for_who. a,b do.
            if. (spouse who)>:0 do. fail 'ALREADY MARRIED ',who{::Ids end.
        end.
        if. (a is_ancestor b)+.(b is_ancestor a)+.a are_siblings b do. fail 'CLOSE KIN ',pair end.
        for_who. a,b do.
            if. year<16+who{Birth do. fail 'TOO YOUNG ',who{::Ids end.
        end.
        for_who. a,b do.
            for_record. records_of who do.
                if. year<:3{record{Marriages do. fail 'BAD YEAR ',who{::Ids end.
            end.
        end.
        Marriages =: Marriages,1 6$a,b,year,_1,0,_1
        say 'MARRIED';(a{::Ids);(b{::Ids);year
    case. 'DIVORCE' do.
        a =. person 0{::y
        b =. person 1{::y
        year =. 0".2{::y
        pair =. (a{::Ids),' ',b{::Ids
        if. b~:spouse a do. fail 'NOT MARRIED ',pair end.
        record =. current_record a
        row =. record{Marriages
        if. year<:2{row do. fail 'BAD YEAR ',a{::Ids end.
        row =. year 3}row
        row =. 1 4}row
        Marriages =: row record}Marriages
        say 'DIVORCED';(a{::Ids);(b{::Ids);year
    end.
)

query =: 4 : 0
    cmd =. x
    if. -.(<cmd)e.;:'UNDO CENSUS TERM STATS AUDIT' do.
        who =. person 0{::y
        ident =. who{::Ids
    end.
    select. cmd
    case. 'UNDO' do.
        if. 0=#HistoryStates do. fail 'NOTHING TO UNDO' end.
        line =. _1{::HistoryLines
        restore _1{::HistoryStates
        HistoryStates =: }:HistoryStates
        HistoryLines =: }:HistoryLines
        emit 'UNDONE ',line
    case. 'INFO' do.
        reset_phi ''
        say 'INFO';ident;(who{::Names);((who{Sex){SexLetters);life_years who
        emit '  parents: ',person_list parents who
        for_record. records_of who do.
            row =. record{Marriages
            years =. (number 2{row),'-'
            if. (3{row)>:0 do. years =. years,number 3{row end.
            status =. (4{row){::;:'current divorced widowed'
            emit '  marriage: ',((record other who){::Ids),' ',years,' ',status
        end.
        emit '  children: ',person_list children who
        emit '  siblings: ',person_list siblings who
        emit '  inbreeding: ',fraction_text inbreeding who
    case. 'RELATION';'KINSHIP';'PATH';'COMMON' do.
        a =. who
        b =. person 1{::y
        pair =. (a{::Ids),' ',b{::Ids
        select. cmd
        case. 'RELATION' do. emit 'RELATION ',pair,': ',a relationship_text b
        case. 'KINSHIP' do.
            reset_phi ''
            emit 'KINSHIP ',pair,' ',fraction_text a phi b
        case. 'PATH' do.
            ap =. a apex b
            if. 0=#ap do. emit 'PATH ',pair,' none' return. end.
            depths =. 0 distances {.ap
            route =. (a upward_path depths),|.}:b upward_path depths
            emit 'PATH ',pair,' ',(number +/1 2{ap),': ',' ' join route{Ids
        case. 'COMMON' do.
            ua =. 1 distances a
            ub =. 1 distances b
            shared =. I.(ua>:0)*.ub>:0
            nearest =. i.0
            for_c. shared do.
                if. -.+./(children c)e.shared do. nearest =. nearest,c end.
            end.
            nearest =. id_order nearest
            nearest =. (/:((nearest{ua)+nearest{ub)){nearest
            say 'COMMON';(a{::Ids);(b{::Ids);#nearest
            for_c. nearest do. emit '  ',words (c{::Ids);(c{ua);c{ub end.
        end.
    case. 'RELATIVES';'WHO' do.
        entries =. 0$a:
        question =. ' ' join }.y
        for_otherperson. id_order registered '' do.
            if. otherperson=who do. continue. end.
            terms =. relationship otherperson,who,otherperson{Sex
            if. cmd-:'RELATIVES' do.
                if. #terms do.
                    entries =. entries,<'  ',(otherperson{::Ids),': ',(', ' join terms)
                end.
            else.
                neutral =. relationship otherperson,who,2
                for_i. i.#terms do.
                    if. (question-:i{::terms)+.question-:i{::neutral do.
                        entries =. entries,<'  ',(otherperson{::Ids),': ',i{::terms
                        break.
                    end.
                end.
            end.
        end.
        if. cmd-:'WHO' do. say 'WHO';ident;question;#entries
        else. say 'RELATIVES';ident;#entries end.
        for_entry. entries do. emit >entry end.
    case. 'ANCESTORS';'DESCENDANTS' do.
        ds =. (cmd-:'ANCESTORS') distances who
        matches =. id_order I.ds>0
        matches =. (/:matches{ds){matches
        say cmd;ident;#matches
        for_relative. matches do.
            g =. relative{ds
            if. cmd-:'ANCESTORS' do. term =. kinship_term 0,g,relative{Sex
            else. term =. kinship_term g,0,relative{Sex end.
            emit '  ',words g;(relative{::Ids);term
        end.
    case. 'COUSINS' do.
        degree =. 0".1{::y
        matches =. removals =. i.0
        terms =. 0$a:
        for_relative. id_order registered '' do.
            if. relative=who do. continue. end.
            ap =. relative apex who
            if. 0=#ap do. continue. end.
            da =. 1{ap
            db =. 2{ap
            if. ((da<.db)>:2)*.degree=(da<.db)-1 do.
                matches =. matches,relative
                removals =. removals,|da-db
                terms =. terms,<(relative{Sex)blood_term ap
            end.
        end.
        order =. /:removals
        say 'COUSINS';ident;degree;#matches
        for_i. order do. emit '  ',((i{matches){::Ids),' ',i{::terms end.
    case. 'SIBLINGS' do.
        entries =. 0$a:
        earlier =. 0
        ordered =. age_order registered ''
        rank =. ordered i.who
        for_relative. ordered do.
            if. relative=who do. continue. end.
            shared =. who common_parents relative
            if. shared=2 do. kind =. 'full'
            elseif. shared=1 do. kind =. 'half'
            elseif. (parents who)step_related parents relative do. kind =. 'step'
            else. continue. end.
            if. shared>0 do. earlier =. earlier+(ordered i.relative)<rank end.
            entries =. entries,<'  ',words (relative{::Ids);kind;relative{Birth
        end.
        emit 'SIBLINGS ',ident,' ',(number #entries),' order=',number earlier+1
        for_entry. entries do. emit >entry end.
    case. 'GENERATIONS' do.
        ds =. 0 distances who
        generations =. ~.ds#~ds>0
        generations =. /:~generations
        say 'GENERATIONS';ident;#generations
        for_g. generations do.
            members =. I.ds=g
            years =. members{Birth
            living =. +/0>members{Death
            span =. (number <./years),'-',number >./years
            emit '  ',words g;(#members);living;span
        end.
    case. 'TREE' do.
        say 'TREE';ident;+/0<0 distances who
        TreeSeen =: (#Ids)#0
        tree_visit who,0
    case. 'PEDIGREE' do.
        depth =. 0".1{::y
        PedLines =: 0$a:
        PedSeen =: (#Ids)#0
        pedigree_enter who,1,0,depth
        emit 'PEDIGREE ',ident,' ',(number depth),' entries=',(number #PedLines),' distinct=',number +/PedSeen
        for_line. PedLines do. emit >line end.
    case. 'TIMELINE' do.
        events =. 1 3$(who{Birth),0,_1
        texts =. <'born'
        for_record. records_of who do.
            row =. record{Marriages
            counterpart =. record other who
            events =. events,1 3$(2{row),1,counterpart
            texts =. texts,<'married ',counterpart{::Ids
            if. 1=4{row do.
                events =. events,1 3$(3{row),3,counterpart
                texts =. texts,<'divorced ',counterpart{::Ids
            elseif. (2=4{row)*.counterpart=5{row do.
                events =. events,1 3$(3{row),4,counterpart
                texts =. texts,<'widowed ',counterpart{::Ids
            end.
        end.
        cs =. children who
        for_child. cs do.
            events =. events,1 3$(child{Birth),2,child
            texts =. texts,<'child ',child{::Ids
        end.
        for_kind. 0 1 do.
            if. kind=0 do. relatives =. parents who [ label =. 'parent'
            else. relatives =. cs [ label =. 'child' end.
            for_relative. relatives do.
                death =. relative{Death
                if. (death<0)+.death<who{Birth do. continue. end.
                if. ((who{Death)>:0)*.death>who{Death do. continue. end.
                events =. events,1 3$death,5,relative
                texts =. texts,<'lost ',label,' ',relative{::Ids
            end.
        end.
        if. (who{Death)>:0 do.
            events =. events,1 3$(who{Death),6,_1
            texts =. texts,<'died'
        end.
        ordered =. id_order registered ''
        ranks =. (#Ids)#0
        ranks =. (i.#ordered) ordered}ranks
        keys =. 0 3$0
        for_event. events do.
            counterpart =. 2{event
            rank =. 0
            if. counterpart>:0 do. rank =. 1+counterpart{ranks end.
            keys =. keys,1 3$(0{event),(1{event),rank
        end.
        say 'TIMELINE';ident;#events
        for_i. /:keys do. emit '  ',(number 0{i{events),' ',i{::texts end.
    case. 'CENSUS' do.
        year =. 0".0{::y
        residents =. I.Active*.(Birth<:year)*.((Death<0)+.Death>year)
        residents =. age_order residents
        say 'CENSUS';year;#residents
        for_resident. residents do.
            emit '  ',words (resident{::Ids);(year-resident{Birth);resident census_status year
        end.
    case. 'FIND' do.
        route =. 1{::y
        current =. ,who
        for_step. '.' split route do.
            index =. StepNames i.step
            kind =. index{StepKinds
            sex =. index{StepSexes
            collected =. i.0
            for_member. current do. collected =. collected,kind step_targets member end.
            current =. ~.collected
            if. sex>:0 do. current =. current#~sex=current{Sex end.
        end.
        current =. id_order current#~current~:who
        say 'FIND';ident;route;#current
        for_relative. current do.
            emit '  ',(relative{::Ids),': ',relative relationship_text who
        end.
    case. 'TERM' do.
        da =. 0".0{::y
        db =. 0".1{::y
        sex =. SexLetters i.{.2{::y
        say 'TERM';da;db;(sex{SexLetters);kinship_term da,db,sex
    case. 'STATS' do.
        all =. registered ''
        living =. +/0>all{Death
        links =. +/#&>all{Parents
        couples =. +/0=4{"1 Marriages
        founders =. +/0=#&>all{Parents
        heights =. (#Ids)#0
        for_member. age_order all do.
            height =. 1+>./0,(parents member){heights
            heights =. height member}heights
        end.
        longest =. >./0,all{heights
        emit 'STATS persons=',(number #all),' living=',(number living),' links=',(number links),' couples=',(number couples),' founders=',(number founders),' generations=',number longest
    case. 'AUDIT' do.
        entries =. 0$a:
        for_record. i.#Marriages do.
            row =. record{Marriages
            a =. 0{row
            b =. 1{row
            ap =. a apex b
            if. #ap do.
                entries =. entries,<'  marriage ',(a{::Ids),' ',(b{::Ids),' ',(a{Sex)blood_term ap
            end.
        end.
        reset_phi ''
        for_member. id_order registered '' do.
            value =. inbreeding member
            if. value~:0 do.
                entries =. entries,<'  inbred ',(member{::Ids),' ',fraction_text value
            end.
        end.
        say 'AUDIT';#entries
        for_entry. entries do. emit >entry end.
    end.
)

execute =: 3 : 0
    line =. y
    fields =. ' ' split line
    cmd =. 0{::fields
    args =. }.fields
    Output =: 0$a:
    rebuild_children ''
    saved =. save_state ''
    changing =. (<cmd)e.Modifying
    try.
        if. changing do.
            cmd modify args
            HistoryStates =: HistoryStates,<saved
            HistoryLines =: HistoryLines,<line
        else.
            cmd query args
        end.
    catcht.
        if. changing do. restore saved end.
        Output =: <'ERROR ',Error
    end.
    Output
)
main =: 3 : 0
    count =. 0".1!:1 3
    for_i. i.count do.
        output =. execute 1!:1 3
        for_line. output do. ((>line),LF) 1!:2 4 end.
    end.
    i.0
)
main ''
