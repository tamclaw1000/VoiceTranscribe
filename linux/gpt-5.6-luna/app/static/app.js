const $ = (id) => document.getElementById(id);

let session = null;
let socket = null;
let mediaStream = null;
let audioContext = null;
let sourceNode = null;
let workletNode = null;
let lastSequence = 0;
let reconnectTimer = null;
let reconnectAttempt = 0;
let shouldReconnect = false;
let notificationTimer = null;
let captureStopping = false;
let audioFrameSequence = 0;

function showNotification(text, kind = 'neutral', timeout = 5000) {
  const el = $('notification');
  el.textContent = text;
  el.className = `notification ${kind}`;
  if (notificationTimer) clearTimeout(notificationTimer);
  if (timeout > 0) {
    notificationTimer = setTimeout(() => {
      el.textContent = '';
      el.className = 'notification neutral';
      notificationTimer = null;
    }, timeout);
  }
}

function setConnection(text, kind = 'neutral', announce = false) {
  const el = $('connection');
  el.textContent = text;
  el.className = `status ${kind}`;
  if (announce) showNotification(text, kind);
}

function errorMessage(response, fallback) {
  return response.json()
    .then((body) => body?.error?.message || fallback)
    .catch(() => fallback);
}

function logEvent(event) {
  const log = $('eventLog');
  const line = JSON.stringify(event);
  log.textContent = `${line}\n${log.textContent}`.slice(0, 12000);
}

function renderCaptureDetails(settings = null) {
  const device = $('deviceSelect').selectedOptions[0];
  $('deviceDetails').textContent = device?.value
    ? `Microphone: ${device.textContent}`
    : 'Microphone: unavailable';
  if (settings) {
    $('captureFormat').textContent = `Capture format: ${settings.sampleRate || 'unknown'} Hz · ${settings.channelCount || 'unknown'} channel${settings.channelCount === 1 ? '' : 's'}`;
  }
}

function renderSession() {
  const active = Boolean(session);
  $('startButton').disabled = active;
  $('stopButton').disabled = !active;
  $('pauseButton').disabled = !active || !session.transcribing;
  $('exportButton').disabled = !active;
  $('sessionState').textContent = active
    ? `${session.state}${session.paused ? ' · transcription paused' : ''}`
    : 'No active session';
  $('segmentCount').textContent = `${session?.transcript?.length ?? 0} segments`;
  $('asrStatus').textContent = active
    ? `ASR: ${session.asrStatus || 'idle'} · windows ${session.asrWindowsProcessed || 0}${session.asrLastError ? ` · ${session.asrLastError}` : ''}`
    : 'ASR status: idle';
}

function renderSegment(segment) {
  const transcript = $('transcript');
  const empty = transcript.querySelector('.empty');
  if (empty) empty.remove();
  const row = document.createElement('article');
  row.className = 'segment';
  row.dataset.segmentId = segment.segmentId;
  row.innerHTML = `<div class="meta"><span>${Number(segment.audioOffset).toFixed(2)}s</span><span>${segment.speaker || 'Speaker unavailable'}</span></div><div class="text"></div>`;
  row.querySelector('.text').textContent = segment.text;
  transcript.appendChild(row);
  transcript.scrollTop = transcript.scrollHeight;
}

function applyEvent(event) {
  if (event.sequence && event.sequence <= lastSequence) return;
  if (event.sequence) lastSequence = event.sequence;
  logEvent(event);
  const payload = event.payload || {};
  switch (event.type) {
    case 'session.created':
      session = payload;
      break;
    case 'recording.started':
      session.recording = true;
      session.state = 'recording';
      break;
    case 'recording.finalized':
      session.recording = false;
      if (!session.transcribing) session.state = 'completed';
      break;
    case 'transcription.started':
      session.transcribing = true;
      session.state = session.recording ? 'recording' : 'transcribing';
      break;
    case 'transcription.paused':
      session.paused = true;
      break;
    case 'transcription.resumed':
      session.paused = false;
      break;
    case 'transcription.completed':
      session.transcribing = false;
      session.paused = false;
      session.state = session.recording ? 'recording' : 'completed';
      break;
    case 'transcript.segment.final':
      session.transcript ||= [];
      session.transcript.push(payload);
      renderSegment(payload);
      break;
    case 'audio.level':
      updateLevel(payload.rms, payload.peak, payload.clipping);
      break;
    case 'asr.window.queued':
      session.asrStatus = 'queued';
      break;
    case 'asr.window.started':
      session.asrStatus = 'running';
      break;
    case 'asr.window.completed':
      session.asrStatus = 'ready';
      session.asrWindowsProcessed = payload.windows;
      break;
    case 'transcription.failed':
      session.asrStatus = 'failed';
      session.asrLastError = payload.error;
      showNotification(`Transcription failed: ${payload.error || 'unknown error'}`, 'bad', 0);
      break;
    case 'audio.ack':
      $('audioBytes').textContent = formatBytes(payload.totalBytes);
      break;
  }
  renderSession();
}

