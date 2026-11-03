floor_ratio =: 4 : 0
  <. (x: x) % x: y
)
rounded =: 4 : 0
  ((2*x)+y) floor_ratio 2*y
)
away =: 4 : 0
  (*x) * (|x) rounded y
)
clamp =: 3 : 0
  255 <. 0 >. y
)
root_ratio =: 4 : 0
  low =. 0
  high =. 1
  while. ((high*high)*y)<:x do. high =. 2*high end.
  while. (low+1)<high do.
    middle =. (low+high) floor_ratio 2
    if. ((middle*middle)*y)<:x do. low =. middle
    else. high =. middle
    end.
  end.
  low
)
split =: 4 : 0
  <;._1 x,y
)
join =: 4 : 0
  if. 0=#y do. '' return. end.
  (#x) }. ; (<x) ,&.> y
)
member =: 4 : 0
  (<x) e. ' ' split y
)
decimal =: 3 : 0
  text =. ":y
  '-' (I.text='_')}text
)
hexadecimal =: 4 : 0
  value =. y
  result =. ''
  for_i. i.x do.
    result =. ((16|value){'0123456789ABCDEF'),result
    value =. value floor_ratio 16
  end.
  result
)
color_text =: 3 : 0
  '#',;2 hexadecimal&.> <"0 y
)
sequence_text =: 3 : 0
  ' ' join <"1 color_text"1 y
)
hex_digit =: 3 : 0
  position =. '0123456789abcdefABCDEF' i. {.y
  if. position=22 do. _1 return. end.
  if. position<16 do. position else. position-6 end.
)
digits =: 3 : 0
  (0<#y)*.*./y e.'0123456789'
)
integer =: 4 : 0
  'low high' =. x
  text =. y
  negative =. 0
  if. '-'={.text do.
    negative =. 1
    text =. }.text
  end.
  if. ((#text)<1)+.((#text)>9)+.-.digits text do. (0 0) return. end.
  value =. x: 0".text
  if. negative do. value =. -value end.
  ((low<:value)*.value<:high),value
)
valid_name =: 3 : 0
  ((#y)>:1)*.((#y)<:12)*.*./y e.'abcdefghijklmnopqrstuvwxyz'
)
bnames =: ;:'black maroon green olive navy purple teal silver gray red lime yellow blue magenta cyan white orange pink brown gold coral salmon violet indigo'
bcolors =: 24 3$0 0 0 128 0 0 0 128 0 128 128 0 0 0 128 128 0 128 0 128 128 192 192 192 128 128 128 255 0 0 0 255 0 255 255 0 0 0 255 255 0 255 0 255 255 255 255 255 255 165 0 255 192 203 165 42 42 255 215 0 255 127 80 250 128 114 238 130 238 75 0 130
parse_color =: 3 : 0
  text =. y
  if. '#'={.text do.
    if. -. (#text)e.4 7 do. (i.0) return. end.
    width =. 2
    if. 4=#text do. width =. 1 end.
    result =. i.0
    for_i. i.3 do.
      first =. hex_digit (1+i*width){text
      second =. first
      if. width=2 do. second =. hex_digit (2+i*width){text end.
      if. (first<0)+.second<0 do. (i.0) return. end.
      result =. result,(16*first)+second
    end.
    result return.
  end.
  if. ('rgb('-:4{.text)*.')'={:text do.
    components =. ',' split 4}.}:text
    if. 3~:#components do. (i.0) return. end.
    result =. i.0
    for_box. components do.
      component =. >box
      if. ((#component)<1)+.((#component)>3)+.-.digits component do. (i.0) return. end.
      value =. 0".component
      if. value>255 do. (i.0) return. end.
      result =. result,value
    end.
    result return.
  end.
  names =. bnames,rnames
  colors =. bcolors,rcolors
  position =. names i.<text
  if. position=#names do. (i.0) return. end.
  position{colors
)
distance =: 4 : 0
  +/*:x-y
)
hue =: 3 : 0
  'r g b' =. y
  largest =. >./y
  delta =. largest-<./y
  if. delta=0 do. 0 return. end.
  if. largest=r do.
    numerator =. 60*(g-b)
    if. numerator<0 do. numerator =. numerator+360*delta end.
  elseif. largest=g do. numerator =. (60*(b-r))+120*delta
  else. numerator =. (60*(r-g))+240*delta
  end.
  360|numerator rounded delta
)
hsl =: 3 : 0
  largest =. >./y
  smallest =. <./y
  delta =. largest-smallest
  saturation =. 0
  if. delta>0 do. saturation =. (100*delta) rounded 255-|largest+smallest-255 end.
  (hue y),saturation,(100*(largest+smallest)) rounded 510
)
factors =: 3 : 0
  sector =. y floor_ratio 60
  fraction =. 60|y
  xvalue =. fraction
  if. 2|sector do. xvalue =. 60-fraction end.
  choices =. 6 3$60,xvalue,0,xvalue,60,0,0,60,xvalue,0,xvalue,60,xvalue,0,60,60,0,xvalue
  sector{choices
)
from_hsl =: 3 : 0
  'angle saturation lightness' =. y
  chroma =. (100-| (2*lightness)-100)*saturation
  numerator =. (chroma*((factors angle)-30))+6000*lightness
  (255*numerator) rounded 600000
)
from_hsv =: 3 : 0
  'angle saturation value' =. y
  chroma =. value*saturation
  numerator =. (chroma*((factors angle)-60))+6000*value
  (255*numerator) rounded 600000
)
from_hwb =: 3 : 0
  'angle whiteness blackness' =. y
  if. (whiteness+blackness)>:100 do.
    value =. (255*whiteness) rounded whiteness+blackness
    (3$value) return.
  end.
  numerator =. ((factors angle)*((100-whiteness)-blackness))+60*whiteness
  (255*numerator) rounded 6000
)
model =: 4 : 0
  name =. x
  'r g b' =. y
  largest =. >./y
  smallest =. <./y
  delta =. largest-smallest
  if. name-:'HSL' do. (hsl y) return. end.
  if. name-:'HSV' do.
    saturation =. 0
    if. largest>0 do. saturation =. (100*delta) rounded largest end.
    ((hue y),saturation,(100*largest) rounded 255) return.
  end.
  if. name-:'HWB' do.
    ((hue y),((100*smallest) rounded 255),(100*(255-largest)) rounded 255) return.
  end.
  if. name-:'CMYK' do.
    if. largest=0 do. (0 0 0 100) return. end.
    cyanmagenta =. (100*(largest-y)) rounded largest
    (cyanmagenta,(100*(255-largest)) rounded 255) return.
  end.
  luma =. ((299*r)+(587*g)+114*b) rounded 1000
  if. name-:'YIQ' do.
    ivalue =. (((596*r)-(274*g))-322*b) rounded 1000
    qvalue =. (((211*r)-(523*g))+312*b) rounded 1000
    (luma,ivalue,qvalue) return.
  end.
  cb =. (((128000-(169*r))-(331*g))+500*b) rounded 1000
  cr =. (((128000+(500*r))-(419*g))-81*b) rounded 1000
  clamp luma,cb,cr
)
model_text =: 4 : 0
  name =. x
  values =. name model y
  fields =. 0$<''
  for_i. i.#values do.
    text =. decimal i{values
    if. (name-:'CMYK')+.((name member 'HSL HSV HWB')*.i>0) do. text =. text,'%' end.
    fields =. fields,<text
  end.
  (tolower name),'(',(',' join fields),')'
)
ansi_color =: 3 : 0
  if. y<16 do. (y{bcolors) return. end.
  if. y>:232 do. (3$8+10*(y-232)) return. end.
  levels =. 0 95 135 175 215 255
  value =. y-16
  indices =. (value floor_ratio 36),(6|value floor_ratio 6),6|value
  indices{levels
)
luminance =: 3 : 0
  +/2126 7152 722 * *:y
)
contrast =: 4 : 0
  a =. luminance x
  b =. luminance y
  high =. (a>.b)+32512500
  low =. (a<.b)+32512500
  verdict =. 0
  if. high>:7*low do. verdict =. 2
  elseif. (2*high)>:9*low do. verdict =. 1
  end.
  ((100*high) rounded low),verdict
)
contrast_text =: 4 : 0
  'ratio verdict' =. x contrast y
  tail =. _2{.'0',decimal 100|ratio
  (decimal ratio floor_ratio 100),'.',tail,' ',>verdict{'FAIL';'AA';'AAA'
)
gradient =: 3 : 0
  'first second count' =. y
  result =. 0 3$0
  for_i. i.count do.
    color =. first + ((second-first)*i) away count-1
    result =. result,color
  end.
  result
)
mean_color =: 3 : 0
  (+/y) rounded #y
)
widths =: 3 : 0
  (>./y)-<./y
)
palette =: 4 : 0
  count =. x
  boxes =. ,<y
  while. (#boxes)<count do.
    selected =. _1
    widest =. _1
    channel =. 0
    for_i. i.#boxes do.
      box =. >i{boxes
      if. (#box)<2 do. continue. end.
      spans =. widths box
      component =. spans i. >./spans
      if. (component{spans)>widest do.
        selected =. i
        widest =. component{spans
        channel =. component
      end.
    end.
    box =. >selected{boxes
    box =. box {~ /:channel{"1 box
    middle =. (#box) floor_ratio 2
    next =. 0$<0 3$0
    for_i. i.#boxes do.
      if. i=selected do.
        next =. next,(<middle{.box),<middle}.box
      else. next =. next,i{boxes
      end.
    end.
    boxes =. next
  end.
  boxes
)
blend_component =: 3 : 0
  'mode xvalue yvalue' =. y
  multiplied =. (xvalue*yvalue) floor_ratio 255
  screened =. 255-((255-xvalue)*(255-yvalue)) floor_ratio 255
  if. mode-:'MULTIPLY' do. multiplied return. end.
  if. mode-:'SCREEN' do. screened return. end.
  if. mode member 'OVERLAY HARDLIGHT' do.
    low =. xvalue<128
    if. mode-:'HARDLIGHT' do. low =. yvalue<128 end.
    if. low do. ((2*xvalue*yvalue) floor_ratio 255) return. end.
    (255-((2*(255-xvalue))*(255-yvalue)) floor_ratio 255) return.
  end.
  if. mode-:'SOFTLIGHT' do. ((((255-xvalue)*multiplied)+xvalue*screened) floor_ratio 255) return. end.
  if. mode-:'DARKEN' do. (xvalue<.yvalue) return. end.
  if. mode-:'LIGHTEN' do. (xvalue>.yvalue) return. end.
  if. mode-:'DIFFERENCE' do. (|xvalue-yvalue) return. end.
  if. mode-:'EXCLUSION' do. (xvalue+yvalue-(2*xvalue*yvalue) floor_ratio 255) return. end.
  if. mode-:'ADD' do. (255<.xvalue+yvalue) return. end.
  if. mode-:'SUBTRACT' do. (0>.xvalue-yvalue) return. end.
  if. mode-:'COLORDODGE' do.
    if. yvalue=255 do. 255 return. end.
    (255<.(255*xvalue) floor_ratio 255-yvalue) return.
  end.
  if. yvalue=0 do. 0 return. end.
  0>.255-(255*(255-xvalue)) floor_ratio yvalue
)
schema =: 4 : 0
  command =. x
  count =. y
  if. command-:'BEST' do.
    if. (count>:2)*.count<:33 do. (count$'C') return. end.
    '?' return.
  end.
  if. command member 'SORT DITHER' do.
    if. (count>:1)*.count<:32 do. (count$'C') return. end.
    '?' return.
  end.
  if. command member 'PALETTE KMEANS' do.
    if. (count>:2)*.count<:33 do. ('B',(count-1)$'C') return. end.
    '?' return.
  end.
  definitions =. 'PARSE C';'DEFINE NC';'UNDEFINE N';'LIST';'HSL C';'FROMHSL HPP';'HSV C';'FROMHSV HPP';'HWB C';'FROMHWB HPP';'CMYK C';'FROMCMYK PPPP';'YCBCR C';'FROMYCBCR YYY';'YIQ C';'FROMYIQ YII';'RGB565 C';'FROM565 X';'ANSI C';'FROMANSI Y';'WEBSAFE C';'GRAY CK';'INVERT C';'MIX CCP';'MIXHSL CCP';'GRADIENT CCG';'TINTS CT';'SHADES CT';'TONES CT';'BLEND KCC';'ALPHA CPCP';'SIMULATE CK';'ROTATE CD';'COMPLEMENT C';'TRIADIC C';'TETRADIC C';'SPLITCOMP C';'ANALOGOUS CAS';'LIGHTEN CP';'DARKEN CP';'SATURATE CP';'DESATURATE CP';'NEAREST C';'DISTANCE CC';'CONTRAST CC';'ACCESSIBLE CC';'DESCRIBE C';'RANDOM RU'
  for_definition. definitions do.
    parts =. ' ' split >definition
    if. command-:>{.parts do.
      result =. ''
      if. 2=#parts do. result =. >1{parts end.
      if. count=#result do. result return. end.
      '?' return.
    end.
  end.
  '?'
)
execute =: 3 : 0
  words =. ' ' split y
  command =. >{.words
  arguments =. }.words
  kinds =. command schema #arguments
  if. kinds-:'?' do. 'INVALID' return. end.
  names =. bnames,rnames
  colors =. bcolors,rcolors
  parsed =. (#arguments)$<i.0
  numbers =. (#arguments)$0
  for_i. i.#arguments do.
    kind =. i{kinds
    argument =. >i{arguments
    if. kind='C' do.
      color =. parse_color argument
      if. 3~:#color do. 'INVALID' return. end.
      parsed =. (<color) i}parsed
    elseif. kind='N' do.
      if. -.valid_name argument do. 'INVALID' return. end.
    elseif. kind='K' do.
      keywords =. 'MULTIPLY SCREEN OVERLAY HARDLIGHT SOFTLIGHT DARKEN LIGHTEN DIFFERENCE EXCLUSION ADD SUBTRACT COLORDODGE COLORBURN HUE SATURATION COLOR LUMINOSITY'
      if. command-:'GRAY' do. keywords =. 'LUMA AVERAGE LIGHTNESS HSP'
      elseif. command-:'SIMULATE' do. keywords =. 'PROTANOPIA DEUTERANOPIA TRITANOPIA ACHROMATOPSIA'
      end.
      if. -.argument member keywords do. 'INVALID' return. end.
    elseif. kind='X' do.
      if. (6~:#argument)+.-.'0x'-:2{.argument do. 'INVALID' return. end.
      value =. 0
      for_j. 2+i.4 do.
        digit =. hex_digit j{argument
        if. digit<0 do. 'INVALID' return. end.
        value =. (16*value)+digit
      end.
      numbers =. value i}numbers
    else.
      low =. 0
      high =. 100
      if. kind='H' do. high =. 359
      elseif. kind='Y' do. high =. 255
      elseif. kind='I' do. low =. _255 [ high =. 255
      elseif. kind='D' do. low =. _720 [ high =. 720
      elseif. kind='G' do. low =. 2 [ high =. 16
      elseif. kind='T' do. low =. 1 [ high =. 10
      elseif. kind='A' do. low =. 1 [ high =. 6
      elseif. kind='S' do. low =. 1 [ high =. 60
      elseif. kind='R' do. low =. 1 [ high =. 999999999
      elseif. kind='U' do. low =. 1 [ high =. 16
      elseif. kind='B' do. low =. 1 [ high =. 32
      end.
      'valid value' =. (low,high) integer argument
      if. -.valid do. 'INVALID' return. end.
      numbers =. value i}numbers
    end.
  end.
  if. command member 'PALETTE KMEANS' do.
    if. ({.numbers)>(#arguments)-1 do. 'INVALID' return. end.
  end.
  if. command-:'DEFINE' do.
    name =. >0{arguments
    if. (<name)e.bnames do. 'INVALID' return. end.
    position =. rnames i.<name
    color =. >1{parsed
    if. position<#rnames do. rcolors =: color position}rcolors
    else.
      rnames =: rnames,<name
      rcolors =: rcolors,color
    end.
    (name,' ',color_text color) return.
  end.
  if. command-:'UNDEFINE' do.
    name =. >0{arguments
    position =. rnames i.<name
    if. position=#rnames do. 'INVALID' return. end.
    keep =. position~:i.#rnames
    rnames =: keep#rnames
    rcolors =: keep#rcolors
    (name,' removed') return.
  end.
  if. command-:'LIST' do.
    if. 0=#rnames do. 'NONE' return. end.
    result =. 0$<''
    for_i. /:rnames do.
      result =. result,<(>i{rnames),'=',color_text i{rcolors
    end.
    (' ' join result) return.
  end.
  first =. i.0
  second =. i.0
  if. #parsed do. first =. >0{parsed end.
  if. 1<#parsed do. second =. >1{parsed end.
  if. command member 'HSL HSV HWB CMYK YCBCR YIQ' do.
    (command model_text first) return.
  end.
  if. command-:'PARSE' do.
    matching =. '-'
    for_i. i.#colors do.
      if. first-:i{colors do. matching =. >i{names break. end.
    end.
    components =. 0$<''
    for_value. first do. components =. components,<decimal value end.
    result =. (color_text first);('rgb(',(',' join components),')')
    for_name. ;:'HSL HSV HWB CMYK YCBCR YIQ' do.
      result =. result,< (>name) model_text first
    end.
    result =. result,<matching
    (' ' join result) return.
  end.
  if. command-:'FROMHSL' do. (color_text from_hsl numbers) return. end.
  if. command-:'FROMHSV' do. (color_text from_hsv numbers) return. end.
  if. command-:'FROMHWB' do. (color_text from_hwb numbers) return. end.
  if. command-:'FROMCMYK' do.
    numerator =. 255*(100-3{.numbers)*(100-3{numbers)
    (color_text numerator rounded 10000) return.
  end.
  if. command-:'FROMYCBCR' do.
    'yv cb cr' =. numbers
    cb =. cb-128
    cr =. cr-128
    red =. ((1000*yv)+1402*cr) rounded 1000
    green =. (((1000*yv)-(344*cb))-714*cr) rounded 1000
    blue =. ((1000*yv)+1772*cb) rounded 1000
    (color_text clamp red,green,blue) return.
  end.
  if. command-:'FROMYIQ' do.
    'yv iv qv' =. numbers
    red =. ((1000*yv)+(956*iv)+619*qv) rounded 1000
    green =. (((1000*yv)-(272*iv))-647*qv) rounded 1000
    blue =. (((1000*yv)-(1106*iv))+1703*qv) rounded 1000
    (color_text clamp red,green,blue) return.
  end.
  if. command-:'RGB565' do.
    value =. (2048*((31*0{first) rounded 255))+(32*((63*1{first) rounded 255))+((31*2{first) rounded 255)
    ('0x',4 hexadecimal value) return.
  end.
  if. command-:'FROM565' do.
    value =. {.numbers
    red =. (255*(value floor_ratio 2048)) rounded 31
    green =. (255*(64|value floor_ratio 32)) rounded 63
    blue =. (255*(32|value)) rounded 31
    (color_text red,green,blue) return.
  end.
  if. command-:'FROMANSI' do. (color_text ansi_color {.numbers) return. end.
  if. command member 'ANSI NEAREST' do.
    start =. 0
    stop =. #colors
    if. command-:'ANSI' do. start =. 16 [ stop =. 256 end.
    best =. _1
    bestdistance =. _1
    for_i. start+i.stop-start do.
      if. command-:'ANSI' do. candidate =. ansi_color i
      else. candidate =. i{colors
      end.
      difference =. first distance candidate
      if. (best=_1)+.difference<bestdistance do.
        best =. i
        bestdistance =. difference
      end.
    end.
    if. command-:'ANSI' do.
      label =. decimal best
      selected =. ansi_color best
    else.
      label =. >best{names
      selected =. best{colors
    end.
    (label,' ',(color_text selected),' ',decimal bestdistance) return.
  end.
  if. command member 'WEBSAFE INVERT GRAY' do.
    if. command-:'INVERT' do. (color_text 255-first) return. end.
    if. command-:'WEBSAFE' do. (color_text 51*first rounded 51) return. end.
    method =. >1{arguments
    if. method-:'LUMA' do. value =. (+/299 587 114*first) rounded 1000
    elseif. method-:'AVERAGE' do. value =. (+/first) rounded 3
    elseif. method-:'LIGHTNESS' do. value =. ((>./first)+<./first) rounded 2
    else. value =. (+/ 299 587 114 * *: first) root_ratio 1000
    end.
    (color_text 3$value) return.
  end.
  if. command-:'MIX' do.
    p =. 2{numbers
    numerator =. (first*(100-p))+second*p
    (color_text numerator rounded 100) return.
  end.
  if. command-:'MIXHSL' do.
    a =. hsl first
    b =. hsl second
    p =. 2{numbers
    delta =. 360|(0{b)-0{a
    if. delta>180 do. delta =. delta-360 end.
    angle =. 360|(0{a)+(delta*p) away 100
    saturation =. (1{a)+(((1{b)-1{a)*p) away 100
    lightness =. (2{a)+(((2{b)-2{a)*p) away 100
    (color_text from_hsl angle,saturation,lightness) return.
  end.
  if. command-:'GRADIENT' do.
    (sequence_text gradient first;second;2{numbers) return.
  end.
  if. command member 'TINTS SHADES TONES' do.
    value =. 128
    if. command-:'TINTS' do. value =. 255
    elseif. command-:'SHADES' do. value =. 0
    end.
    count =. 1{numbers
    result =. gradient first;(3$value);count+2
    (sequence_text count{.}.result) return.
  end.
  if. command-:'BLEND' do.
    mode =. >0{arguments
    basecolor =. >1{parsed
    topcolor =. >2{parsed
    if. mode member 'HUE SATURATION COLOR LUMINOSITY' do.
      a =. hsl basecolor
      b =. hsl topcolor
      if. mode member 'HUE COLOR' do. a =. (0{b) (0)}a end.
      if. mode member 'SATURATION COLOR' do. a =. (1{b) (1)}a end.
      if. mode-:'LUMINOSITY' do. a =. (2{b) (2)}a end.
      (color_text from_hsl a) return.
    end.
    result =. i.0
    for_i. i.3 do.
      result =. result,blend_component mode;(i{basecolor);i{topcolor
    end.
    (color_text result) return.
  end.
  if. command-:'ALPHA' do.
    p =. 1{numbers
    q =. 3{numbers
    opacity =. (100*p)+q*(100-p)
    result =. 0 0 0
    if. opacity>0 do.
      numerator =. (100*p*(>0{parsed))+(q*(100-p))*(>2{parsed)
      result =. numerator rounded opacity
    end.
    ((color_text result),' ',(decimal opacity rounded 100),'%') return.
  end.
  if. command-:'SIMULATE' do.
    type =. >1{arguments
    matrix =. 3 3$299 587 114 299 587 114 299 587 114
    if. type-:'PROTANOPIA' do. matrix =. 3 3$567 433 0 558 442 0 0 242 758
    elseif. type-:'DEUTERANOPIA' do. matrix =. 3 3$625 375 0 700 300 0 0 300 700
    elseif. type-:'TRITANOPIA' do. matrix =. 3 3$950 50 0 0 433 567 0 475 525
    end.
    numerator =. matrix +/ . * first
    (color_text numerator rounded 1000) return.
  end.
  if. command member 'ROTATE COMPLEMENT TRIADIC TETRADIC SPLITCOMP ANALOGOUS LIGHTEN DARKEN SATURATE DESATURATE' do.
    values =. hsl first
    shifts =. i.0
    if. command-:'ROTATE' do. shifts =. ,1{numbers
    elseif. command-:'COMPLEMENT' do. shifts =. ,180
    elseif. command-:'TRIADIC' do. shifts =. 120 240
    elseif. command-:'TETRADIC' do. shifts =. 90 180 270
    elseif. command-:'SPLITCOMP' do. shifts =. 150 210
    elseif. command-:'ANALOGOUS' do.
      k =. 1{numbers
      step =. 2{numbers
      for_i. (i.1+2*k)-k do.
        if. i~:0 do. shifts =. shifts,i*step end.
      end.
    else.
      p =. 1{numbers
      if. command-:'LIGHTEN' do. values =. (100<.(2{values)+p) (2)}values
      elseif. command-:'DARKEN' do. values =. (0>.(2{values)-p) (2)}values
      elseif. command-:'SATURATE' do. values =. (100<.(1{values)+p) (1)}values
      else. values =. (0>.(1{values)-p) (1)}values
      end.
      (color_text from_hsl values) return.
    end.
    result =. 0 3$0
    for_shift. shifts do.
      angle =. 360|(0{values)+shift
      result =. result,from_hsl angle,}.values
    end.
    (sequence_text result) return.
  end.
  if. command-:'DISTANCE' do.
    'dr dg db' =. first-second
    redweight =. 1024+(0{first)+0{second
    blueweight =. (1534-(0{first))-0{second
    weighted =. (redweight*dr*dr)+(2048*dg*dg)+blueweight*db*db
    ((decimal first distance second),' ',decimal weighted root_ratio 512) return.
  end.
  if. command-:'CONTRAST' do. (first contrast_text second) return. end.
  if. command-:'ACCESSIBLE' do.
    selected =. first
    assessment =. first contrast second
    if. 0=1{assessment do.
      values =. hsl first
      found =. 0
      for_step. >:i.100 do.
        lightnesses =. ((2{values)-step),(2{values)+step
        for_lightness. lightnesses do.
          if. (lightness>:0)*.lightness<:100 do.
            candidate =. from_hsl (2{.values),lightness
            assessment =. candidate contrast second
            if. 0~:1{assessment do.
              selected =. candidate
              found =. 1
              break.
            end.
          end.
        end.
        if. found do. break. end.
      end.
    end.
    ((color_text selected),' ',selected contrast_text second) return.
  end.
  if. command-:'BEST' do.
    best =. 1
    assessment =. (>1{parsed) contrast first
    for_i. 2+i.(#parsed)-2 do.
      candidate =. (>i{parsed) contrast first
      if. ({.candidate)>{.assessment do.
        best =. i
        assessment =. candidate
      end.
    end.
    selected =. >best{parsed
    ((color_text selected),' ',selected contrast_text first) return.
  end.
  if. command-:'DESCRIBE' do.
    'angle saturation lightness' =. hsl first
    if. lightness<:5 do. 'black' return. end.
    if. lightness>:95 do. 'white' return. end.
    if. lightness<:20 do. lightword =. 'very dark'
    elseif. lightness<:40 do. lightword =. 'dark'
    elseif. lightness<:60 do. lightword =. 'medium'
    elseif. lightness<:80 do. lightword =. 'light'
    else. lightword =. 'very light'
    end.
    if. saturation<10 do. (lightword,' gray') return. end.
    if. saturation<40 do. saturationword =. 'muted'
    elseif. saturation<80 do. saturationword =. 'moderate'
    else. saturationword =. 'vivid'
    end.
    hues =. ' ' split 'red orange yellow chartreuse green spring-green cyan azure blue violet magenta rose'
    hueindex =. (360|angle+15) floor_ratio 30
    (lightword,' ',saturationword,' ',>hueindex{hues) return.
  end.
  if. command member 'PALETTE KMEANS' do.
    k =. {.numbers
    source =. >}.parsed
    boxes =. k palette source
    representatives =. 0 3$0
    for_box. boxes do. representatives =. representatives,mean_color >box end.
    counts =. i.0
    iterations =. 0
    if. command-:'PALETTE' do.
      counts =. #&>boxes
    else.
      for_iteration. >:i.20 do.
        iterations =. iteration
        assigned =. k$<0 3$0
        for_color. source do.
          best =. 0
          bestdistance =. color distance 0{representatives
          for_j. >:i.k-1 do.
            difference =. color distance j{representatives
            if. difference<bestdistance do.
              best =. j
              bestdistance =. difference
            end.
          end.
          group =. >best{assigned
          assigned =. (<group,color) best}assigned
        end.
        next =. representatives
        counts =. i.0
        for_j. i.k do.
          group =. >j{assigned
          counts =. counts,#group
          if. #group do. next =. (mean_color group) j}next end.
        end.
        equal =. next-:representatives
        representatives =. next
        if. equal do. break. end.
      end.
    end.
    result =. 0$<''
    if. command-:'KMEANS' do. result =. <decimal iterations end.
    for_i. i.k do.
      result =. result,<(color_text i{representatives),':',decimal i{counts
    end.
    (' ' join result) return.
  end.
  if. command-:'SORT' do.
    source =. >parsed
    keys =. 0 3$0
    for_color. source do. keys =. keys,hsl color end.
    (sequence_text (/:keys){source) return.
  end.
  if. command-:'DITHER' do.
    diffusion =. 0 0 0
    result =. 0$<''
    for_box. parsed do.
      adjusted =. clamp (>box)+diffusion
      best =. 0
      bestdistance =. adjusted distance 0{bcolors
      for_i. >:i.15 do.
        difference =. adjusted distance i{bcolors
        if. difference<bestdistance do.
          best =. i
          bestdistance =. difference
        end.
      end.
      diffusion =. adjusted-best{bcolors
      result =. result,best{bnames
    end.
    (' ' join result) return.
  end.
  if. command-:'RANDOM' do.
    'state count' =. numbers
    result =. 0 3$0
    for_i. i.count do.
      state =. 2147483647|48271*state
      angle =. 360|state
      state =. 2147483647|48271*state
      saturation =. 40+61|state
      state =. 2147483647|48271*state
      lightness =. 25+51|state
      result =. result,from_hsl angle,saturation,lightness
    end.
    (sequence_text result) return.
  end.
  'INVALID'
)
main =: 3 : 0
  input =. 1!:1 (3)
  lines =. <;._2 input
  count =. 0".>0{lines
  rnames =: 0$<''
  rcolors =: 0 3$0
  for_i. >:i.count do.
    result =. execute >i{lines
    (result,LF) 1!:2 (4)
  end.
  i.0 0
)
main ''
