// Not part of the CMake project in this directory: the Dockerfile's verification
// layer compiles it on its own with clang++-<version> -fsanitize=address, runs it,
// and requires the report to say `stack-use-after-scope`.
//
// It is the bug clang's ASan exists in this image to catch. A holder's destructor
// calls a callback registered after the holder was declared, and the local that
// callback reads is declared after the holder too - so C++ ends that local's
// lifetime first, and the destructor reads a dead variable. GCC keeps the local
// alive until the block ends and prints `read 1`, with or without
// -fsanitize-address-use-after-scope; clang poisons it where its lifetime ends.
//
// A clean run here is a failed build: it means the compiler, its runtime or the
// pairing of the two is not what the image promises.
#include <cstdio>
#include <functional>

struct holder {
    std::function<void()> cb;
    ~holder() { if (cb) cb(); }
};

int main() {
    holder h;
    unsigned answered = 0;
    h.cb = [&] { std::printf("read %u\n", answered); };
    answered = 1;
    return 0;
}
