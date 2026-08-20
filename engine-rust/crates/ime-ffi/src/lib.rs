use engine_protocol::error::ImeErrorCode;
use engine_protocol::{
    escape_json, ABI_VERSION_DIRECT_ACTIONS, ENGINE_VERSION_DIRECT_ACTIONS,
    INTERFACE_VERSION_DIRECT_ACTIONS, INTERFACE_VERSION_PINYIN_STAGE3,
};
use ime_engine::{
    EngineConfig, FuzzyOption, ImeEngine, QuanpinContextRerankingConfig, QuanpinFeatureConfig,
    QUANPIN_CONTEXT_RERANKING_CONFIG_VERSION, QUANPIN_FEATURE_CONFIG_VERSION,
};
#[cfg(test)]
use ime_engine::{FixedCandidateEngine, Stage0ImeEngine};
#[cfg(test)]
use std::ffi::CStr;
#[cfg(test)]
use std::os::raw::c_char;
use std::panic::{self, AssertUnwindSafe};
use std::{ptr, slice, str};
use user_lexicon::{
    load_snapshot_recovering, parse_user_lexicon_bytes, save_snapshot_atomic_if_revision,
    UserLexiconAction, UserLexiconError, UserLexiconLoadReport, UserLexiconSnapshot,
};

#[repr(C)]
#[derive(Clone, Copy)]
pub struct ImeBuffer {
    pub data: *mut u8,
    pub len: usize,
}

impl ImeBuffer {
    const fn empty() -> Self {
        Self {
            data: ptr::null_mut(),
            len: 0,
        }
    }
}

pub struct ImeEngineOpaque {
    engine: ImeEngine,
}

// The C ABI remains rooted here; implementation is grouped by boundary responsibility.
include!("ffi/runtime.rs");
include!("ffi/config.rs");
include!("ffi/serialization.rs");
include!("ffi/exports.rs");
include!("ffi/test_support.rs");
include!("ffi/tests.rs");
