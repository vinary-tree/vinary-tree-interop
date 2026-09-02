#include <vinary_tree/interop.hpp>

#include <cassert>

int main() {
  const vinary_tree::interop::resource empty;
  assert(!empty);
}
