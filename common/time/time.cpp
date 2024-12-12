//
// Created by Yi Lu on 7/22/18.
//

#include "common/time/time.h"

namespace aria {
std::chrono::steady_clock::time_point Time::startTime =
    std::chrono::steady_clock::now();
}