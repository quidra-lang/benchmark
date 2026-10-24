local weights={100,-20,10,5,5,10,-20,100,-20,-50,-2,-2,-2,-2,-50,-20,10,-2,-1,-1,-1,-1,-2,10,5,-2,-1,-1,-1,-1,-2,5,5,-2,-1,-1,-1,-1,-2,5,10,-2,-1,-1,-1,-1,-2,10,-20,-50,-2,-2,-2,-2,-50,-20,100,-20,10,5,5,10,-20,100}
local function set(text) local s={};for x in text:gmatch('%S+') do s[x]=true end;return s end
local transforms=set('rot90 rot180 rot270 mirror flip diag anti')
local zero=set('NEW DUMP SHOW SCORE LEGAL HISTORY SHEET STATS EVAL STABLE SOLVE')
local numeric=set('UNDO REDO HINT PV AI ANALYZE RANDOM PERFT DIVIDE')
local active=set('FLIPS MOVE PLAY HINT PV AI SOLVE AUTOPLAY RANDOM MC DIVIDE')
local extra=set('LOAD TRANSFORM AUTOPLAY MC FLIPS MOVE PLAY RECORD')
local function other(s) return s=='B' and 'W' or 'B' end
local function name(p) return string.char(97+p%8)..(p//8+1) end
local function square(s) return (tonumber(s:sub(2,2))-1)*8+s:byte(1)-97 end
local function inside(r,c) return r>=0 and r<8 and c>=0 and c<8 end
local function initial() local b={};for i=1,64 do b[i]='.' end;b[28]='W';b[37]='W';b[29]='B';b[36]='B';return table.concat(b) end
local function disc(b,p) return b:sub(p+1,p+1) end
local function flips(b,s,p)
    if disc(b,p)~='.' then return {} end;local out,row,col={},p//8,p%8
    for dr=-1,1 do for dc=-1,1 do if dr~=0 or dc~=0 then local r,c=row+dr,col+dc;local line={};while inside(r,c) and disc(b,8*r+c)==other(s) do line[#line+1]=8*r+c;r=r+dr;c=c+dc end;if #line>0 and inside(r,c) and disc(b,8*r+c)==s then for _,q in ipairs(line) do out[#out+1]=q end end end end end;table.sort(out);return out
end
local function legal(b,s) local ms={};for p=0,63 do if disc(b,p)=='.' and #flips(b,s,p)>0 then ms[#ms+1]=p end end;return ms end
local function place(b,s,p) local a={};for i=1,64 do a[i]=b:sub(i,i) end;for _,q in ipairs(flips(b,s,p)) do a[q+1]=s end;a[p+1]=s;return table.concat(a) end
local function count(b,s) local n=0;for i=1,64 do if b:sub(i,i)==s then n=n+1 end end;return n end
local function terminal(b) return #legal(b,'B')==0 and #legal(b,'W')==0 end
local function gameOver(b) local x,y=count(b,'B'),count(b,'W');return 'game over B '..x..' W '..y..' '..(x>y and 'winner B' or x<y and 'winner W' or 'draw') end
local function evaluate(b,s) local w=0;for i=1,64 do local x=b:sub(i,i);w=w+(x==s and weights[i] or x==other(s) and -weights[i] or 0) end;local own,enemy=#legal(b,s),#legal(b,other(s));return w+10*(own-enemy),w,own,enemy end
local searchCache,searchSize={},0
local function search(b,s,d)
    local key=b..s..':'..d;if searchCache[key] then return searchCache[key] end;local ms,o=legal(b,s),other(s);local v
    if #ms==0 and #legal(b,o)==0 then v=(d<0 and 1 or 1000)*(count(b,s)-count(b,o)) elseif d==0 then v=evaluate(b,s) elseif #ms==0 then v=-search(b,o,d<0 and -1 or d-1) else v=-1000000;for _,p in ipairs(ms) do v=math.max(v,-search(place(b,s,p),o,d<0 and -1 or d-1)) end end
    if searchSize>300000 then searchCache={};searchSize=0 end;searchCache[key]=v;searchSize=searchSize+1;return v
end
local function ranked(b,s,d) local rows={};for _,p in ipairs(legal(b,s)) do rows[#rows+1]={-search(place(b,s,p),other(s),d<0 and -1 or d-1),p} end;table.sort(rows,function(a,b) return a[1]>b[1] or (a[1]==b[1] and a[2]<b[2]) end);return rows end
local function variation(b,s,d) local steps={};while d~=0 and not terminal(b) do local ms=ranked(b,s,d);if #ms>0 then local p=ms[1][2];steps[#steps+1]=name(p);b=place(b,s,p) else steps[#steps+1]='pass' end;s=other(s);if d>0 then d=d-1 end end;return steps,b end
local perftCache,perftSize={},0
local function perft(b,s,d) if d==0 then return 1 end;local key=b..s..d;if perftCache[key] then return perftCache[key] end;local ms,o=legal(b,s),other(s);local n=0;if #ms==0 then n=#legal(b,o)==0 and 1 or perft(b,o,d-1) else for _,p in ipairs(ms) do n=n+perft(place(b,s,p),o,d-1) end end;if perftSize>200000 then perftCache={};perftSize=0 end;perftCache[key]=n;perftSize=perftSize+1;return n end
local function stable(b)
    local stable={};local axes={{0,1},{1,0},{1,1},{1,-1}}
    while true do local found={};for p=0,63 do if disc(b,p)~='.' and not stable[p] then local row,col=p//8,p%8;local ok=true;for _,axis in ipairs(axes) do local dr,dc=axis[1],axis[2];local full,anchor=true,false;for _,sign in ipairs({-1,1}) do local r,c=row+dr*sign,col+dc*sign;if not inside(r,c) or (stable[8*r+c] and disc(b,8*r+c)==disc(b,p)) then anchor=true end;while inside(r,c) do if disc(b,8*r+c)=='.' then full=false end;r=r+dr*sign;c=c+dc*sign end end;if not full and not anchor then ok=false;break end end;if ok then found[#found+1]=p end end end;if #found==0 then break end;for _,p in ipairs(found) do stable[p]=true end end
    local black,white=0,0;for p in pairs(stable) do if disc(b,p)=='B' then black=black+1 else white=white+1 end end;return black,white
end
local function transform(p,op) local r,c=p//8,p%8;if op=='rot90' then return 8*c+7-r elseif op=='rot180' then return 63-p elseif op=='rot270' then return 8*(7-c)+r elseif op=='mirror' then return 8*r+7-c elseif op=='flip' then return 8*(7-r)+c elseif op=='diag' then return 8*c+r else return 8*(7-c)+7-r end end
local function transformBoard(b,op) local a={};for p=0,63 do a[transform(p,op)+1]=disc(b,p) end;return table.concat(a) end
local function random(seed) return {value=seed,draw=function(self) self.value=self.value*48271%2147483647;return self.value end} end
local function randomGame(b,s,rng) while true do local ms=legal(b,s);if #ms>0 then b=place(b,s,ms[rng:draw()%#ms+1]) elseif #legal(b,other(s))==0 then return b end;s=other(s) end end
local function average(f,n) local v=100*f//n;return string.format('%d.%02d',v//100,v%100) end
local function emit(...) local xs={...};for i,x in ipairs(xs) do xs[i]=tostring(x) end;io.write(table.concat(xs,' '),'\n') end
local Engine={};Engine.__index=Engine
function Engine.new() local e=setmetatable({},Engine);e:reset();return e end
function Engine:reset() self.board=initial();self.side='B';self.over=false;self.history={};self.redo={} end
function Engine:snapshot() return {board=self.board,side=self.side,over=self.over} end
function Engine:restore(p) self.board=p.board;self.side=p.side;self.over=p.over end
function Engine:status() return self.over and gameOver(self.board) or self.side..' to move' end
function Engine:adjust(quiet) if #legal(self.board,self.side)>0 then return false end;if #legal(self.board,other(self.side))>0 then if not quiet then emit(self.side,'passes') end;self.side=other(self.side);return true end;self.over=true;if not quiet then emit(gameOver(self.board)) end;return false end
function Engine:move(p,quiet,value) local before,s,k=self:snapshot(),self.side,#flips(self.board,self.side,p);self.board=place(self.board,s,p);if not quiet then if value then emit(s,name(p),'flips',k,'value',value) else emit(s,name(p),'flips',k) end end;self.side=other(s);local passed=self:adjust(quiet);self.history[#self.history+1]={side=s,square=p,count=k,passed=passed,before=before,after=self:snapshot()};self.redo={};return passed end
function Engine:reason(p) if self.over then return 'game over' elseif disc(self.board,p)~='.' then return 'occupied' elseif #flips(self.board,self.side,p)==0 then return 'no flips' end;return nil end
function Engine:record(text) local e,ps,passes=Engine.new(),{},0;for i=1,#text,2 do local s=text:sub(i,i+1);local p=square(s);local why=e:reason(p);if why then emit('ILLEGAL move',(i+1)//2,s,why);return end;ps[#ps+1]=p;if e:move(p,true) then passes=passes+1 end end;self:restore(e:snapshot());self.history=e.history;self.redo={};local op=({f5='',e6='diag',d3='anti',c4='rot180'})[name(ps[1])];local normal={};for _,p in ipairs(ps) do normal[#normal+1]=name(op=='' and p or transform(p,op)) end;emit('record',#ps,'moves',passes,'passes');emit('normal',table.concat(normal));emit(self:status()) end
function Engine:sheet() local b=#self.history>0 and self.history[1].before.board or self.board;local fields={};for i=1,64 do fields[i]=b:sub(i,i) end;for i,r in ipairs(self.history) do fields[r.square+1]=tostring(i) end;emit('   a  b  c  d  e  f  g  h');for r=0,7 do local row=tostring(r+1);for c=0,7 do row=row..string.format('%3s',fields[8*r+c+1]) end;emit(row) end end
function Engine:stats() local n,total,passes=#self.history,0,0;for _,r in ipairs(self.history) do total=total+r.count;if r.passed then passes=passes+1 end end;if n==0 then emit('moves 0') else emit('moves',n,'flips',total,'avg',average(total,n),'passes',passes) end;for _,s in ipairs({'B','W'}) do local k,sum,max,p,corners=0,0,-1,nil,0;for _,r in ipairs(self.history) do if r.side==s then k=k+1;sum=sum+r.count;if r.count>max then max=r.count;p=r.square end;if r.square==0 or r.square==7 or r.square==56 or r.square==63 then corners=corners+1 end end end;if k==0 then emit(s,'moves 0') else emit(s,'moves',k,'flips',sum,'avg',average(sum,k),'max',max,name(p),'corners',corners) end end end
function Engine:auto(black,white,seed) local rng=seed and random(seed);local ps,passes={},0;while not self.over do local ms=legal(self.board,self.side);local p=rng and ms[rng:draw()%#ms+1] or ranked(self.board,self.side,self.side=='B' and black or white)[1][2];ps[#ps+1]=name(p);if self:move(p,true) then passes=passes+1 end end;emit(rng and 'random' or 'autoplay',#ps,'moves',passes,'passes');emit('moves',table.concat(ps));emit(gameOver(self.board)) end
function Engine:monteCarlo(k,seed) local rng=random(seed);local best,bp=-1,nil;for _,p in ipairs(legal(self.board,self.side)) do local w,d,l=0,0,0;local start=place(self.board,self.side,p);for _=1,k do local b=randomGame(start,other(self.side),rng);local diff=count(b,self.side)-count(b,other(self.side));if diff>0 then w=w+1 elseif diff<0 then l=l+1 else d=d+1 end end;emit(name(p),w,d,l);if 2*w+d>best then best=2*w+d;bp=p end end;emit('best',name(bp),best) end
function Engine:execute(text)
    local a={};for s in text:gmatch('%S+') do a[#a+1]=s end;local cmd=table.remove(a,1);local err
    if not zero[cmd] and not numeric[cmd] and not extra[cmd] then err='unknown command'
    elseif cmd=='LOAD' then if #a~=2 or #a[1]~=64 or a[1]:find('[^.BW]') or (a[2]~='B' and a[2]~='W') then err='bad board' end
    elseif cmd=='MOVE' or cmd=='FLIPS' then if #a~=1 then err='bad arguments' elseif not a[1]:match('^[a-h][1-8]$') then err='bad square' end
    elseif cmd=='PLAY' or cmd=='RECORD' then if #a~=1 then err='bad arguments' else local t=a[1];local valid=#t>=2 and #t<=120 and #t%2==0;for i=1,#t,2 do if not t:sub(i,i+1):match('^[a-h][1-8]$') then valid=false end end;if not valid then err='bad record' end end
    elseif zero[cmd] then if #a~=0 then err='bad arguments' end
    elseif cmd=='TRANSFORM' then if #a~=1 or not transforms[a[1]] then err='bad arguments' end
    else local expected=(cmd=='AUTOPLAY' or cmd=='MC') and 2 or 1;local valid=#a==expected;local ns={};for i,s in ipairs(a) do if not s:match('^%d+$') then valid=false else ns[i]=tonumber(s) end end;if valid then local n=ns[1];if cmd=='AUTOPLAY' then valid=n>=1 and n<=4 and ns[2]>=1 and ns[2]<=4 elseif cmd=='HINT' or cmd=='PV' or cmd=='AI' or cmd=='ANALYZE' then valid=n>=1 and n<=4 elseif cmd=='PERFT' or cmd=='DIVIDE' then valid=n>=1 and n<=8 elseif cmd=='MC' then valid=n>=1 and n<=100 and ns[2]>=1 and ns[2]<=2147483646 elseif cmd=='RANDOM' then valid=n>=1 and n<=2147483646 else valid=n>=1 end end;if not valid then err='bad arguments' end end
    if err then emit('ERROR',err);return end;if self.over and active[cmd] then emit('ERROR game over');return end;local n=tonumber(a[1])
    if cmd=='NEW' then self:reset();emit('OK')
    elseif cmd=='LOAD' then self.board=a[1];self.side=a[2];self.over=false;self.history={};self.redo={};emit('OK');self:adjust()
    elseif cmd=='DUMP' then emit('board',self.board,self.side)
    elseif cmd=='SHOW' then emit('  a b c d e f g h');local ms={};if not self.over then for _,p in ipairs(legal(self.board,self.side)) do ms[p]=true end end;for r=0,7 do local row={r+1};for c=0,7 do row[#row+1]=ms[8*r+c] and '*' or disc(self.board,8*r+c) end;emit(table.unpack(row)) end;emit(self:status())
    elseif cmd=='SCORE' then emit('score B',count(self.board,'B'),'W',count(self.board,'W'),'empty',count(self.board,'.'))
    elseif cmd=='LEGAL' then local ms=self.over and {} or legal(self.board,self.side);local out={'legal',#ms};for _,p in ipairs(ms) do out[#out+1]=name(p) end;emit(table.unpack(out))
    elseif cmd=='MOVE' or cmd=='FLIPS' then local p=square(a[1]);local why=self:reason(p);if why then emit('ILLEGAL',why) elseif cmd=='MOVE' then self:move(p) else local f=flips(self.board,self.side,p);local out={'flips',a[1],#f};for _,q in ipairs(f) do out[#out+1]=name(q) end;emit(table.unpack(out)) end
    elseif cmd=='PLAY' then for i=1,#a[1],2 do local p=square(a[1]:sub(i,i+1));local why=self:reason(p);if why then emit('ILLEGAL move',(i+1)//2,name(p),why);break end;self:move(p) end
    elseif cmd=='RECORD' then self:record(a[1])
    elseif cmd=='UNDO' then if n>#self.history then emit('ERROR cannot undo') else local start=#self.history-n+1;self:restore(self.history[start].before);local red={};for i=start,#self.history do red[#red+1]=self.history[i] end;for _,r in ipairs(self.redo) do red[#red+1]=r end;for i=#self.history,start,-1 do self.history[i]=nil end;self.redo=red;emit(self:status()) end
    elseif cmd=='REDO' then if n>#self.redo then emit('ERROR cannot redo') else for _=1,n do self.history[#self.history+1]=table.remove(self.redo,1) end;self:restore(self.history[#self.history].after);emit(self:status()) end
    elseif cmd=='HISTORY' then emit('history',#self.history);for i,r in ipairs(self.history) do if r.passed then emit(i,r.side,name(r.square),r.count,'pass') else emit(i,r.side,name(r.square),r.count) end end
    elseif cmd=='SHEET' then self:sheet()
    elseif cmd=='STATS' then self:stats()
    elseif cmd=='TRANSFORM' then local op=a[1];self.board=transformBoard(self.board,op);local function tr(p) return {board=transformBoard(p.board,op),side=p.side,over=p.over} end;for _,rows in ipairs({self.history,self.redo}) do for _,r in ipairs(rows) do r.square=transform(r.square,op);r.before=tr(r.before);r.after=tr(r.after) end end;emit('OK')
    elseif cmd=='EVAL' then local v,w,x,y=evaluate(self.board,self.side);emit('eval',v,'weights',w,'mobility',x,y)
    elseif cmd=='STABLE' then local b,w=stable(self.board);emit('stable B',b,'W',w)
    elseif cmd=='HINT' then for _,row in ipairs(ranked(self.board,self.side,n)) do emit(name(row[2]),row[1]) end
    elseif cmd=='PV' then local steps=variation(self.board,self.side,n);local out={'pv',search(self.board,self.side,n)};for _,s in ipairs(steps) do out[#out+1]=s end;emit(table.unpack(out))
    elseif cmd=='AI' then local row=ranked(self.board,self.side,n)[1];self:move(row[2],false,row[1])
    elseif cmd=='ANALYZE' then local loss={B=0,W=0};for i,r in ipairs(self.history) do local rows=ranked(r.before.board,r.side,n);local best,bp=rows[1][1],rows[1][2];local value;for _,row in ipairs(rows) do if row[2]==r.square then value=row[1];break end end;loss[r.side]=loss[r.side]+best-value;emit(i,r.side,name(r.square),value,'best',name(bp),best) end;emit('loss B',loss.B,'W',loss.W)
    elseif cmd=='SOLVE' then if count(self.board,'.')>=9 then emit('ERROR too many empties') else for _,row in ipairs(ranked(self.board,self.side,-1)) do emit(name(row[2]),row[1]) end;local steps,b=variation(self.board,self.side,-1);local out={'line'};for _,s in ipairs(steps) do out[#out+1]=s end;emit(table.unpack(out));emit('final B',count(b,'B'),'W',count(b,'W')) end
    elseif cmd=='AUTOPLAY' then self:auto(n,tonumber(a[2]))
    elseif cmd=='RANDOM' then self:auto(0,0,n)
    elseif cmd=='MC' then self:monteCarlo(n,tonumber(a[2]))
    elseif cmd=='PERFT' then emit('perft',n,perft(self.board,self.side,n))
    elseif cmd=='DIVIDE' then local total=0;for _,p in ipairs(legal(self.board,self.side)) do local v=perft(place(self.board,self.side,p),other(self.side),n-1);emit(name(p),v);total=total+v end;emit('total',total)
    end
end
local e=Engine.new();local n=tonumber(io.read('*l'));for _=1,n do e:execute(io.read('*l')) end