function updateLevel(rms, peak, clipping = false) {
  const rmsValue = Math.min(1, Math.max(0, Number(rms) || 0));
  const peakValue = Math.min(1, Math.max(0, Number(peak) || 0));
  $('rms').textContent = `${Math.round(rmsValue * 100)}%`;
  $('peak').textContent = `${Math.round(peakValue * 100)}%${clipping ? ' · clip' : ''}`;
  $('meterFill').style.width = `${Math.round(peakValue * 100)}%`;
}

function formatBytes(value) {
  if (value < 1024) return `${value} B`;
  if (value < 1024 * 1024) return `${(value / 1024).toFixed(1)} KB`;
  return `${(value / 1024 / 1024).toFixed(1)} MB`;
}

function formatDuration(seconds) {
  if (!Number.isFinite(seconds)) return 'duration unknown';
  const total = Math.max(0, Math.round(seconds));
  return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, '0')}`;
}

function renderFileTranscript(container, player, segments) {
  container.innerHTML = '';
  if (!segments.length) {
    container.hidden = true;
    return;
  }
  container.hidden = false;
  const rows = segments.map((segment, index) => {
    const row = document.createElement('button');
    row.type = 'button';
    row.className = 'file-segment';
    row.textContent = `${Number(segment.audioOffset).toFixed(2)}s — ${segment.text}`;
    row.dataset.start = String(Number(segment.audioOffset) || 0);
    row.dataset.end = String(Number(segment.audioEndOffset) || Number(segments[index + 1]?.audioOffset) || Number.POSITIVE_INFINITY);
    row.addEventListener('click', () => {
      player.currentTime = Number(row.dataset.start);
    });
    container.appendChild(row);
    return row;
  });
  const updateActiveRow = () => {
    const current = player.currentTime;
    rows.forEach((row) => {
      const active = current >= Number(row.dataset.start) && current < Number(row.dataset.end);
      row.classList.toggle('active', active);
    });
  };
  player.addEventListener('timeupdate', updateActiveRow);
  player.addEventListener('loadedmetadata', updateActiveRow);
  updateActiveRow();
}

function renderFileSources(files) {
  const container = $('fileSources');
  container.innerHTML = '';
  if (!files.length) {
    container.innerHTML = '<p class="muted">No files imported.</p>';
    return;
  }
  for (const file of files) {
    const card = document.createElement('div');
    card.className = 'file-source';
    const status = file.error || `${file.status} · ${Math.round(file.progress * 100)}%`;
    const canTranscribe = ['ready', 'failed'].includes(file.status);
    const actionLabel = file.status === 'failed' ? 'Retry transcription' : 'Transcribe file';
    card.innerHTML = `<strong class="name" title=""></strong><span class="meta"></span><span class="meta status-text"></span><audio class="file-player" controls preload="metadata"></audio><div class="file-transcript"></div><div class="button-row"><button class="secondary" ${canTranscribe ? '' : 'disabled'}>${actionLabel}</button><button class="secondary delete-file">Delete</button></div>`;
    card.querySelector('.name').textContent = file.name;
    card.querySelector('.name').title = file.name;
    card.querySelector('.meta').textContent = `${formatDuration(file.duration)} · ${formatBytes(file.sizeBytes)} · ${file.format}`;
    card.querySelector('.status-text').textContent = status;
    const player = card.querySelector('.file-player');
    player.src = file.audioUrl;
    renderFileTranscript(card.querySelector('.file-transcript'), player, file.transcript || []);
    card.querySelector('button').addEventListener('click', () => transcribeFile(file.id));
    card.querySelector('.delete-file').addEventListener('click', () => deleteFile(file.id));
    container.appendChild(card);
  }
}

async function refreshFiles() {
  const response = await fetch('/api/files');
  if (!response.ok) return [];
  const files = await response.json();
  renderFileSources(files);
  return files;
}

async function uploadFile(file) {
  const form = new FormData();
  form.append('file', file);
  const response = await fetch('/api/files', { method: 'POST', body: form });
  if (!response.ok) throw new Error(await response.text());
  await refreshFiles();
}

async function deleteFile(fileId) {
  const response = await fetch(`/api/files/${fileId}`, { method: 'DELETE' });
  if (!response.ok) {
    showNotification(`File deletion failed: ${await errorMessage(response, 'The file could not be deleted.')}`, 'bad', 0);
    setConnection('File deletion failed', 'bad');
    return;
  }
  await refreshFiles();
  setConnection('File deleted', 'good', true);
}

async function transcribeFile(fileId) {
  const response = await fetch(`/api/files/${fileId}/transcribe`, { method: 'POST' });
  if (!response.ok) {
    showNotification(`File transcription failed: ${await errorMessage(response, 'The file could not be transcribed.')}`, 'bad', 0);
    setConnection('File transcription failed', 'bad');
    return;
  }
  const poll = async () => {
    const files = await refreshFiles();
    const file = files.find((item) => item.id === fileId);
    if (file && ['queued', 'loading', 'transcribing', 'finalizing', 'normalizing'].includes(file.status)) {
      setTimeout(poll, 500);
    } else if (file?.status === 'completed') {
      setConnection(`Transcription complete: ${(file.transcript || []).length} segment${file.transcript?.length === 1 ? '' : 's'}`, 'good', true);
    }
  };
  await poll();
}

function connectEvents() {
  if (!session || !shouldReconnect || socket?.readyState === WebSocket.CONNECTING || socket?.readyState === WebSocket.OPEN) return;
  const protocol = location.protocol === 'https:' ? 'wss' : 'ws';
  socket = new WebSocket(`${protocol}://${location.host}/api/sessions/${session.sessionId}/events?after=${lastSequence}`);
  socket.binaryType = 'arraybuffer';
  socket.onopen = () => {
    reconnectAttempt = 0;
    setConnection('Connected', 'good');
  };
  socket.onmessage = (message) => {
    if (typeof message.data !== 'string') return;
    try {
      applyEvent(JSON.parse(message.data));
    } catch {
      setConnection('Invalid event from server', 'bad');
    }
  };
  socket.onclose = () => {
    socket = null;
    if (!shouldReconnect) {
      setConnection('Disconnected', 'neutral');
      return;
    }
    setConnection('Reconnecting…', 'neutral', true);
    reconnectAttempt += 1;
    const delay = Math.min(10_000, 500 * (2 ** Math.min(reconnectAttempt - 1, 4)));
    reconnectTimer = setTimeout(() => {
      reconnectTimer = null;
      connectEvents();
    }, delay);
  };
  socket.onerror = () => setConnection('Connection error; retrying…', 'bad', true);
}

