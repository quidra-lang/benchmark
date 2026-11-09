LF =: 10{a.
DQ =: '"'
White =: ' ',LF
Letters =: 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
Punctuation =: ((33+i.94){a.) -. Letters
TocMarker =: (9{a.),'toc',9{a.
num =: 3 : ',''0'' 8!:2 y'
join =: 4 : '(#x) }. ; (<x) ,&.> y'
lower =: 3 : '(''abcdefghijklmnopqrstuvwxyz'',a.) {~ (''ABCDEFGHIJKLMNOPQRSTUVWXYZ'',a.) i.y'
starts =: 4 : 0
    if. (#x)>#y do. 0 return. end.
    (,x)-:(#x){.y
)
trim =: 3 : 0
    while. #y do. if. ' '~:{.y do. break. end. y=.}.y end.
    while. #y do. if. ' '~:{:y do. break. end. y=.}:y end.
    y
)
ltrim =: 3 : 0
    while. #y do. if. ' '~:{.y do. break. end. y=.}.y end.
    y
)
split =: 4 : 0
    parts=.0$a:
    part=.''
    for_c. y do.
        if. c=x do.
            parts=.parts,<part
            part=.''
        else. part=.part,c end.
    end.
    parts,<part
)
findAt =: 4 : 0
    'start needle'=.y
    hits=.I. needle E. start}.x
    if. #hits do. start+{.hits else. #x end.
)
htmlEscape =: 3 : 0
    out=.''
    for_c. y do.
        select. c
        case. '&' do. out=.out,'&amp;'
        case. '<' do. out=.out,'&lt;'
        case. '>' do. out=.out,'&gt;'
        case. '"' do. out=.out,'&quot;'
        case. do. out=.out,c
        end.
    end.
    out
)
stripTags =: 3 : 0
    out=.''
    at=.0
    while. at<#y do.
        if. '<'=at{y do.
            close=.y findAt (at+1);'>'
            if. close<#y do. at=.close+1 continue. end.
        end.
        out=.out,at{y
        at=.at+1
    end.
    out
)
normalize =: 3 : 0
    out=.''
    pending=.0
    for_c. lower y do.
        if. c e.White do. pending=.0<#out
        else.
            if. pending do. out=.out,' ' end.
            out=.out,c
            pending=.0
        end.
    end.
    out
)
skipSpace =: 4 : 0
    while. y<#x do.
        if. -. (y{x) e.White do. break. end.
        y=.y+1
    end.
    y
)
escapedRead =: 4 : 0
    'at stops'=.y
    out=.''
    while. at<#x do.
        if. (at{x) e.stops do. break. end.
        if. ('\'=at{x) *. (at+1)<#x do.
            if. ((at+1){x) e.Punctuation do. at=.at+1 end.
        end.
        out=.out,at{x
        at=.at+1
    end.
    out;at
)
runEnd =: 4 : 0
    finish=.y+1
    while. finish<#x do.
        if. (finish{x)~:y{x do. break. end.
        finish=.finish+1
    end.
    finish
)
fence =: 3 : 0
    if. 0=#y do. 0$a: return. end.
    if. -. ({.y) e.'`~' do. 0$a: return. end.
    finish=.y runEnd 0
    if. finish<3 do. 0$a: return. end.
    info=.trim finish}.y
    if. ('`'={.y) *. '`' e.info do. 0$a: return. end.
    (finish{.y);info
)
atx =: 3 : 0
    if. 0=#y do. 0$a: return. end.
    if. '#'~:{.y do. 0$a: return. end.
    n=.y runEnd 0
    if. n>6 do. 0$a: return. end.
    if. n<#y do. if. ' '~:n{y do. 0$a: return. end. end.
    text=.trim n}.y
    finish=.#text
    while. finish>0 do.
        if. '#'~:(finish-1){text do. break. end.
        finish=.finish-1
    end.
    if. finish=0 do. text=.''
    elseif. ' '=(finish-1){text do. text=.trim finish{.text end.
    n;text
)
rule =: 3 : 0
    compact=.y-.' '
    if. 3>#compact do. 0 return. end.
    (({.compact) e.'-*_') *. *./compact={.compact
)
marker =: 3 : 0
    if. (2>#y) +. rule y do. 0$a: return. end.
    ordered=.0
    number=.1
    finish=.0
    if. ({.y) e.'-*+' do. finish=.1
    else.
        while. finish<#y do.
            if. -. (finish{y) e.'0123456789' do. break. end.
            finish=.finish+1
        end.
        if. (finish=0) +. (finish>9) +. finish=#y do. 0$a: return. end.
        if. -. (finish{y) e.'.)' do. 0$a: return. end.
        number=.0".finish{.y
        ordered=.1
        finish=.finish+1
    end.
    if. finish=#y do. 0$a: return. end.
    if. ' '~:finish{y do. 0$a: return. end.
    ((finish-1){y);ordered;number;(y skipSpace finish)}.y
)
interrupts =: 3 : 0
    if. 0=#y do. 0 return. end.
    if. ' '={.y do. 0 return. end.
    (0<#fence y) +. (0<#atx y) +. (rule y) +. ('>'={.y) +. 0<#marker y
)
splitCells =: 3 : 0
    text=.trim y
    at=.'|' starts text
    parts=.0$a:
    cell=.''
    separator=.0
    while. at<#text do.
        ch=.at{text
        at=.at+1
        separator=.0
        if. ('\'=ch) *. at<#text do.
            if. '|'~:at{text do. cell=.cell,'\' end.
            cell=.cell,at{text
            at=.at+1
        elseif. ch='|' do.
            parts=.parts,<trim cell
            cell=.''
            separator=.1
        else. cell=.cell,ch end.
    end.
    if. -.separator do. parts=.parts,<trim cell end.
    parts
)
alignment =: 3 : 0
    left=.':' starts y
    right=.0
    if. #y do. right=.':'={:y end.
    middle=.left}.y
    if. right *. 0<#middle do. middle=.}:middle end.
    if. (0=#middle) +. -. *./middle='-' do. 0;'' return. end.
    1;((2*left)+right){::'';'right';'left';'center'
)

Blocks=:0$a:
RefNames=:RefValues=:FootNames=:FootBodies=:0$a:
newBlock =: 3 : 0
    b=.(<y),(<'') , (<0),(<0),(<0$a:),(<i.0),(<0$a:),(<0$a:),<0$a:
    Blocks=:Blocks,<b
    <:#Blocks
)
setBlock =: 4 : 0
    'id slot'=.x
    b=.id{::Blocks
    b=.(<y) slot}b
    Blocks=:(<b) id}Blocks
)
definition =: 3 : 0
    if. -. '[' starts y do. 0 return. end.
    close=.y findAt 0;']'
    if. close=#y do. 0 return. end.
    if. -. ':' starts (close+1)}.y do. 0 return. end.
    label=.(close-1){.}.y
    body=.trim (close+2)}.y
    if. ('^' starts label) *. (1<#label) *. (0<#body) *. *./(}.label) e.Letters,'-_' do.
        name=.lower }.label
        if. -. (<name) e.FootNames do.
            FootNames=:FootNames,<name
            FootBodies=:FootBodies,<body
        end.
        1 return.
    end.
    if. ('[' e.label) +. (0=#trim label) +. '^' starts label do. 0 return. end.
    'url finish'=.y escapedRead (y skipSpace close+2);' '
    if. 0=#url do. 0 return. end.
    at=.y skipSpace finish
    hasTitle=.0
    title=.''
    if. at<#y do.
        if. (at=finish) +. -. (at{y) e.DQ,'''' do. 0 return. end.
        'title finish'=.y escapedRead (at+1);at{y
        if. finish~:<:#y do. 0 return. end.
        hasTitle=.1
    end.
    name=.normalize label
    if. -. (<name) e.RefNames do.
        RefNames=:RefNames,<name
        RefValues=:RefValues,<url;hasTitle;title
    end.
    1
)
parseBlocks =: 3 : 0
    result=.i.0
    at=.0
    while. at<#y do.
        line=.at{::y
        if. 0=#line do. at=.at+1 continue. end.
        if. '    ' starts line do.
            finish=.at
            while. finish<#y do.
                row=.finish{::y
                if. (0<#row) *. -. '    ' starts row do. break. end.
                finish=.finish+1
            end.
            while. 0=#(finish-1){::y do. finish=.finish-1 end.
            b=.newBlock 'code'
            code=.(4&}.)&.> (finish-at){.at}.y
            (b,4) setBlock code
            result=.result,b
            at=.finish
            continue.
        end.
        if. ' '~:{.line do.
            f=.fence line
            if. #f do.
                'run info'=.f
                b=.newBlock 'code'
                (b,1) setBlock (info i.' '){.info
                code=.0$a:
                at=.at+1
                while. at<#y do.
                    row=.at{::y
                    at=.at+1
                    if. ((#row)>:#run) *. *./row={.run do. break. end.
                    code=.code,<row
                end.
                (b,4) setBlock code
                result=.result,b
                continue.
            end.
            heading=.atx line
            if. #heading do.
                'level text'=.heading
                b=.newBlock 'heading'
                (b,1) setBlock text
                (b,2) setBlock level
                result=.result,b
                at=.at+1
                continue.
            end.
            if. rule line do.
                result=.result,newBlock 'rule'
                at=.at+1
                continue.
            end.
            if. '>'={.line do.
                content=.0$a:
                while. at<#y do.
                    if. -. '>' starts at{::y do. break. end.
                    row=.}.at{::y
                    if. ' ' starts row do. row=.}.row end.
                    content=.content,<row
                    at=.at+1
                end.
                alerts=.'[!NOTE]';'[!TIP]';'[!IMPORTANT]';'[!WARNING]';'[!CAUTION]'
                b=.newBlock 'quote'
                if. ({.content) e.alerts do.
                    (b,0) setBlock 'alert'
                    (b,1) setBlock }:2}.0{::content
                    content=.}.content
                end.
                (b,5) setBlock parseBlocks content
                result=.result,b
                continue.
            end.
            m=.marker line
            if. #m do.
                'kind ordered number body'=.m
                b=.newBlock 'list'
                (b,2) setBlock number
                (b,3) setBlock ordered
                items=.0$a:
                while. 1 do.
                    content=.,<body
                    at=.at+1
                    while. at<#y do.
                        if. -. '  ' starts at{::y do. break. end.
                        content=.content,<2}.at{::y
                        at=.at+1
                    end.
                    items=.items,<parseBlocks content
                    following=.at
                    while. following<#y do.
                        if. #following{::y do. break. end.
                        following=.following+1
                    end.
                    next=.0$a:
                    if. following<#y do. next=.marker following{::y end.
                    if. 0=#next do. break. end.
                    if. (kind~:0{::next) +. ordered~:1{::next do. break. end.
                    at=.following
                    body=.3{::next
                end.
                (b,6) setBlock items
                result=.result,b
                continue.
            end.
            if. definition line do. at=.at+1 continue. end.
            if. (at+1)<#y do.
                if. ('|' e.line) *. '|' e.(at+1){::y do.
                    header=.splitCells line
                    delimiters=.splitCells (at+1){::y
                    valid=.(#header)=#delimiters
                    aligns=.0$a:
                    for_cell. delimiters do.
                        'ok align'=.alignment >cell
                        valid=.valid *. ok
                        aligns=.aligns,<align
                    end.
                    if. valid do.
                        b=.newBlock 'table'
                        (b,4) setBlock header
                        (b,7) setBlock aligns
                        rows=.0$a:
                        at=.at+2
                        while. at<#y do.
                            if. -. '|' e.at{::y do. break. end.
                            row=.splitCells at{::y
                            row=.(#header){.row,(#header)#<''
                            rows=.rows,<row
                            at=.at+1
                        end.
                        (b,8) setBlock rows
                        result=.result,b
                        continue.
                    end.
                end.
            end.
        end.
        finish=.at+1
        level=.0
        while. finish<#y do.
            row=.finish{::y
            if. 0=#row do. break. end.
            if. (3<:#row) *. ((*./row='=') +. *./row='-') do.
                level=.1+'-'={.row
                break.
            end.
            if. interrupts row do. break. end.
            finish=.finish+1
        end.
        text=.LF join ltrim&.>(finish-at){.at}.y
        kind=.'paragraph'
        if. level do. kind=.'heading' elseif. text-:'[TOC]' do. kind=.'toc' end.
        b=.newBlock kind
        (b,1) setBlock text
        (b,2) setBlock level
        result=.result,b
        at=.finish+0<level
    end.
    result
)

piece =: 3 : 'y;'''';0;0;0'
emphasis =: 3 : 0
    'pieces first last'=.y
    out=.''
    at=.first
    while. at<last do.
        'html ch count opens closes'=.at{::pieces
        close=.last
        if. opens do.
            for_i. (at+1)+i.last-(at+1) do.
                'h c n o cl'=.i{::pieces
                if. cl *. (c-:ch) *. n=count do. close=.i break. end.
            end.
        end.
        if. close<last do.
            opening=.'<del>'
            closing=.'</del>'
            if. -.ch-:'~' do.
                opening=.(count-1){::'<em>' ; '<strong>' ; '<em><strong>'
                closing=.(count-1){::'</em>' ; '</strong>' ; '</strong></em>'
            end.
            inside=.emphasis (<pieces),(<at+1),<close
            out=.out,opening,inside,closing
            at=.close+1
        else.
            if. count do. out=.out,count#ch else. out=.out,html end.
            at=.at+1
        end.
    end.
    out
)
tickCloser =: 4 : 0
    'at count'=.y
    while. at<#x do.
        if. '`'=at{x do.
            finish=.x runEnd at
            if. count=finish-at do. at return. end.
            at=.finish
        else. at=.at+1 end.
    end.
    #x
)
closingBracket =: 4 : 0
    at=.y
    depth=.0
    while. at<#x do.
        ch=.at{x
        if. ch='\' do. at=.at+2 continue. end.
        if. ch='`' do.
            finish=.x runEnd at
            close=.x tickCloser finish;finish-at
            if. close=#x do. at=.finish else. at=.close+finish-at end.
            continue.
        end.
        if. ch='[' do. depth=.depth+1
        elseif. ch=']' do.
            depth=.depth-1
            if. depth=0 do. at return. end.
        end.
        at=.at+1
    end.
    #x
)
email =: 3 : 0
    parts=.'@' split y
    if. 2~:#parts do. 0 return. end.
    user=.0{::parts
    if. (0=#user) +. -. *./user e.Letters,'.+-_' do. 0 return. end.
    domain=.'.' split 1{::parts
    if. 2>#domain do. 0 return. end.
    for_part. domain do.
        text=.>part
        if. (0=#text) +. -. *./text e.Letters,'-' do. 0 return. end.
    end.
    1
)
destination =: 4 : 0
    'at label'=.y
    if. '[' starts at}.x do.
        close=.x findAt (at+1);']'
        if. close<#x do.
            raw=.(close-(at+1)){.(at+1)}.x
            if. -. '[' e.raw do.
                if. 0=#raw do. raw=.label end.
                index=.RefNames i.<normalize raw
                if. index=#RefNames do. 0$a: return. end.
                (<index{::RefValues),<close+1 return.
            end.
        end.
    elseif. '(' starts at}.x do.
        'url finish'=.x escapedRead (x skipSpace at+1);White,')'
        next=.x skipSpace finish
        hasTitle=.0
        title=.''
        valid=.1
        if. (next>finish) *. next<#x do.
            if. (next{x) e.DQ,'''' do.
                'title finish'=.x escapedRead (next+1);next{x
                hasTitle=.1
                valid=.finish<#x
                next=.x skipSpace finish+1
            end.
        end.
        if. valid *. ')' starts next}.x do.
            (<url;hasTitle;title),<next+1 return.
        end.
    end.
    index=.RefNames i.<normalize label
    if. index=#RefNames do. 0$a: else. (<index{::RefValues),<at end.
)
UsedIds=:HeadingIds=:HeadingLabels=:NoteNames=:0$a:
HeadingLevels=:NoteCounts=:i.0
referenceId =: 3 : 0
    'number count'=.y
    out=.'fnref-',num number
    if. count>1 do. out=.out,'-',num count end.
    out
)
noteReference =: 3 : 0
    index=.NoteNames i.<y
    if. index=#NoteNames do.
        NoteNames=:NoteNames,<y
        NoteCounts=:NoteCounts,0
    end.
    NoteCounts=:(1+index{NoteCounts) index}NoteCounts
    n=.num index+1
    id=.referenceId (index+1),index{NoteCounts
    '<sup id="',id,'"><a href="#fn-',n,'">',n,'</a></sup>'
)
inline =: 3 : 0
    'text links notes'=.y
    pieces=.0$a:
    at=.0
    while. at<#text do.
        ch=.at{text
        if. ch='\' do.
            if. (at+1)<#text do.
                next=.(at+1){text
                if. next e.Punctuation do.
                    pieces=.pieces,<piece htmlEscape ,next
                    at=.at+2
                    continue.
                elseif. next=LF do.
                    pieces=.pieces,<piece '<br />',LF
                    at=.at+2
                    continue.
                end.
            end.
            pieces=.pieces,<piece '\'
            at=.at+1
            continue.
        end.
        if. ch='`' do.
            finish=.text runEnd at
            count=.finish-at
            close=.text tickCloser finish;count
            if. close=#text do.
                pieces=.pieces,<piece count#'`'
                at=.finish
            else.
                code=.(close-finish){.finish}.text
                code=.' ' (I.code=LF)}code
                if. (0<#trim code) *. (' ' starts code) do.
                    if. ' '={:code do. code=.}.}:code end.
                end.
                pieces=.pieces,<piece '<code>',(htmlEscape code),'</code>'
                at=.close+count
            end.
            continue.
        end.
        if. links *. ch='<' do.
            close=.text findAt (at+1);'>'
            if. close<#text do.
                target=.(close-(at+1)){.(at+1)}.text
                href=.''
                clean=.-.+./target e.White,'<'
                if. clean *. ((('http://' starts target) *. 7<#target) +. ('https://' starts target) *. 8<#target) do.
                    href=.target
                elseif. email target do. href=.'mailto:',target end.
                if. #href do.
                    pieces=.pieces,<piece '<a href="',(htmlEscape href),'">',(htmlEscape target),'</a>'
                    at=.close+1
                    continue.
                end.
            end.
        end.
        preceding=.1
        if. at>0 do. preceding=.(at-1){text e.White,'*_~(' end.
        if. links *. preceding *. (('http://' starts at}.text) +. 'https://' starts at}.text) do.
            finish=.at
            while. finish<#text do.
                if. (finish{text) e.White,'<' do. break. end.
                finish=.finish+1
            end.
            while. finish>at do.
                if. -. ((finish-1){text) e.'.,:;!?*_~)' do. break. end.
                finish=.finish-1
            end.
            url=.(finish-at){.at}.text
            if. -. (<url) e.'http://';'https://' do.
                escaped=.htmlEscape url
                pieces=.pieces,<piece '<a href="',escaped,'">',escaped,'</a>'
                at=.finish
                continue.
            end.
        end.
        if. (ch='[') +. (ch='!') *. '[' starts (at+1)}.text do.
            if. links *. notes *. '[^' starts at}.text do.
                close=.text findAt (at+2);']'
                if. close<#text do.
                    name=.lower (close-(at+2)){.(at+2)}.text
                    if. (<name) e.FootNames do.
                        pieces=.pieces,<piece noteReference name
                        at=.close+1
                        continue.
                    end.
                end.
            end.
            image=.ch='!'
            if. image +. links do.
                opening=.at+image
                close=.text closingBracket opening
                if. close<#text do.
                    label=.(close-(opening+1)){.(opening+1)}.text
                    dest=.text destination (close+1);label
                    if. #dest do.
                        'reference finish'=.dest
                        'url hasTitle title'=.reference
                        content=.inline label;0;0
                        attr=.''
                        if. hasTitle do. attr=.' title="',(htmlEscape title),'"' end.
                        url=.htmlEscape url
                        if. image do. html=.'<img src="',url,'" alt="',(stripTags content),'"',attr,' />'
                        else. html=.'<a href="',url,'"',attr,'>',content,'</a>' end.
                        pieces=.pieces,<piece html
                        at=.finish
                        continue.
                    end.
                end.
            end.
        end.
        if. ch e.'*_~' do.
            finish=.text runEnd at
            count=.finish-at
            before=.' '
            after=.' '
            if. at>0 do. before=.(at-1){text end.
            if. finish<#text do. after=.finish{text end.
            opens=.-.after e.White
            closes=.-.before e.White
            if. (ch='_') *. (before e.Letters) *. after e.Letters do. opens=.closes=.0 end.
            if. ((ch~:'~') *. count<:3) +. (ch='~') *. count=2 do.
                pieces=.pieces,<'';ch;count;opens;closes
            else. pieces=.pieces,<piece count#ch end.
            at=.finish
            continue.
        end.
        pieces=.pieces,<piece htmlEscape ,ch
        at=.at+1
    end.
    emphasis (<pieces),(<0),<#pieces
)
headingHtml =: 3 : 0
    'level text'=.y
    hits=.I.' {#' E.text
    id=.''
    if. (#hits) *. 0<#text do.
        if. '}'={:text do.
            at=.{:hits
            candidate=.}: (at+3)}.text
            if. (0<#candidate) *. *./candidate e.Letters,'-_' do.
                id=.candidate
                text=.trim at{.text
            end.
        end.
    end.
    if. 0=#id do.
        lowered=.lower text
        base=.lowered#~lowered e.'abcdefghijklmnopqrstuvwxyz0123456789-_',White
        base=.'-' (I.base e.White)}base
        if. 0=#base do. base=.'heading' end.
        id=.base
        suffix=.1
        while. (<id) e.UsedIds do.
            id=.base,'-',num suffix
            suffix=.suffix+1
        end.
    end.
    UsedIds=:UsedIds,<id
    html=.inline text;1;1
    HeadingLevels=:HeadingLevels,level
    HeadingIds=:HeadingIds,<id
    HeadingLabels=:HeadingLabels,<stripTags html
    n=.num level
    '<h',n,' id="',id,'">',html,'</h',n,'>'
)
renderSequence =: 3 : 0
    html=.''
    for_id. y do. html=.html,(renderBlock id),LF end.
    html
)
renderItem =: 3 : 0
    html=.'<li>'
    for_id. y do.
        b=.id{::Blocks
        if. 'paragraph'-:0{::b do.
            text=.1{::b
            if. (id_index=0) *. 4<#text do.
                if. (<4{.text) e.'[ ] ';'[x] ';'[X] ' do.
                    checked=.''
                    if. ' '~:1{text do. checked=.' checked=""' end.
                    html=.html,'<input type="checkbox"',checked,' disabled="" /> '
                    text=.4}.text
                end.
            end.
            html=.html,inline text;1;1
        else.
            if. LF~:{:html do. html=.html,LF end.
            html=.html,(renderBlock id),LF
        end.
    end.
    html,'</li>'
)
tableRow =: 3 : 0
    'tag aligns cells'=.y
    lines=.0$a:
    for_cell. cells do.
        align=.cell_index{::aligns
        style=.''
        if. #align do. style=.' style="text-align:',align,'"' end.
        content=.inline (>cell);1;1
        lines=.lines,<'<',tag,style,'>',content,'</',tag,'>'
    end.
    LF join lines
)
renderBlock =: 3 : 0
    'kind text number ordered lines children items aligns rows'=.y{::Blocks
    select. kind
    case. 'heading' do. headingHtml number;text
    case. 'paragraph' do. '<p>',(inline text;1;1),'</p>'
    case. 'rule' do. '<hr />'
    case. 'toc' do. TocMarker
    case. 'code' do.
        attr=.''
        if. #text do. attr=.' class="language-',(htmlEscape text),'"' end.
        html=.'<pre><code',attr,'>'
        for_line. lines do. html=.html,(htmlEscape >line),LF end.
        html,'</code></pre>'
    case. 'quote' do. '<blockquote>',LF,(renderSequence children),'</blockquote>'
    case. 'alert' do.
        name=.lower text
        title=.({.text),}.name
        '<div class="alert alert-',name,'">',LF,'<p class="alert-title">',title,'</p>',LF,(renderSequence children),'</div>'
    case. 'list' do.
        tag=.ordered{::'ul';'ol'
        attr=.''
        if. ordered *. number~:1 do. attr=.' start="',(num number),'"' end.
        html=.'<',tag,attr,'>',LF
        for_item. items do. html=.html,(renderItem >item),LF end.
        html,'</',tag,'>'
    case. 'table' do.
        html=.'<table>',LF,'<thead>',LF,'<tr>',LF
        html=.html,(tableRow (<'th'),(<aligns),<lines),LF,'</tr>',LF,'</thead>',LF
        if. #rows do.
            html=.html,'<tbody>',LF
            for_row. rows do.
                html=.html,'<tr>',LF,(tableRow (<'td'),(<aligns),row),LF,'</tr>',LF
            end.
            html=.html,'</tbody>',LF
        end.
        html,'</table>'
    end.
)
tocList =: 4 : 0
    html=.'<ul>',LF
    for_i. I.x=y do.
        html=.html,'<li><a href="#',(i{::HeadingIds),'">',(i{::HeadingLabels),'</a>'
        if. i e.x do. html=.html,LF,(x tocList i),LF end.
        html=.html,'</li>',LF
    end.
    html,'</ul>'
)
toc =: 3 : 0
    parents=.i.0
    stack=.i.0
    for_level. HeadingLevels do.
        while. #stack do.
            if. level>({:stack){HeadingLevels do. break. end.
            stack=.}:stack
        end.
        parent=._1
        if. #stack do. parent=.{:stack end.
        parents=.parents,parent
        stack=.stack,level_index
    end.
    html=.'<nav class="toc">',LF
    if. #parents do. html=.html,(parents tocList _1),LF end.
    html,'</nav>'
)
footnoteList =: 3 : 0
    if. 0=#NoteNames do. '' return. end.
    html=.'<section class="footnotes">',LF,'<ol>',LF
    for_name. NoteNames do.
        index=.name_index
        body=.inline ((FootNames i.name){::FootBodies);1;0
        links=.0$a:
        for_count. >:i.index{NoteCounts do.
            id=.referenceId (index+1),count
            links=.links,<'<a href="#',id,'">&#8617;</a>'
        end.
        html=.html,'<li id="fn-',(num index+1),'">',body,' ',(' 'join links),'</li>',LF
    end.
    html,'</ol>',LF,'</section>',LF
)
main =: 3 : 0
    lines=.<;._2 (1!:1 <'/dev/stdin'),LF
    lines=.(lines i.<'@@END@@'){.lines
    document=.parseBlocks lines
    html=.renderSequence document
    contents=.toc ''
    output=.''
    at=.0
    while. at<#html do.
        found=.html findAt at;TocMarker
        output=.output,(found-at){.at}.html
        if. found=#html do. break. end.
        output=.output,contents
        at=.found+#TocMarker
    end.
    1!:2&2 output,footnoteList ''
)
main''
