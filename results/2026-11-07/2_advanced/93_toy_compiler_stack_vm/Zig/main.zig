const std=@import("std");
const l=@import("lexer.zig");
const p=@import("parser.zig");
const semantic=@import("semantic.zig");
const cg=@import("codegen.zig");
const vm=@import("vm.zig");
const rules=[_][]const u8{"const-jump","not-compare","not-jump","invert-branch","thread","jump-next","unreachable"};
fn inRange(n:i64) bool { return n>=-2147483648 and n<=2147483647; }
fn literal(n:*p.Node,value:i64) *p.Node { const out=p.node(.literal,n.position,&.{}); out.typ=n.typ; out.value=value; return out; }
fn foldExpression(n:*p.Node,count:*usize) *p.Node {
    for(n.children) |*child| child.*=foldExpression(child.*,count);
    if(n.kind==.unary and n.children[0].kind==.literal) { const value=if(l.eq(n.op,"-")) -n.children[0].value else @as(i64,@intFromBool(n.children[0].value==0)); if(inRange(value)) { count.*+=1; return literal(n,value); } }
    if(n.kind!=.binary) return n;
    const a=n.children[0]; const b=n.children[1]; const op=n.op;
    if(a.kind==.literal and b.kind==.literal) {
        var result:?i64=null; const x=a.value; const y=b.value;
        if(l.eq(op,"+")) result=x+y else if(l.eq(op,"-")) result=x-y else if(l.eq(op,"*")) result=x*y
        else if(l.eq(op,"/")) { if(y!=0) result=@divTrunc(x,y); }
        else if(l.eq(op,"%")) { if(y!=0) result=@rem(x,y); }
        else result=@intFromBool(if(l.eq(op,"<")) x<y else if(l.eq(op,"<=")) x<=y else if(l.eq(op,">")) x>y else if(l.eq(op,">=")) x>=y else if(l.eq(op,"==")) x==y else if(l.eq(op,"!=")) x!=y else if(l.eq(op,"&&")) x!=0 and y!=0 else x!=0 or y!=0);
        if(result) |value| if(inRange(value)) { count.*+=1; return literal(n,value); };
    }
    if(a.kind==.literal and ((l.eq(op,"&&") and a.value==0) or (l.eq(op,"||") and a.value!=0))) { count.*+=1; return literal(n,a.value); }
    if(a.kind==.literal and ((l.eq(op,"&&") and a.value!=0) or (l.eq(op,"||") and a.value==0) or (l.eq(op,"+") and a.value==0) or (l.eq(op,"*") and a.value==1))) { count.*+=1; return b; }
    if(b.kind==.literal and (((l.eq(op,"+") or l.eq(op,"-")) and b.value==0) or ((l.eq(op,"*") or l.eq(op,"/")) and b.value==1) or (l.eq(op,"&&") and b.value!=0) or (l.eq(op,"||") and b.value==0))) { count.*+=1; return a; }
    return n;
}
fn foldStatement(n:*p.Node,count:*usize) *p.Node {
    switch(n.kind) {
        .declaration=>{ const decl=n.declaration.?; if(decl.initializer) |initializer| decl.initializer=foldExpression(initializer,count); },
        .assignment,.print_stmt,.call_stmt,.return_stmt=>for(n.children) |*child| { child.*=foldExpression(child.*,count); },
        .if_stmt=>{ n.children[0]=foldExpression(n.children[0],count); if(n.children[0].kind==.literal) { count.*+=1; if(n.children[0].value!=0) return foldStatement(n.children[1],count); if(n.children.len==3) return foldStatement(n.children[2],count); return p.node(.empty,n.position,&.{}); } n.children[1]=foldStatement(n.children[1],count); if(n.children.len==3) n.children[2]=foldStatement(n.children[2],count); },
        .while_stmt=>{ n.children[0]=foldExpression(n.children[0],count); if(n.children[0].kind==.literal and n.children[0].value==0) { count.*+=1; return p.node(.empty,n.position,&.{}); } n.children[1]=foldStatement(n.children[1],count); },
        .for_stmt=>{ n.children[0]=foldStatement(n.children[0],count); if(n.children[1].kind!=.empty) n.children[1]=foldExpression(n.children[1],count); n.children[2]=foldStatement(n.children[2],count); n.children[3]=foldStatement(n.children[3],count); },
        .block=>for(n.children) |*child| { child.*=foldStatement(child.*,count); },else=>{},
    }
    return n;
}
fn inverse(op:cg.Opcode) cg.Opcode { return if(op==.JUMPF) .JUMPT else .JUMPF; }
fn negated(op:cg.Opcode) ?cg.Opcode { return switch(op) {.LT=>.GE,.LE=>.GT,.GT=>.LE,.GE=>.LT,.EQ=>.NE,.NE=>.EQ,else=>null}; }
fn jumps(op:cg.Opcode,n:i64) bool { return (op==.JUMPF and n==0) or (op==.JUMPT and n!=0); }
fn delete(code:*std.ArrayList(cg.Instruction),at:usize) void { _=code.orderedRemove(at); for(code.items) |*instruction| if(cg.jump(instruction.op) and instruction.a>@as(i64,@intCast(at))) { instruction.a-=1; }; }
fn optimize(original:[]const cg.Instruction,counts:*[7]usize) []const cg.Instruction {
    var code:std.ArrayList(cg.Instruction)=.empty; for(original) |instruction| l.append(cg.Instruction,&code,instruction);
    outer: while(true) {
        const targets=l.alloc(bool,code.items.len+1); @memset(targets,false); for(code.items) |instruction| if(cg.jump(instruction.op)) { targets[@intCast(instruction.a)]=true; };
        for(0..code.items.len) |i| {
            const a=code.items[i]; const next=i+1<code.items.len; const b:cg.Instruction=if(next) code.items[i+1] else a; const free=next and !targets[i+1]; var rule:?usize=null;
            if(a.op==.PUSH and free and cg.conditional(b.op)) { if(jumps(b.op,a.a)) { code.items[i]=.{.op=.JUMP,.a=b.a,.position=b.position}; delete(&code,i+1); } else { delete(&code,i+1); delete(&code,i); } rule=0; }
            else if(free and b.op==.NOT and negated(a.op)!=null) { code.items[i].op=negated(a.op).?; delete(&code,i+1); rule=1; }
            else if(a.op==.NOT and free and cg.conditional(b.op)) { code.items[i]=.{.op=inverse(b.op),.a=b.a,.position=b.position}; delete(&code,i+1); rule=2; }
            else if(cg.conditional(a.op) and a.a==@as(i64,@intCast(i+2)) and free and b.op==.JUMP) { code.items[i].op=inverse(a.op); code.items[i].a=b.a; delete(&code,i+1); rule=3; }
            else {
                if(cg.jump(a.op) and a.a<@as(i64,@intCast(code.items.len))) { const target:usize=@intCast(a.a); const at=code.items[target]; var new:?i64=null; if(at.op==.JUMP) new=at.a else if(at.op==.PUSH and target+1<code.items.len and cg.conditional(code.items[target+1].op)) { const branch=code.items[target+1]; new=if(jumps(branch.op,at.a)) branch.a else @intCast(target+2); } if(new!=null and new.?!=a.a) { code.items[i].a=new.?; rule=4; } }
                if(rule==null and cg.jump(a.op) and a.a==@as(i64,@intCast(i+1))) { if(a.op==.JUMP) delete(&code,i) else code.items[i]=.{.op=.POP,.position=a.position}; rule=5; }
                if(rule==null and cg.transfer(a.op) and free) { delete(&code,i+1); rule=6; }
            }
            if(rule) |r| { counts[r]+=1; continue :outer; }
        }
        break;
    }
    return code.items;
}
fn nextIndices(code:[]const cg.Instruction,at:usize) []const usize { var out:std.ArrayList(usize)=.empty; const instruction=code[at]; if(!cg.transfer(instruction.op) and at+1<code.len) l.append(usize,&out,at+1); if(cg.jump(instruction.op) and instruction.a<@as(i64,@intCast(code.len))) { const target:usize=@intCast(instruction.a); var duplicate=false; for(out.items) |i| if(i==target) { duplicate=true; break; }; if(!duplicate) l.append(usize,&out,target); } return out.items; }
fn effect(instruction:cg.Instruction) i64 { return switch(instruction.op) {.PUSH,.LOADG,.LOADL,.READ=>1,.POP,.STOREG,.STOREL,.JUMPF,.JUMPT,.RETV,.ADD,.SUB,.MUL,.DIV,.MOD,.LT,.LE,.GT,.GE,.EQ,.NE=>-1,.STOREA=>-2,.CALL=>-instruction.b+@as(i64,@intFromBool(instruction.callee.?.typ!=.void)),.PRINT=>-instruction.a,else=>0}; }
fn flow(unit:*cg.Unit) void {
    const code=unit.after; const leaders=l.alloc(bool,code.len); @memset(leaders,false); leaders[0]=true;
    for(code,0..) |instruction,i| { if(cg.jump(instruction.op) and instruction.a<@as(i64,@intCast(code.len))) leaders[@intCast(instruction.a)]=true; if((cg.jump(instruction.op) or cg.transfer(instruction.op)) and i+1<code.len) leaders[i+1]=true; }
    var starts:std.ArrayList(usize)=.empty; for(leaders,0..) |yes,i| if(yes) l.append(usize,&starts,i); const block_for=l.alloc(usize,code.len); for(starts.items,0..) |first,k| { const end=if(k+1<starts.items.len) starts.items[k+1] else code.len; for(first..end) |i| block_for[i]=k; }
    var blocks:std.ArrayList(cg.Block)=.empty; for(starts.items,0..) |first,k| { const last=(if(k+1<starts.items.len) starts.items[k+1] else code.len)-1; var successors:std.ArrayList(usize)=.empty; for(nextIndices(code,last)) |i| { const b=block_for[i]; var duplicate=false; for(successors.items) |old| if(old==b) { duplicate=true; break; }; if(!duplicate) l.append(usize,&successors,b); } l.append(cg.Block,&blocks,.{.first=first,.last=last,.successors=successors.items}); } unit.blocks=blocks.items;
    const depths=l.alloc(?i64,code.len); @memset(depths,null); depths[0]=0; var queue:std.ArrayList(usize)=.empty; l.append(usize,&queue,0); var at:usize=0;
    while(at<queue.items.len) : (at+=1) { const i=queue.items[at]; const depth=depths[i].?+effect(code[i]); unit.stack_depth=@max(unit.stack_depth,depth); for(nextIndices(code,i)) |next| if(depths[next]==null) { depths[next]=depth; l.append(usize,&queue,next); }; }
}
fn recursive(start:*p.Declaration,current:*p.Declaration,seen:*std.AutoHashMap(*p.Declaration,void)) bool { for(current.calls.items) |callee| { if(callee==start) return true; if(!seen.contains(callee)) { seen.put(callee,{}) catch @panic("allocation failed"); if(recursive(start,callee,seen)) return true; } } return false; }
fn signature(decl:*p.Declaration) []const u8 { var out:l.Text=.{}; out.put(" {s}(",.{@tagName(decl.typ)}); for(decl.parameters,0..) |param,i| { if(i>0) out.put(",",.{}); out.put("{s}",.{@tagName(param.typ)}); } out.put(")",.{}); return out.data.items; }
fn callees(decl:*p.Declaration) []const u8 { const names=l.alloc([]const u8,decl.calls.items.len); for(decl.calls.items,names) |callee,*name| name.*=callee.name; std.mem.sort([]const u8,names,{},struct { fn less(_:void,a:[]const u8,b:[]const u8) bool { return std.mem.order(u8,a,b)==.lt; } }.less); return if(names.len==0) "-" else std.mem.join(l.allocator,",",names) catch @panic("allocation failed"); }
fn listing(declarations:[]const *p.Declaration,units:[]cg.Unit,before_code:[]const cg.Instruction,after_code:[]const cg.Instruction,text:*l.Text) void {
    var globals:usize=0; for(declarations) |decl| globals+=@intFromBool(!decl.function); text.line("globals:{s}",.{if(globals==0) " none" else ""});
    for(declarations) |decl| if(!decl.function) text.line("  {d} {s} {s}",.{decl.address,decl.name,if(decl.array) l.fmt("int[{d}]",.{decl.size}) else @tagName(decl.typ)});
    text.line("functions:",.{}); for(units) |unit| { text.line("  {s}{s} address={d}->{d} size={d}->{d} slots={d} stack={d} blocks={d} calls={s}{s}",.{unit.name,if(unit.declaration) |decl| signature(decl) else "",unit.before_start,unit.after_start,unit.before.len,unit.after.len,unit.slots.len,unit.stack_depth,unit.blocks.len,if(unit.declaration) |decl| callees(decl) else "main",if(unit.recursive) " recursive" else ""}); for(unit.slots,0..) |decl,i| text.line("    slot {d} {s} {s}",.{i,decl.name,@tagName(decl.typ)}); }
    text.line("references:",.{}); for([_]bool{false,true}) |functions| for(declarations) |decl| { if(decl.function!=functions) continue; text.put("  {s} defined {d} used",.{decl.name,decl.name_position.line}); const refs=l.alloc(usize,decl.references.items.len); for(decl.references.items,refs) |pos,*line| line.*=pos.line; std.mem.sort(usize,refs,{},std.sort.asc(usize)); var last:usize=0; for(refs) |line| if(line!=last) { text.put(" {d}",.{line}); last=line; }; if(refs.len==0) text.put(" -",.{}); text.put("\n",.{}); };
    for([_]bool{false,true}) |after| { const code=if(after) after_code else before_code; text.line("{s} peephole: {d} instructions",.{if(after) "after" else "before",code.len}); for(units) |unit| { text.line("{s}:",.{unit.name}); const start=if(after) unit.after_start else unit.before_start; const size=(if(after) unit.after else unit.before).len; for(start..start+size) |pc| text.line("{d: >5}  {s}",.{pc,cg.spelling(code[pc])}); } }
    text.line("control flow:",.{}); for(units) |unit| { text.line("  {s}",.{unit.name}); for(unit.blocks,0..) |block,k| { text.put("    B{d} {d}-{d}",.{k,unit.after_start+block.first,unit.after_start+block.last}); if(block.successors.len>0) { text.put(" ->",.{}); for(block.successors) |successor| text.put(" B{d}",.{successor}); } text.put("\n",.{}); } }
}
const Ranked=struct { name:[]const u8,count:usize,id:usize=0,second:[]const u8="" };
fn rankLess(_:void,a:Ranked,b:Ranked) bool { if(a.count!=b.count) return a.count>b.count; const order=std.mem.order(u8,a.name,b.name); return order==.lt or (order==.eq and std.mem.order(u8,a.second,b.second)==.lt); }
fn statistics(units:[]const cg.Unit,code:[]const cg.Instruction,result:vm.Result,comparison:vm.Result,before_size:usize,folds:usize,peephole:[7]usize,text:*l.Text) void {
    var changes:usize=0; for(peephole) |count| changes+=count; text.line("code: {d} -> {d}",.{before_size,code.len}); text.line("folds: {d}",.{folds}); text.line("peephole: {d}",.{changes}); for(rules,peephole) |name,count| text.line("  {s} {d}",.{name,count}); text.line("executed: {d}",.{result.executed}); text.line("executed before peephole: {d}",.{comparison.executed});
    var same=result.output.len==comparison.output.len; if(same) for(result.output,comparison.output) |a,b| if(!l.eq(a,b)) { same=false; break; }; if(result.failure==null or comparison.failure==null) { if(result.failure!=null or comparison.failure!=null) same=false; } else if(!l.eq(result.failure.?,comparison.failure.?)) same=false;
    text.line("behaviour: {s}",.{if(same) "same" else "different"}); text.line("max call depth: {d}",.{result.max_depth}); text.line("max stack: {d}",.{result.max_stack});
    const op_counts=l.alloc(usize,@typeInfo(cg.Opcode).@"enum".fields.len); @memset(op_counts,0); for(code,result.counts) |instruction,count| op_counts[@intFromEnum(instruction.op)]+=count; var ranked:std.ArrayList(Ranked)=.empty;
    for(op_counts,0..) |count,id| if(count>0) l.append(Ranked,&ranked,.{.name=@tagName(@as(cg.Opcode,@enumFromInt(id))),.count=count}); std.mem.sort(Ranked,ranked.items,{},rankLess); text.line("opcodes:",.{}); for(ranked.items) |entry| text.line("  {s} {d}",.{entry.name,entry.count}); ranked=.empty;
    for(units[1..],1..) |unit,id| { var count:usize=0; for(result.counts[unit.after_start..unit.after_start+unit.after.len]) |n| count+=n; l.append(Ranked,&ranked,.{.name=unit.name,.count=count,.id=id}); } std.mem.sort(Ranked,ranked.items,{},rankLess); text.line("functions:",.{}); for(ranked.items) |entry| text.line("  {s} calls={d} executed={d}",.{entry.name,result.calls[entry.id],entry.count}); ranked=.empty;
    for(result.pairs,0..) |count,id| if(count>0) l.append(Ranked,&ranked,.{.name=units[id/units.len].name,.second=units[id%units.len].name,.count=count}); std.mem.sort(Ranked,ranked.items,{},rankLess); text.line("calls:",.{}); for(ranked.items) |entry| text.line("  {s} -> {s} {d}",.{entry.name,entry.second,entry.count});
    var lines=std.AutoHashMap(usize,usize).init(l.allocator); for(code,result.counts) |instruction,count| { const entry=lines.getOrPut(instruction.position.line) catch @panic("allocation failed"); if(!entry.found_existing) entry.value_ptr.*=0; entry.value_ptr.*+=count; }
    const Line=struct { line:usize,count:usize }; var line_rank:std.ArrayList(Line)=.empty; var unexecuted:std.ArrayList(usize)=.empty; var it=lines.iterator(); while(it.next()) |entry| { if(entry.value_ptr.*>0) l.append(Line,&line_rank,.{.line=entry.key_ptr.*,.count=entry.value_ptr.*}) else l.append(usize,&unexecuted,entry.key_ptr.*); }
    std.mem.sort(Line,line_rank.items,{},struct { fn less(_:void,a:Line,b:Line) bool { return a.count>b.count or (a.count==b.count and a.line<b.line); } }.less); std.mem.sort(usize,unexecuted.items,{},std.sort.asc(usize)); text.line("hot lines:",.{}); for(line_rank.items[0..@min(5,line_rank.items.len)]) |entry| text.line("  line {d}: {d}",.{entry.line,entry.count}); text.line("coverage: {d} of {d} lines",.{line_rank.items.len,lines.count()}); text.put("not executed:",.{}); if(unexecuted.items.len==0) text.put(" none",.{}); for(unexecuted.items) |line| text.put(" {d}",.{line}); text.put("\n",.{});
    var spots:std.ArrayList(usize)=.empty; for(result.counts,0..) |count,pc| if(count>0) l.append(usize,&spots,pc); std.mem.sort(usize,spots.items,result.counts,struct { fn less(counts:[]const usize,a:usize,b:usize) bool { return counts[a]>counts[b] or (counts[a]==counts[b] and a<b); } }.less); text.line("hot spots:",.{}); for(spots.items[0..@min(5,spots.items.len)]) |pc| text.line("  pc={d} count={d} {s}",.{pc,result.counts[pc],cg.spelling(code[pc])});
}
const Program=struct { name:[]const u8,first_line:usize,lines:std.ArrayList([]const u8)=.empty,input:std.ArrayList(i64)=.empty };
fn linesOf(text:[]const u8) []const []const u8 { var out:std.ArrayList([]const u8)=.empty; var it=std.mem.splitScalar(u8,text,'\n'); while(it.next()) |line| l.append([]const u8,&out,line); return out.items[0..out.items.len-1]; }
fn positionDisplay(text:*l.Text,program:Program,position:l.Position) void { text.line("  {s}",.{program.lines.items[position.line-program.first_line]}); text.line("  {s}^",.{l.spaces(position.column-1)}); }
const TableRow=[5][]const u8;
fn summaryTable(rows:[]const TableRow,text:*l.Text) void { var widths=[_]usize{0}**5; for(rows) |row| for(row,0..) |value,i| { widths[i]=@max(widths[i],value.len); }; for(rows) |row| { text.put("  ",.{}); for(row,0..) |value,i| { if(i>0) text.put("  ",.{}); const padding=l.spaces(widths[i]-value.len); if(i<2) text.put("{s}{s}",.{value,padding}) else text.put("{s}{s}",.{padding,value}); } text.put("\n",.{}); } }
pub fn main(init:std.process.Init) !void {
    var arena:std.heap.ArenaAllocator=.init(init.gpa); defer arena.deinit(); l.allocator=arena.allocator(); var programs:std.ArrayList(Program)=.empty;
    for(linesOf(try l.read(init.io,"input/program.src")),1..) |line,i| { if(std.mem.startsWith(u8,line,"#program ")) l.append(Program,&programs,.{.name=line[9..],.first_line=i+1}) else l.append([]const u8,&programs.items[programs.items.len-1].lines,line); }
    var input_program:usize=0; for(linesOf(try l.read(init.io,"input/input.txt"))) |line| { if(std.mem.startsWith(u8,line,"#input ")) { for(programs.items,0..) |program,i| if(l.eq(program.name,line[7..])) { input_program=i; break; }; } else { var words=std.mem.tokenizeScalar(u8,line,' '); while(words.next()) |word| l.append(i64,&programs.items[input_program].input,std.fmt.parseInt(i64,word,10) catch unreachable); } }
    var listing_text:l.Text=.{}; var output:l.Text=.{}; var diagnostics:l.Text=.{}; var stats:l.Text=.{}; var table:std.ArrayList(TableRow)=.empty; l.append(TableRow,&table,.{"program","status","code","executed","output"}); var compiled:usize=0; var compile_errors=[_]usize{0}**3; var runtime_errors:usize=0; var total_folds:usize=0; var total_rules=[_]usize{0}**7; var total_executed:usize=0;
    for(programs.items) |program| {
        for([_]*l.Text{&listing_text,&output,&diagnostics,&stats}) |text| text.line("== program {s} ==",.{program.name}); var source:l.Text=.{}; for(program.lines.items) |line| source.line("{s}",.{line}); const lexed=l.scan(source.data.items,program.first_line); var failure=lexed.failure; var declarations:[]const *p.Declaration=&.{}; var analyzer:semantic.Analyzer=undefined; var main_function:?*p.Declaration=null;
        if(failure==null) { var parser=p.Parser{.tokens=lexed.tokens}; declarations=parser.program() catch blk:{ failure=parser.failure; break :blk &.{}; }; }
        if(failure==null) { analyzer=.{.declarations=declarations}; main_function=analyzer.analyze(lexed.tokens[lexed.tokens.len-1].position) catch blk:{ failure=analyzer.failure; break :blk null; }; }
        if(failure) |error_value| { for([_] []const u8{"lexical","syntax","semantic"},0..) |kind,i| if(l.eq(kind,error_value.kind)) { compile_errors[i]+=1; }; listing_text.line("not compiled",.{}); stats.line("not compiled",.{}); diagnostics.line("{s} error {s}: {s}",.{error_value.kind,error_value.position.str(),error_value.message}); positionDisplay(&diagnostics,program,error_value.position); diagnostics.line("status: compile error",.{}); l.append(TableRow,&table,.{program.name,l.fmt("{s} error",.{error_value.kind}),"-","-","-"}); continue; }
        compiled+=1; for(semantic.collectWarnings(analyzer)) |warning| diagnostics.line("warning {s}: {s}",.{warning.position.str(),warning.message}); var folds:usize=0; for(declarations) |decl| { if(!decl.function) { if(decl.initializer) |initializer| decl.initializer=foldExpression(initializer,&folds); } else if(decl.reachable) decl.body=foldStatement(decl.body.?,&folds); }
        const units=cg.generate(declarations,main_function.?); var peephole=[_]usize{0}**7; for(units) |*unit| { unit.after=optimize(unit.before,&peephole); flow(unit); if(unit.declaration) |decl| { var seen=std.AutoHashMap(*p.Declaration,void).init(l.allocator); unit.recursive=recursive(decl,decl,&seen); } } const before_code=cg.flatten(units,false); const after_code=cg.flatten(units,true); listing(declarations,units,before_code,after_code,&listing_text);
        var global_size:usize=0; for(declarations) |decl| if(!decl.function) { global_size+=decl.size; }; const result=vm.run(after_code,units,true,global_size,program.input.items); const comparison=vm.run(before_code,units,false,global_size,program.input.items); for(result.output) |line| output.line("{s}",.{line});
        if(result.failure) |message| { runtime_errors+=1; const instruction=after_code[result.error_pc]; diagnostics.line("runtime error {s}: {s} in {s}",.{instruction.position.str(),message,units[vm.unitAt(units,result.error_pc,true)].name}); positionDisplay(&diagnostics,program,instruction.position); var count:usize=0; var i=result.frames.len; while(i>1) { i-=1; const caller=after_code[result.frames[i].return_address-1]; if(count<5) diagnostics.line("  called from {s} at {s}",.{units[vm.unitAt(units,result.frames[i].return_address-1,true)].name,caller.position.str()}); count+=1; } if(count>5) diagnostics.line("  ... {d} more",.{count-5}); diagnostics.line("status: runtime error",.{}); }
        else diagnostics.line("status: ok",.{});
        statistics(units,after_code,result,comparison,before_code.len,folds,peephole,&stats); total_folds+=folds; total_executed+=result.executed; for(peephole,0..) |count,i| total_rules[i]+=count; l.append(TableRow,&table,.{program.name,if(result.failure==null) "ok" else "runtime error",l.fmt("{d}",.{after_code.len}),l.fmt("{d}",.{result.executed}),l.fmt("{d}",.{result.output.len})});
    }
    var total_changes:usize=0; for(total_rules) |count| total_changes+=count; stats.line("== summary ==",.{}); stats.line("programs: {d}",.{programs.items.len}); stats.line("compiled: {d}",.{compiled}); stats.line("compile errors: lexical {d} syntax {d} semantic {d}",.{compile_errors[0],compile_errors[1],compile_errors[2]}); stats.line("runtime errors: {d}",.{runtime_errors}); stats.line("folds: {d}",.{total_folds}); stats.line("peephole: {d}",.{total_changes}); for(rules,total_rules) |name,count| stats.line("  {s} {d}",.{name,count}); stats.line("executed: {d}",.{total_executed}); summaryTable(table.items,&stats);
    try l.write(init.io,"listing.txt",listing_text); try l.write(init.io,"output.txt",output); try l.write(init.io,"diagnostics.txt",diagnostics); try l.write(init.io,"stats.txt",stats);
}
