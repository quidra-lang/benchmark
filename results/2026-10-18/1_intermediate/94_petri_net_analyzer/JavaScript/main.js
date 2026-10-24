'use strict';
const fs = require('fs');
const lines = fs.readFileSync(0, 'utf8').trimEnd().split(/\r?\n/);
let cursor = 0;
const out = s => console.log(s);
const yes = b => b ? 'yes' : 'no';
const listing = a => a.length ? a.join(' ') : 'none';
const marking = a => '(' + a.map(v => v < 0 ? 'w' : v).join(',') + ')';
const integer = (s, lo, hi) => /^(0|[1-9][0-9]{0,9})$/.test(s) && +s >= lo && +s <= hi ? +s : -1;
const gcd = (a, b) => b ? gcd(b, a % b) : Math.abs(a);
const fail = s => { throw new Error(s); };
function visit(adj, start) {
  const seen = Array(adj.length).fill(false), queue = [start]; seen[start] = true;
  for (let q = 0; q < queue.length; ++q) for (const v of adj[queue[q]]) if (!seen[v]) { seen[v] = true; queue.push(v); }
  return seen;
}
function flows(matrix) {
  const n = matrix.length, m = matrix[0].length;
  let rows = matrix.map((r, i) => r.concat(Array.from({length:n}, (_, j) => +(i === j))));
  for (let j = 0; j < m; ++j) {
    const next = rows.filter(r => r[j] === 0);
    for (const r of rows) if (r[j] > 0) for (const s of rows) if (s[j] < 0) {
      let v = r.map((x, k) => -s[j] * x + r[j] * s[k]);
      const d = v.reduce((g, x) => gcd(g, x), 0); v = v.map(x => x / d); next.push(v);
    }
    const unique = [...new Map(next.map(r => [r.join(','), r])).values()];
    const supports = unique.map(r => r.slice(m).reduce((mask, v, i) => mask | (v > 0 ? 1 << i : 0), 0));
    rows = unique.filter((_, i) => !supports.some(s => s !== supports[i] && (s & supports[i]) === s));
  }
  return rows.map(r => r.slice(m)).sort((a, b) => { for (let i = 0; i < n; ++i) if (a[i] !== b[i]) return b[i] - a[i]; return 0; });
}
class Net {
  constructor(name) {
    this.name = name; this.p = []; this.t = []; this.initial = []; this.cap = []; this.prio = [];
    this.pre = Array.from({length:16}, () => Array(16).fill(0));
    this.post = Array.from({length:16}, () => Array(16).fill(0));
    this.inh = Array.from({length:16}, () => Array(16).fill(0));
    this.arcs = 0; this.inhibitors = 0; this.current = []; this.history = [];
  }
  define(w) {
    const [cmd, a, b, c] = w, n = w.length - 1;
    if (!['place','transition','arc','inhibit'].includes(cmd)) fail('unknown definition ' + cmd);
    if (!(cmd === 'place' ? n === 2 || n === 3 : cmd === 'transition' ? n === 1 || n === 2 : n === 3)) fail('wrong number of arguments');
    if (cmd === 'place' || cmd === 'transition') {
      if (this.p.includes(a) || this.t.includes(a)) fail('duplicate name ' + a);
      if (cmd === 'place') {
        if (n === 3 && +b > +c) fail('tokens exceed capacity of ' + a);
        this.p.push(a); this.initial.push(+b); this.cap.push(n === 3 ? +c : 0);
      } else { this.t.push(a); this.prio.push(n === 2 ? +b : 0); }
    } else if (cmd === 'arc') {
      for (const x of [a,b]) if (!this.p.includes(x) && !this.t.includes(x)) fail('unknown node ' + x);
      const pa = this.p.indexOf(a), pb = this.p.indexOf(b);
      if ((pa >= 0) === (pb >= 0)) fail('arc must connect a place and a transition');
      const p = pa >= 0 ? pa : pb, t = this.t.indexOf(pa >= 0 ? b : a), mat = pa >= 0 ? this.pre : this.post;
      if (mat[p][t]) fail(`duplicate arc ${a} ${b}`);
      mat[p][t] = +c; ++this.arcs;
    } else {
      const p = this.p.indexOf(a), t = this.t.indexOf(b);
      if (p < 0) fail('unknown place ' + a); if (t < 0) fail('unknown transition ' + b);
      if (this.inh[p][t]) fail(`duplicate inhibitor ${a} ${b}`);
      this.inh[p][t] = +c; ++this.inhibitors;
    }
  }
  reason(m, t) {
    for (let p = 0; p < this.p.length; ++p) if (m[p] >= 0 && m[p] < this.pre[p][t]) return 'insufficient tokens in ' + this.p[p];
    for (let p = 0; p < this.p.length; ++p) if (this.inh[p][t] && (m[p] < 0 || m[p] >= this.inh[p][t])) return 'inhibited by ' + this.p[p];
    for (let p = 0; p < this.p.length; ++p) if (this.cap[p] && (m[p] < 0 || m[p] - this.pre[p][t] + this.post[p][t] > this.cap[p])) return 'capacity of ' + this.p[p] + ' exceeded';
    return '';
  }
  enabled(m) { return this.t.map((_, t) => t).filter(t => !this.reason(m, t)); }
  fire(m, t) { return m.map((v, p) => v < 0 ? -1 : v - this.pre[p][t] + this.post[p][t]); }
  commit(t) { this.history.push(this.current); this.current = this.fire(this.current, t); }
  names(indices) { return indices.map(t => this.t[t]); }
  graph(start, limit, target = null) {
    const states = [start.slice()], parents = [-1], via = [-1], edges = [[]], index = new Map([[start.join(','),0]]);
    const g = {states, parents, via, edges, found:-1, aborted:false};
    const matches = m => target && m.every((v,p) => v >= target[p][0] && (target[p][1] < 0 || v === target[p][1]));
    if (matches(start)) { g.found = 0; return g; }
    for (let q = 0; q < states.length; ++q) for (const t of this.enabled(states[q])) {
      const m = this.fire(states[q], t), key = m.join(','); let k = index.get(key);
      if (k === undefined) {
        if (states.length === limit) { g.aborted = true; return g; }
        k = states.length; index.set(key,k); states.push(m); parents.push(q); via.push(t); edges.push([]);
        if (matches(m)) { g.found = k; return g; }
      }
      edges[q].push([t,k]);
    }
    return g;
  }
  path(g, k) { const path = []; while (g.parents[k] >= 0) { path.push(g.via[k]); k = g.parents[k]; } return path.reverse(); }
  reach(limit, display) {
    const g = this.graph(this.current,limit), {states,edges} = g;
    if (g.aborted) { out(`reachability graph limit ${limit} exceeded`); return; }
    if (display) { states.forEach((m,i) => out(`M${i} ${marking(m)}: ` + (edges[i].map(([t,k]) => `${this.t[t]}->M${k}`).join(' ') || 'dead'))); return; }
    const adj = edges.map(e => e.map(x => x[1])), reach = states.map((_,i) => visit(adj,i)), comp = states.map(() => -1);
    let count = 0;
    for (let i = 0; i < states.length; ++i) if (comp[i] < 0) { for (let j = i; j < states.length; ++j) if (reach[i][j] && reach[j][i]) comp[j] = count; ++count; }
    const terminal = Array(count).fill(true);
    edges.forEach((e,i) => e.forEach(([,j]) => { if (comp[i] !== comp[j]) terminal[comp[i]] = false; }));
    const dead = states.map((_,i) => i).filter(i => !edges[i].length);
    const max = this.p.map((_,p) => Math.max(...states.map(m => m[p]))), bound = Math.max(...max);
    const home = states.map((_,j) => reach.every(r => r[j]));
    let persistent = true;
    for (let i = 0; i < states.length; ++i) for (const [t,k] of edges[i]) for (const [u] of edges[i]) if (t !== u && this.reason(states[k],u)) persistent = false;
    const levels = this.t.map((name,t) => {
      const present = Array(count).fill(false); let used = false, cycle = false;
      edges.forEach((e,i) => e.forEach(([u,k]) => { if (u === t) { used = true; present[comp[i]] = true; if (comp[i] === comp[k]) cycle = true; } }));
      return name + '=' + (terminal.every((v,c) => !v || present[c]) ? 'L4' : cycle ? 'L3' : used ? 'L1' : 'L0');
    });
    out(`reachable markings: ${states.length}`); out(`edges: ${edges.reduce((s,e) => s+e.length,0)}`);
    out(`components: ${count} (terminal ${terminal.filter(Boolean).length})`); out(`dead markings: ${dead.length}`);
    for (const i of dead) out(`  M${i} ${marking(states[i])} path ${listing(this.names(this.path(g,i))).replace(/^none$/,'empty')}`);
    out('max tokens: '+marking(max)); out('bound: '+bound); out('safe: '+yes(bound<=1)); out('home markings: '+home.filter(Boolean).length);
    out('reversible: '+yes(home[0])); out('persistent: '+yes(persistent)); out('liveness: '+levels.join(' '));
  }
  cover(limit) {
    const states = [this.current.slice()], parents = [-1], via = [-1], old = [false], dead = [false];
    const rank = v => v < 0 ? Infinity : v;
    for (let q = 0; q < states.length; ++q) {
      if (old[q]) continue;
      const enabled = this.enabled(states[q]); dead[q] = !enabled.length;
      const ancestors = []; for (let a = q; a >= 0; a = parents[a]) ancestors.push(a); ancestors.reverse();
      for (const t of enabled) {
        const m = this.fire(states[q],t);
        for (const a of ancestors) if (m.every((v,p) => rank(v) >= rank(states[a][p])) && m.some((v,p) => rank(v) > rank(states[a][p])))
          for (let p = 0; p < m.length; ++p) if (!this.cap[p] && rank(m[p]) > rank(states[a][p])) m[p] = -1;
        if (states.length === limit) { out(`coverability tree limit ${limit} exceeded`); return; }
        old.push(states.some(s => s.every((v,p) => v === m[p]))); states.push(m); parents.push(q); via.push(t); dead.push(false);
      }
    }
    out('coverability tree nodes: '+states.length);
    states.forEach((m,i) => out(`  ${i} ${marking(m)} `+(i ? `<- ${parents[i]} ${this.t[via[i]]}` : 'root')+(old[i]?' old':'')+(dead[i]?' dead':'')));
    const max = this.p.map((_,p) => states.some(m => m[p]<0) ? -1 : Math.max(...states.map(m=>m[p])));
    out('bounds: '+marking(max)); out('unbounded: '+listing(this.p.filter((_,p)=>max[p]<0)));
  }
  sets(trap, minimal = true) {
    const found = [];
    for (let mask = 1; mask < 1<<this.p.length; ++mask) {
      let valid = true;
      for (let t = 0; t < this.t.length; ++t) {
        let input = false, output = false;
        for (let p = 0; p < this.p.length; ++p) if (mask & 1<<p) { input ||= this.post[p][t]>0; output ||= this.pre[p][t]>0; }
        if (trap ? output && !input : input && !output) { valid = false; break; }
      }
      if (valid) found.push(mask);
    }
    const bits = mask => this.p.map((_,p)=>p).filter(p=>mask & 1<<p);
    return found.filter(mask => !minimal || !found.some(s => s!==mask && (s&mask)===s)).sort((a,b) => { const x=bits(a),y=bits(b); if(x.length!==y.length)return x.length-y.length; for(let i=0;i<x.length;++i)if(x[i]!==y[i])return x[i]-y[i]; return 0; });
  }
  setText(mask) { return '{'+this.p.filter((_,p)=>mask & 1<<p).join(',')+'}'; }
  realize(counts) {
    const used = this.t.map(()=>0), stack = [this.current.slice()], choices=[0], path=[], seen=new Set();
    const total = counts.reduce((a,b)=>a+b,0);
    while (stack.length) {
      const depth=path.length;
      if(depth===total)return path;
      let chosen=-1;
      for(let t=choices[depth];t<this.t.length;++t) {
        choices[depth]=t+1;
        if(used[t]>=counts[t] || this.reason(stack[depth],t))continue;
        ++used[t]; const key=used.join(','); --used[t]; if(seen.has(key))continue;
        chosen=t; seen.add(key); break;
      }
      if(chosen>=0){++used[chosen];path.push(chosen);stack.push(this.fire(stack[depth],chosen));choices.push(0);}
      else{stack.pop();choices.pop();if(path.length)--used[path.pop()];}
    }
    return null;
  }
  invariants(transpose) {
    const matrix=this.p.map((_,p)=>this.t.map((_,t)=>this.post[p][t]-this.pre[p][t]));
    const a=transpose?this.t.map((_,t)=>this.p.map((_,p)=>matrix[p][t])):matrix;
    const f=flows(a),names=transpose?this.t:this.p;
    out(`${transpose?'T':'P'}-semiflows: ${f.length}`);
    const bounds=names.map(()=>null), covered=names.map(()=>false);
    for(const coeff of f){
      const terms=coeff.map((v,i)=>v?(v===1?'':v+'*')+names[i]:'').filter(Boolean).join(' + ');
      coeff.forEach((v,i)=>{if(v)covered[i]=true;});
      if(transpose){const path=this.realize(coeff);out('  '+terms+': '+(path===null?'not realizable':'realizable '+this.names(path).join(' ')));}
      else{const value=coeff.reduce((s,v,p)=>s+v*this.current[p],0);out('  '+terms+' = '+value);coeff.forEach((v,p)=>{if(v){const b=Math.floor(value/v);bounds[p]=bounds[p]===null?b:Math.min(bounds[p],b);}});}
    }
    if(!transpose)out('bounds: ('+bounds.map(v=>v===null?'-':v).join(',')+')');
    out((transpose?'consistent: ':'conservative: ')+yes(covered.every(Boolean)));
  }
  classify() {
    const P=this.p.length,T=this.t.length;
    const inputs=this.t.map((_,t)=>this.p.map((_,p)=>p).filter(p=>this.pre[p][t]));
    const outputs=this.p.map((_,p)=>this.t.map((_,t)=>t).filter(t=>this.pre[p][t]));
    const ordinary=this.p.every((_,p)=>this.t.every((_,t)=>this.pre[p][t]<=1&&this.post[p][t]<=1));
    const pure=this.p.every((_,p)=>this.t.every((_,t)=>!this.pre[p][t]||!this.post[p][t]));
    const sm=ordinary&&inputs.every((a,t)=>a.length===1&&this.p.filter((_,p)=>this.post[p][t]).length===1);
    const mg=ordinary&&outputs.every((a,p)=>a.length===1&&this.t.filter((_,t)=>this.post[p][t]).length===1);
    const fc=ordinary&&outputs.every((a,p)=>a.every(t=>a.length===1||inputs[t].length===1));
    const efc=ordinary&&outputs.every((a,p)=>outputs.every((b,q)=>!a.some(t=>b.includes(t))||a.join(',')===b.join(',')));
    for(const [label,value] of [['ordinary',ordinary],['pure',pure],['state machine',sm],['marked graph',mg],['free choice',fc],['extended free choice',efc]])out(label+': '+yes(value));
    let verdict=!fc?'not applicable':P>12?'too many places':'holds';
    if(fc&&P<=12){const traps=this.sets(true);for(const s of this.sets(false))if(!traps.some(q=>(s&q)===q&&this.current.some((v,p)=>v>0&&(q&1<<p)))){verdict='fails at '+this.setText(s);break;}}
    out('commoner: '+verdict);
  }
  workflow(limit) {
    const sources=this.p.map((_,p)=>p).filter(p=>this.t.every((_,t)=>!this.post[p][t]));
    const sinks=this.p.map((_,p)=>p).filter(p=>this.t.every((_,t)=>!this.pre[p][t]));
    if(sources.length!==1){out(`workflow: no (${sources.length} source places)`);return;}if(sinks.length!==1){out(`workflow: no (${sinks.length} sink places)`);return;}
    const i=sources[0],o=sinks[0],P=this.p.length,adj=Array.from({length:P+this.t.length},()=>[]),rev=adj.map(()=>[]);
    for(let p=0;p<P;++p)for(let t=0;t<this.t.length;++t){if(this.pre[p][t]){adj[p].push(P+t);rev[P+t].push(p);}if(this.post[p][t]){adj[P+t].push(p);rev[p].push(P+t);}}
    const forward=visit(adj,i),back=visit(rev,o),names=this.p.concat(this.t);
    for(let v=0;v<names.length;++v)if(!forward[v]||!back[v]){out(`workflow: no (${names[v]} is not on a path from ${this.p[i]} to ${this.p[o]})`);return;}
    out(`workflow: source ${this.p[i]} sink ${this.p[o]}`);
    const start=this.p.map((_,p)=>+(p===i)),goal=this.p.map((_,p)=>+(p===o)),g=this.graph(start,limit);
    if(g.aborted){out(`reachability graph limit ${limit} exceeded`);return;}
    const end=g.states.findIndex(m=>m.every((v,p)=>v===goal[p])),r=g.edges.map(()=>[]);
    g.edges.forEach((e,u)=>e.forEach(([,v])=>r[v].push(u)));
    const option=end>=0&&visit(r,end).every(Boolean),proper=g.states.every(m=>m[o]<1||m.every((v,p)=>v===goal[p]));
    const live=this.t.every((_,t)=>g.edges.some(e=>e.some(([u])=>u===t)));
    out('option to complete: '+yes(option));out('proper completion: '+yes(proper));out('no dead transitions: '+yes(live));out('sound: '+yes(option&&proper&&live));
  }
  execute(w) {
    const cmd=w[0],args=w.slice(1),arity={MARKING:0,RESET:0,SET:2,ENABLED:0,FIRE:-1,UNDO:1,SIMULATE:3,CONFLICTS:0,REACH:1,GRAPH:1,COVER:1,PATH:2,INCIDENCE:0,PINV:0,TINV:0,SIPHONS:0,TRAPS:0,CLASSIFY:0,WORKFLOW:1,SHOW:0};
    if(!Object.hasOwn(arity,cmd))fail('unknown command '+cmd);
    if(arity[cmd]<0?!args.length:args.length!==arity[cmd])fail('wrong number of arguments');
    let limit=0;if(['REACH','GRAPH','COVER','PATH','WORKFLOW'].includes(cmd)){limit=integer(args[0],1,2000);if(limit<0)fail('invalid limit '+args[0]);}
    switch(cmd){
      case 'MARKING':out('marking '+marking(this.current));break;
      case 'RESET':this.current=this.initial.slice();this.history=[];out('marking '+marking(this.current));break;
      case 'SET':{const p=this.p.indexOf(args[0]);if(p<0)fail('unknown place '+args[0]);const v=integer(args[1],0,999);if(v<0)fail('invalid tokens '+args[1]);if(this.cap[p]&&v>this.cap[p])fail('tokens exceed capacity of '+args[0]);this.current=this.current.slice();this.current[p]=v;this.history=[];out('marking '+marking(this.current));break;}
      case 'ENABLED':out('enabled: '+listing(this.names(this.enabled(this.current))));break;
      case 'FIRE':{const ts=args.map(a=>{const t=this.t.indexOf(a);if(t<0)fail('unknown transition '+a);return t;});for(let i=0;i<ts.length;++i){const reason=this.reason(this.current,ts[i]);if(reason){out(`step ${i+1}: ${args[i]} not enabled (${reason}) at ${marking(this.current)}`);return;}this.commit(ts[i]);}out(`fired ${ts.length} -> ${marking(this.current)}`);break;}
      case 'UNDO':{const k=integer(args[0],1,1000);if(k<0)fail('invalid count '+args[0]);if(k>this.history.length)fail(`cannot undo ${k}: history size ${this.history.length}`);this.current=this.history[this.history.length-k];this.history.length-=k;out('marking '+marking(this.current));break;}
      case 'SIMULATE':{const steps=integer(args[0],1,1000);let x=integer(args[1],1,2147483646);if(steps<0)fail('invalid steps '+args[0]);if(x<0)fail('invalid seed '+args[1]);if(!['PRIORITY','RANDOM'].includes(args[2]))fail('invalid mode '+args[2]);const counts=this.t.map(()=>0);let done=0;for(;done<steps;++done){const e=this.enabled(this.current);if(!e.length){out(`dead (steps=${done})`);break;}let t=e[0];if(args[2]==='RANDOM'){x=x*48271%2147483647;t=e[x%e.length];}else for(const u of e)if(this.prio[u]>this.prio[t])t=u;this.commit(t);++counts[t];out(`step ${done+1}: ${this.t[t]} -> ${marking(this.current)}`);}if(done===steps)out(`completed (steps=${steps})`);out('counts: '+this.t.map((n,t)=>n+'='+counts[t]).join(' '));break;}
      case 'CONFLICTS':{const structural=[],effective=[];for(let u=0;u<this.t.length;++u)for(let v=u+1;v<this.t.length;++v){const pair=this.t[u]+'/'+this.t[v];if(this.p.some((_,p)=>this.pre[p][u]&&this.pre[p][v]))structural.push(pair);if(!this.reason(this.current,u)&&!this.reason(this.current,v)&&(this.reason(this.fire(this.current,u),v)||this.reason(this.fire(this.current,v),u)))effective.push(pair);}out('structural: '+listing(structural));out('effective: '+listing(effective));break;}
      case 'REACH':case 'GRAPH':this.reach(limit,cmd==='GRAPH');break;
      case 'COVER':this.cover(limit);break;
      case 'PATH':{const entries=args[1].split(',');if(entries.length!==this.p.length)fail(`target needs ${this.p.length} entries`);const target=entries.map(s=>{if(s==='*')return [0,-1];const plus=s.endsWith('+'),v=integer(plus?s.slice(0,-1):s,0,9999999999);if(v<0)fail('invalid target entry '+s);return [v,plus?-1:v];});const g=this.graph(this.current,limit,target);if(g.found>=0){const path=this.names(this.path(g,g.found));out(`reached ${marking(g.states[g.found])} length=${path.length}`+(path.length?': '+path.join(' '):''));}else if(g.aborted)out(`search limit ${limit} exceeded`);else out(`unreachable (markings explored: ${g.states.length})`);break;}
      case 'INCIDENCE':{const rows=[['',...this.t],...this.p.map((name,p)=>[name,...this.t.map((_,t)=>String(this.post[p][t]-this.pre[p][t]))])],width=rows[0].map((_,i)=>Math.max(...rows.map(r=>r[i].length)));for(const r of rows)out(r.map((s,i)=>i?s.padStart(width[i]):s.padEnd(width[i])).join('  ').trimEnd());break;}
      case 'PINV':case 'TINV':this.invariants(cmd==='TINV');break;
      case 'SIPHONS':case 'TRAPS':{if(this.p.length>12)fail('more than 12 places');const sets=this.sets(cmd==='TRAPS');out(`minimal ${cmd==='TRAPS'?'traps':'siphons'}: ${sets.length}`);for(const s of sets)out('  '+this.setText(s)+' tokens='+this.current.reduce((sum,v,p)=>sum+((s&1<<p)?v:0),0));break;}
      case 'CLASSIFY':this.classify();break;
      case 'WORKFLOW':this.workflow(limit);break;
      case 'SHOW':this.p.forEach((name,p)=>out(`place ${name} tokens=${this.initial[p]} capacity=${this.cap[p]||'none'}`));this.t.forEach((name,t)=>{const list=mat=>this.p.map((n,p)=>mat[p][t]?n+':'+mat[p][t]:'').filter(Boolean).join(',')||'-';out(`transition ${name} priority=${this.prio[t]} pre=${list(this.pre)} post=${list(this.post)} inhibit=${list(this.inh)}`);});break;
    }
  }
}
const blocks=+lines[cursor++];
for(let b=0;b<blocks;++b){const net=new Net(lines[cursor++].split(' ')[1]);while(lines[cursor]!=='END NET'){try{net.define(lines[cursor++].split(' '));}catch(e){out('error: '+e.message);}}++cursor;net.current=net.initial.slice();out(`net ${net.name}: places=${net.p.length} transitions=${net.t.length} arcs=${net.arcs} inhibitors=${net.inhibitors}`);const n=+lines[cursor++];for(let i=0;i<n;++i){try{net.execute(lines[cursor++].split(' '));}catch(e){out('error: '+e.message);}}}
