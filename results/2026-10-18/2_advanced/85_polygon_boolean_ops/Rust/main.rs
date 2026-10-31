mod rational;
mod intersections;
mod greiner_hormann;
mod rings;
mod render;
use std::collections::{BTreeMap,BTreeSet};
use std::fs;
use rational::{Point,cross,x_cmp,y_cmp};
use rings::{Ring,Rings,Region};
use intersections::{on,touch,overlap,segment};
#[derive(Clone)] struct Polygon{
    input:Rings,
    rings:Rings
}
#[derive(Clone)] struct Target{
    region:Region,
    operands:Option<(Rings,Rings)>
}
fn integer(s:&str)->Option<i128>{
    let digits=s.strip_prefix('-').unwrap_or(s);
    if digits.is_empty()||digits.len()>9||!digits.bytes().all(|c|c.is_ascii_digit()){
        None
    }else{
        s.parse().ok()
    }
}
fn name(s:&str)->bool{
    !s.is_empty()&&s.len()<=16&&s.bytes().all(|c|c.is_ascii_lowercase()||c.is_ascii_digit()||c==b'_')
}
fn validate(rings:&Rings)->Option<String>{
    for(k,r)in rings.iter().enumerate(){
        let n=r.len();
        if n<3{
            return Some(format!("too_few_vertices ring {}",k+1));
        }
        for &p in r{
            if p.x<0||p.y<0||p.x>1000*p.d||p.y>1000*p.d{
                return Some(format!("out_of_range ring {} {}",k+1,p));
            }
        }
        let mut seen=BTreeSet::new();
        for &p in r{
            if !seen.insert(p){
                return Some(format!("duplicate_vertex ring {} {}",k+1,p));
            }
        }
        for i in 0..n{
            if cross(r[(i+n-1)%n],r[i],r[(i+1)%n])==0{
                return Some(format!("collinear ring {} {}",k+1,r[i]));
            }
        }
        for i in 0..n{
            for j in i+1..n{
                if j==i+1||i==0&&j==n-1{
                    continue;
                }
                if touch(r[i],r[(i+1)%n],r[j],r[(j+1)%n]){
                    return Some(format!("self_intersection ring {} {} {}",k+1,segment(r[i],r[(i+1)%n]),segment(r[j],r[(j+1)%n])));
                }
            }
        }
    }
    for i in 0..rings.len(){
        for j in i+1..rings.len(){
            for e in 0..rings[i].len(){
                for f in 0..rings[j].len(){
                    let(a,b,c,d)=(rings[i][e],rings[i][(e+1)%rings[i].len()],rings[j][f],rings[j][(f+1)%rings[j].len()]);
                    if touch(a,b,c,d){
                        return Some(format!("rings_touch rings {} {} {} {}",i+1,j+1,segment(a,b),segment(c,d)));
                    }
                }
            }
        }
    }
    for k in 1..rings.len(){
        if !rings::inside(rings[k][0],&rings[0]){
            return Some(format!("hole_outside ring {} {}",k+1,rings[k][0]));
        }
    }
    for i in 1..rings.len(){
        for j in i+1..rings.len(){
            if rings::inside(rings[j][0],&rings[i]){
                return Some(format!("hole_in_hole rings {} {} {}",i+1,j+1,rings[j][0]));
            }
            if rings::inside(rings[i][0],&rings[j]){
                return Some(format!("hole_in_hole rings {} {} {}",i+1,j+1,rings[i][0]));
            }
        }
    }
    None
}
fn parse_block(content:&[(usize,String)],end:usize)->Result<Rings,String>{
    let mut rings=Vec::new();
    let mut i=0;
    while i<content.len(){
        let(line,text)=&content[i];
        let a:Vec<_>=text.split(' ').collect();
        let n=if a.len()==2&&(a[0]=="OUTER"&&rings.is_empty()||a[0]=="HOLE"&&!rings.is_empty())&&a[1].len()<=9&&!a[1].is_empty()&&a[1].bytes().all(|c|c.is_ascii_digit()){
            a[1].parse::<usize>().ok().filter(|&n|n>0)
        }else{
            None
        };
        let n=n.ok_or_else(||format!("format line {}",line))?;
        i+=1;
        let mut ring=Vec::new();
        for _ in 0..n{
            if i==content.len(){
                return Err(format!("format line {}",end));
            }
            let(line,text)=&content[i];
            let a:Vec<_>=text.split(' ').collect();
            let point=if a.len()==2{
                integer(a[0]).zip(integer(a[1]))
            }else{
                None
            };
            let(x,y)=point.ok_or_else(||format!("format line {}",line))?;
            ring.push(Point::integer(x,y));
            i+=1;
        }
        rings.push(ring);
    }
    if rings.is_empty(){
        Err(format!("format line {}",end))
    }else{
        Ok(rings)
    }
}
fn polygons()->(BTreeMap<String,Option<Polygon>>,Vec<String>,usize,usize){
    let text=fs::read_to_string("input/polygons.txt").unwrap();
    let lines:Vec<_>=text.lines().collect();
    let mut polygons=BTreeMap::new();
    let mut rejected=Vec::new();
    let(mut i,mut blocks,mut valid)=(0,0,0);
    while i<lines.len(){
        if lines[i].is_empty()||lines[i].starts_with('#'){
            i+=1;
            continue;
        }
        let name=lines[i].split(' ').nth(1).unwrap().to_string();
        let start=i+1;
        i+=1;
        let mut content=Vec::new();
        while lines[i]!="END"{
            if !lines[i].is_empty()&&!lines[i].starts_with('#'){
                content.push((i+1,lines[i].to_string()));
            }
            i+=1;
        }
        let end=i+1;
        i+=1;
        blocks+=1;
        if polygons.contains_key(&name){
            rejected.push(format!("polygon {} duplicate_name line {}",name,start));
            continue;
        }
        match parse_block(&content,end){
            Err(error)=>{
                rejected.push(format!("polygon {} {}",name,error));
                polygons.insert(name,None);
            },Ok(input)=>if let Some(error)=validate(&input){
                rejected.push(format!("polygon {} {}",name,error));
                polygons.insert(name,None);
            }else{
                let rings=rings::canonical(input.clone());
                polygons.insert(name,Some(Polygon{
                    input,
                    rings
                }));
                valid+=1;
            }
        }
    }
    (polygons,rejected,blocks,valid)
}
fn get_polygon<'a>(name:&str,polygons:&'a BTreeMap<String,Option<Polygon>>)->Result<&'a Polygon,String>{
    match polygons.get(name){
        None=>Err(format!("unknown_polygon {}",name)),Some(None)=>Err(format!("invalid_polygon {}",name)),Some(Some(p))=>Ok(p)
    }
}
fn target(text:&str,polygons:&BTreeMap<String,Option<Polygon>>,results:&BTreeMap<usize,Target>)->Result<Target,String>{
    if let Some(n)=text.strip_prefix('@'){
        if n.is_empty()||n.len()>9||!n.bytes().all(|c|c.is_ascii_digit()){
            return Err(format!("bad_target {}",text));
        }
        let k=n.parse().unwrap();
        results.get(&k).cloned().ok_or_else(||format!("bad_target {}",text))
    }else{
        let p=get_polygon(text,polygons)?;
        Ok(Target{
            region:vec![p.rings.clone()],
            operands:None
        })
    }
}
fn general(a:&Rings,b:&Rings,an:&str,bn:&str)->Option<String>{
    for r in a{
        for &p in r{
            if b.iter().any(|q|q.contains(&p)){
                return Some(format!("shared_vertex {}",p));
            }
        }
    }
    for r in a{
        for e in 0..r.len(){
            for q in b{
                for f in 0..q.len(){
                    let(u,v,s,t)=(r[e],r[(e+1)%r.len()],q[f],q[(f+1)%q.len()]);
                    if overlap(u,v,s,t){
                        return Some(format!("overlapping_edges {} {}",segment(u,v),segment(s,t)));
                    }
                }
            }
        }
    }
    for(p,q,pn,qn)in[(a,b,an,bn),(b,a,bn,an)].iter(){
        for r in *p{
            for &v in r{
                for s in *q{
                    for e in 0..s.len(){
                        let(u,w)=(s[e],s[(e+1)%s.len()]);
                        if on(u,w,v){
                            return Some(format!("vertex_on_edge {} {} {} {}",pn,v,qn,segment(u,w)));
                        }
                    }
                }
            }
        }
    }
    None
}
fn convex(rings:&Rings)->bool{
    rings.len()==1&&(0..rings[0].len()).all(|i|{
        let r=&rings[0];
        cross(r[(i+r.len()-1)%r.len()],r[i],r[(i+1)%r.len()])>0
    })
}
fn clip(a:&Rings,w:&Ring)->Rings{
    let mut result=Vec::new();
    for r in a{
        let mut l=r.clone();
        for j in 0..w.len(){
            let(c1,c2)=(w[j],w[(j+1)%w.len()]);
            let mut m=Vec::new();
            for i in 0..l.len(){
                let(prev,cur)=(l[(i+l.len()-1)%l.len()],l[i]);
                let(pin,cin)=(cross(c1,c2,prev)>0,cross(c1,c2,cur)>0);
                if pin!=cin{
                    m.push(intersections::line_intersection(prev,cur,c1,c2));
                }
                if cin{
                    m.push(cur);
                }
            }
            l=m;
        }
        let clean:Vec<_>=l.iter().enumerate().filter(|(i,p)|**p!=l[(*i+l.len()-1)%l.len()]).map(|(_,p)|*p).collect();
        if clean.len()>=3{
            result.push(clean);
        }
    }
    result
}
fn cyclic(a:&Ring,b:&Ring)->bool{
    a.len()==b.len()&&(0..b.len()).any(|k|(0..a.len()).all(|i|a[i]==b[(i+k)%b.len()]))
}
fn locate(region:&Region,p:Point)->String{
    for(k,polygon)in region.iter().enumerate(){
        for(j,r)in polygon.iter().enumerate(){
            if rings::boundary(p,r){
                return if j==0{
                    format!("boundary outer {}",k+1)
                }else{
                    format!("boundary hole {} {}",k+1,j)
                };
            }
        }
    }
    for(k,polygon)in region.iter().enumerate(){
        if rings::inside(p,&polygon[0])&&polygon[1..].iter().all(|r|!rings::inside(p,r)){
            return format!("inside polygon {}",k+1);
        }
    }
    "outside".into()
}
fn operand_location(p:Point,r:&Rings)->&'static str{
    if r.iter().any(|r|rings::boundary(p,r)){
        "boundary"
    }else if rings::interior(p,r){
        "inside"
    }else{
        "outside"
    }
}
fn hull(r:&Ring)->Ring{
    let mut s=r.clone();
    s.sort_by(|a,b|x_cmp(*a,*b).then(y_cmp(*a,*b)));
    let mut lower:Ring=Vec::new();
    for &p in &s{
        while lower.len()>=2&&cross(lower[lower.len()-2],lower[lower.len()-1],p)<=0{
            lower.pop();
        }
        lower.push(p);
    }
    let mut upper:Ring=Vec::new();
    for &p in s.iter().rev(){
        while upper.len()>=2&&cross(upper[upper.len()-2],upper[upper.len()-1],p)<=0{
            upper.pop();
        }
        upper.push(p);
    }
    lower.pop();
    upper.pop();
    lower.extend(upper);
    lower
}
fn integer_twice_area(r:&Ring)->i128{
    (0..r.len()).map(|i|r[i].x*r[(i+1)%r.len()].y-r[(i+1)%r.len()].x*r[i].y).sum()
}
fn values(region:&Region,a:&Rings,b:Option<&Rings>)->(Vec<String>,usize,usize,usize,f64){
    let count_rings=region.iter().map(Vec::len).sum::<usize>();
    let holes=count_rings-region.len();
    let vertices=region.iter().flat_map(|p|p.iter()).map(Vec::len).sum::<usize>();
    let area=rings::total_area(region);
    let mut lines=vec![format!("polygons {} rings {} holes {} vertices {} area {:.3}",region.len(),count_rings,holes,vertices,area)];
    let(mut sx,mut sy,mut perimeter)=(0.0,0.0,0.0);
    let(mut acount,mut bcount,mut xcount)=(0,0,0);
    let mut points=Vec::new();
    for(k,p)in region.iter().enumerate(){
        for(j,r)in p.iter().enumerate(){
            let label=if j==0{
                format!("outer {}",k+1)
            }else{
                format!("hole {} {}",k+1,j)
            };
            lines.push(format!("{} {} {:.3} {}",label,r.len(),rings::area(r),r.iter().map(Point::to_string).collect::<Vec<_>>().join(" ")));
            perimeter+=rings::perimeter(r);
            for i in 0..r.len(){
                let(x1,y1)=r[i].real();
                let(x2,y2)=r[(i+1)%r.len()].real();
                let c=x1*y2-x2*y1;
                sx+=(x1+x2)*c;
                sy+=(y1+y2)*c;
                let v=r[i];
                if a.iter().any(|r|r.contains(&v)){
                    acount+=1;
                }else if b.map_or(false,|b|b.iter().any(|r|r.contains(&v))){
                    bcount+=1;
                }else{
                    xcount+=1;
                }
                points.push(v);
            }
        }
    }
    if points.is_empty(){
        lines.push("bbox none".into());
        lines.push("centroid none".into());
    }else{
        let minx=points.iter().min_by(|a,b|x_cmp(**a,**b)).unwrap();
        let miny=points.iter().min_by(|a,b|y_cmp(**a,**b)).unwrap();
        let maxx=points.iter().max_by(|a,b|x_cmp(**a,**b)).unwrap();
        let maxy=points.iter().max_by(|a,b|y_cmp(**a,**b)).unwrap();
        let low=Point::new(minx.x*miny.d,miny.y*minx.d,minx.d*miny.d);
        let high=Point::new(maxx.x*maxy.d,maxy.y*maxx.d,maxx.d*maxy.d);
        lines.push(format!("bbox {} {}",low,high));
        lines.push(format!("centroid ({:.3},{:.3})",sx/(6.0*area),sy/(6.0*area)));
    }
    lines.push(format!("perimeter {:.3}",perimeter));
    lines.push(format!("origins a {} b {} crossing {}",acount,bcount,xcount));
    (lines,count_rings,holes,vertices,area)
}
fn properties(p:&Polygon,area:f64)->Vec<String>{
    let orientations=p.input.iter().map(|r|if integer_twice_area(r)>0{
        "ccw"
    }else{
        "cw"
    }).collect::<Vec<_>>().join(" ");
    let reflex=p.rings.iter().map(|r|(0..r.len()).filter(|&i|cross(r[(i+r.len()-1)%r.len()],r[i],r[(i+1)%r.len()])<0).count()).sum::<usize>();
    let hull=hull(&p.rings[0]);
    let hull_area=integer_twice_area(&hull)as f64/2.0;
    vec![format!("input {}",orientations),format!("reflex {}",reflex),format!("hull {} {:.3} solidity {:.6}",hull.len(),hull_area,area/hull_area)]
}
const KINDS:[&str;12]=["UNION","INTERSECTION","DIFFERENCE","XOR","CLIP","AREA","MOVE","ROTATE","MIRROR","SNAP","LOCATE","RENDER"];
fn arguments(a:&[&str])->bool{
    let expected=match a[0]{
        "UNION"|"INTERSECTION"|"DIFFERENCE"|"XOR"|"CLIP"|"SNAP"=>3,"AREA"=>2,"LOCATE"=>4,"MOVE"|"MIRROR"=>5,"ROTATE"=>6,"RENDER"=>8,_=>return false
    };
    if a.len()!=expected{
        return false;
    }
    let valid=|i:usize,lo:i128,hi:i128|integer(a[i]).map_or(false,|v|lo<=v&&v<=hi);
    match a[0]{
        "LOCATE"=>valid(2,0,1000)&&valid(3,0,1000),"RENDER"=>{
            if !(valid(2,0,1000)&&valid(3,0,1000)&&valid(4,1,100)&&valid(5,1,100)&&valid(6,1,100)&&valid(7,1,60)){
                return false;
            }
            let v:Vec<_>=a[2..].iter().map(|s|integer(s).unwrap()).collect();
            v[0]+v[2]*v[4]<=1000&&v[1]+v[3]*v[5]<=1000
        },"MOVE"=>valid(2,-1000,1000)&&valid(3,-1000,1000)&&name(a[4]),"ROTATE"=>valid(2,0,1000)&&valid(3,0,1000)&&valid(4,1,3)&&name(a[5]),"MIRROR"=>(a[2]=="x"||a[2]=="y")&&valid(3,0,1000)&&name(a[4]),"SNAP"=>name(a[2]),_=>true
    }
}
struct Operation{
    lines:Vec<String>,
    area:Option<String>,
    drawing:Vec<String>,
    target:Option<Target>,
    definition:Option<(String,Polygon)>,
    crossings:usize
}
fn operation(number:usize,text:&str,polygons:&BTreeMap<String,Option<Polygon>>,results:&BTreeMap<usize,Target>)->Result<Operation,String>{
    let a:Vec<_>=text.split(' ').collect();
    let kind=a[0];
    if !KINDS.contains(&kind){
        return Err(format!("unknown_operation {}",kind));
    }
    if !arguments(&a){
        return Err("bad_arguments".into());
    }
    let binary=KINDS[..5].contains(&kind);
    let defining=["MOVE","ROTATE","MIRROR","SNAP"].contains(&kind);
    let input=if binary||["AREA","MOVE","ROTATE","MIRROR"].contains(&kind){
        Some(get_polygon(a[1],polygons)?.clone())
    }else{
        None
    };
    let b=if binary{
        Some(get_polygon(a[2],polygons)?.clone())
    }else{
        None
    };
    let resolved=if ["LOCATE","RENDER","SNAP"].contains(&kind){
        Some(target(a[1],polygons,results)?)
    }else{
        None
    };
    let newname=if defining{
        Some(*a.last().unwrap())
    }else{
        None
    };
    if let Some(n)=newname{
        if polygons.contains_key(n){
            return Err(format!("duplicate_name {}",n));
        }
    }
    if kind=="SNAP"&&resolved.as_ref().unwrap().region.len()!=1{
        return Err(format!("not_single {}",a[1]));
    }
    if kind=="CLIP"&&!convex(&b.as_ref().unwrap().rings){
        return Err(format!("not_convex {}",a[2]));
    }
    if binary{
        if let Some(reason)=general(&input.as_ref().unwrap().rings,&b.as_ref().unwrap().rings,a[1],a[2]){
            return Err(reason);
        }
    }
    let mut op=Operation{
        lines:vec![format!("op {} {}",number,text)],
        area:None,
        drawing:Vec::new(),
        target:None,
        definition:None,
        crossings:0
    };
    if kind=="LOCATE"{
        let target=resolved.unwrap();
        let point=Point::integer(integer(a[2]).unwrap(),integer(a[3]).unwrap());
        op.lines.push(format!("location {}",locate(&target.region,point)));
        if let Some((a,b))=&target.operands{
            op.lines.push(format!("operands a {} b {}",operand_location(point,a),operand_location(point,b)));
        }
        return Ok(op);
    }
    if kind=="RENDER"{
        let target=resolved.unwrap();
        let values:Vec<_>=a[2..].iter().map(|s|integer(s).unwrap()).collect();
        let(drawing,counts)=render::draw(&target.region,target.operands.as_ref(),&values);
        op.drawing.push(format!("render {} {} cols {} rows {} result {} a {} b {} both {}",number,a[1],values[4],values[5],counts[0],counts[1],counts[2],counts[3]));
        op.drawing.extend(drawing);
        op.lines.clear();
        return Ok(op);
    }
    let mut polygon=input.clone();
    if defining{
        let input_rings:Rings=if kind=="SNAP"{
            resolved.unwrap().region[0].iter().map(|r|r.iter().map(|p|p.snap()).collect()).collect()
        }else{
            input.as_ref().unwrap().input.iter().map(|r|r.iter().map(|p|{
                let(mut x,mut y)=(p.x,p.y);
                match kind{
                    "MOVE"=>{
                        x+=integer(a[2]).unwrap();
                        y+=integer(a[3]).unwrap();
                    },"ROTATE"=>{
                        let(cx,cy,q)=(integer(a[2]).unwrap(),integer(a[3]).unwrap(),integer(a[4]).unwrap());
                        for _ in 0..q{
                            let(nx,ny)=(cx-(y-cy),cy+(x-cx));
                            x=nx;
                            y=ny;
                        }
                    },_=>{
                        let c=integer(a[3]).unwrap();
                        if a[2]=="x"{
                            x=2*c-x;
                        }else{
                            y=2*c-y;
                        }
                    }
                }
                Point::integer(x,y)
            }).collect()).collect()
        };
        if kind=="SNAP"{
            if let Some(reason)=validate(&input_rings){
                return Err(format!("invalid_result {}",reason));
            }
        }else if input_rings.iter().flat_map(|r|r.iter()).any(|p|p.x<0||p.y<0||p.x>1000||p.y>1000){
            return Err(format!("out_of_range {}",newname.unwrap()));
        }
        let defined=Polygon{
            rings:rings::canonical(input_rings.clone()),
            input:input_rings
        };
        op.definition=Some((newname.unwrap().into(),defined.clone()));
        polygon=Some(defined);
    }
    let region;
    if binary{
        let(a_rings,b_rings)=(&input.as_ref().unwrap().rings,&b.as_ref().unwrap().rings);
        let graph=greiner_hormann::Graph::new(a_rings,b_rings);
        let relation=if !graph.ordered.is_empty(){
            "overlap"
        }else if graph.na==a_rings.len()&&graph.nb==0{
            "within"
        }else if graph.nb==b_rings.len()&&graph.na==0{
            "contains"
        }else if graph.na==0&&graph.nb==0{
            "disjoint"
        }else{
            "overlap"
        };
        let union=graph.result("UNION");
        let intersection=graph.result("INTERSECTION");
        let iou=rings::total_area(&intersection)/rings::total_area(&union);
        op.crossings=graph.ordered.len();
        op.lines.push(format!("relation {} iou {:.6}",relation,iou));
        op.lines.push(format!("crossings {}",op.crossings));
        for &(point,enter)in &graph.ordered{
            op.lines.push(format!("crossing {} {}",point,if enter{
                "in"
            }else{
                "out"
            }));
        }
        region=match kind{
            "UNION"=>union,"INTERSECTION"|"CLIP"=>intersection,"DIFFERENCE"=>graph.result("DIFFERENCE"),_=>{
                let mut result=graph.result("DIFFERENCE");
                result.extend(greiner_hormann::Graph::new(b_rings,a_rings).result("DIFFERENCE"));
                result.sort_by_key(|p|p[0][0]);
                result
            }
        };
        op.target=Some(Target{
            region:region.clone(),
            operands:Some((a_rings.clone(),b_rings.clone()))
        });
    }else{
        region=vec![polygon.as_ref().unwrap().rings.clone()];
        op.target=Some(Target{
            region:region.clone(),
            operands:None
        });
    }
    let operand_a=if binary{
        &input.as_ref().unwrap().rings
    }else{
        &polygon.as_ref().unwrap().rings
    };
    let(values,rings_count,holes,vertices,area)=values(&region,operand_a,b.as_ref().map(|p|&p.rings));
    op.lines.extend(values);
    op.area=Some(format!("{}:{},{},{},{},{:.3}",number,a.join(":"),rings_count,holes,vertices,area));
    if !binary{
        op.lines.extend(properties(polygon.as_ref().unwrap(),area));
    }
    if kind=="CLIP"{
        let clipped=clip(operand_a,&b.as_ref().unwrap().rings[0]);
        let result_rings:Vec<_>=region.iter().flat_map(|p|p.iter()).collect();
        let matched=result_rings.len()==clipped.len()&&result_rings.iter().all(|r|clipped.iter().any(|c|cyclic(r,c)));
        op.lines.push(format!("crosscheck {} rings {} vertices {}",if matched{
            "match"
        }else{
            "mismatch"
        },clipped.len(),clipped.iter().map(Vec::len).sum::<usize>()));
    }
    Ok(op)
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
    let(mut polygons,mut rejections,blocks,valid)=polygons();
    let mut targets=BTreeMap::new();
    let mut result=Vec::new();
    let mut areas=vec!["operation,rings,holes,vertices,area".into()];
    let mut drawing=Vec::new();
    let(mut total,mut succeeded,mut defined,mut crossings)=(0,0,0,0);
    let mut kinds=[[0usize;2];12];
    for line in fs::read_to_string("input/operations.txt").unwrap().lines(){
        if line.is_empty()||line.starts_with('#'){
            continue;
        }
        total+=1;
        let kind=line.split(' ').next().unwrap();
        let index=KINDS.iter().position(|k|*k==kind);
        if let Some(i)=index{
            kinds[i][0]+=1;
        }
        match operation(total,line,&polygons,&targets){
            Err(reason)=>rejections.push(format!("op {} {}",total,reason)),Ok(op)=>{
                succeeded+=1;
                kinds[index.unwrap()][1]+=1;
                crossings+=op.crossings;
                result.extend(op.lines);
                if let Some(area)=op.area{
                    areas.push(area);
                }
                drawing.extend(op.drawing);
                if let Some(target)=op.target{
                    targets.insert(total,target);
                }
                if let Some((name,polygon))=op.definition{
                    polygons.insert(name,Some(polygon));
                    defined+=1;
                }
            }
        }
    }
    result.push(format!("summary polygons {} valid {} invalid {} defined {}",blocks,valid,blocks-valid,defined));
    result.push(format!("summary operations {} succeeded {} rejected {}",total,succeeded,total-succeeded));
    result.push(format!("summary crossings {}",crossings));
    for(i,kind)in KINDS.iter().enumerate(){
        result.push(format!("kind {} {} {}",kind,kinds[i][0],kinds[i][1]));
    }
    rejections.insert(0,format!("rejections {}",rejections.len()));
    write("results.txt",&result);
    write("areas.csv",&areas);
    write("render.txt",&drawing);
    write("rejections.txt",&rejections);
}
