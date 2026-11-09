const std=@import("std");
const l=@import("lexer.zig");
const cg=@import("codegen.zig");
pub const Frame=struct { locals:std.ArrayList(i64)=.empty,return_address:usize };
pub const Result=struct { output:[]const []const u8,failure:?[]const u8=null,error_pc:usize=0,frames:[]const Frame,executed:usize,counts:[]usize,calls:[]usize,pairs:[]usize,max_depth:usize,max_stack:usize };
pub fn unitAt(units:[]const cg.Unit,pc:usize,after:bool) usize { var result:usize=0; for(units,0..) |unit,i| { if(pc>=(if(after) unit.after_start else unit.before_start)) result=i else break; } return result; }
fn index(n:i64) usize { return @intCast(n); }
pub fn run(code:[]const cg.Instruction,units:[]const cg.Unit,after:bool,global_size:usize,input:[]const i64) Result {
    const globals=l.alloc(i64,global_size); @memset(globals,0); var stack:std.ArrayList(i64)=.empty; var frames:std.ArrayList(Frame)=.empty; var output:std.ArrayList([]const u8)=.empty;
    const counts=l.alloc(usize,code.len); @memset(counts,0); const calls=l.alloc(usize,units.len); @memset(calls,0); const pairs=l.alloc(usize,units.len*units.len); @memset(pairs,0); var pc:usize=0; var executed:usize=0; var consumed:usize=0; var max_depth:usize=0; var max_stack:usize=0; var failure:?[]const u8=null;
    while(true) {
        if(executed==100000) { failure="instruction limit exceeded"; break; } const instruction=code[pc]; counts[pc]+=1; executed+=1; var next=pc+1;
        switch(instruction.op) {
            .PUSH=>l.append(i64,&stack,instruction.a),.POP=>{ _=stack.pop(); },
            .LOADG=>l.append(i64,&stack,globals[index(instruction.a)]),.STOREG=>globals[index(instruction.a)]=stack.pop().?,
            .LOADL=>l.append(i64,&stack,frames.items[frames.items.len-1].locals.items[index(instruction.a)]),.STOREL=>frames.items[frames.items.len-1].locals.items[index(instruction.a)]=stack.pop().?,
            .LOADA,.STOREA=>{
                const value=if(instruction.op==.STOREA) stack.pop().? else @as(i64,0); const i=stack.pop().?;
                if(i<0 or i>=instruction.b) failure=l.fmt("index {d} out of bounds for array of size {d}",.{i,instruction.b})
                else if(instruction.op==.STOREA) globals[index(instruction.a+i)]=value else l.append(i64,&stack,globals[index(instruction.a+i)]);
            },
            .ADD,.SUB,.MUL,.DIV,.MOD,.LT,.LE,.GT,.GE,.EQ,.NE=>{
                const b=stack.pop().?; const a=stack.pop().?; var value:i64=0;
                if((instruction.op==.DIV or instruction.op==.MOD) and b==0) failure="division by zero"
                else { value=switch(instruction.op) {.ADD=>a+b,.SUB=>a-b,.MUL=>a*b,.DIV=>@divTrunc(a,b),.MOD=>@rem(a,b),.LT=>@intFromBool(a<b),.LE=>@intFromBool(a<=b),.GT=>@intFromBool(a>b),.GE=>@intFromBool(a>=b),.EQ=>@intFromBool(a==b),.NE=>@intFromBool(a!=b),else=>unreachable}; if(value < -2147483648 or value > 2147483647) failure="integer overflow" else l.append(i64,&stack,value); }
            },
            .NEG=>{ const value=-stack.pop().?; if(value < -2147483648 or value > 2147483647) failure="integer overflow" else l.append(i64,&stack,value); },.NOT=>{ const value=stack.pop().?; l.append(i64,&stack,@intFromBool(value==0)); },
            .JUMP=>next=index(instruction.a),.JUMPF,.JUMPT=>{ const value=stack.pop().?; if((value==0)==(instruction.op==.JUMPF)) next=index(instruction.a); },
            .CALL=>{
                if(frames.items.len==100) failure="call depth limit exceeded" else {
                    const n=index(instruction.b); var frame=Frame{.return_address=pc+1}; for(stack.items[stack.items.len-n..]) |value| l.append(i64,&frame.locals,value); stack.shrinkRetainingCapacity(stack.items.len-n); l.append(Frame,&frames,frame); const caller=unitAt(units,pc,after); const callee=unitAt(units,index(instruction.a),after); calls[callee]+=1; pairs[caller*units.len+callee]+=1; next=index(instruction.a);
                }
            },
            .ENTER=>{ const locals=&frames.items[frames.items.len-1].locals; while(locals.items.len<index(instruction.a)) l.append(i64,locals,0); },
            .RET,.RETV=>{ next=frames.pop().?.return_address; },
            .READ=>{ if(consumed==input.len) failure="read past end of input" else { l.append(i64,&stack,input[consumed]); consumed+=1; } },
            .PRINT=>{ const n=index(instruction.a); var line:l.Text=.{}; for(stack.items[stack.items.len-n..],0..) |value,i| { if(i>0) line.put(" ",.{}); line.put("{d}",.{value}); } l.append([]const u8,&output,line.data.items); stack.shrinkRetainingCapacity(stack.items.len-n); },
            .HALT=>{},
        }
        if(failure!=null) break; max_depth=@max(max_depth,frames.items.len); max_stack=@max(max_stack,stack.items.len); if(instruction.op==.HALT) break; pc=next;
    }
    return .{.output=output.items,.failure=failure,.error_pc=pc,.frames=frames.items,.executed=executed,.counts=counts,.calls=calls,.pairs=pairs,.max_depth=max_depth,.max_stack=max_stack};
}
