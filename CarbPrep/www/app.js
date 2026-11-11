// CarbPrep — Barcode Carb & Batch Meal Prep Calculator (iOS .ipa & PWA)

const STORAGE_KEYS = {
  CURRENT_MEAL: 'carbprep_current_meal_v1',
  PREPPED_MEALS: 'carbprep_prepped_meals_v1',
  FOOD_LIBRARY: 'carbprep_food_library_v1',
  SETTINGS: 'carbprep_settings_v1'
};

// Pre-loaded offline staples & common UK/US barcodes
const DEFAULT_FOODS = [
  { id: 'f_basmati_dry', barcode: '5000169005033', name: 'Basmati Rice (Dry Weight)', brand: 'Staple / Generic', servingG: 75, carbs100: 77.8, fiber100: 1.4, sugar100: 0.2, protein100: 8.5, fat100: 0.9, kcal100: 356 },
  { id: 'f_basmati_cooked', barcode: '5000169085219', name: 'Basmati Rice (Cooked)', brand: 'Staple / Microwave Pouch', servingG: 180, carbs100: 31.0, fiber100: 0.8, sugar100: 0.1, protein100: 3.5, fat100: 1.2, kcal100: 151 },
  { id: 'f_pasta_dry', barcode: '5000169005415', name: 'Penne / Fusilli Pasta (Dry)', brand: 'Staple / Generic', servingG: 75, carbs100: 72.0, fiber100: 3.4, sugar100: 3.2, protein100: 12.5, fat100: 1.5, kcal100: 355 },
  { id: 'f_oats', barcode: '5000157024671', name: 'Rolled Porridge Oats', brand: 'Quaker / Staple', servingG: 40, carbs100: 60.0, fiber100: 9.0, sugar100: 1.1, protein100: 11.0, fat100: 8.0, kcal100: 374 },
  { id: 'f_beans', barcode: '5000157024886', name: 'Baked Beans in Tomato Sauce', brand: 'Heinz', servingG: 207, carbs100: 12.5, fiber100: 3.7, sugar100: 4.3, protein100: 4.7, fat100: 0.2, kcal100: 78 },
  { id: 'f_kidney_beans', barcode: '5000169043127', name: 'Red Kidney Beans in Water (Drained)', brand: 'Staple', servingG: 120, carbs100: 16.0, fiber100: 6.5, sugar100: 0.6, protein100: 8.4, fat100: 0.6, kcal100: 116 },
  { id: 'f_chopped_tom', barcode: '5000169011225', name: 'Chopped Tomatoes (Tinned)', brand: 'Staple', servingG: 200, carbs100: 3.9, fiber100: 1.0, sugar100: 3.7, protein100: 1.1, fat100: 0.1, kcal100: 23 },
  { id: 'f_sweet_potato', barcode: '0000000004074', name: 'Sweet Potato (Raw / Peeled)', brand: 'Fresh Produce', servingG: 150, carbs100: 20.1, fiber100: 3.0, sugar100: 4.2, protein100: 1.6, fat100: 0.1, kcal100: 86 },
  { id: 'f_white_potato', barcode: '0000000004072', name: 'White Potato (Raw / Boiled)', brand: 'Fresh Produce', servingG: 175, carbs100: 17.5, fiber100: 1.8, sugar100: 0.8, protein100: 2.0, fat100: 0.1, kcal100: 77 },
  { id: 'f_chicken_breast', barcode: '5000169112205', name: 'Chicken Breast Fillet (Raw)', brand: 'Staple', servingG: 150, carbs100: 0.0, fiber100: 0.0, sugar100: 0.0, protein100: 24.0, fat100: 1.1, kcal100: 106 },
  { id: 'f_beef_mince', barcode: '5000169113004', name: 'Lean Beef Steak Mince (5% Fat)', brand: 'Staple', servingG: 125, carbs100: 0.0, fiber100: 0.0, sugar100: 0.0, protein100: 21.5, fat100: 5.0, kcal100: 131 },
  { id: 'f_bread_slice', barcode: '5010044000116', name: 'Toastie Thick White Bread (1 Slice = 47g)', brand: 'Warburtons', servingG: 47, carbs100: 45.9, fiber100: 2.3, sugar100: 3.0, protein100: 9.2, fat100: 2.1, kcal100: 244 },
  { id: 'f_banana', barcode: '0000000004011', name: 'Banana (Peeled Flesh)', brand: 'Fresh Produce', servingG: 100, carbs100: 22.8, fiber100: 2.6, sugar100: 12.2, protein100: 1.1, fat100: 0.3, kcal100: 89 }
];

const DEFAULT_PREPS = [
  {
    id: 'prep_sample_1',
    name: 'Chicken, Sweet Potato & Basmati Prep',
    notes: '4 meal-prep tubs (420g cooked per tub)',
    portionsTotal: 4,
    portionsLeft: 4,
    cookedWeightG: 1680,
    createdAt: new Date().toISOString(),
    items: [
      { name: 'Basmati Rice (Dry Weight)', brand: 'Staple', weightG: 300, carbs100: 77.8, fiber100: 1.4, sugar100: 0.2, protein100: 8.5, fat100: 0.9, kcal100: 356 },
      { name: 'Sweet Potato (Raw / Peeled)', brand: 'Fresh', weightG: 400, carbs100: 20.1, fiber100: 3.0, sugar100: 4.2, protein100: 1.6, fat100: 0.1, kcal100: 86 },
      { name: 'Chicken Breast Fillet (Raw)', brand: 'Staple', weightG: 600, carbs100: 0.0, fiber100: 0.0, sugar100: 0.0, protein100: 24.0, fat100: 1.1, kcal100: 106 }
    ]
  },
  {
    id: 'prep_sample_2',
    name: 'Beef Chilli Con Carne Batch',
    notes: '5 portions in fridge/freezer (350g per tub)',
    portionsTotal: 5,
    portionsLeft: 5,
    cookedWeightG: 1750,
    createdAt: new Date().toISOString(),
    items: [
      { name: 'Lean Beef Steak Mince (5% Fat)', brand: 'Staple', weightG: 500, carbs100: 0.0, fiber100: 0.0, sugar100: 0.0, protein100: 21.5, fat100: 5.0, kcal100: 131 },
      { name: 'Red Kidney Beans (Drained)', brand: 'Staple', weightG: 480, carbs100: 16.0, fiber100: 6.5, sugar100: 0.6, protein100: 8.4, fat100: 0.6, kcal100: 116 },
      { name: 'Chopped Tomatoes (2 Tins)', brand: 'Staple', weightG: 800, carbs100: 3.9, fiber100: 1.0, sugar100: 3.7, protein100: 1.1, fat100: 0.1, kcal100: 23 }
    ]
  }
];

