#ifndef RUNNER_SCREEN_SOURCES_H_
#define RUNNER_SCREEN_SOURCES_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
RegisterScreenSources(flutter::BinaryMessenger* messenger);

#endif  // RUNNER_SCREEN_SOURCES_H_
