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

// ============ Hook CLLocationManager ============
%hook CLLocationManager

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

// ============ 三指双击手势安装（由 SpoofPanel.mm 实现）============
extern void DKSetupGestureOnWindow(UIWindow *window);
extern void DKShowPanel(void);

%hook UIWindow
- (void)makeKeyAndVisible {
    %orig;
    DKSetupGestureOnWindow(self);
}
%end

%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    UIWindow *kw = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                    if (w.isKeyWindow) { kw = w; break; }
                }
            }
            if (kw) break;
        }
    }
    if (!kw) kw = [UIApplication sharedApplication].keyWindow;
    if (kw) DKSetupGestureOnWindow(kw);
}
%end
