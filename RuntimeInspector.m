//
//  RuntimeInspector.m
//  Version: 8.0 (Minimal Test)
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

__attribute__((constructor))
static void test_init(void) {
    // Ghi log ra Console
    NSLog(@"[RuntimeInspector] v8.0 DYLIB LOADED THÀNH CÔNG!");

    // Ghi file vào thư mục tmp (dễ tìm nhất)
    NSString *tmp = NSTemporaryDirectory();
    NSString *path = [tmp stringByAppendingPathComponent:@"HELLO_TEST.txt"];
    NSString *content = @"Dylib đã load thành công vào tiến trình app!\n";
    
    NSError *error = nil;
    BOOL success = [content writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error];
    
    if (success) {
        NSLog(@"[RuntimeInspector] Ghi file THÀNH CÔNG tại: %@", path);
    } else {
        NSLog(@"[RuntimeInspector] Ghi file THẤT BẠI: %@", error.localizedDescription);
    }
}
