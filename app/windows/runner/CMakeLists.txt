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
  "screen_recording_core.cpp"
  "screen_recorder.cpp"
  "recording_probe.cpp"
  "recording_hud.cpp"
  "camera_capture.cpp"
  "camera_bubble.cpp"
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

# Captures only its own generated-color window; no private desktop capture.
add_executable(screen_recording_check EXCLUDE_FROM_ALL "screen_recording_core.cpp" "gpu_video_writer.cpp" "microphone_capture.cpp" "camera_capture.cpp" "tests/screen_recording_check.cpp")
target_compile_features(screen_recording_check PRIVATE cxx_std_17)
target_compile_options(screen_recording_check PRIVATE /W4 /WX /EHsc /wd"4100")
target_compile_definitions(screen_recording_check PRIVATE "NOMINMAX")
target_link_libraries(screen_recording_check PRIVATE "d3d11.lib" "dxgi.lib" "mf.lib" "mfplat.lib" "mfreadwrite.lib" "mfuuid.lib" "ole32.lib" "oleaut32.lib" "windowsapp.lib" "user32.lib" "gdi32.lib")

add_executable(recording_probe_check EXCLUDE_FROM_ALL "recording_probe.cpp" "tests/recording_probe_check.cpp")
target_compile_features(recording_probe_check PRIVATE cxx_std_17)
target_compile_options(recording_probe_check PRIVATE /W4 /WX /EHsc /wd"4100")
target_compile_definitions(recording_probe_check PRIVATE "NOMINMAX")
target_link_libraries(recording_probe_check PRIVATE "mfplat.lib" "mfreadwrite.lib" "mfuuid.lib" "ole32.lib" "windowsapp.lib")

add_executable(recording_clock_check EXCLUDE_FROM_ALL "tests/recording_clock_check.cpp")
target_compile_features(recording_clock_check PRIVATE cxx_std_17)
target_compile_options(recording_clock_check PRIVATE /W4 /WX /EHsc)

add_executable(recording_fixture_window WIN32 EXCLUDE_FROM_ALL "tests/recording_fixture_window.cpp")
target_compile_features(recording_fixture_window PRIVATE cxx_std_17)
target_compile_options(recording_fixture_window PRIVATE /W4 /WX /EHsc /wd"4100")
target_link_libraries(recording_fixture_window PRIVATE "user32.lib" "gdi32.lib")

add_executable(camera_capture_check EXCLUDE_FROM_ALL "camera_capture.cpp" "tests/camera_capture_check.cpp")
target_compile_features(camera_capture_check PRIVATE cxx_std_17)
target_compile_options(camera_capture_check PRIVATE /W4 /WX /EHsc /wd"4100")
target_compile_definitions(camera_capture_check PRIVATE "NOMINMAX" "SPAWNALPHA_CAMERA_FIXTURE")
target_link_libraries(camera_capture_check PRIVATE "mf.lib" "mfplat.lib" "mfreadwrite.lib" "mfuuid.lib" "ole32.lib" "windowsapp.lib")

add_executable(paired_recording_check EXCLUDE_FROM_ALL "screen_recording_core.cpp" "gpu_video_writer.cpp" "microphone_capture.cpp" "camera_capture.cpp" "tests/paired_recording_check.cpp")
target_compile_features(paired_recording_check PRIVATE cxx_std_17)
target_compile_options(paired_recording_check PRIVATE /W4 /WX /EHsc /wd"4100")
target_compile_definitions(paired_recording_check PRIVATE "NOMINMAX" "SPAWNALPHA_CAMERA_FIXTURE")
target_link_libraries(paired_recording_check PRIVATE "d3d11.lib" "dxgi.lib" "mf.lib" "mfplat.lib" "mfreadwrite.lib" "mfuuid.lib" "ole32.lib" "oleaut32.lib" "windowsapp.lib" "user32.lib" "gdi32.lib")

# Explicit UI check binary only. It reads generated video as the camera while
# exercising the real protected windows, channels, common clock and local store.
# Neither this target nor the fixture-only camera API is part of normal builds.
get_target_property(PAIRED_UI_SOURCES ${BINARY_NAME} SOURCES)
get_target_property(PAIRED_UI_DEFINITIONS ${BINARY_NAME} COMPILE_DEFINITIONS)
add_executable(paired_ui_fixture WIN32 EXCLUDE_FROM_ALL ${PAIRED_UI_SOURCES})
apply_standard_settings(paired_ui_fixture)
set_property(TARGET paired_ui_fixture PROPERTY COMPILE_DEFINITIONS ${PAIRED_UI_DEFINITIONS} "SPAWNALPHA_CAMERA_FIXTURE")
target_include_directories(paired_ui_fixture PRIVATE "${CMAKE_SOURCE_DIR}")
target_link_libraries(paired_ui_fixture PRIVATE $<TARGET_PROPERTY:${BINARY_NAME},LINK_LIBRARIES>)
add_dependencies(paired_ui_fixture flutter_assemble)

# Explicit audio checks. The full pipeline links generated endpoints so no
# private playback/microphone samples can be written to its fixture videos.
add_executable(recording_audio_mixer_check EXCLUDE_FROM_ALL "tests/recording_audio_mixer_check.cpp")
target_compile_features(recording_audio_mixer_check PRIVATE cxx_std_17)
target_compile_options(recording_audio_mixer_check PRIVATE /W4 /WX /EHsc)

add_executable(system_audio_capture_check EXCLUDE_FROM_ALL "microphone_capture.cpp" "tests/system_audio_capture_check.cpp")
target_compile_features(system_audio_capture_check PRIVATE cxx_std_17)
target_compile_options(system_audio_capture_check PRIVATE /W4 /WX /EHsc /wd"4100")
target_compile_definitions(system_audio_capture_check PRIVATE "NOMINMAX")
target_link_libraries(system_audio_capture_check PRIVATE "ole32.lib" "windowsapp.lib")

add_executable(audio_recording_check EXCLUDE_FROM_ALL "screen_recording_core.cpp" "gpu_video_writer.cpp" "camera_capture.cpp" "tests/audio_capture_fixture.cpp" "tests/screen_recording_check.cpp")
target_compile_features(audio_recording_check PRIVATE cxx_std_17)
target_compile_options(audio_recording_check PRIVATE /W4 /WX /EHsc /wd"4100")
target_compile_definitions(audio_recording_check PRIVATE "NOMINMAX" "SPAWNALPHA_AUDIO_FIXTURE")
target_link_libraries(audio_recording_check PRIVATE "d3d11.lib" "dxgi.lib" "mf.lib" "mfplat.lib" "mfreadwrite.lib" "mfuuid.lib" "ole32.lib" "oleaut32.lib" "windowsapp.lib" "user32.lib" "gdi32.lib")
