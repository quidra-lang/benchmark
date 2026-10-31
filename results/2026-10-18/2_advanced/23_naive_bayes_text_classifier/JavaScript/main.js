'use strict';

const fs = require('node:fs');
const { tokenize } = require('./tokenizer');
const { compareText, buildVocabulary, encode } = require('./vocabulary');
const nb = require('./naive_bayes');
const rocchio = require('./rocchio');
const { real, rounded, proportion, metric, evaluate, evaluationLines } = require('./evaluation');

const models = ['multinomial', 'bernoulli', 'complement', 'rocchio', 'vote'];
const pairs = [];
for (let first = 0; first < 4; first++) for (let second = first + 1; second < 4; second++) pairs.push([first, second]);
const readLines = name => fs.readFileSync('input/' + name, 'ascii').split('\n').slice(0, -1);
const twoDecimal = value => Math.floor(value / 100) + '.' + String(value % 100).padStart(2, '0');
const alphaText = entry => entry.alpha === null ? '-' : twoDecimal(entry.alpha);
const classCountsText = (counts, classes) => classes.map((name, c) => name + ' ' + counts[c]).join(' ');

function hundredfold(text) {
    const [whole, fraction] = text.split('.');
    return Number(whole) * 100 + Number(fraction);
}

function readInput() {
    const values = new Map(readLines('params.txt').map(line => {
        const [key, ...fields] = line.split(' ');
        return [key, fields];
    }));
    const integer = key => Number(values.get(key)[0]);
    const settings = {
        alphas: values.get('ALPHAS').map(hundredfold), minimum: integer('MIN_DF'), features: integer('FEATURES'),
        kind: values.get('BIGRAMS')[0] === 'yes' ? 'bigrams' : 'unigrams', top: integer('TOP'),
        curve: values.get('CURVE').map(Number), sizes: values.get('SIZES').map(Number),
        thresholds: values.get('THRESHOLDS').map(hundredfold), lengths: values.get('LENGTHS').map(Number),
        iterations: integer('EM_ITERATIONS'), weight: hundredfold(values.get('EM_WEIGHT')[0]),
        bootstrap: Number(values.get('BOOTSTRAP')[0]), seed: Number(values.get('BOOTSTRAP')[1]),
    };
    const stopwords = new Set(readLines('stopwords.txt'));
    const trainingFields = readLines('train.txt').map(line => line.split('\t'));
    const classes = [...new Set(trainingFields.map(([name]) => name))].sort(compareText);
    const classIndex = new Map(classes.map((name, c) => [name, c]));
    const train = trainingFields.map(([name, text], i) => ({ number: i + 1, label: classIndex.get(name), tokens: tokenize(text, stopwords) }));
    const test = readLines('test.txt').map((line, order) => {
        const [id, name, text] = line.split('\t');
        return { id, order, label: name === '?' ? null : classIndex.get(name), tokens: tokenize(text, stopwords) };
    });
    const unlabelled = readLines('unlabelled.txt').map(text => ({ tokens: tokenize(text, stopwords) }));
    return { settings, classes, train, test, unlabelled };
}

function makeVocabulary(documents, data, kind = data.settings.kind, size = data.settings.features) {
    return buildVocabulary(documents, data.classes.length, data.settings.minimum, size, kind);
}

function fitModels(documents, vocabulary, selections, classCount) {
    const encoded = documents.map(document => encode(document, vocabulary));
    const counts = nb.trainingCounts(documents, encoded, classCount, vocabulary.terms.length);
    const trained = selections.slice(0, 3).map((entry, m) => nb.train(models[m], counts, entry.alpha));
    trained.push(rocchio.train(documents, encoded, vocabulary, classCount));
    return { vocabulary, counts, models: trained };
}

function majorityVote(predictions, classCount) {
    const votes = Array(classCount).fill(0);
    for (const prediction of predictions) votes[prediction.label]++;
    const maximum = Math.max(...votes);
    const label = predictions.find(prediction => votes[prediction.label] === maximum).label;
    return { label, score: maximum / 4 };
}

