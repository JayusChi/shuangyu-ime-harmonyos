#ifndef RUST_BUFFER_H
#define RUST_BUFFER_H

#include "ime_engine_ffi.h"

#include <string>

class RustBuffer {
  public:
    RustBuffer();
    explicit RustBuffer(ImeBuffer buffer);
    ~RustBuffer();

    RustBuffer(const RustBuffer&) = delete;
    RustBuffer& operator=(const RustBuffer&) = delete;

    RustBuffer(RustBuffer&& other) noexcept;
    RustBuffer& operator=(RustBuffer&& other) noexcept;

    ImeBuffer* Out();
    std::string ToString() const;
    bool Empty() const;
    void Reset();

  private:
    ImeBuffer buffer_;
};

#endif
