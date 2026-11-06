// API client wrapper with credentials, error mapping, and authorization handling.
window.EX = window.EX || {};

(function () {
  'use strict';
  const EX = window.EX;

  class ApiError extends Error {
    constructor(status, code, message, extra = null) {
      super(message || code);
      this.name = 'ApiError';
      this.status = status;
      this.code = code || 'unknown';
      this.extra = extra;
    }
  }
  EX.ApiError = ApiError;

  async function request(path, options = {}) {
    options.credentials = 'same-origin';
    options.headers = options.headers || {};

    let res;
    try {
      res = await fetch(path, options);
    } catch (err) {
      throw new ApiError(0, 'network_error', err.message || 'Network error');
    }

    if (!res.ok) {
      let code = 'unknown';
      let message = res.statusText || 'Error';
      let extra = null;

      try {
        const json = await res.json();
        if (json && json.error) {
          code = json.error.code || code;
          message = json.error.message || message;
          extra = json.error.extra || null;
        }
      } catch (_) {}

      // On 401 (except for login), notify unauthorized
      if (res.status === 401 && path !== '/api/login') {
        if (typeof EX.onUnauthorized === 'function') {
          EX.onUnauthorized();
        }
      }

      throw new ApiError(res.status, code, message, extra);
    }

    if (res.status === 204) {
      return null;
    }

    const contentType = res.headers.get('content-type') || '';
    if (contentType.includes('application/json')) {
      return await res.json();
    }
    return await res.text();
  }

  EX.api = {
    get(path) {
      return request(path, { method: 'GET' });
    },

    post(path, body) {
      const isJson = body && typeof body === 'object' && !(body instanceof FormData) && !(body instanceof Blob);
      return request(path, {
        method: 'POST',
        headers: isJson ? { 'Content-Type': 'application/json' } : {},
        body: isJson ? JSON.stringify(body) : body
      });
    },

    patch(path, body) {
      return request(path, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body || {})
      });
    },

    del(path) {
      return request(path, { method: 'DELETE' });
    },

    put(path, blob, contentType = 'application/octet-stream') {
      return request(path, {
        method: 'PUT',
        headers: { 'Content-Type': contentType },
        body: blob
      });
    },

    // Specific endpoints
    login(username, password) {
      return EX.api.post('/api/login', { username, password });
    },

    logout() {
      return EX.api.post('/api/logout', {});
    },

    me() {
      return EX.api.get('/api/me');
    },

    health() {
      return EX.api.get('/api/health');
    },

    stats() {
      return EX.api.get('/api/stats');
    },

    listNodes(parentId, sort = 'name', order = 'asc') {
      const p = parentId ? encodeURIComponent(parentId) : 'root';
      return EX.api.get(`/api/nodes?parent=${p}&sort=${sort}&order=${order}`);
    },

    getNode(id) {
      return EX.api.get(`/api/nodes/${encodeURIComponent(id)}`);
    },

    createFolder(parentId, name) {
      return EX.api.post('/api/folders', { parentId: parentId || null, name });
    },

    rename(id, name) {
      return EX.api.patch(`/api/nodes/${encodeURIComponent(id)}`, { name });
    },

    move(ids, parentId) {
      return EX.api.post('/api/nodes/move', { ids, parentId: parentId || null });
    },

    trash(ids) {
      return EX.api.post('/api/nodes/trash', { ids });
    },

    restore(ids) {
      return EX.api.post('/api/nodes/restore', { ids });
    },

    purge(ids) {
      return EX.api.post('/api/nodes/purge', { ids });
    },

    listTrash() {
      return EX.api.get('/api/trash');
    },

    emptyTrash() {
      return EX.api.post('/api/trash/empty', {});
    },

    search(q, tagId) {
      const params = [];
      if (q) params.push(`q=${encodeURIComponent(q)}`);
      if (tagId !== null && tagId !== undefined && tagId !== '') params.push(`tag=${encodeURIComponent(tagId)}`);
      return EX.api.get(`/api/search?${params.join('&')}`);
    },

    listTags() {
      return EX.api.get('/api/tags');
    },

    createTag(name, color = '#6b7280') {
      return EX.api.post('/api/tags', { name, color });
    },

    updateTag(id, patch) {
      return EX.api.patch(`/api/tags/${encodeURIComponent(id)}`, patch);
    },

    deleteTag(id) {
      return EX.api.del(`/api/tags/${encodeURIComponent(id)}`);
    },

    tagNodes(ids, add = [], remove = []) {
      return EX.api.post('/api/nodes/tag', { ids, add, remove });
    },

    contentUrl(id, dl = false) {
      return `/api/files/${encodeURIComponent(id)}/content${dl ? '?dl=1' : ''}`;
    },

    thumbUrl(id) {
      return `/api/files/${encodeURIComponent(id)}/thumb`;
    },

    putThumb(id, blob) {
      return EX.api.put(`/api/files/${encodeURIComponent(id)}/thumb`, blob, 'image/jpeg');
    },

    zipDownload(ids) {
      if (!ids || ids.length === 0) return;
      const form = document.createElement('form');
      form.method = 'POST';
      form.action = '/api/zip';
      form.target = '_self';
      form.style.display = 'none';

      const input = document.createElement('input');
      input.type = 'hidden';
      input.name = 'ids';
      input.value = Array.isArray(ids) ? ids.join(',') : ids;
      form.appendChild(input);

      document.body.appendChild(form);
      form.submit();
      setTimeout(() => form.remove(), 1000);
    }
  };

})();
