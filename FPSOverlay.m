#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <mach/mach.h>
#import <sys/sysctl.h>
#import <float.h>
#import <string.h>

#define FPS_HISTORY_SIZE 120
#define CPU_SAMPLE_INTERVAL 0.5

@interface FPSOverlayController : NSObject
{
    UILabel *_label;
    UIWindow *_hostWindow;

    CADisplayLink *_displayLink;
    NSTimer *_refreshTimer;
    NSTimer *_batteryTimer;
    NSTimer *_cpuTimer;

    CFTimeInterval _lastTimestamp;
    NSInteger _frameCount;

    double _fpsHistory[FPS_HISTORY_SIZE];
    NSInteger _historyCount;

    double _cpuPercent;
    uint64_t _previousUserTime;
    uint64_t _previousSystemTime;
    uint64_t _previousWallTime;
    BOOL _hasCPUBase;

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
        _cpuPercent = 0.0;
        _previousUserTime = 0;
        _previousSystemTime = 0;
        _previousWallTime = 0;
        _hasCPUBase = NO;
        _started = NO;

        [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    }
    return self;
}

- (void)dealloc
{
    [_refreshTimer invalidate];
    [_batteryTimer invalidate];
    [_cpuTimer invalidate];
    [_displayLink invalidate];
    [_label removeFromSuperview];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

#pragma mark - Device

- (NSString *)deviceModel
{
    size_t size = 0;
    sysctlbyname("hw.machine", NULL, &size, NULL, 0);
    if (size == 0) return @"iPhone";

    char *machine = malloc(size);
    if (!machine) return @"iPhone";

    sysctlbyname("hw.machine", machine, &size, NULL, 0);
    NSString *identifier = [NSString stringWithUTF8String:machine];
    free(machine);

    if (!identifier) return @"iPhone";

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
    return name ? name : identifier;
}

- (NSString *)cpuName
{
    NSString *model = [self deviceModel];

    if ([model hasPrefix:@"iPhone 11"]) return @"A13";
    if ([model hasPrefix:@"iPhone 12"]) return @"A14";
    if ([model isEqualToString:@"iPhone 13"] ||
        [model isEqualToString:@"iPhone 13 mini"] ||
        [model isEqualToString:@"iPhone 13 Pro"] ||
        [model isEqualToString:@"iPhone 13 Pro Max"]) return @"A15";
    if ([model isEqualToString:@"iPhone 14"] ||
        [model isEqualToString:@"iPhone 14 Plus"]) return @"A15";
    if ([model isEqualToString:@"iPhone 14 Pro"] ||
        [model isEqualToString:@"iPhone 14 Pro Max"]) return @"A16";
    if ([model isEqualToString:@"iPhone 15"] ||
        [model isEqualToString:@"iPhone 15 Plus"]) return @"A16";
    if ([model hasPrefix:@"iPhone 15 Pro"]) return @"A17 Pro";
    if ([model hasPrefix:@"iPhone 16"]) return @"A18";
    if ([model hasPrefix:@"iPhone 17"]) return @"A19";
    if ([model isEqualToString:@"iPhone Air"]) return @"Apple Silicon";

    return @"Apple CPU";
}

- (NSString *)gpuName
{
    NSString *model = [self deviceModel];

    if ([model hasPrefix:@"iPhone 11"]) return @"A13 GPU";
    if ([model hasPrefix:@"iPhone 12"]) return @"A14 GPU";
    if ([model hasPrefix:@"iPhone 13"]) return @"A15 GPU";
    if ([model isEqualToString:@"iPhone 14"] || [model isEqualToString:@"iPhone 14 Plus"]) return @"A15 GPU";
    if ([model hasPrefix:@"iPhone 14 Pro"]) return @"A16 GPU";
    if ([model hasPrefix:@"iPhone 15 Pro"]) return @"A17 GPU";
    if ([model hasPrefix:@"iPhone 15"]) return @"A16 GPU";
    if ([model hasPrefix:@"iPhone 16"]) return @"A18 GPU";
    if ([model hasPrefix:@"iPhone 17"]) return @"A19 GPU";
    return @"Apple GPU";
}

- (NSInteger)cpuCoreCount
{
    int cores = 0;
    size_t size = sizeof(cores);
    if (sysctlbyname("hw.ncpu", &cores, &size, NULL, 0) == 0 && cores > 0) return cores;
    return 0;
}

#pragma mark - CPU

- (void)sampleCPU:(NSTimer *)timer
{
    task_thread_times_info_data_t times;
    mach_msg_type_number_t count = TASK_THREAD_TIMES_INFO_COUNT;

    kern_return_t kr = task_info(mach_task_self(),
                                 TASK_THREAD_TIMES_INFO,
                                 (task_info_t)&times,
                                 &count);
    if (kr != KERN_SUCCESS) return;

    uint64_t user = ((uint64_t)times.user_time.seconds * 1000000ULL) +
                    (uint64_t)times.user_time.microseconds;
    uint64_t system = ((uint64_t)times.system_time.seconds * 1000000ULL) +
                      (uint64_t)times.system_time.microseconds;

    CFTimeInterval now = CACurrentMediaTime();
    uint64_t wall = (uint64_t)(now * 1000000.0);

    if (_hasCPUBase) {
        uint64_t cpuDelta = (user - _previousUserTime) +
                            (system - _previousSystemTime);
        uint64_t wallDelta = wall - _previousWallTime;

        if (wallDelta > 0) {
            double percent = ((double)cpuDelta / (double)wallDelta) * 100.0;
            NSInteger cores = [self cpuCoreCount];

            if (cores > 0) {
                /* task time can exceed 100% when several threads run at once. */
                percent = percent / (double)cores;
            }

            if (percent < 0.0) percent = 0.0;
            if (percent > 100.0) percent = 100.0;
            _cpuPercent = percent;
        }
    }

    _previousUserTime = user;
    _previousSystemTime = system;
    _previousWallTime = wall;
    _hasCPUBase = YES;

    [self updateLabel];
}

#pragma mark - Memory

- (double)ramMB
{
    mach_task_basic_info_data_t info;
    mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;

    kern_return_t result = task_info(mach_task_self(),
                                     MACH_TASK_BASIC_INFO,
                                     (task_info_t)&info,
                                     &count);
    if (result != KERN_SUCCESS) return 0.0;

    return (double)info.resident_size / (1024.0 * 1024.0);
}

- (double)totalRAMGB
{
    uint64_t bytes = [NSProcessInfo processInfo].physicalMemory;
    return (double)bytes / (1024.0 * 1024.0 * 1024.0);
}

#pragma mark - Battery / display

- (NSString *)batteryText
{
    UIDevice *device = [UIDevice currentDevice];
    device.batteryMonitoringEnabled = YES;
    float level = device.batteryLevel;

    if (level < 0.0f) return @"--";
    return [NSString stringWithFormat:@"%.0f%%", level * 100.0f];
}

- (double)refreshRate
{
    if (@available(iOS 10.3, *)) {
        if (_hostWindow && _hostWindow.screen) {
            return _hostWindow.screen.maximumFramesPerSecond;
        }
    }
    return 60.0;
}

- (NSString *)thermalText
{
    if (@available(iOS 11.0, *)) {
        NSProcessInfoThermalState state = [NSProcessInfo processInfo].thermalState;
        switch (state) {
            case NSProcessInfoThermalStateNominal: return @"NOM";
            case NSProcessInfoThermalStateFair: return @"FAIR";
            case NSProcessInfoThermalStateSerious: return @"SER";
            case NSProcessInfoThermalStateCritical: return @"CRIT";
        }
    }
    return @"--";
}

#pragma mark - FPS graph

- (NSString *)tinyGraph
{
    if (_historyCount < 2) return @"▁▁▁▁▁▁▁▁";

    static NSString *blocks = @"▁▂▃▄▅▆▇█";
    NSInteger graphCount = 8;
    NSMutableString *graph = [NSMutableString stringWithCapacity:graphCount];

    NSInteger start = _historyCount > graphCount ? (_historyCount - graphCount) : 0;
    NSInteger count = _historyCount - start;

    double minValue = DBL_MAX;
    double maxValue = 0.0;

    for (NSInteger i = start; i < _historyCount; i++) {
        double v = _fpsHistory[i];
        if (v < minValue) minValue = v;
        if (v > maxValue) maxValue = v;
    }

    double range = maxValue - minValue;
    if (range < 0.1) range = 1.0;

    for (NSInteger i = 0; i < count; i++) {
        double v = _fpsHistory[start + i];
        NSInteger index = (NSInteger)floor(((v - minValue) / range) * 7.0 + 0.5);
        if (index < 0) index = 0;
        if (index > 7) index = 7;
        unichar c = [blocks characterAtIndex:index];
        [graph appendFormat:@"%C", c];
    }

    while ([graph length] < graphCount) {
        [graph insertString:@"▁" atIndex:0];
    }

    return graph;
}

#pragma mark - UI

- (UILabel *)makeLabel
{
    UILabel *label = [[UILabel alloc] init];
    label.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.52];
    label.layer.cornerRadius = 4.0;
    label.layer.masksToBounds = YES;
    label.font = [UIFont monospacedDigitSystemFontOfSize:8.5 weight:UIFontWeightSemibold];
    label.numberOfLines = 1;
    label.textAlignment = NSTextAlignmentLeft;
    label.userInteractionEnabled = NO;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.40;
    label.lineBreakMode = NSLineBreakByClipping;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.layer.shadowColor = UIColor.blackColor.CGColor;
    label.layer.shadowOffset = CGSizeMake(0.5, 0.5);
    label.layer.shadowOpacity = 0.9;
    label.layer.shadowRadius = 1.0;
    return label;
}

