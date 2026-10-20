import {readFileSync} from 'node:fs';
export interface Product { name:string;category:string;price:number }
export interface Transaction { tid:string;customer:string;day:number;units:Map<string,number> }
export interface Basket extends Transaction { items:Set<string> }
export interface Itemset { items:string[];count:number }
export const compareNames=(a:string,b:string)=>a<b?-1:a>b?1:0;
export function compareItemsets(a:string[],b:string[]):number {
  for(let i=0;i<Math.min(a.length,b.length);i++) { const c=compareNames(a[i],b[i]);if(c) return c; }
  return a.length-b.length;
}
export const itemsetKey=(items:string[])=>items.join('+');
export const contains=(items:ReadonlySet<string>,subset:string[])=>subset.every(item=>items.has(item));
export function readCsv(path:string) {
  return readFileSync(path,'ascii').slice(0,-1).split('\n').slice(1).map((line,i)=>({line:i+2,fields:line.split(',')}));
}
export function buildBasket(transaction:Transaction):Basket { return {...transaction,items:new Set(transaction.units.keys())}; }
export function extendBasket(basket:Basket,products:Map<string,Product>):Set<string> {
  const items=new Set(basket.items);for(const item of basket.items) items.add(products.get(item)!.category);return items;
}
