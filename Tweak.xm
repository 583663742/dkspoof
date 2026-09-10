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

static BOOL DKSpoofEnabled(void) {
    return [DKDefaults() boolForKey:kKeyEnabled];
}

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

// 统一的伪造回调派发
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
    if (DKSpoofEnabled()) {
        CLLocation *fake = DKFakeLocation();
        if (fake) {
            return fake;
        }
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
        if (DKSpoofCoordinate(&coord)) {
            return coord;
        }
    }
    return %orig;
}

%end
