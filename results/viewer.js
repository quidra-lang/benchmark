/* The Python tokenizer is the source of truth; this file only renders its data. */
(() => {
  'use strict';
  const controls = document.getElementById('controls');
  const selectors = ['date', 'difficulty', 'topic', 'language', 'task']
    .map(id => document.getElementById(id));
  const message = document.getElementById('message');
  const summary = document.getElementById('summary');
  const output = document.getElementById('programs');
  const root = new URL('./', document.baseURI);
  let catalog;
  let pending;

  function status(text, error = false) {
    message.textContent = text;
    message.hidden = !text;
    message.setAttribute('role', error ? 'alert' : 'status');
  }

  function dataURL(view) {
    if (typeof view !== 'string' || !view.endsWith('.json') ||
        /[\\\u0000-\u001f]/.test(view) ||
        view.split('/').some(part => !part || part === '.' || part === '..')) {
      throw new Error('Invalid token data path.');
    }
    // Encode each component: language names include C++ and C#.
    return new URL(view.split('/').map(encodeURIComponent).join('/'), root);
  }

  async function readJSON(url, signal) {
    const response = await fetch(url, { signal, cache: 'no-cache' });
    if (!response.ok) throw new Error(`Unable to load data (HTTP ${response.status}).`);
    return response.json();
  }

  function render(data) {
    if (data?.version !== 1 || !Array.isArray(data.programs) || !data.programs.length) {
      throw new Error('Invalid token data.');
    }
    const fragment = document.createDocumentFragment();
    for (const program of data.programs) {
      if (typeof program?.source !== 'string' || !Array.isArray(program.lengths)) {
        throw new Error('Invalid token data.');
      }
      // Python lengths count Unicode code points; JS string offsets count UTF-16 units.
      const characters = Array.from(program.source);
      if (program.lengths.some(length => !Number.isSafeInteger(length) || length <= 0) ||
          program.lengths.reduce((total, length) => total + length, 0) !== characters.length) {
        throw new Error('Invalid token data: token boundaries do not match the source.');
      }
      const block = document.createElement('div');
      block.className = 'program';
      let lineNumber = 0;
      let code;
      function newLine() {
        const line = document.createElement('div');
        line.className = 'line';
        const number = document.createElement('span');
        number.className = 'number';
        number.textContent = String(++lineNumber);
        number.setAttribute('aria-hidden', 'true');
        code = document.createElement('span');
        code.className = 'code';
        line.append(number, code);
        block.append(line);
      }
      newLine();
      let offset = 0;
      program.lengths.forEach((length, index) => {
        const text = characters.slice(offset, offset + length).join('');
        offset += length;
        text.split('\n').forEach((part, position) => {
          if (position) newLine();
          if (part) {
            const token = document.createElement('span');
            token.className = `token c${index % 12}`;
            token.textContent = part;
            code.append(token);
          }
        });
      });
      fragment.append(block);
    }
    return fragment;
  }

  async function show(view) {
    pending?.abort();
    const request = new AbortController();
    pending = request;
    output.replaceChildren();
    summary.hidden = true;
    summary.textContent = '';
    status('Loading…');
    try {
      const data = await readJSON(dataURL(view), request.signal);
      if (pending !== request) return;
      output.replaceChildren(render(data));
      const total = data.programs.reduce((count, program) => count + program.lengths.length, 0);
      summary.textContent = `Tokens: ${total.toLocaleString('en-US')}`;
      summary.hidden = false;
      status('');
      const url = new URL(location.href);
      url.searchParams.set('view', view);
      history.replaceState(null, '', url);
    } catch (error) {
      if (pending === request) status(error.message, true);
    }
  }

  function fill(selected = []) {
    let branch = catalog.results;
    for (let level = 0; level < selectors.length; level++) {
      let choices = level === 4 ? Array.from(typeof branch === 'string' ? branch : '') :
        Object.keys(branch ?? {}).sort();
      if (!level) choices.reverse();
      const select = selectors[level];
      select.replaceChildren(...choices.map(value => {
        const option = document.createElement('option');
        option.value = value;
        option.textContent = level === 4 ? `Task ${value}` : value.replaceAll('_', ' ');
        return option;
      }));
      select.disabled = !choices.length;
      select.value = choices.includes(selected[level]) ? selected[level] : (choices[0] ?? '');
      if (level < 4) branch = branch?.[select.value];
    }
  }

  function selectedView() {
    const parts = selectors.map(select => select.value);
    return parts.every(Boolean) ? `${parts.slice(0, 4).join('/')}/task${parts[4]}.json` : null;
  }

  controls.addEventListener('change', () => {
    fill(selectors.map(select => select.value));
    const view = selectedView();
    if (view) show(view);
  });

  async function start() {
    if (location.protocol === 'file:') {
      status('Open this viewer through a static web server, such as GitHub Pages or http://localhost:8000/results/.', true);
      return;
    }
    const requested = new URL(location.href).searchParams.get('view');
    try {
      catalog = await readJSON(new URL('views.json', document.baseURI));
      if (catalog?.version !== 1 || !catalog.results || typeof catalog.results !== 'object') {
        throw new Error('Invalid view index.');
      }
      const parts = requested?.split('/');
      const selection = parts?.length === 5 && /^task[AB]\.json$/.test(parts[4]) ?
        [...parts.slice(0, 4), parts[4][4]] : [];
      fill(selection);
      if (requested) {
        // Also permit a standalone token.json without adding it to the benchmark index.
        controls.hidden = selectedView() !== requested;
        await show(requested);
      } else if (selectedView()) {
        await show(selectedView());
      } else {
        status('No token views are available.');
      }
    } catch (error) {
      if (requested) {
        controls.hidden = true;
        await show(requested);
      } else {
        status(error.message, true);
      }
    }
  }

  start();
})();
