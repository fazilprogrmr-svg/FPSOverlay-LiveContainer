#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#import <mach/mach.h>
#import <sys/sysctl.h>
#import <float.h>
#import <math.h>
#import <string.h>

#define FPS_HISTORY_SIZE 240

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
    if (count < 0) count = 0;
    if (count > FPS_HISTORY_SIZE) count = FPS_HISTORY_SIZE;
    _count = count;
    if (count > 0) {
        memcpy(_values, values, sizeof(double) * count);
    }
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect
{
    if (_count < 2) return;

    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    CGFloat width = CGRectGetWidth(rect);
    CGFloat height = CGRectGetHeight(rect);

    CGContextSetLineWidth(ctx, 0.7);
    CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithWhite:1.0 alpha:0.20].CGColor);

    CGFloat y60 = height * 0.18;
    CGFloat y30 = height * 0.68;

    CGContextMoveToPoint(ctx, 0, y60);
    CGContextAddLineToPoint(ctx, width, y60);
    CGContextMoveToPoint(ctx, 0, y30);
    CGContextAddLineToPoint(ctx, width, y30);
    CGContextStrokePath(ctx);

    CGContextSetLineWidth(ctx, 1.8);
    CGContextSetStrokeColorWithColor(ctx, [UIColor colorWithWhite:1.0 alpha:0.90].CGColor);

    for (NSInteger i = 0; i < _count; i++) {
        double fps = _values[i];
        if (fps < 0.0) fps = 0.0;
        if (fps > 120.0) fps = 120.0;

        CGFloat x = width * ((CGFloat)i / (CGFloat)(FPS_HISTORY_SIZE - 1));
        CGFloat y = height - ((CGFloat)(fps / 120.0) * height);

        if (i == 0) CGContextMoveToPoint(ctx, x, y);
        else CGContextAddLineToPoint(ctx, x, y);
    }

    CGContextStrokePath(ctx);
}

@end

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
        _historyCount = 0;
        _sumFPS = 0.0;
        _sampleCount = 0;
        _minFPS = DBL_MAX;
        _maxFPS = 0.0;
        _lastTimestamp = 0.0;
        _frameCount = 0;
        _started = NO;

        [UIDevice currentDevice].batteryMonitoringEnabled = YES;

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(batteryChanged:)
                                                     name:UIDeviceBatteryLevelDidChangeNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationActive:)
                                                     name:UIApplicationDidBecomeActiveNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_refreshTimer invalidate];
    [_displayLink invalidate];
    [super dealloc];
}

- (void)batteryChanged:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateLabels];
    });
}

- (void)applicationActive:(NSNotification *)notification
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self start];
        [self refreshWindow];
    });
}

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
        @"iPhone12,1": @"iPhone 11", @"iPhone12,3": @"iPhone 11 Pro", @"iPhone12,5": @"iPhone 11 Pro Max",
        @"iPhone13,1": @"iPhone 12 mini", @"iPhone13,2": @"iPhone 12", @"iPhone13,3": @"iPhone 12 Pro", @"iPhone13,4": @"iPhone 12 Pro Max",
        @"iPhone14,4": @"iPhone 13 mini", @"iPhone14,5": @"iPhone 13", @"iPhone14,2": @"iPhone 13 Pro", @"iPhone14,3": @"iPhone 13 Pro Max",
        @"iPhone14,7": @"iPhone 14", @"iPhone14,8": @"iPhone 14 Plus", @"iPhone15,2": @"iPhone 14 Pro", @"iPhone15,3": @"iPhone 14 Pro Max",
        @"iPhone15,4": @"iPhone 15", @"iPhone15,5": @"iPhone 15 Plus", @"iPhone16,1": @"iPhone 15 Pro", @"iPhone16,2": @"iPhone 15 Pro Max",
        @"iPhone17,1": @"iPhone 16 Pro", @"iPhone17,2": @"iPhone 16 Pro Max", @"iPhone17,3": @"iPhone 16", @"iPhone17,4": @"iPhone 16 Plus",
        @"iPhone18,1": @"iPhone 17 Pro", @"iPhone18,2": @"iPhone 17 Pro Max", @"iPhone18,3": @"iPhone 17", @"iPhone18,4": @"iPhone Air"
    };

    NSString *name = [models objectForKey:identifier];
    return name ? name : identifier;
}

