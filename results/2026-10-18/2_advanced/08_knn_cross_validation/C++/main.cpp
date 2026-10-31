#include "knn.hpp"
#include <algorithm>
#include <array>
#include <cmath>
#include <numeric>
#include <set>
#include <sstream>
#include <utility>

template<class... Args> static std::string line(const Args&... args) {
    std::ostringstream out; bool first = true; ((out << (first ? "" : " ") << args,first = false),...); return out.str();
}
static std::string join(const Lines& values, const std::string& separator = " ") {
    std::string result; for (const std::string& value : values) { if (!result.empty()) result += separator; result += value; } return result;
}
static void append(Lines& target, const Lines& source) { target.insert(target.end(),source.begin(),source.end()); }
static Lines parts(const std::vector<Lines>& sections) {
    Lines result; for (const Lines& section : sections) { if (!result.empty()) result.push_back(""); append(result,section); } return result;
}
static int correctCount(const std::vector<Prediction>& predictions, const Rows& rows) {
    int count = 0; for (int j = 0; j < static_cast<int>(rows.size()); ++j) count += predictions[j].result.label == rows[j]->label; return count;
}
static Vector errors(const std::vector<Prediction>& predictions, const Rows& rows) {
    Vector result; for (int j = 0; j < static_cast<int>(rows.size()); ++j) result.push_back(predictions[j].estimate - *rows[j]->target); return result;
}
struct CrossValidation { Model model; std::vector<Prediction> predictions; std::vector<bool> hits; int correct = 0; double error = 0; };
static std::vector<CrossValidation> crossValidate(const std::vector<Model>& models, const Rows& rows, int count, const Indices& features) {
    std::vector<CrossValidation> results;
    std::vector<std::pair<std::string, std::string>> spaces;
    for (const Model& model : models) {
        results.push_back({model,std::vector<Prediction>(rows.size()),{}});
        std::pair<std::string, std::string> space{model.scaling,model.metric};
        if (std::find(spaces.begin(),spaces.end(),space) == spaces.end()) spaces.push_back(space);
    }
    for (const Indices& fold : stratifiedFolds(rows,count)) {
        Rows training = without(rows,fold), queries = selected(rows,fold);
        for (const auto& space : spaces) {
            std::vector<Order> orders = neighborOrders(training,queries,space.first,space.second,features);
            for (CrossValidation& result : results) if (result.model.scaling == space.first && result.model.metric == space.second)
                for (int j = 0; j < static_cast<int>(fold.size()); ++j) result.predictions[fold[j]] = predictionFromOrder(orders[j],result.model.k,result.model.weighting);
        }
    }
    for (CrossValidation& result : results) {
        for (int j = 0; j < static_cast<int>(rows.size()); ++j) { bool hit = result.predictions[j].result.label == rows[j]->label; result.hits.push_back(hit); result.correct += hit; }
        result.error = rmse(errors(result.predictions,rows));
    }
    return results;
}
static Indices indices(int count) { Indices result(count); std::iota(result.begin(),result.end(),0); return result; }
static int bestClassifier(const std::vector<CrossValidation>& results, Indices chosen = {}) {
    if (chosen.empty()) chosen = indices(static_cast<int>(results.size())); int best = chosen[0];
    for (int index : chosen) if (results[index].correct > results[best].correct) best = index; return best;
}
static int bestRegressor(const std::vector<CrossValidation>& results, Indices chosen = {}) {
    if (chosen.empty()) chosen = indices(static_cast<int>(results.size())); int best = chosen[0];
    for (int index : chosen) if (fourDecimal(results[index].error) < fourDecimal(results[best].error)) best = index; return best;
}
class ClassifierSpace {
    std::map<const Row*, Order> orders;
    Model model;
public:
    ClassifierSpace(const Model& model, const Rows& train, const Rows& test, const Indices& features) : model(model) {
        Rows queries = train; queries.insert(queries.end(),test.begin(),test.end());
        std::vector<Order> found = neighborOrders(train,queries,model.scaling,model.metric,features);
        for (int j = 0; j < static_cast<int>(queries.size()); ++j) orders[queries[j]] = found[j];
    }
    Order order(const Row* query, const Rows& rows) const {
        std::set<const Row*> included(rows.begin(),rows.end()); Order result;
        for (const Neighbor& neighbor : orders.at(query)) if (included.count(neighbor.row)) result.push_back(neighbor); return result;
    }
    Vote predict(const Row* query, const Rows& rows, int k) const {
        Order nearest = order(query,rows); nearest.resize(std::min<int>(k,nearest.size())); return vote(nearest,model.weighting);
    }
};

