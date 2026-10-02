#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

@interface FPSOverlayController : NSObject
@property(nonatomic, strong) UILabel *label;
@property(nonatomic, strong) CADisplayLink *displayLink;
@property(nonatomic, weak) UIWindow *hostWindow;
@property(nonatomic) CFTimeInterval lastTimestamp;
@property(nonatomic) NSInteger frameCount;
@end

@implementation FPSOverlayController

- (void)start {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self attachToGameWindow];
    });
}

- (UIWindow *)findGameWindow {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {

            if (scene.activationState != UISceneActivationStateForegroundActive &&
                scene.activationState != UISceneActivationStateForegroundInactive) {
                continue;
            }

            if (![scene isKindOfClass:[UIWindowScene class]]) {
                continue;
            }

            UIWindowScene *windowScene = (UIWindowScene *)scene;

            // Prefer the key window.
            for (UIWindow *window in windowScene.windows) {
                if (!window.hidden &&
                    window.alpha > 0.01 &&
                    window.windowLevel == UIWindowLevelNormal &&
                    window.isKeyWindow) {
                    return window;
                }
            }

            // Otherwise use the first normal visible window.
            for (UIWindow *window in windowScene.windows) {
                if (!window.hidden &&
                    window.alpha > 0.01 &&
                    window.windowLevel == UIWindowLevelNormal) {
                    return window;
                }
            }
        }
    }

    return nil;
}

- (void)attachToGameWindow {
    UIWindow *window = [self findGameWindow];

    if (!window) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self attachToGameWindow];
        });
        return;
    }

    self.hostWindow = window;

    UILabel *label = [[UILabel alloc] init];

    label.textColor = [UIColor whiteColor];
    label.backgroundColor = [UIColor clearColor];
    label.font = [UIFont boldSystemFontOfSize:22.0];
    label.numberOfLines = 2;
    label.textAlignment = NSTextAlignmentLeft;
    label.text = @"FPS --\n-- ms";
    label.userInteractionEnabled = NO;

    // Shadow only — no background box.
    label.layer.shadowColor = [UIColor blackColor].CGColor;
    label.layer.shadowOffset = CGSizeMake(1.0, 1.0);
    label.layer.shadowOpacity = 0.9;
    label.layer.shadowRadius = 2.0;

    label.translatesAutoresizingMaskIntoConstraints = NO;

    [window addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:window.leadingAnchor
                                            constant:155.0],

        [label.topAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.topAnchor
                                         constant:8.0],

        [label.widthAnchor constraintEqualToConstant:170.0],

        [label.heightAnchor constraintEqualToConstant:60.0]
    ]];

    self.label = label;
    self.lastTimestamp = 0;
    self.frameCount = 0;

    self.displayLink =
        [CADisplayLink displayLinkWithTarget:self
                                    selector:@selector(frameTick:)];

    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop]
                           forMode:NSRunLoopCommonModes];
}

- (void)frameTick:(CADisplayLink *)link {

    if (self.lastTimestamp == 0) {
        self.lastTimestamp = link.timestamp;
        self.frameCount = 0;
        return;
    }

    self.frameCount++;

    CFTimeInterval elapsed =
        link.timestamp - self.lastTimestamp;

    if (elapsed >= 0.5) {

        double fps =
            self.frameCount / elapsed;

        double ms =
            fps > 0.0 ? (1000.0 / fps) : 0.0;

        self.label.text =
            [NSString stringWithFormat:@"FPS %.1f\n%.2f ms",
                                       fps,
                                       ms];

        self.frameCount = 0;
        self.lastTimestamp = link.timestamp;
    }
}

@end

static FPSOverlayController *gFPSOverlayController;

__attribute__((constructor))
static void FPSOverlayInit(void) {

    dispatch_async(dispatch_get_main_queue(), ^{

        gFPSOverlayController =
            [FPSOverlayController new];

        [gFPSOverlayController start];
    });
}
