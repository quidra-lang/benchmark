mod lexer;
mod parser;
mod boxes;
mod layout;
mod canvas;
use std::collections::BTreeMap;
use std::fs;
use parser::{Node,Formula};
use boxes::BoxNode as B;
use layout::Params;
fn display(kind:&str,value:&str,references:&BTreeMap<String,String>)->String{
    match kind{
        "command"=>lexer::symbol(value.strip_prefix('\\').unwrap()).unwrap().0,"eqref"=>references.get(value).cloned().unwrap_or_else(||"(??)".into()),_=>value.into()
    }
}
fn typeset(n:&Node,script:bool,p:&Params,references:&BTreeMap<String,String>)->B{
    match n{
        Node::Atom{
            kind,value,..
        }
        =>{
            let description=match kind.as_str(){
                "text"=>format!("text \"{}\"",value),"eqref"=>format!("eqref \"{}\"",value),_=>format!("atom \"{}\"",value)
            };
            if !script&&kind=="command"&&["\\sum","\\prod","\\int"].contains(&value.as_str()){
                let glyph=boxes::large(&value[1..]);
                let mut result=B::new(glyph[0].len(),3,1,description);
                for(y,s)in glyph.into_iter().enumerate(){
                    result.string(0,y,s);
                }
                result
            }else{
                B::text(display(kind,value,references),description)
            }
        },Node::Row(nodes)=>{
            let(_,gaps)=layout::spacing(nodes,script,p);
            layout::row(nodes.iter().map(|n|typeset(n,script,p,references)).collect(),&gaps,"row",&[])
        },Node::Script(base,sub,sup)=>{
            let b=typeset(base,script,p,references);
            let s=sub.as_ref().map(|n|typeset(n,true,p,references));
            let u=sup.as_ref().map(|n|typeset(n,true,p,references));
            let sw=s.as_ref().map_or(0,|b|b.width);
            let sh=s.as_ref().map_or(0,|b|b.height);
            let uw=u.as_ref().map_or(0,|b|b.width);
            let uh=u.as_ref().map_or(0,|b|b.height);
            let stacked=!script&&match base.as_ref(){
                Node::Atom{
                    kind,value,..
                }
                =>kind=="command"&&["\\sum","\\prod","\\lim","\\max","\\min"].contains(&value.as_str()),Node::Accent(name,_)=>name=="overbrace"||name=="underbrace",_=>false
            };
            if stacked{
                let width=b.width.max(sw).max(uw);
                let height=uh+b.height+sh;
                let baseline=uh+b.baseline;
                let bh=b.height;
                let bw=b.width;
                let mut result=B::new(width,height,baseline,"limits");
                result.child(b,(width-bw)/2,uh,"base: ");
                if let Some(s)=s{
                    result.child(s,(width-sw)/2,uh+bh,"sub: ");
                }
                if let Some(u)=u{
                    result.child(u,(width-uw)/2,0,"sup: ");
                }
                result
            }else{
                let tp=if b.baseline==0{
                    -1isize
                }else{
                    0
                }
                -uh as isize+1;
                let ts=if b.height-1-b.baseline==0{
                    b.height
                }else{
                    b.height-1
                };
                let top=if u.is_some(){
                    tp.min(0)
                }else{
                    0
                };
                let bottom=if s.is_some(){
                    (b.height-1).max(ts+sh-1)
                }else{
                    b.height-1
                };
                let shift=(-top)as usize;
                let width=b.width+sw.max(uw);
                let baseline=b.baseline+shift;
                let bw=b.width;
                let mut result=B::new(width,(bottom as isize-top+1)as usize,baseline,"scripts");
                result.child(b,0,shift,"base: ");
                if let Some(s)=s{
                    result.child(s,bw,ts+shift,"sub: ");
                }
                if let Some(u)=u{
                    result.child(u,bw,(tp-top)as usize,"sup: ");
                }
                result
            }
        },Node::Binary(name,a,b)=>{
            if name=="frac"&&script{
                let part=|n:&Node|{
                    if matches!(n,Node::Row(_))||matches!(n,Node::Binary(name,..)if name=="frac"){
                        typeset(&Node::Delimited("(".into(),")".into(),Box::new(n.clone()),0),true,p,references)
                    }else{
                        typeset(n,true,p,references)
                    }
                };
                let numerator=part(a);
                let denominator=part(b);
                let slash=B::text("/".into(),"atom \"/\"".into());
                return layout::row(vec![numerator,slash,denominator],&[0,0],"slash",&["num: ".into(),String::new(),"den: ".into()]);
            }
            let placed=name=="overset"||name=="underset";
            let a=typeset(a,if placed{
                true
            }else{
                script
            },p,references);
            let b=typeset(b,script,p,references);
            let(aw,ah,bw,bh,bb)=(a.width,a.height,b.width,b.height,b.baseline);
            match name.as_str(){
                "frac"=>{
                    let width=aw.max(bw)+2;
                    let mut result=B::new(width,ah+1+bh,ah,"frac");
                    result.string(0,ah,"-".repeat(width));
                    result.child(a,(width-aw)/2,0,"num: ");
                    result.child(b,(width-bw)/2,ah+1,"den: ");
                    result
                },"binom"=>{
                    let width=aw.max(bw);
                    let mut result=B::new(width+2,ah+1+bh,ah,"binom");
                    boxes::add_delimiter(&mut result,"(",0);
                    boxes::add_delimiter(&mut result,")",width+1);
                    result.child(a,1+(width-aw)/2,0,"upper: ");
                    result.child(b,1+(width-bw)/2,ah+1,"lower: ");
                    result
                },"overset"=>{
                    let width=aw.max(bw);
                    let mut result=B::new(width,ah+bh,ah+bb,"overset");
                    result.child(a,(width-aw)/2,0,"over: ");
                    result.child(b,(width-bw)/2,ah,"base: ");
                    result
                },_=>{
                    let width=aw.max(bw);
                    let mut result=B::new(width,ah+bh,bb,"underset");
                    result.child(b,(width-bw)/2,0,"base: ");
                    result.child(a,(width-aw)/2,bh,"under: ");
                    result
                }
            }
        },Node::Root(index,body)=>{
            let body=typeset(body,script,p,references);
            let index=index.as_ref().map(|n|typeset(n,true,p,references));
            let k=body.height;
            let extra=index.as_ref().map_or(0,|i|i.width.saturating_sub(1));
            let top=index.as_ref().map_or(0,|i|i.height.saturating_sub(k));
            let width=extra+k+1+body.width;
            let baseline=body.baseline+1+top;
            let mut result=B::new(width,k+1+top,baseline,if index.is_some(){
                "root"
            }else{
                "sqrt"
            });
            result.string(extra+k+1,top,"_".repeat(body.width));
            result.string(extra,k+top,"\\");
            for r in 1..=k{
                result.string(extra+k-r+1,r+top,"/");
            }
            if let Some(index)=index{
                let height=index.height;
                result.child(index,0,k+top-height,"index: ");
                result.child(body,extra+k+1,1+top,"body: ");
            }else{
                result.child(body,extra+k+1,1+top,"");
            }
            result
        },Node::Delimited(left,right,body,_)=>{
            let body=typeset(body,script,p,references);
            let wl=usize::from(left!=".");
            let wr=usize::from(right!=".");
            let mut result=B::new(wl+body.width+wr,body.height,body.baseline,format!("delim {} {}",left,right));
            let rx=wl+body.width;
            boxes::add_delimiter(&mut result,left,0);
            boxes::add_delimiter(&mut result,right,rx);
            result.child(body,wl,0,"");
            result
        },Node::Matrix(environment,rows)=>{
            let cells:Vec<Vec<_>>=rows.iter().map(|r|r.iter().map(|n|typeset(n,script,p,references)).collect()).collect();
            let columns=rows[0].len();
            let widths:Vec<_>=(0..columns).map(|j|cells.iter().map(|r|r[j].width).max().unwrap()).collect();
            let ascents:Vec<_>=cells.iter().map(|r|r.iter().map(|b|b.baseline).max().unwrap()).collect();
            let descents:Vec<_>=cells.iter().map(|r|r.iter().map(|b|b.height-1-b.baseline).max().unwrap()).collect();
            let heights:Vec<_>=ascents.iter().zip(&descents).map(|(a,d)|a+d+1).collect();
            let body_width=widths.iter().sum::<usize>()+p.col_gap*(columns-1);
            let body_height=heights.iter().sum::<usize>()+p.row_gap*(rows.len()-1);
            let shift=if environment=="matrix"{
                0
            }else{
                2
            };
            let width=body_width+if environment=="matrix"{
                0
            }else if environment=="cases"{
                2
            }else{
                4
            };
            let mut result=B::new(width,body_height,(body_height-1)/2,format!("{} rows={} cols={}",environment,rows.len(),columns));
            match environment.as_str(){
                "pmatrix"=>{
                    boxes::add_delimiter(&mut result,"(",0);
                    boxes::add_delimiter(&mut result,")",body_width+3);
                },"bmatrix"=>{
                    boxes::add_delimiter(&mut result,"[",0);
                    boxes::add_delimiter(&mut result,"]",body_width+3);
                },"vmatrix"=>{
                    boxes::add_delimiter(&mut result,"|",0);
                    boxes::add_delimiter(&mut result,"|",body_width+3);
                },"cases"=>boxes::add_delimiter(&mut result,"\\{",0),_=>()
            };
            let mut y=0;
            for(i,row)in cells.into_iter().enumerate(){
                let mut x=shift;
                for(j,b)in row.into_iter().enumerate(){
                    let offset=if environment=="cases"{
                        0
                    }else{
                        (widths[j]-b.width)/2
                    };
                    let by=y+ascents[i]-b.baseline;
                    result.child(b,x+offset,by,&format!("cell {},{}: ",i+1,j+1));
                    x+=widths[j]+p.col_gap;
                }
                y+=heights[i]+p.row_gap;
            }
            result
        },Node::Accent(name,body)=>{
            let body=typeset(body,script,p,references);
            let(bw,bh,bb)=(body.width,body.height,body.baseline);
            let width=match name.as_str(){
                "hat"|"dot"|"tilde"=>bw.max(1),"vec"=>bw.max(2),"overbrace"|"underbrace"=>bw+2,_=>bw
            };
            let baseline=if name=="underbrace"{
                bb
            }else{
                bb+1
            };
            let mut result=B::new(width,bh+1,baseline,name.clone());
            match name.as_str(){
                "overline"=>result.string(0,0,"_".repeat(width)),"hat"|"dot"|"tilde"=>result.string((width-1)/2,0,match name.as_str(){
                    "hat"=>"^","dot"=>".",_=>"~"
                }),"vec"=>result.string(0,0,format!("{}>","-".repeat(width-1))),"overbrace"=>result.string(0,0,format!("/{}\\","-".repeat(bw))),_=>result.string(0,bh,format!("\\{}/","-".repeat(bw)))
            }
            let x=usize::from(name=="overbrace"||name=="underbrace");
            let y=usize::from(name!="underbrace");
            result.child(body,x,y,"");
            result
        }
    }
}
fn tree(n:&Node)->String{
    match n{
        Node::Atom{
            kind,value,..
        }
        =>match kind.as_str(){
            "symbol"=>format!("'{}'",value),"text"=>format!("\"{}\"",value),"eqref"=>format!("(eqref \"{}\")",value),_=>value.clone()
        },Node::Row(nodes)=>format!("(row{})",nodes.iter().map(|n|format!(" {}",tree(n))).collect::<String>()),Node::Binary(name,a,b)=>format!("({} {} {})",name,tree(a),tree(b)),Node::Root(index,body)=>if let Some(index)=index{
            format!("(root {} {})",tree(index),tree(body))
        }else{
            format!("(sqrt {})",tree(body))
        },Node::Script(base,sub,sup)=>match(sub,sup){
            (Some(s),Some(u))=>format!("(subsup {} {} {})",tree(base),tree(s),tree(u)),(Some(s),None)=>format!("(sub {} {})",tree(base),tree(s)),(None,Some(u))=>format!("(sup {} {})",tree(base),tree(u)),_=>unreachable!()
        },Node::Delimited(left,right,body,_)=>{
            let delimiter=|s:&str|if s.len()==1{
                format!("'{}'",s)
            }else{
                s.into()
            };
            format!("(delim {} {} {})",delimiter(left),delimiter(right),tree(body))
        },Node::Matrix(name,rows)=>format!("({}{})",name,rows.iter().map(|r|format!(" [{}]",r.iter().map(tree).collect::<Vec<_>>().join(" "))).collect::<String>()),Node::Accent(name,body)=>format!("({} {})",name,tree(body))
    }
}
fn linear(n:&Node,script:bool,p:&Params,references:&BTreeMap<String,String>)->String{
    let child=|n:&Node|linear(n,script,p,references);
    let parenthesize=|n:&Node,style:bool,base:bool|{
        let text=linear(n,style,p,references);
        if matches!(n,Node::Row(_))||matches!(n,Node::Binary(name,..)if name=="frac")||base&&matches!(n,Node::Script(..)){
            format!("({})",text)
        }else{
            text
        }
    };
    match n{
        Node::Atom{
            kind,value,..
        }
        =>display(kind,value,references),Node::Row(nodes)=>{
            let(_,gaps)=layout::spacing(nodes,script,p);
            let mut text=String::new();
            for(i,n)in nodes.iter().enumerate(){
                if i>0{
                    text.push_str(&" ".repeat(gaps[i-1]));
                }
                text.push_str(&child(n));
            }
            text
        },Node::Binary(name,a,b)=>match name.as_str(){
            "frac"=>format!("{}/{}",parenthesize(a,script,false),parenthesize(b,script,false)),"binom"=>format!("binom({}, {})",child(a),child(b)),_=>format!("{}({}, {})",name,linear(a,true,p,references),child(b))
        },Node::Root(index,body)=>if let Some(index)=index{
            format!("root({}, {})",linear(index,true,p,references),child(body))
        }else{
            format!("sqrt({})",child(body))
        },Node::Script(base,sub,sup)=>{
            let mut text=parenthesize(base,script,true);
            if let Some(sub)=sub{
                text.push('_');
                text.push_str(&parenthesize(sub,true,false));
            }
            if let Some(sup)=sup{
                text.push('^');
                text.push_str(&parenthesize(sup,true,false));
            }
            text
        },Node::Delimited(left,right,body,_)=>{
            fn d(s:&str)->&str{match s{
                "."=>"","\\{"=>"{","\\}"=>"}",_=>s
            }}
            format!("{}{}{}",d(left),child(body),d(right))
        },Node::Matrix(name,rows)=>format!("{}[{}]",name,rows.iter().map(|r|r.iter().map(child).collect::<Vec<_>>().join(", ")).collect::<Vec<_>>().join("; ")),Node::Accent(name,body)=>format!("{}({})",name,child(body))
    }
}
fn warnings(n:&Node,references:&BTreeMap<String,String>,out:&mut Vec<(usize,String)>){
    match n{
        Node::Atom{
            kind,value,column
        }
        =>{
            if kind=="identifier"&&lexer::command_name(value){
                out.push((*column,format!("{} is a command name; write \\{}",value,value)));
            }
            if kind=="eqref"&&!references.contains_key(value){
                out.push((*column,format!("undefined reference \"{}\"",value)));
            }
        },Node::Row(nodes)=>{
            for n in nodes{
                warnings(n,references,out);
            }
        },Node::Binary(_,a,b)=>{
            warnings(a,references,out);
            warnings(b,references,out);
        },Node::Root(index,body)=>{
            if let Some(i)=index{
                warnings(i,references,out);
            }
            warnings(body,references,out);
        },Node::Script(base,sub,sup)=>{
            warnings(base,references,out);
            if let Some(n)=sub{
                warnings(n,references,out);
            }
            if let Some(n)=sup{
                warnings(n,references,out);
            }
        },Node::Delimited(left,right,body,column)=>{
            if left!="."&&right!="."&&![("(",")"),("[","]"),("|","|"),("\\{","\\}")].iter().any(|(a,b)|left==a&&right==b){
                out.push((*column,format!("\\left{} closed by \\right{}",left,right)));
            }
            warnings(body,references,out);
        },Node::Matrix(_,rows)=>{
            for n in rows.iter().flat_map(|r|r.iter()){
                warnings(n,references,out);
            }
        },Node::Accent(_,body)=>warnings(body,references,out)
    }
}
struct Line{
    start:usize,
    end:usize,
    indent:usize,
    width:usize
}
fn build_lines(nodes:&[Node],boxes:&[B],types:&[(usize,usize)],gaps:&[usize],p:&Params,stage:usize)->Vec<Line>{
    let n=nodes.len();
    let mut breaks=Vec::new();
    for i in 1..n{
        let relation=types[i].0==3;
        let binary=stage>=1&&types[i].0==2&&matches!(&nodes[i],Node::Atom{
            kind,value,..
        }
        if kind=="symbol"&&(value=="+"||value=="-"));
        let punctuation=stage>=2&&types[i-1].1==6;
        if relation||binary||punctuation{
            breaks.push(i);
        }
    }
    breaks.push(n);
    let mut lines=Vec::new();
    let mut start=0;
    let mut alignment=None;
    while start<n{
        let indent=if start==0{
            0
        }else if let Some((column,width))=alignment{
            if types[start].0==3{
                column
            }else{
                column+width+p.rel
            }
        }else{
            p.indent
        };
        let width=|end:usize|boxes[start..end].iter().map(|b|b.width).sum::<usize>()+gaps[start..end-1].iter().sum::<usize>();
        let candidates:Vec<_>=breaks.iter().copied().filter(|&end|end>start).collect();
        let end=candidates.iter().copied().filter(|&end|indent+width(end)<=p.width).last().unwrap_or(candidates[0]);
        let line_width=width(end);
        if start==0{
            if let Some(r)=(start..end).find(|&i|types[i].0==3){
                let column=boxes[..r].iter().map(|b|b.width).sum::<usize>()+gaps[..r].iter().sum::<usize>();
                alignment=Some((column,boxes[r].width));
            }
        }
        lines.push(Line{
            start,
            end,
            indent,
            width:line_width
        });
        start=end;
    }
    lines
}
struct Placed{
    node:B,
    x:usize,
    y:usize
}
struct Layout{
    placed:Vec<Placed>,
    width:usize,
    height:usize,
    lines:usize,
    overfull:Vec<(usize,usize)>
}
fn compose(elements:&[Node],tag:Option<&String>,p:&Params,references:&BTreeMap<String,String>)->Layout{
    let(types,gaps)=layout::spacing(elements,false,p);
    let boxes:Vec<_>=elements.iter().map(|n|typeset(n,false,p,references)).collect();
    let mut lines=Vec::new();
    for stage in 0..3{
        lines=build_lines(elements,&boxes,&types,&gaps,p,stage);
        if lines.iter().all(|l|l.indent+l.width<=p.width){
            break;
        }
    }
    let mut placed=Vec::new();
    let mut overfull=Vec::new();
    let(mut width,mut y)=(0,0);
    for(k,l)in lines.iter().enumerate(){
        if l.indent+l.width>p.width{
            overfull.push((k+1,l.indent+l.width));
        }
        let node=layout::row(boxes[l.start..l.end].to_vec(),&gaps[l.start..l.end-1],&format!("line {}",k+1),&[]);
        width=width.max(l.indent+node.width);
        let height=node.height;
        placed.push(Placed{
            node,
            x:l.indent,
            y
        });
        y+=height;
    }
    if let Some(tag)=tag{
        let tx=p.width-tag.len();
        let last=placed.last().unwrap();
        let ty=if tx>=last.x+last.node.width+2{
            last.y+last.node.baseline
        }else{
            let ty=y;
            y+=1;
            ty
        };
        let node=B::text(tag.clone(),format!("tag \"{}\"",tag));
        width=width.max(tx+node.width);
        placed.push(Placed{
            node,
            x:tx,
            y:ty
        });
    }
    Layout{
        placed,
        width,
        height:y,
        lines:lines.len(),
        overfull
    }
}
struct Record{
    text:String,
    formula:Result<Formula,lexer::Error>,
    tag:Option<String>,
    warnings:Vec<(usize,String)>
}
fn params()->Params{
    let mut values=BTreeMap::new();
    for line in fs::read_to_string("input/params.txt").unwrap().lines(){
        let(a,b)=line.split_once(' ').unwrap();
        values.insert(a.to_string(),b.parse::<usize>().unwrap());
    }
    Params{
        width:values["width"],
        indent:values["indent"],
        rel:values["rel_space"],
        binary:values["bin_space"],
        punctuation:values["punct_space"],
        col_gap:values["col_gap"],
        row_gap:values["row_gap"]
    }
}
fn diagnostic(number:usize,text:&str,column:usize,message:&str,out:&mut Vec<String>){
    out.push(format!("formula {}, column {}: {}",number,column,message));
    out.push(format!("  {}",text));
    out.push(format!("{}^"," ".repeat(column+1)));
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
    let p=params();
    let mut records:Vec<_>=fs::read_to_string("input/formulas.txt").unwrap().lines().map(|text|Record{
        text:text.into(),
        formula:lexer::lex(text).and_then(|tokens|parser::parse(tokens,text.len()+1)),
        tag:None,
        warnings:Vec::new()
    }).collect();
    let mut counter=0;
    let mut references=BTreeMap::new();
    for r in &mut records{
        if let Ok(f)=&r.formula{
            r.tag=if let Some((value,_))=&f.tag{
                Some(format!("({})",value))
            }else if f.label.is_some(){
                counter+=1;
                Some(format!("({})",counter))
            }else{
                None
            };
        }
    }
    for r in &mut records{
        if let Ok(f)=&r.formula{
            if let Some((name,column))=&f.label{
                if references.contains_key(name){
                    r.warnings.push((*column,format!("duplicate label \"{}\"",name)));
                }else{
                    references.insert(name.clone(),r.tag.clone().unwrap());
                }
            }
        }
    }
    let(mut rendered,mut boxes,mut trees,mut errors)=(Vec::new(),Vec::new(),Vec::new(),Vec::new());
    let mut kinds=BTreeMap::new();
    let(mut valid,mut total_boxes,mut max_depth,mut warning_count,mut overfull_count)=(0,0,0,0,0);
    for(i,r)in records.iter_mut().enumerate(){
        let number=i+1;
        if i>0{
            rendered.push(String::new());
        }
        rendered.push(format!("formula {}",number));
        match &r.formula{
            Err(error)=>{
                rendered.push("(error)".into());
                boxes.push(format!("formula {}: error",number));
                trees.push(format!("formula {}: error",number));
                diagnostic(number,&r.text,error.column,&error.message,&mut errors);
            },Ok(f)=>{
                valid+=1;
                for n in &f.elements{
                    warnings(n,&references,&mut r.warnings);
                }
                r.warnings.sort_by_key(|w|w.0);
                warning_count+=r.warnings.len();
                for(column,message)in &r.warnings{
                    diagnostic(number,&r.text,*column,&format!("warning: {}",message),&mut errors);
                }
                let composed=compose(&f.elements,r.tag.as_ref(),&p,&references);
                overfull_count+=composed.overfull.len();
                for(k,width)in &composed.overfull{
                    errors.push(format!("formula {}: line {} is overfull (width {} > {})",number,k,width,p.width));
                }
                let mut grid=vec![vec![' ';composed.width];composed.height];
                let mut box_lines=Vec::new();
                let mut depth=0;
                for placed in &composed.placed{
                    canvas::paint(&placed.node,placed.x,placed.y,&mut grid);
                    canvas::describe(&placed.node,placed.x,placed.y,0,"",&mut box_lines,&mut kinds,&mut depth);
                }
                total_boxes+=box_lines.len();
                max_depth=max_depth.max(depth);
                boxes.push(format!("formula {}: lines={} width={} height={} boxes={} depth={}",number,composed.lines,composed.width,composed.height,box_lines.len(),depth));
                boxes.extend(box_lines);
                rendered.extend(canvas::lines(&grid));
                trees.push(format!("formula {}: {}",number,f.elements.iter().map(tree).collect::<Vec<_>>().join(" ")));
                let text=linear(&Node::Row(f.elements.clone()),false,&p,&references);
                let text=text.trim_end();
                trees.push(if text.is_empty(){
                    "  linear:".into()
                }else{
                    format!("  linear: {}",text)
                });
                if let Some(tag)=&r.tag{
                    trees.push(format!("  tag: {}",tag));
                }
            }
        }
    }
    boxes.push(format!("summary: boxes={} max_depth={}",total_boxes,max_depth));
    for(kind,count)in kinds{
        boxes.push(format!("  {}: {}",kind,count));
    }
    errors.push(format!("formulas={} rendered={} errors={} warnings={} overfull={}",records.len(),valid,records.len()-valid,warning_count,overfull_count));
    write("rendered.txt",&rendered);
    write("boxes.txt",&boxes);
    write("trees.txt",&trees);
    write("errors.txt",&errors);
}