function sendJson(value) {
  if (socket?.readyState === WebSocket.OPEN) socket.send(JSON.stringify(value));
}

function microphoneAvailabilityMessage() {
  if (!window.isSecureContext) return 'Microphone requires HTTPS. Open https://tamclaw:10000/ and accept the development certificate warning first.';
  if (!navigator.mediaDevices?.getUserMedia) return 'This Edge context does not expose microphone capture. Check site permissions and browser policy.';
  return null;
}

async function setupMicrophone() {
  const unavailableMessage = microphoneAvailabilityMessage();
  if (unavailableMessage) throw new Error(unavailableMessage);
  captureStopping = false;
  mediaStream = await navigator.mediaDevices.getUserMedia({
    audio: {
      deviceId: $('deviceSelect').value ? { exact: $('deviceSelect').value } : undefined,
      channelCount: 1,
      echoCancellation: false,
      noiseSuppression: false,
      autoGainControl: false,
    },
  });
  const [track] = mediaStream.getAudioTracks();
  const settings = track?.getSettings?.() || {};
  renderCaptureDetails(settings);
  if (track) {
    track.onended = () => {
      if (captureStopping) return;
      showNotification('Microphone input ended or permission was revoked. The session is stopping.', 'bad', 0);
      setConnection('Microphone disconnected', 'bad');
      if (session) stopSession();
    };
  }
  audioContext = new AudioContext();
  await audioContext.audioWorklet.addModule('/audio-worklet.js');
  sourceNode = audioContext.createMediaStreamSource(mediaStream);
  workletNode = new AudioWorkletNode(audioContext, 'voice-transcribe-processor');
  workletNode.port.onmessage = ({ data }) => {
    if (data.type !== 'audio') return;
    updateLevel(data.rms, data.peak, data.clipping);
    sendJson({ type: 'client.level', rms: data.rms, peak: data.peak, clipping: data.clipping });
    if (socket?.readyState === WebSocket.OPEN && session?.recording) {
      audioFrameSequence += 1;
      sendJson({ type: 'client.audio.frame', frameSequence: audioFrameSequence, capturedAt: Date.now() });
      socket.send(data.samples.buffer);
    }
  };
  sourceNode.connect(workletNode);
  // Connecting to a silent destination keeps processing alive without audible feedback.
  const silentOutput = audioContext.createGain();
  silentOutput.gain.value = 0;
  workletNode.connect(silentOutput);
  silentOutput.connect(audioContext.destination);
  const actualRate = audioContext.sampleRate;
  return actualRate;
}