function predictRows(bundle, documents, includeVote = false) {
    return documents.map(document => {
        const encoded = encode(document, bundle.vocabulary);
        const predictions = bundle.models.map((model, m) => m < 3 ? nb.predict(model, encoded) : rocchio.predict(model, encoded));
        if (includeVote) predictions.push(majorityVote(predictions, bundle.counts.classes.length));
        return { document, encoded, predictions };
    });
}

function evaluateRows(rows, model, classCount) {
    return evaluate(rows.map(row => row.document.label), rows.map(row => row.predictions[model].label), classCount);
}

function crossValidation(data) {
    const entries = [];
    for (let m = 0; m < 3; m++) {
        for (const alpha of data.settings.alphas) entries.push({ model: m, alpha, predictions: Array(data.train.length), correctByFold: Array(5).fill(0) });
    }
    entries.push({ model: 3, alpha: null, predictions: Array(data.train.length), correctByFold: Array(5).fill(0) });
    const folds = [];
    for (let f = 0; f < 5; f++) {
        const training = data.train.filter(document => (document.number - 1) % 5 !== f);
        const validation = data.train.filter(document => (document.number - 1) % 5 === f);
        const vocabulary = makeVocabulary(training, data);
        const encodedTraining = training.map(document => encode(document, vocabulary));
        const encodedValidation = validation.map(document => encode(document, vocabulary));
        const counts = nb.trainingCounts(training, encodedTraining, data.classes.length, vocabulary.terms.length);
        folds.push({ train: training.length, validate: validation.length, candidates: vocabulary.candidateCount, vocabulary: vocabulary.terms.length });
        for (const entry of entries) {
            const model = entry.model === 3 ? rocchio.train(training, encodedTraining, vocabulary, data.classes.length)
                : nb.train(models[entry.model], counts, entry.alpha);
            for (let i = 0; i < validation.length; i++) {
                const prediction = entry.model === 3 ? rocchio.predict(model, encodedValidation[i]) : nb.predict(model, encodedValidation[i]);
                entry.predictions[validation[i].number - 1] = prediction.label;
                if (prediction.label === validation[i].label) entry.correctByFold[f]++;
            }
        }
    }
    const actual = data.train.map(document => document.label);
    for (const entry of entries) entry.evaluation = evaluate(actual, entry.predictions, data.classes.length);
    const selections = [];
    for (let m = 0; m < 4; m++) {
        let best = null;
        for (const entry of entries) {
            if (entry.model !== m) continue;
            if (best === null || rounded(entry.evaluation.macro) > rounded(best.evaluation.macro)) best = entry;
        }
        selections.push(best);
    }
    return { entries, folds, selections };
}

function vocabularyLines(data, vocabulary) {
    const lines = [`documents ${data.train.length} terms ${vocabulary.termCount} candidates ${vocabulary.candidateCount} vocabulary ${vocabulary.terms.length}`];
    for (let i = 0; i < vocabulary.ranking.length; i++) {
        const term = vocabulary.ranking[i];
        lines.push(`${i + 1} ${term.term} ${term.df} ${real(term.chiSquare)} ${data.classes[term.bestClass]}`);
    }
    return lines;
}

function crossValidationLines(data, cv) {
    const lines = ['model,alpha,correct,accuracy,macro_f1,selected'];
    for (const entry of cv.entries) {
        lines.push([models[entry.model], alphaText(entry), entry.evaluation.correct,
            real(entry.evaluation.correct / data.train.length), real(entry.evaluation.macro),
            entry === cv.selections[entry.model] ? 'yes' : 'no'].join(','));
    }
    return lines;
}

function predictionLines(data, rows) {
    const lines = ['id,model,label,score'];
    for (const row of rows) {
        for (let m = 0; m < models.length; m++) {
            const prediction = row.predictions[m];
            lines.push([row.document.id, models[m], data.classes[prediction.label], real(prediction.score)].join(','));
        }
    }
    return lines;
}

