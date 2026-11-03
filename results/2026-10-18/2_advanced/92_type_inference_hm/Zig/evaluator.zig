const std=@import("std");
const u=@import("unifier.zig");
const p=@import("parser.zig");
pub const Entry=struct { name:[]const u8,value:*Value };
pub const Environment=[]const Entry;
pub const Value=struct { kind:enum{integer,boolean,string,pair,list,closure,builtin},integer:i64=0,string:[]const u8="",items:[]const *Value=&.{},parameter:[]const u8="",body:?*p.Node=null,environment:Environment=&.{} };
pub fn value(kind:@FieldType(Value,"kind")) *Value { return u.create(Value,.{.kind=kind}); }
pub fn integer(n:i64) *Value { const v=value(.integer); v.integer=n; return v; }
pub fn boolean(n:bool) *Value { const v=value(.boolean); v.integer=@intFromBool(n); return v; }
pub fn string(s:[]const u8) *Value { const v=value(.string); v.string=s; return v; }
pub fn collection(kind:@FieldType(Value,"kind"),items:[]const *Value) *Value { const v=value(kind); const copy=u.alloc(*Value,items.len); @memcpy(copy,items); v.items=copy; return v; }
pub fn extend(env:Environment,entry:Entry) Environment { var out:std.ArrayList(Entry)=.empty; for(env) |old| if(!u.eq(old.name,entry.name)) u.append(Entry,&out,old); u.append(Entry,&out,entry); return out.items; }
pub fn escaped(s:[]const u8) []const u8 { var out:u.Text=.{}; out.put("\"",.{}); for(s) |c| switch(c) {'\\'=>out.put("\\\\",.{}),'"'=>out.put("\\\"",.{}),'\n'=>out.put("\\n",.{}),'\t'=>out.put("\\t",.{}),else=>out.put("{c}",.{c})}; out.put("\"",.{}); return out.data.items; }
pub fn print(v:*const Value) []const u8 { switch(v.kind) { .integer=>return u.fmt("{d}",.{v.integer}),.boolean=>return if(v.integer==0) "false" else "true",.string=>return escaped(v.string),.closure,.builtin=>return "<fun>",.pair=>return u.fmt("({s}, {s})",.{print(v.items[0]),print(v.items[1])}),.list=>{ var out:u.Text=.{}; out.put("[",.{}); for(v.items,0..) |x,i| { if(i>0) out.put("; ",.{}); out.put("{s}",.{print(x)}); } out.put("]",.{}); return out.data.items; } } }
pub const Evaluator=struct {
    failure:?u.Failure=null,calls:usize=0,
    const Error=error{Runtime};
    fn fail(self:*Evaluator,pos:u.Position,comptime s:[]const u8,args:anytype) Error { self.failure=.{.position=pos,.message=u.fmt(s,args)}; return error.Runtime; }
    fn checked(self:*Evaluator,n:i64,pos:u.Position) Error!*Value { if(n < -2147483648 or n > 2147483647) return self.fail(pos,"integer overflow",.{}); return integer(n); }
    pub fn compare(self:*Evaluator,a:*Value,b:*Value,pos:u.Position) Error!std.math.Order {
        switch(a.kind) { .integer,.boolean=>return std.math.order(a.integer,b.integer),.string=>return std.mem.order(u8,a.string,b.string),.closure,.builtin=>return self.fail(pos,"functional value compared",.{}),.pair,.list=>{ for(a.items[0..@min(a.items.len,b.items.len)],b.items[0..@min(a.items.len,b.items.len)]) |x,y| { const result=try self.compare(x,y,pos); if(result!=.eq) return result; } return std.math.order(a.items.len,b.items.len); } }
    }
    pub fn expression(self:*Evaluator,n:*p.Node,env:Environment) Error!*Value {
        const k=n.kind;
        if(u.eq(k,"integer")) return integer(std.fmt.parseInt(i64,n.value,10) catch unreachable); if(u.eq(k,"boolean")) return boolean(u.eq(n.value,"true")); if(u.eq(k,"string")) return string(n.value);
        if(u.eq(k,"name")) { for(env) |entry| if(u.eq(entry.name,n.value)) return entry.value; unreachable; }
        if(u.eq(k,"fun")) { const v=value(.closure); v.parameter=n.value; v.body=n.children[0]; v.environment=env; return v; }
        if(u.eq(k,"apply")) { const f=try self.expression(n.children[0],env); const argument=try self.expression(n.children[1],env); self.calls+=1;
            if(f.kind==.closure) { const local=if(u.eq(f.parameter,"_")) f.environment else extend(f.environment,.{.name=f.parameter,.value=argument}); return self.expression(f.body.?,local); }
            if(u.eq(f.string,"fst")) return argument.items[0]; if(u.eq(f.string,"snd")) return argument.items[1]; if(u.eq(f.string,"not")) return boolean(argument.integer==0); if(u.eq(f.string,"string_of_int")) return string(u.fmt("{d}",.{argument.integer})); return self.fail(n.position,"failure {s}",.{print(argument)});
        }
        if(u.eq(k,"neg")) return self.checked(-(try self.expression(n.children[0],env)).integer,n.operator_position);
        if(u.eq(k,"if")) { const condition=try self.expression(n.children[0],env); return self.expression(n.children[if(condition.integer!=0) @as(usize,1) else 2],env); }
        if(u.eq(k,"binary")) {
            const a=try self.expression(n.children[0],env); const op=n.value;
            if(u.eq(op,"&&") and a.integer==0) return a; if(u.eq(op,"||") and a.integer!=0) return a; const b=try self.expression(n.children[1],env);
            if(u.eq(op,"&&") or u.eq(op,"||")) return b;
            if(u.eq(op,"+")) return self.checked(a.integer+b.integer,n.operator_position); if(u.eq(op,"-")) return self.checked(a.integer-b.integer,n.operator_position); if(u.eq(op,"*")) return self.checked(a.integer*b.integer,n.operator_position);
            if(u.eq(op,"/") or u.eq(op,"mod")) { if(b.integer==0) return self.fail(n.operator_position,"division by zero",.{}); const quotient=@divTrunc(a.integer,b.integer); return self.checked(if(u.eq(op,"/")) quotient else a.integer-b.integer*quotient,n.operator_position); }
            if(u.eq(op,"^")) return string(u.fmt("{s}{s}",.{a.string,b.string}));
            if(u.eq(op,"::")) { const items=u.alloc(*Value,b.items.len+1); items[0]=a; @memcpy(items[1..],b.items); return collection(.list,items); }
            const order=try self.compare(a,b,n.operator_position); return boolean(if(u.eq(op,"=")) order==.eq else if(u.eq(op,"<>")) order!=.eq else if(u.eq(op,"<")) order==.lt else if(u.eq(op,">")) order==.gt else if(u.eq(op,"<=")) order!=.gt else order!=.lt);
        }
        if(u.eq(k,"pair") or u.eq(k,"list")) { const items=u.alloc(*Value,n.children.len); for(n.children,items) |child,*v| v.*=try self.expression(child,env); return collection(if(u.eq(k,"pair")) .pair else .list,items); }
        if(u.eq(k,"match")) { const target=try self.expression(n.children[0],env); for(n.arms) |arm| { var entries:std.ArrayList(Entry)=.empty; if(try self.match(arm.pattern,target,&entries)) { var local=env; for(entries.items) |entry| local=extend(local,entry); return self.expression(arm.expression,local); } } return self.fail(n.position,"match failure",.{}); }
        return self.expression(n.children[0],try self.group(n,env));
    }
    pub fn group(self:*Evaluator,n:*p.Node,env:Environment) Error!Environment {
        var entries:std.ArrayList(Entry)=.empty;
        for(n.bindings) |binding| { const v=try self.expression(binding.expression,env); u.append(Entry,&entries,.{.name=binding.name,.value=v}); }
        var out=env; for(entries.items) |entry| out=extend(out,entry); if(n.recursive) for(entries.items) |entry| { entry.value.environment=out; }; return out;
    }
    fn match(self:*Evaluator,n:*p.Node,v:*Value,entries:*std.ArrayList(Entry)) Error!bool {
        const k=n.kind; if(u.eq(k,"wildcard")) return true; if(u.eq(k,"name")) { u.append(Entry,entries,.{.name=n.value,.value=v}); return true; }
        if(u.eq(k,"integer")) return v.integer==(std.fmt.parseInt(i64,n.value,10) catch unreachable); if(u.eq(k,"string")) return u.eq(v.string,n.value); if(u.eq(k,"boolean")) return (v.integer!=0)==u.eq(n.value,"true");
        if(u.eq(k,"cons")) { if(v.items.len==0) return false; if(!try self.match(n.children[0],v.items[0],entries)) return false; return self.match(n.children[1],collection(.list,v.items[1..]),entries); }
        if(v.items.len!=n.children.len) return false; for(n.children,v.items) |child,item| if(!try self.match(child,item,entries)) return false; return true;
    }
};
