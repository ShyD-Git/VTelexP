//
//  RuntimeInspector.m
//  Version: 5.0
//  Target:  iOS 16.3.1, TrollFools v4.3
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <string.h>
#import <stdlib.h>

static NSString * const RI_VERSION   = @"[RuntimeInspector] v5.0";
static NSString * const RI_DUMP_FILE = @"RuntimeDump_v5.txt";

#pragma mark - Helpers

static void RI_WriteDump(NSString *content) {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docs = paths.count ? paths.firstObject : nil;
    NSString *lib = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) firstObject];
    NSString *tmp = NSTemporaryDirectory();

    NSArray *targets = @[docs ?: @"", lib ?: @"", tmp ?: @""];
    for (NSString *dir in targets) {
        if (dir.length == 0) continue;
        NSString *path = [dir stringByAppendingPathComponent:RI_DUMP_FILE];
        [content writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

static BOOL RI_ClassLooksRelevant(NSString *cls) {
    if (cls.length == 0) return NO;
    NSString *lower = cls.lowercaseString;
    static NSString * const keys[] = {
        @"purchase", @"subscri", @"unlock", @"paywall",
        @"storekit", @"receipt", @"entitle", @"product",
        @"userdefault", @"keychain", @"license", @"trial"
    };
    for (size_t i = 0; i < sizeof(keys)/sizeof(keys[0]); i++) {
        if ([lower containsString:keys[i]]) return YES;
    }
    return NO;
}

static void RI_DumpClass(Class c, NSMutableString *out) {
    [out appendFormat:@"\n=== %s  (super: %s) ===\n", class_getName(c), class_getSuperclass(c) ? class_getName(class_getSuperclass(c)) : "<root>"];
    unsigned int mc = 0;
    Method *methods = class_copyMethodList(c, &mc);
    if (mc) {
        [out appendString:@"methods:\n"];
        for (unsigned int i = 0; i < mc; i++) {
            [out appendFormat:@"  - %s   [%s]\n", sel_getName(method_getName(methods[i])), method_getTypeEncoding(methods[i]) ?: "?"];
        }
        free(methods);
    }
    unsigned int propc = 0;
    objc_property_t *props = class_copyPropertyList(c, &propc);
    if (propc) {
        [out appendString:@"properties:\n"];
        for (unsigned int i = 0; i < propc; i++) {
            [out appendFormat:@"  @property %s\n", property_getName(props[i])];
        }
        free(props);
    }
    unsigned int ivc = 0;
    Ivar *ivars = class_copyIvarList(c, &ivc);
    if (ivc) {
        [out appendString:@"ivars:\n"];
        for (unsigned int i = 0; i < ivc; i++) {
            [out appendFormat:@"  ivar %s\n", ivar_getName(ivars[i])];
        }
        free(ivars);
    }
}

static void RI_RunDump(void) {
    @autoreleasepool {
        NSMutableString *out = [NSMutableString string];
        [out appendFormat:@"%@\nBundle: %@\n\n", RI_VERSION, [[NSBundle mainBundle] bundleIdentifier]];

        unsigned int classCount = 0;
        Class *allClasses = objc_copyClassList(&classCount);
        NSMutableArray<Class> *targets = [NSMutableArray array];
        for (unsigned int i = 0; i < classCount; i++) {
            if (RI_ClassLooksRelevant(NSStringFromClass(allClasses[i]))) [targets addObject:allClasses[i]];
        }
        free(allClasses);

        [out appendFormat:@"--- %lu relevant classes ---\n", (unsigned long)targets.count];
        for (Class c in targets) { RI_DumpClass(c, out); }

        RI_WriteDump(out);
        NSLog(@"[RuntimeInspector] v5.0 dumped to files.");
    }
}

static void RI_ShowAlert(void) {
    UIWindow *keyWindow = nil;
    
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
                for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                    if (w.isKeyWindow) { keyWindow = w; break; }
                }
            }
        }
    }
    if (!keyWindow) keyWindow = [UIApplication sharedApplication].keyWindow;
    
    if (keyWindow && keyWindow.rootViewController) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"RuntimeInspector v5.0"
                                                                       message:@"Dylib đã chạy! File dump đã ghi."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [keyWindow.rootViewController presentViewController:alert animated:YES completion:nil];
    }
}

__attribute__((constructor))
static void RI_Init(void) {
    NSLog(@"[RuntimeInspector] v5.0 loaded.");
    
    // Ghi file ngay lập tức
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        RI_RunDump();
    });
    
    // Đợi 3 giây cho UI app hiện lên rồi mới bung Alert
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        RI_ShowAlert();
    });
}
