#ifndef IME_ENGINE_FFI_H
#define IME_ENGINE_FFI_H

#include <stddef.h>
#include <stdint.h>
#ifndef __cplusplus
#include <stdbool.h>
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ImeBuffer {
    uint8_t* data;
    size_t len;
} ImeBuffer;

typedef struct ImeEngineOpaque ImeEngineOpaque;
typedef ImeEngineOpaque* ImeEngineHandle;

uint32_t ime_engine_get_abi_version(void);

int32_t ime_engine_get_version(ImeBuffer* out_buffer);

int32_t ime_engine_create(const uint8_t* config_utf8, size_t config_len, ImeEngineHandle* out_handle);

int32_t ime_engine_process_key(ImeEngineHandle handle, const uint8_t* key_utf8, size_t key_len, ImeBuffer* out_buffer);

int32_t ime_engine_insert_segment_boundary(ImeEngineHandle handle, ImeBuffer* out_buffer);

int32_t ime_engine_backspace(ImeEngineHandle handle, ImeBuffer* out_buffer);

int32_t ime_engine_reset(ImeEngineHandle handle, ImeBuffer* out_buffer);

int32_t ime_engine_change_scheme(ImeEngineHandle handle, const uint8_t* scheme_utf8, size_t scheme_len, ImeBuffer* out_buffer);

int32_t ime_engine_select_candidate(ImeEngineHandle handle, size_t candidate_index, ImeBuffer* out_buffer);

int32_t ime_engine_select_pinyin_combination(
    ImeEngineHandle handle, size_t combination_index, ImeBuffer* out_buffer);

int32_t ime_engine_next_candidate_page(ImeEngineHandle handle, ImeBuffer* out_buffer);

int32_t ime_engine_previous_candidate_page(ImeEngineHandle handle, ImeBuffer* out_buffer);

int32_t ime_engine_get_code_table_category_config(ImeEngineHandle handle, ImeBuffer* out_buffer);

int32_t ime_engine_set_code_table_categories(
    ImeEngineHandle handle,
    const uint8_t* category_ids_json_utf8,
    size_t category_ids_json_len,
    ImeBuffer* out_buffer);

int32_t ime_engine_reload_user_lexicon(ImeEngineHandle handle, ImeBuffer* out_buffer);

int32_t ime_user_lexicon_load(
    const uint8_t* path_utf8, size_t path_len, ImeBuffer* out_buffer);

int32_t ime_user_lexicon_save(
    const uint8_t* path_utf8,
    size_t path_len,
    const uint8_t* expected_revision_utf8,
    size_t expected_revision_len,
    const uint8_t* content_utf8,
    size_t content_len,
    ImeBuffer* out_buffer);

int32_t ime_engine_set_user_model_path(
    ImeEngineHandle handle, const uint8_t* path_utf8, size_t path_len, ImeBuffer* out_buffer);

int32_t ime_engine_load_user_model(ImeEngineHandle handle, ImeBuffer* out_buffer);

int32_t ime_engine_flush_user_model(ImeEngineHandle handle, ImeBuffer* out_buffer);

int32_t ime_engine_clear_user_model(ImeEngineHandle handle, ImeBuffer* out_buffer);

int32_t ime_engine_set_user_learning_enabled(ImeEngineHandle handle, bool enabled, ImeBuffer* out_buffer);

int32_t ime_engine_set_session_learning_allowed(ImeEngineHandle handle, bool allowed, ImeBuffer* out_buffer);

int32_t ime_engine_destroy(ImeEngineHandle* handle);

int32_t ime_engine_free_buffer(ImeBuffer* buffer);


#ifdef __cplusplus
}
#endif

#endif
