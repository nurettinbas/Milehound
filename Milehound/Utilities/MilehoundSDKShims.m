#import "MilehoundSDKShims.h"

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 270100
#import <UIKit/UIHingeInteraction.h>
#endif

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 270000
#import <AVFoundation/AVFoundation.h>
#endif

void MilehoundInstallHingeInteraction(UIView *view, void (^onFullyOpen)(BOOL fullyOpen)) {
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 270100
    if (@available(iOS 27.1, *)) {
        UIHingeInteraction *interaction = [[UIHingeInteraction alloc] initWithUpdateHandler:^(UIHingeInteraction *interaction, UIHingeInteractionUpdate *update) {
            (void)interaction;
            UIHinge *hinge = update.hinge;
            onFullyOpen(hinge != nil && hinge.status == UIHingeStatusFullyOpen);
        }];
        [view addInteraction:interaction];
        return;
    }
#endif
    (void)view;
    (void)onFullyOpen;
}

BOOL MilehoundActivateAudioSessionIfAvailable(void (^completion)(BOOL activated)) {
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 270000
    if (@available(iOS 27.0, *)) {
        [[AVAudioSession sharedInstance] activateWithOptions:0 completionHandler:^(BOOL activated, NSError *error) {
            (void)error;
            completion(activated);
        }];
        return YES;
    }
#endif
    (void)completion;
    return NO;
}
