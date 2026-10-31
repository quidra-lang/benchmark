split =: 4 : 0
  <;._1 x,y
)
join =: 4 : 0
  if. 0=#y do. '' return. end.
  (#x)}.;(<x),&.>y
)
text_equal =: 4 : 0
  (,x)-:,y
)
number =: 3 : 0
  ,'0' 8!:2 y
)
floor_ratio =: 4 : 0
  <.(x:x)%x:y
)
power =: 4 : 0
  (x:x)^y
)
char_value =: 4 : 0
  if. 1~:#y do. _1 return. end.
  k =. x i.{.,y
  if. k=#x do. _1 else. k end.
)
digits =: 4 : 0
  (0<#y)*.((#y)<:x)*.*./y e.'0123456789'
)
BAD =: _1000000000000x
integer =: 3 : 0
  negative =. '-'={.y
  magnitude =. y
  if. negative do. magnitude =. }.y end.
  if. -.9 digits magnitude do. BAD return. end.
  result =. 0".magnitude
  if. negative do. -result else. result end.
)
ranged =: 4 : 0
  result =. integer y
  if. ((0{x)<:result)*.result<:1{x do. result else. BAD end.
)
coordinate =: 4 : 0
  negative =. '-'={.y
  magnitude =. y
  if. negative do. magnitude =. }.y end.
  parts =. '.' split magnitude
  if. (#parts)>2 do. BAD return. end.
  if. -.3 digits 0{::parts do. BAD return. end.
  fraction =. 0
  if. 2=#parts do.
    part =. 1{::parts
    if. -.6 digits part do. BAD return. end.
    fraction =. (0".part)*10 power 6-#part
  end.
  result =. (1000000*0".0{::parts)+fraction
  if. negative do. result =. -result end.
  if. x do.
    if. (result< _90000000)+.result>90000000 do. BAD else. result end.
  else.
    if. (result< _180000000)+.result>:180000000 do. BAD else. result end.
  end.
)
padded =: 4 : 0
  result =. number y
  ((0>.x-#result)#'0'),result
)
coordinate_text =: 3 : 0
  magnitude =. |y
  prefix =. ''
  if. y<0 do. prefix =. '-' end.
  prefix,(number magnitude floor_ratio 1000000),'.',6 padded 1000000|magnitude
)
SYSTEMS =: ;:'GEOHASH MAIDENHEAD PLUSCODE GARS GEOREF MESH'
PSEQ =: (<1 2 3 4 5 6 7 8 9),(<2 4 6 8),(<2 4 6 8 10 11),(<5 6 7),(<2 4 8 10 12),<4 6 8 9 10 11
GH =: '0123456789bcdefghjkmnpqrstuvwxyz'
L24 =: 'ABCDEFGHJKLMNPQRSTUVWXYZ'
P20 =: '23456789CFGHJMPQRVWX'
G25 =: 'ABCDEFGHJKLMNOPQRSTUVWXYZ'
BANDS =: 'CDEFGHJKLMNPQRSTUVWX'
MROWS =: 'ABCDEFGHJKLMNPQRSTUV'
MCOLS =: 'STUVWXYZ';'ABCDEFGH';'JKLMNPQR'
SCALES =: 1 8 80 160 320 640
system_id =: 3 : 0
  k =. SYSTEMS i.<,y
  if. k=6 do. _1 else. k end.
)
precision_index =: 4 : 0
  if. (x<0)+.x>:6 do. _1 return. end.
  sequence =. x{::PSEQ
  k =. sequence i.y
  if. k=#sequence do. _1 else. k end.
)
dimensions =: 4 : 0
  k =. x precision_index y
  select. x
  case. 0 do. (2 power (1+5*y) floor_ratio 2),2 power (5*y) floor_ratio 2
  case. 1 do. 2#k{18 180 4320 43200
  case. 2 do. k{6 2$18 9 360 180 7200 3600 144000 72000 2880000 1440000 11520000 7200000
  case. 3 do. k{3 2$720 360 1440 720 4320 2160
  case. 4 do. k{5 2$24 12 360 180 21600 10800 216000 108000 2160000 1080000
  case. 5 do. (k{SCALES)*360 270
  end.
)
point_cell =: 3 : 0
  'sys p lat lon' =. y
  'w h' =. sys dimensions p
  cx =. ((lon+180000000)*w) floor_ratio 360000000
  cy =. (h-1)<.((lat+90000000)*h) floor_ratio 180000000
  sys,p,cx,cy
)
encode =: 3 : 0
  'sys p cx cy' =. y
  if. sys=0 do.
    xb =. ((1+5*p) floor_ratio 2)-1
    yb =. ((5*p) floor_ratio 2)-1
    result =. ''
    group =. 0
    for_k. i.5*p do.
      if. 0=2|k do.
        bit =. 2|cx floor_ratio 2 power xb
        xb =. xb-1
      else.
        bit =. 2|cy floor_ratio 2 power yb
        yb =. yb-1
      end.
      group =. (2*group)+bit
      if. 4=5|k do.
        result =. result,group{GH
        group =. 0
      end.
    end.
    result return.
  end.
  if. sys e.1 2 do.
    plus =. sys=2
    count =. p floor_ratio 2
    if. p=11 do. count =. 5 end.
    if. plus do.
      rx =. 18 20 20 20 20
      ry =. 9 20 20 20 20
      alphabets =. 5$<P20
    else.
      rx =. 18 10 24 10
      ry =. rx
      alphabets =. 'ABCDEFGHIJKLMNOPQR';'0123456789';'abcdefghijklmnopqrstuvwx';'0123456789'
    end.
    dx =. cx
    dy =. cy
    if. p=11 do.
      dx =. cx floor_ratio 4
      dy =. cy floor_ratio 5
    end.
    xd =. (count{.rx) #: dx
    yd =. (count{.ry) #: dy
    result =. ''
    for_k. i.count do.
      alphabet =. k{::alphabets
      if. plus do. result =. result,((k{yd){P20),(k{xd){P20
      else. result =. result,((k{xd){alphabet),(k{yd){alphabet
      end.
    end.
    if. p=11 do. result =. result,((4*5|cy)+4|cx){P20 end.
    if. plus do.
      if. p<8 do. result,((8-p)#'0'),'+' return. end.
      (8{.result),'+',8}.result return.
    end.
    result return.
  end.
  if. sys=3 do.
    area =. _1
    quadrant =. _1
    if. p=7 do.
      area =. 1+(3|cx)+3*2-3|cy
      cx =. cx floor_ratio 3
      cy =. cy floor_ratio 3
    end.
    if. p>:6 do.
      quadrant =. 1+(2|cx)+2*1-2|cy
      cx =. cx floor_ratio 2
      cy =. cy floor_ratio 2
    end.
    result =. (3 padded cx+1),((cy floor_ratio 24){L24),(24|cy){L24
    if. p>:6 do. result =. result,number quadrant end.
    if. p=7 do. result =. result,number area end.
    result return.
  end.
  if. sys=4 do.
    m =. 0
    if. p>:8 do. m =. (p-4) floor_ratio 2 end.
    scale =. 1
    if. m>0 do. scale =. 6*10 power m-1 end.
    e =. scale|cx
    n =. scale|cy
    cx =. cx floor_ratio scale
    cy =. cy floor_ratio scale
    if. p=2 do. (cx{L24),cy{L24 return. end.
    result =. ((cx floor_ratio 15){L24),((cy floor_ratio 15){L24),((15|cx){L24),(15|cy){L24
    if. m>0 do. result =. result,(m padded e),m padded n end.
    result return.
  end.
  k =. sys precision_index p
  scale =. k{SCALES
  u =. cx-280*scale
  v =. cy-135*scale
  if. (u<0)+.(u>:80*scale)+.(v<0)+.v>:100*scale do. '-' return. end.
  xd =. ((k+1){.80 8 10 2 2 2) #: u
  yd =. ((k+1){.100 8 10 2 2 2) #: v
  result =. (2 padded 0{yd),2 padded 0{xd
  for_j. 1+i.k do.
    if. j<3 do. result =. result,(number j{yd),number j{xd
    else. result =. result,number 1+(j{xd)+2*j{yd
    end.
  end.
  result
)
decode =: 4 : 0
  sys =. x
  invalid =. sys,0 0 0
  if. (sys<0)+.sys>:6 do. invalid return. end.
  code =. y
  p =. #code
  cx =. 0
  cy =. 0
  if. sys=2 do.
    if. -.p e.9 11 12 do. invalid return. end.
    if. '+'~:8{code do. invalid return. end.
    raw =. (8{.code),9}.code
    prefix =. (8{.code) i.'0'
    if. prefix<8 do.
      if. (-.prefix e.2 4 6)+.9~:#code do. invalid return. end.
      if. -. *./'0'=prefix}.8{.code do. invalid return. end.
      raw =. prefix{.code
    end.
    p =. #raw
    if. 0>sys precision_index p do. invalid return. end.
    count =. (p<.10) floor_ratio 2
    for_k. i.count do.
      yd =. P20 char_value (2*k){raw
      xd =. P20 char_value (1+2*k){raw
      if. (yd<0)+.xd<0 do. invalid return. end.
      if. k=0 do.
        cy =. (cy*9)+yd
        cx =. (cx*18)+xd
      else.
        cy =. (cy*20)+yd
        cx =. (cx*20)+xd
      end.
    end.
    if. p=11 do.
      digit =. P20 char_value 10{raw
      if. digit<0 do. invalid return. end.
      cx =. (4*cx)+4|digit
      cy =. (5*cy)+digit floor_ratio 4
    end.
  else.
    if. 0>sys precision_index p do. invalid return. end.
    if. sys=0 do.
      bit_count =. 0
      for_k. i.p do.
        digit =. GH char_value k{code
        if. digit<0 do. invalid return. end.
        for_shift. |.i.5 do.
          bit =. 2|digit floor_ratio 2 power shift
          if. 0=2|bit_count do. cx =. (2*cx)+bit
          else. cy =. (2*cy)+bit
          end.
          bit_count =. bit_count+1
        end.
      end.
    elseif. sys=1 do.
      alphabets =. 'ABCDEFGHIJKLMNOPQR';'0123456789';'abcdefghijklmnopqrstuvwx';'0123456789'
      radices =. 18 10 24 10
      for_k. i.p floor_ratio 2 do.
        xd =. (k{::alphabets) char_value (2*k){code
        yd =. (k{::alphabets) char_value (1+2*k){code
        if. (xd<0)+.yd<0 do. invalid return. end.
        cx =. (cx*k{radices)+xd
        cy =. (cy*k{radices)+yd
      end.
    elseif. sys=3 do.
      if. -.3 digits 3{.code do. invalid return. end.
      cx =. (0".3{.code)-1
      a =. (15{.L24) char_value 3{code
      b =. L24 char_value 4{code
      if. (cx<0)+.(cx>:720)+.(a<0)+.b<0 do. invalid return. end.
      cy =. (24*a)+b
      if. p>:6 do.
        q =. '1234' char_value 5{code
        if. q<0 do. invalid return. end.
        cx =. (2*cx)+2|q
        cy =. (2*cy)+1-q floor_ratio 2
      end.
      if. p=7 do.
        q =. '123456789' char_value 6{code
        if. q<0 do. invalid return. end.
        cx =. (3*cx)+3|q
        cy =. (3*cy)+2-q floor_ratio 3
      end.
    elseif. sys=4 do.
      cx =. L24 char_value 0{code
      cy =. (12{.L24) char_value 1{code
      if. (cx<0)+.cy<0 do. invalid return. end.
      if. p>:4 do.
        a =. (15{.L24) char_value 2{code
        b =. (15{.L24) char_value 3{code
        if. (a<0)+.b<0 do. invalid return. end.
        cx =. (15*cx)+a
        cy =. (15*cy)+b
      end.
      if. p>:8 do.
        m =. (p-4) floor_ratio 2
        east =. m{.4}.code
        north =. (m+4)}.code
        if. (-.m digits east)+.-.m digits north do. invalid return. end.
        e =. 0".east
        n =. 0".north
        scale =. 6*10 power m-1
        if. (e>:scale)+.n>:scale do. invalid return. end.
        cx =. (scale*cx)+e
        cy =. (scale*cy)+n
      end.
    else.
      if. -.11 digits code do. invalid return. end.
      u =. 0".2{.2}.code
      v =. 0".2{.code
      if. u>:80 do. invalid return. end.
      k =. sys precision_index p
      for_j. 1+i.k do.
        if. j<3 do.
          yd =. 0".(2+j*2){code
          xd =. 0".(3+j*2){code
          radix =. 10
          if. j=1 do. radix =. 8 end.
          if. (xd>:radix)+.yd>:radix do. invalid return. end.
          u =. (radix*u)+xd
          v =. (radix*v)+yd
        else.
          q =. '1234' char_value (j+5){code
          if. q<0 do. invalid return. end.
          u =. (2*u)+2|q
          v =. (2*v)+q floor_ratio 2
        end.
      end.
      scale =. k{SCALES
      cx =. (280*scale)+u
      cy =. (135*scale)+v
    end.
  end.
  'w h' =. sys dimensions p
  result =. sys,p,cx,cy
  if. (cx<0)+.(cx>:w)+.(cy<0)+.cy>:h do. invalid return. end.
  if. -.code text_equal encode result do. invalid return. end.
  result
)
ancestor =: 4 : 0
  'sys p cx cy' =. x
  old =. sys dimensions p
  next =. sys dimensions y
  xy =. ((cx,cy)*next) floor_ratio old
  sys,y,xy
)
same_cell =: 4 : 0
  (1 2 3{x)-:1 2 3{y
)
encoded_result =: 3 : 0
  result =. encode y
  if. result text_equal '-' do. 'OUT OF AREA' else. result end.
)
relate =: 4 : 0
  ad =. (0{x) dimensions 1{x
  bd =. (0{y) dimensions 1{y
  aa =. ((2{x)*0{bd),((1+2{x)*0{bd),((3{x)*1{bd),(1+3{x)*1{bd
  bb =. ((2{y)*0{ad),((1+2{y)*0{ad),((3{y)*1{ad),(1+3{y)*1{ad
  if. aa-:bb do. 'EQUAL' return. end.
  if. ((0{aa)>:0{bb)*.((1{aa)<:1{bb)*.((2{aa)>:2{bb)*.(3{aa)<:3{bb do. 'INSIDE' return. end.
  if. ((0{bb)>:0{aa)*.((1{bb)<:1{aa)*.((2{bb)>:2{aa)*.(3{bb)<:3{aa do. 'CONTAINS' return. end.
  latitude =. ((2{aa)>.2{bb)<:((3{aa)<.3{bb)
  if. (((0{aa)>.0{bb)<((1{aa)<.1{bb))*.((2{aa)>.2{bb)<((3{aa)<.3{bb) do. 'OVERLAP' return. end.
  seam =. (((1+2{x)=0{ad)*.0=2{y)+.(((1+2{y)=0{bd)*.0=2{x)
  if. latitude*.((((0{aa)>.0{bb)<:((1{aa)<.1{bb))+.seam) do. 'TOUCH' return. end.
  'DISJOINT'
)
compact =: 3 : 0
  current =. 0$<i.0
  for_cell. y do.
    cell =. >cell
    covered =. 0
    for_other. y do.
      other =. >other
      if. (1{other)<1{cell do.
        if. (cell ancestor 1{other) same_cell other do. covered =. 1 end.
      end.
    end.
    for_other. current do. if. cell same_cell >other do. covered =. 1 end. end.
    if. -.covered do. current =. current,<cell end.
  end.
  changed =. 1
  while. changed do.
    changed =. 0
    for_cell. current do.
      cell =. >cell
      sys =. 0{cell
      p =. 1{cell
      index =. sys precision_index p
      if. index=0 do. continue. end.
      parent =. cell ancestor (index-1){sys{::PSEQ
      child_dim =. sys dimensions p
      parent_dim =. sys dimensions 1{parent
      required =. */child_dim floor_ratio parent_dim
      remove =. (#current)$0
      for_k. i.#current do.
        other =. k{::current
        if. p=1{other do.
          if. (other ancestor 1{parent) same_cell parent do. remove =. (1) k}remove end.
        end.
      end.
      if. required=+/remove do.
        current =. ((-.remove)#current),<parent
        changed =. 1
        break.
      end.
    end.
  end.
  coordinates =. >current
  keys =. (1{"1 coordinates),.(-3{"1 coordinates),.2{"1 coordinates
  current =. (/:keys){current
  ' ' join encode&.>current
)
other_system =: 3 : 0
  fields =. y
  command =. 0{::fields
  count =. #fields
  if. command text_equal 'UTMZONE' do.
    if. count~:3 do. 'INVALID' return. end.
    lat =. 1 coordinate 1{::fields
    lon =. 0 coordinate 2{::fields
    if. BAD e.lat,lon do. 'INVALID' return. end.
    if. (lat< _80000000)+.lat>:84000000 do. 'NONE' return. end.
    band =. (19<.(lat+80000000) floor_ratio 8000000){BANDS
    zone =. 1+(lon+180000000) floor_ratio 6000000
    if. (band='V')*.(lon>:3000000)*.lon<12000000 do. zone =. 32
    elseif. (band='X')*.(lon>:0)*.lon<42000000 do.
      if. lon<9000000 do. zone =. 31
      elseif. lon<21000000 do. zone =. 33
      elseif. lon<33000000 do. zone =. 35
      else. zone =. 37
      end.
    end.
    (number zone),band return.
  end.
  if. command text_equal 'QUADKEY' do.
    if. count~:4 do. 'INVALID' return. end.
    z =. 1 23 ranged 3{::fields
    if. z=BAD do. 'INVALID' return. end.
    high =. (2 power z)-1
    cx =. (0,high) ranged 1{::fields
    cy =. (0,high) ranged 2{::fields
    if. BAD e.cx,cy do. 'INVALID' return. end.
    result =. ''
    for_k. |.i.z do.
      bx =. 2|cx floor_ratio 2 power k
      by =. 2|cy floor_ratio 2 power k
      result =. result,number bx+2*by
    end.
    result return.
  end.
  if. command text_equal 'UNQUADKEY' do.
    if. count~:2 do. 'INVALID' return. end.
    key =. 1{::fields
    if. (0=#key)+.(#key)>23 do. 'INVALID' return. end.
    cx =. 0
    cy =. 0
    for_c. key do.
      digit =. '0123' char_value c
      if. digit<0 do. 'INVALID' return. end.
      cx =. (2*cx)+2|digit
      cy =. (2*cy)+digit floor_ratio 2
    end.
    'x=',(number cx),' y=',(number cy),' z=',number #key return.
  end.
  if. (<command)e.'OSGB';'MGRS' do.
    mgrs =. command text_equal 'MGRS'
    expected =. 4
    if. mgrs do. expected =. 6 end.
    if. count~:expected do. 'INVALID' return. end.
    zone =. 0
    band =. ''
    offset =. 1
    low =. 0
    ehigh =. 699999
    nhigh =. 1299999
    if. mgrs do.
      zone =. 1 60 ranged 1{::fields
      band =. 2{::fields
      if. (zone=BAD)+.0>BANDS char_value band do. 'INVALID' return. end.
      offset =. 3
      low =. 100000
      ehigh =. 899999
      nhigh =. 9999999
    end.
    e =. (low,ehigh) ranged offset{::fields
    n =. (0,nhigh) ranged (offset+1){::fields
    d =. 0 5 ranged (offset+2){::fields
    if. BAD e.e,n,d do. 'INVALID' return. end.
    if. mgrs do.
      column =. ((e floor_ratio 100000)-1){(3|zone){::MCOLS
      shift =. 5*0=2|zone
      row =. (20|shift+n floor_ratio 100000){MROWS
      result =. (number zone),band,' ',column,row
    else.
      a =. (5*3-n floor_ratio 500000)+2+e floor_ratio 500000
      b =. (5*4-5|n floor_ratio 100000)+5|e floor_ratio 100000
      result =. (a{G25),b{G25
    end.
    if. d>0 do. result =. result,' ',(d{.5 padded 100000|e),' ',d{.5 padded 100000|n end.
    result return.
  end.
  if. (<command)e.'UNOSGB';'UNMGRS' do.
    mgrs =. command text_equal 'UNMGRS'
    offset =. 1+mgrs
    if. -.count e.(offset+1),offset+3 do. 'INVALID' return. end.
    e =. 0
    n =. 0
    prefix =. ''
    if. mgrs do.
      gzd =. 1{::fields
      if. -. (#gzd)e.2 3 do. 'INVALID' return. end.
      zone_text =. }:gzd
      band =. {:gzd
      if. (-.2 digits zone_text)+.('0'={.zone_text)+.0>BANDS char_value band do. 'INVALID' return. end.
      zone =. 1 60 ranged zone_text
      square =. 2{::fields
      if. (zone=BAD)+.2~:#square do. 'INVALID' return. end.
      c =. ((3|zone){::MCOLS) char_value 0{square
      r =. MROWS char_value 1{square
      if. (c<0)+.r<0 do. 'INVALID' return. end.
      e =. 100000*c+1
      n =. 100000*20|r-5*0=2|zone
      prefix =. gzd,' '
    else.
      letters =. 1{::fields
      if. 2~:#letters do. 'INVALID' return. end.
      a =. G25 char_value 0{letters
      b =. G25 char_value 1{letters
      if. (a<0)+.b<0 do. 'INVALID' return. end.
      e =. (500000*((5|a)-2))+100000*5|b
      n =. (500000*3-a floor_ratio 5)+100000*4-b floor_ratio 5
      if. (e<0)+.(e>:700000)+.(n<0)+.n>:1300000 do. 'INVALID' return. end.
    end.
    size =. 100000
    if. count=offset+3 do.
      east =. (offset+1){::fields
      north =. (offset+2){::fields
      if. (-.5 digits east)+.(-.5 digits north)+.(#east)~:#north do. 'INVALID' return. end.
      size =. 10 power 5-#east
      e =. e+size*0".east
      n =. n+size*0".north
    end.
    prefix,'sw=',(number e),',',(number n),' size=',number size return.
  end.
  'INVALID'
)
execute =: 3 : 0
  fields =. ' ' split y
  command =. 0{::fields
  count =. #fields
  if. (<command)e.'SHORTEN';'RECOVER' do.
    if. count~:4 do. 'INVALID' return. end.
    lat =. 1 coordinate 2{::fields
    lon =. 0 coordinate 3{::fields
    if. BAD e.lat,lon do. 'INVALID' return. end.
    cell =. 2 decode 1{::fields
    if. command text_equal 'SHORTEN' do.
      if. (1{cell)<8 do. 'INVALID' return. end.
      'w h' =. 2 dimensions 1{cell
      dx =. |(360000000*1+2*2{cell)-((lon+180000000)*2*w)
      dy =. |(180000000*1+2*3{cell)-((lat+90000000)*2*h)
      remove =. 0
      if. (dx<15000*2*w)*.dy<15000*2*h do. remove =. 6
      elseif. (dx<300000*2*w)*.dy<300000*2*h do. remove =. 4
      end.
      remove}.1{::fields return.
    end.
    parts =. '+' split 1{::fields
    if. 2~:#parts do. 'INVALID' return. end.
    if. (-.(#0{::parts)e.2 4)+.-.(#1{::parts)e.0 2 3 do. 'INVALID' return. end.
    raw =. ;parts
    if. -. *./raw e.P20 do. 'INVALID' return. end.
    removed =. 8-#0{::parts
    reference =. encode point_cell 2 10,lat,lon
    cell =. 2 decode (removed{.reference),1{::fields
    if. 0=1{cell do. 'INVALID' return. end.
    'w h' =. 2 dimensions 1{cell
    distance =. 50000
    if. removed=4 do. distance =. 1000000 end.
    cy =. 180000000*1+2*3{cell
    cx =. 360000000*1+2*2{cell
    ry =. (lat+90000000)*2*h
    rx =. (lon+180000000)*2*w
    my =. (distance*h) floor_ratio 180000000
    mx =. (distance*w) floor_ratio 360000000
    py =. 3{cell
    px =. 2{cell
    if. ((ry+distance*h)<cy)*.(cy-distance*2*h)>:0 do. py =. py-my
    elseif. ((ry-distance*h)>cy)*.(cy+distance*2*h)<:180000000*2*h do. py =. py+my
    end.
    if. (rx+distance*w)<cx do. px =. w|px-mx
    elseif. (rx-distance*w)>cx do. px =. w|px+mx
    end.
    encode 2,(1{cell),px,py return.
  end.
  if. command text_equal 'RELATE' do.
    if. count~:5 do. 'INVALID' return. end.
    a =. (system_id 1{::fields) decode 2{::fields
    b =. (system_id 3{::fields) decode 4{::fields
    if. (0=1{a)+.0=1{b do. 'INVALID' return. end.
    a relate b return.
  end.
  known =. ;:'ENCODE DECODE NEIGHBORS PARENT CHILDREN COMMON COMPACT CONTAINS COVER CONVERT STEPS PATH SIZE'
  if. -. (<command)e.known do. other_system fields return. end.
  if. count<3 do. 'INVALID' return. end.
  sys =. system_id 1{::fields
  if. sys<0 do. 'INVALID' return. end.
  if. (<command)e.'ENCODE';'COVER';'SIZE' do.
    expected =. 3
    if. command text_equal 'ENCODE' do. expected =. 5
    elseif. command text_equal 'COVER' do. expected =. 7
    end.
    if. count~:expected do. 'INVALID' return. end.
    slot =. 2
    if. command text_equal 'ENCODE' do. slot =. 4 end.
    p =. integer slot{::fields
    if. 0>sys precision_index p do. 'INVALID' return. end.
    'w h' =. sys dimensions p
    if. command text_equal 'SIZE' do.
      total =. w*h
      if. sys=5 do.
        scale =. (sys precision_index p){SCALES
        total =. 8000*scale*scale
      end.
      'w=',(coordinate_text 360000000 floor_ratio w),' h=',(coordinate_text 180000000 floor_ratio h),' cells=',number total return.
    end.
    offset =. 3
    if. command text_equal 'ENCODE' do. offset =. 2 end.
    lat =. 1 coordinate offset{::fields
    lon =. 0 coordinate (offset+1){::fields
    if. BAD e.lat,lon do. 'INVALID' return. end.
    first =. point_cell sys,p,lat,lon
    if. command text_equal 'ENCODE' do. encoded_result first return. end.
    north =. 1 coordinate 5{::fields
    east =. 0 coordinate 6{::fields
    if. (BAD e.north,east)+.lat>north do. 'INVALID' return. end.
    last =. point_cell sys,p,north,east
    columns =. 1+(2{last)-2{first
    if. lon>east do. columns =. w<.columns+w end.
    if. (columns*(1+(3{last)-3{first))>100 do. 'TOO MANY' return. end.
    result =. 0$<''
    for_row. (3{last)-i.1+(3{last)-3{first do.
      for_k. i.columns do. result =. result,<encode sys,p,(w|k+2{first),row end.
    end.
    ' ' join result return.
  end.
  if. command text_equal 'COMPACT' do.
    if. (count<3)+.count>102 do. 'INVALID' return. end.
    cells =. 0$<i.0
    for_k. 2+i.count-2 do.
      cell =. sys decode k{::fields
      if. 0=1{cell do. 'INVALID' return. end.
      cells =. cells,<cell
    end.
    compact cells return.
  end.
  expected =. 3
  if. (<command)e.'COMMON';'STEPS';'PATH' do. expected =. 4
  elseif. command text_equal 'CONTAINS' do. expected =. 5
  elseif. command text_equal 'CONVERT' do. expected =. 6
  end.
  if. count~:expected do. 'INVALID' return. end.
  cell =. sys decode 2{::fields
  if. 0=1{cell do. 'INVALID' return. end.
  'ignore p cx cy' =. cell
  'w h' =. sys dimensions p
  if. command text_equal 'DECODE' do.
    south =. _90000000+(180000000*cy) floor_ratio h
    west =. _180000000+(360000000*cx) floor_ratio w
    north =. _90000000+(180000000*cy+1) floor_ratio h
    east =. _180000000+(360000000*cx+1) floor_ratio w
    center_y =. _90000000+(180000000*1+2*cy) floor_ratio 2*h
    center_x =. _180000000+(360000000*1+2*cx) floor_ratio 2*w
    'sw=',(coordinate_text south),',',(coordinate_text west),' ne=',(coordinate_text north),',',(coordinate_text east),' c=',(coordinate_text center_y),',',coordinate_text center_x return.
  end.
  if. command text_equal 'CONTAINS' do.
    lat =. 1 coordinate 3{::fields
    lon =. 0 coordinate 4{::fields
    if. BAD e.lat,lon do. 'INVALID' return. end.
    if. cell same_cell point_cell sys,p,lat,lon do. 'YES' else. 'NO' end. return.
  end.
  if. command text_equal 'CONVERT' do.
    target =. system_id 4{::fields
    q =. integer 5{::fields
    if. (-.'TO' text_equal 3{::fields)+.0>target precision_index q do. 'INVALID' return. end.
    'nw nh' =. target dimensions q
    nx =. ((1+2*cx)*nw) floor_ratio 2*w
    ny =. ((1+2*cy)*nh) floor_ratio 2*h
    encoded_result target,q,nx,ny return.
  end.
  if. command text_equal 'NEIGHBORS' do.
    offsets =. 8 2$0 1 1 1 1 0 1 _1 0 _1 _1 _1 _1 0 _1 1
    result =. 0$<''
    for_offset. offsets do.
      row =. cy+1{offset
      if. (row<0)+.row>:h do. result =. result,<'-'
      else. result =. result,<encode sys,p,(w|cx+0{offset),row
      end.
    end.
    ' ' join result return.
  end.
  if. (<command)e.'PARENT';'CHILDREN' do.
    index =. sys precision_index p
    sequence =. sys{::PSEQ
    if. command text_equal 'PARENT' do.
      if. index=0 do. 'NONE' else. encode cell ancestor (index-1){sequence end. return.
    end.
    if. (index+1)=#sequence do. 'NONE' return. end.
    q =. (index+1){sequence
    ratios =. (sys dimensions q) floor_ratio w,h
    'rx ry' =. ratios
    if. 100<rx*ry do. 'TOO MANY' return. end.
    result =. 0$<''
    for_row. |.i.ry do.
      for_col. i.rx do. result =. result,<encode sys,q,((rx*cx)+col),((ry*cy)+row) end.
    end.
    ' ' join result return.
  end.
  other =. sys decode 3{::fields
  if. 0=1{other do. 'INVALID' return. end.
  if. command text_equal 'COMMON' do.
    index =. (sys precision_index p)<.sys precision_index 1{other
    sequence =. sys{::PSEQ
    for_k. |.i.index+1 do.
      a =. cell ancestor k{sequence
      if. a same_cell other ancestor k{sequence do. encode a return. end.
    end.
    'NONE' return.
  end.
  if. p~:1{other do. 'MISMATCH' return. end.
  dx =. w|(2{other)-cx
  if. (2*dx)>w do. dx =. dx-w end.
  dy =. (3{other)-cy
  if. command text_equal 'STEPS' do. 'dx=',(number dx),' dy=',number dy return. end.
  steps =. (|dx)>.|dy
  if. steps>:100 do. 'TOO MANY' return. end.
  if. steps=0 do. encode cell return. end.
  result =. 0$<''
  for_k. i.steps+1 do.
    px =. w|cx+((2*k*dx)+steps) floor_ratio 2*steps
    py =. cy+((2*k*dy)+steps) floor_ratio 2*steps
    result =. result,<encode sys,p,px,py
  end.
  ' ' join result
)
main =: 3 : 0
  input =. 1!:1 (3)
  lines =. <;._2 input
  count =. 0".0{::lines
  for_k. 1+i.count do.
    result =. execute k{::lines
    (result,LF) 1!:2 (4)
  end.
  i.0 0
)
main''