- (NSString *)gpuName
{
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) return @"Unknown GPU";
    NSString *name = device.name;
    return name.length ? name : @"Apple GPU";
}

- (NSString *)shortGPUName
{
    NSString *name = [self gpuName];
    if (name.length <= 24) return name;
    if ([name rangeOfString:@"Apple"].location != NSNotFound) return @"Apple GPU";
    return [name substringToIndex:24];
}

- (double)batteryPercentage
{
    float level = UIDevice.currentDevice.batteryLevel;
    return level < 0.0 ? 0.0 : (double)level * 100.0;
}

- (UIWindow *)findGameWindow
{
    if (@available(iOS 13.0, *)) {
        NSSet<UIScene *> *scenes = UIApplication.sharedApplication.connectedScenes;
        for (UIScene *scene in scenes) {
            if (scene.activationState != UISceneActivationStateForegroundActive &&
                scene.activationState != UISceneActivationStateForegroundInactive) continue;
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

- (UILabel *)makeLabel
{
    UILabel *label = [[UILabel alloc] init];
    label.textColor = [UIColor colorWithWhite:1.0 alpha:0.96];
    label.backgroundColor = UIColor.clearColor;
    label.font = [UIFont monospacedDigitSystemFontOfSize:14.0 weight:UIFontWeightSemibold];
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentLeft;
    label.userInteractionEnabled = NO;
    label.layer.shadowColor = UIColor.blackColor.CGColor;
    label.layer.shadowOffset = CGSizeMake(1.0, 1.0);
    label.layer.shadowOpacity = 0.95;
    label.layer.shadowRadius = 2.0;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

- (void)createOverlayOnWindow:(UIWindow *)window
{
    [_leftLabel removeFromSuperview];
    [_rightLabel removeFromSuperview];
    [_deviceLabel removeFromSuperview];
    [_graphView removeFromSuperview];

    _hostWindow = window;
    _leftLabel = [self makeLabel];
    _rightLabel = [self makeLabel];
    _deviceLabel = [self makeLabel];
    _deviceLabel.font = [UIFont monospacedDigitSystemFontOfSize:13.0 weight:UIFontWeightSemibold];

    _graphView = [[FPSGraphView alloc] initWithFrame:CGRectZero];
    _graphView.backgroundColor = UIColor.clearColor;
    _graphView.userInteractionEnabled = NO;
    _graphView.translatesAutoresizingMaskIntoConstraints = NO;

    [window addSubview:_leftLabel];
    [window addSubview:_rightLabel];
    [window addSubview:_deviceLabel];
    [window addSubview:_graphView];

    [NSLayoutConstraint activateConstraints:@[
        [_leftLabel.leadingAnchor constraintEqualToAnchor:window.leadingAnchor constant:20.0],
        [_leftLabel.topAnchor constraintEqualToAnchor:window.safeAreaLayoutGuide.topAnchor constant:8.0],
        [_leftLabel.widthAnchor constraintEqualToConstant:260.0],
        [_leftLabel.heightAnchor constraintEqualToConstant:92.0],

        [_rightLabel.leadingAnchor constraintEqualToAnchor:_leftLabel.trailingAnchor constant:48.0],
        [_rightLabel.topAnchor constraintEqualToAnchor:_leftLabel.topAnchor],
        [_rightLabel.widthAnchor constraintEqualToConstant:220.0],
        [_rightLabel.heightAnchor constraintEqualToConstant:112.0],

        [_deviceLabel.leadingAnchor constraintEqualToAnchor:_rightLabel.leadingAnchor constant:-50.0],
        [_deviceLabel.topAnchor constraintEqualToAnchor:_leftLabel.bottomAnchor constant:10.0],
        [_deviceLabel.widthAnchor constraintEqualToConstant:470.0],
        [_deviceLabel.heightAnchor constraintEqualToConstant:24.0],

        [_graphView.leadingAnchor constraintEqualToAnchor:_deviceLabel.leadingAnchor],
        [_graphView.topAnchor constraintEqualToAnchor:_deviceLabel.bottomAnchor constant:13.0],
        [_graphView.widthAnchor constraintEqualToConstant:430.0],
        [_graphView.heightAnchor constraintEqualToConstant:42.0]
    ]];

    [self updateLabels];
}

- (void)refreshWindow
{
    UIWindow *window = [self findGameWindow];
    if (!window) return;

    if (_hostWindow != window || _leftLabel.superview != window ||
        _rightLabel.superview != window || _deviceLabel.superview != window) {
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

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        [self refreshWindow];
        if (!self->_refreshTimer) {
            self->_refreshTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                                    target:self
                                                                  selector:@selector(refreshWindow)
                                                                  userInfo:nil
                                                                   repeats:YES];
        }
    });
}

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

        _sumFPS += fps;
        _sampleCount++;
        if (fps < _minFPS) _minFPS = fps;
        if (fps > _maxFPS) _maxFPS = fps;

        [self updateLabels];
        if (_graphView) [_graphView setFPSValues:_fpsHistory count:_historyCount];
    }

    _frameCount = 0;
    _lastTimestamp = link.timestamp;
}

