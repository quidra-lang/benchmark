LF =: 10{a.
BS =: '\'
Match =: 0{a.
Digits =: '0123456789'
Lower =: 'abcdefghijklmnopqrstuvwxyz'
Upper =: 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
NoTokens =: 0 2$a:
Lines =: 0$a:
Ids =: i.0
Current =: 0
Marks =: 26#0
Cut =: 0$a:
Pattern =: ''
Replacement =: ''
ReplacementSet =: 0
DisplayCount =: 5
Undo =: 0$a:
Redo =: 0$a:
FileNames =: 0$a:
Files =: 0$a:
NextId =: 1
Out =: 0$a:
Error =: ''

number =: 3 : 0
    text =. ,'0' 8!:2 |y
    if. y<0 do. '-',text else. text end.
)
join =: 4 : 0
    text =. ''
    for_i. i.#y do.
        if. i do. text =. text,x end.
        text =. text,i{::y
    end.
    text
)
emit =: 3 : '(y,LF) 1!:2 4'
add_line =: 3 : 'Out =: Out,<y'
fail =: 3 : 0
    Error =: y
    throw.
)
full_snapshot =: 3 : 'Lines;Ids;Current;Marks;Cut;Pattern;Replacement;ReplacementSet;DisplayCount;Undo;Redo;FileNames;Files;NextId'
restore =: 3 : '''Lines Ids Current Marks Cut Pattern Replacement ReplacementSet DisplayCount Undo Redo FileNames Files NextId'' =: y'
record =: 3 : 'y;Lines;Ids;Current'

digits_end =: 4 : 0
    i =. x
    while. i<#y do.
        if. -. (i{y)e.Digits do. break. end.
        i =. i+1
    end.
    i
)
delimited =: 3 : 0
    'source start delimiter' =. y
    text =. replacement =. ''
    i =. start
    while. i<#source do.
        ch =. i{source
        if. ch=BS do.
            i =. i+1
            if. i=#source do. fail 'missing delimiter' end.
            text =. text,i{source
            replacement =. replacement,i{source
        elseif. ch=delimiter do.
            text;replacement;((i-start){.start}.source);i+1 return.
        else.
            text =. text,ch
            if. ch='&' do. replacement =. replacement,Match
            else. replacement =. replacement,ch end.
        end.
        i =. i+1
    end.
    fail 'missing delimiter'
)
scan_address =: 3 : 0
    elements =. NoTokens
    i =. 0
    while. i<#y do.
        ch =. i{y
        if. ch e.Digits,'+-' do.
            start =. i
            i =. (i+1) digits_end y
            kind =. 'offset'
            if. ch e.Digits do. kind =. 'number' end.
            elements =. elements,kind;(i-start){.start}.y
        elseif. ch e.'.$,;%' do.
            elements =. elements,(,ch);''
            i =. i+1
        elseif. ch='''' do.
            i =. i+1
            word =. ''
            if. i<#y do.
                word =. ,i{y
                i =. i+1
            end.
            elements =. elements,'mark';word
        elseif. ch e.'/?' do.
            'word replacement raw next' =. delimited y;(i+1);ch
            elements =. elements,(,ch);word
            i =. next
        else. break. end.
    end.
    elements;i}.y
)
single_address =: 3 : 0
    if. 0=#y do. 0 return. end.
    kinds =. 0{"1 y
    if. -. ({.kinds)e.;:'number . $ mark / ? offset' do. 0 return. end.
    *./(}.kinds)=<'offset'
)
address_form =: 3 : 0
    if. 0=#y do. 0;NoTokens;'';<NoTokens return. end.
    if. (1=#y)*.('%'-:0{::,y) do.
        2;(1 2$('number';'1'));',';<1 2$('$';'') return.
    end.
    separators =. I.(0{"1 y)e.(',';';')
    if. 1<#separators do. fail 'bad address' end.
    if. 0=#separators do.
        if. -. single_address y do. fail 'bad address' end.
        1;y;'';<NoTokens return.
    end.
    index =. {.separators
    left =. index{.y
    right =. (index+1)}.y
    if. #left do.
        if. -. single_address left do. fail 'bad address' end.
    end.
    if. #right do.
        if. -. single_address right do. fail 'bad address' end.
    end.
    2;left;(0{::index{y);<right
)
positive_argument =: 3 : 0
    if. 0=#y do. _1 return. end.
    if. -. *./y e.Digits do. fail 'invalid suffix' end.
    value =. 0".y
    if. value=0 do. fail 'invalid suffix' end.
    value
)
print_suffix =: 3 : 0
    if. 0=#y do. y return. end.
    if. (1~:#y)+.-.*./y e.'pnl' do. fail 'invalid suffix' end.
    y
)
file_name =: 3 : 0
    if. ((#y)<2)+.(#y)>9 do. fail 'invalid file name' end.
    if. (' '~:{.y)+.-.*./(}.y)e.Lower,Digits do. fail 'invalid file name' end.
    }.y
)
is_sort =: 3 : '(y-:''sort'')+.(''sort ''-:5{.y)'
parse_substitution =: 3 : 0
    search =. replacement =. suffix =. ''
    previous =. 1
    flags =. y
    if. -. *./y e.'gpnl',Digits do.
        delimiter =. {.y
        if. delimiter e.' ',BS do. fail 'missing delimiter' end.
        'search unused raw next' =. delimited y;1;delimiter
        'unused replacement raw next' =. delimited y;next;delimiter
        previous =. raw-:'%'
        flags =. next}.y
    end.
    replace_all =. counted =. 0
    count =. 1
    i =. 0
    while. i<#flags do.
        ch =. i{flags
        i =. i+1
        if. ch='g' do.
            if. replace_all do. fail 'invalid suffix' end.
            replace_all =. 1
        elseif. ch e.'pnl' do.
            if. #suffix do. fail 'invalid suffix' end.
            suffix =. ,ch
        elseif. ch e.Digits do.
            if. counted do. fail 'invalid suffix' end.
            start =. i-1
            i =. i digits_end flags
            count =. 0".(i-start){.start}.flags
            if. count=0 do. fail 'invalid suffix' end.
            counted =. 1
        else. fail 'invalid suffix' end.
    end.
    search;replacement;previous;replace_all;suffix;count
)
parse_command =: 3 : 0
    kind =. argument =. suffix =. search =. replacement =. ''
    destination =. NoTokens
    previous =. replace_all =. 0
    count =. 1
    subcommand =. 0$a:
    if. is_sort y do.
        kind =. 'sort'
        if. -. y-:'sort' do.
            argument =. 5}.y
            if. (0=#argument)+.-.*./argument e.'ruin' do. fail 'invalid suffix' end.
            if. (#argument)~:#~.argument do. fail 'invalid suffix' end.
            if. ('i'e.argument)*.'n'e.argument do. fail 'invalid suffix' end.
        end.
    else.
        if. #y do. kind =. ,{.y end.
        argument =. 1}.y
        if. (0=#kind)+.(<kind)e.;:'a i c p n l = # y K h f' do.
            if. #argument do. fail 'invalid suffix' end.
        elseif. (<kind)e.;:'d x j J' do.
            suffix =. print_suffix argument
            argument =. ''
        elseif. (<kind)e.;:'z > < u' do.
            argument =. positive_argument argument
        elseif. kind-:'~' do.
            if. -. (<argument)e.('';'u';'l') do. fail 'invalid suffix' end.
        elseif. kind-:'r' do.
            if. *./argument e.Digits do.
                kind =. 'redo'
                argument =. positive_argument argument
            else.
                kind =. 'read'
                argument =. file_name argument
            end.
        elseif. kind-:'w' do.
            if. #argument do.
                kind =. 'write'
                argument =. file_name argument
            end.
        elseif. (<kind)e.;:'W e' do.
            argument =. file_name argument
        elseif. kind-:'k' do.
            if. (1~:#argument)+.-.*./argument e.Lower do. fail 'invalid mark' end.
        elseif. (<kind)e.;:'m t' do.
            'destination tail' =. scan_address argument
            if. -. single_address destination do. fail 'invalid destination' end.
            suffix =. print_suffix tail
            argument =. ''
        elseif. kind-:'s' do.
            'search replacement previous replace_all suffix count' =. parse_substitution argument
            argument =. ''
        elseif. (<kind)e.;:'g v' do.
            if. 0=#argument do. fail 'missing delimiter' end.
            if. ({.argument)e.' ',BS do. fail 'missing delimiter' end.
            'search unused raw next' =. delimited argument;1;{.argument
            tail =. next}.argument
            if. 0=#tail do. tail =. 'p' end.
            if. (-.({.tail)e.'pnldmtjJs><~aicx')+.is_sort tail do. fail 'invalid global command' end.
            subcommand =. parse_command tail
            argument =. ''
        else. fail 'unknown command' end.
    end.
    kind;argument;suffix;destination;search;replacement;previous;replace_all;count;<subcommand
)
has_text =: 3 : 0
    try.
        'elements command' =. scan_address y
        if. (<command)e.;:'a i c' do. 1 return. end.
        if. (#command)<2 do. 0 return. end.
        if. -.({.command)e.'gv' do. 0 return. end.
        if. (1{command)e.' ',BS do. 0 return. end.
        'search replacement raw next' =. delimited command;2;1{command
        (<next}.command)e.;:'a i c'
    catcht. 0 end.
)
address_kind =: 3 : 0
    kind =. 0{::y
    if. (<kind)e.;:'u redo h K f e' do. 0
    elseif. (<kind)e.;:'a i x = read k z' do. 1
    else. 2 end.
)
modifying =: 3 : 0
    kind =. 0{::y
    if. (<kind)e.;:'g v' do.
        -. (<0{::9{::y)e.;:'p n l'
    else. (<kind)e.;:'a i c d x j J m t s > < ~ sort read e' end.
)
choose_pattern =: 3 : 0
    if. #y do. Pattern =: y end.
    if. 0=#Pattern do. fail 'no previous pattern' end.
    Pattern
)
contains =: 4 : '+./x E.y'
address =: 3 : 0
    'kind word' =. {.y
    value =. Current
    first_offset =. 0
    last =. #Lines
    if. -. kind-:'offset' do.
        first_offset =. 1
        select. kind
        case. 'number' do. value =. 0".word
        case. '.' do. value =. Current
        case. '$' do. value =. last
        case. 'mark' do.
            if. (1~:#word)+.-.*./word e.Lower do. fail 'invalid mark' end.
            value =. Ids i.(Lower i.{.word){Marks
            if. value=last do. fail 'mark not set' end.
            value =. value+1
        case. do.
            pattern =. choose_pattern word
            value =. 0
            pivot =. Current
            if. (kind-:'?')*.Current=0 do. pivot =. last+1 end.
            for_step. 1+i.last do.
                if. kind-:'/' do. index =. last|pivot+step-1
                else. index =. last|(pivot-step)-1 end.
                if. pattern contains index{::Lines do.
                    value =. index+1
                    break.
                end.
            end.
            if. value=0 do. fail 'no match' end.
        end.
    end.
    for_element. first_offset}.y do.
        'kind word' =. element
        magnitude =. 1
        if. 1<#word do. magnitude =. 0".}.word end.
        if. '+'={.word do. value =. value+magnitude
        else. value =. value-magnitude end.
    end.
    value
)
addresses =: 3 : 0
    'count left separator right' =. y
    if. count=0 do. i.0 return. end.
    if. count=1 do. ,address left return. end.
    if. #left do. a =. address left
    elseif. separator-:',' do. a =. 1
    else. a =. Current end.
    if. separator-:';' do.
        if. (a<0)+.a>#Lines do. fail 'address out of range' end.
        Current =: a
    end.
    if. #right do. b =. address right else. b =. #Lines end.
    a,b
)
resolve_range =: 3 : 0
    'command values' =. y
    kind =. 0{::command
    arity =. address_kind command
    last =. #Lines
    if. arity=0 do. 0 0 return. end.
    if. arity=1 do.
        if. #values do. a =. {.values
        elseif. (<kind)e.;:'= read' do. a =. last
        elseif. kind-:'z' do. a =. Current+1
        else. a =. Current end.
        minimum =. (<kind)e.;:'k z'
        if. (a<minimum)+.a>last do. fail 'address out of range' end.
        a,a return.
    end.
    if. 1=#values do. a =. b =. {.values
    elseif. 2=#values do. 'a b' =. values
    elseif. (<kind)e.;:'w write W #' do. 1,last return.
    elseif. (<kind)e.;:'g v sort' do. a =. 1 [ b =. last
    elseif. (<kind)e.;:'j J' do. a =. Current [ b =. Current+1
    else. a =. b =. Current end.
    if. (a<1)+.(b<1)+.(a>last)+.b>last do. fail 'address out of range' end.
    if. (a>b)+.(a=b)*.(<kind)e.;:'j J' do. fail 'invalid range' end.
    a,b
)

contents =: 3 : 0
    'a b' =. y
    (1+b-a){.(a-1)}.Lines
)
new_lines =: 3 : 0
    identities =. NextId+i.#y
    NextId =: NextId+#y
    y;identities
)
replace =: 3 : 0
    'position count inserted identities' =. y
    Lines =: (position{.Lines),inserted,(position+count)}.Lines
    Ids =: (position{.Ids),identities,(position+count)}.Ids
)
print_line =: 3 : 0
    'index form' =. y
    text =. (index-1){::Lines
    if. form-:'n' do.
        label =. number index
        add_line ((0>.3-#label)#' '),label,' ',text
    elseif. form-:'l' do.
        text =. ((1+text=BS)#text),'$'
        while. 40<#text do.
            add_line (39{.text),BS
            text =. 39}.text
        end.
        add_line text
    else. add_line text end.
)
suffix_line =: 3 : 0
    suffix =. 2{::y
    if. (#suffix)*.Current>0 do. print_line Current;suffix end.
)
word_count =: 3 : 0
    mask =. y~:' '
    +/mask>0,}:mask
)
bytes =: 3 : '(#y)++/#&>y'
trim_left =: 3 : '((y='' '') i.0)}.y'
letter_case =: 4 : 0
    upper =. y e.Upper
    lower =. y e.Lower
    codes =. a.i.y
    if. x-:'u' do. codes =. codes-32*lower
    elseif. x-:'l' do. codes =. codes+32*upper
    else. codes =. codes+32*(upper-lower) end.
    a.{~codes
)
leading_integer =: 3 : 0
    negative =. '-'={.y
    finish =. negative digits_end y
    if. finish=negative do. 0 return. end.
    magnitude =. 0".(finish-negative){.negative}.y
    magnitude*1-2*negative
)
substitute =: 3 : 0
    'command range inside' =. y
    'kind argument suffix destination search replacement previous replace_all count subcommand' =. command
    pattern =. choose_pattern search
    if. previous do.
        if. -.ReplacementSet do. fail 'no previous substitution' end.
        replacement =. Replacement
    end.
    Replacement =: replacement
    ReplacementSet =: 1
    expanded =. ''
    for_ch. replacement do.
        if. ch=Match do. expanded =. expanded,pattern
        else. expanded =. expanded,ch end.
    end.
    'a b' =. range
    changed =. 0
    for_index. (a-1)+i.1+b-a do.
        original =. index{::Lines
        result =. ''
        position =. occurrence =. substituted =. 0
        while. 1 do.
            hits =. I.pattern E.position}.original
            if. 0=#hits do. break. end.
            found =. position+{.hits
            result =. result,(found-position){.position}.original
            occurrence =. occurrence+1
            if. (occurrence=count)+.replace_all*.occurrence>count do.
                result =. result,expanded
                substituted =. 1
            else. result =. result,pattern end.
            position =. found+#pattern
        end.
        if. -.substituted do. continue. end.
        result =. result,position}.original
        if. 80<#result do. fail 'line too long' end.
        if. 0=#result do. fail 'bad line' end.
        if. ' '={:result do. fail 'bad line' end.
        Lines =: (<result) index}Lines
        Current =: index+1
        changed =. changed+1
    end.
    if. (changed=0)*.-.inside do. fail 'no match' end.
    if. changed do. suffix_line command end.
    changed
)
execute =: 3 : 0
    'command range text inside' =. y
    'kind argument suffix destination search replacement previous replace_all count subcommand' =. command
    'a b' =. range
    indices =. (a-1)+i.0>.1+b-a
    select. kind
    case. '' do.
        print_line b;'p'
        Current =: b
    case. 'p';'n';'l' do.
        for_index. 1+indices do. print_line index;kind end.
        Current =: b
    case. 'z' do.
        if. argument~:_1 do. DisplayCount =: argument end.
        last =. (#Lines)<.a+DisplayCount-1
        for_index. a+i.1+last-a do. print_line index;'p' end.
        Current =: last
    case. '=' do. add_line number a
    case. '#' do.
        selected =. contents range
        add_line 'count lines=',(number #selected),' words=',(number +/word_count&>selected),' chars=',number +/#&>selected
    case. 'w' do.
        selected =. contents range
        for_line. selected do. add_line >line end.
        add_line 'lines=',(number #selected),' bytes=',number bytes selected
    case. 'a';'i' do.
        position =. a
        if. kind-:'i' do. position =. (a>.1)-1 end.
        'inserted identities' =. new_lines text
        replace position;0;inserted;identities
        Current =: position+#text
    case. 'c';'d' do.
        Cut =: contents range
        inserted =. 0$a:
        identities =. i.0
        if. kind-:'c' do. 'inserted identities' =. new_lines text end.
        replace (a-1);(#indices);inserted;identities
        if. #inserted do. Current =: a+(#inserted)-1
        else. Current =: a<.#Lines end.
    case. 'y' do. Cut =: contents range
    case. 'x' do.
        if. 0=#Cut do. fail 'nothing to put' end.
        'inserted identities' =. new_lines Cut
        replace a;0;inserted;identities
        Current =: a+#Cut
    case. 'm';'t' do.
        d =. address destination
        if. (d<0)+.d>#Lines do. fail 'address out of range' end.
        selected =. indices{Lines
        identities =. indices{Ids
        position =. d
        if. kind-:'m' do.
            if. (a<:d)*.d<b do. fail 'invalid destination' end.
            replace (a-1);(#indices);(0$a:);i.0
            if. d>:b do. position =. d-#indices end.
        else. 'selected identities' =. new_lines selected end.
        replace position;0;selected;identities
        Current =: position+#selected
    case. 'j';'J' do.
        selected =. contents range
        separator =. ''
        if. kind-:'J' do.
            selected =. ({.selected),trim_left&.>}.selected
            separator =. ' '
        end.
        joined =. separator join selected
        if. 80<#joined do. fail 'line too long' end.
        identity =. (a-1){Ids
        replace (a-1);(#indices);(<joined);,identity
        Current =: a
    case. '>';'<';'~' do.
        width =. argument
        if. -.kind-:'~' do.
            if. width=_1 do. width =. 4 end.
        end.
        for_index. indices do.
            line =. index{::Lines
            if. kind-:'>' do.
                if. 80<width+#line do. fail 'line too long' end.
                line =. (width#' '),line
            elseif. kind-:'<' do.
                line =. (width<.(line=' ') i.0)}.line
            else. line =. argument letter_case line end.
            Lines =: (<line) index}Lines
        end.
        Current =: b
    case. 'sort' do.
        selected =. contents range
        if. 'n'e.argument do. keys =. leading_integer&>selected
        else.
            key_text =. selected
            if. 'i'e.argument do. key_text =. 'l'&letter_case&.>selected end.
            keys =. s:key_text
        end.
        if. 'r'e.argument do. order =. \:keys else. order =. /:keys end.
        if. 'u'e.argument do.
            sorted_keys =. order{keys
            order =. (1,(}.sorted_keys)~:}:sorted_keys)#order
        end.
        replace (a-1);(#indices);(order{selected);order{indices{Ids
        Current =: a+(#order)-1
    case. 's' do. substitute command;range;inside return.
    case. 'k' do. Marks =: ((a-1){Ids) (Lower i.{.argument)}Marks
    case. 'K' do.
        parts =. 0$a:
        for_mark. i.26 do.
            index =. Ids i.mark{Marks
            if. index<#Ids do. parts =. parts,<((mark{Lower),'=',number index+1) end.
        end.
        if. #parts do. add_line 'marks ',' ' join parts else. add_line 'marks none' end.
    case. 'u';'redo' do.
        amount =. argument
        if. amount=_1 do. amount =. 1 end.
        if. kind-:'u' do.
            source =. Undo [ target =. Redo
            reason =. 'nothing to undo'
        else.
            source =. Redo [ target =. Undo
            reason =. 'nothing to redo'
        end.
        if. amount>#source do. fail reason end.
        for_i. i.amount do.
            saved =. >{:source
            source =. }:source
            target =. target,<record 0{::saved
            'Lines Ids Current' =: 1}.saved
        end.
        if. kind-:'u' do. Undo =: source [ Redo =: target
        else. Redo =: source [ Undo =: target end.
    case. 'h' do.
        add_line 'history undo=',(number #Undo),' redo=',number #Redo
        for_direction. i.2 do.
            if. direction do. history =. |.Redo [ label =. 'redo'
            else. history =. |.Undo [ label =. 'undo' end.
            for_i. i.#history do.
                add_line label,' ',(number i+1),': ',0{::i{::history
            end.
        end.
    case. 'g';'v' do.
        pattern =. choose_pattern search
        selected =. i.0
        for_index. indices do.
            if. (kind-:'g')=pattern contains index{::Lines do.
                selected =. selected,index{Ids
            end.
        end.
        if. 0=#selected do. fail 'no match' end.
        changed =. 0
        for_identity. selected do.
            index =. Ids i.identity
            if. index=#Ids do. continue. end.
            Current =: index+1
            subrange =. resolve_range subcommand;i.0
            changed =. changed+execute subcommand;subrange;text;1
        end.
        if. ('s'-:0{::subcommand)*.changed=0 do. fail 'no match' end.
    case. 'write';'W';'read';'e' do.
        index =. FileNames i.<argument
        if. (<kind)e.;:'write W' do.
            file =. contents range
            if. (kind-:'W')*.index<#FileNames do. file =. (index{::Files),file end.
            if. index=#FileNames do.
                FileNames =: FileNames,<argument
                Files =: Files,<file
            else. Files =: (<file) index}Files end.
        else.
            if. index=#FileNames do. fail 'no such file' end.
            file =. index{::Files
            'inserted identities' =. new_lines file
            if. kind-:'read' do.
                replace a;0;inserted;identities
                Current =: a+#file
            else.
                Lines =: inserted
                Ids =: identities
                Current =: #file
            end.
        end.
        add_line 'file ',argument,' lines=',(number #file),' bytes=',number bytes file
    case. 'f' do.
        parts =. 0$a:
        for_index. /:s:FileNames do.
            parts =. parts,<((index{::FileNames),'=',number #index{::Files)
        end.
        if. #parts do. add_line 'files ',' ' join parts else. add_line 'files none' end.
    end.
    if. (<kind)e.;:'d x j J m t' do. suffix_line command end.
    0
)
process =: 4 : 0
    saved =. full_snapshot ''
    before =. record x
    Out =: 0$a:
    try.
        'elements tail' =. scan_address x
        form =. address_form elements
        command =. parse_command tail
        count =. 0{::form
        arity =. address_kind command
        if. (arity=0)*.count>0 do. fail 'unexpected address' end.
        if. (arity=1)*.count=2 do. fail 'too many addresses' end.
        values =. addresses form
        range =. resolve_range command;values
        execute command;range;y;0
        if. 200<#Lines do. fail 'buffer full' end.
        if. modifying command do.
            Undo =: Undo,<before
            Redo =: 0$a:
        end.
    catcht.
        restore saved
        Out =: <'? ',Error
    end.
    Out
)
main =: 3 : 0
    input =. <;._2 (1!:1 3),LF
    i =. 0
    while. i<#input do.
        source =. i{::input
        i =. i+1
        if. source-:'Q' do. break. end.
        text =. 0$a:
        if. has_text source do.
            while. -.'.'-:i{::input do.
                text =. text,i{input
                i =. i+1
            end.
            i =. i+1
        end.
        for_line. source process text do. emit >line end.
    end.
)
main ''
