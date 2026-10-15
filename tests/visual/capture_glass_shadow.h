#include <CoreGraphics/CoreGraphics.h>

// Explicit IDs supplied by the probe; never enumerates other apps' windows.
CGImageRef _Nullable WattsonCaptureOwnedWindows(CGRect bounds, CGWindowID foreground,
                                               CGWindowID background) CF_RETURNS_RETAINED;
