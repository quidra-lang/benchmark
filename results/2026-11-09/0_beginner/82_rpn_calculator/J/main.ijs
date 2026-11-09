split =: 4 : 0
  <;._1 x,y
)

main =: 3 : 0
  expressions =. '3 4 + 2 *';'-17 5 / 4 -3 * -';'1 2 + * 3';'15 7 1 1 + - / 3 * 2 1 1 + + -';'4 2 5 * + 1 3 2 * - 5 + /';'2 3 4 + 5';'46341 46339 * -2 /'
  for_box. expressions do.
    expression =. >box
    stack =. i.0
    failure =. ''
    for_tokenbox. ' ' split expression do.
      token =. >tokenbox
      operator =. ((#token)=1)*.({.token)e.'+-*/'
      if. operator do.
        if. (#stack)<2 do. failure =. 'stack underflow' break. end.
        b =. {:stack
        a =. _2{stack
        stack =. _2}.stack
        if. token-:'+' do. value =. a+b
        elseif. token-:'-' do. value =. a-b
        elseif. token-:'*' do. value =. a*b
        elseif. b=0 do. failure =. 'division by zero' break.
        else. value =. (*a)*(*b)*<.(|a)%|b
        end.
        stack =. stack,value
      else. stack =. stack,0".token
      end.
    end.
    if. (0=#failure)*.1~:#stack do. failure =. 'leftover operands' end.
    if. #failure do. result =. 'error: ',failure
    else. result =. , '0' 8!:2 {.stack
    end.
    smoutput expression,' => ',result
  end.
)
main ''
