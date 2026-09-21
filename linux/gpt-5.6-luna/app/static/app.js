const $ = (id) => document.getElementById(id);

let session = null;
let socket = null;
let mediaStream = null;
let audioContext = null;
let sourceNode = null;
let workletNode = null;
let lastSequence = 0;
let reconnectTimer = null;
let shouldReconnect = false;

function setConnection(text, kind = 'neutral') {
  const el = $('connection');
  el.textContent = text;
  el.className = `status ${kind}`;
}

function logEvent(event) {
  const log = $('eventLog');
  const line = JSON.stringify(event);
  log.textContent = `${line}\n${log.textContent}`.slice(0, 12000);
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
    const transcriptText = (file.transcript || []).map((segment) => `${Number(segment.audioOffset).toFixed(2)}s — ${segment.text}`).join('\\n');
    card.innerHTML = `<strong class="name" title=""></strong><span class="meta"></span><span class="meta status-text"></span><pre class="file-transcript"></pre><div class="button-row"><button class="secondary" ${file.status !== 'ready' ? 'disabled' : ''}>Transcribe file</button><button class="secondary delete-file">Delete</button></div>`;
    card.querySelector('.name').textContent = file.name;
    card.querySelector('.name').title = file.name;
    card.querySelector('.meta').textContent = `${formatDuration(file.duration)} · ${formatBytes(file.sizeBytes)} · ${file.format}`;
    card.querySelector('.status-text').textContent = status;
    card.querySelector('.file-transcript').textContent = transcriptText;
    card.querySelector('.file-transcript').hidden = !transcriptText;
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
    setConnection(`File deletion failed: ${await response.text()}`, 'bad');
    return;
  }
  await refreshFiles();
  setConnection('File deleted', 'good');
}

async function transcribeFile(fileId) {
  const response = await fetch(`/api/files/${fileId}/transcribe`, { method: 'POST' });
  if (!response.ok) {
    setConnection(`File transcription failed: ${await response.text()}`, 'bad');
    return;
  }
  const poll = async () => {
    const files = await refreshFiles();
    const file = files.find((item) => item.id === fileId);
    if (file && ['queued', 'transcribing', 'normalizing'].includes(file.status)) {
      setTimeout(poll, 500);
    } else if (file?.status === 'completed') {
      setConnection(`Transcription complete: ${(file.transcript || []).length} segment${file.transcript?.length === 1 ? '' : 's'}`, 'good');
    }
  };
  await poll();
}

function connectEvents() {
  if (!session) return;
  const protocol = location.protocol === 'https:' ? 'wss' : 'ws';
  socket = new WebSocket(`${protocol}://${location.host}/api/sessions/${session.sessionId}/events?after=${lastSequence}`);
  socket.binaryType = 'arraybuffer';
  socket.onopen = () => setConnection('Connected', 'good');
  socket.onmessage = (message) => {
    if (typeof message.data === 'string') applyEvent(JSON.parse(message.data));
  };
  socket.onclose = () => {
    socket = null;
    if (shouldReconnect) {
      setConnection('Reconnecting…', 'neutral');
      reconnectTimer = setTimeout(connectEvents, 1000);
    } else {
      setConnection('Disconnected', 'neutral');
    }
  };
  socket.onerror = () => setConnection('Connection error', 'bad');
}

function sendJson(value) {
  if (socket?.readyState === WebSocket.OPEN) socket.send(JSON.stringify(value));
}

async function setupMicrophone() {
  mediaStream = await navigator.mediaDevices.getUserMedia({
    audio: {
      deviceId: $('deviceSelect').value ? { exact: $('deviceSelect').value } : undefined,
      channelCount: 1,
      echoCancellation: false,
      noiseSuppression: false,
      autoGainControl: false,
    },
  });
  audioContext = new AudioContext();
  await audioContext.audioWorklet.addModule('/audio-worklet.js');
  sourceNode = audioContext.createMediaStreamSource(mediaStream);
  workletNode = new AudioWorkletNode(audioContext, 'voice-transcribe-processor');
  workletNode.port.onmessage = ({ data }) => {
    if (data.type !== 'audio') return;
    updateLevel(data.rms, data.peak, data.clipping);
    sendJson({ type: 'client.level', rms: data.rms, peak: data.peak, clipping: data.clipping });
    if (socket?.readyState === WebSocket.OPEN && session?.recording) {
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
    const sampleRate = audioContext?.sampleRate || 48000;
    const response = await fetch('/api/sessions', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ source_name: $('sourceName').value || 'Browser microphone', sample_rate: sampleRate, channels: 1 }),
    });
    if (!response.ok) throw new Error(await response.text());
    session = await response.json();
    lastSequence = 0;
    $('transcript').innerHTML = '';
    shouldReconnect = true;
    connectEvents();
    await setupMicrophone();
    await fetch(`/api/sessions/${session.sessionId}/recording/start`, { method: 'POST' });
    await fetch(`/api/sessions/${session.sessionId}/transcription/start`, { method: 'POST' });
    renderSession();
  } catch (error) {
    stopMicrophone();
    session = null;
    setConnection(`Start failed: ${error.message}`, 'bad');
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
  } catch {
    $('deviceSelect').innerHTML = '<option>Microphone permission unavailable</option>';
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
    await uploadFile(file);
    setConnection('File imported', 'good');
  } catch (error) {
    setConnection(`Upload failed: ${error.message}`, 'bad');
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