function studyLines(data, selections) {
    const labelled = data.test.filter(document => document.label !== null);
    const curve = ['size,vocabulary,model,correct,accuracy,macro_f1'];
    for (const size of data.settings.curve) {
        const training = data.train.slice(0, size);
        const vocabulary = makeVocabulary(training, data);
        const rows = predictRows(fitModels(training, vocabulary, selections, data.classes.length), labelled);
        for (let m = 0; m < 4; m++) {
            const evaluation = evaluateRows(rows, m, data.classes.length);
            curve.push([size, vocabulary.terms.length, models[m], evaluation.correct,
                real(evaluation.correct / labelled.length), real(evaluation.macro)].join(','));
        }
    }
    const features = ['terms,features,vocabulary,model,correct,accuracy,macro_f1'];
    for (const kind of ['unigrams', 'bigrams']) {
        for (const size of data.settings.sizes) {
            const vocabulary = makeVocabulary(data.train, data, kind, size);
            const rows = predictRows(fitModels(data.train, vocabulary, selections, data.classes.length), labelled);
            for (let m = 0; m < 4; m++) {
                const evaluation = evaluateRows(rows, m, data.classes.length);
                features.push([kind, size, vocabulary.terms.length, models[m], evaluation.correct,
                    real(evaluation.correct / labelled.length), real(evaluation.macro)].join(','));
            }
        }
    }
    return { curve, features };
}

function dataLines(data, bundle, rows, labelled) {
    const { classes, train, test, unlabelled, settings } = data;
    const vocabulary = bundle.vocabulary;
    const lines = [`documents train ${train.length} test ${test.length} labelled ${labelled.length} unlabelled ${unlabelled.length} classes ${classes.length}`];
    for (let c = 0; c < classes.length; c++) {
        lines.push(`class ${classes[c]} train ${bundle.counts.classes[c]} test ${labelled.filter(row => row.document.label === c).length}`);
    }
    let raw = 0;
    let stopped = 0;
    let short = 0;
    let kept = 0;
    let bigrams = 0;
    const distinctWords = new Set();
    const distinctBigrams = new Set();
    for (const document of train) {
        raw += document.tokens.raw;
        stopped += document.tokens.stopped;
        short += document.tokens.short;
        kept += document.tokens.unigrams.length;
        for (const word of document.tokens.unigrams) distinctWords.add(word);
        if (settings.kind === 'bigrams') {
            bigrams += document.tokens.pairs.length;
            for (const term of document.tokens.pairs) distinctBigrams.add(term);
        }
    }
    lines.push(`train_tokens raw ${raw} stopwords ${stopped} short ${short} unigrams ${kept} bigrams ${bigrams}`);
    lines.push(`train_terms unigrams ${distinctWords.size} bigrams ${distinctBigrams.size} candidates ${vocabulary.candidateCount} vocabulary ${vocabulary.terms.length}`);
    let total = 0;
    let included = 0;
    const unknown = new Map();
    for (const row of rows) {
        total += row.document.tokens[settings.kind].length;
        included += row.encoded.sequence.length;
        for (const word of row.document.tokens.unigrams) {
            if (!vocabulary.indices.has(word)) unknown.set(word, (unknown.get(word) ?? 0) + 1);
        }
    }
    const outOfVocabulary = [...unknown].sort((a, b) => b[1] - a[1] || compareText(a[0], b[0])).slice(0, settings.top);
    lines.push(`test_terms total ${total} in_vocabulary ${included}`);
    lines.push('test_oov' + outOfVocabulary.map(([word, count]) => ` ${word} ${count}`).join(''));
    return lines;
}

