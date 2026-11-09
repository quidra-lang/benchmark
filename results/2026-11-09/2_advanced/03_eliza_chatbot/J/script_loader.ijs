TextDirectives =: ;:'INITIAL FINAL DEFAULT QUESTION REPEAT'
GlobalDirectives =: TextDirectives,;:'QUIT STOP MEMSIZE PERSIST PRE POST SYNON'
RuleDirectives =: ;:'DECOMP MEMORY'
ItemDirectives =: ;:'REASM GOTO NEWKEY RESTATE'
MoveDirectives =: ;:'GOTO NEWKEY RESTATE'
Directives =: GlobalDirectives,(<'KEY'),RuleDirectives,ItemDirectives
is_word =: 3 : 0
    if. 0=#y do. 0 return. end.
    (*./y e.Lowercase,Digits,'''' )*.(-.({.y)='''')*.-.({:y)=''''
)
is_reference =: 3 : 0
    if. 3~:#y do. 0 return. end.
    ('('=0{y)*.(')'=2{y)*.(1{y)e.Digits
)
is_number =: 3 : '((#y)e.1 2)*.*./y e.Digits'
is_element =: 3 : 0
    if. (<y)e.;:'* #' do. 1 return. end.
    if. '@'={.y do. is_word }.y else. is_word y end.
)
well_formed =: 4 : 0
    count =. #y
    if. (<x)e.TextDirectives,<'REASM' do. count>0 return. end.
    select. x
    case. 'QUIT';'STOP' do. (count>0)*.*./is_word&>y
    case. 'MEMSIZE' do.
        if. count~:1 do. 0 return. end.
        if. -.is_number 0{::y do. 0 return. end.
        (num 0{::y)e.>:i.20
    case. 'PERSIST' do.
        if. count~:1 do. 0 return. end.
        (0{y)e.;:'cycles memory'
    case. 'PRE';'SYNON' do. (count>:2)*.*./is_word&>y
    case. 'POST' do.
        if. count<2 do. 0 return. end.
        is_word 0{::y
    case. 'KEY' do.
        if. count~:2 do. 0 return. end.
        (is_word 0{::y)*.is_number 1{::y
    case. 'DECOMP';'MEMORY' do. (count>0)*.*./is_element&>y
    case. 'GOTO' do.
        if. count~:1 do. 0 return. end.
        is_word 0{::y
    case. 'NEWKEY' do. count=0
    case. 'RESTATE' do.
        if. count<2 do. 0 return. end.
        (is_word 0{::y)*.*./(is_word&>}.y)+.is_reference&>}.y
    end.
)
add_diagnostic =: 3 : 0
    Diagnostics =: Diagnostics,<y
    i.0
)
load_script =: 3 : 0
    ScriptLines =: read_lines y
    Texts =: empty_table ''
    for_box. TextDirectives do. Texts =: (box,<0$a:) put_key Texts end.
    QuitWords =: StopWords =: Persist =: 0$a:
    Capacity =: 3
    Pres =: Posts =: Groups =: Keywords =: Rules =: Items =: Diagnostics =: 0$a:
    PreTable =: PostTable =: GroupWords =: FirstDefinitions =: empty_table ''
    KeywordWords =: 0$a:
    currentkeyword =. currentrule =. _1
    ignoring =. 0
    for_index. i.#ScriptLines do.
        line =. index{::ScriptLines
        if. 0=#line do. continue. end.
        if. '#'={.line do. continue. end.
        parts =. ' ' split line
        name =. 0{::parts
        args =. }.parts
        text =. ' ' join args
        if. (<name)e.GlobalDirectives,<'KEY' do.
            currentkeyword =. currentrule =. _1
            ignoring =. 0
        elseif. (<name)e.RuleDirectives,ItemDirectives do.
            if. ignoring do. continue. end.
            if. (<name)e.RuleDirectives do. currentrule =. _1 end.
        end.
        code =. message =. ''
        unique =. ''
        if. -.(<name)e.Directives do.
            code =. 'SYNTAX'
            message =. 'unknown directive ',name
        elseif. -.name well_formed args do.
            code =. 'SYNTAX'
            message =. 'bad arguments for ',name
        elseif. ((<name)e.RuleDirectives)*.currentkeyword=_1 do.
            code =. 'ORPHAN'
            message =. name,' without KEY'
        elseif. (name-:'REASM')*.currentrule=_1 do.
            code =. 'ORPHAN'
            message =. 'REASM without DECOMP or MEMORY'
        elseif. (<name)e.MoveDirectives do.
            orphan =. currentrule=_1
            if. -.orphan do. orphan =. 'MEMORY'-:0{::currentrule{::Rules end.
            if. orphan do.
                code =. 'ORPHAN'
                message =. name,' without DECOMP'
            end.
        end.
        if. 0=#code do.
            if. name-:'MEMSIZE' do. unique =. name
            elseif. (<name)e.;:'KEY SYNON PRE POST PERSIST' do. unique =. name,' ',0{::args end.
            if. #unique do.
                if. unique has_key FirstDefinitions do.
                    code =. 'DUPLICATE'
                    message =. unique,' first defined at line ',number unique get_key FirstDefinitions
                    if. name-:'KEY' do. ignoring =. 1 end.
                end.
            end.
        end.
        if. #code do.
            add_diagnostic (<index+1),(<code),<message
            continue.
        end.
        if. #unique do. FirstDefinitions =: ((<unique),<index+1) put_key FirstDefinitions end.
        if. (<name)e.TextDirectives do.
            Texts =: ((<name),<(name get_key Texts),<text) put_key Texts
        elseif. name-:'QUIT' do. QuitWords =: ~.QuitWords,args
        elseif. name-:'STOP' do. StopWords =: ~.StopWords,args
        elseif. name-:'MEMSIZE' do. Capacity =: num 0{::args
        elseif. name-:'PERSIST' do. Persist =: Persist,0{args
        elseif. (<name)e.;:'PRE POST' do.
            entry =. (0{args),(<}.args),<index+1
            if. name-:'PRE' do.
                Pres =: Pres,<entry
                PreTable =: ((0{args),<}.args) put_key PreTable
            else.
                Posts =: Posts,<entry
                PostTable =: ((0{args),<}.args) put_key PostTable
            end.
        elseif. name-:'SYNON' do.
            Groups =: Groups,<(0{args),(<~.args),<index+1
            GroupWords =: ((0{args),<~.args) put_key GroupWords
        elseif. name-:'KEY' do.
            currentkeyword =. #Keywords
            KeywordWords =: KeywordWords,0{args
            Keywords =: Keywords,<(0{args),(<num 1{::args),(<index+1),(<0$0),<0$0
        elseif. (<name)e.RuleDirectives do.
            currentrule =. #Rules
            Rules =: Rules,<(<name),(<args),(<index+1),<0$0
            field =. 4-'MEMORY'-:name
            keyword =. currentkeyword{::Keywords
            keyword =. (<(field{::keyword),currentrule) field}keyword
            Keywords =: (<keyword) currentkeyword}Keywords
        else.
            itemid =. #Items
            Items =: Items,<(<name),(<text),(<args),<index+1
            rule =. currentrule{::Rules
            rule =. (<(3{::rule),itemid) 3}rule
            Rules =: (<rule) currentrule}Rules
        end.
    end.
    i.0
)
