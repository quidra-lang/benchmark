LF=:10{a.
DIGITS=:'0123456789'
LETTERS=:'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
WORD=:'_',DIGITS,LETTERS
Sd=:a.i.DIGITS
Sw=:a.i.WORD
Ss=:9 10 11 12 13 32
allchars=:i.128
swapcase=:3 :0
 c=.a.i.y
  if.  (c>:65)*.c<:90  do.  a.{~c+32  elseif.  (c>:97)*.c<:122  do.  a.{~c-32  else.  y  end.
)
char_equal=:4 :0
 (x=y)+.('i'e.Flags)*.(x e.LETTERS)*.(swapcase x)=y
)
class_test=:4 :0
 'set neg'=.x
 hit=.(a.i.y)e.set
  if.  ('i'e.Flags)*.y e.LETTERS  do.  hit=.hit+. (a.i.swapcase y)e.set  end.
 neg~:hit
)
word_at=:3 :0
  if.  (y<0)+.y>:#Subject  do.  0  else.  (y{Subject)e.WORD  end.
)
assertion=:4 :0
  select. x
  case. 'BOL'  do.  (y=0)+.('m'e.Flags)*.(y>0)*.(LF=({.((y-1)}.Subject),0{a.))
  case. 'EOL'  do.  (y=#Subject)+.('m'e.Flags)*.(LF=({.(y}.Subject),0{a.))
  case. 'WORD'  do.  (word_at y-1)~:word_at y
  case. 'NOTWORD'  do.  (word_at y-1)=word_at y
  end.
)
consumes=:4 :0
  if.  y>:#Subject  do.  0  return.   end.
 'op arg'=.x
 c=.y{Subject
  select. op
  case. 'CHAR'  do.  arg char_equal c
  case. 'ANY'  do.  ('s'e.Flags)+.c~:LF
  case. 'CLASS'  do.  arg class_test c
  case.  do.  0
  end.
)
escape_set=:3 :0
  select. tolower y
  case. 'd'  do.  s=.Sd
  case. 'w'  do.  s=.Sw
  case. 's'  do.  s=.Ss
  end.
  if.  y e.'DWS'  do.  allchars-.s  else.  s  end.
)
