/* Read-only JXA. No UI scripting, broad preference domain reads or mutations. */
ObjC.import('Foundation');
ObjC.import('AppKit');
ObjC.import('CoreFoundation');

function unwrapped(value) {
    try { return ObjC.unwrap(value); } catch (_) { return null; }
}

function versionValue(value) {
    var text = unwrapped(value);
    return typeof text === 'string' && /^[A-Za-z0-9][A-Za-z0-9._+()-]{0,79}$/.test(text)
        ? text : 'unavailable';
}

function dictionary(path) {
    try {
        var value = $.NSDictionary.dictionaryWithContentsOfFile($(path));
        return value.isNil() ? null : value;
    } catch (_) { return null; }
}

function field(value, key) {
    try { return value ? value.objectForKey($(key)) : null; } catch (_) { return null; }
}

function fileText(path) {
    try {
        var attributes = $.NSFileManager.defaultManager.attributesOfItemAtPathError($(path), Ref());
        var size = Number(unwrapped(attributes.objectForKey($('NSFileSize'))));
        if (!isFinite(size) || size < 0 || size > 16384) return '';
        var value = $.NSString.stringWithContentsOfFileEncodingError($(path), $.NSUTF8StringEncoding, Ref());
        return value.isNil() ? '' : String(unwrapped(value)).trim();
    } catch (_) { return ''; }
}

function exists(path) {
    return Boolean($.NSFileManager.defaultManager.fileExistsAtPath($(path)));
}

function describePreference(object) {
    if (!object || object.isNil()) return { status: 'available', exists: false, type: 'absent' };
    var result = { status: 'available', exists: true, type: 'unsupported' };
    var type = Number($.CFGetTypeID(object));
    if (type === Number($.CFBooleanGetTypeID())) result.type = 'boolean';
    else if (type === Number($.CFNumberGetTypeID())) {
        result.type = 'number';
        var value = unwrapped(object);
        if (typeof value === 'number' && isFinite(value) && Math.abs(value) <= 9007199254740991) {
            result.value = value;
        } else result.numericValueStatus = 'unsupported-range';
    } else if (type === Number($.CFStringGetTypeID())) result.type = 'string';
    else if (type === Number($.CFArrayGetTypeID())) result.type = 'array';
    else if (type === Number($.CFDictionaryGetTypeID())) result.type = 'dictionary';
    else if (type === Number($.CFDataGetTypeID())) result.type = 'data';
    else if (type === Number($.CFDateGetTypeID())) result.type = 'date';
    return result;
}

function readBatteryPreference() {
    try {
        // Read exactly this key and scope. Do not synchronize or write the domain.
        var raw = $.CFPreferencesCopyValue($('Battery'), $('com.apple.controlcenter'),
            $.kCFPreferencesCurrentUser, $.kCFPreferencesCurrentHost);
        // JXA returns a CF reference wrapper; inspect the bridged object, not the wrapper.
        return describePreference(ObjC.castRefToObject(raw));
    } catch (_) { return { status: 'unavailable', exists: null, type: 'unavailable' }; }
}

function sanitizeProbe(operation, text) {
    var result = { operation: operation, budgetMs: 4000, status: 'probe-unavailable' };
    var raw;
    try { raw = JSON.parse(text); } catch (_) { return result; }
    if (!raw || raw.operation !== operation) return result;
    var statuses = ['success', 'helper-error', 'invalid-response', 'response-too-large',
        'timeout', 'connection-failed', 'io-error'];
    if (statuses.indexOf(raw.status) < 0) return result;
    result.status = raw.status;
    if (typeof raw.durationMs === 'number' && isFinite(raw.durationMs)
        && raw.durationMs >= 0 && raw.durationMs <= 10000 && Math.floor(raw.durationMs) === raw.durationMs) {
        result.durationMs = raw.durationMs;
    }
    if (raw.status !== 'success' && raw.status !== 'helper-error') return result;
    var response = raw.response;
    if (!response || typeof response.ok !== 'boolean') {
        result.status = 'invalid-response'; return result;
    }
    var clean = { ok: response.ok };
    if (response.ok && raw.status === 'success') {
        var key = operation === 'health' ? 'health' : 'hidden';
        if (typeof response[key] !== 'boolean') { result.status = 'invalid-response'; return result; }
        clean[key] = response[key];
    } else if (!response.ok && raw.status === 'helper-error') {
        var errors = ['unknown battery preference', 'request expired', 'rejected', 'malformed'];
        clean.error = errors.indexOf(response.error) >= 0 ? response.error : 'unrecognized-error';
        var reasons = ['userContextUnavailable', 'preferenceSyncFailed', 'preferenceMissing',
            'preferenceTypeUnsupported', 'preferenceValueUnsupported', 'preferenceWorkerFailed'];
        if (reasons.indexOf(response.reason) >= 0) clean.reason = response.reason;
    } else { result.status = 'invalid-response'; return result; }
    result.response = clean;
    return result;
}

