mod pddl_parser;
mod grounding;
mod heuristics;
mod search;
mod graphplan;
use std::collections::{BTreeMap,BTreeSet};
use std::fs;
use pddl_parser::{Domain,Problem,Atom};
use grounding::{Grounding,Action,State};
fn arguments(d:&Domain,args:&[String],expected:&[String],table:&BTreeMap<String,String>,noun:&str)->Option<String>{
    if args.len()!=expected.len(){
        return Some(format!("expected {} arguments, got {}",expected.len(),args.len()));
    }
    for(i,(x,t))in args.iter().zip(expected).enumerate(){
        if let Some(actual)=table.get(x){
            if !grounding::subtype(d,actual,t){
                return Some(format!("argument {} ({}) is not of type {}",i+1,x,t));
            }
        }else{
            return Some(format!("unknown {} {}",noun,x));
        }
    }
    None
}
fn atom_error(d:&Domain,a:&Atom,table:&BTreeMap<String,String>,noun:&str,equality:bool)->Option<String>{
    let types=if equality&&a.predicate=="="{
        vec!["object".into(),"object".into()]
    }else if let Some(p)=d.predicates.iter().find(|p|p.name==a.predicate){
        p.types.clone()
    }else{
        return Some(format!("unknown predicate {}",a.predicate));
    };
    arguments(d,&a.terms,&types,table,noun)
}
fn validate_domain(d:&mut Domain){
    let mut actions=Vec::new();
    for a in &d.actions{
        let table=a.parameters.iter().cloned().collect();
        let mut error=a.parameters.iter().find(|(_,t)|!d.type_order.contains(t)).map(|(_,t)|format!("unknown type {}",t));
        if error.is_none(){
            for l in a.pre.iter().chain(&a.effects){
                if let Some(reason)=atom_error(d,&l.atom,&table,"variable",true){
                    error=Some(format!("{}: {}",l.atom.text(),reason));
                    break;
                }
            }
        }
        if let Some(error)=error{
            d.diagnostics.push(format!("error: action {}: {}",a.name,error));
        }else{
            actions.push(a.clone());
        }
    }
    d.actions=actions;
    for p in &d.predicates{
        if !d.actions.iter().any(|a|a.pre.iter().chain(&a.effects).any(|l|l.atom.predicate==p.name)){
            d.diagnostics.push(format!("warning: predicate {} is not used by any action",p.name));
        }
    }
}
fn validate_problem(d:&Domain,p:&mut Problem){
    let table=p.objects.iter().cloned().collect();
    for side in 0..2{
        let original=if side==0{
            p.initial.clone()
        }else{
            p.goals.clone()
        };
        let mut seen=BTreeSet::new();
        let mut kept=Vec::new();
        for a in original{
            let error=atom_error(d,&a,&table,"object",false).or_else(||if seen.contains(&a){
                Some("duplicate".into())
            }else{
                None
            });
            if let Some(reason)=error{
                p.diagnostics.push(format!("warning: {} {}: {}",if side==0{
                    "init"
                }else{
                    "goal"
                },a.text(),reason));
            }else{
                seen.insert(a.clone());
                kept.push(a);
            }
        }
        if side==0{
            p.initial=kept;
        }else{
            p.goals=kept;
        }
    }
}
fn list(heading:&str,values:Vec<String>)->String{
    format!("{} {}",heading,if values.is_empty(){
        "-".into()
    }else{
        values.join(" ")
    })
}
fn numbers(values:&State)->String{
    if values.is_empty(){
        "-".into()
    }else{
        values.iter().map(usize::to_string).collect::<Vec<_>>().join(",")
    }
}
fn htext(value:i64)->String{
    if value>=heuristics::INF{
        "inf".into()
    }else{
        value.to_string()
    }
}
fn hvalues(v:[i64;5])->String{
    format!("goalcount={} hmax={} hadd={} ff={} lmcount={}",htext(v[0]),htext(v[1]),htext(v[2]),htext(v[3]),htext(v[4]))
}
fn cost(g:&Grounding,plan:&[usize])->i64{
    plan.iter().map(|&a|g.actions[a].cost).sum()
}
fn domain_report(d:&Domain)->Vec<String>{
    let mut lines=vec![format!("== domain {} ==",d.name)];
    lines.extend(d.diagnostics.clone());
    for t in &d.type_order{
        let mut chain=vec![t.clone()];
        let mut current=t;
        while let Some(parent)=d.parents.get(current){
            chain.push(parent.clone());
            current=parent;
        }
        lines.push(format!("type {}",chain.join(" < ")));
    }
    let fluent=grounding::fluents(d);
    for p in &d.predicates{
        lines.push(format!("predicate {}/{} {}",p.name,p.types.len(),if fluent.contains(&p.name){
            "fluent"
        }else{
            "static"
        }));
    }
    for a in &d.actions{
        lines.push(format!("action {}/{} cost={} pre={} add={} del={}",a.name,a.parameters.len(),a.cost,a.pre.len(),a.effects.iter().filter(|l|!l.negative).count(),a.effects.iter().filter(|l|l.negative).count()));
    }
    lines
}
fn grounding_report(d:&Domain,p:&Problem,g:&Grounding)->Vec<String>{
    let mut lines=vec![String::new(),format!("== problem {} ==",p.name)];
    lines.extend(p.diagnostics.clone());
    lines.push(format!("objects: {}",p.objects.len()));
    for t in &d.type_order{
        lines.push(list(&format!("  {}:",t),p.objects.iter().filter(|(_,u)|grounding::subtype(d,u,t)).map(|(n,_)|n.clone()).collect()));
    }
    lines.push(format!("static facts: {}",g.static_count));
    for(i,a)in d.actions.iter().enumerate(){
        let s=g.stats[i];
        lines.push(format!("schema {}: assignments={} candidates={} reachable={}",a.name,s[0],s[1],s[2]));
    }
    lines.push(format!("candidates: {} reachable: {}",g.stats.iter().map(|s|s[1]).sum::<usize>(),g.actions.len()));
    lines.push(format!("facts: {} init: {} goals: {}",g.facts.len(),g.initial.len(),g.goals.len()));
    for a in &g.unreachable{
        lines.push(format!("unreachable goal: {}",a.text()));
    }
    lines.push(list("facts by predicate:",d.predicates.iter().filter(|p|g.fluent.contains(&p.name)).map(|p|format!("{}={}",p.name,g.facts.iter().filter(|a|a.predicate==p.name).count())).collect()));
    lines.push("facts:".into());
    for(i,a)in g.facts.iter().enumerate(){
        lines.push(format!("  {} {}",i,a.text()));
    }
    lines.push("actions:".into());
    for(i,a)in g.actions.iter().enumerate(){
        lines.push(format!("  {} {} cost={} pre={} neg={} add={} del={}",i,a.text(),a.cost,numbers(&a.pre),numbers(&a.neg),numbers(&a.add),numbers(&a.del)));
    }
    lines
}
struct Validation{
    status:&'static str,
    messages:Vec<String>,
    correct:usize
}
impl Validation{
    fn verdict(&self)->String{
        if self.status=="valid"{
            format!("valid {}",self.messages[0])
        }else{
            format!("{}: {}",self.status,self.messages[0])
        }
    }
}
fn validate_steps(d:&Domain,p:&Problem,steps:&[Atom])->Validation{
    let mut world:BTreeSet<_>=p.initial.iter().cloned().collect();
    let table=p.objects.iter().cloned().collect();
    let mut cost=0;
    for(k,step)in steps.iter().enumerate(){
        let action=d.actions.iter().find(|a|a.name==step.predicate);
        let error=if let Some(a)=action{
            let expected=a.parameters.iter().map(|(_,t)|t.clone()).collect::<Vec<_>>();
            arguments(d,&step.terms,&expected,&table,"object")
        }else{
            Some(format!("unknown action {}",step.predicate))
        };
        if let Some(error)=error{
            return Validation{
                status:"invalid",
                messages:vec![format!("step {} {}: {}",k+1,step.text(),error)],
                correct:k
            };
        }
        let action=action.unwrap();
        let values:BTreeMap<_,_>=action.parameters.iter().map(|(n,_)|n.clone()).zip(step.terms.iter().cloned()).collect();
        for l in &action.pre{
            let l=l.replace(&values);
            let truth=if l.atom.predicate=="="{
                l.atom.terms[0]==l.atom.terms[1]
            }else{
                world.contains(&l.atom)
            };
            if truth==l.negative{
                return Validation{
                    status:"invalid",
                    messages:vec![format!("step {} {}: precondition {} is false",k+1,step.text(),l.text())],
                    correct:k
                };
            }
        }
        for l in action.effects.iter().filter(|l|l.negative){
            world.remove(&l.atom.replace(&values));
        }
        for l in action.effects.iter().filter(|l|!l.negative){
            world.insert(l.atom.replace(&values));
        }
        cost+=action.cost;
    }
    let missing:Vec<_>=p.goals.iter().filter(|a|!world.contains(*a)).map(|a|format!("unsatisfied goal {}",a.text())).collect();
    if missing.is_empty(){
        Validation{
            status:"valid",
            messages:vec![format!("length={} cost={}",steps.len(),cost)],
            correct:steps.len()
        }
    }else{
        Validation{
            status:"goal not reached",
            messages:missing,
            correct:steps.len()
        }
    }
}
fn steps(g:&Grounding,plan:&[usize])->Vec<Atom>{
    plan.iter().map(|&i|Atom{
        predicate:g.actions[i].name.clone(),
        terms:g.actions[i].args.clone()
    }).collect()
}
fn map_steps(g:&Grounding,steps:&[Atom])->Vec<usize>{
    steps.iter().map(|s|g.actions.iter().position(|a|a.name==s.predicate&&a.args==s.terms).unwrap()).collect()
}
fn interfere(a:&Action,b:&Action)->bool{
    !a.del.is_disjoint(&b.pre)||!a.del.is_disjoint(&b.add)||!b.del.is_disjoint(&a.pre)||!b.del.is_disjoint(&a.add)||!a.add.is_disjoint(&b.neg)||!b.add.is_disjoint(&a.neg)
}
fn parallel(g:&Grounding,plan:&[usize])->Vec<Vec<usize>>{
    let mut levels:Vec<usize>=Vec::new();
    for(j,&a)in plan.iter().enumerate(){
        let mut level=0usize;
        for i in 0..j{
            let b=plan[i];
            if !g.actions[b].add.is_disjoint(&g.actions[a].pre)||!g.actions[b].del.is_disjoint(&g.actions[a].neg)||interfere(&g.actions[b],&g.actions[a]){
                level=level.max(levels[i]);
            }
        }
        levels.push(level+1);
    }
    let mut layers=vec![Vec::new();levels.iter().max().copied().unwrap_or(0)];
    for(i,&a)in plan.iter().enumerate(){
        layers[levels[i]-1].push(a);
    }
    layers
}
fn parallel_verdict(g:&Grounding,layers:&[Vec<usize>])->String{
    let mut state=g.initial.clone();
    for(k,layer)in layers.iter().enumerate(){
        if layer.iter().any(|&a|!search::applicable(&g.actions[a],&state))||layer.iter().enumerate().any(|(i,&a)|layer[i+1..].iter().any(|&b|interfere(&g.actions[a],&g.actions[b]))){
            return format!("invalid at layer {}",k+1);
        }
        let deletes:State=layer.iter().flat_map(|&a|g.actions[a].del.iter().copied()).collect();
        state=state.difference(&deletes).copied().collect();
        for &a in layer{
            state.extend(&g.actions[a].add);
        }
    }
    if g.goals.is_subset(&state){
        "valid".into()
    }else{
        "goal not reached".into()
    }
}
fn improve(g:&Grounding,plan:&[usize])->Vec<usize>{
    let mut plan=plan.to_vec();
    let mut i=0;
    while i<plan.len(){
        let mut state=g.initial.clone();
        for &a in &plan[..i]{
            state=search::apply(&g.actions[a],&state);
        }
        let mut next=plan[..i].to_vec();
        for &a in &plan[i+1..]{
            if search::applicable(&g.actions[a],&state){
                state=search::apply(&g.actions[a],&state);
                next.push(a);
            }
        }
        if g.goals.is_subset(&state){
            plan=next;
        }else{
            i+=1;
        }
    }
    plan
}
fn transformed(g:&Grounding)->(Vec<Action>,State,usize){
    let negatives:State=g.actions.iter().flat_map(|a|a.neg.iter().copied()).collect();
    let complements:BTreeMap<_,_>=negatives.iter().enumerate().map(|(j,&p)|(p,g.facts.len()+j)).collect();
    let mut initial=g.initial.clone();
    for(&p,&q)in &complements{
        if !initial.contains(&p){
            initial.insert(q);
        }
    }
    let mut actions=g.actions.clone();
    for a in &mut actions{
        a.pre.extend(a.neg.iter().map(|p|complements[p]));
        a.add.extend(a.del.iter().filter_map(|p|complements.get(p).copied()));
        a.del.extend(g.actions.iter().find(|b|b.source==a.source&&b.args==a.args).unwrap().add.iter().filter_map(|p|complements.get(p).copied()));
    }
    (actions,initial,complements.len())
}
struct Params{
    budget:usize,
    weight:i64,
    limit:usize,
    runs:Vec<(String,String)>,
    repair:(String,String)
}
fn params()->Params{
    let mut p=Params{
        budget:0,
        weight:0,
        limit:0,
        runs:Vec::new(),
        repair:(String::new(),String::new())
    };
    for line in fs::read_to_string("input/params.txt").unwrap().lines(){
        if line.is_empty()||line.starts_with('#'){
            continue;
        }
        let a:Vec<_>=line.split(' ').collect();
        match a[0]{
            "budget"=>p.budget=a[1].parse().unwrap(),"weight"=>p.weight=a[1].parse().unwrap(),"graphplan"=>p.limit=a[1].parse().unwrap(),"run"=>p.runs.push((a[1].into(),a[2].into())),_=>p.repair=(a[1].into(),a[2].into())
        }
    }
    p
}
struct Candidate{
    problem:String,
    label:String,
    steps:Vec<Atom>
}
fn candidates()->Vec<Candidate>{
    let mut all:Vec<Candidate>=Vec::new();
    for line in fs::read_to_string("input/candidates.txt").unwrap().lines(){
        if line.is_empty()||line.starts_with('#'){
            continue;
        }
        if line.starts_with("plan "){
            let a:Vec<_>=line.split(' ').collect();
            all.push(Candidate{
                problem:a[1].into(),
                label:a[2].into(),
                steps:Vec::new()
            });
        }else if line!="end"{
            let a:Vec<_>=line[1..line.len()-1].split(' ').collect();
            all.last_mut().unwrap().steps.push(Atom{
                predicate:a[0].into(),
                terms:a[1..].iter().map(|s|s.to_string()).collect()
            });
        }
    }
    all
}
fn plan_block(d:&Domain,p:&Problem,g:&Grounding,plan:&[usize],tag:&str,lm:&State,seen:&mut Vec<(Vec<usize>,String)>)->(Vec<String>,Vec<String>,bool){
    let same=seen.iter().find(|(old,_)|old==plan).map(|(_,tag)|format!(" (same as {})",tag)).unwrap_or_default();
    if same.is_empty(){
        seen.push((plan.to_vec(),tag.into()));
    }
    let mut lines=vec![format!("plan: length={} cost={}{}",plan.len(),cost(g,plan),same)];
    for(k,&a)in plan.iter().enumerate(){
        lines.push(format!("  {} {}",k+1,g.actions[a].text()));
    }
    lines.push(list("schemas:",d.actions.iter().enumerate().filter_map(|(i,a)|{
        let count=plan.iter().filter(|&&j|g.actions[j].source==i).count();
        if count>0{
            Some(format!("{}={}",a.name,count))
        }else{
            None
        }
    }).collect()));
    let layers=parallel(g,plan);
    lines.push(format!("parallel: layers={}",layers.len()));
    for(k,layer)in layers.iter().enumerate(){
        lines.push(list(&format!("  {}:",k+1),layer.iter().map(|&a|g.actions[a].text()).collect()));
    }
    let improved=improve(g,plan);
    lines.push(format!("improved: length={} cost={} removed={}",improved.len(),cost(g,&improved),plan.len()-improved.len()));
    if improved.len()<plan.len(){
        for(k,&a)in improved.iter().enumerate(){
            lines.push(format!("  {} {}",k+1,g.actions[a].text()));
        }
    }
    let mut state=g.initial.clone();
    let mut reached=State::new();
    for &a in plan{
        state=search::apply(&g.actions[a],&state);
        reached.extend(state.intersection(lm).copied());
    }
    lines.push(format!("landmarks reached: {}/{}",reached.len(),lm.len()));
    for &p in lm.difference(&reached){
        lines.push(format!("  missed {}",g.facts[p].text()));
    }
    let original=validate_steps(d,p,&steps(g,plan));
    let improved=validate_steps(d,p,&steps(g,&improved));
    let validation=vec![format!("{}: {}",tag,original.verdict()),format!("  parallel: {}",parallel_verdict(g,&layers)),format!("  improved: {}",improved.verdict())];
    (lines,validation,original.status=="valid")
}
fn profile(g:&Grounding,plan:&[usize],tag:&str)->Vec<String>{
    let mut lines=vec![format!("-- profile ({}) --",tag)];
    let mut state=g.initial.clone();
    let mut remaining=cost(g,plan);
    let mut over=[0;5];
    for k in 0..=plan.len(){
        let values=heuristics::values(g,&state);
        for i in 0..5{
            if values[i]>remaining{
                over[i]+=1;
            }
        }
        lines.push(format!("  {}: h*={} {}",k,remaining,hvalues(values)));
        if k<plan.len(){
            state=search::apply(&g.actions[plan[k]],&state);
            remaining-=g.actions[plan[k]].cost;
        }
    }
    lines.push(format!("overestimates: goalcount={} hmax={} hadd={} ff={} lmcount={}",over[0],over[1],over[2],over[3],over[4]));
    lines.push(format!("-- causal links ({}) --",tag));
    let mut suppliers=vec![0;g.facts.len()];
    for(k,&a)in plan.iter().enumerate(){
        lines.push(list(&format!("  {} {}:",k+1,g.actions[a].text()),g.actions[a].pre.iter().map(|&p|format!("{}<-{}",g.facts[p].text(),suppliers[p])).collect()));
        for &p in &g.actions[a].add{
            suppliers[p]=k+1;
        }
    }
    lines.push(list("  goal:",g.goals.iter().map(|&p|format!("{}<-{}",g.facts[p].text(),suppliers[p])).collect()));
    lines
}
fn result_line(r:&search::Result,unreachable:bool)->String{
    if unreachable{
        "result: FAIL (unreachable goal)".into()
    }else if r.status=="solved"{
        format!("result: solved expanded={} generated={}",r.expanded,r.generated)
    }else{
        format!("result: FAIL ({}) expanded={} generated={}",r.status,r.expanded,r.generated)
    }
}
fn write(name:&str,lines:&[String]){
    fs::create_dir_all("output").unwrap();
    fs::write(format!("output/{}",name),if lines.is_empty(){
        String::new()
    }else{
        lines.join("\n")+"\n"
    }).unwrap();
}
fn main(){
    let mut domain=pddl_parser::domain();
    validate_domain(&mut domain);
    let mut problems=pddl_parser::problems();
    for p in &mut problems{
        validate_problem(&domain,p);
    }
    let params=params();
    let grounds:Vec<_>=problems.iter().map(|p|grounding::ground(&domain,p)).collect();
    let tags:Vec<_>=params.runs.iter().map(|(a,h)|format!("{} {}",a,h)).chain(std::iter::once("graphplan".into())).collect();
    let mut grounding_lines=domain_report(&domain);
    let mut plans=Vec::new();
    let mut graph_lines=Vec::new();
    let mut validation=Vec::new();
    let mut comparison=vec!["problem,algorithm,heuristic,length,cost,expanded,generated".into()];
    let mut problem_summary=Vec::new();
    let mut tag_stats=vec![[0usize;4];tags.len()];
    let mut bests=Vec::new();
    let(mut analyzed,mut valid_plans)=(0,0);
    for(index,p)in problems.iter().enumerate(){
        let g=&grounds[index];
        let unreachable=!g.unreachable.is_empty();
        grounding_lines.extend(grounding_report(&domain,p,g));
        plans.push(format!("== problem {} ==",p.name));
        validation.push(format!("== problem {} ==",p.name));
        graph_lines.push(format!("== problem {} ==",p.name));
        let mut lm=State::new();
        if unreachable{
            plans.push("initial h: unreachable goal".into());
        }else{
            let values=heuristics::values(g,&g.initial);
            plans.push(format!("initial h: {}",hvalues(values)));
            lm=heuristics::landmarks(g,&g.initial).unwrap_or_default();
            plans.push(format!("landmarks: {}",lm.len()));
            for &p in &lm{
                plans.push(format!("  {}",g.facts[p].text()));
            }
            let(ff,relaxed,helpful)=heuristics::relaxed(g,&g.initial);
            plans.push(format!("relaxed plan: length={} cost={}",relaxed.len(),htext(ff)));
            for a in relaxed{
                plans.push(format!("  {}",g.actions[a].text()));
            }
            plans.push(list("helpful:",helpful.iter().map(|&a|g.actions[a].text()).collect()));
        }
        let mut results=Vec::new();
        for(a,h)in &params.runs{
            results.push(if unreachable{
                search::Result::failure("unreachable goal")
            }else{
                search::run(g,&g.initial,a,h,params.budget,params.weight)
            });
        }
        if unreachable{
            graph_lines.push("result: FAIL (unreachable goal)".into());
            results.push(search::Result::failure("unreachable goal"));
        }else{
            let(actions,initial,complements)=transformed(g);
            let graph=graphplan::run(&actions,&initial,&g.goals,params.limit);
            graph_lines.push(format!("complementary facts: {}",complements));
            graph_lines.extend(graph.records);
            if graph.search.status=="solved"{
                graph_lines.push(format!("result: solved levels={} length={} cost={} searched={} memo_hits={} tried={}",graph.layers.len(),graph.search.plan.len(),cost(g,&graph.search.plan),graph.search.expanded,graph.hits,graph.search.generated));
                for(k,layer)in graph.layers.iter().enumerate(){
                    graph_lines.push(list(&format!("layer {}:",k+1),layer.iter().map(|&a|g.actions[a].text()).collect()));
                }
            }else{
                graph_lines.push(format!("result: FAIL ({}) searched={} memo_hits={} tried={}",graph.search.status,graph.search.expanded,graph.hits,graph.search.generated));
            }
            results.push(graph.search);
        }
        graph_lines.push(String::new());
        let best=results.iter().filter(|r|r.status=="solved").map(|r|cost(g,&r.plan)).min();
        bests.push(best);
        let proof=params.runs.iter().enumerate().position(|(i,(a,h))|(a=="ucs"&&h=="none"||a=="astar"&&h=="hmax")&&results[i].status=="solved");
        let optimal=if let Some(i)=proof{
            cost(g,&results[i].plan).to_string()
        }else if results.iter().any(|r|["unreachable goal","dead end","exhausted","unreachable"].contains(&r.status)){
            "none".into()
        }else{
            "unknown".into()
        };
        let solved=results.iter().filter(|r|r.status=="solved").count();
        problem_summary.push(format!("{}: solved={}/{} best={} optimal={}",p.name,solved,results.len(),best.map_or_else(||"-".into(),|n|n.to_string()),optimal));
        let mut seen=Vec::new();
        for(i,r)in results.iter().enumerate(){
            plans.push(format!("-- {} --",tags[i]));
            plans.push(result_line(r,unreachable));
            tag_stats[i][2]+=r.expanded;
            tag_stats[i][3]+=r.generated;
            let(algorithm,h)=if i<params.runs.len(){
                (&params.runs[i].0[..],&params.runs[i].1[..])
            }else{
                ("graphplan","none")
            };
            let(length,cost_text)=if r.status=="solved"{
                tag_stats[i][0]+=1;
                if Some(cost(g,&r.plan))==best{
                    tag_stats[i][1]+=1;
                }
                let(block,checked,valid)=plan_block(&domain,p,g,&r.plan,&tags[i],&lm,&mut seen);
                plans.extend(block);
                validation.extend(checked);
                analyzed+=1;
                valid_plans+=usize::from(valid);
                (r.plan.len().to_string(),cost(g,&r.plan).to_string())
            }else{
                ("-".into(),"-".into())
            };
            comparison.push(format!("{},{},{},{},{},{},{}",p.name,algorithm,h,length,cost_text,r.expanded,r.generated));
        }
        if let Some(i)=proof{
            plans.extend(profile(g,&results[i].plan,&tags[i]));
        }
        plans.push(String::new());
        validation.push(String::new());
    }
    plans.push("== summary ==".into());
    plans.extend(problem_summary);
    for(i,tag)in tags.iter().enumerate(){
        let s=tag_stats[i];
        plans.push(format!("{}: solved={} best={} expanded={} generated={}",tag,s[0],s[1],s[2],s[3]));
    }
    validation.push("== candidates ==".into());
    let candidates=candidates();
    let mut valid_candidates=0;
    for(k,c)in candidates.iter().enumerate(){
        let i=problems.iter().position(|p|p.name==c.problem).unwrap();
        let p=&problems[i];
        let g=&grounds[i];
        let checked=validate_steps(&domain,p,&c.steps);
        if checked.status=="valid"{
            valid_candidates+=1;
            validation.push(format!("candidate {} {} {}: {}",k+1,p.name,c.label,checked.verdict()));
            let mapped=map_steps(g,&c.steps);
            let improved=improve(g,&mapped);
            validation.push(format!("  improved: length={} cost={} removed={} best known={}",improved.len(),cost(g,&improved),mapped.len()-improved.len(),bests[i].map_or_else(||"-".into(),|v|v.to_string())));
        }else{
            validation.push(format!("candidate {} {} {}: {}",k+1,p.name,c.label,checked.status));
            for m in &checked.messages{
                validation.push(format!("  {}",m));
            }
            if !g.unreachable.is_empty(){
                validation.push("  repair: FAIL (unreachable goal)".into());
                continue;
            }
            let mut mapped=map_steps(g,&c.steps[..checked.correct]);
            let mut state=g.initial.clone();
            for &a in &mapped{
                state=search::apply(&g.actions[a],&state);
            }
            let repair=search::run(g,&state,&params.repair.0,&params.repair.1,params.budget,params.weight);
            if repair.status!="solved"{
                validation.push(format!("  repair: FAIL ({})",repair.status));
            }else{
                let added=repair.plan.len();
                mapped.extend(repair.plan);
                let repaired=validate_steps(&domain,p,&steps(g,&mapped));
                validation.push(format!("  repair: kept={} added={} {}",checked.correct,added,repaired.verdict()));
                for(j,&a)in mapped.iter().enumerate(){
                    validation.push(format!("    {} {}",j+1,g.actions[a].text()));
                }
            }
        }
    }
    validation.push(String::new());
    validation.push("== summary ==".into());
    validation.push(format!("plans: {} valid: {}",analyzed,valid_plans));
    validation.push(format!("candidates: {} valid: {}",candidates.len(),valid_candidates));
    write("grounding.txt",&grounding_lines);
    write("plans.txt",&plans);
    write("graphplan.txt",&graph_lines);
    write("validation.txt",&validation);
    write("comparison.csv",&comparison);
}
