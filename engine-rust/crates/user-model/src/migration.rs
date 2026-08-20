use crate::error::UserModelError;
use crate::limits::FORMAT_VERSION;

pub(crate) fn ensure_supported_format(version: u16) -> Result<(), UserModelError> {
    if version == FORMAT_VERSION {
        Ok(())
    } else {
        Err(UserModelError::UnsupportedVersion { version })
    }
}
