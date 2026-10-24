symbols <- strsplit('H He Li Be B C N O F Ne Na Mg Al Si P S Cl Ar K Ca Sc Ti V Cr Mn Fe Co Ni Cu Zn Ga Ge As Se Br Kr Rb Sr Y Zr Nb Mo Tc Ru Rh Pd Ag Cd In Sn Sb Te I Xe',' ',fixed=TRUE)[[1]]
W <- setNames(c(1008,4003,6941,9012,10811,12011,14007,15999,18998,20180,22990,24305,26982,28086,30974,32065,35453,39948,39098,40078,44956,47867,50942,51996,54938,55845,58933,58693,63546,65380,69723,72630,74922,78971,79904,83798,85468,87620,88906,91224,92906,95950,98000,101070,102906,106420,107868,112414,114818,118710,121760,127600,126904,131293),symbols)
valence <- c(H=1,F=1,Cl=1,Br=1,I=1,O=2,S=2,Se=2,B=3,N=3,P=3,As=3,C=4,Si=4,Ge=4)
metals <- c(Li=1,Na=1,K=1,Rb=1,Be=2,Mg=2,Ca=2,Sr=2,Al=3)
heats <- new.env(hash=TRUE,parent=emptyenv())
fail <- function(s) stop(structure(list(message=paste0('error: ',s)),class=c('chem_error','error','condition')))
no_coefficients <- function(s) stop(structure(list(message=s),class=c('chem_error','error','condition')))
num <- function(n) sprintf('%.0f',n)
gcd <- function(a,b) {a<-abs(a);b<-abs(b);while(b!=0){t<-a%%b;a<-b;b<-t};a}
dec <- function(n,d) paste0(num(floor(n/10^d)),'.',sprintf(paste0('%0',d,'.0f'),n%%10^d))
ent <- function(n) paste0(if(n<0) '-' else '',dec(abs(n),2))
signed <- function(n) paste0(if(n>0) '+' else '',num(n))
fraction <- function(n=0,d=1) {g<-gcd(n,d);c(n=n/g*if(d<0) -1 else 1,d=abs(d)/g)}
fsub <- function(a,b) fraction(a[1]*b[2]-b[1]*a[2],a[2]*b[2])
fmul <- function(a,b) fraction(a[1]*b[1],a[2]*b[2])
fdiv <- function(a,b) fraction(a[1]*b[2],a[2]*b[1])
ftext <- function(x) paste0(signed(x[1]),if(x[2]==1) '' else paste0('/',num(x[2])))
hill_order <- function(c) {es<-sort(names(c),method='radix');if('C'%in%es)c('C',if('H'%in%es)'H',setdiff(es,c('C','H'))) else es}
add <- function(a,b,k=1) {for(e in names(b)){if(!e%in%names(a))a[e]<-0;a[e]<-a[e]+b[e]*k};a}
mass <- function(c) sum(c*W[names(c)])
hill <- function(c,q=0) {es<-hill_order(c);s<-paste0(es,ifelse(c[es]==1,'',num(c[es])),collapse='');if(q!=0)s<-paste0(s,'^',if(abs(q)==1) '' else num(abs(q)),if(q>0)'+' else '-');s}
formula <- function(text,word=text) {
  chars<-strsplit(text,'',fixed=TRUE)[[1]];p<-1;seen<-character()
  peek<-function()if(p<=length(chars))chars[p] else ''
  number<-function(){start<-p;while(grepl('^[0-9]$',peek()))p<<-p+1;if(start==p)return(1);if(chars[start]=='0')stop('syntax');as.numeric(paste0(chars[start:(p-1)],collapse=''))}
  sequence<-function(){c<-numeric();items<-0;repeat{ch<-peek();if(grepl('^[A-Z]$',ch)){e<-ch;p<<-p+1;if(grepl('^[a-z]$',peek())){e<-paste0(e,peek());p<<-p+1};seen<<-c(seen,e);item<-setNames(1,e)}else if(ch%in%c('(','[')){p<<-p+1;item<-sequence();if(peek()!=if(ch=='(')')' else ']')stop('syntax');p<<-p+1}else break;c<-add(c,item,number());items<-items+1};if(items==0)stop('syntax');c}
  f<-tryCatch({c<-sequence();while(peek()=='.'){p<-p+1;k<-number();c<-add(c,sequence(),k)};q<-0;if(peek()=='^'){p<-p+1;k<-number();ch<-peek();if(!ch%in%c('+','-'))stop('syntax');p<-p+1;q<-if(ch=='+')k else -k};if(p!=nchar(text)+1)stop('syntax');list(c=c,q=q)},error=function(e)NULL)
  if(is.null(f))fail(paste0('invalid formula ',word));for(e in seen)if(!e%in%names(W))fail(paste0('unknown element ',e));f$m<-mass(f$c);f
}
species <- function(word,check=FALSE) {
  state<-'';f<-word;k<-1
  for(s in c('(s)','(l)','(g)','(aq)'))if(endsWith(word,s)){state<-s;f<-substr(word,1,nchar(word)-nchar(s));break}
  if(check&&grepl('^[0-9]',f)){digits<-regmatches(f,regexpr('^[0-9]+',f));if(startsWith(f,'0'))fail(paste0('invalid formula ',word));k<-as.numeric(digits);f<-substring(f,nchar(digits)+1)}
  z<-formula(f,word);c(z,list(f=f,state=state,name=paste0(f,state),k=k))
}
equation <- function(a,check=FALSE) {
  if(length(a)%%2==0)fail('malformed equation')
  odd<-seq(1,length(a),by=2);even<-if(length(a)>=2)seq(2,length(a),by=2)else integer()
  if(length(a)%%2==0||sum(a[even]=='->')!=1||any(!a[even]%in%c('+','->'))||any(a[odd]%in%c('+','->')))fail('malformed equation')
  list<-lapply(a[odd],species,check=check);r<-(match('->',a)+1)/2
  list(list=list,r=r,sign=ifelse(seq_along(list)<=r,1,-1))
}
quantity <- function(s){if(!grepl('^(0|[1-9][0-9]{0,3})(\\.[0-9]{1,3})?$',s,perl=TRUE))fail(paste0('invalid quantity ',s));parts<-strsplit(s,'.',fixed=TRUE)[[1]];q<-as.numeric(parts[1])*1000;if(length(parts)>1)q<-q+as.numeric(paste0(parts[2],strrep('0',3-nchar(parts[2]))));if(q==0)fail(paste0('invalid quantity ',s));q}
enthalpy <- function(s){if(!grepl('^-?(0|[1-9][0-9]{0,4})(\\.[0-9]{1,2})?$',s,perl=TRUE))fail(paste0('invalid enthalpy ',s));parts<-strsplit(sub('^-','',s),'.',fixed=TRUE)[[1]];q<-as.numeric(parts[1])*100;if(length(parts)>1)q<-q+as.numeric(paste0(parts[2],strrep('0',2-nchar(parts[2]))));q*if(startsWith(s,'-'))-1 else 1}
composition_matrix <- function(list,sign){all<-numeric();for(s in list)all<-add(all,s$c);labels<-c(hill_order(all),'charge');rows<-lapply(labels,function(e)vapply(seq_along(list),function(i){s<-list[[i]];sign[i]*if(e=='charge')s$q else if(e%in%names(s$c))s$c[e] else 0},numeric(1)));list(labels=labels,rows=rows)}
nullspace <- function(rows,n){a<-lapply(rows,function(r)lapply(r,fraction));piv<-free<-integer()
  for(j in seq_len(n)){r<-length(piv)+1;i<-r;while(i<=length(a)&&a[[i]][[j]][1]==0)i<-i+1;if(i>length(a)){free<-c(free,j);next};t<-a[[r]];a[[r]]<-a[[i]];a[[i]]<-t;t<-a[[r]][[j]];a[[r]]<-lapply(a[[r]],fdiv,b=t)
    for(k in seq_along(a))if(k!=r&&a[[k]][[j]][1]!=0){t<-a[[k]][[j]];for(z in seq_len(n))a[[k]][[z]]<-fsub(a[[k]][[z]],fmul(t,a[[r]][[z]]))};piv<-c(piv,j)}
  basis<-lapply(free,function(f){v<-replicate(n,fraction(),simplify=FALSE);v[[f]]<-fraction(1);for(i in seq_along(piv))v[[piv[i]]]<-fraction(-a[[i]][[f]][1],a[[i]][[f]][2]);l<-1;for(x in v)l<-l/gcd(l,x[2])*x[2];b<-vapply(v,function(x)x[1]*(l/x[2]),numeric(1));g<-Reduce(gcd,b,init=0);b/g});list(rank=length(piv),basis=basis)
}
coefficients <- function(list,sign,k=length(list)){ns<-nullspace(composition_matrix(list,sign)$rows,length(list));d<-length(ns$basis);if(d>=2)no_coefficients(paste0('AMBIGUOUS (nullity ',d,')'));if(d==0)no_coefficients('IMPOSSIBLE');v<-ns$basis[[1]];if(v[1]<0)v<--v;if(any(v[seq_len(k)]<=0))no_coefficients('IMPOSSIBLE');v}
term <- function(s,k)paste0(if(k==1)'' else num(k),s)
notation <- function(eq,v){t<-vapply(seq_along(eq$list),function(i)term(eq$list[[i]]$name,v[i]),character(1));paste0(paste(t[seq_len(eq$r)],collapse=' + '),' -> ',paste(t[seq(eq$r+1,length(t))],collapse=' + '))}
gas <- function(s,n,d)if(s$state=='(g)')paste0(' ',dec(floor(n*22414/d),3),' L')else ''
ratio_report <- function(a){es<-hill_order(a);f<-es[1];for(e in es)if(a[e]*W[f]<a[f]*W[e])f<-e;out<-vapply(es,function(e)paste(e,dec(floor(1000*a[e]*W[f]/(W[e]*a[f])),3)),character(1));for(k in 1:12){counts<-setNames(numeric(length(es)),es);ok<-TRUE;for(e in es){n<-k*a[e]*W[f];d<-W[e]*a[f];i<-floor((2*n+d)/(2*d));counts[e]<-i;if(20*abs(n-i*d)>d)ok<-FALSE};if(ok)return(c(out,paste0(hill(counts),' (k = ',k,')')))};c(out,'no simple ratio')}
group_notation <- function(f,k){core<-strsplit(f,'^',fixed=TRUE)[[1]][1];if(k==1)return(core);depth<-0;last<--1;if(startsWith(core,'[')){chars<-strsplit(core,'',fixed=TRUE)[[1]];for(i in seq_along(chars)){if(chars[i]=='[')depth<-depth+1;if(chars[i]==']'){depth<-depth-1;if(depth==0){last<-i;break}}}};paste0(if(grepl('^[A-Z][a-z]?$',core)||last==nchar(core))core else paste0('(',core,')'),num(k))}
counts<-c(ELEMENT=1,PARSE=1,MASS=1,PERCENT=1,EMPIRICAL=1,DBE=1,OXSTATE=1,MOLES=2,GRAMS=2,MOLECULAR=2,SALT=2,HEAT=2,COMBUST=3,HEATS=0,DERIVE=-2,BALANCE=-1,MATRIX=-1,CHECK=-1,DELTAH=-1,REDOX=-3,HALF=-3,STOICH=-4,LIMITING=-4,YIELD=-4)
execute <- function(line){words<-strsplit(line,' ',fixed=TRUE)[[1]];cmd<-words[1];a<-words[-1];n<-length(a);if(!cmd%in%names(counts))fail(paste0('unknown command ',cmd));e<-counts[cmd];if((e>=0&&n!=e)||(e==-1&&n<1)||(e==-2&&(n<2||n%%2!=0))||(e==-3&&n<2))fail(paste0('wrong argument count for ',cmd))
  if(cmd=='ELEMENT'){if(!a[1]%in%names(W))fail(paste0('unknown element ',a[1]));return(paste0(a[1],' (Z = ',match(a[1],symbols),') ',dec(W[a[1]],3),' u'))}
  if(cmd=='HEATS'){names<-sort(ls(heats,all.names=TRUE),method='radix');return(if(!length(names))'no enthalpies'else vapply(names,function(s)paste(s,ent(heats[[s]]),'kJ/mol'),character(1)))}
  if(cmd=='HEAT'){species(a[1]);h<-enthalpy(a[2]);s<-paste0('dHf(',a[1],') = ',ent(h),' kJ/mol');if(exists(a[1],heats,inherits=FALSE))s<-paste0(s,' (was ',ent(heats[[a[1]]]),')');heats[[a[1]]]<-h;return(s)}
  if(cmd=='DERIVE'){b<-numeric();for(i in seq(1,n,by=2)){s<-a[i];if(!s%in%names(W))fail(paste0('unknown element ',s));if(s%in%names(b))fail(paste0('duplicate element ',s));q<-quantity(a[i+1]);if(q>100000)fail(paste0('invalid percentage ',a[i+1]));b[s]<-q};t<-sum(b);if(abs(t-100000)>1000)fail(paste0('percentages sum to ',dec(t,3)));return(ratio_report(b))}
  if(cmd=='COMBUST'){qs<-vapply(a,quantity,numeric(1));s<-qs[1];c<-floor(qs[2]*12011/44009);h<-floor(qs[3]*2016/18015);o<-s-c-h;if(c==0||h==0||100*o < -s)fail('inconsistent masses');b<-c(C=c,H=h);if(100*o>s)b['O']<-o;return(c(vapply(names(b),function(e)paste('mass',e,dec(b[e],3),'g'),character(1)),ratio_report(b)))}
  if(cmd%in%c('PARSE','MASS','PERCENT','EMPIRICAL','DBE','OXSTATE','MOLES','GRAMS','MOLECULAR','SALT')){f<-formula(a[1]);c<-f$c;q<-f$q;m<-f$m;es<-hill_order(c)
    if(cmd=='PARSE')return(paste0(hill(c,q),' (',paste(paste(es,num(c[es])),collapse=', '),'; charge ',signed(q),')'))
    if(cmd=='MASS')return(paste0('M(',a[1],') = ',dec(m,3),' g/mol'))
    if(cmd=='PERCENT')return(vapply(es,function(e)paste0(e,' ',dec(floor(10000*c[e]*W[e]/m),2),'%'),character(1)))
    if(cmd=='EMPIRICAL'){g<-Reduce(gcd,c);return(paste0(hill(c/g),' (n = ',num(g),')'))}
    if(cmd=='DBE'){if(q!=0)fail(paste0('charged formula ',a[1]));t<-2;for(e in es){if(!e%in%names(valence))fail(paste0('no valence for ',e));t<-t+c[e]*(valence[e]-2)};return(paste0('DBE = ',if(t<0)'-'else '',num(floor(abs(t)/2)),'.',if(t%%2!=0)'5'else '0'))}
    if(cmd=='OXSTATE'){st<-list();last<-NULL;assign_state<-function(e,n){st[[e]]<<-fraction(n);last<<-e}
      if(length(es)==1)st[[es[1]]]<-fraction(q,c[es[1]])else{if('F'%in%es)assign_state('F',-1);for(e in es)if(e%in%names(metals))assign_state(e,metals[e]);if('H'%in%es)assign_state('H',if(all(es=='H'|es%in%names(metals)))-1 else 1);if('O'%in%es)assign_state('O',-2)else if(!'F'%in%es)for(e in c('Cl','Br','I'))if(e%in%es){assign_state(e,-1);break};u<-setdiff(es,names(st));if(length(u)>1)return(paste0('indeterminate: ',paste(u,collapse=' ')));total<-sum(vapply(names(st),function(e)c[e]*st[[e]][1],numeric(1)));if(length(u))st[[u[1]]]<-fraction(q-total,c[u[1]])else if(total!=q)st[[last]]<-fraction(q-total+c[last]*st[[last]][1],c[last])};return(paste(vapply(es,function(e)paste(e,ftext(st[[e]])),character(1)),collapse=', '))}
    if(cmd=='SALT'){b<-formula(a[2]);if(q<=0)fail(paste0('not a cation ',a[1]));if(b$q>=0)fail(paste0('not an anion ',a[2]));for(s in a)if(grepl('.',s,fixed=TRUE))fail(paste0('hydrate ion ',s));g<-gcd(q,b$q);x<--b$q/g;y<-q/g;z<-add(c*x,b$c,y);return(paste0(group_notation(a[1],x),group_notation(a[2],y),' (',hill(z),', ',dec(mass(z),3),' g/mol)'))}
    if(cmd=='MOLECULAR'&&q!=0)fail(paste0('charged formula ',a[1]));x<-quantity(a[2]);if(cmd=='MOLES')return(paste0(dec(x,3),' g ',a[1],' = ',dec(floor(x*1000000/m),6),' mol'));if(cmd=='GRAMS')return(paste0(dec(x,3),' mol ',a[1],' = ',dec(floor(x*m/1000),3),' g'));k<-floor((2*x+m)/(2*m));if(k==0||10*abs(x-k*m)>m)return(paste0('no integer multiple (ratio ',dec(floor(1000*x/m),3),')'));return(paste0(hill(c*k),' (n = ',num(k),', ',dec(k*m,3),' g/mol)'))
  }
  if(cmd%in%c('REDOX','HALF')){if(!a[1]%in%c('acidic','basic'))fail(paste0('invalid medium ',a[1]));eq<-equation(a[-1]);for(s in eq$list)if(s$f%in%c('H^+','OH^-','H2O'))fail(paste0('reserved species ',s$name));aux<-list(species(if(a[1]=='acidic')'H^+'else 'OH^-'),species('H2O'));if(cmd=='HALF')aux[[3]]<-list(f='e^-',name='e^-',state='',k=1,c=numeric(),q=-1,m=0);list<-c(eq$list,aux);v<-coefficients(list,c(eq$sign,rep(1,length(aux))),length(eq$list));left<-right<-character();for(i in seq_along(eq$list))if(i<=eq$r)left<-c(left,term(list[[i]]$name,v[i]))else right<-c(right,term(list[[i]]$name,v[i]));for(i in seq(length(eq$list)+1,length(list)))if(v[i]>0)left<-c(left,term(list[[i]]$name,v[i]))else if(v[i]<0)right<-c(right,term(list[[i]]$name,-v[i]));out<-paste0(paste(left,collapse=' + '),' -> ',paste(right,collapse=' + '));if(cmd=='HALF')out<-c(out,if(tail(v,1)>0)'reduction'else if(tail(v,1)<0)'oxidation'else 'no electron transfer');return(out)}
  words<-a;rest<-character();if(cmd%in%c('STOICH','LIMITING','YIELD')){if(sum(a==':')!=1)fail('invalid separator');i<-match(':',a);words<-if(i==1)character()else a[seq_len(i-1)];rest<-if(i==length(a))character()else a[seq(i+1,length(a))];if((cmd=='STOICH'&&length(rest)!=2)||(cmd=='YIELD'&&length(rest)!=4))fail(paste0('wrong argument count for ',cmd))}
  eq<-equation(words,cmd=='CHECK');list<-eq$list;r<-eq$r
  if(cmd=='MATRIX'){m<-composition_matrix(list,eq$sign);ns<-nullspace(m$rows,length(list));return(c(paste0('columns: ',paste(vapply(list,`[[`,character(1),'name'),collapse=' ')),vapply(seq_along(m$rows),function(i)paste0(m$labels[i],': ',paste(num(m$rows[[i]]),collapse=' ')),character(1)),paste0('rank ',ns$rank,', nullity ',length(ns$basis)),vapply(ns$basis,function(v)paste0('null: ',paste(num(v),collapse=' ')),character(1))))}
  if(cmd=='CHECK'){m<-composition_matrix(list,eq$sign);diff<-character();for(i in seq_along(m$rows)){row<-m$rows[[i]];l<-sum(vapply(seq_len(r),function(j)row[j]*list[[j]]$k,numeric(1)));rr<--sum(vapply(seq(r+1,length(list)),function(j)row[j]*list[[j]]$k,numeric(1)));if(l!=rr)diff<-c(diff,paste0(m$labels[i],': ',if(m$labels[i]=='charge')signed(l)else num(l),' != ',if(m$labels[i]=='charge')signed(rr)else num(rr)))};if(length(diff))return(c('not balanced',diff));g<-Reduce(gcd,vapply(list,`[[`,numeric(1),'k'));return(if(g==1)'balanced'else paste0('balanced, not in lowest terms (gcd ',num(g),')'))}
  qs<-numeric();target<-product<-NA_integer_
  if(cmd=='DELTAH')for(s in list)if(!exists(s$name,heats,inherits=FALSE))fail(paste0('no enthalpy for ',s$name))
  if(cmd=='STOICH'){target<-match(rest[1],vapply(list,`[[`,character(1),'name'));if(is.na(target))fail(paste0('species ',rest[1],' not in equation'));qs<-quantity(rest[2])}
  if(cmd=='LIMITING'){if(length(rest)!=r)fail(paste0('expected ',r,' masses, got ',length(rest)));qs<-vapply(rest,quantity,numeric(1))}
  if(cmd=='YIELD'){target<-match(rest[1],vapply(list[seq_len(r)],`[[`,character(1),'name'));if(is.na(target))fail(paste0(rest[1],' is not a reactant'));product<-match(rest[3],vapply(list[seq(r+1,length(list))],`[[`,character(1),'name'))+r;if(is.na(product))fail(paste0(rest[3],' is not a product'));q1<-quantity(rest[2]);q2<-quantity(rest[4]);qs<-c(q1,q2)}
  v<-coefficients(list,eq$sign);out<-notation(eq,v);if(cmd=='BALANCE')return(out)
  if(cmd=='DELTAH'){h<-sum(vapply(seq_along(list),function(i)-eq$sign[i]*v[i]*heats[[list[[i]]$name]],numeric(1)));return(c(out,paste0('dH = ',ent(h),' kJ (',if(h<0)'exothermic'else if(h>0)'endothermic'else 'thermoneutral',')')))}
  if(cmd=='STOICH'){d<-v[target]*list[[target]]$m;return(c(out,vapply(seq_along(list),function(i){s<-list[[i]];x<-qs[1]*v[i];paste0(s$name,' ',dec(floor(x*1000000/d),6),' mol ',dec(floor(x*s$m/d),3),' g',gas(s,x,d))},character(1))))}
  if(cmd=='YIELD'){t<-floor(qs[1]*v[product]*list[[product]]$m/(v[target]*list[[target]]$m));return(c(out,paste0('theoretical ',dec(t,3),' g'),paste0('actual ',dec(qs[2],3),' g'),if(t==0)'yield undefined'else paste0('yield ',dec(floor(qs[2]*10000/t),2),'%')))}
  l<-1;for(i in seq_len(r))if(qs[i]*v[l]*list[[l]]$m<qs[l]*v[i]*list[[i]]$m)l<-i;d<-v[l]*list[[l]]$m;out<-c(out,paste0('limiting ',list[[l]]$name),paste0('extent ',dec(floor(qs[l]*1000000/d),6),' mol'))
  for(i in seq(r+1,length(list)))out<-c(out,paste0('product ',list[[i]]$name,' ',dec(floor(qs[l]*v[i]*list[[i]]$m/d),3),' g',gas(list[[i]],qs[l]*v[i],d)))
  for(i in seq_len(r))if(i!=l)out<-c(out,paste0('remaining ',list[[i]]$name,' ',dec(floor((qs[i]*d-qs[l]*v[i]*list[[i]]$m)/d),3),' g'));out
}
input<-readLines(file('stdin'),warn=FALSE);for(line in input[seq_len(as.numeric(input[1]))+1]){out<-tryCatch(execute(line),chem_error=function(e)e$message);cat(paste0(out,'\n'),sep='')}
