#include "my_application.h"

int main(int argc, char** argv) {
  // Flutter 3.50 draws into a Wayland subsurface in a way that deadlocks
  // against GTK when the window is resized, often as early as startup
  // (https://github.com/flutter/flutter/issues/196529). X11 does not take
  // that path, so prefer it where there is an X server, which under Wayland
  // means running through Xwayland. Remove this once Flutter has a fix.
  gdk_set_allowed_backends("x11,*");

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
