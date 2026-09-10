// DKSpoof v2 - 位置模拟面板（严格照 FakeTools 结构复刻）
// 结构：搜索框 + [历史记录][输入位置][输入海拔] + 地图 + 坐标浮层 + 两个开关 + 确认位置
// 唤出：三指双击

#import <UIKit/UIKit.h>
#import <MapKit/MapKit.h>
#import <CoreLocation/CoreLocation.h>

extern NSUserDefaults *DKDefaults(void);
extern BOOL DKSpoofEnabled(void);
extern BOOL DKSpoofCoordinate(CLLocationCoordinate2D *outCoord);
extern void DKRefreshAllManagers(void);   // 改坐标后实时推送

static NSString * const kKeyEnabled = @"LocationSpoofingEnabled";
static NSString * const kKeyLat     = @"SpoofLatitude";
static NSString * const kKeyLon     = @"SpoofLongitude";
static NSString * const kKeyAlt     = @"SpoofAltitude";
static NSString * const kKeyAltOn   = @"AltitudeSpoofingEnabled";
static NSString * const kKeySaved   = @"SavedLocations";
static NSString * const kKeyHistory = @"LocationHistory";

#pragma mark - 记录模型

@interface DKPlace : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) double lat;
@property (nonatomic, assign) double lon;
@end
@implementation DKPlace
- (NSDictionary *)dict { return @{@"name": self.name ?: @"", @"lat": @(self.lat), @"lon": @(self.lon)}; }
+ (instancetype)fromDict:(NSDictionary *)d {
    DKPlace *p = [DKPlace new];
    p.name = d[@"name"] ?: @"";
    p.lat = [d[@"lat"] doubleValue];
    p.lon = [d[@"lon"] doubleValue];
    return p;
}
@end

static NSArray<DKPlace *> *DKLoadPlaces(NSString *key) {
    NSArray *arr = [DKDefaults() arrayForKey:key];
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *d in arr) {
        if ([d isKindOfClass:[NSDictionary class]]) [out addObject:[DKPlace fromDict:d]];
    }
    return out;
}
static void DKSavePlaceTo(NSString *key, DKPlace *place) {
    NSMutableArray *arr = [NSMutableArray array];
    for (DKPlace *p in DKLoadPlaces(key)) [arr addObject:[p dict]];
    [arr insertObject:[place dict] atIndex:0];
    if (arr.count > 50) [arr removeObjectsInRange:NSMakeRange(50, arr.count - 50)];
    [DKDefaults() setObject:arr forKey:key];
    [DKDefaults() synchronize];
}

#pragma mark - 位置历史

@interface DKHistoryVC : UITableViewController
@property (nonatomic, strong) NSArray<DKPlace *> *items;
@property (nonatomic, copy) void (^onPick)(DKPlace *p);
@end
@implementation DKHistoryVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"位置历史";
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:self action:@selector(closeTapped)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemTrash target:self action:@selector(clearTapped)];
    self.items = DKLoadPlaces(kKeyHistory);
}
- (void)closeTapped { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)clearTapped {
    [DKDefaults() setObject:@[] forKey:kKeyHistory];
    [DKDefaults() synchronize];
    self.items = @[];
    [self.tableView reloadData];
}
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s { return self.items.count; }
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:@"h"];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"h"];
    DKPlace *p = self.items[ip.row];
    c.textLabel.text = p.name.length ? p.name : [NSString stringWithFormat:@"%.6f, %.6f", p.lat, p.lon];
    c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return c;
}
- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (self.onPick) self.onPick(self.items[ip.row]);
    [self dismissViewControllerAnimated:YES completion:nil];
}
@end

#pragma mark - 主面板

@interface DKPanelVC : UIViewController <MKMapViewDelegate, UISearchBarDelegate>
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) MKMapView *mapView;
@property (nonatomic, strong) UIView *infoCard;
@property (nonatomic, strong) UILabel *coordLabel;
@property (nonatomic, strong) UISwitch *locationSwitch;
@property (nonatomic, strong) UISwitch *altitudeSwitch;
@property (nonatomic, strong) MKPointAnnotation *pin;
@property (nonatomic, assign) CLLocationCoordinate2D picked;
@property (nonatomic, assign) BOOL hasPicked;
@end

