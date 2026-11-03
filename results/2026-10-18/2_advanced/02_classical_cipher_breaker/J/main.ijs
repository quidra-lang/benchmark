ScriptPath =: >{:4!:3''
SourceDirectory =: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
load SourceDirectory,'scoring.ijs'

div =: 4 : '<.(x:x)%x:y'
num =: 3 : '10#.Digits i.y'
number =: 3 : 0
    value =. y
    text =. ''
    while. value>0 do.
        text =. ((10|value){Digits),text
        value =. value div 10
    end.
    if. 0=#text do. '0' else. text end.
)
split =: 4 : 0
    parts =. 0$a:
    while. 1 do.
        position =. y i.x
        parts =. parts,<position{.y
        if. position=#y do. parts return. end.
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
read_lines =: 3 : '<;._2 (1!:1 <y)'
empty_table =: 3 : '0 2$a:'
table_keys =: 3 : '0{"1 y'
has_key =: 4 : '(<x)e.table_keys y'
get_key =: 4 : '((table_keys y)i.<x){::1{"1 y'
put_key =: 4 : 0
    'key value' =. x
    position =. (table_keys y)i.<key
    if. position<#y do. (<value) (<position,1)}y
    else. y,1 2$(<key),<value end.
)
digits =: 3 : '(0<#y)*.*./y e.Digits'
width_digits =: 4 : '((#y)>:0{x)*.((#y)<:1{x)*.digits y'
valid_name =: 3 : '(0<#y)*.((#y)<:16)*.*./y e.Lowercase,Digits,''_'''
bad =: 3 : 0
    JobError =: y
    0$a:
)
Commands =: ;:'ENCRYPT DECRYPT BREAK ANALYZE COMPARE IDENTIFY'
NamingCommands =: ;:'ENCRYPT DECRYPT BREAK'
Ciphers =: ;:'caesar affine vigenere autokey playfair railfence columnar'
SubstitutionCiphers =: ;:'caesar affine vigenere autokey'

load SourceDirectory,'substitution.ijs'
load SourceDirectory,'transposition.ijs'
load SourceDirectory,'playfair.ijs'
load SourceDirectory,'analysis.ijs'

