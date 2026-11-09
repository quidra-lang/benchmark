const std=@import("std");
const l=@import("lexer.zig");
pub const Type=enum { int,bool,void };
pub const Declaration=struct { name:[]const u8,typ:Type,position:l.Position,name_position:l.Position,global:bool=false,parameter:bool=false,function:bool=false,array:bool=false,size:usize=1,size_position:l.Position=.{.line=1,.column=1},initializer:?*Node=null,parameters:[]const *Declaration=&.{},body:?*Node=null,references:std.ArrayList(l.Position)=.empty,reads:usize=0,calls:std.ArrayList(*Declaration)=.empty,reachable:bool=false,slot:usize=0,address:usize=0,unit:usize=0 };
pub const Kind=enum { literal,variable,index,call,read,unary,binary,block,declaration,assignment,call_stmt,if_stmt,while_stmt,for_stmt,break_stmt,continue_stmt,return_stmt,print_stmt,empty };
pub const Node=struct { kind:Kind,position:l.Position,closing:l.Position=.{.line=1,.column=1},name:[]const u8="",op:[]const u8="",value:i64=0,typ:Type=.int,children:[]*Node=&.{},declaration:?*Declaration=null,target:?*Declaration=null,normal:bool=true };
pub fn node(kind:Kind,pos:l.Position,children:[]const *Node) *Node { const cs=l.alloc(*Node,children.len); @memcpy(cs,children); return l.create(Node,.{.kind=kind,.position=pos,.children=cs}); }
fn precedence(s:[]const u8) usize { const groups=[_][]const []const u8{&.{"||"},&.{"&&"},&.{"==","!="},&.{"<","<=",">",">="},&.{"+","-"},&.{"*","/","%"}}; for(groups,1..) |group,k| for(group) |op| { if(l.eq(op,s)) return k; }; return 0; }
pub const Parser=struct {
    tokens:[]const l.Token,at:usize=0,failure:?l.Failure=null,
    const Error=error{Syntax};
    fn current(self:*Parser) l.Token { return self.tokens[self.at]; }
    fn is(self:*Parser,text:[]const u8) bool { return l.eq(self.current().text,text); }
    fn read(self:*Parser) l.Token { const t=self.current(); if(t.kind!=.end) self.at+=1; return t; }
    fn bad(self:*Parser) Error { const t=self.current(); self.failure=.{.kind="syntax",.position=t.position,.message=if(t.kind==.end) "unexpected end of program" else l.fmt("unexpected '{s}'",.{t.text})}; return error.Syntax; }
    fn take(self:*Parser,s:[]const u8) Error!l.Token { if(!self.is(s)) return self.bad(); return self.read(); }
    fn name(self:*Parser) Error!l.Token { if(self.current().kind!=.identifier) return self.bad(); return self.read(); }
    fn isType(self:*Parser) bool { return self.is("int") or self.is("bool") or self.is("void"); }
    fn typeToken(self:*Parser) Error!l.Token { if(!self.isType()) return self.bad(); return self.read(); }
    fn declarationHeader(self:*Parser) Error!*Declaration { const typ=try self.typeToken(); const name_token=try self.name(); return l.create(Declaration,.{.name=name_token.text,.typ=std.meta.stringToEnum(Type,typ.text).?,.position=typ.position,.name_position=name_token.position}); }
    pub fn program(self:*Parser) Error![]const *Declaration {
        var out:std.ArrayList(*Declaration)=.empty;
        while(self.current().kind!=.end) { const decl=try self.declarationHeader(); decl.global=true;
            if(self.is("(")) { decl.function=true; _=self.read(); var params:std.ArrayList(*Declaration)=.empty; if(!self.is(")")) while(true) { const param=try self.declarationHeader(); param.parameter=true; l.append(*Declaration,&params,param); if(!self.is(",")) break; _=self.read(); }; _=try self.take(")"); decl.parameters=params.items; decl.body=try self.block(); }
            else { if(self.is("[")) { decl.array=true; _=self.read(); if(self.current().kind!=.integer) return self.bad(); const size=self.read(); decl.size=std.fmt.parseInt(usize,size.text,10) catch unreachable; decl.size_position=size.position; _=try self.take("]"); } else if(self.is("=")) { _=self.read(); decl.initializer=try self.expression(); } _=try self.take(";"); }
            l.append(*Declaration,&out,decl);
        }
        return out.items;
    }
    fn local(self:*Parser,required:bool,semicolon:bool) Error!*Node { const decl=try self.declarationHeader(); if(self.is("=")) { _=self.read(); decl.initializer=try self.expression(); } else if(required) return self.bad(); if(semicolon) _=try self.take(";"); const out=node(.declaration,decl.position,&.{}); out.declaration=decl; return out; }
    fn block(self:*Parser) Error!*Node { const start=try self.take("{"); var statements:std.ArrayList(*Node)=.empty; while(!self.is("}") and self.current().kind!=.end) l.append(*Node,&statements,if(self.isType()) try self.local(false,true) else try self.statement()); const close=try self.take("}"); const out=node(.block,start.position,statements.items); out.closing=close.position; return out; }
    fn statement(self:*Parser) Error!*Node {
        if(self.is("{")) return self.block(); const start=self.current();
        if(self.is("if") or self.is("while")) { const conditional=self.is("if"); _=self.read(); _=try self.take("("); const condition=try self.expression(); _=try self.take(")"); const body=try self.statement(); var children:std.ArrayList(*Node)=.empty; l.append(*Node,&children,condition); l.append(*Node,&children,body); if(conditional and self.is("else")) { _=self.read(); l.append(*Node,&children,try self.statement()); } return node(if(conditional) .if_stmt else .while_stmt,start.position,children.items); }
        if(self.is("for")) { _=self.read(); _=try self.take("("); const initial=if(self.is(";")) node(.empty,self.current().position,&.{}) else if(self.isType()) try self.local(true,false) else try self.simple(); _=try self.take(";"); const condition=if(self.is(";")) node(.empty,self.current().position,&.{}) else try self.expression(); _=try self.take(";"); const update=if(self.is(")")) node(.empty,self.current().position,&.{}) else try self.simple(); _=try self.take(")"); const body=try self.statement(); return node(.for_stmt,start.position,&.{initial,condition,update,body}); }
        if(self.is("break") or self.is("continue")) { _=self.read(); _=try self.take(";"); return node(if(l.eq(start.text,"break")) .break_stmt else .continue_stmt,start.position,&.{}); }
        if(self.is("return")) { _=self.read(); var children:std.ArrayList(*Node)=.empty; if(!self.is(";")) l.append(*Node,&children,try self.expression()); _=try self.take(";"); return node(.return_stmt,start.position,children.items); }
        if(self.is("print")) { _=self.read(); _=try self.take("("); var children:std.ArrayList(*Node)=.empty; l.append(*Node,&children,try self.expression()); while(self.is(",")) { _=self.read(); l.append(*Node,&children,try self.expression()); } _=try self.take(")"); _=try self.take(";"); return node(.print_stmt,start.position,children.items); }
        const simple_node=try self.simple(); _=try self.take(";"); return simple_node;
    }
    fn simple(self:*Parser) Error!*Node {
        if(self.is("read")) { const expr=try self.primary(); return node(.call_stmt,expr.position,&.{expr}); }
        const name_token=try self.name();
        if(self.is("(")) { const call_expression=try self.call(name_token); return node(.call_stmt,name_token.position,&.{call_expression}); }
        var children:std.ArrayList(*Node)=.empty; if(self.is("[")) { _=self.read(); l.append(*Node,&children,try self.expression()); _=try self.take("]"); }
        _=try self.take("="); l.append(*Node,&children,try self.expression()); const out=node(.assignment,name_token.position,children.items); out.name=name_token.text; return out;
    }
    fn expression(self:*Parser) Error!*Node { return self.binary(1); }
    fn binary(self:*Parser,k:usize) Error!*Node { if(k==7) return self.unary(); var a=try self.binary(k+1); while(precedence(self.current().text)==k) { const op=self.read(); const b=try self.binary(k+1); const out=node(.binary,op.position,&.{a,b}); out.op=op.text; a=out; } return a; }
    fn unary(self:*Parser) Error!*Node { if(self.is("-") or self.is("!")) { const op=self.read(); const out=node(.unary,op.position,&.{try self.unary()}); out.op=op.text; return out; } return self.primary(); }
    fn call(self:*Parser,name_token:l.Token) Error!*Node { _=try self.take("("); var args:std.ArrayList(*Node)=.empty; if(!self.is(")")) while(true) { l.append(*Node,&args,try self.expression()); if(!self.is(",")) break; _=self.read(); }; _=try self.take(")"); const out=node(.call,name_token.position,args.items); out.name=name_token.text; return out; }
    fn primary(self:*Parser) Error!*Node {
        const token=self.current(); if(token.kind==.integer or self.is("true") or self.is("false")) { _=self.read(); const out=node(.literal,token.position,&.{}); out.typ=if(token.kind==.integer) .int else .bool; out.value=if(token.kind==.integer) std.fmt.parseInt(i64,token.text,10) catch unreachable else @intFromBool(l.eq(token.text,"true")); return out; }
        if(self.is("read")) { _=self.read(); _=try self.take("("); _=try self.take(")"); return node(.read,token.position,&.{}); }
        if(self.is("(")) { _=self.read(); const out=try self.expression(); _=try self.take(")"); return out; }
        const name_token=try self.name(); if(self.is("(")) return self.call(name_token); const indexed=self.is("["); var children:std.ArrayList(*Node)=.empty; if(indexed) { _=self.read(); l.append(*Node,&children,try self.expression()); _=try self.take("]"); } const out=node(if(indexed) .index else .variable,name_token.position,children.items); out.name=name_token.text; return out;
    }
};
