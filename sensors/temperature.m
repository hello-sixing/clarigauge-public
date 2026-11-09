// Read-only IOHID temperature events; API pattern documented by
// https://github.com/fermion-star/apple_sensors/blob/master/temp_sensor.m
#import <Foundation/Foundation.h>
#include <dlfcn.h>

typedef CFTypeRef (*CreateClient)(CFAllocatorRef);
typedef void (*SetMatching)(CFTypeRef, CFDictionaryRef);
typedef CFArrayRef (*CopyServices)(CFTypeRef);
typedef CFTypeRef (*CopyProperty)(CFTypeRef, CFStringRef);
typedef CFTypeRef (*CopyEvent)(CFTypeRef, int64_t, int32_t, int64_t);
typedef double (*FloatValue)(CFTypeRef, uint32_t);

int main(void) {
    @autoreleasepool {
        void *h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
        if (!h) return 2;
        CreateClient create = (CreateClient)dlsym(h,"IOHIDEventSystemClientCreate");
        SetMatching match = (SetMatching)dlsym(h,"IOHIDEventSystemClientSetMatching");
        CopyServices services = (CopyServices)dlsym(h,"IOHIDEventSystemClientCopyServices");
        CopyProperty property = (CopyProperty)dlsym(h,"IOHIDServiceClientCopyProperty");
        CopyEvent event = (CopyEvent)dlsym(h,"IOHIDServiceClientCopyEvent");
        FloatValue value = (FloatValue)dlsym(h,"IOHIDEventGetFloatValue");
        if (!create || !match || !services || !property || !event || !value) return 3;
        CFTypeRef client = create(kCFAllocatorDefault);
        if (!client) return 4;
        match(client,(__bridge CFDictionaryRef)@{@"PrimaryUsagePage":@65280,@"PrimaryUsage":@5});
        CFArrayRef devices = services(client);
        NSMutableDictionary *temps = [NSMutableDictionary dictionary];
        if (devices) {
            for (CFIndex i=0;i<CFArrayGetCount(devices);i++) {
                CFTypeRef service = CFArrayGetValueAtIndex(devices,i);
                CFTypeRef name = property(service,CFSTR("Product"));
                CFTypeRef sample = event(service,15,0,0);
                if (name && sample && CFGetTypeID(name)==CFStringGetTypeID()) {
                    double celsius = value(sample,15<<16);
                    if (isfinite(celsius) && celsius>0 && celsius<150)
                        temps[(__bridge NSString *)name]=@(celsius);
                }
                if (name) CFRelease(name);
                if (sample) CFRelease(sample);
            }
            CFRelease(devices);
        }
        CFRelease(client);
        NSDictionary *result=@{@"sensors_celsius":temps,@"thermal_state":@([NSProcessInfo processInfo].thermalState)};
        NSData *json=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingSortedKeys error:nil];
        puts([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String);
        dlclose(h);
        return temps.count ? 0 : 5;
    }
}
