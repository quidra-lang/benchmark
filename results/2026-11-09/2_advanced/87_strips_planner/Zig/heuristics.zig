const std=@import("std");
const p=@import("pddl_parser.zig");
const g=@import("grounding.zig");
pub const infinity:i64=1<<60;
pub fn str(v:i64) []const u8 { return if(v>=infinity) "inf" else p.fmt("{d}",.{v}); }
fn add(a:i64,b:i64) i64 { return @min(infinity,a+b); }
pub const Values=struct { goalcount:i64=0,hmax:i64=0,hadd:i64=0,ff:i64=0,lmcount:i64=0,relaxed:[]const usize=&.{},helpful:[]const usize=&.{},landmarks:g.Set=0,
    pub fn get(self:Values,name:[]const u8) i64 { if(p.eq(name,"none")) return 0; if(p.eq(name,"goalcount")) return self.goalcount; if(p.eq(name,"hmax")) return self.hmax; if(p.eq(name,"hadd")) return self.hadd; if(p.eq(name,"ff")) return self.ff; return self.lmcount; }
};
fn relaxedCosts(ground:g.Ground,state:g.Set,sum:bool) []i64 { const costs=p.alloc(i64,ground.facts.len); for(costs,0..) |*cost,i| cost.*=if(state&g.bit(i)!=0) 0 else infinity; while(true) { var changed=false; for(ground.actions) |action| { var v:i64=0; for(g.members(action.pre)) |i| v=if(sum) add(v,costs[i]) else @max(v,costs[i]); v=add(v,action.cost); for(g.members(action.add)) |i| if(v<costs[i]) { costs[i]=v; changed=true; }; } if(!changed) break; } return costs; }
fn achieve(ground:g.Ground,state:g.Set,costs:[]const i64,fact:usize,selected:[]bool) void { if(state&g.bit(fact)!=0) return; var best:?usize=null; var minimum=infinity; for(ground.actions,0..) |action,i| if(action.add&g.bit(fact)!=0) { var value=action.cost; for(g.members(action.pre)) |q| value=add(value,costs[q]); if(value<minimum) { minimum=value; best=i; } }; const a=best.?; if(selected[a]) return; selected[a]=true; for(g.members(ground.actions[a].pre)) |q| achieve(ground,state,costs,q,selected); }
fn compute(ground:g.Ground,state:g.Set,landmarks:bool) Values {
    var out:Values=.{}; out.goalcount=@popCount(ground.goal&~state); const maxcost=relaxedCosts(ground,state,false); const sumcost=relaxedCosts(ground,state,true);
    for(g.members(ground.goal)) |goal| { out.hmax=@max(out.hmax,maxcost[goal]); out.hadd=add(out.hadd,sumcost[goal]); }
    if(out.hadd>=infinity) { out.ff=infinity; out.lmcount=infinity; return out; }
    const selected=p.alloc(bool,ground.actions.len); @memset(selected,false); for(g.members(ground.goal)) |goal| achieve(ground,state,sumcost,goal,selected); var relaxed:std.ArrayList(usize)=.empty; var helpful:std.ArrayList(usize)=.empty;
    for(selected,ground.actions,0..) |yes,action,i| if(yes) { p.append(usize,&relaxed,i); out.ff+=action.cost; if(g.subset(action.pre,state) and action.neg&state==0) p.append(usize,&helpful,i); };
    out.relaxed=relaxed.items; out.helpful=helpful.items; if(!landmarks) return out;
    const factlevel=p.alloc(i64,ground.facts.len); const actionlevel=p.alloc(i64,ground.actions.len); @memset(factlevel,infinity); @memset(actionlevel,infinity); for(g.members(state)) |q| factlevel[q]=0;
    var level:i64=0; while(true) : (level+=1) { var changed=false; for(ground.actions,0..) |action,i| { if(actionlevel[i]!=infinity) continue; var ready=true; for(g.members(action.pre)) |q| if(factlevel[q]>level) { ready=false; break; }; if(ready) { actionlevel[i]=level; for(g.members(action.add)) |q| if(factlevel[q]==infinity) { factlevel[q]=level+1; changed=true; }; } } if(!changed) break; }
    out.landmarks=ground.goal&~state;
    while(true) { var changed=false; for(g.members(out.landmarks)) |fact| {
        var intersection:g.Set=~@as(g.Set,0); for(ground.actions,0..) |action,i| if(action.add&g.bit(fact)!=0 and actionlevel[i]==factlevel[fact]-1) { intersection&=action.pre; };
        for(g.members(intersection&~state&~out.landmarks)) |q| { var reachable=state; while(true) { const old=reachable; for(ground.actions) |action| if(action.add&g.bit(q)==0 and g.subset(action.pre,reachable)) { reachable|=action.add; }; if(reachable==old) break; } if(!g.subset(ground.goal,reachable)) { out.landmarks|=g.bit(q); changed=true; } }
    } if(!changed) break; }
    out.lmcount=@popCount(out.landmarks); return out;
}
pub fn evaluate(ground:g.Ground,state:g.Set) Values { return compute(ground,state,true); }
pub fn helpfulActions(ground:g.Ground,state:g.Set) []const usize { return compute(ground,state,false).helpful; }
pub fn estimate(ground:g.Ground,state:g.Set,name:[]const u8) i64 {
    if(p.eq(name,"none")) return 0; if(p.eq(name,"goalcount")) return @popCount(ground.goal&~state);
    if(p.eq(name,"hmax") or p.eq(name,"hadd")) { const sum=p.eq(name,"hadd"); const costs=relaxedCosts(ground,state,sum); var result:i64=0; for(g.members(ground.goal)) |q| result=if(sum) add(result,costs[q]) else @max(result,costs[q]); return result; }
    return compute(ground,state,p.eq(name,"lmcount")).get(name);
}
