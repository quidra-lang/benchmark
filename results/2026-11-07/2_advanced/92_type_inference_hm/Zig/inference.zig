const std=@import("std");
const u=@import("unifier.zig");
const p=@import("parser.zig");
pub const Entry=struct { name:[]const u8,scheme:u.Scheme,mark:?*p.Mark=null };
pub const Environment=[]const Entry;
pub fn lookup(env:Environment,name:[]const u8) ?Entry { for(env) |entry| if(u.eq(entry.name,name)) return entry; return null; }
pub fn extend(env:Environment,entry:Entry) Environment { var out:std.ArrayList(Entry)=.empty; for(env) |old| if(!u.eq(old.name,entry.name)) u.append(Entry,&out,old); u.append(Entry,&out,entry); return out.items; }
pub fn distance(a:[]const u8,b:[]const u8) usize { const row=u.alloc(usize,b.len+1); for(row,0..) |*v,i| v.*=i; for(a,1..) |x,i| { var diagonal=row[0]; row[0]=i; for(b,1..) |y,j| { const old=row[j]; row[j]=@min(@min(row[j]+1,row[j-1]+1),diagonal+@intFromBool(x!=y)); diagonal=old; } } return row[b.len]; }
pub const Infer=struct {
    failure:?u.Failure=null,locals:std.ArrayList(*p.Binding)=.empty,marks:std.ArrayList(*p.Mark)=.empty,
    const Error=error{Type};
    pub fn fail(self:*Infer,pos:u.Position,comptime message:[]const u8,args:anytype) Error { self.failure=.{.position=pos,.message=u.fmt(message,args)}; return error.Type; }
    pub fn check(self:*Infer,expected:*u.Type,found:*u.Type,pos:u.Position) Error!void {
        if(u.unify(expected,found)) |failed| { var printer:u.TypePrinter=.{}; const e=printer.print(expected,null); const f=printer.print(found,null); var extra:[]const u8="";
            if(failed.infinite) { const a=u.resolve(failed.expected); const v=if(a.kind==.variable) failed.expected else failed.found; const t=if(a.kind==.variable) failed.found else failed.expected; const variable=printer.print(v,null); const typ=printer.print(t,null); extra=u.fmt(" (infinite type {s} = {s})",.{variable,typ}); }
            else if(u.resolve(expected)!=failed.expected or u.resolve(found)!=failed.found) { const first=printer.print(failed.expected,null); const second=printer.print(failed.found,null); extra=u.fmt(" ({s} vs {s})",.{first,second}); }
            return self.fail(pos,"expected {s} but found {s}{s}",.{e,f,extra});
        }
    }
    fn mark(self:*Infer,name:[]const u8,pos:u.Position,top:bool) *p.Mark { const m=u.create(p.Mark,.{.name=name,.position=pos,.top=top}); u.append(*p.Mark,&self.marks,m); return m; }
    pub fn expression(self:*Infer,n:*p.Node,env:Environment) Error!*u.Type {
        const result=try self.expressionInner(n,env); n.typ=result; return result;
    }
    fn expressionInner(self:*Infer,n:*p.Node,env:Environment) Error!*u.Type {
        const kind=n.kind;
        if(u.eq(kind,"integer")) return u.primitive(.integer); if(u.eq(kind,"string")) return u.primitive(.string); if(u.eq(kind,"boolean")) return u.primitive(.boolean);
        if(u.eq(kind,"name")) { const entry=lookup(env,n.value) orelse { var best:?[]const u8=null; var minimum:usize=3; for(env) |candidate| { const d=distance(n.value,candidate.name); if(d<=2 and d<n.value.len and (d<minimum or (d==minimum and (best==null or std.mem.order(u8,candidate.name,best.?)==.lt)))) { best=candidate.name; minimum=d; } } return self.fail(n.position,"unbound variable '{s}'{s}",.{n.value,if(best) |name| u.fmt(" (did you mean '{s}'?)",.{name}) else ""}); }; n.mark=entry.mark; if(entry.mark) |m| m.uses+=1; return u.instantiate(entry.scheme); }
        if(u.eq(kind,"fun")) { const a=u.fresh(); var local=env; if(!u.eq(n.value,"_")) { const pos=if(n.operator_position.line==0) n.position else n.operator_position; const mark_value=self.mark(n.value,pos,false); n.mark=mark_value; local=extend(env,.{.name=n.value,.scheme=.{.typ=a},.mark=mark_value}); } const result=try self.expression(n.children[0],local); return u.construct(.function,a,result); }
        if(u.eq(kind,"apply")) { var function=u.resolve(try self.expression(n.children[0],env)); if(function.kind==.variable) { const a=u.fresh(); const result=u.fresh(); function.link=u.construct(.function,a,result); function=u.resolve(function); } if(function.kind!=.function) { var printer:u.TypePrinter=.{}; return self.fail(n.children[0].position,"expected a function but found {s}",.{printer.print(function,null)}); } const arg=try self.expression(n.children[1],env); try self.check(function.a.?,arg,n.children[1].position); return function.b.?; }
        if(u.eq(kind,"binary")) {
            const op=n.value; var first:*u.Type=undefined; var second:*u.Type=undefined; var result:*u.Type=undefined;
            if(u.eq(op,"::")) { first=u.fresh(); second=u.construct(.list,first,null); result=second; }
            else if(u.eq(op,"^") or u.eq(op,"&&") or u.eq(op,"||")) { first=u.primitive(if(u.eq(op,"^")) .string else .boolean); second=first; result=first; }
            else if(p.precedence(op)==3) { first=u.fresh(); second=first; result=u.primitive(.boolean); }
            else { first=u.primitive(.integer); second=first; result=first; }
            const left=try self.expression(n.children[0],env); try self.check(first,left,n.children[0].position); const right=try self.expression(n.children[1],env); try self.check(second,right,n.children[1].position); return result;
        }
        if(u.eq(kind,"neg")) { const t=try self.expression(n.children[0],env); const integer=u.primitive(.integer); try self.check(integer,t,n.children[0].position); return integer; }
        if(u.eq(kind,"if")) { const cond=try self.expression(n.children[0],env); try self.check(u.primitive(.boolean),cond,n.children[0].position); const a=try self.expression(n.children[1],env); const b=try self.expression(n.children[2],env); try self.check(a,b,n.children[2].position); return a; }
        if(u.eq(kind,"pair")) { const a=try self.expression(n.children[0],env); const b=try self.expression(n.children[1],env); return u.construct(.pair,a,b); }
        if(u.eq(kind,"list")) { const a=u.fresh(); for(n.children) |child| { const t=try self.expression(child,env); try self.check(a,t,child.position); } return u.construct(.list,a,null); }
        if(u.eq(kind,"match")) { const t=try self.expression(n.children[0],env); const result=u.fresh(); for(n.arms) |arm| { var bindings:std.ArrayList(Entry)=.empty; const pt=try self.pattern(arm.pattern,&bindings); try self.check(t,pt,arm.pattern.position); var local=env; for(bindings.items) |entry| local=extend(local,entry); const rt=try self.expression(arm.expression,local); try self.check(result,rt,arm.expression.position); } return result; }
        const local=try self.group(n,env,false); return self.expression(n.children[0],local);
    }
    fn pattern(self:*Infer,n:*p.Node,bindings:*std.ArrayList(Entry)) Error!*u.Type {
        const k=n.kind; var result:*u.Type=undefined;
        if(u.eq(k,"wildcard")) result=u.fresh()
        else if(u.eq(k,"name")) { if(lookup(bindings.items,n.value)!=null) return self.fail(n.position,"variable '{s}' is bound twice in this pattern",.{n.value}); result=u.fresh(); n.mark=self.mark(n.value,n.position,false); u.append(Entry,bindings,.{.name=n.value,.scheme=.{.typ=result},.mark=n.mark}); }
        else if(u.eq(k,"integer")) result=u.primitive(.integer) else if(u.eq(k,"boolean")) result=u.primitive(.boolean) else if(u.eq(k,"string")) result=u.primitive(.string)
        else if(u.eq(k,"pair")) { const a=try self.pattern(n.children[0],bindings); const b=try self.pattern(n.children[1],bindings); result=u.construct(.pair,a,b); }
        else if(u.eq(k,"cons")) { const a=u.fresh(); const left=try self.pattern(n.children[0],bindings); try self.check(a,left,n.children[0].position); const list=u.construct(.list,a,null); const right=try self.pattern(n.children[1],bindings); try self.check(list,right,n.children[1].position); result=list; }
        else { const a=u.fresh(); for(n.children) |child| { const t=try self.pattern(child,bindings); try self.check(a,t,child.position); } result=u.construct(.list,a,null); }
        n.typ=result; return result;
    }
    pub fn group(self:*Infer,n:*p.Node,env:Environment,top:bool) Error!Environment {
        for(n.bindings,0..) |binding,i| { for(n.bindings[0..i]) |old| if(u.eq(old.name,binding.name)) return self.fail(binding.position,"variable '{s}' is bound twice in this let",.{binding.name}); if(n.recursive and !u.eq(binding.expression.kind,"fun")) return self.fail(binding.position,"'{s}' in let rec must be a function",.{binding.name}); }
        const types=u.alloc(*u.Type,n.bindings.len); var recursive_env=env;
        for(n.bindings,0..) |*binding,i| { binding.mark=self.mark(binding.name,binding.position,top); if(n.recursive) { types[i]=u.fresh(); recursive_env=extend(recursive_env,.{.name=binding.name,.scheme=.{.typ=types[i]},.mark=binding.mark}); } }
        for(n.bindings,0..) |binding,i| { const t=try self.expression(binding.expression,if(n.recursive) recursive_env else env); if(n.recursive) try self.check(types[i],t,binding.position) else types[i]=t; }
        n.rec_used=false; for(n.bindings) |binding| if(binding.mark.?.uses>0) { n.rec_used=true; };
        var out=env; for(n.bindings,0..) |*binding,i| { binding.scheme=u.generalize(types[i],env); out=extend(out,.{.name=binding.name,.scheme=binding.scheme.?,.mark=binding.mark}); if(!top) u.append(*p.Binding,&self.locals,binding); } return out;
    }
};
