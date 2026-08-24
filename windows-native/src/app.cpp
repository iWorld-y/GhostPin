#include "app.hpp"

#include "raii.hpp"

namespace ghostpin::app {

int Controller::run(HINSTANCE, int) const {
    // 后续任务接入消息窗口、HUD、托盘和存储服务。
    return 0;
}

} // namespace ghostpin::app