// State
let currentMeal = [];
let preppedMeals = [];
let foodLibrary = [];
let settings = {
  icr: 10,          // 1 unit per 10g carbs
  carbBasis: 'total', // 'total' | 'net'
  bgUnit: 'mmol',   // 'mmol' | 'mgdl'
  targetBg: 5.5,
  isf: 2.5,
  rounding: 0.5
};

// Load State from localStorage
function loadState() {
  try {
    const savedMeal = localStorage.getItem(STORAGE_KEYS.CURRENT_MEAL);
    currentMeal = savedMeal ? JSON.parse(savedMeal) : [];

    const savedPreps = localStorage.getItem(STORAGE_KEYS.PREPPED_MEALS);
    preppedMeals = savedPreps ? JSON.parse(savedPreps) : DEFAULT_PREPS;

    const savedFoods = localStorage.getItem(STORAGE_KEYS.FOOD_LIBRARY);
    foodLibrary = savedFoods ? JSON.parse(savedFoods) : DEFAULT_FOODS;

    const savedSettings = localStorage.getItem(STORAGE_KEYS.SETTINGS);
    if (savedSettings) {
      settings = { ...settings, ...JSON.parse(savedSettings) };
    }
  } catch (e) {
    console.error('Error loading state:', e);
    foodLibrary = DEFAULT_FOODS;
    preppedMeals = DEFAULT_PREPS;
  }
}

function saveState() {
  try {
    localStorage.setItem(STORAGE_KEYS.CURRENT_MEAL, JSON.stringify(currentMeal));
    localStorage.setItem(STORAGE_KEYS.PREPPED_MEALS, JSON.stringify(preppedMeals));
    localStorage.setItem(STORAGE_KEYS.FOOD_LIBRARY, JSON.stringify(foodLibrary));
    localStorage.setItem(STORAGE_KEYS.SETTINGS, JSON.stringify(settings));
  } catch (e) {}
}

// Toast Notification
let toastTimer = null;
function showToast(msg) {
  const el = document.getElementById('toast');
  el.textContent = msg;
  el.classList.add('show');
  if (toastTimer) clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.classList.remove('show'), 2400);
}

// Macro Calculation Helper
function calcMacrosForItems(items) {
  let carbs = 0, fiber = 0, sugar = 0, protein = 0, fat = 0, kcal = 0, rawWeight = 0;
  for (const item of items) {
    const factor = (Number(item.weightG) || 0) / 100.0;
    carbs += (Number(item.carbs100) || 0) * factor;
    fiber += (Number(item.fiber100) || 0) * factor;
    sugar += (Number(item.sugar100) || 0) * factor;
    protein += (Number(item.protein100) || 0) * factor;
    fat += (Number(item.fat100) || 0) * factor;
    kcal += (Number(item.kcal100) || 0) * factor;
    rawWeight += (Number(item.weightG) || 0);
  }
  const netCarbs = Math.max(0, carbs - fiber);
  return { carbs, netCarbs, fiber, sugar, protein, fat, kcal, rawWeight };
}

function calculateBolusUnits(carbsTotal, netCarbsTotal, currentBgVal = null) {
  const activeCarbs = settings.carbBasis === 'net' ? netCarbsTotal : carbsTotal;
  const icr = Math.max(0.5, Number(settings.icr) || 10);
  let units = activeCarbs / icr;

  if (currentBgVal !== null && !isNaN(currentBgVal) && currentBgVal > 0) {
    const diff = currentBgVal - Number(settings.targetBg || 5.5);
    const isf = Math.max(0.1, Number(settings.isf) || 2.5);
    units += diff / isf;
  }

  units = Math.max(0, units);
  const step = Number(settings.rounding) || 0.5;
  return Math.round(units / step) * step;
}

