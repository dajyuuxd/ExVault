// Application lifecycle, initialization, login screen, and hash routing.
window.EX = window.EX || {};

(function () {
  'use strict';
  const EX = window.EX;
  const h = EX.h;

  EX.init = async function () {
    // 1. Initialize Theme
    let theme = typeof localStorage !== 'undefined' ? localStorage.getItem('exv.theme') : null;
    if (!theme || (theme !== 'light' && theme !== 'dark')) {
      theme = (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches) ? 'dark' : 'light';
    }
    document.documentElement.setAttribute('data-theme', theme);

    // 2. Setup unauthorized listener
    EX.onUnauthorized = function () {
      EX.state.user = null;
      EX.renderLogin();
    };

    // 3. Setup Hash Change Listener
    window.addEventListener('hashchange', handleRoute);

    // 4. Keyboard Shortcuts
    document.addEventListener('keydown', handleKeydown);

    // 5. Check login status
    try {
      const me = await EX.api.me();
      if (me && me.username) {
        EX.state.user = me.username;
        if (me.chunkSize) EX.state.limits.chunkSize = me.chunkSize;
        handleRoute();
      } else {
        EX.renderLogin();
      }
    } catch (_) {
      EX.renderLogin();
    }
  };

  function handleRoute() {
    const hash = window.location.hash || '#/f/root';

    if (hash.startsWith('#/v/')) {
      const vid = decodeURIComponent(hash.slice('#/v/'.length));
      if (EX.viewer && typeof EX.viewer.open === 'function') {
        EX.viewer.open(vid, EX.state.items);
      }
      return;
    }

    if (hash === '#/trash') {
      EX.setState({ mode: 'trash', parent: null, tagId: null, query: '' });
      EX.reload();
    } else if (hash.startsWith('#/search/')) {
      const q = decodeURIComponent(hash.slice('#/search/'.length));
      EX.setState({ mode: 'search', query: q, tagId: null, parent: null });
      EX.reload();
    } else if (hash.startsWith('#/tag/')) {
      const tid = decodeURIComponent(hash.slice('#/tag/'.length));
      EX.setState({ mode: 'tag', tagId: tid, query: '', parent: null });
      EX.reload();
    } else if (hash.startsWith('#/f/')) {
      const pid = decodeURIComponent(hash.slice('#/f/'.length));
      const parent = (pid === 'root' || !pid) ? null : pid;
      EX.setState({ mode: 'files', parent: parent, tagId: null, query: '' });
      EX.reload();
    } else {
      EX.navigate(null);
    }
  }

  function handleKeydown(e) {
    if (['INPUT', 'TEXTAREA'].includes(e.target.tagName)) return;
    if (document.querySelector('.modal-overlay')) return;

    if (e.key === 'Delete' || e.key === 'Backspace') {
      if (EX.state.selection.size > 0 && EX.state.mode === 'files') {
        e.preventDefault();
        EX.bulkTrash();
      }
    } else if (e.key === 'F2') {
      if (EX.state.selection.size === 1 && EX.state.mode === 'files') {
        e.preventDefault();
        const id = Array.from(EX.state.selection)[0];
        const item = (EX.state.items || []).find((i) => i.id === id);
        if (item && typeof EX.promptRename === 'function') {
          EX.promptRename(item);
        } else {
          EX.promptRenameSelected();
        }
      }
    } else if (e.key === 'Enter') {
      if (EX.state.selection.size === 1) {
        e.preventDefault();
        const id = Array.from(EX.state.selection)[0];
        const item = (EX.state.items || []).find((i) => i.id === id);
        if (item) {
          if (item.kind === 'folder') {
            EX.navigate(item.id);
          } else if (EX.viewer && typeof EX.viewer.open === 'function') {
            EX.viewer.open(item.id, EX.state.items);
          } else {
            window.open(EX.api.contentUrl(item.id, true), '_blank');
          }
        }
      }
    } else if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'a') {
      e.preventDefault();
      EX.selectAll();
    } else if (e.key === 'Escape') {
      if (typeof EX.closeContextMenu === 'function') EX.closeContextMenu();
      EX.clearSelection();
    }
  }

  EX.renderLogin = function (errorMessage = null, waitSeconds = 0) {
    const app = EX.$('#app');
    if (!app) return;

    app.className = 'login-screen';
    app.textContent = '';

    const title = h('h1', { class: 'login-title' }, EX.t('login.title'));
    const tagline = h('p', { class: 'login-tagline' }, EX.t('app.tagline'));

    const userInput = h('input', {
      type: 'text',
      class: 'form-input',
      placeholder: EX.t('login.username'),
      required: true,
      autocapitalize: 'off',
      autocorrect: 'off'
    });

    const passInput = h('input', {
      type: 'password',
      class: 'form-input',
      placeholder: EX.t('login.password'),
      required: true
    });

    const submitBtn = h('button', {
      type: 'submit',
      class: 'btn btn-primary btn-block'
    }, EX.t('login.submit'));

    const errorEl = h('div', { class: 'login-error', style: { display: errorMessage ? 'block' : 'none' } }, errorMessage || '');

    // Rate limiter countdown handler
    let countdownTimer = null;
    if (waitSeconds > 0) {
      submitBtn.disabled = true;
      let remaining = waitSeconds;
      errorEl.textContent = EX.t('login.rate_limited', { seconds: remaining });
      errorEl.style.display = 'block';

      countdownTimer = setInterval(() => {
        remaining -= 1;
        if (remaining <= 0) {
          clearInterval(countdownTimer);
          submitBtn.disabled = false;
          errorEl.style.display = 'none';
        } else {
          errorEl.textContent = EX.t('login.rate_limited', { seconds: remaining });
        }
      }, 1000);
    }

    const form = h('form', {
      class: 'login-card',
      onsubmit: async (e) => {
        e.preventDefault();
        if (countdownTimer) clearInterval(countdownTimer);

        const u = userInput.value.trim();
        const p = passInput.value;
        if (!u || !p) return;

        submitBtn.disabled = true;
        try {
          await EX.api.login(u, p);
          const me = await EX.api.me();
          EX.state.user = me.username;
          if (me.chunkSize) EX.state.limits.chunkSize = me.chunkSize;
          handleRoute();
        } catch (err) {
          submitBtn.disabled = false;
          if (err.status === 429) {
            const retry = err.extra && err.extra.retryAfter ? parseInt(err.extra.retryAfter, 10) : 30;
            EX.renderLogin(null, retry);
          } else {
            errorEl.textContent = EX.t('err.' + (err.code || 'bad_credentials'));
            errorEl.style.display = 'block';
            passInput.value = '';
            passInput.focus();
          }
        }
      }
    },
      h('div', { class: 'login-logo' }, '📦'),
      title,
      tagline,
      errorEl,
      userInput,
      passInput,
      submitBtn
    );

    app.appendChild(form);
    setTimeout(() => userInput.focus(), 50);
  };

  // Launch on DOMContentLoaded
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', EX.init);
  } else {
    EX.init();
  }

})();
