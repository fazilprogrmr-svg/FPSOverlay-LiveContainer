#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <mach/mach.h>
#import <sys/sysctl.h>
#import <float.h>
#import <string.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <objc/message.h>

#define FPS_HISTORY_SIZE 120
#define CPU_SAMPLE_INTERVAL 0.5
#define OVERLAY_REFRESH_INTERVAL 0.5
#define BATTERY_SAMPLE_INTERVAL 2.0

typedef NS_ENUM(NSInteger, FPSOverlayPreset) {
    FPSOverlayPresetDefault = 0,
    FPSOverlayPresetMinimal = 1,
    FPSOverlayPresetNeon = 2,
    FPSOverlayPresetPerformance = 3
};

@class FPSOverlayController;
static FPSOverlayController *gFPSOverlayController = nil;

/*
 * Metal presentation counter. CADisplayLink fires with the display refresh
 * cadence (for example 60 Hz) even when a Metal game is only presenting
 * 30 rendered frames per second. Count actual Metal drawable presentations
 * instead so FPS/Frame Time follows the rendered frame cadence.
 */
static volatile uint64_t gMetalPresentedFrames = 0;
static IMP gOriginalCAMetalLayerNextDrawable = NULL;
static const void *kFPSOverlayPresentedHandlerKey = &kFPSOverlayPresentedHandlerKey;

typedef id (*FPSNextDrawableIMP)(id, SEL);
typedef void (*FPSAddPresentedHandlerIMP)(id, SEL, id);

