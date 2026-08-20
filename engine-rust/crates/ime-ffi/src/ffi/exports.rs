#[no_mangle]
pub extern "C" fn ime_engine_get_abi_version() -> u32 {
    ABI_VERSION_DIRECT_ACTIONS
}

#[no_mangle]
pub extern "C" fn ime_engine_get_version(out_buffer: *mut ImeBuffer) -> i32 {
    clear_out_buffer(out_buffer);
    catch_ffi(|| write_output(out_buffer, ENGINE_VERSION_DIRECT_ACTIONS))
}

#[no_mangle]
/// # Safety
///
/// `out_handle` must be either null or point to writable caller-owned storage.
/// When `config_len > 0`, `config_utf8` must point to `config_len` readable
/// bytes that remain valid for the duration of the call.
pub unsafe extern "C" fn ime_engine_create(
    config_utf8: *const u8,
    config_len: usize,
    out_handle: *mut *mut ImeEngineOpaque,
) -> i32 {
    if !out_handle.is_null() {
        // SAFETY: out_handle was checked for null and points to caller-owned writable storage.
        unsafe {
            *out_handle = ptr::null_mut();
        }
    }

    catch_ffi(|| {
        if out_handle.is_null() {
            return ImeErrorCode::InvalidArgument.as_i32();
        }

        let config_utf8 = match read_input_utf8(config_utf8, config_len) {
            Ok(value) => value,
            Err(code) => return code.as_i32(),
        };
        let config = match parse_engine_config(&config_utf8) {
            Ok(value) => value,
            Err(code) => return code.as_i32(),
        };
        let engine = match ImeEngine::new(config) {
            Ok(value) => value,
            Err(error) => return map_create_error(error).as_i32(),
        };

        let opaque = Box::new(ImeEngineOpaque { engine });
        // SAFETY: out_handle is non-null and receives ownership of the Box raw pointer.
        unsafe {
            *out_handle = Box::into_raw(opaque);
        }
        ImeErrorCode::Success.as_i32()
    })
}

#[no_mangle]
pub extern "C" fn ime_engine_process_key(
    handle: *mut ImeEngineOpaque,
    key_utf8: *const u8,
    key_len: usize,
    out_buffer: *mut ImeBuffer,
) -> i32 {
    clear_out_buffer(out_buffer);
    catch_ffi(|| {
        let key = match read_input_utf8(key_utf8, key_len) {
            Ok(value) => value,
            Err(code) => return code.as_i32(),
        };
        let key = match validate_key_arg(&key) {
            Ok(value) => value,
            Err(code) => return code.as_i32(),
        };
        let engine = match engine_from_handle(handle) {
            Ok(value) => value,
            Err(code) => return code.as_i32(),
        };
        write_output(out_buffer, &engine.engine.process_key(key).to_json())
    })
}

#[no_mangle]
pub extern "C" fn ime_engine_insert_segment_boundary(
    handle: *mut ImeEngineOpaque,
    out_buffer: *mut ImeBuffer,
) -> i32 {
    clear_out_buffer(out_buffer);
    catch_ffi(|| {
        let engine = match engine_from_handle(handle) {
            Ok(value) => value,
            Err(code) => return code.as_i32(),
        };
        let result = match engine.engine.insert_segment_boundary() {
            Ok(value) => value,
            Err(error) => return error.code().as_i32(),
        };
        write_output(out_buffer, &result.to_json())
    })
}

#[no_mangle]
pub extern "C" fn ime_engine_backspace(
    handle: *mut ImeEngineOpaque,
    out_buffer: *mut ImeBuffer,
) -> i32 {
    clear_out_buffer(out_buffer);
    catch_ffi(|| {
        let engine = match engine_from_handle(handle) {
            Ok(value) => value,
            Err(code) => return code.as_i32(),
        };
        write_output(out_buffer, &engine.engine.backspace().to_json())
    })
}

#[no_mangle]
pub extern "C" fn ime_engine_reset(
    handle: *mut ImeEngineOpaque,
    out_buffer: *mut ImeBuffer,
) -> i32 {
    clear_out_buffer(out_buffer);
    catch_ffi(|| {
        let engine = match engine_from_handle(handle) {
            Ok(value) => value,
            Err(code) => return code.as_i32(),
        };
        write_output(out_buffer, &engine.engine.reset().to_json())
    })
}