@implementation DKPanelVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    CGFloat W = self.view.bounds.size.width;
    CGFloat H = self.view.bounds.size.height;

    // ---- 顶部标题栏 ----
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, W, 56)];
    title.text = @"位置模拟";
    title.font = [UIFont boldSystemFontOfSize:18];
    title.textAlignment = NSTextAlignmentCenter;
    title.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:title];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(W - 52, 12, 40, 32);
    [close setTitle:@"✕" forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:22];
    [close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    close.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [self.view addSubview:close];

    // ---- 搜索框 ----
    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 56, W, 50)];
    self.searchBar.delegate = self;
    self.searchBar.placeholder = @"搜索地址或地点";
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:self.searchBar];

    // ---- 三个按钮：历史记录 | 输入位置 | 输入海拔 ----
    UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[@"历史记录", @"输入位置", @"输入海拔"]];
    seg.frame = CGRectMake(20, 112, W - 40, 36);
    seg.selectedSegmentIndex = -1;
    [seg addTarget:self action:@selector(segChanged:) forControlEvents:UIControlEventValueChanged];
    seg.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:seg];

    // ---- 地图 ----
    CGFloat mapTop = 160;
    CGFloat mapBottomMargin = 140;
    self.mapView = [[MKMapView alloc] initWithFrame:CGRectMake(12, mapTop, W - 24, H - mapTop - mapBottomMargin)];
    self.mapView.delegate = self;
    self.mapView.layer.cornerRadius = 12;
    self.mapView.clipsToBounds = YES;
    self.mapView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.mapView];

    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(mapLongPressed:)];
    lp.minimumPressDuration = 0.35;
    [self.mapView addGestureRecognizer:lp];

    // ---- 坐标浮层（地图左上）----
    self.infoCard = [[UIView alloc] initWithFrame:CGRectMake(24, mapTop + 12, 200, 60)];
    self.infoCard.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.92];
    self.infoCard.layer.cornerRadius = 8;
    [self.view addSubview:self.infoCard];
    self.coordLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 6, 180, 48)];
    self.coordLabel.numberOfLines = 2;
    self.coordLabel.font = [UIFont systemFontOfSize:13];
    self.coordLabel.textColor = [UIColor blackColor];
    [self.infoCard addSubview:self.coordLabel];

    // ---- 两个开关：位置模拟 | 海拔模拟 ----
    CGFloat swY = H - 118;
    UILabel *locIcon = [[UILabel alloc] initWithFrame:CGRectMake(W/2 - 110, swY, 30, 30)];
    locIcon.text = @"➤";
    locIcon.font = [UIFont systemFontOfSize:22];
    locIcon.textColor = [UIColor systemBlueColor];
    locIcon.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin;
    [self.view addSubview:locIcon];

    self.locationSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(W/2 - 70, swY, 51, 31)];
    self.locationSwitch.on = DKSpoofEnabled();
    [self.locationSwitch addTarget:self action:@selector(locSwitchChanged) forControlEvents:UIControlEventValueChanged];
    self.locationSwitch.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin;
    [self.view addSubview:self.locationSwitch];

    UILabel *altIcon = [[UILabel alloc] initWithFrame:CGRectMake(W/2 + 20, swY, 30, 30)];
    altIcon.text = @"⛰";
    altIcon.font = [UIFont systemFontOfSize:20];
    altIcon.textColor = [UIColor systemGrayColor];
    altIcon.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin;
    [self.view addSubview:altIcon];

    self.altitudeSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(W/2 + 55, swY, 51, 31)];
    self.altitudeSwitch.on = [DKDefaults() boolForKey:kKeyAltOn];
    [self.altitudeSwitch addTarget:self action:@selector(altSwitchChanged) forControlEvents:UIControlEventValueChanged];
    self.altitudeSwitch.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin;
    [self.view addSubview:self.altitudeSwitch];

    UILabel *locText = [[UILabel alloc] initWithFrame:CGRectMake(W/2 - 110, swY + 32, 100, 20)];
    locText.text = @"位置模拟";
    locText.font = [UIFont systemFontOfSize:13];
    locText.textAlignment = NSTextAlignmentCenter;
    locText.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin;
    [self.view addSubview:locText];

    UILabel *altText = [[UILabel alloc] initWithFrame:CGRectMake(W/2 + 10, swY + 32, 100, 20)];
    altText.text = @"海拔模拟";
    altText.font = [UIFont systemFontOfSize:13];
    altText.textAlignment = NSTextAlignmentCenter;
    altText.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin;
    [self.view addSubview:altText];

    // ---- 确认位置 大按钮 ----
    UIButton *confirm = [UIButton buttonWithType:UIButtonTypeSystem];
    confirm.frame = CGRectMake(20, H - 66, W - 40, 50);
    [confirm setTitle:@"确认位置" forState:UIControlStateNormal];
    confirm.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    [confirm setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    confirm.backgroundColor = [UIColor systemBlueColor];
    confirm.layer.cornerRadius = 10;
    [confirm addTarget:self action:@selector(confirmTapped) forControlEvents:UIControlEventTouchUpInside];
    confirm.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleTopMargin;
    [self.view addSubview:confirm];

    // ---- 初始化地图位置 ----
    CLLocationCoordinate2D init = CLLocationCoordinate2DMake(39.9042, 116.4074);
    if (DKSpoofCoordinate(&init)) {
        self.picked = init;
        self.hasPicked = YES;
        [self dropPin:init title:@"已保存的位置"];
    } else {
        init = CLLocationCoordinate2DMake(39.9042, 116.4074);
    }
    [self.mapView setRegion:MKCoordinateRegionMakeWithDistance(init, 1500, 1500) animated:NO];
    [self updateCoordLabel];
}

