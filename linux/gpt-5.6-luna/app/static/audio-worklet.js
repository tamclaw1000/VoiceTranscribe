class VoiceTranscribeProcessor extends AudioWorkletProcessor {
  process(inputs) {
    const input = inputs[0];
    if (!input || !input[0]) return true;
    const channel = input[0];
    const samples = channel.slice();
    let sum = 0;
    let peak = 0;
    for (const sample of samples) {
      sum += sample * sample;
      peak = Math.max(peak, Math.abs(sample));
    }
    const rms = Math.sqrt(sum / Math.max(samples.length, 1));
    this.port.postMessage({ type: 'audio', samples, rms, peak, clipping: peak >= 0.99 }, [samples.buffer]);
    return true;
  }
}
registerProcessor('voice-transcribe-processor', VoiceTranscribeProcessor);
