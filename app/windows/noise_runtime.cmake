# Commercial BSD-3 source subset, reviewed in docs/compliance.md. No learned
# weights, codec, resampler, network/device runtime or upstream build scripts.
include(FetchContent)
FetchContent_Declare(sa_noise_source
  EXCLUDE_FROM_ALL
  URL https://codeload.github.com/xiph/speexdsp/zip/refs/tags/SpeexDSP-1.2.1
  URL_HASH SHA256=be16e16bcbc26875916a8eedd3b5b46cb93bef4714c49895a28f8c86b81437cf
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE)
FetchContent_MakeAvailable(sa_noise_source)
add_library(spawnalpha_noise STATIC
  "${sa_noise_source_SOURCE_DIR}/libspeexdsp/preprocess.c"
  "${sa_noise_source_SOURCE_DIR}/libspeexdsp/mdf.c"
  "${sa_noise_source_SOURCE_DIR}/libspeexdsp/filterbank.c"
  "${sa_noise_source_SOURCE_DIR}/libspeexdsp/fftwrap.c"
  "${sa_noise_source_SOURCE_DIR}/libspeexdsp/smallft.c")
target_compile_features(spawnalpha_noise PRIVATE c_std_11)
target_compile_definitions(spawnalpha_noise PRIVATE FLOATING_POINT USE_SMALLFT DISABLE_WARNINGS "EXPORT=" _CRT_SECURE_NO_WARNINGS)
target_include_directories(spawnalpha_noise PUBLIC "${sa_noise_source_SOURCE_DIR}/include")
# Keep upstream C warnings separate from our own /W4 /WX application checks.
target_compile_options(spawnalpha_noise PRIVATE /W1)
