// See CMakeLists.txt in this directory: compiled and run by the Dockerfile's
// verification layer, then deleted. It returns non-zero on a wrong answer, so
// ctest fails rather than merely printing.
//
// The pieces it touches are the ones clang-tidy then reads through this file:
// std::string and std::function are where libstdc++ hides its `throw` behind
// external `__throw_*`, which is the reason the image exists, and std::thread is
// what a host test suite starts. (Since glibc 2.34 pthread lives in libc itself,
// so this cannot fail for want of -pthread; Threads::Threads is linked because
// that is how a project spells it, and find_package(Threads) has to resolve.)
#include <cstdio>
#include <functional>
#include <string>
#include <thread>

int main() {
  std::string answer;
  const std::function<void()> fill = [&answer] { answer = "jethome host image"; };

  std::thread worker(fill);
  worker.join();

  if (answer != "jethome host image") {
    std::fprintf(stderr, "smoke: the worker thread wrote '%s'\n", answer.c_str());
    return 1;
  }
  return 0;
}
