//
//  Tweak.m
//  FLEXing
//
//  Created by Tanner Bennett on 2016-07-11
//  Copyright © 2016 Tanner Bennett. All rights reserved.
//


#import <roothide.h>
#import <notify.h>
#import <objc/runtime.h>
#import <unistd.h>
#import "Interfaces.h"

BOOL initialized = NO;
id manager = nil;
SEL show = nil;

static id (*FLXGetManager)();
static SEL (*FLXRevealSEL)();
static Class (*FLXWindowClass)();
static int volumeFLEXNotifyToken = 0;

#define SUSU_FLEX_RPC_ROOT @"/var/mobile/Library/Caches/com.susudear.flexing.rpc"
#define SUSU_FLEX_RPC_REQUEST_NOTIFICATION_PREFIX @"com.susudear.flexing.rpc.request/"
#define SUSU_FLEX_RPC_REPLY_NOTIFICATION_PREFIX @"com.susudear.flexing.rpc.reply/"

/// FLEX Runtime Agent 运行在目标 App 进程内，负责把运行时信息序列化为 JSON 返回给 MCP。
@interface SUSUFlexRuntimeAgent : NSObject
@property (nonatomic, copy) NSString *bundleIdentifier;
@property (nonatomic, assign) int notifyToken;
+ (instancetype)sharedAgent;
- (void)start;
- (void)handlePendingRequest;
@end

/// 将 bundle id 转成安全文件名，与 MCP 侧保持一致。
static NSString *SUSUFlexSafeFileComponent(NSString *value) {
    NSMutableString *safe = [NSMutableString stringWithString:value ?: @""];
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-_"];
    for (NSUInteger i = 0; i < safe.length; i++) {
        unichar c = [safe characterAtIndex:i];
        if (![allowed characterIsMember:c]) {
            [safe replaceCharactersInRange:NSMakeRange(i, 1) withString:@"_"];
        }
    }
    return safe.length > 0 ? safe : @"unknown";
}

@implementation SUSUFlexRuntimeAgent

+ (instancetype)sharedAgent {
    static SUSUFlexRuntimeAgent *agent;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        agent = [SUSUFlexRuntimeAgent new];
    });
    return agent;
}

/// 启动 Agent：按当前 App 的 bundle id 注册 Darwin notification 请求入口。
- (void)start {
    if (self.notifyToken != 0) return;
    self.bundleIdentifier = NSBundle.mainBundle.bundleIdentifier;
    if (self.bundleIdentifier.length == 0) return;

    NSString *notification = [SUSU_FLEX_RPC_REQUEST_NOTIFICATION_PREFIX stringByAppendingString:self.bundleIdentifier];
    notify_register_dispatch(notification.UTF8String, &_notifyToken, dispatch_get_main_queue(), ^(__unused int token) {
        [[SUSUFlexRuntimeAgent sharedAgent] handlePendingRequest];
    });
}

/// 读取 MCP 写入的请求文件，执行 action，再写入响应文件。
- (void)handlePendingRequest {
    NSString *safeBundle = SUSUFlexSafeFileComponent(self.bundleIdentifier);
    NSString *requestPath = [[SUSU_FLEX_RPC_ROOT stringByAppendingPathComponent:@"requests"] stringByAppendingPathComponent:[safeBundle stringByAppendingPathExtension:@"json"]];
    NSData *data = [NSData dataWithContentsOfFile:requestPath];
    if (data.length == 0) return;

    NSError *error = nil;
    NSDictionary *request = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (![request isKindOfClass:[NSDictionary class]]) return;

    NSString *requestId = [request[@"id"] isKindOfClass:[NSString class]] ? request[@"id"] : [[NSUUID UUID] UUIDString];
    NSString *action = [request[@"action"] isKindOfClass:[NSString class]] ? request[@"action"] : @"";
    NSDictionary *arguments = [request[@"arguments"] isKindOfClass:[NSDictionary class]] ? request[@"arguments"] : @{};

    NSDictionary *response = [self responseForAction:action arguments:arguments requestId:requestId];
    NSData *responseData = [NSJSONSerialization dataWithJSONObject:response options:0 error:nil];
    if (!responseData) return;

    NSString *responsesDir = [SUSU_FLEX_RPC_ROOT stringByAppendingPathComponent:@"responses"];
    [[NSFileManager defaultManager] createDirectoryAtPath:responsesDir withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0777} error:nil];
    NSString *responsePath = [responsesDir stringByAppendingPathComponent:[requestId stringByAppendingPathExtension:@"json"]];
    [responseData writeToFile:responsePath atomically:YES];

    NSString *replyNotification = [SUSU_FLEX_RPC_REPLY_NOTIFICATION_PREFIX stringByAppendingString:requestId];
    notify_post(replyNotification.UTF8String);
}

