#include "mining.h"
#include <stdlib.h>
#include <string.h>

Records read_records(const char *name){
 char path[128],line[256];snprintf(path,sizeof path,"input/%s",name);FILE *file=fopen(path,"r");if(!file)exit(1);Records rows={0};int capacity=0;fgets(line,sizeof line,file);
 while(fgets(line,sizeof line,file)){if(rows.count==capacity){capacity=capacity?capacity*2:64;Record *grown=realloc(rows.rows,(size_t)capacity*sizeof *grown);if(!grown)exit(1);rows.rows=grown;}Record *row=&rows.rows[rows.count++];memset(row,0,sizeof *row);int field=0;for(char *token=strtok(line,",\n");token;token=strtok(NULL,",\n"))strcpy(row->fields[field++],token);}
 fclose(file);return rows;
}
void mask_add(Mask *mask,int item){mask->words[item/64]|=UINT64_C(1)<<(item%64);}
bool mask_has(Mask mask,int item){return (mask.words[item/64]&(UINT64_C(1)<<(item%64)))!=0;}
Mask extended_basket(const Basket *b,const Dataset *d){Mask result=b->items;for(int j=0;j<d->product_ids.count;j++){int i=d->product_ids.values[j];if(mask_has(b->items,i))mask_add(&result,d->taxonomy[i]);}return result;}
bool contains(Mask items,Itemset set){for(int j=0;j<set.size;j++)if(!mask_has(items,set.ids[j]))return false;return true;}
int64_t support_count(const BasketList *baskets,Itemset set,bool extended){int64_t count=0;for(int j=0;j<baskets->count;j++){Basket *b=baskets->values[j];count+=contains(extended?b->extended:b->items,set);}return count;}
int compare_itemsets(Itemset a,Itemset b){int length=a.size<b.size?a.size:b.size;for(int j=0;j<length;j++)if(a.ids[j]!=b.ids[j])return a.ids[j]<b.ids[j]?-1:1;return (a.size>b.size)-(a.size<b.size);}
int compare_sized(Itemset a,Itemset b){return a.size==b.size?compare_itemsets(a,b):(a.size>b.size)-(a.size<b.size);}
bool subset(Itemset a,Itemset b){int j=0;for(int k=0;k<b.size;k++)if(j<a.size&&a.ids[j]==b.ids[k])j++;return j==a.size;}
Itemset set_union(Itemset a,Itemset b){Itemset out={0};int i=0,j=0;while(i<a.size||j<b.size){int v;if(j==b.size||(i<a.size&&a.ids[i]<b.ids[j]))v=a.ids[i++];else v=b.ids[j++];if(!out.size||out.ids[out.size-1]!=v)out.ids[out.size++]=v;}return out;}
Itemset select_items(Itemset set,unsigned mask){Itemset out={0};for(int j=0;j<set.size;j++)if(mask&(1u<<j))out.ids[out.size++]=set.ids[j];return out;}
Itemset remove_item(Itemset set,int index){Itemset out={0};for(int j=0;j<set.size;j++)if(j!=index)out.ids[out.size++]=set.ids[j];return out;}
void append_entry(Entries *entries,Entry entry){if(entries->count==entries->capacity){entries->capacity=entries->capacity?entries->capacity*2:64;Entry *grown=realloc(entries->values,(size_t)entries->capacity*sizeof *grown);if(!grown)exit(1);entries->values=grown;}entries->values[entries->count++]=entry;}
int64_t entry_count(const Entries *entries,Itemset set){int low=0,high=entries->count;while(low<high){int middle=low+(high-low)/2,c=compare_sized(entries->values[middle].set,set);if(c<0)low=middle+1;else high=middle;}return low<entries->count&&!compare_sized(entries->values[low].set,set)?entries->values[low].count:0;}
