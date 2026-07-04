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
            FLEXingShowLoadingThenRun(^{
                notify_post(notification.UTF8String);
            });
        } else if (initialized && manager && show) {
            FLEXingShowExplorerWithLoading();
        }
    }

    return %orig;
}
%end

%end // VolumeButtonGesture

%ctor {
    %init(VolumeButtonGesture);
}