static void FPSOverlayAttachPresentedHandler(id drawable)
{
    if (!drawable) return;

    SEL addHandlerSEL = NSSelectorFromString(@"addPresentedHandler:");
    if (![drawable respondsToSelector:addHandlerSEL]) return;

    /* A drawable object can be reused for many frames. Attach once. */
    if (objc_getAssociatedObject(drawable, kFPSOverlayPresentedHandlerKey)) return;

    id marker = [[NSObject alloc] init];
    objc_setAssociatedObject(drawable, kFPSOverlayPresentedHandlerKey, marker, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [marker release];

    FPSAddPresentedHandlerIMP addHandler = (FPSAddPresentedHandlerIMP)objc_msgSend;
    id handler = [[^(id presentedDrawable) {
        __sync_fetch_and_add(&gMetalPresentedFrames, 1);
    } copy] autorelease];

    addHandler(drawable, addHandlerSEL, handler);
}

static id FPSOverlay_CAMetalLayer_nextDrawable(id self, SEL _cmd)
{
    if (!gOriginalCAMetalLayerNextDrawable) return nil;

    FPSNextDrawableIMP original = (FPSNextDrawableIMP)gOriginalCAMetalLayerNextDrawable;
    id drawable = original(self, _cmd);
    FPSOverlayAttachPresentedHandler(drawable);
    return drawable;
}

static void FPSOverlayInstallMetalFrameHook(void)
{
    Class metalLayerClass = NSClassFromString(@"CAMetalLayer");
    SEL nextDrawableSEL = NSSelectorFromString(@"nextDrawable");
    Method method = metalLayerClass ? class_getInstanceMethod(metalLayerClass, nextDrawableSEL) : NULL;
    if (!method) return;

    gOriginalCAMetalLayerNextDrawable = method_getImplementation(method);
    method_setImplementation(method, (IMP)FPSOverlay_CAMetalLayer_nextDrawable);
}


@interface FPSOverlayController : NSObject
{
    UILabel *_label;
    UIView *_containerView;
    UIWindow *_hostWindow;

    CADisplayLink *_displayLink;
    NSTimer *_refreshTimer;
    NSTimer *_batteryTimer;
    NSTimer *_cpuTimer;

    CFTimeInterval _lastTimestamp;
    NSInteger _frameCount;

    double _fpsHistory[FPS_HISTORY_SIZE];
    NSInteger _historyCount;

    uint64_t _lastMetalPresentedFrames;
    CFTimeInterval _lastFPSSampleTime;
    double _measuredFPS;
    BOOL _hasMetalFPS;

    double _cpuPercent;
    uint64_t _previousUserTime;
    uint64_t _previousSystemTime;
    uint64_t _previousWallTime;
    BOOL _hasCPUBase;

    double _batteryPercent;
    BOOL _hasBatteryPercent;

    BOOL _started;
    BOOL _compactMode;
    BOOL _hidden;
    NSInteger _preset;
    CGFloat _hudOpacity;
}
- (void)start;
- (void)refreshWindow;
- (void)applyPreset:(FPSOverlayPreset)preset;
@end

@implementation FPSOverlayController

- (id)init
{
    self = [super init];
    if (self) {
        _lastTimestamp = 0.0;
        _frameCount = 0;
        _historyCount = 0;
        _lastMetalPresentedFrames = 0;
        _lastFPSSampleTime = 0.0;
        _measuredFPS = 0.0;
        _hasMetalFPS = NO;
        _cpuPercent = 0.0;
        _previousUserTime = 0;
        _previousSystemTime = 0;
        _previousWallTime = 0;
        _hasCPUBase = NO;
        _batteryPercent = -1.0;
        _hasBatteryPercent = NO;
        _started = NO;
        _compactMode = NO;
        _hidden = NO;
        _preset = FPSOverlayPresetDefault;
        _hudOpacity = 0.52;

        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSInteger savedPreset = [defaults integerForKey:@"FPSOverlay_Preset"];
        if (savedPreset < FPSOverlayPresetDefault || savedPreset > FPSOverlayPresetPerformance) {
            savedPreset = FPSOverlayPresetDefault;
        }
        [self applyPreset:(FPSOverlayPreset)savedPreset];
        _hidden = [defaults boolForKey:@"FPSOverlay_Hidden"];
        _compactMode = [defaults boolForKey:@"FPSOverlay_CompactMode"];

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
    [_containerView removeFromSuperview];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

- (NSString *)presetName:(FPSOverlayPreset)preset
{
    switch (preset) {
        case FPSOverlayPresetMinimal: return @"Minimal";
        case FPSOverlayPresetNeon: return @"Neon";
        case FPSOverlayPresetPerformance: return @"Performance";
        case FPSOverlayPresetDefault:
        default: return @"Default";
    }
}

- (void)applyPreset:(FPSOverlayPreset)preset
{
    _preset = preset;

    switch (preset) {
        case FPSOverlayPresetMinimal:
            _compactMode = YES;
            _hudOpacity = 0.28;
            break;
        case FPSOverlayPresetNeon:
            _compactMode = NO;
            _hudOpacity = 0.55;
            break;
        case FPSOverlayPresetPerformance:
            _compactMode = NO;
            _hudOpacity = 0.60;
            break;
        case FPSOverlayPresetDefault:
        default:
            _compactMode = NO;
            _hudOpacity = 0.48;
            break;
    }

    [self savePreferences];
    [self updateLabel];
}

- (void)cyclePreset
{
    NSInteger nextPreset = (_preset + 1) % 4;
    [self applyPreset:(FPSOverlayPreset)nextPreset];
}

- (void)savePreferences
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setInteger:_preset forKey:@"FPSOverlay_Preset"];
    [defaults setBool:_compactMode forKey:@"FPSOverlay_CompactMode"];
    [defaults setBool:_hidden forKey:@"FPSOverlay_Hidden"];

    if (_containerView && _hostWindow) {
        [defaults setFloat:_containerView.frame.origin.x forKey:@"FPSOverlay_LabelOriginX"];
        [defaults setFloat:_containerView.frame.origin.y forKey:@"FPSOverlay_LabelOriginY"];
    }

    [defaults synchronize];
}

- (void)handlePan:(UIPanGestureRecognizer *)panGesture
{
    if (!_hostWindow || !_containerView || _hidden) return;

    CGPoint translation = [panGesture translationInView:_hostWindow];
    CGRect frame = _containerView.frame;
    frame.origin.x += translation.x;
    frame.origin.y += translation.y;

    CGFloat minX = 8.0;
    CGFloat maxX = _hostWindow.bounds.size.width - frame.size.width - 8.0;
    CGFloat minY = 20.0;
    CGFloat maxY = _hostWindow.bounds.size.height - frame.size.height - 8.0;

    if (frame.origin.x < minX) frame.origin.x = minX;
    if (frame.origin.x > maxX) frame.origin.x = maxX;
    if (frame.origin.y < minY) frame.origin.y = minY;
    if (frame.origin.y > maxY) frame.origin.y = maxY;

    _containerView.frame = frame;
    [panGesture setTranslation:CGPointZero inView:_hostWindow];

    if (panGesture.state == UIGestureRecognizerStateEnded ||
        panGesture.state == UIGestureRecognizerStateCancelled ||
        panGesture.state == UIGestureRecognizerStateFailed) {
        [self savePreferences];
    }
}

- (void)toggleCompactMode
{
    _compactMode = !_compactMode;
    [self savePreferences];
    [self updateLabel];
}

- (void)toggleVisibility
{
    _hidden = !_hidden;
    [self savePreferences];
    if (_containerView) {
        _containerView.hidden = _hidden;
        _containerView.alpha = _hidden ? 0.0 : 1.0;
    }
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)tapGesture
{
    if (tapGesture.state != UIGestureRecognizerStateEnded) return;
    [self toggleCompactMode];
}

- (void)handleTripleTap:(UITapGestureRecognizer *)tapGesture
{
    if (tapGesture.state != UIGestureRecognizerStateEnded) return;
    [self toggleVisibility];
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture
{
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    [self cyclePreset];
}

- (void)positionLabelForWindow:(UIWindow *)window
{
    if (!_label || !_containerView || !window) return;

    [_label sizeToFit];

    CGFloat pad = 8.0;
    CGFloat maxWidth = window.bounds.size.width - (pad * 2.0);
    CGFloat width = _label.bounds.size.width + 20.0;
    if (width > maxWidth) width = maxWidth;

    CGFloat height = 32.0;
    CGRect frame = _containerView.frame;
    frame.size.width = width;
    frame.size.height = height;

    if (frame.origin.x <= 0.0 || frame.origin.x > window.bounds.size.width - width) {
        frame.origin.x = pad;
    }
    if (frame.origin.y <= 0.0 || frame.origin.y > window.bounds.size.height - height) {
        frame.origin.y = 20.0;
    }

    _containerView.frame = frame;
    _label.frame = CGRectMake(6.0, 4.0, frame.size.width - 12.0, frame.size.height - 8.0);
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

    if ([model hasPrefix:@"iPhone 11"]) return @"A13 Bionic";
    if ([model hasPrefix:@"iPhone 12"]) return @"A14 Bionic";
    if ([model isEqualToString:@"iPhone 13"] ||
        [model isEqualToString:@"iPhone 13 mini"] ||
        [model isEqualToString:@"iPhone 13 Pro"] ||
        [model isEqualToString:@"iPhone 13 Pro Max"]) return @"A15 Bionic";
    if ([model isEqualToString:@"iPhone 14"] ||
        [model isEqualToString:@"iPhone 14 Plus"]) return @"A15 Bionic";
    if ([model isEqualToString:@"iPhone 14 Pro"] ||
        [model isEqualToString:@"iPhone 14 Pro Max"]) return @"A16 Bionic";
    if ([model isEqualToString:@"iPhone 15"] ||
        [model isEqualToString:@"iPhone 15 Plus"]) return @"A16 Bionic";
    if ([model hasPrefix:@"iPhone 15 Pro"]) return @"A17 Pro";
    if ([model hasPrefix:@"iPhone 16"]) return @"A18";
    if ([model hasPrefix:@"iPhone 17"]) return @"A19";
    if ([model isEqualToString:@"iPhone Air"]) return @"Apple Silicon";

    return @"Apple CPU";
}

- (NSString *)gpuName
{
    void *handle = dlopen("/System/Library/Frameworks/Metal.framework/Metal", RTLD_LAZY);
    if (handle) {
        id (*createDevice)(void) = (id (*)(void))dlsym(handle, "MTLCreateSystemDefaultDevice");
        if (createDevice) {
            id device = createDevice();
            if (device && [device respondsToSelector:NSSelectorFromString(@"name")]) {
                NSString *name = [device name];
                if (name.length > 0) {
                    return name;
                }
            }
        }
        dlclose(handle);
    }

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

- (double)batteryPercent
{
    UIDevice *device = [UIDevice currentDevice];
    device.batteryMonitoringEnabled = YES;

    float level = device.batteryLevel;
    if (level >= 0.0f && level <= 1.0f) {
        return (double)level * 100.0;
    }

    return -1.0;
}

- (void)updateBatteryReading
{
    double level = [self batteryPercent];

    if (level >= 0.0 && level <= 100.0) {
        _batteryPercent = level;
        _hasBatteryPercent = YES;
    }

    [self updateLabel];
}

- (NSString *)batteryText
{
    if (!_hasBatteryPercent) return @"--";
    return [NSString stringWithFormat:@"%.0f%%", _batteryPercent];
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
            case NSProcessInfoThermalStateNominal: return @"Normal";
            case NSProcessInfoThermalStateFair: return @"Fair";
            case NSProcessInfoThermalStateSerious: return @"Serious";
            case NSProcessInfoThermalStateCritical: return @"Critical";
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

#pragma mark - UI - Liquid Glass Design

- (UIView *)makeLiquidGlassContainer
{
    UIView *container = [[UIView alloc] init];
    container.backgroundColor = [UIColor clearColor];
    container.layer.masksToBounds = YES;
    
    /* Liquid Glass: frosted glass effect with soft rounded corners */
    container.layer.cornerRadius = 10.0;
    container.layer.cornerCurve = kCACornerCurveContinuous;
    
    /* Base blur background */
    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    blurView.frame = container.bounds;
    blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [container addSubview:blurView];
    [blurView release];
    
    /* Semi-transparent overlay for liquid glass depth */
    UIView *glassOverlay = [[UIView alloc] init];
    glassOverlay.backgroundColor = [UIColor colorWithWhite:0.2 alpha:_hudOpacity * 0.4];
    glassOverlay.frame = container.bounds;
    glassOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [container addSubview:glassOverlay];
    [glassOverlay release];
    
    /* Subtle border for liquid glass definition */
    container.layer.borderWidth = 0.8;
    container.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.12].CGColor;
    
    /* Soft shadow for depth */
    container.layer.shadowColor = UIColor.blackColor.CGColor;
    container.layer.shadowOpacity = 0.3;
    container.layer.shadowOffset = CGSizeMake(0, 2);
    container.layer.shadowRadius = 6.0;
    
    return container;
}

- (UILabel *)makeLabel
{
    UILabel *label = [[UILabel alloc] init];
    label.backgroundColor = [UIColor clearColor];
    label.font = [UIFont monospacedDigitSystemFontOfSize:10.5 weight:UIFontWeightSemibold];
    label.numberOfLines = 1;
    label.textAlignment = NSTextAlignmentLeft;
    label.userInteractionEnabled = NO;
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.50;
    label.lineBreakMode = NSLineBreakByClipping;
    return label;
}

- (CGFloat)fontSizeForWindow:(UIWindow *)window
{
    CGFloat width = window.bounds.size.width;
    if (width >= 1000.0) return 11.5;
    if (width >= 700.0) return 10.5;
    if (width >= 500.0) return 9.5;
    return 8.0;
}

- (void)createOverlayOnWindow:(UIWindow *)window
{
    [_label removeFromSuperview];
    [_containerView removeFromSuperview];
    [_label release];
    [_containerView release];
    _label = nil;
    _containerView = nil;

    _hostWindow = window;
    
    /* Create liquid glass container */
    _containerView = [self makeLiquidGlassContainer];
    _containerView.hidden = _hidden;
    _containerView.alpha = _hidden ? 0.0 : 1.0;
    
    /* Create label inside container */
    _label = [self makeLabel];
    _label.font = [UIFont monospacedDigitSystemFontOfSize:[self fontSizeForWindow:window] weight:UIFontWeightSemibold];
    [_containerView addSubview:_label];

    /* Gestures on container */
    UIPanGestureRecognizer *panGesture = [[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)] autorelease];
    UITapGestureRecognizer *doubleTapGesture = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)] autorelease];
    UITapGestureRecognizer *tripleTapGesture = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTripleTap:)] autorelease];
    UILongPressGestureRecognizer *longPressGesture = [[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)] autorelease];
    doubleTapGesture.numberOfTapsRequired = 2;
    doubleTapGesture.numberOfTouchesRequired = 1;
    tripleTapGesture.numberOfTapsRequired = 3;
    tripleTapGesture.numberOfTouchesRequired = 1;
    longPressGesture.minimumPressDuration = 0.6;
    [tripleTapGesture requireGestureRecognizerToFail:doubleTapGesture];
    [_containerView addGestureRecognizer:panGesture];
    [_containerView addGestureRecognizer:doubleTapGesture];
    [_containerView addGestureRecognizer:tripleTapGesture];
    [_containerView addGestureRecognizer:longPressGesture];

    [window addSubview:_containerView];

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    CGFloat x = [defaults floatForKey:@"FPSOverlay_LabelOriginX"];
    CGFloat y = [defaults floatForKey:@"FPSOverlay_LabelOriginY"];
    if (x <= 0.0 || x > window.bounds.size.width - 80.0) x = 12.0;
    if (y <= 0.0 || y > window.bounds.size.height - 32.0) y = 20.0;
    _containerView.frame = CGRectMake(x, y, 250.0, 32.0);

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

    if (_hidden) {
        _containerView.hidden = YES;
        _containerView.alpha = 0.0;
        return;
    }

    if (_hostWindow) {
        _label.font = [UIFont monospacedDigitSystemFontOfSize:[self fontSizeForWindow:_hostWindow] weight:UIFontWeightSemibold];
    }

    _containerView.hidden = NO;
    _containerView.alpha = 1.0;

    double fps = _measuredFPS;
    if (fps <= 0.0 && _historyCount > 0) fps = _fpsHistory[_historyCount - 1];

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

    NSString *gpuText = [NSString stringWithFormat:@"GPU %@", gpu];

    NSString *plain;
    if (_compactMode) {
        plain = [NSString stringWithFormat:@"FPS %.0f | %@ | RAM %@ | BATT %@ | FT %.1fms | %@",
                 fps, cpuText, ramText, battery, frameTime, graph];
    } else {
        plain = [NSString stringWithFormat:
            @"FPS %.0f | %@ | %@ | RAM %@ | BATT %@ | FT %.1fms | HZ %.0f | Thermal State: %@ | %@",
            fps, cpuText, gpuText, ramText, battery, frameTime, hz, thermal, graph];
    }

    NSMutableAttributedString *styled =
        [[[NSMutableAttributedString alloc] initWithString:plain] autorelease];

    UIColor *white = [UIColor colorWithWhite:0.98 alpha:1.0];
    UIColor *cyan = [UIColor colorWithRed:0.25 green:0.85 blue:1.0 alpha:1.0];
    UIColor *green = [UIColor colorWithRed:0.35 green:1.0 blue:0.55 alpha:1.0];
    UIColor *pink = [UIColor colorWithRed:1.0 green:0.35 blue:0.65 alpha:1.0];
    UIColor *orange = [UIColor colorWithRed:1.0 green:0.70 blue:0.25 alpha:1.0];
    UIColor *purple = [UIColor colorWithRed:0.75 green:0.55 blue:1.0 alpha:1.0];

    if (_preset == FPSOverlayPresetNeon) {
        cyan = [UIColor colorWithRed:0.18 green:0.98 blue:1.0 alpha:1.0];
        green = [UIColor colorWithRed:0.25 green:1.0 blue:0.75 alpha:1.0];
        pink = [UIColor colorWithRed:1.0 green:0.45 blue:0.80 alpha:1.0];
        orange = [UIColor colorWithRed:1.0 green:0.75 blue:0.30 alpha:1.0];
        purple = [UIColor colorWithRed:0.68 green:0.55 blue:1.0 alpha:1.0];
    } else if (_preset == FPSOverlayPresetPerformance) {
        cyan = [UIColor colorWithRed:0.30 green:0.88 blue:1.0 alpha:1.0];
        green = [UIColor colorWithRed:0.30 green:0.98 blue:0.50 alpha:1.0];
    }

    [styled addAttribute:NSForegroundColorAttributeName value:white range:NSMakeRange(0, [plain length])];

    NSRange r;
    r = [plain rangeOfString:@"FPS"]; if (r.location != NSNotFound) [styled addAttribute:NSForegroundColorAttributeName value:cyan range:r];
    r = [plain rangeOfString:@"CPU"]; if (r.location != NSNotFound) [styled addAttribute:NSForegroundColorAttributeName value:cyan range:r];
    r = [plain rangeOfString:@"GPU"]; if (r.location != NSNotFound) [styled addAttribute:NSForegroundColorAttributeName value:green range:r];
    r = [plain rangeOfString:@"RAM"]; if (r.location != NSNotFound) [styled addAttribute:NSForegroundColorAttributeName value:purple range:r];
    r = [plain rangeOfString:@"BATT"]; if (r.location != NSNotFound) [styled addAttribute:NSForegroundColorAttributeName value:pink range:r];
    r = [plain rangeOfString:@"FT"]; if (r.location != NSNotFound) [styled addAttribute:NSForegroundColorAttributeName value:orange range:r];
    r = [plain rangeOfString:@"HZ"]; if (r.location != NSNotFound) [styled addAttribute:NSForegroundColorAttributeName value:purple range:r];
    r = [plain rangeOfString:@"Thermal State:"]; if (r.location != NSNotFound) [styled addAttribute:NSForegroundColorAttributeName value:orange range:r];
    r = [plain rangeOfString:graph options:NSBackwardsSearch range:NSMakeRange(0, [plain length])];
    if (r.location != NSNotFound) [styled addAttribute:NSForegroundColorAttributeName value:green range:r];

    _label.attributedText = styled;
    [self positionLabelForWindow:_hostWindow];
}