/// 按 action 分发到具体 runtime 查询能力，所有结果都必须是 JSON 可序列化对象。
- (NSDictionary *)responseForAction:(NSString *)action arguments:(NSDictionary *)arguments requestId:(NSString *)requestId {
    if ([action isEqualToString:@"ping"]) {
        return @{ @"id": requestId, @"ok": @YES, @"result": @{ @"bundle_id": self.bundleIdentifier ?: @"", @"process": NSProcessInfo.processInfo.processName ?: @"", @"pid": @(getpid()) } };
    }
    if ([action isEqualToString:@"classes"]) {
        return @{ @"id": requestId, @"ok": @YES, @"result": [self runtimeClasses:arguments] };
    }
    if ([action isEqualToString:@"methods"]) {
        return [self runtimeMethods:arguments requestId:requestId];
    }
    return @{ @"id": requestId, @"ok": @NO, @"error": @"unknown_action", @"action": action ?: @"" };
}

/// 枚举当前进程 Objective-C 类，并支持 prefix/contains/limit 过滤，避免返回过大数据。
- (NSDictionary *)runtimeClasses:(NSDictionary *)arguments {
    NSString *prefix = [arguments[@"prefix"] isKindOfClass:[NSString class]] ? arguments[@"prefix"] : nil;
    NSString *contains = [arguments[@"contains"] isKindOfClass:[NSString class]] ? arguments[@"contains"] : nil;
    NSInteger limit = [arguments[@"limit"] respondsToSelector:@selector(integerValue)] ? [arguments[@"limit"] integerValue] : 200;
    if (limit <= 0) limit = 200;
    if (limit > 2000) limit = 2000;

    int count = objc_getClassList(NULL, 0);
    Class *classes = (__unsafe_unretained Class *)calloc((size_t)count, sizeof(Class));
    int actual = objc_getClassList(classes, count);
    NSMutableArray *names = [NSMutableArray array];
    for (int i = 0; i < actual && names.count < (NSUInteger)limit; i++) {
        NSString *name = @(class_getName(classes[i]));
        if (prefix.length > 0 && ![name hasPrefix:prefix]) continue;
        if (contains.length > 0 && [name rangeOfString:contains options:NSCaseInsensitiveSearch].location == NSNotFound) continue;
        [names addObject:name];
    }
    free(classes);
    return @{ @"bundle_id": self.bundleIdentifier ?: @"", @"count": @(names.count), @"total_loaded_classes": @(actual), @"classes": names };
}

/// 枚举指定类的实例方法和类方法，返回 selector 名称用于逆向定位调用面。
- (NSDictionary *)runtimeMethods:(NSDictionary *)arguments requestId:(NSString *)requestId {
    NSString *className = [arguments[@"class"] isKindOfClass:[NSString class]] ? arguments[@"class"] : nil;
    if (className.length == 0) return @{ @"id": requestId, @"ok": @NO, @"error": @"missing_class" };

    Class cls = NSClassFromString(className);
    if (!cls) return @{ @"id": requestId, @"ok": @NO, @"error": @"class_not_found", @"class": className };

    BOOL includeInstance = ![arguments[@"include_instance"] respondsToSelector:@selector(boolValue)] || [arguments[@"include_instance"] boolValue];
    BOOL includeClass = ![arguments[@"include_class"] respondsToSelector:@selector(boolValue)] || [arguments[@"include_class"] boolValue];
    NSMutableDictionary *result = [@{ @"class": className } mutableCopy];

    if (includeInstance) result[@"instance_methods"] = [self methodNamesForClass:cls prefix:@"-"];
    if (includeClass) result[@"class_methods"] = [self methodNamesForClass:object_getClass(cls) prefix:@"+"];
    return @{ @"id": requestId, @"ok": @YES, @"result": result };
}

/// 将 Method 列表转换成字符串，保留 +/- 前缀便于区分实例方法和类方法。
- (NSArray *)methodNamesForClass:(Class)cls prefix:(NSString *)prefix {
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    NSMutableArray *names = [NSMutableArray arrayWithCapacity:count];
    for (unsigned int i = 0; i < count; i++) {
        SEL selector = method_getName(methods[i]);
        [names addObject:[NSString stringWithFormat:@"%@ %@", prefix ?: @"", NSStringFromSelector(selector)]];
    }
    free(methods);
    return names;
}

@end


/// This isn't perfect, but works for most cases as intended
inline bool isLikelyUIProcess() {
    NSString *executablePath = NSProcessInfo.processInfo.arguments[0];

    return [executablePath hasPrefix:@"/var/containers/Bundle/Application"] ||
        [executablePath hasPrefix:@"/Applications"] ||
        [executablePath containsString:@"/procursus/Applications"] ||
        [executablePath hasSuffix:@"CoreServices/SpringBoard.app/SpringBoard"];
}

