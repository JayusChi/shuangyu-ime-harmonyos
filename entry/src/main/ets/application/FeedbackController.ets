import { HapticFeedbackService } from '../infrastructure/haptic/HapticFeedbackService';
import { KeySoundService } from '../infrastructure/audio/KeySoundService';

export class FeedbackController {
  private readonly haptic: HapticFeedbackService;
  private readonly sound: KeySoundService;

  constructor(
    haptic: HapticFeedbackService = new HapticFeedbackService(),
    sound: KeySoundService = new KeySoundService()
  ) {
    this.haptic = haptic;
    this.sound = sound;
  }

  accepted(isRepeatedDelete: boolean = false): void {
    this.haptic.trigger(isRepeatedDelete);
    this.sound.trigger();
  }

  dispose(): void {
    this.haptic.dispose();
    this.sound.dispose();
  }
}
