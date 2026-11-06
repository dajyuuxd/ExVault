// Chunked upload engine, client thumbnail generation, and client image compression.
window.EX = window.EX || {};

(function () {
  'use strict';
  const EX = window.EX;
  const h = EX.h;

  let panelEl = null;
  let closeTimer = null;
  let reloadTimer = null;
  let isQueuePaused = false;

  EX.upload = {
    queue: [],
    active: 0,
    maxParallel: 2,
    minimized: false,

    // Enqueue files (File[] or FileList or { file, parentId }[])
    enqueue(files, parentId) {
      if (!files || files.length === 0) return;
      if (closeTimer) {
        clearTimeout(closeTimer);
        closeTimer = null;
      }
      isQueuePaused = false;

      const fileList = Array.from(files);
      for (const item of fileList) {
        const file = item.file || item;
        const targetParent = item.parentId !== undefined ? item.parentId : parentId;

        const job = {
          id: 'job_' + Date.now() + '_' + Math.random().toString(36).substr(2, 6),
          file: file,
          parentId: targetParent || null,
          name: file.name,
          size: file.size,
          sent: 0,
          chunkSent: 0,
          state: 'queued', // queued | compressing | uploading | processing | done | error | canceled
          uploadId: null,
          chunkSize: 4194304,
          speed: 0,
          speedSamples: [],
          error: null,
          xhr: null,
          node: null
        };
        EX.upload.queue.push(job);
      }

      EX.upload.renderPanel();
      EX.upload.startNext();
    },

    // Traverse dragged items/directories using webkitGetAsEntry
    async enqueueEntries(items, parentId) {
      if (!items || items.length === 0) return;

      const fileEntries = [];
      const entriesToProcess = [];

      for (let i = 0; i < items.length; i++) {
        const item = items[i];
        if (typeof item.webkitGetAsEntry === 'function') {
          const entry = item.webkitGetAsEntry();
          if (entry) entriesToProcess.push(entry);
        } else if (item.getAsFile) {
          const file = item.getAsFile();
          if (file) fileEntries.push({ file, parentId });
        }
      }

      if (entriesToProcess.length > 0) {
        for (const entry of entriesToProcess) {
          const results = await traverseEntry(entry, parentId);
          fileEntries.push(...results);
        }
      }

      if (fileEntries.length > 0) {
        EX.upload.enqueue(fileEntries, parentId);
      }
    },

    startNext() {
      if (isQueuePaused) return;

      while (EX.upload.active < EX.upload.maxParallel) {
        const job = EX.upload.queue.find((j) => j.state === 'queued');
        if (!job) break;

        EX.upload.active++;
        EX.upload.uploadOne(job).finally(() => {
          EX.upload.active = Math.max(0, EX.upload.active - 1);
          EX.upload.renderPanel();
          EX.upload.startNext();
          checkAllFinished();
        });
      }
      EX.upload.renderPanel();
    },

    async uploadOne(job) {
      if (job.state === 'canceled') return;

      try {
        // 1. Maybe compress image if enabled
        job.state = 'compressing';
        EX.upload.renderPanel();

        try {
          const compressed = await EX.upload.maybeCompressImage(job.file);
          if (compressed && compressed !== job.file) {
            job.file = compressed;
            job.size = compressed.size;
          }
        } catch (_) {}

        if (job.state === 'canceled') return;

        // 2. Initiate upload session with POST /api/upload
        job.state = 'uploading';
        EX.upload.renderPanel();

        const initBody = {
          parentId: job.parentId,
          name: job.name,
          size: job.size,
          mime: job.file.type || '',
          lastModified: job.file.lastModified || Date.now()
        };

        const initResp = await requestWithRetry(
          () => EX.api.post('/api/upload', initBody),
          job
        );

        if (job.state === 'canceled') return;

        job.uploadId = initResp.uploadId;
        job.chunkSize = initResp.chunkSize || 4194304;
        job.sent = initResp.offset || 0;

        // 3. Send Chunks
        if (job.size > 0 && job.sent < job.size) {
          await EX.upload.sendChunks(job);
        }

        if (job.state === 'canceled') return;

        // 4. Finish and Poll
        await EX.upload.finishAndPoll(job);

        // 5. Generate and upload thumbnail if done
        if (job.state === 'done' && job.node && job.node.id) {
          try {
            const thumbBlob = await EX.upload.makeThumb(job.file);
            if (thumbBlob) {
              await EX.api.putThumb(job.node.id, thumbBlob);
            }
          } catch (_) {
            // Thumbnail failure does not fail the upload
          }
        }

        // Debounced reload of items view
        triggerDebouncedReload();

      } catch (err) {
        if (job.state !== 'canceled') {
          job.state = 'error';
          job.error = err.message || EX.t('err.unknown');
        }
      } finally {
        job.xhr = null;
        EX.upload.renderPanel();
      }
    },

    async sendChunks(job) {
      while (job.sent < job.size) {
        if (job.state === 'canceled') return;

        const start = job.sent;
        const end = Math.min(start + job.chunkSize, job.size);
        const chunkBlob = job.file.slice(start, end);

        let retries = 0;
        const maxRetries = 5;
        const backoff = [1000, 2000, 4000, 8000, 16000];

        while (true) {
          if (job.state === 'canceled') return;

          try {
            const newOffset = await sendOneChunk(job, start, chunkBlob);
            job.sent = newOffset;
            job.chunkSent = 0;
            break; // Chunk succeeded
          } catch (err) {
            if (job.state === 'canceled') return;

            // Check if 401 Unauthorized
            if (err.status === 401) {
              isQueuePaused = true;
              job.state = 'queued';
              if (typeof EX.onUnauthorized === 'function') {
                EX.onUnauthorized();
              }
              throw err;
            }

            // Check if 409 offset_mismatch
            if (err.status === 409) {
              if (err.extra && typeof err.extra.offset === 'number') {
                job.sent = err.extra.offset;
                job.chunkSent = 0;
                break; // Continue loop with corrected offset
              } else {
                try {
                  const st = await EX.api.get(`/api/upload/${encodeURIComponent(job.uploadId)}`);
                  if (typeof st.offset === 'number') {
                    job.sent = st.offset;
                    job.chunkSent = 0;
                    break;
                  }
                } catch (_) {}
              }
            }

            // Check if 429 or 503
            if (err.status === 429 || err.status === 503) {
              await sleep(2000);
              continue;
            }

            // Network or 5xx retry with backoff
            if (retries < maxRetries) {
              const delay = backoff[retries] || 16000;
              retries++;
              await sleep(delay);
              continue;
            }

            // Exceeded retries
            throw err;
          }
        }
      }
    },

    async finishAndPoll(job) {
      if (job.state === 'canceled') return;
      job.state = 'processing';
      EX.upload.renderPanel();

      const finishResp = await requestWithRetry(
        () => EX.api.post(`/api/upload/${encodeURIComponent(job.uploadId)}/finish`, {}),
        job
      );

      if (finishResp && finishResp.state === 'done') {
        job.state = 'done';
        job.node = finishResp.node || null;
        return;
      }

      // Poll until state is done or error
      let pollDelay = 1000;
      while (true) {
        if (job.state === 'canceled') return;
        await sleep(pollDelay);
        pollDelay = Math.min(3000, Math.round(pollDelay * 1.5));

        const statusResp = await EX.api.get(`/api/upload/${encodeURIComponent(job.uploadId)}`);
        if (statusResp.state === 'done') {
          job.state = 'done';
          job.node = statusResp.node || null;
          return;
        } else if (statusResp.state === 'error') {
          job.state = 'error';
          job.error = statusResp.error || EX.t('upload.error');
          return;
        }
      }
    },

    cancel(job) {
      if (!job) return;
      if (job.xhr) {
        try {
          job.xhr.abort();
        } catch (_) {}
        job.xhr = null;
      }
      job.state = 'canceled';
      if (job.uploadId) {
        EX.api.del(`/api/upload/${encodeURIComponent(job.uploadId)}`).catch(() => {});
      }
      EX.upload.renderPanel();
    },

    cancelAll() {
      for (const job of EX.upload.queue) {
        if (['queued', 'compressing', 'uploading', 'processing'].includes(job.state)) {
          EX.upload.cancel(job);
        }
      }
      EX.upload.renderPanel();
    },

    clearCompleted() {
      EX.upload.queue = EX.upload.queue.filter(
        (j) => !['done', 'error', 'canceled'].includes(j.state)
      );
      EX.upload.renderPanel();
    },

    async makeThumb(file) {
      if (!file) return null;

      const isImage = file.type.startsWith('image/') || /\.(jpe?g|png|webp|gif|bmp)$/i.test(file.name);
      const isVideo = file.type.startsWith('video/') || /\.(mp4|webm|mov|m4v|mkv)$/i.test(file.name);

      if (isImage) {
        return makeImageThumb(file);
      }
      if (isVideo) {
        return makeVideoThumb(file);
      }
      return null;
    },

    async maybeCompressImage(file, opts = {}) {
      if (!file) return file;
      const isCompressEnabled = (opts.enabled !== undefined)
        ? opts.enabled
        : (typeof localStorage !== 'undefined' && localStorage.getItem('exv.imgCompress') === '1');

      if (!isCompressEnabled) return file;

      const isJpeg = file.type === 'image/jpeg' || /\.jpe?g$/i.test(file.name);
      if (!isJpeg) return file;

      const maxEdge = opts.maxEdge !== undefined
        ? opts.maxEdge
        : parseInt((typeof localStorage !== 'undefined' ? localStorage.getItem('exv.maxEdge') : null) || '2560', 10);

      const quality = opts.quality !== undefined
        ? opts.quality
        : parseFloat((typeof localStorage !== 'undefined' ? localStorage.getItem('exv.imgQuality') : null) || '0.82');

      try {
        let source;
        if (typeof createImageBitmap === 'function') {
          source = await createImageBitmap(file);
        } else {
          source = await new Promise((resolve, reject) => {
            const img = new Image();
            img.onload = () => resolve(img);
            img.onerror = reject;
            img.src = URL.createObjectURL(file);
          });
        }

        let origW = source.width;
        let origH = source.height;
        let targetW = origW;
        let targetH = origH;

        if (maxEdge > 0 && (origW > maxEdge || origH > maxEdge)) {
          if (origW >= origH) {
            targetW = maxEdge;
            targetH = Math.round((origH * maxEdge) / origW);
          } else {
            targetH = maxEdge;
            targetW = Math.round((origW * maxEdge) / origH);
          }
        }

        const canvas = document.createElement('canvas');
        canvas.width = targetW;
        canvas.height = targetH;
        const ctx = canvas.getContext('2d');
        ctx.drawImage(source, 0, 0, targetW, targetH);

        if (source.close) source.close();

        const blob = await new Promise((resolve) => {
          canvas.toBlob(resolve, 'image/jpeg', quality);
        });

        // Only use compressed result if at least 10% smaller than original
        if (blob && blob.size < file.size * 0.9) {
          return new File([blob], file.name, {
            type: 'image/jpeg',
            lastModified: file.lastModified || Date.now()
          });
        }
      } catch (_) {}

      return file;
    },

    renderPanel() {
      const app = EX.$('#app');
      if (!app) return null;

      if (EX.upload.queue.length === 0) {
        if (panelEl && panelEl.parentNode) {
          panelEl.parentNode.removeChild(panelEl);
          panelEl = null;
        }
        return null;
      }

      if (!panelEl) {
        panelEl = h('div', { class: 'upload-panel' });
      }

      panelEl.textContent = '';
      if (EX.upload.minimized) {
        panelEl.classList.add('minimized');
      } else {
        panelEl.classList.remove('minimized');
      }

      // Compute statistics
      let totalBytes = 0;
      let sentBytes = 0;
      let activeCount = 0;
      let maxSpeed = 0;

      for (const j of EX.upload.queue) {
        totalBytes += j.size;
        sentBytes += (j.sent + (j.chunkSent || 0));
        if (['queued', 'compressing', 'uploading', 'processing'].includes(j.state)) {
          activeCount++;
          if (j.speed > maxSpeed) maxSpeed = j.speed;
        }
      }

      const overallPercent = totalBytes > 0 ? Math.min(100, Math.round((sentBytes / totalBytes) * 100)) : 0;

      // Header
      const headerTitle = h('div', { class: 'upload-title-wrap' },
        h('span', {}, '⬆'),
        h('span', {}, `${EX.t('upload.title')} (${activeCount > 0 ? activeCount : EX.upload.queue.length})`),
        overallPercent > 0 && activeCount > 0
          ? h('span', { class: 'upload-overall-pct' }, `${overallPercent}%`)
          : null
      );

      const minimizeBtn = h('button', {
        class: 'btn btn-icon',
        title: EX.upload.minimized ? 'Expand' : 'Minimize',
        onclick: (e) => {
          e.stopPropagation();
          EX.upload.minimized = !EX.upload.minimized;
          EX.upload.renderPanel();
        }
      }, EX.upload.minimized ? '▢' : '—');

      const clearBtn = h('button', {
        class: 'btn btn-icon',
        title: EX.t('upload.clear_done'),
        onclick: (e) => {
          e.stopPropagation();
          EX.upload.clearCompleted();
        }
      }, '🧹');

      const cancelAllBtn = activeCount > 0 ? h('button', {
        class: 'btn btn-icon',
        title: EX.t('upload.cancel_all'),
        onclick: (e) => {
          e.stopPropagation();
          EX.upload.cancelAll();
        }
      }, '✖') : null;

      const headerActions = h('div', { class: 'upload-actions' },
        clearBtn,
        cancelAllBtn,
        minimizeBtn
      );

      const header = h('div', {
        class: 'upload-header',
        onclick: () => {
          EX.upload.minimized = !EX.upload.minimized;
          EX.upload.renderPanel();
        }
      }, headerTitle, headerActions);

      // Body: list of jobs
      const body = h('div', { class: 'upload-body' });
      for (const j of EX.upload.queue) {
        const item = renderUploadJobItem(j);
        body.appendChild(item);
      }

      panelEl.appendChild(header);
      panelEl.appendChild(body);

      if (!panelEl.parentNode) {
        app.appendChild(panelEl);
      }

      return panelEl;
    }
  };

  // Render individual upload job row
  function renderUploadJobItem(job) {
    const curBytes = Math.min(job.size, job.sent + (job.chunkSent || 0));
    const pct = job.size > 0 ? Math.min(100, Math.round((curBytes / job.size) * 100)) : (job.state === 'done' ? 100 : 0);

    let statusText = '';
    let fillClass = '';

    if (job.state === 'queued') {
      statusText = EX.t('upload.title') + ' (queued)';
    } else if (job.state === 'compressing') {
      statusText = EX.t('upload.compressing');
    } else if (job.state === 'uploading') {
      const spd = job.speed > 0 ? ` • ${EX.fmtBytes(job.speed)}/s` : '';
      statusText = `${EX.fmtBytes(curBytes)} / ${EX.fmtBytes(job.size)} (${pct}%)${spd}`;
    } else if (job.state === 'processing') {
      statusText = EX.t('upload.processing');
    } else if (job.state === 'done') {
      statusText = EX.t('upload.done');
      fillClass = 'done';
    } else if (job.state === 'error') {
      statusText = `${EX.t('upload.error')}: ${job.error || ''}`;
      fillClass = 'error';
    } else if (job.state === 'canceled') {
      statusText = EX.t('upload.canceled');
      fillClass = 'error';
    }

    const nameSpan = h('span', { class: 'upload-item-name', title: job.name }, job.name);

    let actionBtn = null;
    if (['queued', 'compressing', 'uploading', 'processing'].includes(job.state)) {
      actionBtn = h('button', {
        class: 'btn btn-icon btn-upload-cancel',
        title: EX.t('action.cancel'),
        onclick: () => EX.upload.cancel(job)
      }, '✕');
    } else if (job.state === 'error') {
      actionBtn = h('button', {
        class: 'btn btn-icon',
        title: 'Retry',
        onclick: () => {
          job.state = 'queued';
          job.error = null;
          job.sent = 0;
          job.chunkSent = 0;
          EX.upload.startNext();
        }
      }, '↻');
    }

    const itemHeader = h('div', { class: 'upload-item-header' }, nameSpan, actionBtn);
    const itemStatus = h('div', { class: 'upload-item-status' }, h('span', {}, statusText));

    const progressTrack = h('div', { class: 'upload-item-progress-track' },
      h('div', {
        class: `upload-item-progress-fill ${fillClass}`,
        style: { width: `${job.state === 'done' ? 100 : pct}%` }
      })
    );

    return h('div', { class: 'upload-item' }, itemHeader, itemStatus, progressTrack);
  }

  // Send a single chunk using XMLHttpRequest to track accurate upload progress
  function sendOneChunk(job, offset, blob) {
    return new Promise((resolve, reject) => {
      const xhr = new XMLHttpRequest();
      job.xhr = xhr;

      const url = `/api/upload/${encodeURIComponent(job.uploadId)}?offset=${offset}`;
      xhr.open('PUT', url, true);
      xhr.setRequestHeader('Content-Type', 'application/octet-stream');

      xhr.upload.onprogress = (evt) => {
        if (evt.lengthComputable) {
          job.chunkSent = evt.loaded;
          recordSpeed(job, job.sent + evt.loaded);
          EX.upload.renderPanel();
        }
      };

      xhr.onload = () => {
        job.xhr = null;
        if (xhr.status >= 200 && xhr.status < 300) {
          try {
            const data = JSON.parse(xhr.responseText);
            resolve(data.offset !== undefined ? data.offset : offset + blob.size);
          } catch (_) {
            resolve(offset + blob.size);
          }
        } else {
          let errData = {};
          try {
            errData = JSON.parse(xhr.responseText);
          } catch (_) {}
          const error = new Error(errData.message || `HTTP ${xhr.status}`);
          error.status = xhr.status;
          error.code = errData.code;
          error.extra = errData.extra;
          reject(error);
        }
      };

      xhr.onerror = () => {
        job.xhr = null;
        const error = new Error('Network error');
        error.status = 0;
        reject(error);
      };

      xhr.onabort = () => {
        job.xhr = null;
        const error = new Error('Aborted');
        error.status = -1;
        reject(error);
      };

      xhr.send(blob);
    });
  }

  // Calculate 5-second moving average speed
  function recordSpeed(job, currentTotalBytes) {
    const now = Date.now();
    job.speedSamples.push({ time: now, bytes: currentTotalBytes });

    // Keep samples within the last 5000 ms
    job.speedSamples = job.speedSamples.filter((s) => now - s.time <= 5000);

    if (job.speedSamples.length >= 2) {
      const oldest = job.speedSamples[0];
      const latest = job.speedSamples[job.speedSamples.length - 1];
      const timeSec = (latest.time - oldest.time) / 1000;
      const byteDiff = latest.bytes - oldest.bytes;
      if (timeSec > 0.1) {
        job.speed = Math.max(0, byteDiff / timeSec);
      }
    }
  }

  // Make JPEG thumbnail from image
  function makeImageThumb(file) {
    return new Promise((resolve) => {
      const img = new Image();
      const url = URL.createObjectURL(file);

      img.onload = () => {
        URL.revokeObjectURL(url);
        let w = img.width;
        let h = img.height;
        const maxEdge = 320;

        if (w > maxEdge || h > maxEdge) {
          if (w >= h) {
            h = Math.round((h * maxEdge) / w);
            w = maxEdge;
          } else {
            w = Math.round((w * maxEdge) / h);
            h = maxEdge;
          }
        }

        const canvas = document.createElement('canvas');
        canvas.width = Math.max(1, w);
        canvas.height = Math.max(1, h);
        const ctx = canvas.getContext('2d');
        ctx.drawImage(img, 0, 0, w, h);

        canvas.toBlob((blob) => {
          if (blob && blob.size <= 262144) {
            resolve(blob);
          } else if (blob) {
            // Compress with lower quality if > 256KB
            canvas.toBlob((blob2) => {
              resolve(blob2 && blob2.size <= 262144 ? blob2 : null);
            }, 'image/jpeg', 0.5);
          } else {
            resolve(null);
          }
        }, 'image/jpeg', 0.7);
      };

      img.onerror = () => {
        URL.revokeObjectURL(url);
        resolve(null);
      };

      img.src = url;
    });
  }

  // Make JPEG thumbnail from video
  function makeVideoThumb(file) {
    return new Promise((resolve) => {
      const video = document.createElement('video');
      video.muted = true;
      video.playsInline = true;
      video.preload = 'metadata';
      const url = URL.createObjectURL(file);

      let timedOut = false;
      const timer = setTimeout(() => {
        timedOut = true;
        URL.revokeObjectURL(url);
        resolve(null);
      }, 8000);

      video.onloadedmetadata = () => {
        if (timedOut) return;
        const duration = video.duration || 1;
        video.currentTime = Math.min(1, duration / 10);
      };

      video.onseeked = () => {
        if (timedOut) return;
        clearTimeout(timer);

        try {
          let w = video.videoWidth || 320;
          let h = video.videoHeight || 240;
          const maxEdge = 320;

          if (w > maxEdge || h > maxEdge) {
            if (w >= h) {
              h = Math.round((h * maxEdge) / w);
              w = maxEdge;
            } else {
              w = Math.round((w * maxEdge) / h);
              h = maxEdge;
            }
          }

          const canvas = document.createElement('canvas');
          canvas.width = Math.max(1, w);
          canvas.height = Math.max(1, h);
          const ctx = canvas.getContext('2d');
          ctx.drawImage(video, 0, 0, w, h);

          URL.revokeObjectURL(url);
          canvas.toBlob((blob) => {
            resolve(blob && blob.size <= 262144 ? blob : null);
          }, 'image/jpeg', 0.7);
        } catch (_) {
          URL.revokeObjectURL(url);
          resolve(null);
        }
      };

      video.onerror = () => {
        if (timedOut) return;
        clearTimeout(timer);
        URL.revokeObjectURL(url);
        resolve(null);
      };

      video.src = url;
    });
  }

  // Recursively traverse webkitGetAsEntry directory tree
  async function traverseEntry(entry, parentId) {
    if (entry.isFile) {
      return new Promise((resolve) => {
        entry.file((file) => {
          resolve([{ file, parentId }]);
        }, () => resolve([]));
      });
    }

    if (entry.isDirectory) {
      let folderId = null;
      try {
        const created = await EX.api.createFolder(parentId, entry.name);
        folderId = created.id;
      } catch (err) {
        if (err.code === 'name_conflict') {
          try {
            const list = await EX.api.listNodes(parentId);
            const found = (list.items || []).find((n) => n.type === 'folder' && n.name === entry.name);
            if (found) folderId = found.id;
          } catch (_) {}
        }
      }

      if (!folderId) return [];

      const dirReader = entry.createReader();
      const childEntries = await readAllDirectoryEntries(dirReader);
      const results = [];
      for (const child of childEntries) {
        const sub = await traverseEntry(child, folderId);
        results.push(...sub);
      }
      return results;
    }

    return [];
  }

  function readAllDirectoryEntries(reader) {
    return new Promise((resolve) => {
      const all = [];
      function readBatch() {
        reader.readEntries((entries) => {
          if (!entries || entries.length === 0) {
            resolve(all);
          } else {
            all.push(...entries);
            readBatch();
          }
        }, () => resolve(all));
      }
      readBatch();
    });
  }

  // Helper: Request with retry for JSON API calls (init, finish)
  async function requestWithRetry(fn, job) {
    let retries = 0;
    const maxRetries = 5;
    const backoff = [1000, 2000, 4000, 8000, 16000];

    while (true) {
      if (job.state === 'canceled') throw new Error('Canceled');

      try {
        return await fn();
      } catch (err) {
        if (job.state === 'canceled') throw new Error('Canceled');

        if (err.status === 401) {
          isQueuePaused = true;
          job.state = 'queued';
          if (typeof EX.onUnauthorized === 'function') {
            EX.onUnauthorized();
          }
          throw err;
        }

        if (err.status === 429 || err.status === 503) {
          await sleep(2000);
          continue;
        }

        if (retries < maxRetries) {
          const delay = backoff[retries] || 16000;
          retries++;
          await sleep(delay);
          continue;
        }

        throw err;
      }
    }
  }

  // Auto-close panel 5s after all uploads are finished
  function checkAllFinished() {
    const hasPending = EX.upload.queue.some((j) =>
      ['queued', 'compressing', 'uploading', 'processing'].includes(j.state)
    );

    if (!hasPending && EX.upload.queue.length > 0) {
      if (!closeTimer) {
        closeTimer = setTimeout(() => {
          EX.upload.clearCompleted();
        }, 5000);
      }
    }
  }

  // Debounce reloading view after successful uploads
  function triggerDebouncedReload() {
    if (reloadTimer) clearTimeout(reloadTimer);
    reloadTimer = setTimeout(() => {
      if (EX.state.mode === 'files') {
        EX.reload();
      }
    }, 500);
  }

  function sleep(ms) {
    return new Promise((res) => setTimeout(res, ms));
  }

  // Warn before closing tab if uploads are active
  if (typeof window !== 'undefined') {
    window.addEventListener('beforeunload', (e) => {
      const hasActive = EX.upload.queue.some((j) =>
        ['queued', 'compressing', 'uploading', 'processing'].includes(j.state)
      );
      if (hasActive) {
        e.preventDefault();
        e.returnValue = EX.t('upload.confirm_leave');
        return e.returnValue;
      }
    });
  }

})();
