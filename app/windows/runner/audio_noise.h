#ifndef RUNNER_AUDIO_NOISE_H_
#define RUNNER_AUDIO_NOISE_H_
#include <speex/speex_preprocess.h>
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <memory>
#include <stdexcept>
#include <vector>

struct NoisePolicy { bool enabled = false; double suppression = -12, strength = .65; };
// SpeexDSP is an unmodified BSD-3 static dependency. See noise_runtime.cmake
// and assets/licenses/speexdsp.txt. All device/file/clock ownership stays here.
// Its overlap-add output describes the previous block. Blend with that same
// original block; the reader discards startup and flushes the retained tail.
class AudioNoise {
 public:
  static constexpr size_t kFrame = 480;
  AudioNoise(uint32_t channels, NoisePolicy policy) : channels_(channels), policy_(policy), previous_(kFrame * channels, 0) {
    Require(channels >= 1 && channels <= 2 && std::isfinite(policy.suppression) && policy.suppression >= -20 && policy.suppression <= -3 &&
      std::isfinite(policy.strength) && policy.strength >= 0 && policy.strength <= 1);
    if (policy.enabled) Reset();
  }
  void Reset() {
    std::fill(previous_.begin(), previous_.end(), int16_t{0});
    if (!policy_.enabled) return;
    for (uint32_t c = 0; c < channels_; ++c) {
      state_[c].reset(speex_preprocess_state_init(static_cast<int>(kFrame), 48000)); Require(state_[c] != nullptr);
      int on = 1, off = 0, suppression = static_cast<int>(std::lround(policy_.suppression));
      Require(speex_preprocess_ctl(state_[c].get(), SPEEX_PREPROCESS_SET_DENOISE, &on) == 0 &&
        speex_preprocess_ctl(state_[c].get(), SPEEX_PREPROCESS_SET_AGC, &off) == 0 &&
        speex_preprocess_ctl(state_[c].get(), SPEEX_PREPROCESS_SET_VAD, &off) == 0 &&
        speex_preprocess_ctl(state_[c].get(), SPEEX_PREPROCESS_SET_DEREVERB, &off) == 0 &&
        speex_preprocess_ctl(state_[c].get(), SPEEX_PREPROCESS_SET_NOISE_SUPPRESS, &suppression) == 0);
    }
  }
  std::vector<int16_t> Process(const std::vector<int16_t>& pcm) {
    Require(policy_.enabled && pcm.size() == kFrame * channels_);
    auto result = previous_;
    for (uint32_t c = 0; c < channels_; ++c) {
      std::array<int16_t, kFrame> mono{};
      for (size_t f = 0; f < kFrame; ++f) mono[f] = pcm[f * channels_ + c];
      speex_preprocess_run(state_[c].get(), mono.data());
      for (size_t f = 0; f < kFrame; ++f) {
        const auto at = f * channels_ + c;
        const auto mixed = previous_[at] * (1 - policy_.strength) + mono[f] * policy_.strength;
        result[at] = static_cast<int16_t>(std::clamp(std::lround(mixed), -32768L, 32767L));
      }
    }
    previous_ = pcm; return result;
  }
 private:
  static void Require(bool value) { if (!value) throw std::runtime_error("Invalid noise reduction"); }
  struct Destroy { void operator()(SpeexPreprocessState* value) const { speex_preprocess_state_destroy(value); } };
  uint32_t channels_; NoisePolicy policy_;
  std::unique_ptr<SpeexPreprocessState, Destroy> state_[2];
  std::vector<int16_t> previous_;
};
#endif
