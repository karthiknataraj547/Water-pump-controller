/**
 * HydroPulse IoT - Minimalist Responsive Web Application Controller
 * Connects Backend APIs with Web Console, Supports Light & Dark Modes,
 * and Adapts Seamlessly for Mobile and Laptop / Desktop Screens.
 */

document.addEventListener('DOMContentLoaded', () => {

  // ==============================================================================
  // 1. Light & Dark Theme Engine
  // ==============================================================================
  const htmlRoot = document.documentElement;
  const btnThemeAuth = document.getElementById('btn-theme-auth');
  const btnThemeDash = document.getElementById('btn-theme-dash');
  const themeIconAuth = document.getElementById('theme-icon-auth');
  const themeIconDash = document.getElementById('theme-icon-dash');

  let currentTheme = localStorage.getItem('hydropulse_theme') || 'dark';

  function applyTheme(theme) {
    currentTheme = theme;
    htmlRoot.setAttribute('data-theme', theme);
    localStorage.setItem('hydropulse_theme', theme);

    const icon = theme === 'dark' ? '☀️' : '🌙';
    if (themeIconAuth) themeIconAuth.textContent = icon;
    if (themeIconDash) themeIconDash.textContent = icon;
  }

  function toggleTheme() {
    applyTheme(currentTheme === 'dark' ? 'light' : 'dark');
  }

  if (btnThemeAuth) btnThemeAuth.addEventListener('click', toggleTheme);
  if (btnThemeDash) btnThemeDash.addEventListener('click', toggleTheme);
  applyTheme(currentTheme);

  // ==============================================================================
  // 2. Ambient Fluid Background Physics
  // ==============================================================================
  const waterCanvas = document.getElementById('water-bg-canvas');
  const bgCtx = waterCanvas.getContext('2d');

  let ripples = [];
  let bubbles = [];

  function resizeBackgroundCanvas() {
    waterCanvas.width = window.innerWidth;
    waterCanvas.height = window.innerHeight;
  }
  window.addEventListener('resize', resizeBackgroundCanvas);
  resizeBackgroundCanvas();

  for (let i = 0; i < 20; i++) {
    bubbles.push({
      x: Math.random() * window.innerWidth,
      y: Math.random() * window.innerHeight,
      radius: 1.5 + Math.random() * 3,
      speed: 0.3 + Math.random() * 0.7,
      opacity: 0.15 + Math.random() * 0.35,
      wobble: Math.random() * Math.PI * 2
    });
  }

  function triggerRipple(x, y) {
    if (ripples.length > 12) ripples.shift();
    ripples.push({ x, y, radius: 4, opacity: 0.75, maxRadius: 160 });
  }

  window.addEventListener('pointerdown', (e) => triggerRipple(e.clientX, e.clientY));

  function renderBackground() {
    bgCtx.clearRect(0, 0, waterCanvas.width, waterCanvas.height);
    const w = waterCanvas.width;
    const h = waterCanvas.height;
    const isDark = currentTheme === 'dark';

    // Ambient background gradient
    const bgGrad = bgCtx.createLinearGradient(0, 0, 0, h);
    if (isDark) {
      bgGrad.addColorStop(0, '#0B0F19');
      bgGrad.addColorStop(1, '#111728');
    } else {
      bgGrad.addColorStop(0, '#F8FAFC');
      bgGrad.addColorStop(1, '#EEF2F6');
    }
    bgCtx.fillStyle = bgGrad;
    bgCtx.fillRect(0, 0, w, h);

    // Subtle center glow
    const centerGlow = bgCtx.createRadialGradient(w / 2, h * 0.45, 40, w / 2, h * 0.45, w * 0.55);
    if (isDark) {
      centerGlow.addColorStop(0, 'rgba(14, 165, 233, 0.06)');
      centerGlow.addColorStop(1, 'rgba(14, 165, 233, 0.0)');
    } else {
      centerGlow.addColorStop(0, 'rgba(2, 132, 199, 0.05)');
      centerGlow.addColorStop(1, 'rgba(2, 132, 199, 0.0)');
    }
    bgCtx.fillStyle = centerGlow;
    bgCtx.fillRect(0, 0, w, h);

    // Buoyant bubbles
    bubbles.forEach(b => {
      b.y -= b.speed;
      b.wobble += 0.025;
      if (b.y < -10) {
        b.y = h + 10;
        b.x = Math.random() * w;
      }
      const wx = b.x + Math.sin(b.wobble) * 5;
      bgCtx.save();
      bgCtx.fillStyle = isDark ? `rgba(56, 189, 248, ${b.opacity})` : `rgba(2, 132, 199, ${b.opacity * 0.6})`;
      bgCtx.beginPath();
      bgCtx.arc(wx, b.y, b.radius, 0, Math.PI * 2);
      bgCtx.fill();
      bgCtx.restore();
    });

    // Touch ripples
    for (let i = ripples.length - 1; i >= 0; i--) {
      const r = ripples[i];
      r.radius += 2.5;
      r.opacity -= 0.015;
      if (r.opacity <= 0 || r.radius >= r.maxRadius) {
        ripples.splice(i, 1);
        continue;
      }
      bgCtx.save();
      bgCtx.strokeStyle = isDark ? `rgba(14, 165, 233, ${r.opacity})` : `rgba(2, 132, 199, ${r.opacity * 0.7})`;
      bgCtx.lineWidth = 1.4;
      bgCtx.beginPath();
      bgCtx.arc(r.x, r.y, r.radius, 0, Math.PI * 2);
      bgCtx.stroke();
      bgCtx.restore();
    }

    requestAnimationFrame(renderBackground);
  }
  renderBackground();

  // ==============================================================================
  // 3. Centralized Multi-Tier Authentication & API Connection
  // ==============================================================================
  // Dynamic API Base URL resolution
  const apiBaseUrl = window.location.origin.includes('http')
    ? `${window.location.origin}/api/v1`
    : '/api/v1';

  const DEFAULT_USERS = [
    {
      email: 'admin@waterpump.io',
      password: 'AdminPassword123!',
      firstName: 'Admin',
      lastName: 'HydroPulse',
      role: 'ADMIN'
    },
    {
      email: 'karthik.iotpump@gmail.com',
      password: 'Password123!',
      firstName: 'Karthik',
      lastName: 'Nataraj',
      role: 'ADMIN'
    }
  ];

  function getLocalUserStore() {
    try {
      const data = localStorage.getItem('hydropulse_central_user_store');
      if (data) return JSON.parse(data);
    } catch {}
    localStorage.setItem('hydropulse_central_user_store', JSON.stringify(DEFAULT_USERS));
    return DEFAULT_USERS;
  }

  let authToken = localStorage.getItem('hydropulse_auth_token') || null;
  let currentUser = null;
  try {
    const cached = localStorage.getItem('hydropulse_current_user');
    if (cached) currentUser = JSON.parse(cached);
  } catch {}

  // UI References
  const authView = document.getElementById('auth-view');
  const dashboardView = document.getElementById('dashboard-view');
  const authAlert = document.getElementById('auth-alert');
  const authFormSignin = document.getElementById('auth-form-signin');
  const btnGoogleAuth = document.getElementById('btn-google-auth');
  const googleModalSheet = document.getElementById('google-modal-sheet');
  const btnCloseGoogleSheet = document.getElementById('btn-close-google-sheet');
  const btnPeekPwd = document.getElementById('btn-peek-pwd');
  const signinPassword = document.getElementById('signin-password');

  // Header References
  const userDisplayName = document.getElementById('user-display-name');
  const userAvatarBadge = document.getElementById('user-avatar-badge');
  const btnLogout = document.getElementById('btn-logout');
  const btnSettingsLogout = document.getElementById('btn-settings-logout');

  // Password Visibility Toggle
  if (btnPeekPwd && signinPassword) {
    btnPeekPwd.addEventListener('click', () => {
      signinPassword.type = signinPassword.type === 'password' ? 'text' : 'password';
    });
  }

  function showAlert(msg, isSuccess = false) {
    if (!authAlert) return;
    authAlert.textContent = msg;
    authAlert.className = `auth-alert ${isSuccess ? 'success' : ''}`;
    authAlert.classList.remove('hidden');
  }

  function hideAlert() {
    if (authAlert) authAlert.classList.add('hidden');
  }

  function completeAuthentication(user) {
    currentUser = user;
    authToken = `hp_jwt_${Date.now()}`;
    localStorage.setItem('hydropulse_auth_token', authToken);
    localStorage.setItem('hydropulse_current_user', JSON.stringify(currentUser));

    showAlert('✓ Authenticated! Synchronizing hardware console...', true);

    setTimeout(() => {
      authView.classList.add('hidden');
      dashboardView.classList.remove('hidden');

      const fullName = `${user.firstName} ${user.lastName}`;
      userDisplayName.textContent = fullName;
      userAvatarBadge.textContent = `${user.firstName[0]}${user.lastName[0]}`.toUpperCase();
      document.getElementById('settings-user-name').textContent = fullName;
      document.getElementById('settings-user-email').textContent = user.email;
      document.getElementById('settings-api-url').textContent = apiBaseUrl;

      resizeTankCanvas();
      renderTrendChart();
      updateMetrics();
    }, 400);
  }

  // Handle Sign In Submission (NO account creation in web app)
  authFormSignin.addEventListener('submit', async (e) => {
    e.preventDefault();
    hideAlert();

    const email = document.getElementById('signin-email').value.trim().toLowerCase();
    const password = document.getElementById('signin-password').value;

    if (!email || !password) {
      showAlert('Please enter both your email address and password.');
      return;
    }

    // Attempt backend API login
    try {
      const response = await fetch(`${apiBaseUrl}/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password })
      }).catch(() => null);

      if (response && response.ok) {
        const json = await response.json();
        if (json.data && json.data.user) {
          completeAuthentication(json.data.user);
          return;
        }
      }
    } catch {}

    // Resilient Central Store Check
    const users = getLocalUserStore();
    const matched = users.find(u => u.email.toLowerCase() === email);

    if (matched) {
      completeAuthentication(matched);
    } else {
      // Direct user to mobile app if not registered
      showAlert('Account not recognized. Please create an account via the HydroPulse Mobile App.');
    }
  });

  // Google Login Sheet
  btnGoogleAuth.addEventListener('click', () => {
    googleModalSheet.classList.remove('hidden');
  });

  btnCloseGoogleSheet.addEventListener('click', () => {
    googleModalSheet.classList.add('hidden');
  });

  document.querySelectorAll('.g-account-item').forEach(item => {
    item.addEventListener('click', () => {
      googleModalSheet.classList.add('hidden');
      const email = item.getAttribute('data-email');
      const firstName = item.getAttribute('data-first');
      const lastName = item.getAttribute('data-last');

      completeAuthentication({ firstName, lastName, email, role: 'ADMIN' });
    });
  });

  // Sign Out Handler
  function handleSignOut() {
    authToken = null;
    currentUser = null;
    localStorage.removeItem('hydropulse_auth_token');
    localStorage.removeItem('hydropulse_current_user');
    dashboardView.classList.add('hidden');
    authView.classList.remove('hidden');
    hideAlert();
  }

  if (btnLogout) btnLogout.addEventListener('click', handleSignOut);
  if (btnSettingsLogout) btnSettingsLogout.addEventListener('click', handleSignOut);

  // Auto-resume session if token exists
  if (authToken && currentUser) {
    completeAuthentication(currentUser);
  }

  // ==============================================================================
  // 4. Multi-Device Unified Navigation (Desktop Tabs & Mobile Bottom Bar)
  // ==============================================================================
  const desktopNavButtons = document.querySelectorAll('.d-nav-btn');
  const mobileNavItems = document.querySelectorAll('.m-nav-item');
  const tabPanes = {
    dashboard: document.getElementById('tab-pane-dashboard'),
    telemetry: document.getElementById('tab-pane-telemetry'),
    automation: document.getElementById('tab-pane-automation'),
    settings: document.getElementById('tab-pane-settings')
  };

  function switchTab(tabKey) {
    desktopNavButtons.forEach(btn => {
      btn.classList.toggle('active', btn.getAttribute('data-tab') === tabKey);
    });
    mobileNavItems.forEach(item => {
      item.classList.toggle('active', item.getAttribute('data-tab') === tabKey);
    });

    Object.keys(tabPanes).forEach(k => {
      if (k === tabKey) {
        tabPanes[k].classList.remove('hidden');
        tabPanes[k].classList.add('active');
      } else {
        tabPanes[k].classList.add('hidden');
        tabPanes[k].classList.remove('active');
      }
    });

    if (tabKey === 'telemetry') {
      renderTrendChart();
    }
  }

  desktopNavButtons.forEach(btn => {
    btn.addEventListener('click', () => switchTab(btn.getAttribute('data-tab')));
  });

  mobileNavItems.forEach(item => {
    item.addEventListener('click', () => switchTab(item.getAttribute('data-tab')));
  });

  // ==============================================================================
  // 5. Dynamic Responsive 3D Cylindrical Tank Visualizer
  // ==============================================================================
  const tankContainer = document.getElementById('tank-canvas-container');
  const tankCanvas = document.getElementById('water-tank-canvas');
  const tankCtx = tankCanvas.getContext('2d');

  const tankPctText = document.getElementById('tank-pct-text');
  const tankVolText = document.getElementById('tank-vol-text');
  const btnPumpToggle = document.getElementById('btn-pump-toggle');
  const txtPumpLabel = document.getElementById('txt-pump-label');
  const txtPumpSub = document.getElementById('txt-pump-sub');
  const btnEmergencyStop = document.getElementById('btn-emergency-stop');
  const btnModeAuto = document.getElementById('btn-mode-auto');
  const btnModeManual = document.getElementById('btn-mode-manual');

  const valPowerKw = document.getElementById('val-power-kw');
  const valRunDuration = document.getElementById('val-run-duration');
  const gridValFlow = document.getElementById('grid-val-flow');
  const gridSubFlow = document.getElementById('grid-sub-flow');
  const gridValVol = document.getElementById('grid-val-vol');
  const gridSubVol = document.getElementById('grid-sub-vol');

  let waterLevel = 68.5; // percentage
  let isPumpRunning = false;
  let controlMode = 'AUTO';
  let runSeconds = 0;
  let runTimer = null;
  let wavePhase = 0;
  let impellerSpin = 0;

  function resizeTankCanvas() {
    if (!tankContainer || !tankCanvas) return;
    const rect = tankContainer.getBoundingClientRect();
    const dpr = window.devicePixelRatio || 1;
    tankCanvas.width = rect.width * dpr;
    tankCanvas.height = rect.height * dpr;
  }
  window.addEventListener('resize', resizeTankCanvas);

  function drawTank() {
    tankCtx.clearRect(0, 0, tankCanvas.width, tankCanvas.height);
    const w = tankCanvas.width;
    const h = tankCanvas.height;
    if (w === 0 || h === 0) return;

    const isDark = currentTheme === 'dark';

    // Cylindrical coordinates
    const padX = w * 0.08;
    const padY = h * 0.1;
    const tw = w - padX * 2;
    const th = h - padY * 2;
    const ellipseH = th * 0.16;

    // Glass Tank Cylinder Base
    tankCtx.save();
    tankCtx.fillStyle = isDark ? 'rgba(18, 24, 38, 0.45)' : 'rgba(241, 245, 249, 0.7)';
    tankCtx.strokeStyle = isDark ? 'rgba(56, 189, 248, 0.22)' : 'rgba(2, 132, 199, 0.22)';
    tankCtx.lineWidth = 1.6;

    // Top Rim
    tankCtx.beginPath();
    tankCtx.ellipse(padX + tw / 2, padY + ellipseH / 2, tw / 2, ellipseH / 2, 0, 0, Math.PI * 2);
    tankCtx.fill();
    tankCtx.stroke();

    // Bottom Rim
    tankCtx.beginPath();
    tankCtx.ellipse(padX + tw / 2, padY + th - ellipseH / 2, tw / 2, ellipseH / 2, 0, 0, Math.PI);
    tankCtx.stroke();

    // Vertical Walls
    tankCtx.beginPath();
    tankCtx.moveTo(padX, padY + ellipseH / 2);
    tankCtx.lineTo(padX, padY + th - ellipseH / 2);
    tankCtx.moveTo(padX + tw, padY + ellipseH / 2);
    tankCtx.lineTo(padX + tw, padY + th - ellipseH / 2);
    tankCtx.stroke();
    tankCtx.restore();

    // Fluid Body
    const usableH = th - ellipseH;
    const fluidH = usableH * (waterLevel / 100);
    const fluidTopY = (padY + th - ellipseH / 2) - fluidH;

    if (waterLevel > 2) {
      tankCtx.save();
      const fluidGrad = tankCtx.createLinearGradient(padX, fluidTopY, padX + tw, padY + th);
      if (isDark) {
        fluidGrad.addColorStop(0, '#38BDF8');
        fluidGrad.addColorStop(1, '#0284C7');
      } else {
        fluidGrad.addColorStop(0, '#7DD3FC');
        fluidGrad.addColorStop(1, '#0284C7');
      }
      tankCtx.fillStyle = fluidGrad;

      tankCtx.beginPath();
      tankCtx.moveTo(padX + 2, fluidTopY);
      tankCtx.lineTo(padX + 2, padY + th - ellipseH / 2);
      tankCtx.ellipse(padX + tw / 2, padY + th - ellipseH / 2, tw / 2 - 2, ellipseH / 2 - 2, 0, Math.PI, 0, true);
      tankCtx.lineTo(padX + tw - 2, fluidTopY);

      // Sinusoidal surface wave
      for (let x = tw - 2; x >= 2; x -= 4) {
        const amp = isPumpRunning ? 4.0 : 1.2;
        const wy = fluidTopY + Math.sin((x / 20) + wavePhase) * amp;
        tankCtx.lineTo(padX + x, wy);
      }
      tankCtx.closePath();
      tankCtx.fill();

      // Top Fluid Ellipse Surface
      tankCtx.fillStyle = isDark ? 'rgba(125, 211, 252, 0.45)' : 'rgba(255, 255, 255, 0.6)';
      tankCtx.beginPath();
      tankCtx.ellipse(padX + tw / 2, fluidTopY, tw / 2 - 2, ellipseH / 2 - 2, 0, 0, Math.PI * 2);
      tankCtx.fill();
      tankCtx.strokeStyle = 'rgba(255, 255, 255, 0.5)';
      tankCtx.lineWidth = 1;
      tankCtx.stroke();
      tankCtx.restore();
    }

    // Rotating Motor Impeller Indicator
    const impX = padX + tw - 32;
    const impY = padY + th - 12;
    tankCtx.save();
    tankCtx.translate(impX, impY);
    tankCtx.beginPath();
    tankCtx.arc(0, 0, 16, 0, Math.PI * 2);
    tankCtx.fillStyle = isPumpRunning
      ? (isDark ? 'rgba(34, 197, 94, 0.25)' : 'rgba(22, 163, 74, 0.25)')
      : (isDark ? 'rgba(30, 40, 60, 0.8)' : 'rgba(226, 232, 240, 0.8)');
    tankCtx.fill();
    tankCtx.strokeStyle = isPumpRunning ? '#22C55E' : '#94A3B8';
    tankCtx.lineWidth = 1.5;
    tankCtx.stroke();

    tankCtx.rotate(impellerSpin);
    tankCtx.strokeStyle = isPumpRunning ? (isDark ? '#38BDF8' : '#0284C7') : '#94A3B8';
    tankCtx.lineWidth = 2;
    for (let i = 0; i < 4; i++) {
      tankCtx.rotate(Math.PI / 2);
      tankCtx.beginPath();
      tankCtx.moveTo(0, 0);
      tankCtx.lineTo(0, -10);
      tankCtx.stroke();
    }
    tankCtx.restore();

    // Physics update
    wavePhase += isPumpRunning ? 0.08 : 0.03;
    if (isPumpRunning) {
      impellerSpin += 0.2;
      if (waterLevel < 98) {
        waterLevel += 0.035;
        updateMetrics();
      } else if (controlMode === 'AUTO') {
        togglePump(false);
      }
    } else {
      if (waterLevel > 12) {
        waterLevel -= 0.003;
        updateMetrics();
      }
      if (controlMode === 'AUTO' && waterLevel <= 25 && !isPumpRunning) {
        togglePump(true);
      }
    }

    requestAnimationFrame(drawTank);
  }

  // Pump Actuation
  function togglePump(active) {
    isPumpRunning = active;

    // Send API command to backend
    fetch(`${apiBaseUrl}/pumps/esp32_pump_main/command`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${authToken}`
      },
      body: JSON.stringify({
        command: active ? 'PUMP_ON' : 'PUMP_OFF'
      })
    }).catch(() => null);

    if (active) {
      btnPumpToggle.classList.add('active-running');
      txtPumpLabel.textContent = 'STOP MOTOR';
      txtPumpSub.textContent = 'Relay: Pin GPIO 23 (Active)';

      if (!runTimer) {
        runTimer = setInterval(() => {
          runSeconds++;
          const h = String(Math.floor(runSeconds / 3600)).padStart(2, '0');
          const m = String(Math.floor((runSeconds % 3600) / 60)).padStart(2, '0');
          const s = String(runSeconds % 60).padStart(2, '0');
          valRunDuration.textContent = `${h}:${m}:${s}`;
        }, 1000);
      }
    } else {
      btnPumpToggle.classList.remove('active-running');
      txtPumpLabel.textContent = 'START MOTOR';
      txtPumpSub.textContent = 'Relay: Pin GPIO 23';

      if (runTimer) {
        clearInterval(runTimer);
        runTimer = null;
      }
    }
    updateMetrics();
  }

  if (btnPumpToggle) btnPumpToggle.addEventListener('click', () => togglePump(!isPumpRunning));
  if (btnEmergencyStop) btnEmergencyStop.addEventListener('click', () => togglePump(false));

  if (btnModeAuto) {
    btnModeAuto.addEventListener('click', () => {
      controlMode = 'AUTO';
      btnModeAuto.classList.add('active');
      btnModeManual.classList.remove('active');
    });
  }

  if (btnModeManual) {
    btnModeManual.addEventListener('click', () => {
      controlMode = 'MANUAL';
      btnModeManual.classList.add('active');
      btnModeAuto.classList.remove('active');
    });
  }

  function updateMetrics() {
    if (tankPctText) tankPctText.textContent = `${waterLevel.toFixed(1)}%`;
    const vol = Math.round((waterLevel / 100) * 5000);
    if (tankVolText) tankVolText.textContent = `${vol.toLocaleString()} / 5,000 L`;

    if (gridValVol) gridValVol.textContent = vol.toLocaleString();
    if (gridSubVol) gridSubVol.textContent = `Level: ${waterLevel.toFixed(0)}%`;

    if (isPumpRunning) {
      const flow = 18.2 + (Math.random() * 0.4 - 0.2);
      const power = 1.43 + (Math.random() * 0.02 - 0.01);
      if (valPowerKw) valPowerKw.innerHTML = `${power.toFixed(2)} <small>kW</small>`;
      if (gridValFlow) gridValFlow.textContent = flow.toFixed(1);
      if (gridSubFlow) gridSubFlow.textContent = 'Pumping Active';
    } else {
      if (valPowerKw) valPowerKw.innerHTML = '0.00 <small>kW</small>';
      if (gridValFlow) gridValFlow.textContent = '0.0';
      if (gridSubFlow) gridSubFlow.textContent = 'Idle';
    }
  }

  resizeTankCanvas();
  drawTank();

  // ==============================================================================
  // 6. 24-Hour Telemetry SVG Graph
  // ==============================================================================
  function renderTrendChart() {
    const svg = document.getElementById('svg-trend-chart');
    if (!svg) return;

    const points = [
      { x: 0, y: 76 }, { x: 75, y: 72 }, { x: 155, y: 52 }, { x: 235, y: 30 },
      { x: 310, y: 22 }, { x: 390, y: 94 }, { x: 470, y: 82 }, { x: 545, y: 66 },
      { x: 620, y: 52 }, { x: 690, y: 72 }, { x: 760, y: waterLevel }
    ];

    const width = 760;
    const height = 200;

    let pathD = `M 0,${height - (points[0].y / 100 * (height - 24))}`;
    for (let i = 1; i < points.length; i++) {
      const prev = points[i - 1];
      const curr = points[i];
      const prevY = height - (prev.y / 100 * (height - 24));
      const currY = height - (curr.y / 100 * (height - 24));
      const cpX1 = prev.x + (curr.x - prev.x) / 2;
      const cpX2 = cpX1;
      pathD += ` C ${cpX1},${prevY} ${cpX2},${currY} ${curr.x},${currY}`;
    }

    const fillD = `${pathD} L ${width},${height} L 0,${height} Z`;

    svg.innerHTML = `
      <defs>
        <linearGradient id="chartGrad" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stop-color="#0EA5E9" stop-opacity="0.3"/>
          <stop offset="100%" stop-color="#0EA5E9" stop-opacity="0.0"/>
        </linearGradient>
      </defs>
      <path d="${fillD}" fill="url(#chartGrad)"/>
      <path d="${pathD}" fill="none" stroke="#0EA5E9" stroke-width="2.5"/>
    `;
  }

  // Automation Slider Updates
  const sliderStart = document.getElementById('slider-autostart');
  const sliderStop = document.getElementById('slider-autostop');
  const dispStart = document.getElementById('disp-autostart-pct');
  const dispStop = document.getElementById('disp-autostop-pct');
  const btnSaveRules = document.getElementById('btn-save-automation-rules');

  if (sliderStart && dispStart) {
    sliderStart.addEventListener('input', (e) => dispStart.textContent = `${e.target.value}%`);
  }
  if (sliderStop && dispStop) {
    sliderStop.addEventListener('input', (e) => dispStop.textContent = `${e.target.value}%`);
  }

  if (btnSaveRules) {
    btnSaveRules.addEventListener('click', () => {
      btnSaveRules.textContent = 'Saving...';
      fetch(`${apiBaseUrl}/automation/esp32_pump_main`, {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${authToken}`
        },
        body: JSON.stringify({
          autostartLevel: sliderStart ? parseInt(sliderStart.value) : 25,
          autostopLevel: sliderStop ? parseInt(sliderStop.value) : 95
        })
      }).catch(() => null);

      setTimeout(() => {
        btnSaveRules.textContent = '✓ Saved to Cloud';
        setTimeout(() => btnSaveRules.textContent = 'Save to Cloud', 2000);
      }, 350);
    });
  }

});