- (void)createOverlayOnWindow:(UIWindow *)window
{
    [_label removeFromSuperview];
    [_label release];
    _label = nil;

    _hostWindow = window;
    _label = [self makeLabel];
    [window addSubview:_label];

    [NSLayoutConstraint activateConstraints:@[
        [_label.centerXAnchor constraintEqualToAnchor:window.centerXAnchor],
        [_label.leadingAnchor constraintGreaterThanOrEqualToAnchor:window.leadingAnchor constant:8.0],
        [_label.trailingAnchor constraintLessThanOrEqualToAnchor:window.trailingAnchor constant:-8.0],
        [_label.topAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.topAnchor constant:3.0],
        [_label.heightAnchor constraintEqualToConstant:19.0]
    ]];

    [self updateLabel];
}

- (UIWindow *)findGameWindow
{
    if (@available(iOS 13.0, *)) {
        NSSet<UIScene *> *scenes = UIApplication.sharedApplication.connectedScenes;

        for (UIScene *scene in scenes) {
            if (scene.activationState != UISceneActivationStateForegroundActive &&
                scene.activationState != UISceneActivationStateForegroundInactive) {
                continue;
            }

            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            UIWindowScene *windowScene = (UIWindowScene *)scene;

            for (UIWindow *window in windowScene.windows) {
                if (!window.hidden && window.alpha > 0.01 &&
                    window.windowLevel == UIWindowLevelNormal && window.isKeyWindow) {
                    return window;
                }
            }

            for (UIWindow *window in windowScene.windows) {
                if (!window.hidden && window.alpha > 0.01 &&
                    window.windowLevel == UIWindowLevelNormal) {
                    return window;
                }
            }
        }
    }

    return nil;
}

