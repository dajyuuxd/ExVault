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

    const searchInput = h('input', {
      type: 'search',
      class: 'search-input',
      placeholder: EX.t('top.search_placeholder'),
      value: EX.state.query || '',
      onkeydown: (e) => {
        if (e.key === 'Enter') {
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
      h('div', { class: 'topbar-right' }, viewToggleBtn, langToggleBtn, themeToggleBtn, logoutBtn)
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

      bar.appendChild(h('button', {
        class: 'btn btn-primary',
        onclick: () => fileInput.click()
      }, '↑ ' + EX.t('action.upload')));

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
    for (const item of items) {
      listContainer.appendChild(EX.renderListItem(item));
    }

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

    const nameEl = h('div', { class: 'col-name' },
      h('span', { class: 'item-icon' }, icon),
      h('span', { class: 'item-name-text' }, item.name)
    );

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

    return row;
  };

  EX.renderGrid = function (items) {
    const grid = h('div', {
      class: `grid-view grid-size-${EX.state.gridSize || 'M'} grid-fit-${EX.state.gridFit || 'contain'}`
    });

    for (const item of items) {
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
          src: EX.api.thumbUrl(item.id),
          loading: 'lazy',
          decoding: 'async',
          class: 'grid-thumb',
          alt: item.name
        });
      } else {
        let icon = isFolder ? '📁' : '📄';
        if (!isFolder) {
          if (EX.isImage(item)) icon = '🖼';
          else if (EX.isVideo(item)) icon = '🎞';
          else if (EX.isPdf(item)) icon = '📕';
        }
        preview = h('span', { class: 'grid-icon-placeholder' }, icon);
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
        h('div', { class: 'grid-name', title: item.name }, item.name)
      );

      grid.appendChild(card);
    }

    return grid;
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
        // Direct click
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

      async function renderFolderLevel(parent, container) {
        const res = await EX.api.listNodes(parent, 'name', 'asc');
        const folders = (res.items || []).filter((i) => i.kind === 'folder' && !ids.includes(i.id));

        for (const f of folders) {
          const itemRow = h('div', {
            class: 'tree-item',
            onclick: () => {
              treeContainer.querySelectorAll('.tree-item').forEach((el) => el.classList.remove('selected'));
              itemRow.classList.add('selected');
              selectedTargetId = f.id;
            }
          }, '📁 ' + f.name);
          container.appendChild(itemRow);
        }
      }

      // Root level choice
      const rootItem = h('div', {
        class: 'tree-item selected',
        onclick: () => {
          treeContainer.querySelectorAll('.tree-item').forEach((el) => el.classList.remove('selected'));
          rootItem.classList.add('selected');
          selectedTargetId = null;
        }
      }, '📦 ' + EX.t('nav.all_files'));
      treeContainer.appendChild(rootItem);

      renderFolderLevel(null, treeContainer);

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

      for (const tag of EX.state.tags || []) {
        const checkbox = h('input', {
          type: 'checkbox',
          onchange: (e) => {
            if (e.target.checked) checkedTags.add(tag.id);
            else checkedTags.delete(tag.id);
          }
        });
        const tagRow = h('label', { class: 'tag-dialog-row' },
          checkbox,
          h('span', { class: 'tag-dot', style: { backgroundColor: tag.color } }),
          h('span', {}, tag.name)
        );
        tagsList.appendChild(tagRow);
      }

      // Add new tag row
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
            close();
            EX.openTagDialog(ids);
          } catch (err) {
            EX.toast(EX.t('err.' + err.code), 'error');
          }
        }
      }, '+ ' + EX.t('dialog.new_tag_add'));

      const newTagSection = h('div', { class: 'new-tag-section' }, newTagName, newTagColor, addTagBtn);

      const submit = async () => {
        try {
          const add = Array.from(checkedTags);
          await EX.api.tagNodes(ids, add, []);
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
