const std=@import("std");
const l=@import("lexer.zig");
const p=@import("parser.zig");
pub const Opcode=enum { PUSH,POP,LOADG,STOREG,LOADL,STOREL,LOADA,STOREA,ADD,SUB,MUL,DIV,MOD,LT,LE,GT,GE,EQ,NE,NEG,NOT,JUMP,JUMPF,JUMPT,CALL,ENTER,RET,RETV,READ,PRINT,HALT };
pub const Instruction=struct { op:Opcode,a:i64=0,b:i64=0,position:l.Position,callee:?*p.Declaration=null };
pub const Block=struct { first:usize,last:usize,successors:[]const usize };
pub const Unit=struct { name:[]const u8,declaration:?*p.Declaration=null,before:[]const Instruction=&.{},after:[]const Instruction=&.{},slots:[]const *p.Declaration=&.{},before_start:usize=0,after_start:usize=0,stack_depth:i64=0,blocks:[]const Block=&.{},recursive:bool=false };
pub fn jump(op:Opcode) bool { return op==.JUMP or op==.JUMPF or op==.JUMPT; }
pub fn conditional(op:Opcode) bool { return op==.JUMPF or op==.JUMPT; }
pub fn transfer(op:Opcode) bool { return op==.JUMP or op==.RET or op==.RETV or op==.HALT; }
pub fn operands(op:Opcode) usize { return switch(op) {.PUSH,.LOADG,.STOREG,.LOADL,.STOREL,.JUMP,.JUMPF,.JUMPT,.ENTER,.PRINT=>1,.LOADA,.STOREA,.CALL=>2,else=>0}; }
pub fn spelling(instruction:Instruction) []const u8 { return switch(operands(instruction.op)) {0=>@tagName(instruction.op),1=>l.fmt("{s} {d}",.{@tagName(instruction.op),instruction.a}),else=>l.fmt("{s} {d} {d}",.{@tagName(instruction.op),instruction.a,instruction.b})}; }
pub fn arithmetic(op:[]const u8) Opcode { const symbols=[_][]const u8{"+","-","*","/","%","<","<=",">",">=","==","!="}; const ops=[_]Opcode{.ADD,.SUB,.MUL,.DIV,.MOD,.LT,.LE,.GT,.GE,.EQ,.NE}; for(symbols,ops) |s,o| if(l.eq(op,s)) return o; unreachable; }
const Loop=struct { breaks:std.ArrayList(usize)=.empty,continues:std.ArrayList(usize)=.empty };
const Generator=struct {
    code:std.ArrayList(Instruction)=.empty,loops:std.ArrayList(Loop)=.empty,
    fn emit(self:*Generator,op:Opcode,a:i64,b:i64,pos:l.Position) usize { const i=self.code.items.len; l.append(Instruction,&self.code,.{.op=op,.a=a,.b=b,.position=pos}); return i; }
    fn patch(self:*Generator,at:usize,target:usize) void { self.code.items[at].a=@intCast(target); }
    fn expression(self:*Generator,n:*p.Node) void {
        switch(n.kind) {
            .literal=>{ _=self.emit(.PUSH,n.value,0,n.position); },.read=>{ _=self.emit(.READ,0,0,n.position); },
            .variable=>{ const decl=n.target.?; _=self.emit(if(decl.global) .LOADG else .LOADL,@intCast(if(decl.global) decl.address else decl.slot),0,n.position); },
            .index=>{ self.expression(n.children[0]); const decl=n.target.?; _=self.emit(.LOADA,@intCast(decl.address),@intCast(decl.size),n.position); },
            .call=>{ for(n.children) |arg| self.expression(arg); const i=self.emit(.CALL,0,@intCast(n.children.len),n.position); self.code.items[i].callee=n.target; },
            .unary=>{ self.expression(n.children[0]); _=self.emit(if(l.eq(n.op,"-")) .NEG else .NOT,0,0,n.position); },
            .binary=>{
                self.expression(n.children[0]); if(l.eq(n.op,"&&") or l.eq(n.op,"||")) { const or_op=l.eq(n.op,"||"); const first=self.emit(if(or_op) .JUMPT else .JUMPF,0,0,n.position); self.expression(n.children[1]); const end=self.emit(.JUMP,0,0,n.position); self.patch(first,self.code.items.len); _=self.emit(.PUSH,@intFromBool(or_op),0,n.position); self.patch(end,self.code.items.len); }
                else { self.expression(n.children[1]); _=self.emit(arithmetic(n.op),0,0,n.position); }
            },else=>unreachable,
        }
    }
    fn statement(self:*Generator,n:*p.Node) void {
        switch(n.kind) {
            .empty=>{},.block=>for(n.children) |statement_node| { self.statement(statement_node); },
            .declaration=>{ const decl=n.declaration.?; if(decl.initializer) |initializer| self.expression(initializer) else { _=self.emit(.PUSH,0,0,decl.name_position); } _=self.emit(.STOREL,@intCast(decl.slot),0,decl.name_position); },
            .assignment=>{ const decl=n.target.?; for(n.children) |expr| self.expression(expr); if(n.children.len==2) { _=self.emit(.STOREA,@intCast(decl.address),@intCast(decl.size),n.position); } else { _=self.emit(if(decl.global) .STOREG else .STOREL,@intCast(if(decl.global) decl.address else decl.slot),0,n.position); } },
            .call_stmt=>{ const expr=n.children[0]; self.expression(expr); if(expr.kind==.read or expr.typ!=.void) _=self.emit(.POP,0,0,n.position); },
            .print_stmt=>{ for(n.children) |expr| self.expression(expr); _=self.emit(.PRINT,@intCast(n.children.len),0,n.position); },
            .return_stmt=>{ if(n.children.len>0) self.expression(n.children[0]); _=self.emit(if(n.children.len==0) .RET else .RETV,0,0,n.position); },
            .if_stmt=>{ self.expression(n.children[0]); const branch=self.emit(.JUMPF,0,0,n.position); self.statement(n.children[1]); if(n.children.len==3) { const end=self.emit(.JUMP,0,0,n.position); self.patch(branch,self.code.items.len); self.statement(n.children[2]); self.patch(end,self.code.items.len); } else self.patch(branch,self.code.items.len); },
            .while_stmt,.for_stmt=>{
                const for_loop=n.kind==.for_stmt; if(for_loop) self.statement(n.children[0]); const head=self.code.items.len; const condition=n.children[if(for_loop) @as(usize,1) else 0]; var exit:?usize=null;
                if(condition.kind!=.empty) { self.expression(condition); exit=self.emit(.JUMPF,0,0,n.position); }
                l.append(Loop,&self.loops,.{}); self.statement(n.children[if(for_loop) @as(usize,3) else 1]); const continuation=if(for_loop) self.code.items.len else head; if(for_loop) self.statement(n.children[2]); _=self.emit(.JUMP,@intCast(head),0,n.position); const end=self.code.items.len; if(exit) |i| self.patch(i,end); const loop=self.loops.pop().?; for(loop.breaks.items) |i| self.patch(i,end); for(loop.continues.items) |i| self.patch(i,continuation);
            },
            .break_stmt,.continue_stmt=>{ const i=self.emit(.JUMP,0,0,n.position); const loop=&self.loops.items[self.loops.items.len-1]; l.append(usize,if(n.kind==.break_stmt) &loop.breaks else &loop.continues,i); },
            else=>unreachable,
        }
    }
};
fn localDeclarations(n:*p.Node,out:*std.ArrayList(*p.Declaration)) void { if(n.kind==.declaration) l.append(*p.Declaration,out,n.declaration.?); for(n.children) |child| localDeclarations(child,out); }
pub fn generate(declarations:[]const *p.Declaration,main:*p.Declaration) []Unit {
    var units:std.ArrayList(Unit)=.empty; l.append(Unit,&units,.{.name="<init>"}); var address:usize=0;
    for(declarations) |decl| { if(!decl.function) { decl.address=address; address+=decl.size; } else if(decl.reachable) { decl.unit=units.items.len; l.append(Unit,&units,.{.name=decl.name,.declaration=decl}); } }
    var initialization:Generator=.{}; for(declarations) |decl| if(!decl.function) { if(decl.initializer) |initializer| { initialization.expression(initializer); _=initialization.emit(.STOREG,@intCast(decl.address),0,decl.name_position); } }; const call=initialization.emit(.CALL,0,0,main.name_position); initialization.code.items[call].callee=main; _=initialization.emit(.HALT,0,0,main.name_position); units.items[0].before=initialization.code.items;
    for(units.items[1..]) |*unit| { const decl=unit.declaration.?; var locals:std.ArrayList(*p.Declaration)=.empty; localDeclarations(decl.body.?,&locals); std.mem.sort(*p.Declaration,locals.items,{},struct { fn less(_:void,a:*p.Declaration,b:*p.Declaration) bool { return l.before(a.name_position,b.name_position); } }.less); var slots:std.ArrayList(*p.Declaration)=.empty; for(decl.parameters) |param| l.append(*p.Declaration,&slots,param); for(locals.items) |local| l.append(*p.Declaration,&slots,local); for(slots.items,0..) |variable,i| variable.slot=i; unit.slots=slots.items;
        var generator:Generator=.{}; _=generator.emit(.ENTER,@intCast(slots.items.len),0,decl.name_position); generator.statement(decl.body.?); if(decl.typ==.void) _=generator.emit(.RET,0,0,decl.body.?.closing); unit.before=generator.code.items;
    }
    return units.items;
}
pub fn flatten(units:[]Unit,after:bool) []const Instruction {
    var address:usize=0; for(units) |*unit| { if(after) unit.after_start=address else unit.before_start=address; address+=(if(after) unit.after else unit.before).len; }
    var out:std.ArrayList(Instruction)=.empty;
    for(units) |unit| { const start=if(after) unit.after_start else unit.before_start; for(if(after) unit.after else unit.before) |original| { var instruction=original; if(jump(instruction.op)) instruction.a+=@intCast(start); if(instruction.callee) |callee| instruction.a=@intCast(if(after) units[callee.unit].after_start else units[callee.unit].before_start); l.append(Instruction,&out,instruction); } }
    return out.items;
}
