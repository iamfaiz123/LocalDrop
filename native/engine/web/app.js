// LocalDrop browser client. Served by the host's engine; works fully offline.
'use strict';
(() => {
  const $ = (id) => document.getElementById(id);
  const el = (tag, cls, text) => {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  };

  // ------------------------------------------------------------- SHA-256
  // Incremental SHA-256 (crypto.subtle is unavailable on plain-HTTP LAN
  // origins, and has no streaming API anyway).
  const K = new Uint32Array([
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ]);
  class Sha256 {
    constructor() {
      this.h = new Uint32Array([0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]);
      this.w = new Uint32Array(64);
      this.buf = new Uint8Array(64);
      this.bufLen = 0;
      this.total = 0;
    }
    block(d, o) {
      const w = this.w, h = this.h;
      for (let i = 0; i < 16; i++) w[i] = (d[o + 4 * i] << 24) | (d[o + 4 * i + 1] << 16) | (d[o + 4 * i + 2] << 8) | d[o + 4 * i + 3];
      for (let i = 16; i < 64; i++) {
        const a = w[i - 15], b = w[i - 2];
        const s0 = ((a >>> 7) | (a << 25)) ^ ((a >>> 18) | (a << 14)) ^ (a >>> 3);
        const s1 = ((b >>> 17) | (b << 15)) ^ ((b >>> 19) | (b << 13)) ^ (b >>> 10);
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) | 0;
      }
      let a = h[0], b = h[1], c = h[2], e0 = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];
      for (let i = 0; i < 64; i++) {
        const S1 = ((e >>> 6) | (e << 26)) ^ ((e >>> 11) | (e << 21)) ^ ((e >>> 25) | (e << 7));
        const t1 = (hh + S1 + ((e & f) ^ (~e & g)) + K[i] + w[i]) | 0;
        const S0 = ((a >>> 2) | (a << 30)) ^ ((a >>> 13) | (a << 19)) ^ ((a >>> 22) | (a << 10));
        const t2 = (S0 + ((a & b) ^ (a & c) ^ (b & c))) | 0;
        hh = g; g = f; f = e; e = (e0 + t1) | 0; e0 = c; c = b; b = a; a = (t1 + t2) | 0;
      }
      h[0] += a; h[1] += b; h[2] += c; h[3] += e0; h[4] += e; h[5] += f; h[6] += g; h[7] += hh;
    }
    update(data) {
      let i = 0;
      this.total += data.length;
      if (this.bufLen) {
        while (this.bufLen < 64 && i < data.length) this.buf[this.bufLen++] = data[i++];
        if (this.bufLen < 64) return;
        this.block(this.buf, 0);
        this.bufLen = 0;
      }
      for (; i + 64 <= data.length; i += 64) this.block(data, i);
      while (i < data.length) this.buf[this.bufLen++] = data[i++];
    }
    hex() {
      const bits = this.total * 8;
      const pad = new Uint8Array(((this.bufLen < 56 ? 56 : 120) - this.bufLen) + 8);
      pad[0] = 0x80;
      const hi = Math.floor(bits / 0x100000000), lo = bits >>> 0;
      const n = pad.length;
      pad[n - 8] = hi >>> 24; pad[n - 7] = hi >>> 16; pad[n - 6] = hi >>> 8; pad[n - 5] = hi;
      pad[n - 4] = lo >>> 24; pad[n - 3] = lo >>> 16; pad[n - 2] = lo >>> 8; pad[n - 1] = lo;
      const saved = this.total;
      this.update(pad);
      this.total = saved;
      return Array.from(this.h, (x) => (x >>> 0).toString(16).padStart(8, '0')).join('');
    }
  }

  // ------------------------------------------------------------- helpers
  const fmtBytes = (n) => {
    if (n == null) return '';
    const u = ['B', 'KB', 'MB', 'GB', 'TB'];
    let i = 0;
    while (n >= 1024 && i < u.length - 1) { n /= 1024; i++; }
    return `${n >= 100 || i === 0 ? Math.round(n) : n.toFixed(1)} ${u[i]}`;
  };
  const fmtTime = (ms) => {
    const d = new Date(ms), now = new Date();
    const t = d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
    if (d.toDateString() === now.toDateString()) return `Today, ${t}`;
    const y = new Date(now); y.setDate(now.getDate() - 1);
    if (d.toDateString() === y.toDateString()) return `Yesterday, ${t}`;
    return `${d.toLocaleDateString([], { day: 'numeric', month: 'short' })}, ${t}`;
  };
  const colorHex = (c) => (c ? '#' + (c & 0xffffff).toString(16).padStart(6, '0') : '#EDE8FF');
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  let toastTimer;
  function toast(msg, isError) {
    const t = $('toast');
    t.textContent = msg;
    t.className = 'toast' + (isError ? ' error' : '');
    t.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => (t.hidden = true), isError ? 5000 : 2800);
  }

  class ApiError extends Error {
    constructor(message, status, body) {
      super(message);
      this.status = status;
      this.code = body && body.code;
      this.data = body;
    }
  }

  async function api(path, opts = {}) {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), opts.timeout || 20000);
    const headers = Object.assign({}, opts.headers || {});
    let body = opts.body;
    if (body !== undefined && !(body instanceof Blob)) {
      headers['Content-Type'] = 'application/json';
      body = JSON.stringify(body);
    }
    let res;
    try {
      res = await fetch(path, { method: opts.method || 'GET', headers, body, credentials: 'same-origin', signal: ctrl.signal });
    } catch (e) {
      throw new ApiError(e.name === 'AbortError' ? 'The host did not respond in time' : 'Cannot reach the host', 0, { code: 'network' });
    } finally {
      clearTimeout(timer);
    }
    let data = null;
    try { data = await res.json(); } catch (_) { /* non-JSON body */ }
    if (!res.ok) {
      const err = data && data.error;
      throw new ApiError((err && err.message) || `Request failed (${res.status})`, res.status, err);
    }
    return data;
  }

  // ------------------------------------------------------------- state
  const S = {
    session: null, me: null, participants: [], items: [], ids: new Set(), total: 0, next: 0,
    loading: false, filter: { kind: 'all', uploader: '', order: 'desc' }, selectMode: false,
    selected: new Set(), viewer: -1, ws: null, wsRetry: 0, wsUp: false, ended: false,
    transfers: [], tab: 'active', pendingTimer: null,
  };

  const views = ['v-loading', 'v-message', 'v-join', 'v-pending', 'v-gallery'];
  function show(id) {
    views.forEach((v) => ($(v).hidden = v !== id));
    $('bottombar').hidden = id !== 'v-gallery';
    $('conn').hidden = id !== 'v-gallery';
  }
  function message(title, text, { icon = '!', retry = false } = {}) {
    closeViewer();
    closeSheets();
    $('msgTitle').textContent = title;
    $('msgText').textContent = text;
    $('msgIcon').textContent = icon;
    $('msgRetry').hidden = !retry;
    show('v-message');
  }

  // ------------------------------------------------------------- boot / join
  function deviceId() {
    try {
      let d = localStorage.getItem('ld_device');
      if (!d) {
        const b = new Uint8Array(16);
        crypto.getRandomValues(b);
        d = Array.from(b, (x) => x.toString(16).padStart(2, '0')).join('');
        localStorage.setItem('ld_device', d);
      }
      return d;
    } catch (_) {
      return undefined;
    }
  }

  async function boot() {
    show('v-loading');
    $('loadingText').textContent = 'Connecting to the host…';
    let info;
    try {
      info = await api('/api/session/info', { timeout: 10000 });
    } catch (e) {
      if (e.code === 'session_ended') return message('Session ended', 'The host has ended this session.', { icon: '✓' });
      return message('Can’t reach the host', 'Make sure this phone is connected to the host’s hotspot or Wi-Fi network, then try again.', { retry: true });
    }
    S.session = info;
    const sid = new URLSearchParams(location.search).get('sid');
    if (sid && sid !== info.id) toast('This QR code belongs to an older session. Joining the current one.');
    try {
      const me = await api('/api/session/me');
      return handleMe(me);
    } catch (e) {
      if (e.code === 'session_ended') return message('Session ended', 'The host has ended this session.', { icon: '✓' });
      if (e.status && e.status !== 401) return message('Something went wrong', e.message, { retry: true });
      showJoin();
    }
  }

  function handleMe(me) {
    S.me = me.participant;
    switch (S.me.status) {
      case 'active': return enterGallery(me.session);
      case 'pending': return showPending();
      case 'blocked': return message('You were blocked', 'The host blocked this device from the session.');
      case 'removed': return message('You were removed', 'The host removed you from this session.', { retry: true });
      default: return showJoin();
    }
  }

  function showJoin() {
    $('joinSession').textContent = S.session ? S.session.name : 'Join session';
    $('joinHost').textContent = S.session ? `Hosted by ${S.session.host_name} · Enter your details to join` : 'Enter your details to join';
    const pinLen = (S.session && S.session.pin_length) || 6;
    $('joinPin').maxLength = pinLen;
    $('joinPin').placeholder = Array(pinLen).fill('•').join(' ');
    try { $('joinName').value = localStorage.getItem('ld_name') || ''; } catch (_) { /* storage blocked */ }
    $('joinError').hidden = true;
    show('v-join');
  }

  $('joinForm').addEventListener('submit', async (ev) => {
    ev.preventDefault();
    const name = $('joinName').value.trim();
    const pin = $('joinPin').value.replace(/\s/g, '');
    const err = $('joinError');
    err.hidden = true;
    if (!name) { err.textContent = 'Enter your name.'; err.hidden = false; return; }
    if (!/^\d{4,6}$/.test(pin)) { err.textContent = 'Enter the PIN shown on the host’s screen.'; err.hidden = false; return; }
    $('joinBtn').disabled = true;
    try {
      const r = await api('/api/session/join', { method: 'POST', body: { name, pin, device_id: deviceId() } });
      try { localStorage.setItem('ld_name', name); } catch (_) { /* ignore */ }
      $('joinPin').value = '';
      handleMe({ participant: r.participant, session: r.session });
    } catch (e) {
      err.textContent = e.code === 'network' ? 'Cannot reach the host. Check your Wi-Fi connection.' : e.message;
      err.hidden = false;
    } finally {
      $('joinBtn').disabled = false;
    }
  });

  function showPending() {
    show('v-pending');
    clearInterval(S.pendingTimer);
    S.pendingTimer = setInterval(async () => {
      try {
        const me = await api('/api/session/me');
        if (me.participant.status !== 'pending') {
          clearInterval(S.pendingTimer);
          handleMe(me);
        }
      } catch (e) {
        if (e.status === 401 || e.code === 'session_ended') {
          clearInterval(S.pendingTimer);
          e.code === 'session_ended' ? message('Session ended', 'The host has ended this session.') : message('Request declined', 'The host did not let you in.', { retry: true });
        }
      }
    }, 3000);
  }
  $('pendingCancel').addEventListener('click', async () => {
    clearInterval(S.pendingTimer);
    try { await api('/api/session/leave', { method: 'POST', body: {} }); } catch (_) { /* already gone */ }
    showJoin();
  });
  $('msgRetry').addEventListener('click', boot);

  // ------------------------------------------------------------- gallery
  function enterGallery(session) {
    S.session = session;
    show('v-gallery');
    renderHeader();
    connectWs();
    loadParticipants();
    reload();
  }

  function renderHeader() {
    $('galTitle').textContent = S.session.name;
    const members = S.participants.filter((p) => p.status === 'active').length || S.session.participant_count || 1;
    $('galSub').textContent = `${members} member${members === 1 ? '' : 's'} · ${S.total} item${S.total === 1 ? '' : 's'}`;
    const canUpload = S.session.upload_permission !== 'host_only' || (S.me && S.me.role === 'host');
    $('uploadBtn').disabled = !canUpload;
    $('uploadBtn').textContent = canUpload ? '＋ Upload photos & videos' : 'Uploads are turned off by the host';
  }

  async function loadParticipants() {
    try {
      const r = await api('/api/session/participants');
      S.participants = r.participants;
      const sel = $('uploaderFilter');
      const cur = sel.value;
      sel.replaceChildren(el('option', null, 'Everyone'));
      sel.firstChild.value = '';
      for (const p of S.participants) {
        const o = el('option', null, p.id === S.me.id ? `${p.name} (you)` : p.name);
        o.value = p.id;
        sel.appendChild(o);
      }
      sel.value = cur;
      renderHeader();
      renderMembers();
    } catch (e) {
      handleAuthError(e);
    }
  }

  function query(offset) {
    const p = new URLSearchParams({ offset: String(offset), limit: '60', order: S.filter.order });
    if (S.filter.kind === 'photo' || S.filter.kind === 'video') p.set('kind', S.filter.kind);
    if (S.filter.kind === 'fav') p.set('favorites', 'true');
    if (S.filter.uploader) p.set('uploader', S.filter.uploader);
    return '/api/media?' + p;
  }

  async function reload() {
    S.items = [];
    S.ids.clear();
    S.next = 0;
    S.selected.clear();
    $('grid').replaceChildren();
    await loadMore();
  }

  async function loadMore() {
    if (S.loading || S.next == null) return;
    S.loading = true;
    $('moreSpinner').hidden = false;
    try {
      const r = await api(query(S.next));
      for (const m of r.items) addItem(m, false);
      S.total = r.total;
      S.next = r.next_offset;
      renderHeader();
    } catch (e) {
      if (!handleAuthError(e)) toast(e.message, true);
    } finally {
      S.loading = false;
      $('moreSpinner').hidden = true;
      $('empty').hidden = S.items.length > 0;
    }
  }

  new IntersectionObserver((entries) => {
    if (entries.some((e) => e.isIntersecting) && !$('v-gallery').hidden) loadMore();
  }, { rootMargin: '600px' }).observe($('sentinel'));

  function matches(m) {
    if (S.filter.kind === 'photo' && m.kind !== 'photo') return false;
    if (S.filter.kind === 'video' && m.kind !== 'video') return false;
    if (S.filter.kind === 'fav' && !m.favorite) return false;
    if (S.filter.uploader && m.uploader.id !== S.filter.uploader) return false;
    return true;
  }

  function tile(m) {
    const b = el('button', 'tile');
    b.type = 'button';
    b.dataset.id = m.id;
    b.setAttribute('aria-label', `${m.kind} by ${m.uploader.name}`);
    if (m.has_thumbnail) {
      const img = el('img');
      img.loading = 'lazy';
      img.decoding = 'async';
      img.alt = '';
      img.src = `${m.thumbnail_url}?v=${m.sha256.slice(0, 8)}`;
      img.addEventListener('error', () => img.replaceWith(el('div', 'ph', m.kind === 'video' ? '🎬' : '📷')));
      b.appendChild(img);
    } else {
      b.appendChild(el('div', 'ph', m.kind === 'video' ? '🎬' : '📷'));
    }
    if (m.kind === 'video') b.appendChild(el('div', 'play', '▶'));
    if (m.favorite) b.appendChild(el('div', 'fav', '♥'));
    if (S.selectMode) b.appendChild(el('div', 'check', S.selected.has(m.id) ? '✓' : ''));
    if (S.selected.has(m.id)) b.classList.add('selected');
    b.addEventListener('click', () => onTile(m.id));
    return b;
  }

  function addItem(m, prepend) {
    if (S.ids.has(m.id)) return;
    S.ids.add(m.id);
    const t = tile(m);
    if (prepend) {
      S.items.unshift(m);
      $('grid').prepend(t);
    } else {
      S.items.push(m);
      $('grid').appendChild(t);
    }
    $('empty').hidden = true;
  }

  function rerenderTile(m) {
    const old = $('grid').querySelector(`[data-id="${m.id}"]`);
    if (old) old.replaceWith(tile(m));
  }

  function removeItem(id) {
    const i = S.items.findIndex((m) => m.id === id);
    if (i < 0) return;
    S.items.splice(i, 1);
    S.ids.delete(id);
    S.selected.delete(id);
    const t = $('grid').querySelector(`[data-id="${id}"]`);
    if (t) t.remove();
    $('empty').hidden = S.items.length > 0;
    if (S.viewer >= 0) {
      if (S.items.length === 0) closeViewer();
      else openViewer(Math.min(S.viewer >= i ? Math.max(S.viewer - (S.viewer > i ? 1 : 0), 0) : S.viewer, S.items.length - 1));
    }
  }

  function onTile(id) {
    if (S.selectMode) {
      S.selected.has(id) ? S.selected.delete(id) : S.selected.add(id);
      const m = S.items.find((x) => x.id === id);
      if (m) rerenderTile(m);
      updateSelCount();
      return;
    }
    openViewer(S.items.findIndex((m) => m.id === id));
  }

  $('kindPills').addEventListener('click', (e) => {
    const b = e.target.closest('.pill');
    if (!b) return;
    S.filter.kind = b.dataset.kind;
    $('kindPills').querySelectorAll('.pill').forEach((p) => p.classList.toggle('selected', p === b));
    reload();
  });
  $('uploaderFilter').addEventListener('change', (e) => { S.filter.uploader = e.target.value; reload(); });
  $('sortBtn').addEventListener('click', () => {
    S.filter.order = S.filter.order === 'desc' ? 'asc' : 'desc';
    $('sortBtn').textContent = S.filter.order === 'desc' ? 'Newest first' : 'Oldest first';
    reload();
  });

  // ------------------------------------------------------------- viewer
  function canDelete(m) {
    return S.me && (m.uploader.id === S.me.id || S.me.role === 'host');
  }

  function openViewer(i) {
    if (i < 0 || i >= S.items.length) return;
    S.viewer = i;
    const m = S.items[i];
    const stage = $('vMedia');
    stage.replaceChildren();
    if (m.kind === 'video') {
      const v = el('video');
      v.controls = true;
      v.playsInline = true;
      v.preload = 'metadata';
      if (m.has_thumbnail) v.poster = m.thumbnail_url;
      v.src = m.file_url;
      stage.appendChild(v);
    } else {
      const img = el('img');
      img.alt = m.filename;
      img.decoding = 'async';
      img.src = m.file_url;
      img.addEventListener('error', () => stage.replaceChildren(el('p', 'muted', 'This photo can’t be displayed in this browser. Download it to view.')));
      stage.appendChild(img);
    }
    $('vCount').textContent = `${i + 1} of ${S.total}`;
    $('vName').textContent = m.uploader.name + (m.uploader.id === (S.me && S.me.id) ? ' (you)' : '');
    $('vTime').textContent = `${fmtTime(m.created_at)} · ${fmtBytes(m.size)}`;
    const av = $('vAvatar');
    av.textContent = m.uploader.initials || '?';
    av.style.background = colorHex(m.uploader.avatar_color);
    const dl = $('vDownload');
    dl.href = `${m.file_url}?download=1`;
    dl.setAttribute('download', m.filename);
    dl.hidden = S.session.download_permission === 'host_only' && S.me.role !== 'host';
    $('vFav').textContent = m.favorite ? '♥' : '♡';
    $('vDelete').hidden = !canDelete(m);
    $('vPrev').hidden = i === 0;
    $('vNext').hidden = i >= S.items.length - 1 && S.next == null;
    $('viewer').hidden = false;
    if (i >= S.items.length - 5) loadMore();
  }

  function closeViewer() {
    S.viewer = -1;
    $('vMedia').replaceChildren();
    $('viewer').hidden = true;
  }
  $('vClose').addEventListener('click', closeViewer);
  $('vPrev').addEventListener('click', () => openViewer(S.viewer - 1));
  $('vNext').addEventListener('click', async () => {
    if (S.viewer >= S.items.length - 1) await loadMore();
    openViewer(S.viewer + 1);
  });
  document.addEventListener('keydown', (e) => {
    if ($('viewer').hidden) return;
    if (e.key === 'Escape') closeViewer();
    if (e.key === 'ArrowLeft') $('vPrev').click();
    if (e.key === 'ArrowRight') $('vNext').click();
  });
  let touchX = null;
  $('vStage').addEventListener('touchstart', (e) => { touchX = e.touches[0].clientX; }, { passive: true });
  $('vStage').addEventListener('touchend', (e) => {
    if (touchX == null) return;
    const dx = e.changedTouches[0].clientX - touchX;
    touchX = null;
    if (Math.abs(dx) > 60 && !(e.target instanceof HTMLVideoElement)) (dx < 0 ? $('vNext') : $('vPrev')).click();
  });
  $('vFav').addEventListener('click', async () => {
    const m = S.items[S.viewer];
    if (!m) return;
    try {
      await api(`/api/media/${m.id}/favorite`, { method: m.favorite ? 'DELETE' : 'POST', body: {} });
      m.favorite = !m.favorite;
      $('vFav').textContent = m.favorite ? '♥' : '♡';
      rerenderTile(m);
    } catch (e) {
      toast(e.message, true);
    }
  });
  $('vDelete').addEventListener('click', async () => {
    const m = S.items[S.viewer];
    if (!m || !confirm(`Delete “${m.filename}” for everyone? This cannot be undone.`)) return;
    try {
      await api(`/api/media/${m.id}`, { method: 'DELETE' });
      S.total--;
      removeItem(m.id);
      renderHeader();
      toast('Deleted');
    } catch (e) {
      toast(e.message, true);
    }
  });

  // ------------------------------------------------------------- selection + downloads
  function setSelectMode(on) {
    S.selectMode = on;
    S.selected.clear();
    $('normalBar').hidden = on;
    $('selectBar').hidden = !on;
    S.items.forEach(rerenderTile);
    updateSelCount();
  }
  function updateSelCount() {
    $('selCount').textContent = `${S.selected.size} selected`;
  }
  $('selectBtn').addEventListener('click', () => setSelectMode(true));
  $('selCancel').addEventListener('click', () => setSelectMode(false));
  $('selAll').addEventListener('click', () => {
    const all = S.selected.size === S.items.length;
    S.items.forEach((m) => (all ? S.selected.delete(m.id) : S.selected.add(m.id)));
    S.items.forEach(rerenderTile);
    updateSelCount();
  });

  function triggerDownload(url, name) {
    const a = el('a');
    a.href = url;
    a.setAttribute('download', name || '');
    a.hidden = true;
    document.body.appendChild(a);
    a.click();
    a.remove();
  }

  $('selDownload').addEventListener('click', async () => {
    const ids = [...S.selected];
    if (!ids.length) return toast('Select photos or videos first');
    if (ids.length === 1) {
      const m = S.items.find((x) => x.id === ids[0]);
      triggerDownload(`${m.file_url}?download=1`, m.filename);
    } else {
      try {
        const r = await api('/api/media/download', { method: 'POST', body: { ids } });
        toast(`Preparing ${r.count} files (${fmtBytes(r.size)}) as a ZIP…`);
        triggerDownload(r.url, r.filename);
      } catch (e) {
        return toast(e.message, true);
      }
    }
    setSelectMode(false);
  });

  $('selDelete').addEventListener('click', async () => {
    const mine = S.items.filter((m) => S.selected.has(m.id) && canDelete(m));
    const skipped = S.selected.size - mine.length;
    if (!mine.length) return toast('You can only delete your own uploads', true);
    if (!confirm(`Delete ${mine.length} item${mine.length === 1 ? '' : 's'} for everyone? This cannot be undone.`)) return;
    let failed = 0;
    for (const m of mine) {
      try {
        await api(`/api/media/${m.id}`, { method: 'DELETE' });
        S.total--;
        removeItem(m.id);
      } catch (_) {
        failed++;
      }
    }
    renderHeader();
    setSelectMode(false);
    toast(failed ? `${failed} item(s) could not be deleted` : skipped ? `Deleted. ${skipped} item(s) from others were skipped.` : 'Deleted', failed > 0);
  });

  // ------------------------------------------------------------- uploads
  const MAX_PARALLEL = 2;
  let uid = 0;
  const ACTIVE = new Set(['queued', 'uploading', 'paused', 'failed', 'preparing']);

  $('uploadBtn').addEventListener('click', () => $('fileInput').click());
  $('addMore').addEventListener('click', () => $('fileInput').click());
  $('fileInput').addEventListener('change', (e) => {
    const files = [...e.target.files];
    e.target.value = '';
    for (const f of files) {
      S.transfers.push({ id: ++uid, file: f, status: 'queued', sent: 0, speed: 0, error: '', uploadId: null, xhr: null, hasher: null, hashedTo: 0, retries: 0 });
    }
    if (files.length) {
      toast(`${files.length} file${files.length === 1 ? '' : 's'} added to uploads`);
      pump();
      renderTransfers();
    }
  });

  function pump() {
    const running = S.transfers.filter((t) => t.status === 'uploading' || t.status === 'preparing').length;
    const next = S.transfers.filter((t) => t.status === 'queued').slice(0, Math.max(0, MAX_PARALLEL - running));
    next.forEach(run);
    renderTransfers();
  }

  async function hashUpTo(t, target) {
    if (t.hasher && t.hashedTo === target) return;
    if (!t.hasher || t.hashedTo > target) { t.hasher = new Sha256(); t.hashedTo = 0; }
    const step = 8 * 1024 * 1024;
    while (t.hashedTo < target) {
      if (t.stop) throw Object.assign(new Error('stopped'), { stopped: true });
      const end = Math.min(t.hashedTo + step, target);
      t.hasher.update(new Uint8Array(await t.file.slice(t.hashedTo, end).arrayBuffer()));
      t.hashedTo = end;
    }
  }

  function putChunk(t, offset, bytes) {
    return new Promise((resolve, reject) => {
      const x = new XMLHttpRequest();
      t.xhr = x;
      x.open('PUT', `/api/uploads/${t.uploadId}?offset=${offset}`);
      x.timeout = 180000;
      let lastT = performance.now(), lastB = 0;
      x.upload.onprogress = (e) => {
        const now = performance.now();
        if (now - lastT > 400) {
          const inst = ((e.loaded - lastB) / (now - lastT)) * 1000;
          t.speed = t.speed ? t.speed * 0.6 + inst * 0.4 : inst;
          lastT = now;
          lastB = e.loaded;
        }
        t.sent = offset + e.loaded;
        renderTransfer(t);
      };
      x.onload = () => {
        t.xhr = null;
        let d = null;
        try { d = JSON.parse(x.responseText); } catch (_) { /* not json */ }
        if (x.status >= 200 && x.status < 300) resolve(d);
        else reject(new ApiError((d && d.error && d.error.message) || `Upload failed (${x.status})`, x.status, d && d.error));
      };
      const net = (msg) => () => { t.xhr = null; reject(Object.assign(new ApiError(msg, 0, { code: 'network' }), { network: true })); };
      x.onerror = net('Connection to the host was lost');
      x.ontimeout = net('The host stopped responding');
      x.onabort = () => { t.xhr = null; reject(Object.assign(new Error('stopped'), { stopped: true })); };
      x.send(bytes);
    });
  }

  async function run(t) {
    t.status = 'preparing';
    t.stop = false;
    t.error = '';
    renderTransfer(t);
    try {
      const c = await api('/api/media/upload', { method: 'POST', body: { filename: t.file.name, size: t.file.size } });
      if (c.duplicate) {
        t.status = 'duplicate';
        t.media = c.media;
        return;
      }
      t.uploadId = c.upload_id;
      const chunk = Math.max(256 * 1024, Math.min(c.chunk_size, c.max_chunk_size));
      let offset = c.received;
      await hashUpTo(t, offset);
      t.status = 'uploading';
      t.sent = offset;
      renderTransfer(t);
      while (offset < t.file.size) {
        if (t.stop) throw Object.assign(new Error('stopped'), { stopped: true });
        const end = Math.min(offset + chunk, t.file.size);
        const bytes = new Uint8Array(await t.file.slice(offset, end).arrayBuffer());
        try {
          const r = await putChunk(t, offset, bytes);
          if (t.hashedTo === offset) { t.hasher.update(bytes); t.hashedTo = end; }
          offset = r.received;
          t.retries = 0;
        } catch (e) {
          if (e.code === 'offset_mismatch' && e.data && typeof e.data.received === 'number') {
            offset = e.data.received;
            await hashUpTo(t, offset);
            continue;
          }
          throw e;
        }
        await hashUpTo(t, offset);
      }
      t.status = 'verifying';
      renderTransfer(t);
      const done = await api(`/api/uploads/${t.uploadId}/complete`, { method: 'POST', body: { sha256: t.hasher.hex() }, timeout: 600000 });
      t.status = done.duplicate ? 'duplicate' : 'done';
      t.media = done.media;
      t.sent = t.file.size;
      t.hasher = null;
      if (done.needs_client_thumbnail) clientThumbnail(t.file, done.media);
    } catch (e) {
      if (e.stopped) {
        if (t.status !== 'cancelled') t.status = 'paused';
      } else if ((e.network || e.status >= 500 || e.status === 429 || e.code === 'upload_busy') && t.retries < 6) {
        t.retries++;
        t.status = 'queued';
        t.error = `${e.message} — retrying…`;
        renderTransfer(t);
        await sleep(Math.min(30000, 1000 * 2 ** t.retries));
      } else {
        t.status = 'failed';
        t.error = e.code === 'insufficient_storage' ? 'The host is out of storage space' : e.message;
        if (e.code === 'integrity_failed') t.hasher = null;
      }
    } finally {
      renderTransfer(t);
      pump();
    }
  }

  function pauseTask(t) {
    t.stop = true;
    if (t.xhr) t.xhr.abort();
    if (t.status === 'queued') t.status = 'paused';
    renderTransfer(t);
  }
  function resumeTask(t) {
    t.status = 'queued';
    t.retries = 0;
    pump();
  }
  async function cancelTask(t) {
    const prev = t.status;
    t.status = 'cancelled';
    t.stop = true;
    if (t.xhr) t.xhr.abort();
    renderTransfer(t);
    if (t.uploadId && prev !== 'done') {
      for (let i = 0; i < 5; i++) {
        try { await api(`/api/uploads/${t.uploadId}`, { method: 'DELETE' }); break; } catch (e) {
          if (e.code !== 'upload_busy') break;
          await sleep(500);
        }
      }
    }
    pump();
  }

  async function clientThumbnail(file, media) {
    try {
      const blob = media.kind === 'video' ? await videoThumb(file) : await imageThumb(file);
      if (blob) await fetch(`/api/media/${media.id}/thumbnail`, { method: 'PUT', body: blob, credentials: 'same-origin' });
    } catch (e) {
      console.warn('LocalDrop: could not create a thumbnail for', file.name, e);
    }
  }
  function drawThumb(src, w, h) {
    const scale = Math.min(1, 480 / Math.max(w, h));
    const c = document.createElement('canvas');
    c.width = Math.max(1, Math.round(w * scale));
    c.height = Math.max(1, Math.round(h * scale));
    c.getContext('2d').drawImage(src, 0, 0, c.width, c.height);
    return new Promise((r) => c.toBlob(r, 'image/jpeg', 0.8));
  }
  function waitFor(target, ev, ms) {
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error(`timeout waiting for ${ev}`)), ms);
      target.addEventListener(ev, () => { clearTimeout(timer); resolve(); }, { once: true });
      target.addEventListener('error', () => { clearTimeout(timer); reject(new Error('media error')); }, { once: true });
    });
  }
  async function videoThumb(file) {
    const url = URL.createObjectURL(file);
    try {
      const v = document.createElement('video');
      v.muted = true;
      v.playsInline = true;
      v.preload = 'auto';
      v.src = url;
      await waitFor(v, 'loadeddata', 15000);
      v.currentTime = Math.min(1, (v.duration || 0) / 2);
      await waitFor(v, 'seeked', 15000);
      return await drawThumb(v, v.videoWidth, v.videoHeight);
    } finally {
      URL.revokeObjectURL(url);
    }
  }
  async function imageThumb(file) {
    const url = URL.createObjectURL(file);
    try {
      const img = new Image();
      img.decoding = 'async';
      img.src = url;
      await waitFor(img, 'load', 20000);
      return await drawThumb(img, img.naturalWidth, img.naturalHeight);
    } finally {
      URL.revokeObjectURL(url);
    }
  }

  const STATUS_TEXT = {
    queued: 'Waiting…', preparing: 'Preparing…', paused: 'Paused', verifying: 'Verifying…',
    done: 'Uploaded', duplicate: 'Already in the gallery', cancelled: 'Cancelled', failed: 'Failed',
  };

  function transferRow(t) {
    const row = el('div', 'item');
    row.id = `tr-${t.id}`;
    const th = el('div', 'thumb', t.file.type.startsWith('video') ? '🎬' : '📷');
    const mid = el('div', 'grow');
    mid.append(el('div', 'name', t.file.name), el('div', 'detail'), el('div', 'bar'));
    mid.lastChild.appendChild(el('i'));
    const pct = el('div', 'pct');
    const actions = el('div', 'actions');
    row.append(th, mid, pct, actions);
    return row;
  }

  function renderTransfer(t) {
    const active = ACTIVE.has(t.status) || t.status === 'verifying';
    if ((S.tab === 'active') !== active) {
      const r = $(`tr-${t.id}`);
      if (r) r.remove();
      updateTransferBadge();
      $('transferEmpty').hidden = $('transferList').children.length > 0;
      if (S.tab === 'done' && !active) renderTransfers();
      return;
    }
    let row = $(`tr-${t.id}`);
    if (!row) {
      row = transferRow(t);
      $('transferList').appendChild(row);
    }
    const p = t.file.size ? t.sent / t.file.size : 0;
    row.className = 'item' + (t.status === 'failed' ? ' failed' : t.status === 'done' || t.status === 'duplicate' ? ' done' : '');
    const detail = row.querySelector('.detail');
    detail.textContent =
      t.status === 'uploading' ? `${fmtBytes(t.file.size)} · ${fmtBytes(t.speed)}/s`
        : `${fmtBytes(t.file.size)} · ${t.error || STATUS_TEXT[t.status] || ''}`;
    row.querySelector('.bar > i').style.width = `${Math.round((t.status === 'done' || t.status === 'duplicate' ? 1 : p) * 100)}%`;
    row.querySelector('.pct').textContent =
      t.status === 'uploading' || t.status === 'paused' ? `${Math.floor(p * 100)}%` : t.status === 'queued' ? 'Queued' : '';
    const actions = row.querySelector('.actions');
    actions.replaceChildren();
    const btn = (label, title, fn) => {
      const b = el('button', null, label);
      b.title = title;
      b.setAttribute('aria-label', title);
      b.addEventListener('click', fn);
      actions.appendChild(b);
    };
    if (t.status === 'uploading' || t.status === 'queued' || t.status === 'preparing') btn('❚❚', 'Pause', () => pauseTask(t));
    if (t.status === 'paused') btn('▶', 'Resume', () => resumeTask(t));
    if (t.status === 'failed') btn('↻', 'Retry', () => resumeTask(t));
    if (active && t.status !== 'verifying') btn('✕', 'Cancel', () => cancelTask(t));
    updateTransferBadge();
    $('transferEmpty').hidden = true;
  }

  function renderTransfers() {
    $('transferList').replaceChildren();
    const list = S.transfers.filter((t) => (S.tab === 'active') === (ACTIVE.has(t.status) || t.status === 'verifying'));
    list.forEach(renderTransfer);
    $('transferEmpty').hidden = list.length > 0;
    const n = S.transfers.filter((t) => ACTIVE.has(t.status) || t.status === 'verifying').length;
    $('tabActive').textContent = `Uploading (${n})`;
    updateTransferBadge();
  }
  function updateTransferBadge() {
    const n = S.transfers.filter((t) => t.status === 'uploading' || t.status === 'queued' || t.status === 'preparing' || t.status === 'verifying').length;
    $('transferCount').textContent = String(n);
    $('transferCount').hidden = n === 0;
  }
  document.querySelectorAll('#transfersSheet .pill').forEach((p) =>
    p.addEventListener('click', () => {
      S.tab = p.dataset.tab;
      document.querySelectorAll('#transfersSheet .pill').forEach((x) => x.classList.toggle('selected', x === p));
      renderTransfers();
    }),
  );
  $('clearDone').addEventListener('click', () => {
    S.transfers = S.transfers.filter((t) => ACTIVE.has(t.status) || t.status === 'verifying' || t.status === 'uploading');
    renderTransfers();
  });
  window.addEventListener('beforeunload', (e) => {
    if (S.transfers.some((t) => t.status === 'uploading' || t.status === 'queued' || t.status === 'preparing')) {
      e.preventDefault();
      e.returnValue = '';
    }
  });

  // ------------------------------------------------------------- sheets
  function openSheet(id) {
    $('sheetBackdrop').hidden = false;
    $(id).hidden = false;
  }
  function closeSheets() {
    $('sheetBackdrop').hidden = true;
    $('transfersSheet').hidden = true;
    $('menuSheet').hidden = true;
  }
  $('sheetBackdrop').addEventListener('click', closeSheets);
  $('transfersBtn').addEventListener('click', () => { renderTransfers(); openSheet('transfersSheet'); });
  $('menuBtn').addEventListener('click', async () => {
    renderMembers();
    openSheet('menuSheet');
    loadParticipants();
    try {
      const s = await api('/api/storage/info');
      $('storageText').textContent = `Shared so far: ${fmtBytes(s.media_bytes)}` + (s.free_bytes != null ? ` · ${fmtBytes(s.free_bytes)} free on the host` : '');
    } catch (_) { /* optional info */ }
  });

  function renderMembers() {
    const list = $('memberList');
    list.replaceChildren();
    for (const p of S.participants) {
      const row = el('div', 'item');
      const av = el('div', 'avatar', p.initials || '?');
      av.style.background = colorHex(p.avatar_color);
      const mid = el('div', 'grow');
      const name = el('div', 'name');
      const dot = el('span', 'online-dot' + (p.online ? ' on' : ''));
      name.append(dot, document.createTextNode(p.name + (p.role === 'host' ? ' (Host)' : '') + (S.me && p.id === S.me.id ? ' · you' : '')));
      mid.append(name, el('div', 'detail', `${fmtBytes(p.bytes)} · ${p.photos + p.videos} items`));
      row.append(av, mid);
      list.appendChild(row);
    }
  }

  $('leaveBtn').addEventListener('click', async () => {
    const busy = S.transfers.some((t) => t.status === 'uploading' || t.status === 'queued');
    if (!confirm(busy ? 'Uploads are still running. Leave anyway?' : 'Leave this session?')) return;
    S.transfers.forEach((t) => { t.stop = true; if (t.xhr) t.xhr.abort(); });
    try { await api('/api/session/leave', { method: 'POST', body: {} }); } catch (_) { /* leaving anyway */ }
    S.leaving = true;
    if (S.ws) S.ws.close();
    closeSheets();
    showJoin();
  });

  // ------------------------------------------------------------- realtime
  function setConn(ok, text) {
    S.wsUp = ok;
    $('conn').classList.toggle('bad', !ok);
    $('connText').textContent = text || (ok ? 'Connected' : 'Reconnecting…');
  }

  let pingTimer, reloadPeopleTimer;
  function connectWs() {
    if (S.ws && S.ws.readyState <= 1) return;
    S.leaving = false;
    const ws = new WebSocket(`${location.protocol === 'https:' ? 'wss' : 'ws'}://${location.host}/api/ws`);
    S.ws = ws;
    ws.onopen = () => {
      const wasDown = S.wsRetry > 0;
      S.wsRetry = 0;
      setConn(true);
      $('banner').hidden = true;
      clearInterval(pingTimer);
      pingTimer = setInterval(() => ws.readyState === 1 && ws.send('ping'), 20000);
      if (wasDown) { reload(); loadParticipants(); }
    };
    ws.onmessage = (m) => {
      if (m.data === 'pong') return;
      try { onEvent(JSON.parse(m.data)); } catch (e) { console.warn('LocalDrop: bad event', e); }
    };
    ws.onclose = async () => {
      clearInterval(pingTimer);
      if (S.ended || S.leaving || $('v-gallery').hidden) return;
      setConn(false);
      S.wsRetry++;
      if (S.wsRetry > 2) {
        $('banner').textContent = 'Connection to the host was lost. Make sure you are still on the host’s Wi-Fi. Reconnecting…';
        $('banner').hidden = false;
      }
      // Distinguish "kicked/ended" from "network down".
      try {
        const me = await api('/api/session/me', { timeout: 5000 });
        if (me.participant.status !== 'active') return handleMe(me);
      } catch (e) {
        if (handleAuthError(e)) return;
      }
      setTimeout(connectWs, Math.min(15000, 500 * 2 ** S.wsRetry));
    };
  }

  function handleAuthError(e) {
    if (e.code === 'session_ended') { S.ended = true; message('Session ended', 'The host has ended this session.', { icon: '✓' }); return true; }
    if (e.code === 'removed' || e.code === 'blocked' || e.status === 401) {
      S.leaving = true;
      message(e.code === 'blocked' ? 'You were blocked' : 'You are no longer in this session', e.code === 'blocked' ? 'The host blocked this device.' : 'Join again with the session PIN.', { retry: e.code !== 'blocked' });
      return true;
    }
    return false;
  }

  function onEvent(ev) {
    const d = ev.data || {};
    switch (ev.type) {
      case 'media_uploaded':
        S.total++;
        if (matches(d) && (S.filter.order === 'desc' || S.next == null)) addItem(d, S.filter.order === 'desc');
        renderHeader();
        schedulePeople();
        break;
      case 'media_updated': {
        const m = S.items.find((x) => x.id === d.id);
        if (m) {
          Object.assign(m, d, { favorite: m.favorite });
          rerenderTile(m);
        }
        break;
      }
      case 'media_deleted':
        if (S.ids.has(d.id)) { S.total--; removeItem(d.id); renderHeader(); }
        schedulePeople();
        break;
      case 'participant_joined':
      case 'participant_left':
      case 'participant_status':
        schedulePeople();
        break;
      case 'participant_removed':
        if (S.me && d.id === S.me.id) {
          S.leaving = true;
          if (d.reason !== 'left') message(d.reason === 'blocked' ? 'You were blocked' : 'You were removed', 'The host removed you from this session.', { retry: d.reason !== 'blocked' });
        } else schedulePeople();
        break;
      case 'session_updated':
        Object.assign(S.session, d);
        renderHeader();
        break;
      case 'session_ended':
        S.ended = true;
        S.transfers.forEach((t) => { t.stop = true; if (t.xhr) t.xhr.abort(); });
        message('Session ended', d.media_deleted ? 'The host ended the session and removed the shared media.' : 'The host ended this session. Thanks for sharing!', { icon: '✓' });
        break;
      case 'storage_warning':
        $('banner').textContent = `The host is running low on storage (${fmtBytes(d.free_bytes)} left). Large uploads may fail.`;
        $('banner').hidden = false;
        break;
      case 'resync':
        reload();
        loadParticipants();
        break;
      default:
        break;
    }
  }
  function schedulePeople() {
    clearTimeout(reloadPeopleTimer);
    reloadPeopleTimer = setTimeout(loadParticipants, 400);
  }

  boot();
})();
