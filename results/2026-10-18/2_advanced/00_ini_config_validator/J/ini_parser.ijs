is_name =: 3 : 0
    if. 0=#y do. 0 return. end.
    (({.y)e.Letters) *. *./y e.Letters,Digits,'_'
)
is_section_name =: 3 : '*./is_name&> ''.'' split y'
trim_segments =: 3 : 0
    y =. (<ltrim 0{::y) 0}y
    (<rtrim (<:#y){::y) (<:#y)}y
)

NB. Statements are (kind; logical line; target; value).
parse_document =: 3 : 0
    'document physical' =. y
    statements =. 0$a:
    diagnostics =. 0$a:
    section =. ''
    base =. ''
    assigned =. empty_table ''
    for_logical. logical_lines physical do.
        'line segments error' =. >logical
        if. #error do.
            'code message' =. error
            diagnostics =. diagnostics,<(<document),(<line),(<code),<message
            continue.
        end.
        segments =. trim_segments segments
        first =. 0{::segments
        if. (1=#segments) *. 0=#first do. continue. end.
        code =. message =. ''
        if. '['={.first do.
            'header parent colon' =. ':' cut_first }.}:first
            header =. trim_spaces header
            parent =. trim_spaces parent
            relative =. ('.'={.header) *. is_section_name }.header
            valid =. (1=#segments) *. ']'={:first
            valid =. valid *. (relative +. is_section_name header)
            if. colon do. valid =. valid *. is_section_name parent end.
            if. -.valid do.
                code =. 'E_SECTION'
                message =. 'invalid section header'
                section =. ''
            elseif. relative *. 0=#base do.
                code =. 'E_SECTION'
                message =. 'relative section without base'
                section =. ''
            else.
                if. relative do. section =. base,header
                else. section =. base =. header end.
                if. colon do.
                    statements =. statements,< (<'inherit'),(<line),(<section),<parent
                end.
            end.
        elseif. '@'={.first do.
            words =. (' ' split first)-.<''
            valid =. (1=#segments) *. 2=#words
            if. valid do.
                valid =. (({.words)e.'@include';'@unset') *. is_name 1{::words
            end.
            if. -.valid do. code =. 'E_SYNTAX' [ message =. 'invalid directive'
            elseif. '@include'-:0{::words do.
                statements =. statements,< (<'include'),(<line),(<1{::words),<''
            elseif. 0=#section do. code =. 'E_NO_SECTION' [ message =. 'no current section'
            else.
                statements =. statements,< (<'unset'),(<line),(<section,'.',1{::words),<''
            end.
        else.
            outside =. (I.0=2|i.#segments){segments
            equal =. +./'=' e.&> outside
            if. -.equal do. code =. 'E_SYNTAX' [ message =. 'invalid line'
            else.
                'key rest found' =. '=' cut_first first
                if. -.found do. code =. 'E_SYNTAX' [ message =. 'invalid key'
                else.
                    key =. trim_spaces key
                    append =. '+'={:key
                    if. append do. key =. rtrim }:key end.
                    if. -.is_name key do. code =. 'E_SYNTAX' [ message =. 'invalid key'
                    else.
                        parts =. trim_segments (<rest),}.segments
                        valid =. 1=#parts
                        value =. 0{::parts
                        if. 3=#parts do.
                            valid =. (0=#0{::parts) *. 0=#2{::parts
                            value =. 1{::parts
                        end.
                        if. -.valid do. code =. 'E_SYNTAX' [ message =. 'invalid value'
                        elseif. 0=#section do. code =. 'E_NO_SECTION' [ message =. 'no current section'
                        else.
                            full =. section,'.',key
                            if. -.append do.
                                if. full has_key assigned do.
                                    code =. 'W_DUPLICATE'
                                    message =. full,' already set at line ',number full get_key assigned
                                end.
                                assigned =. ((<full),<line) put_key assigned
                            end.
                            kind =. append{::'assign';'append'
                            statements =. statements,<(<kind),(<line),(<full),<value
                        end.
                    end.
                end.
            end.
        end.
        if. #code do. diagnostics =. diagnostics,<(<document),(<line),(<code),<message end.
    end.
    (<statements),<diagnostics
)