- (void)closeTapped { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)updateCoordLabel {
    double alt = [DKDefaults() doubleForKey:kKeyAlt];
    if (self.hasPicked) {
        self.coordLabel.text = [NSString stringWithFormat:@"位置: %.4f, %.4f\n海拔: %.2f米",
                                self.picked.latitude, self.picked.longitude, alt];
    } else {
        self.coordLabel.text = @"位置: 未选择\n海拔: --";
    }
}

- (void)dropPin:(CLLocationCoordinate2D)c title:(NSString *)title {
    if (self.pin) [self.mapView removeAnnotation:self.pin];
    self.pin = [MKPointAnnotation new];
    self.pin.coordinate = c;
    self.pin.title = title;
    [self.mapView addAnnotation:self.pin];
}

// 反向地理编码：坐标 → 地址名（异步更新 pin 标题）
- (void)resolveNameForCoord:(CLLocationCoordinate2D)c {
    CLLocation *loc = [[CLLocation alloc] initWithLatitude:c.latitude longitude:c.longitude];
    CLGeocoder *geo = [CLGeocoder new];
    __weak typeof(self) ws = self;
    [geo reverseGeocodeLocation:loc completionHandler:^(NSArray<CLPlacemark *> *placemarks, NSError *error) {
        if (error || placemarks.count == 0) return;
        CLPlacemark *pm = placemarks.firstObject;
        // 拼一个较完整的地址
        NSMutableString *s = [NSMutableString string];
        if (pm.subLocality) [s appendString:pm.subLocality];
        if (pm.name && ![s containsString:pm.name]) { if (s.length) [s appendString:@" "]; [s appendString:pm.name]; }
        if (s.length == 0 && pm.locality) [s appendString:pm.locality];
        NSString *name = s.length ? s : (pm.name ?: @"");
        if (name.length) {
            ws.pin.title = name;
            // 更新地图标注
            [ws.mapView removeAnnotation:ws.pin];
            [ws.mapView addAnnotation:ws.pin];
        }
    }];
}

