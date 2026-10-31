#include "keychain.h"
#include <Security/Security.h>
#include <CoreFoundation/CoreFoundation.h>
#include <TargetConditionals.h>
#include <stdlib.h>
#include <string.h>

static CFMutableDictionaryRef query(void) {
    CFMutableDictionaryRef q = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFDictionarySetValue(q, kSecClass, kSecClassGenericPassword);
    CFDictionarySetValue(q, kSecAttrService, CFSTR("dev.chordesk.embedded-tailnet"));
    CFDictionarySetValue(q, kSecAttrAccount, CFSTR("node-state-v1"));
    CFDictionarySetValue(q, kSecAttrSynchronizable, kCFBooleanFalse);
    return q;
}

int cr_state_read(void **data, size_t *length) {
    *data = NULL; *length = 0;
    CFMutableDictionaryRef q = query();
    CFDictionarySetValue(q, kSecReturnData, kCFBooleanTrue);
    CFDictionarySetValue(q, kSecMatchLimit, kSecMatchLimitOne);
    CFTypeRef value = NULL;
    OSStatus status = SecItemCopyMatching(q, &value);
    CFRelease(q);
    if (status == errSecItemNotFound) return 0;
    if (status != errSecSuccess) return status;
    if (!value || CFGetTypeID(value) != CFDataGetTypeID() || CFDataGetLength(value) > 2 * 1024 * 1024) {
        if (value) CFRelease(value);
        return errSecDecode;
    }
    *length = (size_t)CFDataGetLength(value);
    *data = malloc(*length ? *length : 1);
    if (!*data) { CFRelease(value); return errSecAllocate; }
    memcpy(*data, CFDataGetBytePtr(value), *length);
    CFRelease(value);
    return 0;
}

int cr_state_write(const void *data, size_t length) {
    if (length > 2 * 1024 * 1024) return errSecParam;
    CFMutableDictionaryRef q = query();
    CFDataRef value = CFDataCreate(NULL, data, (CFIndex)length);
    const void *keys[] = { kSecValueData };
    const void *values[] = { value };
    CFDictionaryRef update = CFDictionaryCreate(NULL, keys, values, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    OSStatus status = SecItemUpdate(q, update);
    if (status == errSecItemNotFound) {
        CFDictionarySetValue(q, kSecValueData, value);
#if TARGET_OS_IPHONE
        CFDictionarySetValue(q, kSecAttrAccessible, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly);
#endif
        status = SecItemAdd(q, NULL);
    }
    CFRelease(update); CFRelease(value); CFRelease(q);
    return status;
}
