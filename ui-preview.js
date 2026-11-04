/* UI review controls. Additional settings here describe interaction, not image processing. */
(() => {
  'use strict';
  const $ = selector => document.querySelector(selector);
  const panel = $('#inspector-content');
  const values = { mask: 'brush', effect: 'mosaic', hardness: 80, brushSize: 48, strength: 18, cropRatio: 'free', fill: 'transparent', border: 'white', borderSize: 32, brushTip: 'round', smoothing: 30, spacing: 10, pressure: true, lineHeight: 1.4, tracking: 0, sample: 'merged', sampleSize: 'point', straight: 0, photoWidth: 1800, photoHeight: 1200, filterCategory: '全部' };
  let currentTool = 'adjust';
  const svg = name => `<svg aria-hidden="true"><use href="#i-${name}"/></svg>`;
  const titles = { select: '选择', hand: '平移', adjust: '调色', filters: '滤镜', brush: '画笔', text: '文字', shape: '形状', mosaic: '打码', crop: '裁剪', eyedropper: '取色', transform: '旋转与翻转', canvas: '画布与留白', border: '边框', history: '历史记录' };
  const section = (title, content, open = true) => `<details class="settings-section" ${open ? 'open' : ''}><summary>${title}</summary><div class="settings-body">${content}</div></details>`;
  const choice = (key, items, label) => `<div class="choice-grid" role="group" aria-label="${label}">${items.map(([value, text, ico]) => `<button type="button" data-ui-choice="${key}" data-value="${value}" aria-pressed="${String(values[key] === value)}" class="choice ${values[key] === value ? 'selected' : ''}">${ico ? svg(ico) : ''}<span>${text}</span></button>`).join('')}</div>`;
  const range = (key, text, min, max, unit = '') => `<label class="ui-range-label">${text}<output data-ui-output="${key}">${values[key]}${unit}</output><input type="range" data-ui-range="${key}" min="${min}" max="${max}" step="${key === 'lineHeight' ? '.1' : '1'}" value="${values[key]}" aria-label="${text}" data-unit="${unit}" style="--fill:${(values[key] - min) / (max - min) * 100}%"></label>`;
  const check = (key, text) => `<label class="checkbox-line"><input type="checkbox" data-ui-check="${key}" ${values[key] ? 'checked' : ''}>${text}</label>`;
  const action = (name, text, ico = '') => `<button class="secondary-button ui-action" data-action="${name}">${ico ? svg(ico) : ''}${text}</button>`;
  const modeHint = text => `<p class="mode-hint">${text}</p>`;

  const context = document.createElement('div');
  context.className = 'tool-context';
  context.setAttribute('aria-label', '当前工具与快捷操作');
  $('#viewport').before(context);
  const badge = document.createElement('span');
  badge.className = 'mask-preview-badge'; badge.textContent = '画笔遮罩 · 交互预览'; badge.hidden = true;
  $('#viewport').append(badge);
  const cursor = document.createElement('div');cursor.className = 'brush-cursor';cursor.hidden = true;$('#viewport').append(cursor);
  const maskCanvas = document.createElement('canvas');maskCanvas.className = 'mask-preview-canvas';maskCanvas.setAttribute('aria-label', '画笔遮罩预览');$('#canvas-stage').append(maskCanvas);
  let painting = false;
  let spaceHeld = false;

  function syncContext() {
    let quick = '';
    if (currentTool === 'mosaic') quick = choice('mask', [['brush','画笔','brush'],['rect','矩形','rect']], '遮罩方式');
    else if (currentTool === 'crop') quick = choice('cropRatio', [['free','自由'],['original','原比例'],['1:1','1:1'],['4:3','4:3'],['16:9','16:9']], '裁剪比例');
    else if (currentTool === 'text') quick = '<span class="context-help">点击放置文字 · 在右侧编辑内容与排版</span>';
    else if (currentTool === 'shape') quick = '<span class="context-help">右侧选择形状 · Shift 约束比例或角度</span>';
    else if (currentTool === 'select') quick = '<span class="context-help">点击选择 · Shift 多选 · 拖动移动</span>';
    else quick = '<span class="context-help">滚轮缩放 · 空格拖动平移</span>';
    context.innerHTML = `<strong>${titles[currentTool] || '工具'}</strong><span class="context-divider"></span>${quick}<button class="context-more" data-open-search title="查找功能">${svg('plus')}更多工具</button>`;
    badge.hidden = currentTool !== 'mosaic' || values.mask !== 'brush';
    maskCanvas.hidden = badge.hidden;
    if (currentTool === 'mosaic') $('#tool-hint').textContent = values.mask === 'brush' ? '拖动涂抹遮罩 · 空格平移 · 滚轮缩放' : '拖出矩形选区 · 空格平移 · 滚轮缩放';
    if (badge.hidden) cursor.hidden = true;
  }

  function decorate(tool) {
    currentTool = tool;
    panel.querySelectorAll('[data-ui-extra]').forEach(el => el.remove());
    $('#panel-title').textContent = titles[tool] || '工具';
    if (tool === 'mosaic') {
      $('#panel-eyebrow').textContent = 'REDACT';
      $('#inspector-note').textContent = '画笔显示遮罩范围；新增参数当前用于 UI 交互预览。';
      panel.innerHTML = `<div class="panel-step"><span>1</span>选择涂抹方式</div>${choice('mask', [['brush','画笔涂抹','brush'],['rect','矩形选区','rect']], '遮罩方式')}<div class="panel-step"><span>2</span>选择遮挡效果</div>${choice('effect', [['mosaic','马赛克','mosaic'],['blur','模糊','filter']], '遮挡效果')}<div class="brush-size-preview"><i style="width:${Math.min(64,values.brushSize)}px;height:${Math.min(64,values.brushSize)}px"></i><span>${values.mask === 'brush' ? '拖动画笔覆盖需要遮挡的位置' : '拖出矩形覆盖需要遮挡的区域'}</span></div>${values.mask === 'brush' ? range('brushSize','画笔大小',8,160,' px') + range('hardness','边缘硬度',0,100,'%') : ''}${range('strength',values.effect === 'mosaic' ? '马赛克块大小' : '模糊强度',4,48,' px')}<button class="secondary-button wide-button" data-clear-mask>清除遮罩预览</button>${modeHint('先选覆盖范围，再调遮挡效果。画笔遮罩为交互演示。')}`;
    } else if (tool === 'canvas') {
      $('#panel-eyebrow').textContent = 'CANVAS & SPACE';
      $('#inspector-note').textContent = '画布扩展增加空间，图片尺寸调整缩放整张图片。';
      panel.innerHTML = `<p class="panel-intro">加白边、为文字留位置，或改变整张图片的尺寸。</p>${section('画布扩展', `<div class="space-preview"><div>原图</div></div>${choice('fill',[['transparent','透明'],['white','白色'],['custom','自定义']],'扩展背景')}${action('canvas-size','设置画布尺寸…','fit')}`)}${section('图片尺寸', `<p class="muted-text">按比例缩放底图与绘制对象。</p>${action('resize','修改图片尺寸…','shape')}`)}${section('常用画布比例',choice('cropRatio',[['1:1','方形 1:1'],['4:3','横图 4:3'],['3:4','竖图 3:4'],['16:9','横屏 16:9']],'画布比例'),false)}`;
    } else if (tool === 'transform') {
      $('#panel-eyebrow').textContent = 'TRANSFORM';$('#inspector-note').textContent = '旋转与翻转操作针对整张画面及对象；拉直参数为交互预览。';
      panel.innerHTML = `${section('旋转',`<div class="ui-action-grid">${action('rotate-left','向左 90°','rotate')}${action('rotate-right','向右 90°','redo')}</div>`)}${section('翻转',`<div class="ui-action-grid">${action('flip-x','水平翻转','arrow')}${action('flip-y','垂直翻转','arrow')}</div>`)}${section('拉直',`${range('straight','旋转角度',-45,45,'°')}<button class="secondary-button wide-button" data-zero-straight>归零</button>`)}${action('crop','转到裁剪','crop')}`;
    } else if (tool === 'border') {
      $('#panel-eyebrow').textContent = 'FRAME & MARGIN';$('#inspector-note').textContent = '边框样式与尺寸为交互预览，实际输出待后续接入。';
      panel.innerHTML = `<div class="frame-preview ${values.border}"><img src="assets/demo.jpg" alt="边框样式预览"></div>${choice('border',[['white','白色留白'],['dark','深色边框'],['polaroid','拍立得'],['none','无边框']],'边框样式')}${range('borderSize','边框宽度',0,120,' px')}${section('边距设置',check('borderEqual','四边相同')+range('bottomMargin','底部留白',0,180,' px'),false)}${modeHint('预览边框的视觉比例；也可通过“画布”精确增加留白。')}${action('canvas-size','设置精确留白…','fit')}`;
    } else if (tool === 'history') {
      $('#panel-eyebrow').textContent = 'EDIT HISTORY';$('#inspector-note').textContent = '一步对应一次操作；历史记录只在当前编辑窗口中保留。';
      panel.innerHTML = `<div class="ui-action-grid">${action('undo','撤销','undo')}${action('redo','重做','redo')}</div><div class="history-entry"><span class="history-point"></span><div>打开图片<small>${$('#tab-name').textContent}</small></div><span class="history-current">起点</span></div><p class="muted-text">编辑后可通过顶部撤销、重做返回相邻状态。完整历史列表将在编辑逻辑确定后接入。</p>${section('操作规则','<p class="muted-text">一笔绘制 = 一步<br>一次滑杆拖动 = 一步<br>一段文字编辑 = 一步<br>保存后继续保留当前对象</p>',false)}`;
    } else {
      const extra = document.createElement('div');extra.dataset.uiExtra = '';
      if (tool === 'brush') extra.innerHTML = section('笔刷细节',choice('brushTip',[['round','圆头'],['square','方头']],'笔头')+range('hardness','硬度',0,100,'%')+range('spacing','间距',1,60,'%')+range('smoothing','防抖',0,100,'%')+check('pressure','使用触控笔压感')+modeHint('笔刷细节为参数交互预览。'),false);
      if (tool === 'text') extra.innerHTML = section('排版细节',range('lineHeight','行距',1,2.5)+range('tracking','字间距',-5,30,' px')+check('textBold','粗体')+check('textShadow','投影')+modeHint('行距、字距与投影为交互预览。'),false);
      if (tool === 'shape') extra.innerHTML = section('线条与填充',choice('lineStyle',[['solid','实线'],['dash','虚线']],'线条样式')+choice('shapeFill',[['none','无填充'],['solid','纯色'],['soft','半透明']],'填充方式')+range('corners','圆角',0,80,' px')+modeHint('附加样式为交互预览。'),false);
      if (tool === 'crop') {extra.innerHTML = section('裁剪比例',choice('cropRatio',[['free','自由'],['original','原比例'],['1:1','1:1'],['4:3','4:3'],['3:4','3:4'],['16:9','16:9']],'裁剪比例')+check('cropThirds','显示三分线')+modeHint('比例选择为交互预览；可在画布上拖出自由选区。'));panel.prepend(extra);}
      if (tool === 'eyedropper') extra.innerHTML = section('采样设置',choice('sample',[['merged','合成画面'],['photo','仅照片']],'采样来源')+choice('sampleSize',[['point','单个像素'],['average','区域平均']],'采样范围')+modeHint('采样选项为交互预览。'));
      // Color controls are organized by color-ui.js after this decorator runs.
      if (tool !== 'crop' && extra.innerHTML) panel.append(extra);
      if (tool === 'filters') {
        panel.querySelectorAll('[data-preset] img').forEach(img => {img.className = `look-${img.closest('button').dataset.preset}`;});
      }
    }
    syncContext();
    // Extra settings stay in UI state only, outside the editor undo stack.
    panel.querySelectorAll('[data-ui-range]').forEach(input => {if(values[input.dataset.uiRange] == null){values[input.dataset.uiRange] = Number(input.value) || 0;}});
  }

  Object.assign(values,{bottomMargin:64,borderEqual:true,textBold:false,textShadow:false,lineStyle:'solid',shapeFill:'none',corners:0,cropThirds:true,vibrance:0,tint:0,clarity:0,vignette:0});
  document.addEventListener('nekopic:panel',event=>decorate(event.detail.tool));
  document.addEventListener('click',event=>{
    const choiceButton=event.target.closest('[data-ui-choice]');
    if(choiceButton){values[choiceButton.dataset.uiChoice]=choiceButton.dataset.value;decorate(currentTool);}
    if(event.target.closest('[data-zero-straight]')){values.straight=0;decorate(currentTool);}
    if(event.target.closest('[data-clear-mask]')) maskCanvas.getContext('2d').clearRect(0,0,maskCanvas.width,maskCanvas.height);
    if(event.target.closest('[data-open-search]'))openSearch();
  });
  document.addEventListener('input',event=>{
    const input=event.target;
    if(input.dataset.uiRange){const key=input.dataset.uiRange;values[key]=Number(input.value);document.querySelectorAll(`[data-ui-output="${key}"]`).forEach(output=>output.textContent=input.value+(input.dataset.unit||''));input.style.setProperty('--fill',`${(input.value-input.min)/(input.max-input.min)*100}%`);if(key==='brushSize'){const dot=panel.querySelector('.brush-size-preview i');if(dot){dot.style.width=`${Math.min(64,input.value)}px`;dot.style.height=dot.style.width;}}if(key==='borderSize'){const frame=panel.querySelector('.frame-preview');if(frame)frame.style.padding=`${8+Number(input.value)/3}px`;}}
    if(input.dataset.uiCheck)values[input.dataset.uiCheck]=input.checked;
  });

  // A separate translucent mask makes the brush gesture reviewable without implementing redaction.
  const overlay=$('#overlay-canvas');
  function brushMode(){return currentTool==='mosaic'&&values.mask==='brush'&&!spaceHeld;}
  function maskPoint(event){const r=overlay.getBoundingClientRect();return {x:(event.clientX-r.left)*overlay.width/r.width,y:(event.clientY-r.top)*overlay.height/r.height};}
  overlay.addEventListener('pointerdown',event=>{if(!brushMode()||event.button!==0||event.ctrlKey)return;event.stopImmediatePropagation();event.preventDefault();if(maskCanvas.width!==overlay.width||maskCanvas.height!==overlay.height){maskCanvas.width=overlay.width;maskCanvas.height=overlay.height;}painting=true;overlay.setPointerCapture(event.pointerId);const ctx=maskCanvas.getContext('2d'),p=maskPoint(event);ctx.strokeStyle='#edbc9d88';ctx.fillStyle='#edbc9d88';ctx.lineWidth=values.brushSize;ctx.lineCap='round';ctx.lineJoin='round';ctx.beginPath();ctx.moveTo(p.x,p.y);ctx.lineTo(p.x+.01,p.y+.01);ctx.stroke();},true);
  overlay.addEventListener('pointermove',event=>{if(!brushMode())return;const r=$('#viewport').getBoundingClientRect(),scale=overlay.getBoundingClientRect().width/overlay.width;cursor.hidden=false;cursor.style.left=`${event.clientX-r.left}px`;cursor.style.top=`${event.clientY-r.top}px`;cursor.style.width=`${values.brushSize*scale}px`;cursor.style.height=cursor.style.width;if(!painting)return;event.stopImmediatePropagation();const p=maskPoint(event),ctx=maskCanvas.getContext('2d');ctx.lineTo(p.x,p.y);ctx.stroke();ctx.beginPath();ctx.moveTo(p.x,p.y);},true);
  for(const type of ['pointerup','pointercancel'])overlay.addEventListener(type,event=>{if(!painting)return;event.stopImmediatePropagation();painting=false;if(overlay.hasPointerCapture(event.pointerId))overlay.releasePointerCapture(event.pointerId);},true);
  overlay.addEventListener('pointerleave',()=>cursor.hidden=true);

  const search=document.createElement('dialog');search.className='command-dialog';search.id='command-dialog';
  search.innerHTML='<div class="search-input-row">'+svg('select')+'<input id="function-search" placeholder="搜索功能，例如：马赛克、留白、文字…" aria-label="搜索功能"><button data-search-close title="关闭搜索">Esc</button></div><div id="search-results" class="search-results"></div><div class="search-footer">↑ ↓ 选择<span>Enter 打开</span></div>';
  document.body.append(search);
  const commands=[...Object.entries(titles).map(([id,title])=>({id,title,kind:'tool',description:{adjust:'白平衡 · HSL · 曲线 · 色彩分级 · 去雾 · 降噪 · 暗角',filters:'风格预设 · 自然 · 胶片 · 人像 · 黑白 · 收藏 · 强度',mosaic:'画笔涂抹 / 矩形选区 · 马赛克 / 模糊',canvas:'画布扩展 · 留白 · 图片尺寸',text:'多行文字 · 字体 · 描边与排版',crop:'自由裁剪 · 常用比例',border:'白边 · 深色 · 拍立得'}[id]||'打开工具设置'})),...Object.entries({'save-as':'另存为 / 导出','resize':'修改图片尺寸','canvas-size':'修改画布尺寸','copy-result':'复制结果到剪贴板','fit':'适应窗口','actual':'100% 实际大小','theme':'切换深浅主题','shortcuts':'快捷键一览','open':'打开图片'}).map(([id,title])=>({id,title,kind:'action',description:'桌面常用操作'}))];
  let resultIndex=0,filtered=[];
  function renderResults(){const query=$('#function-search').value.trim().toLowerCase();filtered=commands.filter(c=>(c.title+c.description).toLowerCase().includes(query));resultIndex=Math.min(resultIndex,Math.max(0,filtered.length-1));$('#search-results').innerHTML=filtered.map((c,index)=>`<button class="search-result ${index===resultIndex?'selected':''}" data-search-index="${index}"><span>${svg(c.kind==='tool'?'adjust':'arrow')}</span><div>${c.title}<small>${c.description}</small></div><kbd>↵</kbd></button>`).join('')||'<p class="panel-intro search-empty">没有找到这个功能，试试“画布”或“文字”。</p>';}
  function openSearch(){resultIndex=0;$('#function-search').value='';renderResults();search.showModal();$('#function-search').focus();}
  function chooseCommand(index){const command=filtered[index];if(!command)return;search.close();const button=document.querySelector(command.kind==='tool'?`[data-tool="${command.id}"]`:`[data-action="${command.id}"]`);button?.click();}
  $('#command-search').addEventListener('click',openSearch);$('#function-search').addEventListener('input',()=>{resultIndex=0;renderResults();});
  search.addEventListener('click',event=>{if(event.target.closest('[data-search-close]'))search.close();const button=event.target.closest('[data-search-index]');if(button)chooseCommand(Number(button.dataset.searchIndex));});
  search.addEventListener('keydown',event=>{if(event.key==='ArrowDown'||event.key==='ArrowUp'){event.preventDefault();resultIndex=(resultIndex+(event.key==='ArrowDown'?1:-1)+filtered.length)%Math.max(1,filtered.length);renderResults();$('#search-results .selected')?.scrollIntoView({block:'nearest'});}if(event.key==='Enter'){event.preventDefault();chooseCommand(resultIndex);}});
  document.addEventListener('keydown',event=>{if((event.ctrlKey||event.metaKey)&&event.key.toLowerCase()==='k'){event.preventDefault();if(!search.open)openSearch();}},true);
  document.addEventListener('keydown',event=>{if(event.code==='Space'&&!['INPUT','TEXTAREA','SELECT'].includes(event.target.tagName)){spaceHeld=true;cursor.hidden=true;}},true);
  document.addEventListener('keyup',event=>{if(event.code==='Space')spaceHeld=false;},true);
  window.addEventListener('blur',()=>{spaceHeld=false;painting=false;cursor.hidden=true;});
  decorate(document.querySelector('[data-tool].active')?.dataset.tool||'adjust');
})();
