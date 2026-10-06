cmake_minimum_required(VERSION 3.24)
project(spawnalpha_word_timing_check LANGUAGES C CXX)
# Explicit prototype only. Normal app/CI builds never download or link this.
# All fetched source/build files stay under the caller's app/build directory.
include(FetchContent)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_IS_DEV OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(WHISPER_CURL OFF CACHE BOOL "" FORCE)
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_SSE42 OFF CACHE BOOL "" FORCE)
set(GGML_BMI2 OFF CACHE BOOL "" FORCE)
set(GGML_AVX OFF CACHE BOOL "" FORCE)
set(GGML_AVX2 OFF CACHE BOOL "" FORCE)
set(GGML_FMA OFF CACHE BOOL "" FORCE)
set(GGML_F16C OFF CACHE BOOL "" FORCE)
set(GGML_LLAMAFILE OFF CACHE BOOL "" FORCE)
set(GGML_CUDA OFF CACHE BOOL "" FORCE)
set(GGML_VULKAN OFF CACHE BOOL "" FORCE)
FetchContent_Declare(whisper_cpp
  URL https://codeload.github.com/ggml-org/whisper.cpp/zip/refs/tags/v1.9.4
  URL_HASH SHA256=873e67727d51213d3a14a6700c7415900a6645b78c4e6edad9328eea90e53572
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
FetchContent_MakeAvailable(whisper_cpp)
add_executable(word_timing_check ../../windows/runner/local_transcription.cpp
  ../../windows/runner/gpu_video_writer.cpp check.cpp)
target_compile_features(word_timing_check PRIVATE cxx_std_17)
target_compile_options(word_timing_check PRIVATE /W4 /WX /EHsc /wd"4100")
target_compile_definitions(word_timing_check PRIVATE NOMINMAX)
target_link_libraries(word_timing_check PRIVATE whisper d3d11 dxgi mf mfplat mfreadwrite mfuuid ole32 oleaut32 windowsapp bcrypt)
