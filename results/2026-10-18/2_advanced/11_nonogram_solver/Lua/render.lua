local Clues=require('clues')
local M={}
function M.char(state) return ('?#.'):sub(state+1,state+1) end
function M.state(character) return character=='#' and 1 or character=='.' and 2 or 0 end
function M.string(cells) local parts={}; for i,state in ipairs(cells) do parts[i]=M.char(state) end; return table.concat(parts) end
function M.display(names,grids)
    local lines={'grid '..table.concat(names,' ')}
    for r=1,#grids[1] do local parts={}; for i,grid in ipairs(grids) do parts[i]=M.string(grid[r]) end; lines[#lines+1]=table.concat(parts,' | ') end
    return lines
end
function M.sheet(rows,columns,grid)
    local tokens,width,depth,margin={},0,0,0
    for c,clue in ipairs(columns) do tokens[c]={}; for token in Clues.text(clue,' '):gmatch('[^ ]+') do tokens[c][#tokens[c]+1]=token; width=math.max(width,#token+1) end; depth=math.max(depth,#tokens[c]) end
    for _,clue in ipairs(rows) do margin=math.max(margin,#Clues.text(clue,' ')) end
    local lines={}
    for t=1,depth do
        local parts={string.rep(' ',margin)}
        for _,column in ipairs(tokens) do local skipped=depth-#column; local token=t>skipped and column[t-skipped] or ''; parts[#parts+1]=string.rep(' ',width-#token)..token end
        lines[#lines+1]=table.concat(parts):gsub(' +$','')
    end
    for r,clue in ipairs(rows) do local text=Clues.text(clue,' '); local line=string.rep(' ',margin-#text)..text; for _,state in ipairs(grid[r]) do line=line..string.rep(' ',width-1)..M.char(state) end; lines[#lines+1]=line end
    return lines
end
return M
