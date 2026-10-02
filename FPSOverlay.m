#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <mach/mach.h>
#import <sys/sysctl.h>
#import <float.h>

#pragma mark - FPS Graph

@interface FPSGraphView : UIView

@property(nonatomic, strong) NSArray<NSNumber *> *values;

@end

@implementation FPSGraphView

- (void)drawRect:(CGRect)rect
{
    CGContextRef context = UIGraphicsGetCurrentContext();

    if (!context) {
        return;
    }

    /*
     * Reference lines
     */
    CGContextSetLineWidth(context, 1.0);
    CGContextSetStrokeColorWithColor(
        context,
        [UIColor colorWithWhite:1.0 alpha:0.18].CGColor
    );

    for (NSInteger i = 1; i <= 3; i++) {

        CGFloat y =
            rect.size.height -
            (rect.size.height * (CGFloat)i / 4.0);

        CGContextMoveToPoint(context, 0.0, y);
        CGContextAddLineToPoint(context, rect.size.width, y);
    }

    CGContextStrokePath(context);

    /*
     * Need at least two points for graph
     */
    if (self.values.count < 2) {
        return;
    }

    /*
     * FPS graph
     */
    CGContextSetStrokeColorWithColor(
        context,
        [UIColor colorWithWhite:1.0 alpha:0.95].CGColor
    );

    CGContextSetLineWidth(context, 1.4);

    CGFloat width = rect.size.width;
    CGFloat height = rect.size.height;

    /*
     * Graph scale.
     *
     * 120 FPS is the top of the graph.
     */
    CGFloat maximumFPS = 120.0;

    for (NSUInteger i = 0;
         i < self.values.count;
         i++) {

        NSNumber *number =
            [self.values objectAtIndex:i];

        double fps = [number doubleValue];

        fps = MAX(0.0, MIN(maximumFPS, fps));

        CGFloat x;

        if (self.values.count <= 1) {

            x = 0.0;

        } else {

            x =
                width *
                ((CGFloat)i /
                 (CGFloat)(self.values.count - 1));
        }

        CGFloat y =
            height -
            ((CGFloat)fps / maximumFPS) * height;

        if (i == 0) {

            CGContextMoveToPoint(
                context,
                x,
                y
            );

        } else {

            CGContextAddLineToPoint(
                context,
                x,
                y
            );
        }
    }

    CGContextStrokePath(context);
}

@end


#pragma mark - FPS Overlay Controller

@interface FPSOverlayController : NSObject

@property(nonatomic, strong) UILabel *leftLabel;
@property(nonatomic, strong) UILabel *rightLabel;
@property(nonatomic, strong) UILabel *deviceLabel;

@property(nonatomic, strong) FPSGraphView *graphView;

/*
 * IMPORTANT:
 *
 * Changed from weak to strong.
 *
 * Theos is compiling this tweak with manual reference
 * counting, where weak properties are not supported.
 */
@property(nonatomic, strong) UIWindow *hostWindow;

@property(nonatomic, strong) CADisplayLink *displayLink;
@property(nonatomic, strong) NSTimer *refreshTimer;

@property(nonatomic) CFTimeInterval lastTimestamp;
@property(nonatomic) NSInteger frameCount;

@property(nonatomic, strong) NSMutableArray<NSNumber *> *fpsSamples;
@property(nonatomic, strong) NSMutableArray<NSNumber *> *frameTimeSamples;

@property(nonatomic) double sumFPS;

@end


@implementation FPSOverlayController


#pragma mark Initialization

- (instancetype)init
{
    self = [super init];

    if (self) {

        _fpsSamples =
            [NSMutableArray array];

        _frameTimeSamples =
            [NSMutableArray array];

        _sumFPS = 0.0;

        _lastTimestamp = 0.0;

        _frameCount = 0;
    }

    return self;
}


#pragma mark - Find Game Window

