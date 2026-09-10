// DKSpoof v2 - DingTalk 虚拟定位（三指双击唤出 + 地图选点面板）
// 唤出方式：三指双击（同 FakeTools）

#import <CoreLocation/CoreLocation.h>
#import <Foundation/Foundation.h>
#import <MapKit/MapKit.h>
#import <UIKit/UIKit.h>

// ============ 配置存储 ============
static NSString * const kSuite        = @"group.dkspoof.config";
static NSString * const kKeyEnabled   = @"LocationSpoofingEnabled";
static NSString * const kKeyLat       = @"SpoofLatitude";
static NSString * const kKeyLon       = @"SpoofLongitude";
static NSString * const kKeyAlt       = @"SpoofAltitude";
static NSString * const kKeyAltOn     = @"AltitudeSpoofingEnabled";

NSUserDefaults *DKDefaults(void) {
    static NSUserDefaults *d = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        d = [[NSUserDefaults alloc] initWithSuiteName:kSuite];
        if (!d) d = [NSUserDefaults standardUserDefaults];
    });
    return d;
}

BOOL DKSpoofEnabled(void) { return [DKDefaults() boolForKey:kKeyEnabled]; }

BOOL DKSpoofCoordinate(CLLocationCoordinate2D *outCoord) {
    NSUserDefaults *d = DKDefaults();
    double lat = [d doubleForKey:kKeyLat];
    double lon = [d doubleForKey:kKeyLon];
    if (lat == 0.0 && lon == 0.0) return NO;
    CLLocationCoordinate2D c = CLLocationCoordinate2DMake(lat, lon);
    if (!CLLocationCoordinate2DIsValid(c)) return NO;
    if (outCoord) *outCoord = c;
    return YES;
}

CLLocation *DKFakeLocation(void) {
    CLLocationCoordinate2D coord;
    if (!DKSpoofCoordinate(&coord)) return nil;
    NSUserDefaults *d = DKDefaults();
    double alt = [d boolForKey:kKeyAltOn] ? [d doubleForKey:kKeyAlt] : 0.0;
    return [[CLLocation alloc] initWithCoordinate:coord
                                        altitude:alt
                              horizontalAccuracy:5.0
                                verticalAccuracy:5.0
                                          course:0.0
                                           speed:0.0
                                       timestamp:[NSDate date]];
}

static void DKDeliverFakeLocation(CLLocationManager *mgr) {
    CLLocation *fake = DKFakeLocation();
    if (!fake) return;
    id delegate = [mgr delegate];
    if (delegate && [delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
        [delegate locationManager:mgr didUpdateLocations:@[fake]];
    }
}

// ============ 活动 CLLocationManager 追踪（用于实时刷新）============
// 记录所有被创建的 manager，改坐标后可主动推送新位置
static NSHashTable *DKActiveManagers(void) {
    static NSHashTable *t = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        t = [NSHashTable weakObjectsHashTable];
    });
    return t;
}

// 主动刷新：开关/坐标变化时调用
// 开 → 推送伪造位置；关 → 重启定位恢复真实
void DKRefreshAllManagers(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSArray *all = [DKActiveManagers() allObjects];
        BOOL spoof = DKSpoofEnabled();
        for (CLLocationManager *mgr in all) {
            if (spoof) {
                DKDeliverFakeLocation(mgr);          // 开：立即推送伪造位置
            } else {
                [mgr stopUpdatingLocation];          // 关：重启定位，走原生 → 真实
                [mgr startUpdatingLocation];
            }
        }
    });
}

// ============ Hook CLLocationManager ============
%hook CLLocationManager

- (instancetype)init {
    id r = %orig;
    if (r) [DKActiveManagers() addObject:r];
    return r;
}

- (CLLocation *)location {
    if (DKSpoofEnabled()) {
        CLLocation *fake = DKFakeLocation();
        if (fake) return fake;
    }
    return %orig;
}

- (void)startUpdatingLocation {
    if (DKSpoofEnabled() && DKFakeLocation()) {
        DKDeliverFakeLocation(self);
        return;
    }
    %orig;
}

- (void)requestLocation {
    if (DKSpoofEnabled() && DKFakeLocation()) {
        DKDeliverFakeLocation(self);
        return;
    }
    %orig;
}

- (void)startMonitoringSignificantLocationChanges {
    if (DKSpoofEnabled() && DKFakeLocation()) {
        DKDeliverFakeLocation(self);
        return;
    }
    %orig;
}

%end

// ============ Hook CLLocation ============
%hook CLLocation
- (CLLocationCoordinate2D)coordinate {
    if (DKSpoofEnabled()) {
        CLLocationCoordinate2D coord = {0, 0};
        if (DKSpoofCoordinate(&coord)) return coord;
    }
    return %orig;
}
%end

// ============ 三指双击手势安装 ============
extern void DKSetupGestureOnWindow(UIWindow *window);

%hook UIWindow
- (void)makeKeyAndVisible {
    %orig;
    DKSetupGestureOnWindow(self);
}
%end

// dylib 加载后延迟安装（兜底：对已存在的 keyWindow）
%ctor {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *key = nil;
        if (@available(iOS 13.0, *)) {
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if ([scene isKindOfClass:[UIWindowScene class]]) {
                    for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                        if (w.isKeyWindow) { key = w; break; }
                    }
                }
                if (key) break;
            }
        }
        if (!key) key = [UIApplication sharedApplication].keyWindow;
        if (key) DKSetupGestureOnWindow(key);
    });
}
