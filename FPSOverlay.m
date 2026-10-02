#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <mach/mach.h>
#import <sys/sysctl.h>
#import <float.h>
#import <string.h>

#define FPS_HISTORY_SIZE 240

@interface FPSOverlayController : NSObject
{
    UILabel *_label;
    UILabel *_deviceLabel;

    UIWindow *_hostWindow;

    CADisplayLink *_displayLink;
    NSTimer *_refreshTimer;
    NSTimer *_batteryTimer;

    CFTimeInterval _lastTimestamp;
    NSInteger _frameCount;

    double _fpsHistory[FPS_HISTORY_SIZE];
    NSInteger _historyCount;

    double _sumFPS;
    NSInteger _sampleCount;
    double _minFPS;
    double _maxFPS;

    BOOL _started;
}
- (void)start;
- (void)refreshWindow;
@end

@implementation FPSOverlayController

- (id)init
{
    self = [super init];

    if (self) {
        _lastTimestamp = 0.0;
        _frameCount = 0;
        _historyCount = 0;
        _sumFPS = 0.0;
        _sampleCount = 0;
        _minFPS = DBL_MAX;
        _maxFPS = 0.0;
        _started = NO;

        /*
         * Battery monitoring is enabled immediately.
         * The separate timer below re-reads the battery level
         * periodically instead of relying only on Apple's
         * battery-change notification.
         */
        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    }

    return self;
}

- (void)dealloc
{
    [_refreshTimer invalidate];
    [_batteryTimer invalidate];
    [_displayLink invalidate];

    [[NSNotificationCenter defaultCenter] removeObserver:self];

    [super dealloc];
}

#pragma mark - Device

- (NSString *)deviceModel
{
    size_t size = 0;

    sysctlbyname("hw.machine", NULL, &size, NULL, 0);

    if (size == 0) {
        return @"iPhone";
    }

    char *machine = malloc(size);

    if (!machine) {
        return @"iPhone";
    }

    sysctlbyname("hw.machine", machine, &size, NULL, 0);

    NSString *identifier =
        [NSString stringWithUTF8String:machine];

    free(machine);

    if (!identifier) {
        return @"iPhone";
    }

    NSDictionary *models = @{
        @"iPhone12,1": @"iPhone 11",
        @"iPhone12,3": @"iPhone 11 Pro",
        @"iPhone12,5": @"iPhone 11 Pro Max",

        @"iPhone13,1": @"iPhone 12 mini",
        @"iPhone13,2": @"iPhone 12",
        @"iPhone13,3": @"iPhone 12 Pro",
        @"iPhone13,4": @"iPhone 12 Pro Max",

        @"iPhone14,4": @"iPhone 13 mini",
        @"iPhone14,5": @"iPhone 13",
        @"iPhone14,2": @"iPhone 13 Pro",
        @"iPhone14,3": @"iPhone 13 Pro Max",

        @"iPhone14,7": @"iPhone 14",
        @"iPhone14,8": @"iPhone 14 Plus",
        @"iPhone15,2": @"iPhone 14 Pro",
        @"iPhone15,3": @"iPhone 14 Pro Max",

        @"iPhone15,4": @"iPhone 15",
        @"iPhone15,5": @"iPhone 15 Plus",
        @"iPhone16,1": @"iPhone 15 Pro",
        @"iPhone16,2": @"iPhone 15 Pro Max",

        @"iPhone17,1": @"iPhone 16 Pro",
        @"iPhone17,2": @"iPhone 16 Pro Max",
        @"iPhone17,3": @"iPhone 16",
        @"iPhone17,4": @"iPhone 16 Plus",

        @"iPhone18,1": @"iPhone 17 Pro",
        @"iPhone18,2": @"iPhone 17 Pro Max",
        @"iPhone18,3": @"iPhone 17",
        @"iPhone18,4": @"iPhone Air"
    };

    NSString *name = [models objectForKey:identifier];

    if (name) {
        return name;
    }

    return identifier;
}

