/* Read-only JXA; uses AppKit properties, never UI scripting or System Events. */
ObjC.import('Foundation');
ObjC.import('AppKit');

function stringValue(value) {
    if (value === undefined || value === null) return null;
    try { return ObjC.unwrap(value); } catch (_) { return null; }
}

function versionValue(value) {
    var text = stringValue(value);
    return typeof text === 'string' && /^[A-Za-z0-9][A-Za-z0-9._+()-]{0,79}$/.test(text)
        ? text : 'unavailable';
}

function readDictionary(path) {
    try {
        var value = $.NSDictionary.dictionaryWithContentsOfFile($(path));
        return value.isNil() ? null : value;
    }
    catch (_) { return null; }
}

function dictionaryValue(dictionary, key) {
    try { return dictionary ? dictionary.objectForKey($(key)) : null; }
    catch (_) { return null; }
}

function fileText(path) {
    var error = Ref();
    var value = $.NSString.stringWithContentsOfFileEncodingError($(path), $.NSUTF8StringEncoding, error);
    return value ? String(ObjC.unwrap(value)).trim() : '';
}

function number(value) {
    return typeof value === 'number' && isFinite(value) ? value : null;
}

function rect(value) {
    return { x: number(value.origin.x), y: number(value.origin.y),
        width: number(value.size.width), height: number(value.size.height) };
}

function storedPreferences() {
    var defaults = $.NSUserDefaults.alloc.initWithSuiteName($('com.leoarrow.wattson'));
    var containerPath = String(ObjC.unwrap($.NSHomeDirectory()))
        + '/Library/Containers/com.leoarrow.wattson/Data/Library/Preferences/com.leoarrow.wattson.plist';
    var containerExists = Boolean($.NSFileManager.defaultManager.fileExistsAtPath($(containerPath)));
    var container = containerExists ? readDictionary(containerPath) : null;
    var preferenceSource = container ? 'sandbox-container'
        : containerExists ? 'sandbox-container-unavailable' : 'standard-domain-container-absent';
    var types = {
        'menubar.showsPercentage': 'boolean',
        'menubar.iconStyle': ['wattson', 'native'],
        'updates.checkOnLaunch': 'boolean',
        'appearance.liquidGlassEnabled': 'boolean',
        'appearance.liquidGlassStyle': ['regular', 'clear'],
        'appearance.liquidGlassTransparency': 'unit',
        'appearance.colorScheme': ['system', 'light', 'dark'],
        'appearance.inAppLogoStyle': ['color', 'clear'],
        'appearance.dockIconStyle': ['hidden', 'color', 'clear'],
        'popover.module.flow': 'boolean', 'popover.module.ring': 'boolean',
        'popover.module.lanes': 'boolean', 'popover.module.history': 'boolean',
        'popover.module.runtime': 'boolean'
    };
    var result = {};
    Object.keys(types).forEach(function (key) {
        var raw = container ? dictionaryValue(container, key)
            : containerExists ? null : defaults.objectForKey($(key));
        var value;
        try { value = ObjC.deepUnwrap(raw); } catch (_) { value = null; }
        if (value === undefined || value === null) { result[key] = { stored: false }; return; }
        var kind = types[key], valid = false;
        if (kind === 'boolean') {
            valid = typeof value === 'boolean' || value === 0 || value === 1;
            if (valid) value = Boolean(value);
        } else if (kind === 'unit') {
            valid = typeof value === 'number' && isFinite(value) && value >= 0 && value <= 1;
        } else { valid = typeof value === 'string' && kind.indexOf(value) >= 0; }
        result[key] = valid ? { stored: true, value: value } : { stored: true, invalid: true };
    });
    return { source: preferenceSource, values: result };
}

