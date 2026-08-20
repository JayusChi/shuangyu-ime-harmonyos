fn catch_ffi(action: impl FnOnce() -> i32) -> i32 {
    match panic::catch_unwind(AssertUnwindSafe(action)) {
        Ok(code) => code,
        Err(_) => ImeErrorCode::EngineInternalError.as_i32(),
    }
}

fn clear_out_buffer(out_buffer: *mut ImeBuffer) {
    if !out_buffer.is_null() {
        // SAFETY: out_buffer was checked for null and points to caller-owned writable storage.
        unsafe {
            *out_buffer = ImeBuffer::empty();
        }
    }
}

fn write_output(out_buffer: *mut ImeBuffer, value: &str) -> i32 {
    if out_buffer.is_null() {
        return ImeErrorCode::BufferAllocationFailed.as_i32();
    }

    let mut bytes = value.as_bytes().to_vec().into_boxed_slice();
    let len = bytes.len();
    let data = if len == 0 {
        ptr::null_mut()
    } else {
        bytes.as_mut_ptr()
    };
    std::mem::forget(bytes);

    // SAFETY: out_buffer was checked for null and points to caller-owned writable storage.
    unsafe {
        *out_buffer = ImeBuffer { data, len };
    }
    ImeErrorCode::Success.as_i32()
}

fn read_input_utf8(input_utf8: *const u8, input_len: usize) -> Result<String, ImeErrorCode> {
    if input_len == 0 {
        return Ok(String::new());
    }
    if input_utf8.is_null() {
        return Err(ImeErrorCode::InvalidArgument);
    }

    // SAFETY: input_utf8 is non-null and the caller promises input_len readable bytes.
    let bytes = unsafe { slice::from_raw_parts(input_utf8, input_len) };
    str::from_utf8(bytes)
        .map(str::to_owned)
        .map_err(|_| ImeErrorCode::InvalidUtf8)
}

#[cfg(test)]
fn read_c_string_utf8(input_utf8: *const c_char) -> Result<String, ImeErrorCode> {
    if input_utf8.is_null() {
        return Err(ImeErrorCode::InvalidArgument);
    }

    // SAFETY: legacy callers pass a non-null NUL-terminated C string valid for this call.
    let input = unsafe { CStr::from_ptr(input_utf8) };
    input
        .to_str()
        .map(str::to_owned)
        .map_err(|_| ImeErrorCode::InvalidUtf8)
}

fn validate_key_arg(key: &str) -> Result<char, ImeErrorCode> {
    let mut chars = key.chars();
    let Some(ch) = chars.next() else {
        return Err(ImeErrorCode::InvalidArgument);
    };
    if chars.next().is_some()
        || !(ch.is_ascii_lowercase() || ch == ';' || ch == '`' || matches!(ch, '2'..='9'))
    {
        return Err(ImeErrorCode::InvalidArgument);
    }
    Ok(ch)
}

fn map_create_error(error: ime_engine::EngineCreateError) -> ImeErrorCode {
    error.code()
}

fn write_status(
    out_buffer: *mut ImeBuffer,
    result: Result<user_model::UserModelStatus, ime_engine::EngineOperationError>,
) -> i32 {
    match result {
        Ok(status) => write_output(out_buffer, &status.to_json()),
        Err(error) => error.code().as_i32(),
    }
}

fn engine_from_handle<'a>(
    handle: *mut ImeEngineOpaque,
) -> Result<&'a mut ImeEngineOpaque, ImeErrorCode> {
    if handle.is_null() {
        return Err(ImeErrorCode::InvalidHandle);
    }
    // SAFETY: handle is non-null and must have been returned by ime_engine_create.
    Ok(unsafe { &mut *handle })
}