- (UIWindow *)findGameWindow
{
    if (@available(iOS 13.0, *)) {

        NSSet<UIScene *> *scenes =
            UIApplication.sharedApplication.connectedScenes;

        for (UIScene *scene in scenes) {

            if (scene.activationState !=
                    UISceneActivationStateForegroundActive &&
                scene.activationState !=
                    UISceneActivationStateForegroundInactive) {

                continue;
            }

            if (![scene isKindOfClass:[UIWindowScene class]]) {
                continue;
            }

            UIWindowScene *windowScene =
                (UIWindowScene *)scene;


            /*
             * First try the key window.
             */
            for (UIWindow *window in windowScene.windows) {

                if (!window.hidden &&
                    window.alpha > 0.01 &&
                    window.windowLevel ==
                        UIWindowLevelNormal &&
                    window.isKeyWindow) {

                    return window;
                }
            }


            /*
             * Otherwise use the first visible normal window.
             */
            for (UIWindow *window in windowScene.windows) {

                if (!window.hidden &&
                    window.alpha > 0.01 &&
                    window.windowLevel ==
                        UIWindowLevelNormal) {

                    return window;
                }
            }
        }
    }

    return nil;
}


#pragma mark - Create Label

- (UILabel *)makeLabel
{
    UILabel *label =
        [[UILabel alloc] init];

    label.textColor =
        UIColor.whiteColor;

    label.backgroundColor =
        UIColor.clearColor;

    label.font =
        [UIFont monospacedDigitSystemFontOfSize:12.0
                                          weight:UIFontWeightBold];

    label.numberOfLines = 0;

    label.textAlignment =
        NSTextAlignmentLeft;

    label.userInteractionEnabled = NO;

    /*
     * ARMSX2-style readable shadow.
     */
    label.layer.shadowColor =
        UIColor.blackColor.CGColor;

    label.layer.shadowOffset =
        CGSizeMake(1.0, 1.0);

    label.layer.shadowOpacity = 1.0;

    label.layer.shadowRadius = 1.5;

    label.translatesAutoresizingMaskIntoConstraints = NO;

    return label;
}


#pragma mark - Attach Overlay