function validationParts(data, cv) {
    const folds = ['folds 5'];
    for (let f = 0; f < cv.folds.length; f++) {
        const fold = cv.folds[f];
        folds.push(`fold ${f + 1} train ${fold.train} validate ${fold.validate} candidates ${fold.candidates} vocabulary ${fold.vocabulary}`);
    }
    const selected = ['selection'];
    for (const entry of cv.selections) {
        selected.push(`${models[entry.model]} alpha ${alphaText(entry)} correct ${proportion(entry.evaluation.correct, data.train.length)}` +
            ` macro_f1 ${real(entry.evaluation.macro)} folds ${entry.correctByFold.join(' ')}`);
    }
    const parts = [folds, selected];
    for (const entry of cv.selections) {
        parts.push([`cross_validation ${models[entry.model]} alpha ${alphaText(entry)}`, ...evaluationLines(entry.evaluation, data.classes)]);
    }
    return parts;
}

function testParts(data, labelled, selections) {
    const parts = [];
    for (let m = 0; m < models.length; m++) {
        const evaluation = evaluateRows(labelled, m, data.classes.length);
        const lines = [`test ${models[m]} alpha ${m < 3 ? alphaText(selections[m]) : '-'}`,
            `labelled ${labelled.length} correct ${proportion(evaluation.correct, labelled.length)}`];
        if (m < 4) {
            const count = labelled.filter(row => row.predictions[m].ranking.slice(0, 2).includes(row.document.label)).length;
            lines.push('top2 ' + proportion(count, labelled.length));
        }
        lines.push(...evaluationLines(evaluation, data.classes));
        parts.push(lines);
    }
    return parts;
}

function probabilityParts(data, labelled, selections) {
    const parts = [];
    for (let m = 0; m < 3; m++) {
        const lowerBounds = [0, ...data.settings.thresholds];
        const bins = lowerBounds.map(() => ({ count: 0, correct: 0, total: 0 }));
        let loss = 0;
        let brier = 0;
        for (const row of labelled) {
            const prediction = row.predictions[m];
            const trueClass = row.document.label;
            loss += Math.log(prediction.normalizer) - (prediction.scores[trueClass] - prediction.scores[prediction.label]);
            let squared = 0;
            for (let c = 0; c < data.classes.length; c++) {
                const difference = prediction.probabilities[c] - (c === trueClass ? 1 : 0);
                squared += difference * difference;
            }
            brier += squared;
            const bin = data.settings.thresholds.filter(threshold => prediction.score >= threshold / 100).length;
            bins[bin].count++;
            if (prediction.label === trueClass) bins[bin].correct++;
            bins[bin].total += prediction.score;
        }
        const lines = [`probability ${models[m]} alpha ${alphaText(selections[m])}`,
            `log_loss ${real(loss / labelled.length)} brier ${real(brier / labelled.length)}`];
        for (let i = 0; i < bins.length; i++) {
            const bin = bins[i];
            const prefix = `bin ${twoDecimal(lowerBounds[i])} rows ${bin.count}`;
            lines.push(bin.count === 0 ? prefix : prefix + ` correct ${proportion(bin.correct, bin.count)} mean ${real(bin.total / bin.count)}`);
        }
        for (const threshold of data.settings.thresholds) {
            const accepted = labelled.filter(row => row.predictions[m].score >= threshold / 100);
            const correct = accepted.filter(row => row.predictions[m].label === row.document.label).length;
            lines.push(`threshold ${twoDecimal(threshold)} covered ${proportion(accepted.length, labelled.length)}` +
                ` correct ${accepted.length === 0 ? '-' : proportion(correct, accepted.length)}`);
        }
        parts.push(lines);
    }
    return parts;
}

function lengthLines(data, labelled) {
    const lowerBounds = [0, ...data.settings.lengths];
    const buckets = lowerBounds.map(() => ({ count: 0, correct: models.map(() => 0) }));
    for (const row of labelled) {
        const index = data.settings.lengths.filter(boundary => row.encoded.sequence.length >= boundary).length;
        const bucket = buckets[index];
        bucket.count++;
        for (let m = 0; m < models.length; m++) if (row.predictions[m].label === row.document.label) bucket.correct[m]++;
    }
    const lines = ['lengths'];
    for (let i = 0; i < buckets.length; i++) {
        const bucket = buckets[i];
        let line = `length ${lowerBounds[i]} rows ${bucket.count}`;
        if (bucket.count > 0) line += models.map((name, m) => ` ${name} ${proportion(bucket.correct[m], bucket.count)}`).join('');
        lines.push(line);
    }
    return lines;
}

