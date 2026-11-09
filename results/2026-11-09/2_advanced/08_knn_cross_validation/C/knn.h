#ifndef KNN_H
#define KNN_H

#include <stdbool.h>
#include <stdio.h>

#define MAX_ROWS 300
#define MAX_TEST 100
#define MAX_FEATURES 8
#define MAX_CLASSES 300

typedef enum {STANDARD,MINMAX} ScalingMethod;
typedef enum {SQUARED_EUCLIDEAN,MANHATTAN,CHEBYSHEV,COSINE} Metric;
typedef enum {UNIFORM,DISTANCE} Weighting;
typedef struct {int *values,count,capacity;} Integers;
typedef struct {char id[9],label[17];double values[MAX_FEATURES],target;int label_index,index;bool has_target;} Row;
typedef struct {Row *values[MAX_ROWS];int count;} Rows;
typedef struct {int values[MAX_FEATURES],count;} Features;
typedef struct {
 ScalingMethod scalings[2];int scaling_count,k[25],k_count;Metric metrics[4];int metric_count;Weighting weightings[2];int weighting_count;
 int folds,edit_k,top;Integers curve;double bins[99];int bin_count;
} Settings;
typedef struct {
 char feature_names[MAX_FEATURES][17],labels[MAX_CLASSES][17];int feature_count,label_count;
 Row train[MAX_ROWS],test[MAX_TEST];Rows training,testing;Settings settings;
} Dataset;
typedef struct {double centers[MAX_FEATURES],scales[MAX_FEATURES];} Scaling;
typedef struct {int k;Metric metric;Weighting weighting;ScalingMethod scaling;} Model;
typedef struct {Row *row;double distance;} Neighbor;
typedef struct {int label,runner;double share,runner_share,estimate;} Prediction;
typedef struct {Neighbor *values;int queries,references;} Orders;
typedef struct {char **values;int count,capacity;} Lines;
extern const char *const scaling_names[2],*const metric_names[4],*const weighting_names[2];
void read_dataset(Dataset *data);
Scaling compute_scaling(const Rows *rows,ScalingMethod method,int dimension);
void transform(Scaling scaling,const Row *row,Features features,double *vector);
double distance(const double *a,const double *b,int count,Metric metric);
void sort_neighbors(Neighbor *order,int count);
void neighbor_order(const double *query,const Rows *rows,const double *vectors,int width,Metric metric,Neighbor *order);
Prediction predict_order(const Neighbor *order,int count,int k,Weighting weighting);
const char *model_notation(Model model);
void stratified(const Rows *rows,int folds,int *assignment);
Rows training_rows(const Rows *rows,const int *assignment,int excluded_fold);
Orders neighbor_orders(const Rows *training,const Rows *queries,ScalingMethod scaling,Metric metric,Features features,int dimension);
void predict_rows(Model model,const Rows *training,const Rows *queries,Features features,int dimension,Prediction *predictions);
double rmse(const double *errors,int count);
double mae(const double *errors,int count);
double r_squared(const double *errors,const double *targets,int count);
const char *fixed(double value,int places);
const char *real(double value);
double four(double value);
const char *ratio(int numerator,int denominator);
const char *fraction_metric(int numerator,int denominator);
void add_line(Lines *lines,const char *format,...);
void append_lines(Lines *to,const Lines *from);
void append_part(Lines *to,const Lines *part);
void write_report(const char *name,const Lines *lines);

#endif
