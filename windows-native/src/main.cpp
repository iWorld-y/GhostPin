#include "app.hpp"

#include "raii.hpp"

#include <windows.h>

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int show_command) {
    ghostpin::platform::com_apartment apartment;
    return ghostpin::app::Controller{}.run(instance, show_command);
}
