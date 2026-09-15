from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
BACKUP = ROOT / 'outputs' / 'clipboard-reverse-before'
def edit(name, transform):
    path = ROOT / name
    data = path.read_bytes()
    backup = BACKUP / name
    if not backup.exists():
        backup.parent.mkdir(parents=True, exist_ok=True)
        backup.write_bytes(data)
    text = data.decode('utf-8-sig').replace('\r\n', '\n')
    result = transform(text)
    if result == text: raise RuntimeError('No change: ' + name)
    original = backup.read_bytes()
    encoding = 'utf-8-sig' if original.startswith(b'\xef\xbb\xbf') else 'utf-8'
    temporary = path.with_name(path.name + '.ofi.tmp')
    assert temporary.resolve().is_relative_to(ROOT)
    temporary.write_bytes(result.replace('\n', '\r\n' if b'\r\n' in data else '\n').encode(encoding))
    temporary.replace(path)
def replace(name, old, new):
    def apply(text):
        if text.count(old) != 1: raise RuntimeError(f'{name}: expected one match, got {text.count(old)}: {old[:80]}')
        return text.replace(old,new)
    edit(name, apply)

replace('engine-rust/crates/code-table-runtime/src/state.rs', 'impl CodeTableStateMachine {', '''impl CodeTableStateMachine {
    /// Read-only lookup includes hidden character categories, so full codes
    /// remain discoverable even when their extra candidates are disabled.
    pub fn reverse_lookup(&self, text: &str) -> Vec<String> {
        let mut chars = text.chars();
        let Some(character) = chars.next() else { return Vec::new() };
        if chars.next().is_some()
            || !matches!(character as u32, 0x3007 | 0x3400..=0x9fff | 0xf900..=0xfaff | 0x20000..=0x323af)
        {
            return Vec::new();
        }
        let mut codes = std::collections::BTreeSet::new();
        for category in &self.bundle.categories {
            if category.id == QUICK_SYMBOL_CATEGORY_ID { continue; }
            for entry in &category.lexicon.entries {
                if entry.text == text { codes.insert(entry.pinyin_key.clone()); }
            }
        }
        for entry in self.user_lexicon.entries().iter().filter(|entry| entry.text == text) {
            match entry.action {
                UserLexiconAction::Delete => { codes.remove(&entry.code); }
                UserLexiconAction::Add | UserLexiconAction::Fixed | UserLexiconAction::Position(_) => {
                    codes.insert(entry.code.clone());
                }
                _ => {}
            }
        }
        let mut codes = codes.into_iter()
            .filter(|code| (1..=4).contains(&code.len()) && code.bytes().all(|byte| byte.is_ascii_lowercase()))
            .collect::<Vec<_>>();
        codes.sort_by(|left, right| right.len().cmp(&left.len()).then_with(|| left.cmp(right)));
        codes.truncate(64);
        codes
    }
''')
replace('engine-rust/crates/ime-engine/src/formal/composition_state.rs', 'impl ImeEngine {', '''impl ImeEngine {
    pub fn reverse_lookup(&self, text: &str) -> Vec<String> {
        match &self.backend {
            EngineBackend::CodeTable(machine) => machine.reverse_lookup(text),
            _ => Vec::new(),
        }
    }
''')
replace('engine-rust/crates/code-table-runtime/src/action.rs', 'fn trusted_direct_control(action: &str, target: &str) -> bool {\n    match action {', 'fn trusted_direct_control(action: &str, target: &str) -> bool {\n    match action {\n        "clipboard.reverse" => target.is_empty(),')
replace('engine-rust/crates/ime-ffi/src/ffi/exports.rs', '#[no_mangle]\npub extern "C" fn ime_engine_get_code_table_category_config(', '''#[no_mangle]
/// # Safety
/// `text_utf8` must reference `text_len` readable bytes for the duration of the call.
pub unsafe extern "C" fn ime_engine_reverse_lookup(
    handle: *mut ImeEngineOpaque,
    text_utf8: *const u8,
    text_len: usize,
    out_buffer: *mut ImeBuffer,
) -> i32 {
    clear_out_buffer(out_buffer);
    catch_ffi(|| {
        if text_len > 4 { return ImeErrorCode::InvalidArgument.as_i32(); }
        let text = match read_input_utf8(text_utf8, text_len) {
            Ok(value) => value,
            Err(code) => return code.as_i32(),
        };
        let engine = match engine_from_handle(handle) {
            Ok(value) => value,
            Err(code) => return code.as_i32(),
        };
        write_owned_output(out_buffer, association_suggestions_json(&engine.engine.reverse_lookup(&text)))
    })
}

#[no_mangle]
pub extern "C" fn ime_engine_get_code_table_category_config(''')
replace('scripts/import-shuangyu-customer-lexicon.ps1', '        switch -CaseSensitive ($operation) {', '''        switch -CaseSensitive ($operation) {
            '$CC(default(dict.rev(clip()), "[复制反查]"), type(dict.rev(clip())))' { $record.type = 'DIRECT_CONTROL'; $record.action = 'clipboard.reverse'; $record.target = ''; $record.label = '[复制反查]' }''')