- (void)refreshWindow
{
    UIWindow *window =
        [self findGameWindow];

    if (!window) {
        return;
    }


    /*
     * Reattach when the game creates/replaces
     * its UIWindow.
     */
    if (self.hostWindow != window ||
        self.leftLabel.superview != window) {


        /*
         * Remove old UI.
         */
        [self.leftLabel removeFromSuperview];
        [self.rightLabel removeFromSuperview];
        [self.deviceLabel removeFromSuperview];
        [self.graphView removeFromSuperview];


        self.hostWindow = window;


        /*
         * Create labels.
         */
        self.leftLabel =
            [self makeLabel];

        self.rightLabel =
            [self makeLabel];

        self.deviceLabel =
            [self makeLabel];


        /*
         * Create graph.
         */
        self.graphView =
            [[FPSGraphView alloc] init];

        self.graphView.backgroundColor =
            UIColor.clearColor;

        self.graphView.userInteractionEnabled =
            NO;

        self.graphView.translatesAutoresizingMaskIntoConstraints =
            NO;


        /*
         * Add everything to the game window.
         */
        [window addSubview:self.leftLabel];

        [window addSubview:self.rightLabel];

        [window addSubview:self.deviceLabel];

        [window addSubview:self.graphView];


        UILayoutGuide *safe =
            window.safeAreaLayoutGuide;


        /*
         * LEFT COLUMN
         *
         * FPS
         * AVG
         * 1% LOW
         * 0.1% LOW
         */
        [NSLayoutConstraint activateConstraints:@[

            [self.leftLabel.trailingAnchor
                constraintEqualToAnchor:safe.trailingAnchor
                constant:-180.0],

            [self.leftLabel.topAnchor
                constraintEqualToAnchor:safe.topAnchor
                constant:6.0],

            [self.leftLabel.widthAnchor
                constraintEqualToConstant:175.0],

            [self.leftLabel.heightAnchor
                constraintEqualToConstant:82.0]
        ]];


        /*
         * RIGHT COLUMN
         *
         * Frame time
         * MIN
         * MAX
         * HZ
         * RAM
         */
        [NSLayoutConstraint activateConstraints:@[

            [self.rightLabel.trailingAnchor
                constraintEqualToAnchor:safe.trailingAnchor
                constant:-8.0],

            [self.rightLabel.topAnchor
                constraintEqualToAnchor:safe.topAnchor
                constant:6.0],

            [self.rightLabel.widthAnchor
                constraintEqualToConstant:170.0],

            [self.rightLabel.heightAnchor
                constraintEqualToConstant:105.0]
        ]];


        /*
         * DEVICE INFORMATION
         */
        [NSLayoutConstraint activateConstraints:@[

            [self.deviceLabel.trailingAnchor
                constraintEqualToAnchor:safe.trailingAnchor
                constant:-8.0],

            [self.deviceLabel.topAnchor
                constraintEqualToAnchor:
                    self.rightLabel.bottomAnchor
                constant:0.0],

            [self.deviceLabel.widthAnchor
                constraintEqualToConstant:340.0],

            [self.deviceLabel.heightAnchor
                constraintEqualToConstant:42.0]
        ]];


        /*
         * FPS GRAPH
         */
        [NSLayoutConstraint activateConstraints:@[

            [self.graphView.trailingAnchor
                constraintEqualToAnchor:safe.trailingAnchor
                constant:-8.0],

            [self.graphView.topAnchor
                constraintEqualToAnchor:
                    self.deviceLabel.bottomAnchor
                constant:2.0],

            [self.graphView.widthAnchor
                constraintEqualToConstant:245.0],

            [self.graphView.heightAnchor
                constraintEqualToConstant:70.0]
        ]];


        [self updateLabels];
    }


    /*
     * Create CADisplayLink only once.
     */
    if (!self.displayLink) {

        self.displayLink =
            [CADisplayLink displayLinkWithTarget:self
                                        selector:@selector(frameTick:)];

        [self.displayLink
            addToRunLoop:NSRunLoop.mainRunLoop
            forMode:NSRunLoopCommonModes];
    }
}


#pragma mark - Current FPS

- (double)currentFPS
{
    NSNumber *last =
        self.fpsSamples.lastObject;

    if (!last) {
        return 0.0;
    }

    return [last doubleValue];
}


#pragma mark - Average FPS

- (double)averageFPS
{
    if (self.fpsSamples.count == 0) {
        return 0.0;
    }

    return
        self.sumFPS /
        (double)self.fpsSamples.count;
}


#pragma mark - Percentile

- (double)percentileLow:(double)percent
{
    if (self.fpsSamples.count < 2) {
        return 0.0;
    }

    NSArray<NSNumber *> *sortedSamples =
        [self.fpsSamples
            sortedArrayUsingSelector:@selector(compare:)];

    NSUInteger index =
        (NSUInteger)floor(
            (double)(sortedSamples.count - 1) *
            percent
        );

    NSNumber *value =
        [sortedSamples objectAtIndex:index];

    return [value doubleValue];
}


#pragma mark - Rolling Minimum

- (double)rollingMin
{
    if (self.fpsSamples.count == 0) {
        return 0.0;
    }

    double minimum = DBL_MAX;

    for (NSNumber *number in self.fpsSamples) {

        double value =
            [number doubleValue];

        if (value < minimum) {
            minimum = value;
        }
    }

    return minimum;
}


#pragma mark - Rolling Maximum

- (double)rollingMax
{
    if (self.fpsSamples.count == 0) {
        return 0.0;
    }

    double maximum = 0.0;

    for (NSNumber *number in self.fpsSamples) {

        double value =
            [number doubleValue];

        if (value > maximum) {
            maximum = value;
        }
    }

    return maximum;
}


