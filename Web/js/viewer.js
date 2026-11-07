// In-browser previewer for images, videos, audio, PDF, and text (T17).
window.EX = window.EX || {};

(function () {
  'use strict';
  const EX = window.EX;
  const h = EX.h;

  let overlayEl = null;
  let keydownHandler = null;

  EX.viewer = {
    currentList: [],
    currentIndex: -1,
    isOpen: false,
    zoom: 1,
    panX: 0,
    panY: 0,
    isDragging: false,
    dragStartX: 0,
    dragStartY: 0,
    activeMediaEl: null,
    prevHash: '',

    open(nodeId, list) {
      // Guard against redundant open calls (e.g. hashchange triggered after open)
      if (EX.viewer.isOpen && EX.viewer.currentList[EX.viewer.currentIndex] && EX.viewer.currentList[EX.viewer.currentIndex].id === nodeId) {
        return;
      }

      // 1. Build list of viewable items
      const sourceList = list && list.length > 0 ? list : (EX.state.items || []);
      const viewable = sourceList.filter((n) => n && n.kind === 'file' && isViewableNode(n));

      if (viewable.length === 0) {
        // Direct download fallback if node cannot be previewed
        window.open(EX.api.contentUrl(nodeId, true), '_self');
        return;
      }

      EX.viewer.currentList = viewable;
      EX.viewer.currentIndex = viewable.findIndex((n) => n.id === nodeId);
      if (EX.viewer.currentIndex === -1) {
        EX.viewer.currentIndex = 0;
      }

      // 2. Remember previous hash
      if (!EX.viewer.isOpen) {
        EX.viewer.prevHash = window.location.hash || '#/f/root';
      }

      EX.viewer.isOpen = true;
      EX.viewer.resetZoom();

      // 3. Update hash
      const cur = EX.viewer.currentList[EX.viewer.currentIndex];
      if (cur) {
        window.location.hash = `#/v/${encodeURIComponent(cur.id)}`;
      }

      // 4. Mount overlay and render
      ensureOverlay();
      EX.viewer.renderCurrent();

      // 5. Setup keyboard shortcuts
      if (!keydownHandler) {
        keydownHandler = (e) => {
          if (!EX.viewer.isOpen) return;
          if (['INPUT', 'TEXTAREA'].includes(e.target.tagName)) return;

          if (e.key === 'Escape') {
            e.preventDefault();
            EX.viewer.close();
          } else if (e.key === 'ArrowLeft') {
            e.preventDefault();
            EX.viewer.prev();
          } else if (e.key === 'ArrowRight') {
            e.preventDefault();
            EX.viewer.next();
          } else if (e.key === '+' || e.key === '=') {
            e.preventDefault();
            EX.viewer.zoomIn();
          } else if (e.key === '-') {
            e.preventDefault();
            EX.viewer.zoomOut();
          } else if (e.key === '0') {
            e.preventDefault();
            EX.viewer.toggleFit();
          }
        };
        window.addEventListener('keydown', keydownHandler);
      }
    },

    close() {
      if (!EX.viewer.isOpen) return;

      cleanupActiveMedia();

      if (overlayEl && overlayEl.parentNode) {
        overlayEl.parentNode.removeChild(overlayEl);
        overlayEl = null;
      }

      EX.viewer.isOpen = false;
      EX.viewer.currentList = [];
      EX.viewer.currentIndex = -1;

      if (keydownHandler) {
        window.removeEventListener('keydown', keydownHandler);
        keydownHandler = null;
      }

      // Restore hash
      if (window.location.hash.startsWith('#/v/')) {
        window.location.hash = EX.viewer.prevHash || '#/f/root';
      }
    },

    next() {
      if (EX.viewer.currentIndex < EX.viewer.currentList.length - 1) {
        cleanupActiveMedia();
        EX.viewer.currentIndex++;
        EX.viewer.resetZoom();
        const cur = EX.viewer.currentList[EX.viewer.currentIndex];
        if (cur) {
          window.location.hash = `#/v/${encodeURIComponent(cur.id)}`;
        }
        EX.viewer.renderCurrent();
      }
    },

    prev() {
      if (EX.viewer.currentIndex > 0) {
        cleanupActiveMedia();
        EX.viewer.currentIndex--;
        EX.viewer.resetZoom();
        const cur = EX.viewer.currentList[EX.viewer.currentIndex];
        if (cur) {
          window.location.hash = `#/v/${encodeURIComponent(cur.id)}`;
        }
        EX.viewer.renderCurrent();
      }
    },

    resetZoom() {
      EX.viewer.zoom = 1;
      EX.viewer.panX = 0;
      EX.viewer.panY = 0;
      EX.viewer.isDragging = false;
    },

    zoomIn() {
      const img = overlayEl ? overlayEl.querySelector('.viewer-image') : null;
      if (!img) return;
      EX.viewer.zoom = Math.min(5, EX.viewer.zoom * 1.25);
      applyTransform(img);
    },

    zoomOut() {
      const img = overlayEl ? overlayEl.querySelector('.viewer-image') : null;
      if (!img) return;
      EX.viewer.zoom = Math.max(0.2, EX.viewer.zoom * 0.8);
      applyTransform(img);
    },

    toggleFit() {
      const img = overlayEl ? overlayEl.querySelector('.viewer-image') : null;
      if (!img) return;
      if (EX.viewer.zoom === 1) {
        EX.viewer.zoom = 2;
      } else {
        EX.viewer.zoom = 1;
        EX.viewer.panX = 0;
        EX.viewer.panY = 0;
      }
      applyTransform(img);
    },

    renderCurrent() {
      if (!overlayEl) return;
      const node = EX.viewer.currentList[EX.viewer.currentIndex];
      if (!node) {
        EX.viewer.close();
        return;
      }

      // Topbar Info
      const filenameEl = overlayEl.querySelector('.viewer-filename');
      if (filenameEl) filenameEl.textContent = node.name;

      const metaEl = overlayEl.querySelector('.viewer-meta');
      if (metaEl) {
        let sizeInfo = EX.fmtBytes(node.size);
        if (node.codec === 'zlib' && node.storedSize && node.storedSize < node.size) {
          sizeInfo = `${EX.fmtBytes(node.size)} → ${EX.fmtBytes(node.storedSize)}`;
        }
        const counter = `${EX.viewer.currentIndex + 1} / ${EX.viewer.currentList.length}`;
        metaEl.textContent = `${sizeInfo} • ${EX.fmtDate(node.modifiedAt)} • [${counter}]`;
      }

      // Download button link
      const dlBtn = overlayEl.querySelector('.viewer-btn-dl');
      if (dlBtn) {
        dlBtn.onclick = () => window.open(EX.api.contentUrl(node.id, true), '_self');
      }

      // Toggle Image controls visibility in topbar
      const imgControls = overlayEl.querySelector('.viewer-image-controls');
      const isImg = EX.isImage(node);
      if (imgControls) {
        imgControls.style.display = isImg ? 'flex' : 'none';
      }

      // Navigation Buttons
      const prevBtn = overlayEl.querySelector('.viewer-nav-prev');
      const nextBtn = overlayEl.querySelector('.viewer-nav-next');
      if (prevBtn) prevBtn.style.display = EX.viewer.currentIndex > 0 ? 'flex' : 'none';
      if (nextBtn) nextBtn.style.display = EX.viewer.currentIndex < EX.viewer.currentList.length - 1 ? 'flex' : 'none';

      // Body Preview Container
      const bodyEl = overlayEl.querySelector('.viewer-body');
      const contentContainer = overlayEl.querySelector('.viewer-content-container');
      if (!contentContainer) return;

      contentContainer.textContent = '';
      cleanupActiveMedia();

      if (isImg) {
        renderImage(node, contentContainer);
        // Preload next image (1 image only)
        preloadNext();
      } else if (EX.isVideo(node)) {
        renderVideo(node, contentContainer);
      } else if (isAudioNode(node)) {
        renderAudio(node, contentContainer);
      } else if (EX.isPdf(node)) {
        renderPdf(node, contentContainer);
      } else if (EX.isText(node)) {
        renderText(node, contentContainer);
      } else {
        renderFallback(node, contentContainer);
      }
    }
  };

  function isViewableNode(node) {
    if (!node || node.kind === 'folder') return false;
    return EX.isImage(node) || EX.isVideo(node) || isAudioNode(node) || EX.isPdf(node) || EX.isText(node);
  }

  function isAudioNode(node) {
    if (!node) return false;
    if (node.mime && node.mime.startsWith('audio/')) return true;
    const e = EX.ext(node.name);
    return ['mp3', 'm4a', 'aac', 'wav', 'ogg', 'flac'].includes(e);
  }

  function ensureOverlay() {
    if (overlayEl) return;

    overlayEl = h('div', { class: 'viewer-overlay' });

    // Topbar
    const infoCol = h('div', { class: 'viewer-info' },
      h('div', { class: 'viewer-filename' }, ''),
      h('div', { class: 'viewer-meta' }, '')
    );

    const imgControls = h('div', { class: 'viewer-actions viewer-image-controls' },
      h('button', {
        class: 'btn btn-icon',
        title: EX.t('viewer.zoom_out'),
        onclick: () => EX.viewer.zoomOut()
      }, '−'),
      h('button', {
        class: 'btn btn-icon',
        title: EX.t('viewer.zoom_in'),
        onclick: () => EX.viewer.zoomIn()
      }, '+'),
      h('button', {
        class: 'btn btn-icon',
        title: EX.t('viewer.fit'),
        onclick: () => EX.viewer.toggleFit()
      }, '⤢')
    );

    const actionsCol = h('div', { class: 'viewer-actions' },
      imgControls,
      h('button', {
        class: 'btn btn-icon viewer-btn-dl',
        title: EX.t('action.download')
      }, '⬇'),
      h('button', {
        class: 'btn btn-icon',
        title: EX.t('action.close'),
        onclick: () => EX.viewer.close()
      }, '✕')
    );

    const topbar = h('header', { class: 'viewer-topbar' }, infoCol, actionsCol);

    // Nav arrows
    const prevBtn = h('button', {
      class: 'viewer-nav-btn viewer-nav-prev',
      title: EX.t('viewer.prev'),
      onclick: (e) => {
        e.stopPropagation();
        EX.viewer.prev();
      }
    }, '❮');

    const nextBtn = h('button', {
      class: 'viewer-nav-btn viewer-nav-next',
      title: EX.t('viewer.next'),
      onclick: (e) => {
        e.stopPropagation();
        EX.viewer.next();
      }
    }, '❯');

    const contentContainer = h('div', { class: 'viewer-content-container' });

    const body = h('div', {
      class: 'viewer-body',
      onclick: (e) => {
        if (e.target === body) {
          EX.viewer.close();
        }
      }
    }, prevBtn, nextBtn, contentContainer);

    overlayEl.appendChild(topbar);
    overlayEl.appendChild(body);

    document.body.appendChild(overlayEl);
  }

  function cleanupActiveMedia() {
    if (EX.viewer.activeMediaEl) {
      try {
        const el = EX.viewer.activeMediaEl;
        el.pause();
        el.removeAttribute('src');
        el.load();
      } catch (_) {}
      EX.viewer.activeMediaEl = null;
    }
  }

  function applyTransform(img) {
    if (!img) return;
    img.style.transform = `translate(${EX.viewer.panX}px, ${EX.viewer.panY}px) scale(${EX.viewer.zoom})`;
  }

  function renderImage(node, container) {
    const img = h('img', {
      class: 'viewer-image',
      src: EX.api.contentUrl(node.id),
      alt: node.name
    });

    applyTransform(img);

    // Mouse drag pan
    img.onmousedown = (e) => {
      if (EX.viewer.zoom <= 1) return;
      e.preventDefault();
      EX.viewer.isDragging = true;
      EX.viewer.dragStartX = e.clientX - EX.viewer.panX;
      EX.viewer.dragStartY = e.clientY - EX.viewer.panY;
      img.classList.add('dragging');
    };

    window.onmousemove = (e) => {
      if (!EX.viewer.isDragging) return;
      EX.viewer.panX = e.clientX - EX.viewer.dragStartX;
      EX.viewer.panY = e.clientY - EX.viewer.dragStartY;
      applyTransform(img);
    };

    window.onmouseup = () => {
      if (EX.viewer.isDragging) {
        EX.viewer.isDragging = false;
        img.classList.remove('dragging');
      }
    };

    // Wheel zoom
    img.onwheel = (e) => {
      e.preventDefault();
      if (e.deltaY < 0) {
        EX.viewer.zoom = Math.min(5, EX.viewer.zoom * 1.15);
      } else {
        EX.viewer.zoom = Math.max(0.2, EX.viewer.zoom * 0.85);
      }
      applyTransform(img);
    };

    // Double click to toggle 100% / Fit
    img.ondblclick = (e) => {
      e.stopPropagation();
      EX.viewer.toggleFit();
    };

    container.appendChild(img);
  }

  function renderVideo(node, container) {
    const video = h('video', {
      class: 'viewer-media-video',
      controls: true,
      preload: 'metadata',
      playsinline: true,
      autoplay: true
    });

    video.src = EX.api.contentUrl(node.id);
    EX.viewer.activeMediaEl = video;

    video.onerror = () => {
      const err = video.error;
      console.error('[ExVault] Video playback error:', err, 'code:', err ? err.code : 'unknown', 'src:', video.src);
      let errorMsg = EX.t('viewer.unsupported_video');
      if (err && err.code === 2) {
        errorMsg = EX.t('viewer.video_network_error') || EX.t('err.busy');
      }
      container.textContent = '';
      container.appendChild(h('div', { class: 'viewer-error-box' },
        h('span', { style: { fontSize: '48px' } }, '⚠️'),
        h('p', {}, errorMsg),
        h('button', {
          class: 'btn btn-primary',
          onclick: () => window.open(EX.api.contentUrl(node.id, true), '_self')
        }, EX.t('action.download'))
      ));
    };

    container.appendChild(video);
  }

  function renderAudio(node, container) {
    const audio = h('audio', {
      class: 'viewer-media-audio',
      controls: true,
      preload: 'metadata',
      autoplay: true
    });

    audio.src = EX.api.contentUrl(node.id);
    EX.viewer.activeMediaEl = audio;

    container.appendChild(audio);
  }

  function renderPdf(node, container) {
    const iframe = h('iframe', {
      class: 'viewer-pdf-frame',
      src: EX.api.contentUrl(node.id)
    });

    container.appendChild(iframe);
  }

  async function renderText(node, container) {
    const loadingEl = h('div', { style: { color: '#ffffff' } }, EX.t('viewer.loading'));
    container.appendChild(loadingEl);

    const isRaw = node.codec === 'raw';
    const fetchHeaders = {};
    if (isRaw) {
      // Fetch up to 512KB via Range header
      fetchHeaders['Range'] = 'bytes=0-524287';
    }

    try {
      const resp = await fetch(EX.api.contentUrl(node.id), {
        credentials: 'same-origin',
        headers: fetchHeaders
      });

      if (!resp.ok && resp.status !== 206) {
        throw new Error(`HTTP ${resp.status}`);
      }

      let text = await resp.text();
      let isTruncated = false;

      if (!isRaw && text.length > 524288) {
        text = text.slice(0, 524288);
        isTruncated = true;
      } else if (node.size > 524288) {
        isTruncated = true;
      }

      container.textContent = '';

      const box = h('div', { class: 'viewer-text-box' });
      if (isTruncated) {
        box.appendChild(h('div', { class: 'viewer-text-notice' }, EX.t('viewer.text_truncated')));
      }

      const pre = h('pre', { class: 'viewer-text-content' });
      pre.textContent = text;
      box.appendChild(pre);

      container.appendChild(box);
    } catch (_) {
      container.textContent = '';
      renderFallback(node, container);
    }
  }

  function renderFallback(node, container) {
    container.appendChild(h('div', { class: 'viewer-error-box' },
      h('span', { style: { fontSize: '48px' } }, '📄'),
      h('p', {}, node.name),
      h('button', {
        class: 'btn btn-primary',
        onclick: () => window.open(EX.api.contentUrl(node.id, true), '_self')
      }, EX.t('action.download'))
    ));
  }

  function preloadNext() {
    if (EX.viewer.currentIndex + 1 < EX.viewer.currentList.length) {
      const nextNode = EX.viewer.currentList[EX.viewer.currentIndex + 1];
      if (EX.isImage(nextNode)) {
        const img = new Image();
        img.src = EX.api.contentUrl(nextNode.id);
      }
    }
  }

})();
