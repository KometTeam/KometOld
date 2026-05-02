#include "my_application.h"
#include <glib.h>
#include <gdk/gdk.h>

// Фильтр для подавления раздражающих GTK/GDK warnings
static void suppress_gtk_warnings(const gchar* log_domain,
                                   GLogLevelFlags log_level,
                                   const gchar* message,
                                   gpointer user_data) {
  // Игнорируем ВСЕ ошибки конвертации UTF8/selection (проблема GTK с clipboard)
  if (g_strstr_len(message, -1, "Error converting") != NULL) {
    return;
  }
  
  // Игнорируем invalid UTF-8
  if (g_strstr_len(message, -1, "invalid UTF-8") != NULL) {
    return;
  }
  
  // Игнорируем другие раздражающие warning'и
  if (g_strstr_len(message, -1, "g_object_unref") != NULL) {
    return;
  }
  
  // Для остальных - стандартный вывод
  g_log_default_handler(log_domain, log_level, message, user_data);
}

int main(int argc, char** argv) {
  g_setenv("GDK_SYNCHRONIZE", "0", TRUE);
  g_setenv("G_MESSAGES_DEBUG", "", TRUE);
  g_setenv("GTK_DEBUG", "no-css-cache", TRUE);

  // Устанавливаем наш фильтр для Gdk и GTK warnings
  g_log_set_handler("Gdk", G_LOG_LEVEL_WARNING, suppress_gtk_warnings, NULL);
  g_log_set_handler("Gtk", G_LOG_LEVEL_WARNING, suppress_gtk_warnings, NULL);
  g_log_set_handler("Gdk", G_LOG_LEVEL_CRITICAL, suppress_gtk_warnings, NULL);
  g_log_set_handler("Gtk", G_LOG_LEVEL_CRITICAL, suppress_gtk_warnings, NULL);

  gdk_set_allowed_backends("x11");
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