// Render Current Meal Tab
function renderCurrentMeal() {
  const totals = calcMacrosForItems(currentMeal);

  document.getElementById('meal-total-carbs').textContent = `${totals.carbs.toFixed(1)}g`;
  document.getElementById('meal-net-carbs').textContent = `${totals.netCarbs.toFixed(1)}g`;
  document.getElementById('meal-fiber').textContent = `${totals.fiber.toFixed(1)}g`;
  document.getElementById('meal-sugar').textContent = `${totals.sugar.toFixed(1)}g`;
  document.getElementById('meal-protein').textContent = `${totals.protein.toFixed(1)}g`;
  document.getElementById('meal-fat').textContent = `${totals.fat.toFixed(1)}g`;
  document.getElementById('meal-kcal').textContent = `${Math.round(totals.kcal)}`;

  const bgStr = document.getElementById('current-bg-input').value;
  const bgVal = bgStr ? parseFloat(bgStr) : null;
  const bolus = calculateBolusUnits(totals.carbs, totals.netCarbs, bgVal);

  const basisText = settings.carbBasis === 'net' ? 'Net' : 'Total';
  document.getElementById('bolus-formula-label').textContent = `Suggested Bolus (1u : ${settings.icr}g ${basisText})`;
  document.getElementById('meal-bolus-units').textContent = `${bolus.toFixed(settings.rounding === 0.1 ? 1 : (settings.rounding === 1 ? 0 : 1))} units`;
  document.getElementById('btn-header-ratio').textContent = `💉 1u : ${settings.icr}g`;
  document.getElementById('bg-unit-label').textContent = `BG (${settings.bgUnit === 'mgdl' ? 'mg/dL' : 'mmol/L'}):`;

  document.getElementById('meal-item-count').textContent = String(currentMeal.length);
  document.getElementById('save-prep-cta').style.display = currentMeal.length > 0 ? 'block' : 'none';

  const listEl = document.getElementById('meal-items-list');
  if (currentMeal.length === 0) {
    listEl.innerHTML = `
      <div class="empty-state">
        <div style="font-size:28px; margin-bottom:6px;">📷</div>
        <div style="font-weight:700; color:#e2e8f0; margin-bottom:4px;">Your meal plate is empty</div>
        <div>Tap <b>Scan Barcode</b>, <b>Snap Barcode</b>, or search a food above to start calculating carbs.</div>
      </div>
    `;
    return;
  }

  listEl.innerHTML = '';
  currentMeal.forEach((item, index) => {
    const f = (Number(item.weightG) || 0) / 100.0;
    const itemCarbs = (item.carbs100 * f).toFixed(1);
    const itemNet = Math.max(0, (item.carbs100 - (item.fiber100 || 0)) * f).toFixed(1);
    const card = document.createElement('div');
    card.className = 'item-card';
    card.innerHTML = `
      <div class="item-top">
        <div>
          <div class="item-name">${escapeHtml(item.name)}</div>
          <div class="item-meta">
            ${escapeHtml(item.brand || 'Food')} • ${item.carbs100}g carbs / 100g
            ${item.barcode ? ` • #${escapeHtml(item.barcode)}` : ''}
          </div>
        </div>
        <div class="item-carbs-badge">
          ${itemCarbs}g Carbs
          <div style="font-size:10px; color:#6ee7b7; font-weight:600;">${itemNet}g Net</div>
        </div>
      </div>
      <div class="item-controls">
        <div class="weight-stepper">
          <button class="step-btn" data-act="sub50" data-idx="${index}">-50g</button>
          <button class="step-btn" data-act="sub10" data-idx="${index}">-10g</button>
          <input type="number" class="weight-input" value="${item.weightG}" min="1" step="1" data-idx="${index}" />
          <span style="font-size:12px; color:var(--text-muted); font-weight:700;">g</span>
          <button class="step-btn" data-act="add10" data-idx="${index}">+10g</button>
          <button class="step-btn" data-act="add50" data-idx="${index}">+50g</button>
        </div>
        <button class="step-btn" data-act="remove" data-idx="${index}" style="color:#fca5a5;">✕</button>
      </div>
    `;
    listEl.appendChild(card);
  });

  // Bind weight buttons & inputs
  listEl.querySelectorAll('.step-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      const idx = Number(btn.dataset.idx);
      const act = btn.dataset.act;
      if (!currentMeal[idx]) return;
      if (act === 'remove') {
        currentMeal.splice(idx, 1);
      } else if (act === 'sub10') {
        currentMeal[idx].weightG = Math.max(5, Number(currentMeal[idx].weightG) - 10);
      } else if (act === 'sub50') {
        currentMeal[idx].weightG = Math.max(5, Number(currentMeal[idx].weightG) - 50);
      } else if (act === 'add10') {
        currentMeal[idx].weightG = Number(currentMeal[idx].weightG) + 10;
      } else if (act === 'add50') {
        currentMeal[idx].weightG = Number(currentMeal[idx].weightG) + 50;
      }
      saveState();
      renderCurrentMeal();
    });
  });

  listEl.querySelectorAll('.weight-input').forEach(inp => {
    inp.addEventListener('input', () => {
      const idx = Number(inp.dataset.idx);
      const val = parseFloat(inp.value);
      if (currentMeal[idx] && !isNaN(val) && val >= 0) {
        currentMeal[idx].weightG = val;
        saveState();
        const totalsNow = calcMacrosForItems(currentMeal);
        document.getElementById('meal-total-carbs').textContent = `${totalsNow.carbs.toFixed(1)}g`;
        document.getElementById('meal-net-carbs').textContent = `${totalsNow.netCarbs.toFixed(1)}g`;
        const b = calculateBolusUnits(totalsNow.carbs, totalsNow.netCarbs, bgVal);
        document.getElementById('meal-bolus-units').textContent = `${b.toFixed(1)} units`;
      }
    });
    inp.addEventListener('change', () => renderCurrentMeal());
  });
}

// Render Saved Prepped Meals Vault (Tab 2)
function renderPreppedMeals() {
  const listEl = document.getElementById('preps-list');
  if (preppedMeals.length === 0) {
    listEl.innerHTML = `
      <div class="empty-state">
        <div style="font-size:28px; margin-bottom:6px;">🍱</div>
        <div style="font-weight:700; color:#e2e8f0; margin-bottom:4px;">No Prepped Meals Saved Yet</div>
        <div>Build a recipe in <b>Meal Scan</b> and tap <b>Save Current Meal as Prepped Batch</b>.</div>
      </div>
    `;
    return;
  }

  listEl.innerHTML = '';
  preppedMeals.forEach((prep, pIdx) => {
    const batch = calcMacrosForItems(prep.items || []);
    const portions = Math.max(1, Number(prep.portionsTotal) || 1);
    const cookedWeight = Number(prep.cookedWeightG) > 0 ? Number(prep.cookedWeightG) : batch.rawWeight;
    const portionWeight = Math.round(cookedWeight / portions);

    const carbsPerPortion = batch.carbs / portions;
    const netPerPortion = batch.netCarbs / portions;
    const kcalPerPortion = batch.kcal / portions;
    const bolusPerPortion = calculateBolusUnits(carbsPerPortion, netPerPortion);

    const carbsPer100Cooked = cookedWeight > 0 ? (batch.carbs / cookedWeight) * 100 : 0;
    const netPer100Cooked = cookedWeight > 0 ? (batch.netCarbs / cookedWeight) * 100 : 0;
    const kcalPer100Cooked = cookedWeight > 0 ? (batch.kcal / cookedWeight) * 100 : 0;

    const ingSummary = (prep.items || []).map(i => `${i.name} (${i.weightG}g)`).join(' • ');

    const card = document.createElement('div');
    card.className = 'prep-card';
    card.innerHTML = `
      <div class="item-top">
        <div>
          <div class="item-name" style="font-size:16px;">🍱 ${escapeHtml(prep.name)}</div>
          <div class="item-meta">${escapeHtml(prep.notes || `${portions} portions • Total cooked: ${cookedWeight}g`)}</div>
        </div>
        <div style="display:flex; align-items:center; gap:5px;">
          <button class="step-btn" data-pact="dec-tub" data-pidx="${pIdx}">-</button>
          <span style="font-size:12px; font-weight:800; color:#38bdf8; padding:0 4px;">
            ${prep.portionsLeft ?? portions}/${portions} tubs
          </span>
          <button class="step-btn" data-pact="inc-tub" data-pidx="${pIdx}">+</button>
        </div>
      </div>

      <div style="font-size:11px; color:var(--text-muted); margin-bottom:8px; line-height:1.4;">
        <b>Batch Ingredients:</b> ${escapeHtml(ingSummary)}
      </div>

      <div class="prep-badges">
        <div class="prep-stat">
          <div class="prep-stat-lbl">1 Tub (~${portionWeight}g)</div>
          <div class="prep-stat-val" style="color:#fbbf24;">${carbsPerPortion.toFixed(1)}g</div>
          <div style="font-size:10px; color:#34d399;">${netPerPortion.toFixed(1)}g Net</div>
        </div>
        <div class="prep-stat">
          <div class="prep-stat-lbl">Bolus / Tub</div>
          <div class="prep-stat-val" style="color:#e9d5ff;">💉 ${bolusPerPortion.toFixed(1)}u</div>
          <div style="font-size:10px; color:var(--text-muted);">${Math.round(kcalPerPortion)} kcal</div>
        </div>
        <div class="prep-stat">
          <div class="prep-stat-lbl">Per 100g Cooked</div>
          <div class="prep-stat-val" style="color:#38bdf8;">${carbsPer100Cooked.toFixed(1)}g</div>
          <div style="font-size:10px; color:var(--text-muted);">Whole Batch: ${batch.carbs.toFixed(0)}g</div>
        </div>
      </div>

      <!-- Custom Weighed Portion Calculator -->
      <div class="portion-weigh-box">
        <div style="display:flex; align-items:center; gap:6px;">
          <span style="font-size:12px; font-weight:700; color:#6ee7b7;">⚖️ Weigh Portion:</span>
          <input type="number" class="weight-input prep-weigh-inp" value="${portionWeight}" min="1" step="5" data-pidx="${pIdx}" style="width:68px;" />
          <span style="font-size:12px; color:#6ee7b7; font-weight:700;">g</span>
        </div>
        <div style="font-size:13px; font-weight:800; color:#fff;" id="prep-weigh-res-${pIdx}">
          = ${carbsPerPortion.toFixed(1)}g Carbs (💉 ${bolusPerPortion.toFixed(1)}u)
        </div>
      </div>

      <div style="display:flex; justify-content:space-between; gap:8px; margin-top:10px;">
        <button class="btn btn-primary" data-pact="eat-portion" data-pidx="${pIdx}" style="flex:1; padding:9px; font-size:12px;">
          🍽️ Add Weighed Portion to Meal
        </button>
        <button class="btn btn-secondary" data-pact="load-recipe" data-pidx="${pIdx}" style="padding:9px 11px; font-size:12px;">
          ✏️ Edit Batch
        </button>
        <button class="btn btn-danger" data-pact="delete-prep" data-pidx="${pIdx}" style="padding:9px 11px; font-size:12px;">
          🗑️
        </button>
      </div>
    `;
    listEl.appendChild(card);

    // Live weigh input listener
    const weighInp = card.querySelector('.prep-weigh-inp');
    const weighRes = card.querySelector(`#prep-weigh-res-${pIdx}`);
    weighInp.addEventListener('input', () => {
      const g = parseFloat(weighInp.value) || 0;
      const c = (carbsPer100Cooked * g) / 100.0;
      const nc = (netPer100Cooked * g) / 100.0;
      const u = calculateBolusUnits(c, nc);
      weighRes.textContent = `= ${c.toFixed(1)}g Carbs (💉 ${u.toFixed(1)}u)`;
    });
  });

  // Bind prep card actions
  listEl.querySelectorAll('[data-pact]').forEach(btn => {
    btn.addEventListener('click', () => {
      const pIdx = Number(btn.dataset.pidx);
      const act = btn.dataset.pact;
      const prep = preppedMeals[pIdx];
      if (!prep) return;

      if (act === 'dec-tub') {
        prep.portionsLeft = Math.max(0, (prep.portionsLeft ?? prep.portionsTotal) - 1);
        saveState();
        renderPreppedMeals();
      } else if (act === 'inc-tub') {
        prep.portionsLeft = (prep.portionsLeft ?? prep.portionsTotal) + 1;
        saveState();
        renderPreppedMeals();
      } else if (act === 'delete-prep') {
        preppedMeals.splice(pIdx, 1);
        saveState();
        renderPreppedMeals();
        showToast('Prepped meal removed');
      } else if (act === 'load-recipe') {
        currentMeal = JSON.parse(JSON.stringify(prep.items || []));
        saveState();
        renderCurrentMeal();
        switchTab('tab-meal');
        showToast(`Loaded "${prep.name}" batch ingredients`);
      } else if (act === 'eat-portion') {
        const batch = calcMacrosForItems(prep.items || []);
        const portions = Math.max(1, Number(prep.portionsTotal) || 1);
        const cookedWeight = Number(prep.cookedWeightG) > 0 ? Number(prep.cookedWeightG) : batch.rawWeight;
        const cardEl = btn.closest('.prep-card');
        const weighedG = parseFloat(cardEl.querySelector('.prep-weigh-inp').value) || Math.round(cookedWeight / portions);

        const factor = cookedWeight > 0 ? 100.0 / cookedWeight : 1.0;
        currentMeal.push({
          name: `${prep.name} (Prepped Portion)`,
          brand: 'Meal Prep Vault',
          barcode: '',
          weightG: weighedG,
          carbs100: Number((batch.carbs * factor).toFixed(2)),
          fiber100: Number((batch.fiber * factor).toFixed(2)),
          sugar100: Number((batch.sugar * factor).toFixed(2)),
          protein100: Number((batch.protein * factor).toFixed(2)),
          fat100: Number((batch.fat * factor).toFixed(2)),
          kcal100: Number((batch.kcal * factor).toFixed(1))
        });
        if ((prep.portionsLeft ?? prep.portionsTotal) > 0) {
          prep.portionsLeft = (prep.portionsLeft ?? prep.portionsTotal) - 1;
        }
        saveState();
        renderCurrentMeal();
        renderPreppedMeals();
        switchTab('tab-meal');
        showToast(`Added ${weighedG}g of ${prep.name} to Meal!`);
      }
    });
  });
}

