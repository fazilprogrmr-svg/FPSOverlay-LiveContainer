#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <mach/mach.h>
#import <sys/sysctl.h>
#import <float.h>
#import <string.h>

#define FPS_HISTORY_SIZE 240

#pragma mark - Graph View

@interface FPSGraphView : UIView
{
    double _values[FPS_HISTORY_SIZE];
    NSInteger _count;
}

- (void)setFPSValues:(const double *)values count:(NSInteger)count;

@end

@implementation FPSGraphView

- (void)setFPSValues:(const double *)values count:(NSInteger)count
{
    if (count < 0) {
        count = 0;
    }

    if (count > FPS_HISTORY_SIZE) {
        count = FPS_HISTORY_SIZE;
    }

    _count = count;

    if (count > 0 && values != NULL) {
        memcpy(_values, values, sizeof(double) * count);
    }

    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect
{
    CGContextRef context = UIGraphicsGetCurrentContext();

    if (!context) {
        return;
    }

    CGContextSetLineWidth(context, 1.0);
    CGContextSetStrokeColorWithColor(
        context,
        [UIColor colorWithWhite:1.0 alpha:0.16].CGColor
    );

    NSInteger i;

    for (i = 1; i <= 3; i++) {
        CGFloat y =
            rect.size.height -
            (rect.size.height * (CGFloat)i / 4.0);

        CGContextMoveToPoint(context, 0.0, y);
        CGContextAddLineToPoint(context, rect.size.width, y);
    }

    CGContextStrokePath(context);

    if (_count < 2) {
        return;
    }

    CGContextSetStrokeColorWithColor(
        context,
        [UIColor colorWithWhite:1.0 alpha:0.95].CGColor
    );

    CGContextSetLineWidth(context, 1.4);

    CGFloat width = rect.size.width;
    CGFloat height = rect.size.height;
    CGFloat maximumFPS = 120.0;

    for (i = 0; i < _count; i++) {
        double fps = _values[i];

        if (fps < 0.0) {
            fps = 0.0;
        }

        if (fps > maximumFPS) {
            fps = maximumFPS;
        }

        CGFloat x =
            width * ((CGFloat)i / (CGFloat)(_count - 1));

        CGFloat y =
            height -
            ((CGFloat)fps / maximumFPS) * height;

        if (i == 0) {
            CGContextMoveToPoint(context, x, y);
        } else {
            CGContextAddLineToPoint(context, x, y);
        }
    }

    CGContextStrokePath(context);
}

@end

#pragma mark - Overlay Controller

@interface FPSOverlayController : NSObject
{
    UILabel *_leftLabel;
    UILabel *_rightLabel;
    UILabel *_deviceLabel;

    FPSGraphView *_graphView;

    UIWindow *_hostWindow;

    CADisplayLink *_displayLink;
    NSTimer *_refreshTimer;

    CFTimeInterval _lastTimestamp;
    NSInteger _frameCount;

    double _fpsHistory[FPS_HISTORY_SIZE];
    double _frameTimeHistory[FPS_HISTORY_SIZE];

    NSInteger _historyCount;
    double _sumFPS;
}

- (void)start;
- (void)refreshWindow;

@end

@implementation FPSOverlayController

#pragma mark Initialization

- (id)init
{
    self = [super init];

    if (self) {
        memset(_fpsHistory, 0, sizeof(_fpsHistory));
        memset(_frameTimeHistory, 0, sizeof(_frameTimeHistory));

        _historyCount = 0;
        _sumFPS = 0.0;
        _lastTimestamp = 0.0;
        _frameCount = 0;
    }

    return self;
}

#pragma mark Window

- (UIWindow *)findGameWindow
{
    if (@available(iOS 13.0, *)) {
        NSSet *scenes =
            [UIApplication.sharedApplication connectedScenes];

        for (UIScene *scene in scenes) {
            if ([scene activationState] !=
                    UISceneActivationStateForegroundActive &&
                [scene activationState] !=
                    UISceneActivationStateForegroundInactive) {
                continue;
            }

            if (![scene isKindOfClass:[UIWindowScene class]]) {
                continue;
            }

            UIWindowScene *windowScene =
                (UIWindowScene *)scene;

            NSArray *windows =
                [windowScene windows];

            for (UIWindow *window in windows) {
                if (![window isHidden] &&
                    [window alpha] > 0.01 &&
                    [window windowLevel] == UIWindowLevelNormal &&
                    [window isKeyWindow]) {
                    return window;
                }
            }

            for (UIWindow *window in windows) {
                if (![window isHidden] &&
                    [window alpha] > 0.01 &&
                    [window windowLevel] == UIWindowLevelNormal) {
                    return window;
                }
            }
        }
    }

    return nil;
}

#pragma mark UI

- (UILabel *)createLabel
{
    UILabel *label = [[UILabel alloc] init];

    [label setTextColor:[UIColor whiteColor]];
    [label setBackgroundColor:[UIColor clearColor]];

    [label setFont:
        [UIFont monospacedDigitSystemFontOfSize:12.0
                                          weight:UIFontWeightBold]];

    [label setNumberOfLines:0];
    [label setTextAlignment:NSTextAlignmentLeft];
    [label setUserInteractionEnabled:NO];

    [[label layer] setShadowColor:
        [UIColor blackColor].CGColor];

    [[label layer] setShadowOffset:
        CGSizeMake(1.0, 1.0)];

    [[label layer] setShadowOpacity:1.0];
    [[label layer] setShadowRadius:1.5];

    [label setTranslatesAutoresizingMaskIntoConstraints:NO];

    return label;
}

- (void)refreshWindow
{
    UIWindow *window = [self findGameWindow];

    if (!window) {
        return;
    }

    if (_hostWindow != window ||
        [_leftLabel superview] != window) {

        [_leftLabel removeFromSuperview];
        [_rightLabel removeFromSuperview];
        [_deviceLabel removeFromSuperview];
        [_graphView removeFromSuperview];

        _hostWindow = window;

        _leftLabel = [self createLabel];
        _rightLabel = [self createLabel];
        _deviceLabel = [self createLabel];

        _graphView = [[FPSGraphView alloc] init];

        [_graphView setBackgroundColor:[UIColor clearColor]];
        [_graphView setUserInteractionEnabled:NO];
        [_graphView setTranslatesAutoresizingMaskIntoConstraints:NO];

        [window addSubview:_leftLabel];
        [window addSubview:_rightLabel];
        [window addSubview:_deviceLabel];
        [window addSubview:_graphView];

        UILayoutGuide *safe =
            [window safeAreaLayoutGuide];

        [NSLayoutConstraint activateConstraints:@[
            [_leftLabel.trailingAnchor
                constraintEqualToAnchor:safe.trailingAnchor
                constant:-180.0],

            [_leftLabel.topAnchor
                constraintEqualToAnchor:safe.topAnchor
                constant:6.0],

            [_leftLabel.widthAnchor
                constraintEqualToConstant:175.0],

            [_leftLabel.heightAnchor
                constraintEqualToConstant:82.0]
        ]];

        [NSLayoutConstraint activateConstraints:@[
            [_rightLabel.trailingAnchor
                constraintEqualToAnchor:safe.trailingAnchor
                constant:-8.0],

            [_rightLabel.topAnchor
                constraintEqualToAnchor:safe.topAnchor
                constant:6.0],

            [_rightLabel.widthAnchor
                constraintEqualToConstant:170.0],

            [_rightLabel.heightAnchor
                constraintEqualToConstant:105.0]
        ]];

        [NSLayoutConstraint activateConstraints:@[
            [_deviceLabel.trailingAnchor
                constraintEqualToAnchor:safe.trailingAnchor
                constant:-8.0],

            [_deviceLabel.topAnchor
                constraintEqualToAnchor:_rightLabel.bottomAnchor
                constant:0.0],

            [_deviceLabel.widthAnchor
                constraintEqualToConstant:340.0],

            [_deviceLabel.heightAnchor
                constraintEqualToConstant:42.0]
        ]];

        [NSLayoutConstraint activateConstraints:@[
            [_graphView.trailingAnchor
                constraintEqualToAnchor:safe.trailingAnchor
                constant:-8.0],

            [_graphView.topAnchor
                constraintEqualToAnchor:_deviceLabel.bottomAnchor
                constant:2.0],

            [_graphView.widthAnchor
                constraintEqualToConstant:245.0],

            [_graphView.heightAnchor
                constraintEqualToConstant:70.0]
        ]];
    }

    if (!_displayLink) {
        _displayLink =
            [CADisplayLink displayLinkWithTarget:self
                                        selector:@selector(frameTick:)];

        [_displayLink addToRunLoop:[NSRunLoop mainRunLoop]
                           forMode:NSRunLoopCommonModes];
    }

    [self updateLabels];
}

#pragma mark Statistics

- (double)currentFPS
{
    if (_historyCount <= 0) {
        return 0.0;
    }

    return _fpsHistory[_historyCount - 1];
}

- (double)averageFPS
{
    if (_historyCount <= 0) {
        return 0.0;
    }

    return _sumFPS / (double)_historyCount;
}

- (double)minimumFPS
{
    if (_historyCount <= 0) {
        return 0.0;
    }

    double minimum = DBL_MAX;

    NSInteger i;

    for (i = 0; i < _historyCount; i++) {
        if (_fpsHistory[i] < minimum) {
            minimum = _fpsHistory[i];
        }
    }

    return minimum;
}

- (double)maximumFPS
{
    if (_historyCount <= 0) {
        return 0.0;
    }

    double maximum = 0.0;

    NSInteger i;

    for (i = 0; i < _historyCount; i++) {
        if (_fpsHistory[i] > maximum) {
            maximum = _fpsHistory[i];
        }
    }

    return maximum;
}

- (double)percentile:(double)percent
{
    if (_historyCount < 2) {
        return 0.0;
    }

    double sorted[FPS_HISTORY_SIZE];

    NSInteger i;

    for (i = 0; i < _historyCount; i++) {
        sorted[i] = _fpsHistory[i];
    }

    for (i = 1; i < _historyCount; i++) {
        double key = sorted[i];
        NSInteger j = i - 1;

        while (j >= 0 && sorted[j] > key) {
            sorted[j + 1] = sorted[j];
            j--;
        }

        sorted[j + 1] = key;
    }

    NSInteger index =
        (NSInteger)floor(
            (double)(_historyCount - 1) * percent
        );

    if (index < 0) {
        index = 0;
    }

    if (index >= _historyCount) {
        index = _historyCount - 1;
    }

    return sorted[index];
}

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

#pragma mark Device

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

    char *machine = calloc(1, size);

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

    return identifier ? identifier : @"Unknown";
}

