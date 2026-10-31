'use strict';

const fs = require('fs');

function lines(path) {
  return fs.readFileSync(path, 'ascii').split('\n').slice(0, -1);
}

function examples(path, multiclass = false) {
  return lines(path).slice(1).map(line => {
    const fields = line.split(',');
    const row = { id: fields[0], point: [Number(fields[1]), Number(fields[2])] };
    if (multiclass) {
      row.class = Number(fields[3]);
      row.role = fields[4];
    } else row.label = Number(fields[3]);
    return row;
  });
}

function read() {
  const params = { kernels: [] };
  for (const line of lines('input/params.txt')) {
    const [key, ...values] = line.split(' ');
    const nums = values.map(Number);
    switch (key) {
      case 'C_GRID': params.cs = nums; break;
      case 'KERNEL': {
        const kernel = { name: values[0], kind: values[1], index: params.kernels.length };
        if (kernel.kind === 'poly') {
          kernel.degree = nums[2]; kernel.gamma = nums[3]; kernel.coef0 = nums[4];
        } else if (kernel.kind === 'rbf') kernel.gamma = nums[2];
        params.kernels.push(kernel);
        break;
      }
      case 'TOLERANCE': params.tau = nums[0]; break;
      case 'EPS': params.eps = nums[0]; break;
      case 'MAX_PASSES': params.maxPasses = nums[0]; break;
      case 'FOLDS': params.folds = nums[0]; break;
      case 'LEARNING_CURVE': params.learningCurve = nums; break;
      case 'NEWTON_ITERATIONS': params.newtonIterations = nums[0]; break;
      case 'MULTICLASS': params.multiName = values[0]; params.multiC = nums[1]; break;
      case 'PEGASOS': params.pegasos = { lambda: nums[0], iterations: nums[1], seed: nums[2] }; break;
      case 'PLOT_X': [params.xMin, params.xMax] = nums; break;
      case 'PLOT_Y': [params.yMin, params.yMax] = nums; break;
      case 'PLOT_SIZE': [params.width, params.height] = nums; break;
    }
  }
  const multi = examples('input/multiclass.csv', true);
  return { train: examples('input/train.csv'), test: examples('input/test.csv'),
    multiTrain: multi.filter(row => row.role === 'train'),
    multiTest: multi.filter(row => row.role === 'test'), params };
}

module.exports = { read };