function comparisonLines(rows, labelled) {
    const lines = ['comparison'];
    for (const [first, second] of pairs) {
        const agreement = rows.filter(row => row.predictions[first].label === row.predictions[second].label).length;
        let b = 0;
        let c = 0;
        for (const row of labelled) {
            const correctFirst = row.predictions[first].label === row.document.label;
            const correctSecond = row.predictions[second].label === row.document.label;
            if (correctFirst && !correctSecond) b++;
            if (correctSecond && !correctFirst) c++;
        }
        const difference = Math.max(0, Math.abs(b - c) - 1);
        const statistic = b + c === 0 ? metric(0, 1) : metric(difference * difference, b + c);
        lines.push(`${models[first]} ${models[second]} agree ${proportion(agreement, rows.length)} b ${b} c ${c} statistic ${statistic}`);
    }
    const errors = Array(5).fill(0);
    for (const row of labelled) errors[row.predictions.slice(0, 4).filter(prediction => prediction.label !== row.document.label).length]++;
    lines.push('errors ' + errors.map((count, index) => index + ' ' + count).join(' '));
    return lines;
}

function bootstrapLines(data, labelled) {
    const repetitions = data.settings.bootstrap;
    const samples = models.map(() => []);
    const totals = models.map(() => 0);
    const comparisons = pairs.map(() => ({ wins: 0, ties: 0, losses: 0 }));
    const correctness = labelled.map(row => row.predictions.map(prediction => prediction.label === row.document.label ? 1 : 0));
    let state = data.settings.seed;
    for (let r = 0; r < repetitions; r++) {
        const correct = models.map(() => 0);
        for (let i = 0; i < labelled.length; i++) {
            state = (48271 * state) % 2147483647;
            const selected = correctness[state % labelled.length];
            for (let m = 0; m < models.length; m++) correct[m] += selected[m];
        }
        for (let m = 0; m < models.length; m++) { samples[m].push(correct[m]); totals[m] += correct[m]; }
        for (let i = 0; i < pairs.length; i++) {
            const [first, second] = pairs[i];
            if (correct[first] > correct[second]) comparisons[i].wins++;
            else if (correct[first] === correct[second]) comparisons[i].ties++;
            else comparisons[i].losses++;
        }
    }
    const index = Math.floor(repetitions / 40);
    const lines = [`bootstrap resamples ${repetitions} seed ${data.settings.seed}`];
    for (let m = 0; m < models.length; m++) {
        samples[m].sort((a, b) => a - b);
        lines.push(`${models[m]} mean ${real(totals[m] / (repetitions * labelled.length))}` +
            ` low ${proportion(samples[m][index], labelled.length)} high ${proportion(samples[m][repetitions - 1 - index], labelled.length)}`);
    }
    for (let i = 0; i < pairs.length; i++) {
        const [first, second] = pairs[i];
        const result = comparisons[i];
        lines.push(`pair ${models[first]} ${models[second]} wins ${result.wins} ties ${result.ties} losses ${result.losses}`);
    }
    return lines;
}

function hardDocumentLines(data, selections) {
    const hard = data.train.filter(document => selections.every(entry => entry.predictions[document.number - 1] !== document.label));
    const counts = data.classes.map(() => 0);
    for (const document of hard) counts[document.label]++;
    const lines = [`hard_documents ${hard.length} ${classCountsText(counts, data.classes)}`];
    for (const document of hard.slice(0, data.settings.top)) {
        const predictions = selections.map(entry => data.classes[entry.predictions[document.number - 1]]);
        lines.push(`${document.number} true ${data.classes[document.label]} predicted ${predictions.join(' ')}`);
    }
    return lines;
}