inline bool isSnapchatApp() {
    // See: near line 44 below
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.toyopagroup.picaboo"];
}

inline BOOL flexAlreadyLoaded() {
    return NSClassFromString(@"FLEXExplorerToolbar") != nil;
}

%ctor {
    // 启动运行时 RPC Agent，让 MCP 可以在目标 App 进程内查询类和方法等信息。
    [[SUSUFlexRuntimeAgent sharedAgent] start];
    NSString *standardPath = jbroot(@"/Library/MobileSubstrate/DynamicLibraries/libFLEX.dylib");
    NSString *reflexPath =   jbroot(@"/Library/MobileSubstrate/DynamicLibraries/libreflex.dylib");
    NSFileManager *disk = NSFileManager.defaultManager;
    NSString *libflex = nil;
    NSString *libreflex = nil;
    void *handle = nil;

    if ([disk fileExistsAtPath:standardPath]) {
        libflex = standardPath;
        if ([disk fileExistsAtPath:reflexPath]) {
            libreflex = reflexPath;
        }
    } else {
        // Check if libFLEX resides in the same folder as me
        NSString *executablePath = NSProcessInfo.processInfo.arguments[0];
        NSString *whereIam = executablePath.stringByDeletingLastPathComponent;
        NSString *possibleFlexPath = [whereIam stringByAppendingPathComponent:@"Frameworks/libFLEX.dylib"];
        NSString *possibleRelexPath = [whereIam stringByAppendingPathComponent:@"Frameworks/libreflex.dylib"];
        if ([disk fileExistsAtPath:possibleFlexPath]) {
            libflex = possibleFlexPath;
            if ([disk fileExistsAtPath:possibleRelexPath]) {
                libreflex = possibleRelexPath;
            }
        } else {
            // libFLEX not found
            // ...
        }
    }

    if (libflex) {
        // Hey Snapchat / Snap Inc devs,
        // This is so users don't get their accounts locked.
        if (isLikelyUIProcess() && !isSnapchatApp()) {
            handle = dlopen(libflex.UTF8String, RTLD_LAZY);

            if (libreflex) {
                dlopen(libreflex.UTF8String, RTLD_NOW);
            }
        }
    }

    if (handle || flexAlreadyLoaded()) {
        // FLEXing.dylib itself does not hard-link against libFLEX.dylib,
        // instead libFLEX.dylib provides getters for the relevant class
        // objects so that it can be updated independently of THIS tweak.
        FLXGetManager = (id(*)())dlsym(handle, "FLXGetManager");
        FLXRevealSEL = (SEL(*)())dlsym(handle, "FLXRevealSEL");
        FLXWindowClass = (Class(*)())dlsym(handle, "FLXWindowClass");

        if (FLXGetManager && FLXRevealSEL) {
            manager = FLXGetManager();
            show = FLXRevealSEL();
            initialized = YES;

            NSString *bid = NSBundle.mainBundle.bundleIdentifier;
            if (bid.length > 0 && ![bid isEqualToString:@"com.apple.springboard"]) {
                NSString *notification = [@"com.susudear.flexing.volume/" stringByAppendingString:bid];
                notify_register_dispatch(notification.UTF8String, &volumeFLEXNotifyToken, dispatch_get_main_queue(), ^(int token) {
                    if (initialized && manager && show) {
                        [manager performSelector:show];
                    }
                });
            }
        }
    }
}

%hook UIWindow
- (BOOL)_shouldCreateContextAsSecure {
    return (initialized && [self isKindOfClass:FLXWindowClass()]) ? YES : %orig;
}

%end


%hook FLEXExplorerViewController
- (BOOL)_canShowWhileLocked {
    return YES;
}
%end

%hook _UISheetPresentationController
- (id)initWithPresentedViewController:(id)present presentingViewController:(id)presenter {
    self = %orig;
    if ([present isKindOfClass:%c(FLEXNavigationController)]) {
        // Enable half height sheet
        if ([self respondsToSelector:@selector(_presentsAtStandardHalfHeight)]) {
            self._presentsAtStandardHalfHeight = YES;
        } else {
            self._detents = @[[%c(_UISheetDetent) _mediumDetent], [%c(_UISheetDetent) _largeDetent]];
        }
        // Start fullscreen, 0 for half height
        self._indexOfCurrentDetent = 1;
        // Don't expand unless dragged up
        self._prefersScrollingExpandsToLargerDetentWhenScrolledToEdge = NO;
        // Don't dim first detent
        self._indexOfLastUndimmedDetent = 1;
    }

    return self;
}
%end

%hook FLEXManager
%new
+ (NSString *)dlopen:(NSString *)path {
    if (!dlopen(path.UTF8String, RTLD_NOW)) {
        return @(dlerror());
    }

    return @"OK";
}
%end
