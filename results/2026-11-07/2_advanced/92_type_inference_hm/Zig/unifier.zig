const std = @import("std");
pub var allocator: std.mem.Allocator = undefined;
pub fn alloc(comptime T:type,n:usize) []T { return allocator.alloc(T,n) catch @panic("allocation failed"); }
pub fn create(comptime T:type,v:T) *T { const p=allocator.create(T) catch @panic("allocation failed"); p.*=v; return p; }
pub fn append(comptime T:type,a:*std.ArrayList(T),v:T) void { a.append(allocator,v) catch @panic("allocation failed"); }
pub fn fmt(comptime s:[]const u8,a:anytype) []const u8 { return std.fmt.allocPrint(allocator,s,a) catch @panic("allocation failed"); }
pub fn eq(a:[]const u8,b:[]const u8) bool { return std.mem.eql(u8,a,b); }
pub const Text=struct { data:std.ArrayList(u8)=.empty, pub fn put(self:*Text,comptime s:[]const u8,a:anytype) void { self.data.appendSlice(allocator,fmt(s,a)) catch @panic("allocation failed"); } pub fn line(self:*Text,comptime s:[]const u8,a:anytype) void { self.put(s,a); self.put("\n",.{}); } };
pub const Position=struct { file:usize=0,line:usize=1,column:usize=1 };
pub const Failure=struct { position:Position,message:[]const u8 };
pub const Kind=enum { variable, integer, boolean, string, list, pair, function, rigid };
pub const Type=struct { kind:Kind, id:usize=0, link:?*Type=null, a:?*Type=null,b:?*Type=null, spelling:[]const u8="" };
var next_id:usize=0;
pub fn fresh() *Type { const t=create(Type,.{.kind=.variable,.id=next_id}); next_id+=1; return t; }
pub fn primitive(kind:Kind) *Type { return create(Type,.{.kind=kind}); }
pub fn construct(kind:Kind,a:*Type,b:?*Type) *Type { return create(Type,.{.kind=kind,.a=a,.b=b}); }
pub fn resolve(t:*Type) *Type { if(t.link) |link| { t.link=resolve(link); return t.link.?; } return t; }
pub fn occurs(v:*Type,t0:*Type) bool { const t=resolve(t0); if(v==t) return true; if(t.a) |a| if(occurs(v,a)) return true; if(t.b) |b| if(occurs(v,b)) return true; return false; }
pub const Failed=struct { expected:*Type,found:*Type,infinite:bool=false };
pub fn unify(e0:*Type,f0:*Type) ?Failed {
    const e=resolve(e0); const f=resolve(f0); if(e==f) return null;
    if(e.kind==.variable) { if(occurs(e,f)) return .{.expected=e,.found=f,.infinite=true}; e.link=f; return null; }
    if(f.kind==.variable) { if(occurs(f,e)) return .{.expected=e,.found=f,.infinite=true}; f.link=e; return null; }
    if(e.kind!=f.kind or (e.kind==.rigid and !eq(e.spelling,f.spelling))) return .{.expected=e,.found=f};
    if(e.a) |a| if(unify(a,f.a.?)) |failure| return failure;
    if(e.b) |b| if(unify(b,f.b.?)) |failure| return failure; return null;
}
pub const Scheme=struct { typ:*Type,quantified:[]const usize=&.{} };
pub fn contains(ids:[]const usize,id:usize) bool { for(ids) |v| if(v==id) return true; return false; }
pub fn free(t0:*Type,out:*std.ArrayList(usize)) void { const t=resolve(t0); if(t.kind==.variable and !contains(out.items,t.id)) append(usize,out,t.id); if(t.a) |a| free(a,out); if(t.b) |b| free(b,out); }
pub fn generalize(t:*Type,environment:anytype) Scheme {
    var all:std.ArrayList(usize)=.empty; free(t,&all); var blocked:std.ArrayList(usize)=.empty;
    for(environment) |entry| { var variables:std.ArrayList(usize)=.empty; free(entry.scheme.typ,&variables); for(variables.items) |id| if(!contains(entry.scheme.quantified,id) and !contains(blocked.items,id)) append(usize,&blocked,id); }
    var q:std.ArrayList(usize)=.empty; for(all.items) |id| if(!contains(blocked.items,id)) append(usize,&q,id); return .{.typ=t,.quantified=q.items};
}
fn instantiateType(t0:*Type,q:[]const usize,replacements:[]*Type) *Type { const t=resolve(t0); if(t.kind==.variable) { for(q,0..) |id,i| if(id==t.id) return replacements[i]; return t; } if(t.a) |a| return construct(t.kind,instantiateType(a,q,replacements),if(t.b) |b| instantiateType(b,q,replacements) else null); return t; }
pub fn instantiate(s:Scheme) *Type { const replacements=alloc(*Type,s.quantified.len); for(replacements) |*t| t.*=fresh(); return instantiateType(s.typ,s.quantified,replacements); }
pub const TypePrinter=struct {
    variables:std.ArrayList(*Type)=.empty,
    pub fn print(self:*TypePrinter,t0:*Type,local:?[]const usize) []const u8 {
        const t=resolve(t0);
        if(t.kind==.variable or t.kind==.rigid) { var id:?usize=null; for(self.variables.items,0..) |v,i| if(v==t) { id=i; break; }; if(id==null) { id=self.variables.items.len; append(*Type,&self.variables,t); } const k=id.?; const weak=if(local) |q| t.kind==.variable and !contains(q,t.id) else false; return fmt("'{s}{c}{s}",.{if(weak) "_" else "",@as(u8,'a')+@as(u8,@intCast(k%26)),if(k<26) "" else fmt("{d}",.{k/26})}); }
        if(t.kind==.integer) return "int"; if(t.kind==.boolean) return "bool"; if(t.kind==.string) return "string";
        const a=resolve(t.a.?); var left=self.print(a,local); if((t.kind==.list or t.kind==.pair) and (a.kind==.pair or a.kind==.function) or (t.kind==.function and a.kind==.function)) left=fmt("({s})",.{left});
        if(t.kind==.list) return fmt("{s} list",.{left}); const b=resolve(t.b.?); var right=self.print(b,local); if(t.kind==.pair and (b.kind==.pair or b.kind==.function)) right=fmt("({s})",.{right}); return fmt("{s}{s}{s}",.{left,if(t.kind==.pair) " * " else " -> ",right});
    }
};
