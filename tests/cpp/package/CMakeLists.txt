cmake_minimum_required(VERSION 3.20)
project(vinary_tree_interop_cpp_consumer LANGUAGES CXX)

find_package(vinary-tree-interop CONFIG REQUIRED)

add_executable(vinary-tree-interop-cpp-consumer main.cpp)
target_link_libraries(vinary-tree-interop-cpp-consumer
  PRIVATE vinary-tree::interop-cpp
)

enable_testing()
add_test(NAME cpp-installed-package
  COMMAND vinary-tree-interop-cpp-consumer
)