function snapshot(scratch) {
    var system = dictionary('/System/Library/CoreServices/SystemVersion.plist');
    var info = dictionary('/Applications/Wattson.app/Contents/Info.plist');
    var receipt = dictionary('/var/db/receipts/com.leoarrow.wattson.pkg.plist');
    var applications = $.NSRunningApplication.runningApplicationsWithBundleIdentifier($('com.leoarrow.wattson'));
    var home = String(unwrapped($.NSHomeDirectory())), running = [];
    for (var index = 0; index < applications.count && index < 8; index++) {
        var application = applications.objectAtIndex(index);
        var path = unwrapped(application.bundleURL.path);
        var bundle = $.NSBundle.bundleWithURL(application.bundleURL);
        running.push({ location: path === '/Applications/Wattson.app' ? 'canonical-Applications'
                : path === home + '/Applications/Wattson.app' ? 'user-Applications' : 'other-redacted',
            version: versionValue(field(bundle.infoDictionary, 'CFBundleShortVersionString')),
            build: versionValue(field(bundle.infoDictionary, 'CFBundleVersion')),
            finishedLaunching: Boolean(application.finishedLaunching) });
    }
    var architecture = fileText(scratch + '/architecture.raw');
    return { schema: 1, collector: 'system-battery-icon-v1', collectedAtUTC: new Date().toISOString(),
        privacy: 'Read-only. No personal paths, names, serials, screenshots, logs, full preference domains or upload.',
        system: { productVersion: versionValue(field(system, 'ProductVersion')),
            buildVersion: versionValue(field(system, 'ProductBuildVersion')),
            swVersProductVersion: versionValue($(fileText(scratch + '/productVersion.raw'))),
            swVersBuildVersion: versionValue($(fileText(scratch + '/buildVersion.raw'))),
            architecture: ['arm64', 'x86_64'].indexOf(architecture) >= 0 ? architecture : 'unavailable' },
        installation: { canonicalPresent: exists('/Applications/Wattson.app'),
            version: versionValue(field(info, 'CFBundleShortVersionString')),
            build: versionValue(field(info, 'CFBundleVersion')),
            packageVersion: versionValue(field(receipt, 'PackageVersion')),
            signature: fileText(scratch + '/signature.raw') === 'verified' ? 'verified' : 'unavailable-or-failed',
            helperPresent: exists('/Library/PrivilegedHelperTools/com.leoarrow.wattson.helper'),
            launchDaemonPresent: exists('/Library/LaunchDaemons/com.leoarrow.wattson.helper.plist'),
            socketPresent: exists('/var/run/wattson-helper.sock'),
            runningInstanceCount: Number(applications.count), runningInstances: running },
        currentUserCurrentHostBatteryPreference: readBatteryPreference(),
        helper: { health: sanitizeProbe('health', fileText(scratch + '/health.raw')),
            batteryIcon: sanitizeProbe('getSystemBatteryIconHidden', fileText(scratch + '/batteryIcon.raw')) } };
}

function run(arguments) {
    if (arguments.length !== 2 || arguments[0] !== 'snapshot') throw new Error('Unknown collection mode.');
    return JSON.stringify(snapshot(arguments[1]), null, 2);
}
