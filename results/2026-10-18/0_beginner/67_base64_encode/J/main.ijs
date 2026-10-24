encode =: 3 : 0
  alphabet =. 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
  bytes =. a.i.y
  result =. ''
  for_i. 3*i.>. (#bytes)%3 do.
    remaining =. (#bytes)-i
    second =. third =. 0
    if. remaining>:2 do. second =. (i+1){bytes end.
    if. remaining>:3 do. third =. (i+2){bytes end.
    value =. ((i{bytes)*65536)+(second*256)+third
    result =. result,(<.value%262144){alphabet
    result =. result,(64|<.value%4096){alphabet
    if. remaining>:2 do. result =. result,(64|<.value%64){alphabet
    else. result =. result,'='
    end.
    if. remaining>:3 do. result =. result,(64|value){alphabet
    else. result =. result,'='
    end.
  end.
  result
)
main =: 3 : 0
  for_box. 'Man';'Hello, World!';'';'<b>bold</b>';'a+b=c?' do.
    text =. >box
    smoutput '"',text,'" -> "',(encode text),'"'
  end.
)
main ''
