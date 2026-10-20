LF =: 10{a.
num =: 3 : ',''0'' 8!:2 y'
eq =: 4 : '(,x)-:,y'
split =: 4 : '<;._1 x,y'
join =: 4 : 0
    text =. ''
    for_i. i.#y do.
        if. i do. text =. text,x end.
        text =. text,i{::y
    end.
    text
)
words =: 3 : 0
    result =. 0$a:
    for_v. y do.
        v =. >v
        if. 2~:3!:0 v do. v =. num v end.
        result =. result,<,v
    end.
    ' 'join result
)
emit =: 3 : '1!:2&2 y,LF'
say =: 3 : 'emit words y'
parse =: 3 : '0".y'
FlagNames =: ;:'bold dim italic underline blink reverse hidden strike'
ModeNames =: ;:'IRM LNM DECCKM DECSCNM DECOM DECAWM DECTCEM DECKPAM BRACKETED'
InitialModes =: 0 0 0 0 0 1 1 0 0
Colors =: ;:'black red green yellow blue magenta cyan white'
Counters =: 10#0
bump =: 3 : 'Counters =: (>:y{Counters)y}Counters'
blank =: 3 : '(H,W)$32'
emptyAttrs =: 3 : '(H,W)$0'
reset =: 3 : 0
    Chars =: (blank'');<blank''
    CellAttrs =: (emptyAttrs'');<emptyAttrs''
    Alt =: 0
    Row =: 0
    Col =: 0
    Pending =: 0
    Modes =: InitialModes
    G0 =: 0
    G1 =: 0
    GL =: 0
    Shape =: 1
    Top =: 0
    Bottom =: H-1
    Tabs =: 8+8*i.<.W%8
    Tabs =: Tabs#~Tabs<W
    Saves =: 2#<i.0
    Back =: 0$a:
    HasTitle =: 0
    Title =: ''
    Last =: ''
    Pool =: <(8#0);'default';'default'
    Attr =: 0
    Parser =: 0
    Private =: ''
    Params =: ''
    Intermediate =: ''
    Osc =: ''
)
rowText =: 3 : 0
    text =. y{a.
    while. #text do.
        if. ' '~:{:text do. break. end.
        text =. }:text
    end.
    text
)
scroll =: 4 : 0
    for_k. i.y do.
        chars =. Alt{::Chars
        attrs =. Alt{::CellAttrs
        if. x do.
            removed =. Top{chars
            for_r. Top+i.Bottom-Top do.
                chars =. ((r+1){chars)r}chars
                attrs =. ((r+1){attrs)r}attrs
            end.
            chars =. (W#32)Bottom}chars
            attrs =. (W#0)Bottom}attrs
            if. (Alt=0)*.Top=0 do.
                Back =: Back,<rowText removed
                if. 100<#Back do. Back =: }.Back end.
            end.
        else.
            for_r. |.>:Top+i.Bottom-Top do.
                chars =. ((r-1){chars)r}chars
                attrs =. ((r-1){attrs)r}attrs
            end.
            chars =. (W#32)Top}chars
            attrs =. (W#0)Top}attrs
        end.
        Chars =: (<chars)Alt}Chars
        CellAttrs =: (<attrs)Alt}CellAttrs
    end.
)
lineFeed =: 3 : 0
    if. Row=Bottom do. 1 scroll 1
    elseif. Row<H-1 do. Row =: >:Row end.
)
reverseFeed =: 3 : 0
    if. Row=Top do. 0 scroll 1
    elseif. Row>0 do. Row =: <:Row end.
)
tab =: 3 : 0
    if. y do.
        stops =. Tabs#~Tabs<Col
        Col =: 0
        if. #stops do. Col =: >./stops end.
    else.
        stops =. Tabs#~Tabs>Col
        Col =: W-1
        if. #stops do. Col =: <./stops end.
    end.
)
address =: 3 : 0
    if. 4{Modes do. Bottom<.Top+y-1 else. (H-1)<.y-1 end.
)
home =: 3 : 0
    Row =: address 1
    Col =: 0
)
save =: 3 : 0
    Saves =: (<Row;Col;Attr;(4{Modes);G0;G1;GL)Alt}Saves
)
restore =: 3 : 0
    Pending =: 0
    s =. Alt{::Saves
    if. #s do.
        'Row Col Attr origin G0 G1 GL' =: s
        Modes =: origin 4}Modes
    else.
        Row =: 0
        Col =: 0
        Attr =: 0
        Modes =: 0 4}Modes
        G0 =: 0
        G1 =: 0
        GL =: 0
    end.
)
write =: 3 : 0
    bump 1
    Last =: ,y
    if. Pending do.
        Pending =: 0
        Col =: 0
        lineFeed''
    end.
    chars =. Alt{::Chars
    attrs =. Alt{::CellAttrs
    if. 0{Modes do.
        for_c. |.>:Col+i.(W-1)-Col do.
            chars =. ((<Row,c-1){chars)(<Row,c)}chars
            attrs =. ((<Row,c-1){attrs)(<Row,c)}attrs
        end.
    end.
    chars =. (a.i.{.y)(<Row,Col)}chars
    attrs =. Attr (<Row,Col)}attrs
    Chars =: (<chars)Alt}Chars
    CellAttrs =: (<attrs)Alt}CellAttrs
    if. Col<W-1 do. Col =: >:Col
    elseif. 5{Modes do. Pending =: 1 end.
)
print =: 3 : 0
    c =. ,y
    graphics =. G0
    if. GL do. graphics =. G1 end.
    if. graphics do.
        if. '`'eq c do. c =. '*'
        elseif. 'a'eq c do. c =. '#'
        elseif. ({.c)e.'jklmntuvw' do. c =. '+'
        elseif. 'q'eq c do. c =. '-'
        elseif. 'x'eq c do. c =. '|'
        elseif. '~'eq c do. c =. 'o' end.
    end.
    write c
)
control =: 3 : 0
    if. y e.8 9 10 11 12 13 do. Pending =: 0 end.
    select. y
    case. 7 do. bump 3
    case. 8 do. Col =: 0>.Col-1
    case. 9 do. tab 0
    case. 10;11;12 do.
        lineFeed''
        if. 1{Modes do. Col =: 0 end.
    case. 13 do. Col =: 0
    case. 14 do. GL =: 1
    case. 15 do. GL =: 0
    end.
)
esc =: 3 : 0
    key =. y
    if. 1=#key do. key =. {.key end.
    known =. '7';'8';'D';'E';'M';'H';'c';'=';'>';'\';'(0';'(B';')0';')B';'#8'
    if. -.(<key)e.known do. bump 6 return. end.
    if. (<key)e.'D';'E';'M';'c';'#8' do. Pending =: 0 end.
    select. key
    case. '7' do. save''
    case. '8' do. restore''
    case. 'D' do. lineFeed''
    case. 'E' do. Col =: 0
        lineFeed''
    case. 'M' do. reverseFeed''
    case. 'H' do. Tabs =: /:~~.Tabs,Col
    case. 'c' do. reset''
    case. '=' do. Modes =: 1 7}Modes
    case. '>' do. Modes =: 0 7}Modes
    case. '(0' do. G0 =: 1
    case. '(B' do. G0 =: 0
    case. ')0' do. G1 =: 1
    case. ')B' do. G1 =: 0
    case. '#8' do.
        Chars =: (<(H,W)$a.i.'E')Alt}Chars
        CellAttrs =: (<emptyAttrs'')Alt}CellAttrs
        Top =: 0
        Bottom =: H-1
        Modes =: 0 4}Modes
        Row =: 0
        Col =: 0
    end.
    bump 2
)
executeOsc =: 3 : 0
    if. (<2{.Osc)e.'0;';'2;' do.
        HasTitle =: 1
        Title =: 2}.Osc
        bump 2
    else. bump 6 end.
)
palette =: 3 : 0
    if. y<8 do. y{::Colors
    elseif. y<16 do. 'bright-',(y-8){::Colors
    else. num y end.
)
hexByte =: 3 : '((<.y%16),16|y){''0123456789abcdef'''
sgr =: 3 : 0
    'flags fg bg' =. Attr{::Pool
    ps =. y
    if. 0=#ps do. ps =. ,0 end.
    i =. 0
    while. i<#ps do.
        v =. i{ps
        if. v=0 do. flags =. 8#0 [ fg =. 'default' [ bg =. 'default'
        elseif. v e.1 2 3 4 5 7 8 9 do. flags =. 1 (1 2 3 4 5 7 8 9 i.v)}flags
        elseif. v=22 do. flags =. 0 (0 1)}flags
        elseif. v e.23 24 25 27 28 29 do. flags =. 0 (2+23 24 25 27 28 29 i.v)}flags
        elseif. (v>:30)*.v<:37 do. fg =. palette v-30
        elseif. (v>:90)*.v<:97 do. fg =. palette v-82
        elseif. (v>:40)*.v<:47 do. bg =. palette v-40
        elseif. (v>:100)*.v<:107 do. bg =. palette v-92
        elseif. v=39 do. fg =. 'default'
        elseif. v=49 do. bg =. 'default'
        elseif. v e.38 48 do.
            if. (i+2)<#ps do.
                if. (5=(i+1){ps)*.255>:(i+2){ps do.
                    color =. palette (i+2){ps
                    i =. i+2
                elseif. ((i+4)<#ps)*.2=(i+1){ps do.
                    rgb =. (i+2 3 4){ps
                    if. +./rgb>255 do. 0 return. end.
                    color =. '#',;hexByte&.><"0 rgb
                    i =. i+4
                else. 0 return. end.
            else. 0 return. end.
            if. v=38 do. fg =. color else. bg =. color end.
        else. 0 return. end.
        i =. >:i
    end.
    attrs =. flags;fg;bg
    index =. Pool i.<attrs
    if. index=#Pool do. Pool =: Pool,<attrs end.
    Attr =: index
    1
)
setModes =: 4 : 0
    dec =. '?'={.x
    setting =. 'h'={:x
    ps =. y
    if. 0=#ps do. ps =. ,0 end.
    allowed =. 4 20
    if. dec do. allowed =. 1 5 6 7 25 47 1047 1048 1049 2004 end.
    if. -.*./ps e.allowed do. 0 return. end.
    for_p. ps do.
        if. -.dec do. Modes =: setting (4 20 i.p)}Modes
        elseif. p e.1 5 7 25 2004 do.
            index =. (1 5 7 25 2004 i.p){2 3 5 6 8
            Modes =: setting index}Modes
            if. (p=7)*.-.setting do. Pending =: 0 end.
        elseif. p=6 do.
            Pending =: 0
            Modes =: setting 4}Modes
            home''
        elseif. p=1048 do.
            if. setting do. save'' else. restore'' end.
        else.
            Pending =: 0
            if. setting*.Alt=0 do.
                if. p=1049 do. save'' end.
                Alt =: 1
                if. p=1049 do.
                    Chars =: (<blank'')1}Chars
                    CellAttrs =: (<emptyAttrs'')1}CellAttrs
                end.
            elseif. (-.setting)*.Alt=1 do.
                if. p=1047 do.
                    Chars =: (<blank'')1}Chars
                    CellAttrs =: (<emptyAttrs'')1}CellAttrs
                end.
                Alt =: 0
                if. p=1049 do. restore'' end.
            end.
        end.
    end.
    1
)
reportedRow =: 3 : 0
    if. 4{Modes do. 1>.1+Row-Top else. >:Row end.
)
reply =: 3 : 0
    bump 4
    emit 'REPLY ',y
)
erase =: 3 : 0
    'r first last' =. y
    chars =. Alt{::Chars
    attrs =. Alt{::CellAttrs
    for_c. first+i.1+last-first do.
        chars =. 32 (<r,c)}chars
        attrs =. 0 (<r,c)}attrs
    end.
    Chars =: (<chars)Alt}Chars
    CellAttrs =: (<attrs)Alt}CellAttrs
)
up =: 3 : 0
    bound =. 0
    if. Row>:Top do. bound =. Top end.
    Row =: bound>.Row-y
)
down =: 3 : 0
    bound =. H-1
    if. Row<:Bottom do. bound =. Bottom end.
    Row =: bound<.Row+y
)
csi =: 4 : 0
    key =. x
    if. 1=#key do. key =. {.key end.
    ps =. y
    p =. 0 [ p2 =. 0
    if. #ps do. p =. {.ps end.
    if. 1<#ps do. p2 =. 1{ps end.
    n =. 1>.p
    known =. 'A';'B';'e';'C';'a';'D';'E';'F';'G';'`';'H';'f';'d';'I';'Z';'J';'K';'X';'@';'P';'L';'M';'S';'T';'b';'g';'m';'h';'l';'?h';'?l';' q';'r';'s';'u';'!p';'n';'?n';'c';'>c';'t';'$p';'?$p'
    if. -.(<key)e.known do. 6 return. end.
    if. ('J'eq key)*.p>3 do. 6 return. end.
    if. ('K'eq key)*.p>2 do. 6 return. end.
    if. ('g'eq key)*.-.p e.0 3 do. 6 return. end.
    if. (' q'eq key)*.p>6 do. 6 return. end.
    if. ('n'eq key)*.-.p e.5 6 do. 6 return. end.
    if. ('?n'eq key)*.p~:6 do. 6 return. end.
    if. ((<key)e.'c';'>c')*.p~:0 do. 6 return. end.
    if. ('t'eq key)*.p~:18 do. 6 return. end.
    if. 'm'eq key do. if. sgr ps do. 2 else. 6 end. return. end.
    if. (<key)e.'h';'l';'?h';'?l' do. if. key setModes ps do. 2 else. 6 end. return. end.
    if. 'r'eq key do.
        t =. p [ b =. p2
        if. t=0 do. t =. 1 end.
        if. b=0 do. b =. H end.
        b =. H<.b
        if. t>:b do. 9 return. end.
        Pending =: 0
        Top =: t-1
        Bottom =: b-1
        home''
        2 return.
    end.
    clearing =. 'A';'B';'C';'D';'E';'F';'G';'H';'I';'J';'K';'L';'M';'P';'S';'T';'X';'Z';'`';'a';'d';'e';'f';'@';'!p'
    if. (<key)e.clearing do. Pending =: 0 end.
    select. key
    case. 'A' do. up n
    case. 'B';'e' do. down n
    case. 'C';'a' do. Col =: (W-1)<.Col+n
    case. 'D' do. Col =: 0>.Col-n
    case. 'E' do. down n
        Col =: 0
    case. 'F' do. up n
        Col =: 0
    case. 'G';'`' do. Col =: (W-1)<.n-1
    case. 'H';'f' do.
        Row =: address n
        Col =: (W-1)<.(1>.p2)-1
    case. 'd' do. Row =: address n
    case. 'I';'Z' do. for_i. i.n do. tab 'Z'eq key end.
    case. 'J' do.
        if. p=3 do. Back =: 0$a:
        else.
            for_r. i.H do.
                if. (p=2)+.((p=0)*.r>Row)+.(p=1)*.r<Row do. erase r,0,W-1
                elseif. r=Row do.
                    first =. 0 [ last =. W-1
                    if. p=0 do. first =. Col end.
                    if. p=1 do. last =. Col end.
                    erase r,first,last
                end.
            end.
        end.
    case. 'K' do.
        first =. 0 [ last =. W-1
        if. p=0 do. first =. Col end.
        if. p=1 do. last =. Col end.
        erase Row,first,last
    case. 'X' do. erase Row,Col,((W-1)<.Col+n-1)
    case. '@';'P' do.
        chars =. Alt{::Chars [ attrs =. Alt{::CellAttrs
        cr =. Row{chars [ ar =. Row{attrs
        k =. n<.W-Col
        if. '@'eq key do.
            cr =. (Col{.cr),(k#32),(Col}.(-k)}.cr)
            ar =. (Col{.ar),(k#0),(Col}.(-k)}.ar)
        else.
            cr =. (Col{.cr),((Col+k)}.cr),k#32
            ar =. (Col{.ar),((Col+k)}.ar),k#0
        end.
        chars =. cr Row}chars [ attrs =. ar Row}attrs
        Chars =: (<chars)Alt}Chars [ CellAttrs =: (<attrs)Alt}CellAttrs
    case. 'L';'M' do.
        if. (Row>:Top)*.Row<:Bottom do.
            chars =. Alt{::Chars [ attrs =. Alt{::CellAttrs
            k =. n<.1+Bottom-Row
            for_i. i.k do.
                if. 'L'eq key do.
                    for_r. |.>:Row+i.Bottom-Row do.
                        chars =. ((r-1){chars)r}chars [ attrs =. ((r-1){attrs)r}attrs
                    end.
                    chars =. (W#32)Row}chars [ attrs =. (W#0)Row}attrs
                else.
                    for_r. Row+i.Bottom-Row do.
                        chars =. ((r+1){chars)r}chars [ attrs =. ((r+1){attrs)r}attrs
                    end.
                    chars =. (W#32)Bottom}chars [ attrs =. (W#0)Bottom}attrs
                end.
            end.
            Chars =: (<chars)Alt}Chars [ CellAttrs =: (<attrs)Alt}CellAttrs
            Col =: 0
        end.
    case. 'S';'T' do. ('S'eq key)scroll n<.1+Bottom-Top
    case. 'b' do. if. #Last do. for_i. i.n do. write Last end. end.
    case. 'g' do. if. p=3 do. Tabs =: i.0 else. Tabs =: Tabs-.Col end.
    case. ' q' do. Shape =: n
    case. 's' do. save''
    case. 'u' do. restore''
    case. '!p' do.
        Modes =: 0 (0 2 4 7)}Modes
        Modes =: 1 (5 6)}Modes
        Top =: 0 [ Bottom =: H-1 [ Attr =: 0
        G0 =: 0 [ G1 =: 0 [ GL =: 0
        Saves =: (<i.0)Alt}Saves
    case. 'n' do.
        if. p=5 do. reply '^[[0n'
        else. reply '^[[',(num reportedRow''),';',(num >:Col),'R' end.
    case. '?n' do. reply '^[[?',(num reportedRow''),';',(num >:Col),';1R'
    case. 'c' do. reply '^[[?1;2c'
    case. '>c' do. reply '^[[>0;95;0c'
    case. 't' do. reply '^[[8;',(num H),';',(num W),'t'
    case. '$p';'?$p' do.
        dec =. '?'={.key
        status =. 0
        if. dec do.
            if. p e.1 5 6 7 25 2004 do.
                index =. (1 5 6 7 25 2004 i.p){2 3 4 5 6 8
                status =. 2-index{Modes
            elseif. p e.47 1047 1049 do. status =. 2-Alt end.
        elseif. p e.4 20 do. status =. 2-(4 20 i.p){Modes end.
        prefix =. '^[['
        if. dec do. prefix =. prefix,'?' end.
        reply prefix,(num p),';',(num status),'$y'
    end.
    2
)
finishCsi =: 3 : 0
    fields =. 0$a:
    if. #Params do. fields =. ';'split Params end.
    if. 17<:#fields do. bump 9 return. end.
    values =. i.0
    for_f. fields do.
        v =. 0
        for_c. >f do. v =. 9999<.(10*v)+'0123456789'i.c end.
        values =. values,v
    end.
    result =. (Private,Intermediate,y)csi values
    bump result
)
feed =: 3 : 0
    bump 0
    n =. y
    if. n=27 do.
        if. Parser=7 do. executeOsc''
        elseif. Parser~:0 do. bump 8 end.
        Private =: '' [ Params =: '' [ Intermediate =: '' [ Osc =: ''
        Parser =: 1
        return.
    end.
    if. n e.24 26 do.
        if. Parser~:0 do. bump 8 [ Parser =: 0 end.
        return.
    end.
    if. n<32 do.
        if. Parser=7 do.
            if. n=7 do. executeOsc'' [ Parser =: 0 end.
        else. control n end.
        return.
    end.
    c =. ,n{a.
    intermediate =. n<:47
    final =. n>:64
    if. Parser=0 do. print c
    elseif. Parser=7 do. Osc =: Osc,c
    elseif. Parser=1 do.
        if. intermediate do. Intermediate =: Intermediate,c [ Parser =: 2
        elseif. '['eq c do. Parser =: 3
        elseif. ']'eq c do. Parser =: 7
        else. esc Intermediate,c
            Parser =: 0
        end.
    elseif. Parser=2 do.
        if. intermediate do. Intermediate =: Intermediate,c
        else. esc Intermediate,c
            Parser =: 0
        end.
    elseif. Parser=6 do.
        if. final do. bump 7 [ Parser =: 0 end.
    else.
        if. (Parser=3)*.n e.60 61 62 63 do. Private =: c [ Parser =: 4 return. end.
        if. Parser=3 do. Parser =: 4 end.
        if. Parser=4 do.
            if. ((n>:48)*.n<:57)+.';'eq c do. Params =: Params,c
            elseif. intermediate do. Intermediate =: Intermediate,c [ Parser =: 5
            elseif. final do. finishCsi c
                Parser =: 0
            else. Parser =: 6 end.
        elseif. Parser=5 do.
            if. intermediate do. Intermediate =: Intermediate,c
            elseif. final do. finishCsi c
                Parser =: 0
            else. Parser =: 6 end.
        end.
    end.
)
dump =: 3 : 0
    name =. 'main'
    if. Alt do. name =. 'alt' end.
    text =. words y;name;'cursor';((num >:Row),',',num >:Col);'scrollback';#Back
    if. Pending do. text =. text,' pending' end.
    emit text
    for_r. Alt{::Chars do. emit '|',rowText r end.
)
key =: 3 : 0
    name =. y
    arrows =. ;:'UP DOWN RIGHT LEFT HOME END'
    ai =. arrows i.<name
    enter =. '^M'
    if. 1{Modes do. enter =. '^M^J' end.
    if. ai<#arrows do.
        prefix =. '^[['
        if. 2{Modes do. prefix =. '^[O' end.
        sent =. prefix,ai{'ABCDHF'
    elseif. 'ENTER'eq name do. sent =. enter
    elseif. 'KPENTER'eq name do.
        sent =. enter
        if. 7{Modes do. sent =. '^[OM' end.
    elseif. (3=#name)*.'KP'eq 2{.name do.
        sent =. ,{:name
        if. 7{Modes do. sent =. '^[O',(112+'0123456789'i.{:name){a. end.
    else.
        names =. ;:'INSERT DELETE PAGEUP PAGEDOWN F1 F2 F3 F4 F5 F6 F7 F8 F9 F10 F11 F12 TAB BACKSPACE ESCAPE'
        strings =. '^[[2~';'^[[3~';'^[[5~';'^[[6~';'^[OP';'^[OQ';'^[OR';'^[OS';'^[[15~';'^[[17~';'^[[18~';'^[[19~';'^[[20~';'^[[21~';'^[[23~';'^[[24~';'^I';'^?';'^['
        sent =. (names i.<name){::strings
    end.
    say 'KEY';name;sent
)
attrText =: 3 : 0
    'flags fg bg' =. y{::Pool
    names =. flags#FlagNames
    if. -.'default'eq fg do. names =. names,<'fg=',fg end.
    if. -.'default'eq bg do. names =. names,<'bg=',bg end.
    ' 'join names
)
finish =: 3 : 0
    if. Parser~:0 do. bump 8 [ Parser =: 0 end.
    dump 'FINAL'
    if. HasTitle do. emit 'TITLE "',Title,'"' else. emit 'TITLE none' end.
    modes =. 0$a:
    for_i. i.9 do.
        if. (i{Modes)~:i{InitialModes do.
            v =. 'off'
            if. i{Modes do. v =. 'on' end.
            modes =. modes,<(i{::ModeNames),'=',v
        end.
    end.
    if. G0 do. modes =. modes,<'G0=graphics' end.
    if. G1 do. modes =. modes,<'G1=graphics' end.
    if. GL do. modes =. modes,<'GL=G1' end.
    if. Shape~:1 do. modes =. modes,<'CURSOR=',num Shape end.
    if. 0=#modes do. modes =. <'default' end.
    emit 'MODES ',' 'join modes
    emit 'REGION ',(num >:Top),'-',num >:Bottom
    stops =. 'none'
    if. #Tabs do. stops =. ','join num&.><"0 >:/:~Tabs end.
    emit 'TABS ',stops
    say 'SCROLLBACK';#Back
    for_s. (_5>. -#Back){.Back do. emit '|',>s end.
    runs =. 0$a:
    attrs =. Alt{::CellAttrs
    for_r. i.H do.
        c =. 0
        while. c<W do.
            first =. c
            id =. (<r,c){attrs
            while. c<W do.
                if. id~:(<r,c){attrs do. break. end.
                c =. >:c
            end.
            if. id~:0 do.
                runs =. runs,<words 'row';(>:r);'col';((num >:first),'-',num c);attrText id
            end.
        end.
    end.
    say 'ATTRS';#runs
    for_run. runs do. emit >run end.
    say 'BELL';3{Counters
    say 'REPLIES';4{Counters
    emit 'STATS bytes=',(num 0{Counters),' printed=',(num 1{Counters),' sequences=',num 2{Counters
    emit 'IGNORED ',(num +/6}.Counters),' unsupported=',(num 6{Counters),' malformed=',(num 7{Counters),' canceled=',(num 8{Counters),' invalid=',num 9{Counters
)
main =: 3 : 0
    lines =. <;._2 (1!:1 <'/dev/stdin'),LF
    'W H' =: parse 0{::lines
    reset''
    caret =. '@GHIJKLMNOXZ[^'
    codes =. 0 7 8 9 10 11 12 13 14 15 24 26 27 94
    for_line. }.lines do.
        line =. >line
        if. '%%END'eq line do. finish'' break.
        elseif. '%%DUMP'eq line do. bump 5
            dump 'DUMP ',num 5{Counters
        elseif. '%%KEY 'eq 6{.line do. key 6}.line
        elseif. '%%PASTE 'eq 8{.line do.
            text =. ''
            for_c. 8}.line do.
                text =. text,c
                if. c='^' do. text =. text,'^' end.
            end.
            if. 8{Modes do. text =. '^[[200~',text,'^[[201~' end.
            emit 'PASTE ',text
        else.
            i =. 0
            while. i<#line do.
                c =. i{line
                if. c='^' do.
                    i =. >:i
                    feed (caret i.i{line){codes
                else. feed a.i.c end.
                i =. >:i
            end.
        end.
    end.
)
main''
