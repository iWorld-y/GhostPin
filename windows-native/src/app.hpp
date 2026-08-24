#pragma once

#include <windows.h>

namespace ghostpin::app {

class Controller final {
public:
    int run(HINSTANCE instance, int show_command) const;
};

} // namespace ghostpin::app