class Experiment {
    Dataset data;
    Settings s;
    Rows train, test, labelled, targeted;
    Lines labels;
    Indices features;
    std::vector<Model> grid;
    std::vector<Indices> folds;
    std::vector<CrossValidation> results;
    int classifier, regressor;
    std::vector<Prediction> testPredictions, testEstimates;
    std::string labelCounts(const Rows& rows) const {
        std::map<std::string, int> counts; for (const Row* row : rows) ++counts[row->label]; Lines fields;
        for (const std::string& label : labels) fields.push_back(line(label,counts[label])); return join(fields);
    }
    std::string names(const Indices& chosen) const { Lines result; for (int index : chosen) result.push_back(data.features[index]); return join(result); }
    std::string trainRatio(int correct) const { return ratio(correct,static_cast<int>(train.size())); }
    std::string summary(const CrossValidation& result, bool regression) const {
        return regression ? line(result.model.notation(),"rmse",fixed(result.error),"correct",trainRatio(result.correct)) : line(result.model.notation(),"correct",trainRatio(result.correct),"rmse",fixed(result.error));
    }
    Lines evaluation(const Rows& rows, const std::vector<Prediction>& predictions) const {
        int size = static_cast<int>(labels.size()); std::vector<Indices> matrix(size,Indices(size));
        for (int j = 0; j < static_cast<int>(rows.size()); ++j) {
            int truth = static_cast<int>(std::find(labels.begin(),labels.end(),rows[j]->label) - labels.begin());
            int predicted = static_cast<int>(std::find(labels.begin(),labels.end(),predictions[j].result.label) - labels.begin()); ++matrix[truth][predicted];
        }
        Lines lines{"true\\predicted " + join(labels)};
        for (int a = 0; a < size; ++a) { Lines cells{labels[a]}; for (int value : matrix[a]) cells.push_back(std::to_string(value)); lines.push_back(join(cells)); }
        std::array<double, 3> totals{}; std::array<int, 3> valued{};
        for (int c = 0; c < size; ++c) {
            int predicted = 0, actual = 0, hit = matrix[c][c];
            for (int j = 0; j < size; ++j) { predicted += matrix[j][c]; actual += matrix[c][j]; }
            const std::array<std::pair<int, int>, 3> metrics{{{hit,predicted},{hit,actual},{2 * hit,predicted + actual}}};
            for (int j = 0; j < 3; ++j) if (metrics[j].second) { totals[j] += static_cast<double>(metrics[j].first) / metrics[j].second; ++valued[j]; }
            lines.push_back(line("class",labels[c],"precision",fraction(hit,predicted),"recall",fraction(hit,actual),"f1",fraction(2 * hit,predicted + actual),"support",actual));
        }
        lines.push_back(line("macro precision",valued[0] ? fixed(totals[0] / valued[0]) : "-","recall",valued[1] ? fixed(totals[1] / valued[1]) : "-","f1",valued[2] ? fixed(totals[2] / valued[2]) : "-")); return lines;
    }
    Lines reliability(const Rows& rows, const std::vector<Prediction>& predictions) const {
        Vector lowers{0}; lowers.insert(lowers.end(),s.bins.begin(),s.bins.end()); Indices counts(lowers.size()), hits(lowers.size()); Vector shares(lowers.size());
        for (int j = 0; j < static_cast<int>(rows.size()); ++j) {
            int bin = 0; for (double bound : s.bins) bin += bound <= predictions[j].result.share;
            ++counts[bin]; hits[bin] += predictions[j].result.label == rows[j]->label; shares[bin] += predictions[j].result.share;
        }
        Lines lines;
        for (int j = 0; j < static_cast<int>(lowers.size()); ++j) lines.push_back(counts[j] ? line("bin",fixed(lowers[j],2),"rows",counts[j],"correct",ratio(hits[j],counts[j]),"share",fixed(shares[j] / counts[j])) : line("bin",fixed(lowers[j],2),"rows 0")); return lines;
    }
    std::vector<Prediction> labelledPredictions() const {
        std::vector<Prediction> result; for (int j = 0; j < static_cast<int>(test.size()); ++j) if (!test[j]->label.empty()) result.push_back(testPredictions[j]); return result;
    }
    std::vector<Lines> leaveOneOut() const {
        const Model& model = results[classifier].model; std::map<int, std::vector<Prediction>> byK; std::vector<Prediction> estimates;
        for (int j = 0; j < static_cast<int>(train.size()); ++j) {
            Rows others = without(train,{j}); Order order = neighborOrders(others,{train[j]},model.scaling,model.metric,features)[0];
            for (int k : s.ks) byK[k].push_back(predictionFromOrder(order,k,model.weighting));
            estimates.push_back(predictRows(results[regressor].model,others,{train[j]},features)[0]);
        }
        Indices failed; Rows errorsRows;
        const std::vector<Prediction>& predictions = byK.at(model.k);
        for (int j = 0; j < static_cast<int>(train.size()); ++j) if (predictions[j].result.label != train[j]->label) { failed.push_back(j); errorsRows.push_back(train[j]); }
        Lines classification{line("leave_one_out classifier",model.notation()),line("errors",trainRatio(static_cast<int>(failed.size()))),"class_errors " + labelCounts(errorsRows)};
        std::sort(failed.begin(),failed.end(),[&](int a, int b) { return train[a]->id < train[b]->id; });
        for (int j : failed) classification.push_back(line(train[j]->id,"true",train[j]->label,"predicted",predictions[j].result.label,"share",fixed(predictions[j].result.share)));
        Vector residuals = errors(estimates,train); Indices ranking = indices(static_cast<int>(train.size()));
        std::sort(ranking.begin(),ranking.end(),[&](int a, int b) { double x = fourDecimal(std::abs(residuals[a])), y = fourDecimal(std::abs(residuals[b])); return x != y ? x > y : train[a]->id < train[b]->id; });
        Lines regression{line("leave_one_out regressor",results[regressor].model.notation()),line("rmse",fixed(rmse(residuals)),"mae",fixed(mae(residuals))),line("largest",s.top,"residuals")};
        for (int j = 0; j < std::min<int>(s.top,ranking.size()); ++j) { int i = ranking[j]; regression.push_back(line(train[i]->id,"target",fixed(*train[i]->target),"estimate",fixed(estimates[i].estimate),"residual",fixed(residuals[i]))); }
        Lines perK{line("leave_one_out by k metric=" + model.metric,"weighting=" + model.weighting,"scaling=" + model.scaling)};
        for (int k : s.ks) perK.push_back(line("k=" + std::to_string(k),"correct",trainRatio(correctCount(byK.at(k),train)),"rmse",fixed(rmse(errors(byK.at(k),train)))));
        return {classification,regression,perK};
    }
    Lines nested() const {
        Lines lines{line("nested_cross_validation folds",s.folds)}; Vector estimates(train.size()); int correct = 0;
        for (int f = 0; f < static_cast<int>(folds.size()); ++f) {
            Rows inner = without(train,folds[f]), queries = selected(train,folds[f]); std::vector<CrossValidation> innerResults = crossValidate(grid,inner,s.folds,features);
            const CrossValidation& c = innerResults[bestClassifier(innerResults)]; const CrossValidation& r = innerResults[bestRegressor(innerResults)];
            std::vector<Prediction> predictions = predictRows(c.model,inner,queries,features), predictedEstimates = predictRows(r.model,inner,queries,features);
            int hits = correctCount(predictions,queries); correct += hits;
            for (int j = 0; j < static_cast<int>(queries.size()); ++j) estimates[folds[f][j]] = predictedEstimates[j].estimate;
            lines.push_back(line("fold",f + 1,"classifier",c.model.notation(),"inner",fixed(static_cast<double>(c.correct) / inner.size()),"outer",ratio(hits,static_cast<int>(queries.size()))));
            lines.push_back(line("fold",f + 1,"regressor",r.model.notation(),"inner",fixed(r.error),"outer",fixed(rmse(errors(predictedEstimates,queries)))));
        }
        Vector residuals; for (int j = 0; j < static_cast<int>(train.size()); ++j) residuals.push_back(estimates[j] - *train[j]->target);
        lines.push_back(line("nested accuracy",trainRatio(correct),"rmse",fixed(rmse(residuals)))); return lines;
    }
    Lines featureSelection() const {
        const Model& model = results[classifier].model; Indices current = features, chosen = features; int chosenCount = results[classifier].correct, step = 0;
        Lines lines{line("feature_selection",model.notation()),line("start features",names(current),"correct",trainRatio(chosenCount))};
        while (current.size() >= 3) {
            int remove = current[0], maximum = -1; Lines candidates;
            for (int feature : current) {
                Indices remaining; for (int other : current) if (other != feature) remaining.push_back(other);
                int count = crossValidate({model},train,s.folds,remaining)[0].correct; candidates.push_back(line(data.features[feature],count));
                if (count > maximum) { maximum = count; remove = feature; }
            }
            current.erase(std::find(current.begin(),current.end(),remove));
            lines.push_back(line("step",++step,"remove",data.features[remove],"correct",trainRatio(maximum),"candidates",join(candidates)));
            if (maximum >= chosenCount) { chosen = current; chosenCount = maximum; }
        }
        int testCorrect = correctCount(predictRows(model,train,labelled,chosen),labelled);
        lines.push_back(line("selected features",names(chosen),"correct",trainRatio(chosenCount))); lines.push_back(line("selected test",ratio(testCorrect,static_cast<int>(labelled.size())))); return lines;
    }
    Lines metricsReport() const {
        const CrossValidation& c = results[classifier]; const CrossValidation& r = results[regressor];
        std::vector<Lines> sections{{line("data train",train.size(),"test",test.size(),"labelled",labelled.size(),"targets",targeted.size(),"features",features.size(),"classes",labels.size()),"classes " + labelCounts(train)}};
        for (const std::string& method : s.scalings) {
            Scaling scaling = computeScaling(train,method); Lines lines{line("scaling",method)};
            for (int feature : features) lines.push_back(line(data.features[feature],"center",fixed(scaling.centers[feature],6),"scale",fixed(scaling.scales[feature],6))); sections.push_back(lines);
        }
        Lines foldLines{line("folds",s.folds)};
        for (int f = 0; f < static_cast<int>(folds.size()); ++f) foldLines.push_back(line("fold",f + 1,"size",folds[f].size(),labelCounts(selected(train,folds[f])))); sections.push_back(foldLines);
        sections.push_back({line("grid",grid.size()),"best_classifier " + summary(c,false),"best_regressor " + summary(r,true)});
        for (bool regression : {false,true}) {
            Indices ranking = indices(static_cast<int>(results.size()));
            std::stable_sort(ranking.begin(),ranking.end(),[&](int a, int b) { return regression ? fourDecimal(results[a].error) < fourDecimal(results[b].error) : results[a].correct > results[b].correct; });
            Lines lines{line("top",s.top,"by",regression ? "rmse" : "accuracy")};
            for (int j = 0; j < std::min<int>(s.top,ranking.size()); ++j) lines.push_back(line(j + 1,summary(results[ranking[j]],regression))); sections.push_back(lines);
        }
        for (int item = 0; item < 4; ++item) {
            std::string name = item == 0 ? "k" : item == 1 ? "metric" : item == 2 ? "weighting" : "scaling";
            Lines values = item == 1 ? s.metrics : item == 2 ? s.weightings : item == 3 ? s.scalings : Lines{};
            if (item == 0) for (int k : s.ks) values.push_back(std::to_string(k));
            Lines lines{"best per " + name};
            for (const std::string& value : values) {
                Indices chosen;
                for (int j = 0; j < static_cast<int>(results.size()); ++j) {
                    const Model& model = results[j].model; std::string current = item == 0 ? std::to_string(model.k) : item == 1 ? model.metric : item == 2 ? model.weighting : model.scaling;
                    if (current == value) chosen.push_back(j);
                }
                const CrossValidation& bestC = results[bestClassifier(results,chosen)]; const CrossValidation& bestR = results[bestRegressor(results,chosen)];
                lines.push_back(line(name + "=" + value,"classifier",bestC.model.notation(),"accuracy",fixed(static_cast<double>(bestC.correct) / train.size()),"regressor",bestR.model.notation(),"rmse",fixed(bestR.error)));
            }
            sections.push_back(lines);
        }
        Lines classifierFolds{"classifier folds"}, regressorFolds{"regressor folds"};
        for (int f = 0; f < static_cast<int>(folds.size()); ++f) {
            int correct = 0; Vector residuals;
            for (int index : folds[f]) { correct += c.hits[index]; residuals.push_back(r.predictions[index].estimate - *train[index]->target); }
            classifierFolds.push_back(line("fold",f + 1,"correct",ratio(correct,static_cast<int>(folds[f].size()))));
            regressorFolds.push_back(line("fold",f + 1,"size",folds[f].size(),"rmse",fixed(rmse(residuals))));
        }
        sections.push_back(classifierFolds); sections.push_back(regressorFolds);
        Lines cvClasses{"cross_validation classes"}; append(cvClasses,evaluation(train,c.predictions)); sections.push_back(cvClasses);
        Lines cvReliability{"cross_validation reliability"}; append(cvReliability,reliability(train,c.predictions)); sections.push_back(cvReliability);
        Lines mcnemar{"mcnemar"};
        for (const std::string& metric : s.metrics) {
            Indices chosen; for (int j = 0; j < static_cast<int>(results.size()); ++j) if (results[j].model.metric == metric) chosen.push_back(j);
            const CrossValidation& comparison = results[bestClassifier(results,chosen)]; int b = 0, d = 0;
            for (int j = 0; j < static_cast<int>(train.size()); ++j) { b += c.hits[j] && !comparison.hits[j]; d += comparison.hits[j] && !c.hits[j]; }
            int adjusted = std::max(0,std::abs(b - d) - 1), numerator = adjusted * adjusted;
            mcnemar.push_back(line(comparison.model.notation(),"b",b,"c",d,"statistic",b + d ? fraction(numerator,b + d) : "0/1 0.0000","significant",1000 * numerator > 3841 * (b + d) ? "yes" : "no"));
        }
        sections.push_back(mcnemar);
        for (const Lines& section : leaveOneOut()) sections.push_back(section);
        sections.push_back(nested()); sections.push_back(featureSelection());
        std::vector<Prediction> labelledResults = labelledPredictions();
        Lines classification{line("test classification",c.model.notation()),line("labelled",labelled.size(),"correct",ratio(correctCount(labelledResults,labelled),static_cast<int>(labelled.size())))};
        append(classification,evaluation(labelled,labelledResults)); sections.push_back(classification);
        Lines testReliability{"test reliability"}; append(testReliability,reliability(labelled,labelledResults)); sections.push_back(testReliability);
        Indices uncertainty = indices(static_cast<int>(test.size())); Vector margins;
        for (const Prediction& prediction : testPredictions) margins.push_back(prediction.result.share - prediction.result.runnerShare);
        std::stable_sort(uncertainty.begin(),uncertainty.end(),[&](int a, int b) { return fourDecimal(margins[a]) < fourDecimal(margins[b]); });
        Lines uncertain{line("uncertain",s.top,"test rows")};
        for (int j = 0; j < std::min<int>(s.top,uncertainty.size()); ++j) {
            int i = uncertainty[j]; const Vote& v = testPredictions[i].result;
            uncertain.push_back(line(test[i]->id,"predicted",v.label,"share",fixed(v.share),"runner_up",v.runner.empty() ? "-" : v.runner,"share",fixed(v.runnerShare),"margin",fixed(margins[i]),"true",test[i]->label.empty() ? "-" : test[i]->label));
        }
        sections.push_back(uncertain);
        Vector residuals, targets; std::map<std::string, Vector> classErrors;
        for (int j = 0; j < static_cast<int>(test.size()); ++j) if (test[j]->target) {
            double error = testEstimates[j].estimate - *test[j]->target; residuals.push_back(error); targets.push_back(*test[j]->target); classErrors[test[j]->label].push_back(error);
        }
        Lines regression{line("test regression",r.model.notation()),line("targets",targets.size(),"rmse",fixed(rmse(residuals)),"mae",fixed(mae(residuals)),"r2",fixed(rSquared(residuals,targets)))};
        for (const std::string& label : labels) regression.push_back(line("class",label,"targets",classErrors[label].size(),"rmse",classErrors[label].empty() ? "-" : fixed(rmse(classErrors[label])))); sections.push_back(regression);
        Lines mistakes{"misclassified test rows"}; int count = 0;
        for (int j = 0; j < static_cast<int>(test.size()); ++j) if (!test[j]->label.empty() && testPredictions[j].result.label != test[j]->label) {
            ++count; const Vote& v = testPredictions[j].result; mistakes.push_back(line(test[j]->id,"true",test[j]->label,"predicted",v.label,"share",fixed(v.share)));
            for (const Neighbor& neighbor : testPredictions[j].neighbors) mistakes.push_back("  " + line(neighbor.row->id,neighbor.row->label,fixed(neighbor.distance)));
        }
        mistakes.push_back(line("count",count)); sections.push_back(mistakes); return parts(sections);
    }
    Lines learningCurve() const {
        Lines lines{"n,train_size,correct,accuracy,rmse"};
        for (int limit : s.curve) {
            Rows chosen; std::map<std::string, int> taken;
            for (const Row* row : train) if (taken[row->label] < limit) { ++taken[row->label]; chosen.push_back(row); }
            int correct = correctCount(predictRows(results[classifier].model,chosen,labelled,features),labelled);
            double error = rmse(errors(predictRows(results[regressor].model,chosen,targeted,features),targeted));
            lines.push_back(join({std::to_string(limit),std::to_string(chosen.size()),std::to_string(correct),fixed(static_cast<double>(correct) / labelled.size()),fixed(error)},","));
        }
        return lines;
    }
    static std::pair<Rows, int> condense(const ClassifierSpace& space, const Rows& rows) {
        Rows store{rows[0]}; std::set<const Row*> stored{rows[0]}; int scans = 0;
        while (true) {
            ++scans; bool added = false;
            for (const Row* row : rows) if (!stored.count(row) && space.order(row,store)[0].row->label != row->label) { store.push_back(row); stored.insert(row); added = true; }
            if (!added) break;
        }
        std::sort(store.begin(),store.end(),[](const Row* a, const Row* b) { return a->id < b->id; }); return {store,scans};
    }
    static Lines idLines(const Rows& rows) {
        Lines lines;
        for (int j = 0; j < static_cast<int>(rows.size()); j += 10) { Lines ids; for (int k = j; k < std::min<int>(j + 10,rows.size()); ++k) ids.push_back(rows[k]->id); lines.push_back(join(ids)); } return lines;
    }
    Lines prototypes() const {
        const Model& model = results[classifier].model; ClassifierSpace space(model,train,test,features);
        Rows ordered = train; std::sort(ordered.begin(),ordered.end(),[](const Row* a, const Row* b) { return a->id < b->id; }); Rows edited = ordered;
        Lines editing{line("editing k=" + std::to_string(s.editK))}; int pass = 0;
        while (true) {
            std::vector<std::pair<const Row*, Vote>> removals;
            for (const Row* row : edited) {
                Rows others; for (const Row* other : edited) if (other != row) others.push_back(other);
                Vote result = space.predict(row,others,s.editK); if (result.label != row->label) removals.push_back({row,result});
            }
            editing.push_back(line("pass",++pass,"removed",removals.size()));
            std::set<const Row*> removed;
            for (const auto& removal : removals) { removed.insert(removal.first); editing.push_back("  " + line(removal.first->id,"true",removal.first->label,"predicted",removal.second.label,"share",fixed(removal.second.share))); }
            if (removals.empty()) break;
            edited.erase(std::remove_if(edited.begin(),edited.end(),[&](const Row* row) { return removed.count(row) != 0; }),edited.end());
        }
        editing.push_back(line("edited size",edited.size(),"removed",train.size() - edited.size()));
        auto condensed = condense(space,ordered), editedCondensed = condense(space,edited);
        std::vector<Lines> sections{{line("space",model.notation())},editing,{line("condensing original scans",condensed.second,"size",condensed.first.size()),line("condensing edited scans",editedCondensed.second,"size",editedCondensed.first.size())}};
        const std::array<Rows, 4> sets{ordered,edited,condensed.first,editedCondensed.first}; const Lines setNames{"original","edited","condensed","edited_condensed"}; Lines setLines;
        for (int j = 0; j < 4; ++j) {
            int knn = 0, one = 0;
            for (const Row* row : labelled) { knn += space.predict(row,sets[j],model.k).label == row->label; one += space.order(row,sets[j])[0].row->label == row->label; }
            setLines.push_back(line("set",setNames[j],"size",sets[j].size(),labelCounts(sets[j]),"knn",ratio(knn,static_cast<int>(labelled.size())),"1nn",ratio(one,static_cast<int>(labelled.size()))));
        }
        sections.push_back(setLines); Lines ids{"prototypes condensed"}; append(ids,idLines(condensed.first)); sections.push_back(ids); ids = {"prototypes edited_condensed"}; append(ids,idLines(editedCondensed.first)); sections.push_back(ids);
        Lines borders{"borders"}; int total = 0;
        for (const std::string& label : labels) {
            int count = 0, boundary = 0; double same = 0, other = 0;
            for (const Row* row : ordered) if (row->label == label) {
                ++count; Rows others; for (const Row* reference : ordered) if (reference != row) others.push_back(reference);
                Order order = space.order(row,others); boundary += order[0].row->label != label;
                same += std::find_if(order.begin(),order.end(),[&](const Neighbor& neighbor) { return neighbor.row->label == label; })->distance;
                other += std::find_if(order.begin(),order.end(),[&](const Neighbor& neighbor) { return neighbor.row->label != label; })->distance;
            }
            total += boundary; borders.push_back(line("class",label,"size",count,"border",boundary,"same",fixed(same / count),"other",fixed(other / count)));
        }
        borders.push_back(line("border total",trainRatio(total))); sections.push_back(borders);
        std::map<const Row*, int> occurrences; for (const Row* row : train) occurrences[row] = 0;
        for (const Prediction& prediction : testPredictions) for (const Neighbor& neighbor : prediction.neighbors) ++occurrences[neighbor.row];
        Rows ranked = ordered; std::stable_sort(ranked.begin(),ranked.end(),[&](const Row* a, const Row* b) { return occurrences[a] > occurrences[b]; });
        Lines hubs{line("hubs k=" + std::to_string(model.k),"queries",test.size())};
        for (int j = 0; j < std::min<int>(s.top,ranked.size()); ++j) hubs.push_back(line(ranked[j]->id,ranked[j]->label,occurrences[ranked[j]]));
        int anti = 0; for (const auto& occurrence : occurrences) anti += occurrence.second == 0;
        hubs.push_back(line("anti_hubs",anti)); sections.push_back(hubs); return parts(sections);
    }
public:
    explicit Experiment(Dataset input) : data(std::move(input)), s(data.settings) {
        for (const Row& row : data.train) train.push_back(&row);
        for (const Row& row : data.test) { test.push_back(&row); if (!row.label.empty()) labelled.push_back(&row); if (row.target) targeted.push_back(&row); }
        std::set<std::string> labelSet; for (const Row* row : train) labelSet.insert(row->label); labels = Lines(labelSet.begin(),labelSet.end()); features = indices(static_cast<int>(data.features.size()));
        for (int k : s.ks) for (const std::string& metric : s.metrics) for (const std::string& weighting : s.weightings) for (const std::string& scaling : s.scalings) grid.push_back({k,metric,weighting,scaling});
        folds = stratifiedFolds(train,s.folds); results = crossValidate(grid,train,s.folds,features); classifier = bestClassifier(results); regressor = bestRegressor(results);
        testPredictions = predictRows(results[classifier].model,train,test,features); testEstimates = predictRows(results[regressor].model,train,test,features);
    }
    void write() const {
        Lines gridLines{"k,metric,weighting,scaling,correct,accuracy,rmse"};
        for (const CrossValidation& result : results) { const Model& m = result.model; gridLines.push_back(join({std::to_string(m.k),m.metric,m.weighting,m.scaling,std::to_string(result.correct),fixed(static_cast<double>(result.correct) / train.size()),fixed(result.error)},",")); }
        Lines predictions{"id,label,vote_share,estimate"};
        for (int j = 0; j < static_cast<int>(test.size()); ++j) predictions.push_back(join({test[j]->id,testPredictions[j].result.label,fixed(testPredictions[j].result.share),fixed(testEstimates[j].estimate)},","));
        writeLines("cv_grid.csv",gridLines); writeLines("predictions.csv",predictions); writeLines("metrics.txt",metricsReport()); writeLines("learning_curve.csv",learningCurve()); writeLines("prototypes.txt",prototypes());
    }
};

int main() { Experiment experiment(readDataset()); experiment.write(); }
