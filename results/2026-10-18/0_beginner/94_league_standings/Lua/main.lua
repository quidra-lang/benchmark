local teams = {"Lions","Tigers","Eagles","Sharks","Wolves","Bears"}
local records = {}
for _,team in ipairs(teams) do records[team] = {played=0,wins=0,draws=0,losses=0,gf=0,ga=0,points=0} end
local matches = {"Lions 0-3 Bears","Tigers 2-2 Wolves","Eagles 4-0 Sharks","Bears 0-1 Sharks","Wolves 2-1 Eagles","Lions 0-1 Tigers","Tigers 3-3 Bears","Eagles 2-2 Lions","Sharks 2-2 Wolves","Bears 3-1 Wolves","Lions 2-0 Sharks","Tigers 2-1 Eagles","Eagles 1-0 Bears","Sharks 2-0 Tigers","Wolves 2-1 Lions"}
for _,match in ipairs(matches) do
    local home,h,a,away = match:match("(%a+) (%d+)%-(%d+) (%a+)")
    h,a = tonumber(h),tonumber(a)
    for _,side in ipairs({{home,h,a},{away,a,h}}) do
        local record = records[side[1]]
        local gf,ga = side[2],side[3]
        record.played = record.played+1
        record.gf,record.ga = record.gf+gf,record.ga+ga
        if gf > ga then
            record.wins = record.wins+1
            record.points = record.points+3
        elseif gf == ga then
            record.draws = record.draws+1
            record.points = record.points+1
        else
            record.losses = record.losses+1
        end
    end
end
table.sort(teams,function(a,b)
    local x,y = records[a],records[b]
    if x.points ~= y.points then return x.points > y.points end
    if x.gf-x.ga ~= y.gf-y.ga then return x.gf-x.ga > y.gf-y.ga end
    if x.gf ~= y.gf then return x.gf > y.gf end
    return a < b
end)
for position,team in ipairs(teams) do
    local r = records[team]
    local difference = r.gf-r.ga
    local signed = difference > 0 and "+"..difference or tostring(difference)
    io.write(string.format("%d. %s P=%d W=%d D=%d L=%d GF=%d GA=%d GD=%s Pts=%d\n",position,team,r.played,r.wins,r.draws,r.losses,r.gf,r.ga,signed,r.points))
end