- (NSString *)gpuName
{
    /*
     * No Metal dependency here.
     * Keep GPU detection lightweight for compatibility.
     */
    NSString *model = [self deviceModel];

    if ([model isEqualToString:@"iPhone 11"] ||
        [model isEqualToString:@"iPhone 11 Pro"] ||
        [model isEqualToString:@"iPhone 11 Pro Max"]) {
        return @"Apple A13 GPU";
    }

    if ([model hasPrefix:@"iPhone 12"]) {
        return @"Apple A14 GPU";
    }

    if ([model isEqualToString:@"iPhone 13"] ||
        [model isEqualToString:@"iPhone 13 mini"] ||
        [model isEqualToString:@"iPhone 13 Pro"] ||
        [model isEqualToString:@"iPhone 13 Pro Max"]) {
        return @"Apple A15 GPU";
    }

    if ([model hasPrefix:@"iPhone 14"]) {
        if ([model isEqualToString:@"iPhone 14 Pro"] ||
            [model isEqualToString:@"iPhone 14 Pro Max"]) {
            return @"Apple A16 GPU";
        }

        return @"Apple A15 GPU";
    }

    if ([model hasPrefix:@"iPhone 15"]) {
        if ([model isEqualToString:@"iPhone 15 Pro"] ||
            [model isEqualToString:@"iPhone 15 Pro Max"]) {
            return @"Apple A17 Pro GPU";
        }

        return @"Apple A16 GPU";
    }

    if ([model hasPrefix:@"iPhone 16"]) {
        return @"Apple A18 GPU";
    }

    if ([model hasPrefix:@"iPhone 17"]) {
        return @"Apple GPU";
    }

    if ([model isEqualToString:@"iPhone Air"]) {
        return @"Apple GPU";
    }

    return @"Apple GPU";
}

#pragma mark - Battery

- (double)batteryPercentage
{
    /*
     * IMPORTANT:
     * Read the value every time this method is called.
     * We don't cache it.
     */
    UIDevice *device = [UIDevice currentDevice];

    if (!device.batteryMonitoringEnabled) {
        device.batteryMonitoringEnabled = YES;
    }

    float level = device.batteryLevel;

    if (level < 0.0f) {
        return -1.0;
    }

    return (double)level * 100.0;
}

- (NSString *)batteryText
{
    double level = [self batteryPercentage];

    if (level < 0.0) {
        return @"BAT --";
    }

    UIDeviceBatteryState state =
        [UIDevice currentDevice].batteryState;

    if (state == UIDeviceBatteryStateCharging ||
        state == UIDeviceBatteryStateFull) {

        return [NSString stringWithFormat:
                    @"BAT %3.0f%% ⚡", level];
    }

    return [NSString stringWithFormat:
                @"BAT %3.0f%%", level];
}

- (void)batteryTimerTick
{
    /*
     * Re-enable monitoring and read the actual current
     * battery value every 5 seconds.
     */
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;

    [self updateLabels];
}

#pragma mark - Window

