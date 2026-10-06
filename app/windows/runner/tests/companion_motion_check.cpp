#include "../companion_motion.h"
#include <iostream>
#include <stdexcept>

void Require(bool value) { if (!value) throw std::runtime_error("Companion placement failed"); }
int main() {
  try {
    CompanionMotion motion({440, 256, 24, 4, 2, 1, 140, 24});
    const CompanionRect work{0, 0, 1920, 1040};
    motion.Reset(740, 0);
    CompanionRect rect{};
    double time = 0;
    auto settle = [&](double x, double y, int frames, CompanionRect area) {
      for (int i = 0; i < frames; ++i) {
        time += 0.016;
        rect = motion.Step(x, y, area, time, 0.016);
        Require(rect.x >= area.x && rect.y >= area.y);
        Require(rect.x + rect.width <= area.x + area.width);
        Require(rect.y + rect.height <= area.y + area.height);
      }
    };
    settle(1000, 400, 40, work);
    settle(1100, 450, 40, work);
    Require(rect.x + rect.width < 1100 && rect.y + rect.height < 450);
    settle(800, 350, 40, work);
    Require(rect.x > 800 && rect.y > 350);
    settle(1910, 1030, 50, work);
    Require(rect.x + rect.width < 1910 && rect.y + rect.height < 1030);
    settle(10, 10, 50, work);
    Require(rect.x > 10 && rect.y > 10);
    // Stillness, including hand jitter, docks on the same monitor.
    for (int i = 0; i < 230; ++i) settle(11 + (i % 2), 11, 1, work);
    Require(std::abs(rect.x - 740) < 1 && rect.y < 1);
    // Negative-coordinate monitor and a gap: every in-flight frame is bounded.
    settle(-600, 400, 40, {-1280, 100, 1280, 924});
    // Narrow work area shrinks safely rather than producing inverted clamps.
    settle(20, 20, 40, {0, 0, 320, 200});
    Require(rect.width == 320 && rect.height == 200 && rect.x == 0 && rect.y == 0);
    motion.Reset(0, 0);
    rect = motion.Step(1000, 400, work, 0, 10);
    Require(std::isfinite(rect.x) && std::isfinite(rect.y));
    std::cout << "PASS companion direction, edges, rest, jitter, monitor, delay and reset\n";
    return 0;
  } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
}