// Render Saved Foods & Barcodes Library (Tab 3)
function renderFoodLibrary() {
  const filter = (document.getElementById('food-lib-filter').value || '').trim().toLowerCase();
  const listEl = document.getElementById('foods-library-list');
  const filtered = foodLibrary.filter(f =>
    !filter ||
    (f.name && f.name.toLowerCase().includes(filter)) ||
    (f.brand && f.brand.toLowerCase().includes(filter)) ||
    (f.barcode && f.barcode.includes(filter))
  );

  if (filtered.length === 0) {
    listEl.innerHTML = `<div class="empty-state">No matching foods found. Tap <b>+ Add Food</b> to save a custom barcode or ingredient.</div>`;
    return;
  }

  listEl.innerHTML = '';
  filtered.forEach(food => {
    const card = document.createElement('div');
    card.className = 'item-card';
    card.innerHTML = `
      <div class="item-top">
        <div>
          <div class="item-name">${escapeHtml(food.name)}</div>
          <div class="item-meta">
            ${escapeHtml(food.brand || 'Staple')}
            ${food.barcode ? ` • Barcode: ${escapeHtml(food.barcode)}` : ''}
            • Default: ${food.servingG || 100}g
          </div>
          <div style="font-size:11px; color:#94a3b8; margin-top:4px;">
            Per 100g: <b style="color:#fbbf24;">${food.carbs100}g Carbs</b> (${food.fiber100 || 0}g Fiber) • ${food.protein100 || 0}g Prot • ${food.kcal100 || 0} kcal
          </div>
        </div>
        <div style="display:flex; flex-direction:column; gap:6px;">
          <button class="btn btn-primary" data-fact="add" data-fid="${food.id}" style="padding:7px 12px; font-size:12px;">+ Meal</button>
          <button class="step-btn" data-fact="del" data-fid="${food.id}" style="color:#fca5a5; font-size:11px;">Delete</button>
        </div>
      </div>
    `;
    listEl.appendChild(card);
  });

  listEl.querySelectorAll('[data-fact]').forEach(btn => {
    btn.addEventListener('click', () => {
      const fid = btn.dataset.fid;
      const act = btn.dataset.fact;
      const food = foodLibrary.find(f => f.id === fid);
      if (!food) return;

      if (act === 'add') {
        addFoodItemToCurrentMeal(food);
        switchTab('tab-meal');
      } else if (act === 'del') {
        foodLibrary = foodLibrary.filter(f => f.id !== fid);
        saveState();
        renderFoodLibrary();
        showToast('Removed from Saved Foods');
      }
    });
  });
}