function uncertainLines(data, rows) {
    const uncertain = rows.slice().sort((a, b) => rounded(a.predictions[0].margin) - rounded(b.predictions[0].margin)
        || a.document.order - b.document.order).slice(0, data.settings.top);
    const lines = ['uncertain multinomial ' + uncertain.length];
    for (const row of uncertain) {
        const prediction = row.predictions[0];
        lines.push(`${row.document.id} predicted ${data.classes[prediction.label]} runner_up ${data.classes[prediction.ranking[1]]}` +
            ` margin ${real(prediction.margin)} posterior ${real(prediction.score)} true ${row.document.label === null ? '?' : data.classes[row.document.label]}`);
    }
    return lines;
}

function ratioOrder(a, b) {
    const left = a.numerator * b.denominator;
    const right = b.numerator * a.denominator;
    if (left !== right) return left > right ? -1 : 1;
    return compareText(a.term, b.term);
}

function evidenceLines(data, bundle, labelled, alpha) {
    const misclassified = labelled.filter(row => row.predictions[0].label !== row.document.label);
    const lines = ['misclassified multinomial ' + misclassified.length];
    for (const row of misclassified) {
        const prediction = row.predictions[0];
        const trueClass = row.document.label;
        const terms = row.encoded.first.map(index => ({ index, term: bundle.vocabulary.terms[index].term,
            numerator: 100 * bundle.counts.occurrences[prediction.label][index] + alpha,
            denominator: 100 * bundle.counts.occurrences[trueClass][index] + alpha }));
        terms.sort(ratioOrder);
        lines.push(`${row.document.id} true ${data.classes[trueClass]} predicted ${data.classes[prediction.label]} posterior ${real(prediction.score)}`);
        for (const entry of terms.slice(0, 3)) {
            const value = bundle.models[0].weights[prediction.label][entry.index] - bundle.models[0].weights[trueClass][entry.index];
            lines.push(`  ${entry.term} count ${row.encoded.counts.get(entry.index)} evidence ${real(value)}`);
        }
    }
    return lines;
}

function characteristicParts(data, bundle, selections) {
    const parts = [];
    const counts = bundle.counts;
    const size = bundle.vocabulary.terms.length;
    for (let m = 0; m < 2; m++) {
        const alpha = selections[m].alpha;
        parts.push([`model ${models[m]} alpha ${twoDecimal(alpha)} vocabulary ${size} top ${data.settings.top}`]);
        for (let c = 0; c < data.classes.length; c++) {
            const total = m === 0 ? counts.totals[c] : counts.classes[c];
            const other = m === 0 ? counts.total - total : counts.documents - total;
            const terms = bundle.vocabulary.terms.map((entry, index) => {
                const count = m === 0 ? counts.occurrences[c][index] : counts.documentTerms[c][index];
                const otherCount = (m === 0 ? counts.termTotals[index] : counts.documentTotals[index]) - count;
                return { term: entry.term, count, otherCount, numerator: 100 * count + alpha, denominator: 100 * otherCount + alpha };
            }).sort(ratioOrder).slice(0, data.settings.top);
            const lines = [`class ${data.classes[c]} total ${total} other ${other}`];
            for (let i = 0; i < terms.length; i++) {
                const term = terms[i];
                const smoothing = m === 0 ? alpha * size : 2 * alpha;
                const odds = Math.log((100 * term.count + alpha) / (100 * total + smoothing)) -
                    Math.log((100 * term.otherCount + alpha) / (100 * other + smoothing));
                lines.push(`${i + 1} ${term.term} ${term.count} ${term.otherCount} ${real(odds)}`);
            }
            parts.push(lines);
        }
    }
    return parts;
}

