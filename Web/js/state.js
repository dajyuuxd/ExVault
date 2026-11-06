// Application reactive state store and hash routing.
window.EX = window.EX || {};

(function () {
  'use strict';
  const EX = window.EX;

  const savedView = typeof localStorage !== 'undefined' ? localStorage.getItem('exv.view') : 'list';
  const savedGridSize = typeof localStorage !== 'undefined' ? localStorage.getItem('exv.gridSize') : 'M';
  const savedFit = typeof localStorage !== 'undefined' ? localStorage.getItem('exv.fit') : 'contain';

  EX.state = {
    user: null,
    parent: null,
    path: [],
    items: [],
    sort: 'name',
    order: 'asc',
    view: savedView === 'grid' ? 'grid' : 'list',
    gridSize: ['S', 'M', 'L'].includes(savedGridSize) ? savedGridSize : 'M',
    gridFit: savedFit === 'cover' ? 'cover' : 'contain',
    selection: new Set(),
    mode: 'files', // 'files' | 'trash' | 'search' | 'tag'
    query: '',
    tagId: null,
    tags: [],
    stats: null,
    limits: { chunkSize: 4 * 1024 * 1024 }
  };

  EX.setState = function (patch) {
    if (!patch || typeof patch !== 'object') return;
    Object.assign(EX.state, patch);
    if (patch.view) {
      if (typeof localStorage !== 'undefined') localStorage.setItem('exv.view', patch.view);
    }
    if (patch.gridSize) {
      if (typeof localStorage !== 'undefined') localStorage.setItem('exv.gridSize', patch.gridSize);
    }
    if (patch.gridFit) {
      if (typeof localStorage !== 'undefined') localStorage.setItem('exv.fit', patch.gridFit);
    }
    if (typeof EX.render === 'function') {
      EX.render();
    }
  };

  EX.navigate = function (parentId) {
    const target = parentId ? `#/f/${encodeURIComponent(parentId)}` : '#/f/root';
    if (window.location.hash === target) {
      EX.reload();
    } else {
      window.location.hash = target;
    }
  };

  EX.reload = async function () {
    try {
      if (EX.state.mode === 'trash') {
        const res = await EX.api.listTrash();
        EX.setState({
          items: res.items || [],
          path: [],
          selection: new Set()
        });
      } else if (EX.state.mode === 'search') {
        const res = await EX.api.search(EX.state.query, EX.state.tagId);
        EX.setState({
          items: res.items || [],
          selection: new Set()
        });
      } else if (EX.state.mode === 'tag') {
        const res = await EX.api.search('', EX.state.tagId);
        EX.setState({
          items: res.items || [],
          selection: new Set()
        });
      } else {
        // Mode 'files'
        const res = await EX.api.listNodes(EX.state.parent, EX.state.sort, EX.state.order);
        EX.setState({
          items: res.items || [],
          path: res.path || [],
          selection: new Set()
        });
      }

      // Also refresh stats and tags in background
      Promise.all([
        EX.api.stats().catch(() => null),
        EX.api.listTags().catch(() => null)
      ]).then(([stats, tags]) => {
        const patch = {};
        if (stats) patch.stats = stats;
        if (tags && tags.items) patch.tags = tags.items;
        if (Object.keys(patch).length > 0) {
          EX.setState(patch);
        }
      });
    } catch (err) {
      EX.toast(EX.t('err.' + (err.code || 'unknown')), 'error');
    }
  };

})();
