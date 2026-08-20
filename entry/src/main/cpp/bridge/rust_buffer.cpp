#include "rust_buffer.h"

#include <utility>

RustBuffer::RustBuffer() : buffer_{nullptr, 0} {}

RustBuffer::RustBuffer(ImeBuffer buffer) : buffer_(buffer) {}

RustBuffer::~RustBuffer() {
    Reset();
}

RustBuffer::RustBuffer(RustBuffer&& other) noexcept : buffer_(other.buffer_) {
    other.buffer_ = {nullptr, 0};
}

RustBuffer& RustBuffer::operator=(RustBuffer&& other) noexcept {
    if (this != &other) {
        Reset();
        buffer_ = other.buffer_;
        other.buffer_ = {nullptr, 0};
    }
    return *this;
}

ImeBuffer* RustBuffer::Out() {
    Reset();
    return &buffer_;
}

std::string RustBuffer::ToString() const {
    if (buffer_.data == nullptr || buffer_.len == 0) {
        return "";
    }
    return std::string(reinterpret_cast<const char*>(buffer_.data), buffer_.len);
}

bool RustBuffer::Empty() const {
    return buffer_.data == nullptr || buffer_.len == 0;
}

void RustBuffer::Reset() {
    if (buffer_.data != nullptr || buffer_.len != 0) {
        ime_engine_free_buffer(&buffer_);
    } else {
        buffer_ = {nullptr, 0};
    }
}