function addFoodItemToCurrentMeal(food, customWeightG = null) {
  const w = customWeightG || Number(food.servingG) || 100;
  currentMeal.push({
    name: food.name,
    brand: food.brand || '',
    barcode: food.barcode || '',
    weightG: w,
    carbs100: Number(food.carbs100) || 0,
    fiber100: Number(food.fiber100) || 0,
    sugar100: Number(food.sugar100) || 0,
    protein100: Number(food.protein100) || 0,
    fat100: Number(food.fat100) || 0,
    kcal100: Number(food.kcal100) || 0
  });
  saveState();
  renderCurrentMeal();
  showToast(`Added ${food.name} (${w}g)`);
}

// OpenFoodFacts Barcode & Name Lookup
async function lookupBarcodeOrSearch(query) {
  const q = (query || '').trim();
  if (!q) return;

  // 1. Check if it's a numeric barcode (8 to 14 digits)
  if (/^\d{4,14}$/.test(q)) {
    await handleScannedBarcode(q);
    return;
  }

  // 2. Otherwise search local library + OpenFoodFacts by text name
  const resultsBox = document.getElementById('search-results-box');
  resultsBox.style.display = 'block';
  resultsBox.innerHTML = `<div class="item-card" style="text-align:center; color:var(--accent);">🔍 Searching "${escapeHtml(q)}"...</div>`;

  const localMatches = foodLibrary.filter(f =>
    (f.name && f.name.toLowerCase().includes(q.toLowerCase())) ||
    (f.brand && f.brand.toLowerCase().includes(q.toLowerCase()))
  );

  let remoteProducts = [];
  try {
    const url = `https://world.openfoodfacts.org/cgi/search.pl?search_terms=${encodeURIComponent(q)}&search_simple=1&action=process&json=1&page_size=6`;
    const res = await fetch(url);
    const data = await res.json();
    if (data && Array.isArray(data.products)) {
      remoteProducts = data.products
        .filter(p => p.product_name && p.nutriments)
        .map(p => parseOpenFoodFactsProduct(p, p.code || ''));
    }
  } catch (e) {}

  const combined = [...localMatches, ...remoteProducts];
  if (combined.length === 0) {
    resultsBox.innerHTML = `
      <div class="item-card" style="text-align:center;">
        <div style="margin-bottom:8px;">No products found for "${escapeHtml(q)}".</div>
        <button class="btn btn-primary" id="btn-create-from-search">+ Create Custom Food "${escapeHtml(q)}"</button>
      </div>
    `;
    document.getElementById('btn-create-from-search').addEventListener('click', () => {
      resultsBox.style.display = 'none';
      openCustomFoodModal({ name: q });
    });
    return;
  }

  resultsBox.innerHTML = `
    <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:6px;">
      <span style="font-size:12px; font-weight:700; color:var(--accent);">Search Results (${combined.length})</span>
      <button class="step-btn" id="btn-close-search-results">✕ Close</button>
    </div>
  `;
  document.getElementById('btn-close-search-results').addEventListener('click', () => {
    resultsBox.style.display = 'none';
  });

  combined.slice(0, 8).forEach((item) => {
    const row = document.createElement('div');
    row.className = 'item-card';
    row.style.marginBottom = '6px';
    row.style.padding = '10px 12px';
    row.innerHTML = `
      <div style="display:flex; justify-content:space-between; align-items:center; gap:8px;">
        <div>
          <div style="font-size:14px; font-weight:700;">${escapeHtml(item.name)}</div>
          <div style="font-size:11px; color:var(--text-muted);">
            ${escapeHtml(item.brand || 'Food')} • <b style="color:#fbbf24;">${item.carbs100}g Carbs/100g</b> (${item.fiber100 || 0}g Fiber)
          </div>
        </div>
        <button class="btn btn-primary" style="padding:7px 12px; font-size:12px;">+ Add</button>
      </div>
    `;
    row.querySelector('button').addEventListener('click', () => {
      rememberFoodInLibrary(item);
      addFoodItemToCurrentMeal(item);
      resultsBox.style.display = 'none';
      document.getElementById('barcode-search-input').value = '';
    });
    resultsBox.appendChild(row);
  });
}

