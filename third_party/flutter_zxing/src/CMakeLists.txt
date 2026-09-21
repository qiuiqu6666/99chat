cmake_minimum_required(VERSION 3.10)

project(flutter_zxing LANGUAGES C CXX)

add_library(
    flutter_zxing
    SHARED
    common.cpp
    native_zxing.cpp
)

if(MSVC)
  target_compile_definitions(flutter_zxing PRIVATE NOMINMAX)
endif()

set (BUILD_WRITERS ON)

# ZXing's install() rules write into Flutter's generator-expression
# CMAKE_INSTALL_PREFIX and break `flutter run` on Windows.
set(_ZXING_SKIP_INSTALL_RULES ${CMAKE_SKIP_INSTALL_RULES})
set(CMAKE_SKIP_INSTALL_RULES ON)
add_subdirectory(zxing/core)
set(CMAKE_SKIP_INSTALL_RULES ${_ZXING_SKIP_INSTALL_RULES})

file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/zxing/core/cmake_install.cmake"
  "# ZXing install rules skipped; stub so parent cmake_install.cmake include succeeds.\n")

target_link_libraries(flutter_zxing ZXing)

# use log-lib only for android platform
if (ANDROID)
    find_library(log-lib log)
    target_link_libraries(flutter_zxing ${log-lib})
endif (ANDROID)