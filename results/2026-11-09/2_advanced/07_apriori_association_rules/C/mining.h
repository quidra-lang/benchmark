#ifndef MINING_H
#define MINING_H

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

#define MAX_ITEMS 72
#define MAX_BASKETS 2000
#define MAX_CUSTOMERS 500

typedef struct {int64_t n,d;} Fraction;
typedef struct {int size,ids[5];} Itemset;
typedef struct {int count,values[MAX_ITEMS];} IDs;
typedef struct {uint64_t words[2];} Mask;
typedef struct {char fields[4][33];} Record;
typedef struct {Record *rows;int count;} Records;
typedef struct {char name[17],category[13];int64_t price;} Product;
typedef struct {char id[10],customer[9];int day;int64_t counts[MAX_ITEMS];Mask items,extended;} Basket;
typedef struct {Basket *values[MAX_BASKETS];int count;} BasketList;
typedef struct {char **values;int count,capacity;} Lines;
typedef struct {int64_t minimum,category_minimum,sequence_minimum,train_minimum,test_minimum,negative_expected;int max_size,split,top,matrix;Fraction confidence,lift,group_lift,negative_lift,trend;} Params;
typedef struct {
 Params params;char names[MAX_ITEMS][17];int item_count,category_count;Product products[MAX_ITEMS];IDs product_ids,category_ids;int taxonomy[MAX_ITEMS];
 Basket transactions[MAX_BASKETS];int transaction_count;BasketList baskets,train,test;Lines errors;
 int item_rows,transaction_rows,adopted,duplicates,empty;
} Dataset;
typedef struct {Itemset set;int64_t count;} Entry;
typedef struct {Entry *values;int count,capacity;} Entries;
typedef struct {Itemset *values;int count,capacity,joined,excluded,pruned;} Candidates;
typedef struct {int size,joined,excluded,pruned,counted;Entries frequent;} Level;
typedef struct {Level levels[5];int level_count;Entries entries;int64_t total;} Apriori;
typedef struct {int header,nodes,trees,conditional_nodes;Entries entries;} Growth;
typedef struct {Itemset set,x,y;int64_t count;Fraction support,confidence,lift,leverage,conviction,improvement;bool infinite;int rank;} Rule;
typedef struct {Rule *values;int count,capacity,generated,productive;} RuleSet;
Records read_records(const char *name);
void mask_add(Mask *mask,int item);
bool mask_has(Mask mask,int item);
Mask extended_basket(const Basket *basket,const Dataset *data);
bool contains(Mask items,Itemset set);
int64_t support_count(const BasketList *baskets,Itemset set,bool extended);
int compare_itemsets(Itemset a,Itemset b);
int compare_sized(Itemset a,Itemset b);
bool subset(Itemset a,Itemset b);
Itemset set_union(Itemset a,Itemset b);
Itemset select_items(Itemset set,unsigned mask);
Itemset remove_item(Itemset set,int index);
void append_entry(Entries *entries,Entry entry);
int64_t entry_count(const Entries *entries,Itemset set);
Candidates generate_candidates(const Entries *previous,int size,const Dataset *data,bool exclude);
Entries count_candidates(const Candidates *candidates,const BasketList *baskets,int64_t minimum,bool extended);
Growth fp_growth(const BasketList *baskets,int64_t minimum,int maximum,int item_count);
Fraction fraction(int64_t numerator,int64_t denominator);
int fraction_compare(Fraction a,Fraction b);
Fraction fraction_subtract(Fraction a,Fraction b);
Fraction lift_of(int64_t total,int64_t together,int64_t first,int64_t second);
bool meets_thresholds(Fraction confidence,Fraction lift,const Params *params);
Rule rule_metrics(Itemset set,Itemset x,Itemset y,int64_t count,int64_t total,int64_t nx,int64_t ny);
void append_rule(RuleSet *rules,Rule rule);
int compare_rules(const void *left,const void *right);
const char *fraction_text(Fraction value);
const char *percentage(int64_t part,int64_t whole);
const char *money(int64_t cents);
const char *ids_text(const int *ids,int count,const Dataset *data);
const char *itemset_text(Itemset set,const Dataset *data);
const char *rule_arrow(Rule rule,const Dataset *data);
void add_line(Lines *lines,const char *format,...);
void append_lines(Lines *to,const Lines *from);
Lines rules_csv(const RuleSet *rules,const Dataset *data);
void write_report(const char *name,const Lines *lines);

#endif
