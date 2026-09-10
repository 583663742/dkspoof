// DKSpoof - DingTalk 虚拟定位
// 纯 hook 版：读 App Group 共享配置，伪造 CLLocationManager 定位
// 参考 FakeTools 机制（CLLocationManager hook + NSUserDefaults initWithSuiteName）

#import <CoreLocation/CoreLocation.h>
#import <Foundation/Foundation.h>

// ============ 共享配置读取（App Group） ============
static NSString * const kSpoofSuiteName = @"group.dkspoof.config";
static NSString * const kKeyEnabled      = @"LocationSpoofingEnabled";
static NSString * const kKeyLat          = @"SpoofLatitude";
static NSString * const kKeyLon          = @"SpoofLongitude";
static NSString * const kKeyAltEnabled   = @"AltitudeSpoofingEnabled";
static NSString * const kKeyAlt          = @"SpoofAltitude";

static NSUserDefaults *DKDefaults(void) {
    static NSUserDefaults *d = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        d = [[NSUserDefaults alloc] initWithSuiteName:kSpoofSuiteName];
    });
    return d;
}

// 是否开启定位伪造
static BOOL DKSpoofEnabled(void) {
    return [DKDefaults() boolForKey:kKeyEnabled];
}

// 读取伪造坐标；返回 NO 表示无有效坐标
static BOOL DKSpoofCoordinate(CLLocationCoordinate2D *outCoord) {
    NSUserDefaults *d = DKDefaults();
    double lat = [d doubleForKey:kKeyLat];
    double lon = [d doubleForKey:kKeyLon];
    if (lat == 0.0 && lon == 0.0) return NO;
    CLLocationCoordinate2D c = CLLocationCoordinate2DMake(lat, lon);
    if (!CLLocationCoordinate2DIsValid(c)) return NO;
    if (outCoord) *outCoord = c;
    return YES;
}

// 构造伪造成 CLLocation（水平精度 5m，模拟真实 GPS）
static CLLocation *DKFakeLocation(void) {
    CLLocationCoordinate2D coord;
    if (!DKSpoofCoordinate(&coord)) return nil;
    NSUserDefaults *d = DKDefaults();
    BOOL altEnabled = [d boolForKey:kKeyAltEnabled];
    double alt = altEnabled ? [d doubleForKey:kKeyAlt] : 0.0;
    return [[CLLocation alloc] initWithCoordinate:coord
                                        altitude:alt
                              horizontalAccuracy:5.0
                                verticalAccuracy:5.0
                                          course:0.0
                                           speed:0.0
                                       timestamp:[NSDate date]];
}

// ============ Hook CLLocationManager ============
%hook CLLocationManager

// 拦截 location getter：直接返回伪造位置
- (CLLocation *)location {
    if (DKSpoofEnabled()) {
        CLLocation *fake = DKFakeLocation();
        if (fake) return fake;
    }
    return %orig;
}

// 拦截启动定位：改为直接回调伪造位置，不启真实 GPS
- (void)startUpdatingLocation {
    if (!DKSpoofEnabled()) { %orig; return; }
    CLLocation *fake = DKFakeLocation();
    if (!fake) { %orig; return; }
    id delegate = [self delegate];
    if (delegate && [delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
        [delegate locationManager:self didUpdateLocations:@[fake]];
    }
}

// 拦截单次定位请求
- (void)requestLocation {
    if (!DKSpoofEnabled()) { %orig; return; }
    CLLocation *fake = DKFakeLocation();
    if (!fake) { %orig; return; }
    id delegate = [self delegate];
    if (delegate && [delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
        [delegate locationManager:self didUpdateLocations:@[fake]];
    }
}

// 拦截持续定位（显著变化）
- (void)startMonitoringSignificantLocationChanges {
    if (!DKSpoofEnabled()) { %orig; return; }
    CLLocation *fake = DKFakeLocation();
    if (!fake) { %orig; return; }
    id delegate = [self delegate];
    if (delegate && [delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
        [delegate locationManager:self didUpdateLocations:@[fake]];
    }
}

%end

// ============ Hook CLLocation（防止直接读坐标绕过） ============
%hook CLLocation

- (CLLocationCoordinate2D)coordinate {
    static NSUserDefaults *d = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        d = [[NSUserDefaults alloc] initWithSuiteName:kSpoofSuiteName];
    });
    if ([d boolForKey:kKeyEnabled]) {
        CLLocationCoordinate2D coord;
        if (DKSpoofCoordinate(&coord)) return coord;
    }
    return %orig;
}

%end
