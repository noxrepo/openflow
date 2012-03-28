/* Do not modify this file.  */
/* It is created automatically by the Makefile.  */

#ifdef _WIN32
extern "C" {
#endif

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <gmodule.h>

#include "moduleinfo.h"

#ifndef ENABLE_STATIC
#ifdef _WIN32
extern "C" __declspec(dllexport) const gchar version[] = VERSION;
#else
G_MODULE_EXPORT const gchar version[] = VERSION;
#endif

/* Start the functions we need for the plugin stuff */

G_MODULE_EXPORT void
plugin_register (void)
{
  {extern void proto_register_openflow (void); proto_register_openflow ();}
}

G_MODULE_EXPORT void
plugin_reg_handoff(void)
{
  {extern void proto_reg_handoff_openflow (void); proto_reg_handoff_openflow ();}
}
#endif

#ifdef _WIN32
}
#endif
