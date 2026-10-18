main =: 3 : 0
  state =. 42
  arrival =. 0
  free =. 0 0
  totalwait =. maxwait =. 0
  for_customer. >:i.20 do.
    state =. 2147483647|48271*state
    arrival =. arrival+1+5|state
    state =. 2147483647|48271*state
    service =. 2+7|state
    teller =. 0
    if. (1{free)<0{free do. teller =. 1 end.
    start =. arrival>.teller{free
    end =. start+service
    wait =. start-arrival
    free =. end teller}free
    totalwait =. totalwait+wait
    maxwait =. maxwait>.wait
    smoutput 'customer ',(":customer),': arrive=',(":arrival),' start=',(":start),' end=',(":end),' teller=',(":>:teller),' wait=',":wait
  end.
  smoutput 'average wait: ',, '2' 8!:2 totalwait%20
  smoutput 'max wait: ',":maxwait
  smoutput 'last departure: ',":>./free
)
main ''
