#ifndef RUST_ENGINE_HANDLE_H
#define RUST_ENGINE_HANDLE_H

#include "rust_engine_bridge.h"
#include "ime_engine_ffi.h"

#include <string>

class RustEngineHandle {
  public:
    RustEngineHandle();
    explicit RustEngineHandle(ImeEngineHandle handle);
    ~RustEngineHandle();

    RustEngineHandle(const RustEngineHandle&) = delete;
    RustEngineHandle& operator=(const RustEngineHandle&) = delete;

    RustEngineHandle(RustEngineHandle&& other) noexcept;
    RustEngineHandle& operator=(RustEngineHandle&& other) noexcept;

    static RustCallResult Create(const std::string& config, RustEngineHandle& out);

    RustCallResult ProcessKey(const std::string& key);
    RustCallResult InsertSegmentBoundary();
    RustCallResult Backspace();
    RustCallResult Reset();
    RustCallResult ChangeScheme(const std::string& schemeId);
    RustCallResult SelectCandidate(size_t candidateIndex);
    RustCallResult SelectPinyinCombination(size_t combinationIndex);
    RustCallResult NextCandidatePage();
    RustCallResult PreviousCandidatePage();
    RustCallResult GetLocalAssociations();
    RustCallResult GetCodeTableCategoryConfig();
    RustCallResult SetCodeTableCategories(const std::string& categoryIdsJson);
    RustCallResult ReloadUserLexicon();
    RustCallResult SetUserModelPath(const std::string& path);
    RustCallResult LoadUserModel();
    RustCallResult FlushUserModel();
    RustCallResult ClearUserModel();
    RustCallResult SetUserLearningEnabled(bool enabled);
    RustCallResult SetSessionLearningAllowed(bool allowed);
    int32_t Destroy();
    bool IsValid() const;

  private:
    ImeEngineHandle handle_;
};

#endif
