import { describe, it, expect } from '@ohos/hypium';
import {
  QWERTY_LAYOUT,
  KeyboardKeyKind,
  KeyboardKeySpec,
  QWERTY_KEY_ROWS,
  LegacyKeyboardKeySpec
} from '../main/ets/presentation/keyboard/model/KeyboardLayoutSpec';
import {
  PORTRAIT_METRICS,
  LANDSCAPE_METRICS,
  getMetricsForOrientation,
  calculateTotalKeyboardHeight,
  KEY_WEIGHTS,
  DELETE_REPEAT_CONFIG
} from '../main/ets/presentation/keyboard/design/KeyboardMetrics';
import {
  LIGHT_PALETTE,
  DARK_PALETTE,
  getPaletteForColorMode,
  resolveModeSwitchKeyTextColor
} from '../main/ets/presentation/keyboard/design/KeyboardPalette';
import { DeleteRepeatController } from '../main/ets/application/DeleteRepeatController';
import { KeyboardMode } from '../main/ets/domain/keyboard/KeyboardAction';

function delay(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, ms);
  });
}

export default function stage3Tests() {
  describe('Stage 3: Keyboard UI Engineering', () => {
    describe('KeyboardLayoutSpec', () => {
      it('QWERTY layout has 4 rows in natural order', 0, () => {
        expect(QWERTY_LAYOUT.rows.length).assertEqual(4);

        const qRow = QWERTY_LAYOUT.rows[0];
        expect(qRow.keys.length).assertEqual(10);
        expect(qRow.keys[0].label).assertEqual('Q');
        expect(qRow.keys[9].label).assertEqual('P');

        const aRow = QWERTY_LAYOUT.rows[1];
        expect(aRow.keys.length).assertEqual(9);
        expect(aRow.keys[0].label).assertEqual('A');
        expect(aRow.keys[8].label).assertEqual('L');

        const zRow = QWERTY_LAYOUT.rows[2];
        expect(zRow.keys[0].label).assertEqual('Z');
        expect(zRow.keys[6].label).assertEqual('M');

        const funcRow = QWERTY_LAYOUT.rows[3];
        expect(funcRow.keys.length).assertEqual(3);
        expect(funcRow.keys.filter((key: KeyboardKeySpec) => key.id === 'hide').length)
          .assertEqual(0);
      });

      it('Letter keys have correct kind and preview enabled', 0, () => {
        const qRow = QWERTY_LAYOUT.rows[0];
        qRow.keys.forEach((key: KeyboardKeySpec) => {
          expect(key.kind).assertEqual(KeyboardKeyKind.LETTER);
          expect(key.previewEnabled).assertTrue();
          expect(key.weight).assertEqual(1);
        });
      });

      it('Function keys have preview disabled', 0, () => {
        const funcRow = QWERTY_LAYOUT.rows[3];
        funcRow.keys.forEach((key: KeyboardKeySpec) => {
          expect(key.previewEnabled).assertFalse();
        });
      });

      it('Delete key exists in Z row', 0, () => {
        let hasDeleteKey = false;
        let deleteLabel = '';
        const zRow = QWERTY_LAYOUT.rows[2];
        zRow.keys.forEach((key: KeyboardKeySpec) => {
          if (key.kind === KeyboardKeyKind.DELETE) {
            hasDeleteKey = true;
            deleteLabel = key.label;
          }
        });

        expect(hasDeleteKey).assertTrue();
        expect(deleteLabel).assertEqual('删除');
      });

      it('Space key has larger weight', 0, () => {
        let hasSpaceKey = false;
        let spaceWeight = 0;
        const funcRow = QWERTY_LAYOUT.rows[3];
        funcRow.keys.forEach((key: KeyboardKeySpec) => {
          if (key.kind === KeyboardKeyKind.SPACE) {
            hasSpaceKey = true;
            spaceWeight = key.weight;
          }
        });

        expect(hasSpaceKey).assertTrue();
        expect(spaceWeight > 1).assertTrue();
      });

      it('Legacy QWERTY_KEY_ROWS maintains compatibility', 0, () => {
        expect(QWERTY_KEY_ROWS.length).assertEqual(4);
        expect(QWERTY_KEY_ROWS[0][0].label).assertEqual('Q');
        expect(QWERTY_KEY_ROWS[1][0].label).assertEqual('A');
        expect(QWERTY_KEY_ROWS[2][0].label).assertEqual('Z');
      });
    });

    describe('KeyboardMetrics', () => {
      it('Portrait and landscape metrics are different', 0, () => {
        expect(PORTRAIT_METRICS.letterKeyHeight === LANDSCAPE_METRICS.letterKeyHeight).assertFalse();
        expect(PORTRAIT_METRICS.rowSpacing === LANDSCAPE_METRICS.rowSpacing).assertFalse();
        expect(PORTRAIT_METRICS.keySpacing === LANDSCAPE_METRICS.keySpacing).assertFalse();
      });

      it('Landscape metrics are more compact than portrait', 0, () => {
        expect(LANDSCAPE_METRICS.letterKeyHeight < PORTRAIT_METRICS.letterKeyHeight).assertTrue();
        expect(LANDSCAPE_METRICS.rowSpacing <= PORTRAIT_METRICS.rowSpacing).assertTrue();
      });

      it('getMetricsForOrientation returns correct metrics', 0, () => {
        const portraitMetrics = getMetricsForOrientation(false);
        const landscapeMetrics = getMetricsForOrientation(true);

        expect(portraitMetrics.letterKeyHeight).assertEqual(PORTRAIT_METRICS.letterKeyHeight);
        expect(landscapeMetrics.letterKeyHeight).assertEqual(LANDSCAPE_METRICS.letterKeyHeight);
      });

      it('calculateTotalKeyboardHeight is reasonable', 0, () => {
        const portraitHeight = calculateTotalKeyboardHeight(PORTRAIT_METRICS);
        const landscapeHeight = calculateTotalKeyboardHeight(LANDSCAPE_METRICS);

        expect(portraitHeight > 200).assertTrue();
        expect(portraitHeight < 2000).assertTrue();
        expect(landscapeHeight < portraitHeight).assertTrue();
      });

      it('KEY_WEIGHTS contains expected keys', 0, () => {
        expect(KEY_WEIGHTS.LETTER).assertEqual(1);
        expect(KEY_WEIGHTS.SPACE > KEY_WEIGHTS.LETTER).assertTrue();
        expect(KEY_WEIGHTS.DELETE > KEY_WEIGHTS.LETTER).assertTrue();
      });

      it('DELETE_REPEAT_CONFIG has reasonable values', 0, () => {
        expect(DELETE_REPEAT_CONFIG.LONG_PRESS_DELAY_MS > 100).assertTrue();
        expect(DELETE_REPEAT_CONFIG.LONG_PRESS_DELAY_MS < 2000).assertTrue();
        expect(DELETE_REPEAT_CONFIG.REPEAT_INTERVAL_MS > 10).assertTrue();
        expect(DELETE_REPEAT_CONFIG.REPEAT_INTERVAL_MS < 200).assertTrue();
      });
    });

    describe('KeyboardPalette', () => {
      it('Light and dark palettes have different colors', 0, () => {
        expect(LIGHT_PALETTE.panelBackground === DARK_PALETTE.panelBackground).assertFalse();
        expect(LIGHT_PALETTE.letterKeyText === DARK_PALETTE.letterKeyText).assertFalse();
        expect(LIGHT_PALETTE.letterKeyBackground === DARK_PALETTE.letterKeyBackground).assertFalse();
      });

      it('getPaletteForColorMode returns correct palette', 0, () => {
        const lightPalette = getPaletteForColorMode(false);
        const darkPalette = getPaletteForColorMode(true);

        expect(lightPalette.panelBackground).assertEqual(LIGHT_PALETTE.panelBackground);
        expect(darkPalette.panelBackground).assertEqual(DARK_PALETTE.panelBackground);
      });

      it('Mode switch keys have different colors for different modes', 0, () => {
        expect(LIGHT_PALETTE.modeKeyBackgroundEnglish === LIGHT_PALETTE.modeKeyBackgroundChinese).assertFalse();
        expect(LIGHT_PALETTE.modeKeyTextEnglish === LIGHT_PALETTE.modeKeyTextChinese).assertFalse();
      });

      it('uses the normal function-key text color for Chinese ϟ12 only', 0, () => {
        expect(resolveModeSwitchKeyTextColor('number', KeyboardMode.CHINESE, LIGHT_PALETTE))
          .assertEqual(LIGHT_PALETTE.functionKeyText);
        expect(resolveModeSwitchKeyTextColor('mode-switch', KeyboardMode.CHINESE, LIGHT_PALETTE))
          .assertEqual(LIGHT_PALETTE.modeKeyTextChinese);
        expect(resolveModeSwitchKeyTextColor('number', KeyboardMode.ENGLISH, LIGHT_PALETTE))
          .assertEqual(LIGHT_PALETTE.modeKeyTextEnglish);
      });
    });

    describe('DeleteRepeatController', () => {
      it('starts in inactive state', 0, () => {
        let deleteCount = 0;
        const controller = new DeleteRepeatController(() => {
          deleteCount++;
        });

        expect(controller.isActivated()).assertFalse();
        controller.destroy();
      });

      it('becomes active when started', 0, () => {
        let deleteCount = 0;
        const controller = new DeleteRepeatController(() => {
          deleteCount++;
        });

        controller.start();
        expect(controller.isActivated()).assertTrue();
        controller.destroy();
      });

      it('becomes inactive when stopped', 0, () => {
        let deleteCount = 0;
        const controller = new DeleteRepeatController(() => {
          deleteCount++;
        });

        controller.start();
        controller.stop();
        expect(controller.isActivated()).assertFalse();
        controller.destroy();
      });

      it('single delete does not activate repeat', 0, () => {
        let deleteCount = 0;
        const controller = new DeleteRepeatController(() => {
          deleteCount++;
        });

        controller.triggerSingleDelete();
        expect(controller.isActivated()).assertFalse();
        expect(deleteCount).assertEqual(1);
        controller.destroy();
      });

      it('does not start repeat if already active', 0, () => {
        let deleteCount = 0;
        const controller = new DeleteRepeatController(() => {
          deleteCount++;
        });

        controller.start();
        controller.start();
        expect(controller.isActivated()).assertTrue();
        controller.destroy();
      });

      it('starts and stops repeat without residual timer', 0, async () => {
        let deleteCount = 0;
        const controller = new DeleteRepeatController(() => {
          deleteCount++;
        });

        controller.start();
        expect(controller.isActivated()).assertTrue();
        await delay(600);

        controller.stop();
        expect(controller.isActivated()).assertFalse();
        const countAfterStop = deleteCount;
        await delay(100);

        expect(deleteCount).assertEqual(countAfterStop);
        controller.destroy();
      });

      it('clears all timers on destroy', 0, async () => {
        let deleteCount = 0;
        const controller = new DeleteRepeatController(() => {
          deleteCount++;
        });

        controller.start();
        controller.destroy();

        const countAtDestroy = deleteCount;
        await delay(700);
        expect(deleteCount).assertEqual(countAtDestroy);
      });

      it('uses the configured long-press delay for repeat deletion', 0, async () => {
        let deleteCount = 0;
        const controller = new DeleteRepeatController(() => {
          deleteCount++;
        }, 5);

        controller.start();
        await delay(20);
        controller.stop();
        expect(deleteCount > 0).assertTrue();
        controller.destroy();
      });
    });

    describe('Stage 2 Backward Compatibility', () => {
      it('QWERTY_KEY_ROWS maintains Stage 2 structure', 0, () => {
        expect(Array.isArray(QWERTY_KEY_ROWS)).assertTrue();
        expect(QWERTY_KEY_ROWS.length).assertEqual(4);

        QWERTY_KEY_ROWS.forEach((row: LegacyKeyboardKeySpec[]) => {
          expect(Array.isArray(row)).assertTrue();
          expect(row.length > 0).assertTrue();
        });
      });

      it('Legacy keys have required properties', 0, () => {
        const firstKey = QWERTY_KEY_ROWS[0][0];
        expect(firstKey.id.length > 0).assertTrue();
        expect(firstKey.label.length > 0).assertTrue();
        expect(firstKey.role.length > 0).assertTrue();
        expect(firstKey.weight > 0).assertTrue();
        expect(firstKey.action.type.length > 0).assertTrue();
      });
    });
  });
}
