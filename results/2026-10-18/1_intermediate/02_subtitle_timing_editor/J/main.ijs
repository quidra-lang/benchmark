NB. Milliseconds and products are integers; division explicitly enters exact rationals.
split =: 4 : 0
  <;._1 x,y
)
join =: 4 : 0
  if. 0=#y do. '' return. end.
  (#x)}.;(<x),&.>y
)
NB. Strings from cut are lists; character literals/indexes may be atoms.
text_equal =: 4 : 0
  (,x) -: ,y
)
number =: 3 : 0
  ,'0' 8!:2 y
)
floor_ratio =: 4 : 0
  <.(x:x)%x:y
)
rounded =: 4 : 0
  if. y<0 do. (-x) rounded -y return. end.
  ((2*x)+y) floor_ratio 2*y
)
digits =: 4 : 0
  (0<#y)*.((#y)<:x)*.*./y e.'0123456789'
)
time_value =: 3 : 0
  if. 12~:#y do. _1 return. end.
  if. -. ':,:' text_equal 5 8 2{y do. _1 return. end.
  raw =. (2{.y),(2{.3}.y),(2{.6}.y),9}.y
  if. -.9 digits raw do. _1 return. end.
  hours =. 0".2{.y
  minutes =. 0".2{.3}.y
  seconds =. 0".2{.6}.y
  if. (minutes>59)+.seconds>59 do. _1 return. end.
  (3600000*hours)+(60000*minutes)+(1000*seconds)+0".9}.y
)
padded =: 4 : 0
  value =. number y
  ((0>.x-#value)#'0'),value
)
time_text =: 4 : 0
  if. x text_equal 'ASS' do.
    c =. (y+5) floor_ratio 10
    (number c floor_ratio 360000),':',(2 padded 60|c floor_ratio 6000),':',(2 padded 60|c floor_ratio 100),'.',2 padded 100|c return.
  end.
  separator =. ','
  if. x text_equal 'VTT' do. separator =. '.' end.
  (2 padded y floor_ratio 3600000),':',(2 padded 60|y floor_ratio 60000),':',(2 padded 60|y floor_ratio 1000),separator,3 padded 1000|y
)
decimal_text =: 3 : 0
  (number y floor_ratio 100),'.',2 padded 100|y
)
NB. A cue is a boxed record: index; start; end; boxed text lines.
characters =: 3 : 0
  +/#&>3{::y
)
dialogue =: 3 : 0
  for_line. 3{::y do.
    if. '- ' text_equal 2{.>line do. 1 return. end.
  end.
  0
)
words_of =: 3 : 0
  words =. ' ' split ' ' join y
  words #~ 0<#&>words
)
wrap =: 4 : 0
  result =. 0$<''
  for_word. words_of y do.
    word =. >word
    if. 0=#result do. result =. ,<word
    elseif. ((#_1{::result)+1+#word)<:x do.
      result =. (<(_1{::result),' ',word) _1}result
    else. result =. result,<word
    end.
  end.
  result
)
list_line =: 4 : 0
  (number x),' ',(number 0{::y),' ',('SRT' time_text 1{::y),' ',('SRT' time_text 2{::y),' ','|' join 3{::y
)
find_from =: 3 : 0
  'value needle start' =. y
  matches =. I.needle E.start}.value
  if. #matches do. start+{.matches else. _1 end.
)
markup =: 4 : 0
  tail =. x}.y
  tags =. '<i>';'</i>';'<b>';'</b>';'<u>';'</u>'
  for_k. i.6 do.
    tag =. k{::tags
    if. tag text_equal (#tag){.tail do. 1,(#tag),0,k return. end.
  end.
  if. '</font>' text_equal 7{.tail do. 2 7 0 0 return. end.
  if. ('<font' text_equal 5{.tail)*.(#tail)>5 do.
    if. (5{tail)e.' >' do.
      close =. find_from (<tail),(<'>' ),<5
      if. close>:0 do. 2,(1+close),0 0 return. end.
    end.
  end.
  if. (#tail)>:6 do.
    if. ('{\an' text_equal 4{.tail)*.('}'=5{tail)*.(4{tail)e.'123456789' do.
      3 6,(0".4{tail),0 return.
    end.
  end.
  0 1 0 0
)
spaces_trim =: 3 : 0
  positions =. I.y~:' '
  if. 0=#positions do. '' return. end.
  ((1+{:positions)-{.positions){.({.positions)}.y
)
convert_markup =: 4 : 0
  result =. ''
  removed =. 0
  first_code =. 0
  p =. 0
  ass_tags =. '{\i1}';'{\i0}';'{\b1}';'{\b0}';'{\u1}';'{\u0}'
  while. p<#y do.
    'kind width code tag' =. p markup y
    raw =. width{.p}.y
    if. kind~:0 do.
      removed =. removed+1
      if. (kind=3)*.first_code=0 do. first_code =. code end.
      if. (x text_equal 'VTT')*.kind=1 do. result =. result,raw
      elseif. x text_equal 'ASS' do.
        if. kind=1 do. result =. result,tag{::ass_tags
        elseif. kind=3 do. result =. result,raw
        end.
      end.
    elseif. x text_equal 'VTT' do.
      select. {.raw
      case. '&' do. result =. result,'&amp;'
      case. '<' do. result =. result,'&lt;'
      case. '>' do. result =. result,'&gt;'
      case. do. result =. result,raw
      end.
    else. result =. result,raw
    end.
    p =. p+width
  end.
  if. -.x text_equal 'ASS' do. result =. spaces_trim result end.
  (<result),(<removed),<first_code
)
clean_hi =: 3 : 0
  result =. ''
  segments =. 0
  p =. 0
  while. p<#y do.
    close =. ''
    if. '['=p{y do. close =. ']'
    elseif. '('=p{y do. close =. ')'
    end.
    end_at =. _1
    if. #close do. end_at =. find_from (<y),(<close),<p+1 end.
    if. end_at>:0 do.
      segments =. segments+1
      p =. 1+end_at
    else.
      result =. result,p{y
      p =. p+1
    end.
  end.
  result =. ' ' join words_of <result
  prefix =. ''
  if. '- ' text_equal 2{.result do. prefix =. '- ' end.
  body =. (#prefix)}.result
  colon =. body i.':'
  speaker =. (colon>0)*.colon<#body
  if. speaker do.
    label =. colon{.body
    speaker =. (({.label)e.'ABCDEFGHIJKLMNOPQRSTUVWXYZ')*.*./label e.'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 '
  end.
  if. speaker do. result =. ' ' join words_of <prefix,(1+colon)}.body end.
  (<result),(<segments),<speaker
)
schema =: 3 : 0
  select. y
  case. 'SEARCH';'REPLACE' do. ,<'string'
  case. 'AT' do. ,<'time'
  case. 'GAPS';'FIXOVERLAP';'EXTEND';'MERGE';'SPLIT' do. ,<'unsigned'
  case. 'FRAMES';'SNAP' do. ,<'fps'
  case. 'SHIFT' do. ,<'signed'
  case. 'SHIFTFROM' do. ;:'position signed'
  case. 'SCALE' do. ;:'unsigned unsigned'
  case. 'SYNC' do. ;:'position time position time'
  case. 'TIME' do. ;:'position time time'
  case. 'INSERT' do. ;:'position time time text'
  case. 'TEXT' do. ;:'position text'
  case. 'DELETE' do. ,<'position'
  case. do. 0$<''
  end.
)
CUES =: 0$<i.0
HISTORY =: 0$<i.0
execute =: 3 : 0
  fields =. ' ' split y
  command =. 0{::fields
  known =. ;:'LIST VALIDATE SEARCH AT GAPS STATS PRINT TOVTT TOASS FRAMES SHIFT SHIFTFROM SCALE SYNC SNAP FIXOVERLAP EXTEND TIME SORT RENUMBER MERGE SPLIT INSERT DELETE TEXT BALANCE STRIP CLEANHI REPLACE UNDO'
  if. -. (<command)e.known do. <'ERROR unknown command' return. end.
  kinds =. schema command
  if. (command text_equal 'DELETE')*.3=#fields do. kinds =. ;:'position position' end.
  string_tail =. (<command)e.'SEARCH';'INSERT';'TEXT';'REPLACE'
  if. (#fields)<1+#kinds do. <'ERROR bad arguments' return. end.
  if. -.string_tail do.
    if. (#fields)~:1+#kinds do. <'ERROR bad arguments' return. end.
  end.
  args =. 0$<''
  values =. i.0
  fps =. i.0
  for_k. i.#kinds do.
    argument =. (k+1){::fields
    if. string_tail*.k=(#kinds)-1 do. argument =. ' ' join (k+1)}.fields end.
    args =. args,<argument
    kind =. k{::kinds
    value =. 0
    if. kind text_equal 'time' do.
      value =. time_value argument
      if. value<0 do. <'ERROR bad arguments' return. end.
    elseif. kind text_equal 'fps' do.
      rate =. '/' split argument
      if. (#rate)>2 do. <'ERROR bad arguments' return. end.
      for_part. rate do.
        part =. >part
        if. -.9 digits part do. <'ERROR bad arguments' return. end.
        component =. 0".part
        if. (component<1)+.component>100000 do. <'ERROR bad arguments' return. end.
        fps =. fps,component
      end.
      if. 1=#fps do. fps =. fps,1 end.
    elseif. kind text_equal 'text' do.
      if. 0 e.#&>'|' split argument do. <'ERROR bad arguments' return. end.
    elseif. -.kind text_equal 'string' do.
      magnitude =. argument
      if. (kind text_equal 'signed')*.'-'={.argument do. magnitude =. }.argument end.
      if. -.9 digits magnitude do. <'ERROR bad arguments' return. end.
      value =. 0".magnitude
      if. '-'={.argument do. value =. -value end.
      if. (kind text_equal 'position')*.value<1 do. <'ERROR bad arguments' return. end.
    end.
    values =. values,value
  end.
  if. command text_equal 'REPLACE' do.
    pair =. '|' split 0{::args
    if. 2~:#pair do. <'ERROR bad arguments' return. end.
    if. 0 e.#&>pair do. <'ERROR bad arguments' return. end.
  end.
  if. (<command)e.'GAPS';'FIXOVERLAP';'MERGE' do.
    if. 60000<{.values do. <'ERROR bad arguments' return. end.
  elseif. command text_equal 'EXTEND' do.
    if. (1>{.values)+.60000<{.values do. <'ERROR bad arguments' return. end.
  elseif. command text_equal 'SPLIT' do.
    if. (10>{.values)+.80<{.values do. <'ERROR bad arguments' return. end.
  elseif. command text_equal 'SCALE' do.
    if. +./(values<1)+.values>100000 do. <'ERROR bad arguments' return. end.
  elseif. (command text_equal 'DELETE')*.2=#values do.
    if. (1{values)<0{values do. <'ERROR bad arguments' return. end.
  end.
  n =. #CUES
  for_k. i.#kinds do.
    if. 'position' text_equal k{::kinds do.
      limit =. n+(command text_equal 'INSERT')
      if. (k{values)>limit do. <'ERROR no cue ',number k{values return. end.
    end.
  end.
  if. command text_equal 'SYNC' do.
    if. (1{::((0{values)-1){::CUES)=1{::((2{values)-1){::CUES do. <'ERROR sync points coincide' return. end.
  end.
  if. command text_equal 'UNDO' do.
    if. 0=#HISTORY do. <'ERROR nothing to undo' return. end.
    record =. _1{::HISTORY
    CUES =: 1{::record
    HISTORY =: }:HISTORY
    <'UNDO command=',0{::record return.
  end.
  modifying =. ;:'SHIFT SHIFTFROM SCALE SYNC SNAP FIXOVERLAP EXTEND TIME SORT RENUMBER MERGE SPLIT INSERT DELETE TEXT BALANCE STRIP CLEANHI REPLACE'
  if. (<command)e.modifying do.
    record =. (<command),<CUES
    HISTORY =: HISTORY,<record
  end.
  output =. 0$<''
  if. (<command)e.'LIST';'AT';'SEARCH';'GAPS';'FRAMES' do.
    count =. 0
    for_k. i.n do.
      cue =. k{::CUES
      selected =. command text_equal 'LIST'
      if. command text_equal 'AT' do. selected =. ((1{::cue)<:0{values)*.(0{values)<2{::cue end.
      if. selected do.
        output =. output,< (k+1) list_line cue
        count =. count+1
      elseif. command text_equal 'SEARCH' do.
        needle =. 0{::args
        for_line. 3{::cue do.
          line =. >line
          if. +./needle E.line do.
            output =. output,<(number k+1),' ',('SRT' time_text 1{::cue),' ',line
            count =. count+1
            break.
          end.
        end.
      elseif. (command text_equal 'GAPS')*.(k+1)<n do.
        gap =. (1{::(k+1){::CUES)-2{::cue
        if. gap<0{values do.
          output =. output,<(number k+1),' ',(number k+2),' ',number gap
          count =. count+1
        end.
      elseif. command text_equal 'FRAMES' do.
        f =. ((1{::cue)*0{fps) floor_ratio 1000*1{fps
        g =. ((2{::cue)*0{fps) floor_ratio 1000*1{fps
        output =. output,<(number k+1),' ',(number f),' ',number g
      end.
    end.
    if. command text_equal 'AT' do. output =. output,<'AT active=',number count
    elseif. command text_equal 'SEARCH' do. output =. output,<'SEARCH found=',number count
    elseif. command text_equal 'GAPS' do. output =. output,<'GAPS count=',number count
    end.
    output return.
  end.
  if. command text_equal 'VALIDATE' do.
    for_k. i.n do.
      cue =. k{::CUES
      duration =. (2{::cue)-1{::cue
      prefix =. 'cue ',(number k+1),': '
      if. (0{::cue)~:k+1 do. output =. output,<prefix,'index ',(number 0{::cue),' (expected ',(number k+1),')' end.
      if. duration<:0 do. output =. output,<prefix,'end not after start' end.
      if. k>0 do.
        gap =. (2{::(k-1){::CUES)-1{::cue
        if. gap>0 do. output =. output,<prefix,'overlaps previous by ',(number gap),' ms' end.
      end.
      if. ((duration>:1)*.duration<700)+.duration>7000 do.
        label =. 'too long ('
        if. duration<700 do. label =. 'too short (' end.
        output =. output,<prefix,label,(number duration),' ms)'
      end.
      lines =. 3{::cue
      for_j. i.#lines do.
        if. 42<#j{::lines do. output =. output,<prefix,'line ',(number j+1),' too long (',(number #j{::lines),' chars)' end.
      end.
      if. (#lines)>:3 do. output =. output,<prefix,'too many lines (',(number #lines),')' end.
      count =. characters cue
      if. duration>:1 do.
        if. (count*1000)>21*duration do. output =. output,<prefix,'too fast (',(decimal_text (count*100000) floor_ratio duration),' cps)' end.
      end.
    end.
    output,<'VALIDATE problems=',number #output return.
  end.
  if. command text_equal 'STATS' do.
    output =. ,<'STATS cues=',number n
    if. n=0 do. output return. end.
    total =. 0
    count =. 0
    longest =. 0
    longest_duration =. _1
    gap_position =. 0
    largest_gap =. 0
    for_k. i.n do.
      cue =. k{::CUES
      duration =. 0>.(2{::cue)-1{::cue
      total =. total+duration
      if. duration>0 do. count =. count+characters cue end.
      if. duration>longest_duration do.
        longest_duration =. duration
        longest =. k+1
      end.
      if. (k+1)<n do.
        gap =. (1{::(k+1){::CUES)-2{::cue
        if. (gap_position=0)+.gap>largest_gap do.
          largest_gap =. gap
          gap_position =. k+1
        end.
      end.
    end.
    output =. output,<'duration total=',('SRT' time_text total),' mean=','SRT' time_text total floor_ratio n
    speed =. '-'
    if. total>0 do. speed =. decimal_text (count*100000) floor_ratio total end.
    output =. output,<'speed ',speed
    output =. output,<'longest cue=',(number longest),' duration=','SRT' time_text longest_duration
    gap_line =. 'gap none'
    if. n>1 do. gap_line =. 'gap cue=',(number gap_position),' ms=',number largest_gap end.
    output,<gap_line return.
  end.
  if. (<command)e.'PRINT';'TOVTT';'TOASS' do.
    if. command text_equal 'TOVTT' do. output =. 'WEBVTT';''
    elseif. command text_equal 'TOASS' do. output =. '[Events]';'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text'
    end.
    for_cue. CUES do.
      cue =. >cue
      lines =. 3{::cue
      first_code =. 0
      if. -.command text_equal 'PRINT' do.
        mode =. 'VTT'
        if. command text_equal 'TOASS' do. mode =. 'ASS' end.
        lines =. 0$<''
        for_line. 3{::cue do.
          converted =. mode convert_markup >line
          if. first_code=0 do. first_code =. 2{::converted end.
          if. (command text_equal 'TOASS')+.0<#0{::converted do. lines =. lines,0{converted end.
        end.
      end.
      if. command text_equal 'TOASS' do.
        output =. output,<'Dialogue: 0,',('ASS' time_text 1{::cue),',',('ASS' time_text 2{::cue),',Default,,0,0,0,,','\N' join lines
      elseif. #lines do.
        settings =. ''
        if. (command text_equal 'TOVTT')*.first_code>0 do.
          if. first_code>:7 do. settings =. settings,' line:0'
          elseif. first_code>:4 do. settings =. settings,' line:50%'
          end.
          if. 1=3|first_code do. settings =. settings,' align:start'
          elseif. 0=3|first_code do. settings =. settings,' align:end'
          end.
        end.
        style =. 'SRT'
        if. command text_equal 'TOVTT' do. style =. 'VTT' end.
        output =. output,<number 0{::cue
        output =. output,<(style time_text 1{::cue),' --> ',(style time_text 2{::cue),settings
        output =. output,lines, (< '')
      end.
    end.
    output return.
  end.
  if. (<command)e.'SHIFT';'SHIFTFROM';'SCALE';'SYNC';'SNAP' do.
    begin =. 0
    if. command text_equal 'SHIFTFROM' do. begin =. (0{values)-1 end.
    clamped =. 0
    changed =. 0
    sync_start =. 0
    sync_den =. 1
    if. command text_equal 'SYNC' do.
      sync_start =. 1{::((0{values)-1){::CUES
      sync_den =. (1{::((2{values)-1){::CUES)-sync_start
    end.
    for_k. begin+i.n-begin do.
      cue =. k{::CUES
      was_clamped =. 0
      for_j. 1 2 do.
        original =. j{::cue
        value =. original
        if. command text_equal 'SHIFT' do. value =. value+0{values
        elseif. command text_equal 'SHIFTFROM' do. value =. value+1{values
        elseif. command text_equal 'SCALE' do. value =. (original*0{values) rounded 1{values
        elseif. command text_equal 'SYNC' do.
          numerator =. ((1{values)*sync_den)+((original-sync_start)*((3{values)-1{values))
          value =. numerator rounded sync_den
        else.
          frame =. (original*0{fps) rounded 1000*1{fps
          value =. (frame*1000*1{fps) rounded 0{fps
        end.
        if. value<0 do.
          was_clamped =. 1
          value =. 0
        end.
        changed =. changed+value~:original
        cue =. (<value) j}cue
      end.
      CUES =: (<cue) k}CUES
      clamped =. clamped+was_clamped
    end.
    if. command text_equal 'SNAP' do. <'SNAP changed=',number changed
    elseif. command text_equal 'SCALE' do. <'SCALE cues=',number n
    else. <command,' cues=',(number n-begin),' clamped=',number clamped
    end. return.
  end.
  if. command text_equal 'FIXOVERLAP' do.
    fixed =. 0
    failed =. 0
    for_k. i.0>.n-1 do.
      cue =. k{::CUES
      candidate =. (1{::(k+1){::CUES)-0{values
      if. (2{::cue)>candidate do.
        if. candidate>1{::cue do.
          cue =. (<candidate) 2}cue
          CUES =: (<cue) k}CUES
          fixed =. fixed+1
        else.
          failed =. failed+1
          output =. output,<'cue ',(number k+1),': cannot fix'
        end.
      end.
    end.
    output,<'FIXOVERLAP fixed=',(number fixed),' failed=',number failed return.
  end.
  if. command text_equal 'EXTEND' do.
    extended =. 0
    short =. 0
    for_k. i.n do.
      cue =. k{::CUES
      if. ((2{::cue)-1{::cue)<0{values do.
        candidate =. (1{::cue)+0{values
        if. (k+1)<n do. candidate =. candidate<.1{::(k+1){::CUES end.
        if. candidate>2{::cue do.
          cue =. (<candidate) 2}cue
          CUES =: (<cue) k}CUES
          extended =. extended+1
        end.
      end.
      short =. short+((2{::cue)-1{::cue)<0{values
    end.
    <'EXTEND extended=',(number extended),' short=',number short return.
  end.
  if. (<command)e.'TIME';'TEXT' do.
    p =. (0{values)-1
    cue =. p{::CUES
    if. command text_equal 'TIME' do.
      cue =. (<1{values) 1}cue
      cue =. (<2{values) 2}cue
      result =. 'TIME cue=',number 1+p
    else.
      lines =. '|' split 1{::args
      cue =. (<lines) 3}cue
      result =. 'TEXT cue=',(number 1+p),' lines=',number #lines
    end.
    CUES =: (<cue) p}CUES
    <result return.
  end.
  if. command text_equal 'SORT' do.
    keys =. 0 2$0
    for_cue. CUES do.
      keys =. keys,>1 2{>cue
    end.
    order =. /:keys
    moved =. +/order~:i.n
    CUES =: order{CUES
    <'SORT moved=',number moved return.
  end.
  if. command text_equal 'RENUMBER' do.
    changed =. 0
    for_k. i.n do.
      cue =. k{::CUES
      if. (0{::cue)~:k+1 do.
        changed =. changed+1
        cue =. (<k+1) 0}cue
        CUES =: (<cue) k}CUES
      end.
    end.
    <'RENUMBER changed=',number changed return.
  end.
  if. command text_equal 'INSERT' do.
    p =. (0{values)-1
    cue =. (<p+1),(<1{values),(<2{values),<'|' split 3{::args
    CUES =: (p{.CUES),(<cue),p}.CUES
    <'INSERT cue=',(number p+1),' cues=',number #CUES return.
  end.
  if. command text_equal 'DELETE' do.
    p =. (0{values)-1
    q =. p+1
    if. 2=#values do. q =. 1{values end.
    CUES =: (p{.CUES),q}.CUES
    <'DELETE removed=',(number q-p),' cues=',number #CUES return.
  end.
  if. command text_equal 'MERGE' do.
    merged =. 0$<i.0
    joins =. 0
    for_cue. CUES do.
      cue =. >cue
      joined =. 0
      if. #merged do.
        previous =. _1{::merged
        if. ((1{::cue)-2{::previous)<0{values do.
          if. (-.dialogue previous)*.-.dialogue cue do.
            lines =. 42 wrap (3{::previous),3{::cue
            if. (#lines)<:2 do.
              previous =. (<(2{::previous)>.2{::cue) 2}previous
              previous =. (<lines) 3}previous
              merged =. (<previous) _1}merged
              joined =. 1
              joins =. joins+1
            end.
          end.
        end.
      end.
      if. -.joined do. merged =. merged,<cue end.
    end.
    CUES =: merged
    <'MERGE merged=',(number joins),' cues=',number #CUES return.
  end.
  if. command text_equal 'SPLIT' do.
    result =. 0$<i.0
    split_count =. 0
    for_cue. CUES do.
      cue =. >cue
      duration =. (2{::cue)-1{::cue
      if. (duration<:0)+.dialogue cue do. result =. result,<cue continue. end.
      lines =. (0{values) wrap 3{::cue
      if. (#lines)<:2 do.
        cue =. (<lines) 3}cue
        result =. result,<cue
        continue.
      end.
      split_count =. split_count+1
      parts =. 0$<i.0
      counts =. i.0
      for_k. 2*i.(1+#lines) floor_ratio 2 do.
        part =. (2<.(#lines)-k){.k}.lines
        parts =. parts,<part
        counts =. counts,+/#&>part
      end.
      total =. +/counts
      durations =. (duration*counts) floor_ratio total
      remainders =. total|duration*counts
      order =. \:remainders
      rest =. duration-+/durations
      for_k. rest{.order do. durations =. (1+k{durations) k}durations end.
      cursor =. 1{::cue
      for_k. i.#parts do.
        part_cue =. (0{cue),(<cursor),(<cursor+k{durations),k{parts
        result =. result,<part_cue
        cursor =. cursor+k{durations
      end.
    end.
    CUES =: result
    <'SPLIT split=',(number split_count),' cues=',number #CUES return.
  end.
  if. command text_equal 'BALANCE' do.
    changed =. 0
    skipped =. 0
    dialogues =. 0
    for_k. i.n do.
      cue =. k{::CUES
      if. dialogue cue do. dialogues =. dialogues+1 continue. end.
      words =. words_of 3{::cue
      joined =. ' ' join words
      best =. 0$<''
      best_difference =. 0
      if. (#joined)<:42 do. best =. ,<joined
      else.
        for_j. 1+i.0>.(#words)-1 do.
          left =. ' ' join j{.words
          right =. ' ' join j}.words
          difference =. |(#left)-#right
          if. ((#left)<:42)*.(#right)<:42 do.
            use =. 0=#best
            if. #best do. use =. (difference<best_difference)+.((difference=best_difference)*.(#left)<#0{::best) end.
            if. use do.
              best =. (<left),<right
              best_difference =. difference
            end.
          end.
        end.
      end.
      if. 0=#best do. skipped =. skipped+1
      elseif. -.best text_equal 3{::cue do.
        cue =. (<best) 3}cue
        CUES =: (<cue) k}CUES
        changed =. changed+1
      end.
    end.
    <'BALANCE changed=',(number changed),' skipped=',(number skipped),' dialogue=',number dialogues return.
  end.
  if. command text_equal 'REPLACE' do.
    'old new' =. '|' split 0{::args
    replacements =. 0
    changed_cues =. 0
    for_k. i.n do.
      cue =. k{::CUES
      lines =. 3{::cue
      changed =. 0
      for_j. i.#lines do.
        line =. j{::lines
        result =. ''
        p =. 0
        while. p<#line do.
          if. old text_equal (#old){.p}.line do.
            result =. result,new
            p =. p+#old
            replacements =. replacements+1
            changed =. 1
          else.
            result =. result,p{line
            p =. p+1
          end.
        end.
        lines =. (<result) j}lines
      end.
      cue =. (<lines) 3}cue
      CUES =: (<cue) k}CUES
      changed_cues =. changed_cues+changed
    end.
    <'REPLACE count=',(number replacements),' cues=',number changed_cues return.
  end.
  remaining =. 0$<i.0
  tags =. 0
  segments =. 0
  labels =. 0
  removed_lines =. 0
  for_cue. CUES do.
    cue =. >cue
    lines =. 0$<''
    for_line. 3{::cue do.
      if. command text_equal 'STRIP' do.
        converted =. 'STRIP' convert_markup >line
        text =. 0{::converted
        tags =. tags+1{::converted
      else.
        cleaned =. clean_hi >line
        text =. 0{::cleaned
        segments =. segments+1{::cleaned
        labels =. labels+2{::cleaned
        if. text text_equal '-' do. text =. '' end.
      end.
      if. 0=#text do. removed_lines =. removed_lines+1
      else. lines =. lines,<text
      end.
    end.
    if. #lines do.
      cue =. (<lines) 3}cue
      remaining =. remaining,<cue
    end.
  end.
  removed_cues =. n-#remaining
  CUES =: remaining
  if. command text_equal 'STRIP' do. prefix =. 'STRIP tags=',number tags
  else. prefix =. 'CLEANHI segments=',(number segments),' labels=',number labels
  end.
  <prefix,' removed_lines=',(number removed_lines),' removed_cues=',number removed_cues
)
load_block =: 4 : 0
  problem =. ''
  if. -.6 digits 0{::y do. problem =. 'index'
  elseif. (#y)<2 do. problem =. 'time'
  else.
    value =. 1{::y
    if. (#value)~:29 do. problem =. 'time'
    elseif. -. ' --> ' text_equal 5{.12}.value do. problem =. 'time'
    elseif. ((time_value 12{.value)<0)+.(time_value 17}.value)<0 do. problem =. 'time'
    elseif. (#y)<3 do. problem =. 'no text'
    end.
  end.
  if. #problem do.
    ('BAD CUE ',(number x),': ',problem,LF) 1!:2 (4)
    1
  else.
    cue =. (<0".0{::y),(<time_value 12{.1{::y),(<time_value 17}.1{::y),<2}.y
    CUES =: CUES,<cue
    0
  end.
)
main =: 3 : 0
  input =. 1!:1 (3)
  lines =. <;._2 input
  pending =. 0$<''
  block_number =. 0
  bad =. 0
  p =. 0
  while. 1 do.
    line =. p{::lines
    p =. p+1
    if. (0=#line)+.line text_equal '###' do.
      if. #pending do.
        block_number =. block_number+1
        bad =. bad+block_number load_block pending
        pending =. 0$<''
      end.
      if. line text_equal '###' do. break. end.
    else. pending =. pending,<line
    end.
  end.
  ('LOAD cues=',(number #CUES),' bad=',(number bad),LF) 1!:2 (4)
  count =. 0".p{::lines
  p =. p+1
  for_k. i.count do.
    output =. execute (p+k){::lines
    for_line. output do. ((>line),LF) 1!:2 (4) end.
  end.
  i.0 0
)
main''
