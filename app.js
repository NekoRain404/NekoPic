(() => {
  'use strict';

  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
  const clone = value => structuredClone(value);
  const clamp = (value, min, max) => Math.min(max, Math.max(min, value));
  const uid = () => `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
  const icon = name => `<svg aria-hidden="true"><use href="#i-${name}"/></svg>`;
  const photoCanvas = $('#photo-canvas');
  const photoCtx = photoCanvas.getContext('2d', { willReadFrequently: true });
  const overlayCanvas = $('#overlay-canvas');
  const overlayCtx = overlayCanvas.getContext('2d', { willReadFrequently: true });
  const viewport = $('#viewport');
  const stage = $('#canvas-stage');
  const inspector = $('#inspector-content');
  const fileInput = $('#file-input');
  const compositeCanvas = document.createElement('canvas');
  const compositeCtx = compositeCanvas.getContext('2d', { willReadFrequently: true });

  const LIMITS = { edge: 8192, pixels: 32_000_000, history: 80, historyBytes: 128 * 1024 * 1024, strokePoints: 4096 };
  const presets = {
    none: { label: '原图', exposure: 0, contrast: 0, saturation: 0, temperature: 0, fade: 0, grayscale: 0, sepia: 0 },
    warm: { label: '暖调', exposure: 5, contrast: 5, saturation: 8, temperature: 28, fade: 0, grayscale: 0, sepia: 8 },
    film: { label: '胶片', exposure: -2, contrast: 18, saturation: -8, temperature: 8, fade: 14, grayscale: 0, sepia: 12 },
    mono: { label: '黑白', exposure: 3, contrast: 12, saturation: -100, temperature: 0, fade: 0, grayscale: 100, sepia: 0 },
    faded: { label: '褪色', exposure: 7, contrast: -18, saturation: -24, temperature: 6, fade: 24, grayscale: 0, sepia: 5 },
    fresh: { label: '清透', exposure: 6, contrast: 7, saturation: 12, temperature: -5, fade: 0, grayscale: 0, sepia: 0 },
    vivid: { label: '鲜明', exposure: 2, contrast: 17, saturation: 28, temperature: 0, fade: 0, grayscale: 0, sepia: 0 },
    cool: { label: '冷杉', exposure: -3, contrast: 8, saturation: -10, temperature: -28, fade: 3, grayscale: 0, sepia: 0 },
    sunset: { label: '落日', exposure: 4, contrast: 9, saturation: 14, temperature: 42, fade: 5, grayscale: 0, sepia: 18 },
    soft: { label: '柔光', exposure: 10, contrast: -14, saturation: -8, temperature: 9, fade: 8, grayscale: 0, sepia: 0 },
    cream: { label: '奶油', exposure: 8, contrast: -9, saturation: -18, temperature: 16, fade: 14, grayscale: 0, sepia: 6 },
    vintage: { label: '旧时光', exposure: -2, contrast: 6, saturation: -28, temperature: 20, fade: 20, grayscale: 0, sepia: 30 },
    silver: { label: '银盐', exposure: -3, contrast: 28, saturation: -100, temperature: 0, fade: 4, grayscale: 100, sepia: 0 }
  };

  const state = {
    name: '山间来信.jpg', mime: 'image/jpeg', hasImage: false, base: document.createElement('canvas'),
    objects: [], selected: [], tool: 'adjust', previousTool: 'brush', color: '#eeb99a',
    adjustments: { exposure: 0, contrast: 0, highlights: 0, shadows: 0, saturation: 0, temperature: 0, sharpness: 0 },
    preset: 'none', presetStrength: 100, shape: 'rect', mosaicMode: 'mosaic',
    brush: { size: 18, opacity: 100 }, text: { size: 48, font: 'Noto Sans CJK SC', align: 'left', outline: true },
    shapeStyle: { width: 8, fill: false }, mosaic: { size: 18, strength: 16 },
    zoom: 0.5, panX: 0, panY: 0, fitView: true, grid: false, snap: true, compare: false,
    cropRect: null, active: null, space: false, rev: 0, savedRev: 0, history: [], historyIndex: -1,
    fileHandle: null, currentExport: 'jpeg', anchor: 'center', recoveryTimer: 0, recent: []
  };

  const panelMeta = {
    adjust: ['LIGHT & COLOR', '调色', '调色只作用于底图，文字和绘图保持原色。'],
    filters: ['ONE-TAP LOOKS', '滤镜', '预设可以调整强度，仍可继续微调每一项参数。'],
    brush: ['DRAW', '画笔', '一整笔作为一次撤销；最多记录 4096 个采样点。'],
    text: ['TYPE', '文字', '支持多行、对齐、描边和中文字体回退。'],
    shape: ['SHAPES', '形状', '按住 Shift 等比缩放，直线与箭头吸附到 45°。'],
    mosaic: ['REDACT', '打码', '马赛克和模糊用于分享前遮挡局部内容。'],
    crop: ['CROP', '裁剪', '裁剪会移动对象坐标并永久限制在新画布内。'],
    eyedropper: ['COLOR SAMPLE', '取色器', '点击照片或对象取色；放大镜显示采样像素。'],
    select: ['OBJECTS', '选择', 'Shift 多选；拖动对象，或使用对齐与层级命令。'],
    hand: ['NAVIGATE', '平移', '拖动画布；滚轮缩放，双击适应窗口。']
  };

  function setCanvasSize(width, height) {
    for (const canvas of [photoCanvas, overlayCanvas, compositeCanvas]) {
      canvas.width = width;
      canvas.height = height;
    }
    stage.style.width = `${width}px`;
    stage.style.height = `${height}px`;
    $('#dimensions').textContent = `${width} × ${height} px`;
  }

  function canvasClone(source) {
    const canvas = document.createElement('canvas');
    canvas.width = source.width;
    canvas.height = source.height;
    canvas.getContext('2d').drawImage(source, 0, 0);
    return canvas;
  }

  function snapshot() {
    return {
      base: state.base,
      objects: clone(state.objects), adjustments: clone(state.adjustments), preset: state.preset,
      presetStrength: state.presetStrength, name: state.name, mime: state.mime, rev: state.rev
    };
  }

  function restore(snap) {
    state.base = snap.base;
    state.objects = clone(snap.objects);
    state.adjustments = clone(snap.adjustments);
    state.preset = snap.preset;
    state.presetStrength = snap.presetStrength;
    state.name = snap.name;
    state.mime = snap.mime;
    state.rev = snap.rev;
    state.selected = [];
    setCanvasSize(state.base.width, state.base.height);
    updateDocumentChrome();
    renderAll();
    renderInspector();
  }

  function initHistory() {
    state.history = [snapshot()];
    state.historyIndex = 0;
    updateHistoryButtons();
  }

  function commit(label = '编辑') {
    state.rev += 1;
    state.history.splice(state.historyIndex + 1);
    state.history.push(snapshot());
    if (state.history.length > LIMITS.history) state.history.shift();
    state.historyIndex = state.history.length - 1;
    markDirty();
    updateHistoryButtons();
    $('#workspace-state').textContent = label;
    scheduleRecovery();
  }

  function undo() {
    if (state.historyIndex <= 0) return;
    state.historyIndex -= 1;
    restore(state.history[state.historyIndex]);
    toast('已撤销上一步');
  }

  function redo() {
    if (state.historyIndex >= state.history.length - 1) return;
    state.historyIndex += 1;
    restore(state.history[state.historyIndex]);
    toast('已重做');
  }

  function updateHistoryButtons() {
    $('#undo-button').disabled = state.historyIndex <= 0;
    $('#redo-button').disabled = state.historyIndex >= state.history.length - 1;
  }

  function markDirty() {
    $('#dirty-dot').hidden = state.rev === state.savedRev;
    document.title = `${state.name}${state.rev === state.savedRev ? '' : ' *'} - NekoPic`;
  }

  function updateDocumentChrome() {
    document.title = `${state.name}${state.rev === state.savedRev ? '' : ' *'} - NekoPic`;
    $('#tab-name').textContent = state.name;
    const ext = state.name.includes('.') ? state.name.split('.').pop() : state.mime.split('/')[1];
    $('#tab-format').textContent = (ext || 'IMG').toUpperCase();
    $('#object-count').textContent = `${state.objects.length} 个对象`;
    markDirty();
  }

  function effectiveAdjustments() {
    const result = { ...state.adjustments };
    const preset = presets[state.preset] || presets.none;
    const strength = state.presetStrength / 100;
    for (const [key, value] of Object.entries(preset)) {
      if (key !== 'label') result[key] = (result[key] || 0) + value * strength;
    }
    return result;
  }

  function renderPhoto() {
    if (!state.hasImage) return;
    photoCtx.clearRect(0, 0, photoCanvas.width, photoCanvas.height);
    const a = effectiveAdjustments();
    if (state.compare) {
      photoCtx.drawImage(state.base, 0, 0);
      return;
    }
    const exposure = Math.max(0, 100 + a.exposure * 1.35);
    const contrast = Math.max(0, 100 + a.contrast);
    const saturate = Math.max(0, 100 + a.saturation);
    const grayscale = clamp(a.grayscale || 0, 0, 100);
    const sepia = clamp(a.sepia || 0, 0, 100);
    photoCtx.filter = `brightness(${exposure}%) contrast(${contrast}%) saturate(${saturate}%) grayscale(${grayscale}%) sepia(${sepia}%)`;
    photoCtx.drawImage(state.base, 0, 0);
    photoCtx.filter = 'none';
    if (a.temperature) {
      photoCtx.save();
      photoCtx.globalCompositeOperation = a.temperature > 0 ? 'soft-light' : 'screen';
      photoCtx.globalAlpha = Math.abs(a.temperature) / 260;
      photoCtx.fillStyle = a.temperature > 0 ? '#ff8a3d' : '#5d9fff';
      photoCtx.fillRect(0, 0, photoCanvas.width, photoCanvas.height);
      photoCtx.restore();
    }
    if (a.shadows || a.highlights || a.fade) {
      photoCtx.save();
      if (a.shadows) {
        photoCtx.globalCompositeOperation = a.shadows > 0 ? 'screen' : 'multiply';
        photoCtx.globalAlpha = Math.abs(a.shadows) / 420;
        photoCtx.fillStyle = a.shadows > 0 ? '#8995a0' : '#17212a';
        photoCtx.fillRect(0, 0, photoCanvas.width, photoCanvas.height);
      }
      if (a.highlights) {
        photoCtx.globalCompositeOperation = a.highlights > 0 ? 'screen' : 'multiply';
        photoCtx.globalAlpha = Math.abs(a.highlights) / 500;
        photoCtx.fillStyle = a.highlights > 0 ? '#fff4e5' : '#7a7270';
        photoCtx.fillRect(0, 0, photoCanvas.width, photoCanvas.height);
      }
      if (a.fade) {
        photoCtx.globalCompositeOperation = 'screen';
        photoCtx.globalAlpha = a.fade / 300;
        photoCtx.fillStyle = '#c7b7a5';
        photoCtx.fillRect(0, 0, photoCanvas.width, photoCanvas.height);
      }
      photoCtx.restore();
    }
  }

  function objectBounds(object) {
    if (object.type === 'stroke') {
      const xs = object.points.map(p => p.x), ys = object.points.map(p => p.y);
      return { x: Math.min(...xs) - object.size / 2, y: Math.min(...ys) - object.size / 2,
        w: Math.max(...xs) - Math.min(...xs) + object.size, h: Math.max(...ys) - Math.min(...ys) + object.size };
    }
    if (object.type === 'text') {
      const lines = object.text.split('\n');
      const width = Math.max(80, ...lines.map(line => line.length * object.size * .75));
      return { x: object.x, y: object.y - object.size, w: width, h: lines.length * object.size * 1.28 };
    }
    const x = Math.min(object.x1, object.x2), y = Math.min(object.y1, object.y2);
    return { x, y, w: Math.abs(object.x2 - object.x1), h: Math.abs(object.y2 - object.y1) };
  }

  function drawStroke(ctx, object) {
    if (!object.points.length) return;
    ctx.save();
    ctx.globalAlpha = object.opacity / 100;
    ctx.strokeStyle = object.color;
    ctx.fillStyle = object.color;
    ctx.lineWidth = object.size;
    ctx.lineJoin = 'round';
    ctx.lineCap = 'round';
    ctx.beginPath();
    ctx.moveTo(object.points[0].x, object.points[0].y);
    for (let i = 1; i < object.points.length; i++) {
      const p = object.points[i - 1], n = object.points[i];
      ctx.quadraticCurveTo(p.x, p.y, (p.x + n.x) / 2, (p.y + n.y) / 2);
    }
    if (object.points.length === 1) ctx.arc(object.points[0].x, object.points[0].y, object.size / 2, 0, Math.PI * 2);
    ctx.stroke();
    ctx.restore();
  }

  function shapePath(ctx, object) {
    const b = objectBounds(object);
    ctx.beginPath();
    if (object.subtype === 'rect') ctx.rect(b.x, b.y, b.w, b.h);
    else if (object.subtype === 'ellipse') ctx.ellipse(b.x + b.w / 2, b.y + b.h / 2, b.w / 2, b.h / 2, 0, 0, Math.PI * 2);
    else if (object.subtype === 'polygon') {
      const cx = b.x + b.w / 2, cy = b.y + b.h / 2;
      for (let i = 0; i < 5; i++) {
        const angle = -Math.PI / 2 + i * Math.PI * 2 / 5;
        const x = cx + Math.cos(angle) * b.w / 2, y = cy + Math.sin(angle) * b.h / 2;
        i ? ctx.lineTo(x, y) : ctx.moveTo(x, y);
      }
      ctx.closePath();
    } else {
      ctx.moveTo(object.x1, object.y1);
      ctx.lineTo(object.x2, object.y2);
      if (object.subtype === 'arrow') {
        const angle = Math.atan2(object.y2 - object.y1, object.x2 - object.x1);
        const head = Math.max(18, object.width * 3);
        ctx.moveTo(object.x2, object.y2);
        ctx.lineTo(object.x2 - Math.cos(angle - .55) * head, object.y2 - Math.sin(angle - .55) * head);
        ctx.moveTo(object.x2, object.y2);
        ctx.lineTo(object.x2 - Math.cos(angle + .55) * head, object.y2 - Math.sin(angle + .55) * head);
      }
    }
  }

  function drawObject(ctx, object, includeEffects = true) {
    ctx.save();
    ctx.beginPath();
    ctx.rect(0, 0, overlayCanvas.width, overlayCanvas.height);
    ctx.clip();
    if (object.type === 'stroke') drawStroke(ctx, object);
    else if (object.type === 'text') {
      ctx.globalAlpha = object.opacity ?? 1;
      ctx.font = `${object.weight || 500} ${object.size}px "${object.font}", "Noto Sans CJK SC", "Noto Sans", sans-serif`;
      ctx.textAlign = object.align;
      ctx.textBaseline = 'alphabetic';
      ctx.fillStyle = object.color;
      ctx.strokeStyle = object.strokeColor || '#111111';
      ctx.lineWidth = Math.max(2, object.size / 14);
      const lines = object.text.split('\n');
      let x = object.x;
      if (object.align === 'center') x += object.width / 2;
      if (object.align === 'right') x += object.width;
      lines.forEach((line, index) => {
        const y = object.y + index * object.size * 1.28;
        if (object.outline) ctx.strokeText(line, x, y, object.width);
        ctx.fillText(line, x, y, object.width);
      });
    } else if (object.type === 'shape') {
      ctx.strokeStyle = object.color;
      ctx.fillStyle = object.color;
      ctx.lineWidth = object.width;
      ctx.lineJoin = 'round';
      ctx.lineCap = 'round';
      shapePath(ctx, object);
      if (object.fill && !['line', 'arrow'].includes(object.subtype)) {
        ctx.globalAlpha = .22;
        ctx.fill();
        ctx.globalAlpha = 1;
      }
      ctx.stroke();
    } else if (object.type === 'mosaic' && includeEffects) {
      drawMosaic(ctx, object);
    }
    ctx.restore();
  }

  function drawMosaic(ctx, object) {
    const b = objectBounds(object);
    if (b.w < 2 || b.h < 2) return;
    const source = document.createElement('canvas');
    source.width = compositeCanvas.width;
    source.height = compositeCanvas.height;
    const sctx = source.getContext('2d');
    sctx.drawImage(photoCanvas, 0, 0);
    sctx.drawImage(overlayCanvas, 0, 0);
    ctx.save();
    ctx.beginPath();
    ctx.rect(b.x, b.y, b.w, b.h);
    ctx.clip();
    if (object.mode === 'blur') {
      ctx.filter = `blur(${Math.max(3, object.strength / 2)}px)`;
      ctx.drawImage(source, b.x - 24, b.y - 24, b.w + 48, b.h + 48, b.x - 24, b.y - 24, b.w + 48, b.h + 48);
    } else {
      const block = Math.max(5, object.strength);
      const sw = Math.max(1, Math.round(b.w / block)), sh = Math.max(1, Math.round(b.h / block));
      const tiny = document.createElement('canvas');
      tiny.width = sw; tiny.height = sh;
      tiny.getContext('2d').drawImage(source, b.x, b.y, b.w, b.h, 0, 0, sw, sh);
      ctx.imageSmoothingEnabled = false;
      ctx.drawImage(tiny, 0, 0, sw, sh, b.x, b.y, b.w, b.h);
      ctx.imageSmoothingEnabled = true;
    }
    ctx.filter = 'none';
    ctx.restore();
  }

  function renderOverlay() {
    overlayCtx.clearRect(0, 0, overlayCanvas.width, overlayCanvas.height);
    if (state.compare) return;
    for (const object of state.objects) drawObject(overlayCtx, object);
    if (state.grid) drawGrid();
    if (state.cropRect) drawCropOverlay();
    for (const id of state.selected) {
      const object = state.objects.find(item => item.id === id);
      if (object) drawSelection(object);
    }
  }

  function drawGrid() {
    const step = Math.max(40, Math.round(Math.min(overlayCanvas.width, overlayCanvas.height) / 12));
    overlayCtx.save();
    overlayCtx.strokeStyle = '#ffffff55';
    overlayCtx.lineWidth = 1 / state.zoom;
    overlayCtx.beginPath();
    for (let x = step; x < overlayCanvas.width; x += step) { overlayCtx.moveTo(x, 0); overlayCtx.lineTo(x, overlayCanvas.height); }
    for (let y = step; y < overlayCanvas.height; y += step) { overlayCtx.moveTo(0, y); overlayCtx.lineTo(overlayCanvas.width, y); }
    overlayCtx.stroke();
    overlayCtx.restore();
  }

  function drawSelection(object) {
    const b = objectBounds(object);
    overlayCtx.save();
    overlayCtx.setLineDash([7 / state.zoom, 5 / state.zoom]);
    overlayCtx.lineWidth = 1.5 / state.zoom;
    overlayCtx.strokeStyle = '#ffffff';
    overlayCtx.fillStyle = '#edbc9d';
    overlayCtx.strokeRect(b.x - 5 / state.zoom, b.y - 5 / state.zoom, b.w + 10 / state.zoom, b.h + 10 / state.zoom);
    for (const [x, y] of [[b.x, b.y], [b.x + b.w, b.y], [b.x, b.y + b.h], [b.x + b.w, b.y + b.h]]) {
      overlayCtx.fillRect(x - 4 / state.zoom, y - 4 / state.zoom, 8 / state.zoom, 8 / state.zoom);
    }
    overlayCtx.restore();
  }

  function drawCropOverlay() {
    const r = state.cropRect;
    overlayCtx.save();
    overlayCtx.fillStyle = '#00000088';
    overlayCtx.fillRect(0, 0, overlayCanvas.width, r.y);
    overlayCtx.fillRect(0, r.y, r.x, r.h);
    overlayCtx.fillRect(r.x + r.w, r.y, overlayCanvas.width - r.x - r.w, r.h);
    overlayCtx.fillRect(0, r.y + r.h, overlayCanvas.width, overlayCanvas.height - r.y - r.h);
    overlayCtx.strokeStyle = '#ffffff';
    overlayCtx.lineWidth = 2 / state.zoom;
    overlayCtx.setLineDash([8 / state.zoom, 5 / state.zoom]);
    overlayCtx.strokeRect(r.x, r.y, r.w, r.h);
    overlayCtx.restore();
  }

  function renderAll() {
    renderPhoto();
    renderOverlay();
    updateDocumentChrome();
  }

  function updateStage() {
    const rect = viewport.getBoundingClientRect();
    stage.style.left = `${rect.width / 2 - photoCanvas.width * state.zoom / 2 + state.panX}px`;
    stage.style.top = `${rect.height / 2 - photoCanvas.height * state.zoom / 2 + state.panY}px`;
    stage.style.transform = `scale(${state.zoom})`;
    $('#zoom-range').value = Math.round(state.zoom * 100);
    $('#zoom-label').textContent = `${Math.round(state.zoom * 100)}%`;
    $('#zoom-range').style.setProperty('--fill', `${(state.zoom * 100 - 5) / 2.95}%`);
  }

  function fitCanvas() {
    if (!state.hasImage) return;
    state.fitView = true;
    const rect = viewport.getBoundingClientRect();
    state.zoom = clamp(Math.min((rect.width - 110) / photoCanvas.width, (rect.height - 150) / photoCanvas.height), .05, 3);
    state.panX = 0; state.panY = 0;
    updateStage();
  }

  function setZoom(value, clientX, clientY) {
    state.fitView = false;
    const old = state.zoom;
    const next = clamp(value, .05, 3);
    if (clientX != null) {
      const vr = viewport.getBoundingClientRect();
      const sx = vr.width / 2 - photoCanvas.width * old / 2 + state.panX;
      const sy = vr.height / 2 - photoCanvas.height * old / 2 + state.panY;
      const px = (clientX - vr.left - sx) / old, py = (clientY - vr.top - sy) / old;
      const nsx = clientX - vr.left - px * next, nsy = clientY - vr.top - py * next;
      state.panX = nsx - (vr.width / 2 - photoCanvas.width * next / 2);
      state.panY = nsy - (vr.height / 2 - photoCanvas.height * next / 2);
    }
    state.zoom = next;
    updateStage();
  }

  function pointFromEvent(event) {
    const rect = overlayCanvas.getBoundingClientRect();
    return { x: clamp((event.clientX - rect.left) / state.zoom, 0, overlayCanvas.width), y: clamp((event.clientY - rect.top) / state.zoom, 0, overlayCanvas.height) };
  }

  function hitTest(point) {
    for (let i = state.objects.length - 1; i >= 0; i--) {
      const object = state.objects[i], b = objectBounds(object), pad = Math.max(12 / state.zoom, object.width || object.size || 0);
      if (point.x >= b.x - pad && point.x <= b.x + b.w + pad && point.y >= b.y - pad && point.y <= b.y + b.h + pad) return object;
    }
    return null;
  }

  function moveObject(object, dx, dy) {
    if (object.type === 'stroke') object.points.forEach(p => { p.x += dx; p.y += dy; });
    else if (object.type === 'text') { object.x += dx; object.y += dy; }
    else { object.x1 += dx; object.x2 += dx; object.y1 += dy; object.y2 += dy; }
  }

  function selectTool(tool) {
    state.tool = tool;
    if (!['select', 'hand', 'adjust', 'filters', 'crop', 'eyedropper'].includes(tool)) state.previousTool = tool;
    $$('[data-tool]').forEach(button => button.classList.toggle('active', button.dataset.tool === tool));
    overlayCanvas.style.cursor = tool === 'hand' ? 'grab' : tool === 'text' ? 'text' : tool === 'select' ? 'default' : 'crosshair';
    if (tool !== 'crop') state.cropRect = null;
    const hints = {
      brush: '拖动绘制 · 一笔一次撤销', text: '点击画布放置多行文字', shape: '拖动绘制 · Shift 约束比例 / 角度',
      mosaic: '拖出矩形区域进行打码', crop: '拖出裁剪区域后在右侧应用', eyedropper: '移动查看像素 · 点击取色',
      select: '点击选择 · Shift 多选 · 拖动移动', hand: '拖动画布 · 滚轮缩放'
    };
    $('#tool-hint').textContent = hints[tool] || '滚轮缩放 · 空格拖动平移 · 按住 M 对比原图';
    renderInspector();
    renderOverlay();
  }

  function sliderRow(key, label, value, min = -100, max = 100) {
    const fill = (value - min) / (max - min) * 100;
    return `<div class="slider-field"><label class="slider-label" for="slider-${key}">${label}<output class="slider-value">${value > 0 ? '+' : ''}${Math.round(value)}</output></label><input id="slider-${key}" data-adjust="${key}" type="range" min="${min}" max="${max}" value="${value}" style="--fill:${fill}%"></div>`;
  }

  function colorControls() {
    return `<label class="field-label">颜色</label><div class="color-row"><input data-color-control type="color" value="${state.color}"><span class="hex-value">${state.color.toUpperCase()}</span></div><div class="swatches">${['#f7f4ed','#1b1d1e','#eeb99a','#e46a5d','#e1b74e','#6da788','#61a3c7','#9275b9'].map(c => `<button class="swatch ${c === state.color ? 'selected' : ''}" data-swatch="${c}" style="--swatch:${c}" title="${c}"></button>`).join('')}</div>`;
  }

  function renderInspector() {
    const [eyebrow, title, note] = panelMeta[state.tool] || panelMeta.adjust;
    $('#panel-eyebrow').textContent = eyebrow;
    $('#panel-title').textContent = title;
    $('#inspector-note').textContent = note;
    if (state.tool === 'adjust') {
      inspector.innerHTML = `<button class="auto-button" data-panel-action="auto">${icon('filter')}自动优化</button><div class="section-label">基础调整<span class="section-meta">NON-DESTRUCTIVE</span></div>${sliderRow('exposure','曝光',state.adjustments.exposure)}${sliderRow('contrast','对比度',state.adjustments.contrast)}${sliderRow('highlights','高光',state.adjustments.highlights)}${sliderRow('shadows','阴影',state.adjustments.shadows)}<div class="section-rule"></div>${sliderRow('saturation','饱和度',state.adjustments.saturation)}${sliderRow('temperature','色温',state.adjustments.temperature)}<div class="histogram">${[22,32,28,46,66,82,55,72,92,78,44,31,24,38,52,34,22,13].map(h => `<i style="height:${h}%"></i>`).join('')}</div><div class="histogram-labels"><span>暗部</span><span>中间调</span><span>高光</span></div>`;
    } else if (state.tool === 'filters') {
      inspector.innerHTML = `<p class="panel-intro">一键确定照片的气质，再用强度留住自己的分寸。</p><div class="filter-grid">${Object.entries(presets).map(([key, p]) => `<button class="filter-card ${state.preset === key ? 'selected' : ''}" data-preset="${key}"><img src="assets/demo.jpg" alt=""><span>${p.label}</span></button>`).join('')}</div><div class="section-rule"></div>${sliderRow('presetStrength','滤镜强度',state.presetStrength,0,100)}`;
    } else if (state.tool === 'brush') {
      inspector.innerHTML = `${colorControls()}<div class="section-rule"></div>${sliderRow('brushSize','笔刷大小',state.brush.size,1,120)}${sliderRow('brushOpacity','不透明度',state.brush.opacity,5,100)}<p class="muted-text">圆头软边画笔。连续移动合并为一条笔迹，最多 4096 个采样点。</p>`;
    } else if (state.tool === 'text') {
      const object = state.objects.find(o => o.id === state.selected[0] && o.type === 'text');
      inspector.innerHTML = `<label class="field-label">文字内容</label><textarea id="text-content" placeholder="输入多行文字">${object ? escapeHtml(object.text) : '在这里写下\n想留下的话'}</textarea><label class="field-label">字体</label><select id="text-font"><option>Noto Sans CJK SC</option><option>Noto Serif CJK SC</option><option>Source Han Sans SC</option><option>DejaVu Sans</option><option>sans-serif</option></select>${sliderRow('textSize','字号',object?.size || state.text.size,12,160)}<div class="inline-options">${['left','center','right'].map(a => `<button data-align="${a}" class="${(object?.align || state.text.align) === a ? 'selected' : ''}">${{left:'左对齐',center:'居中',right:'右对齐'}[a]}</button>`).join('')}</div><label class="checkbox-line"><input id="text-outline" type="checkbox" ${(object?.outline ?? state.text.outline) ? 'checked' : ''}>深色描边</label>${colorControls()}<p class="muted-text">字体列表优先使用中文字体；缺字时回退到 Noto Sans CJK 与系统无衬线字体。</p>`;
      if (object) $('#text-font', inspector).value = object.font;
    } else if (state.tool === 'shape') {
      const types = [['rect','rect','矩形'],['ellipse','ellipse','椭圆'],['line','line','直线'],['arrow','arrow','箭头'],['polygon','polygon','多边形']];
      inspector.innerHTML = `<div class="tool-options">${types.map(([key, ico, label]) => `<button class="option-button ${state.shape === key ? 'selected' : ''}" data-shape="${key}">${icon(ico)}<span>${label}</span></button>`).join('')}</div>${colorControls()}<div class="section-rule"></div>${sliderRow('shapeWidth','线条粗细',state.shapeStyle.width,1,40)}<label class="checkbox-line"><input id="shape-fill" type="checkbox" ${state.shapeStyle.fill ? 'checked' : ''}>半透明填充</label>`;
    } else if (state.tool === 'mosaic') {
      inspector.innerHTML = `<div class="tool-options"><button class="option-button ${state.mosaicMode === 'mosaic' ? 'selected' : ''}" data-mosaic-mode="mosaic">${icon('mosaic')}<span>马赛克</span></button><button class="option-button ${state.mosaicMode === 'blur' ? 'selected' : ''}" data-mosaic-mode="blur">${icon('filter')}<span>模糊</span></button></div>${sliderRow('mosaicStrength','块大小 / 强度',state.mosaic.strength,5,48)}<p class="muted-text">拖出矩形即可遮挡。用于高敏感内容时，建议导出后再检查一次最终像素。</p>`;
    } else if (state.tool === 'crop') {
      const r = state.cropRect;
      inspector.innerHTML = `<p class="panel-intro">在画布上拖出需要保留的区域。裁剪后对象坐标随新画布移动，区域外内容被截去。</p>${r ? `<div class="section-label">${Math.round(r.w)} × ${Math.round(r.h)} px<span class="section-meta">SELECTION</span></div><button class="primary-button wide-button" data-panel-action="apply-crop">应用裁剪</button><button class="secondary-button wide-button" data-panel-action="clear-crop">重新选择</button>` : '<p class="muted-text">尚未选择裁剪区域。</p>'}`;
    } else if (state.tool === 'select') {
      inspector.innerHTML = objectPanel();
    } else if (state.tool === 'eyedropper') {
      inspector.innerHTML = `<p class="panel-intro">从合成后的画面取色，画笔、文字和形状会共享前景色。</p><div class="color-row"><span class="foreground-chip" style="background:${state.color}"></span><strong class="hex-value">${state.color.toUpperCase()}</strong></div><p class="muted-text">点击后会返回上一个绘图工具。</p>`;
    } else {
      inspector.innerHTML = `<p class="panel-intro">拖动画布寻找细节。按住空格也可以从任何工具临时进入平移。</p><button class="secondary-button wide-button" data-action="fit">适应窗口</button><button class="secondary-button wide-button" data-action="actual">实际大小 · 100%</button>`;
    }
    bindInspectorEvents();
    document.dispatchEvent(new CustomEvent('nekopic:panel', { detail: { tool: state.tool } }));
  }

  function objectPanel() {
    const rows = state.objects.slice().reverse().map(object => `<button class="object-row ${state.selected.includes(object.id) ? 'selected' : ''}" data-object-id="${object.id}">${icon(object.type === 'text' ? 'text' : object.type === 'stroke' ? 'brush' : object.type === 'mosaic' ? 'mosaic' : 'shape')}<span>${objectLabel(object)}</span><small>${object.type.toUpperCase()}</small></button>`).join('');
    return `<p class="panel-intro">选择一个或多个对象，然后对齐、调整层级或删除。</p><div class="inline-options"><button data-object-action="align-left">左对齐</button><button data-object-action="align-center">居中</button><button data-object-action="align-right">右对齐</button></div><div class="inline-options"><button data-object-action="back">下移一层</button><button data-object-action="front">上移一层</button></div><div class="object-list">${rows || '<p class="muted-text">还没有可编辑对象。</p>'}</div>`;
  }

  function objectLabel(object) {
    if (object.type === 'text') return object.text.split('\n')[0].slice(0, 12) || '文字';
    if (object.type === 'stroke') return '画笔笔迹';
    if (object.type === 'mosaic') return object.mode === 'blur' ? '模糊区域' : '马赛克区域';
    return { rect: '矩形', ellipse: '椭圆', line: '直线', arrow: '箭头', polygon: '多边形' }[object.subtype] || '形状';
  }

  function escapeHtml(value) {
    return value.replace(/[&<>"']/g, char => ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' })[char]);
  }

  function bindInspectorEvents() {
    $$('input[type=range]', inspector).forEach(input => {
      input.addEventListener('pointerdown', () => input.dataset.before = input.value);
      input.addEventListener('input', handleSlider);
      input.addEventListener('change', () => {
        if (input.dataset.before !== input.value) commit(`${input.closest('.slider-field')?.querySelector('.slider-label')?.firstChild?.textContent || '参数'}已调整`);
      });
    });
    $('[data-color-control]', inspector)?.addEventListener('input', event => setColor(event.target.value));
    $('#text-content', inspector)?.addEventListener('focus', event => event.target.dataset.before = event.target.value);
    $('#text-content', inspector)?.addEventListener('input', event => {
      const object = selectedText();
      if (object) { object.text = event.target.value; renderOverlay(); }
    });
    $('#text-content', inspector)?.addEventListener('blur', event => {
      if (selectedText() && event.target.dataset.before !== event.target.value) commit('文字已编辑');
    });
    $('#text-font', inspector)?.addEventListener('change', event => updateTextProperty('font', event.target.value));
    $('#text-outline', inspector)?.addEventListener('change', event => updateTextProperty('outline', event.target.checked));
    $('#shape-fill', inspector)?.addEventListener('change', event => { state.shapeStyle.fill = event.target.checked; });
  }

  function handleSlider(event) {
    const input = event.target, value = Number(input.value), key = input.dataset.adjust;
    const output = input.closest('.slider-field')?.querySelector('output');
    if (output) output.textContent = `${value > 0 && !['presetStrength','brushSize','brushOpacity','textSize','shapeWidth','mosaicStrength'].includes(key) ? '+' : ''}${value}`;
    input.style.setProperty('--fill', `${(value - Number(input.min)) / (Number(input.max) - Number(input.min)) * 100}%`);
    if (key in state.adjustments) state.adjustments[key] = value;
    else if (key === 'presetStrength') state.presetStrength = value;
    else if (key === 'brushSize') state.brush.size = value;
    else if (key === 'brushOpacity') state.brush.opacity = value;
    else if (key === 'shapeWidth') state.shapeStyle.width = value;
    else if (key === 'mosaicStrength') state.mosaic.strength = value;
    else if (key === 'textSize') {
      state.text.size = value;
      const object = selectedText(); if (object) object.size = value;
    }
    renderAll();
  }

  function selectedText() { return state.objects.find(o => o.id === state.selected[0] && o.type === 'text'); }
  function updateTextProperty(key, value) {
    state.text[key] = value;
    const object = selectedText();
    if (object) { object[key] = value; renderOverlay(); commit('文字样式已调整'); }
  }

  function setColor(color) {
    state.color = color.toLowerCase();
    $('#global-color').value = state.color;
    $('#rail-color').style.background = state.color;
    const object = state.objects.find(o => o.id === state.selected[0]);
    if (object && ['text','shape'].includes(object.type)) { object.color = state.color; renderOverlay(); }
    renderInspector();
  }

  function pointerDown(event) {
    if (!state.hasImage || event.button > 1) return;
    if (event.button === 1 || state.space || state.tool === 'hand') {
      state.active = { kind: 'pan', x: event.clientX, y: event.clientY, panX: state.panX, panY: state.panY };
      overlayCanvas.style.cursor = 'grabbing';
      overlayCanvas.setPointerCapture(event.pointerId);
      event.preventDefault();
      return;
    }
    const point = pointFromEvent(event);
    overlayCanvas.setPointerCapture(event.pointerId);
    if (state.tool === 'brush') {
      const object = { id: uid(), type: 'stroke', color: state.color, size: state.brush.size, opacity: state.brush.opacity, points: [point] };
      state.objects.push(object); state.selected = [object.id]; state.active = { kind: 'draw', object };
    } else if (state.tool === 'shape') {
      const object = { id: uid(), type: 'shape', subtype: state.shape, color: state.color, width: state.shapeStyle.width, fill: state.shapeStyle.fill, x1: point.x, y1: point.y, x2: point.x, y2: point.y };
      state.objects.push(object); state.selected = [object.id]; state.active = { kind: 'shape', object, start: point };
    } else if (state.tool === 'mosaic') {
      const object = { id: uid(), type: 'mosaic', mode: state.mosaicMode, strength: state.mosaic.strength, x1: point.x, y1: point.y, x2: point.x, y2: point.y };
      state.objects.push(object); state.selected = [object.id]; state.active = { kind: 'shape', object, start: point };
    } else if (state.tool === 'crop') {
      state.cropRect = { x: point.x, y: point.y, w: 0, h: 0 };
      state.active = { kind: 'crop', start: point };
    } else if (state.tool === 'text') {
      const content = $('#text-content')?.value || '双击编辑文字';
      const object = { id: uid(), type: 'text', x: point.x, y: point.y, width: Math.min(600, overlayCanvas.width - point.x), text: content, size: state.text.size, font: state.text.font, align: state.text.align, outline: state.text.outline, strokeColor: '#151718', color: state.color };
      state.objects.push(object); state.selected = [object.id]; commit('已添加文字'); renderOverlay(); renderInspector();
    } else if (state.tool === 'select') {
      const hit = hitTest(point);
      if (!hit) { state.selected = []; renderOverlay(); renderInspector(); return; }
      if (event.shiftKey) state.selected = state.selected.includes(hit.id) ? state.selected.filter(id => id !== hit.id) : [...state.selected, hit.id];
      else if (!state.selected.includes(hit.id)) state.selected = [hit.id];
      state.active = { kind: 'move', start: point, originals: new Map(state.selected.map(id => [id, clone(state.objects.find(o => o.id === id))])) };
      renderOverlay(); renderInspector();
    } else if (state.tool === 'eyedropper') sampleColor(event, true);
    renderOverlay();
  }

  function pointerMove(event) {
    if (state.tool === 'eyedropper' && state.hasImage) updateLoupe(event);
    const active = state.active;
    if (!active) return;
    if (active.kind === 'pan') {
      state.panX = active.panX + event.clientX - active.x;
      state.panY = active.panY + event.clientY - active.y;
      updateStage(); return;
    }
    const point = pointFromEvent(event);
    if (active.kind === 'draw') {
      if (active.object.points.length < LIMITS.strokePoints) active.object.points.push(point);
    } else if (active.kind === 'shape') {
      let x = point.x, y = point.y;
      if (event.shiftKey) {
        if (['line','arrow'].includes(active.object.subtype)) {
          const dx = x - active.start.x, dy = y - active.start.y, distance = Math.hypot(dx, dy);
          const angle = Math.round(Math.atan2(dy, dx) / (Math.PI / 4)) * Math.PI / 4;
          x = active.start.x + Math.cos(angle) * distance; y = active.start.y + Math.sin(angle) * distance;
        } else {
          const size = Math.max(Math.abs(x - active.start.x), Math.abs(y - active.start.y));
          x = active.start.x + Math.sign(x - active.start.x || 1) * size; y = active.start.y + Math.sign(y - active.start.y || 1) * size;
        }
      }
      active.object.x2 = x; active.object.y2 = y;
    } else if (active.kind === 'crop') {
      state.cropRect = { x: Math.min(active.start.x, point.x), y: Math.min(active.start.y, point.y), w: Math.abs(point.x - active.start.x), h: Math.abs(point.y - active.start.y) };
    } else if (active.kind === 'move') {
      let dx = point.x - active.start.x, dy = point.y - active.start.y;
      if (state.snap) {
        const selectedObjects = state.selected.map(id => state.objects.find(o => o.id === id));
        const box = combinedBounds(selectedObjects);
        if (Math.abs(box.x + box.w / 2 + dx - overlayCanvas.width / 2) < 12 / state.zoom) dx = overlayCanvas.width / 2 - box.x - box.w / 2;
        if (Math.abs(box.y + box.h / 2 + dy - overlayCanvas.height / 2) < 12 / state.zoom) dy = overlayCanvas.height / 2 - box.y - box.h / 2;
      }
      for (const [id, original] of active.originals) {
        const target = state.objects.find(o => o.id === id);
        Object.assign(target, clone(original)); moveObject(target, dx, dy);
      }
    }
    renderOverlay();
  }

  function pointerUp(event) {
    const active = state.active;
    if (!active) return;
    state.active = null;
    if (overlayCanvas.hasPointerCapture(event.pointerId)) overlayCanvas.releasePointerCapture(event.pointerId);
    overlayCanvas.style.cursor = state.tool === 'hand' ? 'grab' : state.tool === 'select' ? 'default' : 'crosshair';
    if (active.kind === 'draw') commit('已添加一笔');
    else if (active.kind === 'shape') {
      const b = objectBounds(active.object);
      if (b.w < 3 && b.h < 3) state.objects = state.objects.filter(o => o.id !== active.object.id);
      else commit(active.object.type === 'mosaic' ? '已添加打码区域' : '已添加形状');
    } else if (active.kind === 'move') commit('对象已移动');
    if (active.kind === 'crop') renderInspector();
    renderAll();
  }

  function combinedBounds(objects) {
    const boxes = objects.filter(Boolean).map(objectBounds);
    if (!boxes.length) return { x:0,y:0,w:0,h:0 };
    const left = Math.min(...boxes.map(b => b.x)), top = Math.min(...boxes.map(b => b.y));
    const right = Math.max(...boxes.map(b => b.x + b.w)), bottom = Math.max(...boxes.map(b => b.y + b.h));
    return { x:left, y:top, w:right-left, h:bottom-top };
  }

  function compose(includeSelection = false, background = null) {
    compositeCtx.save();
    compositeCtx.clearRect(0, 0, compositeCanvas.width, compositeCanvas.height);
    if (background) { compositeCtx.fillStyle = background; compositeCtx.fillRect(0, 0, compositeCanvas.width, compositeCanvas.height); }
    compositeCtx.drawImage(photoCanvas, 0, 0);
    for (const object of state.objects) drawObject(compositeCtx, object);
    compositeCtx.restore();
    return compositeCanvas;
  }

  function updateLoupe(event) {
    const point = pointFromEvent(event), source = compose();
    const ctx = $('#loupe-canvas').getContext('2d');
    const size = 13;
    ctx.imageSmoothingEnabled = false;
    ctx.clearRect(0, 0, 120, 120);
    ctx.drawImage(source, point.x - size / 2, point.y - size / 2, size, size, 0, 0, 120, 120);
    ctx.strokeStyle = '#ffffff'; ctx.lineWidth = 2; ctx.strokeRect(55, 55, 10, 10);
    const data = source.getContext('2d').getImageData(Math.floor(point.x), Math.floor(point.y), 1, 1).data;
    const hex = rgbToHex(data[0], data[1], data[2]);
    $('#loupe-color').textContent = hex;
    const vr = viewport.getBoundingClientRect(), loupe = $('#loupe');
    loupe.hidden = false;
    loupe.style.left = `${clamp(event.clientX - vr.left + 18, 8, vr.width - 150)}px`;
    loupe.style.top = `${clamp(event.clientY - vr.top + 18, 8, vr.height - 160)}px`;
  }

  function sampleColor(event, select = false) {
    const point = pointFromEvent(event), data = compose().getContext('2d').getImageData(Math.floor(point.x), Math.floor(point.y), 1, 1).data;
    setColor(rgbToHex(data[0], data[1], data[2]));
    if (select) { toast(`已取色 ${state.color.toUpperCase()}`); selectTool(state.previousTool || 'brush'); $('#loupe').hidden = true; }
  }

  function rgbToHex(r, g, b) { return `#${[r,g,b].map(v => v.toString(16).padStart(2,'0')).join('')}`.toUpperCase(); }

  async function loadImageSource(source, name = '未命名图片.png', mime = 'image/png', restored = null) {
    const url = typeof source === 'string' ? source : URL.createObjectURL(source);
    const image = new Image();
    image.decoding = 'async';
    image.onload = () => {
      const width = image.naturalWidth, height = image.naturalHeight;
      if (width > LIMITS.edge || height > LIMITS.edge || width * height > LIMITS.pixels) {
        toast('图片超过 8192 px 单边或 3200 万像素上限');
        if (typeof source !== 'string') URL.revokeObjectURL(url); return;
      }
      const base = document.createElement('canvas'); base.width = width; base.height = height;
      base.getContext('2d', { colorSpace: 'srgb' }).drawImage(image, 0, 0);
      state.base = base; state.hasImage = true; state.name = name; state.mime = mime;
      state.objects = restored?.objects || []; state.adjustments = restored?.adjustments || { exposure:0,contrast:0,highlights:0,shadows:0,saturation:0,temperature:0,sharpness:0 };
      state.preset = restored?.preset || 'none'; state.presetStrength = restored?.presetStrength ?? 100;
      state.rev = restored?.rev || 0; state.savedRev = restored?.savedRev || 0; state.selected = [];
      setCanvasSize(width, height); initHistory(); renderAll(); renderInspector();
      $('#canvas-empty').hidden = true; stage.hidden = false; $('#canvas-caption').hidden = name !== '山间来信.jpg';
      $('#workspace-hint').textContent = name === '山间来信.jpg' ? '调一点光，让照片靠近记忆。' : '所有编辑都留在本机浏览器中。';
      requestAnimationFrame(fitCanvas);
      rememberRecent(name, mime);
      if (typeof source !== 'string') URL.revokeObjectURL(url);
    };
    image.onerror = () => toast('无法读取这张图片');
    image.src = url;
  }

  function openFile(file) {
    if (!file || !file.type.startsWith('image/')) { toast('请选择图片文件'); return; }
    loadImageSource(file, file.name, file.type);
  }

  function rememberRecent(name, mime) {
    state.recent = [{ name, mime, time: Date.now() }, ...state.recent.filter(r => r.name !== name)].slice(0, 6);
    localStorage.setItem('nekopic-recent', JSON.stringify(state.recent));
  }

  function rotate(clockwise = true) {
    const oldW = state.base.width, oldH = state.base.height;
    const next = document.createElement('canvas'); next.width = oldH; next.height = oldW;
    const ctx = next.getContext('2d');
    ctx.translate(clockwise ? oldH : 0, clockwise ? 0 : oldW);
    ctx.rotate((clockwise ? 1 : -1) * Math.PI / 2); ctx.drawImage(state.base, 0, 0);
    state.base = next;
    transformObjects((x,y) => clockwise ? ({ x: oldH - y, y: x }) : ({ x: y, y: oldW - x }), oldH, oldW);
    setCanvasSize(oldH, oldW); commit(clockwise ? '已顺时针旋转' : '已逆时针旋转'); renderAll(); fitCanvas();
  }

  function flip(horizontal) {
    const w = state.base.width, h = state.base.height, next = document.createElement('canvas'); next.width=w; next.height=h;
    const ctx = next.getContext('2d'); ctx.translate(horizontal ? w : 0, horizontal ? 0 : h); ctx.scale(horizontal ? -1 : 1, horizontal ? 1 : -1); ctx.drawImage(state.base,0,0);
    state.base = next; transformObjects((x,y) => ({ x: horizontal ? w-x : x, y: horizontal ? y : h-y }), w, h);
    commit(horizontal ? '已水平翻转' : '已垂直翻转'); renderAll();
  }

  function transformObjects(fn) {
    for (const object of state.objects) {
      if (object.type === 'stroke') object.points = object.points.map(p => fn(p.x,p.y));
      else if (object.type === 'text') { const p=fn(object.x,object.y); object.x=p.x; object.y=p.y; }
      else { const a=fn(object.x1,object.y1), b=fn(object.x2,object.y2); object.x1=a.x;object.y1=a.y;object.x2=b.x;object.y2=b.y; }
    }
  }

  function resizeImage(width, height) {
    const oldW=state.base.width, oldH=state.base.height, sx=width/oldW, sy=height/oldH;
    const next=document.createElement('canvas'); next.width=width;next.height=height;
    const ctx=next.getContext('2d'); ctx.imageSmoothingQuality='high';ctx.drawImage(state.base,0,0,width,height);state.base=next;
    transformObjects((x,y)=>({x:x*sx,y:y*sy}));
    for (const object of state.objects) {
      if (object.size) object.size *= Math.sqrt(sx * sy);
      if (object.width) object.width *= object.type === 'text' ? sx : Math.sqrt(sx * sy);
    }
    setCanvasSize(width,height);commit('图片尺寸已修改');renderAll();fitCanvas();
  }

  function resizeCanvas(width,height,anchor,transparent,background) {
    const oldW=state.base.width,oldH=state.base.height;
    const cols={left:0,center:.5,right:1}, rows={top:0,center:.5,bottom:1};
    const [v,h]=anchor==='center'?['center','center']:anchor.split('-');
    const dx=Math.round((width-oldW)*cols[h]),dy=Math.round((height-oldH)*rows[v]);
    const next=document.createElement('canvas');next.width=width;next.height=height;const ctx=next.getContext('2d');
    if(!transparent){ctx.fillStyle=background;ctx.fillRect(0,0,width,height);}ctx.drawImage(state.base,dx,dy);state.base=next;
    transformObjects((x,y)=>({x:x+dx,y:y+dy}));setCanvasSize(width,height);commit('画布尺寸已修改');renderAll();fitCanvas();
  }

  function applyCrop() {
    const r=state.cropRect;if(!r||r.w<2||r.h<2)return;
    const x=Math.round(r.x),y=Math.round(r.y),w=Math.round(r.w),h=Math.round(r.h);const next=document.createElement('canvas');next.width=w;next.height=h;next.getContext('2d').drawImage(state.base,x,y,w,h,0,0,w,h);state.base=next;
    transformObjects((px,py)=>({x:px-x,y:py-y}));
    state.objects=state.objects.filter(o=>{const b=objectBounds(o);return b.x+b.w>0&&b.y+b.h>0&&b.x<w&&b.y<h;});
    state.cropRect=null;setCanvasSize(w,h);commit('图片已裁剪');renderAll();renderInspector();fitCanvas();
  }

  function openSizeDialog(mode) {
    const dialog=$('#size-dialog');dialog.dataset.mode=mode;
    $('#size-title').textContent=mode==='image'?'修改图片尺寸':'修改画布尺寸';
    $('#size-eyebrow').textContent=mode==='image'?'IMAGE SIZE':'CANVAS SIZE';
    $('#size-description').textContent=mode==='image'?'底图和所有对象将按比例一起缩放。':'扩展或收缩画布，不缩放照片；对象随锚点移动。';
    $('#size-width').value=state.base.width;$('#size-height').value=state.base.height;
    $('#aspect-field').hidden=mode!=='image';$('#canvas-options').hidden=mode==='image';
    if(mode==='canvas') buildAnchorGrid();dialog.showModal();
  }

  function buildAnchorGrid(){
    $('#anchor-grid').innerHTML=['top-left','top-center','top-right','center-left','center-center','center-right','bottom-left','bottom-center','bottom-right'].map(a=>`<button class="${state.anchor===a.replace('center-center','center')?'selected':''}" data-anchor="${a.replace('center-center','center')}" title="${a}">•</button>`).join('');
  }

  function validSize(w,h){return w>=1&&h>=1&&w<=LIMITS.edge&&h<=LIMITS.edge&&w*h<=LIMITS.pixels;}

  function showExportDialog() {
    const dialog=$('#export-dialog');$('#export-name').value=state.name.replace(/\.[^.]+$/,'');$('#export-dimensions').textContent=`${state.base.width} × ${state.base.height} px`;
    const preview=compose();$('#export-preview').src=preview.toDataURL('image/jpeg',.75);updateExportControls();dialog.showModal();
  }

  function updateExportControls(){
    $$('.format-options button').forEach(b=>b.classList.toggle('selected',b.dataset.format===state.currentExport));
    $('#quality-field').hidden=state.currentExport==='png';$('#jpeg-background-field').hidden=state.currentExport!=='jpeg';
  }

  async function exportImage() {
    const format=state.currentExport,mime=`image/${format}`,quality=Number($('#export-quality').value)/100;
    const canvas=compose(false,format==='jpeg'?$('#jpeg-background').value:null);
    const blob=await new Promise(resolve=>canvas.toBlob(resolve,mime,quality));
    if(!blob){toast('当前浏览器不支持这种导出格式');return;}
    const ext=format==='jpeg'?'jpg':format;let name=($('#export-name').value.trim()||'NekoPic')+`.${ext}`;
    const finishSave = savedName => {
      state.name=savedName;state.mime=mime;state.savedRev=state.rev;markDirty();updateDocumentChrome();
      $('#export-dialog').close();toast(`已保存 ${savedName} · 当前对象仍可编辑`);clearRecovery();
    };
    try{
      if(typeof window.showSaveFilePicker==='function'){
        const handle=await window.showSaveFilePicker({suggestedName:name,types:[{description:`${format.toUpperCase()} 图片`,accept:{[mime]:[`.${ext}`]}}]});
        const writable=await handle.createWritable();await writable.write(blob);await writable.close();state.fileHandle=handle;name=handle.name;
      }else downloadBlob(blob,name);
      finishSave(name);
    }catch(error){
      if(error.name!=='AbortError') {downloadBlob(blob,name);finishSave(name);toast('文件选择不可用，已改用浏览器下载保存');}
    }
  }

  function downloadBlob(blob,name){const url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);}

  async function copyResult(){
    try{const blob=await new Promise(resolve=>compose().toBlob(resolve,'image/png'));await navigator.clipboard.write([new ClipboardItem({'image/png':blob})]);toast('合并图像已复制到剪贴板');}
    catch{toast('浏览器未允许写入剪贴板');}
  }

  function deleteSelected(){if(!state.selected.length)return;state.objects=state.objects.filter(o=>!state.selected.includes(o.id));state.selected=[];commit('对象已删除');renderOverlay();renderInspector();}
  function duplicateSelected(){const copies=state.objects.filter(o=>state.selected.includes(o.id)).map(o=>{const n=clone(o);n.id=uid();moveObject(n,18,18);return n;});if(!copies.length)return;state.objects.push(...copies);state.selected=copies.map(o=>o.id);commit('对象已复制');renderOverlay();renderInspector();}

  function alignSelected(mode){const selected=state.objects.filter(o=>state.selected.includes(o.id));if(selected.length<2)return toast('请至少选择两个对象');const target=combinedBounds(selected);for(const o of selected){const b=objectBounds(o);const dx=mode==='left'?target.x-b.x:mode==='right'?target.x+target.w-b.x-b.w:target.x+target.w/2-b.x-b.w/2;moveObject(o,dx,0);}commit('对象已对齐');renderOverlay();}
  function layerSelected(front){const ids=new Set(state.selected),selected=state.objects.filter(o=>ids.has(o.id)),others=state.objects.filter(o=>!ids.has(o.id));state.objects=front?[...others,...selected]:[...selected,...others];commit(front?'对象已上移':'对象已下移');renderOverlay();renderInspector();}

  function compare(on){state.compare=on;$('#compare-label').hidden=!on;renderAll();}

  function resetCurrentPanel(){
    if(state.tool==='adjust'){state.adjustments={exposure:0,contrast:0,highlights:0,shadows:0,saturation:0,temperature:0,sharpness:0};commit('调色已重置');}
    else if(state.tool==='filters'){state.preset='none';state.presetStrength=100;commit('滤镜已重置');}
    else if(state.tool==='crop')state.cropRect=null;
    renderAll();renderInspector();
  }

  function showInfo(type){
    const shortcuts=[['打开图片','Ctrl O'],['保存 / 另存为','Ctrl S / Ctrl Shift S'],['撤销 / 重做','Ctrl Z / Ctrl Shift Z'],['适应窗口 / 100%','Ctrl 0 / Ctrl 1'],['选择 / 画笔 / 文字','V / B / T'],['调色 / 滤镜 / 裁剪','A / F / C'],['取色器','I'],['临时平移','按住 Space'],['查看原图','按住 M'],['删除对象','Delete']];
    $('#info-title').textContent=type==='about'?'关于 NekoPic':'键盘快捷键';
    $('#info-content').innerHTML=type==='about'?`<p class="panel-intro">NekoPic 是面向 Linux 桌面的轻量图片编辑器概念原型。当前版本运行在浏览器中，用来验证布局、工具流程和保存规则。</p><p class="muted-text">32 MP / 单边 8192 px · 80 步撤销 · sRGB 合并输出 · IndexedDB 临时恢复。无工程文件，关闭重开后对象不可单独编辑。</p>`:shortcuts.map(([a,b])=>`<div class="shortcut-row"><span>${a}</span><kbd>${b}</kbd></div>`).join('');
    $('#info-dialog').showModal();
  }

  function showRecent(){
    $('#info-title').textContent='最近打开';
    $('#info-content').innerHTML=state.recent.length?state.recent.map(r=>`<button class="recent-row" data-recent="${escapeHtml(r.name)}">${escapeHtml(r.name)}<small>${new Date(r.time).toLocaleString('zh-CN')} · 浏览器不会保留原文件路径，请重新选择文件</small></button>`).join(''):'<p class="panel-intro">还没有最近打开的图片。</p>';
    $('#info-dialog').showModal();
  }

  function toast(message){const el=$('#toast');el.textContent=message;el.hidden=false;clearTimeout(toast.timer);toast.timer=setTimeout(()=>el.hidden=true,2600);}

  function closeImage(force=false){
    if(!force&&state.rev!==state.savedRev){$('#confirm-dialog').showModal();return;}
    state.hasImage=false;state.objects=[];state.selected=[];stage.hidden=true;$('#canvas-empty').hidden=false;$('#dimensions').textContent='— × — px';$('#object-count').textContent='0 个对象';document.title='NekoPic';clearRecovery();
  }

  async function pasteImage(){
    try{const items=await navigator.clipboard.read();for(const item of items){const type=item.types.find(t=>t.startsWith('image/'));if(type){openFile(new File([await item.getType(type)],'剪贴板图片.png',{type}));return;}}toast('剪贴板里没有图片');}catch{toast('浏览器未允许读取剪贴板');}
  }

  function handleAction(action){
    const actions={
      open:()=>fileInput.click(),paste:pasteImage,recent:showRecent,save:()=>state.fileHandle?showExportDialog():showExportDialog(),'save-as':showExportDialog,'copy-result':copyResult,'close-image':()=>closeImage(),undo,redo,duplicate:duplicateSelected,delete:deleteSelected,'select-all':()=>{state.selected=state.objects.map(o=>o.id);selectTool('select');},
      'rotate-left':()=>rotate(false),'rotate-right':()=>rotate(true),'flip-x':()=>flip(true),'flip-y':()=>flip(false),resize:()=>openSizeDialog('image'),'canvas-size':()=>openSizeDialog('canvas'),crop:()=>selectTool('crop'),fit:fitCanvas,actual:()=>setZoom(1),grid:()=>{state.grid=!state.grid;renderOverlay();toast(state.grid?'网格已显示':'网格已隐藏');},snap:()=>{state.snap=!state.snap;toast(state.snap?'中心吸附已开启':'中心吸附已关闭');},theme:toggleTheme,shortcuts:()=>showInfo('shortcuts'),about:()=>showInfo('about'),'zoom-out':()=>setZoom(state.zoom-.1),'zoom-in':()=>setZoom(state.zoom+.1),'reset-panel':resetCurrentPanel
    };actions[action]?.();closeMenus();
  }

  function toggleTheme(){const html=document.documentElement;html.dataset.theme=html.dataset.theme==='light'?'dark':'light';localStorage.setItem('nekopic-theme',html.dataset.theme);}
  function closeMenus(){ $$('.dropdown').forEach(d=>d.hidden=true); $$('.menu-trigger').forEach(b=>b.setAttribute('aria-expanded','false')); }

  function handlePanelClick(event){
    const target=event.target.closest('button');if(!target)return;
    if(target.dataset.preset){state.preset=target.dataset.preset;commit(`已应用${presets[state.preset].label}滤镜`);renderAll();renderInspector();}
    if(target.dataset.shape){state.shape=target.dataset.shape;renderInspector();}
    if(target.dataset.mosaicMode){state.mosaicMode=target.dataset.mosaicMode;renderInspector();}
    if(target.dataset.swatch)setColor(target.dataset.swatch);
    if(target.dataset.align)updateTextProperty('align',target.dataset.align);
    if(target.dataset.objectId){state.selected=event.shiftKey?[...new Set([...state.selected,target.dataset.objectId])]:[target.dataset.objectId];renderOverlay();renderInspector();}
    if(target.dataset.objectAction?.startsWith('align-'))alignSelected(target.dataset.objectAction.replace('align-',''));
    if(target.dataset.objectAction==='front')layerSelected(true);if(target.dataset.objectAction==='back')layerSelected(false);
    if(target.dataset.panelAction==='auto'){Object.assign(state.adjustments,{exposure:6,contrast:8,highlights:-12,shadows:15,saturation:7,temperature:3});commit('已自动优化');renderAll();renderInspector();}
    if(target.dataset.panelAction==='apply-crop')applyCrop();if(target.dataset.panelAction==='clear-crop'){state.cropRect=null;renderOverlay();renderInspector();}
  }

  function keyboard(event){
    const typing=['INPUT','TEXTAREA','SELECT'].includes(event.target.tagName);if(typing&&event.key!=='Escape')return;
    const mod=event.ctrlKey||event.metaKey,key=event.key.toLowerCase();
    if(mod&&key==='o'){event.preventDefault();fileInput.click();}else if(mod&&key==='s'){event.preventDefault();showExportDialog();}else if(mod&&key==='z'){event.preventDefault();event.shiftKey?redo():undo();}else if(mod&&key==='0'){event.preventDefault();fitCanvas();}else if(mod&&key==='1'){event.preventDefault();setZoom(1);}else if(mod&&key==='a'){event.preventDefault();state.selected=state.objects.map(o=>o.id);selectTool('select');}else if(mod&&key==='d'){event.preventDefault();duplicateSelected();}else if(event.key==='Delete')deleteSelected();
    else if(!mod&&['v','h','a','f','b','t','c','i'].includes(key))selectTool({v:'select',h:'hand',a:'adjust',f:'filters',b:'brush',t:'text',c:'crop',i:'eyedropper'}[key]);
    else if(key===' '){state.space=true;overlayCanvas.style.cursor='grab';event.preventDefault();}else if(key==='m'&&!event.repeat)compare(true);else if(key==='?' )showInfo('shortcuts');else if(event.key==='Escape'){$$('dialog[open]').forEach(d=>d.close());closeMenus();state.cropRect=null;renderOverlay();}
  }

  function keyup(event){if(event.key===' '){state.space=false;overlayCanvas.style.cursor=state.tool==='hand'?'grab':state.tool==='select'?'default':'crosshair';}if(event.key.toLowerCase()==='m')compare(false);}

  function scheduleRecovery(){clearTimeout(state.recoveryTimer);$('#recovery-status').textContent='正在准备自动恢复…';state.recoveryTimer=setTimeout(saveRecovery,900);}
  async function recoveryDb(){return new Promise((resolve,reject)=>{const request=indexedDB.open('nekopic-recovery',1);request.onupgradeneeded=()=>request.result.createObjectStore('drafts');request.onsuccess=()=>resolve(request.result);request.onerror=()=>reject(request.error);});}
  async function saveRecovery(){
    if(!state.hasImage||state.rev===state.savedRev)return;
    try{const blob=await new Promise(resolve=>state.base.toBlob(resolve,'image/png'));const db=await recoveryDb();const tx=db.transaction('drafts','readwrite');tx.objectStore('drafts').put({blob,name:state.name,mime:state.mime,objects:clone(state.objects),adjustments:clone(state.adjustments),preset:state.preset,presetStrength:state.presetStrength,rev:state.rev,savedRev:state.savedRev,time:Date.now()},'latest');await new Promise((resolve,reject)=>{tx.oncomplete=resolve;tx.onerror=()=>reject(tx.error);});db.close();$('#recovery-status').textContent='已写入临时恢复';}
    catch{$('#recovery-status').textContent='自动恢复不可用';}
  }
  async function readRecovery(){try{const db=await recoveryDb();const tx=db.transaction('drafts');const request=tx.objectStore('drafts').get('latest');const result=await new Promise((resolve,reject)=>{request.onsuccess=()=>resolve(request.result);request.onerror=()=>reject(request.error);});db.close();return result;}catch{return null;}}
  async function clearRecovery(){try{const db=await recoveryDb();const tx=db.transaction('drafts','readwrite');tx.objectStore('drafts').delete('latest');db.close();$('#recovery-status').textContent='自动恢复待命';}catch{}}

  function wireEvents(){
    document.addEventListener('click',event=>{const action=event.target.closest('[data-action]')?.dataset.action;if(action)handleAction(action);const close=event.target.closest('[data-close]')?.dataset.close;if(close)$('#'+close).close();});
    $$('[data-tool]').forEach(button=>button.addEventListener('click',()=>selectTool(button.dataset.tool)));
    $$('.menu-trigger').forEach(button=>button.addEventListener('click',event=>{event.stopPropagation();const dropdown=button.nextElementSibling,willOpen=dropdown.hidden;closeMenus();dropdown.hidden=!willOpen;button.setAttribute('aria-expanded',String(willOpen));}));
    document.addEventListener('click',event=>{if(!event.target.closest('.menu-host'))closeMenus();});
    inspector.addEventListener('click',handlePanelClick);
    overlayCanvas.addEventListener('pointerdown',pointerDown);overlayCanvas.addEventListener('pointermove',pointerMove);overlayCanvas.addEventListener('pointerup',pointerUp);overlayCanvas.addEventListener('pointercancel',pointerUp);overlayCanvas.addEventListener('pointerleave',()=>{if(state.tool==='eyedropper')$('#loupe').hidden=true;});
    viewport.addEventListener('wheel',event=>{event.preventDefault();setZoom(state.zoom*(event.deltaY>0?.9:1.1),event.clientX,event.clientY);},{passive:false});
    viewport.addEventListener('dblclick',fitCanvas);
    $('#zoom-range').addEventListener('input',event=>setZoom(Number(event.target.value)/100));
    fileInput.addEventListener('change',()=>{openFile(fileInput.files[0]);fileInput.value='';});
    $('#rail-color').addEventListener('click',()=>$('#global-color').click());$('#global-color').addEventListener('input',event=>setColor(event.target.value));
    $('#compare-button').addEventListener('pointerdown',()=>compare(true));$('#compare-button').addEventListener('pointerup',()=>compare(false));$('#compare-button').addEventListener('pointerleave',()=>compare(false));
    document.addEventListener('keydown',keyboard);document.addEventListener('keyup',keyup);window.addEventListener('resize',()=>state.fitView?fitCanvas():updateStage());window.addEventListener('beforeunload',event=>{if(state.rev!==state.savedRev){event.preventDefault();event.returnValue='';}});
    ['dragenter','dragover'].forEach(type=>viewport.addEventListener(type,event=>{event.preventDefault();$('#drop-overlay').hidden=false;}));
    ['dragleave','drop'].forEach(type=>viewport.addEventListener(type,event=>{event.preventDefault();$('#drop-overlay').hidden=true;if(type==='drop')openFile(event.dataTransfer.files[0]);}));
    $$('.format-options button').forEach(button=>button.addEventListener('click',()=>{state.currentExport=button.dataset.format;updateExportControls();}));
    $('#export-quality').addEventListener('input',event=>$('#quality-label').textContent=`${event.target.value}%`);$('#export-confirm').addEventListener('click',exportImage);
    $('#size-width').addEventListener('input',event=>{if($('#size-dialog').dataset.mode==='image'&&$('#size-aspect').checked)$('#size-height').value=Math.round(Number(event.target.value)*state.base.height/state.base.width);});
    $('#size-height').addEventListener('input',event=>{if($('#size-dialog').dataset.mode==='image'&&$('#size-aspect').checked)$('#size-width').value=Math.round(Number(event.target.value)*state.base.width/state.base.height);});
    $('#anchor-grid').addEventListener('click',event=>{const button=event.target.closest('[data-anchor]');if(button){state.anchor=button.dataset.anchor;buildAnchorGrid();}});
    $('#size-confirm').addEventListener('click',()=>{const w=Number($('#size-width').value),h=Number($('#size-height').value);if(!validSize(w,h))return toast('尺寸必须在 8192 px 单边与 3200 万像素以内');if($('#size-dialog').dataset.mode==='image')resizeImage(w,h);else resizeCanvas(w,h,state.anchor,$('#canvas-transparent').checked,$('#canvas-background').value);$('#size-dialog').close();});
    $('#confirm-cancel').addEventListener('click',()=>$('#confirm-dialog').close());$('#confirm-discard').addEventListener('click',()=>{$('#confirm-dialog').close();state.savedRev=state.rev;closeImage(true);});$('#confirm-save').addEventListener('click',()=>{$('#confirm-dialog').close();showExportDialog();});
    $('#recovery-discard').addEventListener('click',()=>{$('#recovery-dialog').close();clearRecovery();});
  }

  async function init(){
    state.recent=JSON.parse(localStorage.getItem('nekopic-recent')||'[]');document.documentElement.dataset.theme=localStorage.getItem('nekopic-theme')||'dark';
    wireEvents();setColor(state.color);await loadImageSource('assets/demo.jpg',state.name,state.mime);
    const recovery=await readRecovery();
    if(recovery){$('#recovery-dialog').dataset.available='true';$('#recovery-dialog').showModal();$('#recovery-restore').onclick=()=>{$('#recovery-dialog').close();loadImageSource(recovery.blob,recovery.name,recovery.mime,recovery);};}
  }

  init();
})();
