# MIT source pinned to the already licence-checked prototype release. No server,
# downloader, examples, copied codec or device capture enters the app.
enable_language(C)
if(CMAKE_VERSION VERSION_LESS 3.28)
  message(FATAL_ERROR "Offline speech requires CMake 3.28 or newer (current Visual Studio 2022).")
endif()
include(FetchContent)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
foreach(flag WHISPER_BUILD_IS_DEV WHISPER_BUILD_TESTS WHISPER_BUILD_EXAMPLES WHISPER_BUILD_SERVER WHISPER_CURL GGML_NATIVE GGML_OPENMP GGML_SSE42 GGML_BMI2 GGML_AVX GGML_AVX2 GGML_FMA GGML_F16C GGML_LLAMAFILE GGML_CUDA GGML_VULKAN)
  set(${flag} OFF CACHE BOOL "" FORCE)
endforeach()
FetchContent_Declare(whisper_cpp
  EXCLUDE_FROM_ALL
  URL https://codeload.github.com/ggml-org/whisper.cpp/zip/refs/tags/v1.9.4
  URL_HASH SHA256=873e67727d51213d3a14a6700c7415900a6645b78c4e6edad9328eea90e53572
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
FetchContent_MakeAvailable(whisper_cpp)
