local files,ranks='abcdefgh','12345678'
local initial='rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'
local rook={{0,1},{0,-1},{-1,0},{1,0}}
local bishop={{1,1},{-1,1},{1,-1},{-1,-1}}
local king={{0,1},{0,-1},{-1,0},{1,0},{1,1},{-1,1},{1,-1},{-1,-1}}
local knight={{1,2},{2,1},{2,-1},{1,-2},{-1,-2},{-2,-1},{-2,1},{-1,2}}
local rules={K={4,7,6,5,{5,6}},Q={4,0,2,3,{1,2,3}},k={60,63,62,61,{61,62}},q={60,56,58,59,{57,58,59}}}
local function fail(s) error(s,0) end
local function emit(s) io.write(s,'\n') end
local function contains(s,c) return s:find(c,1,true)~=nil end
local function opposite(c) return c=='w' and 'b' or 'w' end
local function color(p) return p==p:upper() and 'w' or 'b' end
local function colored(p,c) return c=='w' and p or p:lower() end
local function step(c) return c=='w' and 8 or -8 end
local function square(s) if not s:match('^[a-h][1-8]$') then return -1 end return s:byte(1)-97+8*(s:byte(2)-49) end
local function name(s) return files:sub(s%8+1,s%8+1)..ranks:sub(s//8+1,s//8+1) end
local function number(s,lo,hi) if not s:match('^%d+$') or (#s>1 and s:sub(1,1)=='0') then return -1 end local n=tonumber(s);return n>=lo and n<=hi and n or -1 end
local function shift(s,dx,dy) local x,y=s%8+dx,s//8+dy;if x<0 or x>7 or y<0 or y>7 then return -1 end return 8*y+x end
local function targets(b,s)
    local p=b[s];local kind=p:upper();local result={};local dirs
    if contains('PNK',kind) then
        dirs=kind=='P' and {{-1,color(p)=='w' and 1 or -1},{1,color(p)=='w' and 1 or -1}} or kind=='N' and knight or king
        for _,d in ipairs(dirs) do local t=shift(s,d[1],d[2]);if t>=0 then result[#result+1]=t end end
    else
        dirs=kind=='Q' and king or kind=='R' and rook or bishop
        for _,d in ipairs(dirs) do local t=shift(s,d[1],d[2]);while t>=0 do result[#result+1]=t;if b[t]~='.' then break end;t=shift(t,d[1],d[2]) end end
    end
    return result
end
local function attackers(b,t,c)
    local a={};for s=0,63 do if b[s]~='.' and color(b[s])==c then for _,v in ipairs(targets(b,s)) do if v==t then a[#a+1]=s;break end end end end;return a
end
local Position={};Position.__index=Position
function Position.new(b,side,rights,ep,half,full) return setmetatable({board=b,side=side,rights=rights,ep=ep,half=half,full=full},Position) end
function Position:check(c) c=c or self.side;local k;for s=0,63 do if self.board[s]==colored('K',c) then k=s;break end end return #attackers(self.board,k,opposite(c))>0 end
function Position:castle(m) return self.board[m.s]:upper()=='K' and math.abs(m.t-m.s)==2 end
function Position:enpassant(m) return self.board[m.s]:upper()=='P' and m.s%8~=m.t%8 and self.board[m.t]=='.' end
function Position:capture(m) return self.board[m.t]~='.' or self:enpassant(m) end
function Position:captured(m) return self.board[m.t]~='.' and self.board[m.t]:lower() or self:enpassant(m) and 'p' or '-' end
function Position:play(m)
    local b={};for s=0,63 do b[s]=self.board[s] end;local piece=b[m.s];local kind=piece:upper()
    if self:enpassant(m) then b[m.t-step(self.side)]='.' end
    if self:castle(m) then local r=rules[colored(m.t>m.s and 'K' or 'Q',self.side)];b[r[4]]=b[r[2]];b[r[2]]='.' end
    b[m.t]=m.p~='' and colored(m.p,self.side) or piece;b[m.s]='.'
    local rights='';for r in self.rights:gmatch('.') do if (kind~='K' or color(r)~=self.side) and rules[r][2]~=m.s and rules[r][2]~=m.t then rights=rights..r end end
    return Position.new(b,opposite(self.side),rights,kind=='P' and math.abs(m.t-m.s)==16 and (m.s+m.t)//2 or -1,(kind=='P' or self:capture(m)) and 0 or self.half+1,self.full+(self.side=='b' and 1 or 0))
end
function Position:pseudo()
    local result={}
    for s=0,63 do local p=self.board[s]
        if p~='.' and color(p)==self.side then
            local pawn=p:upper()=='P';local a={}
            if pawn then
                local d=step(self.side)
                if self.board[s+d]=='.' then a[#a+1]=s+d;if s//8==(self.side=='w' and 1 or 6) and self.board[s+2*d]=='.' then a[#a+1]=s+2*d end end
                for _,t in ipairs(targets(self.board,s)) do if (self.board[t]~='.' and color(self.board[t])~=self.side) or t==self.ep then a[#a+1]=t end end
            else for _,t in ipairs(targets(self.board,s)) do if self.board[t]=='.' or color(self.board[t])~=self.side then a[#a+1]=t end end end
            for _,t in ipairs(a) do
                if pawn and t//8==(self.side=='w' and 7 or 0) then for p in ('QRBN'):gmatch('.') do result[#result+1]={s=s,t=t,p=p} end
                else result[#result+1]={s=s,t=t,p=''} end
            end
        end
    end
    return result
end
function Position:castlingMove(k) local r=rules[colored(k and 'K' or 'Q',self.side)];return {s=r[1],t=r[3],p=''} end
function Position:castlingProblem(k)
    local right=colored(k and 'K' or 'Q',self.side);local r=rules[right]
    if not contains(self.rights,right) then return 'no castling right' end
    for _,s in ipairs(r[5]) do if self.board[s]~='.' then return 'path blocked' end end
    if self:check() then return 'in check' end
    if #attackers(self.board,r[4],opposite(self.side))>0 then return 'through check' end
    if self:play(self:castlingMove(k)):check(self.side) then return 'into check' end
    return nil
end
function Position:legal()
    if self.cached then return self.cached end
    local a={};for _,m in ipairs(self:pseudo()) do if not self:play(m):check(self.side) then a[#a+1]=m end end
    for _,k in ipairs({true,false}) do if not self:castlingProblem(k) then a[#a+1]=self:castlingMove(k) end end
    self.cached=a;return a
end
function Position:mark(m) local q=self:play(m);return q:check() and (#q:legal()>0 and '+' or '#') or '' end
function Position:disambiguation(m)
    local any,file,rank=false,true,true
    for _,x in ipairs(self:legal()) do if not self:castle(x) and x.t==m.t and x.s~=m.s and self.board[x.s]==self.board[m.s] then any=true;file=file and x.s%8~=m.s%8;rank=rank and x.s//8~=m.s//8 end end
    if not any then return '' end
    if file then return files:sub(m.s%8+1,m.s%8+1) end
    if rank then return ranks:sub(m.s//8+1,m.s//8+1) end
    return name(m.s)
end
function Position:san(m)
    local kind=self.board[m.s]:upper();local text
    if self:castle(m) then text=m.t>m.s and 'O-O' or 'O-O-O'
    elseif kind=='P' then text=(self:capture(m) and files:sub(m.s%8+1,m.s%8+1)..'x' or '')..name(m.t)..(m.p~='' and '='..m.p or '')
    else text=kind..self:disambiguation(m)..(self:capture(m) and 'x' or '')..name(m.t) end
    return text..self:mark(m)
end
function Position:key()
    local ep=-1;if self.ep>=0 then for _,m in ipairs(self:legal()) do if self:enpassant(m) then ep=self.ep;break end end end
    local b='';for s=0,63 do b=b..self.board[s] end;return b..' '..self.side..' '..self.rights..' '..ep
end
function Position:state() return self:check() and (#self:legal()>0 and 'check' or 'checkmate') or (#self:legal()>0 and 'normal' or 'stalemate') end
function Position:insufficient()
    local a={};for s=0,63 do local p=self.board[s]:upper();if p~='.' and p~='K' then if contains('PRQ',p) then return false end;a[#a+1]=s end end
    if #a<=1 then return true end;local shade=(a[1]%8+a[1]//8)%2
    for _,s in ipairs(a) do if self.board[s]:upper()~='B' or (s%8+s//8)%2~=shade then return false end end;return true
end
function Position:pins()
    local k;for s=0,63 do if self.board[s]==colored('K',self.side) then k=s end end;local found={}
    for _,d in ipairs(king) do local first=-1;local t=shift(k,d[1],d[2]);while t>=0 do local p=self.board[t]
        if p~='.' then if first<0 then if color(p)~=self.side then break end;first=t
        else if color(p)~=self.side and contains('Q'..((d[1]==0 or d[2]==0) and 'R' or 'B'),p:upper()) then found[#found+1]={first,t} end;break end end
        t=shift(t,d[1],d[2])
    end end
    table.sort(found,function(a,b)return a[1]<b[1]end);return found
end
function Position:fen()
    local rows={};for r=7,0,-1 do local row='';for f=0,7 do row=row..self.board[8*r+f] end;rows[#rows+1]=row:gsub('%.+',function(run)return tostring(#run)end) end
    return table.concat({table.concat(rows,'/'),self.side,self.rights~='' and self.rights or '-',self.ep>=0 and name(self.ep) or '-',self.half,self.full},' ')
end
local function split(s) local a={};for x in s:gmatch('%S+') do a[#a+1]=x end;return a end
local function parseFen(a)
    if #a~=6 then fail('fields') end;local rows={};for row in (a[1]..'/'):gmatch('(.-)/') do rows[#rows+1]=row end
    if #rows~=8 then fail('placement') end;local b={};for s=0,63 do b[s]='.' end
    for i,row in ipairs(rows) do local f,digit=0,false;for c in row:gmatch('.') do
        if contains('12345678',c) then if digit then fail('placement') end;f=f+tonumber(c);digit=true
        else if not contains('KQRBNPkqrbnp',c) or f>=8 then fail('placement') end;b[(8-i)*8+f]=c;f=f+1;digit=false end
    end;if f~=8 then fail('placement') end end
    local white,black=0,0;for s=0,63 do if b[s]=='K' then white=white+1 elseif b[s]=='k' then black=black+1 end end;if white~=1 or black~=1 then fail('kings') end
    for s=0,7 do if b[s]:upper()=='P' or b[56+s]:upper()=='P' then fail('pawns') end end
    local side=a[2];if side~='w' and side~='b' then fail('side') end
    local rights=a[3]=='-' and '' or a[3];local previous=0
    if a[3]~='-' then if #rights==0 then fail('castling') end;for r in rights:gmatch('.') do local i=('KQkq'):find(r,1,true);if not i or i<=previous then fail('castling') end;previous=i end end
    for r in rights:gmatch('.') do local rule=rules[r];if b[rule[1]]~=colored('K',color(r)) or b[rule[2]]~=colored('R',color(r)) then fail('castling') end end
    local ep=-1;if a[4]~='-' then ep=square(a[4]);local d=step(side);if ep<0 or ep//8~=(side=='w' and 5 or 2) or b[ep]~='.' or b[ep+d]~='.' or b[ep-d]~=colored('P',opposite(side)) then fail('en passant') end end
    local half,full=number(a[5],0,999),number(a[6],1,999);if half<0 or full<0 or (ep>=0 and half~=0) then fail('clocks') end
    local p=Position.new(b,side,rights,ep,half,full);if p:check(opposite(side)) then fail('check') end;return p
end
local function readSan(pos,text)
    local last=text:sub(-1);local mark=(last=='+' or last=='#') and last or '';local body=mark~='' and text:sub(1,-2) or text
    local castling=body=='O-O' or body=='O-O-O';local promotion,target,capture,kind,file,rank='',-1,false,'P','',''
    if not castling then
        if #body>=2 and body:sub(-2,-2)=='=' then promotion=body:sub(-1);if not contains('QRBN',promotion) then fail('syntax') end;body=body:sub(1,-3) end
        target=square(body:sub(-2));if target<0 then fail('syntax') end;body=body:sub(1,-3);capture=body:sub(-1)=='x';if capture then body=body:sub(1,-2) end
        if #body>0 and contains('KQRBN',body:sub(1,1)) then kind=body:sub(1,1);local f,r=body:sub(2):match('^([a-h]?)([1-8]?)$');if not f or promotion~='' then fail('syntax') end;file,rank=f,r
        else if not body:match(capture and '^[a-h]$' or '^$') then fail('syntax') end;file=body end
    end
    local legal=pos:legal();if #legal==0 then fail('game over') end;local move
    if castling then local k=body=='O-O';local problem=pos:castlingProblem(k);if problem then fail(problem) end;move=pos:castlingMove(k)
    else
        local function matches(m) return pos.board[m.s]:upper()==kind and m.t==target and not pos:castle(m) and (file=='' or files:sub(m.s%8+1,m.s%8+1)==file) and (rank=='' or ranks:sub(m.s//8+1,m.s//8+1)==rank) and (kind~='P' or (m.s%8~=m.t%8)==capture) end
        local candidates={};for _,m in ipairs(legal) do if matches(m) then candidates[#candidates+1]=m end end
        if #candidates==0 then for _,m in ipairs(pos:pseudo()) do if matches(m) then fail('leaves king in check') end end;fail('no such move') end
        move=candidates[1];for _,m in ipairs(candidates) do if m.s~=move.s then fail('ambiguous') end end
        if pos:capture(move)~=capture then fail('capture mark') end
        if move.p~='' and promotion=='' then fail('missing promotion') end
        if promotion~='' and move.p=='' then fail('invalid promotion') end
        if kind~='P' and file..rank~=pos:disambiguation(move) then fail('disambiguation') end;move={s=move.s,t=move.t,p=promotion}
    end
    if pos:mark(move)~=mark then fail('check mark') end;return move
end
local function readUci(pos,text)
    if (#text~=4 and #text~=5) or square(text:sub(1,2))<0 or square(text:sub(3,4))<0 or (#text==5 and not contains('qrbn',text:sub(5))) then fail('syntax') end
    local s,t,p=square(text:sub(1,2)),square(text:sub(3,4)),text:sub(5):upper();local legal=pos:legal()
    if #legal==0 then fail('game over') end;if pos.board[s]=='.' or color(pos.board[s])~=pos.side then fail('no piece') end
    for _,m in ipairs(legal) do if m.s==s and m.t==t then if m.p~='' and p=='' then fail('missing promotion') end;if p~='' and m.p=='' then fail('invalid promotion') end;return {s=s,t=t,p=p} end end
    for _,m in ipairs(pos:pseudo()) do if m.s==s and m.t==t then fail('leaves king in check') end end;fail('no such move')
end
local function perft(p,d,stats)
    if d==0 then return 1 end;local total=0
    for _,m in ipairs(p:legal()) do local q=p:play(m);total=total+perft(q,d-1,stats)
        if d==1 and stats then stats[1]=stats[1]+1;if p:capture(m) then stats[2]=stats[2]+1 end;if p:enpassant(m) then stats[3]=stats[3]+1 end;if p:castle(m) then stats[4]=stats[4]+1 end;if m.p~='' then stats[5]=stats[5]+1 end;if q:check() then stats[6]=stats[6]+1;if #q:legal()==0 then stats[7]=stats[7]+1 end end end
    end;return total
end
local Game={};Game.__index=Game
function Game.new(start,loaded) return setmetatable({positions={start or parseFen(split(initial))},records={},loaded=loaded or false},Game) end
function Game:current() return self.positions[#self.positions] end
function Game:play(m) local p=self:current();self.records[#self.records+1]={san=p:san(m),uci=name(m.s)..name(m.t)..m.p:lower(),captured=p:captured(m)};self.positions[#self.positions+1]=p:play(m) end
function Game:repetition() local key=self:current():key();local n=0;for _,p in ipairs(self.positions) do if p:key()==key then n=n+1 end end;return n end
function Game:draws() local a={};if self:current().half>=100 then a[#a+1]='fifty' end;if self:repetition()>=3 then a[#a+1]='threefold' end;if self:current():insufficient() then a[#a+1]='insufficient' end;return a end
function Game:result() local p=self:current();local state=p:state();if state=='checkmate' then return p.side=='b' and '1-0' or '0-1' end;return (state=='stalemate' or #self:draws()>0) and '1/2-1/2' or '*' end
local game=Game.new()
local function execute(line)
    local a=split(line);local cmd=table.remove(a,1)
    if not contains(' NEW LOAD FEN BOARD MOVE UCI LEGAL STATUS UNDO PERFT DIVIDE ATTACKS PINS HISTORY PGN ',' '..cmd..' ') then emit('ERROR unknown command');return end
    local bad=contains(' NEW FEN BOARD STATUS PINS HISTORY PGN ',' '..cmd..' ') and #a~=0 or (cmd=='MOVE' or cmd=='UCI') and #a==0
    if cmd=='LEGAL' then bad=#a>1 or #a==1 and square(a[1])<0 end
    if cmd=='ATTACKS' then bad=#a~=1 or #a==1 and square(a[1])<0 end
    local n=-1;if cmd=='UNDO' or cmd=='PERFT' or cmd=='DIVIDE' then n=#a==1 and number(a[1],1,cmd=='UNDO' and 9999 or 3) or -1;bad=n<0 end
    if bad then emit('ERROR bad arguments');return end;local p=game:current()
    if cmd=='NEW' then game=Game.new();emit('OK')
    elseif cmd=='LOAD' then local ok,q=pcall(parseFen,a);if ok then game=Game.new(q,true);emit('OK') else emit('ERROR bad fen ('..q..')') end
    elseif cmd=='FEN' then emit(p:fen())
    elseif cmd=='BOARD' then for r=7,0,-1 do local row={r+1};for f=0,7 do row[#row+1]=p.board[8*r+f] end;emit(table.concat(row,' ')) end;emit('  a b c d e f g h')
    elseif cmd=='MOVE' or cmd=='UCI' then local played={};local failure
        for i,text in ipairs(a) do local ok,m=pcall(cmd=='MOVE' and readSan or readUci,game:current(),text);if not ok then failure='ILLEGAL move '..i..': '..text..' ('..m..')';break end;game:play(m);played[#played+1]=game.records[#game.records].san end
        if cmd=='UCI' and #played>0 then emit('san '..table.concat(played,' ')) end;if failure then emit(failure) elseif cmd=='MOVE' then emit('OK') end
    elseif cmd=='LEGAL' then local from=#a==1 and square(a[1]) or -1;local list={};for _,m in ipairs(p:legal()) do if from<0 or m.s==from then list[#list+1]=p:san(m) end end;table.sort(list);local row={'legal',#list};for _,s in ipairs(list) do row[#row+1]=s end;emit(table.concat(row,' '))
    elseif cmd=='STATUS' then local row={'status',p.side=='w' and 'white' or 'black',p:state(),'rep',game:repetition()};for _,s in ipairs(game:draws()) do row[#row+1]=s end;emit(table.concat(row,' '))
    elseif cmd=='UNDO' then if n>#game.records then emit('ERROR cannot undo') else for _=1,n do table.remove(game.records);table.remove(game.positions) end;emit('OK') end
    elseif cmd=='PERFT' then local stats={0,0,0,0,0,0,0};perft(p,n,stats);local row={'perft',n};for i,f in ipairs({'nodes','captures','ep','castles','promotions','checks','mates'}) do row[#row+1]=f;row[#row+1]=stats[i] end;emit(table.concat(row,' '))
    elseif cmd=='DIVIDE' then local rows={};local total=0;for _,m in ipairs(p:legal()) do local v=perft(p:play(m),n-1);rows[#rows+1]={p:san(m),v};total=total+v end;table.sort(rows,function(x,y)return x[1]<y[1]end);for _,r in ipairs(rows) do emit(r[1]..' '..r[2]) end;emit('total '..total)
    elseif cmd=='ATTACKS' then local row={'attacks',a[1]};for _,c in ipairs({'w','b'}) do local found=attackers(p.board,square(a[1]),c);row[#row+1]=c=='w' and 'white' or 'black';row[#row+1]=#found;for _,s in ipairs(found) do row[#row+1]=name(s) end end;emit(table.concat(row,' '))
    elseif cmd=='PINS' then local pins=p:pins();local row={'pins',#pins};for _,pair in ipairs(pins) do row[#row+1]=name(pair[1])..'-'..name(pair[2]) end;emit(table.concat(row,' '))
    elseif cmd=='HISTORY' then emit('history '..#game.records);for i,r in ipairs(game.records) do emit(i..' '..r.uci..' '..r.san..' '..r.captured) end
    elseif cmd=='PGN' then local result=game:result();emit('[Result "'..result..'"]');if game.loaded then emit('[SetUp "1"]');emit('[FEN "'..game.positions[1]:fen()..'"]') end;local row={};for i,r in ipairs(game.records) do local q=game.positions[i];if q.side=='w' then row[#row+1]=q.full..'.' elseif i==1 then row[#row+1]=q.full..'...' end;row[#row+1]=r.san end;row[#row+1]=result;emit(table.concat(row,' '))
    end
end
local count=tonumber(io.read());for _=1,count do execute(io.read()) end
