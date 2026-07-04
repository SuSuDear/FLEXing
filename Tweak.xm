//
//  Tweak.m
//  FLEXing
//
//  Created by Tanner Bennett on 2016-07-11
//  Copyright © 2016 Tanner Bennett. All rights reserved.
//


#import <roothide.h>
#import <notify.h>
#import <QuartzCore/QuartzCore.h>
#import "Interfaces.h"

BOOL initialized = NO;
id manager = nil;
SEL show = nil;

static id (*FLXGetManager)();
static SEL (*FLXRevealSEL)();
static Class (*FLXWindowClass)();
static int volumeFLEXNotifyToken = 0;


@interface FLEXingLoadingDotsView : UIView
@property (nonatomic, strong) NSArray<UIView *> *dots;
@end

@implementation FLEXingLoadingDotsView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        NSMutableArray<UIView *> *items = [NSMutableArray array];
        UIColor *dotColor = nil;
        if (@available(iOS 13.0, *)) {
            dotColor = UIColor.systemBlueColor;
        } else {
            dotColor = [UIColor colorWithRed:0.0 green:0.48 blue:1.0 alpha:1.0];
        }

        for (NSInteger i = 0; i < 3; i++) {
            UIView *dot = [[UIView alloc] initWithFrame:CGRectZero];
            dot.backgroundColor = dotColor;
            dot.layer.cornerRadius = 4.0;
            dot.translatesAutoresizingMaskIntoConstraints = NO;
            [self addSubview:dot];
            [items addObject:dot];
        }

        self.dots = items;
        UIView *d0 = self.dots[0];
        UIView *d1 = self.dots[1];
        UIView *d2 = self.dots[2];
        [NSLayoutConstraint activateConstraints:@[
            [d0.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [d1.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [d2.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [d1.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [d0.rightAnchor constraintEqualToAnchor:d1.leftAnchor constant:-7.0],
            [d2.leftAnchor constraintEqualToAnchor:d1.rightAnchor constant:7.0]
        ]];

        for (UIView *dot in self.dots) {
            [NSLayoutConstraint activateConstraints:@[
                [dot.widthAnchor constraintEqualToConstant:8.0],
                [dot.heightAnchor constraintEqualToConstant:8.0]
            ]];
        }
    }
    return self;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) {
        [self startAnimating];
    }
}

- (void)startAnimating {
    for (NSUInteger i = 0; i < self.dots.count; i++) {
        UIView *dot = self.dots[i];
        CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.y"];
        animation.values = @[@0.0, @-7.0, @0.0];
        animation.keyTimes = @[@0.0, @0.45, @1.0];
        animation.duration = 0.72;
        animation.beginTime = CACurrentMediaTime() + (0.12 * i);
        animation.repeatCount = HUGE_VALF;
        animation.removedOnCompletion = NO;
        [dot.layer addAnimation:animation forKey:@"flexing.dots.bounce"];
    }
}

@end

static UIView *FLEXingLoadingOverlay = nil;

static UIWindow *FLEXingPresentationWindow(void) {
    UIWindow *keyWindow = UIApplication.sharedApplication.keyWindow;
    if (keyWindow) return keyWindow;

    for (UIWindow *window in UIApplication.sharedApplication.windows.reverseObjectEnumerator) {
        if (!window.hidden && window.alpha > 0.0) {
            return window;
        }
    }
    return nil;
}

static void FLEXingShowLoadingOverlay(void) {
    UIWindow *window = FLEXingPresentationWindow();
    if (!window || FLEXingLoadingOverlay) return;

    UIView *overlay = [[UIView alloc] initWithFrame:window.bounds];
    overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    overlay.userInteractionEnabled = NO;
    overlay.alpha = 0.0;
    overlay.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.12];

    UIView *card = [[UIView alloc] initWithFrame:CGRectZero];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.layer.cornerRadius = 18.0;
    card.layer.masksToBounds = YES;
    if (@available(iOS 13.0, *)) {
        card.backgroundColor = [UIColor.secondarySystemBackgroundColor colorWithAlphaComponent:0.92];
    } else {
        card.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.92];
    }
    [overlay addSubview:card];

    FLEXingLoadingDotsView *dotsView = [[FLEXingLoadingDotsView alloc] initWithFrame:CGRectZero];
    dotsView.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:dotsView];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.text = @"Loading FLEX";
    label.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
    label.textAlignment = NSTextAlignmentCenter;
    if (@available(iOS 13.0, *)) {
        label.textColor = UIColor.secondaryLabelColor;
    } else {
        label.textColor = UIColor.darkGrayColor;
    }
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:label];

    [window addSubview:overlay];
    [NSLayoutConstraint activateConstraints:@[
        [card.centerXAnchor constraintEqualToAnchor:overlay.centerXAnchor],
        [card.centerYAnchor constraintEqualToAnchor:overlay.centerYAnchor],
        [card.widthAnchor constraintEqualToConstant:170.0],
        [card.heightAnchor constraintEqualToConstant:92.0],
        [dotsView.topAnchor constraintEqualToAnchor:card.topAnchor constant:22.0],
        [dotsView.centerXAnchor constraintEqualToAnchor:card.centerXAnchor],
        [dotsView.widthAnchor constraintEqualToConstant:64.0],
        [dotsView.heightAnchor constraintEqualToConstant:24.0],
        [label.topAnchor constraintEqualToAnchor:dotsView.bottomAnchor constant:10.0],
        [label.leftAnchor constraintEqualToAnchor:card.leftAnchor constant:16.0],
        [label.rightAnchor constraintEqualToAnchor:card.rightAnchor constant:-16.0]
    ]];

    FLEXingLoadingOverlay = overlay;
    [UIView animateWithDuration:0.16 animations:^{
        overlay.alpha = 1.0;
    }];
}

static void FLEXingHideLoadingOverlay(void) {
    UIView *overlay = FLEXingLoadingOverlay;
    FLEXingLoadingOverlay = nil;
    if (!overlay) return;

    [UIView animateWithDuration:0.16 animations:^{
        overlay.alpha = 0.0;
    } completion:^(BOOL finished) {
        [overlay removeFromSuperview];
    }];
}

void FLEXingShowLoadingThenRun(dispatch_block_t block) {
    dispatch_async(dispatch_get_main_queue(), ^{
        FLEXingShowLoadingOverlay();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.55 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            FLEXingHideLoadingOverlay();
            if (block) block();
        });
    });
}

void FLEXingShowExplorerWithLoading(void) {
    if (!initialized || !manager || !show) return;

    FLEXingShowLoadingThenRun(^{
        if (initialized && manager && show) {
            [manager performSelector:show];
        }
    });
}

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