parse_key =: 4 : 0
    cipher =. x
    word =. y
    if. (<cipher)e.;:'caesar railfence' do.
        if. 1 2 width_digits word do.
            value =. num word
            if. cipher-:'caesar' do. low =. 0 [ high =. 25
            else. low =. 2 [ high =. 20 end.
            if. (value>:low)*.value<:high do. number value return. end.
        end.
    elseif. cipher-:'affine' do.
        parts =. ',' split word
        if. 2=#parts do.
            if. *./(1 2)&width_digits&>parts do.
                'a b' =. num&>parts
                if. (a e.AffineMultipliers)*.b<:25 do.
                    (number a),',',number b return.
                end.
            end.
        end.
    else.
        low =. 1
        high =. 20
        characters =. Alphabet,Lowercase
        if. cipher-:'columnar' do.
            low =. 2
            high =. 9
            characters =. characters,Digits
        elseif. cipher-:'playfair' do. high =. 25 end.
        if. ((#word)>:low)*.((#word)<:high)*.*./word e.characters do.
            key =. uppercase word
            if. cipher-:'playfair' do. key =. replace_j key end.
            key return.
        end.
    end.
    bad 'bad key ',word
)
option_limits =: 4 : 0
    limits =. empty_table ''
    if. x-:'ANALYZE' do.
        ((<'MAXLEN'),<2 20 10) put_key limits return.
    elseif. x-:'IDENTIFY' do.
        ((<'KEYS'),<0$0) put_key limits return.
    end.
    limits =. ((<'TOP'),<1 20 5) put_key limits
    select. y
    case. 'vigenere' do.
        limits =. ((<'MAXLEN'),<2 20 10) put_key limits
        limits =. ((<'IOC'),<1 100000 6000) put_key limits
        limits =. ((<'KASISKI'),<1 100 60) put_key limits
        limits =. ((<'REFINE'),<0 10 5) put_key limits
    case. 'autokey' do. limits =. ((<'MAXLEN'),<1 20 8) put_key limits
    case. 'railfence' do. limits =. ((<'MAXRAILS'),<2 20 10) put_key limits
    case. 'columnar' do. limits =. ((<'MAXLEN'),<2 6 6) put_key limits
    case. 'playfair' do. limits =. ((<'KEYS'),<0$0) put_key limits
    end.
    limits
)
parse_options =: 4 : 0
    limits =. x
    options =. empty_table ''
    for_box. table_keys limits do.
        name =. >box
        if. name-:'KEYS' do. value =. '' else. value =. 2{name get_key limits end.
        options =. ((<name),<value) put_key options
    end.
    seen =. 0$a:
    for_box. y do.
        word =. >box
        position =. word i.'='
        name =. position{.word
        if. (position=#word)+.(-.name has_key limits)+.(<name)e.seen do.
            bad 'bad option ',word return.
        end.
        value =. (position+1)}.word
        if. name-:'KEYS' do.
            if. -.valid_name value do. bad 'bad option ',word return. end.
        else.
            if. -.1 6 width_digits value do. bad 'bad option ',word return. end.
            value =. num value
            range =. name get_key limits
            if. (value<0{range)+.value>1{range do. bad 'bad option ',word return. end.
        end.
        seen =. seen,<name
        options =. ((<name),<value) put_key options
    end.
    options
)
default_options =: 3 : '(''BREAK'' option_limits y) parse_options 0$a:'
validate_job =: 3 : 0
    words =. y
    command =. 0{::words
    newname =. ''
    if. (<command)e.NamingCommands do.
        if. 5<:#words do.
            if. 'AS'-:_2{::words do.
                newname =. _1{::words
                words =. _2}.words
                if. -.valid_name newname do. bad 'bad syntax' return. end.
            end.
        end.
    end.
    select. command
    case. 'ENCRYPT';'DECRYPT' do. valid =. 4=#words
    case. 'BREAK' do. valid =. 3<:#words
    case. 'COMPARE' do. valid =. 3=#words
    case. do. valid =. (#words)e.2 3
    end.
    if. -.valid do. bad 'bad syntax' return. end.
    cipher =. key =. second =. ''
    options =. empty_table ''
    if. (<command)e.NamingCommands do.
        cipher =. 1{::words
        if. -.(<cipher)e.Ciphers do. bad 'unknown cipher ',cipher return. end.
    end.
    if. (<command)e.;:'ENCRYPT DECRYPT' do.
        key =. cipher parse_key 2{::words
        if. #JobError do. 0$a: return. end.
        source =. 3{::words
    elseif. command-:'BREAK' do.
        source =. 2{::words
        options =. (command option_limits cipher) parse_options 3}.words
        if. #JobError do. 0$a: return. end.
        if. cipher-:'playfair' do.
            if. 0=#'KEYS' get_key options do. bad 'missing option KEYS' return. end.
        end.
    else.
        source =. 1{::words
        if. command-:'COMPARE' do. second =. 2{::words
        else.
            options =. (command option_limits cipher) parse_options 2}.words
            if. #JobError do. 0$a: return. end.
        end.
    end.
    references =. <source
    if. command-:'COMPARE' do. references =. references,<second
    elseif. 'KEYS' has_key options do.
        name =. 'KEYS' get_key options
        if. #name do. references =. references,<name end.
    end.
    for_box. references do.
        name =. >box
        if. -.name has_key Messages do. bad 'unknown message ',name return. end.
    end.
    if. #newname do.
        if. newname has_key Messages do. bad 'duplicate message ',newname return. end.
    end.
    (<command),(<cipher),(<key),(<source),(<newname),(<options),<second
)
message_text =: 3 : 'LF join y get_key Messages'
job_prefix =: 3 : '''JOB '',(number JobCount),'' '',0{::y'
as_suffix =: 3 : 0
    if. #y do. ' as=',y else. '' end.
)
number_list =: 3 : ''','' join number&.><"0 y'
count_list =: 3 : 0
    top =. top_counts y
    items =. 0$a:
    for_index. i.#top do.
        'pair count' =. index{top
        items =. items,<pair,':',number count
    end.
    ' ' join items
)
group_form =: 3 : 0
    text =. y
    lines =. 0$a:
    while. #text do.
        line =. (50<.#text){.text
        text =. 50}.text
        groups =. 0$a:
        while. #line do.
            groups =. groups,<(5<.#line){.line
            line =. 5}.line
        end.
        lines =. lines,<' ' join groups
    end.
    lines
)
transform_text =: 4 : 0
    'cipher key decrypt' =. x
    if. (<cipher)e.SubstitutionCiphers do. x substitute y
    elseif. cipher-:'railfence' do. ((<key),<decrypt) rail_fence y
    elseif. cipher-:'columnar' do. ((<key),<decrypt) columnar y
    else. ((<key),<decrypt) playfair y end.
)
solution_lines =: 4 : 0
    'cipher key' =. x
    'text letters' =. y
    args =. (<cipher),(<key),<1
    if. (<cipher)e.SubstitutionCiphers do. LF split args transform_text text
    else. group_form args transform_text letters end.
)
playfair_keys =: 3 : 0
    keys =. 0$a:
    index =. 0
    while. index<#y do.
        if. -.is_letter index{y do. index =. index+1
        continue. end.
        start =. index
        while. index<#y do.
            if. -.is_letter index{y do. break. end.
            index =. index+1
        end.
        key =. replace_j uppercase (index-start){.start}.y
        if. -.(<key)e.keys do. keys =. keys,<key end.
    end.
    keys
)
period_profile =: 4 : 0
    repeats =. repeated_trigrams y
    gaps =. 0$0
    for_box. repeats do. gaps =. gaps,2{::>box end.
    periods =. 0$a:
    for_length. >:i.x do.
        indices =. length column_indices y
        average =. (+/indices) div length
        kasiski =. +/0=length|gaps
        periods =. periods,<(<length),(<indices),(<average),<kasiski
    end.
    (<periods),(<repeats),<#gaps
)
profile_lines =: 3 : 0
    'periods repeats gapcount' =. y
    lines =. 0$a:
    for_box. periods do.
        'length indices average kasiski' =. >box
        lines =. lines,<'L=',(number length),' ioc=',(number average),' kasiski=',(number kasiski),' cols=',number_list indices
    end.
    lines =. lines,<'kasiski repeats=',(number #repeats),' spacings=',number gapcount
    for_box. repeats do.
        'trigram positions gaps divisor' =. >box
        lines =. lines,<trigram,' at=',(number_list positions),' gaps=',(number_list gaps),' gcd=',number divisor
    end.
    lines
)
choose_length =: 4 : 0
    'periods repeats gapcount' =. y
    threshold =. 'IOC' get_key x
    kasiskilength =. 0
    if. gapcount do.
        for_box. }.periods do.
            'length indices average kasiski' =. >box
            if. (100*kasiski)>:gapcount*'KASISKI' get_key x do. kasiskilength =. length end.
        end.
    end.
    if. kasiskilength do.
        if. (2{::(kasiskilength-1){::periods)>:threshold do.
            (<kasiskilength),<'kasiski' return.
        end.
    end.
    bestlength =. 1
    bestaverage =. _1
    for_box. periods do.
        'length indices average kasiski' =. >box
        if. average>:threshold do. (<length),<'ioc' return. end.
        if. average>bestaverage do. bestaverage =. average
        bestlength =. length end.
    end.
    (<bestlength),<'maxioc'
)
column_key =: 4 : 0
    'letters length' =. y
    key =. ''
    for_box. length columns letters do.
        values =. Alphabet i.>box
        bestshift =. 0
        bestscore =. _1
        for_shift. i.26 do.
            previous =. shift
            score =. 0
            for_value. values do.
                plain =. 26|value-previous
                score =. score+plain{Monograms
                if. x-:'autokey' do. previous =. plain end.
            end.
            if. score>bestscore do. bestscore =. score
            bestshift =. shift end.
        end.
        key =. key,bestshift{Alphabet
    end.
    key
)
permutations =: 3 : 0
    if. 0=#y do. <'' return. end.
    result =. 0$a:
    for_index. i.#y do.
        rest =. (index{.y),(index+1)}.y
        for_box. permutations rest do.
            result =. result,<(index{y),>box
        end.
    end.
    result
)
make_candidate =: 4 : 0
    'cipher key' =. x
    plain =. (x,<1) transform_text y
    if. (<cipher)e.;:'caesar affine' do. score =. monogram_fitness plain
    else. score =. bigram_fitness plain end.
    (<key),(<plain),<score
)
break_cipher =: 4 : 0
    cipher =. x
    'letters options keylist' =. y
    keys =. 0$a:
    select. cipher
    case. 'caesar' do. keys =. number&.><"0 i.26
    case. 'affine' do.
        for_a. AffineMultipliers do.
            for_b. i.26 do. keys =. keys,<(number a),',',number b end.
        end.
    case. 'railfence' do.
        keys =. number&.><"0 2+i.('MAXRAILS' get_key options)-1
    case. 'columnar' do.
        for_width. 2+i.('MAXLEN' get_key options)-1 do.
            keys =. keys,permutations (>:i.width){Digits
        end.
    case. 'playfair' do. keys =. keylist
    case. do.
        for_length. >:i.'MAXLEN' get_key options do.
            keys =. keys,<cipher column_key (<letters),<length
        end.
    end.
    records =. 0$a:
    for_box. keys do.
        records =. records,<((<cipher),box) make_candidate letters
    end.
    profile =. 0$a:
    length =. passes =. changes =. 0
    method =. ''
    if. cipher-:'vigenere' do.
        profile =. ('MAXLEN' get_key options) period_profile letters
        'length method' =. options choose_length profile
        initial =. (length-1){::records
        key =. 0{::initial
        reference =. 2{::initial
        while. passes<'REFINE' get_key options do.
            passes =. passes+1
            changed =. 0
            for_index. i.length do.
                bestletter =. 'A'
                bestscore =. _1
                for_letter. Alphabet do.
                    candidate =. letter index}key
                    plain =. ((<'vigenere'),(<candidate),<1) substitute letters
                    score =. bigram_fitness plain
                    if. score>bestscore do. bestscore =. score
                    bestletter =. letter end.
                end.
                if. bestscore>reference do.
                    key =. bestletter index}key
                    reference =. bestscore
                    changes =. changes+1
                    changed =. 1
                end.
            end.
            if. -.changed do. break. end.
        end.
        resultkey =. key
        resultscore =. reference
    end.
    scores =. 0$0
    for_box. records do. scores =. scores,2{::>box end.
    order =. /:(-scores),.i.#scores
    ranked =. order{records
    if. -.cipher-:'vigenere' do.
        resultkey =. 0{::0{::ranked
        resultscore =. 2{::0{::ranked
    end.
    (<resultkey),(<resultscore),(<ranked),(<profile),(<length),(<method),(<passes),<changes
)
store_lines =: 4 : 0
    Results =: Results,y
    if. #x do. Messages =: ((<x),<y) put_key Messages end.
    i.0
)
transform_job =: 3 : 0
    'command cipher key source newname options second' =. y
    text =. message_text source
    letters =. letter_string text
    if. 0=#letters do. bad 'no letters' return. end.
    decrypt =. command-:'DECRYPT'
    if. decrypt*.cipher-:'playfair' do.
        if. -.valid_playfair letters do. bad 'bad playfair text' return. end.
    end.
    args =. (<cipher),(<key),<decrypt
    if. (<cipher)e.SubstitutionCiphers do.
        transformed =. args transform_text text
        lines =. LF split transformed
    else.
        transformed =. args transform_text letters
        lines =. group_form transformed
    end.
    header =. (job_prefix y),' ',cipher,' key=',key,' source=',source
    header =. header,' letters=',(number #letter_string transformed),' lines=',(number #lines),as_suffix newname
    Results =: Results,<header
    newname store_lines lines
)
break_job =: 3 : 0
    'command cipher key source newname options second' =. y
    text =. message_text source
    letters =. letter_string text
    if. 40>#letters do. bad 'text too short' return. end.
    keylist =. 0$a:
    if. cipher-:'playfair' do.
        if. -.valid_playfair letters do. bad 'bad playfair text' return. end.
        keylist =. playfair_keys message_text 'KEYS' get_key options
        if. 0=#keylist do. bad 'empty key list' return. end.
    end.
    result =. cipher break_cipher (<letters),(<options),<keylist
    'key score ranked profile length method passes changes' =. result
    lines =. ((<cipher),<key) solution_lines (<text),<letters
    header =. (job_prefix y),' ',cipher,' source=',source
    Results =: Results,<header,' key=',key,' score=',(number score),' lines=',(number #lines),as_suffix newname
    newname store_lines lines
    margin =. 0
    if. 1<#ranked do. margin =. (2{::0{::ranked)-2{::1{::ranked end.
    Candidates =: Candidates,<header,' tried=',(number #ranked),' margin=',number margin
    count =. (#ranked)<.'TOP' get_key options
    for_index. i.count do.
        'candidatekey plain candidatescore' =. index{::ranked
        Candidates =: Candidates,<(number index+1),' ',candidatekey,' ',(number candidatescore),' ',40{.plain
    end.
    if. cipher-:'vigenere' do.
        Analysis =: Analysis,(<header),<'letters=',number #letters
        Analysis =: Analysis,profile_lines profile
        Analysis =: Analysis,<'decision length=',(number length),' method=',method
        Analysis =: Analysis,<'refine passes=',(number passes),' changes=',(number changes),' key=',key
    elseif. cipher-:'playfair' do.
        pairs =. 2 pair_counts replace_j letters
        square =. playfair_square key
        rows =. 0$a:
        for_start. 5*i.5 do. rows =. rows,<5{.start}.square end.
        Analysis =: Analysis,(<header),<'letters=',number #letters
        Analysis =: Analysis,<'digraphs pairs=',(number (#letters) div 2),' distinct=',number #pairs
        Analysis =: Analysis,<'top ',count_list pairs
        Analysis =: Analysis,<'square ',' ' join rows
    end.
    i.0
)
analyze_job =: 3 : 0
    'command cipher key source newname options second' =. y
    letters =. letter_string message_text source
    count =. #letters
    if. count<40 do. bad 'text too short' return. end.
    counts =. letter_counts letters
    distinct =. +/counts>0
    doubles =. I.(}:letters)=}.letters
    pairdoubles =. +/0=2|doubles
    header =. (job_prefix y),' source=',source
    Results =: Results,<header,' letters=',number count
    report =. (<header),<'letters=',number count
    report =. report,<'ioc=',(number ioc letters),' mono=',(number monogram_fitness letters),' bigram=',number bigram_fitness letters
    report =. report,<'doubles=',(number #doubles),' pair_doubles=',(number pairdoubles),' distinct=',number distinct
    for_index. i.26 do.
        occurrences =. index{counts
        report =. report,<(index{Alphabet),' ',(number occurrences),' ',occurrences percentage count
    end.
    report =. report,<'bigrams ',count_list 1 pair_counts letters
    report =. report,profile_lines ('MAXLEN' get_key options) period_profile letters
    Analysis =: Analysis,report
    i.0
)
compare_job =: 3 : 0
    'command cipher key source newname options second' =. y
    first =. letter_string message_text source
    other =. letter_string message_text second
    header =. (job_prefix y),' ',source,' ',second
    if. first-:other do.
        Results =: Results,<header,' equal letters=',number #first
        i.0 return.
    end.
    shared =. (#first)<.#other
    mismatches =. I.(shared{.first)~:shared{.other
    position =. shared+1
    if. #mismatches do. position =. 1+{.mismatches end.
    Results =: Results,<header,' differ letters=',(number #first),',',(number #other),' first=',(number position),' mismatches=',number #mismatches
    i.0
)
identify_job =: 3 : 0
    'command cipher key source newname options second' =. y
    text =. message_text source
    letters =. letter_string text
    count =. #letters
    if. count<40 do. bad 'text too short' return. end.
    index =. ioc letters
    average =. (monogram_fitness letters) div count
    distinct =. +/0<letter_counts letters
    shaped =. (0=2|count)*.(-.'J'e.letters)*.valid_playfair letters
    keylist =. 0$a:
    ciphers =. 0$a:
    if. shaped do.
        family =. 'playfair'
        keyname =. 'KEYS' get_key options
        if. #keyname do.
            keylist =. playfair_keys message_text keyname
            if. 0=#keylist do. bad 'empty key list' return. end.
            ciphers =. <'playfair'
        end.
    elseif. (index>:5500)*.average>:44 do.
        family =. 'transposition'
        ciphers =. ;:'railfence columnar'
    elseif. index>:5500 do.
        family =. 'monoalphabetic'
        ciphers =. <'affine'
    else.
        family =. 'polyalphabetic'
        ciphers =. ;:'vigenere autokey'
    end.
    shape =. 'no'
    if. shaped do. shape =. 'yes' end.
    header =. (job_prefix y),' source=',source
    report =. <header
    report =. report,<'letters=',(number count),' ioc=',(number index),' mono_avg=',(number average),' distinct=',(number distinct),' shape=',shape
    report =. report,<'family=',family
    chosen =. 0$a:
    chosencipher =. ''
    for_box. ciphers do.
        cipher =. >box
        result =. cipher break_cipher (<letters),(<default_options cipher),<keylist
        report =. report,<'try ',cipher,' key=',(0{::result),' score=',number 1{::result
        better =. 0=#chosen
        if. #chosen do. better =. (1{::result)>1{::chosen end.
        if. better do. chosen =. result
        chosencipher =. cipher end.
    end.
    header =. header,' family=',family
    if. 0=#chosen do. Results =: Results,<header
    else.
        key =. 0{::chosen
        if. chosencipher-:'affine' do.
            parts =. ',' split key
            if. 1=num 0{::parts do.
                chosencipher =. 'caesar'
                key =. 1{::parts
            end.
        end.
        lines =. ((<chosencipher),<key) solution_lines (<text),<letters
        Results =: Results,<header,' cipher=',chosencipher,' key=',key,' score=',(number 1{::chosen),' lines=',number #lines
        Results =: Results,lines
        report =. report,<'choice ',chosencipher
    end.
    Analysis =: Analysis,report
    i.0
)
process_job =: 3 : 0
    JobCount =: JobCount+1
    JobError =: ''
    words =. ' ' split y
    command =. 0{::words
    index =. Commands i.<command
    if. index=#Commands do.
        Results =: Results,<'JOB ',(number JobCount),' ERROR unknown command'
        i.0 return.
    end.
    job =. validate_job words
    if. 0=#JobError do.
        select. command
        case. 'ENCRYPT';'DECRYPT' do. transform_job job
        case. 'BREAK' do. break_job job
        case. 'ANALYZE' do. analyze_job job
        case. 'COMPARE' do. compare_job job
        case. 'IDENTIFY' do. identify_job job
        end.
    end.
    if. #JobError do.
        ErrorCounts =: (1+index{ErrorCounts) index}ErrorCounts
        Results =: Results,<'JOB ',(number JobCount),' ERROR ',JobError
    else. OkCounts =: (1+index{OkCounts) index}OkCounts end.
    i.0
)
read_messages =: 3 : 0
    messages =. empty_table ''
    name =. ''
    body =. 0$a:
    for_box. read_lines y do.
        line =. >box
        if. 0=#name do.
            if. #line do. name =. 8}.line
            body =. 0$a: end.
        elseif. line-:'END' do.
            messages =. ((<name),<body) put_key messages
            name =. ''
        else. body =. body,<line end.
    end.
    messages
)
write_lines =: 4 : 0
    text =. ''
    for_box. y do. text =. text,(>box),LF end.
    text 1!:2 <'output/',x
    i.0
)
main =: 3 : 0
    read_weights 'input/weights.txt'
    Messages =: read_messages 'input/messages.txt'
    JobCount =: 0
    OkCounts =: ErrorCounts =: 6$0
    Results =: Candidates =: Analysis =: 0$a:
    for_box. read_lines 'input/jobs.txt' do.
        line =. >box
        if. 0=#line do. continue. end.
        if. '#'={.line do. continue. end.
        process_job line
    end.
    for_index. i.6 do.
        Results =: Results,<'TOTAL ',(index{::Commands),' ok=',(number index{OkCounts),' errors=',number index{ErrorCounts
    end.
    ok =. +/OkCounts
    Results =: Results,<'SUMMARY jobs=',(number JobCount),' ok=',(number ok),' errors=',(number JobCount-ok),' messages=',number #Messages
    if. 0=#1!:0 <'output' do. 1!:5 <'output' end.
    'results.txt' write_lines Results
    'candidates.txt' write_lines Candidates
    'analysis.txt' write_lines Analysis
    i.0
)
main ''