function snapshot(scratch) {
    var system = readDictionary('/System/Library/CoreServices/SystemVersion.plist');
    var info = readDictionary('/Applications/Wattson.app/Contents/Info.plist');
    var receipt = readDictionary('/var/db/receipts/com.leoarrow.wattson.pkg.plist');
    var workspace = $.NSWorkspace.sharedWorkspace;
    var running = [], displays = [];
    var applications = $.NSRunningApplication.runningApplicationsWithBundleIdentifier($('com.leoarrow.wattson'));
    var home = String(ObjC.unwrap($.NSHomeDirectory()));
    for (var index = 0; index < applications.count; index++) {
        var application = applications.objectAtIndex(index);
        var path = stringValue(application.bundleURL.path);
        var bundle = $.NSBundle.bundleWithURL(application.bundleURL);
        running.push({ pid: number(application.processIdentifier),
            location: path === '/Applications/Wattson.app' ? 'canonical-Applications'
                : path === home + '/Applications/Wattson.app' ? 'user-Applications' : 'other-redacted',
            version: versionValue(dictionaryValue(bundle.infoDictionary, 'CFBundleShortVersionString')),
            build: versionValue(dictionaryValue(bundle.infoDictionary, 'CFBundleVersion')),
            finishedLaunching: Boolean(application.finishedLaunching) });
    }
    var screenStatus = 'available';
    try {
        var screens = $.NSScreen.screens;
        for (var screenIndex = 0; screenIndex < screens.count; screenIndex++) {
            var screen = screens.objectAtIndex(screenIndex), insets = screen.safeAreaInsets;
            displays.push({ index: screenIndex, framePoints: rect(screen.frame),
                visibleFramePoints: rect(screen.visibleFrame), scaleFactor: number(screen.backingScaleFactor),
                safeAreaInsetsPoints: { top: number(insets.top), bottom: number(insets.bottom),
                    left: number(insets.left), right: number(insets.right) } });
        }
        if (!displays.length) screenStatus = 'unavailable-no-GUI-session';
    } catch (_) { screenStatus = 'unavailable'; }
    var model = fileText(scratch + '/model.raw'), architecture = fileText(scratch + '/architecture.raw');
    return { schema: 1, issue: 19, collectedAtUTC: new Date().toISOString(),
        privacy: 'Read-only. No personal paths, names, serials, window titles, screenshots or upload.',
        system: {
            productVersion: versionValue(dictionaryValue(system, 'ProductVersion')),
            buildVersion: versionValue(dictionaryValue(system, 'ProductBuildVersion')),
            swVersProductVersion: versionValue($(fileText(scratch + '/productVersion.raw'))),
            swVersBuildVersion: versionValue($(fileText(scratch + '/buildVersion.raw'))),
            model: /^[A-Za-z]+[0-9]+,[0-9]+$/.test(model) ? model : 'unavailable',
            architecture: ['arm64', 'x86_64'].indexOf(architecture) >= 0 ? architecture : 'unavailable'
        },
        installation: { canonicalPresent: Boolean($.NSFileManager.defaultManager.fileExistsAtPath($('/Applications/Wattson.app'))),
            version: versionValue(dictionaryValue(info, 'CFBundleShortVersionString')),
            build: versionValue(dictionaryValue(info, 'CFBundleVersion')),
            packageVersion: versionValue(dictionaryValue(receipt, 'PackageVersion')),
            signature: fileText(scratch + '/signature.raw') === 'verified' ? 'verified' : 'unavailable-or-failed',
            helperPresent: Boolean($.NSFileManager.defaultManager.fileExistsAtPath($('/Library/PrivilegedHelperTools/com.leoarrow.wattson.helper'))),
            runningInstances: running },
        storedPreferences: storedPreferences(),
        accessibility: { reduceMotion: Boolean(workspace.accessibilityDisplayShouldReduceMotion),
            reduceTransparency: Boolean(workspace.accessibilityDisplayShouldReduceTransparency),
            increaseContrast: Boolean(workspace.accessibilityDisplayShouldIncreaseContrast) },
        displayStatus: screenStatus, displays: displays };
}

