load_schema =: 3 : 0
    specs =. 0$a:
    lines =. read_lines y
    for_index. i.#lines do.
        text =. index{::lines
        if. (0=#trim_spaces text) +. '#'={.text do. continue. end.
        words =. ' ' split text
        pattern =. 0{::words
        parts =. '.' split section_of pattern
        spec =. empty_table ''
        spec =. ((<'line'),<index+1) put_key spec
        spec =. ((<'pattern'),<pattern) put_key spec
        spec =. ((<'key'),<key_name pattern) put_key spec
        spec =. ((<'parts'),<parts) put_key spec
        spec =. ((<'wildcard'),<(<,'*')e.parts) put_key spec
        spec =. ((<'kind'),<1{::words) put_key spec
        for_flag. ;:'required secret unique fixed' do.
            spec =. ((< >flag),<0) put_key spec
        end.
        spec =. ((<'values'),<0$a:) put_key spec
        spec =. ((<'item'),<'string') put_key spec
        spec =. ((<'aliases'),<0$a:) put_key spec
        spec =. ((<'when'),<'') put_key spec
        spec =. ((<'le'),<'') put_key spec
        for_word. 2}.words do.
            'attribute argument found' =. '=' cut_first >word
            if. (<attribute)e.;:'required secret unique fixed' do. value =. 1
            elseif. attribute-:'range' do. value =. '..' split argument
            elseif. attribute-:'values' do. value =. ',' split argument
            elseif. attribute-:'alias' do. attribute =. 'aliases' [ value =. ',' split argument
            else. value =. argument end.
            spec =. ((<attribute),<value) put_key spec
        end.
        specs =. specs,<spec
    end.
    specs
)
spec_matches =: 4 : 0
    patterns =. 'parts' get_key x
    parts =. '.' split y
    if. (#patterns)~:#parts do. 0 return. end.
    *./(patterns=parts)+.patterns=<,'*'
)
spec_for =: 3 : 0
    for_box. Schema do.
        spec =. >box
        if. -. 'wildcard' get_key spec do.
            if. y-:'pattern' get_key spec do. spec return. end.
        end.
    end.
    for_box. Schema do.
        spec =. >box
        if. 'wildcard' get_key spec do.
            if. (key_name y)-:'key' get_key spec do.
                if. spec spec_matches section_of y do. spec return. end.
            end.
        end.
    end.
    empty_table ''
)
target_keys =: 4 : 0
    if. -. 'wildcard' get_key x do. <'pattern' get_key x return. end.
    keys =. 0$a:
    for_box. sort_strings y do.
        section =. >box
        if. x spec_matches section do.
            key =. section,'.','key' get_key x
            chosen =. spec_for key
            if. ('line' get_key x)='line' get_key chosen do. keys =. keys,<key end.
        end.
    end.
    keys
)