#pragma mark - 地图选点
- (void)mapLongPressed:(UILongPressGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateBegan) return;
    CGPoint pt = [gr locationInView:self.mapView];
    CLLocationCoordinate2D coord = [self.mapView convertPoint:pt toCoordinateFromView:self.mapView];
    self.picked = coord;
    self.hasPicked = YES;
    [self dropPin:coord title:@"解析中…"];
    [self updateCoordLabel];
    [self resolveNameForCoord:coord];   // ★ 反查真实地点名
}

- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id<MKAnnotation>)annotation {
    if ([annotation isKindOfClass:[MKUserLocation class]]) return nil;
    MKPinAnnotationView *v = (MKPinAnnotationView *)[mapView dequeueReusableAnnotationViewWithIdentifier:@"pin"];
    if (!v) { v = [[MKPinAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:@"pin"]; v.canShowCallout = YES; }
    v.annotation = annotation;
    v.pinTintColor = [UIColor systemRedColor];
    v.animatesDrop = YES;
    return v;
}

#pragma mark - 搜索
- (void)searchBarSearchButtonClicked:(UISearchBar *)sb {
    [sb resignFirstResponder];
    NSString *q = sb.text;
    if (!q.length) return;
    CLGeocoder *geo = [CLGeocoder new];
    [geo geocodeAddressString:q completionHandler:^(NSArray<CLPlacemark *> *placemarks, NSError *error) {
        if (error || placemarks.count == 0) return;
        CLPlacemark *pm = placemarks.firstObject;
        CLLocationCoordinate2D c = pm.location.coordinate;
        self.picked = c;
        self.hasPicked = YES;
        [self dropPin:c title:pm.name ?: q];
        [self.mapView setRegion:MKCoordinateRegionMakeWithDistance(c, 1200, 1200) animated:YES];
        [self updateCoordLabel];
    }];
}

#pragma mark - 三个按钮
- (void)segChanged:(UISegmentedControl *)seg {
    NSInteger idx = seg.selectedSegmentIndex;
    seg.selectedSegmentIndex = -1;
    if (idx == 0) {
        // 历史记录
        DKHistoryVC *h = [DKHistoryVC new];
        __weak typeof(self) ws = self;
        h.onPick = ^(DKPlace *p) {
            CLLocationCoordinate2D c = CLLocationCoordinate2DMake(p.lat, p.lon);
            ws.picked = c; ws.hasPicked = YES;
            [ws dropPin:c title:p.name.length ? p.name : @"已保存的位置"];
            [ws.mapView setRegion:MKCoordinateRegionMakeWithDistance(c, 1200, 1200) animated:YES];
            [ws updateCoordLabel];
        };
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:h];
        nav.modalPresentationStyle = UIModalPresentationPageSheet;
        [self presentViewController:nav animated:YES completion:nil];
    } else if (idx == 1) {
        [self promptInputLocation];
    } else if (idx == 2) {
        [self promptInputAltitude];
    }
}