function capturePlan(installation) {
    var running = installation.runningInstances || [];
    if (running.length && running.every(function (instance) { return instance.version === '4.3.3'; })) {
        return 'skipped-no-trace-4.3.3';
    }
    if (!running.length) return installation.version === '4.3.3'
        ? 'skipped-no-trace-4.3.3' : 'skipped-no-running-instance';
    return 'capture';
}

function events(scratch, mode) {
    var environment = JSON.parse(fileText(scratch + '/snapshot.raw'));
    var raw = fileText(scratch + '/events.ndjson'), accepted = [];
    var knownPIDs = (environment.installation.runningInstances || []).map(function (instance) {
        return instance.pid;
    }).filter(function (pid) { return typeof pid === 'number' && pid > 0 && pid <= 2147483647 && Math.floor(pid) === pid; });
    // Strict event grammar is intentionally closed. Unknown messages never leave scratch.
    raw.split(/\r?\n/).forEach(function (line) {
        var entry;
        try { entry = JSON.parse(line); } catch (_) { return; }
        if (entry.subsystem !== 'com.leoarrow.wattson' || entry.category !== 'popup-events') return;
        if (typeof entry.processID !== 'number' || knownPIDs.indexOf(entry.processID) < 0) return;
        var match = /^source=(status-action|global-mouse|local-mouse|workspace-activation|workspace-space-or-session|outside-click) eventType=(-?[0-9]{1,10}) eventNumber=(-?[0-9]{1,10}) windowNumber=(-?[0-9]{1,10}) openBefore=(true|false|0|1) openAfter=(true|false|0|1) anchorHit=(true|false|0|1)$/.exec(entry.eventMessage || '');
        if (!match || accepted.length >= 200) return;
        var eventType = Number(match[2]), eventNumber = Number(match[3]), windowNumber = Number(match[4]);
        if ([-1, 1, 2, 3, 4, 25, 26].indexOf(eventType) < 0
            || eventNumber < -1 || eventNumber > 2147483647
            || windowNumber < -1 || windowNumber > 2147483647) return;
        var asBoolean = function (value) { return value === 'true' || value === '1'; };
        accepted.push({ processID: entry.processID, source: match[1], eventType: eventType, eventNumber: eventNumber,
            windowNumber: windowNumber, openBefore: asBoolean(match[5]),
            openAfter: asBoolean(match[6]), anchorHit: asBoolean(match[7]) });
    });
    var attributes = $.NSFileManager.defaultManager.attributesOfItemAtPathError($(scratch + '/events.ndjson'), Ref());
    var capturedBytes = Number(ObjC.unwrap(attributes.objectForKey($('NSFileSize'))));
    return { schema: 1, mode: mode, maximumCaptureBytes: 262144,
        captureReachedLimit: capturedBytes >= 262144, acceptedEvents: accepted,
        traceStatus: mode === 'skipped-collect-only' ? 'not-recorded-collect-only'
            : mode === 'skipped-no-trace-4.3.3' ? 'missing-4.3.3-does-not-emit-popup-traces'
            : mode === 'skipped-no-running-instance' ? 'missing-no-running-Wattson-instance-at-collection-start'
            : accepted.length ? 'recorded'
            : environment.installation.version === '4.3.3' ? 'missing-4.3.3-does-not-emit-popup-traces'
            : !knownPIDs.length ? 'missing-no-running-Wattson-instance-at-collection-start'
            : 'missing-no-supported-popup-events-observed',
        note: 'An empty trace does not prove that clicks reached Wattson or that the popup worked.' };
}

function run(arguments) {
    if (arguments[0] === 'snapshot') return JSON.stringify(snapshot(arguments[1]), null, 2);
    if (arguments[0] === 'plan') return capturePlan(JSON.parse(fileText(arguments[1] + '/snapshot.raw')).installation);
    if (arguments[0] === 'events') return JSON.stringify(events(arguments[1], arguments[2]), null, 2);
    throw new Error('Unknown collection mode.');
}
