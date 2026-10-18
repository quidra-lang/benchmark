NB. Exact cents, integer calendar events, and native boxed catalog records.
LF=:10{a.
EMPTY=:i.0 0
split=:4:0
  <;._1 x,y
)
join=:4:0
  if. 0=#y do. '' return. end.
  (#x)}.;(<x),&.>y
)
text_equal=:4:0
  (,x)-:,y
)
number=:3:0
  ,'0' 8!:2 y
)
floor_ratio=:4:0
  <.(x:x)%x:y
)
money=:3:0
  tail=.number 100|y
  (number y floor_ratio 100),'.',((2-#tail)#'0'),tail
)
cents=:3:0
  parts=.'.' split y
  (100*0".0{::parts)+0".1{::parts
)
padded=:3:0
  text=.number y
  ((8-#text)#'0'),text
)
isbn_value=:3:0
  raw=.y#~y~:'-'
  if. -.(#raw)e.10 13 do. '' return. end.
  total=.0
  for_k. i.#raw do.
    digit=.'0123456789' i.k{raw
    if. (10=#raw)*.(k=9)*.'X'=k{raw do. digit=.10 end.
    if. (digit=10)*.-.((10=#raw)*.(k=9)*.'X'=k{raw) do. '' return. end.
    if. 10=#raw do. weight=.10-k else. weight=.1+2*2|k end.
    total=.total+digit*weight
  end.
  if. 10=#raw do.
    if. 0~:11|total do. '' return. end.
    raw=.'978',9{.raw
    values=.'0123456789'i.raw
    total=.+/values*12$1 3
    raw,number 10|10-10|total
  else.
    if. (0~:10|total)+.-.(<3{.raw)e.'978';'979' do. '' return. end.
    raw
  end.
)
NB. T: ISBN/name/price/copy-indices/queue/borrow-count.
NB. P: ID/type/name/charge-table/history. Charges: day/kind/title/amount/unpaid.
NB. C columns: title/copy-number/state/member/loan-day/due/renewals/expiry.
tget=:4:0
  y{::x{::T
)
pget=:4:0
  y{::x{::P
)
tset=:4:0
  rec=.({.x){::T
  rec=.(<y)({:x)}rec
  T=:(<rec)({.x)}T
  EMPTY
)
pset=:4:0
  rec=.({.x){::P
  rec=.(<y)({:x)}rec
  P=:(<rec)({.x)}P
  EMPTY
)
cget=:4:0
  (<x,y){C
)
cset=:4:0
  C=:y(<x)}C
  EMPTY
)
emit=:3:0
  (y,LF)1!:2(4)
  EMPTY
)
error_line=:3:0
  emit 'ERROR ',y
)
member_id=:3:0
  for_k. i.#P do. if. y text_equal k pget 0 do. k return. end. end.
  _1
)
title_id=:3:0
  for_k. i.#T do. if. y text_equal k tget 0 do. k return. end. end.
  _1
)
title_order=:3:0
  /:0{::&>T
)
member_order=:3:0
  /:0{::&>P
)
rule=:4:0
  if. 'STUDENT' text_equal x pget 1 do. y{3 14 25 1000 2 50 else. y{10 28 10 2000 5 100 end.
)
open_day=:3:0
  date=.y
  while. date e.CLOSED do. date=.date+1 end.
  date
)
balance=:3:0
  items=.y pget 3
  +/4{"1 items
)
counts=:3:0
  if. y<0 do. indices=.i.NC else. indices=.y tget 3 end.
  +/(2{"1 indices{C)=/i.5
)
holdings=:3:0
  +/3{.counts y
)
queue_position=:4:0
  queue=.y tget 4
  at=.queue i.x
  if. at=#queue do. _1 else. at end.
)
copy_of=:3:0
  'person book status'=.y
  for_index. book tget 3 do.
    if. (status=index cget 2)*.person=index cget 3 do. index return. end.
  end.
  _1
)
member_copies=:3:0
  'person status isbnonly'=.y
  indices=.i.0
  keys=.0$a:
  for_k. i.NC do.
    if. (status=k cget 2)*.person=k cget 3 do.
      key=.(k cget 0)tget 0
      if. -.isbnonly do.
        field=.5
        if. status=2 do. field=.7 end.
        key=.(padded k cget field),key
      end.
      indices=.indices,k
      keys=.keys,<key
    end.
  end.
  (/:keys){indices
)
reservations=:3:0
  result=.#member_copies y,2 0
  for_k. i.#T do. if. 0<:y queue_position k do. result=.result+1 end. end.
  result
)
late_days=:3:0
  0>.DAY-y cget 5
)
fine_amount=:3:0
  person=.y cget 3
  ((late_days y)*person rule 2)<.person rule 3
)
charge=:3:0
  'person book kind amount'=.y
  if. amount>0 do.
    items=.person pget 3
    items=.items,DAY,kind,book,amount,amount
    (person,3)pset items
    TOTAL=:(amount+(4+kind){TOTAL)(4+kind)}TOTAL
  end.
  EMPTY
)
release_copy=:3:0
  book=.y cget 0
  (y,3)cset _1
  queue=.book tget 4
  if. 0=#queue do. (y,2)cset 0 return. end.
  person=.{.queue
  (book,4)tset }.queue
  (y,2)cset 2
  (y,3)cset person
  deadline=.open_day DAY+3
  (y,7)cset deadline
  emit 'HOLD ',(book tget 0),' copy ',(number y cget 1),' ',(person pget 0),' until ',number deadline
)
end_loan=:4:0
  index=.y
  person=.index cget 3
  book=.index cget 0
  amount=.fine_amount index
  charge person,book,0,amount
  if. x do. heading=.'LOST' else. heading=.'RETURNED' end.
  entry=.heading,' ',(book tget 0),' copy ',(number index cget 1),' from ',(number index cget 4),' to ',(number DAY),' late ',(number late_days index),' fine ',money amount
  if. x do. entry=.entry,' price ',money book tget 2 end.
  (person,4)pset (person pget 4),<entry
)
lose_copy=:4:0
  index=.y
  person=.index cget 3
  book=.index cget 0
  late=.late_days index
  amount=.fine_amount index
  1 end_loan index
  price=.book tget 2
  charge person,book,2,price
  (index,2)cset 3
  TOTAL=:(1+3{TOTAL)3}TOTAL
  emit x,' ',(person pget 0),' ',(book tget 0),' copy ',(number index cget 1),' late ',(number late),' fine ',(money amount),' price ',(money price),' balance ',money balance person
  if. 0=holdings book do.
    for_person. book tget 4 do. emit 'DROPPED ',(book tget 0),' ',person pget 0 end.
    (book,4)tset i.0
  end.
  EMPTY
)
advance_day=:3:0
  target=.y
  emit 'DAY ',number target
  while. 1 do.
    nextday=.target+1
    for_k. i.NC do.
      status=.k cget 2
      if. status=1 do. nextday=.nextday<.(DAY+1)>.365+k cget 5 end.
      if. status=2 do. nextday=.nextday<.(DAY+1)>.1+k cget 7 end.
    end.
    if. nextday>target do. DAY=:target return. end.
    DAY=:nextday
    losses=.i.0
    keys=.0$a:
    for_k. i.NC do.
      if. (1=k cget 2)*.(365+k cget 5)<:DAY do.
        losses=.losses,k
        keys=.keys,<((k cget 3)pget 0),' ',(k cget 0)tget 0
      end.
    end.
    for_index. (/:keys){losses do. 'AUTOLOST' lose_copy index end.
    expiries=.i.0
    keys=.0$a:
    for_k. i.NC do.
      if. (2=k cget 2)*.(k cget 7)<DAY do.
        expiries=.expiries,k
        keys=.keys,<((k cget 0)tget 0),padded k cget 1
      end.
    end.
    for_index. (/:keys){expiries do.
      person=.index cget 3
      book=.index cget 0
      amount=.person rule 5
      charge person,book,1,amount
      emit 'EXPIRED ',(book tget 0),' copy ',(number index cget 1),' ',(person pget 0),' fee ',money amount
      release_copy index
    end.
  end.
)
renewal_error=:3:0
  if. (y cget 5)<DAY do. 'loan overdue' return. end.
  if. 2=y cget 6 do. 'renewal limit' return. end.
  if. 0<#(y cget 0)tget 4 do. 'title reserved' return. end.
  ''
)
renew_copy=:3:0
  person=.y cget 3
  deadline=.open_day DAY+person rule 1
  (y,5)cset deadline
  renewals=.1+y cget 6
  (y,6)cset renewals
  TOTAL=:(1+2{TOTAL)2}TOTAL
  emit 'RENEW ',(person pget 0),' ',((y cget 0)tget 0),' copy ',(number y cget 1),' due ',(number deadline),' renewals ',number renewals
)
command=:3:0
  words=.' ' split y
  action=.0{::words
  if. (<action)e.'DAY';'CLOSED' do.
    date=.0".1{::words
    if. date<:DAY do. error_line 'invalid day' return. end.
    if. 'DAY' text_equal action do. advance_day date return. end.
    if. date e.CLOSED do. error_line 'already closed' return. end.
    CLOSED=:CLOSED,date
    emit 'CLOSED ',number date
    for_book. title_order'' do.
      for_index. book tget 3 do.
        status=.index cget 2
        if. ((status=1)*.date=index cget 5)+.((status=2)*.date=index cget 7) do.
          replacement=.open_day date
          if. status=1 do.
            field=.5
            label=.' due '
          else.
            field=.7
            label=.' until '
          end.
          (index,field)cset replacement
          emit 'MOVED ',(book tget 0),' copy ',(number index cget 1),' ',((index cget 3)pget 0),label,number replacement
        end.
      end.
    end.
    return.
  end.
  if. 'ADDMEMBER' text_equal action do.
    id=.1{::words
    category=.2{::words
    if. 0<:member_id id do. error_line 'duplicate member' return. end.
    if. -.(<category)e.'STUDENT';'STAFF' do. error_line 'unknown type' return. end.
    name=.' 'join 3}.words
    rec=.(<id),(<category),(<name),(<0 5$0),<0$a:
    P=:P,<rec
    person=.<:#P
    emit 'ADDMEMBER ',id,' ',category,' loans ',(number person rule 0),' days ',number person rule 1
    return.
  end.
  if. (<action)e.'ADDBOOK';'WITHDRAW';'BOOK' do.
    normalized=.isbn_value 1{::words
    book=.title_id normalized
    if. 0=#normalized do. error_line 'invalid isbn' return. end.
    if. (-.'ADDBOOK' text_equal action)*.book<0 do. error_line 'unknown book' return. end.
    if. 'ADDBOOK' text_equal action do.
      name=.' 'join 4}.words
      if. book>:0 do. if. -.name text_equal book tget 1 do. error_line 'title mismatch' return. end. end.
      price=.cents 3{::words
      if. book<0 do.
        book=.#T
        rec=.(<normalized),(<name),(<price),(<i.0),(<i.0),<0
        T=:T,<rec
      end.
      (book,2)tset price
      count=.0".2{::words
      first=.NC
      for_k. i.count do.
        index=.NC
        indices=.book tget 3
        if. NC=#C do. C=:((2*#C),8){.C end.
        row=.book,(1+#indices),0,_1,0,0,0,0
        C=:row NC}C
        NC=:NC+1
        (book,3)tset indices,index
      end.
      emit 'ADDBOOK ',normalized,' added ',(number count),' total ',number holdings book
      for_index. first+i.count do. release_copy index end.
    elseif. 'WITHDRAW' text_equal action do.
      copyno=.0".2{::words
      indices=.book tget 3
      if. (copyno<1)+.copyno>#indices do. error_line 'unknown copy' return. end.
      index=.(copyno-1){indices
      if. 0~:index cget 2 do. error_line 'copy not available' return. end.
      (index,2)cset 4
      emit 'WITHDRAW ',normalized,' copy ',(number copyno),' total ',number holdings book
    else.
      emit 'BOOK ',normalized,' ',book tget 1
      emit 'PRICE ',(money book tget 2),' copies ',(number holdings book),' borrowed ',number book tget 5
      for_index. book tget 3 do.
        status=.index cget 2
        text=.'COPY ',(number index cget 1),' ',status{::;:'AVAILABLE LOANED HOLD LOST WITHDRAWN'
        if. status e.1 2 do.
          if. status=1 do.
            field=.5
            label=.' due '
          else.
            field=.7
            label=.' until '
          end.
          text=.text,' ',((index cget 3)pget 0),label,number index cget field
        end.
        emit text
      end.
      queue=.book tget 4
      text=.'QUEUE ',number #queue
      for_person. queue do. text=.text,' ',person pget 0 end.
      emit text
    end.
    return.
  end.
  personal=.;:'BORROW RETURN RENEW RENEWALL RESERVE CANCEL LOST PAYFINE WAIVE FINES MEMBER HISTORY'
  if. (<action)e.personal do.
    person=.member_id 1{::words
    if. person<0 do. error_line 'unknown member' return. end.
    id=.person pget 0
    loans=.member_copies person,1 0
    loancount=.#loans
    reservedcount=.reservations person
    outstanding=.balance person
    select. action
    case. 'PAYFINE' do.
      if. outstanding=0 do. error_line 'no fines' return. end.
      offered=.cents 2{::words
      remaining=.offered
      details=.0$a:
      items=.person pget 3
      for_k. i.#items do.
        amount=.remaining<.(<k,4){items
        if. amount>0 do.
          unpaid=.((<k,4){items)-amount
          items=.unpaid(<k,4)}items
          remaining=.remaining-amount
          kind=.(<k,1){items
          details=.details,<'ITEM ',(number k+1),' ',(kind{::;:'FINE FEE PRICE'),' paid ',(money amount),' remaining ',money unpaid
        end.
      end.
      (person,3)pset items
      TOTAL=:((7{TOTAL)+offered-remaining)7}TOTAL
      emit 'PAYFINE ',id,' paid ',(money offered-remaining),' change ',(money remaining),' balance ',money balance person
      for_detail. details do. emit >detail end.
      return.
    case. 'WAIVE' do.
      copyno=.0".2{::words
      items=.person pget 3
      if. (copyno<1)+.copyno>#items do. error_line 'unknown item' return. end.
      k=.copyno-1
      amount=.(<k,4){items
      if. amount=0 do. error_line 'item settled' return. end.
      kind=.(<k,1){items
      items=.0(<k,4)}items
      (person,3)pset items
      TOTAL=:((8{TOTAL)+amount)8}TOTAL
      emit 'WAIVE ',id,' item ',(number copyno),' ',(kind{::;:'FINE FEE PRICE'),' amount ',(money amount),' balance ',money balance person
      return.
    case. 'FINES' do.
      items=.person pget 3
      emit 'FINES ',id,' items ',(number +/0<4{"1 items),' balance ',money outstanding
      for_k. i.#items do.
        'date kind book amount unpaid'=.k{items
        if. unpaid>0 do. emit (number k+1),' day ',(number date),' ',(kind{::;:'FINE FEE PRICE'),' ',(book tget 0),' amount ',(money amount),' remaining ',money unpaid end.
      end.
      return.
    case. 'HISTORY' do.
      history=.person pget 4
      emit 'HISTORY ',id,' ',number #history
      for_entry. history do. emit >entry end.
      return.
    case. 'MEMBER' do.
      emit 'MEMBER ',id,' ',(person pget 1),' ',person pget 2
      flag=.' OK'
      if. outstanding>500 do. flag=.' BLOCKED' end.
      emit 'STATUS loans ',(number loancount),'/',(number person rule 0),' reservations ',(number reservedcount),'/',(number person rule 4),' balance ',(money outstanding),flag
      for_index. loans do.
        book=.index cget 0
        text=.'LOAN ',(book tget 0),' copy ',(number index cget 1),' due ',(number index cget 5),' renewals ',number index cget 6
        if. (index cget 5)<DAY do. text=.text,' late ',(number late_days index),' fine ',money fine_amount index end.
        emit text
      end.
      for_index. member_copies person,2 0 do.
        emit 'HOLD ',((index cget 0)tget 0),' copy ',(number index cget 1),' until ',number index cget 7
      end.
      for_book. title_order'' do.
        position=.person queue_position book
        if. position>:0 do. emit 'QUEUE ',(book tget 0),' position ',number position+1 end.
      end.
      return.
    case. 'RENEWALL' do.
      if. loancount=0 do. error_line 'no loans' return. end.
      if. outstanding>500 do. error_line 'member blocked' return. end.
      renewed=.0
      skipped=.0
      for_index. member_copies person,1 1 do.
        reason=.renewal_error index
        if. #reason do.
          emit 'SKIP ',((index cget 0)tget 0),' ',reason
          skipped=.skipped+1
        else.
          renew_copy index
          renewed=.renewed+1
        end.
      end.
      emit 'RENEWALL ',id,' renewed ',(number renewed),' skipped ',number skipped
      return.
    end.
    normalized=.isbn_value 2{::words
    book=.title_id normalized
    if. 0=#normalized do. error_line 'invalid isbn' return. end.
    if. book<0 do. error_line 'unknown book' return. end.
    loan=.copy_of person,book,1
    hold=.copy_of person,book,2
    position=.person queue_position book
    if. 'BORROW' text_equal action do.
      overdue=.0
      for_index. loans do. if. (index cget 5)<DAY do. overdue=.1 end. end.
      available=._1
      otherhold=.0
      for_index. book tget 3 do.
        if. (0=index cget 2)*.available<0 do. available=.index end.
        if. 2=index cget 2 do. otherhold=.1 end.
      end.
      reason=.''
      if. DAY e.CLOSED do. reason=.'library closed'
      elseif. loan>:0 do. reason=.'already borrowed'
      elseif. outstanding>500 do. reason=.'member blocked'
      elseif. overdue do. reason=.'overdue loans'
      elseif. loancount>:person rule 0 do. reason=.'loan limit'
      elseif. (hold<0)*.available<0 do.
        if. otherhold do. reason=.'all copies on hold' else. reason=.'no copy available' end.
      end.
      if. #reason do. error_line reason return. end.
      index=.available
      if. hold>:0 do. index=.hold end.
      (index,2)cset 1
      (index,3)cset person
      (index,4)cset DAY
      deadline=.open_day DAY+person rule 1
      (index,5)cset deadline
      (index,6)cset 0
      (book,5)tset 1+book tget 5
      TOTAL=:(1+0{TOTAL)0}TOTAL
      emit 'BORROW ',id,' ',normalized,' copy ',(number index cget 1),' due ',number deadline
    elseif. (<action)e.'RETURN';'LOST';'RENEW' do.
      if. loan<0 do. error_line 'not borrowed' return. end.
      if. 'LOST' text_equal action do. 'LOST' lose_copy loan
      elseif. 'RENEW' text_equal action do.
        reason=.renewal_error loan
        if. outstanding>500 do. reason=.'member blocked' end.
        if. #reason do. error_line reason else. renew_copy loan end.
      else.
        late=.late_days loan
        amount=.fine_amount loan
        0 end_loan loan
        TOTAL=:(1+1{TOTAL)1}TOTAL
        emit 'RETURN ',id,' ',normalized,' copy ',(number loan cget 1),' late ',(number late),' fine ',(money amount),' balance ',money balance person
        release_copy loan
      end.
    elseif. 'CANCEL' text_equal action do.
      if. (position<0)*.hold<0 do. error_line 'not reserved' return. end.
      if. position>:0 do.
        queue=.book tget 4
        (book,4)tset queue#~(i.#queue)~:position
        emit 'CANCEL ',id,' ',normalized,' queue'
      else.
        emit 'CANCEL ',id,' ',normalized,' hold copy ',number hold cget 1
        release_copy hold
      end.
    else.
      values=.counts book
      reason=.''
      if. loan>:0 do. reason=.'already borrowed'
      elseif. (position>:0)+.hold>:0 do. reason=.'already reserved'
      elseif. outstanding>500 do. reason=.'member blocked'
      elseif. reservedcount>:person rule 4 do. reason=.'reservation limit'
      elseif. 0=holdings book do. reason=.'no copies'
      elseif. 0<0{values do. reason=.'copy available' end.
      if. #reason do. error_line reason return. end.
      queue=.(book tget 4),person
      (book,4)tset queue
      dues=.i.0
      for_index. book tget 3 do. if. 1=index cget 2 do. dues=.dues,index cget 5 end. end.
      dues=./:~dues
      estimate=.'none'
      if. (#dues)>:#queue do. estimate=.number ((#queue)-1){dues end.
      emit 'RESERVE ',id,' ',normalized,' position ',(number #queue),' estimate ',estimate
    end.
    return.
  end.
  select. action
  case. 'MEMBERS' do.
    emit 'MEMBERS ',number #P
    for_person. member_order'' do.
      outstanding=.balance person
      flag=.' OK'
      if. outstanding>500 do. flag=.' BLOCKED' end.
      emit (person pget 0),' ',(person pget 1),' loans ',(number #member_copies person,1 0),' reservations ',(number reservations person),' balance ',(money outstanding),flag
    end.
  case. 'SEARCH' do.
    keyword=.tolower ' 'join }.words
    found=.i.0
    keys=.0$a:
    for_book. i.#T do.
      name=.tolower book tget 1
      if. 1 e.keyword E.name do.
        found=.found,book
        keys=.keys,<name,LF,book tget 0
      end.
    end.
    found=.(/:keys){found
    emit 'SEARCH ',number #found
    for_book. found do.
      values=.counts book
      emit (book tget 0),' ',(number 0{values),'/',(number holdings book),' ',book tget 1
    end.
  case. 'INVENTORY' do.
    values=.counts _1
    emit 'INVENTORY titles ',(number #T),' copies ',(number +/3{.values),' available ',(number 0{values),' loaned ',(number 1{values),' hold ',(number 2{values),' lost ',(number 3{values),' withdrawn ',number 4{values
    for_book. title_order'' do.
      values=.counts book
      emit (book tget 0),' copies ',(number holdings book),' available ',(number 0{values),' loaned ',(number 1{values),' hold ',(number 2{values),' queue ',number #book tget 4
    end.
  case. 'OVERDUE' do.
    found=.i.0
    keys=.0$a:
    for_index. i.NC do.
      if. (1=index cget 2)*.(index cget 5)<DAY do.
        found=.found,index
        keys=.keys,<(padded index cget 5),((index cget 3)pget 0),' ',(index cget 0)tget 0
      end.
    end.
    found=.(/:keys){found
    emit 'OVERDUE ',number #found
    for_index. found do.
      emit ((index cget 3)pget 0),' ',((index cget 0)tget 0),' copy ',(number index cget 1),' due ',(number index cget 5),' late ',(number late_days index),' fine ',money fine_amount index
    end.
  case. 'NOTICES' do.
    notices=.0$a:
    for_person. member_order'' do.
      for_stage. i.3 do.
        status=.1
        if. stage=2 do. status=.2 end.
        for_index. member_copies person,status,0 do.
          due=.index cget 5
          if. (stage=2)+.((stage=0)*.due<DAY)+.((stage=1)*.(DAY<:due)*.due<:DAY+2) do.
            if. stage=2 do.
              label=.' until '
              date=.index cget 7
            else.
              label=.' due '
              date=.due
            end.
            notices=.notices,<(stage{::;:'OVERDUE DUESOON PICKUP'),' ',(person pget 0),' ',((index cget 0)tget 0),label,number date
          end.
        end.
      end.
    end.
    emit 'NOTICES ',number #notices
    for_text. notices do. emit >text end.
  case. 'STATS' do.
    values=.counts _1
    outstanding=.+/balance"0 i.#P
    emit 'STATS day ',(number DAY),' titles ',(number #T),' members ',(number #P),' closed ',number #CLOSED
    emit 'LOANS borrowed ',(number 0{TOTAL),' returned ',(number 1{TOTAL),' renewed ',(number 2{TOTAL),' lost ',(number 3{TOTAL),' active ',number 1{values
    emit 'MONEY fines ',(money 4{TOTAL),' fees ',(money 5{TOTAL),' charges ',(money 6{TOTAL),' paid ',(money 7{TOTAL),' waived ',(money 8{TOTAL),' outstanding ',money outstanding
    found=.i.0
    keys=.0$a:
    for_book. i.#T do.
      if. 0<book tget 5 do.
        found=.found,book
        keys=.keys,<(padded 1001-book tget 5),book tget 0
      end.
    end.
    ranking=.(3<.#found){.( /:keys){found
    for_k. i.#ranking do.
      book=.k{ranking
      emit 'TOP ',(number k+1),' ',(book tget 0),' ',(number book tget 5),' ',book tget 1
    end.
  end.
  EMPTY
)
main=:3:0
  T=:0$a:
  P=:0$a:
  C=:16 8$0
  NC=:0
  DAY=:1
  CLOSED=:i.0
  TOTAL=:9#0
  input=.1!:1(3)
  if. LF~:{:input do. input=.input,LF end.
  lines=.<;._2 input
  count=.0".0{::lines
  for_k. i.count do. command (k+1){::lines end.
  EMPTY
)
main''
