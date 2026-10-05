cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "screen_sources.cpp"
  "screen_preview.cpp"
  "floating_prompter.cpp"
  "gpu_video_writer.cpp"
  "microphone_capture.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# C++/WinRT reports capture failures through exceptions. Keep this local to
# the runner; Flutter and third-party plugin build flags stay unchanged.
get_target_property(RUNNER_DEFINITIONS ${BINARY_NAME} COMPILE_DEFINITIONS)
list(REMOVE_ITEM RUNNER_DEFINITIONS "_HAS_EXCEPTIONS=0")
set_property(TARGET ${BINARY_NAME} PROPERTY COMPILE_DEFINITIONS ${RUNNER_DEFINITIONS})

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app flutter_wrapper_plugin)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_link_libraries(${BINARY_NAME} PRIVATE "d3d11.lib" "dxgi.lib" "windowsapp.lib")
target_link_libraries(${BINARY_NAME} PRIVATE "mf.lib" "mfplat.lib" "mfreadwrite.lib" "mfuuid.lib" "oleaut32.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

# Explicit, non-shipping native check. It generates only synthetic video and
# validates the same encoder used by the recorder; no camera/mic/screen capture.
add_executable(gpu_video_writer_check EXCLUDE_FROM_ALL "gpu_video_writer.cpp" "tests/gpu_video_writer_check.cpp")
target_compile_features(gpu_video_writer_check PRIVATE cxx_std_17)
target_compile_options(gpu_video_writer_check PRIVATE /W4 /WX /EHsc /wd"4100")
target_compile_definitions(gpu_video_writer_check PRIVATE "NOMINMAX")
target_link_libraries(gpu_video_writer_check PRIVATE "d3d11.lib" "dxgi.lib" "mf.lib" "mfplat.lib" "mfreadwrite.lib" "mfuuid.lib" "ole32.lib" "oleaut32.lib" "windowsapp.lib")

# Reads a short microphone stream into memory and discards it. Explicit only.
add_executable(microphone_capture_check EXCLUDE_FROM_ALL "microphone_capture.cpp" "tests/microphone_capture_check.cpp")
target_compile_features(microphone_capture_check PRIVATE cxx_std_17)
target_compile_options(microphone_capture_check PRIVATE /W4 /WX /EHsc /wd"4100")
target_compile_definitions(microphone_capture_check PRIVATE "NOMINMAX")
target_link_libraries(microphone_capture_check PRIVATE "ole32.lib" "windowsapp.lib")
