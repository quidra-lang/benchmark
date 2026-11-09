#include "mining.h"
#include <stdlib.h>

typedef struct {IDs items;int64_t weight;} Pattern;
typedef struct {Pattern *values;int count;} PatternBase;
typedef struct {int item,parent,child,next;int64_t count;} Node;
typedef struct {Node *nodes;int count,capacity;IDs header;int64_t supports[MAX_ITEMS];} Tree;
typedef struct {Tree *tree;Itemset suffix;} Frame;
static int add_node(Tree *tree,int item,int parent){if(tree->count==tree->capacity){tree->capacity=tree->capacity?tree->capacity*2:64;Node *grown=realloc(tree->nodes,(size_t)tree->capacity*sizeof *grown);if(!grown)exit(1);tree->nodes=grown;}int index=tree->count++;tree->nodes[index]=(Node){.item=item,.parent=parent,.child=-1,.next=-1};return index;}
static Tree *build_tree(const PatternBase *base,int64_t minimum,int item_count){
 Tree *t=calloc(1,sizeof *t);if(!t)exit(1);add_node(t,-1,-1);
 for(int j=0;j<base->count;j++)for(int k=0;k<base->values[j].items.count;k++)t->supports[base->values[j].items.values[k]]+=base->values[j].weight;
 for(int i=0;i<item_count;i++)if(t->supports[i]>=minimum)t->header.values[t->header.count++]=i;
 for(int j=1;j<t->header.count;j++){int value=t->header.values[j],k=j;while(k>0){int prev=t->header.values[k-1];if(t->supports[prev]>t->supports[value]||(t->supports[prev]==t->supports[value]&&prev<value))break;t->header.values[k]=prev;k--;}t->header.values[k]=value;}
 for(int j=0;j<base->count;j++){
  Pattern p=base->values[j];Mask present={0};for(int k=0;k<p.items.count;k++)mask_add(&present,p.items.values[k]);int node=0;
  for(int k=0;k<t->header.count;k++){int item=t->header.values[k];if(!mask_has(present,item))continue;int child=t->nodes[node].child;while(child!=-1&&t->nodes[child].item!=item)child=t->nodes[child].next;if(child==-1){child=add_node(t,item,node);t->nodes[child].next=t->nodes[node].child;t->nodes[node].child=child;}t->nodes[child].count+=p.weight;node=child;}
 }
 return t;
}
static PatternBase conditional_base(const Tree *t,int item){
 PatternBase base={0};for(int j=1;j<t->count;j++)if(t->nodes[j].item==item)base.count++;base.values=calloc((size_t)base.count,sizeof *base.values);if(base.count&&!base.values)exit(1);int position=0;
 for(int j=1;j<t->count;j++)if(t->nodes[j].item==item){Pattern *p=&base.values[position++];p->weight=t->nodes[j].count;for(int parent=t->nodes[j].parent;parent!=0;parent=t->nodes[parent].parent)p->items.values[p->items.count++]=t->nodes[parent].item;for(int i=0,k=p->items.count-1;i<k;i++,k--){int value=p->items.values[i];p->items.values[i]=p->items.values[k];p->items.values[k]=value;}}
 return base;
}
static int compare_entries(const void *left,const void *right){const Entry *a=left,*b=right;return compare_sized(a->set,b->set);}
Growth fp_growth(const BasketList *baskets,int64_t minimum,int maximum,int item_count){
 PatternBase base={.count=baskets->count};base.values=calloc((size_t)base.count,sizeof *base.values);if(base.count&&!base.values)exit(1);for(int j=0;j<base.count;j++){base.values[j].weight=1;for(int i=0;i<item_count;i++)if(mask_has(baskets->values[j]->items,i))base.values[j].items.values[base.values[j].items.count++]=i;}
 Tree *tree=build_tree(&base,minimum,item_count);free(base.values);Growth result={.header=tree->header.count,.nodes=tree->count-1};int capacity=64,count=1;Frame *stack=malloc((size_t)capacity*sizeof *stack);if(!stack)exit(1);stack[0]=(Frame){.tree=tree};
 while(count){Frame frame=stack[--count];Tree *current=frame.tree;
  for(int j=current->header.count-1;j>=0;j--){int item=current->header.values[j];Itemset singleton={.size=1,.ids={item}},set=set_union(frame.suffix,singleton);append_entry(&result.entries,(Entry){set,current->supports[item]});
   if(set.size<maximum){PatternBase conditional=conditional_base(current,item);Tree *sub=build_tree(&conditional,minimum,item_count);free(conditional.values);if(sub->count>1){if(count==capacity){capacity*=2;Frame *grown=realloc(stack,(size_t)capacity*sizeof *grown);if(!grown)exit(1);stack=grown;}stack[count++]=(Frame){sub,set};result.trees++;result.conditional_nodes+=sub->count-1;}else{free(sub->nodes);free(sub);}}
  }
  free(current->nodes);free(current);
 }
 free(stack);if(result.entries.count>1)qsort(result.entries.values,(size_t)result.entries.count,sizeof *result.entries.values,compare_entries);return result;
}
