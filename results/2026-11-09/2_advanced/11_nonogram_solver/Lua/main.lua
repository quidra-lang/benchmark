local Clues=require('clues')
local Solver=require('line_solver')
local Propagation=require('propagation')
local Search=require('search')
local Render=require('render')
local fmt=string.format
local function extend(a,b) for _,value in ipairs(b) do a[#a+1]=value end end
local function read_blocks(path)
    local blocks,block={},nil
    for line in io.lines(path) do
        if not block then if line~='' and line:sub(1,1)~='#' then block={line} end
        elseif line=='END' then blocks[#blocks+1]=block; block=nil else block[#block+1]=line end
    end
    return blocks
end
local function tokens(text) local parts={}; for token in text:gmatch('[^ ]+') do parts[#parts+1]=token end; return parts end
local function valid_name(name) return #name>=1 and #name<=20 and not name:find('[^a-z0-9_]') end
local function state_grid(lines)
    local grid={}
    for r,line in ipairs(lines) do grid[r]={}; for c=1,#line do grid[r][c]=Render.state(line:sub(c,c)) end end
    return grid
end
local function parse_puzzle(block)
    local size=tokens(block[2]); local p={name=block[1]:sub(8),width=tonumber(size[2]),height=tonumber(size[3]),raw_rows={},raw_columns={},givens={},answer_result='-'}
    local at=4
    while block[at]~='COLUMNS' do p.raw_rows[#p.raw_rows+1]=block[at]; at=at+1 end
    at=at+1
    while at<=#block and Clues.is_line(block[at]) do p.raw_columns[#p.raw_columns+1]=block[at]; at=at+1 end
    while at<=#block and block[at]:sub(1,6)=='GIVEN ' do local fields=tokens(block[at]); p.givens[#p.givens+1]={row=tonumber(fields[2]),column=tonumber(fields[3]),state=Render.state(fields[4])}; at=at+1 end
    if at<=#block then p.answer_lines={}; for i=at+1,#block do p.answer_lines[#p.answer_lines+1]=block[i] end end
    return p
end
local function validate(p,seen)
    if not valid_name(p.name) then return 'bad name' end
    if seen[p.name] then return 'duplicate name' end
    if p.width<1 or p.width>30 or p.height<1 or p.height>30 then return 'bad size' end
    if #p.raw_rows~=p.height then return fmt('row count %d expected %d',#p.raw_rows,p.height) end
    if #p.raw_columns~=p.width then return fmt('column count %d expected %d',#p.raw_columns,p.width) end
    local totals={0,0}
    for kind,texts in ipairs({p.raw_rows,p.raw_columns}) do
        local label,length=kind==1 and 'row' or 'column',kind==1 and p.width or p.height; local clues={}
        for i,text in ipairs(texts) do
            local clue=Clues.parse(text)
            if not clue then return fmt('bad clue %s %d',label,i) end
            if Clues.span(clue)>length then return fmt('%s %d too long',label,i) end
            clues[#clues+1]=clue; for _,n in ipairs(clue) do totals[kind]=totals[kind]+n end
        end
        if kind==1 then p.rows=clues else p.columns=clues end
    end
    if totals[1]~=totals[2] then return fmt('total mismatch rows=%d columns=%d',totals[1],totals[2]) end
    local occupied={}
    for k,g in ipairs(p.givens) do
        if g.row<1 or g.row>p.height or g.column<1 or g.column>p.width or g.state==Solver.UNKNOWN then return fmt('bad given %d',k) end
        local key=g.row..','..g.column
        if occupied[key] then return fmt('duplicate given %d',k) end
        occupied[key]=true
    end
    if p.answer_lines then
        if #p.answer_lines~=p.height then return 'bad answer' end
        for _,line in ipairs(p.answer_lines) do if #line~=p.width or line:find('[^#.?]') then return 'bad answer' end end
        p.answer=state_grid(p.answer_lines)
    end
end
local function logical(rows,columns,givens,precise)
    local grid,row_marks,column_marks={},{},{}
    for r=1,#rows do grid[r]={}; row_marks[r]=true; for c=1,#columns do grid[r][c]=Solver.UNKNOWN end end
    for c=1,#columns do column_marks[c]=true end
    for _,g in ipairs(givens) do grid[g.row][g.column]=g.state end
    local propagation=Propagation.run(grid,rows,columns,precise,row_marks,column_marks); local result='stuck'
    if propagation.conflict then local step=propagation.conflict; result='contradiction at='..Propagation.label(step.is_row,step.index)
    elseif Propagation.known(grid)==#rows*#columns then result='solved' end
    return {grid=grid,propagation=propagation,result=result}
end
local function analyze(rows,columns,givens)
    local a={simple=logical(rows,columns,givens,false),logic=logical(rows,columns,givens,true),solutions={},difficulty='-',guesses=0,max_depth=0}
    a.line_solves=#a.logic.propagation.steps
    if a.logic.propagation.conflict then a.status='contradiction'
    elseif a.logic.result=='solved' then a.status='unique'; a.solutions={a.logic.grid}; a.difficulty=a.simple.result=='solved' and 'easy' or 'medium'
    else
        a.search=Search.new(rows,columns); a.search:run(a.logic.grid,1); a.solutions=a.search.solutions; a.status=({'none','unique','multiple'})[#a.solutions+1]
        if a.status=='unique' then a.difficulty='hard' end
        a.line_solves=a.line_solves+a.search.line_solves; a.guesses=#a.search.guesses; a.max_depth=a.search.max_depth
    end
    return a
end
local function clue_stats(rows,columns)
    local row_blocks,column_blocks,filled,largest,fixed=0,0,0,0,0
    for kind,clues in ipairs({rows,columns}) do
        local length=kind==1 and #columns or #rows
        for _,clue in ipairs(clues) do
            if kind==1 then row_blocks=row_blocks+#clue; for _,n in ipairs(clue) do filled=filled+n end else column_blocks=column_blocks+#clue end
            for _,n in ipairs(clue) do largest=math.max(largest,n) end
            if #clue==0 or Clues.span(clue)==length then fixed=fixed+1 end
        end
    end
    return fmt('row_blocks=%d column_blocks=%d filled=%d max_block=%d fixed_lines=%d',row_blocks,column_blocks,filled,largest,fixed)
end
local function features(grid)
    local h,w=#grid,#grid[1]; local filled,components,largest=0,0,0; local min_r,min_c,max_r,max_c=h,w,0,0; local visited={}; local symmetry={true,true,true}
    for r=1,h do visited[r]={} end
    for r,row in ipairs(grid) do for c,state in ipairs(row) do
        symmetry[1]=symmetry[1] and state==grid[r][w+1-c]; symmetry[2]=symmetry[2] and state==grid[h+1-r][c]; symmetry[3]=symmetry[3] and state==grid[h+1-r][w+1-c]
        if state==Solver.FILLED then
            filled=filled+1; min_r=math.min(min_r,r); min_c=math.min(min_c,c); max_r=math.max(max_r,r); max_c=math.max(max_c,c)
            if not visited[r][c] then
                components=components+1; local queue={{r,c}}; visited[r][c]=true; local head=1
                while head<=#queue do
                    local cell=queue[head]; head=head+1
                    for _,offset in ipairs({{-1,0},{1,0},{0,-1},{0,1}}) do local rr,cc=cell[1]+offset[1],cell[2]+offset[2]; if rr>=1 and rr<=h and cc>=1 and cc<=w and not visited[rr][cc] and grid[rr][cc]==Solver.FILLED then visited[rr][cc]=true; queue[#queue+1]={rr,cc} end end
                end
                largest=math.max(largest,#queue)
            end
        end
    end end
    local box=filled>0 and fmt('%d,%d,%d,%d',min_r,min_c,max_r,max_c) or '-'; local names={}
    for i,name in ipairs({'lr','ud','rot180'}) do if symmetry[i] then names[#names+1]=name end end
    return fmt('filled=%d components=%d largest=%d bbox=%s symmetry=%s',filled,components,largest,box,#names>0 and table.concat(names,',') or 'none')
end
local function number_list(numbers) if #numbers==0 then return '-' end; local parts={}; for i,n in ipairs(numbers) do parts[i]=tostring(n) end; return table.concat(parts,',') end
local function differing(first,second) local cells={}; for r,row in ipairs(first) do for c,state in ipairs(row) do if state~=second[r][c] then cells[#cells+1]={r,c} end end end; return cells end
local function cell_list(cells) local parts={}; for i,cell in ipairs(cells) do parts[i]=cell[1]..','..cell[2] end; return table.concat(parts,' ') end
local function without(givens,index) local result={}; for i,g in ipairs(givens) do if i~=index then result[#result+1]=g end end; return result end
local function grade(p)
    local answer=p.answer; local row_mismatch,column_mismatch,given_mismatch,occupied={},{},{},{}
    for r,clue in ipairs(p.rows) do if not Solver.has_placement(answer[r],clue) then row_mismatch[#row_mismatch+1]=r end end
    for c,clue in ipairs(p.columns) do if not Solver.has_placement(Propagation.cells(answer,false,c),clue) then column_mismatch[#column_mismatch+1]=c end end
    for k,g in ipairs(p.givens) do occupied[g.row..','..g.column]=true; local state=answer[g.row][g.column]; if state~=Solver.UNKNOWN and state~=g.state then given_mismatch[#given_mismatch+1]=k end end
    local known=Propagation.known(answer); local bad=#row_mismatch+#column_mismatch+#given_mismatch>0; local result=known<p.width*p.height and 'partial' or bad and 'wrong' or 'correct'
    local line=fmt('answer result=%s known=%d rows=%s columns=%s givens=%s',result,known,number_list(row_mismatch),number_list(column_mismatch),number_list(given_mismatch))
    if result=='partial' then
        local extendable='no'
        if not bad then
            local givens={}; extend(givens,p.givens)
            for r,row in ipairs(answer) do for c,state in ipairs(row) do if state~=Solver.UNKNOWN and not occupied[r..','..c] then givens[#givens+1]={row=r,column=c,state=state} end end end
            local a=analyze(p.rows,p.columns,givens); if a.status=='unique' or a.status=='multiple' then extendable='yes' end
        end
        line=line..' extendable='..extendable
    end
    if p.analysis.status=='unique' then local count=0; for r,row in ipairs(answer) do for c,state in ipairs(row) do if state~=Solver.UNKNOWN and state~=p.analysis.solutions[1][r][c] then count=count+1 end end end; line=line..' differs='..count end
    local lines={line}
    for kind,numbers in ipairs({row_mismatch,column_mismatch}) do
        for _,n in ipairs(numbers) do local is_row=kind==1; local clue=is_row and p.rows[n] or p.columns[n]; local cells=Propagation.cells(answer,is_row,n); local suffix=result=='partial' and 'cells='..Render.string(cells) or 'got='..Clues.text(Clues.run(cells),','); lines[#lines+1]=fmt('mismatch %s expected=%s %s',Propagation.label(is_row,n),Clues.text(clue,','),suffix) end
    end
    return result,lines
end
local function puzzle_paragraph(p)
    local lines={'PUZZLE '..p.name}
    if p.error then lines[#lines+1]='error '..p.error; return lines end
    local a=p.analysis
    lines[#lines+1]=fmt('size=%dx%d givens=%d status=%s difficulty=%s',p.width,p.height,#p.givens,a.status,a.difficulty)
    lines[#lines+1]='clues '..clue_stats(p.rows,p.columns)
    lines[#lines+1]=fmt('simple known=%d line_solves=%d result=%s',Propagation.known(a.simple.grid),#a.simple.propagation.steps,a.simple.result)
    lines[#lines+1]=fmt('logic known=%d line_solves=%d result=%s',Propagation.known(a.logic.grid),#a.logic.propagation.steps,a.logic.result)
    local productive,idle,best,at=0,0,0,'-'
    for _,step in ipairs(a.logic.propagation.steps) do if not step.contradiction then if step.gain>0 then productive=productive+1 else idle=idle+1 end; if step.gain>best then best=step.gain; at=Propagation.label(step.is_row,step.index) end end end
    lines[#lines+1]=fmt('steps productive=%d idle=%d best=%d at=%s',productive,idle,best,at)
    if p.width*p.height<=49 then lines[#lines+1]='trace '..Propagation.record(a.logic.propagation) end
    if a.logic.result=='stuck' then
        local remaining={{},{}}
        for kind,n in ipairs({p.height,p.width}) do for i=1,n do local unknown=0; for _,state in ipairs(Propagation.cells(a.logic.grid,kind==1,i)) do if state==Solver.UNKNOWN then unknown=unknown+1 end end; if unknown>0 then remaining[kind][#remaining[kind]+1]=i..':'..unknown end end end
        lines[#lines+1]=fmt('stuck rows=%s columns=%s',table.concat(remaining[1],' '),table.concat(remaining[2],' '))
    end
    if a.status=='contradiction' then local step=a.logic.propagation.conflict; local clue=step.is_row and p.rows[step.index] or p.columns[step.index]; lines[#lines+1]=fmt('conflict line=%s clue=%s cells=%s',Propagation.label(step.is_row,step.index),Clues.text(clue,','),Render.string(Propagation.cells(a.logic.grid,step.is_row,step.index))) end
    if a.search then
        local s=a.search; lines[#lines+1]=fmt('search guesses=%d max_depth=%d backtracks=%d solutions=%d line_solves=%d',#s.guesses,s.max_depth,s.backtracks,#s.solutions,s.line_solves)
        for _,g in ipairs(s.guesses) do lines[#lines+1]=fmt('guess %d depth=%d cell=%d,%d value=%s solves=%d known=%d result=%s',g.number,g.depth,g.row,g.column,Render.char(g.value),g.solves,g.known,g.result) end
    end
    if a.status=='multiple' then local cells=differing(a.solutions[1],a.solutions[2]); lines[#lines+1]=fmt('differ count=%d cells=%s',#cells,cell_list(cells)) end
    local names,grids={},{}
    if a.status=='contradiction' then names={'partial'}; grids={a.logic.grid}
    else
        if a.simple.result=='stuck' then names[#names+1]='simple'; grids[#grids+1]=a.simple.grid end
        if a.logic.result=='stuck' then names[#names+1]='logic'; grids[#grids+1]=a.logic.grid end
        if a.status=='multiple' then extend(names,{'first','second'}); extend(grids,a.solutions) end
    end
    if #names>0 then extend(lines,Render.display(names,grids)) end
    if a.status=='unique' then lines[#lines+1]='sheet'; extend(lines,Render.sheet(p.rows,p.columns,a.solutions[1])); lines[#lines+1]='picture '..features(a.solutions[1]) end
    if #p.givens>0 and a.status~='multiple' then
        local numbers={}
        for k in ipairs(p.givens) do local other=analyze(p.rows,p.columns,without(p.givens,k)); if a.status=='unique' and other.status=='unique' or a.status~='unique' and (other.status=='unique' or other.status=='multiple') then numbers[#numbers+1]=k end end
        lines[#lines+1]='givens '..(a.status=='unique' and 'redundant' or 'blame')..'='..number_list(numbers)
    end
    if p.answer then local result,answer_lines=grade(p); p.answer_result=result; extend(lines,answer_lines) end
    return lines
end
local function join_paragraphs(paragraphs)
    local lines={}
    for _,paragraph in ipairs(paragraphs) do if #lines>0 then lines[#lines+1]='' end; extend(lines,paragraph) end
    return lines
end
local function process_puzzles()
    local puzzles,paragraphs,seen,counts,ranking={},{},{},{},{}; local line_solves,guesses=0,0
    local stats={'puzzle,status,difficulty,width,height,givens,simple_known,logic_known,line_solves,guesses,max_depth,solutions,answer'}
    for _,block in ipairs(read_blocks('input/puzzles.txt')) do
        local p=parse_puzzle(block); p.error=validate(p,seen); seen[p.name]=true; puzzles[#puzzles+1]=p
        if p.error then counts.invalid=(counts.invalid or 0)+1; stats[#stats+1]=p.name..',invalid'..string.rep(',-',11)
        else
            p.analysis=analyze(p.rows,p.columns,p.givens); local a=p.analysis; counts[a.status]=(counts[a.status] or 0)+1; counts[a.difficulty]=(counts[a.difficulty] or 0)+1; line_solves=line_solves+a.line_solves; guesses=guesses+a.guesses
            if a.status=='unique' then ranking[#ranking+1]=p end
        end
        paragraphs[#paragraphs+1]=puzzle_paragraph(p)
        if not p.error then local a=p.analysis; stats[#stats+1]=fmt('%s,%s,%s,%d,%d,%d,%d,%d,%d,%d,%d,%d,%s',p.name,a.status,a.difficulty,p.width,p.height,#p.givens,Propagation.known(a.simple.grid),Propagation.known(a.logic.grid),a.line_solves,a.guesses,a.max_depth,#a.solutions,p.answer_result) end
    end
    local order={easy=1,medium=2,hard=3}
    table.sort(ranking,function(a,b) if order[a.analysis.difficulty]~=order[b.analysis.difficulty] then return order[a.analysis.difficulty]<order[b.analysis.difficulty] end; local x,y=a.analysis.line_solves+25*a.analysis.guesses,b.analysis.line_solves+25*b.analysis.guesses; if x~=y then return x<y end; return a.name<b.name end)
    local ranks={'RANKING'}
    for k,p in ipairs(ranking) do local a=p.analysis; ranks[#ranks+1]=fmt('rank %d %s %s score=%d size=%dx%d',k,p.name,a.difficulty,a.line_solves+25*a.guesses,p.width,p.height) end
    paragraphs[#paragraphs+1]=ranks
    paragraphs[#paragraphs+1]={fmt('SUMMARY puzzles=%d invalid=%d contradiction=%d none=%d unique=%d multiple=%d easy=%d medium=%d hard=%d line_solves=%d guesses=%d',#puzzles,counts.invalid or 0,counts.contradiction or 0,counts.none or 0,counts.unique or 0,counts.multiple or 0,counts.easy or 0,counts.medium or 0,counts.hard or 0,line_solves,guesses)}
    return puzzles,join_paragraphs(paragraphs),stats
end
local function same_clues(p,rows,columns)
    if p.error or p.height~=#rows or p.width~=#columns then return false end
    for i,clue in ipairs(rows) do if not Clues.equal(clue,p.rows[i]) then return false end end
    for i,clue in ipairs(columns) do if not Clues.equal(clue,p.columns[i]) then return false end end
    return true
end
local function process_pictures(puzzles)
    local blocks=read_blocks('input/pictures.txt'); local paragraphs,seen={},{}; local invalid,unique,line_logic,hinted,hints=0,0,0,0,0
    for _,block in ipairs(blocks) do
        local name=block[1]:sub(9); local texts={}; for i=2,#block do texts[#texts+1]=block[i] end
        local reason
        if not valid_name(name) then reason='bad name' elseif seen[name] then reason='duplicate name' elseif #texts<1 or #texts>30 then reason='bad height'
        else for r,line in ipairs(texts) do if #line<1 or #line>30 or #line~=#texts[1] or line:find('[^#.]') then reason='bad row '..r; break end end end
        seen[name]=true
        if reason then invalid=invalid+1; paragraphs[#paragraphs+1]={'# picture '..name..' error '..reason}
        else
            local grid=state_grid(texts); local rows,columns={},{}
            for r,row in ipairs(grid) do rows[r]=Clues.run(row) end
            for c=1,#grid[1] do columns[c]=Clues.run(Propagation.cells(grid,false,c)) end
            local duplicate='-'; for _,p in ipairs(puzzles) do if same_clues(p,rows,columns) then duplicate=p.name; break end end
            local givens={}; local a=analyze(rows,columns,givens)
            if a.status=='unique' then unique=unique+1 end
            if a.difficulty=='easy' or a.difficulty=='medium' then line_logic=line_logic+1 end
            local lines={fmt('# picture %s size=%dx%d %s',name,#columns,#rows,features(grid)),'# clues '..clue_stats(rows,columns)..' duplicate_of='..duplicate,fmt('# plain status=%s difficulty=%s line_solves=%d guesses=%d',a.status,a.difficulty,a.line_solves,a.guesses)}
            while a.status=='multiple' do
                local cell=differing(a.solutions[1],a.solutions[2])[1]; local g={row=cell[1],column=cell[2],state=grid[cell[1]][cell[2]]}; givens[#givens+1]=g; a=analyze(rows,columns,givens); lines[#lines+1]=fmt('# hint %d cell=%d,%d value=%s status=%s',#givens,g.row,g.column,Render.char(g.state),a.status)
            end
            local original={}; extend(original,givens)
            for _,g in ipairs(original) do local index; for k,current in ipairs(givens) do if current.row==g.row and current.column==g.column then index=k; break end end; local trial=without(givens,index); local other=analyze(rows,columns,trial); if other.status=='unique' then givens=trial; lines[#lines+1]=fmt('# drop cell=%d,%d',g.row,g.column) end end
            a=analyze(rows,columns,givens); local added=0
            while a.difficulty=='hard' do local r,c=Search.cell(a.logic.grid); local g={row=r,column=c,state=grid[r][c]}; givens[#givens+1]=g; a=analyze(rows,columns,givens); added=added+1; lines[#lines+1]=fmt('# logic hint %d cell=%d,%d value=%s difficulty=%s',added,r,c,Render.char(g.state),a.difficulty) end
            if #givens>0 then hinted=hinted+1 end
            hints=hints+#givens; lines[#lines+1]=fmt('# final status=%s difficulty=%s hints=%d line_solves=%d guesses=%d',a.status,a.difficulty,#givens,a.line_solves,a.guesses)
            extend(lines,{'PUZZLE '..name,fmt('SIZE %d %d',#columns,#rows),'ROWS'})
            for _,clue in ipairs(rows) do lines[#lines+1]=Clues.text(clue,' ') end
            lines[#lines+1]='COLUMNS'; for _,clue in ipairs(columns) do lines[#lines+1]=Clues.text(clue,' ') end
            table.sort(givens,function(a,b) if a.row~=b.row then return a.row<b.row end; return a.column<b.column end)
            for _,g in ipairs(givens) do lines[#lines+1]=fmt('GIVEN %d %d %s',g.row,g.column,Render.char(g.state)) end
            lines[#lines+1]='END'; paragraphs[#paragraphs+1]=lines
        end
    end
    paragraphs[#paragraphs+1]={fmt('# SUMMARY pictures=%d invalid=%d unique=%d line_logic=%d hinted=%d hints=%d',#blocks,invalid,unique,line_logic,hinted,hints)}
    return join_paragraphs(paragraphs)
end
local puzzles,solutions,stats=process_puzzles()
local generated=process_pictures(puzzles)
os.execute('mkdir -p output')
for name,lines in pairs({['solutions.txt']=solutions,['stats.csv']=stats,['generated.txt']=generated}) do local file=assert(io.open('output/'..name,'w')); file:write(table.concat(lines,'\n'),'\n'); file:close() end
