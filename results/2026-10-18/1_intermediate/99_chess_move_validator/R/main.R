FILES <- strsplit('abcdefgh','')[[1]]
RANKS <- strsplit('12345678','')[[1]]
INITIAL <- 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'
ROOK <- rbind(c(0,1),c(0,-1),c(-1,0),c(1,0))
BISHOP <- rbind(c(1,1),c(-1,1),c(1,-1),c(-1,-1))
KING <- rbind(ROOK,BISHOP)
KNIGHT <- rbind(c(1,2),c(2,1),c(2,-1),c(1,-2),c(-1,-2),c(-2,-1),c(-2,1),c(-1,2))
RULES <- list(K=list(4,7,6,5,c(5,6)),Q=list(4,0,2,3,c(1,2,3)),k=list(60,63,62,61,c(61,62)),q=list(60,56,58,59,c(57,58,59)))
emit <- function(s) cat(s,'\n',sep='')
fail <- function(s) stop(s,call.=FALSE)
color <- function(p) if(p==toupper(p)) 'w' else 'b'
opposite <- function(c) if(c=='w') 'b' else 'w'
colored <- function(p,c) if(c=='w') p else tolower(p)
step <- function(c) if(c=='w') 8 else -8
square <- function(s) if(grepl('^[a-h][1-8]$',s)) match(substr(s,1,1),FILES)-1+8*(match(substr(s,2,2),RANKS)-1) else -1
sq_name <- function(s) paste0(FILES[s%%8+1],RANKS[s%/%8+1])
number <- function(s,lo,hi) {if(!grepl('^(0|[1-9][0-9]*)$',s)) return(-1);n<-as.numeric(s);if(n>=lo&&n<=hi)n else -1}
shift <- function(s,dx,dy) {x<-s%%8+dx;y<-s%/%8+dy;if(x>=0&&x<8&&y>=0&&y<8)8*y+x else -1}
targets <- function(b,s) {
  p<-b[s+1];kind<-toupper(p);a<-integer()
  if(kind %in% c('P','N','K')) {
    dirs<-if(kind=='P')rbind(c(-1,if(color(p)=='w')1 else -1),c(1,if(color(p)=='w')1 else -1)) else if(kind=='N')KNIGHT else KING
    for(i in seq_len(nrow(dirs))) {t<-shift(s,dirs[i,1],dirs[i,2]);if(t>=0)a<-c(a,t)}
  } else {
    dirs<-if(kind=='Q')KING else if(kind=='R')ROOK else BISHOP
    for(i in seq_len(nrow(dirs))) {t<-shift(s,dirs[i,1],dirs[i,2]);while(t>=0) {a<-c(a,t);if(b[t+1]!='.')break;t<-shift(t,dirs[i,1],dirs[i,2])}}
  }
  a
}
attackers <- function(b,t,c) {a<-integer();for(s in 0:63)if(b[s+1]!='.'&&color(b[s+1])==c&&t %in% targets(b,s))a<-c(a,s);a}
position <- function(b,side,rights,ep,half,full) list(board=b,side=side,rights=rights,ep=ep,half=half,full=full)
in_check <- function(p,c=p$side) length(attackers(p$board,match(colored('K',c),p$board)-1,opposite(c)))>0
is_castle <- function(p,m) toupper(p$board[m$s+1])=='K'&&abs(m$t-m$s)==2
is_ep <- function(p,m) toupper(p$board[m$s+1])=='P'&&m$s%%8!=m$t%%8&&p$board[m$t+1]=='.'
is_capture <- function(p,m) p$board[m$t+1]!='.'||is_ep(p,m)
captured <- function(p,m) if(p$board[m$t+1]!='.')tolower(p$board[m$t+1]) else if(is_ep(p,m))'p' else '-'
play <- function(p,m) {
  b<-p$board;piece<-b[m$s+1];kind<-toupper(piece)
  if(is_ep(p,m))b[m$t-step(p$side)+1]<-'.'
  if(is_castle(p,m)) {r<-RULES[[colored(if(m$t>m$s)'K' else 'Q',p$side)]];b[r[[4]]+1]<-b[r[[2]]+1];b[r[[2]]+1]<-'.'}
  b[m$t+1]<-if(nchar(m$p))colored(m$p,p$side) else piece;b[m$s+1]<-'.';rights<-''
  for(r in strsplit(p$rights,'')[[1]])if((kind!='K'||color(r)!=p$side)&&!(RULES[[r]][[2]] %in% c(m$s,m$t)))rights<-paste0(rights,r)
  position(b,opposite(p$side),rights,if(kind=='P'&&abs(m$t-m$s)==16)(m$s+m$t)/2 else -1,if(kind=='P'||is_capture(p,m))0 else p$half+1,p$full+if(p$side=='b')1 else 0)
}
pseudo <- function(p) {
  result<-list()
  for(s in 0:63) {
    piece<-p$board[s+1];if(piece=='.'||color(piece)!=p$side)next;pawn<-toupper(piece)=='P';a<-integer()
    if(pawn) {d<-step(p$side);if(p$board[s+d+1]=='.') {a<-c(a,s+d);if(s%/%8==(if(p$side=='w')1 else 6)&&p$board[s+2*d+1]=='.')a<-c(a,s+2*d)};for(t in targets(p$board,s))if((p$board[t+1]!='.'&&color(p$board[t+1])!=p$side)||t==p$ep)a<-c(a,t)}
    else for(t in targets(p$board,s))if(p$board[t+1]=='.'||color(p$board[t+1])!=p$side)a<-c(a,t)
    for(t in a)for(promotion in if(pawn&&t%/%8==(if(p$side=='w')7 else 0))c('Q','R','B','N') else '')result[[length(result)+1]]<-list(s=s,t=t,p=promotion)
  }
  result
}
castling_move <- function(p,k) {r<-RULES[[colored(if(k)'K' else 'Q',p$side)]];list(s=r[[1]],t=r[[3]],p='')}
castling_problem <- function(p,k) {
  right<-colored(if(k)'K' else 'Q',p$side);r<-RULES[[right]]
  if(!grepl(right,p$rights,fixed=TRUE))return('no castling right')
  if(any(p$board[r[[5]]+1]!='.'))return('path blocked')
  if(in_check(p))return('in check')
  if(length(attackers(p$board,r[[4]],opposite(p$side))))return('through check')
  if(in_check(play(p,castling_move(p,k)),p$side))return('into check')
  ''
}
legal <- function(p) {a<-Filter(function(m)!in_check(play(p,m),p$side),pseudo(p));for(k in c(TRUE,FALSE))if(castling_problem(p,k)=='')a[[length(a)+1]]<-castling_move(p,k);a}
check_mark <- function(p,m) {q<-play(p,m);if(in_check(q))if(length(legal(q)))'+' else '#' else ''}
disambiguation <- function(p,m) {
  a<-Filter(function(x)!is_castle(p,x)&&x$t==m$t&&x$s!=m$s&&p$board[x$s+1]==p$board[m$s+1],legal(p))
  if(!length(a))return('');sources<-vapply(a,function(x)x$s,numeric(1))
  if(all(sources%%8!=m$s%%8))return(FILES[m$s%%8+1])
  if(all(sources%/%8!=m$s%/%8))return(RANKS[m$s%/%8+1])
  sq_name(m$s)
}
san <- function(p,m) {
  kind<-toupper(p$board[m$s+1])
  text<-if(is_castle(p,m))if(m$t>m$s)'O-O' else 'O-O-O' else if(kind=='P')paste0(if(is_capture(p,m))paste0(FILES[m$s%%8+1],'x') else '',sq_name(m$t),if(nchar(m$p))paste0('=',m$p) else '') else paste0(kind,disambiguation(p,m),if(is_capture(p,m))'x' else '',sq_name(m$t))
  paste0(text,check_mark(p,m))
}
key <- function(p) paste(paste0(p$board,collapse=''),p$side,p$rights,if(p$ep>=0&&any(vapply(legal(p),function(m)is_ep(p,m),logical(1))))p$ep else -1)
state <- function(p) if(in_check(p))if(length(legal(p)))'check' else 'checkmate' else if(length(legal(p)))'normal' else 'stalemate'
insufficient <- function(p) {a<-which(p$board!='.'&toupper(p$board)!='K')-1;if(any(toupper(p$board[a+1]) %in% c('P','R','Q')))return(FALSE);length(a)<=1||(all(toupper(p$board[a+1])=='B')&&length(unique((a%%8+a%/%8)%%2))==1)}
pins <- function(p) {
  k<-match(colored('K',p$side),p$board)-1;a<-list()
  for(i in seq_len(nrow(KING))) {dx<-KING[i,1];dy<-KING[i,2];first<- -1;t<-shift(k,dx,dy)
    while(t>=0) {piece<-p$board[t+1];if(piece!='.') {if(first<0) {if(color(piece)!=p$side)break;first<-t} else {if(color(piece)!=p$side&&toupper(piece) %in% c('Q',if(dx==0||dy==0)'R' else 'B'))a[[length(a)+1]]<-c(first,t);break}};t<-shift(t,dx,dy)}
  }
  if(length(a))a[order(vapply(a,function(x)x[1],numeric(1)))] else a
}
fen <- function(p) {
  rows<-character();for(r in 7:0) {row<-'';empty<-0;for(f in 0:7) {piece<-p$board[8*r+f+1];if(piece=='.')empty<-empty+1 else {if(empty)row<-paste0(row,empty);empty<-0;row<-paste0(row,piece)}};if(empty)row<-paste0(row,empty);rows<-c(rows,row)}
  paste(paste(rows,collapse='/'),p$side,if(nchar(p$rights))p$rights else '-',if(p$ep<0)'-' else sq_name(p$ep),p$half,p$full)
}
parse_fen <- function(a) {
  if(length(a)!=6)fail('fields');rows<-head(strsplit(paste0(a[1],'/x'),'/',fixed=TRUE)[[1]],-1);if(length(rows)!=8)fail('placement');b<-rep('.',64)
  for(i in 1:8) {f<-0;digit<-FALSE;for(c in strsplit(rows[i],'')[[1]]) {if(c %in% RANKS) {if(digit)fail('placement');f<-f+as.integer(c);digit<-TRUE} else {if(!(c %in% strsplit('KQRBNPkqrbnp','')[[1]])||f>=8)fail('placement');b[(8-i)*8+f+1]<-c;f<-f+1;digit<-FALSE}};if(f!=8)fail('placement')}
  if(sum(b=='K')!=1||sum(b=='k')!=1)fail('kings')
  if(any(b[c(1:8,57:64)] %in% c('P','p')))fail('pawns')
  side<-a[2];if(!(side %in% c('w','b')))fail('side')
  if(a[3]!='-'&&(a[3]==''||!grepl('^K?Q?k?q?$',a[3])))fail('castling');rights<-if(a[3]=='-')'' else a[3]
  for(r in strsplit(rights,'')[[1]]) {rule<-RULES[[r]];if(b[rule[[1]]+1]!=colored('K',color(r))||b[rule[[2]]+1]!=colored('R',color(r)))fail('castling')}
  ep<- -1;if(a[4]!='-') {ep<-square(a[4]);d<-step(side);if(ep<0||ep%/%8!=(if(side=='w')5 else 2)||b[ep+1]!='.'||b[ep+d+1]!='.'||b[ep-d+1]!=colored('P',opposite(side)))fail('en passant')}
  half<-number(a[5],0,999);full<-number(a[6],1,999);if(half<0||full<0||(ep>=0&&half!=0))fail('clocks')
  p<-position(b,side,rights,ep,half,full);if(in_check(p,opposite(side)))fail('check');p
}
read_san <- function(p,text) {
  last<-substr(text,nchar(text),nchar(text));mark<-if(last %in% c('+','#'))last else '';body<-if(nchar(mark))substr(text,1,nchar(text)-1) else text
  castling<-body %in% c('O-O','O-O-O');promotion<-'';target<- -1;capture<-FALSE;kind<-'P';file<-'';rank<-''
  if(!castling) {
    if(nchar(body)>=2&&substr(body,nchar(body)-1,nchar(body)-1)=='=') {promotion<-substr(body,nchar(body),nchar(body));if(!(promotion %in% c('Q','R','B','N')))fail('syntax');body<-substr(body,1,nchar(body)-2)}
    if(nchar(body)<2)fail('syntax');target<-square(substr(body,nchar(body)-1,nchar(body)));if(target<0)fail('syntax');body<-substr(body,1,nchar(body)-2);capture<-endsWith(body,'x');if(capture)body<-substr(body,1,nchar(body)-1)
    if(nchar(body)&&substr(body,1,1) %in% c('K','Q','R','B','N')) {kind<-substr(body,1,1);h<-regmatches(substring(body,2),regexec('^([a-h]?)([1-8]?)$',substring(body,2)))[[1]];if(!length(h)||nchar(promotion))fail('syntax');file<-h[2];rank<-h[3]}
    else {if(!grepl(if(capture)'^[a-h]$' else '^$',body))fail('syntax');file<-body}
  }
  moves<-legal(p);if(!length(moves))fail('game over')
  if(castling) {k<-body=='O-O';problem<-castling_problem(p,k);if(nchar(problem))fail(problem);m<-castling_move(p,k)}
  else {
    matches<-function(m)toupper(p$board[m$s+1])==kind&&m$t==target&&!is_castle(p,m)&&(!nchar(file)||FILES[m$s%%8+1]==file)&&(!nchar(rank)||RANKS[m$s%/%8+1]==rank)&&(kind!='P'||(m$s%%8!=m$t%%8)==capture)
    a<-Filter(matches,moves);if(!length(a))fail(if(any(vapply(pseudo(p),matches,logical(1))))'leaves king in check' else 'no such move')
    if(length(unique(vapply(a,function(x)x$s,numeric(1))))>1)fail('ambiguous');m<-a[[1]]
    if(is_capture(p,m)!=capture)fail('capture mark');if(nchar(m$p)&&!nchar(promotion))fail('missing promotion');if(nchar(promotion)&&!nchar(m$p))fail('invalid promotion');if(kind!='P'&&paste0(file,rank)!=disambiguation(p,m))fail('disambiguation');m$p<-promotion
  }
  if(check_mark(p,m)!=mark)fail('check mark');m
}
read_uci <- function(p,text) {
  if(!grepl('^[a-h][1-8][a-h][1-8][qrbn]?$',text))fail('syntax');s<-square(substr(text,1,2));t<-square(substr(text,3,4));promotion<-toupper(substring(text,5));moves<-legal(p)
  if(!length(moves))fail('game over');if(p$board[s+1]=='.'||color(p$board[s+1])!=p$side)fail('no piece')
  a<-Filter(function(m)m$s==s&&m$t==t,moves);if(!length(a))fail(if(any(vapply(pseudo(p),function(m)m$s==s&&m$t==t,logical(1))))'leaves king in check' else 'no such move')
  m<-a[[1]];if(nchar(m$p)&&!nchar(promotion))fail('missing promotion');if(nchar(promotion)&&!nchar(m$p))fail('invalid promotion');list(s=s,t=t,p=promotion)
}
perft_count <- function(p,d) {if(d==0)return(1);sum(vapply(legal(p),function(m)perft_count(play(p,m),d-1),numeric(1)))}
perft_stats <- function(p,d) {
  stats<-numeric(7)
  for(m in legal(p)) {q<-play(p,m);if(d>1)stats<-stats+perft_stats(q,d-1) else {check<-in_check(q);stats<-stats+c(1,is_capture(p,m),is_ep(p,m),is_castle(p,m),nchar(m$p)>0,check,check&&!length(legal(q)))}}
  stats
}
new_game <- function(start=parse_fen(strsplit(INITIAL,' ',fixed=TRUE)[[1]]),loaded=FALSE) list(positions=list(start),records=list(),loaded=loaded)
current <- function(g) g$positions[[length(g$positions)]]
play_game <- function(g,m) {p<-current(g);g$records[[length(g$records)+1]]<-list(san=san(p,m),uci=paste0(sq_name(m$s),sq_name(m$t),tolower(m$p)),captured=captured(p,m));g$positions[[length(g$positions)+1]]<-play(p,m);g}
repetition <- function(g) {k<-key(current(g));sum(vapply(g$positions,function(p)key(p)==k,logical(1)))}
draws <- function(g) {a<-character();if(current(g)$half>=100)a<-c(a,'fifty');if(repetition(g)>=3)a<-c(a,'threefold');if(insufficient(current(g)))a<-c(a,'insufficient');a}
result <- function(g) {s<-state(current(g));if(s=='checkmate')if(current(g)$side=='b')'1-0' else '0-1' else if(s=='stalemate'||length(draws(g)))'1/2-1/2' else '*'}
execute <- function(g,line) {
  w<-strsplit(line,' ',fixed=TRUE)[[1]];cmd<-w[1];a<-w[-1]
  if(!(cmd %in% c('NEW','LOAD','FEN','BOARD','MOVE','UCI','LEGAL','STATUS','UNDO','PERFT','DIVIDE','ATTACKS','PINS','HISTORY','PGN'))) {emit('ERROR unknown command');return(g)}
  bad<-cmd %in% c('NEW','FEN','BOARD','STATUS','PINS','HISTORY','PGN')&&length(a)!=0
  if(cmd %in% c('MOVE','UCI'))bad<-length(a)==0
  if(cmd=='LEGAL')bad<-length(a)>1||(length(a)==1&&square(a[1])<0)
  if(cmd=='ATTACKS')bad<-length(a)!=1||(length(a)==1&&square(a[1])<0)
  n<- -1;if(cmd %in% c('UNDO','PERFT','DIVIDE')) {n<-if(length(a)==1)number(a[1],1,if(cmd=='UNDO')9999 else 3) else -1;bad<-n<0}
  if(bad) {emit('ERROR bad arguments');return(g)};p<-current(g)
  if(cmd=='NEW') {g<-new_game();emit('OK')}
  else if(cmd=='LOAD') {q<-tryCatch(parse_fen(a),error=function(e)e);if(inherits(q,'error'))emit(paste0('ERROR bad fen (',conditionMessage(q),')')) else {g<-new_game(q,TRUE);emit('OK')}}
  else if(cmd=='FEN')emit(fen(p))
  else if(cmd=='BOARD') {for(r in 7:0)emit(paste(c(r+1,p$board[8*r+1:8]),collapse=' '));emit('  a b c d e f g h')}
  else if(cmd %in% c('MOVE','UCI')) {
    played<-character();failure<-''
    for(i in seq_along(a)) {m<-tryCatch(if(cmd=='MOVE')read_san(current(g),a[i]) else read_uci(current(g),a[i]),error=function(e)e);if(inherits(m,'error')) {failure<-paste0('ILLEGAL move ',i,': ',a[i],' (',conditionMessage(m),')');break};g<-play_game(g,m);played<-c(played,g$records[[length(g$records)]]$san)}
    if(cmd=='UCI'&&length(played))emit(paste(c('san',played),collapse=' '));if(nchar(failure))emit(failure) else if(cmd=='MOVE')emit('OK')
  }else if(cmd=='LEGAL') {moves<-Filter(function(m)!length(a)||m$s==square(a[1]),legal(p));list<-sort(vapply(moves,function(m)san(p,m),character(1)),method='radix');emit(paste(c('legal',length(list),list),collapse=' '))}
  else if(cmd=='STATUS')emit(paste(c('status',if(p$side=='w')'white' else 'black',state(p),'rep',repetition(g),draws(g)),collapse=' '))
  else if(cmd=='UNDO') {if(n>length(g$records))emit('ERROR cannot undo') else {g$records<-head(g$records,-n);g$positions<-head(g$positions,-n);emit('OK')}}
  else if(cmd=='PERFT') {stats<-perft_stats(p,n);emit(paste(c('perft',n,as.vector(rbind(c('nodes','captures','ep','castles','promotions','checks','mates'),format(stats,scientific=FALSE,trim=TRUE)))),collapse=' '))}
  else if(cmd=='DIVIDE') {moves<-legal(p);sans<-vapply(moves,function(m)san(p,m),character(1));counts<-vapply(moves,function(m)perft_count(play(p,m),n-1),numeric(1));for(i in order(sans,method='radix'))emit(paste(sans[i],format(counts[i],scientific=FALSE,trim=TRUE)));emit(paste('total',format(sum(counts),scientific=FALSE,trim=TRUE)))}
  else if(cmd=='ATTACKS') {row<-c('attacks',a[1]);for(c in c('w','b')) {found<-attackers(p$board,square(a[1]),c);row<-c(row,if(c=='w')'white' else 'black',length(found),vapply(found,sq_name,character(1)))};emit(paste(row,collapse=' '))}
  else if(cmd=='PINS') {found<-pins(p);emit(paste(c('pins',length(found),vapply(found,function(x)paste0(sq_name(x[1]),'-',sq_name(x[2])),character(1))),collapse=' '))}
  else if(cmd=='HISTORY') {emit(paste('history',length(g$records)));for(i in seq_along(g$records)) {r<-g$records[[i]];emit(paste(i,r$uci,r$san,r$captured))}}
  else if(cmd=='PGN') {r<-result(g);emit(paste0('[Result "',r,'"]'));if(g$loaded) {emit('[SetUp "1"]');emit(paste0('[FEN "',fen(g$positions[[1]]),'"]'))};row<-character();for(i in seq_along(g$records)) {q<-g$positions[[i]];if(q$side=='w')row<-c(row,paste0(q$full,'.')) else if(i==1)row<-c(row,paste0(q$full,'...'));row<-c(row,g$records[[i]]$san)};emit(paste(c(row,r),collapse=' '))}
  g
}
lines<-readLines(file('stdin'),warn=FALSE);game<-new_game();for(i in seq_len(as.integer(lines[1])))game<-execute(game,lines[i+1])
