#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

@interface FPSOverlayV2Controller : NSObject
@property(nonatomic,strong) UIWindow *overlayWindow;
@property(nonatomic,strong) UILabel *label;
@property(nonatomic,strong) CADisplayLink *displayLink;
@property(nonatomic) CFTimeInterval lastTimestamp;
@property(nonatomic) NSUInteger frameCount;
@end

@implementation FPSOverlayV2Controller

- (void)start {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self createOverlayWindow];
        [self startDisplayLink];
    });
}

- (UIWindowScene *)activeWindowScene {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        if (scene.activationState == UISceneActivationStateForegroundActive ||
            scene.activationState == UISceneActivationStateForegroundInactive) {
            return (UIWindowScene *)scene;
        }
    }
    return nil;
}

- (void)createOverlayWindow {
    UIWindowScene *scene = [self activeWindowScene];

    if (!scene) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self createOverlayWindow];
        });
        return;
    }

    if (self.overlayWindow) return;

    self.overlayWindow = [[UIWindow alloc] initWithWindowScene:scene];
    self.overlayWindow.frame = scene.coordinateSpace.bounds;
    self.overlayWindow.backgroundColor = UIColor.clearColor;
    self.overlayWindow.windowLevel = UIWindowLevelAlert - 1.0;
    self.overlayWindow.userInteractionEnabled = NO;

    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = UIColor.clearColor;
    self.overlayWindow.rootViewController = vc;

    self.label = [[UILabel alloc] init];
    self.label.translatesAutoresizingMaskIntoConstraints = NO;
    self.label.text = @"FPS V2 --";
    self.label.numberOfLines = 2;
    self.label.textAlignment = NSTextAlignmentCenter;
    self.label.textColor = UIColor.whiteColor;
    self.label.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.72];
    self.label.font = [UIFont monospacedDigitSystemFontOfSize:13.0 weight:UIFontWeightBold];
    self.label.layer.cornerRadius = 7.0;
    self.label.layer.masksToBounds = YES;

    [vc.view addSubview:self.label];

    UILayoutGuide *safe = vc.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [self.label.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:8.0],
        [self.label.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8.0],
        [self.label.widthAnchor constraintEqualToConstant:115.0],
        [self.label.heightAnchor constraintEqualToConstant:44.0]
    ]];

    self.overlayWindow.hidden = NO;
}

- (void)startDisplayLink {
    if (self.displayLink) return;

    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(displayTick:)];

    if (@available(iOS 15.0, *)) {
        self.displayLink.preferredFrameRateRange = CAFrameRateRangeMake(1.0, 120.0, 0.0);
    }

    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)displayTick:(CADisplayLink *)link {
    if (!self.label) return;

    if (self.lastTimestamp == 0) {
        self.lastTimestamp = link.timestamp;
        return;
    }

    self.frameCount++;
    CFTimeInterval elapsed = link.timestamp - self.lastTimestamp;

    if (elapsed >= 0.5) {
        double fps = (double)self.frameCount / elapsed;
        double ms = fps > 0.0 ? 1000.0 / fps : 0.0;
        self.label.text = [NSString stringWithFormat:@"FPS %.1f\n%.2f ms", fps, ms];
        self.frameCount = 0;
        self.lastTimestamp = link.timestamp;
    }
}

@end

__attribute__((constructor))
static void FPSOverlayV2Init(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        static FPSOverlayV2Controller *controller = nil;
        if (!controller) {
            controller = [FPSOverlayV2Controller new];
            [controller start];
        }
    });
}
