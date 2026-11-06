// View rendering: topbar, sidebar, breadcrumb, toolbar, list/grid items, dialogs, and selection.
window.EX = window.EX || {};

(function () {
  'use strict';
  const EX = window.EX;
  const h = EX.h;

  let lastSelectedId = null;

  EX.render = function () {
    const app = EX.$('#app');
    if (!app) return;

    if (!EX.state.user) {
      if (typeof EX.renderLogin === 'function') {
        EX.renderLogin();
      }
      return;
    }

    // Main App Shell
    app.className = 'app-shell';
    app.textContent = '';

    const topbar = EX.renderTopbar();
    const bodyContainer = h('div', { class: 'app-body' });
    const sidebar = EX.renderSidebar();
    const mainArea = h('div', { class: 'app-main' },
      EX.renderBreadcrumb(),
      EX.renderToolbar(),
      EX.renderItems()
    );

    // Drag-and-drop upload zone on mainArea
    let dragCounter = 0;
    const dropOverlay = h('div', { class: 'drop-overlay', style: { display: 'none' } },
      h('div', { class: 'drop-overlay-icon' }, '📥'),
      h('div', { class: 'drop-overlay-text' }, EX.t('upload.drop_hint'))
    );
    mainArea.appendChild(dropOverlay);

    mainArea.addEventListener('dragenter', (e) => {
      e.preventDefault();
      dragCounter++;
      dropOverlay.style.display = 'flex';
    });

    mainArea.addEventListener('dragover', (e) => {
      e.preventDefault();
    });

    mainArea.addEventListener('dragleave', (e) => {
      e.preventDefault();
      dragCounter--;
      if (dragCounter <= 0) {
        dragCounter = 0;
        dropOverlay.style.display = 'none';
      }
    });

    mainArea.addEventListener('drop', (e) => {
      e.preventDefault();
      dragCounter = 0;
      dropOverlay.style.display = 'none';

      if (e.dataTransfer && e.dataTransfer.items && e.dataTransfer.items.length > 0) {
        if (EX.upload && typeof EX.upload.enqueueEntries === 'function') {
          EX.upload.enqueueEntries(e.dataTransfer.items, EX.state.parent);
        }
      } else if (e.dataTransfer && e.dataTransfer.files && e.dataTransfer.files.length > 0) {
        if (EX.upload && typeof EX.upload.enqueue === 'function') {
          EX.upload.enqueue(Array.from(e.dataTransfer.files), EX.state.parent);
        }
      }
    });

    bodyContainer.appendChild(sidebar);
    bodyContainer.appendChild(mainArea);

    app.appendChild(topbar);
    app.appendChild(bodyContainer);

    // If upload panel exists (T15), render it
    if (EX.upload && typeof EX.upload.renderPanel === 'function') {
      const panel = EX.upload.renderPanel();
      if (panel) app.appendChild(panel);
    }
  };

  EX.renderTopbar = function () {
    const mobileMenuBtn = h('button', {
      class: 'btn btn-icon btn-menu-toggle',
      onclick: () => {
        const sb = EX.$('.app-sidebar');
        if (sb) sb.classList.toggle('sidebar-open');
      }
    }, '☰');

    const brand = h('div', { class: 'topbar-brand', onclick: () => EX.navigate(null) },
      h('span', { class: 'brand-icon' }, '📦'),
      h('span', { class: 'brand-title' }, EX.t('app.title'))
    );

    let searchDebounceTimer = null;
    const searchInput = h('input', {
      type: 'search',
      class: 'search-input',
      placeholder: EX.t('top.search_placeholder'),
      value: EX.state.query || '',
      oninput: (e) => {
        const q = e.target.value.trim();
        if (searchDebounceTimer) clearTimeout(searchDebounceTimer);
        searchDebounceTimer = setTimeout(() => {
          if (q) window.location.hash = `#/search/${encodeURIComponent(q)}`;
          else if (EX.state.mode === 'search') EX.navigate(EX.state.parent);
        }, 300);
      },
      onkeydown: (e) => {
        if (e.key === 'Enter') {
          if (searchDebounceTimer) clearTimeout(searchDebounceTimer);
          const q = e.target.value.trim();
          if (q) window.location.hash = `#/search/${encodeURIComponent(q)}`;
          else EX.navigate(EX.state.parent);
        }
      }
    });

    const viewToggleBtn = h('button', {
      class: 'btn btn-icon',
      title: EX.state.view === 'list' ? EX.t('top.view_grid') : EX.t('top.view_list'),
      onclick: () => {
        EX.setState({ view: EX.state.view === 'list' ? 'grid' : 'list' });
      }
    }, EX.state.view === 'list' ? '⊞' : '☰');

    const langToggleBtn = h('button', {
      class: 'btn btn-icon btn-text-icon',
      title: EX.t('top.lang'),
      onclick: () => {
        EX.setLang(EX.lang === 'vi' ? 'en' : 'vi');
      }
    }, EX.lang.toUpperCase());

    const themeToggleBtn = h('button', {
      class: 'btn btn-icon',
      title: EX.t('top.theme'),
      onclick: () => {
        const cur = document.documentElement.getAttribute('data-theme') || 'light';
        const next = cur === 'dark' ? 'light' : 'dark';
        document.documentElement.setAttribute('data-theme', next);
        if (typeof localStorage !== 'undefined') localStorage.setItem('exv.theme', next);
      }
    }, '◐');

    const settingsBtn = h('button', {
      class: 'btn btn-icon',
      title: EX.t('top.settings'),
      onclick: () => EX.openSettingsDialog()
    }, '⚙');

    const logoutBtn = h('button', {
      class: 'btn btn-icon',
      title: EX.t('nav.logout'),
      onclick: async () => {
        try {
          await EX.api.logout();
        } catch (_) {}
        EX.state.user = null;
        EX.render();
      }
    }, '🚪');

    return h('header', { class: 'app-topbar' },
      h('div', { class: 'topbar-left' }, mobileMenuBtn, brand),
      h('div', { class: 'topbar-center' }, searchInput),
      h('div', { class: 'topbar-right' }, viewToggleBtn, langToggleBtn, themeToggleBtn, settingsBtn, logoutBtn)
    );
  };

  EX.renderSidebar = function () {
    const isFiles = EX.state.mode === 'files';
    const isTrash = EX.state.mode === 'trash';

    const allFilesNav = h('div', {
      class: `sidebar-nav-item ${isFiles && !EX.state.tagId ? 'active' : ''}`,
      onclick: () => {
        EX.navigate(null);
        closeMobileSidebar();
      }
    }, h('span', { class: 'nav-icon' }, '📁'), h('span', {}, EX.t('nav.all_files')));

    const trashNav = h('div', {
      class: `sidebar-nav-item ${isTrash ? 'active' : ''}`,
      onclick: () => {
        window.location.hash = '#/trash';
        closeMobileSidebar();
      }
    }, h('span', { class: 'nav-icon' }, '🗑'), h('span', {}, EX.t('nav.trash')));

    // Tags section
    const tagsContainer = h('div', { class: 'sidebar-tags-list' });
    for (const tag of EX.state.tags || []) {
      const isTagActive = EX.state.mode === 'tag' && String(EX.state.tagId) === String(tag.id);
      const dot = h('span', { class: 'tag-dot', style: { backgroundColor: tag.color } });
      const name = h('span', { class: 'tag-name' }, tag.name);
      const tagItem = h('div', {
        class: `sidebar-nav-item ${isTagActive ? 'active' : ''}`,
        onclick: () => {
          window.location.hash = `#/tag/${encodeURIComponent(tag.id)}`;
          closeMobileSidebar();
        }
      }, dot, name);
      tagsContainer.appendChild(tagItem);
    }

    const tagsSection = h('div', { class: 'sidebar-section' },
      h('div', { class: 'sidebar-section-title' }, EX.t('nav.tags')),
      tagsContainer
    );

    // Storage progress section
    let storageSection = null;
    if (EX.state.stats) {
      const stats = EX.state.stats;
      const totalSize = stats.totalBytes || 0;
      const storedSize = stats.storedBytes || 0;
      const diskFree = stats.diskFreeBytes || 0;

      let ratioText = '';
      if (totalSize > 0 && storedSize < totalSize) {
        const pct = Math.round((1 - storedSize / totalSize) * 100);
        ratioText = EX.t('storage.used_ratio', {
          stored: EX.fmtBytes(storedSize),
          size: EX.fmtBytes(totalSize),
          ratio: `−${pct}`
        });
      } else {
        ratioText = EX.fmtBytes(storedSize);
      }

      const freeText = EX.t('storage.free', { free: EX.fmtBytes(diskFree) });

      storageSection = h('div', { class: 'sidebar-storage' },
        h('div', { class: 'storage-title' }, EX.t('nav.storage')),
        h('div', { class: 'storage-info' }, ratioText),
        h('div', { class: 'storage-free' }, freeText)
      );
    }

    return h('aside', { class: 'app-sidebar' },
      allFilesNav,
      trashNav,
      tagsSection,
      storageSection || h('div')
    );
  };

  function closeMobileSidebar() {
    const sb = EX.$('.app-sidebar');
    if (sb) sb.classList.remove('sidebar-open');
  }

  EX.renderBreadcrumb = function () {
    const container = h('nav', { class: 'app-breadcrumb' });

    if (EX.state.mode === 'trash') {
      container.appendChild(h('span', { class: 'crumb-item current' }, EX.t('nav.trash')));
      return container;
    }
    if (EX.state.mode === 'search') {
      container.appendChild(h('span', { class: 'crumb-item current' }, `${EX.t('top.search_placeholder').replace('...', '')}: "${EX.state.query}"`));
      return container;
    }
    if (EX.state.mode === 'tag') {
      const tag = (EX.state.tags || []).find((t) => String(t.id) === String(EX.state.tagId));
      container.appendChild(h('span', { class: 'crumb-item current' }, `${EX.t('nav.tags')}: ${tag ? tag.name : EX.state.tagId}`));
      return container;
    }

    // Mode files
    const rootCrumb = h('span', {
      class: `crumb-item ${EX.state.path.length === 0 ? 'current' : ''}`,
      onclick: () => EX.navigate(null)
    }, EX.t('nav.all_files'));
    container.appendChild(rootCrumb);

    for (let i = 0; i < EX.state.path.length; i++) {
      const item = EX.state.path[i];
      const isLast = i === EX.state.path.length - 1;
      container.appendChild(h('span', { class: 'crumb-separator' }, '/'));
      const crumb = h('span', {
        class: `crumb-item ${isLast ? 'current' : ''}`,
        onclick: isLast ? null : () => EX.navigate(item.id)
      }, item.name);
      container.appendChild(crumb);
    }

    return container;
  };

  EX.renderToolbar = function () {
    const selectedCount = EX.state.selection.size;
    const isTrash = EX.state.mode === 'trash';

    const bar = h('div', { class: 'app-toolbar' });

    if (isTrash) {
      if (selectedCount > 0) {
        bar.appendChild(h('button', { class: 'btn btn-primary', onclick: () => EX.bulkRestore() }, EX.t('action.restore')));
        bar.appendChild(h('button', { class: 'btn btn-danger', onclick: () => EX.bulkPurge() }, EX.t('action.purge')));
      } else {
        bar.appendChild(h('button', { class: 'btn btn-danger', onclick: () => EX.emptyTrashDialog() }, EX.t('action.empty_trash')));
      }
      return bar;
    }

    // Normal files mode toolbar
    if (selectedCount > 0) {
      bar.appendChild(h('span', { class: 'toolbar-count' }, EX.t('status.selected_count', { count: selectedCount })));

      bar.appendChild(h('button', { class: 'btn', onclick: () => EX.bulkDownload() }, EX.t('action.download')));

      if (selectedCount === 1) {
        bar.appendChild(h('button', { class: 'btn', onclick: () => EX.promptRenameSelected() }, EX.t('action.rename')));
      }

      bar.appendChild(h('button', { class: 'btn', onclick: () => EX.openMoveDialog(Array.from(EX.state.selection)) }, EX.t('action.move')));
      bar.appendChild(h('button', { class: 'btn', onclick: () => EX.openTagDialog(Array.from(EX.state.selection)) }, EX.t('action.tag')));
      bar.appendChild(h('button', { class: 'btn btn-danger', onclick: () => EX.bulkTrash() }, EX.t('action.delete')));
    } else {
      // Hidden file input for upload
      const fileInput = h('input', {
        type: 'file',
        multiple: true,
        style: { display: 'none' },
        onchange: (e) => {
          if (e.target.files && e.target.files.length > 0) {
            if (EX.upload && typeof EX.upload.enqueue === 'function') {
              EX.upload.enqueue(Array.from(e.target.files), EX.state.parent);
            }
          }
          e.target.value = '';
        }
      });
      bar.appendChild(fileInput);

      // Hidden folder input for directory upload
      const folderInput = h('input', {
        type: 'file',
        webkitdirectory: '',
        directory: '',
        multiple: true,
        style: { display: 'none' },
        onchange: (e) => {
          if (e.target.files && e.target.files.length > 0) {
            if (EX.upload && typeof EX.upload.enqueue === 'function') {
              EX.upload.enqueue(Array.from(e.target.files), EX.state.parent);
            }
          }
          e.target.value = '';
        }
      });
      bar.appendChild(folderInput);

      bar.appendChild(h('button', {
        class: 'btn btn-primary',
        onclick: () => fileInput.click()
      }, '↑ ' + EX.t('action.upload')));

      bar.appendChild(h('button', {
        class: 'btn',
        title: EX.t('upload.folder'),
        onclick: () => folderInput.click()
      }, '📁 ' + EX.t('upload.folder')));

      bar.appendChild(h('button', {
        class: 'btn',
        onclick: () => EX.promptNewFolder()
      }, '+ ' + EX.t('action.new_folder')));
    }

    return bar;
  };

  EX.renderItems = function () {
    const items = EX.state.items || [];
    if (items.length === 0) {
      let emptyMsg = EX.t('empty.no_files');
      if (EX.state.mode === 'trash') emptyMsg = EX.t('empty.no_trash');
      if (EX.state.mode === 'search') emptyMsg = EX.t('empty.no_search');
      return h('div', { class: 'empty-container' },
        h('div', { class: 'empty-icon' }, '📭'),
        h('div', { class: 'empty-text' }, emptyMsg)
      );
    }

    if (EX.state.view === 'grid') {
      return EX.renderGrid(items);
    }
    return EX.renderList(items);
  };

  // Thumbnail loading manager: max 4 parallel requests to prevent connection exhaustion
  const thumbQueue = [];
  let activeThumbs = 0;
  const MAX_THUMB_PARALLEL = 4;

  function pumpThumbQueue() {
    while (activeThumbs < MAX_THUMB_PARALLEL && thumbQueue.length > 0) {
      const { img, url } = thumbQueue.shift();
      activeThumbs++;
      const temp = new Image();
      temp.onload = () => {
        img.src = url;
        activeThumbs--;
        pumpThumbQueue();
      };
      temp.onerror = () => {
        activeThumbs--;
        pumpThumbQueue();
      };
      temp.src = url;
    }
  }

  const thumbObserver = (typeof window !== 'undefined' && 'IntersectionObserver' in window)
    ? new IntersectionObserver((entries, observer) => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            const img = entry.target;
            observer.unobserve(img);
            const url = img.dataset.src;
            if (url) {
              thumbQueue.push({ img, url });
              pumpThumbQueue();
            }
          }
        }
      }, { rootMargin: '120px' })
    : null;

  function bindLazyThumb(img, url) {
    img.dataset.src = url;
    if (thumbObserver) {
      thumbObserver.observe(img);
    } else {
      thumbQueue.push({ img, url });
      pumpThumbQueue();
    }
  }

  // Cluster / batch rendering for smooth scrolling with thousands of items
  function renderBatchedItems(items, container, renderFn) {
    const BATCH_SIZE = 200;
    let index = 0;

    function renderNextBatch() {
      const fragment = document.createDocumentFragment();
      const end = Math.min(index + BATCH_SIZE, items.length);
      for (; index < end; index++) {
        fragment.appendChild(renderFn(items[index]));
      }
      container.appendChild(fragment);

      if (index < items.length) {
        requestAnimationFrame(renderNextBatch);
      }
    }

    renderNextBatch();
  }

  // Touch long press detector (500ms) for mobile context menu
  function attachTouchLongPress(el, onLongPress) {
    let touchTimer = null;
    let startX = 0;
    let startY = 0;

    el.addEventListener('touchstart', (e) => {
      if (e.touches.length !== 1) return;
      const t = e.touches[0];
      startX = t.clientX;
      startY = t.clientY;

      touchTimer = setTimeout(() => {
        touchTimer = null;
        onLongPress(startX, startY);
      }, 500);
    }, { passive: true });

    el.addEventListener('touchmove', (e) => {
      if (touchTimer && e.touches.length === 1) {
        const t = e.touches[0];
        if (Math.hypot(t.clientX - startX, t.clientY - startY) > 10) {
          clearTimeout(touchTimer);
          touchTimer = null;
        }
      }
    }, { passive: true });

    el.addEventListener('touchend', () => {
      if (touchTimer) {
        clearTimeout(touchTimer);
        touchTimer = null;
      }
    });

    el.addEventListener('touchcancel', () => {
      if (touchTimer) {
        clearTimeout(touchTimer);
        touchTimer = null;
      }
    });
  }

  // Context Menu
  let activeContextMenu = null;

  EX.closeContextMenu = function () {
    if (activeContextMenu && activeContextMenu.parentNode) {
      activeContextMenu.parentNode.removeChild(activeContextMenu);
      activeContextMenu = null;
    }
  };

  EX.openContextMenu = function (x, y, node) {
    EX.closeContextMenu();
    if (!node) return;

    if (!EX.state.selection.has(node.id)) {
      EX.setState({ selection: new Set([node.id]) });
    }

    const isTrash = EX.state.mode === 'trash';
    const isSearch = EX.state.mode === 'search';
    const isFolder = node.kind === 'folder';
    const selCount = EX.state.selection.size;

    const menu = h('div', { class: 'context-menu' });

    function addItem(label, icon, onClick, danger = false) {
      const itemEl = h('div', {
        class: `context-menu-item ${danger ? 'danger' : ''}`,
        onclick: (e) => {
          e.stopPropagation();
          EX.closeContextMenu();
          onClick();
        }
      }, h('span', {}, icon), h('span', {}, label));
      menu.appendChild(itemEl);
    }

    function addDivider() {
      menu.appendChild(h('div', { class: 'context-menu-divider' }));
    }

    if (isTrash) {
      addItem(EX.t('action.restore'), '↺', () => EX.bulkRestore());
      addItem(EX.t('action.purge'), '🗑', () => EX.bulkPurge(), true);
    } else {
      if (selCount === 1) {
        addItem(EX.t('action.open'), isFolder ? '📁' : '👁', () => {
          if (isFolder) EX.navigate(node.id);
          else openItem(node);
        });

        if (isSearch && node.parentId) {
          addItem(EX.t('action.open_folder'), '📂', () => {
            EX.navigate(node.parentId);
          });
        }
      }

      addItem(EX.t('action.download'), '⬇', () => EX.bulkDownload());

      if (selCount === 1) {
        addItem(EX.t('action.rename'), '✎', () => EX.promptRename(node));
      }

      addDivider();
      addItem(EX.t('action.move'), '↗', () => EX.openMoveDialog(Array.from(EX.state.selection)));
      addItem(EX.t('action.tag'), '🏷', () => EX.openTagDialog(Array.from(EX.state.selection)));
      addDivider();
      addItem(EX.t('action.delete'), '🗑', () => EX.bulkTrash(), true);
    }

    document.body.appendChild(menu);
    const rect = menu.getBoundingClientRect();
    let posX = x;
    let posY = y;

    if (posX + rect.width > window.innerWidth) {
      posX = Math.max(10, window.innerWidth - rect.width - 10);
    }
    if (posY + rect.height > window.innerHeight) {
      posY = Math.max(10, window.innerHeight - rect.height - 10);
    }

    menu.style.left = posX + 'px';
    menu.style.top = posY + 'px';

    activeContextMenu = menu;
  };

  if (typeof window !== 'undefined') {
    window.addEventListener('click', () => EX.closeContextMenu());
    window.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') EX.closeContextMenu();
    });
  }

  EX.renderList = function (items) {
    const allSelected = items.length > 0 && items.every((item) => EX.state.selection.has(item.id));

    const checkAll = h('input', {
      type: 'checkbox',
      checked: allSelected,
      onclick: (e) => {
        if (e.target.checked) EX.selectAll();
        else EX.clearSelection();
      }
    });

    const header = h('div', { class: 'list-header' },
      h('div', { class: 'col-check' }, checkAll),
      h('div', { class: 'col-name sortable', onclick: () => setSort('name') }, EX.t('table.name'), getSortArrow('name')),
      h('div', { class: 'col-tags' }, EX.t('table.tags')),
      h('div', { class: 'col-size sortable', onclick: () => setSort('size') }, EX.t('table.size'), getSortArrow('size')),
      h('div', { class: 'col-date sortable', onclick: () => setSort('date') }, EX.t('table.date'), getSortArrow('date'))
    );

    const listContainer = h('div', { class: 'list-body' });
    renderBatchedItems(items, listContainer, EX.renderListItem);

    return h('div', { class: 'list-view' }, header, listContainer);
  };

  EX.renderListItem = function (item) {
    const isSelected = EX.state.selection.has(item.id);
    const isFolder = item.kind === 'folder';

    const checkbox = h('input', {
      type: 'checkbox',
      checked: isSelected,
      onclick: (e) => {
        e.stopPropagation();
        EX.toggleSelect(item.id, e);
      }
    });

    let icon = isFolder ? '📁' : '📄';
    if (!isFolder) {
      if (EX.isImage(item)) icon = '🖼';
      else if (EX.isVideo(item)) icon = '🎞';
      else if (EX.isPdf(item)) icon = '📕';
      else if (EX.isText(item)) icon = '📝';
    }

    const nameText = h('span', { class: 'item-name-text' }, item.name);
    const nameEl = h('div', { class: 'col-name' },
      h('span', { class: 'item-icon' }, icon),
      nameText
    );

    if ((EX.state.mode === 'search' || EX.state.mode === 'tag') && item.pathText) {
      nameEl.appendChild(h('div', {
        class: 'item-path-sub',
        onclick: (e) => {
          e.stopPropagation();
          if (item.parentId) EX.navigate(item.parentId);
        }
      }, '📂 ' + item.pathText));
    }

    // Tags column
    const tagsEl = h('div', { class: 'col-tags' });
    if (item.tagIds && item.tagIds.length > 0) {
      for (const tid of item.tagIds) {
        const tag = (EX.state.tags || []).find((t) => String(t.id) === String(tid));
        if (tag) {
          tagsEl.appendChild(h('span', {
            class: 'item-tag-badge',
            style: { backgroundColor: tag.color }
          }, tag.name));
        }
      }
    }

    // Size column
    let sizeText = '-';
    if (!isFolder) {
      if (item.codec === 'zlib' && item.storedSize && item.storedSize < item.size) {
        sizeText = `${EX.fmtBytes(item.size)} → ${EX.fmtBytes(item.storedSize)}`;
      } else {
        sizeText = EX.fmtBytes(item.size);
      }
    }
    const sizeEl = h('div', { class: 'col-size' }, sizeText);

    // Date column
    const dateEl = h('div', { class: 'col-date' }, EX.fmtDate(item.modifiedAt));

    const row = h('div', {
      class: `list-row ${isSelected ? 'selected' : ''}`,
      onclick: (e) => {
        EX.toggleSelect(item.id, e);
      },
      ondblclick: (e) => {
        e.stopPropagation();
        if (isFolder) {
          EX.navigate(item.id);
        } else {
          openItem(item);
        }
      }
    },
      h('div', { class: 'col-check' }, checkbox),
      nameEl,
      tagsEl,
      sizeEl,
      dateEl
    );

    row.dataset.nodeId = item.id;
    row.draggable = true;

    row.ondragstart = (e) => {
      if (!EX.state.selection.has(item.id)) {
        EX.setState({ selection: new Set([item.id]) });
      }
      const ids = Array.from(EX.state.selection);
      e.dataTransfer.setData('application/json', JSON.stringify(ids));
      e.dataTransfer.effectAllowed = 'move';
    };

    if (isFolder) {
      row.ondragover = (e) => {
        e.preventDefault();
        e.dataTransfer.dropEffect = 'move';
        row.classList.add('drag-over');
      };
      row.ondragleave = () => {
        row.classList.remove('drag-over');
      };
      row.ondrop = async (e) => {
        e.preventDefault();
        row.classList.remove('drag-over');
        try {
          const raw = e.dataTransfer.getData('application/json');
          if (raw) {
            const ids = JSON.parse(raw);
            if (Array.isArray(ids) && !ids.includes(item.id)) {
              await EX.api.move(ids, item.id);
              EX.reload();
            }
          }
        } catch (_) {}
      };
    }

    row.oncontextmenu = (e) => {
      e.preventDefault();
      EX.openContextMenu(e.clientX, e.clientY, item);
    };

    attachTouchLongPress(row, (x, y) => {
      EX.openContextMenu(x, y, item);
    });

    return row;
  };

  EX.renderGrid = function (items) {
    const grid = h('div', {
      class: `grid-view grid-size-${EX.state.gridSize || 'M'} grid-fit-${EX.state.gridFit || 'contain'}`
    });

    renderBatchedItems(items, grid, EX.renderGridCard);
    return grid;
  };

  EX.renderGridCard = function (item) {
    const isSelected = EX.state.selection.has(item.id);
    const isFolder = item.kind === 'folder';

    const checkbox = h('input', {
      type: 'checkbox',
      class: 'grid-check',
      checked: isSelected,
      onclick: (e) => {
        e.stopPropagation();
        EX.toggleSelect(item.id, e);
      }
    });

    let preview = null;
    if (!isFolder && item.hasThumb) {
      preview = h('img', {
        class: 'grid-thumb',
        alt: item.name
      });
      bindLazyThumb(preview, EX.api.thumbUrl(item.id));
    } else {
      let icon = isFolder ? '📁' : '📄';
      if (!isFolder) {
        if (EX.isImage(item)) icon = '🖼';
        else if (EX.isVideo(item)) icon = '🎞';
        else if (EX.isPdf(item)) icon = '📕';
        else if (EX.isText(item)) icon = '📝';
      }
      preview = h('span', { class: 'grid-icon-placeholder' }, icon);
    }

    const nameEl = h('div', { class: 'grid-name', title: item.name }, item.name);

    if ((EX.state.mode === 'search' || EX.state.mode === 'tag') && item.pathText) {
      nameEl.appendChild(h('div', {
        class: 'item-path-sub',
        onclick: (e) => {
          e.stopPropagation();
          if (item.parentId) EX.navigate(item.parentId);
        }
      }, '📂 ' + item.pathText));
    }

    const card = h('div', {
      class: `grid-card ${isSelected ? 'selected' : ''}`,
      onclick: (e) => {
        EX.toggleSelect(item.id, e);
      },
      ondblclick: (e) => {
        e.stopPropagation();
        if (isFolder) EX.navigate(item.id);
        else openItem(item);
      }
    },
      checkbox,
      h('div', { class: 'grid-thumb-container' }, preview),
      nameEl
    );

    card.dataset.nodeId = item.id;
    card.draggable = true;

    card.ondragstart = (e) => {
      if (!EX.state.selection.has(item.id)) {
        EX.setState({ selection: new Set([item.id]) });
      }
      const ids = Array.from(EX.state.selection);
      e.dataTransfer.setData('application/json', JSON.stringify(ids));
      e.dataTransfer.effectAllowed = 'move';
    };

    if (isFolder) {
      card.ondragover = (e) => {
        e.preventDefault();
        e.dataTransfer.dropEffect = 'move';
        card.classList.add('drag-over');
      };
      card.ondragleave = () => {
        card.classList.remove('drag-over');
      };
      card.ondrop = async (e) => {
        e.preventDefault();
        card.classList.remove('drag-over');
        try {
          const raw = e.dataTransfer.getData('application/json');
          if (raw) {
            const ids = JSON.parse(raw);
            if (Array.isArray(ids) && !ids.includes(item.id)) {
              await EX.api.move(ids, item.id);
              EX.reload();
            }
          }
        } catch (_) {}
      };
    }

    card.oncontextmenu = (e) => {
      e.preventDefault();
      EX.openContextMenu(e.clientX, e.clientY, item);
    };

    attachTouchLongPress(card, (x, y) => {
      EX.openContextMenu(x, y, item);
    });

    return card;
  };

  function openItem(node) {
    if (EX.viewer && typeof EX.viewer.open === 'function') {
      EX.viewer.open(node.id, EX.state.items);
    } else {
      window.open(EX.api.contentUrl(node.id, true), '_blank');
    }
  }

  function setSort(key) {
    let order = 'asc';
    if (EX.state.sort === key) {
      order = EX.state.order === 'asc' ? 'desc' : 'asc';
    }
    EX.setState({ sort: key, order });
    EX.reload();
  }

  function getSortArrow(key) {
    if (EX.state.sort !== key) return '';
    return EX.state.order === 'asc' ? ' ↑' : ' ↓';
  }

  // Selection management
  EX.toggleSelect = function (id, event = {}) {
    const sel = new Set(EX.state.selection);

    if (event.shiftKey && lastSelectedId) {
      const items = EX.state.items || [];
      const idx1 = items.findIndex((i) => i.id === lastSelectedId);
      const idx2 = items.findIndex((i) => i.id === id);
      if (idx1 !== -1 && idx2 !== -1) {
        const start = Math.min(idx1, idx2);
        const end = Math.max(idx1, idx2);
        for (let i = start; i <= end; i++) {
          sel.add(items[i].id);
        }
      }
    } else if (event.ctrlKey || event.metaKey) {
      if (sel.has(id)) sel.delete(id);
      else sel.add(id);
      lastSelectedId = id;
    } else {
      if (event.target && event.target.type === 'checkbox') {
        if (event.target.checked) sel.add(id);
        else sel.delete(id);
      } else {
        if (sel.has(id) && sel.size === 1) {
          sel.clear();
        } else {
          sel.clear();
          sel.add(id);
        }
      }
      lastSelectedId = id;
    }

    EX.setState({ selection: sel });
  };

  EX.selectAll = function () {
    const sel = new Set((EX.state.items || []).map((i) => i.id));
    EX.setState({ selection: sel });
  };

  EX.clearSelection = function () {
    EX.setState({ selection: new Set() });
  };

  // Dialogs & Actions
  EX.promptNewFolder = function () {
    openModal(EX.t('dialog.new_folder_title'), (content, close) => {
      const input = h('input', { type: 'text', class: 'form-input', placeholder: EX.t('dialog.new_folder_prompt') });
      const submit = async () => {
        const name = input.value.trim();
        if (!name) return;
        try {
          await EX.api.createFolder(EX.state.parent, name);
          close();
          EX.reload();
        } catch (err) {
          EX.toast(EX.t('err.' + err.code), 'error');
        }
      };

      input.onkeydown = (e) => {
        if (e.key === 'Enter') submit();
      };

      content.appendChild(input);
      content.appendChild(h('div', { class: 'modal-actions' },
        h('button', { class: 'btn', onclick: close }, EX.t('action.cancel')),
        h('button', { class: 'btn btn-primary', onclick: submit }, EX.t('action.create'))
      ));

      setTimeout(() => input.focus(), 50);
    });
  };

  // In-place rename
  EX.promptRename = function (node) {
    if (!node) return;
    const nameEl = document.querySelector(`[data-node-id="${node.id}"] .item-name-text`) ||
                   document.querySelector(`[data-node-id="${node.id}"] .grid-name`);
    if (!nameEl) {
      EX.promptRenameSelected();
      return;
    }

    const origContent = nameEl.textContent;
    nameEl.textContent = '';

    const input = h('input', {
      type: 'text',
      class: 'inline-rename-input',
      value: node.name
    });

    let committed = false;
    async function commit(save) {
      if (committed) return;
      committed = true;
      const newName = input.value.trim();

      if (!save || !newName || newName === node.name) {
        nameEl.textContent = origContent;
        return;
      }

      try {
        await EX.api.rename(node.id, newName);
        EX.reload();
      } catch (err) {
        nameEl.textContent = origContent;
        EX.toast(EX.t('err.' + err.code), 'error');
      }
    }

    input.onkeydown = (e) => {
      e.stopPropagation();
      if (e.key === 'Enter') commit(true);
      else if (e.key === 'Escape') commit(false);
    };

    input.onblur = () => commit(true);

    nameEl.appendChild(input);
    input.focus();

    const dot = node.name.lastIndexOf('.');
    if (dot > 0 && node.kind === 'file') {
      input.setSelectionRange(0, dot);
    } else {
      input.select();
    }
  };

  EX.promptRenameSelected = function () {
    const ids = Array.from(EX.state.selection);
    if (ids.length !== 1) return;
    const node = (EX.state.items || []).find((i) => i.id === ids[0]);
    if (!node) return;

    openModal(EX.t('dialog.rename_title'), (content, close) => {
      const input = h('input', { type: 'text', class: 'form-input', value: node.name });
      const submit = async () => {
        const name = input.value.trim();
        if (!name || name === node.name) {
          close();
          return;
        }
        try {
          await EX.api.rename(node.id, name);
          close();
          EX.reload();
        } catch (err) {
          EX.toast(EX.t('err.' + err.code), 'error');
        }
      };

      input.onkeydown = (e) => {
        if (e.key === 'Enter') submit();
      };

      content.appendChild(input);
      content.appendChild(h('div', { class: 'modal-actions' },
        h('button', { class: 'btn', onclick: close }, EX.t('action.cancel')),
        h('button', { class: 'btn btn-primary', onclick: submit }, EX.t('action.save'))
      ));

      setTimeout(() => {
        input.focus();
        const dot = node.name.lastIndexOf('.');
        if (dot > 0 && node.kind === 'file') {
          input.setSelectionRange(0, dot);
        } else {
          input.select();
        }
      }, 50);
    });
  };

  EX.bulkTrash = function () {
    const ids = Array.from(EX.state.selection);
    if (ids.length === 0) return;
    EX.confirmDialog(EX.t('dialog.confirm_delete_msg', { count: ids.length }), async () => {
      try {
        await EX.api.trash(ids);
        EX.reload();
      } catch (err) {
        EX.toast(EX.t('err.' + err.code), 'error');
      }
    });
  };

  EX.bulkRestore = function () {
    const ids = Array.from(EX.state.selection);
    if (ids.length === 0) return;
    EX.api.restore(ids).then(() => EX.reload()).catch((err) => EX.toast(EX.t('err.' + err.code), 'error'));
  };

  EX.bulkPurge = function () {
    const ids = Array.from(EX.state.selection);
    if (ids.length === 0) return;
    EX.confirmDialog(EX.t('dialog.confirm_purge_msg', { count: ids.length }), async () => {
      try {
        await EX.api.purge(ids);
        EX.reload();
      } catch (err) {
        EX.toast(EX.t('err.' + err.code), 'error');
      }
    });
  };

  EX.emptyTrashDialog = function () {
    EX.confirmDialog(EX.t('dialog.confirm_empty_trash'), async () => {
      try {
        await EX.api.emptyTrash();
        EX.reload();
      } catch (err) {
        EX.toast(EX.t('err.' + err.code), 'error');
      }
    });
  };

  EX.bulkDownload = function () {
    const ids = Array.from(EX.state.selection);
    if (ids.length === 0) return;
    if (ids.length === 1) {
      const item = (EX.state.items || []).find((i) => i.id === ids[0]);
      if (item && item.kind === 'file') {
        window.open(EX.api.contentUrl(item.id, true), '_self');
        return;
      }
    }
    EX.api.zipDownload(ids);
  };

  EX.openMoveDialog = function (ids) {
    if (!ids || ids.length === 0) return;

    openModal(EX.t('dialog.move_title'), (content, close) => {
      let selectedTargetId = null;
      const treeContainer = h('div', { class: 'folder-tree-container' });

      // Root level choice
      const rootRow = h('div', {
        class: 'tree-node-row selected',
        onclick: () => {
          treeContainer.querySelectorAll('.tree-node-row').forEach((r) => r.classList.remove('selected'));
          rootRow.classList.add('selected');
          selectedTargetId = null;
        }
      }, h('span', { class: 'tree-expander' }, ' '), h('span', {}, '📦 ' + EX.t('nav.all_files')));
      treeContainer.appendChild(rootRow);

      async function buildFolderTree(parentFolderId, container, isForbiddenParent = false) {
        try {
          const res = await EX.api.listNodes(parentFolderId, 'name', 'asc');
          const folders = (res.items || []).filter((i) => i.kind === 'folder');

          for (const f of folders) {
            const isSelfOrDescendant = isForbiddenParent || ids.includes(f.id);
            const childrenContainer = h('div', { class: 'tree-children', style: { display: 'none' } });
            let isLoaded = false;
            let isExpanded = false;

            const expander = h('span', { class: 'tree-expander' }, '▶');
            const row = h('div', {
              class: `tree-node-row ${isSelfOrDescendant ? 'disabled' : ''}`,
              onclick: (e) => {
                e.stopPropagation();
                if (isSelfOrDescendant) return;
                treeContainer.querySelectorAll('.tree-node-row').forEach((r) => r.classList.remove('selected'));
                row.classList.add('selected');
                selectedTargetId = f.id;
              }
            }, expander, h('span', {}, '📁 ' + f.name));

            expander.onclick = async (e) => {
              e.stopPropagation();
              isExpanded = !isExpanded;
              expander.textContent = isExpanded ? '▼' : '▶';
              childrenContainer.style.display = isExpanded ? 'flex' : 'none';

              if (isExpanded && !isLoaded) {
                isLoaded = true;
                await buildFolderTree(f.id, childrenContainer, isSelfOrDescendant);
              }
            };

            const nodeWrap = h('div', { class: 'tree-node-wrap' }, row, childrenContainer);
            container.appendChild(nodeWrap);
          }
        } catch (_) {}
      }

      buildFolderTree(null, treeContainer);

      const submit = async () => {
        try {
          await EX.api.move(ids, selectedTargetId);
          close();
          EX.reload();
        } catch (err) {
          EX.toast(EX.t('err.' + err.code), 'error');
        }
      };

      content.appendChild(treeContainer);
      content.appendChild(h('div', { class: 'modal-actions' },
        h('button', { class: 'btn', onclick: close }, EX.t('action.cancel')),
        h('button', { class: 'btn btn-primary', onclick: submit }, EX.t('action.move'))
      ));
    });
  };

  EX.openTagDialog = function (ids) {
    if (!ids || ids.length === 0) return;

    openModal(EX.t('dialog.tag_title'), (content, close) => {
      const tagsList = h('div', { class: 'tags-dialog-list' });
      const checkedTags = new Set();
      const initialTags = new Set();

      if (ids.length === 1) {
        const item = (EX.state.items || []).find((i) => i.id === ids[0]);
        if (item && item.tagIds) {
          for (const tid of item.tagIds) {
            checkedTags.add(tid);
            initialTags.add(tid);
          }
        }
      }

      function renderTagRows() {
        tagsList.textContent = '';
        for (const tag of EX.state.tags || []) {
          const checkbox = h('input', {
            type: 'checkbox',
            checked: checkedTags.has(tag.id),
            onchange: (e) => {
              if (e.target.checked) checkedTags.add(tag.id);
              else checkedTags.delete(tag.id);
            }
          });

          const dot = h('span', { class: 'tag-dot', style: { backgroundColor: tag.color } });
          const nameSpan = h('span', { style: { flex: '1' } }, tag.name);

          const editBtn = h('button', {
            class: 'btn btn-icon',
            title: EX.t('dialog.edit_tag'),
            onclick: (e) => {
              e.preventDefault();
              e.stopPropagation();
              editTagDialog(tag);
            }
          }, '✎');

          const delBtn = h('button', {
            class: 'btn btn-icon',
            title: EX.t('action.delete'),
            onclick: (e) => {
              e.preventDefault();
              e.stopPropagation();
              deleteTagPrompt(tag);
            }
          }, '🗑');

          const row = h('div', { class: 'tag-manager-row' },
            h('label', { class: 'tag-label-wrap' }, checkbox, dot, nameSpan),
            h('div', { class: 'tag-row-actions' }, editBtn, delBtn)
          );

          tagsList.appendChild(row);
        }
      }

      renderTagRows();

      const newTagName = h('input', { type: 'text', class: 'form-input', placeholder: EX.t('dialog.new_tag_name') });
      const newTagColor = h('input', { type: 'color', class: 'color-picker', value: '#3b82f6' });
      const addTagBtn = h('button', {
        class: 'btn',
        onclick: async () => {
          const name = newTagName.value.trim();
          if (!name) return;
          try {
            const created = await EX.api.createTag(name, newTagColor.value);
            EX.state.tags = EX.state.tags || [];
            EX.state.tags.push(created);
            checkedTags.add(created.id);
            newTagName.value = '';
            renderTagRows();
          } catch (err) {
            EX.toast(EX.t('err.' + err.code), 'error');
          }
        }
      }, '+ ' + EX.t('dialog.new_tag_add'));

      const newTagSection = h('div', { class: 'new-tag-section' }, newTagName, newTagColor, addTagBtn);

      function editTagDialog(tag) {
        openModal(EX.t('dialog.edit_tag'), (editContent, editClose) => {
          const nameInput = h('input', { type: 'text', class: 'form-input', value: tag.name });
          const colorInput = h('input', { type: 'color', class: 'color-picker', value: tag.color || '#3b82f6' });
          const saveBtn = h('button', {
            class: 'btn btn-primary',
            onclick: async () => {
              const newName = nameInput.value.trim();
              if (!newName) return;
              try {
                const updated = await EX.api.updateTag(tag.id, { name: newName, color: colorInput.value });
                const idx = EX.state.tags.findIndex((t) => t.id === tag.id);
                if (idx !== -1) EX.state.tags[idx] = updated;
                editClose();
                renderTagRows();
              } catch (err) {
                EX.toast(EX.t('err.' + err.code), 'error');
              }
            }
          }, EX.t('action.save'));

          editContent.appendChild(nameInput);
          editContent.appendChild(colorInput);
          editContent.appendChild(h('div', { class: 'modal-actions' },
            h('button', { class: 'btn', onclick: editClose }, EX.t('action.cancel')),
            saveBtn
          ));
        });
      }

      function deleteTagPrompt(tag) {
        EX.confirmDialog(EX.t('dialog.tag_confirm_delete'), async () => {
          try {
            await EX.api.deleteTag(tag.id);
            EX.state.tags = (EX.state.tags || []).filter((t) => t.id !== tag.id);
            checkedTags.delete(tag.id);
            renderTagRows();
          } catch (err) {
            EX.toast(EX.t('err.' + err.code), 'error');
          }
        });
      }

      const submit = async () => {
        try {
          const add = Array.from(checkedTags).filter((t) => !initialTags.has(t));
          const remove = Array.from(initialTags).filter((t) => !checkedTags.has(t));
          if (add.length > 0 || remove.length > 0) {
            await EX.api.tagNodes(ids, add, remove);
          }
          close();
          EX.reload();
        } catch (err) {
          EX.toast(EX.t('err.' + err.code), 'error');
        }
      };

      content.appendChild(tagsList);
      content.appendChild(newTagSection);
      content.appendChild(h('div', { class: 'modal-actions' },
        h('button', { class: 'btn', onclick: close }, EX.t('action.cancel')),
        h('button', { class: 'btn btn-primary', onclick: submit }, EX.t('action.save'))
      ));
    });
  };

  EX.confirmDialog = function (msg, onConfirm) {
    openModal(EX.t('dialog.confirm_delete_title'), (content, close) => {
      content.appendChild(h('p', { class: 'confirm-msg' }, msg));
      content.appendChild(h('div', { class: 'modal-actions' },
        h('button', { class: 'btn', onclick: close }, EX.t('action.cancel')),
        h('button', {
          class: 'btn btn-danger',
          onclick: () => {
            close();
            if (typeof onConfirm === 'function') onConfirm();
          }
        }, EX.t('action.delete'))
      ));
    });
  };

  EX.openSettingsDialog = function () {
    openModal(EX.t('settings.title'), (content, close) => {
      const isCompress = typeof localStorage !== 'undefined' && localStorage.getItem('exv.imgCompress') === '1';
      const curMaxEdge = (typeof localStorage !== 'undefined' ? localStorage.getItem('exv.maxEdge') : null) || '2560';
      const curQuality = (typeof localStorage !== 'undefined' ? localStorage.getItem('exv.imgQuality') : null) || '0.82';
      const curGridSize = (typeof localStorage !== 'undefined' ? localStorage.getItem('exv.gridSize') : null) || 'M';
      const curFit = (typeof localStorage !== 'undefined' ? localStorage.getItem('exv.fit') : null) || 'contain';

      const compressCheck = h('input', { type: 'checkbox', id: 'setting-compress', checked: isCompress });
      const compressLabel = h('label', { for: 'setting-compress', class: 'setting-checkbox-label' }, EX.t('settings.img_compress'));

      const maxEdgeSelect = h('select', { class: 'form-input' },
        h('option', { value: '1280', selected: curMaxEdge === '1280' }, '1280 px'),
        h('option', { value: '1920', selected: curMaxEdge === '1920' }, '1920 px'),
        h('option', { value: '2560', selected: curMaxEdge === '2560' }, '2560 px (default)'),
        h('option', { value: '0', selected: curMaxEdge === '0' }, EX.t('settings.keep_orig'))
      );

      const qualitySelect = h('select', { class: 'form-input' },
        h('option', { value: '0.7', selected: curQuality === '0.7' }, '0.70'),
        h('option', { value: '0.8', selected: curQuality === '0.8' }, '0.80'),
        h('option', { value: '0.82', selected: curQuality === '0.82' }, '0.82 (default)'),
        h('option', { value: '0.85', selected: curQuality === '0.85' }, '0.85')
      );

      const gridSizeSelect = h('select', { class: 'form-input' },
        h('option', { value: 'S', selected: curGridSize === 'S' }, 'S (96px)'),
        h('option', { value: 'M', selected: curGridSize === 'M' }, 'M (160px)'),
        h('option', { value: 'L', selected: curGridSize === 'L' }, 'L (240px)')
      );

      const fitSelect = h('select', { class: 'form-input' },
        h('option', { value: 'contain', selected: curFit === 'contain' }, 'Contain'),
        h('option', { value: 'cover', selected: curFit === 'cover' }, 'Cover')
      );

      const compressGroup = h('div', { class: 'form-group' },
        h('div', { style: { display: 'flex', alignItems: 'center', gap: '8px' } }, compressCheck, compressLabel),
        h('div', { class: 'form-hint' }, EX.t('settings.exif_warning'))
      );

      const maxEdgeGroup = h('div', { class: 'form-group' },
        h('label', {}, EX.t('settings.max_edge')),
        maxEdgeSelect
      );

      const qualityGroup = h('div', { class: 'form-group' },
        h('label', {}, EX.t('settings.quality')),
        qualitySelect
      );

      const gridGroup = h('div', { class: 'form-group' },
        h('label', {}, `${EX.t('top.view_grid')}: Size`),
        gridSizeSelect
      );

      const fitGroup = h('div', { class: 'form-group' },
        h('label', {}, `${EX.t('top.view_grid')}: Fit`),
        fitSelect
      );

      const submit = () => {
        if (typeof localStorage !== 'undefined') {
          localStorage.setItem('exv.imgCompress', compressCheck.checked ? '1' : '0');
          localStorage.setItem('exv.maxEdge', maxEdgeSelect.value);
          localStorage.setItem('exv.imgQuality', qualitySelect.value);
          localStorage.setItem('exv.gridSize', gridSizeSelect.value);
          localStorage.setItem('exv.fit', fitSelect.value);
        }
        close();
        EX.render();
      };

      content.appendChild(compressGroup);
      content.appendChild(maxEdgeGroup);
      content.appendChild(qualityGroup);
      content.appendChild(gridGroup);
      content.appendChild(fitGroup);

      content.appendChild(h('div', { class: 'modal-actions' },
        h('button', { class: 'btn', onclick: close }, EX.t('action.cancel')),
        h('button', { class: 'btn btn-primary', onclick: submit }, EX.t('action.save'))
      ));
    });
  };

  function openModal(title, builder) {
    const overlay = h('div', { class: 'modal-overlay' });
    const modal = h('div', { class: 'modal-box' });
    const header = h('div', { class: 'modal-header' },
      h('h3', { class: 'modal-title' }, title),
      h('button', { class: 'btn btn-icon modal-close', onclick: () => overlay.remove() }, '✕')
    );
    const body = h('div', { class: 'modal-body' });

    modal.appendChild(header);
    modal.appendChild(body);
    overlay.appendChild(modal);

    const closeFn = () => overlay.remove();
    builder(body, closeFn);

    overlay.onclick = (e) => {
      if (e.target === overlay) closeFn();
    };

    document.body.appendChild(overlay);
  }

})();
