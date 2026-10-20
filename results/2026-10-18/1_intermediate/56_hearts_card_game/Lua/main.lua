local seats, suits, ranks = 'NESW', 'CDSH', '23456789TJQKA'
local directions = {L='LEFT', R='RIGHT', A='ACROSS', H='HOLD'}
local defaults = {TARGET=100, LIMIT=100, MOON='ADD', JACK='OFF', QSBREAK='OFF', BLOOD='OFF', PASS='LRAH'}
local ruleOrder = {'TARGET','LIMIT','MOON','JACK','QSBREAK','BLOOD','PASS'}
local QS, KS, AS, JD = 36, 37, 38, 22
local function copy(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return setmetatable(result, getmetatable(value))
end
local function fail(reason) error({reason=reason}, 0) end
local function seatText(seat) return seats:sub(seat+1,seat+1) end
local function suit(card) return card // 13 end
local function cardText(card) return ranks:sub(card%13+1,card%13+1)..suits:sub(suit(card)+1,suit(card)+1) end
local function contains(list, value)
    for _, item in ipairs(list) do if item == value then return true end end
    return false
end
local function filter(list, predicate)
    local result = {}
    for _, value in ipairs(list) do if predicate(value) then result[#result+1] = value end end
    return result
end
local function append(target, source)
    for _, value in ipairs(source) do target[#target+1] = value end
end
local function cardsText(cards)
    local sorted = copy(cards)
    table.sort(sorted)
    local result = {}
    for _, card in ipairs(sorted) do result[#result+1] = cardText(card) end
    return #result == 0 and '-' or table.concat(result,' ')
end
local function seatValue(word)
    local position = seats:find(word,1,true)
    if #word ~= 1 or not position then fail('bad seat '..word) end
    return position-1
end
local function cardValue(word)
    local r, s = ranks:find(word:sub(1,1),1,true), suits:find(word:sub(2,2),1,true)
    if #word ~= 2 or not r or not s then fail('bad card '..word) end
    return (s-1)*13+r-1
end
local function bounded(word, low, high)
    local value = tonumber(word)
    if not value or value < low or value > high then fail('bad value '..word) end
    return value
end
local function ordered(cards, high)
    local result = copy(cards)
    table.sort(result,function(a,b)
        if a%13 == b%13 then return suit(a)<suit(b) end
        if high then return a%13>b%13 end
        return a%13<b%13
    end)
    return result
end
local function lowest(cards) return ordered(cards,false)[1] end
local function highest(cards) return ordered(cards,true)[1] end
local function penalty(card) return card==QS or suit(card)==3 end
local function pairLine(label, values)
    local result = {label}
    for seat=0,3 do result[#result+1]=seatText(seat); result[#result+1]=tostring(values[seat+1]) end
    return table.concat(result,' ')
end
local function duplicateCards(cards)
    local seen = {}
    for _,card in ipairs(cards) do
        if seen[card] then fail('duplicate card '..cardText(card)) end
        seen[card]=true
    end
end
local Generator = {}
Generator.__index = Generator
function Generator.new(seed) return setmetatable({state=seed},Generator) end
function Generator:shuffle(deck)
    for i=#deck,2,-1 do
        self.state=48271*self.state%2147483647
        local j=self.state%i+1
        deck[i],deck[j]=deck[j],deck[i]
    end
end
local Game = {}
Game.__index = Game
function Game.new(rules,bots,generator)
    return setmetatable({rules=rules,bots=bots,generator=generator,state='between',number=0,
        scores={0,0,0,0},stats={{0,0,0,0},{0,0,0,0},{0,0,0,0},{0,0,0,0}},stacked={},history={},log={},record={}},Game)
end
function Game:point(card)
    if card==QS then return 13 end
    if suit(card)==3 then return 1 end
    return card==JD and self.rules.JACK=='ON' and -10 or 0
end
function Game:points(cards)
    local total=0
    for _,card in ipairs(cards) do total=total+self:point(card) end
    return total
end
function Game:write(level,line)
    self.log[#self.log+1]={level,line}
    if level>0 then self.record[#self.record+1]=line end
end
function Game:deal()
    self.number=self.number+1
    local cycle=self.rules.PASS
    local index=(self.number-1)%#cycle+1
    self.passCode=cycle:sub(index,index)
    self.hands={{},{},{},{}}
    local used,free,deck={},{},{}
    for seat=0,3 do
        self.hands[seat+1]=copy(self.stacked[seat] or {})
        if not self.stacked[seat] then free[#free+1]=seat end
        for _,card in ipairs(self.hands[seat+1]) do used[card]=true end
    end
    for card=0,51 do if not used[card] then deck[#deck+1]=card end end
    self.generator:shuffle(deck)
    for i,card in ipairs(deck) do local hand=self.hands[free[(i-1)%#free+1]+1]; hand[#hand+1]=card end
    self.stacked,self.passes={},{}
    self.taken={{},{},{},{}}
    self.tricks,self.current,self.undo,self.record={},{},{},{}
    self.trickCounts={0,0,0,0}
    self.broken=false
    self:write(1,'hand '..self.number..' pass '..directions[self.passCode])
    for seat=0,3 do self:write(2,seatText(seat)..': '..cardsText(self.hands[seat+1])) end
    if self.passCode=='H' then self:beginPlay() else self.state='passing' end
end
function Game:beginPlay()
    self.state='playing'
    for seat=0,3 do if contains(self.hands[seat+1],0) then self.leader=seat end end
    self:write(2,'lead '..seatText(self.leader))
end
function Game:passCards(seat,cards)
    self.hands[seat+1]=filter(self.hands[seat+1],function(card) return not contains(cards,card) end)
    self.passes[seat]=copy(cards)
    self:write(2,seatText(seat)..' passes '..cardsText(cards))
    for s=0,3 do if not self.passes[s] then return end end
    local offset=({L=1,R=3,A=2})[self.passCode]
    for source=0,3 do append(self.hands[(source+offset)%4+1],self.passes[source]) end
    self:beginPlay()
end
function Game:actor() return (self.leader+#self.current)%4 end
function Game:legal()
    local hand=self.hands[self:actor()+1]
    if #self.current==0 then
        if #self.tricks==0 then return {0} end
        local safe=filter(hand,function(card) return suit(card)~=3 end)
        if not self.broken and #safe>0 then return safe end
        return copy(hand)
    end
    local led=suit(self.current[1][2])
    local followers=filter(hand,function(card) return suit(card)==led end)
    if #followers>0 then return followers end
    if #self.tricks==0 and self.rules.BLOOD=='OFF' then
        local safe=filter(hand,function(card) return not penalty(card) end)
        if #safe>0 then return safe end
    end
    return copy(hand)
end
function Game:choosePass(seat)
    local hand=self.hands[seat+1]
    local low,high=ordered(hand,false),ordered(hand,true)
    local hearts=filter(high,function(card) return suit(card)==3 end)
    local special=filter({QS,KS,AS},function(card) return contains(hand,card) end)
    local strategy=self.bots[seat+1]
    local order={}
    if strategy=='LOW' then order=high
    elseif strategy=='HIGH' then order=low
    elseif strategy=='MOON' then
        append(order,filter(low,function(card) return suit(card)~=3 end))
        append(order,filter(low,function(card) return suit(card)==3 end))
    elseif strategy=='SMART' then
        local protected=contains(hand,QS) and #filter(hand,function(card) return suit(card)==2 end)>=5
        if not protected then append(order,special) end
        local counts={0,0}
        for _,card in ipairs(hand) do if suit(card)<2 then counts[suit(card)+1]=counts[suit(card)+1]+1 end end
        local chosen
        if counts[1]>0 and (counts[2]==0 or counts[1]<=counts[2]) then chosen=0
        elseif counts[2]>0 then chosen=1 end
        if chosen then append(order,filter(high,function(card) return suit(card)==chosen end)) end
        append(order,hearts); append(order,high)
    else append(order,special); append(order,hearts); append(order,high) end
    local result,seen={},{}
    for _,card in ipairs(order) do
        if not seen[card] then result[#result+1]=card; seen[card]=true end
        if #result==3 then break end
    end
    return result
end
function Game:queenPlayed()
    for _,cards in ipairs(self.taken) do if contains(cards,QS) then return true end end
    for _,play in ipairs(self.current) do if play[2]==QS then return true end end
    return false
end
function Game:choosePlay()
    local seat=self:actor()
    local hand,choices=self.hands[seat+1],self:legal()
    local strategy=self.bots[seat+1]
    if strategy=='LOW' then return lowest(choices) end
    if strategy=='HIGH' then return highest(choices) end
    if strategy=='MOON' then
        for other=0,3 do
            if other~=seat and #filter(self.taken[other+1],penalty)>0 then strategy='BASIC' end
        end
    end
    if #self.current==0 then
        if strategy=='SMART' and not self:queenPlayed() and not contains(hand,QS) then
            local small=filter(choices,function(card) return suit(card)==2 and card%13<10 end)
            if #small>0 then return lowest(small) end
        end
        local counts={0,0,0,0}
        for _,card in ipairs(choices) do counts[suit(card)+1]=counts[suit(card)+1]+1 end
        local chosen
        for s=0,3 do
            if counts[s+1]>0 and (not chosen or (strategy=='MOON' and counts[s+1]>counts[chosen+1]) or (strategy~='MOON' and counts[s+1]<counts[chosen+1])) then chosen=s end
        end
        local suited=filter(choices,function(card) return suit(card)==chosen end)
        return strategy=='MOON' and highest(suited) or lowest(suited)
    end
    local led=suit(self.current[1][2])
    if #filter(hand,function(card) return suit(card)==led end)>0 then
        local winning=-1
        for _,play in ipairs(self.current) do if suit(play[2])==led then winning=math.max(winning,play[2]%13) end end
        local lower=filter(choices,function(card) return card%13<winning end)
        if strategy=='MOON' then
            local high=highest(choices)
            return high%13>winning and high or lowest(choices)
        end
        if #lower>0 then return highest(lower) end
        if strategy=='SMART' and #self.current==3 then
            local safe=filter(choices,function(card) return card~=QS end)
            return #safe>0 and highest(safe) or QS
        end
        return lowest(choices)
    end
    if strategy=='MOON' then
        local safe=filter(choices,function(card) return not penalty(card) end)
        return lowest(#safe>0 and safe or choices)
    end
    if contains(choices,QS) then return QS end
    if strategy=='SMART' and not self:queenPlayed() then
        if contains(choices,AS) then return AS end
        if contains(choices,KS) then return KS end
    end
    local hearts=filter(choices,function(card) return suit(card)==3 end)
    return highest(#hearts>0 and hearts or choices)
end
function Game:winner(plays)
    local led=suit(plays[1][2])
    local winner,rank=plays[1][1],-1
    for _,play in ipairs(plays) do
        if suit(play[2])==led and play[2]%13>rank then winner,rank=play[1],play[2]%13 end
    end
    return winner
end
local function playsText(plays)
    local result={}
    for _,play in ipairs(plays) do result[#result+1]=seatText(play[1])..' '..cardText(play[2]) end
    return table.concat(result,' ')
end
function Game:trickLine(plays,number)
    local cards={}
    for _,play in ipairs(plays) do cards[#cards+1]=play[2] end
    return 'trick '..number..': '..playsText(plays)..' -> '..seatText(self:winner(plays))..' '..self:points(cards)
end
function Game:play(card)
    local seat=self:actor()
    local fields=copy({self.hands,self.taken,self.tricks,self.trickCounts,self.current,self.leader,self.broken,self.record})
    self.undo[#self.undo+1]={fields,#self.log,seat,card}
    self.hands[seat+1]=filter(self.hands[seat+1],function(c) return c~=card end)
    self.current[#self.current+1]={seat,card}
    if suit(card)==3 or card==QS and self.rules.QSBREAK=='ON' then self.broken=true end
    if #self.current~=4 then return end
    local winner=self:winner(self.current)
    for _,play in ipairs(self.current) do self.taken[winner+1][#self.taken[winner+1]+1]=play[2] end
    self.trickCounts[winner+1]=self.trickCounts[winner+1]+1
    self.tricks[#self.tricks+1]=self.current
    self:write(2,self:trickLine(self.current,#self.tricks))
    self.current={}; self.leader=winner
    if #self.tricks==13 then self:finishHand() end
end
function Game:undoCard()
    local entry=table.remove(self.undo)
    local f=entry[1]
    self.hands,self.taken,self.tricks,self.trickCounts,self.current,self.leader,self.broken,self.record=f[1],f[2],f[3],f[4],f[5],f[6],f[7],f[8]
    for i=#self.log,entry[2]+1,-1 do self.log[i]=nil end
    return entry[3],entry[4]
end
function Game:claim(seat)
    local remaining={}
    for _,hand in ipairs(self.hands) do append(remaining,hand) end
    local count=13-#self.tricks
    append(self.taken[seat+1],remaining)
    self.trickCounts[seat+1]=self.trickCounts[seat+1]+count
    self.hands={{},{},{},{}}
    self:write(2,'claim '..seatText(seat)..' tricks '..count..' points '..self:points(remaining))
    self:finishHand()
end
function Game:ranking()
    local result={0,1,2,3}
    table.sort(result,function(a,b)
        if self.scores[a+1]==self.scores[b+1] then return a<b end
        return self.scores[a+1]<self.scores[b+1]
    end)
    return result
end
function Game:statsLines()
    local result={}
    for seat=0,3 do
        local s=self.stats[seat+1]
        result[#result+1]='stats '..seatText(seat)..' tricks '..s[1]..' hearts '..s[2]..' queens '..s[3]..' moons '..s[4]
    end
    return result
end
function Game:finishHand()
    local points,shooter={}
    for seat=0,3 do
        points[seat+1]=self:points(self.taken[seat+1])
        if #filter(self.taken[seat+1],penalty)==14 then shooter=seat end
    end
    if shooter then
        points[shooter+1]=points[shooter+1]-26
        local method=self.rules.MOON
        if method=='AUTO' then
            local add,ended={},self.number>=self.rules.LIMIT
            for seat=0,3 do
                add[seat+1]=self.scores[seat+1]+points[seat+1]+(seat==shooter and 0 or 26)
                if add[seat+1]>=self.rules.TARGET then ended=true end
            end
            local winner=0
            for seat=1,3 do if add[seat+1]<add[winner+1] then winner=seat end end
            method=ended and winner~=shooter and 'SUB' or 'ADD'
        end
        if method=='SUB' then points[shooter+1]=points[shooter+1]-26
        else for seat=0,3 do if seat~=shooter then points[seat+1]=points[seat+1]+26 end end end
        self:write(1,'moon '..seatText(shooter)..' '..method)
    end
    local ended=self.number>=self.rules.LIMIT
    for seat=0,3 do
        local index=seat+1
        self.scores[index]=self.scores[index]+points[index]
        if self.scores[index]>=self.rules.TARGET then ended=true end
        local s=self.stats[index]
        s[1]=s[1]+self.trickCounts[index]
        s[2]=s[2]+#filter(self.taken[index],function(card) return suit(card)==3 end)
        s[3]=s[3]+(contains(self.taken[index],QS) and 1 or 0)
        s[4]=s[4]+(shooter==seat and 1 or 0)
    end
    self:write(1,pairLine('points',points)); self:write(1,pairLine('scores',self.scores))
    self.history[#self.history+1]={number=self.number,direction=directions[self.passCode],points=points,shooter=shooter,record=copy(self.record)}
    self.state=ended and 'none' or 'between'
    if not ended then return end
    self:write(0,'game over hands '..self.number)
    for rank,seat in ipairs(self:ranking()) do self:write(0,'rank '..rank..' '..seatText(seat)..' '..self.scores[seat+1]) end
    for _,line in ipairs(self:statsLines()) do self:write(0,line) end
end
function Game:autoPass()
    for seat=0,3 do if not self.passes[seat] then self:passCards(seat,self:choosePass(seat)) end end
end
function Game:autoHand()
    if self.state=='passing' then self:autoPass() end
    while self.state=='playing' do self:play(self:choosePlay()) end
end
function Game:autoGame()
    if self.state=='passing' or self.state=='playing' then self:autoHand() end
    while self.state~='none' do self:deal(); self:autoHand() end
end
local Table={}
Table.__index=Table
function Table.new() return setmetatable({rules=copy(defaults),bots={'BASIC','BASIC','BASIC','BASIC'}},Table) end
function Table:active() return self.game and self.game.state~='none' end
function Table:requireState(kind)
    if kind=='game' or kind=='between' then
        if not self:active() then fail('no game') end
        if kind=='between' and self.game.state~='between' then fail('hand in progress') end
    elseif kind=='hand' then
        if not self:active() or (self.game.state~='passing' and self.game.state~='playing') then fail('no hand') end
    elseif not self:active() or self.game.state~=kind then fail('not '..kind) end
end
function Table:ruleValue(name,word)
    if not defaults[name] then fail('unknown rule '..name) end
    if name=='TARGET' or name=='LIMIT' then
        if not word:match('^-?%d+$') then fail('bad value '..word) end
        return bounded(word,1,name=='TARGET' and 1000 or 100)
    end
    local good
    if name=='PASS' then good=#word>=1 and #word<=8 and not word:find('[^LRAH]')
    elseif name=='MOON' then good=contains({'ADD','SUB','AUTO'},word)
    else good=word=='ON' or word=='OFF' end
    if not good then fail('bad value '..word) end
    return word
end
function Table:simulate(command,seed,count)
    local generator=Generator.new(seed)
    if command=='GAME' then
        local game=Game.new(self.rules,self.bots,generator); game:autoGame()
        local output={'game seed '..seed}
        for _,entry in ipairs(game.log) do if entry[1]<=count then output[#output+1]=entry[2] end end
        return output
    end
    local rounds=command=='ROTATE' and 4 or 1
    local places,stats,totals,hands={},{},{0,0,0,0},0
    for i=1,4 do places[i]={0,0,0,0}; stats[i]={0,0,0,0} end
    for rotation=0,rounds-1 do
        local strategies={}
        for seat=0,3 do strategies[(seat+rotation)%4+1]=self.bots[seat+1] end
        for _=1,count do
            local game=Game.new(self.rules,strategies,generator); game:autoGame()
            hands=hands+game.number
            local ranks={}
            for rank,seat in ipairs(game:ranking()) do ranks[seat]=rank end
            for original=0,3 do
                local actual=(original+rotation)%4
                local index=original+1
                places[index][ranks[actual]]=places[index][ranks[actual]]+1
                totals[index]=totals[index]+game.scores[actual+1]
                for k=1,4 do stats[index][k]=stats[index][k]+game.stats[actual+1][k] end
            end
        end
    end
    local games=rounds*count
    local output={command:lower()..' seed '..seed..' games '..games..' hands '..hands}
    for seat=0,3 do
        local index=seat+1
        local cents=100*totals[index]//games
        local average=(cents<0 and '-' or '')..(math.abs(cents)//100)..'.'..string.format('%02d',math.abs(cents)%100)
        local name=seatText(seat)..(command=='ROTATE' and ' '..self.bots[index] or '')
        local s=stats[index]
        output[#output+1]=name..' places '..table.concat(places[index],' ')..' total '..totals[index]..' average '..average..' tricks '..s[1]..' hearts '..s[2]..' queens '..s[3]..' moons '..s[4]
    end
    return output
end
function Table:command(words)
    local command=words[1]
    local args={table.unpack(words,2)}
    local known={'RULE','BOT','SETTINGS','GAME','MATCH','ROTATE','NEW','ABANDON','STACK','DEAL','SHOW','PASS','PLAY','AUTO','UNDO','CLAIM','LEGAL','PREVIEW','SCORE','TAKEN','TRICKS','VOIDS','UNSEEN','STATS','HISTORY','REPLAY'}
    if not contains(known,command) then fail('unknown command '..command) end
    if command=='RULE' then
        local value=self:ruleValue(args[1],args[2])
        if self:active() then fail('game in progress') end
        self.rules[args[1]]=value
        return {'rule '..args[1]..' '..args[2]}
    elseif command=='BOT' then
        local seat=seatValue(args[1])
        if not contains({'BASIC','LOW','HIGH','SMART','MOON'},args[2]) then fail('bad value '..args[2]) end
        self.bots[seat+1]=args[2]
        return {'bot '..args[1]..' '..args[2]}
    elseif command=='SETTINGS' then
        local parts={'rules'}
        for _,name in ipairs(ruleOrder) do parts[#parts+1]=name; parts[#parts+1]=tostring(self.rules[name]) end
        return {table.concat(parts,' '),pairLine('bots',self.bots)}
    elseif command=='GAME' or command=='MATCH' or command=='ROTATE' then
        local seed=bounded(args[1],1,2147483646)
        local range=({GAME={0,2},MATCH={1,50},ROTATE={1,10}})[command]
        return self:simulate(command,seed,bounded(args[2],range[1],range[2]))
    elseif command=='NEW' then
        local seed=bounded(args[1],1,2147483646)
        if self:active() then fail('game in progress') end
        self.game=Game.new(self.rules,self.bots,Generator.new(seed))
        return {'new game seed '..seed}
    elseif command=='ABANDON' then self:requireState('game'); self.game=nil; return {'game abandoned'} end
    local seat,cards=nil,{}
    if contains({'STACK','PASS','PLAY','CLAIM'},command) then seat=seatValue(args[1]) end
    if contains({'STACK','PASS','PLAY'},command) then for i=2,#args do cards[#cards+1]=cardValue(args[i]) end end
    if command=='STACK' and #cards~=13 then fail('need 13 cards') end
    if command=='AUTO' and not contains({'PASS','CARD','TRICK','HAND','GAME'},args[1]) then fail('bad value '..args[1]) end
    local kind='playing'
    if command=='STACK' or command=='DEAL' then kind='between'
    elseif command=='SHOW' then kind='hand'
    elseif command=='PASS' then kind='passing'
    elseif contains({'SCORE','STATS','HISTORY','REPLAY'},command) then kind='game'
    elseif command=='AUTO' then kind=({PASS='passing',CARD='playing',TRICK='playing',HAND='hand',GAME='game'})[args[1]] end
    self:requireState(kind)
    local game=self.game
    local before=#game.log
    local output={}
    if command=='STACK' then
        duplicateCards(cards)
        for _,card in ipairs(cards) do for other=0,3 do
            if other~=seat and contains(game.stacked[other] or {},card) then fail(cardText(card)..' stacked for '..seatText(other)) end
        end end
        game.stacked[seat]=copy(cards); return {'stacked '..seatText(seat)}
    elseif command=='DEAL' then game:deal()
    elseif command=='SHOW' then
        for s=0,3 do output[#output+1]=seatText(s)..': '..cardsText(game.hands[s+1]) end
        return output
    elseif command=='PASS' then
        if game.passes[seat] then fail(seatText(seat)..' already passed') end
        duplicateCards(cards)
        for _,card in ipairs(cards) do if not contains(game.hands[seat+1],card) then fail(seatText(seat)..' does not hold '..cardText(card)) end end
        game:passCards(seat,cards)
    elseif command=='PLAY' then
        local card=cards[1]
        if seat~=game:actor() then fail('waiting for '..seatText(game:actor())) end
        if not contains(game.hands[seat+1],card) then fail(seatText(seat)..' does not hold '..cardText(card)) end
        if not contains(game:legal(),card) then
            if #game.current==0 then fail(#game.tricks==0 and 'must lead 2C' or 'hearts not broken') end
            local led=suit(game.current[1][2])
            if #filter(game.hands[seat+1],function(c) return suit(c)==led end)>0 then fail('must follow '..suits:sub(led+1,led+1)) end
            fail('no points on first trick')
        end
        output[#output+1]=seatText(seat)..' plays '..cardText(card); game:play(card)
    elseif command=='AUTO' then
        local mode=args[1]
        if mode=='PASS' then game:autoPass()
        elseif mode=='CARD' then
            local card=game:choosePlay(); output[#output+1]=seatText(game:actor())..' plays '..cardText(card); game:play(card)
        elseif mode=='TRICK' then
            local count=#game.tricks
            while game.state=='playing' and #game.tricks==count do game:play(game:choosePlay()) end
        elseif mode=='HAND' then game:autoHand()
        else game:autoGame() end
    elseif command=='UNDO' then
        if #game.undo==0 then fail('nothing to undo') end
        local s,card=game:undoCard(); return {'undo '..seatText(s)..' '..cardText(card)}
    elseif command=='CLAIM' then
        if seat~=game:actor() then fail('waiting for '..seatText(game:actor())) end
        if #game.current>0 then fail('trick in progress') end
        for _,card in ipairs(game.hands[seat+1]) do for other=0,3 do
            if other~=seat then for _,held in ipairs(game.hands[other+1]) do
                if suit(held)==suit(card) and held%13>card%13 then fail('claim rejected') end
            end end
        end end
        game:claim(seat)
    elseif command=='LEGAL' then return {'legal '..seatText(game:actor())..': '..cardsText(game:legal())..' bot '..cardText(game:choosePlay())}
    elseif command=='PREVIEW' then
        local choices=game:legal(); table.sort(choices)
        for _,card in ipairs(choices) do
            local clone=copy(game); local count=#clone.tricks
            clone:play(card)
            while clone.state=='playing' and #clone.tricks==count do clone:play(clone:choosePlay()) end
            local trick=clone.tricks[#clone.tricks]
            local played={}
            for _,play in ipairs(trick) do played[#played+1]=play[2] end
            output[#output+1]='preview '..cardText(card)..' -> '..seatText(clone:winner(trick))..' '..clone:points(played)
        end
        return output
    elseif command=='SCORE' then
        output={pairLine('scores',game.scores)}
        if game.state=='playing' then
            local values={}
            for i=1,4 do values[i]=game:points(game.taken[i]) end
            output[#output+1]=pairLine('taken',values)
        end
        return output
    elseif command=='TAKEN' then
        for s=0,3 do output[#output+1]=seatText(s)..': '..cardsText(filter(game.taken[s+1],function(card) return game:point(card)~=0 end)) end
        return output
    elseif command=='TRICKS' then
        for i,trick in ipairs(game.tricks) do output[#output+1]=game:trickLine(trick,i) end
        if #game.current>0 then output[#output+1]='current: '..playsText(game.current) end
        return #output>0 and output or {'no tricks'}
    elseif command=='VOIDS' then
        local voids={{},{},{},{}}
        local tricks=copy(game.tricks)
        if #game.current>0 then tricks[#tricks+1]=game.current end
        for _,trick in ipairs(tricks) do
            local led=suit(trick[1][2])
            for _,play in ipairs(trick) do if suit(play[2])~=led then voids[play[1]+1][led]=true end end
        end
        local values={}
        for i=1,4 do
            local text=''
            for s=0,3 do if voids[i][s] then text=text..suits:sub(s+1,s+1) end end
            values[i]=text=='' and '-' or text
        end
        return {pairLine('voids',values)}
    elseif command=='UNSEEN' then
        local seen={}
        for _,card in ipairs(game.hands[game:actor()+1]) do seen[card]=true end
        for _,taken in ipairs(game.taken) do for _,card in ipairs(taken) do seen[card]=true end end
        for _,play in ipairs(game.current) do seen[play[2]]=true end
        local unseen={}
        for card=0,51 do if not seen[card] then unseen[#unseen+1]=card end end
        return {'unseen '..seatText(game:actor())..': '..cardsText(unseen)}
    elseif command=='STATS' then return game:statsLines()
    elseif command=='HISTORY' then
        for _,hand in ipairs(game.history) do
            local line='hand '..hand.number..' pass '..hand.direction..' '..pairLine('points',hand.points)
            if hand.shooter then line=line..' moon '..seatText(hand.shooter) end
            output[#output+1]=line
        end
        return #output>0 and output or {'no hands'}
    elseif command=='REPLAY' then
        local hand=tonumber(args[1])
        if hand<1 or hand>#game.history then fail('bad value '..args[1]) end
        return copy(game.history[hand].record)
    end
    for i=before+1,#game.log do output[#output+1]=game.log[i][2] end
    return output
end
local tableState=Table.new()
local count=tonumber(io.read())
for _=1,count do
    local words={}
    for word in io.read():gmatch('%S+') do words[#words+1]=word end
    local ok,result=pcall(function() return tableState:command(words) end)
    if ok then for _,line in ipairs(result) do io.write(line,'\n') end
    elseif type(result)=='table' and result.reason then io.write('error: ',result.reason,'\n')
    else error(result) end
end
