const std=@import("std");
pub var allocator:std.mem.Allocator=undefined;
pub fn alloc(comptime T:type,n:usize) []T { return allocator.alloc(T,n) catch @panic("allocation failed"); }
pub fn create(comptime T:type,v:T) *T { const p=allocator.create(T) catch @panic("allocation failed"); p.*=v; return p; }
pub fn append(comptime T:type,a:*std.ArrayList(T),v:T) void { a.append(allocator,v) catch @panic("allocation failed"); }
pub fn fmt(comptime s:[]const u8,a:anytype) []const u8 { return std.fmt.allocPrint(allocator,s,a) catch @panic("allocation failed"); }
pub fn eq(a:[]const u8,b:[]const u8) bool { return std.mem.eql(u8,a,b); }
pub const Text=struct { data:std.ArrayList(u8)=.empty,pub fn put(self:*Text,comptime s:[]const u8,a:anytype) void { self.data.appendSlice(allocator,fmt(s,a)) catch @panic("allocation failed"); } pub fn line(self:*Text,comptime s:[]const u8,a:anytype) void { self.put(s,a); self.put("\n",.{}); } };
pub fn words(s:[]const u8) []const []const u8 { var out:std.ArrayList([]const u8)=.empty; var it=std.mem.tokenizeAny(u8,s," \n"); while(it.next()) |w| append([]const u8,&out,w); return out.items; }
pub fn number(s:[]const u8) i64 { return std.fmt.parseInt(i64,s,10) catch unreachable; }
pub const Expr=struct { word:[]const u8="",children:[]const *Expr=&.{} };
fn expression(tokens:[]const []const u8,at:*usize) *Expr { const word=tokens[at.*]; at.*+=1; if(!eq(word,"(")) return create(Expr,.{.word=word}); var children:std.ArrayList(*Expr)=.empty; while(!eq(tokens[at.*],")")) append(*Expr,&children,expression(tokens,at)); at.*+=1; return create(Expr,.{.children=children.items}); }
pub fn expressions(text:[]const u8) []const *Expr {
    var tokens:std.ArrayList([]const u8)=.empty; var i:usize=0;
    while(i<text.len) { if(text[i]==';') { while(i<text.len and text[i]!='\n') : (i+=1) {} } else if(text[i]==' ' or text[i]=='\n') i+=1 else if(text[i]=='(' or text[i]==')') { append([]const u8,&tokens,text[i..i+1]); i+=1; } else { const start=i; while(i<text.len and std.mem.indexOfScalar(u8," \n();",text[i])==null) : (i+=1) {} append([]const u8,&tokens,text[start..i]); } }
    var out:std.ArrayList(*Expr)=.empty; var at:usize=0; while(at<tokens.items.len) append(*Expr,&out,expression(tokens.items,&at)); return out.items;
}
pub const Typed=struct { name:[]const u8,typ:[]const u8="object" };
pub fn typed(items:[]const *Expr) []Typed { var out:std.ArrayList(Typed)=.empty; var start:usize=0; var i:usize=0; while(i<items.len) : (i+=1) { if(eq(items[i].word,"-")) { for(out.items[start..]) |*entry| entry.typ=items[i+1].word; start=out.items.len; i+=1; } else append(Typed,&out,.{.name=items[i].word}); } return out.items; }
pub const Atom=struct { predicate:[]const u8,terms:[]const []const u8,
    pub fn notation(self:Atom) []const u8 { var out:Text=.{}; out.put("({s}",.{self.predicate}); for(self.terms) |term| out.put(" {s}",.{term}); out.put(")",.{}); return out.data.items; }
};
pub fn atom(expr:*const Expr) Atom { const terms=alloc([]const u8,expr.children.len-1); for(expr.children[1..],terms) |word,*term| term.*=word.word; return .{.predicate=expr.children[0].word,.terms=terms}; }
pub const Literal=struct { atom:Atom,negative:bool=false };
pub fn literals(expr:*const Expr) []const Literal { var out:std.ArrayList(Literal)=.empty; const list=if(eq(expr.children[0].word,"and")) expr.children[1..] else &[_]*const Expr{expr}; for(list) |entry| { const negative=eq(entry.children[0].word,"not"); append(Literal,&out,.{.atom=atom(if(negative) entry.children[1] else entry),.negative=negative}); } return out.items; }
pub const Type=struct { name:[]const u8,parent:[]const u8="object" };
pub const Predicate=struct { name:[]const u8,arguments:[]Typed,fluent:bool=false };
pub const Schema=struct { name:[]const u8,parameters:[]Typed,conditions:[]const Literal=&.{},effects:[]const Literal,cost:i64=1 };
pub const Domain=struct { name:[]const u8,types:[]Type,predicates:[]Predicate,actions:[]Schema };
pub const Problem=struct { name:[]const u8,objects:[]Typed,initial:[]const Atom,goals:[]const Atom,diagnostics:Text=.{} };
pub fn find(items:anytype,name:[]const u8) ?usize { for(items,0..) |item,i| if(eq(item.name,name)) return i; return null; }
pub fn domain(text:[]const u8) Domain {
    const expr=expressions(text)[0]; var types:std.ArrayList(Type)=.empty; append(Type,&types,.{.name="object"}); var predicates:std.ArrayList(Predicate)=.empty; var actions:std.ArrayList(Schema)=.empty;
    for(expr.children[2..]) |section| { const key=section.children[0].word;
        if(eq(key,":types")) { for(section.children[1..]) |word| if(!eq(word.word,"-") and find(types.items,word.word)==null) append(Type,&types,.{.name=word.word}); const declarations=typed(section.children[1..]); for(declarations) |entry| types.items[find(types.items,entry.name).?].parent=entry.typ; }
        else if(eq(key,":predicates")) { for(section.children[1..]) |decl| append(Predicate,&predicates,.{.name=decl.children[0].word,.arguments=typed(decl.children[1..])}); }
        else if(eq(key,":action")) { var schema=Schema{.name=section.children[1].word,.parameters=&.{},.effects=&.{}}; var i:usize=2; while(i<section.children.len) : (i+=2) { const field=section.children[i].word; const value=section.children[i+1]; if(eq(field,":parameters")) schema.parameters=typed(value.children) else if(eq(field,":precondition")) schema.conditions=literals(value) else { var effects:std.ArrayList(Literal)=.empty; const entries=if(eq(value.children[0].word,"and")) value.children[1..] else &[_]*Expr{value}; for(entries) |entry| { if(eq(entry.children[0].word,"increase")) schema.cost=number(entry.children[2].word) else { const negative=eq(entry.children[0].word,"not"); append(Literal,&effects,.{.atom=atom(if(negative) entry.children[1] else entry),.negative=negative}); } } schema.effects=effects.items; } } append(Schema,&actions,schema); }
    }
    return .{.name=expr.children[1].children[1].word,.types=types.items,.predicates=predicates.items,.actions=actions.items};
}
pub fn problems(text:[]const u8) []Problem { var out:std.ArrayList(Problem)=.empty; for(expressions(text)) |expr| { var problem=Problem{.name=expr.children[1].children[1].word,.objects=&.{},.initial=&.{},.goals=&.{}}; for(expr.children[2..]) |section| { const key=section.children[0].word; if(eq(key,":objects")) problem.objects=typed(section.children[1..]) else if(eq(key,":init")) { const initial=alloc(Atom,section.children.len-1); for(section.children[1..],initial) |entry,*value| value.*=atom(entry); problem.initial=initial; } else if(eq(key,":goal")) { const list=literals(section.children[1]); const goals=alloc(Atom,list.len); for(list,goals) |lit,*goal| goal.*=lit.atom; problem.goals=goals; } } append(Problem,&out,problem); } return out.items; }
pub fn sameAtom(a:Atom,b:Atom) bool { if(!eq(a.predicate,b.predicate) or a.terms.len!=b.terms.len) return false; for(a.terms,b.terms) |x,y| if(!eq(x,y)) return false; return true; }
pub fn atomIndex(atoms:[]const Atom,value:Atom) ?usize { for(atoms,0..) |a,i| if(sameAtom(a,value)) return i; return null; }
pub fn substitute(a:Atom,params:[]const Typed,args:[]const []const u8) Atom { const terms=alloc([]const u8,a.terms.len); for(a.terms,terms) |term,*value| value.*=args[find(params,term).?]; return .{.predicate=a.predicate,.terms=terms}; }
pub fn read(io:std.Io,path:[]const u8) ![]const u8 { return std.Io.Dir.cwd().readFileAlloc(io,path,allocator,.unlimited); }
pub fn write(io:std.Io,name:[]const u8,text:Text) !void { try std.Io.Dir.cwd().writeFile(io,.{.sub_path=fmt("output/{s}",.{name}),.data=text.data.items}); }
