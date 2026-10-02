#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <mach/mach.h>
#import <sys/sysctl.h>
#import <float.h>

#pragma mark - Graph

@interface FPSGraphView : UIView
@property(nonatomic, strong) NSArray<NSNumber *> *values;
@end

@implementation FPSGraphView

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    CGContextSetLineWidth(ctx, 1.0);
    CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithWhite:1.0 alpha:0.20].CGColor);

    // Horizontal reference lines: 30 / 60 / 90 FPS.
    for (NSInteger i = 1; i <= 3; i++) {
        CGFloat y = rect.size.height - (rect.size.height * i / 4.0);
        CGContextMoveToPoint(ctx, 0, y);
        CGContextAddLineToPoint(ctx, rect.size.width, y);
    }
    CGContextStrokePath(ctx);

    if (self.values.count < 2) return;

    CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithWhite:1.0 alpha:0.95].CGColor);
    CGContextSetLineWidth(ctx, 1.4);

    CGFloat width = rect.size.width;
    CGFloat height = rect.size.height;
    CGFloat maxFPS = 120.0;

    for (NSUInteger i = 0; i < self.values.count; i++) {
        double fps = [self.values[i] doubleValue];
        fps = MAX(0.0, MIN(maxFPS, fps));

        CGFloat x = (self.values.count <= 1)
            ? 0.0
            : width * ((CGFloat)i / (CGFloat)(self.values.count - 1));

        CGFloat y = height - (CGFloat)(fps / maxFPS) * height;

        if (i == 0) CGContextMoveToPoint(ctx, x, y);
        else CGContextAddLineToPoint(ctx, x, y);
    }

    CGContextStrokePath(ctx);
}
@end

#pragma mark - Overlay

@interface FPSOverlayController : NSObject
@property(nonatomic, strong) UILabel *leftLabel;
@property(nonatomic, strong) UILabel *rightLabel;
@property(nonatomic, strong) UILabel *deviceLabel;
@property(nonatomic, strong) FPSGraphView *graphView;
@property(nonatomic, weak) UIWindow *hostWindow;

@property(nonatomic, strong) CADisplayLink *displayLink;
@property(nonatomic, strong) NSTimer *refreshTimer;

@property(nonatomic) CFTimeInterval lastTimestamp;
@property(nonatomic) NSInteger frameCount;

@property(nonatomic, strong) NSMutableArray<NSNumber *> *fpsSamples;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *frameTimeSamples;

@property(nonatomic) double minFPS;
@property(nonatomic) double maxFPS;
@property(nonatomic) double sumFPS;
@end

@implementation FPSOverlayController

- (instancetype)init {
    self = [super init];
    if (self) {
        _fpsSamples = [NSMutableArray array];
        _frameTimeSamples = [NSMutableArray array];
        _minFPS = DBL_MAX;
        _maxFPS = 0.0;
    }
    return self;
}

#pragma mark Window

- (UIWindow *)findGameWindow {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState != UISceneActivationStateForegroundActive &&
                scene.activationState != UISceneActivationStateForegroundInactive) {
                continue;
            }

            if (![scene isKindOfClass:[UIWindowScene class]]) continue;

            UIWindowScene *windowScene = (UIWindowScene *)scene;

            for (UIWindow *window in windowScene.windows) {
                if (!window.hidden &&
                    window.alpha > 0.01 &&
                    window.windowLevel == UIWindowLevelNormal &&
                    window.isKeyWindow) {
                    return window;
                }
            }

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

#pragma mark UI

