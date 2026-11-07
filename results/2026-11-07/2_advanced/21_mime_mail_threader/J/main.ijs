ScriptPath =: >{:4!:3''
SourceDirectory =: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
Digits =: '0123456789'
Letters =: 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
Whitespace =: ' ',TAB
div =: 4 : '_1 x:<.(x:x)%x:y'
num =: 3 : '10#.Digits i.y'
number =: 3 : 0
    text =. ''
    while. y>0 do. text =. ((10|y){Digits),text
        y =. y div 10 end.
    if. #text do. text else. '0' end.
)
pad =: 4 : 0
    text =. number y
    ((0>.x-#text)$'0'),text
)
lower =: 3 : 0
    codes =. a.i.y
    a.{~codes+32*(codes>:65)*.codes<:90
)
split =: 4 : 0
    result =. 0$a:
    while. 1 do.
        position =. y i.x
        result =. result,<position{.y
        if. position=#y do. result return. end.
        y =. (position+1)}.y
    end.
)
join =: 4 : 0
    text =. ''
    for_index. i.#y do.
        if. index do. text =. text,x end.
        text =. text,index{::y
    end.
    text
)
words =: 3 : 0
    text =. ' ' (I.y=TAB)}y
    parts =. ' ' split text
    parts#~0<#&>parts
)
collapse =: 3 : ''' '' join words y'
strip_trailing =: 3 : 0
    while. #y do.
        if. -.({:y)e.Whitespace do. break. end.
        y =. }:y
    end.
    y
)
strip =: 3 : 0
    y =. strip_trailing y
    while. #y do.
        if. -.({.y)e.Whitespace do. break. end.
        y =. }.y
    end.
    y
)
format =: 4 : 0
    parts =. '|' split x
    text =. 0{::parts
    for_index. i.#y do.
        value =. index{::y
        if. 2~:3!:0 value do. value =. number value end.
        text =. text,value,(index+1){::parts
    end.
    text
)
ascii_order =: 3 : '/: > (a.&i.)&.> y'
read_lines =: 3 : '<;._2 (1!:1 <''input/'',y)'
load SourceDirectory,'mime.ijs'
load SourceDirectory,'headers.ijs'
load SourceDirectory,'addresses.ijs'
load SourceDirectory,'dates.ijs'
load SourceDirectory,'threader.ijs'
read_mailbox =: 3 : 0
    messages =. 0$a:
    lines =. read_lines 'mailbox.mbox'
    for_index. i.#lines do.
        line =. index{::lines
        if. 'From '-:5{.line do. messages =. messages,<0$a:
        else.
            prefix =. 0
            while. prefix<#line do.
                if. '>'~:prefix{line do. break. end.
                prefix =. prefix+1
            end.
            if. (prefix>0)*.'From '-:5{.prefix}.line do. line =. }.line end.
            row =. (<index+1),<line
            messages =. (<(>{:messages),<row)(<:#messages)}messages
        end.
    end.
    for_index. i.#messages do.
        lines =. index{::messages
        if. #lines do.
            if. 0=#1{::>{:lines do. lines =. }:lines end.
        end.
        messages =. (<lines)index}messages
    end.
    messages
)
sections =: 3 : 0
    for_index. i.#y do.
        if. 0=#1{::index{::y do. (<index{.y),<(index+1)}.y return. end.
    end.
    (<y),<0$a:
)
valid_id =: 3 : 0
    if. (#y)<3 do. 0 return. end.
    if. ('<'~:{.y)+.'>'~:{:y do. 0 return. end.
    inside =. }.}:y
    if. (1~:+/inside='@')+.('@'={.inside)+.'@'={:inside do. 0 return. end.
    codes =. a.i.inside
    (*./(codes>:33)*.codes<:126)*.-.+./inside e.'<>()"\'
)
extract_ids =: 3 : 0
    result =. 0$a:
    while. #y do.
        start =. y i.'<'
        if. start=#y do. break. end.
        tail =. start}.y
        end =. tail i.'>'
        if. end=#tail do. break. end.
        id =. (end+1){.tail
        if. valid_id id do. result =. result,<id end.
        y =. (end+1)}.tail
    end.
    result
)
problem =: 3 : 'CurrentProblems =: CurrentProblems,<y'
bad_headers =: 3 : 0
    for_line. 2{::y do. problem 'bad header line ',number line end.
    i.0
)
parameter =: 4 : 0
    'names values' =. x
    index =. names i.<y
    if. index<#names do. index{::values else. '' end.
)
parse_entity =: 3 : 0
    'part header body enabled' =. y
    identifier =. #Entities
    Entities =: Entities,<0$a:
    main =. 'text'
    subtype =. 'plain'
    names =. values =. 0$a:
    if. enabled*.header header_has 'Content-Type' do.
        parsed =. 1 parse_parameters header header_value 'Content-Type'
        if. 0{::parsed do. 'okay main subtype names values' =. parsed
        else. problem 'bad Content-Type in part ',part end.
    end.
    disposition =. filename =. ''
    if. enabled*.header header_has 'Content-Disposition' do.
        parsed =. 0 parse_parameters header header_value 'Content-Disposition'
        if. 0{::parsed do.
            disposition =. 1{::parsed
            filename =. (3 4{parsed)parameter 'filename'
        else. problem 'bad Content-Disposition in part ',part end.
    end.
    parameters =. (<names),<values
    if. 0=#filename do. filename =. parameters parameter 'name' end.
    if. (main-:'text')*.(<'charset')e.names do.
        charset =. lower parameters parameter 'charset'
        if. -.charset-:'us-ascii' do. problem 'unsupported charset "',charset,'" in part ',part end.
    end.
    multipart =. 0
    children =. 0$0
    content =. ''
    if. enabled*.main-:'multipart' do.
        boundary =. parameters parameter 'boundary'
        if. 0=#boundary do. problem 'missing boundary in part ',part
        else.
            multipart =. 1
            parts =. 0$a:
            closed =. 0
            for_line. body do.
                marker =. strip_trailing 1{::>line
                if. marker-:'--',boundary,'--' do. closed =. 1 break. end.
                if. marker-:'--',boundary do. parts =. parts,<0$a:
                elseif. #parts do. parts =. (<(>{:parts),line)(<:#parts)}parts end.
            end.
            if. 0=#parts do. problem 'no parts in part ',part
            elseif. -.closed do. problem 'unterminated multipart in part ',part end.
            for_index. i.#parts do.
                'head childbody' =. sections index{::parts
                childheader =. parse_fields head
                bad_headers childheader
                childpart =. part,'.',number index+1
                child =. parse_entity (<childpart),(<childheader),(<childbody),<1
                children =. children,child
            end.
        end.
    end.
    if. -.multipart do.
        originals =. 0$a:
        for_line. body do. originals =. originals,1{>line end.
        original =. LF join originals
        encoding =. '7bit'
        if. enabled*.header header_has 'Content-Transfer-Encoding' do. encoding =. lower header header_value 'Content-Transfer-Encoding' end.
        if. encoding-:'base64' do.
            'okay content' =. base64_body original
            if. -.okay do. problem 'bad base64 in part ',part end.
        elseif. encoding-:'quoted-printable' do.
            'content error' =. quoted_printable original
            if. error do. problem 'bad quoted-printable in part ',part end.
        else.
            content =. original
            if. -.(<encoding)e.'7bit';'8bit';'binary' do. problem 'unknown encoding "',encoding,'" in part ',part end.
        end.
    end.
    entity =. (<part),(<main),(<subtype),(<names),(<values),(<disposition),(<filename),(<multipart),(<children),<content
    Entities =: (<entity)identifier}Entities
    identifier
)
recipients =: 4 : 0
    result =. 0$a:
    if. -.x header_has y do. result return. end.
    'okay addresses error' =. parse_address_list x header_value y
    if. -.okay do. problem 'bad ',y
        result return. end.
    for_address. addresses do.
        for_mailbox. 1{::>address do. result =. result,1{>mailbox end.
    end.
    if. error do. problem 'bad encoded word in ',y end.
    result
)
process_message =: 4 : 0
    CurrentProblems =: 0$a:
    'head body' =. sections y
    header =. parse_fields head
    bad_headers header
    checked =. 'From';'To';'Cc';'Subject';'Date';'Message-ID';'In-Reply-To';'References';'MIME-Version';'Content-Type';'Content-Transfer-Encoding';'Content-Disposition'
    for_name. checked do.
        if. (header header_count >name)>1 do. problem 'duplicate ',>name end.
    end.
    sender =. 0$a:
    if. -.header header_has 'From' do. problem 'missing From'
    else.
        'okay addresses error' =. parse_address_list header header_value 'From'
        valid =. okay*.(#addresses)=1
        if. valid do. valid =. -.0{::0{::addresses end.
        if. -.valid do. problem 'bad From'
        else.
            sender =. 0{::1{::0{::addresses
            if. error do. problem 'bad encoded word in From' end.
        end.
    end.
    to =. header recipients 'To'
    cc =. header recipients 'Cc'
    'subject error' =. decode_unstructured header header_value 'Subject'
    if. error do. problem 'bad encoded word in Subject' end.
    base =. subject
    reply =. 0
    while. 're:'-:lower 3{.base do.
        reply =. 1
        base =. 3}.base
        while. #base do.
            if. ' '~:{.base do. break. end.
            base =. }.base
        end.
    end.
    date =. _1
    if. -.header header_has 'Date' do. problem 'missing Date'
    else.
        'date error' =. parse_date header header_value 'Date'
        if. #error do. problem error end.
    end.
    id =. ''
    if. -.header header_has 'Message-ID' do. problem 'missing Message-ID'
    else.
        value =. header header_value 'Message-ID'
        earlier =. KnownIds i.<value
        if. -.valid_id value do. problem 'bad Message-ID'
        elseif. earlier<#KnownIds do. problem 'Message-ID already used by message ',number earlier{KnownNumbers
        else.
            id =. value
            KnownIds =: KnownIds,<id
            KnownNumbers =: KnownNumbers,x
        end.
    end.
    references =. extract_ids header header_value 'References'
    replies =. extract_ids header header_value 'In-Reply-To'
    if. #replies do.
        if. 0=#references do. references =. references,{.replies
        elseif. -.({:references)-:{.replies do. references =. references,{.replies end.
    end.
    enabled =. 0
    if. header header_has 'MIME-Version' do.
        'okay version' =. remove_comments header header_value 'MIME-Version'
        compact =. version#~-.version e.Whitespace
        if. okay*.'1.0'-:compact do. enabled =. 1
        else. problem 'bad MIME-Version' end.
    end.
    entity =. parse_entity (<'1'),(<header),(<body),<enabled
    (<id),(<date),(<sender),(<to),(<cc),(<subject),(<base),(<reply),(<references),(<entity),<CurrentProblems
)
collect_text =: 4 : 0
    'part main subtype names values disposition filename multipart children content' =. y{::Entities
    if. -.multipart do.
        if. (disposition-:'attachment')+.-.main-:'text' do. 0$0 return. end.
        if. (subtype-:'plain')+.x*.subtype-:'html' do. ,y else. 0$0 end.
        return.
    end.
    if. subtype-:'alternative' do.
        for_allow. 0 1 do.
            for_child. children do.
                found =. allow collect_text child
                if. #found do. found return. end.
            end.
        end.
        0$0 return.
    end.
    result =. 0$0
    for_child. children do. result =. result,x collect_text child end.
    result
)
quote_prefix =: 3 : 0
    if. y do. (y$'>'),' ' else. '' end.
)
wrap_text =: 4 : 0
    lines =. 0$a:
    current =. ''
    for_word. words y do.
        word =. >word
        if. (0<#current)*.((#current)+1+#word)>72 do.
            lines =. lines,<x,current
            current =. word
        elseif. #current do. current =. current,' ',word
        else. current =. word end.
    end.
    lines,<x,current
)
flowed_lines =: 4 : 0
    if. 0=#y do. 0$a: return. end.
    logical =. 0$a:
    for_line. LF split y do.
        text =. >line
        depth =. 0
        while. depth<#text do.
            if. '>'~:depth{text do. break. end.
            depth =. depth+1
        end.
        text =. depth}.text
        if. #text do. if. ' '={.text do. text =. }.text end. end.
        flowing =. 0
        if. #text do. flowing =. (' '={:text)*.-.text-:'-- ' end.
        merged =. 0
        if. #logical do.
            'previousdepth previous flowingprevious' =. >{:logical
            if. flowingprevious*.previousdepth=depth do.
                if. x do. previous =. }:previous end.
                logical =. (<(<depth),(<previous,text),<flowing)(<:#logical)}logical
                merged =. 1
            end.
        end.
        if. -.merged do. logical =. logical,<(<depth),(<text),<flowing end.
    end.
    lines =. 0$a:
    for_line. logical do.
        'depth text flowing' =. >line
        lines =. lines,(quote_prefix depth)wrap_text text
    end.
    lines
)
replace_references =: 3 : 0
    names =. 'amp';'lt';'gt';'quot';'apos';'nbsp'
    values =. '&';'<';'>'; '"';'''';' '
    result =. ''
    position =. 0
    while. position<#y do.
        replaced =. 0
        if. '&'=position{y do.
            tail =. (position+1)}.y
            end =. tail i.';'
            if. end<#tail do.
                name =. end{.tail
                index =. names i.<name
                if. index<#names do.
                    result =. result,index{::values
                    replaced =. 1
                elseif. #name do.
                    if. '#'={.name do.
                        digits =. }.name
                        if. 1 2 3 has_digits digits do.
                            value =. num digits
                            if. (value>:32)*.value<:126 do.
                                result =. result,value{a.
                                replaced =. 1
                            end.
                        end.
                    end.
                end.
                if. replaced do. position =. position+end+2 end.
            end.
        end.
        if. -.replaced do. result =. result,position{y
            position =. position+1 end.
    end.
    result
)
html_lines =: 3 : 0
    hidden =. 'head';'style';'script'
    paragraphs =. 'p';'div';'ul';'ol';'table';'tr';'blockquote';'h1';'h2';'h3';'h4';'h5';'h6'
    blocks =. 0$a:
    depth =. 0
    current =. hide =. ''
    position =. 0
    while. position<#y do.
        character =. position{y
        close =. #y
        if. character='<' do. tail =. (position+1)}.y
            offset =. tail i.'>'
            if. offset<#tail do. close =. position+1+offset end.
        end.
        if. close=#y do.
            if. 0=#hide do. current =. current,character end.
            position =. position+1
            continue.
        end.
        inside =. (1+close-position){.position}.y
        inside =. }.}:inside
        position =. close+1
        ending =. 0
        if. #inside do. ending =. '/'={.inside end.
        if. ending do. inside =. }.inside end.
        length =. 0
        while. length<#inside do.
            if. -.(length{inside)e.Letters,Digits do. break. end.
            length =. length+1
        end.
        name =. lower length{.inside
        if. #hide do.
            if. ending*.name-:hide do. hide =. '' end.
        elseif. (-.ending)*.(<name)e.hidden do. hide =. name
        elseif. (name-:'br')+.(-.ending)*.name-:'li' do.
            blocks =. blocks,<(<depth),<current
            current =. ''
            if. name-:'li' do. current =. '* ' end.
        elseif. (<name)e.paragraphs do.
            blocks =. blocks,(<(<depth),<current),<(<depth),<''
            current =. ''
            if. name-:'blockquote' do.
                if. ending do. depth =. 0>.depth-1
                else. depth =. depth+1 end.
            end.
        end.
    end.
    blocks =. blocks,<(<depth),<current
    lines =. 0$a:
    for_block. blocks do.
        'depth text' =. >block
        text =. ' ' (I.text=LF)}text
        text =. strip replace_references collapse text
        if. #text do. lines =. lines,(quote_prefix depth)wrap_text text
        elseif. #lines do.
            if. 0<#>{:lines do. lines =. lines,<'' end.
        end.
    end.
    while. #lines do.
        if. 0<#>{:lines do. break. end.
        lines =. }:lines
    end.
    lines
)
display_lines =: 3 : 0
    'part main subtype names values disposition filename multipart children content' =. y{::Entities
    if. subtype-:'html' do. (<'html'),<html_lines content
    elseif. 'flowed'-:lower ((<names),<values)parameter 'format' do.
        deletespace =. 'yes'-:lower ((<names),<values)parameter 'delsp'
        (<'flowed'),<deletespace flowed_lines content
    else.
        lines =. 0$a:
        if. #content do. lines =. LF split content end.
        (<'plain'),<lines
    end.
)
date_notation =: 3 : 0
    if. y<0 do. 'invalid' else. format_utc y end.
)
subject_notation =: 3 : 0
    if. #y do. y else. '(no subject)' end.
)
walk_thread =: 3 : 0
    'container prefix stem depth' =. y
    ThreadEntries =: ThreadEntries,<(<container),(<prefix),<depth
    children =. container{::ContainerChildren
    for_index. i.#children do.
        if. index=(#children)-1 do. childprefix =. stem,'`- '
            childstem =. stem,'   '
        else. childprefix =. stem,'+- '
            childstem =. stem,'|  ' end.
        walk_thread (<index{children),(<childprefix),(<childstem),<depth+1
    end.
    i.0
)
thread_report =: 4 : 0
    ThreadEntries =: 0$a:
    walk_thread (<y),(<''),(<''),<0
    depth =. count =. 0
    senders =. 0$a:
    dates =. 0$0
    for_entry. ThreadEntries do.
        'container prefix level' =. >entry
        depth =. depth>.level
        message =. container{ContainerMessages
        if. message<0 do. continue. end.
        count =. count+1
        MessageThread =: x message}MessageThread
        MessageDepth =: level message}MessageDepth
        parent =. container{ContainerParents
        parentmessage =. _1
        if. parent>:0 do. parentmessage =. parent{ContainerMessages end.
        MessageParent =: parentmessage message}MessageParent
        row =. message{::Messages
        sender =. 2{::row
        if. #sender do. senders =. senders,1{sender end.
        date =. 1{::row
        if. date>:0 do. dates =. dates,date end.
    end.
    lines =. <'thread | messages | depth | senders |' format (<x),(<count),(<depth),<#~.senders
    if. #dates do. lines =. lines,<'span | .. |' format (<format_utc <./dates),<format_utc >./dates
    else. lines =. lines,<'span -' end.
    subject =. y{::ContainerSubjects
    if. 0=#subject do. subject =. root_subject y end.
    lines =. lines,<'subject ',subject_notation subject
    for_entry. ThreadEntries do.
        'container prefix level' =. >entry
        message =. container{ContainerMessages
        if. message>:0 do.
            row =. message{::Messages
            sender =. 2{::row
            address =. '-'
            if. #sender do. address =. 1{::sender end.
            line =. '[|] | | |' format (<message+1),(<date_notation 1{::row),(<address),<subject_notation 5{::row
        elseif. 0<#container{::ContainerSubjects do. line =. '[subject] ',container{::ContainerSubjects
        else. line =. '[missing] ',container{::ContainerIds end.
        lines =. lines,<prefix,line
    end.
    lines
)
entity_lines =: 3 : 0
    'part main subtype names values disposition filename multipart children content' =. y{::Entities
    line =. 'part ',part,' ',main,'/',subtype
    if. multipart do.
        lines =. <line
        for_child. children do. lines =. lines,entity_lines child end.
        lines return.
    end.
    line =. line,' ',number #content
    if. #disposition do. line =. line,' ',disposition end.
    if. #filename do. line =. line,' "',filename,'"' end.
    <line
)
message_report =: 3 : 0
    'id date sender to cc subject base reply refs body problems' =. y{::Messages
    idtext =. '-'
    if. #id do. idtext =. id end.
    sendertext =. '-'
    if. #sender do.
        'name address' =. sender
        sendertext =. address
        if. #name do. sendertext =. name,' <',address,'>' end.
    end.
    totext =. cctext =. reftext =. '-'
    if. #to do. totext =. ', ' join to end.
    if. #cc do. cctext =. ', ' join cc end.
    if. #refs do. reftext =. ' ' join refs end.
    parenttext =. '-'
    if. (y{MessageParent)>:0 do. parenttext =. number 1+y{MessageParent end.
    lines =. (<'message ',number y+1),(<'id ',idtext),(<'date ',date_notation date),<'from ',sendertext
    lines =. lines,(<'to ',totext),(<'cc ',cctext),(<'subject ',subject_notation subject),<'refs ',reftext
    lines =. lines,<'thread | depth | parent |' format (<y{MessageThread),(<y{MessageDepth),<parenttext
    lines,entity_lines body
)
body_report =: 3 : 0
    lines =. <'request ',y
    known =. KnownIds i.<y
    if. known=#KnownIds do. lines,<'not found' return. end.
    message =. (known{KnownNumbers)-1
    body =. 9{::message{::Messages
    parts =. 1 collect_text body
    lines =. lines,<'message | text parts |' format (<message+1),<#parts
    for_part. parts do.
        'form display' =. display_lines part
        display =. strip_trailing&.>display
        quoted =. signature =. 0
        for_index. i.#display do.
            line =. index{::display
            if. #line do. quoted =. quoted+'>'={.line end.
            if. line-:'--' do. signature =. (#display)-index+1 end.
        end.
        partnumber =. 0{::part{::Entities
        lines =. lines,<'part | | lines | quoted | signature |' format (<partnumber),(<form),(<#display),(<quoted),<signature
        for_line. display do.
            line =. >line
            if. #line do. lines =. lines,<'| ',line
            else. lines =. lines,<'|' end.
        end.
    end.
    lines
)
csv_field =: 3 : 0
    if. -. +./y e.',"' do. y return. end.
    result =. '"'
    for_character. y do.
        result =. result,character
        if. character='"' do. result =. result,'"' end.
    end.
    result,'"'
)
sender_report =: 3 : 0
    addresses =. 0$a:
    names =. 0$a:
    counts =. 0$0
    threads =. dates =. 0$a:
    for_index. i.#Messages do.
        row =. index{::Messages
        sender =. 2{::row
        if. 0=#sender do. continue. end.
        'name address' =. sender
        position =. addresses i.<address
        if. position=#addresses do.
            addresses =. addresses,<address
            names =. names,<''
            counts =. counts,0
            threads =. threads,<0$0
            dates =. dates,<0$0
        end.
        counts =. (1+position{counts)position}counts
        threads =. (<(position{::threads),index{MessageThread)position}threads
        date =. 1{::row
        if. date>:0 do. dates =. (<(position{::dates),date)position}dates end.
        if. #name do. names =. (<name)position}names end.
    end.
    ranks =. /:ascii_order addresses
    order =. /:(-counts),.ranks
    lines =. <'address,name,messages,threads,first,last'
    for_index. order do.
        first =. last =. '-'
        valid =. index{::dates
        if. #valid do. first =. format_utc <./valid
            last =. format_utc >./valid end.
        fields =. (index{addresses),(<csv_field index{::names),(<number index{counts),(<number #~.index{::threads),(<first),<last
        lines =. lines,<',' join fields
    end.
    lines
)
join_blocks =: 3 : 0
    lines =. 0$a:
    for_block. y do.
        if. #lines do. lines =. lines,<'' end.
        lines =. lines,>block
    end.
    lines
)
write_lines =: 4 : 0
    ((LF join y),LF)1!:2 <'output/',x
    i.0
)
main =: 3 : 0
    Entities =: Messages =: KnownIds =: 0$a:
    KnownNumbers =: 0$0
    mailbox =. read_mailbox ''
    for_index. i.#mailbox do. Messages =: Messages,<(index+1)process_message index{::mailbox end.
    roots =. build_threads ''
    MessageThread =: MessageDepth =: (#Messages)$0
    MessageParent =: (#Messages)$_1
    threadblocks =. 0$a:
    for_index. i.#roots do. threadblocks =. threadblocks,<(index+1)thread_report index{roots end.
    messageblocks =. 0$a:
    errors =. 0$a:
    malformed =. problems =. 0
    for_index. i.#Messages do.
        row =. index{::Messages
        issues =. 10{::row
        parent =. index{MessageParent
        if. parent>:0 do.
            date =. 1{::row
            parentdate =. 1{::parent{::Messages
            if. (date>:0)*.(parentdate>:0)*.date<parentdate do.
                issues =. issues,<'dated before parent message ',number parent+1
                row =. (<issues)10}row
                Messages =: (<row)index}Messages
            end.
        end.
        malformed =. malformed+0<#issues
        problems =. problems+#issues
        for_issue. issues do. errors =. errors,<'message |: |' format (<index+1),issue end.
        messageblocks =. messageblocks,<message_report index
    end.
    errors =. (<'messages | malformed | problems |' format (<#Messages),(<malformed),<problems),errors
    bodyblocks =. 0$a:
    for_request. read_lines 'requests.txt' do. bodyblocks =. bodyblocks,<body_report >request end.
    1!:5 ::0: <'output'
    'threads.txt' write_lines join_blocks threadblocks
    'messages.txt' write_lines join_blocks messageblocks
    'bodies.txt' write_lines join_blocks bodyblocks
    'senders.csv' write_lines sender_report ''
    'malformed.txt' write_lines errors
    i.0
)
main ''
