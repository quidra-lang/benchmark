weights<-c(100,-20,10,5,5,10,-20,100,-20,-50,-2,-2,-2,-2,-50,-20,10,-2,-1,-1,-1,-1,-2,10,5,-2,-1,-1,-1,-1,-2,5,5,-2,-1,-1,-1,-1,-2,5,10,-2,-1,-1,-1,-1,-2,10,-20,-50,-2,-2,-2,-2,-50,-20,100,-20,10,5,5,10,-20,100)
transforms<-c('rot90','rot180','rot270','mirror','flip','diag','anti')
zero<-strsplit('NEW DUMP SHOW SCORE LEGAL HISTORY SHEET STATS EVAL STABLE SOLVE',' ')[[1]]
numeric_commands<-strsplit('UNDO REDO HINT PV AI ANALYZE RANDOM PERFT DIVIDE',' ')[[1]]
active<-strsplit('FLIPS MOVE PLAY HINT PV AI SOLVE AUTOPLAY RANDOM MC DIVIDE',' ')[[1]]
commands<-c(zero,numeric_commands,'LOAD','TRANSFORM','AUTOPLAY','MC','FLIPS','MOVE','PLAY','RECORD')
other<-function(s)if(s=='B')'W'else 'B'
square_name<-function(p)if(!length(p))character()else paste0(letters[p%%8+1],floor(p/8)+1)
square_index<-function(s)(as.numeric(substr(s,2,2))-1)*8+match(substr(s,1,1),letters)-1
inside<-function(r,c)r>=0&&r<8&&c>=0&&c<8
initial<-function(){b<-rep('.',64);b[c(28,37)]<-'W';b[c(29,36)]<-'B';b}
flips<-function(b,s,p){if(b[p+1]!='.')return(numeric());out<-numeric();row<-floor(p/8);col<-p%%8;for(dr in -1:1)for(dc in -1:1){if(dr==0&&dc==0)next;r<-row+dr;c<-col+dc;line<-numeric();while(inside(r,c)&&b[8*r+c+1]==other(s)){line<-c(line,8*r+c);r<-r+dr;c<-c+dc};if(length(line)&&inside(r,c)&&b[8*r+c+1]==s)out<-c(out,line)};sort(out)}
legal<-function(b,s)Filter(function(p)b[p+1]=='.'&&length(flips(b,s,p))>0,0:63)
place<-function(b,s,p){f<-flips(b,s,p);b[c(p,f)+1]<-s;b}
terminal<-function(b)!length(legal(b,'B'))&&!length(legal(b,'W'))
game_over<-function(b){x<-sum(b=='B');y<-sum(b=='W');paste('game over B',x,'W',y,if(x>y)'winner B'else if(x<y)'winner W'else 'draw')}
evaluate<-function(b,s){w<-sum(ifelse(b==s,weights,ifelse(b==other(s),-weights,0)));own<-length(legal(b,s));enemy<-length(legal(b,other(s)));c(w+10*(own-enemy),w,own,enemy)}
search_cache<-new.env(hash=TRUE,parent=emptyenv());perft_cache<-new.env(hash=TRUE,parent=emptyenv())
position_key<-function(b,s,d)paste0(paste0(b,collapse=''),s,':',d)
search<-function(b,s,d){key<-position_key(b,s,d);if(exists(key,search_cache,inherits=FALSE))return(search_cache[[key]]);ms<-legal(b,s);o<-other(s);if(!length(ms)&&!length(legal(b,o)))v<-(if(d<0)1 else 1000)*(sum(b==s)-sum(b==o))else if(d==0)v<-evaluate(b,s)[1]else if(!length(ms))v<--search(b,o,if(d<0)-1 else d-1)else v<-max(vapply(ms,function(p)-search(place(b,s,p),o,if(d<0)-1 else d-1),numeric(1)));if(length(search_cache)>300000)rm(list=ls(search_cache,all.names=TRUE),envir=search_cache);search_cache[[key]]<-v;v}
ranked<-function(b,s,d){ms<-legal(b,s);if(!length(ms))return(matrix(numeric(),nrow=0,ncol=2));v<-vapply(ms,function(p)-search(place(b,s,p),other(s),if(d<0)-1 else d-1),numeric(1));rows<-cbind(value=v,square=ms);rows[order(-v,ms),,drop=FALSE]}
variation<-function(b,s,d){steps<-character();while(d!=0&&!terminal(b)){ms<-ranked(b,s,d);if(nrow(ms)){p<-ms[1,2];steps<-c(steps,square_name(p));b<-place(b,s,p)}else steps<-c(steps,'pass');s<-other(s);if(d>0)d<-d-1};list(steps=steps,board=b)}
perft<-function(b,s,d){if(d==0)return(1);key<-position_key(b,s,d);if(exists(key,perft_cache,inherits=FALSE))return(perft_cache[[key]]);ms<-legal(b,s);o<-other(s);n<-if(length(ms))sum(vapply(ms,function(p)perft(place(b,s,p),o,d-1),numeric(1)))else if(length(legal(b,o)))perft(b,o,d-1)else 1;if(length(perft_cache)>200000)rm(list=ls(perft_cache,all.names=TRUE),envir=perft_cache);perft_cache[[key]]<-n;n}
stable<-function(b){stable<-rep(FALSE,64);axes<-list(c(0,1),c(1,0),c(1,1),c(1,-1));repeat{found<-numeric();for(p in 0:63){if(b[p+1]=='.'||stable[p+1])next;row<-floor(p/8);col<-p%%8;ok<-TRUE;for(axis in axes){dr<-axis[1];dc<-axis[2];full<-TRUE;anchor<-FALSE;for(sign in c(-1,1)){r<-row+dr*sign;c<-col+dc*sign;if(!inside(r,c)||(stable[8*r+c+1]&&b[8*r+c+1]==b[p+1]))anchor<-TRUE;while(inside(r,c)){if(b[8*r+c+1]=='.')full<-FALSE;r<-r+dr*sign;c<-c+dc*sign}};if(!full&&!anchor){ok<-FALSE;break}};if(ok)found<-c(found,p)};if(!length(found))break;stable[found+1]<-TRUE};c(sum(stable&b=='B'),sum(stable&b=='W'))}
transform_square<-function(p,op){r<-floor(p/8);c<-p%%8;switch(op,rot90=8*c+7-r,rot180=63-p,rot270=8*(7-c)+r,mirror=8*r+7-c,flip=8*(7-r)+c,diag=8*c+r,anti=8*(7-c)+7-r)}
transform_board<-function(b,op){a<-rep('.',64);for(p in 0:63)a[transform_square(p,op)+1]<-b[p+1];a}
new_random<-function(seed){rng<-new.env(parent=emptyenv());rng$value<-seed;rng}
draw<-function(rng){rng$value<-48271*rng$value%%2147483647;rng$value}
random_game<-function(b,s,rng){repeat{ms<-legal(b,s);if(length(ms))b<-place(b,s,ms[draw(rng)%%length(ms)+1])else if(!length(legal(b,other(s))))return(b);s<-other(s)}}
average<-function(f,n){v<-floor(100*f/n);sprintf('%.0f.%02.0f',floor(v/100),v%%100)}
emit<-function(...)cat(paste(...,collapse=' '),'\n',sep='')
new_engine<-function(){e<-new.env(parent=emptyenv());e$board<-initial();e$side<-'B';e$over<-FALSE;e$history<-list();e$redo<-list();e}
snapshot<-function(e)list(board=e$board,side=e$side,over=e$over)
restore<-function(e,p){e$board<-p$board;e$side<-p$side;e$over<-p$over}
status<-function(e)if(e$over)game_over(e$board)else paste(e$side,'to move')
reset<-function(e){restore(e,list(board=initial(),side='B',over=FALSE));e$history<-list();e$redo<-list()}
adjust<-function(e,quiet=FALSE){if(length(legal(e$board,e$side)))return(FALSE);if(length(legal(e$board,other(e$side)))){if(!quiet)emit(e$side,'passes');e$side<-other(e$side);return(TRUE)};e$over<-TRUE;if(!quiet)emit(game_over(e$board));FALSE}
move<-function(e,p,quiet=FALSE,value=NULL){before<-snapshot(e);s<-e$side;k<-length(flips(e$board,s,p));e$board<-place(e$board,s,p);if(!quiet){if(is.null(value))emit(s,square_name(p),'flips',k)else emit(s,square_name(p),'flips',k,'value',value)};e$side<-other(s);passed<-adjust(e,quiet);e$history[[length(e$history)+1]]<-list(side=s,square=p,count=k,passed=passed,before=before,after=snapshot(e));e$redo<-list();passed}
reason<-function(e,p)if(e$over)'game over'else if(e$board[p+1]!='.')'occupied'else if(!length(flips(e$board,e$side,p)))'no flips'else ''
record<-function(e,text){temp<-new_engine();ps<-vapply(seq(1,nchar(text),by=2),function(i)square_index(substr(text,i,i+1)),numeric(1));passes<-0;for(i in seq_along(ps)){p<-ps[i];why<-reason(temp,p);if(nchar(why)){emit('ILLEGAL move',i,square_name(p),why);return()};passes<-passes+move(temp,p,TRUE)};restore(e,snapshot(temp));e$history<-temp$history;e$redo<-list();op<-c(f5='',e6='diag',d3='anti',c4='rot180')[square_name(ps[1])];normal<-paste0(vapply(ps,function(p)square_name(if(op=='')p else transform_square(p,op)),character(1)),collapse='');emit('record',length(ps),'moves',passes,'passes');emit('normal',normal);emit(status(e))}
sheet<-function(e){fields<-if(length(e$history))e$history[[1]]$before$board else e$board;for(i in seq_along(e$history))fields[e$history[[i]]$square+1]<-as.character(i);emit(paste0(' ',paste0(sprintf('%3s',letters[1:8]),collapse='')));for(r in 0:7)emit(paste0(r+1,paste0(sprintf('%3s',fields[8*r+1:8]),collapse='')))}
stats<-function(e){all<-e$history;total<-sum(vapply(all,`[[`,numeric(1),'count'));if(!length(all))emit('moves 0')else emit('moves',length(all),'flips',total,'avg',average(total,length(all)),'passes',sum(vapply(all,`[[`,logical(1),'passed')));for(s in c('B','W')){rows<-Filter(function(r)r$side==s,all);if(!length(rows)){emit(s,'moves 0');next};counts<-vapply(rows,`[[`,numeric(1),'count');sum<-sum(counts);maximum<-max(counts);first<-rows[[which(counts==maximum)[1]]];corners<-sum(vapply(rows,function(r)r$square%in%c(0,7,56,63),logical(1)));emit(s,'moves',length(rows),'flips',sum,'avg',average(sum,length(rows)),'max',maximum,square_name(first$square),'corners',corners)}}
autoplay<-function(e,black,white,seed=0){rng<-new_random(seed);ps<-character();passes<-0;while(!e$over){ms<-legal(e$board,e$side);p<-if(seed!=0)ms[draw(rng)%%length(ms)+1]else ranked(e$board,e$side,if(e$side=='B')black else white)[1,2];ps<-c(ps,square_name(p));passes<-passes+move(e,p,TRUE)};emit(if(seed!=0)'random'else 'autoplay',length(ps),'moves',passes,'passes');emit('moves',paste0(ps,collapse=''));emit(game_over(e$board))}
monte_carlo<-function(e,k,seed){rng<-new_random(seed);best<--1;bp<--1;for(p in legal(e$board,e$side)){w<-d<-l<-0;start<-place(e$board,e$side,p);for(i in seq_len(k)){b<-random_game(start,other(e$side),rng);diff<-sum(b==e$side)-sum(b==other(e$side));if(diff>0)w<-w+1 else if(diff<0)l<-l+1 else d<-d+1};emit(square_name(p),w,d,l);if(2*w+d>best){best<-2*w+d;bp<-p}};emit('best',square_name(bp),best)}
execute<-function(e,text){a<-strsplit(text,' ',fixed=TRUE)[[1]];cmd<-a[1];a<-a[-1];error<-''
  if(!cmd%in%commands)error<-'unknown command'
  else if(cmd=='LOAD'){if(length(a)!=2||!grepl('^[.BW]{64}$',a[1])||!a[2]%in%c('B','W'))error<-'bad board'}
  else if(cmd%in%c('MOVE','FLIPS')){error<-if(length(a)!=1)'bad arguments'else if(!grepl('^[a-h][1-8]$',a[1]))'bad square'else ''}
  else if(cmd%in%c('PLAY','RECORD')){error<-if(length(a)!=1)'bad arguments'else if(nchar(a[1])>120||!grepl('^([a-h][1-8])+$',a[1]))'bad record'else ''}
  else if(cmd%in%zero){if(length(a))error<-'bad arguments'}
  else if(cmd=='TRANSFORM'){if(length(a)!=1||!a[1]%in%transforms)error<-'bad arguments'}
  else{expected<-if(cmd%in%c('AUTOPLAY','MC'))2 else 1;valid<-length(a)==expected&&all(grepl('^[0-9]+$',a));if(valid){ns<-as.numeric(a);n<-ns[1];valid<-switch(cmd,AUTOPLAY=all(ns>=1&ns<=4),HINT=n>=1&&n<=4,PV=n>=1&&n<=4,AI=n>=1&&n<=4,ANALYZE=n>=1&&n<=4,PERFT=n>=1&&n<=8,DIVIDE=n>=1&&n<=8,MC=n>=1&&n<=100&&ns[2]>=1&&ns[2]<=2147483646,RANDOM=n>=1&&n<=2147483646,n>=1)};if(!valid)error<-'bad arguments'}
  if(nchar(error)){emit('ERROR',error);return()};if(e$over&&cmd%in%active){emit('ERROR game over');return()};n<-if(length(a)&&grepl('^[0-9]+$',a[1]))as.numeric(a[1])else 0
  if(cmd=='NEW'){reset(e);emit('OK')}
  else if(cmd=='LOAD'){restore(e,list(board=strsplit(a[1],'',fixed=TRUE)[[1]],side=a[2],over=FALSE));e$history<-list();e$redo<-list();emit('OK');adjust(e)}
  else if(cmd=='DUMP')emit('board',paste0(e$board,collapse=''),e$side)
  else if(cmd=='SHOW'){emit('  a b c d e f g h');ms<-if(e$over)numeric()else legal(e$board,e$side);for(r in 0:7){row<-ifelse((8*r+0:7)%in%ms,'*',e$board[8*r+1:8]);emit(r+1,paste(row,collapse=' '))};emit(status(e))}
  else if(cmd=='SCORE')emit('score B',sum(e$board=='B'),'W',sum(e$board=='W'),'empty',sum(e$board=='.'))
  else if(cmd=='LEGAL'){ms<-if(e$over)numeric()else legal(e$board,e$side);out<-c('legal',length(ms),square_name(ms));emit(paste(out,collapse=' '))}
  else if(cmd%in%c('MOVE','FLIPS')){p<-square_index(a[1]);why<-reason(e,p);if(nchar(why))emit('ILLEGAL',why)else if(cmd=='MOVE')move(e,p)else{f<-flips(e$board,e$side,p);emit(paste(c('flips',a[1],length(f),square_name(f)),collapse=' '))}}
  else if(cmd=='PLAY'){for(i in seq(1,nchar(a[1]),by=2)){p<-square_index(substr(a[1],i,i+1));why<-reason(e,p);if(nchar(why)){emit('ILLEGAL move',(i+1)/2,square_name(p),why);break};move(e,p)}}
  else if(cmd=='RECORD')record(e,a[1])
  else if(cmd=='UNDO'){if(n>length(e$history))emit('ERROR cannot undo')else{start<-length(e$history)-n+1;removed<-e$history[seq(start,length(e$history))];restore(e,removed[[1]]$before);e$history<-if(start==1)list()else e$history[seq_len(start-1)];e$redo<-c(removed,e$redo);emit(status(e))}}
  else if(cmd=='REDO'){if(n>length(e$redo))emit('ERROR cannot redo')else{added<-e$redo[seq_len(n)];e$redo<-if(n==length(e$redo))list()else e$redo[seq(n+1,length(e$redo))];e$history<-c(e$history,added);restore(e,added[[n]]$after);emit(status(e))}}
  else if(cmd=='HISTORY'){emit('history',length(e$history));for(i in seq_along(e$history)){r<-e$history[[i]];out<-c(i,r$side,square_name(r$square),r$count,if(r$passed)'pass');emit(paste(out,collapse=' '))}}
  else if(cmd=='SHEET')sheet(e)
  else if(cmd=='STATS')stats(e)
  else if(cmd=='TRANSFORM'){op<-a[1];e$board<-transform_board(e$board,op);tr<-function(r){r$square<-transform_square(r$square,op);r$before$board<-transform_board(r$before$board,op);r$after$board<-transform_board(r$after$board,op);r};e$history<-lapply(e$history,tr);e$redo<-lapply(e$redo,tr);emit('OK')}
  else if(cmd=='EVAL'){v<-evaluate(e$board,e$side);emit('eval',v[1],'weights',v[2],'mobility',v[3],v[4])}
  else if(cmd=='STABLE'){v<-stable(e$board);emit('stable B',v[1],'W',v[2])}
  else if(cmd=='HINT'){rows<-ranked(e$board,e$side,n);for(i in seq_len(nrow(rows)))emit(square_name(rows[i,2]),rows[i,1])}
  else if(cmd=='PV'){pv<-variation(e$board,e$side,n);emit(paste(c('pv',search(e$board,e$side,n),pv$steps),collapse=' '))}
  else if(cmd=='AI'){row<-ranked(e$board,e$side,n)[1,];move(e,row[2],FALSE,row[1])}
  else if(cmd=='ANALYZE'){loss<-c(B=0,W=0);for(i in seq_along(e$history)){r<-e$history[[i]];rows<-ranked(r$before$board,r$side,n);best<-rows[1,1];bp<-rows[1,2];v<-rows[rows[,2]==r$square,1];loss[r$side]<-loss[r$side]+best-v;emit(i,r$side,square_name(r$square),v,'best',square_name(bp),best)};emit('loss B',loss['B'],'W',loss['W'])}
  else if(cmd=='SOLVE'){if(sum(e$board=='.')>=9)emit('ERROR too many empties')else{rows<-ranked(e$board,e$side,-1);for(i in seq_len(nrow(rows)))emit(square_name(rows[i,2]),rows[i,1]);pv<-variation(e$board,e$side,-1);emit(paste(c('line',pv$steps),collapse=' '));emit('final B',sum(pv$board=='B'),'W',sum(pv$board=='W'))}}
  else if(cmd=='AUTOPLAY')autoplay(e,n,as.numeric(a[2]))
  else if(cmd=='RANDOM')autoplay(e,0,0,n)
  else if(cmd=='MC')monte_carlo(e,n,as.numeric(a[2]))
  else if(cmd=='PERFT')emit('perft',n,perft(e$board,e$side,n))
  else if(cmd=='DIVIDE'){total<-0;for(p in legal(e$board,e$side)){v<-perft(place(e$board,e$side,p),other(e$side),n-1);emit(square_name(p),v);total<-total+v};emit('total',total)}
}
input<-readLines(file('stdin'),warn=FALSE);e<-new_engine();for(line in input[seq_len(as.numeric(input[1]))+1])execute(e,line)
