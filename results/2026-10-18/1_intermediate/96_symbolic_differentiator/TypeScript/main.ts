import * as fs from 'node:fs';
type Rational = [number, number];
interface Expr { k: number; q: Rational; s: string; a: Expr[] }
type Tree = {f: Expr} | {op: string; a: Tree[]};
const functions = new Set(['sin', 'cos', 'tan', 'exp', 'ln', 'sqrt']);
const fail = (message: string): never => { throw new Error(message); };
function gcd(a: number,b: number): number { while (b) [a,b]=[b,a%b]; return Math.abs(a); }
function rational(p: number,q=1): Rational { if (!q) fail('division by zero'); if(q<0) [p,q]=[-p,-q]; const g=gcd(p,q); return [p/g,q/g]; }
const plus=(a: Rational,b: Rational): Rational=>rational(a[0]*b[1]+b[0]*a[1],a[1]*b[1]);
const times=(a: Rational,b: Rational): Rational=>rational(a[0]*b[0],a[1]*b[1]);
const negate=(a: Rational): Rational=>[-a[0],a[1]];
const num=(p: number,q=1): Expr=>({k:5,q:rational(p,q),s:'',a:[]});
const node=(k: number,a: Expr[]=[],s=''): Expr=>({k,a,s,q:[0,1]});
const zero=num(0), one=num(1), minus=num(-1), half=num(1,2);
const eq=(a: Expr,b: Expr): boolean=>compare(a,b)===0;
function compare(a: Expr,b: Expr): number {
    if(a.k!==b.k) return a.k-b.k;
    if(a.k===5) return Math.sign(a.q[0]*b.q[1]-b.q[0]*a.q[1]);
    if(a.s!==b.s) return a.s<b.s?-1:1;
    for(let i=0;i<Math.min(a.a.length,b.a.length);i++) { const c=compare(a.a[i],b.a[i]); if(c) return c; }
    return a.a.length-b.a.length;
}
const integer=(f: Expr): boolean=>f.k===5&&f.q[1]===1;
const negative=(f: Expr): boolean=>f.k===3&&f.a[1].k===5&&f.a[1].q[0]<0;
const base=(f: Expr): Expr=>f.k===3?f.a[0]:f;
const exponent=(f: Expr): Expr=>f.k===3?f.a[1]:one;
function coefficient(f: Expr): [Rational, Expr[]] { if(f.k===5) return [f.q,[]]; if(f.k===2) return f.a[0].k===5?[f.a[0].q,f.a.slice(1)]:[[1,1],f.a]; return [[1,1],[f]]; }
function product(c: Rational,a: Expr[]): Expr { if(!a.length) return num(...c); if(c[0]!==c[1]) return node(2,[num(...c),...a]); return a.length===1?a[0]:node(2,a); }
function exponentCompare(a: Expr,b: Expr): number { if(a.k===5&&b.k!==5) return -1; if(a.k!==5&&b.k===5) return 1; return compare(a,b); }
function termCompare(a: Expr,b: Expr): number {
    const x=coefficient(a)[1], y=coefficient(b)[1];
    const bases=[...x,...y].map(base).sort(compare).filter((f,i,a)=>!i||!eq(f,a[i-1]));
    for(const f of bases) { const u=x.find(t=>eq(base(t),f)),v=y.find(t=>eq(base(t),f)); const c=exponentCompare(v?exponent(v):zero,u?exponent(u):zero); if(c) return c; } return 0;
}
function add(...operands: Expr[]): Expr {
    const terms: Expr[]=[];
    for(const f of operands) { if(f.k===1) terms.push(...f.a); else if(f.k===2&&f.a.length===2&&f.a[0].k===5&&f.a[1].k===1) for(const t of f.a[1].a) terms.push(mul(f.a[0],t)); else terms.push(f); }
    const groups: {c: Rational; m: Expr[]}[]=[];
    for(const f of terms) { const [c,m]=coefficient(f); const g=groups.find(g=>g.m.length===m.length&&g.m.every((t,i)=>eq(t,m[i]))); if(g) g.c=plus(g.c,c); else groups.push({c,m}); }
    const built=groups.filter(g=>g.c[0]).map(g=>product(g.c,g.m)).sort(termCompare);
    return !built.length?zero:built.length===1?built[0]:node(1,built);
}
function mul(...operands: Expr[]): Expr {
    const factors=operands.flatMap(f=>f.k===2?f.a:[f]); let c: Rational=[1,1]; const groups: {b: Expr; a: Expr[]}[]=[];
    for(const f of factors) { if(f.k===5) c=times(c,f.q); else { const g=groups.find(g=>eq(g.b,base(f))); if(g) g.a.push(f); else groups.push({b:base(f),a:[f]}); } }
    if(!c[0]) return zero;
    const r=groups.map(g=>g.a.length===1?g.a[0]:power(g.b,add(...g.a.map(exponent))));
    if(r.some(f=>f.k===5||f.k===2)||r.some((f,i)=>r.slice(0,i).some(g=>eq(base(f),base(g))))) return mul(num(...c),...r);
    return product(c,r.sort((a,b)=>compare(base(a),base(b))));
}
function root(v: number,d: number): number | null { if(v===1) return 1; if(d>20) return null; const r=Math.round(v**(1/d)); for(let i=Math.max(0,r-1);i<=r+1;i++) if(i**d===v) return i; return null; }
function rationalPower(b: Rational,n: number): Expr { if(n<0) return rationalPower([b[1],b[0]],-n); let r: Rational=[1,1]; while(n) { if(n%2) r=times(r,b); n=Math.floor(n/2); if(n) b=times(b,b); } return num(...r); }
function power(b: Expr,x: Expr): Expr {
    if(eq(x,zero)) return one; if(eq(x,one)) return b;
    if(b.k===5) { if(eq(b,one)) return one; if(x.k!==5) return node(3,[b,x]); if(!b.q[0]) { if(x.q[0]>0) return zero; fail('division by zero'); } if(integer(x)) return rationalPower(b.q,x.q[0]); if(b.q[0]>0) { const s=root(b.q[0],x.q[1]),t=root(b.q[1],x.q[1]); if(s!==null&&t!==null) return rationalPower([s,t],x.q[0]); } }
    else if(integer(x)) { if(b.k===3) return power(b.a[0],mul(b.a[1],x)); if(b.k===2) return mul(...b.a.map(f=>power(f,x))); }
    return node(3,[b,x]);
}
function fn(s: string,a: Expr): Expr {
    if(s==='sqrt') return power(a,half);
    if(eq(a,zero)&&['sin','tan','cos','exp'].includes(s)) return ['sin','tan'].includes(s)?zero:one;
    if(s==='ln'&&eq(a,one)) return zero;
    if(['sin','cos','tan'].includes(s)&&coefficient(a)[0][0]<0) { const t=fn(s,mul(minus,a)); return s==='cos'?t:mul(minus,t); }
    if(a.k===4&&((s==='ln'&&a.s==='exp')||(s==='exp'&&a.s==='ln'))) return a.a[0];
    return node(4,[a],s);
}
function variables(f: Expr): string[] { const r=new Set(f.k===0?[f.s]:[]); for(const a of f.a) for(const s of variables(a)) r.add(s); return [...r].sort(); }
function derivative(f: Expr,v: string): Expr {
    if(f.k===5) return zero; if(f.k===0) return f.s===v?one:zero;
    if(f.k===1) return add(...f.a.map(t=>derivative(t,v)));
    if(f.k===2) return add(...f.a.map((t,i)=>mul(...f.a.map((g,j)=>i===j?derivative(g,v):g))));
    if(f.k===3) { const [b,x]=f.a; if(!variables(x).includes(v)) return mul(x,power(b,add(x,minus)),derivative(b,v)); if(!variables(b).includes(v)) return mul(f,fn('ln',b),derivative(x,v)); return mul(f,add(mul(derivative(x,v),fn('ln',b)),mul(x,derivative(b,v),power(b,minus)))); }
    const a=f.a[0]; const h=f.s==='sin'?fn('cos',a):f.s==='cos'?mul(minus,fn('sin',a)):f.s==='tan'?power(fn('cos',a),num(-2)):f.s==='exp'?f:power(a,minus); return mul(h,derivative(a,v));
}
function substitute(f: Expr,m: Map<string, Expr>): Expr { if(f.k===0) return m.get(f.s)||f; if(f.k===5) return f; const a=f.a.map(t=>substitute(t,m)); return f.k===1?add(...a):f.k===2?mul(...a):f.k===3?power(a[0],a[1]):fn(f.s,a[0]); }
const terms=(f: Expr): Expr[]=>f.k===1?f.a:[f];
function distribute(a: Expr,b: Expr): Expr { return add(...terms(a).flatMap(x=>terms(b).map(y=>mul(x,y)))); }
function expand(f: Expr): Expr { if(f.k===0||f.k===5) return f; const a=f.a.map(expand); if(f.k===1) return add(...a); if(f.k===2) return a.reduce(distribute); if(f.k===4) return fn(f.s,a[0]); if(a[0].k===1&&integer(a[1])&&a[1].q[0]>0) { let r=a[0]; for(let i=1;i<a[1].q[0];i++) r=distribute(r,a[0]); return r; } return power(a[0],a[1]); }
function value(f: Expr): number { if(f.k===5) return f.q[0]/f.q[1]; if(f.k===1) return f.a.reduce((s,t)=>s+value(t),0); if(f.k===2) return f.a.reduce((s,t)=>s*value(t),1); if(f.k===3) { const u=value(f.a[0]),z=value(f.a[1]); if(u<0&&!(f.a[1].k===5?integer(f.a[1]):Number.isInteger(z))) fail('domain error'); return eq(f.a[1],half)?Math.sqrt(u):u**z; } const a=value(f.a[0]); if(f.s==='ln') { if(a<=0) fail('domain error'); return Math.log(a); } return ({sin: Math.sin, cos: Math.cos, tan: Math.tan, exp: Math.exp} as Record<string,(x: number)=>number>)[f.s](a); }
const atomic=(f: Expr): boolean=>f.k===0||f.k===4||(integer(f)&&f.q[0]>=0)||(f.k===3&&eq(f.a[1],half));
const atom=(f: Expr): string=>atomic(f)?show(f):'('+show(f)+')';
const showPower=(b: Expr,x: Expr): string=>eq(x,half)?'sqrt('+show(b)+')':atom(b)+'^'+atom(x);
const factor=(f: Expr): string=>f.k===1?'('+show(f)+')':f.k===3?showPower(f.a[0],f.a[1]):show(f);
function quotient(c: Rational,a: Expr[]): string { const p=Math.abs(c[0]),q=c[1],top=p!==1?[String(p)]:[],bottom=q!==1?[String(q)]:[]; for(const f of a) { if(negative(f)) { const r=num(...negate(f.a[1].q)); bottom.push(eq(r,one)?factor(f.a[0]):showPower(f.a[0],r)); } else top.push(factor(f)); } return (c[0]<0?'-':'')+(top.join('*')||'1')+(!bottom.length?'':bottom.length===1?'/'+bottom[0]:'/('+bottom.join('*')+')'); }
function show(f: Expr): string { if(f.k===5) return f.q[0]+(f.q[1]===1?'':'/'+f.q[1]); if(f.k===0) return f.s; if(f.k===4) return f.s+'('+show(f.a[0])+')'; if(f.k===3) return negative(f)?quotient([1,1],[f]):showPower(f.a[0],f.a[1]); if(f.k===2) return quotient(...coefficient(f)); return f.a.map(show).reduce((a,b)=>a+(b.startsWith('-')?' - '+b.slice(1):' + '+b)); }
function parse(text: string,names: Map<string, Expr>): Expr {
    const tokens: string[]=[]; const re=/[0-9]+|[a-z][a-z0-9]*|[A-Z][A-Z0-9]*|[-+*/^()]| +|./g;
    for(const t of text.match(re)||[]) { if(t[0]===' ') continue; if(!/^[a-zA-Z0-9+*/^()-]+$/.test(t)) fail("invalid character '"+t+"'"); tokens.push(t); }
    let p=0; const peek=()=>tokens[p]||''; const unexpected=()=>fail(p===tokens.length?'unexpected end of expression':"unexpected '"+peek()+"'");
    function accept(s: string): boolean { if(peek()===s) { p++; return true; } return false; }
    function expect(s: string): void { if(!accept(s)) unexpected(); }
    function atomTree(): Tree { const t=peek(); if(!t) unexpected(); if(accept('(')) { const a=expression(); expect(')'); return a; } if(!/^[a-zA-Z0-9]/.test(t)) unexpected(); p++; if(/^[0-9]/.test(t)) return {f:num(Number(t))}; if(/^[A-Z]/.test(t)) { if(!names.has(t)) fail("undefined name '"+t+"'"); return {f:names.get(t)!}; } if(!functions.has(t)) return {f:node(0,[],t)}; expect('('); const a=expression(); expect(')'); return {op:t,a:[a]}; }
    function unary(): Tree { if(accept('-')) return {op:'neg',a:[unary()]}; const a=atomTree(); return accept('^')?{op:'^',a:[a,unary()]}:a; }
    function term(): Tree { let a=unary(); while(peek()==='*'||peek()==='/') { const op=tokens[p++]; a={op,a:[a,unary()]}; } return a; }
    function expression(): Tree { let a=term(); while(peek()==='+'||peek()==='-') { const op=tokens[p++]; a={op,a:[a,term()]}; } return a; }
    function evaluate(t: Tree): Expr { if("f" in t) return t.f; const a=t.a.map(evaluate); switch(t.op) { case '+':return add(...a); case '-':return add(a[0],mul(minus,a[1])); case '*':return mul(...a); case '/':return mul(a[0],power(a[1],minus)); case '^':return power(a[0],a[1]); case 'neg':return mul(minus,a[0]); default:return fn(t.op,a[0]); } }
    const tree=expression(); if(p<tokens.length) unexpected(); return evaluate(tree);
}
const validVariable=(s: string): boolean=>/^[a-z][a-z0-9]*$/.test(s)&&!functions.has(s);
function literal(s: string): Expr { if(!/^-?[0-9]+(?:\/[0-9]+)?$/.test(s)) fail("invalid number '"+s+"'"); const a=s.split('/').map(Number); return num(a[0],a.length===1?1:a[1]); }
const signatures: Record<string, string>={SIMPLIFY:'e',EXPAND:'e',DIFF:'ev',DIFFN:'evn',GRAD:'e',HESSIAN:'e',IMPLICIT:'evv',SUBST:'eve',EVAL:'ea',TANGENT:'evc',LIMIT:'evc',TAYLOR:'evcn'};
function command(line: string,names: Map<string, Expr>): string[] {
    const split=line.indexOf(' '),c=split<0?line:line.slice(0,split),arg=split<0?'':line.slice(split+1);
    if(c==='LET') { const i=arg.indexOf('='); if(i<0) fail('wrong number of arguments'); const s=arg.slice(0,i).trim(); if(!/^[A-Z][A-Z0-9]*$/.test(s)) fail("invalid name '"+s+"'"); const f=parse(arg.slice(i+1).trim(),names); names.set(s,f); return [s+' = '+show(f)]; }
    if(!Object.hasOwn(signatures,c)) fail('unknown command '+c);
    const fields=split<0?[]:arg.split(';').map(s=>s.trim()),sig=signatures[c];
    if(c==='EVAL'?![1,2].includes(fields.length):fields.length!==sig.length) fail('wrong number of arguments');
    const a=fields.map((s,i)=>{ switch(sig[i]) { case 'e':return parse(s,names); case 'v':if(!validVariable(s)) fail("invalid variable '"+s+"'"); return s; case 'n':if(!/^[1-8]$/.test(s)) fail("invalid order '"+s+"'"); return Number(s); case 'c':return literal(s); default:return s; } });
    let f=a[0] as Expr; const v=a[1] as string, x=a[2] as Expr, n=a[3] as number; const order=Number(fields[2]), other=fields[2]; const out: string[]=[];
    if(c==='SIMPLIFY') return ['simplified: '+show(f)]; if(c==='EXPAND') return ['expanded: '+show(expand(f))];
    if(c==='DIFF') return ['d/d'+v+' = '+show(derivative(f,v))];
    if(c==='DIFFN') { for(let k=1;k<=order;k++) { f=derivative(f,v); out.push('d^'+k+'/d'+v+'^'+k+' = '+show(f)); } return out; }
    if(c==='GRAD'||c==='HESSIAN') { const vs=variables(f); if(!vs.length) return ['no variables']; for(let i=0;i<vs.length;i++) { const d=derivative(f,vs[i]); if(c==='GRAD') out.push('d/d'+vs[i]+' = '+show(d)); else for(let j=i;j<vs.length;j++) out.push('d2/d'+vs[i]+'d'+vs[j]+' = '+show(derivative(d,vs[j]))); } return out; }
    if(c==='IMPLICIT') { if(v===other) fail('same variable'); return ['d'+other+'/d'+v+' = '+show(mul(minus,derivative(f,v),power(derivative(f,other),minus)))]; }
    if(c==='SUBST') return ['substituted: '+show(substitute(f,new Map([[v,x]])))];
    if(c==='EVAL') { const m=new Map<string, Expr>(); for(const word of (v||'').split(' ').filter(Boolean)) { const i=word.indexOf('='),s=word.slice(0,i),t=word.slice(i+1); if(i<0||!validVariable(s)||! /^-?[0-9]+(?:\/[0-9]+)?$/.test(t)) fail("invalid assignment '"+word+"'"); const q=literal(t); if(m.has(s)) fail('duplicate variable '+s); m.set(s,q); } for(const s of variables(f)) if(!m.has(s)) fail('no value for '+s); const r=substitute(f,m); return [r.k===5?'exact: '+show(r):'approx: '+value(r).toFixed(6)]; }
    const m=new Map([[v,x]]);
    if(c==='TANGENT') { const slope=substitute(derivative(f,v),m),y=substitute(f,m),variable=node(0,[],v); const t='tangent: y = '+show(add(mul(slope,variable),y,mul(num(...negate(x.q)),slope))); if(eq(slope,zero)) return [t,'normal: '+v+' = '+show(x)]; const k=power(slope,minus); return [t,'normal: y = '+show(add(mul(minus,k,variable),y,mul(x,k)))]; }
    if(c==='LIMIT') { const top=[],bottom=[]; for(const t of f.k===2?f.a:[f]) (negative(t)?bottom:top).push(negative(t)?power(t.a[0],num(...negate(t.a[1].q))):t); let g=mul(...top),h=mul(...bottom); for(let i=0;i<=5;i++) { const u=substitute(g,m),b=substitute(h,m); if(!eq(b,zero)) return ['limit: '+show(mul(u,power(b,minus)))]; if(!eq(u,zero)) return ['limit: unbounded']; if(i<5) { g=derivative(g,v); h=derivative(h,v); } } return ['limit: unknown']; }
    const derivatives=[f]; for(let i=0;i<n;i++) derivatives.push(derivative(derivatives.at(-1)!,v)); let factorial=1; const polynomials=[]; for(let i=0;i<=n;i++) { if(i) factorial*=i; const coefficient=mul(substitute(derivatives[i],m),num(1,factorial)); polynomials.push(mul(coefficient,power(add(node(0,[],v),num(...negate(x.q))),num(i)))); } return ['taylor: '+show(expand(add(...polynomials)))];
}
const lines=fs.readFileSync(0,'utf8').split(/\r?\n/), names=new Map<string, Expr>(), output: string[]=[];
for(const line of lines.slice(1,1+Number(lines[0]))) { try { output.push(...command(line,names)); } catch(e) { output.push('error: '+(e as Error).message); } }
console.log(output.join('\n'));
