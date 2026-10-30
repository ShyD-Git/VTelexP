//
//  RuntimeInspector.m
//  Version: 7.0
//  Target:  iOS 16.3.1, TrollFools v4.3
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <string.h>
#import <stdlib.h>

static NSString * const RI_VERSION   = @"[RuntimeInspector] v7.0";
static NSString * const RI_DUMP_FILE = @"RuntimeDump_v7.txt";
static BOOL hasDumped = NO;

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
        @"userdefault", @"keychain", @"license", @"trial", @"viettelex"
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
        NSLog(@"[RuntimeInspector] v7.0 dumped to file.");
    }
}

#pragma mark - Hook UIViewController

static void (*orig_viewDidAppear)(id, SEL, BOOL);

static void my_viewDidAppear(UIViewController *self, SEL _cmd, BOOL animated) {
    // Gọi lại hàm gốc
    if (orig_viewDidAppear) {
        orig_viewDidAppear(self, _cmd, animated);
    }

    // Chỉ chạy 1 lần duy nhất khi UI đã sẵn sàng
    if (!hasDumped) {
        hasDumped = YES;
        
        // Ghi file
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            RI_RunDump();
        });

        // Hiện Alert báo hiệu thành công
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"RuntimeInspector v7.0"
                                                                       message:@"Hook thành công! File dump đã ghi vào Documents, Library và tmp."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

#pragma mark - Init

__attribute__((constructor))
static void RI_Init(void) {
    NSLog(@"[RuntimeInspector] v7.0 loaded.");
    
    // Hook viewDidAppear của UIViewController
    Class cls = [UIViewController class];
    SEL sel = @selector(viewDidAppear:);
    Method method = class_getInstanceMethod(cls, sel);
    
    if (method) {
        orig_viewDidAppear = (void *)method_getImplementation(method);
        method_setImplementation(method, (IMP)my_viewDidAppear);
        NSLog(@"[RuntimeInspector] Hooked UIViewController viewDidAppear:");
    }
}
