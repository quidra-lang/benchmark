tokenize =: 3 : 0
  result =. 0$<''
  i =. 0
  while. i<#y do.
    char =. i{y
    if. char=' ' do. i =. >:i continue. end.
    start =. i
    if. char e.'0123456789' do.
      while. i<#y do.
        if. -. (i{y)e.'0123456789' do. break. end.
        i =. >:i
      end.
    elseif. char e.'abcdefghijklmnopqrstuvwxyz' do.
      while. i<#y do.
        if. -. (i{y)e.'abcdefghijklmnopqrstuvwxyz' do. break. end.
        i =. >:i
      end.
    else. i =. >:i
    end.
    result =. result,< (i-start){.start}.y
  end.
  result
)
unary =: 3 : 0
  token =. >position{tokens
  position =: >:position
  if. token-:'-' do. (-unary'') return. end.
  if. token-:'(' do.
    value =. expression''
    if. #failure do. 0 return. end.
    position =: >:position
    value return.
  end.
  if. ({.token)e.'0123456789' do. (0".token) return. end.
  index =. names i.<token
  if. index=#names do.
    failure =: 'undefined variable ',token
    0 return.
  end.
  index{values
)
product =: 3 : 0
  value =. unary''
  while. (0=#failure)*.position<#tokens do.
    operation =. >position{tokens
    if. -. (operation-:'*')+.operation-:'/' do. break. end.
    position =: >:position
    right =. unary''
    if. #failure do. 0 return. end.
    if. operation-:'*' do. value =. value*right
    else.
      if. right=0 do.
        failure =: 'division by zero'
        0 return.
      end.
      value =. (*value)*(*right)*<.(|value)%|right
    end.
  end.
  value
)
expression =: 3 : 0
  value =. product''
  while. (0=#failure)*.position<#tokens do.
    operation =. >position{tokens
    if. -. (operation-:'+')+.operation-:'-' do. break. end.
    position =: >:position
    right =. product''
    if. #failure do. 0 return. end.
    if. operation-:'+' do. value =. value+right
    else. value =. value-right
    end.
  end.
  value
)
main =: 3 : 0
  lines =. 'width = 12';'height = width - 5';'area = width * height';'(area + 6) / 4';'shift = -area / 8 + 3';'height = 100 / (height - 7) + bonus';'volume = area * depth';'width = (width+3)*-(2-4)';'width * shift - height'
  names =: 0$<''
  values =: i.0
  for_line. lines do.
    tokens =: tokenize >line
    position =: 0
    target =. ''
    if. (#tokens)>1 do.
      if. '='-:>1{tokens do.
        target =. >0{tokens
        position =: 2
      end.
    end.
    failure =: ''
    value =. expression''
    if. #failure do. smoutput 'error: ',failure
    else.
      result =. , '0' 8!:2 value
      if. #target do.
        index =. names i.<target
        if. index=#names do.
          names =: names,<target
          values =: values,value
        else. values =: value index}values
        end.
        smoutput target,' = ',result
      else. smoutput result
      end.
    end.
  end.
)
main ''
