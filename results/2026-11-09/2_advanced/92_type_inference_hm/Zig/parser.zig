const std=@import("std");
const u=@import("unifier.zig");
const l=@import("lexer.zig");
pub const Mark=struct { name:[]const u8,position:u.Position,uses:usize=0,top:bool=false };
pub const Binding=struct { name:[]const u8,position:u.Position,expression:*Node,mark:?*Mark=null,scheme:?u.Scheme=null,classification:[]const u8="" };
pub const Arm=struct { pattern:*Node,expression:*Node };
pub const Node=struct { kind:[]const u8,value:[]const u8="",position:u.Position,operator_position:u.Position=.{.line=0},children:[]const *Node=&.{},bindings:[]Binding=&.{},recursive:bool=false,rec_position:u.Position=.{},arms:[]const Arm=&.{},mark:?*Mark=null,typ:?*u.Type=null,rec_used:bool=false };
pub const Item=struct { kind:enum{signature,declaration,expression},node:*Node,name:[]const u8="",position:u.Position,signature:?*Node=null };
pub fn node(kind:[]const u8,pos:u.Position,children:[]const *Node) *Node { const cs=u.alloc(*Node,children.len); @memcpy(cs,children); return u.create(Node,.{.kind=kind,.position=pos,.children=cs}); }
pub fn precedence(s:[]const u8) usize { const operators=[_][]const []const u8{&.{"||"},&.{"&&"},&.{"=","<>","<",">","<=",">="},&.{"::","^"},&.{"+","-"},&.{"*","/","mod"}}; for(operators,1..) |group,k| for(group) |op| { if(u.eq(s,op)) return k; }; return 0; }
pub fn rightAssociative(p:usize) bool { return p==1 or p==2 or p==4; }
pub const Parser=struct {
    tokens:[]const l.Token,at:usize=0,failure:?u.Failure=null,
    const Error=error{Syntax};
    pub fn current(self:*Parser) l.Token { return self.tokens[self.at]; }
    fn is(self:*Parser,s:[]const u8) bool { return u.eq(self.current().value,s); }
    fn read(self:*Parser) l.Token { const t=self.current(); if(t.kind!=.eof) self.at+=1; return t; }
    fn bad(self:*Parser) Error { const t=self.current(); self.failure=.{.position=t.position,.message=if(t.kind==.invalid) t.value else if(t.kind==.eof) "unexpected end of file" else u.fmt("unexpected '{s}'",.{t.spelling})}; return error.Syntax; }
    fn take(self:*Parser,s:[]const u8) Error!l.Token { if(!self.is(s)) return self.bad(); return self.read(); }
    fn name(self:*Parser,wildcard:bool) Error!l.Token { if(self.current().kind!=.name or (!wildcard and self.is("_"))) return self.bad(); return self.read(); }
    pub fn item(self:*Parser) Error!Item {
        const start=self.current(); var result:Item=undefined;
        if(self.is("val")) { _=self.read(); const n=try self.name(false); _=try self.take(":"); const t=try self.typeExpression(); result=.{.kind=.signature,.node=t,.name=n.value,.position=n.position,.signature=t}; }
        else if(self.is("let")) { const group=try self.letGroup(); if(self.is("in")) { _=self.read(); const body=try self.expression(); const cs=u.alloc(*Node,1); cs[0]=body; group.children=cs; result=.{.kind=.expression,.node=group,.position=start.position}; } else result=.{.kind=.declaration,.node=group,.position=start.position}; }
        else result=.{.kind=.expression,.node=try self.expression(),.position=start.position};
        _=try self.take(";;"); return result;
    }
    fn letGroup(self:*Parser) Error!*Node {
        const start=try self.take("let"); const out=node("let",start.position,&.{}); if(self.is("rec")) { out.recursive=true; out.rec_position=self.read().position; } var bindings:std.ArrayList(Binding)=.empty;
        while(true) { const n=try self.name(false); var params:std.ArrayList(l.Token)=.empty; while(self.current().kind==.name) u.append(l.Token,&params,try self.name(true)); _=try self.take("="); var value=try self.expression(); var i=params.items.len; while(i>0) { i-=1; const param=params.items[i]; const fun=node("fun",param.position,&.{value}); fun.value=param.value; value=fun; } u.append(Binding,&bindings,.{.name=n.value,.position=n.position,.expression=value}); if(!self.is("and")) break; _=self.read(); }
        out.bindings=bindings.items; return out;
    }
    fn expression(self:*Parser) Error!*Node {
        if(self.is("let")) { const out=try self.letGroup(); _=try self.take("in"); const body=try self.expression(); const cs=u.alloc(*Node,1); cs[0]=body; out.children=cs; return out; }
        if(self.is("fun")) { const start=self.read(); var params:std.ArrayList(l.Token)=.empty; u.append(l.Token,&params,try self.name(true)); while(self.current().kind==.name) u.append(l.Token,&params,try self.name(true)); _=try self.take("->"); var value=try self.expression(); var i=params.items.len; while(i>0) { i-=1; const p=params.items[i]; const out=node("fun",if(i==0) start.position else p.position,&.{value}); out.value=p.value; out.operator_position=p.position; value=out; } return value; }
        if(self.is("if")) { const start=self.read(); const condition=try self.expression(); _=try self.take("then"); const a=try self.expression(); _=try self.take("else"); const b=try self.expression(); return node("if",start.position,&.{condition,a,b}); }
        if(self.is("match")) { const start=self.read(); const expression_node=try self.expression(); _=try self.take("with"); if(self.is("|")) _=self.read(); var arms:std.ArrayList(Arm)=.empty; while(true) { const pattern_node=try self.pattern(); _=try self.take("->"); const value=try self.expression(); u.append(Arm,&arms,.{.pattern=pattern_node,.expression=value}); if(!self.is("|")) break; _=self.read(); } const out=node("match",start.position,&.{expression_node}); out.arms=arms.items; return out; }
        return self.binary(1);
    }
    fn binary(self:*Parser,k:usize) Error!*Node { if(k==7) return self.unary(); var left=try self.binary(k+1); while(precedence(self.current().value)==k) { const op=self.read(); const right=if(rightAssociative(k)) try self.binary(k) else try self.binary(k+1); const out=node("binary",left.position,&.{left,right}); out.value=op.value; out.operator_position=op.position; left=out; } return left; }
    fn atomicStart(self:*Parser) bool { const t=self.current(); return t.kind==.integer or t.kind==.string or (t.kind==.name and !self.is("_")) or self.is("true") or self.is("false") or self.is("(") or self.is("["); }
    fn unary(self:*Parser) Error!*Node { if(self.is("-")) { const t=self.read(); const out=node("neg",t.position,&.{try self.unary()}); out.operator_position=t.position; return out; } var f=try self.atomic(false); while(self.atomicStart()) { const arg=try self.atomic(false); f=node("apply",f.position,&.{f,arg}); } return f; }
    fn atomic(self:*Parser,is_pattern:bool) Error!*Node {
        const t=self.current();
        if(self.is("(")) { _=self.read(); const a=if(is_pattern) try self.pattern() else try self.expression(); if(self.is(",")) { _=self.read(); const b=if(is_pattern) try self.pattern() else try self.expression(); _=try self.take(")"); return node("pair",t.position,&.{a,b}); } _=try self.take(")"); return a; }
        if(self.is("[")) { _=self.read(); var children:std.ArrayList(*Node)=.empty; if(!self.is("]")) { u.append(*Node,&children,if(is_pattern) try self.pattern() else try self.expression()); while(self.is(";")) { _=self.read(); u.append(*Node,&children,if(is_pattern) try self.pattern() else try self.expression()); } } _=try self.take("]"); return node("list",t.position,children.items); }
        if(is_pattern and self.is("-")) { _=self.read(); if(self.current().kind!=.integer) return self.bad(); const integer=self.read(); const out=node("integer",t.position,&.{}); out.value=u.fmt("-{s}",.{integer.value}); return out; }
        var kind:[]const u8=undefined;
        if(t.kind==.integer) kind="integer" else if(t.kind==.string) kind="string" else if(self.is("true") or self.is("false")) kind="boolean" else if(t.kind==.name and (is_pattern or !self.is("_"))) kind=if(self.is("_")) "wildcard" else "name" else return self.bad(); _=self.read(); const out=node(kind,t.position,&.{}); out.value=t.value; return out;
    }
    fn pattern(self:*Parser) Error!*Node { const a=try self.atomic(true); if(!self.is("::")) return a; _=self.read(); const b=try self.pattern(); return node("cons",a.position,&.{a,b}); }
    fn typeExpression(self:*Parser) Error!*Node { const a=try self.productType(); if(!self.is("->")) return a; _=self.read(); return node("function",a.position,&.{a,try self.typeExpression()}); }
    fn productType(self:*Parser) Error!*Node { const a=try self.listType(); if(!self.is("*")) return a; _=self.read(); return node("pair",a.position,&.{a,try self.listType()}); }
    fn listType(self:*Parser) Error!*Node { var a:*Node=undefined; if(self.is("(")) { _=self.read(); a=try self.typeExpression(); _=try self.take(")"); } else { const t=self.current(); if(t.kind!=.typevar and !self.is("int") and !self.is("bool") and !self.is("string")) return self.bad(); _=self.read(); a=node(if(t.kind==.typevar) "typevar" else t.value,t.position,&.{}); a.value=t.value; } while(self.is("list")) { _=self.read(); a=node("list",a.position,&.{a}); } return a; }
};
