import { EffectiveTheme, ImeSettings } from '../domain/settings/ImeSettings';
import { Candidate } from '../infrastructure/native/NativeEngineTypes';
import { InputSessionState } from './InputSessionStore';

export interface FloatingCandidateViewSnapshot {
  session: InputSessionState;
  settings: ImeSettings;
  theme: EffectiveTheme;
  generation: number;
}

/** A visible older snapshot must never commit a newer candidate at the same index. */
export function isFloatingCandidateViewCurrent(
  view: FloatingCandidateViewSnapshot, state: InputSessionState, generation: number
): boolean {
  return view.generation === generation && state.sessionActive && state.editorConnected &&
    view.session.rawInput === state.rawInput && view.session.candidatePage === state.candidatePage &&
    view.session.candidates.length === state.candidates.length &&
    view.session.candidates.every((candidate: Candidate, index: number): boolean => {
      const current = state.candidates[index];
      return candidate.id === current.id && candidate.text === current.text &&
        candidate.displayText === current.displayText && candidate.reading === current.reading;
    });
}

/** Publish only after the native panel has room for this exact content. */
export class FloatingCandidateViewStore {
  private snapshot?: FloatingCandidateViewSnapshot;
  private listeners: (() => void)[] = [];

  getSnapshot(): FloatingCandidateViewSnapshot | undefined { return this.snapshot; }

  publish(snapshot: FloatingCandidateViewSnapshot): void {
    this.snapshot = snapshot;
    this.listeners.slice().forEach((listener: () => void): void => listener());
  }

  clear(): void {
    if (this.snapshot === undefined) { return; }
    this.snapshot = undefined;
    this.listeners.slice().forEach((listener: () => void): void => listener());
  }

  subscribe(listener: () => void): void { this.listeners.push(listener); }
  unsubscribe(listener: () => void): void {
    this.listeners = this.listeners.filter((item: () => void): boolean => item !== listener);
  }
}

const sharedViewStore = new FloatingCandidateViewStore();
export function getSharedFloatingCandidateViewStore(): FloatingCandidateViewStore { return sharedViewStore; }