- (double)averageFPS
{
    return _sampleCount > 0 ? _sumFPS / (double)_sampleCount : 0.0;
}

- (double)currentFPS
{
    return _historyCount > 0 ? _fpsHistory[_historyCount - 1] : 0.0;
}

- (double)percentile:(double)percent
{
    if (_historyCount < 2) return 0.0;

    double sorted[FPS_HISTORY_SIZE];
    memcpy(sorted, _fpsHistory, sizeof(double) * _historyCount);

    for (NSInteger i = 1; i < _historyCount; i++) {
        double key = sorted[i];
        NSInteger j = i - 1;
        while (j >= 0 && sorted[j] > key) {
            sorted[j + 1] = sorted[j];
            j--;
        }
        sorted[j + 1] = key;
    }

    NSInteger index = (NSInteger)floor((double)(_historyCount - 1) * percent);
    if (index < 0) index = 0;
    if (index >= _historyCount) index = _historyCount - 1;
    return sorted[index];
}

- (double)memoryMB
{
    mach_task_basic_info_data_t info;
    mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
    kern_return_t result = task_info(mach_task_self(), MACH_TASK_BASIC_INFO,
                                     (task_info_t)&info, &count);
    if (result != KERN_SUCCESS) return 0.0;
    return (double)info.resident_size / (1024.0 * 1024.0);
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

- (void)updateLabels
{
    if (!_leftLabel || !_rightLabel || !_deviceLabel) return;

    double fps = [self currentFPS];
    double frameTime = fps > 0.0 ? 1000.0 / fps : 0.0;
    double avg = [self averageFPS];
    double low1 = [self percentile:0.01];
    double low01 = [self percentile:0.001];
    double minFPS = _sampleCount > 0 ? _minFPS : 0.0;
    double maxFPS = _maxFPS;
    double hz = [self refreshRate];
    double ram = [self memoryMB];
    double battery = [self batteryPercentage];

    _leftLabel.text = [NSString stringWithFormat:
        @"FPS : %5.1f\nAVG : %5.1f\n1%% LOW : %4.1f\n0.1%% LOW : %4.1f",
        fps, avg, low1, low01];

    _rightLabel.text = [NSString stringWithFormat:
        @"FT  : %5.2f ms\nMIN : %5.1f\nMAX : %5.1f\nHZ  : %5.0f\nRAM : %5.0f MB",
        frameTime, minFPS, maxFPS, hz, ram];

    _deviceLabel.text = [NSString stringWithFormat:
        @"%@  |  GPU : %@  |  BAT : %3.0f%%",
        [self deviceModel], [self shortGPUName], battery];
}

@end

static FPSOverlayController *gFPSOverlayController = nil;

__attribute__((constructor))
static void FPSOverlayInit(void)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        gFPSOverlayController = [[FPSOverlayController alloc] init];

        if ([[UIApplication sharedApplication] applicationState] == UIApplicationStateActive) {
            [gFPSOverlayController start];
        }
    });
}
