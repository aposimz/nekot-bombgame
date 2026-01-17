const app = document.getElementById('app');
const grid = document.getElementById('grid');
const invite = document.getElementById('invite');
const countdown = document.getElementById('countdown');
const winloseOverlay = document.getElementById('winlose-overlay');
const vehicleMessage = document.getElementById('vehicle-message');
let mode = 'idle'; // idle | select | turn
const btnGameCancel = document.getElementById('btn-game-cancel');
const btnCancel = document.getElementById('btn-cancel');
const btnRandom = document.getElementById('btn-random');
const btnOk = document.getElementById('btn-ok');
// closeボタンは削除
let selected = null;
let lastSelectedBtn = null;
const usedNumbers = new Set();
let currentGuessBtn = null;

function setVisible(v) { app.style.display = v ? 'block' : 'none'; }

// ---- Audio helpers ----
let audioCtx;
function getAudioCtx() {
  if (!audioCtx) {
    const Ctx = window.AudioContext || window.webkitAudioContext;
    audioCtx = new Ctx();
  }
  if (audioCtx.state === 'suspended') audioCtx.resume();
  return audioCtx;
}

function beep({ freq = 880, durationMs = 120, type = 'sine', gain = 0.02 } = {}) {
  try {
    const ctx = getAudioCtx();
    const osc = ctx.createOscillator();
    const g = ctx.createGain();
    osc.type = type;
    osc.frequency.value = freq;
    g.gain.value = gain;
    osc.connect(g).connect(ctx.destination);
    const now = ctx.currentTime;
    osc.start(now);
    osc.stop(now + durationMs / 1000);
  } catch (_) { /* ignore */ }
}

function playTurnChime() {
  // simple two-note chime
  beep({ freq: 880, durationMs: 120, type: 'sine', gain: 0.02 });
  setTimeout(() => beep({ freq: 1175, durationMs: 160, type: 'sine', gain: 0.03 }), 140);
}

let countdownTimer = null;
function startCountdownBeep(seconds) {
  if (countdownTimer) { clearInterval(countdownTimer); countdownTimer = null; }
  // immediate tick
  beep({ freq: 740, durationMs: 90, type: 'square', gain: 0.02 });
  let remaining = seconds;
  countdownTimer = setInterval(() => {
    remaining -= 1;
    if (remaining <= 0) {
      // final longer beep
      beep({ freq: 440, durationMs: 400, type: 'sawtooth', gain: 0.03 });
      clearInterval(countdownTimer);
      countdownTimer = null;
      return;
    }
    beep({ freq: 740, durationMs: 90, type: 'square', gain: 0.02 });
  }, 1000);
}

function showWinLose(result) {
  const text = winloseOverlay.querySelector('.winlose-text');
  text.textContent = result;
  
  // シンプルな条件分岐
  if (result.includes('WIN')) {
    text.className = 'winlose-text win';
  } else {
    text.className = 'winlose-text lose';
  }
  
  winloseOverlay.style.display = 'flex';
  winloseOverlay.style.opacity = '1';
  
  // 3秒後にフェードアウト
  setTimeout(() => {
    winloseOverlay.style.opacity = '0';
    setTimeout(() => {
      winloseOverlay.style.display = 'none';
      winloseOverlay.style.opacity = '1';
    }, 500);
  }, 3000);
}

function makeGrid() {
  grid.innerHTML = '';
  for (let i = 1; i <= 25; i++) {
    const btn = document.createElement('button');
    btn.dataset.num = String(i);
    btn.textContent = String(i);
    btn.addEventListener('click', () => {
      if (mode === 'select') {
        if (lastSelectedBtn) lastSelectedBtn.classList.remove('selected');
        selected = i;
        btn.classList.add('selected');
        lastSelectedBtn = btn;
      } else if (mode === 'turn') {
        if (currentGuessBtn && !currentGuessBtn.classList.contains('used')) {
          currentGuessBtn.classList.remove('mark-mine');
        }
        currentGuessBtn = btn;
        if (!btn.classList.contains('used')) btn.classList.add('mark-mine');
        fetch(`https://${GetParentResourceName()}/ui:guess`, { method: 'POST', body: JSON.stringify({ n: i }) });
      }
    });
    grid.appendChild(btn);
  }
}

