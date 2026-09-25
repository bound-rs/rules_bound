// Prints a message found through the runfiles library, then each argument:
// the contents of those that are readable files, the others as they are.
#include <fstream>
#include <iostream>
#include <memory>
#include <sstream>
#include <string>

#include "rules_cc/cc/runfiles/runfiles.h"

using rules_cc::cc::runfiles::Runfiles;

static bool read(const std::string& path, std::string* out) {
  std::ifstream in(path, std::ios::binary);
  if (!in) return false;
  std::ostringstream text;
  text << in.rdbuf();
  *out = text.str();
  return true;
}

int main(int argc, char** argv) {
  std::string error;
  std::unique_ptr<Runfiles> runfiles(Runfiles::Create(argv[0], BAZEL_CURRENT_REPOSITORY, &error));
  std::string message;
  if (!runfiles || !read(runfiles->Rlocation("_main/cc/message.txt"), &message)) {
    std::cerr << "hello: cannot find message.txt " << error << "\n";
    return 1;
  }
  std::cout << message;
  for (int i = 1; i < argc; ++i) {
    std::string contents;
    std::cout << " | " << (read(argv[i], &contents) ? contents : std::string(argv[i]));
  }
  std::cout << "\n";
  return 0;
}
