//
//  SpringBoard.xm
//  FLEXing
//
//  Created by Tanner Bennett on 2019-11-25
//  Copyright © 2019 Tanner Bennett. All rights reserved.
//

//-------------------------------//
// This file is for iOS 13+ only //
//    Credit:  DGh0st/FLEXall    //
//-------------------------------//

#import <notify.h>
#import "Interfaces.h"

%group iOS13StatusBar
// Runs in SpringBoard; forwards status bar events to app
%hook SBMainDisplaySceneLayoutStatusBarView
- (void)_addStatusBarIfNeeded {
	%orig;

	UIView *statusBar = [self valueForKey:@"_statusBar"];
	[statusBar addGestureRecognizer:[[UILongPressGestureRecognizer alloc]
        initWithTarget:self action:@selector(flexGestureHandler:)
    ]];
}

%new
- (void)flexGestureHandler:(UILongPressGestureRecognizer *)recognizer {
	if (recognizer.state == UIGestureRecognizerStateBegan) {
		[self _statusBarTapped:recognizer type:kFLEXLongPressGesture];
	}
}
%end // SBMainDisplaySceneLayoutStatusBarView

// Runs in apps; receives status bar events
%hook UIStatusBarManager
- (void)handleTapAction:(UIStatusBarTapAction *)action {
    if (action.type == kFLEXLongPressGesture) {
        [manager performSelector:show];
    } else {
        %orig(action);
    }
}
%end // UIStatusBarManager
%end // iOS13StatusBar


%group VolumeButtonGesture

%hook SpringBoard
- (BOOL)_handlePhysicalButtonEvent:(UIPressesEvent *)event {
    BOOL upPressed = NO;
    BOOL downPressed = NO;

    for (UIPress *press in event.allPresses.allObjects) {
        if (press.type == 102 && press.force == 1) {
            upPressed = YES;
        }
        if (press.type == 103 && press.force == 1) {
            downPressed = YES;
        }
    }

    if (upPressed && downPressed) {
        SBApplication *frontMostApp = [self _accessibilityFrontMostApplication];
        NSString *bundleIdentifier = [frontMostApp bundleIdentifier];
        if (bundleIdentifier.length > 0) {
            NSString *notification = [@"com.susudear.flexing.volume/" stringByAppendingString:bundleIdentifier];
            notify_post(notification.UTF8String);
        } else if (initialized && manager && show) {
            [manager performSelector:show];
        }
    }

    return %orig;
}
%end

%end // VolumeButtonGesture

%ctor {
    %init(VolumeButtonGesture);

    if (@available(iOS 13, *)) {
        %init(iOS13StatusBar);
    }
}