#pragma mark - Window / start

- (void)batteryNotification:(NSNotification *)notification
{
    [self updateBatteryReading];
}

- (void)batteryTimerTick:(NSTimer *)timer
{
    [self updateBatteryReading];
}

- (void)refreshWindowTimer:(NSTimer *)timer
{
    [self sampleFPS];
    [self refreshWindow];
}

- (void)sampleFPS
{
    CFTimeInterval now = CACurrentMediaTime();
    if (_lastFPSSampleTime == 0.0) {
        _lastFPSSampleTime = now;
        _lastMetalPresentedFrames = gMetalPresentedFrames;
        return;
    }

    CFTimeInterval elapsed = now - _lastFPSSampleTime;
    if (elapsed < 0.25) return;

    uint64_t currentFrames = gMetalPresentedFrames;
    uint64_t deltaFrames = currentFrames - _lastMetalPresentedFrames;
    double metalFPS = (double)deltaFrames / elapsed;

    _lastMetalPresentedFrames = currentFrames;
    _lastFPSSampleTime = now;

    if (deltaFrames > 0) {
        if (metalFPS > 0.0 && metalFPS < 240.0) {
            _measuredFPS = metalFPS;
            _hasMetalFPS = YES;
        }
    } else if (_hasMetalFPS) {
        _measuredFPS = 0.0;
    }

    if (!_hasMetalFPS) {
        [self updateLabel];
    } else {
        [self appendFPSHistory:_measuredFPS];
        [self updateLabel];
    }
}