#[no_mangle]
pub extern "C" fn ime_engine_change_scheme(
    handle: *mut ImeEngineOpaque,
    scheme_utf8: *const u8,
    scheme_len: usize,
    out_buffer: *mut ImeBuffer,
) -> i32 {
    clear_out_buffer(out_buffer);
    catch_ffi(|| {
        let scheme_id = match read_input_utf8(scheme_utf8, scheme_len) {
            Ok(value) => value,
            Err(code) => return code.as_i32(),
        };
        if scheme_id.is_empty() {
            return ImeErrorCode::InvalidScheme.as_i32();
        }
        let engine = match engine_from_handle(handle) {
            Ok(value) => value,
            Err(code) => return code.as_i32(),
        };
        let result = match engine.engine.change_scheme(&scheme_id) {
            Ok(value) => value,
            Err(_) => return ImeErrorCode::InvalidScheme.as_i32(),
        };
        write_output(out_buffer, &result.to_json())
    })
}

#[no_mangle]
pub extern "C" fn ime_engine_select_candidate(
    handle: *mut ImeEngineOpaque,
    candidate_index: usize,
    out_buffer: *mut ImeBuffer,
) -> i32 {
    clear_out_buffer(out_buffer);
    catch_ffi(|| {
        let engine = match engine_from_handle(handle) {
            Ok(value) => value,
            Err(code) => return code.as_i32(),
        };
        let result = match engine.engine.select_candidate(candidate_index) {
            Ok(value) => value,
            Err(error) => return error.code().as_i32(),
        };
        write_output(out_buffer, &result.to_json())
    })
}

#[no_mangle]
pub extern "C" fn ime_engine_select_pinyin_combination(
    handle: *mut ImeEngineOpaque,
    combination_index: usize,
    out_buffer: *mut ImeBuffer,
) -> i32 {
    clear_out_buffer(out_buffer);
    catch_ffi(|| {
        let engine = match engine_from_handle(handle) {
            Ok(value) => value,
            Err(code) => return code.as_i32(),
        };
        let result = match engine.engine.select_pinyin_combination(combination_index) {
            Ok(value) => value,
            Err(error) => return error.code().as_i32(),
        };
        write_output(out_buffer, &result.to_json())
    })
}

#[no_mangle]
pub extern "C" fn ime_engine_next_candidate_page(
    handle: *mut ImeEngineOpaque,
    out_buffer: *mut ImeBuffer,
) -> i32 {
    clear_out_buffer(out_buffer);
    catch_ffi(|| {
        let engine = match engine_from_handle(handle) {
            Ok(value) => value,
            Err(code) => return code.as_i32(),
        };
        let result = match engine.engine.next_candidate_page() {
            Ok(value) => value,
            Err(error) => return error.code().as_i32(),
        };
        write_output(out_buffer, &result.to_json())
    })
}

#[no_mangle]
pub extern "C" fn ime_engine_previous_candidate_page(
    handle: *mut ImeEngineOpaque,
    out_buffer: *mut ImeBuffer,
) -> i32 {
    clear_out_buffer(out_buffer);
    catch_ffi(|| {
        let engine = match engine_from_handle(handle) {
            Ok(value) => value,
            Err(code) => return code.as_i32(),
        };
        let result = match engine.engine.previous_candidate_page() {
            Ok(value) => value,
            Err(error) => return error.code().as_i32(),
        };
        write_output(out_buffer, &result.to_json())
    })
}

#[no_mangle]
pub extern "C" fn ime_engine_get_code_table_category_config(
    handle: *mut ImeEngineOpaque,
    out_buffer: *mut ImeBuffer,
) -> i32 {
    clear_out_buffer(out_buffer);
    catch_ffi(|| {
        let engine = match engine_from_handle(handle) {
            Ok(value) => value,
            Err(code) => return code.as_i32(),
        };
        let snapshot = match engine.engine.code_table_category_config() {
            Ok(value) => value,
            Err(error) => return error.code().as_i32(),
        };
        write_output(out_buffer, &category_config_json(&snapshot))
    })
}

