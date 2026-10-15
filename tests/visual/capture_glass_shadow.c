#include "capture_glass_shadow.h"

CGImageRef WattsonCaptureOwnedWindows(CGRect bounds, CGWindowID foreground, CGWindowID background) {
    CFArrayRef front = CGWindowListCreate(kCGWindowListOptionIncludingWindow, foreground);
    CFArrayRef back = CGWindowListCreate(kCGWindowListOptionIncludingWindow, background);
    if (!front || !back || CFArrayGetCount(front) != 1 || CFArrayGetCount(back) != 1) {
        if (front) CFRelease(front);
        if (back) CFRelease(back);
        return NULL;
    }
    CFMutableArrayRef windows = CFArrayCreateMutableCopy(NULL, 0, front);
    CFArrayAppendValue(windows, CFArrayGetValueAtIndex(back, 0));
    CGImageRef image = CGWindowListCreateImageFromArray(bounds, windows, kCGWindowImageBestResolution);
    CFRelease(windows);
    CFRelease(front);
    CFRelease(back);
    return image;
}