- (void)appendFPSHistory:(double)fps
{
    if (fps <= 0.0 || fps >= 240.0) return;

    if (_historyCount < FPS_HISTORY_SIZE) {
        _fpsHistory[_historyCount++] = fps;
    } else {
        memmove(&_fpsHistory[0], &_fpsHistory[1], sizeof(double) * (FPS_HISTORY_SIZE - 1));
        _fpsHistory[FPS_HISTORY_SIZE - 1] = fps;
    }
}

- (void)refreshWindow
{
    UIWindow *window = [self findGameWindow];
    if (!window) return;

    if (_hostWindow != window || _containerView.superview != window) {
        [self createOverlayOnWindow:window];
    } else {
        _containerView.hidden = _hidden;
        _containerView.alpha = _hidden ? 0.0 : 1.0;
        [window bringSubviewToFront:_containerView];
        _label.font = [UIFont monospacedDigitSystemFontOfSize:[self fontSizeForWindow:window] weight:UIFontWeightSemibold];
    }

    if (!_displayLink) {
        _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(frameTick:)];
        [_displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
}

- (void)start
{
    if (_started) {
        [self updateBatteryReading];
        [self refreshWindow];
        return;
    }

    _started = YES;
    [UIDevice currentDevice].batteryMonitoringEnabled = YES;
    [self updateBatteryReading];

    _batteryTimer = [NSTimer scheduledTimerWithTimeInterval:BATTERY_SAMPLE_INTERVAL
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
                                             selector:@selector(batteryNotification:)
                                                 name:UIDeviceBatteryLevelDidChangeNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(batteryNotification:)
                                                 name:UIDeviceBatteryStateDidChangeNotification
                                               object:nil];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        [self refreshWindow];

        if (!self->_refreshTimer) {
            self->_refreshTimer = [NSTimer scheduledTimerWithTimeInterval:OVERLAY_REFRESH_INTERVAL
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
    if (_hasMetalFPS) return;

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
        _measuredFPS = fps;
        [self appendFPSHistory:fps];
        [self updateLabel];
    }

    _frameCount = 0;
    _lastTimestamp = link.timestamp;
}

@end

#pragma mark - Initialization

__attribute__((constructor))
static void FPSOverlayInit(void)
{
    FPSOverlayInstallMetalFrameHook();

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