function parseOpenFoodFactsProduct(p, barcode) {
  const n = p.nutriments || {};
  const carbs100 = round1(n.carbohydrates_100g ?? n.carbohydrates ?? 0);
  const fiber100 = round1(n.fiber_100g ?? n.fiber ?? 0);
  const sugar100 = round1(n.sugars_100g ?? n.sugars ?? 0);
  const protein100 = round1(n.proteins_100g ?? n.proteins ?? 0);
  const fat100 = round1(n.fat_100g ?? n.fat ?? 0);
  const kcal100 = Math.round(n['energy-kcal_100g'] ?? (n.energy_100g ? n.energy_100g / 4.184 : 0));

  let servingG = 100;
  if (p.serving_quantity && Number(p.serving_quantity) > 0) {
    servingG = Math.round(Number(p.serving_quantity));
  }

  return {
    id: 'off_' + (barcode || Date.now()),
    barcode: String(barcode || p.code || ''),
    name: p.product_name || p.product_name_en || `Barcode ${barcode}`,
    brand: p.brands ? p.brands.split(',')[0].trim() : 'OpenFoodFacts',
    servingG,
    carbs100,
    fiber100,
    sugar100,
    protein100,
    fat100,
    kcal100
  };
}

function rememberFoodInLibrary(food) {
  const exists = foodLibrary.find(f =>
    (food.barcode && f.barcode === food.barcode) ||
    (f.name.toLowerCase() === food.name.toLowerCase() && f.brand === food.brand)
  );
  if (!exists) {
    foodLibrary.unshift({
      ...food,
      id: food.id || 'food_' + Date.now()
    });
    saveState();
    renderFoodLibrary();
  }
}

async function handleScannedBarcode(barcode) {
  const code = String(barcode).trim();
  if (!code) return;

  stopLiveScanner();
  showToast(`🔍 Looking up barcode ${code}...`);

  // 1. Check local saved food library first (instant offline match!)
  const localHit = foodLibrary.find(f => f.barcode === code);
  if (localHit) {
    addFoodItemToCurrentMeal(localHit);
    return;
  }

  // 2. Query OpenFoodFacts API v2
  try {
    const res = await fetch(`https://world.openfoodfacts.org/api/v2/product/${encodeURIComponent(code)}.json`);
    const data = await res.json();
    if (data && data.status === 1 && data.product) {
      const food = parseOpenFoodFactsProduct(data.product, code);
      rememberFoodInLibrary(food);
      addFoodItemToCurrentMeal(food);
      return;
    }
  } catch (e) {
    console.warn('OpenFoodFacts lookup error:', e);
  }

  // 3. Not found in database -> Open Custom Food modal with barcode pre-filled!
  showToast(`New barcode ${code} — enter label nutrition once to save`);
  openCustomFoodModal({ barcode: code, name: '' });
}

// ================= DUAL-ENGINE BARCODE SCANNER (LIVE VIDEO + SNAP PHOTO) =================
let zxingReader = null;
let scannerStream = null;
let isScannerActive = false;

async function startLiveScanner() {
  const box = document.getElementById('scanner-box');
  const video = document.getElementById('scanner-video');
  box.classList.add('active');
  isScannerActive = true;

  try {
    if (window.ZXing && window.ZXing.BrowserMultiFormatReader) {
      if (!zxingReader) {
        zxingReader = new window.ZXing.BrowserMultiFormatReader();
      }
      await zxingReader.decodeFromConstraints(
        {
          audio: false,
          video: {
            facingMode: { ideal: 'environment' },
            width: { ideal: 1280 },
            height: { ideal: 720 }
          }
        },
        video,
        (result, _err) => {
          if (result && isScannerActive) {
            const code = result.getText();
            if (code) {
              handleScannedBarcode(code);
            }
          }
        }
      );
      return;
    }

    // Fallback to raw getUserMedia + native BarcodeDetector
    scannerStream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: { ideal: 'environment' } },
      audio: false
    });
    video.srcObject = scannerStream;
    await video.play();

    if ('BarcodeDetector' in window) {
      const detector = new window.BarcodeDetector({
        formats: ['ean_13', 'ean_8', 'upc_a', 'upc_e', 'code_128']
      });
      const loop = async () => {
        if (!isScannerActive) return;
        try {
          const codes = await detector.detect(video);
          if (codes && codes.length > 0 && codes[0].rawValue) {
            handleScannedBarcode(codes[0].rawValue);
            return;
          }
        } catch (e) {}
        if (isScannerActive) requestAnimationFrame(loop);
      };
      requestAnimationFrame(loop);
    }
  } catch (err) {
    console.warn('Live camera stream blocked or unavailable, opening iOS Camera Snap:', err);
    stopLiveScanner();
    showToast('Opening iOS Camera Barcode Snap...');
    document.getElementById('camera-snap-input').click();
  }
}

function stopLiveScanner() {
  isScannerActive = false;
  document.getElementById('scanner-box').classList.remove('active');
  if (zxingReader) {
    try { zxingReader.reset(); } catch (e) {}
  }
  if (scannerStream) {
    scannerStream.getTracks().forEach(t => t.stop());
    scannerStream = null;
  }
}

