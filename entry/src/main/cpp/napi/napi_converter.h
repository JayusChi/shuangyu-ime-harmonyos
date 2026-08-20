#ifndef NAPI_CONVERTER_H
#define NAPI_CONVERTER_H

#include "napi/native_api.h"

#include <string>

napi_value CreateString(napi_env env, const std::string& value);
napi_value CreateErrorResult(napi_env env, int32_t errorCode, const std::string& message);
napi_value CreateCompositionErrorResult(napi_env env, int32_t errorCode, const std::string& message);
napi_value ConvertEngineJsonToArkObject(napi_env env, const std::string& json);
napi_value ConvertCompositionJsonToArkObject(napi_env env, const std::string& json);
napi_value ConvertUserModelStatusJsonToArkObject(napi_env env, const std::string& json);

#endif