- (UILabel *)makeLabel {
    UILabel *label = [[UILabel alloc] init];
    label.textColor = UIColor.whiteColor;
    label.backgroundColor = UIColor.clearColor;
    label.font = [UIFont monospacedDigitSystemFontOfSize:12.0
                                                   weight:UIFontWeightBold];
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentLeft;
    label.userInteractionEnabled = NO;
    label.layer.shadowColor = UIColor.blackColor.CGColor;
    label.layer.shadowOffset = CGSizeMake(1.0, 1.0);
    label.layer.shadowOpacity = 1.0;
    label.layer.shadowRadius = 1.5;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

- (void)refreshWindow {
    UIWindow *window = [self findGameWindow];
    if (!window) return;

    if (self.hostWindow != window ||
        self.leftLabel.superview != window) {

        [self.leftLabel removeFromSuperview];
        [self.rightLabel removeFromSuperview];
        [self.deviceLabel removeFromSuperview];
        [self.graphView removeFromSuperview];

        self.hostWindow = window;

        self.leftLabel = [self makeLabel];
        self.rightLabel = [self makeLabel];
        self.deviceLabel = [self makeLabel];

        self.graphView = [[FPSGraphView alloc] init];
        self.graphView.backgroundColor = UIColor.clearColor;
        self.graphView.userInteractionEnabled = NO;
        self.graphView.translatesAutoresizingMaskIntoConstraints = NO;

        [window addSubview:self.leftLabel];
        [window addSubview:self.rightLabel];
        [window addSubview:self.deviceLabel];
        [window addSubview:self.graphView];

        UILayoutGuide *safe = window.safeAreaLayoutGuide;

        [NSLayoutConstraint activateConstraints:@[
            // Two compact columns at the upper-right, inspired by emulator HUD layouts.
            [self.leftLabel.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-180.0],
            [self.leftLabel.topAnchor constraintEqualToAnchor:safe.topAnchor constant:6.0],
            [self.leftLabel.widthAnchor constraintEqualToConstant:175.0],
            [self.leftLabel.heightAnchor constraintEqualToConstant:82.0],

            [self.rightLabel.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-8.0],
            [self.rightLabel.topAnchor constraintEqualToAnchor:safe.topAnchor constant:6.0],
            [self.rightLabel.widthAnchor constraintEqualToConstant:170.0],
            [self.rightLabel.heightAnchor constraintEqualToConstant:105.0],

            [self.deviceLabel.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-8.0],
            [self.deviceLabel.topAnchor constraintEqualToAnchor:self.rightLabel.bottomAnchor constant:0.0],
            [self.deviceLabel.widthAnchor constraintEqualToConstant:340.0],
            [self.deviceLabel.heightAnchor constraintEqualToConstant:42.0],

            [self.graphView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-8.0],
            [self.graphView.topAnchor constraintEqualToAnchor:self.deviceLabel.bottomAnchor constant:2.0],
            [self.graphView.widthAnchor constraintEqualToConstant:245.0],
            [self.graphView.heightAnchor constraintEqualToConstant:70.0]
        ]];

        [self updateLabels];
    }

    if (!self.displayLink) {
        self.displayLink =
            [CADisplayLink displayLinkWithTarget:self
                                        selector:@selector(frameTick:)];

        [self.displayLink addToRunLoop:NSRunLoop.mainRunLoop
                               forMode:NSRunLoopCommonModes];
    }
}

#pragma mark Measurements

- (double)currentFPS {
    NSNumber *last = self.fpsSamples.lastObject;
    return last ? [last doubleValue] : 0.0;
}

- (double)averageFPS {
    if (self.fpsSamples.count == 0) return 0.0;
    return self.sumFPS / (double)self.fpsSamples.count;
}

- (double)percentileLow:(double)p {
    if (self.fpsSamples.count < 2) return 0.0;

    NSArray<NSNumber *> *sorted =
        [self.fpsSamples sortedArrayUsingSelector:@selector(compare:)];

    NSUInteger index =
        (NSUInteger)floor((double)(sorted.count - 1) * p);

    NSNumber *value = [sorted objectAtIndex:index];
    return [value doubleValue];
}

- (double)rollingMin {
    if (self.fpsSamples.count == 0) return 0.0;
    double value = DBL_MAX;
    for (NSNumber *n in self.fpsSamples) value = MIN(value, [n doubleValue]);
    return value;
}

- (double)rollingMax {
    if (self.fpsSamples.count == 0) return 0.0;
    double value = 0.0;
    for (NSNumber *n in self.fpsSamples) value = MAX(value, [n doubleValue]);
    return value;
}

- (double)memoryMB {
    mach_task_basic_info_data_t info;
    mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;

    kern_return_t result =
        task_info(mach_task_self(),
                  MACH_TASK_BASIC_INFO,
                  (task_info_t)&info,
                  &count);

    if (result != KERN_SUCCESS) return 0.0;

    return (double)info.resident_size / (1024.0 * 1024.0);
}

- (NSString *)machineIdentifier {
    size_t size = 0;
    sysctlbyname("hw.machine", NULL, &size, NULL, 0);
    if (size == 0) return @"Unknown";

    char *machine = calloc(1, size);
    if (!machine) return @"Unknown";

    sysctlbyname("hw.machine", machine, &size, NULL, 0);
    NSString *identifier = [NSString stringWithUTF8String:machine];
    free(machine);

    return identifier ?: @"Unknown";
}

- (NSString *)deviceName {
    NSString *machine = [self machineIdentifier];

    NSDictionary *known = @{
        @"iPhone14,5": @"iPhone 13",
        @"iPhone14,2": @"iPhone 13 Pro",
        @"iPhone14,3": @"iPhone 13 Pro Max",
        @"iPhone14,4": @"iPhone 13 mini",
        @"iPhone15,4": @"iPhone 15",
        @"iPhone15,5": @"iPhone 15 Plus",
        @"iPhone15,2": @"iPhone 14 Pro",
        @"iPhone15,3": @"iPhone 14 Pro Max",
        @"iPhone17,1": @"iPhone 16 Pro",
        @"iPhone17,2": @"iPhone 16 Pro Max"
    };

    NSString *name = known[machine];
    return name ?: machine;
}

- (NSString *)gpuName {
    // iOS does not expose a reliable public per-game GPU utilization API.
    // We therefore report the platform GPU family rather than inventing utilization.
    NSString *machine = [self machineIdentifier];

    if ([machine hasPrefix:@"iPhone14,"]) return @"Apple GPU";
    if ([machine hasPrefix:@"iPhone15,"]) return @"Apple GPU";
    if ([machine hasPrefix:@"iPhone16,"]) return @"Apple GPU";
    if ([machine hasPrefix:@"iPhone17,"]) return @"Apple GPU";

    return @"Apple GPU";
}

#pragma mark Frame loop

- (void)frameTick:(CADisplayLink *)link {
    if (self.lastTimestamp == 0) {
        self.lastTimestamp = link.timestamp;
        self.frameCount = 0;
        return;
    }

    self.frameCount++;

    CFTimeInterval elapsed = link.timestamp - self.lastTimestamp;

    if (elapsed >= 0.5) {
        double fps = (double)self.frameCount / elapsed;
        double frameTime = fps > 0.0 ? 1000.0 / fps : 0.0;

        if (fps > 0.0 && fps < 240.0) {
            // Keep a 2-minute rolling history: one sample every 0.5 sec.
            if (self.fpsSamples.count >= 240) {
                NSNumber *old = self.fpsSamples.firstObject;
                self.sumFPS -= [old doubleValue];
                [self.fpsSamples removeObjectAtIndex:0];
                [self.frameTimeSamples removeObjectAtIndex:0];
            }

            [self.fpsSamples addObject:@(fps)];
            [self.frameTimeSamples addObject:@(frameTime)];
            self.sumFPS += fps;

            self.minFPS = MIN(self.minFPS, fps);
            self.maxFPS = MAX(self.maxFPS, fps);
        }

        self.frameCount = 0;
        self.lastTimestamp = link.timestamp;

        [self updateLabels];
    }
}

#pragma mark Text

- (void)updateLabels {
    if (!self.leftLabel || !self.rightLabel) return;

    double fps = [self currentFPS];
    double avg = [self averageFPS];
    double ft = fps > 0.0 ? 1000.0 / fps : 0.0;
    double min = [self rollingMin];
    double max = [self rollingMax];
    double low1 = [self percentileLow:0.01];
    double low01 = [self percentileLow:0.001];
    double ram = [self memoryMB];

    NSInteger hz = 60;
    if (self.hostWindow.screen) {
        hz = (NSInteger)self.hostWindow.screen.maximumFramesPerSecond;
    }

    self.leftLabel.text = [NSString stringWithFormat:
        @"FPS : %5.1f\n"
         @"AVG : %5.1f\n"
         @"1%% LOW : %5.1f\n"
         @"0.1%% LOW : %4.1f",
        fps, avg, low1, low01];

    self.rightLabel.text = [NSString stringWithFormat:
        @"FT  : %6.2f ms\n"
         @"MIN : %6.1f\n"
         @"MAX : %6.1f\n"
         @"HZ  : %3ld\n"
         @"RAM : %4.0f MB",
        ft, min, max, (long)hz, ram];

    float battery = UIDevice.currentDevice.batteryLevel;
    NSString *batteryText =
        battery >= 0.0
        ? [NSString stringWithFormat:@"BAT : %3.0f%%", battery * 100.0]
        : @"BAT : N/A";

    self.deviceLabel.text = [NSString stringWithFormat:
        @"%@  |  GPU : %@  |  %@",
        [self deviceName],
        [self gpuName],
        batteryText];

    self.graphView.values = self.fpsSamples;
    [self.graphView setNeedsDisplay];
}

#pragma mark Start

- (void)start {
    UIDevice.currentDevice.batteryMonitoringEnabled = YES;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        [self refreshWindow];

        self.refreshTimer =
            [NSTimer scheduledTimerWithTimeInterval:2.0
                                             target:self
                                           selector:@selector(refreshWindow)
                                           userInfo:nil
                                            repeats:YES];
    });
}

@end

static FPSOverlayController *gFPSOverlayController;

__attribute__((constructor))
static void FPSOverlayInit(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        gFPSOverlayController = [FPSOverlayController new];

        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
                        [gFPSOverlayController start];
                    }];

        // Do not touch game windows or game data during dylib loading.
        // Wait for the app to become active first.
        if (UIApplication.sharedApplication.applicationState ==
            UIApplicationStateActive) {
            [gFPSOverlayController start];
        }
    });
}