function stopMicrophone() {
  captureStopping = true;
  if (reconnectTimer) clearTimeout(reconnectTimer);
  if (workletNode) workletNode.disconnect();
  if (sourceNode) sourceNode.disconnect();
  if (mediaStream) mediaStream.getTracks().forEach((track) => track.stop());
  if (audioContext) audioContext.close();
  workletNode = null;
  sourceNode = null;
  mediaStream = null;
  audioContext = null;
}

async function startSession() {
  $('startButton').disabled = true;
  try {
    await setupMicrophone();
    const sampleRate = audioContext?.sampleRate || 48000;
    const channels = mediaStream?.getAudioTracks()[0]?.getSettings?.().channelCount || 1;
    const response = await fetch('/api/sessions', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ source_name: $('sourceName').value || 'Browser microphone', sample_rate: sampleRate, channels }),
    });
    if (!response.ok) throw new Error(await response.text());
    session = await response.json();
    lastSequence = 0;
    audioFrameSequence = 0;
    $('transcript').innerHTML = '';
    shouldReconnect = true;
    reconnectAttempt = 0;
    connectEvents();
    await fetch(`/api/sessions/${session.sessionId}/recording/start`, { method: 'POST' });
    await fetch(`/api/sessions/${session.sessionId}/transcription/start`, { method: 'POST' });
    renderSession();
  } catch (error) {
    stopMicrophone();
    session = null;
    showNotification(`Start failed: ${error.message}`, 'bad', 0);
    setConnection('Start failed', 'bad');
    renderSession();
  }
}

async function stopSession() {
  if (!session) return;
  shouldReconnect = false;
  await fetch(`/api/sessions/${session.sessionId}/transcription/stop`, { method: 'POST' });
  await fetch(`/api/sessions/${session.sessionId}/recording/stop`, { method: 'POST' });
  stopMicrophone();
  if (socket) socket.close();
  session = null;
  renderSession();
}

async function togglePause() {
  if (!session) return;
  const action = session.paused ? 'resume' : 'pause';
  await fetch(`/api/sessions/${session.sessionId}/transcription/${action}`, { method: 'POST' });
}

async function exportMarkdown() {
  if (!session) return;
  const response = await fetch(`/api/sessions/${session.sessionId}/export/markdown`);
  const data = await response.json();
  const blob = new Blob([data.content], { type: 'text/markdown' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = data.filename;
  link.click();
  URL.revokeObjectURL(url);
}

async function loadDevices() {
  const unavailableMessage = microphoneAvailabilityMessage();
  if (unavailableMessage) {
    $('deviceSelect').innerHTML = `<option>${unavailableMessage}</option>`;
    showNotification(unavailableMessage, 'bad', 0);
    setConnection('Microphone unavailable', 'bad');
    return;
  }
  try {
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    stream.getTracks().forEach((track) => track.stop());
    const devices = await navigator.mediaDevices.enumerateDevices();
    const select = $('deviceSelect');
    select.innerHTML = '';
    devices.filter((device) => device.kind === 'audioinput').forEach((device, index) => {
      const option = document.createElement('option');
      option.value = device.deviceId;
      option.textContent = device.label || `Microphone ${index + 1}`;
      select.appendChild(option);
    });
    select.disabled = false;
    select.addEventListener('change', () => renderCaptureDetails());
    renderCaptureDetails();
  } catch {
    $('deviceSelect').innerHTML = '<option>Microphone permission unavailable</option>';
    showNotification('Microphone permission is needed before starting a session.', 'bad', 0);
    setConnection('Microphone permission needed', 'bad');
  }
}

$('startButton').addEventListener('click', startSession);
$('stopButton').addEventListener('click', stopSession);
$('pauseButton').addEventListener('click', togglePause);
$('exportButton').addEventListener('click', exportMarkdown);
$('fileInput').addEventListener('change', async (event) => {
  const [file] = event.target.files;
  if (!file) return;
  try {
    setConnection(`Uploading ${file.name}…`, 'neutral');
    showNotification(`Uploading ${file.name}…`, 'neutral', 0);
    await uploadFile(file);
    setConnection('File imported', 'good', true);
  } catch (error) {
    showNotification(`Upload failed: ${error.message}`, 'bad', 0);
    setConnection('Upload failed', 'bad');
  } finally {
    event.target.value = '';
  }
});

refreshFiles();
fetch('/api/capabilities').then((response) => response.json()).then((capabilities) => {
  $('versionText').textContent = `v${capabilities.version} · build ${capabilities.build}`;
  $('capabilityText').textContent = `Browser capture: ${capabilities.browserCapture ? 'available' : 'unavailable'} · ASR: ${capabilities.asrEngine}${capabilities.asrModel ? ` (${capabilities.asrModel})` : ''} · Diarization: deferred`;
});
loadDevices();
renderSession();
