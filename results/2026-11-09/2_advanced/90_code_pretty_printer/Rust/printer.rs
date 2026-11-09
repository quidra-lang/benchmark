use std::collections::BTreeMap;
use crate::doc_builder::{Document,Doc,forced};
type Command=(usize,bool,Document);
fn fits(mut remaining:i64,first:Command,stack:&[Command])->bool{
    if remaining<0{
        return false;
    }
    let mut check=stack.to_vec();
    check.push(first);
    while let Some((i,flat,d))=check.pop(){
        match d.as_ref(){
            Doc::Text(s)=>remaining-=s.len()as i64,Doc::IfBreak(a,b)=>remaining-=if flat{
                b.len()
            }else{
                a.len()
            }
            as i64,Doc::Line=>if flat{
                remaining-=1;
            }else{
                return true;
            },Doc::Softline=>if !flat{
                return true;
            },Doc::Hardline=>return true,Doc::Concat(parts)=>{
                for p in parts.iter().rev(){
                    check.push((i,flat,p.clone()));
                }
            },Doc::Group(_,child)=>check.push((i,if forced(&d){
                false
            }else{
                flat
            },child.clone())),Doc::Nest(_,child)|Doc::Align(child)=>check.push((i,flat,child.clone())),_=>()
        }
        if remaining<0{
            return false;
        }
    }
    true
}
pub struct Printed{
    pub lines:Vec<String>,
    pub modes:BTreeMap<usize,&'static str>
}
fn finalize(current:&str,pending:&mut Vec<String>,lines:&mut Vec<String>,width:usize,column:usize){
    let mut line=current.trim_end().to_string();
    if !pending.is_empty(){
        let comment=pending.join(" ");
        if column>0&&line.len()<column-1&&column-1+comment.len()<=width{
            line.push_str(&" ".repeat(column-1-line.len()));
        }else{
            line.push(' ');
        }
        line.push_str(&comment);
        pending.clear();
    }
    lines.push(line);
}
pub fn print(document:Document,width:usize,column:usize)->Printed{
    let mut stack=vec![(0,false,document)];
    let mut lines=Vec::new();
    let mut modes=BTreeMap::new();
    let mut current=String::new();
    let mut col=0;
    let mut pending=Vec::new();
    while let Some((i,flat,d))=stack.pop(){
        match d.as_ref(){
            Doc::Text(s)=>{
                current.push_str(s);
                col+=s.len();
            },Doc::IfBreak(a,b)=>{
                let s=if flat{
                    b
                }else{
                    a
                };
                current.push_str(s);
                col+=s.len();
            },Doc::Line|Doc::Softline|Doc::Hardline=>{
                let newline=matches!(d.as_ref(),Doc::Hardline)||!flat;
                if newline{
                    finalize(&current,&mut pending,&mut lines,width,column);
                    current=" ".repeat(i);
                    col=i;
                }else if matches!(d.as_ref(),Doc::Line){
                    current.push(' ');
                    col+=1;
                }
            },Doc::Concat(parts)=>{
                for p in parts.iter().rev(){
                    stack.push((i,flat,p.clone()));
                }
            },Doc::Nest(n,child)=>stack.push((i+n,flat,child.clone())),Doc::Align(child)=>stack.push((col,flat,child.clone())),Doc::Suffix(s)=>pending.push(s.clone()),Doc::BreakParent=>(),Doc::Group(id,child)=>{
                let mode=if flat{
                    "flat"
                }else if forced(&d){
                    "forced"
                }else if fits(width as i64-col as i64,(i,true,child.clone()),&stack){
                    "flat"
                }else{
                    "break"
                };
                modes.insert(*id,mode);
                stack.push((i,mode=="flat",child.clone()));
            }
        }
    }
    finalize(&current,&mut pending,&mut lines,width,column);
    Printed{
        lines,
        modes
    }
}
