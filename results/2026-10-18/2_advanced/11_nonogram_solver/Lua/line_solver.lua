local M={UNKNOWN=0,FILLED=1,EMPTY=2}
local function fit_table(cells,clue)
    local n,k=#cells,#clue; local empties={[0]=0}; local table_={}
    for i,c in ipairs(cells) do empties[i]=empties[i-1]+(c==M.EMPTY and 1 or 0) end
    for i=0,n do table_[i]={}; for j=0,k do table_[i][j]=false end end
    table_[0][0]=true
    for finish=1,n do for count=0,k do
        local fits=cells[finish]~=M.FILLED and table_[finish-1][count]
        if not fits and count>0 then
            local start=finish-clue[count]
            if start>=0 and empties[finish]==empties[start] then
                if start==0 then fits=count==1 else fits=cells[start]~=M.FILLED and table_[start-1][count-1] end
            end
        end
        table_[finish][count]=fits
    end end
    return table_
end
local function placements(cells,clue)
    local reversed,back={},{}
    for i=#cells,1,-1 do reversed[#reversed+1]=cells[i] end
    for i=#clue,1,-1 do back[#back+1]=clue[i] end
    return {cells=cells,clue=clue,before=fit_table(cells,clue),after=fit_table(reversed,back)}
end
local function starts(p,block)
    local result={}; local n,length=#p.cells,p.clue[block]
    for start=0,n-length do
        local finish=start+length; local possible=true
        for i=start+1,finish do if p.cells[i]==M.EMPTY then possible=false; break end end
        if possible then
            local left=block==1
            if start>0 then left=p.cells[start]~=M.FILLED and p.before[start-1][block-1] end
            local rest=#p.clue-block; local right=rest==0
            if finish<n then right=p.cells[finish+1]~=M.FILLED and p.after[n-finish-1][rest] end
            if left and right then result[#result+1]=start end
        end
    end
    return result
end
function M.has_placement(cells,clue) local p=placements(cells,clue); return p.before[#cells][#clue] end
function M.solve(cells,clue,precise)
    local p=placements(cells,clue)
    if not p.before[#cells][#clue] then return nil end
    local solved,fillable,covered={},{},{}
    for i,c in ipairs(cells) do solved[i]=c; fillable[i]=false; covered[i]=false end
    for block,length in ipairs(clue) do
        local positions=starts(p,block)
        if precise then for _,start in ipairs(positions) do for i=start+1,start+length do fillable[i]=true end end
        else
            local low,high=positions[1],positions[#positions]
            for i=high+1,low+length do if solved[i]==M.UNKNOWN then solved[i]=M.FILLED end end
            for i=low+1,high+length do covered[i]=true end
        end
    end
    for i,c in ipairs(cells) do
        if c==M.UNKNOWN then
            if precise then
                local emptiable=false
                for k=0,#clue do if p.before[i-1][k] and p.after[#cells-i][#clue-k] then emptiable=true; break end end
                if fillable[i] and not emptiable then solved[i]=M.FILLED elseif emptiable and not fillable[i] then solved[i]=M.EMPTY end
            elseif solved[i]==M.UNKNOWN and not covered[i] then solved[i]=M.EMPTY end
        end
    end
    return solved
end
return M
