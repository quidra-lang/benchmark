local M={}
function M.is_line(text) return #text>0 and not text:find('[^0-9 ]') end
function M.parse(text)
    if text=='0' then return {} end
    if text=='' or text:sub(1,1)==' ' or text:sub(-1)==' ' or text:find('  ',1,true) then return nil end
    local clue={}
    for token in text:gmatch('[^ ]+') do if #token>2 or token:sub(1,1)=='0' or not token:match('^[0-9]+$') then return nil end; clue[#clue+1]=tonumber(token) end
    return clue
end
function M.run(cells)
    local clue,run={},0
    for _,cell in ipairs(cells) do if cell==1 then run=run+1 elseif run>0 then clue[#clue+1]=run; run=0 end end
    if run>0 then clue[#clue+1]=run end
    return clue
end
function M.text(clue,separator)
    if #clue==0 then return '0' end
    local parts={}; for i,n in ipairs(clue) do parts[i]=tostring(n) end; return table.concat(parts,separator)
end
function M.span(clue) local total=#clue-1; for _,n in ipairs(clue) do total=total+n end; return total end
function M.equal(a,b) if #a~=#b then return false end; for i,n in ipairs(a) do if n~=b[i] then return false end end; return true end
return M
