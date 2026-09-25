// Prints a message found through the runfiles library; fails without it.
#include <fstream>
#include <iostream>
#include <memory>
#include <sstream>
#include <string>

#include "rules_cc/cc/runfiles/runfiles.h"

using rules_cc::cc::runfiles::Runfiles;

int main(int argc, char** argv) {
  std::string error;
  std::unique_ptr<Runfiles> runfiles(Runfiles::Create(argv[0], BAZEL_CURRENT_REPOSITORY, &error));
  if (!runfiles) {
    std::cerr << "hello: no runfiles: " << error << "\n";
    return 1;
  }
  std::ifstream in(runfiles->Rlocation("_main/message.txt"), std::ios::binary);
  if (!in) {
    std::cerr << "hello: cannot find message.txt\n";
    return 1;
  }
  std::ostringstream message;
  message << in.rdbuf();
  std::cout << message.str();
  return message.str() == "Hello from a bound executable\n" ? 0 : 1;
}
