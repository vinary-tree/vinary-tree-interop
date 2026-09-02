include_guard(GLOBAL)

get_filename_component(_VT_INTEROP_PREFIX "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)

if(NOT TARGET vinary-tree::interop)
  add_library(vinary-tree::interop INTERFACE IMPORTED)
  set_target_properties(vinary-tree::interop PROPERTIES
    INTERFACE_INCLUDE_DIRECTORIES "${_VT_INTEROP_PREFIX}/include"
  )
endif()

if(NOT TARGET vinary-tree::interop-cpp)
  add_library(vinary-tree::interop-cpp INTERFACE IMPORTED)
  set_target_properties(vinary-tree::interop-cpp PROPERTIES
    INTERFACE_INCLUDE_DIRECTORIES "${_VT_INTEROP_PREFIX}/include"
    INTERFACE_COMPILE_FEATURES cxx_std_20
  )
endif()

set(vinary-tree-interop_FOUND TRUE)
unset(_VT_INTEROP_PREFIX)
