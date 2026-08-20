#[cfg(not(any(unix, windows)))]
use std::fs;
use std::fs::File;
use std::io;
use std::path::Path;

pub(crate) enum FileBytes {
    #[cfg(any(unix, windows))]
    Mapped(MappedFile),
    Owned(Vec<u8>),
}

impl FileBytes {
    pub(crate) fn open(path: &Path) -> io::Result<Self> {
        let file = File::open(path)?;
        let len = usize::try_from(file.metadata()?.len())
            .map_err(|_| io::Error::new(io::ErrorKind::InvalidData, "file length overflow"))?;
        if len == 0 {
            return Ok(Self::Owned(Vec::new()));
        }
        #[cfg(any(unix, windows))]
        {
            MappedFile::map(&file, len).map(Self::Mapped)
        }
        #[cfg(not(any(unix, windows)))]
        {
            drop(file);
            fs::read(path).map(Self::Owned)
        }
    }

    pub(crate) fn as_slice(&self) -> &[u8] {
        match self {
            #[cfg(any(unix, windows))]
            Self::Mapped(mapped) => mapped.as_slice(),
            Self::Owned(bytes) => bytes,
        }
    }
}

#[cfg(any(unix, windows))]
pub(crate) struct MappedFile {
    data: *const u8,
    len: usize,
    #[cfg(windows)]
    mapping: *mut core::ffi::c_void,
}

#[cfg(unix)]
impl MappedFile {
    fn map(file: &File, len: usize) -> io::Result<Self> {
        use std::os::fd::AsRawFd;

        const PROT_READ: i32 = 1;
        const MAP_PRIVATE: i32 = 2;
        unsafe extern "C" {
            fn mmap(
                address: *mut core::ffi::c_void,
                length: usize,
                protection: i32,
                flags: i32,
                file_descriptor: i32,
                offset: i64,
            ) -> *mut core::ffi::c_void;
        }
        // SAFETY: the file descriptor remains valid for the mmap call, the
        // mapping is read-only/private, and `len` comes from this file's
        // metadata. The returned view is unmapped by Drop.
        let data = unsafe {
            mmap(
                std::ptr::null_mut(),
                len,
                PROT_READ,
                MAP_PRIVATE,
                file.as_raw_fd(),
                0,
            )
        };
        if data as isize == -1 {
            Err(io::Error::last_os_error())
        } else {
            Ok(Self {
                data: data.cast(),
                len,
            })
        }
    }
}

#[cfg(windows)]
impl MappedFile {
    fn map(file: &File, len: usize) -> io::Result<Self> {
        use std::os::windows::io::AsRawHandle;

        const PAGE_READONLY: u32 = 0x02;
        const FILE_MAP_READ: u32 = 0x0004;
        #[link(name = "kernel32")]
        unsafe extern "system" {
            fn CreateFileMappingW(
                file: *mut core::ffi::c_void,
                attributes: *mut core::ffi::c_void,
                protection: u32,
                maximum_size_high: u32,
                maximum_size_low: u32,
                name: *const u16,
            ) -> *mut core::ffi::c_void;
            fn MapViewOfFile(
                mapping: *mut core::ffi::c_void,
                desired_access: u32,
                offset_high: u32,
                offset_low: u32,
                bytes_to_map: usize,
            ) -> *mut core::ffi::c_void;
            fn CloseHandle(object: *mut core::ffi::c_void) -> i32;
        }
        // SAFETY: the raw handle belongs to the live `File`, the mapping is
        // read-only, and all pointer/handle ownership is retained by Self.
        let mapping = unsafe {
            CreateFileMappingW(
                file.as_raw_handle().cast(),
                std::ptr::null_mut(),
                PAGE_READONLY,
                0,
                0,
                std::ptr::null(),
            )
        };
        if mapping.is_null() {
            return Err(io::Error::last_os_error());
        }
        // A zero length maps the complete file mapping.
        let data = unsafe { MapViewOfFile(mapping, FILE_MAP_READ, 0, 0, 0) };
        if data.is_null() {
            // SAFETY: `mapping` is a valid handle created above.
            unsafe {
                CloseHandle(mapping);
            }
            return Err(io::Error::last_os_error());
        }
        Ok(Self {
            data: data.cast(),
            len,
            mapping,
        })
    }
}

#[cfg(any(unix, windows))]
impl MappedFile {
    fn as_slice(&self) -> &[u8] {
        // SAFETY: `data..data+len` is a live read-only file mapping owned by
        // Self and cannot be mutated through this API.
        unsafe { std::slice::from_raw_parts(self.data, self.len) }
    }
}

#[cfg(unix)]
impl Drop for MappedFile {
    fn drop(&mut self) {
        unsafe extern "C" {
            fn munmap(address: *mut core::ffi::c_void, length: usize) -> i32;
        }
        // SAFETY: this exact view was returned by mmap and is unmapped once.
        unsafe {
            munmap(self.data.cast_mut().cast(), self.len);
        }
    }
}

#[cfg(windows)]
impl Drop for MappedFile {
    fn drop(&mut self) {
        #[link(name = "kernel32")]
        unsafe extern "system" {
            fn UnmapViewOfFile(address: *const core::ffi::c_void) -> i32;
            fn CloseHandle(object: *mut core::ffi::c_void) -> i32;
        }
        // SAFETY: both resources are owned by Self and released exactly once.
        unsafe {
            UnmapViewOfFile(self.data.cast());
            CloseHandle(self.mapping);
        }
    }
}
