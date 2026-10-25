local kinds = {'I', 'O', 'T', 'S', 'Z', 'J', 'L'}
local movements = {'L', 'R', 'LL', 'RR', 'SD', 'DD', 'CW', 'CCW'}
local operation_names = {'L', 'R', 'LL', 'RR', 'SD', 'DD', 'CW', 'CCW', 'HD', 'LOCK', 'HOLD'}
local command_names = {'NEW','PRINT','NEXT','PREVIEW','STATUS','ANALYZE','ROW','GARBAGE','ATTACK','TICK','UNDO','SAVE','LOAD','SPINS','HINT','AUTO'}
local after_end = {'PRINT','NEXT','PREVIEW','STATUS','ANALYZE','LOAD'}
local states = {'0', 'R', '2', 'L'}
local clear_names = {'SINGLE','DOUBLE','TRIPLE','TETRIS','TSPIN_MINI','TSPIN_MINI_SINGLE','TSPIN_MINI_DOUBLE','TSPIN','TSPIN_SINGLE','TSPIN_DOUBLE','TSPIN_TRIPLE'}
local frames = {
    I={'....','####','....','....'},O={'##','##'},T={'.#.','###','...'},
    S={'.##','##.','...'},Z={'##.','.##','...'},J={'#..','###','...'},L={'..#','###','...'}
}
local shapes = {}
for _,kind in ipairs(kinds) do
    local blocks = {}
    for j,line in ipairs(frames[kind]) do
        for i=1,#line do if line:sub(i,i)=='#' then blocks[#blocks+1]={i-1,j-1} end end
    end
    shapes[kind]={blocks}
    for s=2,4 do
        local next_blocks={}
        for _,b in ipairs(blocks) do next_blocks[#next_blocks+1]={#frames[kind]-1-b[2],b[1]} end
        blocks=next_blocks
        shapes[kind][s]=blocks
    end
end
local ordinary_kicks={
    ['01']={{0,0},{-1,0},{-1,1},{0,-2},{-1,-2}},
    ['10']={{0,0},{1,0},{1,-1},{0,2},{1,2}},
    ['12']={{0,0},{1,0},{1,-1},{0,2},{1,2}},
    ['21']={{0,0},{-1,0},{-1,1},{0,-2},{-1,-2}},
    ['23']={{0,0},{1,0},{1,1},{0,-2},{1,-2}},
    ['32']={{0,0},{-1,0},{-1,-1},{0,2},{-1,2}},
    ['30']={{0,0},{-1,0},{-1,-1},{0,2},{-1,2}},
    ['03']={{0,0},{1,0},{1,1},{0,-2},{1,-2}}
}
local i_kicks={
    ['01']={{0,0},{-2,0},{1,0},{-2,-1},{1,2}},
    ['10']={{0,0},{2,0},{-1,0},{2,1},{-1,-2}},
    ['12']={{0,0},{-1,0},{2,0},{-1,2},{2,-1}},
    ['21']={{0,0},{1,0},{-2,0},{1,-2},{-2,1}},
    ['23']={{0,0},{2,0},{-1,0},{2,1},{-1,-2}},
    ['32']={{0,0},{-2,0},{1,0},{-2,-1},{1,2}},
    ['30']={{0,0},{1,0},{-2,0},{1,-2},{-2,1}},
    ['03']={{0,0},{-1,0},{2,0},{-1,2},{2,-1}}
}
local output={}
local function emit(line) output[#output+1]=line end
local function member(items,value)
    for _,item in ipairs(items) do if item==value then return true end end
    return false
end
local function clone(value)
    if type(value)~='table' then return value end
    local result={}
    for k,v in pairs(value) do result[k]=clone(v) end
    return result
end
local function sum(a)
    local n=0
    for _,v in ipairs(a) do n=n+v end
    return n
end
local function seed_step(x) return (48271*x)%2147483647 end
local function spawn(kind) return {0,kind=='O' and 5 or 4,22} end
local function pkey(p) return table.concat(p,',') end
local function cells(kind,p)
    local a={}
    for _,b in ipairs(shapes[kind][p[1]+1]) do a[#a+1]={p[2]+b[1],p[3]-b[2]} end
    return a
end
local function lowest(kind,p)
    local result=23
    for _,b in ipairs(cells(kind,p)) do if b[2]<result then result=b[2] end end
    return result
end
local function bag(x)
    local pieces=clone(kinds)
    for i=7,2,-1 do
        x=seed_step(x)
        local j=x%i+1
        pieces[i],pieces[j]=pieces[j],pieces[i]
    end
    return x,pieces
end
local function fits(board,kind,p)
    for _,b in ipairs(cells(kind,p)) do
        local c,r=b[1],b[2]
        if c<1 or c>10 or r<1 or r>22 or board[r]&(1<<(c-1))~=0 then return false end
    end
    return true
end
local function move(board,kind,p,op)
    local s,x,y=p[1],p[2],p[3]
    if op=='CW' or op=='CCW' then
        local b=(s+(op=='CW' and 1 or 3))%4
        local offsets=kind=='O' and {{0,0}} or (kind=='I' and i_kicks or ordinary_kicks)[tostring(s)..tostring(b)]
        for i,k in ipairs(offsets) do
            local q={b,x+k[1],y+k[2]}
            if fits(board,kind,q) then return q,i end
        end
        return nil
    end
    local dx=(op=='L' or op=='LL') and -1 or (op=='R' or op=='RR') and 1 or 0
    local dy=dx==0 and -1 or 0
    local repeat_move=op=='LL' or op=='RR' or op=='DD'
    local position=p
    local changed=false
    repeat
        local q={s,position[2]+dx,position[3]+dy}
        if not fits(board,kind,q) then break end
        position=q
        changed=true
    until not repeat_move
    if changed then return position,0 end
    return nil
end
local function landing(board,kind,p) return move(board,kind,p,'DD') or p end
local function placed(board,kind,p)
    local result=clone(board)
    for _,b in ipairs(cells(kind,p)) do result[b[2]]=result[b[2]]|(1<<(b[1]-1)) end
    local remaining={}
    for _,row in ipairs(result) do if row~=1023 then remaining[#remaining+1]=row end end
    local lines=22-#remaining
    for i=1,lines do remaining[#remaining+1]=0 end
    return remaining,lines
end
local function evaluate(board,cleared)
    local heights={}
    local holes,bumpiness=0,0
    for c=1,10 do
        local height=0
        for r=22,1,-1 do if board[r]&(1<<(c-1))~=0 then height=r break end end
        heights[c]=height
        for r=1,height do if board[r]&(1<<(c-1))==0 then holes=holes+1 end end
    end
    for c=1,9 do bumpiness=bumpiness+math.abs(heights[c]-heights[c+1]) end
    return {heights=heights,holes=holes,bumpiness=bumpiness,value=76*cleared-51*sum(heights)-36*holes-18*bumpiness}
end
local function routes(board,kind,start,target)
    if not fits(board,kind,start) then return {} end
    local queue={{position=start,keys={}}}
    local seen={[pkey(start)]=true}
    local i=1
    while i<=#queue do
        local entry=queue[i]
        i=i+1
        if target and pkey(landing(board,kind,entry.position))==pkey(target) then return {entry} end
        for _,op in ipairs(movements) do
            local p=move(board,kind,entry.position,op)
            if p and not seen[pkey(p)] then
                seen[pkey(p)]=true
                local keys=clone(entry.keys)
                keys[#keys+1]=op
                queue[#queue+1]={position=p,keys=keys}
            end
        end
    end
    if target then return {} end
    return queue
end
local function tspin(board,p,test)
    local s,x,y=p[1],p[2],p[3]
    local corners={{x,y},{x+2,y},{x+2,y-2},{x,y-2}}
    local blocked={}
    local total=0
    for i,b in ipairs(corners) do
        local c,r=b[1],b[2]
        blocked[i]=c<1 or c>10 or r<1 or r>22 or board[r]&(1<<(c-1))~=0
        if blocked[i] then total=total+1 end
    end
    if total<3 then return '' end
    if blocked[s+1] and blocked[(s+1)%4+1] or test==5 then return 'full' end
    return 'mini'
end
local function clear_info(spin,lines)
    if spin=='full' then return ({'TSPIN','TSPIN_SINGLE','TSPIN_DOUBLE','TSPIN_TRIPLE'})[lines+1],({400,800,1200,1600})[lines+1],({0,2,4,6})[lines+1] end
    if spin=='mini' then return ({'TSPIN_MINI','TSPIN_MINI_SINGLE','TSPIN_MINI_DOUBLE'})[lines+1],({100,200,400})[lines+1],({0,0,1})[lines+1] end
    return ({'','SINGLE','DOUBLE','TRIPLE','TETRIS'})[lines+1],({0,100,300,500,800})[lines+1],({0,0,1,2,4})[lines+1]
end
local Game={}
Game.__index=Game
function Game.new(number,seed,level)
    local stats={drops=0,holds=0,operations=0,faults=0,perfect=0,sent=0,cancelled=0,received=0,combo=0,chain=0,kinds={},clears={}}
    for _,k in ipairs(kinds) do stats.kinds[k]=0 end
    for _,name in ipairs(clear_names) do stats.clears[name]=0 end
    local s={board={},random=seed,queue={},hold=nil,used_hold=false,kind='I',position=spawn('I'),last='none',test=0,keys=0,drop=0,fall=0,ground=0,resets=0,lowest=0,
        initial_level=level,level=level,score=0,lines=0,pieces=0,streak=0,chain=0,pending={},ended=false,stats=stats}
    for i=1,22 do s.board[i]=0 end
    local self=setmetatable({number=number,s=s,history={},start={},saves={}},Game)
    self:add_bag()
    self:spawn_piece(self:next_piece())
    self.start=clone(self.s)
    return self
end
function Game:add_bag()
    local pieces
    self.s.random,pieces=bag(self.s.random)
    for _,piece in ipairs(pieces) do self.s.queue[#self.s.queue+1]=piece end
end
function Game:next_piece()
    local kind=table.remove(self.s.queue,1)
    if #self.s.queue<5 then self:add_bag() end
    return kind
end
function Game:spawn_piece(kind)
    local s=self.s
    s.kind=kind;s.position=spawn(kind);s.last='none';s.test=0;s.keys=0;s.drop=0;s.fall=0;s.ground=0;s.resets=0
    s.lowest=lowest(kind,s.position)
    if not fits(s.board,kind,s.position) then self:over('block out') end
end
function Game:over(reason)
    emit('game over '..reason)
    self:summary()
    self.s.ended=true
    error('game over',0)
end
function Game:update(p,last,test)
    local s=self.s
    s.position=p;s.last=last;s.test=test or 0
    local row=lowest(s.kind,p)
    if row<s.lowest then s.lowest=row;s.resets=0 end
end
function Game:grounded() return move(self.s.board,self.s.kind,self.s.position,'SD')==nil end
function Game:drops(rows)
    local s=self.s
    s.score=s.score+rows;s.drop=s.drop+rows;s.stats.drops=s.stats.drops+rows
end
function Game:insert_garbage(rows,hole)
    local s=self.s
    for r=23-rows,22 do if s.board[r]~=0 then self:over('top out') end end
    local result={}
    for i=1,rows do result[i]=1023~(1<<(hole-1)) end
    for i=1,22-rows do result[rows+i]=s.board[i] end
    s.board=result
end
function Game:operation(op)
    local s=self.s
    if member(movements,op) then
        s.keys=s.keys+1
        local p,test=move(s.board,s.kind,s.position,op)
        if not p then emit('fail '..op) return end
        if op=='SD' or op=='DD' then
            self:drops(s.position[3]-p[3]);self:update(p,'move');s.fall=0;s.ground=0
        else
            self:update(p,(op=='CW' or op=='CCW') and 'rotation' or 'move',test)
            if s.ground>0 and s.resets<15 then s.ground=0;s.resets=s.resets+1 end
        end
    elseif op=='HD' then
        local p=landing(s.board,s.kind,s.position)
        local rows=s.position[3]-p[3]
        self:drops(2*rows)
        if rows>0 then self:update(p,'move') end
        self:lock()
    elseif op=='LOCK' then
        if self:grounded() then self:lock() else emit('fail LOCK') end
    else
        if s.used_hold then emit('fail HOLD') return end
        s.used_hold=true;s.stats.holds=s.stats.holds+1
        local prev=s.hold
        s.hold=s.kind
        self:spawn_piece(prev or self:next_piece())
    end
end
function Game:tick()
    local s=self.s
    if not self:grounded() then
        s.ground=0;s.fall=s.fall+1
        local interval=s.level>=13 and 1 or ({60,48,37,28,21,16,11,8,6,4,3,2})[s.level]
        if s.fall>=interval then self:update({s.position[1],s.position[2],s.position[3]-1},'move');s.fall=0 end
    else
        s.ground=s.ground+1
        if s.ground>=30 then self:lock() end
    end
end
function Game:lock()
    local s=self.s
    local kind,p=s.kind,s.position
    local old_cells=cells(kind,p)
    local shortlist=routes(s.board,kind,spawn(kind),p)
    local shortest=shortlist[1]
    local spin=kind=='T' and s.last=='rotation' and tspin(s.board,p,s.test) or ''
    local n
    s.board,n=placed(s.board,kind,p)
    self.history[#self.history+1]=clone(self.start)
    s.pieces=s.pieces+1;s.stats.kinds[kind]=s.stats.kinds[kind]+1;s.stats.operations=s.stats.operations+s.keys
    local name,points,sent=clear_info(spin,n)
    local level=s.level
    points=points*level
    local back=false
    if n>0 then
        s.streak=s.streak+1
        if n==4 or spin~='' then s.chain=s.chain+1;back=s.chain>=2 else s.chain=0 end
    else s.streak=0 end
    if back then points=math.floor(points*3/2);sent=sent+1 end
    local combo=s.streak-1
    local combo_points=combo>=1 and 50*combo*level or 0
    if combo>=0 then sent=sent+({0,1,1,2,2,3,3,4,4,4,5})[math.min(combo,10)+1] end
    local perfect=n>0
    if perfect then for _,row in ipairs(s.board) do if row~=0 then perfect=false break end end end
    local perfect_points=perfect and (n==4 and back and 3200 or ({800,1200,1800,2000})[n])*level or 0
    if perfect then sent=sent+10;s.stats.perfect=s.stats.perfect+1 end
    local gained=points+combo_points+perfect_points
    s.score=s.score+gained;s.lines=s.lines+n;s.stats.sent=s.stats.sent+sent
    s.stats.combo=math.max(s.stats.combo,combo);s.stats.chain=math.max(s.stats.chain,s.chain)
    emit(string.format('lock %d %s %s %d %d keys %d %s drop %d lines %d sent %d +%d total %d',s.pieces,kind,states[p[1]+1],p[2],p[3],s.keys,shortest and tostring(#shortest.keys) or '-',s.drop,n,sent,gained,s.score))
    if shortest and s.keys>#shortest.keys then
        s.stats.faults=s.stats.faults+1
        emit('finesse '..(#shortest.keys>0 and table.concat(shortest.keys,' ') or 'none'))
    end
    if name~='' then
        s.stats.clears[name]=s.stats.clears[name]+1
        local line='clear '..name..' '..points
        if back then line=line..' b2b' end
        if combo>=1 then line=line..' combo '..combo..' '..combo_points end
        if perfect then line=line..' perfect '..perfect_points end
        emit(line)
    end
    local next_level=s.initial_level+math.floor(s.lines/10)
    if next_level>level then s.level=next_level;emit('level '..s.level) end
    local lock_out=true
    for _,b in ipairs(old_cells) do if b[2]<21 then lock_out=false break end end
    if lock_out then self:over('lock out') end
    local cancelled=math.min(sent,sum(s.pending))
    local remaining=cancelled
    while remaining>0 do
        local n1=math.min(remaining,s.pending[1])
        remaining=remaining-n1;s.pending[1]=s.pending[1]-n1
        if s.pending[1]==0 then table.remove(s.pending,1) end
    end
    if cancelled>0 then s.stats.cancelled=s.stats.cancelled+cancelled;emit('cancel '..cancelled..' pending '..sum(s.pending)) end
    if n==0 then
        local risen=0
        while #s.pending>0 and risen<8 do
            local count=math.min(s.pending[1],8-risen)
            s.random=seed_step(s.random)
            local hole=s.random%10+1
            self:insert_garbage(count,hole)
            s.stats.received=s.stats.received+count;risen=risen+count;s.pending[1]=s.pending[1]-count
            if s.pending[1]==0 then table.remove(s.pending,1) end
            emit('rise '..count..' hole '..hole..' pending '..sum(s.pending))
        end
    end
    s.used_hold=false
    self:spawn_piece(self:next_piece())
    self.start=clone(s)
end
function Game:candidates(kind,start,prefix)
    local s=self.s
    local result={}
    local seen={}
    for _,turns in ipairs({{}, {'CW'}, {'CW','CW'}, {'CCW'}}) do
        local p=start
        local valid=true
        for _,turn in ipairs(turns) do
            local q=move(s.board,kind,p,turn)
            if not q then valid=false break end
            p=q
        end
        if valid then
            local function add(q,shifts)
                local landed=landing(s.board,kind,q)
                local indexes={}
                for _,b in ipairs(cells(kind,landed)) do indexes[#indexes+1]=(b[2]-1)*10+b[1]-1 end
                table.sort(indexes)
                local key=table.concat(indexes,',')
                if seen[key] then return end
                seen[key]=true
                local board,n=placed(s.board,kind,landed)
                local keys={}
                for _,part in ipairs({prefix,turns,shifts,{'HD'}}) do for _,name in ipairs(part) do keys[#keys+1]=name end end
                result[#result+1]={value=evaluate(board,n).value,kind=kind,keys=keys}
            end
            add(p,{})
            for _,direction in ipairs({'L','R'}) do
                local q=p
                local shifts={}
                while true do
                    local nextp=move(s.board,kind,q,direction)
                    if not nextp then break end
                    q=nextp;shifts[#shifts+1]=direction
                    add(q,shifts)
                end
            end
        end
    end
    return result
end
function Game:ranked()
    local s=self.s
    local result=self:candidates(s.kind,s.position,{})
    local held=s.hold or s.queue[1]
    if not s.used_hold and fits(s.board,held,spawn(held)) then
        for _,c in ipairs(self:candidates(held,spawn(held),{'HOLD'})) do result[#result+1]=c end
    end
    for i,c in ipairs(result) do c.order=i end
    table.sort(result,function(a,b) if a.value==b.value then return a.order<b.order else return a.value>b.value end end)
    return result
end
function Game:spins()
    local s=self.s
    if s.kind~='T' then emit('spins 0') return end
    local found={}
    for _,route in ipairs(routes(s.board,s.kind,s.position)) do
        for _,turn in ipairs({'CW','CCW'}) do
            local p,test=move(s.board,'T',route.position,turn)
            if p and not move(s.board,'T',p,'SD') then
                local spin=tspin(s.board,p,test)
                local key=pkey(p)
                if spin~='' and (not found[key] or spin=='full') then found[key]={position=p,spin=spin} end
            end
        end
    end
    local candidates={}
    for _,candidate in pairs(found) do candidates[#candidates+1]=candidate end
    table.sort(candidates,function(a,b)
        local x,y=a.position,b.position
        if x[3]~=y[3] then return x[3]<y[3] end
        if x[2]~=y[2] then return x[2]<y[2] end
        return x[1]<y[1]
    end)
    for _,c in ipairs(candidates) do
        local p=c.position
        local _,lines=placed(s.board,'T',p)
        local name=clear_info(c.spin,lines)
        emit('spin '..states[p[1]+1]..' '..p[2]..' '..p[3]..' '..name)
    end
    emit('spins '..#candidates)
end
function Game:summary()
    local s=self.s
    local a=s.stats
    local c=a.clears
    local function ratio(x,y)
        local q=y==0 and 0 or math.floor(100*x/y)
        return string.format('%d.%02d',math.floor(q/100),q%100)
    end
    emit(string.format('summary game %d score %d level %d lines %d pieces %d',self.number,s.score,s.level,s.lines,s.pieces))
    emit(string.format('clears single %d double %d triple %d tetris %d perfect %d',c.SINGLE,c.DOUBLE,c.TRIPLE,c.TETRIS,a.perfect))
    emit(string.format('tspins mini %d mini_single %d mini_double %d zero %d single %d double %d triple %d',c.TSPIN_MINI,c.TSPIN_MINI_SINGLE,c.TSPIN_MINI_DOUBLE,c.TSPIN,c.TSPIN_SINGLE,c.TSPIN_DOUBLE,c.TSPIN_TRIPLE))
    local piece_counts={}
    for _,k in ipairs(kinds) do piece_counts[#piece_counts+1]=k..' '..a.kinds[k] end
    emit('pieces '..table.concat(piece_counts,' '))
    emit(string.format('best combo %d chain %d holds %d drops %d faults %d',a.combo,a.chain,a.holds,a.drops,a.faults))
    emit(string.format('garbage sent %d cancelled %d received %d',a.sent,a.cancelled,a.received))
    emit('rates app '..ratio(a.sent,s.pieces)..' apl '..ratio(a.sent,s.lines)..' kpp '..ratio(a.operations,s.pieces))
end
function Game:command(command,args)
    local s=self.s
    if command=='PRINT' then
        local current,ghost={},{}
        if not s.ended then
            for _,b in ipairs(cells(s.kind,s.position)) do current[b[2]*10+b[1]]=true end
            for _,b in ipairs(cells(s.kind,landing(s.board,s.kind,s.position))) do ghost[b[2]*10+b[1]]=true end
        end
        for r=22,1,-1 do
            local line=string.format('%2d ',r)
            for c=1,10 do
                if s.board[r]&(1<<(c-1))~=0 then line=line..'#'
                elseif current[r*10+c] then line=line..'@'
                elseif ghost[r*10+c] then line=line..'+'
                else line=line..'.' end
            end
            emit(line)
        end
    elseif command=='NEXT' then
        local queue={}
        for i=1,5 do queue[i]=s.queue[i] end
        emit('hold '..(s.hold or '-')..' next '..table.concat(queue))
    elseif command=='PREVIEW' then
        local n=tonumber(args[1])
        local queue=clone(s.queue)
        local random=s.random
        while #queue<n do
            local pieces
            random,pieces=bag(random)
            for _,k in ipairs(pieces) do queue[#queue+1]=k end
        end
        local list={}
        for i=1,n do list[i]=queue[i] end
        emit('preview '..table.concat(list))
    elseif command=='STATUS' then
        emit('score '..s.score..' level '..s.level..' lines '..s.lines..' pieces '..s.pieces)
        local piece=s.ended and '-' or s.kind..' '..states[s.position[1]+1]..' '..s.position[2]..' '..s.position[3]
        emit('piece '..piece..' streak '..s.streak..' chain '..s.chain..' pending '..sum(s.pending))
    elseif command=='ANALYZE' then
        local e=evaluate(s.board,0)
        emit('heights '..table.concat(e.heights,' '))
        emit('holes '..e.holes..' bumpiness '..e.bumpiness..' value '..e.value)
    elseif command=='ROW' then
        local r=tonumber(args[1])
        local pattern=args[2]
        for _,b in ipairs(cells(s.kind,s.position)) do
            if b[2]==r and pattern:sub(b[1],b[1])=='#' then emit('ERROR overlap') return end
        end
        local row=0
        for i=1,10 do if pattern:sub(i,i)=='#' then row=row|(1<<(i-1)) end end
        s.board[r]=row
        emit('OK')
    elseif command=='GARBAGE' then
        local n,h=tonumber(args[1]),tonumber(args[2])
        self:insert_garbage(n,h)
        for j=0,n do
            local p={s.position[1],s.position[2],s.position[3]+j}
            if fits(s.board,s.kind,p) then s.position=p;emit('OK') return end
        end
        self:over('top out')
    elseif command=='ATTACK' then
        s.pending[#s.pending+1]=tonumber(args[1])
        emit('pending '..sum(s.pending))
    elseif command=='TICK' then
        for i=1,tonumber(args[1]) do self:tick() end
    elseif command=='UNDO' then
        if #self.history==0 then emit('ERROR nothing to undo')
        else
            self.s=table.remove(self.history)
            self.start=clone(self.s)
            emit('undo '..self.s.pieces..' '..self.s.kind)
        end
    elseif command=='SAVE' then
        self.saves[args[1]]={state=clone(s),history=clone(self.history),start=clone(self.start)}
        emit('OK')
    elseif command=='LOAD' then
        local saved=self.saves[args[1]]
        if not saved then emit('ERROR unknown save')
        else
            self.s=clone(saved.state);self.history=clone(saved.history);self.start=clone(saved.start)
            emit('load '..self.s.pieces..' '..self.s.kind)
        end
    elseif command=='SPINS' then self:spins()
    elseif command=='HINT' then
        local ranked=self:ranked()
        for i=1,math.min(tonumber(args[1]),#ranked) do
            local c=ranked[i]
            emit('hint '..i..' '..c.kind..' '..table.concat(c.keys,' ')..' value '..c.value)
        end
    elseif command=='AUTO' then
        for i=1,tonumber(args[1]) do
            local c=self:ranked()[1]
            emit('auto '..c.kind..' '..table.concat(c.keys,' '))
            for _,op in ipairs(c.keys) do self:operation(op) end
        end
    end
end
local function valid_arguments(command,args)
    local function valid_number(text,min,max)
        if not text or not text:match('^%d+$') or (#text>1 and text:sub(1,1)=='0') then return false end
        local n=tonumber(text)
        return n>=min and n<=max
    end
    if command=='NEW' then return #args==2 and valid_number(args[1],1,2147483646) and valid_number(args[2],1,15) end
    if command=='ROW' then
        return #args==2 and valid_number(args[1],1,22) and #args[2]==10 and args[2]:match('^[#%.]+$')~=nil and args[2]:find('%.')~=nil
    end
    if command=='GARBAGE' then return #args==2 and valid_number(args[1],1,10) and valid_number(args[2],1,10) end
    if command=='SAVE' or command=='LOAD' then return #args==1 and #args[1]>=1 and #args[1]<=8 and args[1]:match('^[a-z]+$')~=nil end
    local limits={PREVIEW=14,ATTACK=20,TICK=1000,HINT=10,AUTO=50}
    if limits[command] then return #args==1 and valid_number(args[1],1,limits[command]) end
    return #args==0
end
local game=nil
local serial=0
local n=tonumber(io.read('*l'))
for i=1,n do
    local line=io.read('*l')
    local words={}
    for word in line:gmatch('[^ ]+') do words[#words+1]=word end
    local command=table.remove(words,1)
    local args=words
    local ok,err=pcall(function()
        if member(command_names,command) then
            if not valid_arguments(command,args) then emit('ERROR bad arguments')
            elseif command=='NEW' then
                if game and not game.s.ended then emit('game stopped');game:summary() end
                serial=serial+1
                emit('game '..serial..' seed '..tonumber(args[1])..' level '..tonumber(args[2]))
                game=Game.new(serial,tonumber(args[1]),tonumber(args[2]))
            elseif not game then emit('ERROR no game')
            elseif game.s.ended and not member(after_end,command) then emit('ERROR game over')
            else game:command(command,args) end
        else
            local opwords={command}
            for _,word in ipairs(args) do opwords[#opwords+1]=word end
            local bad=nil
            for _,word in ipairs(opwords) do if not member(operation_names,word) then bad=word break end end
            if bad then emit('ERROR unknown '..bad)
            elseif not game then emit('ERROR no game')
            elseif game.s.ended then emit('ERROR game over')
            else for _,op in ipairs(opwords) do game:operation(op) end end
        end
    end)
    if not ok and err~='game over' then error(err) end
end
if game and not game.s.ended then emit('game stopped');game:summary() end
io.write(table.concat(output,'\n'),'\n')
