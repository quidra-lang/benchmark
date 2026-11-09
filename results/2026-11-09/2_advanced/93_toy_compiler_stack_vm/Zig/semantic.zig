const std=@import("std");
const l=@import("lexer.zig");
const p=@import("parser.zig");
pub const Warning=struct { position:l.Position,message:[]const u8 };
pub const Analyzer=struct {
    declarations:[]const *p.Declaration,failure:?l.Failure=null,scopes:std.ArrayList(std.ArrayList(*p.Declaration))=.empty,variables:std.ArrayList(*p.Declaration)=.empty,current:?*p.Declaration=null,loop_depth:usize=0,
    const Error=error{Semantic};
    fn fail(self:*Analyzer,pos:l.Position,comptime s:[]const u8,args:anytype) Error { self.failure=.{.kind="semantic",.position=pos,.message=l.fmt(s,args)}; return error.Semantic; }
    fn global(self:*Analyzer,name:[]const u8) ?*p.Declaration { for(self.declarations) |decl| if(l.eq(decl.name,name)) return decl; return null; }
    fn scope(self:*Analyzer) *std.ArrayList(*p.Declaration) { return &self.scopes.items[self.scopes.items.len-1]; }
    fn localName(self:*Analyzer,name:[]const u8) bool { for(self.scope().items) |decl| if(l.eq(decl.name,name)) return true; return false; }
    fn lookup(self:*Analyzer,name:[]const u8,pos:l.Position,read_access:bool) ?*p.Declaration {
        var found:?*p.Declaration=null; var i=self.scopes.items.len; while(i>0) { i-=1; for(self.scopes.items[i].items) |decl| if(l.eq(decl.name,name)) { found=decl; break; }; if(found!=null) break; } if(found==null) found=self.global(name);
        if(found) |decl| { l.append(l.Position,&decl.references,pos); decl.reads+=@intFromBool(read_access); } return found;
    }
    fn variable(self:*Analyzer,name:[]const u8,pos:l.Position,indexed:bool,read_access:bool) Error!*p.Declaration {
        const decl=self.lookup(name,pos,read_access) orelse return self.fail(pos,"undeclared identifier '{s}'",.{name});
        if(decl.function) return self.fail(pos,"'{s}' is a function, not a variable",.{name}); if(indexed and !decl.array) return self.fail(pos,"'{s}' is not an array",.{name}); if(!indexed and decl.array) return self.fail(pos,"array '{s}' used without index",.{name}); return decl;
    }
    pub fn expression(self:*Analyzer,n:*p.Node,as_statement:bool) Error!p.Type {
        switch(n.kind) {
            .literal=>return n.typ,.read=>return .int,
            .variable,.index=>{ const decl=try self.variable(n.name,n.position,n.kind==.index,true); n.target=decl; if(n.kind==.index and try self.expression(n.children[0],false)!=.int) return self.fail(n.position,"index of '{s}' must be int",.{n.name}); n.typ=decl.typ; return n.typ; },
            .call=>{
                const decl=self.lookup(n.name,n.position,true) orelse return self.fail(n.position,"undeclared function '{s}'",.{n.name}); if(!decl.function) return self.fail(n.position,"'{s}' is not a function",.{n.name}); n.target=decl;
                if(n.children.len!=decl.parameters.len) return self.fail(n.position,"wrong number of arguments to '{s}' (expected {d}, found {d})",.{n.name,decl.parameters.len,n.children.len});
                for(n.children,decl.parameters,1..) |arg,param,k| if(try self.expression(arg,false)!=param.typ) return self.fail(n.position,"argument {d} of '{s}' must be {s}",.{k,n.name,@tagName(param.typ)});
                if(!as_statement and decl.typ==.void) return self.fail(n.position,"void function '{s}' used as a value",.{n.name}); if(self.current) |current| { var found=false; for(current.calls.items) |callee| if(callee==decl) { found=true; break; }; if(!found) l.append(*p.Declaration,&current.calls,decl); } n.typ=decl.typ; return n.typ;
            },
            .unary=>{ const typ=try self.expression(n.children[0],false); const expected:p.Type=if(l.eq(n.op,"-")) .int else .bool; if(typ!=expected) return self.fail(n.position,"operator '{s}' requires {s} operand",.{n.op,@tagName(expected)}); n.typ=typ; return typ; },
            .binary=>{
                const a=try self.expression(n.children[0],false); const b=try self.expression(n.children[1],false); const equal=l.eq(n.op,"==") or l.eq(n.op,"!="); const logical=l.eq(n.op,"&&") or l.eq(n.op,"||");
                if(equal) { if(a!=b) return self.fail(n.position,"operator '{s}' requires operands of the same type",.{n.op}); }
                else { const expected:p.Type=if(logical) .bool else .int; if(a!=expected or b!=expected) return self.fail(n.position,"operator '{s}' requires {s} operands",.{n.op,@tagName(expected)}); }
                n.typ=if(equal or logical or l.eq(n.op,"<") or l.eq(n.op,"<=") or l.eq(n.op,">") or l.eq(n.op,">=")) .bool else .int; return n.typ;
            },else=>unreachable,
        }
    }
    fn blockContents(self:*Analyzer,n:*p.Node) Error!void { n.normal=true; for(n.children) |child| { try self.statement(child); n.normal=n.normal and child.normal; } }
    fn statement(self:*Analyzer,n:*p.Node) Error!void {
        n.normal=true;
        switch(n.kind) {
            .empty=>{},
            .block=>{ l.append(std.ArrayList(*p.Declaration),&self.scopes,.empty); try self.blockContents(n); _=self.scopes.pop(); },
            .declaration=>{ const decl=n.declaration.?; if(decl.typ==.void) return self.fail(decl.name_position,"variable '{s}' cannot have type void",.{decl.name}); if(self.localName(decl.name)) return self.fail(decl.name_position,"redeclaration of '{s}'",.{decl.name}); if(decl.initializer) |initializer| if(try self.expression(initializer,false)!=decl.typ) return self.fail(decl.name_position,"type mismatch in initialization of '{s}'",.{decl.name}); l.append(*p.Declaration,self.scope(),decl); l.append(*p.Declaration,&self.variables,decl); },
            .assignment=>{ const indexed=n.children.len==2; const decl=try self.variable(n.name,n.position,indexed,false); n.target=decl; if(indexed and try self.expression(n.children[0],false)!=.int) return self.fail(n.position,"index of '{s}' must be int",.{n.name}); const rhs=try self.expression(n.children[n.children.len-1],false); if(rhs!=decl.typ) return self.fail(n.position,"type mismatch in assignment to '{s}'",.{n.name}); },
            .call_stmt=>{ _=try self.expression(n.children[0],true); },
            .if_stmt,.while_stmt=>{ if(try self.expression(n.children[0],false)!=.bool) return self.fail(n.position,"condition of '{s}' must be bool",.{if(n.kind==.if_stmt) "if" else "while"}); if(n.kind==.while_stmt) self.loop_depth+=1; try self.statement(n.children[1]); if(n.kind==.while_stmt) self.loop_depth-=1; if(n.children.len==3) try self.statement(n.children[2]); if(n.kind==.if_stmt) n.normal=n.children.len==2 or n.children[1].normal or n.children[2].normal; },
            .for_stmt=>{ l.append(std.ArrayList(*p.Declaration),&self.scopes,.empty); try self.statement(n.children[0]); if(n.children[1].kind!=.empty and try self.expression(n.children[1],false)!=.bool) return self.fail(n.position,"condition of 'for' must be bool",.{}); try self.statement(n.children[2]); self.loop_depth+=1; try self.statement(n.children[3]); self.loop_depth-=1; _=self.scopes.pop(); },
            .break_stmt,.continue_stmt=>{ if(self.loop_depth==0) return self.fail(n.position,"'{s}' outside loop",.{if(n.kind==.break_stmt) "break" else "continue"}); n.normal=false; },
            .return_stmt=>{ const current=self.current.?; if(current.typ==.void and n.children.len>0) return self.fail(n.position,"function '{s}' must not return a value",.{current.name}); if(current.typ!=.void and n.children.len==0) return self.fail(n.position,"function '{s}' must return a value",.{current.name}); if(current.typ!=.void and try self.expression(n.children[0],false)!=current.typ) return self.fail(n.position,"return value of '{s}' must be {s}",.{current.name,@tagName(current.typ)}); n.normal=false; },
            .print_stmt=>for(n.children,1..) |child,k| { if(try self.expression(child,false)!=.int) return self.fail(n.position,"argument {d} of 'print' must be int",.{k}); },
            else=>unreachable,
        }
    }
    fn forbidden(n:*p.Node) ?l.Position { var result:?l.Position=null; if(n.kind==.variable or n.kind==.index or n.kind==.call or n.kind==.read) result=n.position; for(n.children) |child| if(forbidden(child)) |position| { if(result==null or l.before(position,result.?)) result=position; }; return result; }
    pub fn analyze(self:*Analyzer,end:l.Position) Error!*p.Declaration {
        for(self.declarations,0..) |decl,i| {
            if(!decl.function) { if(decl.array and decl.typ!=.int) return self.fail(decl.name_position,"array '{s}' must have element type int",.{decl.name}); if(decl.array and decl.size==0) return self.fail(decl.size_position,"array '{s}' must have a positive size",.{decl.name}); if(!decl.array and decl.typ==.void) return self.fail(decl.name_position,"variable '{s}' cannot have type void",.{decl.name}); }
            for(self.declarations[0..i]) |old| if(l.eq(old.name,decl.name)) return self.fail(decl.name_position,"redeclaration of '{s}'",.{decl.name});
            if(decl.function) for(decl.parameters,0..) |param,j| { if(param.typ==.void) return self.fail(param.name_position,"parameter '{s}' cannot have type void",.{param.name}); for(decl.parameters[0..j]) |old| if(l.eq(old.name,param.name)) return self.fail(param.name_position,"redeclaration of '{s}'",.{param.name}); }
            else { l.append(*p.Declaration,&self.variables,decl); if(decl.initializer) |initializer| { if(forbidden(initializer)) |position| return self.fail(position,"global initializer must be constant",.{}); if(try self.expression(initializer,false)!=decl.typ) return self.fail(decl.name_position,"type mismatch in initialization of '{s}'",.{decl.name}); } }
        }
        const main=self.global("main") orelse return self.fail(end,"no main function",.{}); if(!main.function) return self.fail(end,"no main function",.{}); if(main.typ!=.void or main.parameters.len>0) return self.fail(main.name_position,"main must be declared as 'void main()'",.{});
        for(self.declarations) |decl| if(decl.function) { self.current=decl; l.append(std.ArrayList(*p.Declaration),&self.scopes,.empty); for(decl.parameters) |param| { l.append(*p.Declaration,self.scope(),param); l.append(*p.Declaration,&self.variables,param); } try self.blockContents(decl.body.?); if(decl.typ!=.void and decl.body.?.normal) return self.fail(decl.name_position,"missing return in function '{s}'",.{decl.name}); _=self.scopes.pop(); };
        reachable(main); return main;
    }
};
fn reachable(decl:*p.Declaration) void { if(decl.reachable) return; decl.reachable=true; for(decl.calls.items) |callee| reachable(callee); }
fn unreachableWarnings(n:*p.Node,warnings:*std.ArrayList(Warning)) void { if(n.kind==.block) { for(n.children,0..) |child,i| if(!child.normal and i+1<n.children.len) { l.append(Warning,warnings,.{.position=n.children[i+1].position,.message="unreachable statement"}); break; }; } for(n.children) |child| unreachableWarnings(child,warnings); }
pub fn collectWarnings(analyzer:Analyzer) []Warning { var out:std.ArrayList(Warning)=.empty; for(analyzer.variables.items) |decl| if(decl.reads==0) l.append(Warning,&out,.{.position=decl.name_position,.message=l.fmt("unused {s} '{s}'",.{if(decl.parameter) "parameter" else "variable",decl.name})}); for(analyzer.declarations) |decl| if(decl.function) { if(!decl.reachable) l.append(Warning,&out,.{.position=decl.name_position,.message=l.fmt("function '{s}' is never called",.{decl.name})}); unreachableWarnings(decl.body.?,&out); }; std.mem.sort(Warning,out.items,{},struct { fn less(_:void,a:Warning,b:Warning) bool { return l.before(a.position,b.position); } }.less); return out.items; }