// Decode Barcode from iOS Camera Photo Snap (Multi-Scale Canvas + ZXing + BarcodeDetector)
async function decodeBarcodeFromImageFile(file) {
  if (!file) return;
  showToast('📸 Decoding barcode from photo...');

  const imgUrl = URL.createObjectURL(file);
  const img = new Image();
  img.src = imgUrl;
  await new Promise((resolve, reject) => {
    img.onload = resolve;
    img.onerror = reject;
  });

  // 1. Try native BarcodeDetector first if supported
  if ('BarcodeDetector' in window) {
    try {
      const detector = new window.BarcodeDetector({
        formats: ['ean_13', 'ean_8', 'upc_a', 'upc_e', 'code_128', 'code_39']
      });
      const hits = await detector.detect(img);
      if (hits && hits.length > 0 && hits[0].rawValue) {
        URL.revokeObjectURL(imgUrl);
        await handleScannedBarcode(hits[0].rawValue);
        return;
      }
    } catch (e) {}
  }

  // 2. Try ZXing across multiple scales/crops so high-res 12MP/48MP iPhone photos decode cleanly
  if (window.ZXing && window.ZXing.BrowserMultiFormatReader) {
    const reader = new window.ZXing.BrowserMultiFormatReader();
    const scales = [1000, 1400, 720];
    for (const maxDim of scales) {
      try {
        const canvas = document.createElement('canvas');
        const ratio = Math.min(1, maxDim / Math.max(img.width, img.height));
        canvas.width = Math.round(img.width * ratio);
        canvas.height = Math.round(img.height * ratio);
        const ctx = canvas.getContext('2d');
        ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
        const dataUrl = canvas.toDataURL('image/jpeg', 0.92);
        const res = await reader.decodeFromImageUrl(dataUrl);
        if (res && res.getText()) {
          URL.revokeObjectURL(imgUrl);
          await handleScannedBarcode(res.getText());
          return;
        }
      } catch (e) {}
    }
  }

  URL.revokeObjectURL(imgUrl);
  showToast('Could not read barcode clearly — try closer or type digits');
  document.getElementById('barcode-search-input').focus();
}

// Custom Food Modal
function openCustomFoodModal(prefill = {}) {
  document.getElementById('cf-name').value = prefill.name || '';
  document.getElementById('cf-brand').value = prefill.brand || '';
  document.getElementById('cf-barcode').value = prefill.barcode || '';
  document.getElementById('cf-serving').value = prefill.servingG || 100;
  document.getElementById('cf-carbs100').value = prefill.carbs100 ?? '';
  document.getElementById('cf-fiber100').value = prefill.fiber100 ?? 0;
  document.getElementById('cf-sugar100').value = prefill.sugar100 ?? 0;
  document.getElementById('cf-kcal100').value = prefill.kcal100 ?? 0;
  document.getElementById('cf-protein100').value = prefill.protein100 ?? 0;
  document.getElementById('cf-fat100').value = prefill.fat100 ?? 0;
  document.getElementById('modal-custom-food').classList.add('open');
}

// Save Batch Prep Modal
function openSavePrepModal() {
  if (currentMeal.length === 0) {
    showToast('Add at least 1 ingredient to your meal first');
    return;
  }
  const totals = calcMacrosForItems(currentMeal);
  document.getElementById('prep-cooked-weight-input').placeholder = `Raw sum: ${Math.round(totals.rawWeight)}g`;
  updatePrepModalPreview();
  document.getElementById('modal-save-prep').classList.add('open');
}

function updatePrepModalPreview() {
  const totals = calcMacrosForItems(currentMeal);
  const portions = Math.max(1, parseInt(document.getElementById('prep-portions-input').value, 10) || 1);
  const cPortion = totals.carbs / portions;
  const ncPortion = totals.netCarbs / portions;
  const uPortion = calculateBolusUnits(cPortion, ncPortion);
  document.getElementById('prep-modal-preview').textContent =
    `${cPortion.toFixed(1)}g Carbs (${ncPortion.toFixed(1)}g Net) • 💉 ${uPortion.toFixed(1)}u / tub`;
}

// Tab Navigation
function switchTab(tabId) {
  document.querySelectorAll('.tab-view').forEach(s => s.classList.toggle('active', s.id === tabId));
  document.querySelectorAll('.tab-bar .tab-btn').forEach(b => b.classList.toggle('active', b.dataset.tab === tabId));
  if (tabId !== 'tab-meal') stopLiveScanner();
}

function round1(val) {
  const n = Number(val);
  return isNaN(n) ? 0 : Math.round(n * 10) / 10;
}