- (NSString *)deviceName
{
    NSString *machine =
        [self machineIdentifier];

    NSDictionary *devices = @{
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
        [devices objectForKey:machine];

    return name ? name : machine;
}

- (NSString *)gpuName
{
    return @"Apple GPU";
}

#pragma mark Frame Measurement

- (void)frameTick:(CADisplayLink *)link
{
    if (_lastTimestamp == 0.0) {
        _lastTimestamp = link.timestamp;
        _frameCount = 0;
        return;
    }

    _frameCount++;

    CFTimeInterval elapsed =
        link.timestamp - _lastTimestamp;

    if (elapsed >= 0.5) {

        double fps =
            (double)_frameCount / elapsed;

        if (fps > 0.0 && fps < 240.0) {

            if (_historyCount >= FPS_HISTORY_SIZE) {

                _sumFPS -= _fpsHistory[0];

                NSInteger i;

                for (i = 1;
                     i < FPS_HISTORY_SIZE;
                     i++) {

                    _fpsHistory[i - 1] =
                        _fpsHistory[i];

                    _frameTimeHistory[i - 1] =
                        _frameTimeHistory[i];
                }

                _historyCount =
                    FPS_HISTORY_SIZE - 1;
            }

            double frameTime =
                1000.0 / fps;

            _fpsHistory[_historyCount] =
                fps;

            _frameTimeHistory[_historyCount] =
                frameTime;

            _historyCount++;

            _sumFPS += fps;
        }

        _frameCount = 0;
        _lastTimestamp = link.timestamp;

        [self updateLabels];
    }
}

#pragma mark Update UI

- (void)updateLabels
{
    if (!_leftLabel ||
        !_rightLabel ||
        !_deviceLabel) {
        return;
    }

    double fps =
        [self currentFPS];

    double average =
        [self averageFPS];

    double frameTime =
        fps > 0.0
            ? 1000.0 / fps
            : 0.0;

    double minimum =
        [self minimumFPS];

    double maximum =
        [self maximumFPS];

    double onePercentLow =
        [self percentile:0.01];

    double zeroPointOnePercentLow =
        [self percentile:0.001];

    double ram =
        [self memoryMB];

    NSInteger hz = 60;

    if (_hostWindow &&
        [_hostWindow screen]) {

        hz =
            (NSInteger)
            [[_hostWindow screen]
                maximumFramesPerSecond];
    }

    [_leftLabel setText:
        [NSString stringWithFormat:
            @"FPS : %5.1f\n"
             @"AVG : %5.1f\n"
             @"1%% LOW : %5.1f\n"
             @"0.1%% LOW : %4.1f",
            fps,
            average,
            onePercentLow,
            zeroPointOnePercentLow
        ]];

    [_rightLabel setText:
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
        ]];

    UIDevice *device =
        [UIDevice currentDevice];

    float battery =
        [device batteryLevel];

    NSString *batteryText;

    if (battery >= 0.0) {
        batteryText =
            [NSString stringWithFormat:
                @"BAT : %3.0f%%",
                battery * 100.0];
    } else {
        batteryText = @"BAT : N/A";
    }

    [_deviceLabel setText:
        [NSString stringWithFormat:
            @"%@ | GPU : %@ | %@",
            [self deviceName],
            [self gpuName],
            batteryText
        ]];

    [_graphView
        setFPSValues:_fpsHistory
        count:_historyCount];
}

#pragma mark Start

- (void)start
{
    [[UIDevice currentDevice]
        setBatteryMonitoringEnabled:YES];

    dispatch_after(
        dispatch_time(
            DISPATCH_TIME_NOW,
            2 * NSEC_PER_SEC
        ),
        dispatch_get_main_queue(),
        ^{

            [self refreshWindow];

            if (!_refreshTimer) {
                _refreshTimer =
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

#pragma mark - Entry Point

static FPSOverlayController *gFPSOverlayController = nil;

__attribute__((constructor))
static void FPSOverlayInit(void)
{
    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            gFPSOverlayController =
                [[FPSOverlayController alloc] init];

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

            if ([[UIApplication sharedApplication]
                    applicationState] ==
                UIApplicationStateActive) {

                [gFPSOverlayController start];
            }
        }
    );
}
