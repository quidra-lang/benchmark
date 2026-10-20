import {compareNames,itemsetKey,type Itemset} from './baskets.ts';
interface Pattern { items:string[];weight:number }
class Node {
  count=0;
  readonly children=new Map<string,Node>();
  constructor(readonly item:string|null,readonly parent:Node|null) {}
}
interface Tree { header:string[];links:Map<string,Node[]>;nodes:number }
function buildTree(base:Pattern[],minimum:number):Tree {
  const counts=new Map<string,number>();
  for(const pair of base) for(const item of pair.items) counts.set(item,(counts.get(item)??0)+pair.weight);
  const header=[...counts.keys()].filter(item=>counts.get(item)!>=minimum).sort((a,b)=>counts.get(b)!-counts.get(a)!||compareNames(a,b));
  const order=new Map(header.map((item,i)=>[item,i])),links=new Map<string,Node[]>(header.map(item=>[item,[]]));
  const root=new Node(null,null);let nodes=0;
  for(const pair of base) {
    const items=pair.items.filter(item=>order.has(item)).sort((a,b)=>order.get(a)!-order.get(b)!);let node=root;
    for(const item of items) {
      let child=node.children.get(item);
      if(!child) { child=new Node(item,node);node.children.set(item,child);links.get(item)!.push(child);nodes++; }
      node=child;node.count+=pair.weight;
    }
  }
  return {header,links,nodes};
}
function conditionalBase(tree:Tree,item:string):Pattern[] {
  return tree.links.get(item)!.map(node=>{
    const items:string[]=[];let parent=node.parent;
    while(parent&&parent.item!==null) { items.push(parent.item);parent=parent.parent; }
    return {items:items.reverse(),weight:node.count};
  });
}
export function mine(baskets:ReadonlySet<string>[],minimum:number,maximum:number) {
  const whole=buildTree(baskets.map(items=>({items:[...items],weight:1})),minimum);
  const stack:{tree:Tree;suffix:string[]}[]=[{tree:whole,suffix:[]}],frequent=new Map<string,Itemset>();
  let conditionalTrees=0,conditionalNodes=0;
  while(stack.length) {
    const {tree,suffix}=stack.pop()!;
    for(const item of tree.header.slice().reverse()) {
      const items=[...suffix,item].sort(compareNames);let count=0;
      for(const node of tree.links.get(item)!) count+=node.count;
      frequent.set(itemsetKey(items),{items,count});
      if(items.length<maximum) {
        const conditional=buildTree(conditionalBase(tree,item),minimum);
        if(conditional.nodes) { stack.push({tree:conditional,suffix:items});conditionalTrees++;conditionalNodes+=conditional.nodes; }
      }
    }
  }
  return {frequent,header:whole.header.length,nodes:whole.nodes,conditionalTrees,conditionalNodes};
}
