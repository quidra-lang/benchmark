const fs=require('fs');
const columns='ABCDEFGHJKLMNOPQRST';
const arity={BOARD:2,KOMI:1,SUPERKO:1,HANDICAP:1,PLAY:2,PASS:1,REPLAY:1,UNDO:0,SHOW:0,MAP:0,STATUS:0,CAPTURES:0,HISTORY:0,MOVES:0,GROUP:1,GROUPS:0,ATARI:0,LEGAL:1,EYES:1,SAFE:1,LADDER:1,DEAD:1,REGIONS:0,SCORE:1};
const handicap={9:'C3 G7 C7 G3 C5 G5 E3 E7 E5',13:'D4 K10 D10 K4 D7 K7 G4 G10 G7',19:'D4 Q16 D16 Q4 D10 Q10 K4 K16 K10'};
const other=c=>c==='B'?'W':'B';
const half=x=>(x<0?'-':'')+Math.floor(Math.abs(x)/2)+'.'+(Math.abs(x)%2?'5':'0');
const sorted=s=>[...s].sort((a,b)=>a-b);
function komi(s) { if(!/^-?(0|[1-9][0-9]*)(?:\.[05])?$/.test(s)) return null; const x=Number(s)*2; return Math.abs(x)>201||(s[0]==='-'&&x===0)?null:x; }
function adjacent(p,n,diagonal=false) { const r=Math.floor(p/n),c=p%n,a=[]; const steps=diagonal?[[-1,-1],[-1,1],[1,-1],[1,1]]:[[-1,0],[1,0],[0,-1],[0,1]]; for(const [dr,dc] of steps) if(r+dr>=0&&r+dr<n&&c+dc>=0&&c+dc<n) a.push((r+dr)*n+c+dc); return a; }
function flood(b,n,p,allowed) { const s=new Set([p]),todo=[p]; while(todo.length) for(const q of adjacent(todo.pop(),n)) if(!s.has(q)&&allowed.includes(b[q])) { s.add(q); todo.push(q); } return s; }
function group(b,n,p) { const stones=flood(b,n,p,b[p]),liberties=new Set(); for(const s of stones) for(const q of adjacent(s,n)) if(b[q]==='.') liberties.add(q); return {color:b[p],first:Math.min(...stones),stones,liberties}; }
function groups(b,n,color='') { const seen=new Set(),r=[]; for(let p=0;p<b.length;p++) if(b[p]!=='.'&&!seen.has(p)&&(!color||color===b[p])) { const g=group(b,n,p); r.push(g); for(const q of g.stones) seen.add(q); } return r; }
function placement(b,n,c,p) { if(b[p]!=='.') return {board:b,captured:0,reason:'occupied'}; const a=b.split(''); a[p]=c; let captured=0; const seen=new Set(); for(const q of adjacent(p,n)) if(a[q]===other(c)&&!seen.has(q)) { const g=group(a.join(''),n,q); for(const t of g.stones) seen.add(t); if(!g.liberties.size) for(const t of g.stones) { a[t]='.'; captured++; } } const board=a.join(''); return {board,captured,reason:group(board,n,p).liberties.size?'':'suicide'}; }
function regions(b,n) { const seen=new Set(),r=[]; for(let p=0;p<b.length;p++) if(b[p]==='.'&&!seen.has(p)) { const points=flood(b,n,p,'.'),border=new Set(); for(const q of points) { seen.add(q); for(const t of adjacent(q,n)) if(b[t]!=='.') border.add(b[t]); } r.push({first:p,points,owner:border.size===1?[...border][0]:'neutral'}); } return r; }
function safe(b,n,c) {
    const own=groups(b,n,c),areas=[],seen=new Set();
    for(let p=0;p<b.length;p++) if(b[p]!==c&&!seen.has(p)) { const points=flood(b,n,p,'.'+other(c)); for(const q of points) seen.add(q); const empty=[...points].filter(q=>b[q]==='.'); areas.push({touch:new Set(own.flatMap((g,i)=>[...points].some(q=>adjacent(q,n).some(t=>g.stones.has(t)))?[i]:[])),vital:new Set(own.flatMap((g,i)=>empty.every(q=>g.liberties.has(q))?[i]:[]))}); }
    let s=new Set(own.map((_,i)=>i)),t=new Set(areas.map((_,i)=>i));
    while(true) { const count=s.size+t.size; s=new Set([...s].filter(i=>[...t].filter(j=>areas[j].vital.has(i)).length>=2)); t=new Set([...t].filter(j=>[...areas[j].touch].every(i=>s.has(i)))); if(count===s.size+t.size) break; } return sorted(s).map(i=>own[i]);
}
function ladder(b,n,p) {
    const defender=b[p],attacker=other(defender),memo=new Map();
    function read(current,depth,defending) {
        if(depth>=40) return {success:defending,move:-1}; const key=current+':'+depth+':'+defending; if(memo.has(key)) return memo.get(key);
        const g=group(current,n,p),candidates=new Set(g.liberties),seen=new Set();
        if(defending) for(const q of g.stones) for(const t of adjacent(q,n)) if(current[t]===attacker&&!seen.has(t)) { const e=group(current,n,t); for(const s of e.stones) seen.add(s); if(e.liberties.size===1) for(const s of e.liberties) candidates.add(s); }
        for(const q of sorted(candidates)) { const next=placement(current,n,defending?defender:attacker,q); if(next.reason) continue; let success;
            if(defending) { const m=group(next.board,n,p).liberties.size; success=m>=3||(m===2&&!read(next.board,depth+1,false).success); }
            else success=!read(next.board,depth+1,true).success;
            if(success) { const result={success:true,move:q}; memo.set(key,result); return result; }
        } const result={success:false,move:-1}; memo.set(key,result); return result;
    }
    const m=group(b,n,p).liberties.size; if(m>=3) return {status:'safe',move:-1}; const r=read(b,0,m===1); return {status:(m===1?r.success:!r.success)?'escapes':'captured',move:r.move};
}
class Game {
    constructor() { this.superko=false; this.output=[]; this.reset(19,13); }
    emit(...a) { this.output.push(a.join(' ')); }
    reset(n,k) { this.n=n; this.komi=k; this.board='.'.repeat(n*n); this.turn='B'; this.captures={B:0,W:0}; this.passes=0; this.over=false; this.handicap=[]; this.history=[]; this.positions=[this.board]; this.dead=new Set(); }
    point(s) { if(!/^[A-HJ-T](?:[1-9]|1[0-9])$/.test(s)) return -1; const c=columns.indexOf(s[0]),r=Number(s.slice(1)); return c<this.n&&r<=this.n?(r-1)*this.n+c:-1; }
    name(p) { return columns[p%this.n]+(Math.floor(p/this.n)+1); }
    sgf(p) { return String.fromCharCode(97+p%this.n,97+this.n-1-Math.floor(p/this.n)); }
    check(c,p) { const r=placement(this.board,this.n,c,p); if(!r.reason&&this.positions.length>=2&&r.board===this.positions.at(-2)) r.reason='ko'; if(!r.reason&&this.superko&&this.positions.includes(r.board)) r.reason='superko'; return r; }
    move(c,p,checked) { const before={board:this.board,turn:this.turn,captures:{...this.captures},passes:this.passes,over:this.over}; let captured=0; if(p<0) { this.passes++; if(this.passes===2) this.over=true; } else { const r=checked||this.check(c,p); this.board=r.board; captured=r.captured; this.captures[c]+=captured; this.passes=0; } this.turn=other(c); this.history.push({color:c,point:p,captured,before}); this.positions.push(this.board); this.dead.clear(); return captured; }
    clean() { return [...this.board].map((c,i)=>this.dead.has(i)?'.':c).join(''); }
    show(map=false) { const b=map?this.clean():this.board,chars=[...b],stars=handicap[this.n].split(' ').filter((_,i)=>this.n===19||i<4||i===8).map(s=>this.point(s));
        if(map) for(const r of regions(b,this.n)) for(const p of r.points) chars[p]=r.owner==='B'?'x':r.owner==='W'?'o':'.';
        for(let p=0;p<b.length;p++) if(b[p]!=='.') chars[p]=b[p]==='B'?(this.dead.has(p)&&!map?'x':'X'):(this.dead.has(p)&&!map?'o':'O'); else if(!map) chars[p]=stars.includes(p)?'+':'.';
        const header='   '+columns.slice(0,this.n).split('').join(' '); this.emit(header); for(let r=this.n;r>=1;r--) this.emit(String(r).padStart(2),chars.slice((r-1)*this.n,r*this.n).join(' '),r); this.emit(header);
    }
    score(method) { const b=this.clean(),territory={B:0,W:0}; for(const r of regions(b,this.n)) if(r.owner!=='neutral') territory[r.owner]+=r.points.size; const total={B:0,W:0};
        for(const c of ['B','W']) { if(method==='AREA') { const stones=[...b].filter(s=>s===c).length; total[c]=2*(stones+territory[c])+(c==='W'?this.komi:0); this.emit(c,'stones',stones,'territory',territory[c],...(c==='W'?['komi',half(this.komi)]:[]),'total',half(total[c])); } else { const prisoners=this.captures[c]+[...this.dead].filter(p=>this.board[p]===other(c)).length; total[c]=2*(territory[c]+prisoners)+(c==='W'?this.komi:0); this.emit(c,'territory',territory[c],'prisoners',prisoners,...(c==='W'?['komi',half(this.komi)]:[]),'total',half(total[c])); } } const d=total.B-total.W; this.emit('result',d>0?'B+'+half(d):d<0?'W+'+half(-d):'Draw');
    }
    execute(line) {
        const [c,...a]=line.split(' '),error=s=>this.emit('ERROR',s); if(!Object.hasOwn(arity,c)) return error('unknown command'); if(a.length!==arity[c]) return error('bad arguments'); let valid=true;
        if(c==='BOARD') valid=['9','13','19'].includes(a[0])&&komi(a[1])!==null; else if(c==='KOMI') valid=komi(a[0])!==null; else if(c==='SUPERKO') valid=['ON','OFF'].includes(a[0]); else if(c==='HANDICAP') valid=/^[2-9]$/.test(a[0]); else if(['PLAY','PASS','LEGAL','EYES','SAFE'].includes(c)) valid=['B','W'].includes(a[0]); else if(c==='SCORE') valid=['AREA','TERRITORY'].includes(a[0]);
        if(!valid) return error('bad arguments'); const p=['PLAY','GROUP','LADDER','DEAD'].includes(c)?this.point(a[c==='PLAY'?1:0]):-1; if(['PLAY','GROUP','LADDER','DEAD'].includes(c)&&p<0) return error('bad point');
        let records=[]; if(c==='REPLAY') { if(!/^(?:;[BW]\[[a-z]{0,2}\])+$/.test(a[0])) return error('bad sequence'); records=[...a[0].matchAll(/;([BW])\[([a-z]*)\]/g)]; if(records.some(r=>r[2]&&(r[2].length!==2||[...r[2]].some(ch=>ch.charCodeAt(0)-97>=this.n)))) return error('bad sequence'); }
        if(['PLAY','PASS','REPLAY'].includes(c)&&this.over) return error('game over');
        switch(c) {
        case 'BOARD': this.reset(Number(a[0]),komi(a[1])); this.emit('board',this.n,'komi',half(this.komi)); break;
        case 'KOMI': this.komi=komi(a[0]); this.emit('komi',half(this.komi)); break;
        case 'SUPERKO':this.superko=a[0]==='ON';this.emit('superko',this.superko?'on':'off');break;
        case 'HANDICAP': { if(this.history.length||/[BW]/.test(this.board)) return error('handicap not allowed'); const k=Number(a[0]),ix=k===5?[0,1,2,3,8]:k===7?[0,1,2,3,4,5,8]:Array.from({length:k},(_,i)=>i),points=handicap[this.n].split(' ');this.handicap=ix.map(i=>this.point(points[i]));const b=[...this.board];for(const q of this.handicap)b[q]='B';this.board=b.join('');this.turn='W';this.positions=[this.board];this.dead.clear();this.emit('handicap',k,...this.handicap.map(q=>this.name(q)));break; }
        case 'PLAY': { const r=this.check(a[0],p),reason=a[0]!==this.turn?'turn':r.reason; if(reason)this.emit('ILLEGAL',a[0],a[1],reason);else {const n=this.move(a[0],p,r);this.emit(a[0],a[1],...(n?['captures',n]:[]));}break; }
        case 'PASS':if(a[0]!==this.turn)this.emit('ILLEGAL',a[0],'pass','turn');else{this.move(a[0],-1);this.emit(a[0],'pass');if(this.over)this.emit('game over');}break;
        case 'REPLAY': { let count=0,stop=[]; for(const r of records){const color=r[1],q=r[2]?(this.n-1-(r[2].charCodeAt(1)-97))*this.n+r[2].charCodeAt(0)-97:-1,next=q<0?null:this.check(color,q),reason=this.over?'game over':color!==this.turn?'turn':next?next.reason:'';if(reason){stop=['stopped',color,q<0?'pass':this.name(q),reason];break;}this.move(color,q,next);count++;}this.emit('replay',count,'moves',...stop);if(this.over)this.emit('game over');break; }
        case 'UNDO': {if(!this.history.length)return error('nothing to undo');const m=this.history.pop();Object.assign(this,m.before);this.positions.pop();this.dead.clear();this.emit('undo',m.color,m.point<0?'pass':this.name(m.point));break;}
        case 'SHOW':this.show();break; case 'MAP':this.show(true);break;
        case 'STATUS':this.emit('size',this.n,'komi',half(this.komi),'handicap',this.handicap.length,'superko',this.superko?'on':'off');this.emit('moves',this.history.length,...(this.over?['game over']:['next',this.turn,'passes',this.passes]));break;
        case 'CAPTURES':this.emit('captures','B',this.captures.B,'W',this.captures.W);break;
        case 'HISTORY':this.emit('history',this.history.length);this.history.forEach((m,i)=>this.emit(i+1,m.color,m.point<0?'pass':this.name(m.point),...(m.captured?['captures',m.captured]:[])));break;
        case 'MOVES':this.emit('(;GM[1]FF[4]SZ['+this.n+']KM['+half(this.komi)+']'+(this.handicap.length?'HA['+this.handicap.length+']AB'+this.handicap.map(p=>'['+this.sgf(p)+']').join(''):'')+this.history.map(m=>';'+m.color+'['+(m.point<0?'':this.sgf(m.point))+']').join('')+')');break;
        case 'GROUP':case 'DEAD':case 'LADDER': {if(this.board[p]==='.')return error('no stone');const g=group(this.board,this.n,p);if(c==='GROUP'){this.emit('group',g.color,this.name(g.first),'size',g.stones.size,'liberties',g.liberties.size);this.emit('stones',...sorted(g.stones).map(q=>this.name(q)));this.emit('liberties',...sorted(g.liberties).map(q=>this.name(q)));}else if(c==='DEAD'){const alive=this.dead.has(p);for(const q of g.stones)if(alive)this.dead.delete(q);else this.dead.add(q);this.emit(alive?'alive':'dead',g.color,this.name(g.first),'size',g.stones.size);}else{const r=ladder(this.board,this.n,p);this.emit('ladder',a[0],r.status,...(r.move<0?[]:[this.name(r.move)]));}break;}
        case 'GROUPS': {const gs=groups(this.board,this.n);this.emit('groups',gs.length);for(const g of gs)this.emit(g.color,this.name(g.first),'size',g.stones.size,'liberties',g.liberties.size,...(this.dead.has(g.first)?['dead']:[]));break;}
        case 'ATARI': {const gs=groups(this.board,this.n).filter(g=>g.liberties.size===1);if(!gs.length)this.emit('atari none');for(const g of gs)this.emit('atari',g.color,this.name(g.first),'size',g.stones.size,'at',this.name([...g.liberties][0]));break;}
        case 'LEGAL': {const rejected=[];let count=0;for(let q=0;q<this.board.length;q++)if(this.board[q]==='.'){const r=this.check(a[0],q);if(r.reason)rejected.push([this.name(q),r.reason]);else count++;}this.emit('legal',a[0],count);for(const r of rejected)this.emit(...r);break;}
        case 'EYES': {const found=[];for(let q=0;q<this.board.length;q++)if(this.board[q]==='.'){const ns=adjacent(q,this.n);if(ns.every(t=>this.board[t]===a[0])){const enemies=adjacent(q,this.n,true).filter(t=>this.board[t]===other(a[0])).length;found.push([this.name(q),enemies<=(ns.length===4?1:0)?'real':'false']);}}this.emit('eyes',a[0],found.length);for(const r of found)this.emit(...r);break;}
        case 'SAFE': {const gs=safe(this.board,this.n,a[0]);this.emit('safe',a[0],gs.length);for(const g of gs)this.emit(this.name(g.first),'size',g.stones.size);break;}
        case 'REGIONS': {const rs=regions(this.clean(),this.n);this.emit('regions',rs.length);for(const r of rs)this.emit(this.name(r.first),'size',r.points.size,r.owner);break;}
        case 'SCORE':this.score(a[0]);break;
        }
    }
}
const game=new Game(),lines=fs.readFileSync(0,'utf8').split(/\r?\n/);for(const line of lines.slice(1,1+Number(lines[0])))game.execute(line);console.log(game.output.join('\n'));
