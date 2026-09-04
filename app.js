/**
 * HydroPulse Showcase Website - Interactive Simulator & Canvas Animations
 */

document.addEventListener('DOMContentLoaded', () => {
  // State variables
  let waterLevelPct = 68.4;
  let isPumpRunning = false;
  let systemMode = 'AUTO';
  let flowRateLpm = 0.0;
  let powerKw = 0.00;
  let runDurationSeconds = 0;
  let runtimeInterval = null;

  // DOM Elements - Hero
  const heroTankCanvas = document.getElementById('hero-tank-canvas');
  const heroLevelPct = document.getElementById('hero-level-pct');
  const heroVolumeLiters = document.getElementById('hero-volume-liters');
  const heroPumpBtn = document.getElementById('hero-pump-btn');
  const heroPumpText = document.getElementById('hero-pump-text');
  const heroModeBtn = document.getElementById('hero-mode-btn');
  const heroFlowVal = document.getElementById('hero-flow-val');
  const heroPowerVal = document.getElementById('hero-power-val');
  const heroRtt = document.getElementById('hero-rtt');

  // DOM Elements - Simulator
  const simModeAuto = document.getElementById('sim-mode-auto');
  const simModeManual = document.getElementById('sim-mode-manual');
  const simPumpAction = document.getElementById('sim-pump-action');
  const simActionLabel = document.getElementById('sim-action-label');
  const simWaterSlider = document.getElementById('sim-water-slider');
  const simLevelSliderVal = document.getElementById('sim-level-slider-val');
  const simEmergencyBtn = document.getElementById('sim-emergency-btn');
  const packetLog = document.getElementById('packet-log');
  const simFlowStat = document.getElementById('sim-flow-stat');
  const simFlowSub = document.getElementById('sim-flow-sub');
  const simRuntimeStat = document.getElementById('sim-runtime-stat');

  // ==============================================================================
  // 1. Fluid Canvas Animation (Hero Tank Visualizer)
  // ==============================================================================
  let ctx = heroTankCanvas.getContext('2d');
  let wavePhase = 0;
  let impellerAngle = 0;

  function renderHeroTank() {
    ctx.clearRect(0, 0, heroTankCanvas.width, heroTankCanvas.height);
    const w = heroTankCanvas.width;
    const h = heroTankCanvas.height;

    // Tank dimensions (Cylindrical isometric perspective)
    const tankX = 40;
    const tankY = 40;
    const tankW = w - 80;
    const tankH = h - 80;
    const ellipseH = 26;

    // 1. Draw Cylindrical Glass Shell Background
    ctx.save();
    ctx.fillStyle = 'rgba(15, 23, 42, 0.6)';
    ctx.strokeStyle = 'rgba(0, 229, 255, 0.25)';
    ctx.lineWidth = 1.5;

    // Cylinder body
    ctx.beginPath();
    ctx.ellipse(tankX + tankW / 2, tankY + ellipseH / 2, tankW / 2, ellipseH / 2, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.stroke();

    ctx.beginPath();
    ctx.ellipse(tankX + tankW / 2, tankY + tankH - ellipseH / 2, tankW / 2, ellipseH / 2, 0, 0, Math.PI);
    ctx.stroke();

    ctx.beginPath();
    ctx.moveTo(tankX, tankY + ellipseH / 2);
    ctx.lineTo(tankX, tankY + tankH - ellipseH / 2);
    ctx.moveTo(tankX + tankW, tankY + ellipseH / 2);
    ctx.lineTo(tankX + tankW, tankY + tankH - ellipseH / 2);
    ctx.stroke();
    ctx.restore();

    // 2. Draw Volumetric Water Body
    const waterHeight = (tankH - ellipseH) * (waterLevelPct / 100);
    const waterTopY = (tankY + tankH - ellipseH / 2) - waterHeight;

    if (waterLevelPct > 1) {
      ctx.save();
      const waterGrad = ctx.createLinearGradient(tankX, waterTopY, tankX + tankW, tankY + tankH);
      waterGrad.addColorStop(0, 'rgba(0, 229, 255, 0.85)');
      waterGrad.addColorStop(0.5, 'rgba(0, 180, 255, 0.7)');
      waterGrad.addColorStop(1, 'rgba(0, 245, 160, 0.9)');

      ctx.fillStyle = waterGrad;

      // Bottom water curve
      ctx.beginPath();
      ctx.moveTo(tankX + 2, waterTopY);
      ctx.lineTo(tankX + 2, tankY + tankH - ellipseH / 2);
      ctx.ellipse(tankX + tankW / 2, tankY + tankH - ellipseH / 2, tankW / 2 - 2, ellipseH / 2 - 2, 0, Math.PI, 0, true);
      ctx.lineTo(tankX + tankW - 2, waterTopY);

      // Top wavy fluid surface
      for (let x = tankW - 2; x >= 2; x -= 4) {
        const waveAmp = isPumpRunning ? 4.5 : 1.5;
        const waveY = waterTopY + Math.sin((x / 20) + wavePhase) * waveAmp;
        ctx.lineTo(tankX + x, waveY);
      }
      ctx.closePath();
      ctx.fill();

      // Top Fluid Ellipse Surface
      ctx.fillStyle = 'rgba(0, 245, 160, 0.45)';
      ctx.beginPath();
      ctx.ellipse(tankX + tankW / 2, waterTopY, tankW / 2 - 2, ellipseH / 2 - 2, 0, 0, Math.PI * 2);
      ctx.fill();
      ctx.strokeStyle = 'rgba(255, 255, 255, 0.6)';
      ctx.lineWidth = 1;
      ctx.stroke();

      ctx.restore();
    }

    // 3. Grid Rings (0%, 50%, 100%)
    ctx.save();
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.15)';
    ctx.setLineDash([4, 4]);
    [0.25, 0.5, 0.75].forEach(pct => {
      const ringY = (tankY + tankH - ellipseH / 2) - (tankH - ellipseH) * pct;
      ctx.beginPath();
      ctx.ellipse(tankX + tankW / 2, ringY, tankW / 2, ellipseH / 2, 0, 0, Math.PI);
      ctx.stroke();
    });
    ctx.restore();

    // 4. Motor Impeller at Bottom Right
    const motorX = tankX + tankW - 35;
    const motorY = tankY + tankH - 10;
    ctx.save();
    ctx.translate(motorX, motorY);

    // Motor housing
    ctx.beginPath();
    ctx.arc(0, 0, 20, 0, Math.PI * 2);
    ctx.fillStyle = isPumpRunning ? 'rgba(0, 245, 160, 0.2)' : 'rgba(30, 41, 59, 0.8)';
    ctx.fill();
    ctx.strokeStyle = isPumpRunning ? '#00F5A0' : 'rgba(255, 255, 255, 0.3)';
    ctx.lineWidth = 2;
    ctx.stroke();

    // Rotating Impeller Blades
    ctx.rotate(impellerAngle);
    ctx.strokeStyle = isPumpRunning ? '#00E5FF' : '#94A3B8';
    ctx.lineWidth = 2.5;
    for (let i = 0; i < 4; i++) {
      ctx.rotate(Math.PI / 2);
      ctx.beginPath();
      ctx.moveTo(0, 0);
      ctx.lineTo(0, -14);
      ctx.stroke();
    }
    ctx.restore();

    // Animation Loop Steps
    wavePhase += isPumpRunning ? 0.08 : 0.03;
    if (isPumpRunning) {
      impellerAngle += 0.25;
      // Simulate level rising during pump run
      if (waterLevelPct < 98) {
        waterLevelPct += 0.04;
        updateUI();
      } else if (systemMode === 'AUTO') {
        // Auto stop at top
        setPumpRunning(false, 'Auto Stop: Tank Full');
      }
    } else {
      // Slow natural consumption in simulation
      if (waterLevelPct > 10) {
        waterLevelPct -= 0.005;
        updateUI();
      }
      // Auto start trigger
      if (systemMode === 'AUTO' && waterLevelPct <= 25 && !isPumpRunning) {
        setPumpRunning(true, 'Auto Start: Water &le; 25%');
      }
    }

    requestAnimationFrame(renderHeroTank);
  }

  // ==============================================================================
  // 2. UI Updates & Synchronizer
  // ==============================================================================
  function updateUI() {
    const clampedLevel = Math.max(0, Math.min(100, waterLevelPct));
    const volumeLiters = Math.round((clampedLevel / 100) * 5000);

    heroLevelPct.textContent = `${clampedLevel.toFixed(1)}%`;
    heroVolumeLiters.textContent = `${volumeLiters.toLocaleString()} / 5,000 L`;
    simWaterSlider.value = clampedLevel.toFixed(0);
    simLevelSliderVal.textContent = `${clampedLevel.toFixed(0)}%`;

    if (isPumpRunning) {
      flowRateLpm = 18.5 + (Math.random() * 1.2 - 0.6);
      powerKw = 1.45 + (Math.random() * 0.04 - 0.02);
      heroFlowVal.textContent = `${flowRateLpm.toFixed(1)} L/min`;
      heroPowerVal.textContent = `${powerKw.toFixed(2)} kW`;
      simFlowStat.innerHTML = `${flowRateLpm.toFixed(1)} <small>L/min</small>`;
      simFlowSub.textContent = '⚡ Motor Active (2900 RPM)';
      simFlowSub.className = 'sub good';
    } else {
      flowRateLpm = 0.0;
      powerKw = 0.00;
      heroFlowVal.textContent = '0.0 L/min';
      heroPowerVal.textContent = '0.00 kW';
      simFlowStat.innerHTML = '0.0 <small>L/min</small>';
      simFlowSub.textContent = 'Impeller Idle';
      simFlowSub.className = 'sub';
    }

    // Dynamic latency jitter
    heroRtt.textContent = `${Math.floor(18 + Math.random() * 12)}ms`;
  }

  function setPumpRunning(running, reason = '') {
    isPumpRunning = running;
    if (running) {
      heroPumpBtn.classList.add('running');
      heroPumpText.textContent = 'STOP MOTOR';
      simPumpAction.classList.add('running');
      simActionLabel.textContent = 'STOP MOTOR';

      if (!runtimeInterval) {
        runtimeInterval = setInterval(() => {
          runDurationSeconds++;
          const hrs = String(Math.floor(runDurationSeconds / 3600)).padStart(2, '0');
          const mins = String(Math.floor((runDurationSeconds % 3600) / 60)).padStart(2, '0');
          const secs = String(runDurationSeconds % 60).padStart(2, '0');
          simRuntimeStat.textContent = `${hrs}:${mins}:${secs}`;
        }, 1000);
      }
      logPacket('pump/usr_demo/command', { action: 'START_PUMP', source: reason || 'APP_UI', status: 'SUCCESS' });
    } else {
      heroPumpBtn.classList.remove('running');
      heroPumpText.textContent = 'START MOTOR';
      simPumpAction.classList.remove('running');
      simActionLabel.textContent = 'START MOTOR';

      if (runtimeInterval) {
        clearInterval(runtimeInterval);
        runtimeInterval = null;
      }
      logPacket('pump/usr_demo/command', { action: 'STOP_PUMP', source: reason || 'APP_UI', status: 'SUCCESS' });
    }
    updateUI();
  }

  function setMode(mode) {
    systemMode = mode;
    heroModeBtn.textContent = `MODE: ${mode}`;
    if (mode === 'AUTO') {
      simModeAuto.classList.add('active');
      simModeManual.classList.remove('active');
    } else {
      simModeAuto.classList.remove('active');
      simModeManual.classList.add('active');
    }
    logPacket('pump/usr_demo/config', { mode: mode, auto_start: 25, auto_stop: 95 });
  }

  // ==============================================================================
  // 3. Event Listeners
  // ==============================================================================
  heroPumpBtn.addEventListener('click', () => setPumpRunning(!isPumpRunning, 'HERO_BUTTON'));
  simPumpAction.addEventListener('click', () => setPumpRunning(!isPumpRunning, 'SIM_BUTTON'));

  heroModeBtn.addEventListener('click', () => {
    setMode(systemMode === 'AUTO' ? 'MANUAL' : 'AUTO');
  });

  simModeAuto.addEventListener('click', () => setMode('AUTO'));
  simModeManual.addEventListener('click', () => setMode('MANUAL'));

  simWaterSlider.addEventListener('input', (e) => {
    waterLevelPct = parseFloat(e.target.value);
    updateUI();
    logPacket('pump/usr_demo/sensor', {
      water_level_pct: waterLevelPct,
      flow_rate_lpm: flowRateLpm,
      tds_ppm: 118,
      temperature_c: 24.5
    });
  });

  simEmergencyBtn.addEventListener('click', () => {
    setPumpRunning(false, 'EMERGENCY_ESTOP');
    logPacket('pump/usr_demo/alert', {
      severity: 'CRITICAL',
      type: 'EMERGENCY_STOP',
      description: 'Physical/App Emergency cut-off triggered.'
    });
  });

  // ==============================================================================
  // 4. Live Packet Terminal Logger
  // ==============================================================================
  function logPacket(topic, payload) {
    const time = new Date().toLocaleTimeString();
    const entry = document.createElement('div');
    entry.className = 'log-entry';
    entry.innerHTML = `<span class="log-time">[${time}]</span> <span class="log-topic">&lt;${topic}&gt;</span> <span class="log-payload">${JSON.stringify(payload)}</span>`;
    packetLog.prepend(entry);

    if (packetLog.children.length > 25) {
      packetLog.removeChild(packetLog.lastChild);
    }
  }

  // Periodic simulated heartbeat packets
  setInterval(() => {
    logPacket('pump/usr_demo/pong', {
      device_id: 'esp32_pump_000000',
      state: 'ONLINE',
      pump_state: isPumpRunning ? 'ON' : 'OFF',
      mode: systemMode,
      rtt_ms: Math.floor(18 + Math.random() * 12),
      uptime_sec: Math.floor(performance.now() / 1000)
    });
  }, 2500);

  // ==============================================================================
  // 5. Draw QR Code Canvas
  // ==============================================================================
  function drawQrPlaceholder() {
    const qrCanvas = document.getElementById('qr-code-canvas');
    if (!qrCanvas) return;
    const qctx = qrCanvas.getContext('2d');
    const size = 160;

    qctx.fillStyle = '#FFFFFF';
    qctx.fillRect(0, 0, size, size);

    // Draw high-tech aesthetic QR Pattern
    qctx.fillStyle = '#070B12';

    // Corner Finder Patterns
    function drawFinder(x, y) {
      qctx.fillRect(x, y, 42, 42);
      qctx.fillStyle = '#FFFFFF';
      qctx.fillRect(x + 6, y + 6, 30, 30);
      qctx.fillStyle = '#00E5FF';
      qctx.fillRect(x + 12, y + 12, 18, 18);
      qctx.fillStyle = '#070B12';
    }

    drawFinder(10, 10);
    drawFinder(size - 52, 10);
    drawFinder(10, size - 52);

    // Simulated QR Data Modules
    for (let r = 0; r < 20; r++) {
      for (let c = 0; c < 20; c++) {
        const inFinder = (r < 7 && c < 7) || (r < 7 && c > 12) || (r > 12 && c < 7);
        if (!inFinder && Math.random() > 0.45) {
          qctx.fillRect(10 + c * 7, 10 + r * 7, 5, 5);
        }
      }
    }

    // Center Logo Droplet Badge
    qctx.fillStyle = '#070B12';
    qctx.beginPath();
    qctx.arc(size / 2, size / 2, 16, 0, Math.PI * 2);
    qctx.fill();
    qctx.fillStyle = '#00F5A0';
    qctx.beginPath();
    qctx.arc(size / 2, size / 2, 8, 0, Math.PI * 2);
    qctx.fill();
  }

  // 6. Dynamic Version & Release Highlights Sync
  function syncWebsiteVersion() {
    fetch(`version.json?t=${Date.now()}`)
      .then(res => res.json())
      .then(data => {
        if (data && data.version) {
          // Version tags in navbar and hero
          document.querySelectorAll('.version-tag').forEach(el => el.textContent = `v${data.version}`);
          
          const pill = document.getElementById('hero-release-pill');
          if (pill) pill.innerHTML = `Latest Release: <strong>v${data.version}</strong> Live • ${data.title || 'Real-Time In-App OTA Update Engine'}`;
          
          const subLabels = document.querySelectorAll('.apk-sub-version');
          subLabels.forEach(el => el.textContent = `v${data.version} • 55.6 MB • Direct Install`);

          const specVer = document.getElementById('spec-version-badge');
          if (specVer) specVer.innerHTML = `📱 Version: <strong>v${data.version}</strong>`;
          
          const specRelease = document.getElementById('spec-release-date');
          if (specRelease && data.release_date) specRelease.innerHTML = `📅 Released: <strong>${data.release_date}</strong>`;

          // Update changelog section
          const changelogBadge = document.querySelector('.release-notes-banner span');
          if (changelogBadge) changelogBadge.textContent = `NEW IN v${data.version}`;
          const changelogTitle = document.querySelector('.release-notes-banner strong');
          if (changelogTitle && data.title) changelogTitle.textContent = data.title;
          const changelogList = document.querySelector('.release-notes-banner ul');
          if (changelogList && Array.isArray(data.changelog) && data.changelog.length > 0) {
            changelogList.innerHTML = data.changelog.map(item => `<li>${item}</li>`).join('');
          }

          // All APK download links
          const downloadLinks = document.querySelectorAll('a[href*="HydroPulse_WaterPumpController.apk"], .download-trigger, .nav-download-btn');
          downloadLinks.forEach(link => {
            const targetUrl = data.download_url ? `${data.download_url}?v=${data.version}` : `releases/HydroPulse_WaterPumpController.apk?v=${data.version}`;
            link.setAttribute('href', targetUrl);
            const span = link.querySelector('span');
            if (span && span.textContent.includes('Download HydroPulse APK')) {
              span.textContent = `Download HydroPulse APK (v${data.version})`;
            }
          });
        }
      })
      .catch(() => {});
  }
  syncWebsiteVersion();

  // Initialize
  drawQrPlaceholder();
  updateUI();
  renderHeroTank();
});
