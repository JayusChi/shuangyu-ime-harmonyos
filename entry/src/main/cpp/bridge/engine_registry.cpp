#include "engine_registry.h"

#include "native_error.h"

EngineRegistry& EngineRegistry::Instance() {
    static EngineRegistry registry;
    return registry;
}

EngineCreateResult EngineRegistry::Create(const std::string& config) {
    RustEngineHandle handle;
    RustCallResult created = RustEngineHandle::Create(config, handle);
    if (created.code != IME_SUCCESS) {
        return {created.code, 0};
    }

    std::lock_guard<std::mutex> lock(mutex_);
    uint32_t id = NextIdLocked();
    engines_.emplace(id, std::move(handle));
    return {IME_SUCCESS, id};
}

int32_t EngineRegistry::Destroy(uint32_t id) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto found = engines_.find(id);
    if (found == engines_.end()) {
        return IME_INVALID_HANDLE;
    }
    engines_.erase(found);
    return IME_SUCCESS;
}

RustCallResult EngineRegistry::ProcessKey(uint32_t id, const std::string& key) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto found = engines_.find(id);
    if (found == engines_.end()) {
        return {IME_INVALID_HANDLE, RustBuffer()};
    }
    return found->second.ProcessKey(key);
}

RustCallResult EngineRegistry::InsertSegmentBoundary(uint32_t id) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto found = engines_.find(id);
    if (found == engines_.end()) {
        return {IME_INVALID_HANDLE, RustBuffer()};
    }
    return found->second.InsertSegmentBoundary();
}

RustCallResult EngineRegistry::Backspace(uint32_t id) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto found = engines_.find(id);
    if (found == engines_.end()) {
        return {IME_INVALID_HANDLE, RustBuffer()};
    }
    return found->second.Backspace();
}

RustCallResult EngineRegistry::Reset(uint32_t id) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto found = engines_.find(id);
    if (found == engines_.end()) {
        return {IME_INVALID_HANDLE, RustBuffer()};
    }
    return found->second.Reset();
}

RustCallResult EngineRegistry::ChangeScheme(uint32_t id, const std::string& schemeId) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto found = engines_.find(id);
    if (found == engines_.end()) {
        return {IME_INVALID_HANDLE, RustBuffer()};
    }
    return found->second.ChangeScheme(schemeId);
}

RustCallResult EngineRegistry::SelectCandidate(uint32_t id, size_t candidateIndex) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto found = engines_.find(id);
    if (found == engines_.end()) {
        return {IME_INVALID_HANDLE, RustBuffer()};
    }
    return found->second.SelectCandidate(candidateIndex);
}

RustCallResult EngineRegistry::SelectPinyinCombination(uint32_t id, size_t combinationIndex) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto found = engines_.find(id);
    if (found == engines_.end()) {
        return {IME_INVALID_HANDLE, RustBuffer()};
    }
    return found->second.SelectPinyinCombination(combinationIndex);
}

RustCallResult EngineRegistry::NextCandidatePage(uint32_t id) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto found = engines_.find(id);
    if (found == engines_.end()) {
        return {IME_INVALID_HANDLE, RustBuffer()};
    }
    return found->second.NextCandidatePage();
}

RustCallResult EngineRegistry::PreviousCandidatePage(uint32_t id) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto found = engines_.find(id);
    if (found == engines_.end()) {
        return {IME_INVALID_HANDLE, RustBuffer()};
    }
    return found->second.PreviousCandidatePage();
}

RustCallResult EngineRegistry::GetLocalAssociations(uint32_t id) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto found = engines_.find(id);
    if (found == engines_.end()) {
        return {IME_INVALID_HANDLE, RustBuffer()};
    }
    return found->second.GetLocalAssociations();
}

RustCallResult EngineRegistry::GetCodeTableCategoryConfig(uint32_t id) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto found = engines_.find(id);
    if (found == engines_.end()) {
        return {IME_INVALID_HANDLE, RustBuffer()};
    }
    return found->second.GetCodeTableCategoryConfig();
}

RustCallResult EngineRegistry::SetCodeTableCategories(uint32_t id, const std::string& categoryIdsJson) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto found = engines_.find(id);
    if (found == engines_.end()) {
        return {IME_INVALID_HANDLE, RustBuffer()};
    }
    return found->second.SetCodeTableCategories(categoryIdsJson);
}

RustCallResult EngineRegistry::SetCodeTableCommitPolicy(uint32_t id, const std::string& policyJson) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto found = engines_.find(id);
    if (found == engines_.end()) {
        return {IME_INVALID_HANDLE, RustBuffer()};
    }
    return found->second.SetCodeTableCommitPolicy(policyJson);
}

RustCallResult EngineRegistry::ReloadUserLexicon(uint32_t id) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto found = engines_.find(id);
    if (found == engines_.end()) {
        return {IME_INVALID_HANDLE, RustBuffer()};
    }
    return found->second.ReloadUserLexicon();
}

RustCallResult EngineRegistry::SetUserModelPath(uint32_t id, const std::string& path) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto found = engines_.find(id);
    if (found == engines_.end()) {
        return {IME_INVALID_HANDLE, RustBuffer()};
    }
    return found->second.SetUserModelPath(path);
}

RustCallResult EngineRegistry::LoadUserModel(uint32_t id) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto found = engines_.find(id);
    if (found == engines_.end()) {
        return {IME_INVALID_HANDLE, RustBuffer()};
    }
    return found->second.LoadUserModel();
}

RustCallResult EngineRegistry::FlushUserModel(uint32_t id) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto found = engines_.find(id);
    if (found == engines_.end()) {
        return {IME_INVALID_HANDLE, RustBuffer()};
    }
    return found->second.FlushUserModel();
}

RustCallResult EngineRegistry::ClearUserModel(uint32_t id) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto found = engines_.find(id);
    if (found == engines_.end()) {
        return {IME_INVALID_HANDLE, RustBuffer()};
    }
    return found->second.ClearUserModel();
}

RustCallResult EngineRegistry::SetUserLearningEnabled(uint32_t id, bool enabled) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto found = engines_.find(id);
    if (found == engines_.end()) {
        return {IME_INVALID_HANDLE, RustBuffer()};
    }
    return found->second.SetUserLearningEnabled(enabled);
}

RustCallResult EngineRegistry::SetSessionLearningAllowed(uint32_t id, bool allowed) {
    std::lock_guard<std::mutex> lock(mutex_);
    auto found = engines_.find(id);
    if (found == engines_.end()) {
        return {IME_INVALID_HANDLE, RustBuffer()};
    }
    return found->second.SetSessionLearningAllowed(allowed);
}

void EngineRegistry::Clear() {
    std::lock_guard<std::mutex> lock(mutex_);
    engines_.clear();
}

uint32_t EngineRegistry::NextIdLocked() {
    while (nextId_ == 0 || engines_.find(nextId_) != engines_.end()) {
        ++nextId_;
    }
    uint32_t id = nextId_;
    ++nextId_;
    return id;
}
