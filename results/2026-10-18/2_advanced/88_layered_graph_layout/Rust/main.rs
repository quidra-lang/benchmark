mod graph_io;
mod acyclic_layering;
mod crossing;
mod coordinates;
mod canvas;
use std::collections::{BTreeMap,BTreeSet,VecDeque};
use std::fs;
use graph_io::Graph;
use crossing::Segment;
struct Model{
    layer:Vec<usize>,
    width:Vec<i64>,
    chains:Vec<Vec<usize>>,
    gaps:Vec<Vec<Segment>>,
    upper:Vec<Vec<usize>>,
    lower:Vec<Vec<usize>>,
    initial:Vec<Vec<usize>>
}
fn reach(n:usize,edges:&[(usize,usize)])->Vec<Vec<bool>>{
    let mut r=vec![vec![false;n];n];
    for i in 0..n{
        r[i][i]=true;
    }
    for &(a,b)in edges{
        r[a][b]=true;
    }
    for k in 0..n{
        for i in 0..n{
            for j in 0..n{
                r[i][j]=r[i][j]||r[i][k]&&r[k][j];
            }
        }
    }
    r
}
fn analysis(g:&Graph)->(usize,usize,usize,usize,Vec<Vec<usize>>){
    let n=g.nodes.len();
    let mut incoming=vec![0;n];
    let mut outgoing=vec![0;n];
    for &(a,b)in &g.edges{
        outgoing[a]+=1;
        incoming[b]+=1;
    }
    let sources=(0..n).filter(|&v|incoming[v]==0&&outgoing[v]>0).count();
    let sinks=(0..n).filter(|&v|outgoing[v]==0&&incoming[v]>0).count();
    let isolated=(0..n).filter(|&v|incoming[v]==0&&outgoing[v]==0).count();
    let mut visited=BTreeSet::new();
    let mut components=0;
    for v in 0..n{
        if visited.contains(&v){
            continue;
        }
        components+=1;
        let mut stack=vec![v];
        while let Some(a)=stack.pop(){
            if visited.insert(a){
                for &(u,w)in &g.edges{
                    if u==a{
                        stack.push(w);
                    }
                    if w==a{
                        stack.push(u);
                    }
                }
            }
        }
    }
    let connected=reach(n,&g.edges);
    let mut remaining:BTreeSet<_>=(0..n).collect();
    let mut scc=Vec::new();
    while let Some(&v)=remaining.iter().next(){
        let group:Vec<_>=remaining.iter().copied().filter(|&u|connected[v][u]&&connected[u][v]).collect();
        for u in &group{
            remaining.remove(u);
        }
        if group.len()>1{
            scc.push(group);
        }
    }
    (sources,sinks,isolated,components,scc)
}
fn model(g:&Graph,heights:&[i64],dag:&[(usize,usize)],removed:&[bool])->Model{
    let n=g.nodes.len();
    let h=*heights.iter().max().unwrap();
    let raw:Vec<_>=heights.iter().map(|v|h-v).collect();
    let mut used:BTreeSet<_>=raw.iter().copied().collect();
    for(i,&(a,b))in dag.iter().enumerate(){
        if !removed[i]{
            used.extend(raw[a]+1..raw[b]);
        }
    }
    let numbered:BTreeMap<_,_>=used.iter().enumerate().map(|(i,&v)|(v,i)).collect();
    let mut layer:Vec<_>=raw.iter().map(|v|numbered[v]).collect();
    let mut width:Vec<_>=g.nodes.iter().map(|(_,s)|(s.len()+2)as i64).collect();
    let mut chains=vec![Vec::new();g.edges.len()];
    for(i,&(a,b))in dag.iter().enumerate(){
        if removed[i]{
            continue;
        }
        let mut chain=vec![a];
        for l in layer[a]+1..layer[b]{
            chain.push(layer.len());
            layer.push(l);
            width.push(1);
        }
        chain.push(b);
        chains[i]=chain;
    }
    let mut gaps=vec![Vec::new();used.len().saturating_sub(1)];
    let mut upper=vec![Vec::new();layer.len()];
    let mut lower=vec![Vec::new();layer.len()];
    for(i,chain)in chains.iter().enumerate(){
        for w in chain.windows(2){
            gaps[layer[w[0]]].push(Segment{
                p:w[0],
                q:w[1],
                edge:i
            });
            upper[w[1]].push(w[0]);
            lower[w[0]].push(w[1]);
        }
    }
    fn visit(v:usize,layer:&[usize],lower:&[Vec<usize>],visited:&mut[bool],order:&mut[Vec<usize>]){
        if visited[v]{
            return;
        }
        visited[v]=true;
        order[layer[v]].push(v);
        for &w in &lower[v]{
            visit(w,layer,lower,visited,order);
        }
    }
    let mut initial=vec![Vec::new();used.len()];
    let mut visited=vec![false;layer.len()];
    for v in 0..n{
        visit(v,&layer,&lower,&mut visited,&mut initial);
    }
    Model{
        layer,
        width,
        chains,
        gaps,
        upper,
        lower,
        initial
    }
}
struct Reduction{
    order:Vec<Vec<usize>>,
    records:Vec<String>,
    csv:Vec<String>,
    initial:usize,
    swept:usize,
    run:usize,
    sweep:usize
}
fn reduce(g:&Graph,m:&Model)->Reduction{
    let n=m.layer.len();
    let mut random=g.settings.integer("seed")as i64;
    let mut records=Vec::new();
    let mut csv=Vec::new();
    let mut adopted=m.initial.clone();
    let(mut best_count,mut best_run,mut best_sweep,mut initial)=(usize::MAX,0,0,0);
    for run in 0..=g.settings.integer("restarts"){
        let mut order=m.initial.clone();
        if run>0{
            for layer in &mut order{
                for j in(1..layer.len()).rev(){
                    random=(48271*random)%2147483647;
                    layer.swap(j,random as usize%(j+1));
                }
            }
        }
        let count=crossing::total(&m.gaps,&order,n);
        if run==0{
            initial=count;
        }
        let(mut run_count,mut run_sweep,mut run_order)=(count,0,order.clone());
        let mut history=vec![order.clone()];
        let mut counts=vec![count];
        records.push(format!("sweep {} 0 initial crossings {}",run,count));
        csv.push(format!("{},{},0,{}",g.name,run,count));
        for sweep in 1..=g.settings.integer("sweeps"){
            let last=sweep-1;
            if counts[last]==0||last>=2&&history[last]==history[last-2]{
                break;
            }
            let old=crossing::positions(&order,n);
            let mut layers:Vec<_>=if sweep%2==1{
                (1..order.len()).collect()
            }else{
                (0..order.len().saturating_sub(1)).rev().collect()
            };
            for i in layers.drain(..){
                let pos=crossing::positions(&order,n);
                let reference=if sweep%2==1{
                    &m.upper
                }else{
                    &m.lower
                };
                let mut moving:Vec<_>=order[i].iter().copied().filter(|&v|!reference[v].is_empty()).collect();
                let key=|v:usize|{
                    let mut values:Vec<_>=reference[v].iter().map(|&u|pos[u]as i64).collect();
                    values.sort();
                    if g.settings.text("heuristic")=="median"{
                        (values[(values.len()-1)/2]+values[values.len()/2],1)
                    }else{
                        (values.iter().sum::<i64>(),values.len()as i64)
                    }
                };
                moving.sort_by(|&a,&b|{
                    let(x,y)=key(a);
                    let(u,v)=key(b);
                    (x*v).cmp(&(u*y))
                });
                let mut next=moving.into_iter();
                for v in &mut order[i]{
                    if !reference[*v].is_empty(){
                        *v=next.next().unwrap();
                    }
                }
            }
            let mut pos=crossing::positions(&order,n);
            let moved=(0..n).filter(|&v|pos[v]!=old[v]).count();
            let mut swaps=0;
            loop{
                let mut changed=false;
                for row in &mut order{
                    for j in 0..row.len().saturating_sub(1){
                        let(v,w)=(row[j],row[j+1]);
                        if crossing::adjacent(v,w,&m.upper,&m.lower,&pos)>crossing::adjacent(w,v,&m.upper,&m.lower,&pos){
                            row.swap(j,j+1);
                            pos[v]=j+1;
                            pos[w]=j;
                            swaps+=1;
                            changed=true;
                        }
                    }
                }
                if !changed{
                    break;
                }
            }
            let count=crossing::total(&m.gaps,&order,n);
            history.push(order.clone());
            counts.push(count);
            records.push(format!("sweep {} {} {} moved {} swaps {} crossings {}",run,sweep,if sweep%2==1{
                "down"
            }else{
                "up"
            },moved,swaps,count));
            csv.push(format!("{},{},{},{}",g.name,run,sweep,count));
            if count<run_count{
                run_count=count;
                run_sweep=sweep;
                run_order=order.clone();
            }
        }
        if run_count<best_count{
            best_count=run_count;
            best_run=run;
            best_sweep=run_sweep;
            adopted=run_order;
        }
    }
    records.push(format!("best run {} sweep {} crossings {}",best_run,best_sweep,best_count));
    if g.settings.on("sifting"){
        let mut round=0;
        loop{
            round+=1;
            let mut moves=0;
            for v in 0..n{
                let i=m.layer[v];
                let old=adopted[i].iter().position(|&u|u==v).unwrap();
                let mut base=adopted[i].clone();
                base.remove(old);
                let mut costs=Vec::new();
                for p in 0..=base.len(){
                    let mut row=base.clone();
                    row.insert(p,v);
                    adopted[i]=row;
                    costs.push(crossing::total(&m.gaps,&adopted,n));
                }
                let minimum=*costs.iter().min().unwrap();
                let position=if costs[old]==minimum{
                    old
                }else{
                    costs.iter().position(|&c|c==minimum).unwrap()
                };
                base.insert(position,v);
                adopted[i]=base;
                if position!=old{
                    moves+=1;
                }
            }
            records.push(format!("sift {} moves {} crossings {}",round,moves,crossing::total(&m.gaps,&adopted,n)));
            if moves==0{
                break;
            }
        }
    }
    Reduction{
        order:adopted,
        records,
        csv,
        initial,
        swept:best_count,
        run:best_run,
        sweep:best_sweep
    }
}
struct Geometry{
    tracks:Vec<usize>,
    gaps:Vec<usize>,
    offsets:Vec<Vec<Option<usize>>>,
    thickness:Vec<usize>,
    starts:Vec<usize>,
    main:usize,
    secondary:usize
}
fn geometry(g:&Graph,m:&Model,order:&[Vec<usize>],c:&coordinates::Coordinates)->Geometry{
    let mut tracks=Vec::new();
    let mut gaps=Vec::new();
    let mut offsets=Vec::new();
    for segments in &m.gaps{
        let mut counts=BTreeMap::new();
        for s in segments{
            if c.x[s.p]!=c.x[s.q]{
                *counts.entry(s.p).or_insert(0usize)+=1;
            }
        }
        let mut buses:BTreeMap<(usize,usize),Vec<usize>>=BTreeMap::new();
        for(k,s)in segments.iter().enumerate(){
            if c.x[s.p]!=c.x[s.q]{
                let key=if counts[&s.p]>=2{
                    (0,s.p)
                }else{
                    (1,s.q)
                };
                buses.entry(key).or_default().push(k);
            }
        }
        let mut buses:Vec<_>=buses.into_iter().map(|((kind,v),members)|{
            let lo=members.iter().map(|&k|c.x[segments[k].p].min(c.x[segments[k].q])).min().unwrap();
            let hi=members.iter().map(|&k|c.x[segments[k].p].max(c.x[segments[k].q])).max().unwrap();
            (lo,hi,kind,c.x[v],members)
        }).collect();
        buses.sort_by_key(|b|(b.0,b.1,b.2,b.3));
        let mut ends=Vec::new();
        let mut assignments=vec![None;segments.len()];
        for(lo,hi,_,_,members)in buses{
            let t=ends.iter().position(|&e|e+1<lo).unwrap_or(ends.len());
            if t==ends.len(){
                ends.push(hi);
            }else{
                ends[t]=hi;
            }
            for k in members{
                assignments[k]=Some(t+1);
            }
        }
        let gap=g.settings.integer("layer_gap").max(ends.len()+2);
        for o in &mut assignments{
            if let Some(t)=o{
                *t+=(gap-2-ends.len())/2;
            }
        }
        tracks.push(ends.len());
        gaps.push(gap);
        offsets.push(assignments);
    }
    let vertical=["TB","BT"].contains(&g.settings.text("direction"));
    let thickness:Vec<_>=order.iter().map(|row|if vertical{
        1
    }else{
        row.iter().map(|&v|m.width[v]as usize).max().unwrap()
    }).collect();
    let mut starts=vec![0;order.len()];
    for i in 1..order.len(){
        starts[i]=starts[i-1]+thickness[i-1]+gaps[i-1];
    }
    let main=starts[order.len()-1]+thickness[order.len()-1];
    let secondary=(0..m.layer.len()).map(|v|c.x[v]+c.right[v]).max().unwrap()as usize+1;
    Geometry{
        tracks,
        gaps,
        offsets,
        thickness,
        starts,
        main,
        secondary
    }
}
fn path(g:&Graph,removed:&[bool])->Option<Vec<usize>>{
    let(start,goal)=g.path?;
    let mut parent=vec![None;g.nodes.len()];
    let mut visited=vec![false;g.nodes.len()];
    let mut queue=VecDeque::new();
    visited[start]=true;
    queue.push_back(start);
    while let Some(a)=queue.pop_front(){
        let mut neighbors:Vec<_>=g.edges.iter().enumerate().filter(|(i,(u,_))|!removed[*i]&&*u==a).map(|(_,(_,v))|*v).collect();
        neighbors.sort();
        for b in neighbors{
            if !visited[b]{
                visited[b]=true;
                parent[b]=Some(a);
                queue.push_back(b);
            }
        }
    }
    if !visited[goal]{
        return None;
    }
    let mut path=vec![goal];
    let mut a=goal;
    while a!=start{
        a=parent[a].unwrap();
        path.push(a);
    }
    path.reverse();
    Some(path)
}
fn draw(g:&Graph,m:&Model,c:&coordinates::Coordinates,geo:&Geometry,reversed:&[bool],removed:&[bool],path:Option<&Vec<usize>>)->(canvas::Canvas,Vec<Vec<(usize,usize)>>,Vec<usize>,Vec<usize>){
    let direction=g.settings.text("direction");
    let vertical=["TB","BT"].contains(&direction);
    let mut canvas=canvas::Canvas::new(geo.main,geo.secondary,direction);
    for v in 0..m.layer.len(){
        let i=m.layer[v];
        if v>=g.nodes.len(){
            for j in 0..geo.thickness[i]{
                canvas.line(geo.starts[i]+j,c.x[v]as usize,true);
            }
        }else if !vertical&&!m.lower[v].is_empty(){
            for j in m.width[v]as usize..geo.thickness[i]{
                canvas.line(geo.starts[i]+j,c.x[v]as usize,true);
            }
        }
    }
    for(i,segments)in m.gaps.iter().enumerate(){
        let g0=geo.starts[i]+geo.thickness[i];
        let gap=geo.gaps[i];
        for(k,s)in segments.iter().enumerate(){
            let(p,q)=(c.x[s.p]as usize,c.x[s.q]as usize);
            if let Some(o)=geo.offsets[i][k]{
                for j in 0..o{
                    canvas.line(g0+j,p,true);
                }
                canvas.corner(g0+o,p);
                canvas.corner(g0+o,q);
                for x in p.min(q)+1..p.max(q){
                    canvas.line(g0+o,x,false);
                }
                for j in o+1..gap{
                    canvas.line(g0+j,q,true);
                }
            }else{
                for j in 0..gap{
                    canvas.line(g0+j,p,true);
                }
            }
        }
    }
    let mut routes=vec![Vec::new();g.edges.len()];
    let mut lengths=vec![0;g.edges.len()];
    let mut bends=vec![0;g.edges.len()];
    for(e,chain)in m.chains.iter().enumerate(){
        if removed[e]{
            continue;
        }
        let a=chain[0];
        let b=*chain.last().unwrap();
        let upper=(geo.starts[m.layer[a]]+if vertical{
            1
        }else{
            m.width[a]as usize
        },c.x[a]as usize);
        let lower=(geo.starts[m.layer[b]]-1,c.x[b]as usize);
        let mut points=vec![upper];
        for w in chain.windows(2){
            let i=m.layer[w[0]];
            let k=m.gaps[i].iter().position(|s|s.p==w[0]&&s.q==w[1]).unwrap();
            if let Some(o)=geo.offsets[i][k]{
                let main=geo.starts[i]+geo.thickness[i]+o;
                points.push((main,c.x[w[0]]as usize));
                points.push((main,c.x[w[1]]as usize));
                bends[e]+=2;
            }
        }
        points.push(lower);
        let mut points:Vec<_>=points.iter().map(|&(a,b)|canvas.map(a,b)).collect();
        if reversed[e]{
            points.reverse();
            canvas.arrow(upper.0,upper.1,true);
        }else{
            canvas.arrow(lower.0,lower.1,false);
        }
        lengths[e]=1+points.windows(2).map(|w|w[0].0.abs_diff(w[1].0)+w[0].1.abs_diff(w[1].1)).sum::<usize>();
        routes[e]=points;
    }
    let on_path:BTreeSet<_>=path.map_or_else(BTreeSet::new,|p|p.iter().copied().collect());
    if let Some(path)=path{
        for w in path.windows(2){
            let e=g.edges.iter().position(|&(a,b)|a==w[0]&&b==w[1]).unwrap();
            for segment in routes[e].windows(2){
                let((r1,c1),(r2,c2))=(segment[0],segment[1]);
                if r1==r2{
                    for col in c1.min(c2)..=c1.max(c2){
                        canvas.highlight(r1,col);
                    }
                }else{
                    for row in r1.min(r2)..=r1.max(r2){
                        canvas.highlight(row,c1);
                    }
                }
            }
        }
    }
    for v in 0..g.nodes.len(){
        let i=m.layer[v];
        let highlighted=on_path.contains(&v);
        let label=format!("{}{}{}",if highlighted{
            '{'
        }else{
            '['
        },g.nodes[v].1,if highlighted{
            '}'
        }else{
            ']'
        });
        let(row,column)=if vertical{
            canvas.map(geo.starts[i],(c.x[v]-c.left[v])as usize)
        }else if direction=="LR"{
            (c.x[v]as usize,geo.starts[i])
        }else{
            (c.x[v]as usize,geo.main-geo.starts[i]-m.width[v]as usize)
        };
        canvas.label(row,column,&label);
    }
    (canvas,routes,lengths,bends)
}
fn process(g:&Graph)->(Vec<String>,Vec<String>,Vec<String>,Vec<String>,[usize;5]){
    let n=g.nodes.len();
    let id=|v:usize|g.nodes[v].0.to_string();
    let edge_name=|e:usize|format!("{}->{}",g.nodes[g.edges[e].0].0,g.nodes[g.edges[e].1].0);
    let(sources,sinks,isolated,components,scc)=analysis(g);
    let sequence=acyclic_layering::sequence(n,&g.edges);
    let mut position=vec![0;n];
    for(i,&v)in sequence.iter().enumerate(){
        position[v]=i;
    }
    let reversed:Vec<_>=g.edges.iter().map(|&(a,b)|position[a]>position[b]).collect();
    let dag:Vec<_>=g.edges.iter().enumerate().map(|(i,&(a,b))|if reversed[i]{
        (b,a)
    }else{
        (a,b)
    }).collect();
    let reach=reach(n,&dag);
    let removed:Vec<_>=dag.iter().enumerate().map(|(i,&(a,b))|g.settings.on("reduce")&&!reversed[i]&&dag.iter().any(|&(u,c)|u==a&&c!=b&&reach[c][b])).collect();
    let drawn:Vec<_>=dag.iter().enumerate().filter(|(i,_)|!removed[*i]).map(|(_,e)|*e).collect();
    let layering=acyclic_layering::assign(n,&drawn,g.settings.text("layering")=="coffman",g.settings.integer("width"),g.settings.on("promotion"));
    let m=model(g,&layering.heights,&dag,&removed);
    let reduced=reduce(g,&m);
    let c=coordinates::assign(n,&reduced.order,&m.layer,&m.upper,&m.lower,&m.width,["TB","BT"].contains(&g.settings.text("direction")),g.settings.integer("node_sep")as i64,g.settings.integer("dummy_sep")as i64);
    let geo=geometry(g,&m,&reduced.order,&c);
    let path=path(g,&removed);
    let(canvas,routes,lengths,bends)=draw(g,&m,&c,&geo,&reversed,&removed,path.as_ref());
    let vertices=m.layer.len();
    let name=|v:usize|if v<n{
        id(v)
    }else{
        format!("d{}",v-n+1)
    };
    let pos=crossing::positions(&reduced.order,vertices);
    let counts:Vec<_>=m.gaps.iter().enumerate().map(|(i,s)|crossing::count(s,&pos,reduced.order[i+1].len())).collect();
    let final_count:usize=counts.iter().sum();
    let brute:usize=m.gaps.iter().map(|s|crossing::brute(s,&pos)).sum();
    let mut edge_crossings=vec![0usize;g.edges.len()];
    for gap in &m.gaps{
        for i in 0..gap.len(){
            for j in i+1..gap.len(){
                let(a,b)=(&gap[i],&gap[j]);
                if(pos[a.p]<pos[b.p]&&pos[a.q]>pos[b.q])||(pos[a.p]>pos[b.p]&&pos[a.q]<pos[b.q]){
                    edge_crossings[a.edge]+=1;
                    edge_crossings[b.edge]+=1;
                }
            }
        }
    }
    let mut layout=vec![format!("graph {}",g.name),format!("settings {}",graph_io::NAMES.iter().zip(&g.settings.values).map(|(n,v)|format!("{}={}",n,v)).collect::<Vec<_>>().join(" ")),format!("acyclic {}",sequence.iter().map(|&v|id(v)).collect::<Vec<_>>().join(" "))];
    if g.settings.text("layering")=="coffman"{
        layout.push(format!("labels {}",(0..n).map(|v|format!("{}:{}",id(v),layering.labels[v])).collect::<Vec<_>>().join(" ")));
    }
    for &(round,v,diff)in &layering.promotions{
        layout.push(format!("promote {} {} {}",round,id(v),diff));
    }
    layout.extend(reduced.records.clone());
    for(i,row)in reduced.order.iter().enumerate(){
        let start=geo.starts[i];
        let end=start+geo.thickness[i]-1;
        let(band_lo,band_hi)=if ["BT","RL"].contains(&g.settings.text("direction")){
            (geo.main-1-end,geo.main-1-start)
        }else{
            (start,end)
        };
        let lo=row.iter().map(|&v|c.x[v]-c.left[v]).min().unwrap();
        let hi=row.iter().map(|&v|c.x[v]+c.right[v]).max().unwrap();
        layout.push(format!("layer {} band {} {} extent {} {} : {}",i,band_lo,band_hi,lo,hi,row.iter().map(|&v|format!("{}@{}",name(v),c.x[v])).collect::<Vec<_>>().join(" ")));
    }
    for i in 0..m.gaps.len(){
        layout.push(format!("between {} {} segments {} crossings {} tracks {} gap {}",i,i+1,m.gaps[i].len(),counts[i],geo.tracks[i],geo.gaps[i]));
    }
    let variants=["ul","ur","dl","dr"];
    layout.push(format!("bk conflicts {} {} smallest {}",c.conflicts,(0..4).map(|i|format!("{}={}/{}",variants[i],c.blocks[i],c.widths[i])).collect::<Vec<_>>().join(" "),variants[c.smallest]));
    for row in &reduced.order{
        for &v in row{
            layout.push(format!("vertex {} layer {} pos {} ul {} ur {} dl {} dr {} x {}",name(v),m.layer[v],pos[v],c.aligned[0][v],c.aligned[1][v],c.aligned[2][v],c.aligned[3][v],c.x[v]));
        }
    }
    for e in 0..g.edges.len(){
        let(a,b)=g.edges[e];
        if removed[e]{
            layout.push(format!("edge {} {} transitive",id(a),id(b)));
        }else{
            let mut chain=m.chains[e].clone();
            if reversed[e]{
                chain.reverse();
            }
            layout.push(format!("edge {} {}{} span {} crossings {} bends {} path {} route {}",id(a),id(b),if reversed[e]{
                " reversed"
            }else{
                ""
            },chain.len()-1,edge_crossings[e],bends[e],chain.iter().map(|&v|c.x[v].to_string()).collect::<Vec<_>>().join(" "),routes[e].iter().map(|(r,c)|format!("{},{}",r,c)).collect::<Vec<_>>().join(" ")));
        }
    }
    layout.push("end".into());
    let mut stats=vec![format!("graph {}",g.name),format!("nodes {} edges {} self_loops {} duplicates {}",n,g.edges.len(),g.loops,g.duplicates),format!("sources {} sinks {} isolated {} components {}",sources,sinks,isolated,components)];
    for s in scc{
        stats.push(format!("scc {}",s.iter().map(|&v|id(v)).collect::<Vec<_>>().join(" ")));
    }
    for(label,flags)in[("reversed",&reversed),("transitive",&removed)].iter(){
        let names:Vec<_>=(0..g.edges.len()).filter(|&e|flags[e]).map(|e|edge_name(e)).collect();
        stats.push(format!("{} {}{}",label,names.len(),if names.is_empty(){
            String::new()
        }else{
            format!(" {}",names.join(" "))
        }));
    }
    stats.push(format!("layers {} max_nodes {} max_vertices {}",reduced.order.len(),reduced.order.iter().map(|r|r.iter().filter(|&&v|v<n).count()).max().unwrap(),reduced.order.iter().map(Vec::len).max().unwrap()));
    stats.push(if g.settings.on("promotion"){
        format!("promotion rounds {} accepted {} dummies_before {}",layering.rounds,layering.promotions.len(),layering.before)
    }else{
        "promotion off".into()
    });
    let mut spans=BTreeMap::new();
    for chain in &m.chains{
        if !chain.is_empty(){
            *spans.entry(chain.len()-1).or_insert(0usize)+=1;
        }
    }
    stats.push(format!("dummies {} span_total {} span_max {}",vertices-n,m.chains.iter().filter(|r|!r.is_empty()).map(|r|r.len()-1).sum::<usize>(),spans.keys().next_back().copied().unwrap_or(0)));
    stats.push(format!("spans {}",if spans.is_empty(){
        "none".into()
    }else{
        spans.iter().map(|(s,n)|format!("{}:{}",s,n)).collect::<Vec<_>>().join(" ")
    }));
    let long:Vec<_>=m.chains.iter().filter(|r|r.len()>=3).collect();
    let vertical=long.iter().filter(|r|r[1..r.len()-1].iter().all(|&v|c.x[v]==c.x[r[1]])).count();
    stats.push(format!("long_edges {} vertical {}",long.len(),vertical));
    stats.push(format!("crossings initial {} swept {} best_run {} best_sweep {} final {} brute {}",reduced.initial,reduced.swept,reduced.run,reduced.sweep,final_count,brute));
    let segments:Vec<_>=m.gaps.iter().flat_map(|s|s.iter()).collect();
    let straight=segments.iter().filter(|s|c.x[s.p]==c.x[s.q]).count();
    stats.push(format!("segments {} straight {} bent {} offset {}",segments.len(),straight,segments.len()-straight,segments.iter().map(|s|(c.x[s.p]-c.x[s.q]).abs()).sum::<i64>()));
    let longest=(0..g.edges.len()).filter(|&e|!removed[e]).min_by_key(|&e|(std::cmp::Reverse(lengths[e]),e));
    stats.push(format!("routes length {} bends {}{}",lengths.iter().sum::<usize>(),bends.iter().sum::<usize>(),longest.map_or_else(String::new,|e|format!(" longest {} {}",edge_name(e),lengths[e]))));
    stats.push(format!("canvas width {} height {} crossing_cells {}",canvas.columns,canvas.rows,canvas.crossings()));
    if let Some((a,b))=g.path{
        stats.push(if let Some(path)=&path{
            format!("path {} {} hops {} : {}",id(a),id(b),path.len()-1,path.iter().map(|&v|id(v)).collect::<Vec<_>>().join(" "))
        }else{
            format!("path {} {} none",id(a),id(b))
        });
    }
    stats.push("end".into());
    let mut drawings=vec![format!("graph {} {}x{}",g.name,canvas.columns,canvas.rows)];
    drawings.extend(canvas.report());
    (layout,stats,reduced.csv,drawings,[n,g.edges.len(),vertices-n,reduced.initial,final_count])
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
    let graphs=graph_io::read();
    let(mut layout,mut stats,mut drawings)=(Vec::new(),Vec::new(),Vec::new());
    let mut csv=vec!["graph,run,sweep,crossings".into()];
    let mut totals=[0usize;5];
    let mut errors=0;
    for g in &graphs{
        if !drawings.is_empty(){
            drawings.push(String::new());
        }
        if let Some((error,line))=&g.error{
            errors+=1;
            let block=vec![format!("graph {}",g.name),format!("error {} line {}",error,line),"end".into()];
            layout.extend(block.clone());
            stats.extend(block);
            drawings.push(format!("graph {} error {}",g.name,error));
        }else{
            let(l,s,c,d,t)=process(g);
            layout.extend(l);
            stats.extend(s);
            csv.extend(c);
            drawings.extend(d);
            for i in 0..5{
                totals[i]+=t[i];
            }
        }
    }
    stats.push(format!("summary graphs {} laid_out {} errors {} nodes {} edges {} dummies {} crossings_initial {} crossings_final {}",graphs.len(),graphs.len()-errors,errors,totals[0],totals[1],totals[2],totals[3],totals[4]));
    write("layout.txt",&layout);
    write("stats.txt",&stats);
    write("crossings.csv",&csv);
    write("drawings.txt",&drawings);
}