- (void)promptInputLocation {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"手动输入位置"
        message:@"请输入纬度和经度\n(例如: 39.9042, 116.4074)" preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"纬度 (-90 ~ 90)"; tf.keyboardType = UIKeyboardTypeNumbersAndPunctuation; }];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"经度 (-180 ~ 180)"; tf.keyboardType = UIKeyboardTypeNumbersAndPunctuation; }];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) ws = self;
    [a addAction:[UIAlertAction actionWithTitle:@"确认" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
        double lat = [a.textFields[0].text doubleValue];
        double lon = [a.textFields[1].text doubleValue];
        if (lat == 0 && lon == 0) return;
        CLLocationCoordinate2D c = CLLocationCoordinate2DMake(lat, lon);
        if (!CLLocationCoordinate2DIsValid(c)) return;
        ws.picked = c; ws.hasPicked = YES;
        [ws dropPin:c title:@"手动输入的位置"];
        [ws.mapView setRegion:MKCoordinateRegionMakeWithDistance(c, 1200, 1200) animated:YES];
        [ws updateCoordLabel];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)promptInputAltitude {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"手动输入海拔"
        message:@"请输入海拔高度（单位：米）" preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) { tf.placeholder = @"海拔（单位：米）"; tf.keyboardType = UIKeyboardTypeNumbersAndPunctuation; }];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"确认" style:UIAlertActionStyleDefault handler:^(UIAlertAction *act) {
        double alt = [a.textFields[0].text doubleValue];
        [DKDefaults() setDouble:alt forKey:kKeyAlt];
        [DKDefaults() setBool:YES forKey:kKeyAltOn];
        [DKDefaults() synchronize];
        [self updateCoordLabel];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - 开关
- (void)locSwitchChanged {
    [DKDefaults() setBool:self.locationSwitch.on forKey:kKeyEnabled];
    [DKDefaults() synchronize];
    DKRefreshAllManagers();   // ★ 开=立即模拟，关=立即还原真实定位
}
- (void)altSwitchChanged {
    [DKDefaults() setBool:self.altitudeSwitch.on forKey:kKeyAltOn];
    [DKDefaults() synchronize];
    DKRefreshAllManagers();   // 海拔变化也刷新
}

#pragma mark - 确认位置
- (void)confirmTapped {
    if (!self.hasPicked) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"未选点" message:@"请先在地图上选择位置" preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }
    NSUserDefaults *d = DKDefaults();
    [d setDouble:self.picked.latitude forKey:kKeyLat];
    [d setDouble:self.picked.longitude forKey:kKeyLon];
    [d setBool:YES forKey:kKeyEnabled];
    [d synchronize];

    // ★ 实时生效：主动向所有活动 manager 推送新位置（无需重启钉钉）
    DKRefreshAllManagers();

    // 保存历史（名字先用坐标，反向解析到后更新）
    NSString *name = self.pin.title.length ? self.pin.title : [NSString stringWithFormat:@"%.4f, %.4f", self.picked.latitude, self.picked.longitude];
    DKPlace *p = [DKPlace new];
    p.name = name; p.lat = self.picked.latitude; p.lon = self.picked.longitude;
    DKSavePlaceTo(kKeyHistory, p);

    UIAlertController *ok = [UIAlertController alertControllerWithTitle:@"已生效"
        message:@"虚拟位置已立即生效" preferredStyle:UIAlertControllerStyleAlert];
    [ok addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:ok animated:YES completion:nil];
}

@end

#pragma mark - 三指双击手势

@interface DKGestureHandler : NSObject <UIGestureRecognizerDelegate>
+ (instancetype)shared;
- (void)handle:(UITapGestureRecognizer *)gr;
@end

static UIWindow *DKPanelWindow = nil;

static void DKShowPanel(void) {
    if (DKPanelWindow) return;
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
    if (!key) return;

    DKPanelVC *panel = [DKPanelVC new];
    panel.modalPresentationStyle = UIModalPresentationFormSheet;
    UIViewController *root = key.rootViewController;
    if (!root) return;
    [root presentViewController:panel animated:YES completion:nil];
}

void DKSetupGestureOnWindow(UIWindow *window) {
    if (!window) return;
    for (UIGestureRecognizer *g in window.gestureRecognizers) {
        if ([g isKindOfClass:[UITapGestureRecognizer class]]) {
            UITapGestureRecognizer *t = (UITapGestureRecognizer *)g;
            if (t.numberOfTapsRequired == 2 && t.numberOfTouchesRequired == 3) return;
        }
    }
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:[DKGestureHandler shared] action:@selector(handle:)];
    tap.numberOfTapsRequired = 2;
    tap.numberOfTouchesRequired = 3;
    tap.cancelsTouchesInView = NO;
    tap.delegate = [DKGestureHandler shared];
    window.multipleTouchEnabled = YES;
    [window addGestureRecognizer:tap];
}

@implementation DKGestureHandler
+ (instancetype)shared {
    static DKGestureHandler *h = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ h = [DKGestureHandler new]; });
    return h;
}
- (void)handle:(UITapGestureRecognizer *)gr {
    if (gr.state == UIGestureRecognizerStateEnded) {
        dispatch_async(dispatch_get_main_queue(), ^{ DKShowPanel(); });
    }
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other { return YES; }
@end
