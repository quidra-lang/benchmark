const std=@import("std");
const p=@import("pddl_parser.zig");
pub const Set=u256;
pub fn bit(i:usize) Set { return @as(Set,1)<<@intCast(i); }
pub fn subset(a:Set,b:Set) bool { return a&b==a; }
pub fn members(s:Set) []const usize { var list:std.ArrayList(usize)=.empty; for(0..256) |i| if(s&bit(i)!=0) p.append(usize,&list,i); return list.items; }
pub fn subtype(domain:p.Domain,child:[]const u8,parent:[]const u8) bool { var t=child; while(true) { if(p.eq(t,parent)) return true; if(p.eq(t,"object")) return false; t=domain.types[p.find(domain.types,t) orelse return false].parent; } }
pub fn fluent(domain:p.Domain,predicate:[]const u8) bool { return domain.predicates[p.find(domain.predicates,predicate).?].fluent; }
pub const Action=struct { source:usize,args:[]const []const u8,cost:i64,notation:[]const u8,pre:Set=0,neg:Set=0,add:Set=0,del:Set=0 };
pub const Counts=struct { assignments:usize=0,candidates:usize=0,reachable:usize=0 };
pub const Ground=struct { facts:[]const p.Atom,actions:[]const Action,initial:Set,goal:Set,unreachable:[]const p.Atom,counts:[]Counts,static_count:usize };
const Candidate=struct { source:usize,args:[]const []const u8,pre:[]const p.Atom,neg:[]const p.Atom,add:[]const p.Atom,del:[]const p.Atom,reachable:bool=false };
fn unique(list:*std.ArrayList(p.Atom),a:p.Atom) void { if(p.atomIndex(list.items,a)==null) p.append(p.Atom,list,a); }
fn enumerate(domain:p.Domain,problem:p.Problem,schema:usize,depth:usize,args:[][]const u8,counts:*Counts,out:*std.ArrayList(Candidate)) void {
    const action=domain.actions[schema]; if(depth<args.len) { for(problem.objects) |object| if(subtype(domain,object.typ,action.parameters[depth].typ)) { args[depth]=object.name; enumerate(domain,problem,schema,depth+1,args,counts,out); }; return; }
    counts.assignments+=1; var pre:std.ArrayList(p.Atom)=.empty; var neg:std.ArrayList(p.Atom)=.empty; var adds:std.ArrayList(p.Atom)=.empty; var deletes:std.ArrayList(p.Atom)=.empty;
    for(action.conditions) |literal| { const a=p.substitute(literal.atom,action.parameters,args); if(p.eq(a.predicate,"=") or !fluent(domain,a.predicate)) { const truth=if(p.eq(a.predicate,"=")) p.eq(a.terms[0],a.terms[1]) else p.atomIndex(problem.initial,a)!=null; if(truth==literal.negative) return; } else unique(if(literal.negative) &neg else &pre,a); }
    for(action.effects) |literal| unique(if(literal.negative) &deletes else &adds,p.substitute(literal.atom,action.parameters,args));
    const values=p.alloc([]const u8,args.len); @memcpy(values,args); counts.candidates+=1; p.append(Candidate,out,.{.source=schema,.args=values,.pre=pre.items,.neg=neg.items,.add=adds.items,.del=deletes.items});
}
fn atomSet(facts:[]const p.Atom,atoms:[]const p.Atom) Set { var set:Set=0; for(atoms) |a| if(p.atomIndex(facts,a)) |i| { set|=bit(i); }; return set; }
pub fn ground(domain:p.Domain,problem:p.Problem) Ground {
    const counts=p.alloc(Counts,domain.actions.len); @memset(counts,.{}); var candidates:std.ArrayList(Candidate)=.empty; for(domain.actions,0..) |action,i| enumerate(domain,problem,i,0,p.alloc([]const u8,action.parameters.len),&counts[i],&candidates);
    var facts:std.ArrayList(p.Atom)=.empty; var static_count:usize=0; for(problem.initial) |a| { if(fluent(domain,a.predicate)) unique(&facts,a) else static_count+=1; }
    while(true) { var changed=false; for(candidates.items) |*candidate| { if(candidate.reachable) continue; var reachable=true; for(candidate.pre) |a| if(p.atomIndex(facts.items,a)==null) { reachable=false; break; }; if(reachable) { candidate.reachable=true; changed=true; counts[candidate.source].reachable+=1; for(candidate.add) |a| unique(&facts,a); } } if(!changed) break; }
    const Context=struct { domain:p.Domain,problem:p.Problem }; std.mem.sort(p.Atom,facts.items,Context{.domain=domain,.problem=problem},struct { fn less(ctx:Context,a:p.Atom,b:p.Atom) bool { const ap=p.find(ctx.domain.predicates,a.predicate).?; const bp=p.find(ctx.domain.predicates,b.predicate).?; if(ap!=bp) return ap<bp; for(a.terms,b.terms) |x,y| { const xi=p.find(ctx.problem.objects,x).?; const yi=p.find(ctx.problem.objects,y).?; if(xi!=yi) return xi<yi; } return false; } }.less);
    var actions:std.ArrayList(Action)=.empty; for(candidates.items) |candidate| if(candidate.reachable) { const schema=domain.actions[candidate.source]; const add=atomSet(facts.items,candidate.add); p.append(Action,&actions,.{.source=candidate.source,.args=candidate.args,.cost=schema.cost,.notation=(p.Atom{.predicate=schema.name,.terms=candidate.args}).notation(),.pre=atomSet(facts.items,candidate.pre),.neg=atomSet(facts.items,candidate.neg),.add=add,.del=atomSet(facts.items,candidate.del)&~add}); };
    var goal:Set=0; var unreachable:std.ArrayList(p.Atom)=.empty; for(problem.goals) |a| { if(p.atomIndex(facts.items,a)) |i| goal|=bit(i) else if(fluent(domain,a.predicate) or p.atomIndex(problem.initial,a)==null) p.append(p.Atom,&unreachable,a); }
    return .{.facts=facts.items,.actions=actions.items,.initial=atomSet(facts.items,problem.initial),.goal=goal,.unreachable=unreachable.items,.counts=counts,.static_count=static_count};
}
