#ifndef ENGINE_NAPI_H
#define ENGINE_NAPI_H

#include "napi/native_api.h"

napi_value GetEngineVersion(napi_env env, napi_callback_info info);
napi_value GetNativeBuildInfo(napi_env env, napi_callback_info info);
napi_value GetInterfaceVersion(napi_env env, napi_callback_info info);
napi_value CreateEngine(napi_env env, napi_callback_info info);
napi_value DestroyEngine(napi_env env, napi_callback_info info);
napi_value ProcessKey(napi_env env, napi_callback_info info);
napi_value InsertSegmentBoundary(napi_env env, napi_callback_info info);
napi_value Backspace(napi_env env, napi_callback_info info);
napi_value Reset(napi_env env, napi_callback_info info);
napi_value ChangeScheme(napi_env env, napi_callback_info info);
napi_value SelectCandidate(napi_env env, napi_callback_info info);
napi_value SelectPinyinCombination(napi_env env, napi_callback_info info);
napi_value NextCandidatePage(napi_env env, napi_callback_info info);
napi_value PreviousCandidatePage(napi_env env, napi_callback_info info);
napi_value GetLocalAssociations(napi_env env, napi_callback_info info);
napi_value GetCodeTableCategoryConfig(napi_env env, napi_callback_info info);
napi_value SetCodeTableCategories(napi_env env, napi_callback_info info);
napi_value ReloadUserLexicon(napi_env env, napi_callback_info info);
napi_value LoadUserLexicon(napi_env env, napi_callback_info info);
napi_value SaveUserLexicon(napi_env env, napi_callback_info info);
napi_value SetUserModelPath(napi_env env, napi_callback_info info);
napi_value LoadUserModel(napi_env env, napi_callback_info info);
napi_value FlushUserModel(napi_env env, napi_callback_info info);
napi_value ClearUserModel(napi_env env, napi_callback_info info);
napi_value SetUserLearningEnabled(napi_env env, napi_callback_info info);
napi_value SetSessionLearningAllowed(napi_env env, napi_callback_info info);

#endif