#pragma mark - RAM

- (double)memoryMB
{
    mach_task_basic_info_data_t info;

    mach_msg_type_number_t count =
        MACH_TASK_BASIC_INFO_COUNT;

    kern_return_t result =
        task_info(
            mach_task_self(),
            MACH_TASK_BASIC_INFO,
            (task_info_t)&info,
            &count
        );

    if (result != KERN_SUCCESS) {
        return 0.0;
    }

    return
        (double)info.resident_size /
        (1024.0 * 1024.0);
}


#pragma mark - Machine Identifier

- (NSString *)machineIdentifier
{
    size_t size = 0;

    sysctlbyname(
        "hw.machine",
        NULL,
        &size,
        NULL,
        0
    );

    if (size == 0) {
        return @"Unknown";
    }

    char *machine =
        calloc(1, size);

    if (!machine) {
        return @"Unknown";
    }

    sysctlbyname(
        "hw.machine",
        machine,
        &size,
        NULL,
        0
    );

    NSString *identifier =
        [NSString stringWithUTF8String:machine];

    free(machine);

    return identifier ?: @"Unknown";
}


#pragma mark - Device Name

- (NSString *)deviceName
{
    NSString *machine =
        [self machineIdentifier];


    NSDictionary *knownDevices = @{

        @"iPhone14,5" : @"iPhone 13",

        @"iPhone14,2" : @"iPhone 13 Pro",

        @"iPhone14,3" : @"iPhone 13 Pro Max",

        @"iPhone14,4" : @"iPhone 13 mini",

        @"iPhone15,4" : @"iPhone 15",

        @"iPhone15,5" : @"iPhone 15 Plus",

        @"iPhone15,2" : @"iPhone 14 Pro",

        @"iPhone15,3" : @"iPhone 14 Pro Max",

        @"iPhone17,1" : @"iPhone 16 Pro",

        @"iPhone17,2" : @"iPhone 16 Pro Max"
    };


    NSString *name =
        [knownDevices objectForKey:machine];

    if (name) {
        return name;
    }

    return machine;
}


#pragma mark - GPU

- (NSString *)gpuName
{
    /*
     * iOS does not provide a reliable public API
     * for per-game GPU utilization.
     *
     * We therefore show the GPU family only.
     */
    return @"Apple GPU";
}


#pragma mark - Frame Tick

- (void)frameTick:(CADisplayLink *)link
{
    if (self.lastTimestamp == 0.0) {

        self.lastTimestamp =
            link.timestamp;

        self.frameCount = 0;

        return;
    }


    self.frameCount++;


    CFTimeInterval elapsed =
        link.timestamp -
        self.lastTimestamp;


    /*
     * Update statistics every 0.5 second.
     */
    if (elapsed >= 0.5) {

        double fps =
            (double)self.frameCount /
            elapsed;


        double frameTime =
            fps > 0.0
                ? (1000.0 / fps)
                : 0.0;


        if (fps > 0.0 &&
            fps < 240.0) {


            /*
             * Keep approximately 2 minutes
             * of rolling samples.
             *
             * One sample every 0.5 sec:
             *
             * 240 samples = 120 seconds.
             */
            if (self.fpsSamples.count >= 240) {

                NSNumber *oldFPS =
                    [self.fpsSamples objectAtIndex:0];

                self.sumFPS -=
                    [oldFPS doubleValue];

                [self.fpsSamples
                    removeObjectAtIndex:0];


                [self.frameTimeSamples
                    removeObjectAtIndex:0];
            }


            [self.fpsSamples
                addObject:@(fps)];

            [self.frameTimeSamples
                addObject:@(frameTime)];


            self.sumFPS += fps;
        }


        self.frameCount = 0;

        self.lastTimestamp =
            link.timestamp;


        [self updateLabels];
    }
}


#pragma mark - Update Overlay Text

