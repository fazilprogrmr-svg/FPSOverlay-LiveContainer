#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

@interface FPSOverlayController : NSObject
@property(nonatomic,strong) UILabel *label;
@property(nonatomic,strong) CADisplayLink *displayLink;
@property(nonatomic) CFTimeInterval lastTimestamp;
@property(nonatomic) NSUInteger frames;
@property(nonatomic) double fps;
@end

@implementation FPSOverlayController

- (void)start {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self installOverlay];
        self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
        [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    });
}

- (void)installOverlay {
    UIWindow *window = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive &&
            [scene isKindOfClass:[UIWindowScene class]]) {
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (w.isKeyWindow) { window = w; break; }
            }
            if (!window) {
                for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                    if (!w.hidden && w.alpha > 0 && w.windowLevel == UIWindowLevelNormal) {
                        window = w; break;
                    }
                }
            }
        }
        if (window) break;
    }

    if (!window) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [self installOverlay]; });
        return;
    }

    self.label = [[UILabel alloc] initWithFrame:CGRectMake(8, 8, 115, 42)];
    self.label.text = @"FPS --";
    self.label.textColor = UIColor.whiteColor;
    self.label.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.65];
    self.label.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightBold];
    self.label.textAlignment = NSTextAlignmentCenter;
    self.label.layer.cornerRadius = 7;
    self.label.layer.masksToBounds = YES;
    self.label.userInteractionEnabled = NO;

    self.label.translatesAutoresizingMaskIntoConstraints = NO;
    [window addSubview:self.label];

    [NSLayoutConstraint activateConstraints:@[
        [self.label.leadingAnchor constraintEqualToAnchor:window.leadingAnchor constant:8],
        [self.label.topAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.topAnchor constant:8],
        [self.label.widthAnchor constraintEqualToConstant:115],
        [self.label.heightAnchor constraintEqualToConstant:42]
    ]];
}

- (void)tick:(CADisplayLink *)link {
    if (self.lastTimestamp == 0) {
        self.lastTimestamp = link.timestamp;
        return;
    }

    self.frames++;
    CFTimeInterval elapsed = link.timestamp - self.lastTimestamp;

    if (elapsed >= 0.5) {
        self.fps = (double)self.frames / elapsed;
        double frameMs = self.fps > 0 ? 1000.0 / self.fps : 0;
        self.label.text = [NSString stringWithFormat:@"FPS %.1f\n%.2f ms", self.fps, frameMs];
        self.frames = 0;
        self.lastTimestamp = link.timestamp;
    }
}

@end

__attribute__((constructor))
static void FPSOverlayInit(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        static FPSOverlayController *controller;
        controller = [FPSOverlayController new];
        [controller start];
    });
}
