// DOM manipulation, formatting, and helper utilities.
window.EX = window.EX || {};

(function () {
  'use strict';
  const EX = window.EX;

  // DOM selection helpers
  EX.$ = function (selector, root = document) {
    return root.querySelector(selector);
  };

  EX.$$ = function (selector, root = document) {
    return Array.from(root.querySelectorAll(selector));
  };

  // Safe element creation without innerHTML
  EX.h = function (tag, attrs, ...children) {
    const el = document.createElement(tag);
    if (attrs) {
      for (const [key, val] of Object.entries(attrs)) {
        if (key === 'className' || key === 'class') {
          el.className = val;
        } else if (key === 'style' && typeof val === 'object') {
          Object.assign(el.style, val);
        } else if (key.startsWith('on') && typeof val === 'function') {
          const evt = key.slice(2).toLowerCase();
          el.addEventListener(evt, val);
        } else if (key.startsWith('data-')) {
          el.setAttribute(key, val);
        } else if (typeof val === 'boolean') {
          if (val) el.setAttribute(key, '');
        } else if (val !== null && val !== undefined) {
          el.setAttribute(key, val);
        }
      }
    }

    for (const child of children) {
      if (child === null || child === undefined || child === false) continue;
      if (Array.isArray(child)) {
        for (const c of child) {
          if (c !== null && c !== undefined && c !== false) {
            el.appendChild(typeof c === 'string' || typeof c === 'number' ? document.createTextNode(c) : c);
          }
        }
      } else if (typeof child === 'string' || typeof child === 'number') {
        el.appendChild(document.createTextNode(child));
      } else if (child instanceof Node) {
        el.appendChild(child);
      }
    }
    return el;
  };

  // Byte formatting: e.g. 1024 -> 1.0 KB, 1048576 -> 1.0 MB
  EX.fmtBytes = function (bytes) {
    if (bytes === 0 || bytes === '0' || !bytes) return '0 B';
    const b = parseInt(bytes, 10);
    if (isNaN(b) || b <= 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(b) / Math.log(k));
    const val = b / Math.pow(k, i);
    return (i === 0 ? val : val.toFixed(1)) + ' ' + sizes[i];
  };

  // Date formatting: e.g. 2026-11-06 14:30
  EX.fmtDate = function (ts) {
    if (!ts) return '-';
    let ms = parseInt(ts, 10);
    if (isNaN(ms) || ms <= 0) return '-';
    if (ms < 10000000000) ms *= 1000; // convert seconds to ms if needed
    const d = new Date(ms);
    const pad = (n) => (n < 10 ? '0' + n : n);
    const year = d.getFullYear();
    const month = pad(d.getMonth() + 1);
    const day = pad(d.getDate());
    const hours = pad(d.getHours());
    const mins = pad(d.getMinutes());
    return `${year}-${month}-${day} ${hours}:${mins}`;
  };

  // Debounce function
  EX.debounce = function (fn, ms) {
    let timer = null;
    return function (...args) {
      clearTimeout(timer);
      timer = setTimeout(() => fn.apply(this, args), ms);
    };
  };

  // File extension extractor
  EX.ext = function (name) {
    if (!name) return '';
    const idx = name.lastIndexOf('.');
    if (idx <= 0 || idx === name.length - 1) return '';
    return name.slice(idx + 1).toLowerCase();
  };

  // File type detectors
  EX.isImage = function (node) {
    if (!node) return false;
    if (node.mime && node.mime.startsWith('image/')) return true;
    const e = EX.ext(node.name);
    return ['jpg', 'jpeg', 'png', 'gif', 'webp', 'svg', 'bmp', 'ico'].includes(e);
  };

  EX.isVideo = function (node) {
    if (!node) return false;
    if (node.mime && node.mime.startsWith('video/')) return true;
    const e = EX.ext(node.name);
    return ['mp4', 'webm', 'mov', 'm4v', 'mkv', 'avi', '3gp', 'ogv', 'ts'].includes(e);
  };

  EX.isPdf = function (node) {
    if (!node) return false;
    if (node.mime === 'application/pdf') return true;
    return EX.ext(node.name) === 'pdf';
  };

  EX.isText = function (node) {
    if (!node) return false;
    if (node.mime && (node.mime.startsWith('text/') || node.mime === 'application/json' || node.mime === 'application/xml' || node.mime === 'application/javascript')) return true;
    const e = EX.ext(node.name);
    return ['txt', 'md', 'markdown', 'log', 'csv', 'json', 'js', 'css', 'html', 'swift', 'py', 'sh', 'c', 'h', 'cpp', 'xml', 'yaml', 'yml'].includes(e);
  };

  // Toast notification
  EX.toast = function (msg, kind = 'info') {
    let container = EX.$('#toast-container');
    if (!container) {
      container = EX.h('div', { id: 'toast-container' });
      document.body.appendChild(container);
    }
    const toast = EX.h('div', { class: `toast toast-${kind}` }, msg);
    container.appendChild(toast);
    setTimeout(() => {
      toast.classList.add('toast-show');
    }, 10);
    setTimeout(() => {
      toast.classList.remove('toast-show');
      setTimeout(() => toast.remove(), 300);
    }, 3500);
  };

})();
