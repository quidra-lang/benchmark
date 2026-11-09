const std=@import("std");
const p=@import("pddl_parser.zig");
const g=@import("grounding.zig");
const search=@import("search.zig");
const Element=struct { action:?usize,noop:?usize=null,pre:g.Set,add:g.Set,del:g.Set };
const Level=struct { facts:g.Set,mutex:[]g.Set,elements:[]const Element=&.{},action_mutex:[]u512=&.{} };
const Memo=struct { level:usize,goals:g.Set };
pub const Result=struct { search:search.Result,layers:[]const []const usize=&.{},memo_hits:usize=0 };
fn actionBit(i:usize) u512 { return @as(u512,1)<<@intCast(i); }
fn compatible(set:g.Set,mutex:[]const g.Set) bool { for(g.members(set)) |q| if(mutex[q]&set!=0) return false; return true; }
fn pairs(mutex:anytype) usize { var count:usize=0; for(mutex) |row| count+=@popCount(row); return count/2; }
const Extractor=struct {
    levels:*std.ArrayList(Level),memo:std.AutoHashMap(Memo,void),searched:usize=0,hits:usize=0,tried:usize=0,
    fn extract(self:*Extractor,level:usize,goals:g.Set) ?[]const []const usize {
        if(level==0) return &.{}; const key=Memo{.level=level,.goals=goals}; if(self.memo.contains(key)) { self.hits+=1; return null; } self.searched+=1;
        const result=self.assign(level,g.members(goals),0,&.{}); if(result==null) self.memo.put(key,{}) catch @panic("allocation failed"); return result;
    }
    fn assign(self:*Extractor,level:usize,goals:[]const usize,start:usize,chosen:[]const usize) ?[]const []const usize {
        const previous=self.levels.items[level-1]; var covered:g.Set=0; for(chosen) |e| covered|=previous.elements[e].add; var at=start; while(at<goals.len and covered&g.bit(goals[at])!=0) at+=1;
        if(at==goals.len) { var pre:g.Set=0; for(chosen) |e| pre|=previous.elements[e].pre; const earlier=self.extract(level-1,pre) orelse return null; var actions:std.ArrayList(usize)=.empty; for(chosen) |e| if(previous.elements[e].action) |a| p.append(usize,&actions,a); std.mem.sort(usize,actions.items,{},std.sort.asc(usize)); const result=p.alloc([]const usize,earlier.len+1); @memcpy(result[0..earlier.len],earlier); result[earlier.len]=actions.items; return result; }
        const fact=goals[at]; var achievers:std.ArrayList(usize)=.empty;
        for(previous.elements,0..) |element,i| if(element.noop!=null and element.noop.?==fact) p.append(usize,&achievers,i);
        for(previous.elements,0..) |element,i| if(element.action!=null and element.add&g.bit(fact)!=0) p.append(usize,&achievers,i);
        for(achievers.items) |e| { var ok=true; for(chosen) |other| if(previous.action_mutex[e]&actionBit(other)!=0) { ok=false; break; }; if(!ok) continue; self.tried+=1; const next=p.alloc(usize,chosen.len+1); @memcpy(next[0..chosen.len],chosen); next[chosen.len]=e; if(self.assign(level,goals,at+1,next)) |result| return result; }
        return null;
    }
};
pub fn run(ground:g.Ground,limit:usize,text:*p.Text) Result {
    var negative:g.Set=0; for(ground.actions) |action| negative|=action.neg; const complements=g.members(negative); const total=ground.facts.len+complements.len; const complement=p.alloc(?usize,ground.facts.len); @memset(complement,null); for(complements,0..) |fact,i| complement[fact]=ground.facts.len+i;
    var initial=ground.initial; for(complements) |fact| if(initial&g.bit(fact)==0) { initial|=g.bit(complement[fact].?); };
    const transformed=p.alloc(Element,ground.actions.len); for(ground.actions,transformed,0..) |action,*element,i| { element.*=.{.action=i,.pre=action.pre,.add=action.add,.del=action.del}; for(g.members(action.neg)) |fact| element.pre|=g.bit(complement[fact].?); for(complements) |fact| { if(action.del&g.bit(fact)!=0) element.add|=g.bit(complement[fact].?); if(action.add&g.bit(fact)!=0) element.del|=g.bit(complement[fact].?); } }
    text.line("complementary facts: {d}",.{complements.len}); var levels:std.ArrayList(Level)=.empty; const mutex=p.alloc(g.Set,total); @memset(mutex,0); p.append(Level,&levels,.{.facts=initial,.mutex=mutex}); var extractor=Extractor{.levels=&levels,.memo=std.AutoHashMap(Memo,void).init(p.allocator)}; var result=Result{.search=.{.status="level limit"}};
    for(0..limit+1) |level| {
        const current=levels.items[level]; text.line("fact level {d}: facts={d} mutexes={d}",.{level,@popCount(current.facts),pairs(current.mutex)}); var extracted=false;
        if(g.subset(ground.goal,current.facts) and compatible(ground.goal,current.mutex)) { extracted=true; const old_search=extractor.searched; const old_hits=extractor.hits; const plan=extractor.extract(level,ground.goal); text.line("extract level {d}: {s} searched={d} memo_hits={d}",.{level,if(plan!=null) "success" else "fail",extractor.searched-old_search,extractor.hits-old_hits}); if(plan) |layers| { result.layers=layers; result.search.status="solved"; break; } }
        if(!extracted and level>0 and @popCount(current.facts)==@popCount(levels.items[level-1].facts) and pairs(current.mutex)==pairs(levels.items[level-1].mutex)) { result.search.status="unreachable"; break; }
        if(level==limit) break;
        var elements:std.ArrayList(Element)=.empty; for(transformed) |element| if(g.subset(element.pre,current.facts) and compatible(element.pre,current.mutex)) p.append(Element,&elements,element); const actions=elements.items.len;
        for(g.members(current.facts)) |fact| p.append(Element,&elements,.{.action=null,.noop=fact,.pre=g.bit(fact),.add=g.bit(fact),.del=0});
        const action_mutex=p.alloc(u512,elements.items.len); @memset(action_mutex,0);
        for(elements.items,0..) |x,i| for(elements.items[i+1..],i+1..) |y,j| {
            var exclusive=(x.del&(y.pre|y.add)!=0) or (y.del&(x.pre|x.add)!=0); for(g.members(x.pre)) |fact| if(current.mutex[fact]&y.pre!=0) { exclusive=true; break; };
            if(exclusive) { action_mutex[i]|=actionBit(j); action_mutex[j]|=actionBit(i); }
        };
        levels.items[level].elements=elements.items; levels.items[level].action_mutex=action_mutex; text.line("action level {d}: actions={d} noops={d} mutexes={d}",.{level,actions,@popCount(current.facts),pairs(action_mutex)});
        var facts:g.Set=0; for(elements.items) |element| facts|=element.add; const next_mutex=p.alloc(g.Set,total); @memset(next_mutex,0); const members=g.members(facts);
        for(members,0..) |q,i| for(members[i+1..]) |r| { var exclusive=true; outer: for(elements.items,0..) |x,xi| { if(x.add&g.bit(q)==0) continue; for(elements.items,0..) |y,yi| if(y.add&g.bit(r)!=0 and (xi==yi or action_mutex[xi]&actionBit(yi)==0)) { exclusive=false; break :outer; }; } if(exclusive) { next_mutex[q]|=g.bit(r); next_mutex[r]|=g.bit(q); } };
        p.append(Level,&levels,.{.facts=facts,.mutex=next_mutex});
    }
    result.search.expanded=extractor.searched; result.search.generated=extractor.tried; result.memo_hits=extractor.hits;
    var plan:std.ArrayList(usize)=.empty; for(result.layers) |layer| for(layer) |action| { p.append(usize,&plan,action); }; result.search.plan=plan.items;
    if(p.eq(result.search.status,"solved")) { text.line("result: solved levels={d} length={d} cost={d} searched={d} memo_hits={d} tried={d}",.{result.layers.len,plan.items.len,search.cost(ground,plan.items),extractor.searched,extractor.hits,extractor.tried}); for(result.layers,1..) |layer,i| { text.put("layer {d}:",.{i}); if(layer.len==0) text.put(" -",.{}); for(layer) |action| text.put(" {s}",.{ground.actions[action].notation}); text.put("\n",.{}); } }
    else text.line("result: FAIL ({s}) searched={d} memo_hits={d} tried={d}",.{result.search.status,extractor.searched,extractor.hits,extractor.tried}); return result;
}