- (void)updateLabels
{
    if (!self.leftLabel ||
        !self.rightLabel) {

        return;
    }


    double fps =
        [self currentFPS];


    double average =
        [self averageFPS];


    double frameTime =
        fps > 0.0
            ? (1000.0 / fps)
            : 0.0;


    double minimum =
        [self rollingMin];


    double maximum =
        [self rollingMax];


    double onePercentLow =
        [self percentileLow:0.01];


    double zeroPointOnePercentLow =
        [self percentileLow:0.001];


    double ram =
        [self memoryMB];


    /*
     * Display refresh rate.
     */
    NSInteger hz = 60;

    if (self.hostWindow.screen) {

        hz =
            (NSInteger)
            self.hostWindow.screen.maximumFramesPerSecond;
    }


    /*
     * LEFT SIDE
     */
    self.leftLabel.text =
        [NSString stringWithFormat:

            @"FPS : %5.1f\n"
             @"AVG : %5.1f\n"
             @"1%% LOW : %5.1f\n"
             @"0.1%% LOW : %4.1f",

            fps,
            average,
            onePercentLow,
            zeroPointOnePercentLow
        ];


    /*
     * RIGHT SIDE
     */
    self.rightLabel.text =
        [NSString stringWithFormat:

            @"FT  : %6.2f ms\n"
             @"MIN : %6.1f\n"
             @"MAX : %6.1f\n"
             @"HZ  : %3ld\n"
             @"RAM : %4.0f MB",

            frameTime,
            minimum,
            maximum,
            (long)hz,
            ram
        ];


    /*
     * Battery.
     */
    float battery =
        UIDevice.currentDevice.batteryLevel;


    NSString *batteryText;


    if (battery >= 0.0) {

        batteryText =
            [NSString stringWithFormat:
                @"BAT : %3.0f%%",
                battery * 100.0];

    } else {

        batteryText =
            @"BAT : N/A";
    }


    /*
     * Device line.
     */
    self.deviceLabel.text =
        [NSString stringWithFormat:

            @"%@  |  GPU : %@  |  %@",

            [self deviceName],

            [self gpuName],

            batteryText
        ];


    /*
     * Graph.
     */
    self.graphView.values =
        self.fpsSamples;


    [self.graphView setNeedsDisplay];
}


#pragma mark - Start

- (void)start
{
    /*
     * Battery monitoring starts only after
     * the application is active.
     */
    UIDevice.currentDevice.batteryMonitoringEnabled =
        YES;


    /*
     * Delay UI creation.
     *
     * This is important for game compatibility.
     */
    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            2 * NSEC_PER_SEC
        ),
        dispatch_get_main_queue(),
        ^{

            [self refreshWindow];


            /*
             * Check for window replacement every 2 seconds.
             */
            if (!self.refreshTimer) {

                self.refreshTimer =
                    [NSTimer
                        scheduledTimerWithTimeInterval:2.0
                        target:self
                        selector:@selector(refreshWindow)
                        userInfo:nil
                        repeats:YES];
            }
        }
    );
}

@end


#pragma mark - Dylib Entry Point

static FPSOverlayController *gFPSOverlayController;


__attribute__((constructor))
static void FPSOverlayInit(void)
{
    /*
     * Do as little as possible during dylib loading.
     *
     * Do NOT touch game windows or game data here.
     */
    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            gFPSOverlayController =
                [[FPSOverlayController alloc] init];


            /*
             * Start when the game becomes active.
             */
            [[NSNotificationCenter defaultCenter]
                addObserverForName:
                    UIApplicationDidBecomeActiveNotification
                object:nil
                queue:
                    [NSOperationQueue mainQueue]
                usingBlock:
                    ^(NSNotification *notification) {

                        [gFPSOverlayController start];
                    }];


            /*
             * If the application is already active,
             * start immediately.
             */
            if (
                UIApplication.sharedApplication.applicationState ==
                UIApplicationStateActive
            ) {

                [gFPSOverlayController start];
            }
        }
    );
}
