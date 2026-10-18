split =: 4 : 0
  result =. 0$<''
  start =. 0
  for_position. I.x E.y do.
    result =. result,< (position-start){.start}.y
    start =. position+#x
  end.
  result,<start}.y
)
decode =: 3 : 0
  result =. ''
  i =. 0
  while. i<#y do.
    char =. i{y
    if. char='+' do. result =. result,' ' [ i =. i+1
    elseif. char='%' do.
      digits =. '0123456789abcdef' i. tolower (i+1 2){y
      value =. (16*0{digits)+1{digits
      result =. result,value{a.
      i =. i+3
    else. result =. result,char [ i =. i+1
    end.
  end.
  result
)
main =: 3 : 0
  queries =. 'name=Alice+Smith&age=30&city=New%20York';'q=c%2B%2B+tutorial&page=2&sort=desc&page=3';'msg=50%25+off%21&debug&lang=en&ref=&lang=ja';'redirect=https%3a%2f%2fexample.com%2Fhome&token=abc==&item10=pen&item2=fish%26chips'
  for_index. i.4 do.
    keys =. values =. 0$<''
    for_box. '&' split >index{queries do.
      item =. >box
      separator =. item i.'='
      key =. decode separator{.item
      value =. ''
      if. separator<#item do. value =. decode (separator+1)}.item end.
      keys =. keys,<key
      values =. values,<value
    end.
    smoutput 'query ',(":>:index),':'
    for_key. /:~ ~.keys do.
      quoted =. 0$<''
      for_i. I.keys=key do.
        quoted =. quoted,<'"',(>i{values),'"'
      end.
      joined =. 2}. ; (<', ') ,&.> quoted
      smoutput '  ',(>key),': ',joined
    end.
  end.
)
main ''
