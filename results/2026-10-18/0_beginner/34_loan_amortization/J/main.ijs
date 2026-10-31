main =: 3 : 0
  balance =. 1000000
  month =. 0
  totalinterest =. 0
  totalpaid =. 0
  while. balance>0 do.
    month =. >:month
    interest =. <.balance%100
    payment =. 50000 <. balance+interest
    principal =. payment-interest
    balance =. balance-principal
    totalinterest =. totalinterest+interest
    totalpaid =. totalpaid+payment
    smoutput 'month ',(":month),': interest=',(":interest),' principal=',(":principal),' balance=',":balance
  end.
  smoutput 'total interest: ',":totalinterest
  smoutput 'total paid: ',":totalpaid
)
main ''
