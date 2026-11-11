(() => {
  'use strict';
  const products = window.RACEBOLT_CATALOG;
  const key = 'racebolt-private-demo-v1';
  const $ = selector => document.querySelector(selector);
  const escape = value => String(value).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const paths = {
    home:'M3 10 12 3l9 7M5 9v11h5v-6h4v6h5V9',shop:'M4 9h16l-1 12H5L4 9Zm4 0V7a4 4 0 0 1 8 0v2',
    heart:'M20.4 4.6a5.5 5.5 0 0 0-7.8 0L12 5.2l-.6-.6a5.5 5.5 0 0 0-7.8 7.8L12 21l8.4-8.6a5.5 5.5 0 0 0 0-7.8Z',
    basket:'m3 7 2 13h14l2-13H3Zm4 0 5-5 5 5M9 11v5m6-5v5',arrow:'M4 12h16m-6-6 6 6-6 6',
    plus:'M12 5v14M5 12h14',minus:'M5 12h14',close:'m6 6 12 12M6 18 18 6',
    shield:'M12 3 4 6v6c0 5 8 9 8 9s8-4 8-9V6l-8-3Zm-4 9 3 3 5-6',flag:'M5 21V3m0 0c4-3 7 3 14 0v10c-7 3-10-3-14 0',
    bolt:'m13 2-9 12h7l-1 8 10-13h-7l0-7',info:'M12 11v6M12 7h.01',search:'m16 16 4 4',check:'m5 12 4 4 10-10',
  };
  const icon = name => `<svg viewBox="0 0 24 24" aria-hidden="true">${name==='search'?'<circle cx="10.5" cy="10.5" r="6.5"/>':''}${name==='info'?'<circle cx="12" cy="12" r="9"/>':''}<path d="${paths[name] || paths.arrow}"/></svg>`;
  let persisted = {};
  try { persisted = JSON.parse(localStorage.getItem(key) || '{}') || {}; } catch (_) {}
  const validId = id => products.some(p => p.id === id);
  const state = {
    page:'home',material:'All',category:'All styles',query:'',sort:'featured',vat:true,
    saved:Array.isArray(persisted.saved)?persisted.saved.filter(validId):[],
    cart:Object.fromEntries(Object.entries(persisted.cart || {}).filter(([id,n]) => validId(id) && Number.isInteger(n) && n>0 && n<=99)),
  };
  let toastTimer, previousFocus;
  const save = () => { try { localStorage.setItem(key,JSON.stringify({saved:state.saved,cart:state.cart})); } catch (_) {} };
  const money = n => '£' + (n/100).toFixed(2);
  const unit = product => Math.round(product.price * 100 / (state.vat ? 1 : 1.2));
  const isRange = p => p.priceText.includes('Price range');
  const vatText = () => state.vat ? 'incl. VAT' : 'ex. VAT';
  const price = p => `${isRange(p)?'<small>FROM</small>':''}${money(unit(p))}`;
  const shortName = p => p.name.replace(/^(Titanium|Stainless Steel|Aluminium) /,'');
  const count = () => Object.values(state.cart).reduce((a,b) => a+b,0);
  const saveButton = p => `<button class="save-button ${state.saved.includes(p.id)?'saved':''}" data-action="save" data-id="${p.id}" aria-label="${state.saved.includes(p.id)?'Unsave':'Save'} ${escape(p.name)}" aria-pressed="${state.saved.includes(p.id)}">${icon('heart')}</button>`;
  function card(p) {
    return `<article class="product-card"><div class="product-stage"><button class="product-open" data-action="product" data-id="${p.id}" aria-label="View ${escape(p.name)}"><img src="${p.image}" alt="${escape(p.name)}" loading="lazy"></button>${saveButton(p)}</div><span class="material-tag">${escape(p.material)}</span><button class="product-name" data-action="product" data-id="${p.id}">${escape(shortName(p))}</button><div class="price-row"><span class="price">${price(p)}</span><button class="add-small" data-action="add" data-id="${p.id}" aria-label="Add ${escape(p.name)} to demo basket">${icon('plus')}</button></div><div class="vat-note">${vatText()} · demo price</div></article>`;
  }
  const footer = () => `<footer class="demo-footer">A private mobile concept for Racebolt UK.<br>Product snapshot · 11 November 2026<br><button data-action="about">About this demo</button> · No live inventory or checkout</footer>`;
  function renderNav() {
    $('#bottom-nav').innerHTML = [['home','home','Home'],['shop','shop','Shop'],['saved','heart','Saved'],['basket','basket','Basket']].map(([page,symbol,label]) => `<button class="nav-item ${state.page===page?'active':''}" data-action="nav" data-page="${page}" ${state.page===page?'aria-current="page"':''}>${icon(symbol)}<span>${label}</span>${page==='basket'&&count()?`<span class="badge">${count()}</span>`:''}${page==='saved'&&state.saved.length?`<span class="badge">${state.saved.length}</span>`:''}</button>`).join('');
  }
  function home() {
    return `<section class="hero" aria-label="Racebolt British engineering"><img class="hero-photo" src="assets/hero.webp" alt="Moto Rapido Ducati on the race circuit"><div class="hero-copy"><div class="eyebrow">ENGINEERED IN BRISTOL</div><h1>SMALL PARTS.<br><em>BIG DIFFERENCE.</em></h1><p>Precision fasteners. Purpose-built for your next ride.</p><button class="primary" data-action="material" data-material="Titanium">EXPLORE TITANIUM ${icon('arrow')}</button></div></section>
      <div class="trust-row"><div>${icon('flag')}<span>BRITISH<br>MANUFACTURED</span></div><div>${icon('shield')}<span>PRECISION<br>ENGINEERED</span></div><div>${icon('bolt')}<span>RACE<br>PROVEN</span></div></div>
      <section class="section"><div class="section-heading"><div><div class="kicker">THE DETAILS MAKE THE DIFFERENCE</div><h2>Built for performance</h2></div><button class="text-link" data-action="nav" data-page="shop">View all ${icon('arrow')}</button></div><div class="product-grid">${[products[0],products[1],products[3],products[6]].map(card).join('')}</div></section>
      <section class="section materials"><div class="section-heading"><div><div class="kicker">FIND YOUR FINISH</div><h2>Choose your material</h2></div></div><div class="material-cards">${[['Titanium','Strength without the weight.','ti-race'],['Stainless steel','A polished, durable all-rounder.','ss-hex'],['Aluminium','Lightweight. Made to stand out.','al-nut']].map(([name,desc,id],n)=>`<button class="material-card" data-action="material" data-material="${name}"><span class="number">0${n+1}</span><div><h3>${name}</h3><p>${desc}</p></div><img src="assets/${id}.webp" alt="" loading="lazy">${icon('arrow')}</button>`).join('')}</div></section>
      <section class="track-card"><img src="assets/engineering.webp" alt="Racebolt motorcycle racing photography" loading="lazy"><div class="track-copy"><div class="kicker">FROM THE WORKSHOP TO THE GRID</div><h2>British engineering.<br>Race-day confidence.</h2><p>Explore a mobile concept inspired by Racebolt's precision fasteners and track partnerships.</p><button class="outline-light" data-action="story">The Racebolt story ${icon('arrow')}</button></div></section>${footer()}`;
  }
  function filtered() {
    let list = products.filter(p => (state.material==='All'||p.material===state.material) && (state.category==='All styles'||p.category===state.category) && `${p.name} ${p.sku} ${p.material} ${p.category}`.toLowerCase().includes(state.query.toLowerCase()));
    if(state.sort==='low') list.sort((a,b)=>a.price-b.price);
    if(state.sort==='high') list.sort((a,b)=>b.price-a.price);
    if(state.sort==='name') list.sort((a,b)=>a.name.localeCompare(b.name));
    return list;
  }
  const noResults = () => `<div class="empty-state"><div class="empty-icon">${icon('search')}</div><h2>No matching parts</h2><p>Try a different material, style or search. This demo includes eight sample products.</p><button class="primary" data-action="reset">Clear filters ${icon('arrow')}</button></div>`;
  function shop() {
    return `<div class="page-head"><div class="kicker">PRECISION. DOWN TO THE LAST THREAD.</div><h1 class="page-title">Find your fasteners</h1><p class="page-subtitle">Eight real products. One easy-to-use demo.</p></div><label class="search-box">${icon('search')}<input id="product-search" type="search" placeholder="Search parts, sizes or SKU…" value="${escape(state.query)}" aria-label="Search parts, sizes or SKU"></label><div class="chip-row">${['All','Titanium','Stainless steel','Aluminium'].map(m=>`<button class="chip ${state.material===m?'active':''}" data-action="material" data-material="${m}" aria-pressed="${state.material===m}">${m==='All'?'All materials':m}</button>`).join('')}</div><div class="filter-row"><select id="style-filter" aria-label="Filter by fastener style">${['All styles',...new Set(products.map(p=>p.category))].map(c=>`<option ${state.category===c?'selected':''}>${escape(c)}</option>`).join('')}</select><select id="sort-filter" aria-label="Sort products">${[['featured','Featured'],['low','Price: low to high'],['high','Price: high to low'],['name','Name: A to Z']].map(([v,t])=>`<option value="${v}" ${state.sort===v?'selected':''}>${t}</option>`).join('')}</select></div><div class="results-label"><span id="results-count"></span><button class="vat-toggle" data-action="vat">Prices ${vatText()}</button></div><div id="shop-results" class="shop-grid"></div>${footer()}`;
  }
  function updateResults() {
    const list=filtered();
    $('#results-count').textContent=`${list.length} sample product${list.length===1?'':'s'}`;
    $('#shop-results').innerHTML=list.length?`<div class="product-grid">${list.map(card).join('')}</div>`:noResults();
  }
  function savedPage() {
    const list=products.filter(p=>state.saved.includes(p.id));
    return `<div class="page-head"><div class="kicker">YOUR SHORTLIST, READY WHEN YOU ARE</div><h1 class="page-title">Saved parts</h1><p class="page-subtitle">${list.length} saved locally on this device.</p></div>${list.length?`<div class="section"><div class="product-grid">${list.map(card).join('')}</div></div>`:`<div class="empty-state"><div class="empty-icon">${icon('heart')}</div><h2>Build your shortlist</h2><p>Tap the heart on any part to save it here. No account needed.</p><button class="primary" data-action="nav" data-page="shop">Explore the range ${icon('arrow')}</button></div>`}${footer()}`;
  }
  function basketPage() {
    const list=products.filter(p=>state.cart[p.id]);
    if(!list.length)return `<div class="page-head"><div class="kicker">JUST A TEST DRIVE. NO REAL ORDERS.</div><h1 class="page-title">Your demo basket</h1></div><div class="empty-state"><div class="empty-icon">${icon('basket')}</div><h2>Your build starts here</h2><p>Add a few parts and try the redesigned basket. Nothing will be ordered or charged.</p><button class="primary" data-action="nav" data-page="shop">Find your fasteners ${icon('arrow')}</button></div>${footer()}`;
    const total=list.reduce((sum,p)=>sum+unit(p)*state.cart[p.id],0);
    return `<div class="page-head"><div class="kicker">JUST A TEST DRIVE. NO REAL ORDERS.</div><h1 class="page-title">Your demo basket</h1><p class="page-subtitle">${count()} item${count()===1?'':'s'} · saved only on this device</p></div><div class="local-notice">${icon('info')}<span>Sample prices, not live stock or a fitment guarantee. No payment details are collected.</span></div>${list.map(p=>`<article class="basket-item"><button class="basket-image" data-action="product" data-id="${p.id}" aria-label="View ${escape(p.name)}"><img src="${p.image}" alt="${escape(p.name)}"></button><div><span class="material-tag">${p.material}</span><h3>${escape(shortName(p))}</h3><div class="price-row"><span class="price">${money(unit(p)*state.cart[p.id])}</span><span class="vat-note">${money(unit(p))} each</span></div><div class="item-controls"><div class="quantity"><button data-action="qty" data-id="${p.id}" data-change="-1" aria-label="Reduce quantity of ${escape(p.name)}">${icon('minus')}</button><span aria-label="Quantity">${state.cart[p.id]}</span><button data-action="qty" data-id="${p.id}" data-change="1" aria-label="Increase quantity of ${escape(p.name)}" ${state.cart[p.id]===99?'disabled':''}>${icon('plus')}</button></div><button class="remove-item" data-action="remove" data-id="${p.id}">Remove</button></div></div></article>`).join('')}<div class="basket-summary"><div class="summary-row"><span>Sample subtotal</span><span>${money(total)}</span></div><div class="summary-row"><span>Delivery</span><span>Not calculated in demo</span></div><div class="summary-row total"><span>Demo total</span><span>${money(total)}</span></div><div class="summary-row"><span>${vatText()} · ${state.vat?'VAT included':'VAT excluded'}</span><button data-action="vat" class="text-link">Switch VAT view</button></div><button class="primary" data-action="demo-checkout">Try demo checkout ${icon('arrow')}</button><p>No payment. No order. This is a private test.</p></div><div class="snapshot"><button data-action="clear-basket" class="text-link">Clear demo basket</button></div>${footer()}`;
  }
  function render() {
    $('#content').innerHTML=({home,shop,saved:savedPage,basket:basketPage}[state.page])();
    renderNav();
    if(state.page==='shop')updateResults();
  }
  function navigate(page) {
    closeModal(); state.page=page; render(); window.scrollTo(0,0);
    $('#content').focus({preventScroll:true});
  }
  function toast(text, basketLink=false) {
    clearTimeout(toastTimer); $('#toast').innerHTML=`<span>${escape(text)}</span>${basketLink?'<button data-action="nav" data-page="basket">View basket</button>':''}`;
    $('#toast').classList.add('visible'); toastTimer=setTimeout(()=>$('#toast').classList.remove('visible'),3000);
  }
  function closeModal() {
    $('#modal-root').innerHTML='';document.body.classList.remove('modal-open');
    if(previousFocus&&previousFocus.isConnected)previousFocus.focus({preventScroll:true});
  }
  function modal(content,label) {
    previousFocus=document.activeElement; $('#modal-root').innerHTML=`<div class="modal-overlay"><section class="modal-sheet" role="dialog" aria-modal="true" aria-label="${escape(label)}"><div class="sheet-handle"></div><button class="modal-close" data-action="close" aria-label="Close dialog">${icon('close')}</button>${content}</section></div>`;
    document.body.classList.add('modal-open');$('.modal-close').focus({preventScroll:true});
  }
  function productModal(p) {
    modal(`<div class="detail-image"><img src="${p.image}" alt="${escape(p.name)}"></div><div class="detail-body"><span class="material-tag">${p.material} · ${p.category}</span><h2>${escape(p.name)}</h2><div class="detail-price"><div><span class="price">${price(p)}</span><div class="vat-note">${vatText()} · sample price</div></div>${saveButton(p)}</div><dl class="spec-list"><dt>Product code</dt><dd>${escape(p.sku)}</dd><dt>Material</dt><dd>${p.material}</dd><dt>Head / part style</dt><dd>${p.category}</dd><dt>Catalog snapshot</dt><dd>11 November 2026</dd></dl><p class="detail-note">${isRange(p)?'The source listing has variant prices. This demo uses the lowest displayed price and does not select a real variant. ':''}Check dimensions, torque requirements and motorcycle fitment before a real purchase. This demo does not verify compatibility or availability.</p><button class="primary" data-action="add" data-id="${p.id}">Add to demo basket ${icon('plus')}</button></div>`,p.name);
  }
  document.addEventListener('click',event=>{
    if(event.target.classList.contains('modal-overlay')) {closeModal();return;}
    const target=event.target.closest('[data-action]');if(!target)return;
    const action=target.dataset.action;const p=products.find(p=>p.id===target.dataset.id);
    if(action==='nav')navigate(target.dataset.page);
    if(action==='material'){state.material=target.dataset.material;state.query='';state.category='All styles';navigate('shop');}
    if(action==='search'){navigate('shop');$('#product-search').focus();}
    if(action==='product'&&p)productModal(p);
    if(action==='add'&&p){if((state.cart[p.id]||0)>=99){toast('Demo quantity limit: 99 per part');return;}state.cart[p.id]=(state.cart[p.id]||0)+1;save();renderNav();if(state.page==='basket')render();toast('Part added to your demo basket',true);}
    if(action==='save'&&p){state.saved=state.saved.includes(p.id)?state.saved.filter(id=>id!==p.id):[...state.saved,p.id];save();const open=!!$('.modal-sheet');render();if(open)productModal(p);toast(state.saved.includes(p.id)?'Part saved to your shortlist':'Part removed from saved');}
    if(action==='qty'&&p){const n=state.cart[p.id]+Number(target.dataset.change);if(n<1)delete state.cart[p.id];else state.cart[p.id]=Math.min(n,99);save();render();}
    if(action==='remove'&&p){delete state.cart[p.id];save();render();toast('Part removed from the demo basket');}
    if(action==='clear-basket'){state.cart={};save();render();toast('Demo basket cleared');}
    if(action==='vat'){state.vat=!state.vat;render();}
    if(action==='reset'){state.material='All';state.category='All styles';state.query='';state.sort='featured';render();}
    if(action==='close')closeModal();
    if(action==='menu')modal(`<div class="info-body"><div class="kicker">RACEBOLT · PRIVATE MOBILE CONCEPT</div><h2>Made for your next ride.</h2>${[['All fasteners','All'],['Titanium','Titanium'],['Stainless steel','Stainless steel'],['Aluminium','Aluminium']].map(([label,m])=>`<button class="menu-row" data-action="material" data-material="${m}">${label}${icon('arrow')}</button>`).join('')}<div class="menu-sub">YOUR TEST DRIVE</div><button class="menu-row" data-action="nav" data-page="saved">Saved parts ${icon('heart')}</button><button class="menu-row" data-action="nav" data-page="basket">Demo basket ${icon('basket')}</button><button class="text-link" data-action="about">About this demo ${icon('info')}</button></div>`,'Navigation menu');
    if(action==='about')modal(`<div class="info-body"><div class="kicker">A NEW MOBILE DIRECTION</div><h2>Racebolt. Reimagined.</h2><p>A private, offline prototype using Racebolt UK's public branding, photos and eight sample products.</p><div class="info-list">Browse by material, style or SKU.<br>Save favourite parts on this device.<br>Test basket quantities and totals.<br>No account, payment or real order.</div><p>Prices are a snapshot from 11 November 2026, not a current offer. Variant listings use their lowest displayed price. VAT view assumes a 20% standard rate.</p><p>The live raceboltuk.com store is unchanged. This app blocks external navigation and does not connect to its checkout or APIs.</p><button class="primary" data-action="close">Back to exploring ${icon('arrow')}</button></div>`,'About this private demo');
    if(action==='story')modal(`<div class="info-body"><div class="kicker">BRITISH ENGINEERING</div><h2>From Bristol.<br>Built for the grid.</h2><p>Racebolt's public website describes over 20 years of fastener manufacturing and high-precision CNC engineering in Bristol.</p><p>Its titanium, stainless steel and aluminium ranges serve riders who care about the details. The brand also works with motorcycle racing teams.</p><p>This test app brings that identity into a cleaner, mobile-first browsing experience. It is not a substitute for Racebolt's technical advice or torque guidance.</p><button class="primary" data-action="nav" data-page="shop">Explore sample products ${icon('arrow')}</button></div>`,'Racebolt story');
    if(action==='demo-checkout')modal(`<div class="info-body"><div class="kicker">DEMO CHECKOUT</div><h2>At the finish line.</h2><p>Your redesigned basket is ready. This prototype stops before payment or order submission.</p><div class="info-list">No payment information requested.<br>No order sent to Racebolt.<br>No stock reserved.<br>Your demo basket stays on this device.</div><button class="primary" data-action="finish-demo">Finish test drive ${icon('check')}</button></div>`,'Demo checkout — no real order');
    if(action==='finish-demo'){closeModal();toast('Demo complete. No order was placed.');}
  });
  document.addEventListener('input',event=>{if(event.target.id==='product-search'){state.query=event.target.value;updateResults();}});
  document.addEventListener('change',event=>{if(event.target.id==='style-filter'){state.category=event.target.value;updateResults();}if(event.target.id==='sort-filter'){state.sort=event.target.value;updateResults();}});
  document.addEventListener('keydown',event=>{
    const dialog=$('.modal-sheet');if(!dialog)return;
    if(event.key==='Escape')closeModal();
    if(event.key==='Tab'){
      const items=[...dialog.querySelectorAll('button:not([disabled]),input,select,[tabindex="0"]')];
      const first=items[0],last=items[items.length-1];
      if(event.shiftKey&&document.activeElement===first){event.preventDefault();last.focus();}
      else if(!event.shiftKey&&document.activeElement===last){event.preventDefault();first.focus();}
    }
  });
  render();
})();