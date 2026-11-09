LF=:10{a.
readlines=:3 : '<;._2 (1!:1 <y)'
words=:3 : '<;._1 '' '',y'
dec=:3 : '(":y) rplc ''_'';''-'''
num=:3 :0
  if. '0x'-:2{.y  do. 16 #. '0123456789abcdef' i.2}.y  else. 0".y rplc '-';'_'  end.
)
hex=:4 : '''0123456789abcdef'' {~ (x$16) #: y'
join=:4 :0
  if. 0=#y  do. '-' else. (#x)}.;(x&,)&.>y  end.
)
write_lines=:4 : '(;(,&LF)&.>y) 1!:2 <x'
belongs=:4 : '(x-:y)+.(x,''.'')-:(1+#x){.y'
nobits=:3 : '''.bss'' belongs y'
stringsection=:3 : '''.rodata.str'' belongs y'
parse_object=:4 :0
 o=.cocreate''
 name__o=:x
 sections__o=:0$a:
 symbols__o=:0$a:
 relocs__o=:0$a:
 comdats__o=:0$a:
 s=.a:
  for_line. y  do.
  w=.words >line
   select. 0{::w
   case. 'section'  do.
   s=.cocreate''
   name__s=:1{::w
   alignment__s=:num 2{::w
   size__s=:num 3{::w
   bytes__s=:i.0
   owner__s=:o
   discard__s=:''
   output__s=:a:
   live__s=:0
   address__s=:0
   mapping__s=:i.0
   sections__o=:sections__o,s
   case. 'data'  do.
   h=.1{::w
   bytes__s=:bytes__s,16 #. _2[\'0123456789abcdef'i.h
   case. 'comdat'  do. comdats__o=:comdats__o,<((1{::w);2}.w)
   case. 'symbol'  do.
   v=.cocreate''
   name__v=:1{::w
   original__v=:name__v
   binding__v=:2{::w
   section__v=:a:
   offset__v=:0
   size__v=:0
   alignment__v=:1
   owner__v=:o
    if. 'common'-:3{::w  do.
    status__v=:'common'
    size__v=:num 4{::w
    alignment__v=:num 5{::w
    elseif. 'undef'-:3{::w  do. status__v=:'undef'
    else.
    status__v=:'defined'
     for_t. sections__o  do.  if. name__t-:3{::w  do. section__v=:t
   break.  end.  end.
    offset__v=:num 4{::w
    end.
   symbols__o=:symbols__o,v
   case. 'reloc'  do.
   r=.cocreate''
    for_t. sections__o  do.  if. name__t-:1{::w  do. section__r=:t
   break.  end.  end.
   offset__r=:num 2{::w
   type__r=:3{::w
    for_v. symbols__o  do.  if. name__v-:4{::w  do. symbol__r=:v
   break.  end.  end.
   addend__r=:num 5{::w
   owner__r=:o
   relocs__o=:relocs__o,r
   end.
  end.
 o
)
