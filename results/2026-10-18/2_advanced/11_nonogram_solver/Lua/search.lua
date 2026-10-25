local Solver=require('line_solver')
local Propagation=require('propagation')
local M={}
function M.cell(grid)
    local rows,columns={},{}
    for c=1,#grid[1] do columns[c]=0 end
    for r,row in ipairs(grid) do rows[r]=0; for c,state in ipairs(row) do if state==Solver.UNKNOWN then rows[r]=rows[r]+1; columns[c]=columns[c]+1 end end end
    local best_r,best_c,score
    for r,row in ipairs(grid) do for c,state in ipairs(row) do if state==Solver.UNKNOWN and (not best_r or rows[r]+columns[c]<score) then best_r,best_c,score=r,c,rows[r]+columns[c] end end end
    return best_r,best_c
end
local Search={}
Search.__index=Search
function M.new(rows,columns) return setmetatable({rows=rows,columns=columns,guesses={},solutions={},max_depth=0,backtracks=0,line_solves=0},Search) end
function Search:run(grid,depth)
    local r,c=M.cell(grid)
    for _,value in ipairs({Solver.FILLED,Solver.EMPTY}) do
        local child=Propagation.clone(grid); child[r][c]=value; local row_marks,column_marks={},{}; row_marks[r]=true; column_marks[c]=true
        local p=Propagation.run(child,self.rows,self.columns,true,row_marks,column_marks); local known=Propagation.known(child); local result='open'
        if p.conflict then result='contradiction at='..Propagation.label(p.conflict.is_row,p.conflict.index); self.backtracks=self.backtracks+1
        elseif known==#self.rows*#self.columns then self.solutions[#self.solutions+1]=child; result='solution'..#self.solutions end
        self.max_depth=math.max(self.max_depth,depth); self.line_solves=self.line_solves+#p.steps
        self.guesses[#self.guesses+1]={number=#self.guesses+1,depth=depth,row=r,column=c,value=value,solves=#p.steps,known=known,result=result}
        if result=='open' then if self:run(child,depth+1) then return true end elseif #self.solutions==2 then return true end
    end
    return false
end
return M
