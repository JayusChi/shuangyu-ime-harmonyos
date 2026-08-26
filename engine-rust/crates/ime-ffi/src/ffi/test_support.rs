#[cfg(test)]
#[no_mangle]
pub extern "C" fn ime_engine_get_test_candidates(
    input_utf8: *const c_char,
    out_buffer: *mut ImeBuffer,
) -> i32 {
    clear_out_buffer(out_buffer);
    catch_ffi(|| {
        let input = match read_c_string_utf8(input_utf8) {
            Ok(value) => value,
            Err(code) => return code.as_i32(),
        };

        let engine = Stage0ImeEngine;
        write_owned_output(
            out_buffer,
            engine.get_test_candidates(&input).to_stage0_json(),
        )
    })
}

#[cfg(test)]
#[no_mangle]
pub extern "C" fn ime_engine_stage5_test_panic(out_buffer: *mut ImeBuffer) -> i32 {
    clear_out_buffer(out_buffer);
    catch_ffi(|| panic!("stage5 test panic probe"))
}

