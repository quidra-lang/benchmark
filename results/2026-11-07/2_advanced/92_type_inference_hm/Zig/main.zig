const std=@import("std");
const u=@import("unifier.zig");
const lexer=@import("lexer.zig");
const p=@import("parser.zig");
const inference=@import("inference.zig");
const evaluator=@import("evaluator.zig");
const Node=p.Node;
const Signature=struct { name:[]const u8,node:*Node,position:u.Position };
fn signatureType(n:*Node,variables:*std.StringHashMap(*u.Type)) *u.Type {
    const k=n.kind; if(u.eq(k,"int")) return u.primitive(.integer); if(u.eq(k,"bool")) return u.primitive(.boolean); if(u.eq(k,"string")) return u.primitive(.string);
    if(u.eq(k,"typevar")) { if(variables.get(n.value)) |t| return t; const t=u.fresh(); variables.put(n.value,t) catch @panic("allocation failed"); return t; }
    return u.construct(if(u.eq(k,"list")) .list else if(u.eq(k,"pair")) .pair else .function,signatureType(n.children[0],variables),if(n.children.len>1) signatureType(n.children[1],variables) else null);
}
fn sameType(a0:*u.Type,b0:*u.Type) bool { const a=u.resolve(a0); const b=u.resolve(b0); if(a==b) return true; if(a.kind!=b.kind or a.kind==.variable) return false; if(a.a!=null and !sameType(a.a.?,b.a.?)) return false; if(a.b!=null and !sameType(a.b.?,b.b.?)) return false; return true; }
fn matchesSignature(a0:*u.Type,b0:*u.Type,map:*std.AutoHashMap(usize,*u.Type)) bool { const a=u.resolve(a0); const b=u.resolve(b0); if(a.kind==.variable) { if(map.get(a.id)) |old| return sameType(old,b); map.put(a.id,b) catch @panic("allocation failed"); return true; } if(a.kind!=b.kind) return false; if(a.a!=null and !matchesSignature(a.a.?,b.a.?,map)) return false; if(a.b!=null and !matchesSignature(a.b.?,b.b.?,map)) return false; return true; }
fn signatureFormat(n:*Node) []const u8 {
    if(n.children.len==0) return if(u.eq(n.kind,"typevar")) n.value else n.kind;
    var a=signatureFormat(n.children[0]); const ak=n.children[0].kind; if(((u.eq(n.kind,"list") or u.eq(n.kind,"pair")) and (u.eq(ak,"pair") or u.eq(ak,"function"))) or (u.eq(n.kind,"function") and u.eq(ak,"function"))) a=u.fmt("({s})",.{a});
    if(u.eq(n.kind,"list")) return u.fmt("{s} list",.{a}); var b=signatureFormat(n.children[1]); const bk=n.children[1].kind; if(u.eq(n.kind,"pair") and (u.eq(bk,"pair") or u.eq(bk,"function"))) b=u.fmt("({s})",.{b}); return u.fmt("{s}{s}{s}",.{a,if(u.eq(n.kind,"pair")) " * " else " -> ",b});
}
fn bindingFormat(binding:p.Binding) []const u8 { var out:u.Text=.{}; out.put("{s}",.{binding.name}); var body=binding.expression; while(u.eq(body.kind,"fun")) { out.put(" {s}",.{body.value}); body=body.children[0]; } out.put(" = {s}",.{format(body,0)}); return out.data.items; }
fn groupFormat(n:*Node) []const u8 { var out:u.Text=.{}; out.put("let {s}",.{if(n.recursive) "rec " else ""}); for(n.bindings,0..) |binding,i| { if(i>0) out.put(" and ",.{}); out.put("{s}",.{bindingFormat(binding)}); } return out.data.items; }
fn strength(n:*Node) usize { const k=n.kind; if(u.eq(k,"let") or u.eq(k,"fun") or u.eq(k,"if") or u.eq(k,"match")) return 0; if(u.eq(k,"binary")) return p.precedence(n.value); if(u.eq(k,"neg")) return 7; if(u.eq(k,"apply")) return 8; return 9; }
fn endsMatch(n:*Node) bool { if(u.eq(n.kind,"match")) return true; if(u.eq(n.kind,"fun") or u.eq(n.kind,"let")) return endsMatch(n.children[0]); if(u.eq(n.kind,"if")) return endsMatch(n.children[2]); return false; }
fn format(n:*Node,required:usize) []const u8 {
    const k=n.kind; var result:[]const u8=undefined;
    if(u.eq(k,"integer")) result=u.fmt("{d}",.{std.fmt.parseInt(i64,n.value,10) catch unreachable})
    else if(u.eq(k,"string")) result=evaluator.escaped(n.value)
    else if(u.eq(k,"name") or u.eq(k,"wildcard") or u.eq(k,"boolean")) result=if(u.eq(k,"wildcard")) "_" else n.value
    else if(u.eq(k,"pair")) result=u.fmt("({s}, {s})",.{format(n.children[0],0),format(n.children[1],0)})
    else if(u.eq(k,"list")) { var out:u.Text=.{}; out.put("[",.{}); for(n.children,0..) |child,i| { if(i>0) out.put("; ",.{}); out.put("{s}",.{format(child,0)}); } out.put("]",.{}); result=out.data.items; }
    else if(u.eq(k,"cons")) { const left=format(n.children[0],0); result=u.fmt("{s} :: {s}",.{if(u.eq(n.children[0].kind,"cons")) u.fmt("({s})",.{left}) else left,format(n.children[1],0)}); }
    else if(u.eq(k,"neg")) result=u.fmt("-{s}",.{format(n.children[0],7)})
    else if(u.eq(k,"binary")) { const level=p.precedence(n.value); const right=p.rightAssociative(level); result=u.fmt("{s} {s} {s}",.{format(n.children[0],level+@intFromBool(right)),n.value,format(n.children[1],level+@intFromBool(!right))}); }
    else if(u.eq(k,"apply")) result=u.fmt("{s} {s}",.{format(n.children[0],8),format(n.children[1],9)})
    else if(u.eq(k,"if")) result=u.fmt("if {s} then {s} else {s}",.{format(n.children[0],0),format(n.children[1],0),format(n.children[2],0)})
    else if(u.eq(k,"fun")) { var out:u.Text=.{}; out.put("fun",.{}); var body=n; while(u.eq(body.kind,"fun")) { out.put(" {s}",.{body.value}); body=body.children[0]; } out.put(" -> {s}",.{format(body,0)}); result=out.data.items; }
    else if(u.eq(k,"let")) result=u.fmt("{s} in {s}",.{groupFormat(n),format(n.children[0],0)})
    else { var out:u.Text=.{}; out.put("match {s} with ",.{format(n.children[0],0)}); for(n.arms,0..) |arm,i| { if(i>0) out.put(" | ",.{}); var body=format(arm.expression,0); if(i+1<n.arms.len and endsMatch(arm.expression)) body=u.fmt("({s})",.{body}); out.put("{s} -> {s}",.{format(arm.pattern,0),body}); } result=out.data.items; }
    return if(strength(n)<required) u.fmt("({s})",.{result}) else result;
}
fn recursiveMark(mark:?*p.Mark,bindings:[]const p.Binding) bool { if(mark==null) return false; for(bindings) |binding| if(binding.mark==mark) return true; return false; }
fn recursion(n:*Node,bindings:[]const p.Binding,tail:bool,result:*[2]usize) void {
    if(u.eq(n.kind,"name") and recursiveMark(n.mark,bindings)) { result[0]+=1; result[1]+=1; return; }
    if(u.eq(n.kind,"apply")) { var head=n; var args:std.ArrayList(*Node)=.empty; while(u.eq(head.kind,"apply")) { u.append(*Node,&args,head.children[1]); head=head.children[0]; } if(u.eq(head.kind,"name") and recursiveMark(head.mark,bindings)) { result[0]+=1; result[1]+=@intFromBool(!tail); } else recursion(head,bindings,false,result); for(args.items) |argument| recursion(argument,bindings,false,result); return; }
    if(u.eq(n.kind,"if")) { recursion(n.children[0],bindings,false,result); recursion(n.children[1],bindings,tail,result); recursion(n.children[2],bindings,tail,result); return; }
    if(u.eq(n.kind,"match")) { recursion(n.children[0],bindings,false,result); for(n.arms) |arm| recursion(arm.expression,bindings,tail,result); return; }
    if(u.eq(n.kind,"let")) { for(n.bindings) |binding| recursion(binding.expression,bindings,false,result); recursion(n.children[0],bindings,tail,result); return; }
    if(u.eq(n.kind,"binary") and (u.eq(n.value,"&&") or u.eq(n.value,"||"))) { recursion(n.children[0],bindings,false,result); recursion(n.children[1],bindings,tail,result); return; }
    for(n.children) |child| recursion(child,bindings,false,result);
}
fn classify(n:*Node) void { if(n.recursive) for(n.bindings) |*binding| { var body=binding.expression; while(u.eq(body.kind,"fun")) body=body.children[0]; var result=[_]usize{0,0}; recursion(body,n.bindings,true,&result); binding.classification=if(result[0]==0) "" else if(result[1]==0) " (tail recursive)" else " (recursive)"; }; for(n.bindings) |binding| classify(binding.expression); for(n.children) |child| classify(child); for(n.arms) |arm| classify(arm.expression); }
const Pattern=struct { tag:[]const u8="any",value:[]const u8="",children:[]const *Pattern=&.{} };
fn pattern(tag:[]const u8,value:[]const u8,children:[]const *Pattern) *Pattern { const cs=u.alloc(*Pattern,children.len); @memcpy(cs,children); return u.create(Pattern,.{.tag=tag,.value=value,.children=cs}); }
fn normalizePattern(n:*Node) *Pattern {
    const k=n.kind; if(u.eq(k,"wildcard") or u.eq(k,"name")) return pattern("any","",&.{});
    if(u.eq(k,"list")) { var tail=pattern("nil","",&.{}); var i=n.children.len; while(i>0) { i-=1; tail=pattern("cons","",&.{normalizePattern(n.children[i]),tail}); } return tail; }
    if(u.eq(k,"pair") or u.eq(k,"cons")) return pattern(k,"",&.{normalizePattern(n.children[0]),normalizePattern(n.children[1])});
    return pattern(k,if(u.eq(k,"integer")) u.fmt("{d}",.{std.fmt.parseInt(i64,n.value,10) catch unreachable}) else n.value,&.{});
}
fn sameConstructor(a:*Pattern,b:*Pattern) bool { return u.eq(a.tag,b.tag) and u.eq(a.value,b.value); }
const Matrix=[]const []const *Pattern;
fn appendPatterns(a:[]const *Pattern,b:[]const *Pattern) []const *Pattern { const out=u.alloc(*Pattern,a.len+b.len); @memcpy(out[0..a.len],a); @memcpy(out[a.len..],b); return out; }
fn specialize(matrix:Matrix,constructor:*Pattern) Matrix { var out:std.ArrayList([]const *Pattern)=.empty; for(matrix) |row| { if(u.eq(row[0].tag,"any")) { const heads=u.alloc(*Pattern,constructor.children.len); for(heads) |*h| h.*=pattern("any","",&.{}); u.append([]const *Pattern,&out,appendPatterns(heads,row[1..])); } else if(sameConstructor(row[0],constructor)) u.append([]const *Pattern,&out,appendPatterns(row[0].children,row[1..])); } return out.items; }
fn constructorTypes(t0:*u.Type,constructor:*Pattern) []const *u.Type { const t=u.resolve(t0); if(u.eq(constructor.tag,"pair") or u.eq(constructor.tag,"cons")) { const out=u.alloc(*u.Type,2); out[0]=t.a.?; out[1]=if(u.eq(constructor.tag,"pair")) t.b.? else t; return out; } return &.{}; }
fn appendTypes(a:[]const *u.Type,b:[]const *u.Type) []const *u.Type { const out=u.alloc(*u.Type,a.len+b.len); @memcpy(out[0..a.len],a); @memcpy(out[a.len..],b); return out; }
fn useful(matrix:Matrix,vector:[]const *Pattern,types:[]const *u.Type) bool {
    if(vector.len==0) return matrix.len==0; const first=vector[0]; const typ=u.resolve(types[0]);
    if(!u.eq(first.tag,"any")) return useful(specialize(matrix,first),appendPatterns(first.children,vector[1..]),appendTypes(constructorTypes(typ,first),types[1..]));
    var constructors:[]const *Pattern=&.{};
    if(typ.kind==.boolean) constructors=&.{pattern("boolean","false",&.{}),pattern("boolean","true",&.{})}
    else if(typ.kind==.pair) constructors=&.{pattern("pair","",&.{pattern("any","",&.{}),pattern("any","",&.{})})}
    else if(typ.kind==.list) constructors=&.{pattern("nil","",&.{}),pattern("cons","",&.{pattern("any","",&.{}),pattern("any","",&.{})})};
    var complete=constructors.len>0; for(constructors) |ctor| { var exists=false; for(matrix) |row| if(sameConstructor(row[0],ctor)) { exists=true; break; }; if(!exists) complete=false; }
    if(complete) { for(constructors) |ctor| { const heads=u.alloc(*Pattern,ctor.children.len); for(heads) |*h| h.*=pattern("any","",&.{}); if(useful(specialize(matrix,ctor),appendPatterns(heads,vector[1..]),appendTypes(constructorTypes(typ,ctor),types[1..]))) return true; } return false; }
    var defaults:std.ArrayList([]const *Pattern)=.empty; for(matrix) |row| if(u.eq(row[0].tag,"any")) u.append([]const *Pattern,&defaults,row[1..]); return useful(defaults.items,vector[1..],types[1..]);
}
const Warning=struct { position:u.Position,message:[]const u8,order:usize };
fn warningWalk(n:*Node,warnings:*std.ArrayList(Warning)) void {
    if(u.eq(n.kind,"match")) { var matrix:std.ArrayList([]const *Pattern)=.empty; const typ=n.children[0].typ.?;
        for(n.arms,0..) |arm,i| { const row=u.alloc(*Pattern,1); row[0]=normalizePattern(arm.pattern); if(i>0 and !useful(matrix.items,row,&.{typ})) u.append(Warning,warnings,.{.position=arm.pattern.position,.message="this match case is unused",.order=2}); u.append([]const *Pattern,&matrix,row); }
        if(useful(matrix.items,&.{pattern("any","",&.{})},&.{typ})) u.append(Warning,warnings,.{.position=n.position,.message="this match is not exhaustive",.order=1});
    }
    if(n.recursive and !n.rec_used) u.append(Warning,warnings,.{.position=n.rec_position,.message="unused rec flag",.order=3});
    for(n.bindings) |binding| warningWalk(binding.expression,warnings); for(n.children) |child| warningWalk(child,warnings); for(n.arms) |arm| warningWalk(arm.expression,warnings);
}
fn before(a:u.Position,b:u.Position) bool { return a.line<b.line or (a.line==b.line and a.column<b.column); }
const Stats=struct { items:usize=0,bindings:usize=0,syntax:usize=0,types:usize=0,runtime:usize=0,warnings:usize=0,calls:usize=0 };
const names=[_][]const u8{"prelude.ml","program.ml"};
fn report(text:*u.Text,sources:[2][]const []const u8,kind:[]const u8,failure:u.Failure) void {
    const pos=failure.position; text.line("{s}:{d}:{d}: {s}: {s}",.{names[pos.file],pos.line,pos.column,kind,failure.message});
    if(pos.line<=sources[pos.file].len) { text.line("    {s}",.{sources[pos.file][pos.line-1]}); const spaces=u.alloc(u8,pos.column+3); @memset(spaces,' '); text.line("{s}^",.{spaces}); }
}
fn builtins() struct { types:inference.Environment,values:evaluator.Environment } {
    var types:inference.Environment=&.{}; var values:evaluator.Environment=&.{};
    for([_][]const u8{"fst","snd","not","string_of_int","failwith"}) |name| {
        const a=u.fresh(); const b=u.fresh(); var typ:*u.Type=undefined;
        if(u.eq(name,"fst") or u.eq(name,"snd")) typ=u.construct(.function,u.construct(.pair,a,b),if(u.eq(name,"fst")) a else b)
        else if(u.eq(name,"not")) typ=u.construct(.function,u.primitive(.boolean),u.primitive(.boolean))
        else if(u.eq(name,"string_of_int")) typ=u.construct(.function,u.primitive(.integer),u.primitive(.string))
        else typ=u.construct(.function,u.primitive(.string),a);
        types=inference.extend(types,.{.name=name,.scheme=u.generalize(typ,@as(inference.Environment,&.{}))}); const v=evaluator.value(.builtin); v.string=name; values=evaluator.extend(values,.{.name=name,.value=v});
    }
    return .{.types=types,.values=values};
}
fn read(io:std.Io,path:[]const u8) ![]const u8 { return std.Io.Dir.cwd().readFileAlloc(io,path,u.allocator,.unlimited); }
fn splitLines(text:[]const u8) []const []const u8 { var out:std.ArrayList([]const u8)=.empty; var it=std.mem.splitScalar(u8,text,'\n'); while(it.next()) |line| u.append([]const u8,&out,line); return out.items[0..out.items.len-1]; }
fn write(io:std.Io,name:[]const u8,text:u.Text) !void { try std.Io.Dir.cwd().writeFile(io,.{.sub_path=u.fmt("output/{s}",.{name}),.data=text.data.items}); }
pub fn main(init:std.process.Init) !void {
    var arena:std.heap.ArenaAllocator=.init(init.gpa); defer arena.deinit(); u.allocator=arena.allocator();
    const source_text=[_] []const u8{try read(init.io,"input/prelude.ml"),try read(init.io,"input/program.ml")}; const sources=[_] []const []const u8{splitLines(source_text[0]),splitLines(source_text[1])}; const initial=builtins(); var type_env=initial.types; var value_env=initial.values;
    var types:u.Text=.{}; var values:u.Text=.{}; var errors:u.Text=.{}; var formatted:u.Text=.{}; var statistics=[_]Stats{.{},.{}};
    for(0..2) |file| {
        types.line("== {s} ==",.{names[file]}); values.line("== {s} ==",.{names[file]}); formatted.line("(* {s} *)",.{names[file]}); var pending:std.ArrayList(Signature)=.empty; var parser=p.Parser{.tokens=lexer.scan(source_text[file],file)}; const stats=&statistics[file];
        while(parser.current().kind!=.eof) {
            stats.items+=1; const item=parser.item() catch { stats.syntax+=1; report(&errors,sources,"syntax error",parser.failure.?); while(parser.current().kind!=.eof and !u.eq(parser.current().value,";;")) parser.at+=1; if(parser.current().kind!=.eof) parser.at+=1; continue; };
            switch(item.kind) { .signature=>formatted.line("val {s} : {s};;",.{item.name,signatureFormat(item.signature.?)}),.declaration=>formatted.line("{s};;",.{groupFormat(item.node)}),.expression=>formatted.line("{s};;",.{format(item.node,0)}) }
            if(item.kind==.signature) { var old:?usize=null; for(pending.items,0..) |s,i| if(u.eq(s.name,item.name)) { old=i; break; }; if(old) |i| { const s=pending.orderedRemove(i); stats.warnings+=1; report(&errors,sources,"warning",.{.position=s.position,.message=u.fmt("signature for '{s}' is never used",.{s.name})}); } u.append(Signature,&pending,.{.name=item.name,.node=item.signature.?,.position=item.position}); continue; }
            const signatures=u.alloc(?Signature,item.node.bindings.len); @memset(signatures,null);
            if(item.kind==.declaration) for(item.node.bindings,0..) |binding,i| { for(pending.items,0..) |s,j| if(u.eq(s.name,binding.name)) { signatures[i]=pending.orderedRemove(j); break; }; };
            var infer:inference.Infer=.{}; var new_types=type_env; var result_type:?*u.Type=null;
            if(item.kind==.declaration) new_types=infer.group(item.node,type_env,true) catch { stats.types+=1; report(&errors,sources,"type error",infer.failure.?); continue; }
            else result_type=infer.expression(item.node,type_env) catch { stats.types+=1; report(&errors,sources,"type error",infer.failure.?); continue; };
            var signature_error=false;
            if(item.kind==.declaration) for(item.node.bindings,signatures) |*binding,signature| if(signature) |s| {
                var variables=std.StringHashMap(*u.Type).init(u.allocator); const declared=signatureType(s.node,&variables); var map=std.AutoHashMap(usize,*u.Type).init(u.allocator);
                if(!matchesSignature(binding.scheme.?.typ,declared,&map)) { var printer:u.TypePrinter=.{}; const inferred=printer.print(binding.scheme.?.typ,null); const expected=printer.print(declared,null); stats.types+=1; report(&errors,sources,"type error",.{.position=binding.position,.message=u.fmt("'{s}' has type {s} but its signature is {s}",.{binding.name,inferred,expected})}); signature_error=true; break; }
                binding.scheme=u.generalize(declared,@as(inference.Environment,&.{})); new_types=inference.extend(new_types,.{.name=binding.name,.scheme=binding.scheme.?,.mark=binding.mark});
            };
            if(signature_error) continue; classify(item.node);
            if(item.kind==.declaration) for(item.node.bindings) |binding| { var printer:u.TypePrinter=.{}; types.line("{s} : {s}{s}",.{binding.name,printer.print(binding.scheme.?.typ,null),binding.classification}); }
            else { var printer:u.TypePrinter=.{}; types.line("- : {s}",.{printer.print(result_type.?,null)}); }
            std.mem.sort(*p.Binding,infer.locals.items,{},struct { fn less(_:void,a:*p.Binding,b:*p.Binding) bool { return before(a.position,b.position); } }.less);
            for(infer.locals.items) |binding| { var printer:u.TypePrinter=.{}; types.line("  {s} ({d}:{d}) : {s}{s}",.{binding.name,binding.position.line,binding.position.column,printer.print(binding.scheme.?.typ,binding.scheme.?.quantified),binding.classification}); }
            var warnings:std.ArrayList(Warning)=.empty; warningWalk(item.node,&warnings); for(infer.marks.items) |mark| if(!mark.top and mark.uses==0 and !std.mem.startsWith(u8,mark.name,"_")) u.append(Warning,&warnings,.{.position=mark.position,.message=u.fmt("unused variable '{s}'",.{mark.name}),.order=4});
            std.mem.sort(Warning,warnings.items,{},struct { fn less(_:void,a:Warning,b:Warning) bool { if(a.position.line!=b.position.line or a.position.column!=b.position.column) return before(a.position,b.position); return a.order<b.order; } }.less);
            for(warnings.items) |warning| { stats.warnings+=1; report(&errors,sources,"warning",.{.position=warning.position,.message=warning.message}); }
            var eval:evaluator.Evaluator=.{}; var new_values=value_env; var result_value:?*evaluator.Value=null;
            if(item.kind==.declaration) new_values=eval.group(item.node,value_env) catch { stats.calls+=eval.calls; stats.runtime+=1; report(&errors,sources,"runtime error",eval.failure.?); continue; }
            else result_value=eval.expression(item.node,value_env) catch { stats.calls+=eval.calls; stats.runtime+=1; report(&errors,sources,"runtime error",eval.failure.?); continue; };
            stats.calls+=eval.calls;
            if(item.kind==.declaration) { for(item.node.bindings) |binding| { for(new_values) |entry| if(u.eq(entry.name,binding.name)) { values.line("{s} = {s}",.{binding.name,evaluator.print(entry.value)}); break; }; } stats.bindings+=item.node.bindings.len; type_env=new_types; value_env=new_values; }
            else values.line("- = {s}",.{evaluator.print(result_value.?)});
        }
        std.mem.sort(Signature,pending.items,{},struct { fn less(_:void,a:Signature,b:Signature) bool { return before(a.position,b.position); } }.less); for(pending.items) |s| { stats.warnings+=1; report(&errors,sources,"warning",.{.position=s.position,.message=u.fmt("signature for '{s}' is never used",.{s.name})}); }
    }
    errors.line("== summary ==",.{}); for(statistics,names) |stats,name| errors.line("{s}: items={d} bindings={d} syntax={d} type={d} runtime={d} warnings={d} calls={d}",.{name,stats.items,stats.bindings,stats.syntax,stats.types,stats.runtime,stats.warnings,stats.calls});
    try write(init.io,"types.txt",types); try write(init.io,"values.txt",values); try write(init.io,"errors.txt",errors); try write(init.io,"formatted.ml",formatted);
}
