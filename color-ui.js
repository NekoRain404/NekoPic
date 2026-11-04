/* Color workspace: advanced controls are intentionally UI-only at this stage. */
(() => {
  'use strict';
  const panel = document.querySelector('#inspector-content');
  const tabs = { basic: '基础', hsl: 'HSL', curves: '曲线', grade: '色彩分级', detail: '细节 / 效果' };
  const channels = [['red','红','#e56e62'],['orange','橙','#e8a366'],['yellow','黄','#ddcf69'],['green','绿','#82b883'],['aqua','青','#72c8bd'],['blue','蓝','#73a5da'],['purple','紫','#ad8bd7'],['magenta','洋红','#d88eb9']];
  const defaults = { whites:0, blacks:0, tint:0, vibrance:0, texture:0, clarity:0, dehaze:0, sharpen:0, noise:0, colorNoise:0, vignette:0, feather:50, grain:0, fade:0, balance:0, blending:50 };
  let values = {...defaults}, activeTab = 'basic', hslChannel = 'red', curveChannel = 'RGB', gradeZone = 'shadows';
  const hsl = Object.fromEntries(channels.map(([id]) => [id,{hue:0,saturation:0,luminance:0}]));
  const grade = {shadows:{hue:220,saturation:0,luminance:0},midtones:{hue:35,saturation:0,luminance:0},highlights:{hue:45,saturation:0,luminance:0}};
  const curves = Object.fromEntries(['RGB','R','G','B'].map(id => [id,[0,25,50,75,100]]));
  const expanded = { light:true, wb:true, color:true, detail:true, noise:false, effect:true };
  let category = '全部', query = '', favorites = new Set(['warm','film']), tool = 'adjust';
  const filterInfo = {
    none:['原图','none'], fresh:['自然','brightness(1.06) contrast(1.07) saturate(1.12)'], vivid:['自然','contrast(1.17) saturate(1.28)'],
    warm:['自然','sepia(.2) saturate(1.15)'], cool:['自然','sepia(.12) hue-rotate(160deg) saturate(.9)'],
    film:['胶片','sepia(.22) contrast(1.18) saturate(.85)'], faded:['胶片','brightness(1.1) contrast(.82) saturate(.76)'], vintage:['胶片','sepia(.5) contrast(.9) saturate(.7)'],
    sunset:['氛围','sepia(.4) saturate(1.3)'], soft:['人像','brightness(1.1) contrast(.86) saturate(.92)'], cream:['人像','sepia(.2) brightness(1.08) contrast(.9)'],
    mono:['黑白','grayscale(1) contrast(1.12)'], silver:['黑白','grayscale(1) contrast(1.28)']
  };
  const esc = s => String(s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const range = (key,label,min=-100,max=100,value=values[key],scope='value') => `<label class="color-range">${label}<output>${value}</output><input type="range" data-color-range="${key}" data-scope="${scope}" aria-label="${label}" min="${min}" max="${max}" value="${value}" style="--fill:${(value-min)/(max-min)*100}%" title="双击恢复默认值"></label>`;
  const section = (id,label,content) => `<details class="settings-section" data-color-section="${id}" ${expanded[id]?'open':''}><summary>${label}</summary><div class="settings-body">${content}</div></details>`;
  const choices = (key,items,selected) => `<div class="color-choices" role="group">${items.map(([id,label])=>`<button data-color-choice="${key}" data-value="${id}" aria-pressed="${id===selected}" class="${id===selected?'selected':''}">${label}</button>`).join('')}</div>`;
  const slot = key => `<div data-native-slot="${key}"></div>`;
  function renderAdjust() {
    // Move bound controls instead of cloning them: existing rendering/undo listeners survive.
    const native = [...panel.querySelectorAll('.slider-field')];
    const auto = panel.querySelector('[data-panel-action="auto"]');
    panel.innerHTML = `<div class="color-tabs" role="tablist" aria-label="调色分组">${Object.entries(tabs).map(([id,label])=>`<button role="tab" id="color-tab-${id}" aria-controls="color-page-${id}" aria-selected="${id===activeTab}" tabindex="${id===activeTab?0:-1}" data-color-tab="${id}">${label}</button>`).join('')}</div><div class="color-tab-content"></div>`;
    const body = panel.querySelector('.color-tab-content');
    body.innerHTML = `
      <div data-color-page="basic" id="color-page-basic" role="tabpanel" aria-labelledby="color-tab-basic">
        <div data-native-auto></div>
        ${section('light','明暗',slot('exposure')+slot('contrast')+slot('highlights')+slot('shadows')+range('whites','白色色阶')+range('blacks','黑色色阶'))}
        ${section('wb','白平衡',slot('temperature')+range('tint','色调 · 绿 — 洋红'))}
        ${section('color','色彩',slot('saturation')+range('vibrance','自然饱和度'))}
      </div>
      <div data-color-page="hsl" id="color-page-hsl" role="tabpanel" aria-labelledby="color-tab-hsl"><p class="color-intro">只调整一种颜色，保留其他颜色。</p><div class="hsl-channels" role="group" aria-label="HSL 颜色通道">${channels.map(([id,label,color])=>`<button data-color-choice="hsl" data-value="${id}" style="--channel:${color}" title="${label}" aria-label="${label}" aria-pressed="${id===hslChannel}"></button>`).join('')}</div><div id="hsl-controls"></div><button class="secondary-button wide-button" data-color-reset="hsl">重置当前颜色</button></div>
      <div data-color-page="curves" id="color-page-curves" role="tabpanel" aria-labelledby="color-tab-curves"><p class="color-intro">拖动控制点调整明暗关系。</p>${choices('curve',['RGB','R','G','B'].map(x=>[x,x]),curveChannel)}<div class="curve-chart"><svg viewBox="0 0 240 240" aria-label="色调曲线交互预览"><path class="curve-grid" d="M0 60H240M0 120H240M0 180H240M60 0V240M120 0V240M180 0V240"/><path class="curve-diagonal" d="M0 240L240 0"/><polyline id="curve-line"/><g id="curve-points"></g></svg></div><div class="curve-axis"><span>暗部</span><span>输入亮度 →</span><span>亮部</span></div><div class="color-choices"><button data-curve-preset="linear">线性</button><button data-curve-preset="contrast">柔和 S 曲线</button><button data-curve-preset="fade">抬起暗部</button></div><div id="curve-accessible"></div></div>
      <div data-color-page="grade" id="color-page-grade" role="tabpanel" aria-labelledby="color-tab-grade"><p class="color-intro">分别为阴影、中间调和高光加入色彩。</p>${choices('grade',[['shadows','阴影'],['midtones','中间调'],['highlights','高光']],gradeZone)}<div class="grading-orbit"><i></i><span>色彩预览</span></div><div id="grade-controls"></div>${range('blending','混合范围',0,100)}${range('balance','明暗平衡')}<button class="secondary-button wide-button" data-color-reset="grade">重置当前区域</button></div>
      <div data-color-page="detail" id="color-page-detail" role="tabpanel" aria-labelledby="color-tab-detail">${section('detail','质感与细节',range('texture','纹理')+range('clarity','清晰度')+range('dehaze','去雾')+range('sharpen','锐化',0,100))}${section('noise','降噪',range('noise','明度降噪',0,100)+range('colorNoise','彩色降噪',0,100))}${section('effect','效果',range('vignette','暗角',-100,100)+range('feather','暗角羽化',0,100)+range('grain','颗粒',0,100)+range('fade','褪色',0,100))}</div>`;
    native.forEach(node => body.querySelector(`[data-native-slot="${node.querySelector('input').dataset.adjust}"]`)?.replaceWith(node));
    if(auto) body.querySelector('[data-native-auto]').replaceWith(auto);
    body.querySelectorAll('[data-color-section]').forEach(el=>el.addEventListener('toggle',()=>expanded[el.dataset.colorSection]=el.open));
    showTab(); updateHsl(); updateGrade(); updateCurve();
    document.querySelector('#inspector-note').textContent = '高级调色为交互预览，暂不写入图片；已有基础调色保留演示效果。';
  }
  function showTab() {
    panel.querySelectorAll('[data-color-tab]').forEach(b=>{b.setAttribute('aria-selected',b.dataset.colorTab===activeTab);b.tabIndex=b.dataset.colorTab===activeTab?0:-1;});
    panel.querySelectorAll('[data-color-page]').forEach(p=>p.hidden=p.dataset.colorPage!==activeTab);
  }
  function updateHsl() {
    const label = channels.find(c=>c[0]===hslChannel)[1];
    panel.querySelector('#hsl-controls').innerHTML=`<div class="color-section-heading">${label}<small>HSL</small></div>${range('hue','色相',-100,100,hsl[hslChannel].hue,'hsl')}${range('saturation','饱和度',-100,100,hsl[hslChannel].saturation,'hsl')}${range('luminance','明亮度',-100,100,hsl[hslChannel].luminance,'hsl')}`;
  }
  function updateGrade() {
    const g=grade[gradeZone];
    panel.querySelector('#grade-controls').innerHTML=range('hue','色相',0,360,g.hue,'grade')+range('saturation','着色饱和度',0,100,g.saturation,'grade')+range('luminance','亮度',-100,100,g.luminance,'grade');
    paintGrade();
  }
  function paintGrade(){const g=grade[gradeZone];panel.querySelector('.grading-orbit i').style.background=`hsl(${g.hue} ${g.saturation}% ${50+g.luminance*.4}%)`;}
  function updateCurve() {
    const points=curves[curveChannel].map((y,i)=>`${i*60},${240-y*2.4}`).join(' ');
    panel.querySelector('#curve-line').setAttribute('points',points);
    panel.querySelector('.curve-chart').style.setProperty('--curve-color',({RGB:'var(--accent)',R:'#e7837c',G:'#8ec997',B:'#84ade1'})[curveChannel]);
    panel.querySelector('#curve-points').innerHTML=curves[curveChannel].map((y,i)=>`<circle data-curve-point="${i}" cx="${i*60}" cy="${240-y*2.4}" r="5"/>`).join('');
    panel.querySelector('#curve-accessible').innerHTML=`<details class="curve-numbers"><summary>精确调整控制点</summary>${curves[curveChannel].map((y,i)=>range(String(i),`输入 ${i*25} · 输出`,0,100,y,'curve')).join('')}</details>`;
  }
  function renderFilters() {
    const cards=[...panel.querySelectorAll('[data-preset]')];
    const strength=panel.querySelector('.slider-field');
    const selected=cards.find(c=>c.classList.contains('selected'));
    panel.innerHTML=`<div class="filter-current"><span>当前风格<strong>${esc(selected?.textContent.trim()||'原图')}</strong></span><button data-preset="none" class="secondary-button">移除滤镜</button></div><div class="filter-strength-slot"></div><input class="filter-search" type="search" aria-label="搜索滤镜" placeholder="搜索风格…" value="${esc(query)}"><div class="filter-categories" role="group" aria-label="滤镜分类">${['全部','自然','胶片','人像','氛围','黑白','收藏'].map(c=>`<button data-filter-category="${c}" aria-pressed="${category===c}">${c==='收藏'?'☆ ':''}${c}</button>`).join('')}</div><div class="filter-result-count" aria-live="polite"></div><div class="filter-grid color-filter-grid"></div><p class="filter-empty" hidden>这里还没有滤镜。试试其他分类，或点 ☆ 收藏喜欢的风格。</p><p class="mode-hint">缩略图为示例照片的风格示意。点击后在主画布查看效果；按住顶部“对比”查看原图。</p>`;
    if(strength)panel.querySelector('.filter-strength-slot').replaceWith(strength);
    const grid=panel.querySelector('.filter-grid');
    cards.forEach(card=>{
      const id=card.dataset.preset, info=filterInfo[id]||['自然','none'];
      card.querySelector('img').style.filter=info[1];card.setAttribute('aria-pressed',card.classList.contains('selected'));
      const item=document.createElement('div');item.className='filter-item';item.dataset.filterId=id;item.dataset.category=info[0];item.dataset.name=card.textContent.trim();
      item.append(card);const fav=document.createElement('button');fav.className='filter-favorite';fav.dataset.favorite=id;fav.title='收藏 '+item.dataset.name;fav.setAttribute('aria-label',fav.title);fav.setAttribute('aria-pressed',favorites.has(id));fav.textContent=favorites.has(id)?'★':'☆';if(id!=='none')item.append(fav);grid.append(item);
    });
    filterCards();document.querySelector('#inspector-note').textContent='12 款内置风格，可叠加基础调色。当前使用简化效果演示，尚未接入专业滤镜库。';
  }
  function filterCards() {
    let count=0;
    panel.querySelectorAll('.filter-item').forEach(item=>{item.hidden=!((category==='全部'||(category==='收藏'?favorites.has(item.dataset.filterId):item.dataset.category===category))&&item.dataset.name.includes(query));if(!item.hidden)count++;});
    panel.querySelector('.filter-empty').hidden=count>0;panel.querySelector('.filter-result-count').textContent=`${count} 个风格${category==='全部'?' · 含原图':''}`;
  }
  function decorate(next) {tool=next;if(tool==='adjust')renderAdjust();if(tool==='filters')renderFilters();}
  document.addEventListener('nekopic:panel',e=>decorate(e.detail.tool));
  panel.addEventListener('click',e=>{
    const b=e.target.closest('button');if(!b)return;
    if(b.dataset.colorTab){activeTab=b.dataset.colorTab;showTab();}
    if(b.dataset.colorChoice){const kind=b.dataset.colorChoice;panel.querySelectorAll(`[data-color-choice="${kind}"]`).forEach(x=>{x.setAttribute('aria-pressed',x===b);x.classList.toggle('selected',x===b);});if(kind==='hsl'){hslChannel=b.dataset.value;updateHsl();}if(kind==='curve'){curveChannel=b.dataset.value;updateCurve();}if(kind==='grade'){gradeZone=b.dataset.value;updateGrade();}}
    if(b.dataset.curvePreset){curves[curveChannel]=({linear:[0,25,50,75,100],contrast:[0,17,50,83,100],fade:[12,32,54,77,100]})[b.dataset.curvePreset];updateCurve();}
    if(b.dataset.colorReset==='hsl'){hsl[hslChannel]={hue:0,saturation:0,luminance:0};updateHsl();}
    if(b.dataset.colorReset==='grade'){grade[gradeZone]={hue:0,saturation:0,luminance:0};updateGrade();}
    if(b.dataset.filterCategory){category=b.dataset.filterCategory;panel.querySelectorAll('[data-filter-category]').forEach(x=>x.setAttribute('aria-pressed',x===b));filterCards();}
    if(b.dataset.favorite){const id=b.dataset.favorite;favorites.has(id)?favorites.delete(id):favorites.add(id);b.textContent=favorites.has(id)?'★':'☆';b.setAttribute('aria-pressed',favorites.has(id));filterCards();}
  });
  panel.addEventListener('input',e=>{
    const input=e.target;if(input.classList.contains('filter-search')){query=input.value.trim();filterCards();return;}
    if(!input.dataset.colorRange)return;const key=input.dataset.colorRange, v=Number(input.value), scope=input.dataset.scope;
    if(scope==='hsl')hsl[hslChannel][key]=v;else if(scope==='grade'){grade[gradeZone][key]=v;paintGrade();}else if(scope==='curve'){curves[curveChannel][key]=v;const points=curves[curveChannel].map((y,i)=>`${i*60},${240-y*2.4}`).join(' ');panel.querySelector('#curve-line').setAttribute('points',points);panel.querySelector(`[data-curve-point="${key}"]`).setAttribute('cy',240-v*2.4);}else values[key]=v;
    input.previousElementSibling.textContent=v;input.style.setProperty('--fill',`${(v-input.min)/(input.max-input.min)*100}%`);
  });
  panel.addEventListener('dblclick',e=>{const input=e.target;if(!input.matches('[data-color-range]'))return;input.value=input.dataset.scope==='curve'?Number(input.dataset.colorRange)*25:input.dataset.scope==='value'?defaults[input.dataset.colorRange]:0;input.dispatchEvent(new Event('input',{bubbles:true}));});
  panel.addEventListener('keydown',e=>{const b=e.target.closest('[data-color-tab]');if(!b||!['ArrowLeft','ArrowRight','Home','End'].includes(e.key))return;e.preventDefault();const ids=Object.keys(tabs),index=ids.indexOf(activeTab);activeTab=e.key==='Home'?ids[0]:e.key==='End'?ids.at(-1):ids[(index+(e.key==='ArrowRight'?1:-1)+ids.length)%ids.length];showTab();panel.querySelector(`[data-color-tab="${activeTab}"]`).focus();});
  let drag=null;
  panel.addEventListener('pointerdown',e=>{const dot=e.target.closest('[data-curve-point]');if(!dot||e.button!==0)return;e.preventDefault();const svg=dot.closest('svg');drag={index:Number(dot.dataset.curvePoint),svg,pointer:e.pointerId};svg.setPointerCapture(e.pointerId);});
  panel.addEventListener('pointermove',e=>{if(!drag)return;const r=drag.svg.getBoundingClientRect();curves[curveChannel][drag.index]=Math.round(Math.max(0,Math.min(100,100-(e.clientY-r.top)/r.height*100)));updateCurve();});
  for(const event of ['pointerup','pointercancel'])panel.addEventListener(event,()=>{if(drag?.svg.hasPointerCapture(drag.pointer))drag.svg.releasePointerCapture(drag.pointer);drag=null;});
  // The panel reset also resets UI-only parameters, before the base app redraws it.
  document.addEventListener('click',e=>{if(tool!=='adjust'||!e.target.closest('[data-action="reset-panel"]'))return;values={...defaults};Object.values(hsl).forEach(v=>Object.assign(v,{hue:0,saturation:0,luminance:0}));Object.values(grade).forEach(v=>Object.assign(v,{hue:0,saturation:0,luminance:0}));Object.keys(curves).forEach(k=>curves[k]=[0,25,50,75,100]);},true);
  decorate(document.querySelector('[data-tool].active')?.dataset.tool||'adjust');
})();
