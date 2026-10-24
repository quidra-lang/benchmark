ScriptPath =: >{:4!:3''
DirectorySeparators =: I.ScriptPath e.'/\'
DirectoryLength =: 1+>./ _1,DirectorySeparators
SourceDirectory =: DirectoryLength{.ScriptPath
load SourceDirectory,'lexer.ijs'
load SourceDirectory,'ini_parser.ijs'
load SourceDirectory,'interpolate.ijs'
load SourceDirectory,'schema.ijs'
load SourceDirectory,'emitter.ijs'

success =: 3 : '(<1),<y'
failure =: 3 : '(<0),<'''''

parse_int =: 3 : 0
    text =. y
    sign =. 1
    if. #text do.
        if. ({.text)e.'+-' do.
            if. '-'={.text do. sign =. _1 end.
            text =. }.text
        end.
    end.
    if. '0x'-:tolower 2{.text do.
        hex =. tolower 2}.text
        if. ((#hex)<1)+.((#hex)>10)+.-.*./hex e.Digits,'abcdef' do. failure '' return. end.
        success sign*16#.(Digits,'abcdef')i.hex
    else.
        parts =. '_' split text
        if. -.*./digits&>parts do. failure '' return. end.
        plain =. ;parts
        if. (#plain)>12 do. failure '' return. end.
        success sign*decimal plain
    end.
)
parse_bool =: 3 : 0
    text =. tolower y
    if. (<text)e.;:'true yes on 1' do. success 1
    elseif. (<text)e.;:'false no off 0' do. success 0
    else. failure '' end.
)
parse_size =: 3 : 0
    text =. y
    position =. 0
    while. position<#text do.
        if. -. (position{text)e.Digits do. break. end.
        position =. position+1
    end.
    whole =. position{.text
    if. -.1 6 width_digits whole do. failure '' return. end.
    rest =. position}.text
    fraction =. ''
    if. '.'={.rest do.
        rest =. }.rest
        position =. 0
        while. position<#rest do.
            if. -. (position{rest)e.Digits do. break. end.
            position =. position+1
        end.
        fraction =. position{.rest
        if. -.1 3 width_digits fraction do. failure '' return. end.
        rest =. position}.rest
    end.
    index =. ('';(,'b');'kb';'mb';'gb')i.<tolower rest
    if. index=5 do. failure '' return. end.
    factor =. index{1 1 1024 1048576 1073741824
    value =. factor*decimal whole
    if. #fraction do.
        scaled =. factor*decimal fraction
        divisor =. 10^#fraction
        if. divisor |!.0 scaled do. failure '' return. end.
        value =. value+<.!.0 scaled%divisor
    end.
    success value
)
parse_duration =: 3 : 0
    if. 1 6 width_digits y do. success decimal y return. end.
    if. 0=#y do. failure '' return. end.
    rest =. y
    previous =. _1
    value =. 0
    while. #rest do.
        position =. 0
        while. position<#rest do.
            if. -. (position{rest)e.Digits do. break. end.
            position =. position+1
        end.
        digits_text =. position{.rest
        if. (-.1 6 width_digits digits_text)+.position=#rest do. failure '' return. end.
        unit =. 'hms'i.position{rest
        if. (unit=3)+.unit<:previous do. failure '' return. end.
        value =. value+(unit{3600 60 1)*decimal digits_text
        previous =. unit
        rest =. (position+1)}.rest
    end.
    success value
)
parse_host =: 3 : 0
    parts =. '.' split y
    if. *./y e.Digits,'.' do.
        if. 4~:#parts do. failure '' return. end.
        for_box. parts do.
            part =. >box
            if. -.1 3 width_digits part do. failure '' return. end.
            if. ((#part)>1)*.'0'={.part do. failure '' return. end.
            if. 255<decimal part do. failure '' return. end.
        end.
        success y return.
    end.
    if. (#y)>253 do. failure '' return. end.
    alnum =. Letters,(toupper Letters),Digits
    for_box. parts do.
        label =. >box
        if. ((#label)<1)+.(#label)>63 do. failure '' return. end.
        if. (-.({.label)e.alnum)+.(-.({:label)e.alnum)+.-.*./label e.alnum,'-' do. failure '' return. end.
    end.
    success tolower y
)
parse_path =: 3 : 0
    if. (0=#y)+.+./y e.' ',LF,HT do. failure '' return. end.
    absolute =. '/'={.y
    parts =. 0$a:
    for_box. '/' split y do.
        part =. >box
        if. (<part)e.'';(,'.') do. continue. end.
        if. -.part-:'..' do. parts =. parts,<part
        else.
            pop =. 0
            if. #parts do. pop =. -.'..'-:>{:parts end.
            if. pop do. parts =. }:parts
            elseif. absolute do. failure '' return.
            else. parts =. parts,<part end.
        end.
    end.
    value =. '/' join parts
    if. absolute do. value =. '/',value
    elseif. 0=#parts do. value =. '.' end.
    success value
)
parse_url =: 3 : 0
    'scheme rest found' =. '://' cut_first y
    if. (-.found)+.0=#scheme do. failure '' return. end.
    letters =. Letters,toupper Letters
    if. (-.({.scheme)e.letters)+.-.*./scheme e.letters,Digits,'+-.' do. failure '' return. end.
    if. +./rest e.'?#' do. failure '' return. end.
    'authority path slash' =. '/' cut_first rest
    'host port colon' =. ':' cut_first authority
    host_result =. parse_host host
    path_result =. parse_path '/',path
    if. (-.0{::host_result)+.-.0{::path_result do. failure '' return. end.
    scheme =. tolower scheme
    value =. scheme,'://',1{::host_result
    if. colon do.
        if. -.1 5 width_digits port do. failure '' return. end.
        if. ('0'={.port)+.65535<decimal port do. failure '' return. end.
        default =. _1
        if. scheme-:'http' do. default =. 80 elseif. scheme-:'https' do. default =. 443 end.
        if. default~:decimal port do. value =. value,':',port end.
    end.
    success value,1{::path_result
)
parse_date =: 3 : 0
    if. 10~:#y do. failure '' return. end.
    if. -. '--'-:4 7{y do. failure '' return. end.
    parts =. '-' split y
    if. -.4 2 2-:#&>parts do. failure '' return. end.
    if. -.*./digits&>parts do. failure '' return. end.
    'year month day' =. decimal&>parts
    if. (year<1)+.(month<1)+.month>12 do. failure '' return. end.
    days =. (month-1){31 28 31 30 31 30 31 31 30 31 30 31
    leap =. ((0=4|year)*.0~:100|year)+.0=400|year
    if. (month=2)*.leap do. days =. 29 end.
    if. (day<1)+.day>days do. failure '' else. success y end.
)
parse_scalar =: 4 : 0
    'text values' =. y
    select. x
    case. 'string' do. success text
    case. 'int' do. parse_int text
    case. 'bool' do. parse_bool text
    case. 'enum' do.
        index =. (tolower&.>values)i.<tolower text
        if. index=#values do. failure '' else. success index{::values end.
    case. 'size' do. parse_size text
    case. 'duration' do. parse_duration text
    case. 'host' do. parse_host text
    case. 'path' do. parse_path text
    case. 'url' do. parse_url text
    case. 'date' do. parse_date text
    end.
)

NB. Normalization returns (success; value; error code; message).
invalid_value =: 3 : 0
    'key kind values display' =. y
    if. kind-:'enum' do.
        code =. 'E_ENUM'
        message =. key,': ',display,' is not one of ',',' join values
    else.
        code =. 'E_TYPE'
        message =. key,': ',display,' is not a valid ',kind
    end.
    (<0),(<''),(<code),<message
)
parse_bound =: 4 : 0
    if. (<x)e.'string';'list' do. decimal y
    else. 1{::x parse_scalar (<y),<0$a: end.
)
bound_notation =: 3 : 0
    if. 2=3!:0 y do. y else. number y end.
)
normalize_value =: 3 : 0
    'key spec text origin' =. y
    kind =. 'kind' get_key spec
    item =. 'item' get_key spec
    values =. 'values' get_key spec
    secret =. 'secret' get_key spec
    if. kind-:'list' do.
        items =. 0$a:
        if. #trim_spaces text do. items =. trim_spaces&.>',' split text end.
        if. (< '')e.items do.
            origin report (<'W_EMPTY_ITEM'),<key,': empty list item ignored'
            items =. items-.<''
        end.
        normalized =. 0$a:
        for_box. items do.
            raw =. >box
            'valid value' =. item parse_scalar (<raw),<values
            if. -.valid do.
                display =. string_notation raw
                if. secret do. display =. MASK end.
                invalid_value (<key),(<item),(<values),<'item ',display return.
            end.
            normalized =. normalized,<value
        end.
        if. 'unique' get_key spec do.
            unique =. notations =. 0$a:
            for_box. normalized do.
                value =. >box
                notation =. value_notation (<item),(<''),<value
                if. -.(<notation)e.notations do.
                    unique =. unique,<value
                    notations =. notations,<notation
                end.
            end.
            if. (#unique)<#normalized do.
                origin report (<'W_DUPLICATE_ITEM'),<key,': duplicate items removed'
            end.
            normalized =. unique
        end.
    else.
        'valid normalized' =. kind parse_scalar (<text),<values
        if. -.valid do.
            display =. string_notation text
            if. secret do. display =. MASK end.
            invalid_value (<key),(<kind),(<values),<display return.
        end.
    end.
    if. 'range' has_key spec do.
        'lower_text upper_text' =. 'range' get_key spec
        measure =. normalized
        display =. ''
        if. kind-:'string' do. measure =. #normalized [ display =. 'length ',number #normalized
        elseif. kind-:'list' do. measure =. #normalized [ display =. 'count ',number #normalized
        else.
            display =. value_notation (<kind),(<item),<normalized
            if. secret do. display =. MASK end.
        end.
        outside =. 0
        lower_shown =. upper_shown =. ''
        if. #lower_text do.
            lower =. kind parse_bound lower_text
            lower_shown =. bound_notation lower
            if. kind-:'date' do. outside =. measure lex_less lower
            else. outside =. measure <!.0 lower end.
        end.
        if. #upper_text do.
            upper =. kind parse_bound upper_text
            upper_shown =. bound_notation upper
            if. kind-:'date' do. outside =. outside +. upper lex_less measure
            else. outside =. outside +. measure >!.0 upper end.
        end.
        if. outside do.
            message =. key,': ',display,' is out of range ',lower_shown,'..',upper_shown
            (<0),(<''),(<'E_RANGE'),<message return.
        end.
    end.
    (<1),(<normalized),(<'') ,<''
)

report =: 4 : 0
    'document line' =. x
    'code message' =. y
    Diagnostics =: Diagnostics,<(<document),(<line),(<code),<message
    i.0
)
define_key =: 3 : 0
    'key value origin' =. y
    DefinitionCount =: DefinitionCount+1
    history =. 0$a:
    if. key has_key Configuration do. history =. 3{::key get_key Configuration end.
    append =. 1
    if. #history do. append =. -.origin-:>{:history end.
    if. append do. history =. history,<origin end.
    definition =. (<value),(<origin),(<DefinitionCount),<history
    Configuration =: ((<key),<definition) put_key Configuration
    i.0
)
find_document =: 3 : 0
    if. -.y has_key Documents do.
        path =. 'input/conf/',y,'.ini'
        document =. 0$a:
        if. #1!:0 <path do. document =. parse_document (<y),<read_lines path end.
        Documents =: ((<y),<document) put_key Documents
    end.
    y get_key Documents
)
apply_document =: 3 : 0
    'name chain' =. y
    document =. find_document name
    IncludeTree =: IncludeTree,<(<(<:#chain)),<name
    Diagnostics =: Diagnostics,1{::document
    for_box. 0{::document do.
        'kind line target value' =. >box
        origin =. (<name),<line
        select. kind
        case. 'assign';'append' do.
            if. kind-:'append' do.
                if. target has_key Configuration do.
                    old =. 0{::target get_key Configuration
                    if. #old do. value =. old,',',value end.
                end.
            end.
            define_key (<target),(<value),<origin
        case. 'unset' do.
            if. target has_key Configuration do. Configuration =: target drop_key Configuration
            else. origin report (<'W_UNSET'),<target,' is not set' end.
        case. 'inherit' do.
            Parents =: ((<target),<(<value),<origin) put_key Parents
        case. 'include' do.
            if. (<target)e.chain do.
                path =. ((chain i.<target)}.chain),<target
                origin report (<'E_INCLUDE_CYCLE'),<'include cycle ',' -> ' join path
                IncludeTree =: IncludeTree,<(<#chain),<target,' (cycle)'
            elseif. 0=#find_document target do.
                origin report (<'E_INCLUDE_MISSING'),<'missing document ',target
                IncludeTree =: IncludeTree,<(<#chain),<target,' (missing)'
            else.
                apply_document (<target),<chain,<target
            end.
        end.
    end.
    i.0
)
inherit_sections =: 3 : 0
    own =. Configuration
    own_names =. table_keys own
    own_sections =. section_of&.>own_names
    for_box. table_keys Parents do.
        section =. >box
        'parent origin' =. section get_key Parents
        chain =. <section
        while. 1 do.
            last =. >{:chain
            if. -.last has_key Parents do. break. end.
            next =. 0{::last get_key Parents
            if. (<next)e.chain do. break. end.
            chain =. chain,<next
        end.
        if. last has_key Parents do.
            path =. chain,<0{::last get_key Parents
            origin report (<'E_INHERIT_CYCLE'),<'inheritance cycle ',' -> ' join path
            continue.
        end.
        if. (-.parent has_key Parents) *. -.(<parent)e.own_sections do.
            origin report (<'W_PARENT_EMPTY'),<'section ',section,' inherits from empty section ',parent
        end.
        for_ancestor. }.chain do.
            for_name. ((< >ancestor)=own_sections)#own_names do.
                source =. >name
                key =. section,'.',key_name source
                if. -.key has_key Configuration do.
                    Configuration =: ((<key),<source get_key own) put_key Configuration
                end.
            end.
        end.
    end.
    i.0
)
resolve_aliases =: 3 : 0
    for_box. Schema do.
        spec =. >box
        canonical =. 'pattern' get_key spec
        aliases =. 0$a:
        for_alias. 'aliases' get_key spec do.
            if. (>alias) has_key Configuration do. aliases =. aliases,alias end.
        end.
        if. 0=#aliases do. continue. end.
        candidates =. aliases
        if. canonical has_key Configuration do. candidates =. (<canonical),candidates end.
        winner =. 0{::candidates
        chosen =. winner get_key Configuration
        for_candidate. }.candidates do.
            key =. >candidate
            definition =. key get_key Configuration
            if. (2{::definition)>2{::chosen do. winner =. key [ chosen =. definition end.
        end.
        for_candidate. candidates do.
            key =. >candidate
            origin =. 1{::key get_key Configuration
            if. -.key-:canonical do.
                origin report (<'W_DEPRECATED'),<key,' is deprecated, use ',canonical
            end.
            if. -.key-:winner do.
                origin report (<'W_SHADOWED'),<key,' is superseded by ',winner,' at ',origin_text 1{::chosen
            end.
        end.
        Configuration =: ((<canonical),<chosen) put_key Configuration
        for_alias. aliases do. Configuration =: (>alias) drop_key Configuration end.
    end.
    i.0
)
fill_defaults =: 3 : 0
    sections =. ~.section_of&.>table_keys Configuration
    for_box. Schema do.
        spec =. >box
        if. 'default' has_key spec do.
            for_target. spec target_keys sections do.
                key =. >target
                if. -.key has_key Configuration do.
                    origin =. (<'schema'),<'line' get_key spec
                    define_key (<key),(<'default' get_key spec),<origin
                end.
            end.
        end.
    end.
    sections
)
check_types =: 3 : 0
    'results diagnostics' =. expand_values Configuration
    Diagnostics =: Diagnostics,diagnostics
    Outputs =: empty_table ''
    for_box. sort_keys table_keys Configuration do.
        key =. >box
        'valid text' =. key get_key results
        if. -.valid do. continue. end.
        definition =. key get_key Configuration
        origin =. 1{::definition
        spec =. spec_for key
        if. 0=#spec do.
            origin report (<'W_UNKNOWN'),<key,' is not in the schema'
            value =. text
            kind =. 'string'
            secret =. 0
            notation =. string_notation text
        else.
            'valid value code message' =. normalize_value (<key),(<spec),(<text),<origin
            if. -.valid do.
                origin report (<code),<message
                continue.
            end.
            kind =. 'kind' get_key spec
            secret =. 'secret' get_key spec
            notation =. value_notation (<kind),(<'item' get_key spec),<value
        end.
        output =. (<definition),(<spec),(<value),(<notation),(<secret),<kind
        Outputs =: ((<key),<output) put_key Outputs
    end.
    i.0
)
check_order =: 3 : 0
    removed =. 0$a:
    for_box. sort_keys table_keys Outputs do.
        key =. >box
        output =. key get_key Outputs
        spec =. 1{::output
        if. 0=#spec do. continue. end.
        le =. 'le' get_key spec
        if. 0=#le do. continue. end.
        target =. (section_of key),'.',le
        if. target has_key Outputs do.
            limit =. target get_key Outputs
            if. -.(<5{::limit)e.;:'int size duration' do. continue. end.
            if. (2{::output) >!.0 2{::limit do.
                origin =. 1{::0{::output
                origin report (<'E_ORDER'),<key,': ',(shown output),' is greater than ',target,' (',(shown limit),')'
                removed =. removed,<key
            end.
        end.
    end.
    for_box. removed do. Outputs =: (>box) drop_key Outputs end.
    i.0
)
check_required =: 3 : 0
    'root sections configured' =. y
    origin =. (<root),<0
    for_box. Schema do.
        spec =. >box
        if. -. 'required' get_key spec do. continue. end.
        for_target. spec target_keys sections do.
            key =. >target
            if. (<key)e.configured do. continue. end.
            when =. 'when' get_key spec
            if. 0=#when do.
                origin report (<'E_REQUIRED'),<key,' is required'
            else.
                condition =. (section_of key),'.',when
                if. condition has_key Outputs do.
                    output =. condition get_key Outputs
                    if. -.'bool'-:5{::output do. continue. end.
                    if. 2{::output do.
                        origin report (<'E_REQUIRED'),<key,' is required when ',condition,' is true'
                    end.
                end.
            end.
        end.
    end.
    i.0
)
check_fixed =: 3 : 0
    for_box. sort_keys table_keys Outputs do.
        key =. >box
        output =. key get_key Outputs
        spec =. 1{::output
        if. 0=#spec do. continue. end.
        if. -. 'fixed' get_key spec do. continue. end.
        for_profile. y do.
            profile =. >profile
            previous =. 'outputs' get_key profile
            if. -.key has_key previous do. continue. end.
            before =. key get_key previous
            if. -. (3{::before)-:3{::output do.
                origin =. 1{::0{::output
                origin report (<'E_FIXED'),<key,': value differs from profile ','name' get_key profile
                Outputs =: key drop_key Outputs
            end.
            break.
        end.
    end.
    i.0
)
diagnostic_less =: 4 : 0
    'ad al ac am' =. x
    'bd bl bc bm' =. y
    if. -.ad-:bd do. ad lex_less bd
    elseif. al~:bl do. al<bl
    elseif. -.ac-:bc do. ac lex_less bc
    else. am lex_less bm end.
)
sort_diagnostics =: diagnostic_less sort_by
summarize =: 3 : 0
    'name root configured' =. y
    diagnostics =. sort_diagnostics ~.Diagnostics
    errors =. manifest =. defaults =. documents =. 0
    for_box. diagnostics do.
        if. 'E_'-:2{.2{:: >box do. errors =. errors+1 end.
    end.
    for_box. 1{"1 Outputs do.
        output =. >box
        document =. 0{::1{::0{::output
        if. document-:'manifest' do. manifest =. manifest+1
        elseif. document-:'schema' do. defaults =. defaults+1
        else. documents =. documents+1 end.
    end.
    profile =. empty_table ''
    profile =. ((<'name'),<name) put_key profile
    profile =. ((<'root'),<root) put_key profile
    profile =. ((<'outputs'),<Outputs) put_key profile
    profile =. ((<'tree'),<IncludeTree) put_key profile
    profile =. ((<'diagnostics'),<diagnostics) put_key profile
    profile =. ((<'errors'),<errors) put_key profile
    profile =. ((<'warnings'),<(#diagnostics)-errors) put_key profile
    profile =. ((<'manifest_keys'),<manifest) put_key profile
    profile =. ((<'default_keys'),<defaults) put_key profile
    profile =. ((<'document_keys'),<documents) put_key profile
    ((<'dropped'),<configured-#Outputs) put_key profile
)
process_profile =: 3 : 0
    'number line earlier' =. y
    words =. ' ' split line
    name =. 0{::words
    root =. 1{::words
    Configuration =: Parents =: empty_table ''
    Diagnostics =: IncludeTree =: 0$a:
    DefinitionCount =: 0
    apply_document (<root),<<root
    for_override. 2}.words do.
        'key value found' =. '=' cut_first >override
        origin =. (<'manifest'),<number
        define_key (<key),(<value),<origin
    end.
    inherit_sections ''
    resolve_aliases ''
    sections =. fill_defaults ''
    configured =. table_keys Configuration
    check_types ''
    check_order ''
    check_required (<root),(<sections),<configured
    check_fixed earlier
    summarize (<name),(<root),<#configured
)
profile_diff =: 3 : 0
    'first second' =. y
    a =. 'outputs' get_key first
    b =. 'outputs' get_key second
    added =. removed =. changed =. 0
    entries =. 0$a:
    for_box. sort_keys ~.(table_keys a),table_keys b do.
        key =. >box
        before =. after =. 0$a:
        if. key has_key a do. before =. key get_key a end.
        if. key has_key b do. after =. key get_key b end.
        if. 0=#before do. sign =. '+' [ added =. added+1
        elseif. 0=#after do. sign =. '-' [ removed =. removed+1
        elseif. -. (3{::before)-:3{::after do. sign =. '~' [ changed =. changed+1
        else. continue. end.
        entries =. entries,<(<sign),(<key),(<before),<after
    end.
    diff =. empty_table ''
    diff =. ((<'first'),<'name' get_key first) put_key diff
    diff =. ((<'second'),<'name' get_key second) put_key diff
    diff =. ((<'added'),<added) put_key diff
    diff =. ((<'removed'),<removed) put_key diff
    diff =. ((<'changed'),<changed) put_key diff
    ((<'entries'),<entries) put_key diff
)
main =: 3 : 0
    Schema =: load_schema 'input/schema.txt'
    Documents =: empty_table ''
    profiles =. 0$a:
    manifest =. read_lines 'input/manifest.txt'
    for_index. i.#manifest do.
        profile =. process_profile (<index+1),(<index{::manifest),<profiles
        profiles =. profiles,<profile
    end.
    diffs =. 0$a:
    for_index. i.<:#profiles do.
        diff =. profile_diff (<index{::profiles),<(index+1){::profiles
        diffs =. diffs,<diff
    end.
    write_outputs (<profiles),<diffs
    i.0
)
main ''
