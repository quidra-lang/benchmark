import {itemsetKey,type Itemset} from './baskets.ts';
export class SupportCounter {
  readonly size:number;
  private readonly index=new Map<string,Set<number>>();
  private readonly cache=new Map<string,number>();
  constructor(baskets:ReadonlySet<string>[]) {
    this.size=baskets.length;this.cache.set('',this.size);
    baskets.forEach((basket,i)=>{ for(const item of basket) {
      let positions=this.index.get(item);if(!positions) { positions=new Set();this.index.set(item,positions); }positions.add(i);
    } });
  }
  count(items:string[]):number {
    const key=itemsetKey(items),cached=this.cache.get(key);if(cached!==undefined) return cached;
    const lists:Set<number>[]=[];
    for(const item of items) { const list=this.index.get(item);if(!list) { this.cache.set(key,0);return 0; }lists.push(list); }
    lists.sort((a,b)=>a.size-b.size);let count=0;
    for(const i of lists[0]) if(lists.every(list=>list.has(i))) count++;
    this.cache.set(key,count);return count;
  }
}
export interface Candidates { items:string[][];candidates:number;excluded:number;pruned:number;counted:number }
export function candidates(previous:string[][],taxonomy?:Map<string,string>):Candidates {
  const known=new Set(previous.map(itemsetKey)),prefix=previous[0].length-1,items:string[][]=[];
  let generated=0,excluded=0,pruned=0;
  for(let i=0;i<previous.length;i++) for(let j=i+1;j<previous.length;j++) {
    const left=previous[i],right=previous[j];
    if(!left.slice(0,prefix).every((item,k)=>item===right[k])) break;
    const joined=[...left,right[right.length-1]];generated++;
    if(taxonomy&&joined.length===2&&(taxonomy.get(joined[0])===joined[1]||taxonomy.get(joined[1])===joined[0])) { excluded++;continue; }
    if(joined.some((_,k)=>!known.has(itemsetKey(joined.filter((_,p)=>p!==k))))) { pruned++;continue; }
    items.push(joined);
  }
  return {items,candidates:generated,excluded,pruned,counted:items.length};
}
export function countCandidates(items:string[][],counter:SupportCounter,minimum:number):Itemset[] {
  const result:Itemset[]=[];for(const set of items) { const count=counter.count(set);if(count>=minimum) result.push({items:set,count}); }return result;
}
