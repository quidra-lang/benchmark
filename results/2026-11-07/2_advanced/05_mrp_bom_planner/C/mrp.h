#ifndef MRP_H
#define MRP_H
#include <stdbool.h>
#include <stdint.h>
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { char **data; int count,capacity; } Strings;
typedef struct { char *data; size_t length,capacity; } Text;
typedef enum { LFL,FOQ,POQ,MIN } LotRule;
typedef struct {
    char id[9],description[41]; int lead; LotRule rule; int64_t a,b,safety,on_hand,material,labor;
    int children[100],parents[100],child_count,parent_count,operations[10],operation_count,code,cumulative;
    int64_t standard_material,standard_labor,standard_total,usage,value; char abc;
} Item;
typedef struct { int parent,child; int64_t quantity,scrap; } Link;
typedef struct { char id[9],description[41]; int64_t minutes,efficiency,available; } WorkCenter;
typedef struct { int item,number,center; int64_t setup,run; } Operation;
typedef struct { int item,week,line; int64_t quantity; } ScheduleRow;
typedef struct { char id[9]; int item,week,line; int64_t quantity; } Inquiry;
typedef struct {
    Item items[100]; int item_count; Link links[300]; int link_count;
    WorkCenter centers[20]; int center_count; Operation operations[200]; int operation_count;
    ScheduleRow mps[500],receipts[200]; int mps_count,receipt_count; Inquiry inquiries[50]; int inquiry_count;
    int horizon,peg[5],peg_count,order[100],item_order[100],center_order[20]; int64_t tree_quantity,scheduled[100][27]; Strings errors;
} Model;

void *allocate(size_t size);
void *resize(void *pointer,size_t size);
char *copy_text(const char *text);
char *format(const char *pattern,...);
void append_text(Text *text,const char *part);
void add_string(Strings *strings,const char *text);
Strings split(const char *text,char separator);
Strings read_lines(const char *name);
char *join(Strings strings,const char *separator);
int64_t integer(const char *text);
void record_error(Model *model,const char *file,int line,const char *message);
int find_item(const Model *model,const char *id);
int find_center(const Model *model,const char *id);
void read_items(Model *model);
char *lot_label(const Item *item);
int64_t need(const Link *link,int64_t quantity);
void read_bom(Model *model);
void compute_structure(Model *model);
int64_t lot_size(const Item *item,int week,int64_t projected,const int64_t *receipts,const int64_t *gross,int horizon);
void read_centers(Model *model);
void read_routings(Model *model);
int operation_week(int receipt,int lead,int index,int count);
void level_loads(const int64_t *loads,int64_t available,int horizon,int64_t *leveled);
void standard_costs(Model *model);
void abc_classes(Model *model);
char *money(int64_t cents);
int64_t percentage(int64_t part,int64_t whole);
char *table_row(const char *label,const int64_t *values,int count,int width);
void write_report(const char *name,Strings lines);
#endif
