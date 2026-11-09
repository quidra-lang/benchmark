mod grid_map;
mod low_level;
mod cbs;
mod prioritized;
mod report;
use std::collections::{BTreeMap,BTreeSet};
use std::fs;
use grid_map::{Cell,Path,Grid};
use low_level::{Constraints,Counts,Abort};
use cbs::{Node,Conflict,position};
use report::{name,cell};
struct Params{
    horizon:usize,
    hl:usize,
    ll:usize,
    window:usize,
    step:usize,
    orders:Vec<Vec<usize>>,
    runs:Vec<(String,String)>,
    animate:String,
    frames:usize,
    delays:Vec<(usize,usize,usize)>
}
impl Params{
    fn read(n:usize)->Self{
        let mut p=Self{
            horizon:0,
            hl:0,
            ll:0,
            window:0,
            step:0,
            orders:vec![(0..n).collect()],
            runs:Vec::new(),
            animate:String::new(),
            frames:0,
            delays:Vec::new()
        };
        for line in fs::read_to_string("input/params.txt").unwrap().lines(){
            let a:Vec<_>=line.split(' ').collect();
            let v=|i:usize|a[i].parse::<usize>().unwrap();
            match a[0]{
                "HORIZON"=>p.horizon=v(1),"HL_BUDGET"=>p.hl=v(1),"LL_BUDGET"=>p.ll=v(1),"WINDOW"=>{
                    p.window=v(1);
                    p.step=v(2);
                },"ORDER"=>p.orders.push(a[1..].iter().map(|s|s.parse().unwrap()).collect()),"RUN"=>p.runs.push((a[1].into(),a[2].into())),"ANIMATE"=>{
                    p.animate=a[1].into();
                    p.frames=v(2);
                },_=>p.delays.push((v(1),v(2),v(3)))
            }
        }
        p
    }
}
fn mdd(grid:&Grid,i:usize,c:usize,constraints:&Constraints)->Vec<BTreeSet<Cell>>{
    let mut layers=vec![BTreeSet::new();c+1];
    layers[0].insert(grid.agents[i].start);
    for t in 1..=c{
        for u in layers[t-1].clone(){
            for v in grid.destinations(u){
                if grid.distances[i].get(&v).map_or(false,|&d|t+d<=c)&&constraints.allowed(u,v,t){
                    layers[t].insert(v);
                }
            }
        }
    }
    layers[c].retain(|&v|v==grid.agents[i].goal);
    for t in(0..c).rev(){
        let next=layers[t+1].clone();
        layers[t].retain(|&u|grid.destinations(u).into_iter().any(|v|next.contains(&v)&&constraints.allowed(u,v,t+1)));
    }
    layers
}
fn classify(conflict:&Conflict,mdds:&[Vec<BTreeSet<Cell>>])->usize{
    let fixed=|i:usize|{
        let width=|t:usize|mdds[i].get(t).map_or(1,BTreeSet::len);
        width(conflict.time)==1&&(conflict.vertex||width(conflict.time-1)==1)
    };
    2-usize::from(fixed(conflict.a))-usize::from(fixed(conflict.b))
}
fn class_text(c:usize)->&'static str{
    ["cardinal","semi_cardinal","non_cardinal"][c]
}
struct Run{
    name:String,
    solver:String,
    function:String,
    paths:Option<Vec<Path>>,
    reason:String,
    high:usize,
    generated:Option<usize>,
    pruned:usize,
    open:usize,
    classes:[usize;3],
    count:Counts,
    notes:Vec<String>,
    trace:Vec<String>
}
impl Run{
    fn new(solver:&str,function:&str,p:&Params)->Self{
        Self{
            name:format!("{}-{}",solver,function),
            solver:solver.into(),
            function:function.into(),
            paths:None,
            reason:String::new(),
            high:0,
            generated:if solver=="CBS"||solver=="ICBS"{
                Some(0)
            }else{
                None
            },
            pruned:0,
            open:0,
            classes:[0;3],
            count:Counts{
                searches:0,
                expansions:0,
                budget:p.ll
            },
            notes:Vec::new(),
            trace:Vec::new()
        }
    }
}
fn pp(grid:&Grid,p:&Params,r:&mut Run){
    for(k,order)in p.orders.iter().enumerate(){
        r.high+=1;
        let result=prioritized::plan(grid,order,k+1,p.horizon,&mut r.count);
        r.trace.extend(result.trace);
        if result.aborted{
            r.reason="ll_budget".into();
            break;
        }
        let order_text:String=order.iter().map(|&i|name(i)).collect();
        r.notes.push(format!("order {} {} planned {} expansions {} {}",k+1,order_text,result.planned,result.expansions,if let Some(i)=result.failed{
            format!("failed {}",name(i))
        }else{
            "ok".into()
        }));
        if result.paths.is_some(){
            r.paths=result.paths;
            r.trace.push(format!("end OK order {}",k+1));
            return;
        }
    }
    if r.reason.is_empty(){
        r.reason="orders".into();
    }
    r.trace.push(format!("end FAIL {}",r.reason));
}
fn tree(grid:&Grid,p:&Params,r:&mut Run)->Result<Option<Node>,Abort>{
    let n=grid.agents.len();
    let constraints=vec![Constraints::default();n];
    let mut paths=Vec::new();
    for i in 0..n{
        paths.push(low_level::search(grid,i,grid.agents[i].start,0,p.horizon,false,&constraints[i],&mut r.count)?.unwrap());
    }
    let root=Node::new(0,None,0,constraints,paths,r.function=="SOC");
    let mut open=BTreeMap::new();
    open.insert(root.key(),root);
    r.generated=Some(1);
    while let Some((_,node))=open.pop_first(){
        r.open=open.len();
        if node.conflicts.is_empty(){
            return Ok(Some(node));
        }
        if r.high==p.hl{
            r.reason="hl_budget".into();
            return Ok(None);
        }
        r.high+=1;
        let(class,index)=if r.solver=="ICBS"{
            let mdds:Vec<_>=(0..n).map(|i|mdd(grid,i,node.paths[i].len()-1,&node.constraints[i])).collect();
            node.conflicts.iter().enumerate().map(|(k,c)|(classify(c,&mdds),k)).min().unwrap()
        }else{
            (0,0)
        };
        if r.solver=="ICBS"{
            r.classes[class]+=1;
        }
        let conflict=&node.conflicts[index];
        let mut children=Vec::new();
        for j in [conflict.a,conflict.b].iter().copied(){
            let mut constraints=node.constraints.clone();
            conflict.constrain(j,&mut constraints[j]);
            let searched=low_level::search(grid,j,grid.agents[j].start,0,p.horizon,false,&constraints[j],&mut r.count);
            let path=match searched{
                Ok(path)=>path,Err(e)=>{
                    r.open=open.len();
                    return Err(e);
                }
            };
            if let Some(path)=path{
                let id=r.generated.unwrap();
                r.generated=Some(id+1);
                let mut paths=node.paths.clone();
                paths[j]=path;
                let child=Node::new(id,Some(node.id),node.depth+1,constraints,paths,r.function=="SOC");
                open.insert(child.key(),child);
                children.push(id.to_string());
            }else{
                r.pruned+=1;
                children.push("-".into());
            }
        }
        r.open=open.len();
        r.trace.push(format!("expand {} node {} parent {} depth {} cost {} conflicts {} split {}{} children {} {}",r.high,node.id,node.parent.map_or_else(||"-".into(),|v|v.to_string()),node.depth,node.cost,node.conflicts.len(),report::conflict(conflict),if r.solver=="ICBS"{
            format!(" class {}",class_text(class))
        }else{
            String::new()
        },children[0],children[1]));
    }
    r.reason="exhausted".into();
    r.open=0;
    Ok(None)
}
fn cbs_run(grid:&Grid,p:&Params,r:&mut Run){
    let answer=match tree(grid,p,r){
        Ok(v)=>v,Err(_)=>{
            r.reason="ll_budget".into();
            None
        }
    };
    r.notes.push(format!("search expanded {} generated {} pruned {} open {}",r.high,r.generated.unwrap(),r.pruned,r.open));
    if r.solver=="ICBS"{
        r.notes.push(format!("classes cardinal {} semi_cardinal {} non_cardinal {}",r.classes[0],r.classes[1],r.classes[2]));
    }
    if let Some(node)=answer{
        r.notes.push(format!("solution node {} depth {}",node.id,node.depth));
        let mut constraints=Vec::new();
        for(i,c)in node.constraints.iter().enumerate(){
            for &(v,t)in &c.states{
                constraints.push((i,t,0,v.0,v.1,v.0,v.1));
            }
            for &(u,v,t)in &c.moves{
                constraints.push((i,t,1,u.0,u.1,v.0,v.1));
            }
        }
        constraints.sort();
        for(i,t,kind,ux,uy,vx,vy)in constraints{
            r.notes.push(if kind==0{
                format!("constraint {} vertex {} t {}",name(i),cell((vx,vy)),t)
            }else{
                format!("constraint {} edge {} {} t {}",name(i),cell((ux,uy)),cell((vx,vy)),t)
            });
        }
        r.trace.push(format!("end OK node {} cost {}",node.id,node.cost));
        r.paths=Some(node.paths);
    }else{
        r.trace.push(format!("end FAIL {}",r.reason));
    }
}
fn whca_search(grid:&Grid,p:&Params,r:&mut Run)->Result<Option<Vec<Path>>,Abort>{
    let n=grid.agents.len();
    let mut positions:Vec<_>=grid.agents.iter().map(|a|a.start).collect();
    let mut executed:Vec<_>=positions.iter().map(|&v|vec![v]).collect();
    let mut time=0;
    loop{
        if (0..n).all(|i|positions[i]==grid.agents[i].goal){
            for(i,path)in executed.iter_mut().enumerate(){
                while path.len()>1&&path[path.len()-2]==grid.agents[i].goal{
                    path.pop();
                }
            }
            return Ok(Some(executed));
        }
        if time>=p.horizon{
            r.reason="timeout".into();
            return Ok(None);
        }
        r.high+=1;
        let mut order:Vec<_>=(0..n).collect();
        order.sort_by_key(|&i|(positions[i]==grid.agents[i].goal,i));
        let mut constraints=Constraints::default();
        let mut windows=vec![Vec::new();n];
        for i in order{
            let before=r.count.expansions;
            let path=low_level::search(grid,i,positions[i],time,time+p.window,true,&constraints,&mut r.count)?;
            if let Some(mut path)=path{
                path.resize(p.window+1,*path.last().unwrap());
                constraints.reserve(&path,time,false);
                r.trace.push(format!("round {} time {} agent {} moves {} expansions {}",r.high,time,name(i),report::actions(&path),r.count.expansions-before));
                windows[i]=path;
            }else{
                r.trace.push(format!("round {} time {} agent {} blocked expansions {}",r.high,time,name(i),r.count.expansions-before));
                r.reason="blocked".into();
                return Ok(None);
            }
        }
        for i in 0..n{
            executed[i].extend(&windows[i][1..=p.step]);
            positions[i]=windows[i][p.step];
        }
        time+=p.step;
    }
}
fn whca(grid:&Grid,p:&Params,r:&mut Run){
    match whca_search(grid,p,r){
        Ok(paths)=>r.paths=paths,Err(_)=>r.reason="ll_budget".into()
    }
    r.notes.push(format!("window {} step {} rounds {}",p.window,p.step,r.high));
    r.trace.push(if r.paths.is_some(){
        format!("end OK rounds {}",r.high)
    }else{
        format!("end FAIL {}",r.reason)
    });
}
fn validate(grid:&Grid,name:&str,paths:&[Path],classes:Option<&[usize]>)->Vec<String>{
    let conflicts=cbs::conflicts(paths);
    let start=paths.iter().enumerate().filter(|(i,p)|p[0]!=grid.agents[*i].start).count();
    let goal=paths.iter().enumerate().filter(|(i,p)|*p.last().unwrap()!=grid.agents[*i].goal).count();
    let moves=paths.iter().flat_map(|p|p.windows(2)).filter(|w|!grid.destinations(w[0]).contains(&w[1])).count();
    let vertex=conflicts.iter().filter(|c|c.vertex).count();
    let edge=conflicts.len()-vertex;
    let tmax=paths.iter().map(|p|p.len()-1).max().unwrap_or(0);
    let mut follows=0;
    for t in 1..=tmax{
        for a in 0..paths.len(){
            for b in 0..paths.len(){
                if a!=b&&position(&paths[a],t)!=position(&paths[a],t-1)&&position(&paths[a],t)==position(&paths[b],t-1)&&position(&paths[b],t)!=position(&paths[a],t-1){
                    follows+=1;
                }
            }
        }
    }
    let mut lines=vec![format!("plan {} verdict {} start {} goal {} moves {} vertex {} edge {} follows {}",name,if start+goal+moves+vertex+edge==0{
        "VALID"
    }else{
        "INVALID"
    },start,goal,moves,vertex,edge,follows)];
    for(k,c)in conflicts.iter().enumerate(){
        lines.push(format!("  {}{}",report::conflict(c),classes.map_or_else(String::new,|a|format!(" {}",class_text(a[k])))));
    }
    lines
}
struct Execution{
    time:usize,
    deadlock:bool,
    hold:usize,
    finish:Vec<usize>
}
fn execution(paths:&[Path],p:&Params)->Execution{
    let steps:Vec<Vec<(usize,Cell)>>=paths.iter().map(|p|p.iter().enumerate().filter(|(t,c)|*t==0||**c!=p[*t-1]).map(|(t,&c)|(t,c)).collect()).collect();
    let n=paths.len();
    let mut progress=vec![0;n];
    let mut r=Execution{
        time:0,
        deadlock:false,
        hold:0,
        finish:vec![0;n]
    };
    while (0..n).any(|i|progress[i]+1<steps[i].len()){
        let mut advancing=Vec::new();
        let mut stopped=false;
        for i in 0..n{
            if progress[i]+1==steps[i].len(){
                continue;
            }
            if p.delays.iter().any(|&(j,s,k)|j==i&&s<=r.time&&r.time<s+k){
                stopped=true;
                continue;
            }
            let(t,c)=steps[i][progress[i]+1];
            let ready=(0..n).filter(|&j|j!=i).all(|j|steps[j].iter().enumerate().all(|(l,&(u,v))|v!=c||u>=t||progress[j]>l));
            if ready{
                advancing.push(i);
            }else{
                r.hold+=1;
            }
        }
        if advancing.is_empty()&&!stopped{
            r.deadlock=true;
            return r;
        }
        for i in advancing{
            progress[i]+=1;
            r.finish[i]=r.time+1;
        }
        r.time+=1;
    }
    r
}
struct Statistics{
    soc:usize,
    makespan:usize,
    extras:Vec<usize>,
    waits:Vec<usize>,
    turns:Vec<usize>,
    traffic:BTreeMap<Cell,usize>,
    waiting:BTreeMap<Cell,usize>,
    execution:Execution
}
fn statistics(grid:&Grid,paths:&[Path],p:&Params)->Statistics{
    let mut s=Statistics{
        soc:paths.iter().map(|p|p.len()-1).sum(),
        makespan:paths.iter().map(|p|p.len()-1).max().unwrap(),
        extras:Vec::new(),
        waits:Vec::new(),
        turns:Vec::new(),
        traffic:BTreeMap::new(),
        waiting:BTreeMap::new(),
        execution:execution(paths,p)
    };
    for(i,path)in paths.iter().enumerate(){
        s.extras.push(path.len()-1-grid.distances[i][&grid.agents[i].start]);
        let actions=report::actions(path);
        let moves:Vec<_>=actions.chars().filter(|&c|c!='.').collect();
        s.turns.push(moves.windows(2).filter(|w|w[0]!=w[1]).count());
        s.waits.push(actions.chars().filter(|&c|c=='.').count());
        for c in path.iter().copied().collect::<BTreeSet<_>>(){
            *s.traffic.entry(c).or_default()+=1;
        }
        for w in path.windows(2){
            if w[0]==w[1]{
                *s.waiting.entry(w[0]).or_default()+=1;
            }
        }
    }
    s
}
fn overview(grid:&Grid,independent:&[Path],mdds:&[Vec<BTreeSet<Cell>>],classes:&[usize])->Vec<String>{
    let cells=grid.cells();
    let n=grid.agents.len();
    let mut degree=[0;4];
    for &c in &cells{
        degree[(grid.destinations(c).len()-1).min(3)]+=1;
    }
    let mut unseen:BTreeSet<_>=cells.iter().copied().collect();
    let mut components=0;
    while let Some(&c)=unseen.iter().next(){
        components+=1;
        for v in grid.distance(c).keys(){
            unseen.remove(v);
        }
    }
    let mut lines=vec![format!("instance width {} height {} free {} agents {}",grid.width,grid.height,cells.len(),n),format!("map isolated {} dead_ends {} corridors {} junctions {} components {}",degree[0],degree[1],degree[2],degree[3],components)];
    let distances:Vec<_>=grid.agents.iter().enumerate().map(|(i,a)|grid.distances[i][&a.start]).collect();
    for i in 0..n{
        lines.push(format!("agent {} start {} goal {} distance {} mdd {} width {}",name(i),cell(grid.agents[i].start),cell(grid.agents[i].goal),distances[i],mdds[i].iter().map(BTreeSet::len).sum::<usize>(),mdds[i].iter().map(BTreeSet::len).max().unwrap()));
    }
    lines.push(format!("lower_bound soc {} makespan {}",distances.iter().sum::<usize>(),distances.iter().max().unwrap()));
    let conflicts=cbs::conflicts(independent);
    let vertex=conflicts.iter().filter(|c|c.vertex).count();
    lines.push(format!("independent conflicts {} vertex {} edge {} cardinal {} semi_cardinal {} non_cardinal {}",conflicts.len(),vertex,conflicts.len()-vertex,classes.iter().filter(|&&c|c==0).count(),classes.iter().filter(|&&c|c==1).count(),classes.iter().filter(|&&c|c==2).count()));
    let mut adjacent=vec![BTreeSet::new();n];
    for c in conflicts{
        adjacent[c.a].insert(c.b);
        adjacent[c.b].insert(c.a);
    }
    let mut visited=BTreeSet::new();
    let mut groups=Vec::new();
    for i in 0..n{
        if visited.contains(&i){
            continue;
        }
        let mut stack=vec![i];
        let mut group=BTreeSet::new();
        while let Some(j)=stack.pop(){
            if visited.insert(j){
                group.insert(j);
                stack.extend(adjacent[j].iter().copied());
            }
        }
        if group.len()>1{
            groups.push(group.iter().map(|&i|name(i)).collect::<String>());
        }
    }
    lines.push(format!("groups {}",if groups.is_empty(){
        "-".into()
    }else{
        groups.join(" ")
    }));
    lines
}
fn pictures(grid:&Grid,p:&Params,r:&Run)->Vec<String>{
    let paths=match &r.paths{
        Some(v)=>v,None=>return vec![format!("run {} FAIL",r.name)]
    };
    let mut lines=vec![format!("run {} frames {}",r.name,p.frames)];
    for t in 0..p.frames{
        let mut picture=grid.rows.clone();
        for(i,a)in grid.agents.iter().enumerate(){
            picture[a.goal.1 as usize][a.goal.0 as usize]=name(i).to_ascii_lowercase();
        }
        let(mut done,mut moving,mut waiting)=(0,0,0);
        for(i,path)in paths.iter().enumerate(){
            let c=position(path,t);
            picture[c.1 as usize][c.0 as usize]=name(i);
            if t>=path.len()-1{
                done+=1;
            }else if t>0&&position(path,t)!=position(path,t-1){
                moving+=1;
            }else{
                waiting+=1;
            }
        }
        lines.push(String::new());
        lines.push(format!("frame {} done {} moving {} waiting {}",t,done,moving,waiting));
        lines.extend(picture.iter().map(|row|row.iter().collect::<String>()));
    }
    let stats=statistics(grid,paths,p);
    for(label,counts)in[("traffic",&stats.traffic),("waits",&stats.waiting)].iter(){
        let mut picture=grid.rows.clone();
        for c in grid.cells(){
            let count=counts.get(&c).copied().unwrap_or(0);
            picture[c.1 as usize][c.0 as usize]=if count==0{
                '.'
            }else if count<10{
                (b'0'+count as u8)as char
            }else{
                '+'
            };
        }
        lines.push(String::new());
        lines.push((*label).into());
        lines.extend(picture.iter().map(|row|row.iter().collect::<String>()));
    }
    lines
}
fn main(){
    let grid=Grid::read();
    let p=Params::read(grid.agents.len());
    let mut independent=Vec::new();
    let mut mdds=Vec::new();
    let mut counts=Counts{
        searches:0,
        expansions:0,
        budget:usize::MAX
    };
    for i in 0..grid.agents.len(){
        independent.push(low_level::search(&grid,i,grid.agents[i].start,0,p.horizon,false,&Constraints::default(),&mut counts).unwrap().unwrap());
        mdds.push(mdd(&grid,i,grid.distances[i][&grid.agents[i].start],&Constraints::default()));
    }
    let conflicts=cbs::conflicts(&independent);
    let classes:Vec<_>=conflicts.iter().map(|c|classify(c,&mdds)).collect();
    let mut solutions=overview(&grid,&independent,&mdds,&classes);
    let mut validation=validate(&grid,"INDEPENDENT",&independent,Some(&classes));
    let mut csv=vec!["run,solver,cost_function,result,reason,cost,soc,makespan,sum_extra,max_extra,waits,turns,exec_soc,exec_makespan,high_level,generated,searches,expansions".into()];
    let mut trace=Vec::new();
    let mut runs=Vec::new();
    let lower_soc:usize=grid.agents.iter().enumerate().map(|(i,a)|grid.distances[i][&a.start]).sum();
    let lower_max=grid.agents.iter().enumerate().map(|(i,a)|grid.distances[i][&a.start]).max().unwrap();
    let mut ranking=Vec::new();
    for(solver,function)in &p.runs{
        let mut r=Run::new(solver,function,&p);
        match solver.as_str(){
            "PP"=>pp(&grid,&p,&mut r),"CBS"|"ICBS"=>cbs_run(&grid,&p,&mut r),_=>whca(&grid,&p,&mut r)
        }
        solutions.push(String::new());
        let mut fields=vec![r.name.clone(),r.solver.clone(),r.function.clone()];
        if let Some(paths)=&r.paths{
            let s=statistics(&grid,paths,&p);
            let cost=if function=="SOC"{
                s.soc
            }else{
                s.makespan
            };
            let lower=if function=="SOC"{
                lower_soc
            }else{
                lower_max
            };
            solutions.push(format!("run {} solver {} cost_function {} result OK cost {} soc {} makespan {} ratio {}",r.name,solver,function,cost,s.soc,s.makespan,report::ratio(cost,lower)));
            solutions.extend(r.notes.clone());
            for(i,path)in paths.iter().enumerate(){
                let goal=grid.agents[i].goal;
                let arrive=path.iter().position(|&c|c==goal).unwrap();
                let leave=path.windows(2).filter(|w|w[0]==goal&&w[1]!=goal).count();
                solutions.push(format!("agent {} cost {} extra {} waits {} turns {} arrive {} leave {} moves {}",name(i),path.len()-1,s.extras[i],s.waits[i],s.turns[i],arrive,leave,report::actions(path)));
            }
            solutions.push(format!("arrivals {}",(0..=s.makespan).map(|t|paths.iter().filter(|p|p.len()-1<=t).count().to_string()).collect::<Vec<_>>().join(" ")));
            let mut hotspots:Vec<_>=s.traffic.iter().map(|(&c,&n)|(c,n)).collect();
            hotspots.sort_by_key(|&(c,n)|(std::cmp::Reverse(n),c.1,c.0));
            solutions.push(format!("hotspots {}",hotspots.iter().take(5).map(|&(c,n)|format!("{}:{}",cell(c),n)).collect::<Vec<_>>().join(" ")));
            let e=&s.execution;
            solutions.push(if e.deadlock{
                format!("execution deadlock time {}",e.time)
            }else{
                format!("execution soc {} makespan {} blocked {} finish {}",e.finish.iter().sum::<usize>(),e.finish.iter().max().unwrap(),e.hold,e.finish.iter().map(usize::to_string).collect::<Vec<_>>().join(" "))
            });
            fields.extend(["OK".into(),"-".into(),cost.to_string(),s.soc.to_string(),s.makespan.to_string(),s.extras.iter().sum::<usize>().to_string(),s.extras.iter().max().unwrap().to_string(),s.waits.iter().sum::<usize>().to_string(),s.turns.iter().sum::<usize>().to_string(),if e.deadlock{
                "-".into()
            }else{
                e.finish.iter().sum::<usize>().to_string()
            },if e.deadlock{
                "-".into()
            }else{
                e.finish.iter().max().unwrap().to_string()
            }].iter().cloned());
            validation.extend(validate(&grid,&r.name,paths,None));
            ranking.push((s.soc,s.makespan,runs.len(),r.name.clone()));
        }else{
            solutions.push(format!("run {} solver {} cost_function {} result FAIL reason {}",r.name,solver,function,r.reason));
            solutions.extend(r.notes.clone());
            validation.push(format!("plan {} verdict NONE",r.name));
            fields.push("FAIL".into());
            fields.push(r.reason.clone());
            fields.extend(vec!["-".into();9]);
        }
        fields.extend([r.high.to_string(),r.generated.map_or_else(||"-".into(),|v|v.to_string()),r.count.searches.to_string(),r.count.expansions.to_string()].iter().cloned());
        csv.push(report::csv(&fields));
        if !trace.is_empty(){
            trace.push(String::new());
        }
        trace.push(format!("run {}",r.name));
        trace.extend(r.trace.clone());
        runs.push(r);
    }
    solutions.push(String::new());
    solutions.push(format!("summary ok {} failed {}",ranking.len(),runs.len()-ranking.len()));
    if !ranking.is_empty(){
        let soc=ranking.iter().map(|r|r.0).min().unwrap();
        let makespan=ranking.iter().map(|r|r.1).min().unwrap();
        solutions.push(format!("best_soc {} {}",soc,ranking.iter().filter(|r|r.0==soc).map(|r|r.3.clone()).collect::<Vec<_>>().join(" ")));
        solutions.push(format!("best_makespan {} {}",makespan,ranking.iter().filter(|r|r.1==makespan).map(|r|r.3.clone()).collect::<Vec<_>>().join(" ")));
        ranking.sort();
        solutions.push(format!("ranking {}",ranking.iter().map(|r|r.3.clone()).collect::<Vec<_>>().join(" ")));
    }
    let animated=runs.iter().find(|r|r.name==p.animate).unwrap();
    report::write("solutions.txt",&solutions);
    report::write("stats.csv",&csv);
    report::write("validation.txt",&validation);
    report::write("trace.txt",&trace);
    report::write("frames.txt",&pictures(&grid,&p,animated));
}