window.addEventListener('message', (e) => {
  const data = e.data;
  if (!data || !data.action) return;
  if (data.action === 'mode') {
    setVisible(true);
    mode = data.mode;
    if (!grid.children.length) makeGrid();
    if (mode === 'select') {
      invite.textContent = '起爆装置の番号をセットしてください';
      selected = null;
      if (lastSelectedBtn) lastSelectedBtn.classList.remove('selected');
      lastSelectedBtn = null;
      // 最初の数字設定時だけ3ボタンを表示
      document.getElementById('actions-select').style.display = 'flex';
      document.getElementById('actions-global').style.display = 'none';
    } else if (mode === 'turn') {
      invite.textContent = data.yourTurn ? 'あなたのターン - 数字を選択してください' : '相手のターン - 待機中';
      if (data.yourTurn) playTurnChime();
      if (currentGuessBtn && !currentGuessBtn.classList.contains('used')) { currentGuessBtn.classList.remove('mark-mine'); }
      currentGuessBtn = null;
      // ターン中はゲームキャンセルのみ
      document.getElementById('actions-select').style.display = 'none';
      document.getElementById('actions-global').style.display = 'flex';
    } else {
      invite.textContent = '';
    }
  }
  if (data.action === 'countdown') {
    setVisible(true);
    // 勝敗ロールに応じてグリッドの配色と文言を切り替え
    const role = data.role; // 'winner' または 'loser'
    const buttons = [...grid.children];
    if (role === 'loser') {
      invite.textContent = 'あなたの車の起爆装置が作動しました！';
      buttons.forEach(b => { b.classList.add('all-red'); b.classList.remove('all-green'); });
      countdown.classList.add('countdown-red');
      countdown.classList.remove('countdown-green');
      showWinLose('YOU LOSE...');
    } else { // role === 'winner'
      invite.textContent = '勝利！退避してください！';
      buttons.forEach(b => { b.classList.add('all-green'); b.classList.remove('all-red'); });
      countdown.classList.add('countdown-green');
      countdown.classList.remove('countdown-red');
      showWinLose('YOU WIN!');
    }

    let s = data.seconds || 10;
    countdown.textContent = `爆発まで: ${s}s`;
    startCountdownBeep(s);
    const timer = setInterval(() => {
      s -= 1;
      countdown.textContent = `爆発まで: ${s}s`;
      if (s <= 0) { clearInterval(timer); }
    }, 1000);
  }
  if (data.action === 'vehicle_message') {
    if (data.show) {
      vehicleMessage.textContent = data.message;
      vehicleMessage.style.display = 'block';
    } else {
      vehicleMessage.style.display = 'none';
    }
  }
  if (data.action === 'close') {
    // カウントダウンタイマーをクリア
    if (countdownTimer) {
      clearInterval(countdownTimer);
      countdownTimer = null;
    }
    
    // 音声コンテキストをクリア（頻繁な使用で重要）
    if (audioCtx) {
      audioCtx.close();
      audioCtx = null;
    }
    
    // モードをリセット
    mode = 'idle';
    
    setVisible(false);
    grid.innerHTML = '';
    invite.textContent = '';
    countdown.textContent = '';
    countdown.className = 'countdown'; // CSSクラスをリセット
    winloseOverlay.style.display = 'none';
    vehicleMessage.style.display = 'none';
    selected = null;
    lastSelectedBtn = null;
    usedNumbers.clear();
    currentGuessBtn = null;
  }
});

makeGrid();

window.addEventListener('DOMContentLoaded', () => setVisible(false));

btnGameCancel.addEventListener('click', () => {
  fetch(`https://${GetParentResourceName()}/ui:cancel`, { method: 'POST' });
});

// 初回の数字設定用ボタン
btnCancel?.addEventListener('click', () => {
  fetch(`https://${GetParentResourceName()}/ui:cancel`, { method: 'POST' });
});

btnRandom?.addEventListener('click', () => {
  if (mode !== 'select') return;
  const i = Math.floor(Math.random() * 25) + 1;
  // ハイライト付与
  if (lastSelectedBtn) lastSelectedBtn.classList.remove('selected');
  const btn = [...grid.children].find(b => Number(b.dataset.num) === i);
  if (btn) {
    btn.classList.add('selected');
    lastSelectedBtn = btn;
  }
  selected = i;
  // 送信
  fetch(`https://${GetParentResourceName()}/ui:ok`, { method: 'POST', body: JSON.stringify({ n: selected }) });
  // リセット
  if (lastSelectedBtn) lastSelectedBtn.classList.remove('selected');
  lastSelectedBtn = null;
  selected = null;
  // 相手の決定待ちの間はUIを閉じる
  setVisible(false);
});

btnOk?.addEventListener('click', () => {
  if (mode !== 'select') return;
  if (selected == null) return;
  fetch(`https://${GetParentResourceName()}/ui:ok`, { method: 'POST', body: JSON.stringify({ n: selected }) });
  // 決定後は選択ハイライトを初期化
  if (lastSelectedBtn) lastSelectedBtn.classList.remove('selected');
  lastSelectedBtn = null;
  selected = null;
  // 相手の決定待ちの間はUIを閉じる
  setVisible(false);
});

// サーバーからのターン選択通知（自分の確定選択のみハイライト）
window.addEventListener('message', (e) => {
  const data = e.data;
  if (!data || !data.action) return;
  if (data.action === 'turn_guess') {
    const { guess, mine } = data;
    if (!mine) return;
    usedNumbers.add(guess);
    const btn = [...grid.children].find(b => Number(b.dataset.num) === guess);
    if (btn) {
      // 確定: このターンの仮選択を確定させ、使用済みにする
      if (currentGuessBtn && currentGuessBtn !== btn && !currentGuessBtn.classList.contains('used')) {
        currentGuessBtn.classList.remove('mark-mine');
      }
      currentGuessBtn = null;
      btn.classList.add('mark-mine');
      btn.classList.add('used');
    }
  }
});

// ESC キーで常にゲームキャンセル（どの画面でも完全終了）
window.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') {
    fetch(`https://${GetParentResourceName()}/ui:cancel`, { method: 'POST' });
  }
});


