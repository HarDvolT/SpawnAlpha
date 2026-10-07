#ifndef RUNNER_AUDIO_DEESSER_H_
#define RUNNER_AUDIO_DEESSER_H_
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <stdexcept>
#include <vector>

struct DeEssPolicy {
  bool enabled = false;
  double cutoff = 5000, ratio = .55, knee = .25, floor = -42, reduction = 3;
  int64_t detector_us = 5000, attack_us = 2000, release_us = 80000;
};
// Own sample-by-sample linked wideband de-esser. The detector uses the
// mathematical high-pass biquad described by the W3C Audio EQ Cookbook:
// https://www.w3.org/TR/audio-eq-cookbook/ . No document/code is bundled.
// The audible output is unfiltered PCM times a bounded gain, with no latency.
class AudioDeEsser {
 public:
  AudioDeEsser(uint32_t channels, DeEssPolicy policy) : channels_(channels), policy_(policy) {
    Require(channels >= 1 && channels <= 2 &&
      std::isfinite(policy.cutoff) && policy.cutoff >= 3000 && policy.cutoff <= 10000 &&
      std::isfinite(policy.ratio) && policy.ratio >= .3 && policy.ratio <= .8 &&
      std::isfinite(policy.knee) && policy.knee >= .1 && policy.knee <= .4 && policy.ratio + policy.knee <= 1 &&
      std::isfinite(policy.floor) && policy.floor >= -60 && policy.floor <= -20 &&
      std::isfinite(policy.reduction) && policy.reduction >= 0 && policy.reduction <= 6 &&
      policy.detector_us >= 1000 && policy.detector_us <= 20000 &&
      policy.attack_us >= 1000 && policy.attack_us <= 20000 &&
      policy.release_us >= 20000 && policy.release_us <= 300000);
    const auto omega = 6.283185307179586 * policy.cutoff / 48000;
    const auto cosine = std::cos(omega), alpha = std::sin(omega) / std::sqrt(2.0);
    b0_ = (1 + cosine) / (2 * (1 + alpha)); b1_ = -2 * b0_;
    a1_ = -2 * cosine / (1 + alpha); a2_ = (1 - alpha) / (1 + alpha);
    detector_ = Coefficient(policy.detector_us); attack_ = Coefficient(policy.attack_us); release_ = Coefficient(policy.release_us);
    floor_ = std::pow(10.0, policy.floor / 10);
  }
  void Reset() { for (auto& memory : memory_) memory = {}; total_ = high_ = reduction_ = 0; }
  void Apply(std::vector<int16_t>& pcm) {
    Require(pcm.size() % channels_ == 0 && pcm.size() <= 48000 * channels_);
    if (!policy_.enabled) return;
    for (size_t f = 0; f < pcm.size() / channels_; ++f) {
      double total = 0, high = 0;
      for (uint32_t c = 0; c < channels_; ++c) {
        const double x = pcm[f * channels_ + c] / 32768.0;
        auto& m = memory_[c]; const auto y = b0_ * x + b1_ * m.x1 + b0_ * m.x2 - a1_ * m.y1 - a2_ * m.y2;
        m.x2 = m.x1; m.x1 = x; m.y2 = m.y1; m.y1 = y;
        total += x * x; high += y * y;
      }
      total_ = detector_ * total_ + (1 - detector_) * total / channels_;
      high_ = detector_ * high_ + (1 - detector_) * high / channels_;
      const auto wanted = high_ >= floor_ && total_ > 0
          ? policy_.reduction * std::clamp((high_ / total_ - policy_.ratio) / policy_.knee, 0.0, 1.0) : 0;
      const auto response = wanted > reduction_ ? attack_ : release_;
      reduction_ = wanted + response * (reduction_ - wanted);
      const auto gain = std::pow(10.0, -reduction_ / 20);
      for (uint32_t c = 0; c < channels_; ++c)
        pcm[f * channels_ + c] = static_cast<int16_t>(std::lround(pcm[f * channels_ + c] * gain));
    }
  }
 private:
  static void Require(bool v) { if (!v) throw std::runtime_error("Invalid sound softening"); }
  static double Coefficient(int64_t time_us) { return std::exp(-1000000.0 / (48000 * time_us)); }
  struct Memory { double x1 = 0, x2 = 0, y1 = 0, y2 = 0; } memory_[2];
  uint32_t channels_; DeEssPolicy policy_;
  double b0_ = 0, b1_ = 0, a1_ = 0, a2_ = 0, detector_ = 0, attack_ = 0, release_ = 0;
  double floor_ = 0, total_ = 0, high_ = 0, reduction_ = 0;
};
#endif
