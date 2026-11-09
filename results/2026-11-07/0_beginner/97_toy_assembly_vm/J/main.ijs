split =: 4 : 0
  <;._1 x,y
)

valueof =: 3 : 0
  index =. 'ABCD'i.{.y
  if. (1=#y)*.({.y)e.'ABCD' do. index{registers
  else. 0".y
  end.
)
main =: 3 : 0
  program =. 'SET A 1';'SET B 1';'SET D 8';'MUL A B';'PRINT A';'ADD B 1';'SUB D 1';'JNZ D -4';'SET A 1071';'SET B 462';'SET C A';'MOD C B';'SET A B';'SET B C';'JNZ B -4';'PRINT A';'HALT'
  registers =: 4$0
  pc =. executed =. 0
  while. (pc>:0)*.pc<#program do.
    fields =. ' ' split >pc{program
    operation =. >{.fields
    executed =. >:executed
    if. operation-:'HALT' do. break. end.
    if. operation-:'PRINT' do. smoutput ":valueof >1{fields
    elseif. operation-:'JNZ' do.
      offset =. 0".>2{fields
      if. 0~:valueof >1{fields do. pc =. pc+offset
      else. pc =. >:pc
      end.
      continue.
    else.
      index =. 'ABCD'i.{.>1{fields
      value =. valueof >2{fields
      old =. index{registers
      if. operation-:'SET' do. result =. value
      elseif. operation-:'ADD' do. result =. old+value
      elseif. operation-:'SUB' do. result =. old-value
      elseif. operation-:'MUL' do. result =. old*value
      else. result =. value|old
      end.
      registers =: result index}registers
    end.
    pc =. >:pc
  end.
  smoutput 'executed: ',":executed
)
main ''