#pragma mark - Labels

- (void)updateLabel
{
    if (!_label) return;

    double fps = 0.0;
    if (_historyCount > 0) fps = _fpsHistory[_historyCount - 1];

    NSString *cpu = [self cpuName];
    NSString *gpu = [self gpuName];
    NSInteger cores = [self cpuCoreCount];
    double ram = [self ramMB];
    double totalRAM = [self totalRAMGB];
    NSString *battery = [self batteryText];
    double hz = [self refreshRate];
    NSString *thermal = [self thermalText];
    NSString *graph = [self tinyGraph];
    double frameTime = fps > 0.0 ? (1000.0 / fps) : 0.0;

    NSString *ramText;
    if (ram >= 1024.0) {
        ramText = [NSString stringWithFormat:@"%.1fG/%.1fG", ram / 1024.0, totalRAM];
    } else {
        ramText = [NSString stringWithFormat:@"%.0fM/%.1fG", ram, totalRAM];
    }

    NSString *cpuText = cores > 0
        ? [NSString stringWithFormat:@"CPU %@ %.0f%%/%ldC", cpu, _cpuPercent, (long)cores]
        : [NSString stringWithFormat:@"CPU %@ %.0f%%", cpu, _cpuPercent];

    /*
     * GPU utilization and device-wide wattage are intentionally omitted.
     * No placeholder/fake values are shown.
     */
    NSString *gpuText = [NSString stringWithFormat:@"GPU %@", gpu];

    NSString *plain = [NSString stringWithFormat:
        @"FPS %.0f | %@ | %@ | RAM %@ | BATT %@ | FT %.1fms | HZ %.0f | THM %@ | %@",
        fps, cpuText, gpuText, ramText, battery, frameTime, hz, thermal, graph];

    NSMutableAttributedString *styled =
        [[[NSMutableAttributedString alloc] initWithString:plain] autorelease];

    UIColor *white = [UIColor colorWithWhite:0.95 alpha:1.0];
    UIColor *cyan = [UIColor colorWithRed:0.25 green:0.85 blue:1.0 alpha:1.0];
    UIColor *green = [UIColor colorWithRed:0.35 green:1.0 blue:0.55 alpha:1.0];
    UIColor *pink = [UIColor colorWithRed:1.0 green:0.35 blue:0.65 alpha:1.0];
    UIColor *orange = [UIColor colorWithRed:1.0 green:0.70 blue:0.25 alpha:1.0];
    UIColor *purple = [UIColor colorWithRed:0.75 green:0.55 blue:1.0 alpha:1.0];

    [styled addAttribute:NSForegroundColorAttributeName value:white range:NSMakeRange(0, [plain length])];

    NSRange r;
    r = [plain rangeOfString:@"FPS"]; if (r.location != NSNotFound) [styled addAttribute:NSForegroundColorAttributeName value:cyan range:r];
    r = [plain rangeOfString:@"CPU"]; if (r.location != NSNotFound) [styled addAttribute:NSForegroundColorAttributeName value:cyan range:r];
    r = [plain rangeOfString:@"GPU"]; if (r.location != NSNotFound) [styled addAttribute:NSForegroundColorAttributeName value:green range:r];
    r = [plain rangeOfString:@"RAM"]; if (r.location != NSNotFound) [styled addAttribute:NSForegroundColorAttributeName value:purple range:r];
    r = [plain rangeOfString:@"BATT"]; if (r.location != NSNotFound) [styled addAttribute:NSForegroundColorAttributeName value:pink range:r];
    r = [plain rangeOfString:@"FT"]; if (r.location != NSNotFound) [styled addAttribute:NSForegroundColorAttributeName value:orange range:r];
    r = [plain rangeOfString:@"HZ"]; if (r.location != NSNotFound) [styled addAttribute:NSForegroundColorAttributeName value:purple range:r];
    r = [plain rangeOfString:@"THM"]; if (r.location != NSNotFound) [styled addAttribute:NSForegroundColorAttributeName value:orange range:r];
    r = [plain rangeOfString:graph options:NSBackwardsSearch range:NSMakeRange(0, [plain length])];
    if (r.location != NSNotFound) [styled addAttribute:NSForegroundColorAttributeName value:green range:r];

    _label.attributedText = styled;
}

