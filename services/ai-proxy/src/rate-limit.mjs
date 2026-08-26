import { ProxyError, ProxyErrorCode } from './errors.mjs';

export class FixedWindowRateLimiter {
  constructor(limitPerMinute, maxSubjects = 20_000) {
    this.limitPerMinute = limitPerMinute;
    this.maxSubjects = maxSubjects;
    this.entries = new Map();
  }

  consume(subject, nowMs = Date.now()) {
    const windowStart = Math.floor(nowMs / 60_000) * 60_000;
    const current = this.entries.get(subject);
    if (!current || current.windowStart !== windowStart) {
      this.prune(windowStart);
      this.entries.set(subject, { windowStart, count: 1 });
      return;
    }
    if (current.count >= this.limitPerMinute) {
      throw new ProxyError(429, ProxyErrorCode.RATE_LIMITED);
    }
    current.count += 1;
  }

  prune(activeWindowStart) {
    for (const [key, value] of this.entries) {
      if (value.windowStart < activeWindowStart) {
        this.entries.delete(key);
      }
    }
    while (this.entries.size >= this.maxSubjects) {
      this.entries.delete(this.entries.keys().next().value);
    }
  }
}

export class RequestReplayGuard {
  constructor(windowMs, maxEntries = 50_000) {
    this.windowMs = windowMs;
    this.maxEntries = maxEntries;
    this.entries = new Map();
  }

  accept(subject, requestId, nowMs = Date.now()) {
    this.prune(nowMs);
    const key = `${subject}\0${requestId}`;
    if (this.entries.has(key)) {
      throw new ProxyError(409, ProxyErrorCode.DUPLICATE_REQUEST);
    }
    this.entries.set(key, nowMs + this.windowMs);
  }

  prune(nowMs) {
    for (const [key, expiresAt] of this.entries) {
      if (expiresAt <= nowMs) {
        this.entries.delete(key);
      }
    }
    while (this.entries.size >= this.maxEntries) {
      this.entries.delete(this.entries.keys().next().value);
    }
  }
}