#[no_mangle]
pub extern "C" fn ime_engine_set_code_table_categories(
    handle: *mut ImeEngineOpaque,
    category_ids_json_utf8: *const u8,
    category_ids_json_len: usize,
    out_buffer: *mut ImeBuffer,
) -> i32 {
    clear_out_buffer(out_buffer);
    catch_ffi(|| {
        let json = match read_input_utf8(category_ids_json_utf8, category_ids_json_len) {
            Ok(value) => value,
            Err(code) => return code.as_i32(),
        };
        let category_ids = match parse_json_string_array(&json) {
            Ok(value) => value,
            Err(code) => return code.as_i32(),
        };
        let engine = match engine_from_handle(handle) {
            Ok(value) => value,
            Err(code) => return code.as_i32(),
        };
        let result = match engine.engine.set_code_table_categories(category_ids) {
            Ok(value) => value,
            Err(error) => return error.code().as_i32(),
        };
        write_output(out_buffer, &result.to_json())
    })
}

#[no_mangle]
pub extern "C" fn ime_engine_reload_user_lexicon(
    handle: *mut ImeEngineOpaque,
    out_buffer: *mut ImeBuffer,
) -> i32 {
    clear_out_buffer(out_buffer);
    catch_ffi(|| {
        let engine = match engine_from_handle(handle) {
            Ok(value) => value,
            Err(code) => return code.as_i32(),
        };
        let result = match engine.engine.reload_user_lexicon() {
            Ok(value) => value,
            Err(error) => return error.code().as_i32(),
        };
        write_output(out_buffer, &result.to_json())
    })
}

#[no_mangle]
pub extern "C" fn ime_user_lexicon_load(
    path_utf8: *const u8,
    path_len: usize,
    out_buffer: *mut ImeBuffer,
) -> i32 {
    clear_out_buffer(out_buffer);
    catch_ffi(|| {
        let path = match read_input_utf8(path_utf8, path_len) {
            Ok(value) if !value.trim().is_empty() => value,
            Ok(_) => return ImeErrorCode::InvalidArgument.as_i32(),
            Err(code) => return code.as_i32(),
        };
        let json = match load_snapshot_recovering(std::path::Path::new(&path)) {
            Ok(report) => user_lexicon_document_json(&report),
            Err(error) => user_lexicon_error_json(&error),
        };
        write_output(out_buffer, &json)
    })
}

#[no_mangle]
pub extern "C" fn ime_user_lexicon_save(
    path_utf8: *const u8,
    path_len: usize,
    expected_revision_utf8: *const u8,
    expected_revision_len: usize,
    content_utf8: *const u8,
    content_len: usize,
    out_buffer: *mut ImeBuffer,
) -> i32 {
    clear_out_buffer(out_buffer);
    catch_ffi(|| {
        let path = match read_input_utf8(path_utf8, path_len) {
            Ok(value) if !value.trim().is_empty() => value,
            Ok(_) => return ImeErrorCode::InvalidArgument.as_i32(),
            Err(code) => return code.as_i32(),
        };
        let expected_revision = match read_input_utf8(expected_revision_utf8, expected_revision_len)
        {
            Ok(value) => value,
            Err(code) => return code.as_i32(),
        };
        let content = match read_input_utf8(content_utf8, content_len) {
            Ok(value) => value,
            Err(code) => return code.as_i32(),
        };
        let snapshot = match parse_user_lexicon_bytes(&path, content.as_bytes()) {
            Ok(parsed) => parsed.into_snapshot(),
            Err(error) => return write_output(out_buffer, &user_lexicon_error_json(&error)),
        };
        if let Err(error) = save_snapshot_atomic_if_revision(
            std::path::Path::new(&path),
            &expected_revision,
            &snapshot,
        ) {
            return write_output(out_buffer, &user_lexicon_error_json(&error));
        }
        write_output(
            out_buffer,
            &user_lexicon_document_json(&saved_user_lexicon_report(snapshot)),
        )
    })
}

#[no_mangle]
pub extern "C" fn ime_engine_set_user_model_path(
    handle: *mut ImeEngineOpaque,
    path_utf8: *const u8,
    path_len: usize,
    out_buffer: *mut ImeBuffer,
) -> i32 {
    clear_out_buffer(out_buffer);
    catch_ffi(|| {
        let path = match read_input_utf8(path_utf8, path_len) {
            Ok(value) => value,
            Err(code) => return code.as_i32(),
        };
        let engine = match engine_from_handle(handle) {
            Ok(value) => value,
            Err(code) => return code.as_i32(),
        };
        write_status(out_buffer, engine.engine.set_user_model_path(&path))
    })
}

