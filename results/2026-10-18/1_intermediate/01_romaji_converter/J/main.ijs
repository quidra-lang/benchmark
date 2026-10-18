NB. Exact mora identifiers in table order; 108=N, 109=Q, 110=L.
split =: 4 : 0
  <;._1 x,y
)
join =: 4 : 0
  if. 0=#y do. '' return. end.
  (#x) }. ; (<x) ,&.> y
)
NB. Strings from cut are lists; character literals/indexes may be atoms.
text_equal =: 4 : 0
  (,x) -: ,y
)
number =: 3 : 0
  , '0' 8!:2 y
)
at =: 4 : 0
  if. (x<0)+.x>:#y do. '' else. x{y end.
)
char_member =: 4 : 0
  (<y) e. <"0 x
)
column_error =: 4 : 0
  'col ',(number x),': ',y
)
DB_ROWS =: ' ' split 'a ka sa ta na ha ma ya ra wa ga za da ba pa'
DB_SYSTEMS =: ' ' split 'HEPBURN TRADITIONAL KUNREI NIHON WAPURO'
DB_GOJUON =: ' ' split 'a i u e o ka ki ku ke ko sa si su se so ta ti tu te to na ni nu ne no ha hi hu he ho ma mi mu me mo ya yu yo ra ri ru re ro wa wi we wo N'
DB_IROHA =: ' ' split 'i ro ha ni ho he to ti ri nu ru wo wa ka yo ta re so tu ne na ra mu u wi no o ku ya ma ke hu ko e te a sa ki yu me mi si we hi mo se su N'
initialize =: 3 : 0
  groups =. '|' split 'a i u e o|ka ki ku ke ko|sa si su se so|ta ti tu te to|na ni nu ne no|ha hi hu he ho|ma mi mu me mo|ya yu yo|ra ri ru re ro|wa wi we wo|ga gi gu ge go|za zi zu ze zo|da di du de do|ba bi bu be bo|pa pi pu pe po'
  DB_IDS =: 0$<''
  DB_ROW_IDS =: i.0
  DB_DANS =: 0$<''
  for_r. i.15 do.
    for_identifier. ' ' split r{::groups do.
      identifier =. >identifier
      DB_IDS =: DB_IDS,<identifier
      DB_ROW_IDS =: DB_ROW_IDS,r
      DB_DANS =: DB_DANS,<_1{.identifier
    end.
  end.
  for_r. 1 2 3 4 5 6 8 10 11 12 13 14 do.
    for_suffix. ;:'ya yu yo' do.
      suffix =. >suffix
      DB_IDS =: DB_IDS,<({.r{::DB_ROWS),suffix
      DB_ROW_IDS =: DB_ROW_IDS,r
      DB_DANS =: DB_DANS,<suffix
    end.
  end.
  exceptions =. ;:'si ti tu hu zi di du wi we wo'
  hepburn =. ;:'shi chi tsu fu ji ji zu i e o'
  wapuro =. ;:'shi chi tsu fu ji di du wi we wo'
  DB_SPELLS =: 0$<i.0
  for_sys. i.5 do.
    table =. 0$<''
    for_m. i.108 do.
      identifier =. m{::DB_IDS
      spelling =. identifier
      e =. exceptions i.<identifier
      if. e<#exceptions do.
        if. sys<2 do. spelling =. e{::hepburn
        elseif. sys=4 do. spelling =. e{::wapuro
        end.
      end.
      if. sys=2 do.
        select. identifier
        case. 'di' do. spelling =. 'zi'
        case. 'du' do. spelling =. 'zu'
        case. 'wi';'we';'wo' do. spelling =. 1}.identifier
        end.
      end.
      if. m>:72 do.
        prefix =. 2{.identifier
        suffix =. 2}.identifier
        if. (sys<2)+.sys=4 do.
          select. prefix
          case. 'sy' do. spelling =. 'sh',suffix
          case. 'ty' do. spelling =. 'ch',suffix
          case. 'zy' do. spelling =. 'j',suffix
          case. 'dy' do. if. sys<2 do. spelling =. 'j',suffix end.
          end.
        elseif. (sys=2)*.prefix text_equal 'dy' do.
          spelling =. 'zy',suffix
        end.
      end.
      table =. table,<spelling
    end.
    DB_SPELLS =: DB_SPELLS,<table
  end.
  i.0 0
)
initialize''
case_pattern =: 3 : 0
  letters =. y #~ y e. 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
  if. letters text_equal tolower letters do. 0 return. end.
  if. ({.y)e.'ABCDEFGHIJKLMNOPQRSTUVWXYZ' do.
    tail_letters =. (}.y) #~ (}.y)e.'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
    if. tail_letters text_equal tolower tail_letters do. 1 return. end.
  end.
  if. (#letters)>:2 do.
    if. letters text_equal toupper letters do. 2 return. end.
  end.
  _1
)
NB. Arguments: system, lowercase word, character offset. Longest then table order.
syllable =: 3 : 0
  'sys value position' =. y
  best =. _1
  width =. 0
  candidates =. ,sys
  if. sys=_1 do. candidates =. i.5 end.
  for_m. i.108 do.
    for_candidate. candidates do.
      spelling =. m{::candidate{::DB_SPELLS
      size =. #spelling
      if. size>width do.
        if. spelling text_equal size{.position}.value do.
          best =. m
          width =. size
        end.
      end.
    end.
  end.
  best,width
)
read_word =: 3 : 0
  'sys original start' =. y
  value =. tolower original
  morae =. i.0
  columns =. i.0
  p =. 0
  while. p<#value do.
    c =. p{value
    c2 =. (p+1) at value
    c3 =. (p+2) at value
    mora =. _1
    width =. 1
    problem =. ''
    if. c='-' do.
      if. 0=#morae do. problem =. 'misplaced long mark'
      elseif. ({:morae)>:108 do. problem =. 'misplaced long mark'
      else. mora =. 110
      end.
    elseif. c='''' do.
      problem =. 'misplaced apostrophe'
    else.
      matched =. syllable (<sys),(<value),<p
      next_match =. syllable (<sys),(<value),<p+1
      if. ({.matched)>:0 do.
        'mora width' =. matched
      elseif. ((sys=4)+.sys=_1)*.'xtu' text_equal 3{.p}.value do.
        mora =. 109
        width =. 3
      elseif. c='n' do.
        mora =. 108
        if. sys=_1 do.
          if. (c2 text_equal '''')+.((c2 text_equal 'n')*.-. 'aiueoy''' char_member c3) do. width =. 2 end.
        elseif. sys=4 do.
          if. c2 text_equal 'n' do. width =. 2 end.
        else.
          if. c2 text_equal '''' do. width =. 2 end.
        end.
      elseif. ((sys=1)+.sys=_1)*.(c='m')*.(1=#c2)*.'bmp' char_member c2 do.
        mora =. 108
      elseif. (-.c e.'aiueon')*.(c2 text_equal ,c)*.({.next_match)>:0 do.
        mora =. 109
      elseif. ((sys<2)+.sys=_1)*.(c='t')*.(c2 text_equal 'c')*.(c3 text_equal 'h')*.({.next_match)>:0 do.
        mora =. 109
      else.
        problem =. 'unknown syllable'
      end.
    end.
    if. #problem do.
      (<(start+p) column_error problem),(<i.0),<i.0 return.
    end.
    morae =. morae,mora
    columns =. columns,start+p
    p =. p+width
  end.
  (<''),(<morae),<columns
)
long_flags =: 3 : 0
  pairs =. (#y)$0
  elements =. (#y)$0
  p =. 0
  while. p<#y do.
    m =. p{y
    if. m=110 do. elements =. 1 p}elements end.
    if. (m<108)*.(p+1)<#y do.
      next_mora =. (p+1){y
      if. next_mora<5 do.
        vowel =. _1{.m{::DB_IDS
        next_vowel =. next_mora{::DB_IDS
        if. (vowel text_equal next_vowel)+.((vowel text_equal 'o')*.next_vowel text_equal 'u')+.((vowel text_equal 'e')*.next_vowel text_equal 'i') do.
          pairs =. 1 (p+1)}pairs
          if. (vowel text_equal 'o')+.((vowel text_equal 'u')*.next_vowel text_equal 'u') do.
            elements =. 1 (p+1)}elements
          end.
          p =. p+2
          continue.
        end.
      end.
    end.
    p =. p+1
  end.
  (<pairs),<elements
)
NB. Word record: original; column; case; morae; mora columns; poem line.
write_parts =: 3 : 0
  'sys word long_value' =. y
  morae =. 3{::word
  columns =. 4{::word
  elements =. 1{::long_flags morae
  result =. 0$<''
  for_k. i.#morae do.
    m =. k{morae
    next_mora =. _1
    if. (k+1)<#morae do. next_mora =. (k+1){morae end.
    next_spelling =. ''
    if. (next_mora>:0)*.next_mora<108 do.
      next_spelling =. next_mora{::sys{::DB_SPELLS
    end.
    first =. 0 at next_spelling
    piece =. ''
    if. k{elements do.
      vowel =. _1{.((k-1){morae){::DB_IDS
      if. long_value text_equal 'KEEP' do.
        if. m=110 do. piece =. '-'
        else. piece =. m{::sys{::DB_SPELLS
        end.
      elseif. long_value text_equal 'PASSPORT' do.
        if. (vowel text_equal 'o')*.-.'aiueo' char_member first do. piece =. 'h' end.
      elseif. long_value text_equal 'HYPHEN' do. piece =. '-'
      elseif. long_value text_equal 'DOUBLE' do. piece =. vowel
      end.
    elseif. m<108 do.
      piece =. m{::sys{::DB_SPELLS
    elseif. m=108 do.
      piece =. 'n'
      if. sys=4 do.
        if. (next_mora=108)+.(1=#first)*.'aiueoyn' char_member first do. piece =. 'nn' end.
      elseif. (sys=1)*.(1=#first)*.'bmp' char_member first do. piece =. 'm'
      elseif. (1=#first)*.'aiueoy' char_member first do. piece =. 'n'''
      end.
    elseif. m=109 do.
      if. (1=#first)*.-.'aiueon' char_member first do.
        piece =. first
        if. (sys<2)*.'ch' text_equal 2{.next_spelling do. piece =. 't' end.
      elseif. sys=4 do. piece =. 'xtu'
      else.
        (<(k{columns) column_error 'small tsu cannot be written'),<0$<'' return.
      end.
    end.
    result =. result,<piece
  end.
  (<''),<result
)
apply_case =: 3 : 0
  'value pattern case_value' =. y
  if. case_value text_equal 'LOWER' do. pattern =. 0
  elseif. case_value text_equal 'TITLE' do. pattern =. 1
  elseif. case_value text_equal 'UPPER' do. pattern =. 2
  end.
  if. pattern=1 do. (toupper {.value),}.value
  elseif. pattern=2 do. toupper value
  else. value
  end.
)
display_mora =: 4 : 0
  if. y<108 do. y{::x{::DB_SPELLS
  else. (y-108){::'N';'Q';'-'
  end.
)
loose =: 3 : 0
  y #~ -.1{::long_flags y
)
devoice =: 3 : 0
  p =. 'gzdbp' i.{.y
  if. p=5 do. y else. (p{'ksthh'),}.y end.
)
key_vectors =: 4 : 0
  order =. DB_GOJUON
  if. x text_equal 'IROHA' do. order =. DB_IROHA end.
  ranks =. i.0
  voices =. i.0
  sizes =. i.0
  marks =. y=110
  for_m. y do.
    if. m=110 do. continue. end.
    voice =. 0
    kana =. 'N'
    if. m=109 do. kana =. 'tu'
    elseif. m<108 do.
      kana =. devoice m{::DB_IDS
      r =. m{DB_ROW_IDS
      if. r=14 do. voice =. 2
      elseif. r>:10 do. voice =. 1
      end.
      if. m>:72 do. kana =. ({.kana),'i' end.
    end.
    ranks =. ranks,order i.<,kana
    voices =. voices,voice
    sizes =. sizes,m=109
    if. (m>:72)*.m<108 do.
      ranks =. ranks,order i.m{DB_DANS
      voices =. voices,0
      sizes =. sizes,1
    end.
  end.
  (<ranks),(<voices),(<sizes),<marks
)
base_sequence =: 3 : 0
  (0{::'GOJUON' key_vectors y) { DB_GOJUON
)
key_before =: 4 : 0
  for_v. i.4 do.
    a =. v{::x
    b =. v{::y
    for_k. i.(#a)<.#b do.
      if. (k{a)~:k{b do. (k{a)<k{b return. end.
    end.
    if. (#a)~:#b do. (#a)<#b return. end.
  end.
  0
)
matches_pattern =: 4 : 0
  previous =. 1,(#y)$0
  for_token. x do.
    current =. (1+#y)$0
    for_k. i.1+#y do.
      if. token=_2 do.
        value =. k{previous
        if. k>0 do. value =. value+.(k-1){current end.
      elseif. k>0 do.
        value =. ((k-1){previous)*.(token=_1)+.token=(k-1){y
      else. value =. 0
      end.
      current =. value k}current
    end.
    previous =. current
  end.
  {:previous
)
SETTINGS =: 'KEEP';'KEEP';'GOJUON'
execute =: 3 : 0
  fields =. ' ' split y
  command =. 0{::fields
  names =. ;:'SET TABLE CONVERT NORMALIZE REVERSE VALID DETECT DIFF SAME MORAE SYLLABLES ROW STATS SORT INDEX FIND HAIKU KAIBUN SHIRITORI'
  if. -. (<command)e.names do. 'ERROR unknown command ',command return. end.
  if. (<command)e.'SET';'TABLE' do.
    if. (#fields)<3 do. 'ERROR missing argument' return. end.
    if. (#fields)>3 do. 'ERROR too many arguments' return. end.
    if. command text_equal 'SET' do.
      option =. 1{::fields
      value =. 2{::fields
      p =. ('LONG';'CASE';'ORDER') i.<option
      if. p=3 do. 'ERROR unknown option ',option return. end.
      allowed =. (<;:'KEEP DROP PASSPORT HYPHEN DOUBLE'),(<;:'KEEP LOWER UPPER TITLE'),<;:'GOJUON IROHA'
      if. -. (<value)e.p{::allowed do. 'ERROR unknown value ',value return. end.
      SETTINGS =: (<value) p}SETTINGS
      option,'=',value return.
    end.
  end.
  argc =. 1
  if. (<command)e.'NORMALIZE';'DETECT' do. argc =. 0
  elseif. (<command)e.'CONVERT';'DIFF';'SAME';'FIND' do. argc =. 2
  end.
  if. -.command text_equal 'TABLE' do.
    if. (#fields)<argc+2 do. 'ERROR missing argument' return. end.
  end.
  source =. _1
  target =. _1
  if. argc>0 do.
    source =. DB_SYSTEMS i.1{fields
    if. source=5 do. 'ERROR unknown system ',1{::fields return. end.
    target =. source
  end.
  if. (<command)e.'CONVERT';'DIFF';'SAME' do.
    target =. DB_SYSTEMS i.2{fields
    if. target=5 do. 'ERROR unknown system ',2{::fields return. end.
  end.
  if. command text_equal 'TABLE' do.
    row =. DB_ROWS i.2{fields
    if. row=15 do. 'ERROR unknown row ',2{::fields return. end.
    ' ' join (row=DB_ROW_IDS)#source{::DB_SPELLS return.
  end.
  text_start =. 1+#command
  for_k. 1+i.argc do. text_start =. text_start+1+#k{::fields end.
  text =. text_start}.y
  pattern =. i.0
  if. command text_equal 'FIND' do.
    raw_pattern =. 2{::fields
    segment =. ''
    for_p. i.1+#raw_pattern do.
      c =. p at raw_pattern
      if. (0=#c)+.'?*' char_member c do.
        reading =. read_word (<source),(<segment),<1
        if. #0{::reading do. 'ERROR invalid pattern' return. end.
        pattern =. pattern,1{::reading
        if. #c do. pattern =. pattern,_1-(c text_equal '*') end.
        segment =. ''
      elseif. c e.'abcdefghijklmnopqrstuvwxyz''-' do.
        segment =. segment,c
      else. 'ERROR invalid pattern' return.
      end.
    end.
  end.
  separators =. ' 0123456789.,!?;:()"'
  if. (<command)e.'SAME';'HAIKU' do. separators =. separators,'/' end.
  word_chars =. 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ''-'
  invalid =. I.-.text e.separators,word_chars
  if. #invalid do. 'ERROR ',(1+{.invalid) column_error 'invalid character' return. end.
  words =. 0$<i.0
  word_lines =. i.0
  poem_line =. 0
  p =. 0
  while. p<#text do.
    if. (p{text)e.word_chars do.
      start =. p
      while. p<#text do.
        if. -. (p{text)e.word_chars do. break. end.
        p =. p+1
      end.
      original =. (p-start){.start}.text
      record =. (<original),(<1+start),(<case_pattern original),(<i.0),(<i.0),<poem_line
      words =. words,<record
      word_lines =. word_lines,poem_line
    else.
      if. '/'=p{text do. poem_line =. poem_line+1 end.
      p =. p+1
    end.
  end.
  line_words =. +/"1 (i.1+poem_line)=/word_lines
  if. command text_equal 'SAME' do.
    if. poem_line~:1 do. 'ERROR expected two texts' return. end.
    if. 0 e.line_words do. 'ERROR expected two texts' return. end.
  elseif. command text_equal 'HAIKU' do.
    if. -. poem_line e.2 4 do. 'ERROR expected 3 or 5 lines' return. end.
    if. 0 e.line_words do. 'ERROR expected 3 or 5 lines' return. end.
  end.
  if. 0=#words do. 'ERROR no words' return. end.
  for_word. words do.
    word =. >word
    if. _1=2{::word do. 'ERROR ',(1{::word) column_error 'mixed case' return. end.
  end.
  if. command text_equal 'DETECT' do.
    results =. 0$<''
    for_sys. i.5 do.
      verdict =. 'canonical'
      for_word. words do.
        word =. >word
        reading =. read_word (<sys),(0{word),1{word
        if. #0{::reading do. verdict =. 'error' break. end.
        word =. (1{reading) 3}word
        word =. (2{reading) 4}word
        written =. write_parts (<sys),(<word),<'KEEP'
        if. #0{::written do. verdict =. 'error' break. end.
        canonical =. apply_case (<;1{::written),(2{word),<'KEEP'
        if. -. canonical text_equal 0{::word do. verdict =. 'readable' end.
      end.
      results =. results,<(sys{::DB_SYSTEMS),'=',verdict
    end.
    ' ' join results return.
  end.
  NB. Finish every parse before any command-specific writing.
  for_k. i.#words do.
    word =. k{::words
    sys =. source
    if. (command text_equal 'SAME')*.1=k{word_lines do. sys =. target end.
    reading =. read_word (<sys),(0{word),1{word
    if. #0{::reading do. 'ERROR ',0{::reading return. end.
    word =. (1{reading) 3}word
    word =. (2{reading) 4}word
    words =. (<word) k}words
  end.
  if. command text_equal 'NORMALIZE' do. target =. 0 end.
  if. (<command)e.'CONVERT';'NORMALIZE';'REVERSE' do.
    result =. ''
    cursor =. 0
    for_word. words do.
      word =. >word
      start =. (1{::word)-1
      result =. result, (start-cursor){.cursor}.text
      writable =. word
      if. command text_equal 'REVERSE' do.
        morae =. 3{::writable
        for_k. i.#morae do.
          if. 110=k{morae do.
            vowel =. _1{.((k-1){morae){::DB_IDS
            morae =. (DB_IDS i.<vowel) k}morae
          end.
        end.
        writable =. (<|.morae) 3}writable
        writable =. (<|.4{::writable) 4}writable
      end.
      written =. write_parts (<target),(<writable),0{SETTINGS
      if. #0{::written do. 'ERROR ',0{::written return. end.
      result =. result,apply_case (<;1{::written),(2{word),1{SETTINGS
      cursor =. start+#0{::word
    end.
    result,cursor}.text return.
  end.
  if. command text_equal 'VALID' do.
    for_word. words do.
      word =. >word
      written =. write_parts (<source),(<word),<'KEEP'
      if. #0{::written do. 'ERROR ',0{::written return. end.
      canonical =. apply_case (<;1{::written),(2{word),<'KEEP'
      original =. 0{::word
      if. -. canonical text_equal original do.
        k =. 0
        while. k<((#canonical)<.#original) do.
          if. (k{canonical)~:k{original do. break. end.
          k =. k+1
        end.
        'INVALID col ',(number k+1{::word),': expected ',canonical return.
      end.
    end.
    'VALID' return.
  end.
  if. (<command)e.'DIFF';'FIND' do.
    selected =. 0$<''
    for_word. words do.
      word =. >word
      if. command text_equal 'FIND' do.
        if. pattern matches_pattern 3{::word do. selected =. selected,0{word end.
      else.
        left =. write_parts (<source),(<word),0{SETTINGS
        if. #0{::left do. 'ERROR ',0{::left return. end.
        right =. write_parts (<target),(<word),0{SETTINGS
        if. #0{::right do. 'ERROR ',0{::right return. end.
        a =. apply_case (<;1{::left),(2{word),1{SETTINGS
        b =. apply_case (<;1{::right),(2{word),1{SETTINGS
        if. -. a text_equal b do. selected =. selected,<a,'>',b end.
      end.
    end.
    result =. (number #selected),' of ',number #words
    if. #selected do. result =. result,': ',' ' join selected end.
    result return.
  end.
  if. command text_equal 'SAME' do.
    'nleft nright' =. line_words
    exact =. 1
    for_k. i.nleft<.nright do.
      a =. 3{::k{::words
      b =. 3{::(nleft+k){::words
      if. -. (loose a) text_equal loose b do. 'DIFFERENT at word ',number 1+k return. end.
      if. -. a text_equal b do. exact =. 0 end.
    end.
    if. nleft~:nright do. 'DIFFERENT at word ',number 1+nleft<.nright return. end.
    if. exact do. 'EXACT' else. 'LOOSE' end. return.
  end.
  if. command text_equal 'HAIKU' do.
    counts =. (1+poem_line)$0
    for_k. i.#words do.
      line =. k{word_lines
      counts =. ((line{counts)+#3{::k{::words) line}counts
    end.
    expected =. 5 7 5
    kind =. 'haiku'
    if. poem_line=4 do.
      expected =. 5 7 5 7 7
      kind =. 'tanka'
    end.
    verdict =. 'NG'
    if. counts text_equal expected do. verdict =. 'OK' end.
    verdict,' ',kind,' ','-' join number&.><"0 counts return.
  end.
  if. (<command)e.'MORAE';'SYLLABLES';'ROW';'STATS' do.
    groups =. 0$<''
    total =. 0
    row_counts =. 10$0
    other_counts =. 6$0
    for_word. words do.
      word =. >word
      morae =. 3{::word
      pieces =. 0$<''
      if. command text_equal 'SYLLABLES' do.
        written =. write_parts (<source),(<word),<'KEEP'
        if. #0{::written do. 'ERROR ',0{::written return. end.
        pieces =. 1{::written
      end.
      pairs =. 0{::long_flags morae
      parts =. 0$<''
      for_k. i.#morae do.
        m =. k{morae
        display =. source display_mora m
        if. command text_equal 'SYLLABLES' do.
          if. (k>0)*.((m>:108)+.k{pairs) do.
            parts =. (<(_1{::parts),k{::pieces) _1}parts
          else.
            parts =. parts,k{pieces
            total =. total+1
          end.
        elseif. command text_equal 'MORAE' do.
          parts =. parts,<display
          total =. total+1
        elseif. command text_equal 'ROW' do.
          detail =. 'special'
          if. m<108 do. detail =. ((m{DB_ROW_IDS){::DB_ROWS),' ',m{::DB_DANS end.
          groups =. groups,<display,': ',detail
        else.
          total =. total+1
          if. m>:108 do.
            p =. m-105
            other_counts =. (1+p{other_counts) p}other_counts
          else.
            r =. m{DB_ROW_IDS
            base =. r
            if. r>:10 do. base =. (r-10){1 2 3 5 5 end.
            row_counts =. (1+base{row_counts) base}row_counts
            if. r=14 do. other_counts =. (1+1{other_counts) 1}other_counts
            elseif. r>:10 do. other_counts =. (1+0{other_counts) 0}other_counts
            end.
            if. m>:72 do. other_counts =. (1+2{other_counts) 2}other_counts end.
          end.
        end.
      end.
      if. (<command)e.'MORAE';'SYLLABLES' do. groups =. groups,<'.' join parts end.
    end.
    if. command text_equal 'ROW' do. ', ' join groups return. end.
    if. (<command)e.'MORAE';'SYLLABLES' do. (number total),': ',' ' join groups return. end.
    result =. 'morae=',number total
    for_r. i.10 do.
      if. r{row_counts do. result =. result,' ',(r{::DB_ROWS),'=',number r{row_counts end.
    end.
    labels =. ;:'voiced semivoiced contracted N Q L'
    for_k. i.6 do. result =. result,' ',(k{::labels),'=',number k{other_counts end.
    result return.
  end.
  if. (<command)e.'SORT';'INDEX' do.
    order_ids =. i.0
    keys =. 0$<i.0
    for_k. i.#words do.
      keys =. keys,< (2{::SETTINGS) key_vectors 3{::k{::words
      order_ids =. order_ids,k
      position =. k
      while. position>0 do.
        if. -. (k{::keys) key_before ((position-1){order_ids){::keys do. break. end.
        order_ids =. ((position-1){order_ids) position}order_ids
        position =. position-1
      end.
      order_ids =. k position}order_ids
    end.
    groups =. 0$<''
    last_heading =. ''
    for_k. order_ids do.
      word =. k{::words
      if. command text_equal 'SORT' do. groups =. groups,0{word continue. end.
      first_kana =. 0{::base_sequence 3{::word
      heading =. first_kana
      if. ((2{::SETTINGS) text_equal 'GOJUON')*.-.first_kana text_equal 'N' do.
        heading =. ((DB_IDS i.<first_kana){DB_ROW_IDS){::DB_ROWS
      end.
      if. heading text_equal last_heading do.
        groups =. (<(_1{::groups),' ',0{::word) _1}groups
      else.
        groups =. groups,<heading,': ',0{::word
        last_heading =. heading
      end.
    end.
    if. command text_equal 'SORT' do. ' ' join groups else. '; ' join groups end. return.
  end.
  if. command text_equal 'KAIBUN' do.
    sequence =. 0$<''
    for_word. words do. sequence =. sequence,base_sequence 3{::>word end.
    verdict =. 'NO '
    if. sequence text_equal |.sequence do. verdict =. 'YES ' end.
    verdict,'.' join sequence return.
  end.
  previous_tail =. ''
  for_k. i.#words do.
    word =. k{::words
    sequence =. base_sequence 3{::word
    prefix =. 'NG ',(number 1+k),': ',0{::word
    if. k>0 do.
      if. -. (0{::sequence) text_equal previous_tail do.
        prefix,' must start with ',(DB_IDS i.<previous_tail){::source{::DB_SPELLS return.
      end.
    end.
    for_earlier. i.k do.
      if. (3{::earlier{::words) text_equal 3{::word do. prefix,' is repeated' return. end.
    end.
    previous_tail =. _1{::sequence
    if. previous_tail text_equal 'N' do. prefix,' ends with N' return. end.
  end.
  'OK ',number #words
)
main =: 3 : 0
  input =. 1!:1 (3)
  if. LF~:{:input do. input=.input,LF end.
  lines =. <;._2 input
  count =. 0".0{::lines
  for_k. 1+i.count do.
    result =. execute k{::lines
    (result,LF) 1!:2 (4)
  end.
  i.0 0
)
main''