- (UIWindow *)findGameWindow
{
    if (@available(iOS 13.0, *)) {

        NSSet<UIScene *> *scenes =
            UIApplication.sharedApplication.connectedScenes;

        for (UIScene *scene in scenes) {

            if (scene.activationState != UISceneActivationStateForegroundActive &&
                scene.activationState != UISceneActivationStateForegroundInactive) {
                continue;
            }

            if (![scene isKindOfClass:[UIWindowScene class]]) {
                continue;
            }

            UIWindowScene *windowScene =
                (UIWindowScene *)scene;

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

#pragma mark - UI

- (UILabel *)makeLabel
{
    UILabel *label = [[UILabel alloc] init];

    label.textColor =
        [UIColor colorWithWhite:1.0 alpha:0.95];

    label.backgroundColor =
        UIColor.clearColor;

    /*
     * Steam Deck / MangoHud-inspired compact terminal style.
     */
    label.font =
        [UIFont monospacedDigitSystemFontOfSize:12.0
                                         weight:UIFontWeightSemibold];

    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentLeft;
    label.userInteractionEnabled = NO;

    /*
     * Thin outline/shadow keeps text readable on bright scenes
     * without creating a box behind the overlay.
     */
    label.layer.shadowColor =
        UIColor.blackColor.CGColor;

    label.layer.shadowOffset =
        CGSizeMake(1.0, 1.0);

    label.layer.shadowOpacity = 0.95;
    label.layer.shadowRadius = 1.5;

    label.translatesAutoresizingMaskIntoConstraints = NO;

    return label;
}

- (void)createOverlayOnWindow:(UIWindow *)window
{
    [_label removeFromSuperview];
    [_deviceLabel removeFromSuperview];

    _hostWindow = window;

    _label = [self makeLabel];
    _deviceLabel = [self makeLabel];

    _deviceLabel.font =
        [UIFont monospacedDigitSystemFontOfSize:11.0
                                         weight:UIFontWeightSemibold];

    [window addSubview:_label];
    [window addSubview:_deviceLabel];

    /*
     * Compact horizontal MangoHud-style layout.
     *
     * Top-left, minimal vertical footprint.
     */
    [NSLayoutConstraint activateConstraints:@[

        [_label.leadingAnchor
            constraintEqualToAnchor:window.leadingAnchor
            constant:18.0],

        [_label.topAnchor
            constraintEqualToAnchor:window.safeAreaLayoutGuide.topAnchor
            constant:5.0],

        [_label.trailingAnchor
            constraintLessThanOrEqualToAnchor:window.trailingAnchor
            constant:-18.0],

        [_label.heightAnchor
            constraintEqualToConstant:23.0],

        [_deviceLabel.leadingAnchor
            constraintEqualToAnchor:_label.leadingAnchor],

        [_deviceLabel.topAnchor
            constraintEqualToAnchor:_label.bottomAnchor
            constant:1.0],

        [_deviceLabel.trailingAnchor
            constraintLessThanOrEqualToAnchor:window.trailingAnchor
            constant:-18.0],

        [_deviceLabel.heightAnchor
            constraintEqualToConstant:20.0]
    ]];

    [self updateLabels];
}

- (void)refreshWindow
{
    UIWindow *window = [self findGameWindow];

    if (!window) {
        return;
    }

    if (_hostWindow != window ||
        _label.superview != window ||
        _deviceLabel.superview != window) {

        [self createOverlayOnWindow:window];
    }

    if (!_displayLink) {

        _displayLink =
            [CADisplayLink displayLinkWithTarget:self
                                        selector:@selector(frameTick:)];

        [_displayLink addToRunLoop:NSRunLoop.mainRunLoop
                           forMode:NSRunLoopCommonModes];
    }
}

#pragma mark - Start

- (void)start
{
    if (_started) {
        [self refreshWindow];
        return;
    }

    _started = YES;

    /*
     * Battery monitoring is enabled before the first UI update.
     */
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;

    /*
     * Battery update timer.
     * This does not depend on battery-change notifications.
     */
    _batteryTimer =
        [NSTimer scheduledTimerWithTimeInterval:5.0
                                         target:self
                                       selector:@selector(batteryTimerTick)
                                       userInfo:nil
                                        repeats:YES];

    /*
     * Battery notification is an additional update path.
     */
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(batteryTimerTick)
               name:UIDeviceBatteryLevelDidChangeNotification
             object:nil];

    /*
     * Delay initial overlay attachment for game compatibility.
     */
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
        dispatch_get_main_queue(),
        ^{
            [self refreshWindow];

            if (!self->_refreshTimer) {

                self->_refreshTimer =
                    [NSTimer scheduledTimerWithTimeInterval:2.0
                                                     target:self
                                                   selector:@selector(refreshWindow)
                                                   userInfo:nil
                                                    repeats:YES];
            }
        }
    );
}

#pragma mark - FPS

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

    if (elapsed < 0.5) {
        return;
    }

    double fps =
        (double)_frameCount / elapsed;

    if (fps > 0.0 && fps < 240.0) {

        if (_historyCount < FPS_HISTORY_SIZE) {

            _fpsHistory[_historyCount] = fps;
            _historyCount++;

        } else {

            memmove(
                &_fpsHistory[0],
                &_fpsHistory[1],
                sizeof(double) * (FPS_HISTORY_SIZE - 1)
            );

            _fpsHistory[FPS_HISTORY_SIZE - 1] = fps;
        }

        _sumFPS += fps;
        _sampleCount++;

        if (fps < _minFPS) {
            _minFPS = fps;
        }

        if (fps > _maxFPS) {
            _maxFPS = fps;
        }

        [self updateLabels];
    }

    _frameCount = 0;
    _lastTimestamp = link.timestamp;
}

