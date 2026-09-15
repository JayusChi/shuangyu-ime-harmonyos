#include "rust_engine_handle.h"

#include "native_error.h"
#include "rust_buffer.h"

#include <utility>

namespace {
RustCallResult CopyResult(int32_t code, RustBuffer& buffer) {
    if (code != IME_SUCCESS) {
        return {code, RustBuffer()};
    }
    if (buffer.Empty()) {
        return {IME_BUFFER_ALLOCATION_FAILED, RustBuffer()};
    }
    return {code, std::move(buffer)};
}
} // namespace

RustEngineHandle::RustEngineHandle() : handle_(nullptr) {}

RustEngineHandle::RustEngineHandle(ImeEngineHandle handle) : handle_(handle) {}

RustEngineHandle::~RustEngineHandle() {
    Destroy();
}

RustEngineHandle::RustEngineHandle(RustEngineHandle&& other) noexcept : handle_(other.handle_) {
    other.handle_ = nullptr;
}

RustEngineHandle& RustEngineHandle::operator=(RustEngineHandle&& other) noexcept {
    if (this != &other) {
        Destroy();
        handle_ = other.handle_;
        other.handle_ = nullptr;
    }
    return *this;
}

RustCallResult RustEngineHandle::Create(const std::string& config, RustEngineHandle& out) {
    ImeEngineHandle rawHandle = nullptr;
    auto* bytes = reinterpret_cast<const uint8_t*>(config.data());
    int32_t code = ime_engine_create(bytes, config.length(), &rawHandle);
    if (code != IME_SUCCESS) {
        return {code, RustBuffer()};
    }
    if (rawHandle == nullptr) {
        return {IME_INVALID_HANDLE, RustBuffer()};
    }
    out = RustEngineHandle(rawHandle);
    return {IME_SUCCESS, RustBuffer()};
}

RustCallResult RustEngineHandle::ProcessKey(const std::string& key) {
    RustBuffer buffer;
    auto* bytes = reinterpret_cast<const uint8_t*>(key.data());
    int32_t code = ime_engine_process_key(handle_, bytes, key.length(), buffer.Out());
    return CopyResult(code, buffer);
}

RustCallResult RustEngineHandle::InsertSegmentBoundary() {
    RustBuffer buffer;
    int32_t code = ime_engine_insert_segment_boundary(handle_, buffer.Out());
    return CopyResult(code, buffer);
}

RustCallResult RustEngineHandle::Backspace() {
    RustBuffer buffer;
    int32_t code = ime_engine_backspace(handle_, buffer.Out());
    return CopyResult(code, buffer);
}

RustCallResult RustEngineHandle::Reset() {
    RustBuffer buffer;
    int32_t code = ime_engine_reset(handle_, buffer.Out());
    return CopyResult(code, buffer);
}

RustCallResult RustEngineHandle::ChangeScheme(const std::string& schemeId) {
    RustBuffer buffer;
    auto* bytes = reinterpret_cast<const uint8_t*>(schemeId.data());
    int32_t code = ime_engine_change_scheme(handle_, bytes, schemeId.length(), buffer.Out());
    return CopyResult(code, buffer);
}

RustCallResult RustEngineHandle::SelectCandidate(size_t candidateIndex) {
    RustBuffer buffer;
    int32_t code = ime_engine_select_candidate(handle_, candidateIndex, buffer.Out());
    return CopyResult(code, buffer);
}

RustCallResult RustEngineHandle::SelectPinyinCombination(size_t combinationIndex) {
    RustBuffer buffer;
    int32_t code = ime_engine_select_pinyin_combination(handle_, combinationIndex, buffer.Out());
    return CopyResult(code, buffer);
}

RustCallResult RustEngineHandle::NextCandidatePage() {
    RustBuffer buffer;
    int32_t code = ime_engine_next_candidate_page(handle_, buffer.Out());
    return CopyResult(code, buffer);
}

RustCallResult RustEngineHandle::PreviousCandidatePage() {
    RustBuffer buffer;
    int32_t code = ime_engine_previous_candidate_page(handle_, buffer.Out());
    return CopyResult(code, buffer);
}

RustCallResult RustEngineHandle::ReverseLookup(const std::string& text) {
    RustBuffer buffer;
    int32_t code = ime_engine_reverse_lookup(handle_, reinterpret_cast<const uint8_t*>(text.data()), text.size(), buffer.Out());
    return CopyResult(code, buffer);
}

RustCallResult RustEngineHandle::GetLocalAssociations() {
    RustBuffer buffer;
    int32_t code = ime_engine_get_local_associations(handle_, buffer.Out());
    return CopyResult(code, buffer);
}

RustCallResult RustEngineHandle::GetCodeTableCategoryConfig() {
    RustBuffer buffer;
    int32_t code = ime_engine_get_code_table_category_config(handle_, buffer.Out());
    return CopyResult(code, buffer);
}

RustCallResult RustEngineHandle::SetCodeTableCategories(const std::string& categoryIdsJson) {
    RustBuffer buffer;
    auto* bytes = reinterpret_cast<const uint8_t*>(categoryIdsJson.data());
    int32_t code = ime_engine_set_code_table_categories(
        handle_, bytes, categoryIdsJson.length(), buffer.Out());
    return CopyResult(code, buffer);
}

RustCallResult RustEngineHandle::SetCodeTableCommitPolicy(const std::string& policyJson) {
    RustBuffer buffer;
    auto* bytes = reinterpret_cast<const uint8_t*>(policyJson.data());
    int32_t code = ime_engine_set_code_table_commit_policy(
        handle_, bytes, policyJson.length(), buffer.Out());
    return CopyResult(code, buffer);
}

RustCallResult RustEngineHandle::ReloadUserLexicon() {
    RustBuffer buffer;
    int32_t code = ime_engine_reload_user_lexicon(handle_, buffer.Out());
    return CopyResult(code, buffer);
}

RustCallResult RustEngineHandle::SetUserModelPath(const std::string& path) {
    RustBuffer buffer;
    auto* bytes = reinterpret_cast<const uint8_t*>(path.data());
    int32_t code = ime_engine_set_user_model_path(handle_, bytes, path.length(), buffer.Out());
    return CopyResult(code, buffer);
}

RustCallResult RustEngineHandle::LoadUserModel() {
    RustBuffer buffer;
    int32_t code = ime_engine_load_user_model(handle_, buffer.Out());
    return CopyResult(code, buffer);
}

RustCallResult RustEngineHandle::FlushUserModel() {
    RustBuffer buffer;
    int32_t code = ime_engine_flush_user_model(handle_, buffer.Out());
    return CopyResult(code, buffer);
}

RustCallResult RustEngineHandle::ClearUserModel() {
    RustBuffer buffer;
    int32_t code = ime_engine_clear_user_model(handle_, buffer.Out());
    return CopyResult(code, buffer);
}

RustCallResult RustEngineHandle::SetUserLearningEnabled(bool enabled) {
    RustBuffer buffer;
    int32_t code = ime_engine_set_user_learning_enabled(handle_, enabled, buffer.Out());
    return CopyResult(code, buffer);
}

RustCallResult RustEngineHandle::SetSessionLearningAllowed(bool allowed) {
    RustBuffer buffer;
    int32_t code = ime_engine_set_session_learning_allowed(handle_, allowed, buffer.Out());
    return CopyResult(code, buffer);
}

int32_t RustEngineHandle::Destroy() {
    if (handle_ == nullptr) {
        return IME_SUCCESS;
    }
    return ime_engine_destroy(&handle_);
}

bool RustEngineHandle::IsValid() const {
    return handle_ != nullptr;
}
