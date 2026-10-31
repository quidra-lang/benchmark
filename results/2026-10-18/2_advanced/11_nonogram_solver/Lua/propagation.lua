local Solver=require('line_solver')
local M={}
function M.label(is_row,index) return (is_row and 'R' or 'C')..index end
function M.cells(grid,is_row,index)
    local cells={}
    if is_row then for i,c in ipairs(grid[index]) do cells[i]=c end else for i,row in ipairs(grid) do cells[i]=row[index] end end
    return cells
end
function M.clone(grid) local copy={}; for r in ipairs(grid) do copy[r]=M.cells(grid,true,r) end; return copy end
function M.known(grid) local n=0; for _,row in ipairs(grid) do for _,c in ipairs(row) do if c~=Solver.UNKNOWN then n=n+1 end end end; return n end
function M.record(propagation)
    local parts={}
    for _,step in ipairs(propagation.steps) do local label=M.label(step.is_row,step.index); parts[#parts+1]=label..(step.contradiction and '!' or '+'..step.gain) end
    return table.concat(parts,' ')
end
function M.run(grid,rows,columns,precise,row_marks,column_marks)
    local result={steps={}}
    while true do
        local is_row,index=true,nil
        for i=1,#rows do if row_marks[i] then index=i; break end end
        if not index then is_row=false; for i=1,#columns do if column_marks[i] then index=i; break end end end
        if not index then return result end
        local clue
        if is_row then row_marks[index]=false; clue=rows[index] else column_marks[index]=false; clue=columns[index] end
        local cells=M.cells(grid,is_row,index); local solved=Solver.solve(cells,clue,precise); local step={is_row=is_row,index=index,gain=0}
        result.steps[#result.steps+1]=step
        if not solved then step.contradiction=true; result.conflict=step; return result end
        for position,state in ipairs(solved) do
            if cells[position]==Solver.UNKNOWN and state~=Solver.UNKNOWN then
                step.gain=step.gain+1
                if is_row then grid[index][position]=state; column_marks[position]=true else grid[position][index]=state; row_marks[position]=true end
            end
        end
    end
end
return M
