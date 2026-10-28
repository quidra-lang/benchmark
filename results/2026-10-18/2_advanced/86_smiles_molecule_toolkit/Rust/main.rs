mod molecule;
mod smiles_parser;
mod rings_aromatic;
mod canonical;
mod search;
use std::collections::{BTreeMap,BTreeSet};
use std::fs;
use molecule::{Molecule,Elements,Error};
use search::{Pattern,Fingerprint};
fn valid_name(s:&str)->bool{
    !s.is_empty()&&s.len()<=32&&s.bytes().all(|c|c.is_ascii_alphanumeric()||c==b'_'||c==b'-')
}
fn number(s:&str,lo:usize,hi:usize)->Option<usize>{
    if s.is_empty()||s.len()>1&&s.starts_with('0')||!s.bytes().all(|c|c.is_ascii_digit()){
        return None;
    }
    s.parse::<usize>().ok().filter(|&n|lo<=n&&n<=hi)
}
fn threshold(s:&str)->Option<(usize,usize)>{
    let a:Vec<_>=s.split('/').collect();
    if a.len()!=2{
        return None;
    }
    let p=number(a[0],0,99)?;
    let q=number(a[1],1,99)?;
    if p<=q{
        Some((p,q))
    }else{
        None
    }
}
fn gcd(mut a:usize,mut b:usize)->usize{
    while b!=0{
        let r=a%b;
        a=b;
        b=r;
    }
    a
}
fn fraction(p:usize,q:usize)->String{
    let g=gcd(p,q);
    format!("{}/{}",p/g,q/g)
}
fn list(a:&[usize],separator:&str)->String{
    a.iter().map(usize::to_string).collect::<Vec<_>>().join(separator)
}
fn analyze(text:&str,e:&Elements)->Result<Molecule,Error>{
    let mut m=smiles_parser::parse(text,e,false)?.molecule;
    rings_aromatic::detect(&mut m);
    for b in &mut m.bonds{
        if b.kind==0{
            b.kind=if m.atoms[b.a].aromatic&&m.atoms[b.b].aromatic&&b.ring{
                4
            }else{
                1
            };
        }
    }
    rings_aromatic::kekulize(&mut m,e)?;
    for i in 0..m.atoms.len(){
        let atom=&m.atoms[i];
        if atom.bracket{
            if m.multiplicity(i)+atom.hydrogens>e[&atom.element].valences.last().unwrap()+atom.charge.unsigned_abs()as usize{
                return Err(Error::new("bad valence",atom.column));
            }
        }else{
            let h=m.organic_hydrogens(i,e).ok_or_else(||Error::new("bad valence",atom.column))?;
            m.atoms[i].hydrogens=h;
        }
    }
    Ok(m)
}
fn scaffold(m:&Molecule,e:&Elements)->Option<String>{
    if m.rings.is_empty(){
        return None;
    }
    let ring_atoms:BTreeSet<_>=m.rings.iter().flat_map(|r|r.iter().copied()).collect();
    let mut remaining:BTreeSet<_>=(0..m.atoms.len()).collect();
    loop{
        let removed=remaining.iter().copied().find(|i|!ring_atoms.contains(i)&&m.neighbors[*i].iter().filter(|(j,_)|remaining.contains(j)).count()==1);
        if let Some(i)=removed{
            remaining.remove(&i);
        }else{
            break;
        }
    }
    let core=remaining.clone();
    for b in &m.bonds{
        if b.kind==2{
            if core.contains(&b.a){
                remaining.insert(b.b);
            }
            if core.contains(&b.b){
                remaining.insert(b.a);
            }
        }
    }
    let mut graph=Molecule::default();
    let mut index=BTreeMap::new();
    for &i in &remaining{
        index.insert(i,graph.atoms.len());
        let mut atom=m.atoms[i].clone();
        atom.hydrogens+=m.neighbors[i].iter().filter(|(j,_)|!remaining.contains(j)).map(|&(_,e)|m.bonds[e].multiplicity).sum::<usize>();
        graph.atoms.push(atom);
    }
    for b in &m.bonds{
        if remaining.contains(&b.a)&&remaining.contains(&b.b){
            let mut b=b.clone();
            b.a=index[&b.a];
            b.b=index[&b.b];
            graph.bonds.push(b);
        }
    }
    graph.rebuild();
    Some(canonical::smiles(&graph,e).0)
}
struct Analysis{
    name:String,
    graph:Molecule,
    smiles:String,
    classes:usize,
    formula:String,
    weight:i64,
    heavy:usize,
    rotatable:usize,
    donors:usize,
    acceptors:usize,
    lipinski:&'static str,
    charge:i32,
    scaffold:Option<String>,
    fingerprint:Fingerprint
}
fn properties(name:String,m:Molecule,e:&Elements)->Analysis{
    let mut counts=BTreeMap::new();
    let mut weight=0;
    let mut hydrogens=0;
    for a in &m.atoms{
        *counts.entry(a.element.clone()).or_insert(0usize)+=1;
        hydrogens+=a.hydrogens;
        weight+=if a.mass==0{
            e[&a.element].mass
        }else{
            a.mass as i64*1000
        };
    }
    *counts.entry("H".into()).or_default()+=hydrogens;
    weight+=hydrogens as i64*e["H"].mass;
    counts.retain(|_,n|*n>0);
    let mut order=Vec::new();
    if counts.contains_key("C"){
        order.push("C".to_string());
        if counts.contains_key("H"){
            order.push("H".to_string());
        }
    }
    let remaining:Vec<_>=counts.keys().filter(|s|!order.contains(s)).cloned().collect();
    order.extend(remaining);
    let formula=order.iter().map(|s|format!("{}{}",s,if counts[s]>1{
        counts[s].to_string()
    }else{
        String::new()
    })).collect::<String>();
    let heavy=m.atoms.iter().filter(|a|a.element!="H").count();
    let heavy_degree:Vec<_>=m.neighbors.iter().map(|n|n.iter().filter(|&&(j,_)|m.atoms[j].element!="H").count()).collect();
    let triple:Vec<_>=m.neighbors.iter().map(|n|n.iter().any(|&(_,e)|m.bonds[e].multiplicity==3)).collect();
    let rotatable=m.bonds.iter().filter(|b|b.multiplicity==1&&!b.ring&&heavy_degree[b.a]>=2&&heavy_degree[b.b]>=2&&!triple[b.a]&&!triple[b.b]).count();
    let acceptors=m.atoms.iter().filter(|a|a.element=="N"||a.element=="O").count();
    let donors=m.atoms.iter().enumerate().filter(|(i,a)|(a.element=="N"||a.element=="O")&&(a.hydrogens>0||m.neighbors[*i].iter().any(|&(j,_)|m.atoms[j].element=="H"))).count();
    let lipinski=if usize::from(weight>500000)+usize::from(donors>5)+usize::from(acceptors>10)<=1{
        "pass"
    }else{
        "fail"
    };
    let charge=m.atoms.iter().map(|a|a.charge).sum();
    let(smiles,classes)=canonical::smiles(&m,e);
    let scaffold=scaffold(&m,e);
    let fingerprint=search::fingerprint(&m,e);
    Analysis{
        name,
        graph:m,
        smiles,
        classes,
        formula,
        weight,
        heavy,
        rotatable,
        donors,
        acceptors,
        lipinski,
        charge,
        scaffold,
        fingerprint
    }
}
fn systems(m:&Molecule)->Vec<(Vec<usize>,&'static str,usize)>{
    let mut remaining:BTreeSet<_>=(0..m.rings.len()).collect();
    let mut result=Vec::new();
    while let Some(&start)=remaining.iter().next(){
        let mut group=BTreeSet::new();
        let mut stack=vec![start];
        remaining.remove(&start);
        while let Some(i)=stack.pop(){
            group.insert(i);
            let neighbors:Vec<_>=remaining.iter().copied().filter(|&j|m.rings[i].iter().any(|a|m.rings[j].contains(a))).collect();
            for j in neighbors{
                remaining.remove(&j);
                stack.push(j);
            }
        }
        let rings:Vec<_>=group.into_iter().collect();
        let atoms:BTreeSet<_>=rings.iter().flat_map(|&i|m.rings[i].iter().copied()).collect();
        let mut kind="isolated";
        if rings.len()>1{
            kind="spiro";
            for x in 0..rings.len(){
                for y in x+1..rings.len(){
                    let common:Vec<_>=m.rings[rings[x]].iter().copied().filter(|a|m.rings[rings[y]].contains(a)).collect();
                    if common.len()>=2{
                        if common.len()==2&&m.bond(common[0],common[1]).is_some(){
                            if kind!="bridged"{
                                kind="fused";
                            }
                        }else{
                            kind="bridged";
                        }
                    }
                }
            }
        }
        result.push((rings,kind,atoms.len()));
    }
    result
}
fn paragraph(output:&mut Vec<String>,lines:Vec<String>){
    if !output.is_empty(){
        output.push(String::new());
    }
    output.extend(lines);
}
fn canonical_report(molecules:&[Analysis])->Vec<String>{
    let mut result=Vec::new();
    let unique=molecules.iter().map(|m|m.smiles.clone()).collect::<BTreeSet<_>>().len();
    let mut lines=vec![format!("CANONICAL molecules={} unique={}",molecules.len(),unique)];
    for m in molecules{
        lines.push(format!("{} {} classes={} charge={}",m.name,m.smiles,m.classes,if m.charge>0{
            format!("+{}",m.charge)
        }else{
            m.charge.to_string()
        }));
    }
    paragraph(&mut result,lines);
    let mut duplicates:BTreeMap<String,Vec<usize>>=BTreeMap::new();
    let mut formulas:BTreeMap<String,Vec<usize>>=BTreeMap::new();
    let mut scaffolds:BTreeMap<String,Vec<usize>>=BTreeMap::new();
    for(i,m)in molecules.iter().enumerate(){
        duplicates.entry(m.smiles.clone()).or_default().push(i);
        formulas.entry(m.formula.clone()).or_default().push(i);
        if let Some(s)=&m.scaffold{
            scaffolds.entry(s.clone()).or_default().push(i);
        }
    }
    let names=|ids:&[usize]|ids.iter().map(|&i|molecules[i].name.clone()).collect::<Vec<_>>().join(",");
    let mut groups:Vec<_>=duplicates.into_iter().filter(|(_,v)|v.len()>=2).collect();
    groups.sort_by_key(|(_,v)|v[0]);
    let mut lines=vec![format!("DUPLICATES groups={} molecules={}",groups.len(),groups.iter().map(|(_,v)|v.len()).sum::<usize>())];
    for(i,(smiles,members))in groups.iter().enumerate(){
        lines.push(format!("group {} {} members={}",i+1,smiles,names(members)));
    }
    paragraph(&mut result,lines);
    let mut groups:Vec<_>=formulas.into_iter().filter_map(|(formula,members)|{
        let forms=members.iter().map(|&i|&molecules[i].smiles).collect::<BTreeSet<_>>().len();
        if forms>=2{
            Some((formula,members,forms))
        }else{
            None
        }
    }).collect();
    groups.sort_by_key(|(_,v,_)|v[0]);
    let mut lines=vec![format!("ISOMERS groups={}",groups.len())];
    for(i,(formula,members,forms))in groups.iter().enumerate(){
        lines.push(format!("isomer {} {} forms={} members={}",i+1,formula,forms,names(members)));
    }
    paragraph(&mut result,lines);
    let mut groups:Vec<_>=scaffolds.into_iter().collect();
    groups.sort_by(|a,b|b.1.len().cmp(&a.1.len()).then(a.0.cmp(&b.0)));
    let mut lines=vec![format!("SCAFFOLDS distinct={} acyclic={}",groups.len(),molecules.iter().filter(|m|m.scaffold.is_none()).count())];
    for(i,(smiles,members))in groups.iter().enumerate(){
        lines.push(format!("scaffold {} {} count={} members={}",i+1,smiles,members.len(),names(members)));
    }
    paragraph(&mut result,lines);
    result
}
fn rings_report(molecules:&[Analysis])->Vec<String>{
    let mut result=Vec::new();
    let(mut total,mut aromatic,mut cyclic)=(0,0,0);
    let mut sizes=BTreeMap::new();
    let mut kinds=[0;4];
    for m in molecules{
        let graph=&m.graph;
        if graph.rings.is_empty(){
            continue;
        }
        cyclic+=1;
        total+=graph.rings.len();
        let ar=graph.rings.iter().filter(|r|r.iter().all(|&i|graph.atoms[i].aromatic)).count();
        aromatic+=ar;
        let systems=systems(graph);
        let ring_atoms=graph.rings.iter().flat_map(|r|r.iter()).collect::<BTreeSet<_>>().len();
        let mut lines=vec![format!("MOLECULE {} atoms={} bonds={} rings={} aromatic={} systems={} ring_atoms={} ring_bonds={}",m.name,graph.atoms.len(),graph.bonds.len(),graph.rings.len(),ar,systems.len(),ring_atoms,graph.bonds.iter().filter(|b|b.ring).count())];
        for(i,r)in graph.rings.iter().enumerate(){
            *sizes.entry(r.len()).or_insert(0usize)+=1;
            let a=r.iter().all(|&i|graph.atoms[i].aromatic);
            let hetero=r.iter().filter(|&&i|graph.atoms[i].element!="C").count();
            lines.push(format!("ring {} size={} aromatic={} hetero={} atoms={}",i+1,r.len(),if a{
                "yes"
            }else{
                "no"
            },hetero,list(&r.iter().map(|i|i+1).collect::<Vec<_>>(),"-")));
        }
        for(i,(rings,kind,atoms))in systems.iter().enumerate(){
            kinds[["isolated","fused","spiro","bridged"].iter().position(|s|s==kind).unwrap()]+=1;
            lines.push(format!("system {} kind={} rings={} atoms={}",i+1,kind,list(&rings.iter().map(|i|i+1).collect::<Vec<_>>(),","),atoms));
        }
        let double:Vec<_>=graph.bonds.iter().filter(|b|b.kind==4&&b.multiplicity==2).map(|b|format!("{}={}",b.a+1,b.b+1)).collect();
        lines.push(format!("kekule {}",if double.is_empty(){
            "-".into()
        }else{
            double.join(" ")
        }));
        paragraph(&mut result,lines);
    }
    let sizes=if sizes.is_empty(){
        "-".into()
    }else{
        sizes.iter().map(|(s,n)|format!("{}={}",s,n)).collect::<Vec<_>>().join(" ")
    };
    paragraph(&mut result,vec![format!("SUMMARY molecules={} cyclic={} rings={} aromatic={}",molecules.len(),cyclic,total,aromatic),format!("sizes {}",sizes),format!("systems isolated={} fused={} spiro={} bridged={}",kinds[0],kinds[1],kinds[2],kinds[3])]);
    result
}
struct Query{
    kind:String,
    id:String,
    args:Vec<String>,
    indices:Vec<usize>,
    pattern:Option<Pattern>,
    count:usize,
    threshold:(usize,usize)
}
fn query(a:&[&str],names:&BTreeMap<String,usize>,e:&Elements)->Result<Query,String>{
    let kind=a[0];
    let args=&a[2..];
    let len=args.len();
    let valid=match kind{
        "MATCH"|"CLUSTER"=>len==1,"MATRIX"=>(2..=12).contains(&len),_=>len==2
    };
    if !valid{
        return Err("bad arguments".into());
    }
    let mut q=Query{
        kind:kind.into(),
        id:a[1].into(),
        args:args.iter().map(|s|s.to_string()).collect(),
        indices:Vec::new(),
        pattern:None,
        count:0,
        threshold:(0,1)
    };
    match kind{
        "MATCH"=>q.pattern=Some(Pattern::parse(args[0],e).map_err(|error|format!("bad pattern {} at column {}",error.reason,error.column))?),"CLUSTER"=>q.threshold=threshold(args[0]).ok_or_else(||"bad threshold".to_string())?,"NEAREST"|"WITHIN"=>{
            q.indices.push(*names.get(args[0]).ok_or_else(||format!("unknown molecule {}",args[0]))?);
            if kind=="NEAREST"{
                q.count=number(args[1],1,99).ok_or_else(||"bad count".to_string())?;
            }else{
                q.threshold=threshold(args[1]).ok_or_else(||"bad threshold".to_string())?;
            }
        },_=>{
            for s in args{
                q.indices.push(*names.get(*s).ok_or_else(||format!("unknown molecule {}",s))?);
            }
            if q.indices.iter().collect::<BTreeSet<_>>().len()!=q.indices.len(){
                return Err("repeated molecule".into());
            }
        }
    }
    Ok(q)
}
fn compare(a:(usize,usize),b:(usize,usize))->std::cmp::Ordering{
    (a.0*b.1).cmp(&(b.0*a.1))
}
fn process(q:&Query,molecules:&[Analysis],sub:&mut Vec<String>,similarity:&mut Vec<String>,counts:&mut[usize;4]){
    let sim=|a:usize,b:usize|search::similarity(&molecules[a].fingerprint,&molecules[b].fingerprint);
    match q.kind.as_str(){
        "MATCH"=>{
            counts[0]+=1;
            let p=q.pattern.as_ref().unwrap();
            let matches:Vec<_>=molecules.iter().enumerate().map(|(i,m)|(i,search::embeddings(p,&m.graph))).filter(|(_,m)|m.count>0).collect();
            counts[1]+=matches.len();
            let mut lines=vec![format!("MATCH {} {} atoms={} bonds={} hits={} embeddings={}",q.id,q.args[0],p.graph.atoms.len(),p.graph.bonds.len(),matches.len(),matches.iter().map(|(_,m)|m.count).sum::<usize>())];
            for(i,m)in &matches{
                lines.push(format!("{} count={} unique={} map={}",molecules[*i].name,m.count,m.unique,list(&m.first,",")));
            }
            if let Some((i,m))=matches.iter().min_by_key(|(i,m)|(std::cmp::Reverse(m.count),*i)){
                lines.push(format!("top {} count={}",molecules[*i].name,m.count));
            }
            paragraph(sub,lines);
        },"CONTAINS"=>{
            counts[2]+=1;
            let(a,b)=(q.indices[0],q.indices[1]);
            let matches=search::embeddings(&Pattern::molecule(&molecules[a].graph),&molecules[b].graph);
            let result=if matches.count>0{
                counts[3]+=1;
                format!("yes count={} unique={} map={}",matches.count,matches.unique,list(&matches.first,","))
            }else{
                "no".into()
            };
            paragraph(sub,vec![format!("CONTAINS {} {} {} result={}",q.id,q.args[0],q.args[1],result)]);
        },"MATRIX"=>{
            let mut lines=vec![format!("MATRIX {} size={}",q.id,q.indices.len())];
            for &a in &q.indices{
                lines.push(format!("row {} {}",molecules[a].name,q.indices.iter().map(|&b|{
                    let(c,u)=sim(a,b);
                    fraction(c,u)
                }).collect::<Vec<_>>().join(" ")));
            }
            let mut best=(0,1,sim(q.indices[0],q.indices[1]));
            for a in 0..q.indices.len(){
                for b in a+1..q.indices.len(){
                    let s=sim(q.indices[a],q.indices[b]);
                    if compare(s,best.2).is_gt(){
                        best=(a,b,s);
                    }
                }
            }
            lines.push(format!("best {} {} {}",q.args[best.0],q.args[best.1],fraction(best.2.0,best.2.1)));
            paragraph(similarity,lines);
        },"NEAREST"|"WITHIN"=>{
            let x=q.indices[0];
            let mut results:Vec<_>=(0..molecules.len()).filter(|&i|i!=x).map(|i|(i,sim(x,i))).collect();
            results.sort_by(|a,b|compare(b.1,a.1).then(a.0.cmp(&b.0)));
            if q.kind=="NEAREST"{
                results.truncate(q.count);
            }else{
                results.retain(|(_,s)|compare(*s,q.threshold).is_ge());
            }
            let first=if q.kind=="NEAREST"{
                format!("NEAREST {} {} count={}",q.id,q.args[0],results.len())
            }else{
                format!("WITHIN {} {} threshold={} count={}",q.id,q.args[0],fraction(q.threshold.0,q.threshold.1),results.len())
            };
            let mut lines=vec![first];
            for(k,(i,(c,u)))in results.iter().enumerate(){
                lines.push(format!("{} {} {} common={}",k+1,molecules[*i].name,fraction(*c,*u),c));
            }
            paragraph(similarity,lines);
        },"COMPARE"=>{
            let(a,b)=(q.indices[0],q.indices[1]);
            let(c,u)=sim(a,b);
            paragraph(similarity,vec![format!("COMPARE {} {} {} bits={},{} common={} union={} tanimoto={} identical={}",q.id,q.args[0],q.args[1],molecules[a].fingerprint.bits.len(),molecules[b].fingerprint.bits.len(),c,u,fraction(c,u),if molecules[a].smiles==molecules[b].smiles{
                "yes"
            }else{
                "no"
            })]);
        },_=>{
            let n=molecules.len();
            let neighbors:Vec<Vec<usize>>=(0..n).map(|i|(0..n).filter(|&j|j!=i&&compare(sim(i,j),q.threshold).is_ge()).collect()).collect();
            let mut order:Vec<_>=(0..n).collect();
            order.sort_by_key(|&i|(std::cmp::Reverse(neighbors[i].len()),i));
            let mut used=BTreeSet::new();
            let mut clusters=Vec::new();
            for i in order{
                if !used.insert(i){
                    continue;
                }
                let mut members=vec![i];
                for &j in &neighbors[i]{
                    if used.insert(j){
                        members.push(j);
                    }
                }
                clusters.push(members);
            }
            let singletons=clusters.iter().filter(|c|c.len()==1).count();
            let mut lines=vec![format!("CLUSTER {} threshold={} clusters={} singletons={}",q.id,fraction(q.threshold.0,q.threshold.1),clusters.len(),singletons)];
            for(k,c)in clusters.iter().filter(|c|c.len()>1).enumerate(){
                lines.push(format!("cluster {} centroid={} size={} members={}",k+1,molecules[c[0]].name,c.len(),c.iter().map(|&i|molecules[i].name.clone()).collect::<Vec<_>>().join(",")));
            }
            paragraph(similarity,lines);
        }
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
    let e=molecule::elements();
    let mut molecules=Vec::new();
    let mut seen=BTreeSet::new();
    let mut molecule_errors=Vec::new();
    let mut causes=BTreeMap::new();
    let mut molecule_lines=0;
    for(i,line)in fs::read_to_string("input/molecules.smi").unwrap().lines().enumerate(){
        if line.is_empty()||line.starts_with('#'){
            continue;
        }
        molecule_lines+=1;
        let a:Vec<_>=line.split(' ').collect();
        let error=if a.len()!=2||a[0].is_empty()||!valid_name(a[1]){
            Some((format!("line {}: bad line",i+1),"bad line".to_string()))
        }else if !seen.insert(a[1].to_string()){
            Some((format!("line {} {}: duplicate name",i+1,a[1]),"duplicate name".to_string()))
        }else{
            match analyze(a[0],&e){
                Ok(m)=>{
                    molecules.push(properties(a[1].into(),m,&e));
                    None
                },Err(error)=>Some((format!("line {} {}: {} at column {}",i+1,a[1],error.reason,error.column),error.reason))
            }
        };
        if let Some((line,cause))=error{
            molecule_errors.push(line);
            *causes.entry(cause).or_insert(0usize)+=1;
        }
    }
    let names:BTreeMap<_,_>=molecules.iter().enumerate().map(|(i,m)|(m.name.clone(),i)).collect();
    let mut properties=vec!["name,formula,weight,heavy_atoms,rings,rotatable,donors,acceptors,lipinski".into()];
    for m in &molecules{
        properties.push(format!("{},{},{}.{:03},{},{},{},{},{},{}",m.name,m.formula,m.weight/1000,m.weight%1000,m.heavy,m.graph.rings.len(),m.rotatable,m.donors,m.acceptors,m.lipinski));
    }
    let mut substructure=Vec::new();
    let mut similarity=vec![format!("FINGERPRINTS molecules={} size=1024 depth=5",molecules.len())];
    for m in &molecules{
        similarity.push(format!("{} bits={} paths={}",m.name,m.fingerprint.bits.len(),m.fingerprint.paths));
    }
    let mut identifiers=BTreeSet::new();
    let mut query_errors=Vec::new();
    let(mut query_lines,mut query_valid)=(0,0);
    let mut counts=[0;4];
    for(i,line)in fs::read_to_string("input/queries.txt").unwrap().lines().enumerate(){
        if line.is_empty()||line.starts_with('#'){
            continue;
        }
        query_lines+=1;
        let a:Vec<_>=line.split(' ').collect();
        let error=if !["MATCH","CONTAINS","MATRIX","NEAREST","WITHIN","COMPARE","CLUSTER"].contains(&a[0]){
            Some((format!("line {}: unknown query",i+1),"unknown query".to_string()))
        }else if a.len()==1||!valid_name(a[1]){
            Some((format!("line {} {}: bad id",i+1,a[0]),"bad id".to_string()))
        }else{
            let checked=if !identifiers.insert(a[1].to_string()){
                Err("duplicate id".to_string())
            }else{
                query(&a,&names,&e)
            };
            match checked{
                Ok(q)=>{
                    query_valid+=1;
                    process(&q,&molecules,&mut substructure,&mut similarity,&mut counts);
                    None
                },Err(reason)=>{
                    let cause=if reason.starts_with("bad pattern "){
                        "bad pattern".into()
                    }else if reason.starts_with("unknown molecule "){
                        "unknown molecule".into()
                    }else{
                        reason.clone()
                    };
                    Some((format!("line {} {} {}: {}",i+1,a[0],a[1],reason),cause))
                }
            }
        };
        if let Some((line,cause))=error{
            query_errors.push(line);
            *causes.entry(cause).or_insert(0usize)+=1;
        }
    }
    paragraph(&mut substructure,vec![format!("SUMMARY patterns={} hits={} contains={} found={}",counts[0],counts[1],counts[2],counts[3])]);
    let mut errors=Vec::new();
    let mut lines=vec![format!("MOLECULES lines={} valid={} errors={}",molecule_lines,molecules.len(),molecule_errors.len())];
    lines.extend(molecule_errors);
    paragraph(&mut errors,lines);
    let mut lines=vec![format!("QUERIES lines={} valid={} errors={}",query_lines,query_valid,query_errors.len())];
    lines.extend(query_errors);
    paragraph(&mut errors,lines);
    let mut causes:Vec<_>=causes.into_iter().collect();
    causes.sort_by(|a,b|b.1.cmp(&a.1).then(a.0.cmp(&b.0)));
    let mut lines=vec![format!("CAUSES kinds={}",causes.len())];
    lines.extend(causes.iter().map(|(r,n)|format!("{}={}",r,n)));
    paragraph(&mut errors,lines);
    write("properties.csv",&properties);
    write("canonical.txt",&canonical_report(&molecules));
    write("rings.txt",&rings_report(&molecules));
    write("substructure.txt",&substructure);
    write("similarity.txt",&similarity);
    write("errors.txt",&errors);
}
