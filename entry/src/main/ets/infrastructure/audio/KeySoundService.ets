import common from '@ohos.app.ability.common';
import { audio } from '@kit.AudioKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { media } from '@kit.MediaKit';
import { Logger } from '../../common/logging/Logger';
import { SettingsStore, getSharedSettingsStore } from '../../state/SettingsStore';

const LOGGER = new Logger('KeySoundService');

export interface KeySoundBackend {
  play(volume?: number): Promise<void>;
  dispose(): Promise<void>;
}

/** Reusable SoundPool backend with a tiny project-generated PCM click. */
export class HarmonyKeySoundBackend implements KeySoundBackend {
  private pool?: media.SoundPool;
  private soundId: number = 0;
  private initializationTask?: Promise<void>;

  initialize(context: common.Context): Promise<void> {
    if (!this.initializationTask) {
      this.initializationTask = this.prepare(context);
    }
    return this.initializationTask;
  }

  async play(volume: number = 0.16): Promise<void> {
    if (this.initializationTask) {
      await this.initializationTask;
    }
    if (!this.pool || this.soundId <= 0) {
      return;
    }
    const parameters: media.PlayParameters = {
      loop: 0,
      rate: audio.AudioRendererRate.RENDER_RATE_NORMAL,
      leftVolume: Math.max(0, Math.min(1, volume)),
      rightVolume: Math.max(0, Math.min(1, volume)),
      priority: 1
    };
    try {
      await this.pool.play(this.soundId, parameters);
    } catch (err) {
      throw new Error(`key sound playback failed: ${JSON.stringify(err)}`);
    }
  }

  async dispose(): Promise<void> {
    const pool = this.pool;
    const soundId = this.soundId;
    this.pool = undefined;
    this.soundId = 0;
    this.initializationTask = undefined;
    if (!pool) {
      return;
    }
    try {
      if (soundId > 0) {
        await pool.unload(soundId);
      }
      await pool.release();
    } catch (err) {
      throw new Error(`key sound disposal failed: ${JSON.stringify(err)}`);
    }
  }

  private async prepare(context: common.Context): Promise<void> {
    const info: audio.AudioRendererInfo = {
      usage: audio.StreamUsage.STREAM_USAGE_MUSIC,
      rendererFlags: 0
    };
    try {
      const pool = await media.createSoundPool(4, info);
      const wav = this.createClickWav();
      const path = `${context.filesDir}/ime_key_click.wav`;
      const file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, wav.buffer);
        this.soundId = await pool.load(file.fd, 0, wav.byteLength);
        this.pool = pool;
      } finally {
        fs.closeSync(file);
        if (!this.pool) {
          await pool.release();
        }
      }
    } catch (err) {
      throw new Error(`key sound initialization failed: ${JSON.stringify(err)}`);
    }
  }

  private createClickWav(): Uint8Array {
    const sampleRate = 8000;
    const sampleCount = 192;
    const dataSize = sampleCount * 2;
    const buffer = new ArrayBuffer(44 + dataSize);
    const bytes = new Uint8Array(buffer);
    const view = new DataView(buffer);
    this.writeAscii(bytes, 0, 'RIFF');
    view.setUint32(4, 36 + dataSize, true);
    this.writeAscii(bytes, 8, 'WAVE');
    this.writeAscii(bytes, 12, 'fmt ');
    view.setUint32(16, 16, true);
    view.setUint16(20, 1, true);
    view.setUint16(22, 1, true);
    view.setUint32(24, sampleRate, true);
    view.setUint32(28, sampleRate * 2, true);
    view.setUint16(32, 2, true);
    view.setUint16(34, 16, true);
    this.writeAscii(bytes, 36, 'data');
    view.setUint32(40, dataSize, true);
    for (let index = 0; index < sampleCount; index += 1) {
      const envelope = 1 - index / sampleCount;
      const sample = Math.round(Math.sin(index * 0.72) * envelope * 5200);
      view.setInt16(44 + index * 2, sample, true);
    }
    return bytes;
  }

  private writeAscii(target: Uint8Array, offset: number, value: string): void {
    for (let index = 0; index < value.length; index += 1) {
      target[offset + index] = value.charCodeAt(index);
    }
  }
}

const SHARED_HARMONY_KEY_SOUND_BACKEND = new HarmonyKeySoundBackend();

export function initializeSharedKeySoundBackend(context: common.Context): void {
  SHARED_HARMONY_KEY_SOUND_BACKEND.initialize(context).catch((err: Object) => {
    LOGGER.debug(`key sound initialization unavailable: ${JSON.stringify(err)}`);
  });
}

export class KeySoundService {
  private readonly backend: KeySoundBackend;
  private readonly settingsStore: SettingsStore;
  private lastPlayAt: number = 0;
  private disposed: boolean = false;

  constructor(
    backend: KeySoundBackend = SHARED_HARMONY_KEY_SOUND_BACKEND,
    settingsStore: SettingsStore = getSharedSettingsStore()
  ) {
    this.backend = backend;
    this.settingsStore = settingsStore;
  }

  trigger(now: number = Date.now()): void {
    if (this.disposed || !this.settingsStore.getSnapshot().keySoundEnabled || now - this.lastPlayAt < 24) {
      return;
    }
    this.lastPlayAt = now;
    this.backend.play(this.settingsStore.getSnapshot().keySoundVolume / 100).catch((err: Object) => {
      LOGGER.debug(`key sound unavailable: ${JSON.stringify(err)}`);
    });
  }

  dispose(): void {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    this.backend.dispose().catch((err: Object) => {
      LOGGER.debug(`key sound release failed: ${JSON.stringify(err)}`);
    });
  }
}
