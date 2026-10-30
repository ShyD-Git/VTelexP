//
//  RuntimeInspector.m
//  Version: 1.0
//  Target:  iOS 16.3.1, TrollFools v4.3
//  Purpose: generic ObjC runtime dumper for dynamic analysis.
//           No interpose, no substrate, pure reflection.
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <string.h>
#import <stdlib.h>

static NSString * const RI_VERSION   = @"[RuntimeInspector] v1.0";
static NSString * const RI_DUMP_FILE = @"RuntimeDump.txt";

#pragma mark - Helpers

static NSString *RI_DocsPath(void) {
    NSArray<NSString *> *paths =
        NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    return paths.count ? paths.firstObject : nil;
}

static BOOL RI_ClassLooksRelevant(NSString *cls) {
    if (cls.length == 0) return NO;
    NSString *lower = cls.lowercaseString;
    // Lọc class dựa trên các keyword runtime phổ biến của StoreKit/Foundation
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

#pragma mark - ObjC Class Dump

static void RI_DumpClass(Class c, NSMutableString *out) {
    [out appendFormat:@"\n=== %s  (super: %s) ===\n",
        class_getName(c),
        class_getSuperclass(c) ? class_getName(class_getSuperclass(c)) : "<root>"];

    unsigned int pc = 0;
    Protocol * __unsafe_unretained *protos = class_copyProtocolList(c, &pc);
    if (pc) {
        [out appendString:@"protocols:\n"];
        for (unsigned int i = 0; i < pc; i++) {
            [out appendFormat:@"  <%s>\n", protocol_getName(protos[i])];
        }
        free(protos);
    }

    unsigned int mc = 0;
    Method *methods = class_copyMethodList(c, &mc);
    if (mc) {
        [out appendString:@"instance methods:\n"];
        for (unsigned int i = 0; i < mc; i++) {
            SEL s = method_getName(methods[i]);
            const char *types = method_getTypeEncoding(methods[i]);
            [out appendFormat:@"  - %s   [%s]\n", sel_getName(s), types ? types : "?"];
        }
        free(methods);
    }

    Class meta = object_getClass(c);
    if (meta) {
        unsigned int cmc = 0;
        Method *cms = class_copyMethodList(meta, &cmc);
        if (cmc) {
            [out appendString:@"class methods:\n"];
            for (unsigned int i = 0; i < cmc; i++) {
                SEL s = method_getName(cms[i]);
                [out appendFormat:@"  + %s\n", sel_getName(s)];
            }
            free(cms);
        }
    }

    unsigned int propc = 0;
    objc_property_t *props = class_copyPropertyList(c, &propc);
    if (propc) {
        [out appendString:@"properties:\n"];
        for (unsigned int i = 0; i < propc; i++) {
            [out appendFormat:@"  @property %s   {%s}\n",
                property_getName(props[i]),
                property_getAttributes(props[i]) ?: "?"];
        }
        free(props);
    }

    unsigned int ivc = 0;
    Ivar *ivars = class_copyIvarList(c, &ivc);
    if (ivc) {
        [out appendString:@"ivars:\n"];
        for (unsigned int i = 0; i < ivc; i++) {
            [out appendFormat:@"  ivar %s   type=%s\n",
                ivar_getName(ivars[i]),
                ivar_getTypeEncoding(ivars[i]) ?: "?"];
        }
        free(ivars);
    }
}

#pragma mark - Loaded-Image String Scan

static BOOL RI_StringLooksInteresting(NSString *s) {
    if (s.length < 5 || s.length > 160) return NO;
    NSString *l = s.lowercaseString;
    static NSString * const keys[] = {
        @"premium", @"plus", @"purchase", @"subscri",
        @"unlock", @"product", @"storekit", @"trial", 
        @"paywall", @"entitle", @"license"
    };
    for (size_t i = 0; i < sizeof(keys)/sizeof(keys[0]); i++) {
        if ([l containsString:keys[i]]) return YES;
    }
    return NO;
}

static void RI_ScanImageStrings(const struct mach_header_64 *mh,
                                intptr_t slide,
                                NSMutableSet<NSString *> *seen,
                                NSMutableString *out) {
    const uint8_t *cursor = (const uint8_t *)mh + sizeof(struct mach_header_64);
    for (uint32_t i = 0; i < mh->ncmds; i++) {
        const struct load_command *lc = (const struct load_command *)cursor;
        if (lc->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
            const struct section_64 *sects =
                (const struct section_64 *)((const uint8_t *)seg + sizeof(struct segment_command_64));
            for (uint32_t s = 0; s < seg->nsects; s++) {
                const char *sn = sects[s].sectname;
                if (strcmp(sn, "__cstring") != 0 &&
                    strcmp(sn, "__objc_methname") != 0 &&
                    strcmp(sn, "__swift5_reflstr") != 0 &&
                    strcmp(sn, "__ustring") != 0) continue;

                const char *base = (const char *)(sects[s].addr + slide);
                size_t size = sects[s].size;
                if (!base || size == 0) continue;

                size_t k = 0;
                while (k < size) {
                    if (k > 0 && base[k-1] != 0) { k++; continue; }
                    const char *cand = base + k;
                    size_t len = strnlen(cand, size - k);
                    if (len < 4 || len > 200) { k += len + 1; continue; }
                    NSString *str = [NSString stringWithUTF8String:cand];
                    if (str && RI_StringLooksInteresting(str) && ![seen containsObject:str]) {
                        [seen addObject:str];
                        [out appendFormat:@"  %@\n", str];
                    }
                    k += len + 1;
                }
            }
        }
        cursor += lc->cmdsize;
    }
}

#pragma mark - Main Dump

static void RI_RunDump(void) {
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"%@\n", RI_VERSION];
    [out appendFormat:@"Bundle ID : %@\n", [[NSBundle mainBundle] bundleIdentifier]];
    [out appendFormat:@"Bundle path: %@\n", [[NSBundle mainBundle] bundlePath]];
    [out appendFormat:@"Timestamp : %@\n\n", [NSDate date]];

    unsigned int classCount = 0;
    Class *allClasses = objc_copyClassList(&classCount);
    NSMutableArray<Class> *targets = [NSMutableArray array];
    for (unsigned int i = 0; i < classCount; i++) {
        Class c = allClasses[i];
        NSString *name = NSStringFromClass(c);
        if (RI_ClassLooksRelevant(name)) [targets addObject:c];
    }
    free(allClasses);

    [out appendFormat:@"--- %lu relevant ObjC classes ---\n", (unsigned long)targets.count];
    for (Class c in targets) {
        RI_DumpClass(c, out);
    }

    [out appendString:@"\n--- interesting strings (loaded images) ---\n"];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    uint32_t imgCount = _dyld_image_count();
    for (uint32_t i = 0; i < imgCount; i++) {
        const char *imgName = _dyld_get_image_name(i);
        if (!imgName) continue;
        
        const struct mach_header *hdr = _dyld_get_image_header(i);
        if (!hdr || hdr->magic != MH_MAGIC_64) continue;

        intptr_t slide = _dyld_get_image_vmaddr_slide(i);
        [out appendFormat:@"# %@\n", @(imgName)];
        RI_ScanImageStrings((const struct mach_header_64 *)hdr, slide, seen, out);
    }

    NSString *docs = RI_DocsPath();
    if (!docs) return;
    
    NSString *path = [docs stringByAppendingPathComponent:RI_DUMP_FILE];
    NSError *err = nil;
    if ([out writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&err]) {
        NSLog(@"%@ dump written: %@", RI_VERSION, path);
    } else {
        NSLog(@"%@ dump FAILED: %@", RI_VERSION, err);
    }
}

#pragma mark - Constructor

__attribute__((constructor))
static void RI_Init(void) {
    NSLog(@"%@ loaded into %@", RI_VERSION, [[NSBundle mainBundle] bundleIdentifier]);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        RI_RunDump();
    });
}
