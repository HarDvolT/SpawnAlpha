#ifndef RUNNER_AUDIO_LOUDNESS_H_
#define RUNNER_AUDIO_LOUDNESS_H_
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <limits>
#include <stdexcept>
#include <vector>

struct SoundBalance { bool enabled = false; double target = -14, ceiling = -2, maximum_boost = 12; };

// Our streaming implementation of numerical K-weighting/gating and 4x FIR
// true-peak measurement specified by ITU-R BS.1770-5 (48kHz mono/stereo).
// https://www.itu.int/rec/R-REC-BS.1770-5-202311-I
// No standard document, third-party code or audio is bundled.
class AudioLoudness {
 public:
  explicit AudioLoudness(uint32_t channels) : channels_(channels), energy_(19200, 0) {
    Require(channels >= 1 && channels <= 2);
  }
  void Add(const std::vector<int16_t>& pcm) {
    Require(pcm.size() % channels_ == 0 && pcm.size() <= 48000 * channels_ && !finished_);
    for (size_t f = 0; f < pcm.size() / channels_; ++f) {
      double energy = 0;
      for (uint32_t c = 0; c < channels_; ++c) {
        const double sample = pcm[f * channels_ + c] / 32768.0;
        const auto shelf = shelves_[c].Apply(sample, 1.53512485958697, -2.69169618940638, 1.19839281085285, -1.69065929318241, .73248077421585);
        const auto highpass = highpasses_[c].Apply(shelf, 1, -2, 1, -1.99004745483398, .99007225036621);
        energy += highpass * highpass; Peak(c, sample);
      }
      const auto slot = static_cast<size_t>(frames_ % 19200);
      sum_ += energy - energy_[slot]; energy_[slot] = energy; ++frames_;
      Require(frames_ <= 24LL * 60 * 60 * 48000);
      if (frames_ >= 19200 && frames_ % 4800 == 0) blocks_.push_back(std::max(0.0, sum_) / 19200);
    }
  }
  double Finish(const SoundBalance& policy) {
    Require(!finished_ && std::isfinite(policy.target) && policy.target >= -36 && policy.target <= -9 &&
      std::isfinite(policy.ceiling) && policy.ceiling >= -12 && policy.ceiling <= 0 &&
      std::isfinite(policy.maximum_boost) && policy.maximum_boost >= 0 && policy.maximum_boost <= 20);
    finished_ = true;
    if (!policy.enabled) return 1;
    for (int i = 0; i < 12; ++i) for (uint32_t c = 0; c < channels_; ++c) Peak(c, 0);
    const double absolute = std::pow(10.0, (-70 + .691) / 10);
    double sum = 0; size_t count = 0;
    for (double e : blocks_) if (e > absolute) { sum += e; ++count; }
    if (count == 0 || peak_ <= 0) return 1;
    const auto relative = sum / count / 10;
    sum = 0; count = 0;
    for (double e : blocks_) if (e > absolute && e > relative) { sum += e; ++count; }
    if (count == 0) return 1;
    loudness_ = -.691 + 10 * std::log10(sum / count);
    return std::min({std::pow(10.0, (policy.target - loudness_) / 20),
      std::pow(10.0, policy.maximum_boost / 20), std::pow(10.0, policy.ceiling / 20) / peak_});
  }
  double loudness() const { return loudness_; }
  double peak() const { return peak_; }
 private:
  struct Biquad {
    double x1 = 0, x2 = 0, y1 = 0, y2 = 0;
    double Apply(double x, double b0, double b1, double b2, double a1, double a2) {
      const double y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
      x2 = x1; x1 = x; y2 = y1; y1 = y; return y;
    }
  };
  void Peak(uint32_t c, double sample) {
    // Numerical filter data, four phases by twelve taps, from Annex 2.
    static constexpr double taps[12][4] = {
      {.001708984375, -.0291748046875, -.0189208984375, -.00830078125},
      {.010986328125, .029296875, .0330810546875, .014892578125},
      {-.0196533203125, -.0517578125, -.0582275390625, -.026611328125},
      {.033203125, .089111328125, .1015625, .047607421875},
      {-.0594482421875, -.16650390625, -.2003173828125, -.102294921875},
      {.1373291015625, .465087890625, .77978515625, .97216796875},
      {.97216796875, .77978515625, .465087890625, .1373291015625},
      {-.102294921875, -.2003173828125, -.16650390625, -.0594482421875},
      {.047607421875, .1015625, .089111328125, .033203125},
      {-.026611328125, -.0582275390625, -.0517578125, -.0196533203125},
      {.014892578125, .0330810546875, .029296875, .010986328125},
      {-.00830078125, -.0189208984375, -.0291748046875, .001708984375},
    };
    auto& memory = peak_memory_[c];
    std::move_backward(memory.begin(), memory.end() - 1, memory.end()); memory[0] = sample;
    peak_ = std::max(peak_, std::abs(sample));
    for (int phase = 0; phase < 4; ++phase) {
      double value = 0; for (int i = 0; i < 12; ++i) value += taps[i][phase] * memory[i];
      peak_ = std::max(peak_, std::abs(value));
    }
  }
  static void Require(bool v) { if (!v) throw std::runtime_error("Invalid sound balance"); }
  uint32_t channels_;
  Biquad shelves_[2], highpasses_[2];
  std::array<double, 12> peak_memory_[2]{};
  std::vector<double> energy_, blocks_;
  int64_t frames_ = 0;
  double sum_ = 0, peak_ = 0, loudness_ = -std::numeric_limits<double>::infinity();
  bool finished_ = false;
};
inline void ApplySoundGain(std::vector<int16_t>& pcm, double gain) {
  if (!std::isfinite(gain) || gain <= 0 || gain > 10) throw std::runtime_error("Invalid sound gain");
  if (gain == 1) return;
  for (auto& sample : pcm) sample = static_cast<int16_t>(std::clamp(std::lround(sample * gain), -32768L, 32767L));
}
#endif
