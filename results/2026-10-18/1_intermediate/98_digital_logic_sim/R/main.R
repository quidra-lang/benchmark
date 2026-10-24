TYPES<-c('AND','OR','NAND','NOR','XOR','XNOR','NOT','BUF','MUX2','DFF')
COUNTS<-c(BUILD=1,RESET=0,SET=3,APPLY=2,PULSE=3,CLOCK=4,RUN=1,WATCH=1,UNWATCH=1,SHOW=0,CHECK=2,PROBE=1,WAVE=2,HISTORY=1,ACTIVITY=1,STATUS=0,MODULES=0,NETLIST=1,HIERARCHY=1,STATS=1,TRUTHTABLE=1,EQUIV=2,FAULTS=1,CRITICAL=1,PERIOD=1)
SIM<-strsplit('RESET SET APPLY PULSE CLOCK RUN WATCH UNWATCH SHOW CHECK PROBE WAVE HISTORY ACTIVITY STATUS',' ',fixed=TRUE)[[1]]
num<-function(n)format(n,scientific=FALSE,trim=TRUE)
emit<-function(s)cat(s,'\n',sep='')
fail<-function(s)stop(s,call.=FALSE)
name_ok<-function(s)nchar(s)<=16&&grepl('^[a-z][a-z0-9_]*$',s)
number_ok<-function(s)nchar(s)<=9&&grepl('^(0|[1-9][0-9]*)$',s)
number<-function(s,positive=FALSE){if(!number_ok(s)||(positive&&s=='0'))fail(paste('bad number',s));as.numeric(s)}
value<-function(s){if(!(s %in% c('0','1','X')))fail(paste('bad value',s));s}
bits<-function(r,n)paste0(vapply(seq_len(n),function(i)as.character(bitwAnd(bitwShiftR(r,n-i),1)),character(1)),collapse='')
logic<-function(k,a){
  y<-if(k %in% c('AND','NAND'))if('0' %in% a)'0' else if('X' %in% a)'X' else '1' else if(k %in% c('OR','NOR'))if('1' %in% a)'1' else if('X' %in% a)'X' else '0' else if(k %in% c('XOR','XNOR'))if('X' %in% a)'X' else as.character(sum(a=='1')%%2) else if(k=='MUX2')if(a[1]=='X')if(a[2]==a[3])a[2] else 'X' else a[if(a[1]=='0')2 else 3] else a[1]
  if(k %in% c('NAND','NOR','XNOR','NOT'))switch(y,'0'='1','1'='0','X'='X') else y
}
circuit<-function(m){
  gates<-list()
  expand<-function(m,prefix,ports){
    actual<-function(s)if(s %in% names(ports))ports[[s]] else paste0(prefix,s)
    for(x in m$body)if(!is.null(x$kind)){g<-x;g$name<-paste0(prefix,g$name);g$inputs<-vapply(g$inputs,actual,character(1));g$output<-actual(g$output);gates[[length(gates)+1]]<<-g}else{mapping<-vapply(x$connections,function(v)actual(v$signal),character(1));names(mapping)<-vapply(x$connections,function(v)v$port,character(1));expand(x$module,paste0(prefix,x$name,'.'),mapping)}
  }
  expand(m,'',character());signals<-c(m$inputs,vapply(gates,function(g)g$output,character(1)));driver<-setNames(seq_along(gates),vapply(gates,function(g)g$output,character(1)));readers<-setNames(rep(list(integer()),length(signals)),signals)
  flops<-which(vapply(gates,function(g)g$kind=='DFF',logical(1)))
  for(i in seq_along(gates))for(s in unique(gates[[i]]$inputs))readers[[s]]<-c(readers[[s]],i)
  waiting<-integer(length(gates));ready<-integer();needed<-0
  for(i in seq_along(gates))if(gates[[i]]$kind!='DFF'){needed<-needed+1;for(s in unique(gates[[i]]$inputs))if(s %in% names(driver)&&gates[[driver[[s]]]]$kind!='DFF')waiting[i]<-waiting[i]+1;if(waiting[i]==0)ready<-c(ready,i)}
  order<-integer();while(length(ready)){i<-tail(ready,1);ready<-head(ready,-1);order<-c(order,i);for(r in readers[[gates[[i]]$output]])if(gates[[r]]$kind!='DFF'){waiting[r]<-waiting[r]-1;if(waiting[r]==0)ready<-c(ready,r)}}
  list(name=m$name,inputs=m$inputs,outputs=m$outputs,gates=gates,signals=signals,driver=driver,readers=readers,flops=flops,order=order,loop=length(order)!=needed)
}
combinational<-function(c){if(length(c$flops))fail(paste(c$name,'is not combinational'));if(c$loop)fail(paste(c$name,'has a combinational loop'));if(length(c$inputs)>8)fail(paste('too many inputs',length(c$inputs)))}
evaluate<-function(c,b,stuck='',v='X'){
  values<-setNames(strsplit(b,'')[[1]],c$inputs);if(stuck %in% c$inputs)values[[stuck]]<-v
  for(i in c$order){g<-c$gates[[i]];values[[g$output]]<-if(g$output==stuck)v else logic(g$kind,unname(values[g$inputs]))}
  paste0(values[c$outputs],collapse='')
}
arrivals<-function(c,period){
  late<-early<-numeric();prev<-character()
  if(period)for(i in c$flops){g<-c$gates[[i]];late[[g$output]]<-early[[g$output]]<-g$delay}else for(s in c$inputs)late[[s]]<-early[[s]]<-0
  for(i in c$order){g<-c$gates[[i]];a<-g$inputs[g$inputs %in% names(late)];if(!length(a))next;best<-a[which.max(late[a])];late[[g$output]]<-late[[best]]+g$delay;early[[g$output]]<-min(early[a])+g$delay;prev[[g$output]]<-best}
  list(late=late,early=early,previous=prev)
}
reset<-function(s){s$values<-setNames(rep('X',length(s$c$signals)),s$c$signals);s$history<-setNames(rep(list(list()),length(s$c$signals)),s$c$signals);s$time<-0;s$sequence<-0;s$processed<-0;s$queue<-list();s$halted<-FALSE}
new_simulation<-function(c){s<-new.env(parent=emptyenv());s$c<-c;s$watch<-character();reset(s);s}
before<-function(a,b)a$time<b$time||(a$time==b$time&&a$id<b$id)
schedule<-function(s,t,x,v){
  e<-list(time=t,id=s$sequence,signal=x,value=v);s$sequence<-s$sequence+1;i<-length(s$queue)+1
  while(i>1){p<-i%/%2;if(!before(e,s$queue[[p]]))break;s$queue[[i]]<-s$queue[[p]];i<-p};s$queue[[i]]<-e
}
pop_event<-function(s){
  result<-s$queue[[1]];last<-s$queue[[length(s$queue)]];s$queue<-head(s$queue,-1)
  if(length(s$queue)){i<-1;while(2*i<=length(s$queue)){j<-2*i;if(j+1<=length(s$queue)&&before(s$queue[[j+1]],s$queue[[j]]))j<-j+1;if(!before(s$queue[[j]],last))break;s$queue[[i]]<-s$queue[[j]];i<-j};s$queue[[i]]<-last};result
}
describe<-function(s,a){if(!length(a))return(character());paste0(a,'=',s$values[a])}
run<-function(s,end){
  total<-0;glitches<-0
  while(length(s$queue)&&s$queue[[1]]$time<end){t<-s$queue[[1]]$time;start<-s$values;changed<-setNames(rep(FALSE,length(start)),names(start));count<-0
    while(length(s$queue)&&s$queue[[1]]$time==t){
      if(count==1000){emit(paste('halted: oscillation at time',num(t)));s$queue<-list();s$time<-t;s$halted<-TRUE;return(invisible(NULL))}
      e<-pop_event(s);count<-count+1;s$processed<-s$processed+1;old<-s$values[[e$signal]];if(old==e$value)next;changed[[e$signal]]<-TRUE;s$values[[e$signal]]<-e$value
      for(i in s$c$readers[[e$signal]]){g<-s$c$gates[[i]];if(g$kind!='DFF')schedule(s,t+g$delay,g$output,logic(g$kind,unname(s$values[g$inputs])))else if(e$signal==g$inputs[1]&&old=='0'&&e$value=='1')schedule(s,t+g$delay,g$output,s$values[[g$inputs[2]]])}
    }
    total<-total+count
    for(x in names(start)[changed])if(s$values[[x]]==start[[x]])glitches<-glitches+1 else s$history[[x]][[length(s$history[[x]])+1]]<-list(time=t,value=s$values[[x]])
    for(x in s$watch)if(s$values[[x]]!=start[[x]])emit(paste(num(t),x,s$values[[x]]))
  }
  s$time<-end;emit(paste('run',num(end),'events',num(total),'glitches',num(glitches),'pending',num(length(s$queue))))
}
new_simulator<-function(){s<-new.env(parent=emptyenv());s$modules<-list();s$simulation<-NULL;s}
lookup<-function(s,name){if(!(name %in% names(s$modules)))fail(paste('unknown module',name));s$modules[[name]]}
require_signal<-function(s,x){if(!(x %in% names(s$simulation$values)))fail(paste('unknown signal',x))}
require_input<-function(s,x){if(!(x %in% s$simulation$c$inputs))fail(paste('not an input',x))}
parse_time<-function(s,w){t<-number(w);if(t<s$simulation$time)fail(paste('time',num(t),'is in the past'));t}
define<-function(s,header,lines){
  line<-header
  tryCatch({
    w<-strsplit(lines[1],' ',fixed=TRUE)[[1]];if(length(w)<5||w[3]!='IN'||sum(w[-(1:3)]=='OUT')!=1||tail(w,1)=='OUT')fail('bad module header')
    name<-w[2];if(nchar(name)>16||!grepl('^[A-Z][A-Z0-9_]*$',name))fail(paste('bad module name',name));if(name %in% names(s$modules))fail(paste('duplicate module',name))
    split<-which(w=='OUT'&seq_along(w)>3);ins<-if(split>4)w[4:(split-1)] else character();outs<-w[(split+1):length(w)];seen<-character()
    for(p in c(ins,outs)){if(!name_ok(p))fail(paste('bad name',p));if(p %in% seen)fail(paste('duplicate port',p));seen<-c(seen,p)}
    driven<-ins;used<-character();body<-reads<-list();gates<-0
    for(i in seq_len(length(lines)-1)){line<-header+i;a<-strsplit(lines[i+1],' ',fixed=TRUE)[[1]];kind<-a[1]
      if(kind %in% TYPES){
        if(length(a)<5||a[length(a)-2]!='->'||sum(a=='->')!=1)fail('bad gate syntax');n<-a[2];if(!name_ok(n))fail(paste('bad name',n));inputs<-if(length(a)>5)a[3:(length(a)-3)] else character();output<-a[length(a)-1];delay<-tail(a,1);lo<-if(kind %in% c('NOT','BUF'))1 else if(kind=='MUX2')3 else 2;hi<-if(match(kind,TYPES)<=6)8 else lo
        if(length(inputs)<lo||length(inputs)>hi)fail(paste('bad input count',length(inputs),'for',kind));for(x in c(inputs,output))if(!name_ok(x))fail(paste('bad name',x))
        if(!number_ok(delay)||as.numeric(delay)>1000)fail(paste('bad delay',delay));if(n %in% used)fail(paste('duplicate name',n));if(output %in% driven)fail(paste('multiple drivers for',output))
        used<-c(used,n);driven<-c(driven,output);body[[length(body)+1]]<-list(name=n,kind=kind,inputs=inputs,output=output,delay=as.numeric(delay));gates<-gates+1;for(x in inputs)reads[[length(reads)+1]]<-list(line=line,signal=x)
      }else if(kind=='INST'){
        if(length(a)<3)fail('bad instance syntax');n<-a[2];if(!name_ok(n))fail(paste('bad name',n));m<-lookup(s,a[3]);connections<-list();ports<-character()
        for(word in a[-(1:3)]){p<-regmatches(word,regexec('^([^=]+)=([^=]+)$',word))[[1]];if(!length(p))fail(paste('bad connection',word));port<-p[2];x<-p[3];if(!(port %in% c(m$inputs,m$outputs)))fail(paste('unknown port',port));if(port %in% ports)fail(paste('duplicate connection',port));if(!name_ok(x))fail(paste('bad name',x));ports<-c(ports,port);connections[[length(connections)+1]]<-list(port=port,signal=x)}
        for(p in m$inputs)if(!(p %in% ports))fail(paste('unconnected input',p));if(n %in% used)fail(paste('duplicate name',n));for(v in connections)if(v$port %in% m$outputs){if(v$signal %in% driven)fail(paste('multiple drivers for',v$signal));driven<-c(driven,v$signal)}
        used<-c(used,n);body[[length(body)+1]]<-list(name=n,module=m,connections=connections);for(v in connections)if(v$port %in% m$inputs)reads[[length(reads)+1]]<-list(line=line,signal=v$signal)
      }else fail(paste('unknown statement',kind))
    }
    for(x in outs)reads[[length(reads)+1]]<-list(line=header,signal=x)
    for(r in reads)if(!(r$signal %in% driven)){line<-r$line;fail(paste('undriven signal',r$signal))}
    s$modules[[name]]<-list(name=name,inputs=ins,outputs=outs,body=body);emit(paste('defined',name,'inputs',length(ins),'outputs',length(outs),'gates',gates,'instances',length(body)-gates))
  },error=function(e)emit(paste0('error: line ',line,': ',conditionMessage(e))))
}
hierarchy<-function(m,depth){for(x in m$body)if(is.null(x$kind)){emit(paste0(strrep('  ',depth),x$name,' ',x$module$name));hierarchy(x$module,depth+1)}}
execute<-function(s,line,w){tryCatch({
  cmd<-w[1];a<-w[-1];if(!(cmd %in% names(COUNTS)))fail(paste('unknown command',cmd));n<-COUNTS[[cmd]]
  if(length(a)<n||(!(cmd %in% c('WATCH','UNWATCH','SHOW'))&&length(a)!=n))fail('wrong argument count')
  if(cmd %in% SIM&&is.null(s$simulation))fail('no circuit');sim<-s$simulation
  if(cmd %in% c('SET','APPLY','PULSE','CLOCK','RUN')&&sim$halted)fail('simulation halted')
  if(cmd=='MODULES'){emit(paste('modules',length(s$modules)));for(m in s$modules)emit(paste(m$name,'inputs',length(m$inputs),'outputs',length(m$outputs),'gates',length(circuit(m)$gates)));return(invisible(NULL))}
  if(cmd %in% c('BUILD','NETLIST','HIERARCHY','STATS','TRUTHTABLE','EQUIV','FAULTS','CRITICAL','PERIOD')){
    m<-lookup(s,a[1]);if(cmd=='EQUIV')m2<-lookup(s,a[2]);c<-circuit(m)
    if(cmd=='BUILD'){s$simulation<-new_simulation(c);emit(paste('built',c$name,'signals',length(c$signals),'gates',length(c$gates)))}
    else if(cmd=='NETLIST'){emit(paste('netlist',c$name,'gates',length(c$gates),'signals',length(c$signals)));for(g in c$gates)emit(paste(c(g$name,g$kind,g$inputs,'->',g$output,g$delay),collapse=' '))}
    else if(cmd=='HIERARCHY'){emit(c$name);hierarchy(m,1)}
    else if(cmd=='STATS'){
      levels<-setNames(rep(0,length(c$signals)),c$signals);depth<-0;for(i in c$order){g<-c$gates[[i]];levels[[g$output]]<-max(levels[g$inputs])+1;depth<-max(depth,levels[[g$output]])};emit(paste('stats',c$name,'gates',length(c$gates),'signals',length(c$signals),'depth',if(c$loop)'-' else depth))
      row<-'types';for(t in TYPES){n<-sum(vapply(c$gates,function(g)g$kind==t,logical(1)));if(n)row<-c(row,t,n)};emit(paste(row,collapse=' '));fanout<-vapply(c$readers,length,integer(1));best<-c$signals[which.max(fanout[c$signals])];emit(paste('max fanout',best,fanout[[best]]))
    }else if(cmd %in% c('CRITICAL','PERIOD')){
      period<-cmd=='PERIOD';if(period&&!length(c$flops))fail(paste(c$name,'has no flip-flops'));if(c$loop)fail(paste(c$name,'has a combinational loop'));arr<-arrivals(c,period);ends<-if(period)vapply(c$flops,function(i)c$gates[[i]]$inputs[2],character(1)) else c$outputs;heading<-if(period)paste('flip-flops',length(c$flops),'period') else 'critical';best<-NULL
      for(x in ends){if(!period)emit(if(x %in% names(arr$late))paste(x,'min',num(arr$early[[x]]),'max',num(arr$late[[x]])) else paste(x,'unreachable'));if(x %in% names(arr$late)&&(is.null(best)||arr$late[[x]]>arr$late[[best]]))best<-x}
      if(is.null(best))emit(paste(heading,'none'))else{path<-best;x<-best;while(x %in% names(arr$previous)){x<-arr$previous[[x]];path<-c(x,path)};emit(paste0(heading,' ',num(arr$late[[best]]),': ',paste(path,collapse=' -> ')))}
    }else{
      combinational(c);rows<-vapply(0:(2^length(c$inputs)-1),function(r)bits(r,length(c$inputs)),character(1));expected<-vapply(rows,function(b)evaluate(c,b),character(1))
      if(cmd=='TRUTHTABLE'){emit(paste(c(c$inputs,'|',c$outputs),collapse=' '));for(r in seq_along(rows))emit(paste(c(strsplit(rows[r],'')[[1]],'|',strsplit(expected[r],'')[[1]]),collapse=' '))}
      else if(cmd=='EQUIV'){d<-circuit(m2);combinational(d);if(length(c$inputs)!=length(d$inputs)||length(c$outputs)!=length(d$outputs))fail('port mismatch');different<-FALSE;for(r in seq_along(rows)){v<-evaluate(d,rows[r]);if(v!=expected[r]){emit(paste0('not equivalent at ',rows[r],': ',expected[r],' vs ',v));different<-TRUE;break}};if(!different)emit('equivalent')}
      else{undetected<-character();tests<-integer();for(x in c$signals)for(v in c('0','1')){found<-0;for(r in seq_along(rows))if(evaluate(c,rows[r],x,v)!=expected[r]){found<-r;break};if(found)tests<-c(tests,found)else undetected<-c(undetected,paste0(x,'/',v))};total<-2*length(c$signals);emit(paste('faults',total,'detected',total-length(undetected)));for(f in undetected)emit(paste('undetected',f));emit(paste(c('tests',rows[sort(unique(tests))]),collapse=' '))}
    };return(invisible(NULL))
  }
  if(cmd=='RESET'){reset(sim);emit('reset')}
  else if(cmd=='SET'){t<-parse_time(s,a[1]);require_input(s,a[2]);v<-value(a[3]);schedule(sim,t,a[2],v);emit(paste('set',a[2],v,'at',num(t)))}
  else if(cmd=='APPLY'){t<-parse_time(s,a[1]);b<-a[2];if(nchar(b)!=length(sim$c$inputs)||grepl('[^01X]',b))fail(paste('bad vector',b));chars<-strsplit(b,'')[[1]];for(i in seq_along(chars))schedule(sim,t,sim$c$inputs[i],chars[i]);emit(paste('apply',b,'at',num(t)))}
  else if(cmd %in% c('PULSE','CLOCK')){require_input(s,a[1]);t<-parse_time(s,a[2]);width<-number(a[3],TRUE);if(cmd=='PULSE'){schedule(sim,t,a[1],'1');schedule(sim,t+width,a[1],'0');emit(paste('pulse',a[1],num(t),num(t+width)))}else{count<-number(a[4],TRUE);for(i in 0:(count-1))schedule(sim,t+i*width,a[1],as.character(i%%2));emit(paste('clock',a[1],'events',num(count),'last',num(t+(count-1)*width)))}}
  else if(cmd=='RUN'){t<-number(a[1]);if(t<=sim$time)fail(paste('time',num(t),'is not after',num(sim$time)));run(sim,t)}
  else if(cmd %in% c('WATCH','UNWATCH')){seen<-character();for(x in a){require_signal(s,x);watched<-x %in% sim$watch;if(if(cmd=='WATCH')watched||x %in% seen else !watched||x %in% seen)fail(paste(if(cmd=='WATCH')'already watched' else 'not watched',x));seen<-c(seen,x)};sim$watch<-if(cmd=='WATCH')c(sim$watch,a) else sim$watch[!(sim$watch %in% a)];emit(paste('watching',if(length(sim$watch))paste(sim$watch,collapse=' ') else 'nothing'))}
  else if(cmd=='SHOW'){for(x in a)require_signal(s,x);emit(paste(if(length(a))describe(sim,a) else c(describe(sim,sim$c$inputs),'|',describe(sim,sim$c$outputs)),collapse=' '))}
  else if(cmd=='CHECK'){require_signal(s,a[1]);v<-value(a[2]);emit(paste0('check ',a[1],'=',v,' ',if(sim$values[[a[1]]]==v)'ok' else paste0('failed (',sim$values[[a[1]]],')')))}
  else if(cmd=='PROBE'){x<-a[1];require_signal(s,x);text<-'input';if(x %in% names(sim$c$driver)){g<-sim$c$gates[[sim$c$driver[[x]]]];text<-paste(c(g$name,g$kind,describe(sim,g$inputs),'delay',g$delay),collapse=' ')};emit(paste0(x,'=',sim$values[[x]],' driven by ',text));r<-sim$c$readers[[x]];emit(paste(c('fanout',length(r),vapply(r,function(i)sim$c$gates[[i]]$name,character(1))),collapse=' '))}
  else if(cmd=='WAVE'){first<-number(a[1]);last<-number(a[2]);if(!(first<last&&last<=sim$time))fail(paste('bad range',num(first),num(last)));if(!length(sim$watch))fail('nothing watched');for(x in sim$watch){h<-sim$history[[x]];i<-1;v<-'X';wave<-character();for(t in first:(last-1)){while(i<=length(h)&&h[[i]]$time<=t){v<-h[[i]]$value;i<-i+1};wave<-c(wave,v)};emit(paste(x,paste0(wave,collapse='')))}}
  else if(cmd=='HISTORY'){x<-a[1];require_signal(s,x);h<-sim$history[[x]];emit(paste(c('history',x,'changes',length(h),vapply(h,function(v)paste0(num(v$time),':',v$value),character(1))),collapse=' '))}
  else if(cmd=='ACTIVITY'){k<-number(a[1],TRUE);ranked<-sim$c$signals;ranked<-ranked[order(-vapply(sim$history[ranked],length,integer(1)),ranked,method='radix')];for(x in head(ranked,k))emit(paste(x,length(sim$history[[x]])))}
  else if(cmd=='STATUS'){emit(paste('circuit',sim$c$name,'time',num(sim$time),'pending',num(length(sim$queue)),'events',num(sim$processed),'halted',if(sim$halted)'yes' else 'no'));emit(paste0('values 0:',sum(sim$values=='0'),' 1:',sum(sim$values=='1'),' X:',sum(sim$values=='X')))}
},error=function(e)emit(paste0('error: line ',line,': ',conditionMessage(e))))}
lines<-readLines(file('stdin'),warn=FALSE);simulator<-new_simulator();i<-1
while(i<=length(lines)&&lines[i]!='END'){w<-strsplit(lines[i],' ',fixed=TRUE)[[1]];if(w[1]=='MODULE'){end<-i+1;while(lines[end]!='ENDMODULE')end<-end+1;define(simulator,i,lines[i:(end-1)]);i<-end+1}else{execute(simulator,i,w);i<-i+1}}
