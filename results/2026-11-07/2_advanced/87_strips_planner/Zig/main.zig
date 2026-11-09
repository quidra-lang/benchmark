const std=@import("std");
const p=@import("pddl_parser.zig");
const g=@import("grounding.zig");
const h=@import("heuristics.zig");
const search=@import("search.zig");
const gp=@import("graphplan.zig");
fn arguments(domain:p.Domain,args:[]const []const u8,expected:[]const p.Typed,table:[]const p.Typed,noun:[]const u8) ?[]const u8 {
    if(args.len!=expected.len) return p.fmt("expected {d} arguments, got {d}",.{expected.len,args.len});
    for(args,expected,1..) |arg,typ,i| { const j=p.find(table,arg) orelse return p.fmt("unknown {s} {s}",.{noun,arg}); if(!g.subtype(domain,table[j].typ,typ.typ)) return p.fmt("argument {d} ({s}) is not of type {s}",.{i,arg,typ.typ}); } return null;
}
fn atomError(domain:p.Domain,atom:p.Atom,table:[]const p.Typed,noun:[]const u8,equality:bool) ?[]const u8 {
    if(equality and p.eq(atom.predicate,"=")) return arguments(domain,atom.terms,&.{.{.name="",.typ="object"},.{.name="",.typ="object"}},table,noun);
    const pred=p.find(domain.predicates,atom.predicate) orelse return p.fmt("unknown predicate {s}",.{atom.predicate}); return arguments(domain,atom.terms,domain.predicates[pred].arguments,table,noun);
}
fn validateDomain(domain:*p.Domain,text:*p.Text) void {
    var kept:std.ArrayList(p.Schema)=.empty; text.line("== domain {s} ==",.{domain.name});
    for(domain.actions) |schema| { var failure:?[]const u8=null; for(schema.parameters) |parameter| if(p.find(domain.types,parameter.typ)==null) { failure=p.fmt("unknown type {s}",.{parameter.typ}); break; };
        if(failure==null) outer: for([_] []const p.Literal{schema.conditions,schema.effects}) |literals| for(literals) |literal| { if(atomError(domain.*,literal.atom,schema.parameters,"variable",true)) |error_message| { failure=p.fmt("{s}: {s}",.{literal.atom.notation(),error_message}); break :outer; } };
        if(failure) |message| text.line("error: action {s}: {s}",.{schema.name,message}) else p.append(p.Schema,&kept,schema);
    }
    domain.actions=kept.items;
    for(domain.predicates) |*predicate| { var used=false; for(domain.actions) |schema| { for(schema.conditions) |literal| if(p.eq(literal.atom.predicate,predicate.name)) { used=true; }; for(schema.effects) |literal| if(p.eq(literal.atom.predicate,predicate.name)) { used=true; predicate.fluent=true; }; } if(!used) text.line("warning: predicate {s} is not used by any action",.{predicate.name}); }
    for(domain.types) |typ| { text.put("type {s}",.{typ.name}); var current=typ.name; while(!p.eq(current,"object")) { current=domain.types[p.find(domain.types,current).?].parent; text.put(" < {s}",.{current}); } text.put("\n",.{}); }
    for(domain.predicates) |predicate| text.line("predicate {s}/{d} {s}",.{predicate.name,predicate.arguments.len,if(predicate.fluent) "fluent" else "static"});
    for(domain.actions) |schema| { var adds:usize=0; var deletes:usize=0; for(schema.effects) |literal| { if(literal.negative) deletes+=1 else adds+=1; } text.line("action {s}/{d} cost={d} pre={d} add={d} del={d}",.{schema.name,schema.parameters.len,schema.cost,schema.conditions.len,adds,deletes}); }
}
fn validateProblem(domain:p.Domain,problem:*p.Problem) void {
    for([_]bool{false,true}) |goal| { var kept:std.ArrayList(p.Atom)=.empty; for(if(goal) problem.goals else problem.initial) |atom| { const failure=atomError(domain,atom,problem.objects,"object",false) orelse if(p.atomIndex(kept.items,atom)!=null) "duplicate" else null; if(failure) |message| problem.diagnostics.line("warning: {s} {s}: {s}",.{if(goal) "goal" else "init",atom.notation(),message}) else p.append(p.Atom,&kept,atom); } if(goal) problem.goals=kept.items else problem.initial=kept.items; }
}
fn numberList(set:g.Set) []const u8 { var out:p.Text=.{}; for(g.members(set),0..) |q,i| { if(i>0) out.put(",",.{}); out.put("{d}",.{q}); } return if(set==0) "-" else out.data.items; }
fn groundingReport(domain:p.Domain,problem:p.Problem,ground:g.Ground,text:*p.Text) void {
    text.line("",.{}); text.line("== problem {s} ==",.{problem.name}); text.put("{s}",.{problem.diagnostics.data.items}); text.line("objects: {d}",.{problem.objects.len});
    for(domain.types) |typ| { text.put("  {s}:",.{typ.name}); var count:usize=0; for(problem.objects) |object| if(g.subtype(domain,object.typ,typ.name)) { text.put(" {s}",.{object.name}); count+=1; }; if(count==0) text.put(" -",.{}); text.put("\n",.{}); }
    text.line("static facts: {d}",.{ground.static_count}); var candidate_count:usize=0; for(domain.actions,ground.counts) |schema,counts| { text.line("schema {s}: assignments={d} candidates={d} reachable={d}",.{schema.name,counts.assignments,counts.candidates,counts.reachable}); candidate_count+=counts.candidates; }
    text.line("candidates: {d} reachable: {d}",.{candidate_count,ground.actions.len}); text.line("facts: {d} init: {d} goals: {d}",.{ground.facts.len,@popCount(ground.initial),@popCount(ground.goal)}); for(ground.unreachable) |atom| text.line("unreachable goal: {s}",.{atom.notation()}); text.put("facts by predicate:",.{}); var fluent_count:usize=0;
    for(domain.predicates) |predicate| if(predicate.fluent) { var count:usize=0; for(ground.facts) |atom| count+=@intFromBool(p.eq(atom.predicate,predicate.name)); text.put(" {s}={d}",.{predicate.name,count}); fluent_count+=1; }; if(fluent_count==0) text.put(" -",.{}); text.put("\n",.{});
    text.line("facts:",.{}); for(ground.facts,0..) |atom,i| text.line("  {d} {s}",.{i,atom.notation()}); text.line("actions:",.{}); for(ground.actions,0..) |action,i| text.line("  {d} {s} cost={d} pre={s} neg={s} add={s} del={s}",.{i,action.notation,action.cost,numberList(action.pre),numberList(action.neg),numberList(action.add),numberList(action.del)});
}
const Step=struct { name:[]const u8,args:[]const []const u8,pub fn notation(self:Step) []const u8 { return (p.Atom{.predicate=self.name,.terms=self.args}).notation(); } };
const Validation=struct { status:[]const u8,messages:[]const []const u8,correct:usize,pub fn verdict(self:Validation) []const u8 { return p.fmt("{s}{s}{s}",.{self.status,if(p.eq(self.status,"valid")) " " else ": ",self.messages[0]}); } };
fn validation(domain:p.Domain,problem:p.Problem,steps:[]const Step) Validation {
    var world:std.ArrayList(p.Atom)=.empty; for(problem.initial) |atom| p.append(p.Atom,&world,atom); var cost:i64=0;
    for(steps,1..) |step,k| {
        var failure:?[]const u8=null; const schema_index=p.find(domain.actions,step.name);
        if(schema_index==null) failure=p.fmt("unknown action {s}",.{step.name}) else {
            const schema=domain.actions[schema_index.?]; failure=arguments(domain,step.args,schema.parameters,problem.objects,"object");
            if(failure==null) for(schema.conditions) |literal| { const atom=p.substitute(literal.atom,schema.parameters,step.args); const truth=if(p.eq(atom.predicate,"=")) p.eq(atom.terms[0],atom.terms[1]) else p.atomIndex(world.items,atom)!=null; if(truth==literal.negative) { failure=p.fmt("precondition {s} is false",.{if(literal.negative) p.fmt("(not {s})",.{atom.notation()}) else atom.notation()}); break; } };
            if(failure==null) { for(schema.effects) |literal| if(literal.negative) { const atom=p.substitute(literal.atom,schema.parameters,step.args); if(p.atomIndex(world.items,atom)) |i| _=world.orderedRemove(i); }; for(schema.effects) |literal| if(!literal.negative) { const atom=p.substitute(literal.atom,schema.parameters,step.args); if(p.atomIndex(world.items,atom)==null) p.append(p.Atom,&world,atom); }; cost+=schema.cost; }
        }
        if(failure) |message| { const messages=p.alloc([]const u8,1); messages[0]=p.fmt("step {d} {s}: {s}",.{k,step.notation(),message}); return .{.status="invalid",.messages=messages,.correct=k-1}; }
    }
    var messages:std.ArrayList([]const u8)=.empty; for(problem.goals) |atom| if(p.atomIndex(world.items,atom)==null) p.append([]const u8,&messages,p.fmt("unsatisfied goal {s}",.{atom.notation()}));
    if(messages.items.len>0) return .{.status="goal not reached",.messages=messages.items,.correct=steps.len}; p.append([]const u8,&messages,p.fmt("length={d} cost={d}",.{steps.len,cost})); return .{.status="valid",.messages=messages.items,.correct=steps.len};
}
fn stepsFor(domain:p.Domain,ground:g.Ground,plan:[]const usize) []const Step { const steps=p.alloc(Step,plan.len); for(plan,steps) |a,*step| { const action=ground.actions[a]; step.*=.{.name=domain.actions[action.source].name,.args=action.args}; } return steps; }
fn mapped(domain:p.Domain,ground:g.Ground,steps:[]const Step) []const usize { var plan:std.ArrayList(usize)=.empty; for(steps) |step| { for(ground.actions,0..) |action,i| { if(!p.eq(domain.actions[action.source].name,step.name) or action.args.len!=step.args.len) continue; var same=true; for(action.args,step.args) |a,b| if(!p.eq(a,b)) { same=false; break; }; if(same) { p.append(usize,&plan,i); break; } } } return plan.items; }
fn improved(ground:g.Ground,original:[]const usize) []const usize {
    var plan=original; var i:usize=0; while(i<plan.len) { var state=ground.initial; for(plan[0..i]) |a| state=search.apply(ground.actions[a],state); var kept:std.ArrayList(usize)=.empty; for(plan[0..i]) |a| p.append(usize,&kept,a); for(plan[i+1..]) |a| if(search.applicable(ground.actions[a],state)) { state=search.apply(ground.actions[a],state); p.append(usize,&kept,a); }; if(g.subset(ground.goal,state)) plan=kept.items else i+=1; } return plan;
}
fn interfere(a:g.Action,b:g.Action) bool { return a.del&(b.pre|b.add)!=0 or b.del&(a.pre|a.add)!=0 or a.add&b.neg!=0 or b.add&a.neg!=0; }
fn parallel(ground:g.Ground,plan:[]const usize) []const []const usize { const level=p.alloc(usize,plan.len); var layers:usize=0; for(plan,0..) |action,j| { level[j]=1; for(plan[0..j],0..) |previous,i| { const a=ground.actions[previous]; const b=ground.actions[action]; if(a.add&b.pre!=0 or a.del&b.neg!=0 or interfere(a,b)) level[j]=@max(level[j],level[i]+1); } layers=@max(layers,level[j]); } const lists=p.alloc(std.ArrayList(usize),layers); @memset(lists,.empty); for(plan,level) |action,k| p.append(usize,&lists[k-1],action); const out=p.alloc([]const usize,layers); for(lists,out) |list,*row| row.*=list.items; return out; }
fn parallelValidation(ground:g.Ground,layers:[]const []const usize) []const u8 { var state=ground.initial; for(layers,1..) |layer,k| { var adds:g.Set=0; var deletes:g.Set=0; for(layer,0..) |a,i| { if(!search.applicable(ground.actions[a],state)) return p.fmt("invalid at layer {d}",.{k}); for(layer[i+1..]) |b| if(interfere(ground.actions[a],ground.actions[b])) return p.fmt("invalid at layer {d}",.{k}); adds|=ground.actions[a].add; deletes|=ground.actions[a].del; } state=(state&~deletes)|adds; } return if(g.subset(ground.goal,state)) "valid" else "goal not reached"; }
const Seen=struct { plan:[]const usize,tag:[]const u8 };
var analyzed:usize=0; var valid_plans:usize=0;
fn actionList(text:*p.Text,heading:[]const u8,ground:g.Ground,actions:[]const usize) void { text.put("{s}",.{heading}); if(actions.len==0) text.put(" -",.{}); for(actions) |a| text.put(" {s}",.{ground.actions[a].notation}); text.put("\n",.{}); }
fn planBlock(domain:p.Domain,problem:p.Problem,ground:g.Ground,plan:[]const usize,tag:[]const u8,landmarks:g.Set,seen:*std.ArrayList(Seen),plans:*p.Text,checks:*p.Text) void {
    var same:?[]const u8=null; for(seen.items) |previous| if(std.mem.eql(usize,previous.plan,plan)) { same=previous.tag; break; }; plans.line("plan: length={d} cost={d}{s}",.{plan.len,search.cost(ground,plan),if(same) |old| p.fmt(" (same as {s})",.{old}) else ""}); for(plan,1..) |action,k| plans.line("  {d} {s}",.{k,ground.actions[action].notation});
    plans.put("schemas:",.{}); var count:usize=0; for(domain.actions,0..) |schema,i| { var uses:usize=0; for(plan) |a| uses+=@intFromBool(ground.actions[a].source==i); if(uses>0) { plans.put(" {s}={d}",.{schema.name,uses}); count+=1; } } if(count==0) plans.put(" -",.{}); plans.put("\n",.{});
    const layers=parallel(ground,plan); plans.line("parallel: layers={d}",.{layers.len}); for(layers,1..) |layer,k| actionList(plans,p.fmt("  {d}:",.{k}),ground,layer); const better=improved(ground,plan); plans.line("improved: length={d} cost={d} removed={d}",.{better.len,search.cost(ground,better),plan.len-better.len}); if(better.len<plan.len) for(better,1..) |action,k| plans.line("  {d} {s}",.{k,ground.actions[action].notation});
    var state=ground.initial; var reached:g.Set=0; for(plan) |a| { state=search.apply(ground.actions[a],state); reached|=state&landmarks; } plans.line("landmarks reached: {d}/{d}",.{@popCount(reached),@popCount(landmarks)}); for(g.members(landmarks&~reached)) |fact| plans.line("  missed {s}",.{ground.facts[fact].notation()});
    const result=validation(domain,problem,stepsFor(domain,ground,plan)); checks.line("{s}: {s}",.{tag,result.verdict()}); checks.line("  parallel: {s}",.{parallelValidation(ground,layers)}); checks.line("  improved: {s}",.{validation(domain,problem,stepsFor(domain,ground,better)).verdict()}); analyzed+=1; valid_plans+=@intFromBool(p.eq(result.status,"valid")); p.append(Seen,seen,.{.plan=plan,.tag=tag});
}
fn heuristicLine(text:*p.Text,prefix:[]const u8,values:h.Values) void { text.line("{s}goalcount={s} hmax={s} hadd={s} ff={s} lmcount={s}",.{prefix,h.str(values.goalcount),h.str(values.hmax),h.str(values.hadd),h.str(values.ff),h.str(values.lmcount)}); }
fn profile(ground:g.Ground,plan:[]const usize,tag:[]const u8,text:*p.Text) void {
    text.line("-- profile ({s}) --",.{tag}); var state=ground.initial; var over=[_]usize{0}**5;
    for(0..plan.len+1) |k| { const remaining=search.cost(ground,plan[k..]); const values=h.evaluate(ground,state); heuristicLine(text,p.fmt("  {d}: h*={d} ",.{k,remaining}),values); for([_]i64{values.goalcount,values.hmax,values.hadd,values.ff,values.lmcount},0..) |value,i| over[i]+=@intFromBool(value>remaining); if(k<plan.len) state=search.apply(ground.actions[plan[k]],state); }
    text.line("overestimates: goalcount={d} hmax={d} hadd={d} ff={d} lmcount={d}",.{over[0],over[1],over[2],over[3],over[4]}); text.line("-- causal links ({s}) --",.{tag}); const supplier=p.alloc(usize,ground.facts.len); @memset(supplier,0);
    for(plan,1..) |a,k| { text.put("  {d} {s}:",.{k,ground.actions[a].notation}); const facts=g.members(ground.actions[a].pre); if(facts.len==0) text.put(" -",.{}); for(facts) |fact| text.put(" {s}<-{d}",.{ground.facts[fact].notation(),supplier[fact]}); text.put("\n",.{}); for(g.members(ground.actions[a].add)) |fact| supplier[fact]=k; }
    text.put("  goal:",.{}); if(ground.goal==0) text.put(" -",.{}); for(g.members(ground.goal)) |fact| text.put(" {s}<-{d}",.{ground.facts[fact].notation(),supplier[fact]}); text.put("\n",.{});
}
const Candidate=struct { problem:usize,label:[]const u8,steps:[]const Step };
fn candidates(text:[]const u8,problems:[]const p.Problem) []const Candidate { var out:std.ArrayList(Candidate)=.empty; var steps:std.ArrayList(Step)=.empty; var candidate:Candidate=undefined; var lines=std.mem.splitScalar(u8,text,'\n'); while(lines.next()) |line| { if(line.len==0 or line[0]=='#') continue; const w=p.words(line); if(p.eq(w[0],"plan")) { candidate=.{.problem=p.find(problems,w[1]).?,.label=w[2],.steps=&.{}}; steps=.empty; } else if(p.eq(w[0],"end")) { candidate.steps=steps.items; p.append(Candidate,&out,candidate); } else { const fields=p.words(line[1..line.len-1]); p.append(Step,&steps,.{.name=fields[0],.args=fields[1..]}); } } return out.items; }
const TagStats=struct { solved:usize=0,best:usize=0,expanded:usize=0,generated:usize=0 };
pub fn main(init:std.process.Init) !void {
    var arena:std.heap.ArenaAllocator=.init(init.gpa); defer arena.deinit(); p.allocator=arena.allocator(); var domain=p.domain(try p.read(init.io,"input/domain.txt")); const problems=p.problems(try p.read(init.io,"input/problems.txt"));
    var runs:std.ArrayList(search.Run)=.empty; var repair:search.Run=undefined; var budget:usize=0; var weight:i64=1; var graph_limit:usize=0; var settings=std.mem.splitScalar(u8,try p.read(init.io,"input/params.txt"),'\n'); while(settings.next()) |line| { if(line.len==0 or line[0]=='#') continue; const w=p.words(line); if(p.eq(w[0],"run")) p.append(search.Run,&runs,.{.algorithm=w[1],.heuristic=w[2]}) else if(p.eq(w[0],"repair")) repair=.{.algorithm=w[1],.heuristic=w[2]} else if(p.eq(w[0],"budget")) budget=@intCast(p.number(w[1])) else if(p.eq(w[0],"weight")) weight=p.number(w[1]) else graph_limit=@intCast(p.number(w[1])); }
    var grounding_text:p.Text=.{}; var plans:p.Text=.{}; var graphplan:p.Text=.{}; var checks:p.Text=.{}; var csv:p.Text=.{}; csv.line("problem,algorithm,heuristic,length,cost,expanded,generated",.{}); validateDomain(&domain,&grounding_text); const grounds=p.alloc(g.Ground,problems.len); const bests=p.alloc(?i64,problems.len); @memset(bests,null); const tag_stats=p.alloc(TagStats,runs.items.len+1); @memset(tag_stats,.{}); var problem_summary:p.Text=.{};
    for(problems,grounds,0..) |*problem,*ground,pi| {
        validateProblem(domain,problem); ground.*=g.ground(domain,problem.*); groundingReport(domain,problem.*,ground.*,&grounding_text); plans.line("== problem {s} ==",.{problem.name}); graphplan.line("== problem {s} ==",.{problem.name}); checks.line("== problem {s} ==",.{problem.name}); const unreachable=ground.unreachable.len>0; var initial:h.Values=.{};
        if(unreachable) plans.line("initial h: unreachable goal",.{}) else { initial=h.evaluate(ground.*,ground.initial); heuristicLine(&plans,"initial h: ",initial); plans.line("landmarks: {d}",.{@popCount(initial.landmarks)}); for(g.members(initial.landmarks)) |fact| plans.line("  {s}",.{ground.facts[fact].notation()}); plans.line("relaxed plan: length={d} cost={s}",.{initial.relaxed.len,h.str(initial.ff)}); for(initial.relaxed) |action| plans.line("  {s}",.{ground.actions[action].notation}); actionList(&plans,"helpful:",ground.*,initial.helpful); }
        const results=p.alloc(search.Result,runs.items.len+1); var seen:std.ArrayList(Seen)=.empty; var proof:?usize=null;
        for(0..results.len) |ri| {
            const run=if(ri<runs.items.len) runs.items[ri] else search.Run{.algorithm="graphplan",.heuristic="none"}; const tag=if(ri<runs.items.len) run.tag() else "graphplan";
            if(unreachable) { results[ri]=.{.status="unreachable goal"}; if(ri==runs.items.len) graphplan.line("result: FAIL (unreachable goal)",.{}); }
            else if(ri<runs.items.len) results[ri]=search.run(ground.*,ground.initial,run,budget,weight) else results[ri]=gp.run(ground.*,graph_limit,&graphplan).search;
            const result=results[ri]; const solved=p.eq(result.status,"solved"); plans.line("-- {s} --",.{tag}); if(unreachable) plans.line("result: FAIL (unreachable goal)",.{}) else if(solved) plans.line("result: solved expanded={d} generated={d}",.{result.expanded,result.generated}) else plans.line("result: FAIL ({s}) expanded={d} generated={d}",.{result.status,result.expanded,result.generated});
            if(solved) { planBlock(domain,problem.*,ground.*,result.plan,tag,initial.landmarks,&seen,&plans,&checks); const cost=search.cost(ground.*,result.plan); if(bests[pi]==null or cost<bests[pi].?) bests[pi]=cost; if(proof==null and (p.eq(tag,"ucs none") or p.eq(tag,"astar hmax"))) proof=ri; }
            csv.line("{s},{s},{s},{s},{s},{d},{d}",.{problem.name,run.algorithm,run.heuristic,if(solved) p.fmt("{d}",.{result.plan.len}) else "-",if(solved) p.fmt("{d}",.{search.cost(ground.*,result.plan)}) else "-",result.expanded,result.generated});
        }
        if(proof) |ri| profile(ground.*,results[ri].plan,runs.items[ri].tag(),&plans); plans.line("",.{}); graphplan.line("",.{}); checks.line("",.{}); var solved_count:usize=0; var impossible=false;
        for(results,0..) |result,ri| { const solved=p.eq(result.status,"solved"); solved_count+=@intFromBool(solved); tag_stats[ri].solved+=@intFromBool(solved); tag_stats[ri].expanded+=result.expanded; tag_stats[ri].generated+=result.generated; if(solved and search.cost(ground.*,result.plan)==bests[pi].?) tag_stats[ri].best+=1; if(p.eq(result.status,"unreachable goal") or p.eq(result.status,"dead end") or p.eq(result.status,"exhausted") or p.eq(result.status,"unreachable")) impossible=true; }
        problem_summary.line("{s}: solved={d}/{d} best={s} optimal={s}",.{problem.name,solved_count,results.len,if(bests[pi]) |cost| p.fmt("{d}",.{cost}) else "-",if(proof) |ri| p.fmt("{d}",.{search.cost(ground.*,results[ri].plan)}) else if(impossible) "none" else "unknown"});
    }
    plans.line("== summary ==",.{}); plans.put("{s}",.{problem_summary.data.items}); for(tag_stats,0..) |stats,i| plans.line("{s}: solved={d} best={d} expanded={d} generated={d}",.{if(i<runs.items.len) runs.items[i].tag() else "graphplan",stats.solved,stats.best,stats.expanded,stats.generated});
    const candidate_list=candidates(try p.read(init.io,"input/candidates.txt"),problems); var candidate_valid:usize=0; checks.line("== candidates ==",.{});
    for(candidate_list,1..) |candidate,number| {
        const problem=problems[candidate.problem]; const ground=grounds[candidate.problem]; const result=validation(domain,problem,candidate.steps); checks.put("candidate {d} {s} {s}: ",.{number,problem.name,candidate.label});
        if(p.eq(result.status,"valid")) { candidate_valid+=1; checks.line("{s}",.{result.verdict()}); const plan=mapped(domain,ground,candidate.steps); const better=improved(ground,plan); checks.line("  improved: length={d} cost={d} removed={d} best known={s}",.{better.len,search.cost(ground,better),plan.len-better.len,if(bests[candidate.problem]) |cost| p.fmt("{d}",.{cost}) else "-"}); continue; }
        checks.line("{s}",.{result.status}); for(result.messages) |message| checks.line("  {s}",.{message}); if(ground.unreachable.len>0) { checks.line("  repair: FAIL (unreachable goal)",.{}); continue; }
        const prefix=mapped(domain,ground,candidate.steps[0..result.correct]); var state=ground.initial; for(prefix) |action| state=search.apply(ground.actions[action],state); const continuation=search.run(ground,state,repair,budget,weight); if(!p.eq(continuation.status,"solved")) { checks.line("  repair: FAIL ({s})",.{continuation.status}); continue; }
        const repaired=p.alloc(usize,prefix.len+continuation.plan.len); @memcpy(repaired[0..prefix.len],prefix); @memcpy(repaired[prefix.len..],continuation.plan); checks.line("  repair: kept={d} added={d} {s}",.{prefix.len,continuation.plan.len,validation(domain,problem,stepsFor(domain,ground,repaired)).verdict()}); for(repaired,1..) |action,k| checks.line("    {d} {s}",.{k,ground.actions[action].notation});
    }
    checks.line("",.{}); checks.line("== summary ==",.{}); checks.line("plans: {d} valid: {d}",.{analyzed,valid_plans}); checks.line("candidates: {d} valid: {d}",.{candidate_list.len,candidate_valid});
    try p.write(init.io,"grounding.txt",grounding_text); try p.write(init.io,"plans.txt",plans); try p.write(init.io,"graphplan.txt",graphplan); try p.write(init.io,"validation.txt",checks); try p.write(init.io,"comparison.csv",csv);
}
