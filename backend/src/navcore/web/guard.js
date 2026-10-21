export function fresh(instruction, received, now) {
  return instruction && Number.isInteger(instruction.capture_monotonic_ms) &&
    Number.isFinite(instruction.valid_for_ms) && instruction.valid_for_ms > 0 &&
    instruction.valid_for_ms <= 1000 && now >= instruction.capture_monotonic_ms &&
    now < instruction.capture_monotonic_ms + 1000 && now >= received &&
    now < received + instruction.valid_for_ms;
}

export class Guard {
  constructor(now) { this.lastFresh = now; this.stale = false; this.seen = new Map(); }
  outcome(result, capture, received) {
    if (!capture || result.capture_monotonic_ms !== capture.at ||
        received < capture.at || received - capture.at >= 1000 ||
        received - capture.requested >= 1000) return false;
    this.lastFresh = received; this.stale = false;
    return true;
  }
  expired(now) {
    if (this.stale || now - this.lastFresh < 1500) return false;
    this.stale = true; return true;
  }
  instruction(value, received, now, repeated = false) {
    if (!fresh(value, received, now)) return null;
    const original = this.seen.get(value.id);
    if (original && (!repeated || now >= original)) return null;
    const deadline = Math.min(original ?? Infinity,
      value.capture_monotonic_ms + 1000, received + value.valid_for_ms);
    if (now >= deadline) return null;
    this.seen.set(value.id, deadline);
    if (this.seen.size > 4096) this.seen.delete(this.seen.keys().next().value);
    return deadline;
  }
}