#pragma mark - Window / start

- (void)batteryTimerTick:(NSTimer *)timer
{
    [self updateLabel];
}

- (void)refreshWindowTimer:(NSTimer *)timer
{
    [self refreshWindow];
}

- (void)refreshWindow
{
    UIWindow *window = [self findGameWindow];
    if (!window) return;

    if (_hostWindow != window || _label.superview != window) {
        [self createOverlayOnWindow:window];
    }

    if (!_displayLink) {
        _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(frameTick:)];
        [_displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
}

- (void)start
{
    if (_started) {
        [self refreshWindow];
        return;
    }

    _started = YES;
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;

    _batteryTimer = [NSTimer scheduledTimerWithTimeInterval:3.0
                                                      target:self
                                                    selector:@selector(batteryTimerTick:)
                                                    userInfo:nil
                                                     repeats:YES];

    _cpuTimer = [NSTimer scheduledTimerWithTimeInterval:CPU_SAMPLE_INTERVAL
                                                  target:self
                                                selector:@selector(sampleCPU:)
                                                userInfo:nil
                                                 repeats:YES];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(updateLabel)
                                                 name:UIDeviceBatteryLevelDidChangeNotification
                                               object:nil];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        [self refreshWindow];

        if (!self->_refreshTimer) {
            self->_refreshTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                                     target:self
                                                                   selector:@selector(refreshWindowTimer:)
                                                                   userInfo:nil
                                                                    repeats:YES];
        }
    });
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
    CFTimeInterval elapsed = link.timestamp - _lastTimestamp;
    if (elapsed < 0.5) return;

    double fps = (double)_frameCount / elapsed;

    if (fps > 0.0 && fps < 240.0) {
        if (_historyCount < FPS_HISTORY_SIZE) {
            _fpsHistory[_historyCount++] = fps;
        } else {
            memmove(&_fpsHistory[0], &_fpsHistory[1], sizeof(double) * (FPS_HISTORY_SIZE - 1));
            _fpsHistory[FPS_HISTORY_SIZE - 1] = fps;
        }
        [self updateLabel];
    }

    _frameCount = 0;
    _lastTimestamp = link.timestamp;
}

@end

#pragma mark - Initialization

static FPSOverlayController *gFPSOverlayController = nil;

__attribute__((constructor))
static void FPSOverlayInit(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        gFPSOverlayController = [[FPSOverlayController alloc] init];

        if ([[UIApplication sharedApplication] applicationState] == UIApplicationStateActive) {
            [gFPSOverlayController start];
        }

        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *notification) {
            [gFPSOverlayController start];
        }];
    });
}