function semiSupervisedLines(data, bundle, labelled, alpha) {
    const unlabelled = data.unlabelled.map(document => encode(document, bundle.vocabulary));
    const weight = data.settings.weight / 100;
    const documentTotal = data.train.length + (data.settings.weight * unlabelled.length) / 100;
    const actual = labelled.map(row => row.document.label);
    const lines = [`semi_supervised multinomial alpha ${twoDecimal(alpha)} weight ${twoDecimal(data.settings.weight)} unlabelled ${unlabelled.length}`];
    let previous = null;
    let model = bundle.models[0];
    for (let iteration = 0; iteration <= data.settings.iterations; iteration++) {
        const posterior = unlabelled.map(document => nb.predict(model, document));
        const assignments = posterior.map(prediction => prediction.label);
        const classCounts = data.classes.map(() => 0);
        for (const assignment of assignments) classCounts[assignment]++;
        const predictions = labelled.map(row => nb.predict(model, row.encoded).label);
        const evaluation = evaluate(actual, predictions, data.classes.length);
        const changed = previous === null ? '-' : assignments.filter((label, i) => label !== previous[i]).length;
        lines.push(`iteration ${iteration} correct ${proportion(evaluation.correct, labelled.length)} macro_f1 ${real(evaluation.macro)}` +
            ` changed ${changed} assigned ${classCountsText(classCounts, data.classes)}`);
        if (iteration === data.settings.iterations) break;
        const occurrences = bundle.counts.occurrences.map(row => row.slice());
        const expectedDocuments = bundle.counts.classes.slice();
        for (let u = 0; u < unlabelled.length; u++) {
            for (let c = 0; c < data.classes.length; c++) {
                const contribution = weight * posterior[u].probabilities[c];
                for (const term of unlabelled[u].first) occurrences[c][term] += contribution * unlabelled[u].counts.get(term);
                expectedDocuments[c] += contribution;
            }
        }
        const totals = occurrences.map(row => {
            let total = 0;
            for (const count of row) total += count;
            return total;
        });
        model = nb.multinomialModel(occurrences, totals, expectedDocuments, documentTotal, alpha);
        previous = assignments;
    }
    return lines;
}

function metricParts(data, cv, bundle, rows) {
    const labelled = rows.filter(row => row.document.label !== null);
    return [dataLines(data, bundle, rows, labelled), ...validationParts(data, cv),
        ...testParts(data, labelled, cv.selections), ...probabilityParts(data, labelled, cv.selections),
        lengthLines(data, labelled), comparisonLines(rows, labelled), bootstrapLines(data, labelled),
        hardDocumentLines(data, cv.selections), uncertainLines(data, rows),
        evidenceLines(data, bundle, labelled, cv.selections[0].alpha),
        semiSupervisedLines(data, bundle, labelled, cv.selections[0].alpha)];
}

function writeLines(name, lines) {
    fs.writeFileSync('output/' + name, lines.length === 0 ? '' : lines.join('\n') + '\n', 'ascii');
}

function writeParts(name, parts) {
    writeLines(name, parts.flatMap((part, i) => i === 0 ? part : ['', ...part]));
}

function main() {
    const data = readInput();
    const cv = crossValidation(data);
    const vocabulary = makeVocabulary(data.train, data);
    const bundle = fitModels(data.train, vocabulary, cv.selections, data.classes.length);
    const rows = predictRows(bundle, data.test, true);
    const studies = studyLines(data, cv.selections);
    const metrics = metricParts(data, cv, bundle, rows);
    const characteristic = characteristicParts(data, bundle, cv.selections);
    fs.mkdirSync('output', { recursive: true });
    writeLines('vocabulary.txt', vocabularyLines(data, vocabulary));
    writeLines('cv_results.csv', crossValidationLines(data, cv));
    writeLines('predictions.csv', predictionLines(data, rows));
    writeLines('learning_curve.csv', studies.curve);
    writeLines('feature_study.csv', studies.features);
    writeParts('metrics.txt', metrics);
    writeParts('top_features.txt', characteristic);
}

main();
