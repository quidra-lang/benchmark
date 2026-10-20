import {mkdirSync,writeFileSync} from 'node:fs';
import {readDataset,type Family,type Shewhart,type Chart,type AttributeChart,type Spec,type Lot} from './dataset.ts';
import {subgroupStatistics,movingRanges,familyLimits,outside,type Model,type Control,type Group} from './variable_charts.ts';
import {attributeModel,attributeLot,type AttributeRow} from './attribute_charts.ts';
import {runRules,zoneName,type RuleSignal} from './run_rules.ts';
import {computeCapability,frequencyDistribution} from './capability.ts';
import {variableBand,cusumBand,averageBand,standardizedBand} from './plot.ts';

const families: Family[]=['XBAR_R','XBAR_S','I_MR'];
const charts: Chart[]=['XBAR_R','R','XBAR_S','S','I','MR','CUSUM','EWMA','MA'];
const attributeCharts: AttributeChart[]=['p','np','c','u'];
const familyCharts: Record<Family,[Shewhart,Shewhart]>={XBAR_R:['XBAR_R','R'],XBAR_S:['XBAR_S','S'],I_MR:['I','MR']};
type Data=ReturnType<typeof readDataset> & {groups:Group[]};
interface Pass { pass:number; count:number; model:Model; out:number[] }
interface Estimation { retained:number[]; removed:number[]; passes:Pass[]; status:string; model:Model }
interface Signal extends RuleSignal { chart:Chart; subgroup:number }
interface AverageRow { plus:number;minus:number;ewma:number;ewmaWidth:number;ma:number;maWidth:number }
interface Baseline { center:number;sigma:number;reference:number;threshold:number;ewmaWidth:number;maWidth:number }
interface Event {
  number:number;start:number;end:number;length:number;signals:Signal[];counts:number[];
  onset:number;shift:number;spread:number;outOfSpec:number;type:string;detection:Map<Chart,number>;
}
interface AttributeResult {
  retained:number[];removed:number[];status:string;passes:{pass:number;count:number;center:number;out:number[]}[];
  rows:AttributeRow[];signals:RuleSignal[];
}
const numbers=(first:number,last:number)=>Array.from({length:last-first+1},(_,i)=>first+i);
function real(value:number):string {
  if(Math.abs(value)>=1e21) return `${BigInt(value)}.0000`;
  const text=value.toFixed(4);return text==='-0.0000'?'0.0000':text;
}
const numberList=(values:number[])=>values.length?values.join(' '):'none';
const controlText=(name:string,c:Control)=>`${name} lcl ${real(c.lcl)} cl ${real(c.cl)} ucl ${real(c.ucl)}`;
function modelText(family:Family,model:Model):string {
  return `${controlText(family==='I_MR'?'I':'XBAR',model.limits[0])} ${controlText(family==='I_MR'?'MR':family==='XBAR_R'?'R':'S',model.limits[1])}`;
}
function estimateFamily(family:Family,data:Data):Estimation {
  const {spec,groups,samples,constants}=data;
  const initial=numbers(1,spec.phase1_subgroups*(family==='I_MR'?spec.subgroup_size:1));
  let retained=initial,model=familyLimits(family,retained,groups,samples,spec.subgroup_size,constants),status='stopped';
  const passes:Pass[]=[];
  for(let pass=1;pass<=spec.max_passes;pass++) {
    if(pass>1) model=familyLimits(family,retained,groups,samples,spec.subgroup_size,constants);
    const excluded=new Set<number>();
    for(let j=0;j<2;j++) for(const point of model.sequences[j]) if(outside(point.value,model.limits[j])) excluded.add(point.number);
    const out=retained.filter(number=>excluded.has(number));passes.push({pass,count:retained.length,model,out});
    if(!out.length) { status='converged';break; }
    if(pass===spec.max_passes) break;
    retained=retained.filter(number=>!excluded.has(number));
  }
  return {retained,removed:initial.filter(number=>!retained.includes(number)),passes,status,model};
}
function monitorAverages(data:Data,estimates:Map<Family,Estimation>) {
  const {spec,constants,groups}=data,xr=estimates.get('XBAR_R')!.model.limits;
  const center=xr[0].cl,sigma=xr[1].cl/constants.d2/Math.sqrt(spec.subgroup_size);
  const reference=spec.cusum_k*sigma,threshold=spec.cusum_h*sigma,lambda=spec.ewma_lambda;
  const q=(1-lambda)*(1-lambda),rho=lambda/(2-lambda),ewmaWidth=spec.ewma_l*sigma*Math.sqrt(rho),maWidth=3*sigma/Math.sqrt(spec.ma_span);
  const baseline:Baseline={center,sigma,reference,threshold,ewmaWidth,maWidth},rows=new Map<number,AverageRow>(),signals:Signal[]=[];
  let plus=0,minus=0,plusLength=0,minusLength=0,z=center,factor=1;
  function emit(chart:Chart,upper:boolean,start:number,end:number,value:number) {
    signals.push({chart,rule:upper?'UPPER':'LOWER',start,end,value,direction:upper?'UP':'DOWN',subgroup:end});
  }
  for(const group of groups.slice(spec.phase1_subgroups)) {
    const end=group.number;
    plus=Math.max(0,plus+(group.mean-center-reference));minus=Math.max(0,minus+(center-group.mean-reference));
    plusLength=plus>0?plusLength+1:0;minusLength=minus>0?minusLength+1:0;
    const savedPlus=plus,savedMinus=minus;
    if(plus>threshold) { emit('CUSUM',true,end-plusLength+1,end,plus);plus=0;plusLength=0; }
    if(minus>threshold) { emit('CUSUM',false,end-minusLength+1,end,minus);minus=0;minusLength=0; }
    z=lambda*group.mean+(1-lambda)*z;factor=factor*q;
    const currentEwmaWidth=spec.ewma_l*sigma*Math.sqrt(rho*(1-factor));
    if(z>center+currentEwmaWidth) emit('EWMA',true,end,end,z);
    if(z<center-currentEwmaWidth) emit('EWMA',false,end,end,z);
    const start=Math.max(spec.phase1_subgroups+1,end-spec.ma_span+1),count=end-start+1;
    let total=0;for(let i=start;i<=end;i++) total+=groups[i-1].total;
    const ma=total/(spec.subgroup_size*count),currentMaWidth=3*sigma/Math.sqrt(count);
    if(ma>center+currentMaWidth) emit('MA',true,start,end,ma);
    if(ma<center-currentMaWidth) emit('MA',false,start,end,ma);
    rows.set(end,{plus:savedPlus,minus:savedMinus,ewma:z,ewmaWidth:currentEwmaWidth,ma,maWidth:currentMaWidth});
  }
  return {baseline,rows,signals};
}
function characterizeEvents(signals:Signal[],data:Data,estimates:Map<Family,Estimation>,baseline:Baseline):Event[] {
  const ranges:{start:number;end:number}[]=[];
  for(const number of [...new Set(signals.map(s=>s.subgroup))].sort((a,b)=>a-b)) {
    const previous=ranges.at(-1);
    if(previous&&number-previous.end-1<=data.spec.event_gap) previous.end=number;
    else ranges.push({start:number,end:number});
  }
  return ranges.map(({start,end},index)=>{
    const found=signals.filter(s=>start<=s.subgroup&&s.subgroup<=end),counts=[0,0,0,0,0],detection=new Map<Chart,number>();
    let onset:number|undefined;
    for(const s of found) {
      const spread=s.chart==='R'||s.chart==='S'||s.chart==='MR';
      counts[s.direction==='NONE'?4:spread?(s.direction==='UP'?2:3):(s.direction==='UP'?0:1)]++;
      detection.set(s.chart,Math.min(detection.get(s.chart)??Infinity,s.subgroup));
      if(s.chart==='CUSUM') onset=Math.min(onset??Infinity,s.start);
    }
    let best=0;for(let i=1;i<5;i++) if(counts[i]>counts[best]) best=i;
    let total=0,deviations=0,outOfSpec=0;
    for(let i=start;i<=end;i++) {
      const group=data.groups[i-1];total+=group.total;deviations+=group.sd;
      for(const sample of group.samples) if(sample.value<data.spec.lsl||sample.value>data.spec.usl) outOfSpec++;
    }
    const length=end-start+1;
    return {number:index+1,start,end,length,signals:found,counts,detection,onset:onset??start,outOfSpec,
      type:['SHIFT_UP','SHIFT_DOWN','SPREAD_UP','SPREAD_DOWN','PATTERN'][best],
      shift:(total/(data.spec.subgroup_size*length)-baseline.center)/baseline.sigma,
      spread:(deviations/length)/estimates.get('XBAR_S')!.model.limits[1].cl};
  });
}
function estimateAttribute(chart:AttributeChart,lots:Lot[],spec:Spec):AttributeResult {
  const initial=numbers(1,lots.length);let retained=initial,status='stopped',model=attributeModel(chart,retained,lots);
  const passes:AttributeResult['passes']=[];
  for(let pass=1;pass<=spec.max_passes;pass++) {
    if(pass>1) model=attributeModel(chart,retained,lots);
    const out=retained.filter(number=>attributeLot(chart,model,lots[number-1]).status!=='ok');
    passes.push({pass,count:retained.length,center:model.center,out});
    if(!out.length) { status='converged';break; }
    if(pass===spec.max_passes) break;
    retained=retained.filter(number=>!out.includes(number));
  }
  const rows=lots.map(lot=>attributeLot(chart,model,lot));
  return {retained,removed:initial.filter(number=>!retained.includes(number)),status,passes,rows,
    signals:runRules(rows.map(row=>({number:row.number,value:row.z})),{lcl:-3,cl:0,ucl:3},spec.rules.STD)};
}
function main() {
  const loaded=readDataset(),data:Data={...loaded,groups:subgroupStatistics(loaded.samples,loaded.spec.subgroup_size)};
  const {spec,groups,samples,constants}=data,n=spec.subgroup_size,m=spec.phase1_subgroups;
  const estimates=new Map<Family,Estimation>(families.map(f=>[f,estimateFamily(f,data)]));
  const checks=new Map<Shewhart,{control:Control;points:number;signals:RuleSignal[]}>();
  const signals:Signal[]=[];
  const phase2=groups.slice(m),means=phase2.map(g=>({number:g.number,value:g.mean}));
  const phaseSequences={XBAR_R:means,R:phase2.map(g=>({number:g.number,value:g.range})),XBAR_S:means,
    S:phase2.map(g=>({number:g.number,value:g.sd})),I:samples.slice(m*n),MR:movingRanges(samples).filter(p=>p.number>m*n)};
  for(const family of families) {
    const model=estimates.get(family)!.model;
    familyCharts[family].forEach((chart,j)=>{
      const sequence=model.sequences[j],control=model.limits[j];
      checks.set(chart,{control,points:sequence.length,signals:runRules(sequence,control,spec.rules[chart])});
      for(const signal of runRules(phaseSequences[chart],control,spec.rules[chart])) signals.push({...signal,chart,
        subgroup:chart==='I'||chart==='MR'?Math.floor((signal.end-1)/n)+1:signal.end});
    });
  }
  const averages=monitorAverages(data,estimates),{baseline,rows}=averages;
  signals.push(...averages.signals);
  const ruleOrder=(r:RuleSignal['rule'])=>typeof r==='number'?r:r==='UPPER'?9:10;
  signals.sort((a,b)=>charts.indexOf(a.chart)-charts.indexOf(b.chart)||a.end-b.end||ruleOrder(a.rule)-ruleOrder(b.rule));
  const events=characterizeEvents(signals,data,estimates,baseline),eventAt=new Map<number,Event>();
  for(const event of events) for(let i=event.start;i<=event.end;i++) eventAt.set(i,event);
  const proposed=new Map<Family,{points:number[];model:Model}>();
  for(const family of families) {
    const points=estimates.get(family)!.retained.slice();
    for(const group of phase2) if(!eventAt.has(group.number)) points.push(...(family==='I_MR'?group.samples.map(s=>s.number):[group.number]));
    proposed.set(family,{points,model:familyLimits(family,points,groups,samples,n,constants)});
  }
  const attributes=new Map(attributeCharts.map(chart=>[chart,estimateAttribute(chart,data.lots,spec)]));
  const limits=[`characteristic ${spec.characteristic}`,`subgroup_size ${n}`,`subgroups ${groups.length}`,`samples ${samples.length}`,`phase1_subgroups ${m}`];
  for(const family of families) {
    const result=estimates.get(family)!;limits.push(`family ${family}`);
    for(const p of result.passes) limits.push(`pass ${p.pass} points ${p.count} ${modelText(family,p.model)} out ${numberList(p.out)}`);
    limits.push(`result ${result.status} passes ${result.passes.length} retained ${result.retained.length} removed ${numberList(result.removed)}`);
  }
  for(const [chart,check] of checks) {
    for(const s of check.signals) limits.push(`phase1_signal ${chart} ${s.rule} ${s.start} ${s.end} ${real(s.value)}`);
    limits.push(`phase1_check ${chart} points ${check.points} signals ${check.signals.length}`);
  }
  for(const family of families) { const p=proposed.get(family)!;limits.push(`proposed ${family} points ${p.points.length} ${modelText(family,p.model)}`); }
  const {center,sigma,reference,threshold,ewmaWidth,maWidth}=baseline;
  limits.push(`cusum target ${real(center)} sigma ${real(sigma)} k ${real(reference)} h ${real(threshold)}`,
    `ewma target ${real(center)} sigma ${real(sigma)} lcl ${real(center-ewmaWidth)} ucl ${real(center+ewmaWidth)}`,
    `ma target ${real(center)} sigma ${real(sigma)} span ${spec.ma_span} lcl ${real(center-maWidth)} ucl ${real(center+maWidth)}`);
  for(const chart of charts) {
    const found=signals.filter(s=>s.chart===chart),ends=new Set(found.map(s=>s.end));
    const rules:RuleSignal['rule'][]=chart==='CUSUM'||chart==='EWMA'||chart==='MA'?['UPPER','LOWER']:spec.rules[chart];
    const points=chart==='I'||chart==='MR'?samples.length-m*n:groups.length-m;
    limits.push(`phase2 ${chart} points ${points} signals ${found.length} signalled ${ends.size} first ${found[0]?.end??'none'} by_rule ${rules.map(r=>`${r}:${found.filter(s=>s.rule===r).length}`).join(' ')}`);
  }
  const eventLines=[`events ${events.length}`];
  for(const e of events) {
    eventLines.push(`event ${e.number} start ${e.start} end ${e.end} length ${e.length} signals ${e.signals.length} charts ${charts.filter(c=>e.detection.has(c)).join(',')}`+
      ` location_up ${e.counts[0]} location_down ${e.counts[1]} spread_up ${e.counts[2]} spread_down ${e.counts[3]} pattern ${e.counts[4]} onset ${e.onset}`+
      ` shift ${real(e.shift)} spread ${real(e.spread)} out_of_spec ${e.outOfSpec} type ${e.type}`,
      `detection ${e.number} ${charts.map(c=>`${c}:${e.detection.get(c)??'-'}`).join(' ')}`);
  }
  const subgroupLines=['subgroup,phase,mean,zone,range,sd,cusum_upper,cusum_lower,ewma,ma,signals,event'];
  const xr=estimates.get('XBAR_R')!;
  for(const g of groups) {
    const row=rows.get(g.number),phase=g.number>m?'phase2':xr.removed.includes(g.number)?'excluded':'phase1';
    subgroupLines.push([g.number,phase,real(g.mean),zoneName(g.mean,xr.model.limits[0]),g.range,real(g.sd),
      ...(row?[row.plus,row.minus,row.ewma,row.ma].map(real):['-','-','-','-']),signals.filter(s=>s.subgroup===g.number).length,eventAt.get(g.number)?.number??'-'].join(','));
  }
  const attributeLines:string[]=[];
  for(const chart of attributeCharts) {
    const r=attributes.get(chart)!;attributeLines.push(`chart ${chart}`);
    for(const p of r.passes) attributeLines.push(`pass ${p.pass} lots ${p.count} center ${real(p.center)} out ${numberList(p.out)}`);
    attributeLines.push(`result ${r.status} passes ${r.passes.length} retained ${r.retained.length} removed ${numberList(r.removed)}`);
    for(const row of r.rows) attributeLines.push(`lot ${row.number} size ${row.inspected} value ${chart==='np'||chart==='c'?row.value:real(row.value)} lcl ${real(row.lcl)} ucl ${real(row.ucl)} z ${real(row.z)} status ${row.status}`);
    for(const s of r.signals) attributeLines.push(`signal ${s.rule} ${s.start} ${s.end} ${real(s.value)}`);
    attributeLines.push(`signals ${r.signals.length}`);
  }
  const capabilityLines:string[]=[];
  function target(points:number[]) {
    const selected=points.map(i=>groups[i-1]),values=selected.flatMap(g=>g.samples);
    return {selected,values,result:computeCapability(selected,values,spec,constants)};
  }
  const fields=[['mean','mean'],['sigma_within','sigmaWithin'],['sigma_sbar','sigmaSbar'],['sigma_overall','sigmaOverall'],
    ['cp','cp'],['cpu','cpu'],['cpl','cpl'],['cpk','cpk'],['pp','pp'],['ppu','ppu'],['ppl','ppl'],['ppk','ppk'],['cpm','cpm']] satisfies [string,keyof Pick<ReturnType<typeof computeCapability>,'mean'|'sigmaWithin'|'sigmaSbar'|'sigmaOverall'|'cp'|'cpu'|'cpl'|'cpk'|'pp'|'ppu'|'ppl'|'ppk'|'cpm'>][];
  for(const [name,points] of [['phase1',xr.retained],['phase2',numbers(m+1,groups.length)]] satisfies [string,number[]][]) {
    const t=target(points),v=t.result;capabilityLines.push(`group ${name} subgroups ${t.selected.length} values ${t.values.length}`);
    for(const [label,key] of fields) capabilityLines.push(`${label} ${real(v[key])}`);
    capabilityLines.push(`cpk_ci ${v.cpkCI.map(real).join(' ')}`,`ppk_ci ${v.ppkCI.map(real).join(' ')}`,`below_lsl ${v.below}`,`above_usl ${v.above}`,`ppm ${real(v.ppm)}`);
    for(const s of v.outOfSpec) capabilityLines.push(`out_of_spec sample ${s.number} subgroup ${s.subgroup} value ${s.value} side ${s.side}`);
    capabilityLines.push(`verdict ${v.verdict}`);
    for(const bin of frequencyDistribution(t.values,spec)) capabilityLines.push(`bin ${bin.lower} ${bin.upper} ${bin.frequency}`+
      (bin.barLength?' '+'#'.repeat(bin.barLength):'')+(bin.marks.length?' '+bin.marks.join(' '):''));
  }
  for(let start=m+1;start+spec.rolling_window-1<=groups.length;start+=spec.rolling_step) {
    const end=start+spec.rolling_window-1,v=target(numbers(start,end)).result;
    capabilityLines.push(`rolling ${start} ${end} mean ${real(v.mean)} sigma_within ${real(v.sigmaWithin)} sigma_overall ${real(v.sigmaOverall)} cpk ${real(v.cpk)} ppk ${real(v.ppk)} verdict ${v.verdict}`);
  }
  const chartLines:string[]=[],has=(chart:Chart,end:number,rule?:RuleSignal['rule'])=>signals.some(s=>s.chart===chart&&s.end===end&&(rule===undefined||s.rule===rule));
  const pictures:{name:string;chart:Chart;family:Family;control:0|1;property:'mean'|'range'|'sd'}[]=[
    {name:'XBAR',chart:'XBAR_R',family:'XBAR_R',control:0,property:'mean'},
    {name:'R',chart:'R',family:'XBAR_R',control:1,property:'range'},{name:'S',chart:'S',family:'XBAR_S',control:1,property:'sd'}];
  const label=(number:number)=>String(number).padStart(3,' ');
  for(const p of pictures) {
    const f=estimates.get(p.family)!,c=f.model.limits[p.control];chartLines.push(`chart ${controlText(p.name,c)}`);
    for(const g of groups) chartLines.push(`${label(g.number)} ${g.number>m?'2':f.removed.includes(g.number)?'x':'1'} ${variableBand(c,g[p.property],g.number>m&&has(p.chart,g.number))} ${real(g[p.property])}`);
  }
  chartLines.push(`chart CUSUM h ${real(threshold)}`);
  for(const [i,r] of rows) chartLines.push(`${label(i)} ${cusumBand(r.plus,r.minus,threshold,has('CUSUM',i,'UPPER'),has('CUSUM',i,'LOWER'))} ${real(r.plus)} ${real(r.minus)}`);
  for(const chart of ['EWMA','MA'] satisfies Chart[]) {
    const width=chart==='EWMA'?ewmaWidth:maWidth;
    chartLines.push(`chart ${controlText(chart,{lcl:center-width,cl:center,ucl:center+width})}`);
    for(const [i,r] of rows) {
      const value=chart==='EWMA'?r.ewma:r.ma,current=chart==='EWMA'?r.ewmaWidth:r.maWidth;
      chartLines.push(`${label(i)} ${averageBand(value,current,width,center,has(chart,i))} ${real(value)} ${real(center-current)} ${real(center+current)}`);
    }
  }
  for(const chart of attributeCharts) {
    chartLines.push(`chart ${chart.toUpperCase()}_STD lcl -3.0000 cl 0.0000 ucl 3.0000`);
    for(const r of attributes.get(chart)!.rows) chartLines.push(`${label(r.number)} ${standardizedBand(r.z,r.status)} ${real(r.z)}`);
  }
  const reports:Record<string,string[]>={'limits.txt':limits,'signals.csv':['chart,rule,start,end,value,direction',...signals.map(s=>`${s.chart},${s.rule},${s.start},${s.end},${real(s.value)},${s.direction}`)],
    'events.txt':eventLines,'subgroups.csv':subgroupLines,'attribute_charts.txt':attributeLines,'capability.txt':capabilityLines,'charts.txt':chartLines};
  mkdirSync('output',{recursive:true});
  for(const [name,lines] of Object.entries(reports)) writeFileSync(`output/${name}`,lines.join('\n')+'\n','ascii');
}
main();