function escapeHtml(str) {
  return String(str || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

// Initialize Settings UI
function populateSettingsUI() {
  document.getElementById('set-icr').value = settings.icr;
  document.getElementById('set-carb-basis').value = settings.carbBasis;
  document.getElementById('set-bg-unit').value = settings.bgUnit;
  document.getElementById('set-target-bg').value = settings.targetBg;
  document.getElementById('set-isf').value = settings.isf;
  document.getElementById('set-rounding').value = String(settings.rounding);
}

// DOM Event Listeners
document.addEventListener('DOMContentLoaded', () => {
  loadState();
  populateSettingsUI();
  renderCurrentMeal();
  renderPreppedMeals();
  renderFoodLibrary();

  // Tab bar buttons
  document.querySelectorAll('.tab-bar .tab-btn').forEach(btn => {
    btn.addEventListener('click', () => switchTab(btn.dataset.tab));
  });

  // Header ratio shortcut
  document.getElementById('btn-header-ratio').addEventListener('click', () => {
    switchTab('tab-settings');
  });

  // BG Input live bolus update
  document.getElementById('current-bg-input').addEventListener('input', () => {
    renderCurrentMeal();
  });

  // Scanner buttons
  document.getElementById('btn-live-scan').addEventListener('click', () => {
    if (isScannerActive) stopLiveScanner();
    else startLiveScanner();
  });
  document.getElementById('btn-close-scanner').addEventListener('click', stopLiveScanner);

  document.getElementById('btn-snap-scan').addEventListener('click', () => {
    document.getElementById('camera-snap-input').click();
  });
  document.getElementById('camera-snap-input').addEventListener('change', (e) => {
    if (e.target.files && e.target.files[0]) {
      decodeBarcodeFromImageFile(e.target.files[0]);
      e.target.value = '';
    }
  });

  // Barcode / Food Lookup
  document.getElementById('btn-lookup-barcode').addEventListener('click', () => {
    lookupBarcodeOrSearch(document.getElementById('barcode-search-input').value);
  });
  document.getElementById('barcode-search-input').addEventListener('keydown', (e) => {
    if (e.key === 'Enter') lookupBarcodeOrSearch(e.target.value);
  });

  // Clear Meal & Custom Inline
  document.getElementById('btn-clear-meal').addEventListener('click', () => {
    currentMeal = [];
    saveState();
    renderCurrentMeal();
    showToast('Meal cleared');
  });
  document.getElementById('btn-add-custom-inline').addEventListener('click', () => openCustomFoodModal());
  document.getElementById('btn-new-custom-food').addEventListener('click', () => openCustomFoodModal());

  // Custom Food Modal
  document.getElementById('btn-close-food-modal').addEventListener('click', () => {
    document.getElementById('modal-custom-food').classList.remove('open');
  });
  document.getElementById('btn-save-custom-food').addEventListener('click', () => {
    const name = document.getElementById('cf-name').value.trim();
    const carbs100 = parseFloat(document.getElementById('cf-carbs100').value);
    if (!name || isNaN(carbs100)) {
      showToast('Please enter a food name and carbs per 100g');
      return;
    }
    const newFood = {
      id: 'custom_' + Date.now(),
      name,
      brand: document.getElementById('cf-brand').value.trim() || 'Custom',
      barcode: document.getElementById('cf-barcode').value.trim(),
      servingG: parseFloat(document.getElementById('cf-serving').value) || 100,
      carbs100: round1(carbs100),
      fiber100: round1(document.getElementById('cf-fiber100').value),
      sugar100: round1(document.getElementById('cf-sugar100').value),
      kcal100: Math.round(parseFloat(document.getElementById('cf-kcal100').value) || 0),
      protein100: round1(document.getElementById('cf-protein100').value),
      fat100: round1(document.getElementById('cf-fat100').value)
    };
    rememberFoodInLibrary(newFood);
    addFoodItemToCurrentMeal(newFood);
    document.getElementById('modal-custom-food').classList.remove('open');
  });

  // Save Prep Modal
  document.getElementById('btn-open-save-prep').addEventListener('click', openSavePrepModal);
  document.getElementById('btn-new-prep-direct').addEventListener('click', () => {
    if (currentMeal.length === 0) {
      switchTab('tab-meal');
      showToast('Scan or add batch ingredients first, then tap Save as Prepped Batch!');
    } else {
      openSavePrepModal();
    }
  });
  document.getElementById('btn-close-prep-modal').addEventListener('click', () => {
    document.getElementById('modal-save-prep').classList.remove('open');
  });
  document.getElementById('prep-portions-input').addEventListener('input', updatePrepModalPreview);

  document.getElementById('btn-confirm-save-prep').addEventListener('click', () => {
    const name = document.getElementById('prep-name-input').value.trim() || `Meal Prep (${new Date().toLocaleDateString()})`;
    const portions = Math.max(1, parseInt(document.getElementById('prep-portions-input').value, 10) || 4);
    const cookedW = parseFloat(document.getElementById('prep-cooked-weight-input').value) || 0;
    const notes = document.getElementById('prep-notes-input').value.trim();

    preppedMeals.unshift({
      id: 'prep_' + Date.now(),
      name,
      notes,
      portionsTotal: portions,
      portionsLeft: portions,
      cookedWeightG: cookedW,
      createdAt: new Date().toISOString(),
      items: JSON.parse(JSON.stringify(currentMeal))
    });

    saveState();
    renderPreppedMeals();
    document.getElementById('modal-save-prep').classList.remove('open');
    document.getElementById('prep-name-input').value = '';
    document.getElementById('prep-cooked-weight-input').value = '';
    document.getElementById('prep-notes-input').value = '';
    switchTab('tab-preps');
    showToast(`Saved "${name}" (${portions} tubs)`);
  });

  // Food Library Filter
  document.getElementById('food-lib-filter').addEventListener('input', renderFoodLibrary);

  // Insulin Settings
  document.getElementById('preset-breakfast').addEventListener('click', () => {
    document.getElementById('set-icr').value = 8;
    settings.icr = 8;
    saveState();
    renderCurrentMeal();
    renderPreppedMeals();
    showToast('Breakfast Ratio 1u : 8g active');
  });
  document.getElementById('preset-lunch').addEventListener('click', () => {
    document.getElementById('set-icr').value = 10;
    settings.icr = 10;
    saveState();
    renderCurrentMeal();
    renderPreppedMeals();
    showToast('Lunch Ratio 1u : 10g active');
  });
  document.getElementById('preset-dinner').addEventListener('click', () => {
    document.getElementById('set-icr').value = 10;
    settings.icr = 10;
    saveState();
    renderCurrentMeal();
    renderPreppedMeals();
    showToast('Dinner Ratio 1u : 10g active');
  });

  document.getElementById('btn-save-settings').addEventListener('click', () => {
    settings.icr = Math.max(0.5, parseFloat(document.getElementById('set-icr').value) || 10);
    settings.carbBasis = document.getElementById('set-carb-basis').value;
    settings.bgUnit = document.getElementById('set-bg-unit').value;
    settings.targetBg = parseFloat(document.getElementById('set-target-bg').value) || 5.5;
    settings.isf = parseFloat(document.getElementById('set-isf').value) || 2.5;
    settings.rounding = parseFloat(document.getElementById('set-rounding').value) || 0.5;
    saveState();
    renderCurrentMeal();
    renderPreppedMeals();
    showToast('Insulin & Carb settings saved!');
  });

  // Export & Import JSON Backup
  document.getElementById('btn-export-data').addEventListener('click', () => {
    const payload = {
      exportedAt: new Date().toISOString(),
      settings,
      preppedMeals,
      foodLibrary
    };
    const blob = new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `CarbPrep-Backup-${new Date().toISOString().slice(0, 10)}.json`;
    a.click();
    URL.revokeObjectURL(url);
    showToast('Backup JSON exported!');
  });

  document.getElementById('btn-import-data').addEventListener('click', () => {
    document.getElementById('import-json-input').click();
  });

  document.getElementById('import-json-input').addEventListener('change', (e) => {
    const file = e.target.files && e.target.files[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = () => {
      try {
        const data = JSON.parse(String(reader.result));
        if (Array.isArray(data.preppedMeals)) preppedMeals = data.preppedMeals;
        if (Array.isArray(data.foodLibrary)) foodLibrary = data.foodLibrary;
        if (data.settings) settings = { ...settings, ...data.settings };
        saveState();
        populateSettingsUI();
        renderCurrentMeal();
        renderPreppedMeals();
        renderFoodLibrary();
        showToast('Backup restored successfully!');
      } catch (err) {
        showToast('Invalid JSON backup file');
      }
    };
    reader.readAsText(file);
    e.target.value = '';
  });

  // Register Service Worker for offline PWA use
  if ('serviceWorker' in navigator && location.protocol.startsWith('http')) {
    navigator.serviceWorker.register('sw.js').catch(() => {});
  }
});
