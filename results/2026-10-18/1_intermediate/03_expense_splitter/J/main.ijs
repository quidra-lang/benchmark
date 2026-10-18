NB. Integer cents throughout; every division explicitly uses extended integers.
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
money_value =: 3 : 0
  'whole cents' =. '.' split y
  (100*0".whole)+0".cents
)
padded =: 4 : 0
  value =. number y
  ((0>.x-#value)#'0'),value
)
money =: 3 : 0
  (number y floor_ratio 100),'.',2 padded 100|y
)
signed_money =: 3 : 0
  prefix =. ''
  if. y>0 do. prefix =. '+'
  elseif. y<0 do. prefix =. '-'
  end.
  prefix,money |y
)
percentage =: 4 : 0
  (money (x*10000) floor_ratio y),'%'
)
rate_text =: 3 : 0
  (number y floor_ratio 10000),'.',4 padded 10000|y
)
equal_distribution =: 4 : 0
  (y$x floor_ratio y)+(i.y)<y|x
)
largest_remainder =: 4 : 0
  whole =. +/y
  result =. (x*y) floor_ratio whole
  remainders =. whole|x*y
  order =. \:remainders
  rest =. x-+/result
  for_k. rest{.order do. result =. (1+k{result) k}result end.
  result
)
NB. Member arrays preserve registration; sorted views are used for all name ties.
DAYNOW =: 1
SERIAL =: 0
MNAMES =: 0$<''
MACTIVE =: i.0
MDAYS =: i.0
CCODES =: 0$<''
CRATES =: i.0
BCATS =: 0$<''
BVALUES =: i.0
USED =: 0$<''
EXPENSES =: 0$<i.0
SETTLEMENTS =: 0$<i.0
NB. Expense fields: id,day,record,payers,payments,A,currency,category,mode,
NB. participants,specified,T,shares,contributions,interval,next day,copy count.
NB. Settlement fields: day,record,sender,receiver,A,currency,T.
member_id =: 3 : 0
  k =. MNAMES i.<y
  if. k=#MNAMES do. _1 else. k end.
)
expense_id =: 3 : 0
  for_k. i.#EXPENSES do.
    if. y text_equal 0{::k{::EXPENSES do. k return. end.
  end.
  _1
)
member_names =: 3 : 0
  names =. MNAMES
  if. y do. names =. MACTIVE#names end.
  /:~names
)
member_problem =: 3 : 0
  k =. member_id y
  if. k<0 do. 'ERROR unknown member ',y return. end.
  if. -.k{MACTIVE do. 'ERROR inactive member ',y return. end.
  ''
)
frozen_member =: 3 : 0
  for_name. (3{::y),9{::y do.
    name =. >name
    if. -. (member_id name){MACTIVE do. name return. end.
  end.
  ''
)
current_rate =: 3 : 0
  if. 0=#y do. 10000 return. end.
  k =. CCODES i.<y
  if. k=#CCODES do. _1 else. k{CRATES end.
)
converted_total =: 4 : 0
  ((x*y)+5000) floor_ratio 10000
)
computed =: 4 : 0
  result =. y
  amount =. 5{::y
  total =. amount converted_total x
  mode =. 8{::y
  specified =. 10{::y
  portions =. specified
  if. mode text_equal 'EQUAL' do. portions =. amount equal_distribution #9{::y
  elseif. (<mode)e.'PERCENT';'SHARES' do. portions =. amount largest_remainder specified
  elseif. mode text_equal 'ADJUST' do. portions =. specified+ (amount-+/specified) equal_distribution #9{::y
  end.
  shares =. total largest_remainder portions
  contributions =. total largest_remainder 4{::y
  result =. (<total) 11}result
  result =. (<shares) 12}result
  result =. (<contributions) 13}result
  result
)
currency_note =: 4 : 0
  if. 0=#y do. '' else. ' [',(money x),' ',y,']' end.
)
expense_net =: 3 : 0
  result =. (#MNAMES)$0
  payers =. 3{::y
  participants =. 9{::y
  for_k. i.#payers do.
    p =. member_id k{::payers
    result =. ((p{result)+k{13{::y) p}result
  end.
  for_k. i.#participants do.
    p =. member_id k{::participants
    result =. ((p{result)-k{12{::y) p}result
  end.
  result
)
balances_of =: 3 : 0
  result =. (#MNAMES)$0
  for_expense. EXPENSES do. result =. result+expense_net >expense end.
  for_settlement. SETTLEMENTS do.
    settlement =. >settlement
    sender =. member_id 2{::settlement
    receiver =. member_id 3{::settlement
    amount =. 6{::settlement
    result =. ((sender{result)+amount) sender}result
    result =. ((receiver{result)-amount) receiver}result
  end.
  result
)
involved =: 4 : 0
  (<x)e.(3{::y),9{::y
)
spent =: 3 : 0
  result =. 0
  for_expense. EXPENSES do.
    expense =. >expense
    if. y text_equal 7{::expense do. result =. result+11{::expense end.
  end.
  result
)
warning =: 3 : 0
  k =. BCATS i.<y
  if. k<#BCATS do.
    excess =. (spent y)-k{BVALUES
    if. excess>0 do. <'  WARNING ',y,' over budget by ',money excess return. end.
  end.
  0$<''
)
expense_result =: 3 : 0
  'expense command payer_list' =. y
  names =. 9{::expense
  amounts =. 12{::expense
  if. payer_list do.
    names =. 3{::expense
    amounts =. 13{::expense
  end.
  parts =. 0$<''
  for_k. i.#names do. parts =. parts,<(k{::names),' ',money k{amounts end.
  command,' ',(0{::expense),' ',(money 11{::expense),((5{::expense) currency_note 6{::expense),' = ',' + ' join parts
)
chronological =: 3 : 0
  keys =. 0 2$0
  for_expense. EXPENSES do.
    keys =. keys,>1 2{>expense
  end.
  /:keys
)

debts_of =: 3 : 0
  n =. #MNAMES
  raw =. (n,n)$0
  names =. member_names 0
  for_expense. EXPENSES do.
    net =. expense_net >expense
    borrowers =. i.0
    lenders =. i.0
    for_name. names do.
      k =. member_id >name
      if. (k{net)<0 do. borrowers =. borrowers,k
      elseif. (k{net)>0 do. lenders =. lenders,k
      end.
    end.
    b =. 0
    l =. 0
    while. (b<#borrowers)*.l<#lenders do.
      sender =. b{borrowers
      receiver =. l{lenders
      amount =. (-sender{net)<.receiver{net
      raw =. (amount+(<sender,receiver){raw) (<sender,receiver)}raw
      net =. ((sender{net)+amount) sender}net
      net =. ((receiver{net)-amount) receiver}net
      if. 0=sender{net do. b =. b+1 end.
      if. 0=receiver{net do. l =. l+1 end.
    end.
  end.
  for_settlement. SETTLEMENTS do.
    settlement =. >settlement
    sender =. member_id 2{::settlement
    receiver =. member_id 3{::settlement
    raw =. (((<sender,receiver){raw)-6{::settlement) (<sender,receiver)}raw
  end.
  raw-|:raw
)
history_of =: 3 : 0
  items =. 0$<i.0
  member =. member_id y
  for_expense. EXPENSES do.
    expense =. >expense
    if. y involved expense do.
      item =. (1{expense),(2{expense),(0{expense),<member{expense_net expense
      items =. items,<item
    end.
  end.
  for_settlement. SETTLEMENTS do.
    settlement =. >settlement
    if. (y text_equal 2{::settlement)+.y text_equal 3{::settlement do.
      change =. 6{::settlement
      if. y text_equal 3{::settlement do. change =. -change end.
      label =. (2{::settlement),'->',3{::settlement
      item =. (0{settlement),(1{settlement),(<label),<change
      items =. items,<item
    end.
  end.
  keys =. 0 2$0
  for_item. items do.
    keys =. keys,>0 1{>item
  end.
  items =. (/:keys){items
  result =. ,<'HISTORY ',y
  running =. 0
  for_item. items do.
    item =. >item
    running =. running+3{::item
    result =. result,<'  day ',(number 0{::item),' ',(2{::item),' ',(signed_money 3{::item),' balance ',signed_money running
  end.
  if. 1=#result do. result =. result,<'  (none)' end.
  result
)
greedy_transfers =: 3 : 0
  'names amounts indent' =. y
  remaining =. amounts
  result =. 0$<''
  while. 1 do.
    sender =. _1
    receiver =. _1
    for_k. i.#names do.
      value =. k{remaining
      if. value<0 do.
        if. sender<0 do. sender =. k
        elseif. value<sender{remaining do. sender =. k
        end.
      elseif. value>0 do.
        if. receiver<0 do. receiver =. k
        elseif. value>receiver{remaining do. receiver =. k
        end.
      end.
    end.
    if. sender<0 do. break. end.
    amount =. (-sender{remaining)<.receiver{remaining
    result =. result,<indent,(sender{::names),' -> ',(receiver{::names),' ',money amount
    remaining =. ((sender{remaining)+amount) sender}remaining
    remaining =. ((receiver{remaining)-amount) receiver}remaining
  end.
  result
)
subset_indices =: 4 : 0
  I.2|y floor_ratio x
)
lex_before =: 4 : 0
  for_k. i.(#x)<.#y do.
    if. (k{x)~:k{y do. (k{x)<k{y return. end.
  end.
  (#x)<#y
)
simplify =: 3 : 0
  balances =. balances_of''
  names =. 0$<''
  amounts =. i.0
  for_name. member_names 0 do.
    name =. >name
    amount =. (member_id name){balances
    if. amount~:0 do.
      names =. names,<name
      amounts =. amounts,amount
    end.
  end.
  if. -.y do.
    transfers =. greedy_transfers (<names),(<amounts),<'  '
    (<'SIMPLIFY GREEDY transfers ',number #transfers),transfers return.
  end.
  count =. #names
  if. count>12 do. <'ERROR too many members' return. end.
  powers =. i.0
  size =. 1
  for_k. i.count do.
    powers =. powers,size
    size =. 2*size
  end.
  sums =. size$0
  dp =. size$0
  for_mask. 1+i.size-1 do.
    members =. powers subset_indices mask
    prior =. mask-({.members){powers
    sums =. ((prior{sums)+({.members){amounts) mask}sums
    best =. >./(mask-members{powers){dp
    dp =. (best+(0=mask{sums)) mask}dp
  end.
  mask =. size-1
  output =. 0$<''
  transfer_count =. 0
  groups =. 0
  while. mask>0 do.
    first =. {.powers subset_indices mask
    present =. 2|mask floor_ratio powers
    selected =. _1
    best_members =. i.0
    for_candidate. 1+i.size-1 do.
      flags =. 2|candidate floor_ratio powers
      if. -. first{flags do. continue. end.
      if. candidate{sums do. continue. end.
      if. +./flags>present do. continue. end.
      if. (1+(mask-candidate){dp)~:mask{dp do. continue. end.
      members =. I.flags
      use =. selected<0
      if. -.use do. use =. members lex_before best_members end.
      if. use do.
        selected =. candidate
        best_members =. members
      end.
    end.
    group_names =. best_members{names
    group_amounts =. best_members{amounts
    output =. output,<'  group ',' ' join group_names
    transfers =. greedy_transfers (<group_names),(<group_amounts),<'    '
    output =. output,transfers
    transfer_count =. transfer_count+#transfers
    groups =. groups+1
    mask =. mask-selected
  end.
  (<'SIMPLIFY OPTIMAL transfers ',(number transfer_count),' groups ',number groups),output
)
execute =: 3 : 0
  fields =. ' ' split y
  command =. 0{::fields
  if. command text_equal 'MEMBER' do.
    name =. 1{::fields
    k =. member_id name
    if. k>:0 do.
      if. k{MACTIVE do. <'ERROR duplicate member ',name return. end.
      MACTIVE =: 1 k}MACTIVE
      MDAYS =: DAYNOW k}MDAYS
      <'MEMBER ',name,' rejoined' return.
    end.
    MNAMES =: MNAMES,<name
    MACTIVE =: MACTIVE,1
    MDAYS =: MDAYS,DAYNOW
    <'MEMBER ',name,' joined' return.
  end.
  if. command text_equal 'LEAVE' do.
    name =. 1{::fields
    problem =. member_problem name
    if. #problem do. <problem return. end.
    k =. member_id name
    if. 0~:k{balances_of'' do. <'ERROR member has a balance ',name return. end.
    MACTIVE =: 0 k}MACTIVE
    MDAYS =: DAYNOW k}MDAYS
    <'LEAVE ',name return.
  end.
  if. command text_equal 'CURRENCY' do.
    code =. 1{::fields
    rate =. 0".2{::fields
    k =. CCODES i.<code
    result =. 'CURRENCY ',code,' ',rate_text rate
    if. k<#CCODES do.
      result =. result,' was ',rate_text k{CRATES
      CRATES =: rate k}CRATES
    else.
      CCODES =: CCODES,<code
      CRATES =: CRATES,rate
    end.
    <result return.
  end.
  if. (<command)e.'EXPENSE';'EDIT' do.
    reference =. 1{::fields
    existing =. expense_id reference
    if. command text_equal 'EXPENSE' do.
      if. (<reference)e.USED do. <'ERROR duplicate id ',reference return. end.
    else.
      if. existing<0 do. <'ERROR unknown expense ',reference return. end.
      inactive =. frozen_member existing{::EXPENSES
      if. #inactive do. <'ERROR inactive member ',inactive return. end.
    end.
    problem =. member_problem 2{::fields
    if. #problem do. <problem return. end.
    amount_spec =. '@' split 3{::fields
    amount =. money_value 0{::amount_spec
    code =. ''
    if. 2=#amount_spec do. code =. 1{::amount_spec end.
    rate =. current_rate code
    if. rate<0 do. <'ERROR unknown currency ',code return. end.
    if. (amount=0)+.0=amount converted_total rate do. <'ERROR invalid amount' return. end.
    mode =. 5{::fields
    participants =. 0$<''
    specified =. i.0
    if. (mode text_equal 'EQUAL')*.'ALL' text_equal 6{::fields do.
      participants =. member_names 1
      specified =. (#participants)$0
    else.
      for_k. 6+i.(#fields)-6 do.
        part =. ':' split k{::fields
        name =. 0{::part
        problem =. member_problem name
        if. #problem do. <problem return. end.
        if. (<name)e.participants do. <'ERROR duplicate member ',name return. end.
        participants =. participants,<name
        value =. 0
        if. 2=#part do.
          if. (<mode)e.'PERCENT';'SHARES' do. value =. 0".1{::part
          else. value =. money_value 1{::part
          end.
        end.
        specified =. specified,value
      end.
    end.
    whole =. +/specified
    if. ((mode text_equal 'EXACT')*.whole~:amount)+.((mode text_equal 'PERCENT')*.whole~:10000)+.((mode text_equal 'SHARES')*.whole<1)+.((mode text_equal 'ADJUST')*.whole>amount) do.
      <'ERROR splits do not add up' return.
    end.
    expense =. (<reference),(<DAYNOW),(<SERIAL+1),(<,2{fields),(<,amount),(<amount),(<code),(4{fields),(<mode),(<participants),(<specified),(<0),(<i.0),(<i.0),(<0),(<0),<0
    if. command text_equal 'EDIT' do.
      old =. existing{::EXPENSES
      for_k. 1 2 14 15 16 do. expense =. (k{old) k}expense end.
    end.
    expense =. rate computed expense
    if. command text_equal 'EXPENSE' do.
      SERIAL =: SERIAL+1
      EXPENSES =: EXPENSES,<expense
      USED =: USED,<reference
    else. EXPENSES =: (<expense) existing}EXPENSES
    end.
    (<expense_result (<expense),(<command),<0),warning 7{::expense return.
  end.
  if. (<command)e.'PAYERS';'DELETE';'RECURRING';'SHOW' do.
    reference =. 1{::fields
    k =. expense_id reference
    if. k<0 do. <'ERROR unknown expense ',reference return. end.
    expense =. k{::EXPENSES
    if. (<command)e.'PAYERS';'DELETE' do.
      inactive =. frozen_member expense
      if. #inactive do. <'ERROR inactive member ',inactive return. end.
    end.
    if. command text_equal 'DELETE' do.
      EXPENSES =: (k{.EXPENSES),(k+1)}.EXPENSES
      <'DELETE ',reference return.
    end.
    if. command text_equal 'PAYERS' do.
      payers =. 0$<''
      payments =. i.0
      for_j. 2+i.(#fields)-2 do.
        part =. ':' split j{::fields
        name =. 0{::part
        problem =. member_problem name
        if. #problem do. <problem return. end.
        if. (<name)e.payers do. <'ERROR duplicate member ',name return. end.
        payers =. payers,<name
        payments =. payments,money_value 1{::part
      end.
      if. (+/payments)~:5{::expense do. <'ERROR payers do not add up' return. end.
      expense =. (<payers) 3}expense
      expense =. (<payments) 4}expense
      expense =. (<(11{::expense) largest_remainder payments) 13}expense
      EXPENSES =: (<expense) k}EXPENSES
      <expense_result (<expense),(<'PAYERS'),<1 return.
    end.
    if. command text_equal 'RECURRING' do.
      interval =. 0".2{::fields
      next_day =. 0
      if. interval>0 do. next_day =. DAYNOW+interval end.
      expense =. (<interval) 14}expense
      expense =. (<next_day) 15}expense
      EXPENSES =: (<expense) k}EXPENSES
      suffix =. ' stopped'
      if. interval>0 do. suffix =. ' interval ',(number interval),' next ',number next_day end.
      <'RECURRING ',reference,suffix return.
    end.
    output =. (<'SHOW ',reference),<'  day ',(number 1{::expense),' category ',(7{::expense),' mode ',(8{::expense),' total ',(money 11{::expense),(5{::expense) currency_note 6{::expense
    payers =. 3{::expense
    participants =. 9{::expense
    specified =. 10{::expense
    mode =. 8{::expense
    for_j. i.#payers do. output =. output,<'  paid ',(j{::payers),' ',money j{13{::expense end.
    for_j. i.#participants do.
      suffix =. ''
      value =. j{specified
      if. mode text_equal 'EXACT' do. suffix =. ' ',money value
      elseif. mode text_equal 'PERCENT' do. suffix =. ' ',(money value),'%'
      elseif. mode text_equal 'SHARES' do. suffix =. ' ',(number value),'/',number +/specified
      elseif. mode text_equal 'ADJUST' do. suffix =. ' +',money value
      end.
      output =. output,<'  share ',(j{::participants),' ',(money j{12{::expense),suffix
    end.
    if. 0<14{::expense do. output =. output,<'  recurring interval ',(number 14{::expense),' next ',number 15{::expense end.
    output return.
  end.
  if. command text_equal 'SETTLE' do.
    for_k. 1 2 do.
      problem =. member_problem k{::fields
      if. #problem do. <problem return. end.
    end.
    if. (1{::fields) text_equal 2{::fields do. <'ERROR same member ',1{::fields return. end.
    amount_spec =. '@' split 3{::fields
    amount =. money_value 0{::amount_spec
    code =. ''
    if. 2=#amount_spec do. code =. 1{::amount_spec end.
    rate =. current_rate code
    if. rate<0 do. <'ERROR unknown currency ',code return. end.
    total =. amount converted_total rate
    if. (amount=0)+.total=0 do. <'ERROR invalid amount' return. end.
    SERIAL =: SERIAL+1
    settlement =. (<DAYNOW),(<SERIAL),(1{fields),(2{fields),(<amount),(<code),<total
    SETTLEMENTS =: SETTLEMENTS,<settlement
    <'SETTLE ',(1{::fields),' -> ',(2{::fields),' ',(money total),amount currency_note code return.
  end.
  if. command text_equal 'BUDGET' do.
    category =. 1{::fields
    amount =. money_value 2{::fields
    k =. BCATS i.<category
    if. amount=0 do.
      if. k<#BCATS do.
        BCATS =: (k{.BCATS),(k+1)}.BCATS
        BVALUES =: (k{.BVALUES),(k+1)}.BVALUES
      end.
      <'BUDGET ',category,' removed' return.
    end.
    if. k=#BCATS do.
      BCATS =: BCATS,<category
      BVALUES =: BVALUES,amount
    else. BVALUES =: amount k}BVALUES
    end.
    <'BUDGET ',category,' ',money amount return.
  end.
  if. command text_equal 'DAY' do.
    day =. 0".1{::fields
    if. day<:DAYNOW do. <'ERROR invalid day ',1{::fields return. end.
    output =. ,<'DAY ',number day
    while. 1 do.
      selected =. _1
      for_k. i.#EXPENSES do.
        candidate =. k{::EXPENSES
        if. (0=14{::candidate)+.(15{::candidate)>day do. continue. end.
        use =. selected<0
        if. -.use do.
          previous =. selected{::EXPENSES
          use =. ((15{::candidate)<15{::previous)+.(((15{::candidate)=15{::previous)*.(2{::candidate)<2{::previous)
        end.
        if. use do. selected =. k end.
      end.
      if. selected<0 do. break. end.
      template =. selected{::EXPENSES
      rate =. current_rate 6{::template
      if. (0<#frozen_member template)+.0=(5{::template) converted_total rate do.
        template =. (<0) 14}template
        template =. (<0) 15}template
        EXPENSES =: (<template) selected}EXPENSES
        output =. output,<'  CANCEL ',0{::template
      else.
        copy =. template
        template =. (<1+16{::template) 16}template
        template =. (<(15{::template)+14{::template) 15}template
        EXPENSES =: (<template) selected}EXPENSES
        copy =. (<(0{::copy),'#',number 2+16{::copy) 0}copy
        copy =. (15{copy) 1}copy
        SERIAL =: SERIAL+1
        copy =. (<SERIAL) 2}copy
        for_k. 14 15 16 do. copy =. (<0) k}copy end.
        copy =. rate computed copy
        EXPENSES =: EXPENSES,<copy
        USED =: USED,0{copy
        output =. output,<'  RECUR ',(0{::copy),' ',money 11{::copy
        output =. output,warning 7{::copy
      end.
    end.
    DAYNOW =: day
    output return.
  end.
  if. command text_equal 'SIMPLIFY' do. simplify 'OPTIMAL' text_equal 1{::fields return. end.
  if. (<command)e.'OWES';'HISTORY' do.
    if. 0>member_id 1{::fields do. <'ERROR unknown member ',1{::fields return. end.
  elseif. command text_equal 'EXPENSES' do.
    if. 'MEMBER' text_equal 1{::fields do.
      if. 0>member_id 2{::fields do. <'ERROR unknown member ',2{::fields return. end.
    end.
  end.
  if. command text_equal 'HISTORY' do. history_of 1{::fields return. end.
  if. command text_equal 'BALANCES' do.
    balances =. balances_of''
    output =. ,<'BALANCES'
    for_name. member_names 1 do.
      name =. >name
      output =. output,<'  ',name,' ',signed_money (member_id name){balances
    end.
    if. 1=#output do. output =. output,<'  (none)' end.
    output return.
  end.
  if. command text_equal 'OWES' do.
    debts =. debts_of''
    name =. 1{::fields
    k =. member_id name
    output =. ,<'OWES ',name
    for_other. member_names 0 do.
      other =. >other
      amount =. (<k,member_id other){debts
      if. amount>0 do. output =. output,<'  ',name,' owes ',other,' ',money amount
      elseif. amount<0 do. output =. output,<'  ',other,' owes ',name,' ',money -amount
      end.
    end.
    if. 1=#output do. output =. output,<'  (none)' end.
    output return.
  end.
  if. command text_equal 'MATRIX' do.
    names =. member_names 1
    if. 0=#names do. 'MATRIX';'  (none)' return. end.
    debts =. debts_of''
    label_width =. >./#&>names
    cell_width =. label_width
    cells =. 0$<i.0
    for_name. names do.
      name =. >name
      row =. 0$<''
      for_other. names do.
        other =. >other
        amount =. 0>.(<(member_id name),member_id other){debts
        cell =. '-'
        if. -.name text_equal other do. cell =. money amount end.
        cell_width =. cell_width>.#cell
        row =. row,<cell
      end.
      cells =. cells,<row
    end.
    heading =. label_width#' '
    for_name. names do.
      name =. >name
      heading =. heading,'  ',((cell_width-#name)#' '),name
    end.
    output =. (<'MATRIX'),<heading
    for_k. i.#names do.
      name =. k{::names
      row =. name,(label_width-#name)#' '
      for_cell. k{::cells do.
        cell =. >cell
        row =. row,'  ',((cell_width-#cell)#' '),cell
      end.
      output =. output,<row
    end.
    output return.
  end.
  if. (<command)e.'MEMBERS';'TOTALS' do.
    output =. ,<command
    for_name. member_names 0 do.
      name =. >name
      k =. member_id name
      count =. 0
      paid =. 0
      share =. 0
      sent =. 0
      received =. 0
      for_expense. EXPENSES do.
        expense =. >expense
        count =. count+name involved expense
        payers =. 3{::expense
        participants =. 9{::expense
        payer =. payers i.<name
        participant =. participants i.<name
        if. payer<#payers do. paid =. paid+payer{13{::expense end.
        if. participant<#participants do. share =. share+participant{12{::expense end.
      end.
      for_settlement. SETTLEMENTS do.
        settlement =. >settlement
        if. name text_equal 2{::settlement do. sent =. sent+6{::settlement end.
        if. name text_equal 3{::settlement do. received =. received+6{::settlement end.
      end.
      if. command text_equal 'MEMBERS' do.
        status =. 'left'
        if. k{MACTIVE do. status =. 'active' end.
        output =. output,<'  ',name,' ',status,' day ',(number k{MDAYS),' expenses ',number count
      else.
        output =. output,<'  ',name,' paid ',(money paid),' share ',(money share),' sent ',(money sent),' received ',money received
      end.
    end.
    if. command text_equal 'MEMBERS' do.
      if. 1=#output do. output =. output,<'  (none)' end.
      output return.
    end.
    for_code. /:~CCODES do.
      code =. >code
      count =. 0
      amount =. 0
      total =. 0
      for_expense. EXPENSES do.
        expense =. >expense
        if. code text_equal 6{::expense do.
          count =. count+1
          amount =. amount+5{::expense
          total =. total+11{::expense
        end.
      end.
      if. count>0 do. output =. output,<'  currency ',code,' expenses ',(number count),' amount ',(money amount),' base ',money total end.
    end.
    total =. +/11{::&>EXPENSES
    settlement_total =. +/6{::&>SETTLEMENTS
    output,<'  expenses ',(number #EXPENSES),' total ',(money total),' settlements ',(number #SETTLEMENTS),' total ',money settlement_total return.
  end.
  if. command text_equal 'BUDGETS' do.
    output =. ,<'BUDGETS'
    for_category. /:~BCATS do.
      category =. >category
      amount =. (BCATS i.<category){BVALUES
      total =. spent category
      label =. ' left '
      if. total>amount do. label =. ' over ' end.
      output =. output,<'  ',category,' spent ',(money total),' budget ',(money amount),' used ',(total percentage amount),label,money |amount-total
    end.
    if. 1=#output do. output =. output,<'  (none)' end.
    output return.
  end.
  if. command text_equal 'CATEGORY' do.
    categories =. 0$<''
    grand_total =. 0
    for_expense. EXPENSES do.
      expense =. >expense
      categories =. categories,7{expense
      grand_total =. grand_total+11{::expense
    end.
    categories =. /:~~.categories
    totals =. spent&>categories
    categories =. (\:totals){categories
    output =. ,<'CATEGORY'
    for_category. categories do.
      category =. >category
      total =. spent category
      output =. output,<'  ',category,' ',(money total),' ',total percentage grand_total
      names =. member_names 0
      shares =. i.0
      for_name. names do.
        name =. >name
        share =. 0
        for_expense. EXPENSES do.
          expense =. >expense
          if. category text_equal 7{::expense do.
            participants =. 9{::expense
            participant =. participants i.<name
            if. participant<#participants do. share =. share+participant{12{::expense end.
          end.
        end.
        shares =. shares,share
      end.
      for_k. \:shares do.
        if. 0<k{shares do. output =. output,<'    ',(k{::names),' ',(money k{shares),' ',(k{shares) percentage total end.
      end.
    end.
    if. 1=#output do. output =. output,<'  (none)' end.
    output return.
  end.
  order =. chronological''
  if. command text_equal 'EXPENSES' do.
    output =. ,<y
    count =. 0
    total =. 0
    condition =. 1{::fields
    for_k. order do.
      expense =. k{::EXPENSES
      selected =. condition text_equal 'ALL'
      if. condition text_equal 'CATEGORY' do. selected =. (7{::expense) text_equal 2{::fields
      elseif. condition text_equal 'MEMBER' do. selected =. (2{::fields) involved expense
      elseif. condition text_equal 'DAYS' do. selected =. ((0".2{::fields)<:1{::expense)*.(1{::expense)<:0".3{::fields
      end.
      if. selected do.
        output =. output,<'  day ',(number 1{::expense),' ',(0{::expense),' ',(7{::expense),' ',(money 11{::expense),' by ',',' join 3{::expense
        count =. count+1
        total =. total+11{::expense
      end.
    end.
    output,<'  count ',(number count),' total ',money total return.
  end.
  NB. PERIODS: chronological traversal gives increasing integral bucket numbers.
  interval =. 0".1{::fields
  output =. ,<'PERIODS ',number interval
  bucket =. _1
  count =. 0
  total =. 0
  for_k. order do.
    expense =. k{::EXPENSES
    next_bucket =. ((1{::expense)-1) floor_ratio interval
    if. (bucket>:0)*.bucket~:next_bucket do.
      output =. output,<'  days ',(number 1+bucket*interval),'-',(number interval+bucket*interval),' expenses ',(number count),' total ',money total
      count =. 0
      total =. 0
    end.
    bucket =. next_bucket
    count =. count+1
    total =. total+11{::expense
  end.
  if. bucket>:0 do. output =. output,<'  days ',(number 1+bucket*interval),'-',(number interval+bucket*interval),' expenses ',(number count),' total ',money total end.
  if. 1=#output do. output =. output,<'  (none)' end.
  output
)
main =: 3 : 0
  input =. 1!:1 (3)
  if. LF~:{:input do. input=.input,LF end.
  lines =. <;._2 input
  count =. 0".0{::lines
  for_k. 1+i.count do.
    output =. execute k{::lines
    for_line. output do. ((>line),LF) 1!:2 (4) end.
  end.
  i.0 0
)
main''