#[no_mangle]
pub extern "C" fn ime_engine_load_user_model(
    handle: *mut ImeEngineOpaque,
    out_buffer: *mut ImeBuffer,
) -> i32 {
    clear_out_buffer(out_buffer);
    catch_ffi(|| {
        let engine = match engine_from_handle(handle) {
            Ok(value) => value,
            Err(code) => return code.as_i32(),
        };
        write_status(out_buffer, engine.engine.load_user_model())
    })
}

#[no_mangle]
pub extern "C" fn ime_engine_flush_user_model(
    handle: *mut ImeEngineOpaque,
    out_buffer: *mut ImeBuffer,
) -> i32 {
    clear_out_buffer(out_buffer);
    catch_ffi(|| {
        let engine = match engine_from_handle(handle) {
            Ok(value) => value,
            Err(code) => return code.as_i32(),
        };
        write_status(out_buffer, engine.engine.flush_user_model())
    })
}

#[no_mangle]
pub extern "C" fn ime_engine_clear_user_model(
    handle: *mut ImeEngineOpaque,
    out_buffer: *mut ImeBuffer,
) -> i32 {
    clear_out_buffer(out_buffer);
    catch_ffi(|| {
        let engine = match engine_from_handle(handle) {
            Ok(value) => value,
            Err(code) => return code.as_i32(),
        };
        write_status(out_buffer, engine.engine.clear_user_model())
    })
}

#[no_mangle]
pub extern "C" fn ime_engine_set_user_learning_enabled(
    handle: *mut ImeEngineOpaque,
    enabled: bool,
    out_buffer: *mut ImeBuffer,
) -> i32 {
    clear_out_buffer(out_buffer);
    catch_ffi(|| {
        let engine = match engine_from_handle(handle) {
            Ok(value) => value,
            Err(code) => return code.as_i32(),
        };
        write_output(
            out_buffer,
            &engine.engine.set_user_learning_enabled(enabled).to_json(),
        )
    })
}

#[no_mangle]
pub extern "C" fn ime_engine_set_session_learning_allowed(
    handle: *mut ImeEngineOpaque,
    allowed: bool,
    out_buffer: *mut ImeBuffer,
) -> i32 {
    clear_out_buffer(out_buffer);
    catch_ffi(|| {
        let engine = match engine_from_handle(handle) {
            Ok(value) => value,
            Err(code) => return code.as_i32(),
        };
        write_output(
            out_buffer,
            &engine
                .engine
                .set_session_learning_allowed(allowed)
                .to_json(),
        )
    })
}

#[no_mangle]
/// # Safety
///
/// `handle` must be either null or point to writable caller-owned handle
/// storage previously initialized by `ime_engine_create`. A null stored handle
/// is accepted and treated as already destroyed.
pub unsafe extern "C" fn ime_engine_destroy(handle: *mut *mut ImeEngineOpaque) -> i32 {
    catch_ffi(|| {
        if handle.is_null() {
            return ImeErrorCode::InvalidArgument.as_i32();
        }

        // SAFETY: handle is non-null and points to caller-owned handle storage.
        let current = unsafe { *handle };
        if current.is_null() {
            return ImeErrorCode::Success.as_i32();
        }

        // SAFETY: current was allocated by Box::into_raw in ime_engine_create.
        unsafe {
            drop(Box::from_raw(current));
            *handle = ptr::null_mut();
        }
        ImeErrorCode::Success.as_i32()
    })
}

#[no_mangle]
/// # Safety
///
/// `buffer` must be either null or point to writable caller-owned buffer
/// storage. Non-null `buffer.data` must have been allocated by this crate and
/// not already released except through a prior call that cleared the same
/// buffer.
pub unsafe extern "C" fn ime_engine_free_buffer(buffer: *mut ImeBuffer) -> i32 {
    catch_ffi(|| {
        if buffer.is_null() {
            return ImeErrorCode::Success.as_i32();
        }

        // SAFETY: buffer is non-null and points to caller-owned buffer storage.
        let current = unsafe { *buffer };
        if !current.data.is_null() && current.len > 0 {
            // SAFETY: data was allocated from a boxed [u8] in write_output with capacity == len.
            unsafe {
                drop(Vec::from_raw_parts(current.data, current.len, current.len));
            }
        }

        // SAFETY: buffer is non-null and points to caller-owned buffer storage.
        unsafe {
            *buffer = ImeBuffer::empty();
        }
        ImeErrorCode::Success.as_i32()
    })
}


