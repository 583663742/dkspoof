// DKSpoof - DingTalk 虚拟定位（写死坐标版 / 测试用）
// 默认开启 + 坐标写死：贵州省遵义市中级人民法院
// 注入钉钉后立即生效，无需配置

#import <CoreLocation/CoreLocation.h>
#import <Foundation/Foundation.h>

// ============ 写死的目标坐标（WGS-84，iOS GPS 坐标系）============
static const double kTargetLat = 27.758693;   // 贵州省遵义市中级人民法院
static const double kTargetLon = 106.927534;
static const double kTargetAlt = 850.0;        // 遵义海拔约 850m
static const BOOL   kSpoofOn   = YES;          // 总开关

// ============ 构造伪造定位 ============
static CLLocation *DKFakeLocation(void) {
    if (!kSpoofOn) return nil;
    CLLocationCoordinate2D coord = CLLocationCoordinate2DMake(kTargetLat, kTargetLon);
    if (!CLLocationCoordinate2DIsValid(coord)) return nil;
    return [[CLLocation alloc] initWithCoordinate:coord
                                        altitude:kTargetAlt
                              horizontalAccuracy:5.0
                                verticalAccuracy:5.0
                                          course:0.0
                                           speed:0.0
                                       timestamp:[NSDate date]];
}

// 统一派发伪造定位回调
static void DKDeliverFakeLocation(CLLocationManager *mgr) {
    CLLocation *fake = DKFakeLocation();
    if (!fake) return;
    id delegate = [mgr delegate];
    if (delegate && [delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
        [delegate locationManager:mgr didUpdateLocations:@[fake]];
    }
}

// ============ Hook CLLocationManager ============
%hook CLLocationManager

- (CLLocation *)location {
    CLLocation *fake = DKFakeLocation();
    if (fake) {
        return fake;
    }
    return %orig;
}

- (void)startUpdatingLocation {
    if (DKFakeLocation()) {
        DKDeliverFakeLocation(self);
        return;
    }
    %orig;
}

- (void)requestLocation {
    if (DKFakeLocation()) {
        DKDeliverFakeLocation(self);
        return;
    }
    %orig;
}

- (void)startMonitoringSignificantLocationChanges {
    if (DKFakeLocation()) {
        DKDeliverFakeLocation(self);
        return;
    }
    %orig;
}

%end

// ============ Hook CLLocation ============
%hook CLLocation

- (CLLocationCoordinate2D)coordinate {
    if (kSpoofOn) {
        return CLLocationCoordinate2DMake(kTargetLat, kTargetLon);
    }
    return %orig;
}

%end