# Carry the read-only API through the existing C ABI, handle registry and N-API layers.
for name, old, new in [
    ('entry/src/main/cpp/include/ime_engine_ffi.h', 'int32_t ime_engine_get_local_associations(ImeEngineHandle handle, ImeBuffer* out_buffer);', 'int32_t ime_engine_reverse_lookup(ImeEngineHandle handle, const uint8_t* text_utf8, size_t text_len, ImeBuffer* out_buffer);'),
    ('entry/src/main/cpp/bridge/rust_engine_handle.h', '    RustCallResult GetLocalAssociations();', '    RustCallResult ReverseLookup(const std::string& text);'),
    ('entry/src/main/cpp/bridge/engine_registry.h', '    RustCallResult GetLocalAssociations(uint32_t id);', '    RustCallResult ReverseLookup(uint32_t id, const std::string& text);'),
    ('entry/src/main/cpp/bridge/rust_engine_bridge.h', 'RustCallResult GetRegisteredEngineLocalAssociations(uint32_t id);', 'RustCallResult ReverseLookupRegisteredEngine(uint32_t id, const std::string& text);'),
    ('entry/src/main/cpp/napi/engine_napi.h', 'napi_value GetLocalAssociations(napi_env env, napi_callback_info info);', 'napi_value ReverseLookup(napi_env env, napi_callback_info info);'),
    ('entry/src/main/cpp/napi/module_init.cpp', '        {"getLocalAssociations", nullptr, GetLocalAssociations, nullptr, nullptr, nullptr, napi_default, nullptr},', '        {"reverseLookup", nullptr, ReverseLookup, nullptr, nullptr, nullptr, napi_default, nullptr},'),
    ('entry/src/main/types/libime_bridge/index.d.ts', '  getLocalAssociations(handle: number): string;', '  reverseLookup(handle: number, text: string): string;'),
    ('entry/src/main/types/libime_bridge/index.d.ts', 'export const getLocalAssociations: (handle: number) => string;', 'export const reverseLookup: (handle: number, text: string) => string;'),
    ('entry/src/main/ets/infrastructure/native/NativeEngineTypes.ets', '  getLocalAssociations?(handle: number): string[];', '  reverseLookup?(handle: number, text: string): string[];'),
]: replace(name, old, old + '\n' + new)

replace('entry/src/main/cpp/bridge/rust_engine_handle.cpp', 'RustCallResult RustEngineHandle::GetLocalAssociations() {', '''RustCallResult RustEngineHandle::ReverseLookup(const std::string& text) {
    RustBuffer buffer;
    int32_t code = ime_engine_reverse_lookup(handle_, reinterpret_cast<const uint8_t*>(text.data()), text.size(), buffer.Out());
    return CopyResult(code, buffer);
}

RustCallResult RustEngineHandle::GetLocalAssociations() {''')
replace('entry/src/main/cpp/bridge/engine_registry.cpp', 'RustCallResult EngineRegistry::GetLocalAssociations(uint32_t id) {', '''RustCallResult EngineRegistry::ReverseLookup(uint32_t id, const std::string& text) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto found = engines_.find(id);
    if (found == engines_.end()) { return {IME_INVALID_HANDLE, RustBuffer()}; }
    return found->second.ReverseLookup(text);
}

RustCallResult EngineRegistry::GetLocalAssociations(uint32_t id) {''')
replace('entry/src/main/cpp/bridge/rust_engine_bridge.cpp', 'RustCallResult GetRegisteredEngineLocalAssociations(uint32_t id) {', '''RustCallResult ReverseLookupRegisteredEngine(uint32_t id, const std::string& text) {
    return EngineRegistry::Instance().ReverseLookup(id, text);
}

RustCallResult GetRegisteredEngineLocalAssociations(uint32_t id) {''')
replace('entry/src/main/cpp/napi/engine_napi.cpp', 'napi_value GetLocalAssociations(napi_env env, napi_callback_info info) {', '''napi_value ReverseLookup(napi_env env, napi_callback_info info) {
    uint32_t handle = 0;
    std::string text;
    if (!ReadHandleAndStringArguments(env, info, handle, text) || text.size() > 4) {
        ThrowNativeError(env, IME_INVALID_ARGUMENT, "reverseLookup requires handle and one character");
        return nullptr;
    }
    RustCallResult result = ReverseLookupRegisteredEngine(handle, text);
    if (result.code != IME_SUCCESS) {
        ThrowNativeError(env, result.code, ErrorMessageForCode(result.code));
        return nullptr;
    }
    return CreateString(env, result.payload);
}

napi_value GetLocalAssociations(napi_env env, napi_callback_info info) {''')
replace('entry/src/main/ets/infrastructure/native/NativeEngineGateway.ets', '  getLocalAssociations(handle: number): string[] {', '''  reverseLookup(handle: number, text: string): string[] {
    try {
      const values = JSON.parse(imeBridge.reverseLookup(handle, text)) as string[];
      if (!Array.isArray(values) || values.length > 64 ||
        values.some((code: string): boolean => typeof code !== 'string' || !/^[a-z]{1,4}$/.test(code))) {
        return [];
      }
      return values.filter((code: string, index: number): boolean => values.indexOf(code) === index);
    } catch (_) { return []; }
  }

  getLocalAssociations(handle: number): string[] {''')
replace('entry/src/main/ets/application/EngineCoordinator.ets', '  getLocalAssociations(): string[] {', '''  reverseLookup(text: string): string[] {
    if (!this.ensureInitialized() || this.gateway.reverseLookup === undefined) { return []; }
    return this.gateway.reverseLookup(this.handle, text);
  }

  getLocalAssociations(): string[] {''')
replace('entry/src/main/ets/infrastructure/native/NativeEngineGateway.ets', "      value.formatId === 'editor.delete-line')", "      value.formatId === 'editor.delete-line' || value.formatId === 'clipboard.reverse')")
replace('entry/src/main/ets/infrastructure/native/NativeEngineGateway.ets', '  private isTrustedDirectControl(action: string, target: string): boolean {', '''  private isTrustedDirectControl(action: string, target: string): boolean {
    if (action === 'clipboard.reverse') { return target.length === 0; }''')
print('Implemented engine, bridge and importer')
