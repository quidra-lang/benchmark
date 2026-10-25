LF =: 10{a.
Digits =: '0123456789'
Upper =: 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
Lower =: 'abcdefghijklmnopqrstuvwxyz'
Letters =: Upper,Lower
AccentSymbols =: (39{a.),'"`^~=.'
Known =: ;:'author editor title journal booktitle edition volume number pages publisher institution school address howpublished month year doi note'
EntryTypes =: ;:'article book inproceedings incollection techreport phdthesis misc'
Required =: (<'author title journal year'),(<'author title publisher year'),(<'author title booktitle year'),(<'author title booktitle publisher year'),(<'author title institution year'),(<'author title school year'),<'author title year'
Styles =: ;:'APA IEEE CHICAGO MLA'
SmallWords =: ;:'a an and as at but by for from in into nor of on or over per so the to up via with yet'
MacroNames =: ;:'jan feb mar apr may jun jul aug sep oct nov dec'
Months =: ;:'January February March April May June July August September October November December'
MonthShort =: 'Jan.';'Feb.';'Mar.';'Apr.';'May';'June';'July';'Aug.';'Sep.';'Oct.';'Nov.';'Dec.'
MacroValues =: Months
Keys =: Types =: Fields =: Primaries =: Editors =: SortTitles =: Suffixes =: 0$a:
CitationRecord =: i.0
Error =: ''
emit =: 3 : '(y,LF) 1!:2 4'
number =: 3 : ',''0'' 8!:2 y'
split =: 4 : '<;._1 x,y'
lower =: 3 : 'a.{~(a.i.y)+32*y e.Upper'
upper =: 3 : 'a.{~(a.i.y)-32*y e.Lower'
plain =: 3 : 'y#~-.y e.''{}'''
join =: 4 : 0
    text =. ''
    for_i. i.#y do.
        if. i do. text =. text,x end.
        text =. text,i{::y
    end.
    text
)
trim_spaces =: 3 : 0
    text =. y
    while. #text do.
        if. ' '~:{.text do. break. end.
        text =. }.text
    end.
    while. #text do.
        if. ' '~:{:text do. break. end.
        text =. }:text
    end.
    text
)
fail =: 3 : 0
    Error =: y
    throw.
)
depth_split =: 4 : 0
    parts =. 0$a:
    start =. position =. depth =. 0
    while. position<#y do.
        if. (depth=0)*.(position+#x)<:#y do.
            if. x-:(#x){.position}.y do.
                parts =. parts,<(position-start){.start}.y
                position =. position+#x
                start =. position
                continue.
            end.
        end.
        character =. position{y
        depth =. depth+('{'=character)-'}'=character
        position =. position+1
    end.
    parts,<start}.y
)
evaluate =: 3 : 0
    depth =. 0
    for_character. y do.
        depth =. depth+('{'=character)-'}'=character
        if. depth<0 do. fail 'unbalanced braces' end.
    end.
    if. depth do. fail 'unbalanced braces' end.
    result =. ''
    for_box. ' # ' depth_split y do.
        term =. >box
        if. ({.term)e.'{"' do.
            result =. result,}.}:term
        elseif. ({.term)e.Digits do.
            result =. result,term
        else.
            index =. MacroNames i.<term
            if. index=#MacroNames do. fail 'unknown macro ''',term,'''' end.
            result =. result,index{::MacroValues
        end.
    end.
    result
)
accent =: 4 : 0
    if. x>:#y do. 0;'' return. end.
    if. '\'~:x{y do. 0;'' return. end.
    if. (x+1)>:#y do. 0;'' return. end.
    command =. (x+1){y
    if. command='&' do. 2;'&' return. end.
    if. (x+2)<#y do.
        letter =. (x+2){y
        if. (command e.AccentSymbols)*.letter e.Letters do. 3;,letter return. end.
    end.
    if. (x+4)<#y do.
        if. (command e.AccentSymbols,'cuvH')*.'{'=(x+2){y do.
            if. (((x+3){y)e.Letters)*.'}'=(x+4){y do. 5;,(x+3){y return. end.
        end.
    end.
    0;''
)
normalize =: 3 : 0
    text =. ''
    position =. 0
    while. position<#y do.
        if. '{'=position{y do.
            'length character' =. (position+1) accent y
            if. length do.
                closing =. position+1+length
                if. closing<#y do.
                    if. '}'=closing{y do.
                        text =. text,character
                        position =. closing+1
                        continue.
                    end.
                end.
            end.
        end.
        'length character' =. position accent y
        if. length do.
            text =. text,character
            position =. position+length
        else.
            text =. text,position{y
            position =. position+1
        end.
    end.
    text =. ' ' (I.'~'=text)}text
    words =. ' ' split text
    ' ' join words#~0<#&>words
)
has_field =: 4 : '(<y)e.{."1 x{::Fields'
field =: 4 : 0
    table =. x{::Fields
    index =. ({."1 table)i.<y
    if. index=#table do. '' else. (<index,1){::table end.
)
load_database =: 3 : 0
    index =. errors =. 0
    while. index<#y do.
        line =. index{::y
        if. 0=#line do. index =. index+1 continue. end.
        if. '%'={.line do. index =. index+1 continue. end.
        reason =. ''
        error_line =. index+1
        if. '@string{'-:8{.line do.
            separator =. {.I.' = ' E.line
            name =. (separator-8){.8}.line
            expression =. }:(separator+3)}.line
            try.
                value =. evaluate expression
                if. (<name)e.MacroNames do. fail 'duplicate macro' end.
                MacroNames =: MacroNames,<name
                MacroValues =: MacroValues,<value
            catcht. reason =. Error
            end.
        else.
            opening =. line i.'{'
            type =. (opening-1){.}.line
            name =. }:(opening+1)}.line
            table =. 0 2$a:
            kind =. EntryTypes i.<type
            if. kind=#EntryTypes do. reason =. 'unknown type ''',type,''''
            elseif. (<name)e.Keys do. reason =. 'duplicate key'
            end.
            index =. index+1
            while. -.'}'-:index{::y do.
                if. 0=#reason do.
                    line =. index{::y
                    separator =. {.I.' = ' E.line
                    field_name =. (separator-2){.2}.line
                    expression =. (separator+3)}.line
                    if. ','={:expression do. expression =. }:expression end.
                    try.
                        value =. evaluate expression
                        if. (<field_name)e.{."1 table do. fail 'duplicate field ''',field_name,'''' end.
                        table =. table,field_name;normalize value
                    catcht.
                        reason =. Error
                        error_line =. index+1
                    end.
                end.
                index =. index+1
            end.
            if. 0=#reason do.
                for_required. ;:kind{::Required do.
                    if. required e.{."1 table do. continue. end.
                    if. (type-:'book')*.(>required)-:'author' do.
                        if. (<'editor')e.{."1 table do. continue. end.
                    end.
                    reason =. 'missing field ''',(>required),''''
                    error_line =. index+1
                    break.
                end.
            end.
            if. 0=#reason do.
                Keys =: Keys,<name
                Types =: Types,<type
                Fields =: Fields,<table
            end.
        end.
        if. #reason do.
            errors =. errors+1
            emit 'ERROR line ',(number error_line),': ',name,': ',reason
        end.
        index =. index+1
    end.
    emit 'LOADED entries=',(number #Keys),' macros=',(number (#MacroNames)-12),' errors=',number errors
)
parse_name =: 3 : 0
    parts =. trim_spaces each ',' depth_split y
    words =. ' ' depth_split 0{::parts
    lowercase_words =. I.({.&>}:words)e.Lower
    first =. von =. last =. junior =. ''
    if. 1=#parts do.
        if. 0=#lowercase_words do.
            first =. ' ' join }:words
            last =. >{:words
        else.
            start =. {.lowercase_words
            finish =. >:{:lowercase_words
            first =. ' ' join start{.words
            von =. ' ' join (finish-start){.start}.words
            last =. ' ' join finish}.words
        end.
    else.
        if. 0=#lowercase_words do. last =. ' ' join words
        else.
            finish =. >:{:lowercase_words
            von =. ' ' join finish{.words
            last =. ' ' join finish}.words
        end.
        first =. >{:parts
        if. 3=#parts do. junior =. 1{::parts end.
    end.
    first;von;last;junior
)
parse_names =: 3 : 0
    parts =. ' and ' depth_split y
    etal =. 'others'-:>{:parts
    if. etal do. parts =. }:parts end.
    names =. 0 4$a:
    for_part. parts do. names =. names,parse_name >part end.
    (<names),<etal
)
surname =: 3 : 0
    text =. 2{::y
    if. #1{::y do. text =. (1{::y),' ',text end.
    plain text
)
initials =: 3 : 0
    text =. plain y
    if. 0=#text do. '' return. end.
    words =. 0$a:
    for_word. ' ' split text do.
        pieces =. 0$a:
        for_piece. '-' split >word do.
            letters =. (>piece)#~(>piece)e.Letters
            pieces =. pieces,<(upper {.letters),'.'
        end.
        words =. words,<'-' join pieces
    end.
    ' ' join words
)
name_form =: 4 : 0
    'abbreviated inverted' =. x
    given =. 0{::y
    if. abbreviated do. given =. initials given else. given =. plain given end.
    text =. surname y
    if. #0{::y do.
        if. inverted do. text =. text,', ',given else. text =. given,' ',text end.
    end.
    if. #3{::y do. text =. text,', ',plain 3{::y end.
    text
)
list_a =: 4 : 0
    if. 1=#y do. >{.y else. (', ' join }:y),', ',x,' ',>{:y end.
)
list_b =: 4 : 0
    if. 2=#y do. (0{::y),' ',x,' ',1{::y else. x list_a y end.
)
author_names =: 4 : 0
    'names etal' =. y
    forms =. 0$a:
    for_i. i.#names do.
        inverted =. (x=0)+.((x e.2 3)*.i=0)
        forms =. forms,<((x<2),inverted) name_form i{names
    end.
    select. x
    case. 0 do.
        if. etal do. (', ' join forms),', et al.'
        elseif. 20>:#forms do. '&' list_a forms
        else. (', ' join 19{.forms),', . . . ',>{:forms
        end.
    case. 1 do.
        if. etal+.7<:#forms do. (> {.forms),' et al.' else. 'and' list_b forms end.
    case. 2 do.
        if. etal+.11<:#forms do. (', ' join (7<.#forms){.forms),', et al.' else. 'and' list_a forms end.
    case. 3 do.
        if. etal+.3<:#forms do. (> {.forms),', et al.' else. 'and' list_a forms end.
    end.
)
editor_names =: 4 : 0
    'names etal' =. y
    forms =. 0$a:
    for_name. names do. forms =. forms,<((x<2),0) name_form name end.
    if. etal do. (>{.forms),' et al.'
    elseif. x=0 do. '&' list_b forms
    else. 'and' list_b forms
    end.
)
singular =: 3 : '(1=#0{::y)*.-.1{::y'
outside_case =: 4 : 0
    text =. y
    depth =. seen_letter =. 0
    for_i. i.#y do.
        character =. i{y
        if. character e.Letters do.
            if. depth=0 do.
                if. x=0 do. character =. lower character
                elseif. x=1 do.
                    capital =. i=0
                    if. i>:2 do. capital =. capital+.': '-:(2{.(i-2)}.y) end.
                    if. capital do. character =. upper character else. character =. lower character end.
                elseif. -.seen_letter do. character =. upper character
                end.
                text =. character i}text
            end.
            seen_letter =. 1
        end.
        depth =. depth+('{'=character)-'}'=character
    end.
    text
)
title_case =: 4 : 0
    if. x=0 do. 1 outside_case y return. end.
    if. x=1 do. y return. end.
    words =. ' ' depth_split y
    converted =. 0$a:
    for_i. i.#words do.
        word =. i{::words
        if. '{'~:{.word do.
            letters =. lower word#~word e.Letters
            small =. ((<letters)e.SmallWords)*.(i>0)*.i<(<:#words)
            if. i do. small =. small*.':'~:{:>(i-1){words end.
            if. small do. word =. 0 outside_case word else. word =. 2 outside_case word end.
        end.
        converted =. converted,<word
    end.
    ' ' join converted
)
sort_title =: 3 : 0
    text =. lower plain y
    for_article. 'a ';'an ';'the ' do.
        prefix =. >article
        if. (#prefix)<:#text do.
            if. prefix-:(#prefix){.text do. (#prefix)}.text return. end.
        end.
    end.
    text
)
prepare_entries =: 3 : 0
    ranks =. 0 4$a:
    for_i. i.#Keys do.
        primary =. 'author'
        if. -.i has_field primary do. primary =. 'editor' end.
        names =. parse_names i field primary
        Primaries =: Primaries,<names
        if. i has_field 'editor' do. Editors =: Editors,<parse_names i field 'editor'
        else. Editors =: Editors,a:
        end.
        title =. sort_title i field 'title'
        SortTitles =: SortTitles,<title
        lead =. {.0{::names
        ranks =. ranks,(lower plain 2{::lead);(plain i field 'year');title;i{::Keys
    end.
    BibliographyOrder =: /:s:ranks
    Suffixes =: (#Keys)#<''
    visited =. (#Keys)#0
    for_i. i.#Keys do.
        if. i{visited do. continue. end.
        group =. i.0
        for_j. i.#Keys do.
            if. (i{Primaries)-:j{Primaries do.
                if. (i field 'year')-:j field 'year' do. group =. group,j end.
            end.
        end.
        visited =. 1 group}visited
        if. 1<#group do.
            order =. group /:s:(group{SortTitles),.group{Keys
            for_k. i.#order do. Suffixes =: (<,k{Lower) (k{order)}Suffixes end.
        end.
    end.
)
ieee_order =: 3 : 0
    remaining =. (i.#Keys)-.CitationRecord
    CitationRecord,remaining /:s:remaining{Keys
)
ieee_number =: 3 : '1+(ieee_order '''')i.y'
year_label =: 4 : 0
    text =. plain y field 'year'
    if. x e.0 2 do. text =. text,y{::Suffixes end.
    text
)
RawTemplates =: <;._2 (0 : 0)
{author}. ({year}). {title}. {journal}<, {volume}<({number})>><, {pages}>.< https://doi.org/{doi}>
{author}. ({year}). {title}< ({edition})>. {publisher}.
{author}. ({year}). {title}. In <{editor} ({eds}), >{booktitle}< ({pp})>.< {publisher}.>
{author}. ({year}). {title}< (Report No. {number})>. {institution}.
{author}. ({year}). {title} [Doctoral dissertation, {school}].
{author}. ({year}<, {month}>). {title}.< {howpublished}.>< {note}.>
{author}, "{title}," {journal}<, vol. {volume}><, no. {number}><, {pp}>, <{mon} >{year}<, doi: {doi}>.
{author}, {title}<, {edition}>. <{address}: >{publisher}, {year}.
{author}, "{title}," in {booktitle}<, {editor}, {eds}><, {address}><, {publisher}>, {year}<, {pp}>.
{author}, "{title}," {institution}<, {address}>, Tech. Rep.< {number}>, {year}.
{author}, "{title}," Ph.D. dissertation, {school}<, {address}>, {year}.
{author}, "{title},"< {howpublished},> <{mon} >{year}.< {note}.>
{author}. {year}. "{title}." {journal}< {volume}>< ({number})><: {pages}>.< https://doi.org/{doi}.>
{author}. {year}. {title}.< {edition}.> <{address}: >{publisher}.
{author}. {year}. "{title}." In {booktitle}<, edited by {editor}><, {pages}>.< <{address}: >{publisher}.>
{author}. {year}. {title}. Technical Report< {number}>. <{address}: >{institution}.
{author}. {year}. "{title}." PhD diss., {school}.
{author}. {year}. {title}.< {howpublished}.>< {note}.>
{author}. "{title}." {journal}<, vol. {volume}><, no. {number}>, <{mon} >{year}<, {pp}>.< https://doi.org/{doi}.>
{author}. {title}.< {edition},> {publisher}, {year}.
{author}. "{title}." {booktitle},< edited by {editor},>< {publisher},> {year}<, {pp}>.
{author}. {title}. {institution}, {year}.< Technical Report {number}.>
{author}. {title}. {year}. {school}, PhD dissertation.
{author}. {title}.< {howpublished},> <{mon} >{year}.< {note}.>
)
template_nodes =: 3 : 0
    nodes =. 0$a:
    while. TemplateCursor<#TemplateSource do.
        character =. TemplateCursor{TemplateSource
        TemplateCursor =: TemplateCursor+1
        if. character='>' do. break. end.
        kind =. 0
        payload =. ,character
        if. character='<' do.
            kind =. 2
            payload =. template_nodes ''
        elseif. character='{' do.
            kind =. 1
            length =. (TemplateCursor}.TemplateSource)i.'}'
            payload =. length{.TemplateCursor}.TemplateSource
            TemplateCursor =: TemplateCursor+length+1
        end.
        nodes =. nodes,<(<kind),<payload
    end.
    nodes
)
prepare_templates =: 3 : 0
    Templates =: 0$a:
    for_template. RawTemplates do.
        TemplateSource =: >template
        TemplateCursor =: 0
        Templates =: Templates,<template_nodes ''
    end.
)
RenderNames =: Known,;:'eds pp mon'
render_value =: 3 : '(RenderNames i.<y){::RenderValues'
set_render =: 4 : 'RenderValues =: (<y) (RenderNames i.<x)}RenderValues'
render_nodes =: 3 : 0
    for_box. y do.
        'kind payload' =. >box
        select. kind
        case. 0 do.
            if. payload-:'.' do.
                if. #RenderOutput do.
                    if. ({:RenderOutput)e.'.?!' do. continue. end.
                end.
            end.
            RenderOutput =: RenderOutput,payload
        case. 1 do. RenderOutput =: RenderOutput,render_value payload
        case. 2 do.
            include =. 1
            for_child_box. payload do.
                child =. >child_box
                if. 1=0{::child do.
                    if. 0=#render_value 1{::child do. include =. 0 break. end.
                end.
            end.
            if. include do. render_nodes payload end.
        end.
    end.
)
ordinal =: 3 : 0
    value =. 0".y
    suffix =. 'th'
    if. -.(100|value)e.11 12 13 do.
        last =. 10|value
        if. last e.1 2 3 do. suffix =. last{::'th';'st';'nd';'rd' end.
    end.
    y,suffix
)
EditorLabels =: ' (Ed.)';' (Eds.)';', Ed.';', Eds.';', ed.';', eds.';', editor';', editors'
reference =: 4 : 0
    'entry repeated' =. y
    RenderValues =: 0$a:
    for_name. Known do. RenderValues =: RenderValues,<plain entry field >name end.
    RenderValues =: RenderValues,3#<''
    names =. entry{::Primaries
    author =. x author_names names
    if. repeated do. author =. '---' end.
    if. -.entry has_field 'author' do. author =. author,((2*x)+-.singular names){::EditorLabels end.
    'author' set_render author
    if. entry has_field 'editor' do.
        editors =. entry{::Editors
        'editor' set_render x editor_names editors
        'eds' set_render (-.singular editors){::'Ed.';'Eds.'
    end.
    'title' set_render plain x title_case entry field 'title'
    'year' set_render x year_label entry
    if. entry has_field 'pages' do.
        pages =. '-' join '--' depth_split plain entry field 'pages'
        'pages' set_render pages
        prefix =. 'p. '
        if. '-'e.pages do. prefix =. 'pp. ' end.
        'pp' set_render prefix,pages
    end.
    if. entry has_field 'edition' do.
        edition =. plain entry field 'edition'
        if. *./edition e.Digits do. edition =. ordinal edition end.
        'edition' set_render edition,' ed.'
    end.
    month =. plain entry field 'month'
    index =. Months i.<month
    if. index<#Months do. month =. index{::MonthShort end.
    'mon' set_render month
    RenderOutput =: ''
    kind =. (EntryTypes i.entry{Types){0 1 2 2 3 4 5
    render_nodes ((6*x)+kind){::Templates
    if. x=1 do. '[',(number ieee_number entry),'] ',RenderOutput else. RenderOutput end.
)
short_name =: 4 : 0
    'style parenthetical' =. x
    'names etal' =. y{::Primaries
    surnames =. 0$a:
    for_name. names do. surnames =. surnames,<surname name end.
    threshold =. 3+style=2
    if. etal+.threshold<:#names do. (>{.surnames),' et al.' return. end.
    conjunction =. 'and'
    if. (style=0)*.parenthetical do. conjunction =. '&' end.
    conjunction list_b surnames
)
citation =: 4 : 0
    'kind entries' =. y
    parenthetical =. (<kind)e.'cite';'citep'
    if. kind-:'citeyear' do.
        years =. 0$a:
        for_entry. entries do. years =. years,<x year_label entry end.
        ', ' join years return.
    end.
    if. parenthetical*.x e.0 2 do. entries =. BibliographyOrder#~BibliographyOrder e.entries end.
    names =. 0$a:
    for_entry. entries do. names =. names,<(x,parenthetical) short_name entry end.
    if. kind-:'citeauthor' do. '; ' join names return. end.
    if. x=3 do.
        text =. '; ' join names
        if. parenthetical do. '(',text,')' else. text end.
        return.
    end.
    if. x=1 do.
        numbers =. ieee_number each <"0 entries
        if. -.parenthetical do.
            parts =. 0$a:
            for_i. i.#entries do. parts =. parts,<(i{::names),' [',(number i{::numbers),']' end.
            '; ' join parts return.
        end.
        numbers =. /:~>numbers
        parts =. 0$a:
        start =. 0
        while. start<#numbers do.
            finish =. start+1
            while. finish<#numbers do.
                if. (finish{numbers)~:1+(finish-1){numbers do. break. end.
                finish =. finish+1
            end.
            if. (finish-start)>:3 do.
                parts =. parts,<'[',(number start{numbers),']-[',(number (finish-1){numbers),']'
            else.
                for_i. start+i.finish-start do. parts =. parts,<'[',(number i{numbers),']' end.
            end.
            start =. finish
        end.
        ', ' join parts return.
    end.
    groups =. 0$a:
    start =. 0
    while. start<#entries do.
        finish =. start+1
        while. finish<#entries do.
            if. -. (start{names)-:finish{names do. break. end.
            finish =. finish+1
        end.
        years =. 0$a:
        for_i. start+i.finish-start do. years =. years,<x year_label i{entries end.
        text =. start{::names
        if. parenthetical do.
            separator =. ' '
            if. x=0 do. separator =. ', ' end.
            text =. text,separator,', ' join years
        else. text =. text,' (',(', ' join years),')'
        end.
        groups =. groups,<text
        start =. finish
    end.
    text =. '; ' join groups
    if. parenthetical do. '(',text,')' else. text end.
)
cite_text =: 4 : 0
    nodes =. 0$a:
    for_start. I.'\'=y do.
        opening =. start+(start}.y)i.'{'
        closing =. opening+(opening}.y)i.'}'
        kind =. ((opening-start)-1){.(start+1)}.y
        keys =. ~.',' split ((closing-opening)-1){.(opening+1)}.y
        entries =. Keys i.keys
        missing =. I.entries=#Keys
        if. #missing do. fail 'unknown key ''',(({.missing){::keys),'''' end.
        nodes =. nodes,<(<start),(<closing+1),(<kind),<entries
    end.
    for_node. nodes do. CitationRecord =: ~.CitationRecord,3{::>node end.
    text =. ''
    position =. 0
    for_node. nodes do.
        'start finish kind entries' =. >node
        text =. text,((start-position){.position}.y),x citation (<kind),<entries
        position =. finish
    end.
    text,position}.y
)
keygen =: 3 : 0
    bases =. 0$a:
    for_i. i.#Keys do.
        lead =. {.0{::i{::Primaries
        last =. plain 2{::lead
        year =. i field 'year'
        word =. ''
        for_part. ' ' split plain i field 'title' do.
            letters =. lower (>part)#~(>part)e.Letters
            if. #letters do.
                if. -.(<letters)e.SmallWords do. word =. letters break. end.
            end.
        end.
        bases =. bases,<(lower last#~last e.Letters),(year#~year e.Digits),word
    end.
    for_i. i.#Keys do.
        base =. i{::bases
        if. 1<+/bases=<base do.
            ordinal =. +/(i{.bases)=<base
            base =. base,a.{~97+ordinal
        end.
        emit (i{::Keys),' -> ',base
    end.
)
warn =: 4 : 0
    emit 'WARN ',(x{::Keys),': ',y
    Warnings =: Warnings+1
)
unknown_fields =: 3 : 0
    names =. ({."1 y{::Fields)-.Known
    names /:s:names
)
check_entries =: 3 : 0
    Warnings =: 0
    titles =. 0$a:
    for_i. i.#Keys do.
        if. i has_field 'pages' do.
            pages =. plain i field 'pages'
            if. ('-'e.pages)*.-.+./'--' E.pages do. i warn 'pages use a single hyphen' end.
            pieces =. '-' split pages
            pieces =. pieces#~0<#&>pieces
            if. 2=#pieces do.
                if. (*./(0{::pieces)e.Digits)*.*./(1{::pieces)e.Digits do.
                    if. (0".0{::pieces)>0".1{::pieces do. i warn 'pages are reversed' end.
                end.
            end.
        end.
        year =. plain i field 'year'
        if. -. (4=#year)*.*./year e.Digits do. i warn 'year is not 4 digits' end.
        title =. plain i field 'title'
        if. (-.+./title e.Lower)*.2<:+/title e.Upper do. i warn 'title is all caps' end.
        if. (i{::Types)-:'article' do.
            if. -.i has_field 'doi' do. i warn 'article has no doi' end.
        end.
        prior =. titles i.<lower title
        if. prior<#titles do. i warn 'same title as ',prior{::Keys end.
        titles =. titles,<lower title
        for_name. unknown_fields i do. i warn 'unknown field ''',(>name),'''' end.
    end.
    emit 'CHECK warnings=',number Warnings
)
export_entry =: 3 : 0
    index =. Keys i.<y
    if. index=#Keys do. fail 'unknown key ''',y,'''' end.
    emit '@',(index{::Types),'{',y,','
    present =. {."1 index{::Fields
    names =. (Known#~Known e.present),unknown_fields index
    for_i. i.#names do.
        name =. i{::names
        text =. '  ',name,' = {',(index field name),'}'
        if. i<(<:#names) do. text =. text,',' end.
        emit text
    end.
    emit '}'
)
stats =: 3 : 0
    emit 'ENTRIES ',number #Keys
    types =. ~.Types
    for_type. types /:s:types do. emit 'TYPE ',(>type),' ',number +/Types=type end.
    years =. 0$a:
    authors =. pairs =. 0$a:
    for_i. i.#Keys do.
        years =. years,<plain i field 'year'
        if. -.i has_field 'author' do. continue. end.
        names =. 0{::i{::Primaries
        forms =. 0$a:
        for_name. names do. forms =. forms,<0 0 name_form name end.
        forms =. ~.forms
        forms =. forms /:s:forms
        authors =. authors,forms
        for_a. i.#forms do.
            for_b. (a+1)+i.(#forms)-(a+1) do. pairs =. pairs,<(a{forms),b{forms end.
        end.
    end.
    distinct_years =. ~.years
    for_year. distinct_years /:s:distinct_years do. emit 'YEAR ',(>year),' ',number +/years=year end.
    emit 'AUTHORS ',number #~.authors
    if. 0=#pairs do. emit 'PAIR none' return. end.
    candidates =. >~.pairs
    candidates =. candidates /:s:candidates
    best_count =. 0
    best =. 0{candidates
    for_pair. candidates do.
        count =. +/pairs=<pair
        if. count>best_count do. best_count =. count best =. pair end.
    end.
    emit 'PAIR ',(0{::best),' & ',(1{::best),' ',number best_count
)
execute =: 3 : 0
    tokens =. ' ' split y
    command =. 0{::tokens
    if. (<command)e.'CITE';'SEARCH' do.
        spaces =. I.' '=y
        if. 1<#spaces do.
            'first second' =. 2{.spaces
            tokens =. (<first{.y),(<((second-first)-1){.(first+1)}.y),<(second+1)}.y
        end.
    end.
    names =. ;:'FORMAT BIBLIOGRAPHY CITE KEYGEN CHECK SEARCH EXPORT STATS'
    kind =. names i.<command
    if. kind=#names do. fail 'unknown command ''',command,'''' end.
    args =. }.tokens
    needed =. kind{2 1 2 0 0 2 1 0
    if. kind=0 do.
        if. (#args)<needed do. fail 'wrong number of arguments' end.
    elseif. (#args)~:needed do. fail 'wrong number of arguments'
    end.
    if. kind<3 do.
        style =. Styles i.{.args
        if. style=#Styles do. fail 'unknown style ''',(0{::args),'''' end.
    end.
    select. command
    case. 'FORMAT' do.
        for_key. }.args do.
            entry =. Keys i.key
            if. entry=#Keys do. emit 'ERROR unknown key ''',(>key),''''
            else. emit style reference entry,0
            end.
        end.
    case. 'BIBLIOGRAPHY' do.
        if. style=3 do. emit 'Works Cited' else. emit 'References' end.
        order =. BibliographyOrder
        if. style=1 do. order =. ieee_order '' end.
        previous =. _1
        for_entry. order do.
            repeated =. 0
            if. (style e.2 3)*.previous>:0 do. repeated =. (previous{Primaries)-:entry{Primaries end.
            emit style reference entry,repeated
            previous =. entry
        end.
    case. 'CITE' do. emit style cite_text 1{::args
    case. 'KEYGEN' do. keygen ''
    case. 'CHECK' do. check_entries ''
    case. 'SEARCH' do.
        field_name =. 0{::args
        needle =. lower 1{::args
        matches =. 0$a:
        for_i. i.#Keys do.
            if. i has_field field_name do.
                if. +./needle E.lower plain i field field_name do. matches =. matches,i{Keys end.
            end.
        end.
        text =. 'MATCHES ',number #matches
        if. #matches do. text =. text,': ',' ' join matches end.
        emit text
    case. 'EXPORT' do. export_entry 0{::args
    case. 'STATS' do. stats ''
    end.
)
main =: 3 : 0
    database =. 0$a:
    while. 1 do.
        line =. 1!:1 3
        if. line-:'%%' do. break. end.
        database =. database,<line
    end.
    load_database database
    prepare_entries ''
    prepare_templates ''
    count =. 0".1!:1 3
    for_i. i.count do.
        line =. 1!:1 3
        try. execute line
        catcht. emit 'ERROR ',Error
        end.
    end.
)
main ''
exit 0
