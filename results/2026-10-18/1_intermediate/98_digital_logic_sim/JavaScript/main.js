const fs = require('fs');
const TYPES = ['AND','OR','NAND','NOR','XOR','XNOR','NOT','BUF','MUX2','DFF'];
const COUNTS = {BUILD:1,RESET:0,SET:3,APPLY:2,PULSE:3,CLOCK:4,RUN:1,WATCH:1,UNWATCH:1,SHOW:0,CHECK:2,PROBE:1,WAVE:2,HISTORY:1,ACTIVITY:1,STATUS:0,MODULES:0,NETLIST:1,HIERARCHY:1,STATS:1,TRUTHTABLE:1,EQUIV:2,FAULTS:1,CRITICAL:1,PERIOD:1};
const SIM = 'RESET SET APPLY PULSE CLOCK RUN WATCH UNWATCH SHOW CHECK PROBE WAVE HISTORY ACTIVITY STATUS'.split(' ');
const fail = text => { throw new Error(text); };
const emit = text => console.log(text);
const nameOK = s => /^[a-z][a-z0-9_]{0,15}$/.test(s);
const numberOK = s => /^(0|[1-9][0-9]{0,8})$/.test(s);
function number(s, positive = false) {
    if (!numberOK(s) || (positive && +s === 0)) fail(`bad number ${s}`);
    return +s;
}
function value(s) { if (!['0','1','X'].includes(s)) fail(`bad value ${s}`); return s; }
function bits(r, n) { return Array.from({length:n}, (_, i) => String((r >> (n-1-i)) & 1)).join(''); }
function logic(kind, a) {
    let y;
    if (['AND','NAND'].includes(kind)) y = a.includes('0') ? '0' : a.includes('X') ? 'X' : '1';
    else if (['OR','NOR'].includes(kind)) y = a.includes('1') ? '1' : a.includes('X') ? 'X' : '0';
    else if (['XOR','XNOR'].includes(kind)) y = a.includes('X') ? 'X' : String(a.filter(x=>x==='1').length%2);
    else if (kind === 'MUX2') y = a[0]==='X' ? (a[1]===a[2] ? a[1] : 'X') : a[a[0]==='0' ? 1 : 2];
    else y = a[0];
    return ['NAND','NOR','XNOR','NOT'].includes(kind) ? ({'0':'1','1':'0','X':'X'})[y] : y;
}
class Circuit {
    constructor(module) {
        this.name=module.name; this.inputs=module.inputs; this.outputs=module.outputs; this.gates=[];
        const expand=(m,p,map)=> {
            const actual=s=>map.get(s) ?? p+s;
            for (const item of m.body) {
                if (item.kind) this.gates.push({...item,name:p+item.name,inputs:item.inputs.map(actual),output:actual(item.output)});
                else expand(item.module,p+item.name+'.',new Map(item.connections.map(([x,y])=>[x,actual(y)])));
            }
        };
        expand(module,'',new Map());
        this.signals=[...this.inputs,...this.gates.map(g=>g.output)];
        this.driver=new Map(this.gates.map(g=>[g.output,g]));
        this.readers=new Map(this.signals.map(s=>[s,[]]));
        for (const g of this.gates) for (const s of new Set(g.inputs)) this.readers.get(s).push(g);
        this.flops=this.gates.filter(g=>g.kind==='DFF');
        const waiting=new Map(), ready=[];
        for (const g of this.gates.filter(g=>g.kind!=='DFF')) {
            const n=new Set(g.inputs.filter(s=>this.driver.has(s)&&this.driver.get(s).kind!=='DFF')).size;
            waiting.set(g,n); if (!n) ready.push(g);
        }
        this.order=[];
        while (ready.length) {
            const g=ready.pop(); this.order.push(g);
            for (const r of this.readers.get(g.output)) if (r.kind!=='DFF') {
                waiting.set(r,waiting.get(r)-1); if (!waiting.get(r)) ready.push(r);
            }
        }
        this.loop=this.order.length!==waiting.size;
    }
    combinational() {
        if (this.flops.length) fail(`${this.name} is not combinational`);
        if (this.loop) fail(`${this.name} has a combinational loop`);
        if (this.inputs.length>8) fail(`too many inputs ${this.inputs.length}`);
        return this;
    }
    evaluate(b, stuck='', v='X') {
        const vals=new Map(this.inputs.map((s,i)=>[s,s===stuck?v:b[i]]));
        for (const g of this.order) vals.set(g.output,g.output===stuck?v:logic(g.kind,g.inputs.map(s=>vals.get(s))));
        return this.outputs.map(s=>vals.get(s)).join('');
    }
    arrivals(period) {
        const late=new Map(), early=new Map(), prev=new Map();
        if (period) for (const g of this.flops) {late.set(g.output,g.delay);early.set(g.output,g.delay);}
        else for (const s of this.inputs) {late.set(s,0);early.set(s,0);}
        for (const g of this.order) {
            const a=g.inputs.filter(s=>late.has(s)); if (!a.length) continue;
            let best=a[0]; for (const s of a) if (late.get(s)>late.get(best)) best=s;
            late.set(g.output,late.get(best)+g.delay);early.set(g.output,Math.min(...a.map(s=>early.get(s)))+g.delay);prev.set(g.output,best);
        }
        return {late,early,prev};
    }
}
class Simulation {
    constructor(c) {this.c=c;this.watch=[];this.reset();}
    reset() {this.vals=new Map(this.c.signals.map(s=>[s,'X']));this.time=0;this.queue=[];this.sequence=0;this.history=new Map(this.c.signals.map(s=>[s,[]]));this.processed=0;this.halted=false;}
    schedule(t,s,v) {
        const event={t,s,v,id:this.sequence++};let i=this.queue.length;this.queue.push(event);
        while (i>0) {const p=(i-1)>>1;if (!this.before(event,this.queue[p])) break;this.queue[i]=this.queue[p];i=p;}this.queue[i]=event;
    }
    before(a,b) {return a.t<b.t || a.t===b.t&&a.id<b.id;}
    pop() {
        const result=this.queue[0],last=this.queue.pop();
        if (this.queue.length) {let i=0;while (2*i+1<this.queue.length) {let j=2*i+1;if (j+1<this.queue.length&&this.before(this.queue[j+1],this.queue[j])) j++;if (!this.before(this.queue[j],last)) break;this.queue[i]=this.queue[j];i=j;}this.queue[i]=last;}
        return result;
    }
    run(end) {
        let total=0,glitches=0;
        while (this.queue.length&&this.queue[0].t<end) {
            const t=this.queue[0].t,start=new Map(this.vals),changed=new Set();let count=0;
            while (this.queue.length&&this.queue[0].t===t) {
                if (count===1000) {emit(`halted: oscillation at time ${t}`);this.queue=[];this.time=t;this.halted=true;return;}
                const e=this.pop();count++;this.processed++;
                const old=this.vals.get(e.s);if (old===e.v) continue;
                this.vals.set(e.s,e.v);changed.add(e.s);
                for (const g of this.c.readers.get(e.s)) {
                    if (g.kind!=='DFF') this.schedule(t+g.delay,g.output,logic(g.kind,g.inputs.map(s=>this.vals.get(s))));
                    else if (e.s===g.inputs[0]&&old==='0'&&e.v==='1') this.schedule(t+g.delay,g.output,this.vals.get(g.inputs[1]));
                }
            }
            total+=count;
            for (const s of changed) if (this.vals.get(s)===start.get(s)) glitches++;else this.history.get(s).push([t,this.vals.get(s)]);
            for (const s of this.watch) if (this.vals.get(s)!==start.get(s)) emit(`${t} ${s} ${this.vals.get(s)}`);
        }
        this.time=end;emit(`run ${end} events ${total} glitches ${glitches} pending ${this.queue.length}`);
    }
    describe(a) {return a.map(s=>`${s}=${this.vals.get(s)}`);}
}
class Simulator {
    constructor() {this.modules=new Map();this.sim=null;}
    lookup(s) {if (!this.modules.has(s)) fail(`unknown module ${s}`);const m=this.modules.get(s);return m;}
    circuit(s) {return new Circuit(this.lookup(s));}
    define(headerNo,lines) {
        let lineNo=headerNo;
        try {
            const w=lines[0].split(' ');
            if (w.length<5||w[2]!=='IN'||w.slice(3).filter(s=>s==='OUT').length!==1||w.at(-1)==='OUT') fail('bad module header');
            const name=w[1];if (!/^[A-Z][A-Z0-9_]{0,15}$/.test(name)) fail(`bad module name ${name}`);
            if (this.modules.has(name)) fail(`duplicate module ${name}`);
            const split=w.indexOf('OUT',3),inputs=w.slice(3,split),outputs=w.slice(split+1),seen=new Set();
            for (const s of [...inputs,...outputs]) {if (!nameOK(s)) fail(`bad name ${s}`);if (seen.has(s)) fail(`duplicate port ${s}`);seen.add(s);}
            const driven=new Set(inputs),used=new Set(),body=[],reads=[];
            for (let i=1;i<lines.length;i++) {
                lineNo=headerNo+i;const a=lines[i].split(' '),kind=a[0],name=a[1];
                if (TYPES.includes(kind)) {
                    if (a.length<5||a.at(-3)!=='->'||a.filter(s=>s==='->').length!==1) fail('bad gate syntax');
                    if (!nameOK(name)) fail(`bad name ${name}`);
                    const ins=a.slice(2,-3),out=a.at(-2),delay=a.at(-1),n=ins.length;
                    const low=['NOT','BUF'].includes(kind)?1:kind==='MUX2'?3:2,high=TYPES.indexOf(kind)<6?8:low;
                    if (n<low||n>high) fail(`bad input count ${n} for ${kind}`);
                    for (const s of [...ins,out]) if (!nameOK(s)) fail(`bad name ${s}`);
                    if (!numberOK(delay)||+delay>1000) fail(`bad delay ${delay}`);
                    if (used.has(name)) fail(`duplicate name ${name}`);
                    if (driven.has(out)) fail(`multiple drivers for ${out}`);
                    used.add(name);driven.add(out);body.push({name,kind,inputs:ins,output:out,delay:+delay});for (const s of ins) reads.push([lineNo,s]);
                } else if (kind==='INST') {
                    if (a.length<3) fail('bad instance syntax');
                    if (!nameOK(name)) fail(`bad name ${name}`);
                    const m=this.lookup(a[2]),connections=[],ports=new Set();
                    for (const word of a.slice(3)) {
                        const p=word.split('=');if (p.length!==2||!p[0]||!p[1]) fail(`bad connection ${word}`);
                        const [port,s]=p;if (![...m.inputs,...m.outputs].includes(port)) fail(`unknown port ${port}`);
                        if (ports.has(port)) fail(`duplicate connection ${port}`);if (!nameOK(s)) fail(`bad name ${s}`);
                        ports.add(port);connections.push([port,s]);
                    }
                    for (const p of m.inputs) if (!ports.has(p)) fail(`unconnected input ${p}`);
                    if (used.has(name)) fail(`duplicate name ${name}`);
                    for (const [p,s] of connections) if (m.outputs.includes(p)) {if (driven.has(s)) fail(`multiple drivers for ${s}`);driven.add(s);}
                    used.add(name);body.push({name,module:m,connections});for (const [p,s] of connections) if (m.inputs.includes(p)) reads.push([lineNo,s]);
                } else fail(`unknown statement ${kind}`);
            }
            for (const s of outputs) reads.push([headerNo,s]);
            for (const [n,s] of reads) if (!driven.has(s)) {lineNo=n;fail(`undriven signal ${s}`);}
            this.modules.set(name,{name,inputs,outputs,body});const gates=body.filter(x=>x.kind).length;
            emit(`defined ${name} inputs ${inputs.length} outputs ${outputs.length} gates ${gates} instances ${body.length-gates}`);
        } catch(e) {emit(`error: line ${lineNo}: ${e.message}`);}
    }
    signal(s) {if (!this.sim.vals.has(s)) fail(`unknown signal ${s}`);}
    input(s) {if (!this.sim.c.inputs.includes(s)) fail(`not an input ${s}`);}
    time(w) {const t=number(w);if (t<this.sim.time) fail(`time ${t} is in the past`);return t;}
    hierarchy(m,depth) {for (const x of m.body) if (!x.kind) {emit('  '.repeat(depth)+x.name+' '+x.module.name);this.hierarchy(x.module,depth+1);}}
    execute(lineNo,w) {
        try {
            const cmd=w[0],a=w.slice(1),n=COUNTS[cmd];
            if (!Object.hasOwn(COUNTS,cmd)) fail(`unknown command ${cmd}`);
            if (a.length<n||(!['WATCH','UNWATCH','SHOW'].includes(cmd)&&a.length!==n)) fail('wrong argument count');
            if (SIM.includes(cmd)&&!this.sim) fail('no circuit');
            const s=this.sim;
            if (['SET','APPLY','PULSE','CLOCK','RUN'].includes(cmd)&&s.halted) fail('simulation halted');
            if (cmd==='MODULES') {emit(`modules ${this.modules.size}`);for (const m of this.modules.values()) emit(`${m.name} inputs ${m.inputs.length} outputs ${m.outputs.length} gates ${new Circuit(m).gates.length}`);return;}
            if (['BUILD','NETLIST','HIERARCHY','STATS','TRUTHTABLE','EQUIV','FAULTS','CRITICAL','PERIOD'].includes(cmd)) {
                const m=this.lookup(a[0]);if (cmd==='EQUIV') this.lookup(a[1]);const c=new Circuit(m);
                if (cmd==='BUILD') {this.sim=new Simulation(c);emit(`built ${c.name} signals ${c.signals.length} gates ${c.gates.length}`);}
                else if (cmd==='NETLIST') {emit(`netlist ${c.name} gates ${c.gates.length} signals ${c.signals.length}`);for (const g of c.gates) emit(`${g.name} ${g.kind} ${g.inputs.join(' ')} -> ${g.output} ${g.delay}`);}
                else if (cmd==='HIERARCHY') {emit(m.name);this.hierarchy(m,1);}
                else if (cmd==='STATS') {
                    const levels=new Map([...c.inputs,...c.flops.map(g=>g.output)].map(x=>[x,0]));for (const g of c.order) levels.set(g.output,Math.max(...g.inputs.map(x=>levels.get(x)))+1);
                    emit(`stats ${c.name} gates ${c.gates.length} signals ${c.signals.length} depth ${c.loop?'-':Math.max(...levels.values())}`);
                    emit(['types',...TYPES.flatMap(t=>{const n=c.gates.filter(g=>g.kind===t).length;return n?[t,String(n)]:[];})].join(' '));
                    let best=c.signals[0];for (const x of c.signals) if (c.readers.get(x).length>c.readers.get(best).length) best=x;emit(`max fanout ${best} ${c.readers.get(best).length}`);
                } else if (cmd==='CRITICAL'||cmd==='PERIOD') {
                    const period=cmd==='PERIOD';if (period&&!c.flops.length) fail(`${c.name} has no flip-flops`);if (c.loop) fail(`${c.name} has a combinational loop`);
                    const {late,early,prev}=c.arrivals(period);const ends=period?c.flops.map(g=>g.inputs[1]):c.outputs;
                    if (!period) for (const x of ends) emit(late.has(x)?`${x} min ${early.get(x)} max ${late.get(x)}`:`${x} unreachable`);
                    let best=null;for (const x of ends) if (late.has(x)&&(best===null||late.get(x)>late.get(best))) best=x;
                    const heading=period?`flip-flops ${c.flops.length} period`:'critical';
                    if (best===null) emit(heading+' none');else {const path=[best];while (prev.has(path.at(-1))) path.push(prev.get(path.at(-1)));emit(`${heading} ${late.get(best)}: ${path.reverse().join(' -> ')}`);}
                } else {
                    c.combinational();const rows=Array.from({length:2**c.inputs.length},(_,r)=>bits(r,c.inputs.length)),expected=rows.map(b=>c.evaluate(b));
                    if (cmd==='TRUTHTABLE') {emit([...c.inputs,'|',...c.outputs].join(' '));for (let r=0;r<rows.length;r++) emit([...rows[r],'|',...expected[r]].join(' '));}
                    else if (cmd==='EQUIV') {const d=this.circuit(a[1]).combinational();if (c.inputs.length!==d.inputs.length||c.outputs.length!==d.outputs.length) fail('port mismatch');const r=rows.findIndex((b,i)=>expected[i]!==d.evaluate(b));emit(r<0?'equivalent':`not equivalent at ${rows[r]}: ${expected[r]} vs ${d.evaluate(rows[r])}`);}
                    else {const undetected=[],tests=new Set();for (const x of c.signals) for (const v of '01') {const r=rows.findIndex((b,i)=>c.evaluate(b,x,v)!==expected[i]);if (r<0) undetected.push(`${x}/${v}`);else tests.add(r);}const total=2*c.signals.length;emit(`faults ${total} detected ${total-undetected.length}`);for (const f of undetected) emit('undetected '+f);emit(['tests',...[...tests].sort((x,y)=>x-y).map(r=>rows[r])].join(' '));}
                }
                return;
            }
            if (cmd==='RESET') {s.reset();emit('reset');}
            else if (cmd==='SET') {const t=this.time(a[0]);this.input(a[1]);value(a[2]);s.schedule(t,a[1],a[2]);emit(`set ${a[1]} ${a[2]} at ${t}`);}
            else if (cmd==='APPLY') {const t=this.time(a[0]),b=a[1];if (b.length!==s.c.inputs.length||!/^[01X]*$/.test(b)) fail(`bad vector ${b}`);s.c.inputs.forEach((x,i)=>s.schedule(t,x,b[i]));emit(`apply ${b} at ${t}`);}
            else if (cmd==='PULSE'||cmd==='CLOCK') {this.input(a[0]);const t=this.time(a[1]),width=number(a[2],true);if (cmd==='PULSE') {s.schedule(t,a[0],'1');s.schedule(t+width,a[0],'0');emit(`pulse ${a[0]} ${t} ${t+width}`);}else {const count=number(a[3],true);for (let i=0;i<count;i++) s.schedule(t+i*width,a[0],String(i%2));emit(`clock ${a[0]} events ${count} last ${t+(count-1)*width}`);}}
            else if (cmd==='RUN') {const t=number(a[0]);if (t<=s.time) fail(`time ${t} is not after ${s.time}`);s.run(t);}
            else if (cmd==='WATCH'||cmd==='UNWATCH') {const seen=new Set();for (const x of a) {this.signal(x);if (cmd==='WATCH'?(s.watch.includes(x)||seen.has(x)):(!s.watch.includes(x)||seen.has(x))) fail(`${cmd==='WATCH'?'already watched':'not watched'} ${x}`);seen.add(x);}s.watch=cmd==='WATCH'?[...s.watch,...a]:s.watch.filter(x=>!seen.has(x));emit('watching '+(s.watch.join(' ')||'nothing'));}
            else if (cmd==='SHOW') {for (const x of a) this.signal(x);emit((a.length?s.describe(a):[...s.describe(s.c.inputs),'|',...s.describe(s.c.outputs)]).join(' '));}
            else if (cmd==='CHECK') {this.signal(a[0]);value(a[1]);emit(`check ${a[0]}=${a[1]} `+(s.vals.get(a[0])===a[1]?'ok':`failed (${s.vals.get(a[0])})`));}
            else if (cmd==='PROBE') {const x=a[0];this.signal(x);const g=s.c.driver.get(x);emit(`${x}=${s.vals.get(x)} driven by `+(g?`${g.name} ${g.kind} ${s.describe(g.inputs).join(' ')} delay ${g.delay}`:'input'));emit(['fanout',s.c.readers.get(x).length,...s.c.readers.get(x).map(g=>g.name)].join(' '));}
            else if (cmd==='WAVE') {const start=number(a[0]),end=number(a[1]);if (!(start<end&&end<=s.time)) fail(`bad range ${start} ${end}`);if (!s.watch.length) fail('nothing watched');for (const x of s.watch) {let i=0,v='X',wave='';const h=s.history.get(x);for (let t=start;t<end;t++) {while (i<h.length&&h[i][0]<=t) v=h[i++][1];wave+=v;}emit(x+' '+wave);}}
            else if (cmd==='HISTORY') {const x=a[0];this.signal(x);const h=s.history.get(x);emit(['history',x,'changes',h.length,...h.map(([t,v])=>`${t}:${v}`)].join(' '));}
            else if (cmd==='ACTIVITY') {const k=number(a[0],true),ranked=[...s.c.signals].sort((x,y)=>s.history.get(y).length-s.history.get(x).length||(x<y?-1:x>y?1:0));for (const x of ranked.slice(0,k)) emit(`${x} ${s.history.get(x).length}`);}
            else if (cmd==='STATUS') {emit(`circuit ${s.c.name} time ${s.time} pending ${s.queue.length} events ${s.processed} halted ${s.halted?'yes':'no'}`);const vals=[...s.vals.values()];emit(`values 0:${vals.filter(x=>x==='0').length} 1:${vals.filter(x=>x==='1').length} X:${vals.filter(x=>x==='X').length}`);}
        } catch(e) {emit(`error: line ${lineNo}: ${e.message}`);}
    }
}
const lines=fs.readFileSync(0,'utf8').trimEnd().split(/\r?\n/),simulator=new Simulator();
for (let i=0;i<lines.length&&lines[i]!=='END';i++) {
    const w=lines[i].split(' ');
    if (w[0]==='MODULE') {let end=i+1;while (lines[end]!=='ENDMODULE') end++;simulator.define(i+1,lines.slice(i,end));i=end;}
    else simulator.execute(i+1,w);
}
