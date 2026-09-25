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
  std::ostringstream contents;
  contents << in.rdbuf();
  // Without the line ending, which a checkout on Windows may make CRLF.
  std::string message = contents.str();
  while (!message.empty() && (message.back() == '\n' || message.back() == '\r')) message.pop_back();
  std::cout << message << "\n";
  return message == "Hello from a bound executable" ? 0 : 1;
}