#pragma mark - Statistics

- (double)currentFPS
{
    if (_historyCount <= 0) {
        return 0.0;
    }

    return _fpsHistory[_historyCount - 1];
}

- (double)averageFPS
{
    if (_sampleCount <= 0) {
        return 0.0;
    }

    return _sumFPS / (double)_sampleCount;
}

- (double)percentile:(double)percent
{
    if (_historyCount < 2) {
        return 0.0;
    }

    double sorted[FPS_HISTORY_SIZE];

    memcpy(
        sorted,
        _fpsHistory,
        sizeof(double) * _historyCount
    );

    for (NSInteger i = 1; i < _historyCount; i++) {

        double key = sorted[i];
        NSInteger j = i - 1;

        while (j >= 0 && sorted[j] > key) {
            sorted[j + 1] = sorted[j];
            j--;
        }

        sorted[j + 1] = key;
    }

    double position =
        ((double)(_historyCount - 1)) * percent;

    NSInteger index =
        (NSInteger)floor(position);

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

    return (double)info.resident_size /
           (1024.0 * 1024.0);
}

- (double)refreshRate
{
    if (@available(iOS 10.3, *)) {

        if (_hostWindow &&
            _hostWindow.screen) {

            return _hostWindow.screen.maximumFramesPerSecond;
        }
    }

    return 60.0;
}

#pragma mark - Labels

- (void)updateLabels
{
    if (!_label || !_deviceLabel) {
        return;
    }

    double fps = [self currentFPS];

    double frameTime =
        fps > 0.0 ?
        (1000.0 / fps) :
        0.0;

    double avg =
        [self averageFPS];

    double onePercentLow =
        [self percentile:0.01];

    double zeroPointOnePercentLow =
        [self percentile:0.001];

    double minFPS =
        _sampleCount > 0 ?
        _minFPS :
        0.0;

    double maxFPS =
        _maxFPS;

    double hz =
        [self refreshRate];

    double ram =
        [self memoryMB];

    /*
     * SINGLE-LINE MAIN HUD.
     * This is the main Steam Deck/MangoHud-inspired design.
     */
    _label.text =
        [NSString stringWithFormat:
            @"FPS %.1f  |  AVG %.1f  |  1%% %.1f  |  0.1%% %.1f  |  FT %.2fms  |  MIN %.1f  |  MAX %.1f  |  HZ %.0f  |  RAM %.0fMB",
            fps,
            avg,
            onePercentLow,
            zeroPointOnePercentLow,
            frameTime,
            minFPS,
            maxFPS,
            hz,
            ram];

    _deviceLabel.text =
        [NSString stringWithFormat:
            @"%@  |  %@  |  %@",
            [self deviceModel],
            [self gpuName],
            [self batteryText]];
}

@end

#pragma mark - Initialization

static FPSOverlayController *gFPSOverlayController = nil;

__attribute__((constructor))
static void FPSOverlayInit(void)
{
    /*
     * Do not touch UIKit from the constructor thread.
     */
    dispatch_async(
        dispatch_get_main_queue(),
        ^{

            gFPSOverlayController =
                [[FPSOverlayController alloc] init];

            if ([[UIApplication sharedApplication]
                    applicationState] ==
                UIApplicationStateActive) {

                [gFPSOverlayController start];
            }

            [[NSNotificationCenter defaultCenter]
                addObserverForName:
                    UIApplicationDidBecomeActiveNotification
                object:nil
                queue:[NSOperationQueue mainQueue]
                usingBlock:
                    ^(NSNotification *notification) {

                        [gFPSOverlayController start];
                    }];
        }
    );
}
