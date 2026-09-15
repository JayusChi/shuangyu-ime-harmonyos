from pathlib import Path
exec((Path(__file__).parent / 'implement-clipboard-reverse.py').read_text(encoding='utf-8').split("replace('engine-rust/crates/code-table-runtime/src/state.rs'")[0])
for name in ['5.直通-规范动作.json', '5.直通-转换报告.json', '清理说明.md']:
    generated = (ROOT / 'outputs/clipboard-reverse-import' / name).read_text(encoding='utf-8')
    edit('双羽词库分类/清理后/' + name, lambda text, generated=generated: generated)
generated = (ROOT / 'outputs/clipboard-reverse-import/5.直通-规范动作.json').read_text(encoding='utf-8')
edit('engine-rust/crates/code-table-runtime/data/production-direct-actions.json', lambda text: generated)
replace('entry/src/test/List.test.ets', 'export default function testsuite() {', 'export default function testsuite() {\n  clipboardReverseLookupTest();')
edit('entry/src/test/List.test.ets', lambda text: "import clipboardReverseLookupTest from './ClipboardReverseLookup.test';\n" + text)
name = 'entry/src/test/Stage2Controller.test.ets'
replace(name, "    it('defaultKeyboardModeIsEnglish',", '''    it('clipboard reverse commits its shared displayed snapshot and never the fallback label', 0, async () => {
      for (const text of ['nirx ni', '']) {
        const store = new InputSessionStore();
        const ime = new FakeImeInputService();
        const engine = createFakeEngineCoordinator();
        engine.initialize();
        const session = new InputSessionController(store, ime, engine);
        store.markSessionStarted();
        session.toggleKeyboardMode();
        const composition = createCompositionResult('ofi', 'ofi', 'complete');
        composition.candidates = [{ id: 'reverse', text: '[复制反查]', reading: 'ofi', source: 'functional' }];
        composition.highlightedIndex = 0;
        store.updateComposition(composition);
        store.setClipboardReverseResult(store.beginClipboardReverseRequest(), { available: true, character: '你', text });
        const result = await session.commitCandidate(0);
        expect(result.success).assertTrue();
        expect(ime.insertedTexts.join('|')).assertEqual(text);
        expect(ime.clearPreviewCount).assertEqual(text.length === 0 ? 1 : 0);
        expect(store.getSnapshot().rawInput).assertEqual('');
        expect(store.getClipboardReverseResult()).assertUndefined();
      }
    });
    it('clipboard reverse rejects stale reads across edits and session changes', 0, () => {
      const store = new InputSessionStore();
      store.markSessionStarted();
      store.toggleKeyboardMode();
      const composition = createCompositionResult('ofi', 'ofi', 'complete');
      composition.candidates = [{ id: 'reverse', text: '[复制反查]', reading: 'ofi', source: 'functional' }];
      store.updateComposition(composition);
      const oldRequest = store.beginClipboardReverseRequest();
      store.updateComposition(createCompositionResult('of', 'of', 'complete'));
      store.updateComposition(composition);
      store.setClipboardReverseResult(oldRequest, { available: true, character: '你', text: 'nirx' });
      expect(store.getClipboardReverseResult()).assertUndefined();
      const current = store.beginClipboardReverseRequest();
      store.setClipboardReverseResult(current, { available: true, character: '你', text: 'nirx' });
      expect(store.getSnapshot().candidates[0].displayText).assertEqual('nirx');
      store.advanceSessionGeneration();
      store.setClipboardReverseResult(current, { available: true, character: '你', text: 'nirx' });
      expect(store.getClipboardReverseResult()).assertUndefined();
    });
    it('clipboard denial preserves the paste action in the candidate bar', 0, async () => {
      const store = new InputSessionStore();
      const ime = new FakeImeInputService();
      const engine = createFakeEngineCoordinator();
      engine.initialize();
      const session = new InputSessionController(store, ime, engine);
      store.markSessionStarted();
      session.toggleKeyboardMode();
      const composition = createCompositionResult('ofi', 'ofi', 'complete');
      composition.candidates = [{ id: 'reverse', text: '[复制反查]', reading: 'ofi', source: 'functional' }];
      store.updateComposition(composition);
      store.setClipboardReverseResult(store.beginClipboardReverseRequest(), { available: false, character: '', text: '' });
      expect((await session.commitCandidate(0)).success).assertFalse();
      expect(ime.insertedTexts.length).assertEqual(0);
      expect(store.getSnapshot().rawInput).assertEqual('ofi');
      expect(store.getSnapshot().lastErrorCode).assertEqual(ImeErrorCode.SUCCESS);
    });

    it('defaultKeyboardModeIsEnglish',''')
print('Copied generated direct actions and added ArkTS integration tests')
