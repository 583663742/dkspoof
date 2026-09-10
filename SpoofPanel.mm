// DKSpoof v2 - 位置模拟面板（自研浅蓝风格）
// 唤出：三指双击

#import <UIKit/UIKit.h>
#import <MapKit/MapKit.h>
#import <CoreLocation/CoreLocation.h>

extern NSUserDefaults *DKDefaults(void);
extern BOOL DKSpoofEnabled(void);
extern BOOL DKSpoofCoordinate(CLLocationCoordinate2D *outCoord);
extern void DKRefreshAllManagers(void);

static NSString * const kKeyEnabled = @"LocationSpoofingEnabled";
static NSString * const kKeyLat     = @"SpoofLatitude";
static NSString * const kKeyLon     = @"SpoofLongitude";
static NSString * const kKeyAlt     = @"SpoofAltitude";
static NSString * const kKeyAltOn   = @"AltitudeSpoofingEnabled";
static NSString * const kKeySaved   = @"SavedLocations";
static NSString * const kKeyHistory = @"LocationHistory";

// ===== 配色 =====
#define DK_BG_TOP     [UIColor colorWithRed:0.898 green:0.945 blue:1.0 alpha:1.0]   // #E5F1FF
#define DK_BG_BOTTOM  [UIColor colorWithRed:0.961 green:0.980 blue:1.0 alpha:1.0]   // #F5FAFF
#define DK_CARD_BG    [UIColor whiteColor]
#define DK_ACCENT     [UIColor colorWithRed:0.192 green:0.510 blue:0.965 alpha:1.0] // #3182F6
#define DK_TOGGLE_ON  [UIColor colorWithRed:1.0 green:0.231 blue:0.188 alpha:1.0]   // #FF3B30 红
#define DK_TEXT_MAIN  [UIColor colorWithRed:0.11 green:0.13 blue:0.18 alpha:1.0]
#define DK_TEXT_SUB   [UIColor colorWithRed:0.45 green:0.50 blue:0.58 alpha:1.0]

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
    self.tableView.backgroundColor = DK_BG_BOTTOM;
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
    c.textLabel.textColor = DK_TEXT_MAIN;
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

// 卡片工厂
- (UIView *)makeCard {
    UIView *v = [[UIView alloc] init];
    v.translatesAutoresizingMaskIntoConstraints = NO;
    v.backgroundColor = DK_CARD_BG;
    v.layer.cornerRadius = 16;
    v.layer.shadowColor = [UIColor colorWithRed:0.2 green:0.4 blue:0.7 alpha:0.10].CGColor;
    v.layer.shadowOpacity = 1.0;
    v.layer.shadowRadius = 10;
    v.layer.shadowOffset = CGSizeMake(0, 3);
    return v;
}

// 图标按钮（历史/输入位置/输入海拔）
- (UIButton *)makeToolButton:(NSString *)title icon:(NSString *)icon sel:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.translatesAutoresizingMaskIntoConstraints = NO;
    b.backgroundColor = DK_CARD_BG;
    b.layer.cornerRadius = 14;
    b.layer.shadowColor = [UIColor colorWithRed:0.2 green:0.4 blue:0.7 alpha:0.10].CGColor;
    b.layer.shadowOpacity = 1.0;
    b.layer.shadowRadius = 8;
    b.layer.shadowOffset = CGSizeMake(0, 2);
    // 图标在上，文字在下
    [b setTitle:[NSString stringWithFormat:@"%@\n%@", icon, title] forState:UIControlStateNormal];
    b.titleLabel.numberOfLines = 2;
    b.titleLabel.textAlignment = NSTextAlignmentCenter;
    b.titleLabel.font = [UIFont systemFontOfSize:12];
    [b setTitleColor:DK_TEXT_MAIN forState:UIControlStateNormal];
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // 浅蓝渐变背景
    CAGradientLayer *grad = [CAGradientLayer layer];
    grad.frame = [UIScreen mainScreen].bounds;
    grad.colors = @[(id)DK_BG_TOP.CGColor, (id)DK_BG_BOTTOM.CGColor];
    grad.startPoint = CGPointMake(0.5, 0);
    grad.endPoint = CGPointMake(0.5, 1);
    [self.view.layer insertSublayer:grad atIndex:0];
    self.view.backgroundColor = DK_BG_BOTTOM;

    // ===== 标题：📍 虚拟定位（左对齐）=====
    UILabel *title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"📍 虚拟定位";
    title.font = [UIFont boldSystemFontOfSize:20];
    title.textColor = DK_TEXT_MAIN;
    [self.view addSubview:title];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.translatesAutoresizingMaskIntoConstraints = NO;
    [close setTitle:@"✕" forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightMedium];
    [close setTitleColor:DK_TEXT_SUB forState:UIControlStateNormal];
    [close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:close];

    // ===== 搜索卡片 =====
    UIView *searchCard = [self makeCard];
    [self.view addSubview:searchCard];
    self.searchBar = [[UISearchBar alloc] init];
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.searchBar.delegate = self;
    self.searchBar.placeholder = @"搜索地址或地点";
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.backgroundImage = [[UIImage alloc] init];
    [searchCard addSubview:self.searchBar];

    // ===== 地图卡片 =====
    UIView *mapCard = [self makeCard];
    mapCard.layer.cornerRadius = 18;
    mapCard.clipsToBounds = NO;
    [self.view addSubview:mapCard];

    self.mapView = [[MKMapView alloc] init];
    self.mapView.translatesAutoresizingMaskIntoConstraints = NO;
    self.mapView.delegate = self;
    self.mapView.layer.cornerRadius = 18;
    self.mapView.clipsToBounds = YES;
    [mapCard addSubview:self.mapView];

    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(mapLongPressed:)];
    lp.minimumPressDuration = 0.35;
    [self.mapView addGestureRecognizer:lp];

    // 坐标浮层
    self.infoCard = [[UIView alloc] init];
    self.infoCard.translatesAutoresizingMaskIntoConstraints = NO;
    self.infoCard.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.95];
    self.infoCard.layer.cornerRadius = 10;
    [self.mapView addSubview:self.infoCard];

    self.coordLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 6, 180, 48)];
    self.coordLabel.numberOfLines = 2;
    self.coordLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightMedium];
    self.coordLabel.textColor = DK_TEXT_MAIN;
    [self.infoCard addSubview:self.coordLabel];

    // ===== 三个图标按钮（横排）=====
    UIButton *btnHistory = [self makeToolButton:@"历史" icon:@"🕐" sel:@selector(tapHistory)];
    UIButton *btnInput   = [self makeToolButton:@"输入位置" icon:@"⌨️" sel:@selector(tapInputLocation)];
    UIButton *btnAlt     = [self makeToolButton:@"输入海拔" icon:@"⛰️" sel:@selector(tapInputAltitude)];
    [self.view addSubview:btnHistory];
    [self.view addSubview:btnInput];
    [self.view addSubview:btnAlt];

    // ===== 开关卡片 =====
    UIView *switchCard = [self makeCard];
    [self.view addSubview:switchCard];

    UILabel *locTitle = [[UILabel alloc] init];
    locTitle.translatesAutoresizingMaskIntoConstraints = NO;
    locTitle.text = @"📍 位置模拟";
    locTitle.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    locTitle.textColor = DK_TEXT_MAIN;
    [switchCard addSubview:locTitle];

    self.locationSwitch = [[UISwitch alloc] init];
    self.locationSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    self.locationSwitch.onTintColor = DK_TOGGLE_ON;   // ★ 红色开启
    self.locationSwitch.on = DKSpoofEnabled();
    [self.locationSwitch addTarget:self action:@selector(locSwitchChanged) forControlEvents:UIControlEventValueChanged];
    [switchCard addSubview:self.locationSwitch];

    UIView *divider = [[UIView alloc] init];
    divider.translatesAutoresizingMaskIntoConstraints = NO;
    divider.backgroundColor = [UIColor colorWithWhite:0.9 alpha:1.0];
    [switchCard addSubview:divider];

    UILabel *altTitle = [[UILabel alloc] init];
    altTitle.translatesAutoresizingMaskIntoConstraints = NO;
    altTitle.text = @"⛰️ 海拔模拟";
    altTitle.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    altTitle.textColor = DK_TEXT_MAIN;
    [switchCard addSubview:altTitle];

    self.altitudeSwitch = [[UISwitch alloc] init];
    self.altitudeSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    self.altitudeSwitch.onTintColor = DK_TOGGLE_ON;   // ★ 红色开启
    self.altitudeSwitch.on = [DKDefaults() boolForKey:kKeyAltOn];
    [self.altitudeSwitch addTarget:self action:@selector(altSwitchChanged) forControlEvents:UIControlEventValueChanged];
    [switchCard addSubview:self.altitudeSwitch];

    // ===== 确认按钮 =====
    UIButton *confirm = [UIButton buttonWithType:UIButtonTypeSystem];
    confirm.translatesAutoresizingMaskIntoConstraints = NO;
    [confirm setTitle:@"确认位置" forState:UIControlStateNormal];
    confirm.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    [confirm setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    confirm.backgroundColor = DK_ACCENT;
    confirm.layer.cornerRadius = 14;
    confirm.layer.shadowColor = DK_ACCENT.CGColor;
    confirm.layer.shadowOpacity = 0.35;
    confirm.layer.shadowRadius = 10;
    confirm.layer.shadowOffset = CGSizeMake(0, 4);
    [confirm addTarget:self action:@selector(confirmTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:confirm];

    // ===== 约束 =====
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
        [title.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [title.heightAnchor constraintEqualToConstant:36],
        [close.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [close.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [close.widthAnchor constraintEqualToConstant:40],
        [close.heightAnchor constraintEqualToConstant:36],

        [searchCard.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:10],
        [searchCard.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [searchCard.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [searchCard.heightAnchor constraintEqualToConstant:54],
        [self.searchBar.topAnchor constraintEqualToAnchor:searchCard.topAnchor constant:4],
        [self.searchBar.leadingAnchor constraintEqualToAnchor:searchCard.leadingAnchor constant:4],
        [self.searchBar.trailingAnchor constraintEqualToAnchor:searchCard.trailingAnchor constant:-4],
        [self.searchBar.bottomAnchor constraintEqualToAnchor:searchCard.bottomAnchor constant:-4],

        [mapCard.topAnchor constraintEqualToAnchor:searchCard.bottomAnchor constant:12],
        [mapCard.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [mapCard.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.mapView.topAnchor constraintEqualToAnchor:mapCard.topAnchor],
        [self.mapView.leadingAnchor constraintEqualToAnchor:mapCard.leadingAnchor],
        [self.mapView.trailingAnchor constraintEqualToAnchor:mapCard.trailingAnchor],
        [self.mapView.bottomAnchor constraintEqualToAnchor:mapCard.bottomAnchor],
        [self.infoCard.topAnchor constraintEqualToAnchor:self.mapView.topAnchor constant:10],
        [self.infoCard.leadingAnchor constraintEqualToAnchor:self.mapView.leadingAnchor constant:10],
        [self.infoCard.widthAnchor constraintEqualToConstant:200],
        [self.infoCard.heightAnchor constraintEqualToConstant:58],

        // 三个按钮
        [btnHistory.topAnchor constraintEqualToAnchor:mapCard.bottomAnchor constant:12],
        [btnHistory.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [btnInput.topAnchor constraintEqualToAnchor:btnHistory.topAnchor],
        [btnInput.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [btnAlt.topAnchor constraintEqualToAnchor:btnHistory.topAnchor],
        [btnAlt.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [btnHistory.widthAnchor constraintEqualToAnchor:btnInput.widthAnchor],
        [btnAlt.widthAnchor constraintEqualToAnchor:btnHistory.widthAnchor],
        [btnHistory.heightAnchor constraintEqualToConstant:58],
        [btnInput.heightAnchor constraintEqualToConstant:58],
        [btnAlt.heightAnchor constraintEqualToConstant:58],

        // 开关卡片
        [switchCard.topAnchor constraintEqualToAnchor:btnHistory.bottomAnchor constant:12],
        [switchCard.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [switchCard.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [switchCard.heightAnchor constraintEqualToConstant:112],
        [locTitle.topAnchor constraintEqualToAnchor:switchCard.topAnchor constant:16],
        [locTitle.leadingAnchor constraintEqualToAnchor:switchCard.leadingAnchor constant:18],
        [self.locationSwitch.centerYAnchor constraintEqualToAnchor:locTitle.centerYAnchor],
        [self.locationSwitch.trailingAnchor constraintEqualToAnchor:switchCard.trailingAnchor constant:-16],
        [divider.topAnchor constraintEqualToAnchor:switchCard.centerYAnchor constant:2],
        [divider.leadingAnchor constraintEqualToAnchor:switchCard.leadingAnchor constant:18],
        [divider.trailingAnchor constraintEqualToAnchor:switchCard.trailingAnchor constant:-18],
        [divider.heightAnchor constraintEqualToConstant:1],
        [altTitle.bottomAnchor constraintEqualToAnchor:switchCard.bottomAnchor constant:-18],
        [altTitle.leadingAnchor constraintEqualToAnchor:switchCard.leadingAnchor constant:18],
        [self.altitudeSwitch.centerYAnchor constraintEqualToAnchor:altTitle.centerYAnchor],
        [self.altitudeSwitch.trailingAnchor constraintEqualToAnchor:switchCard.trailingAnchor constant:-16],

        // 地图底部 = 开关卡片顶部
        [mapCard.bottomAnchor constraintEqualToAnchor:btnHistory.topAnchor constant:-12],

        // 确认按钮
        [confirm.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [confirm.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [confirm.topAnchor constraintEqualToAnchor:switchCard.bottomAnchor constant:14],
        [confirm.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-10],
        [confirm.heightAnchor constraintGreaterThanOrEqualToConstant:50],
    ]];

    // 初始化地图位置
    CLLocationCoordinate2D init = CLLocationCoordinate2DMake(39.9042, 116.4074);
    if (DKSpoofCoordinate(&init)) {
        self.picked = init;
        self.hasPicked = YES;
        [self dropPin:init title:@"已保存的位置"];
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

- (void)mapLongPressed:(UILongPressGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateBegan) return;
    CGPoint pt = [gr locationInView:self.mapView];
    CLLocationCoordinate2D coord = [self.mapView convertPoint:pt toCoordinateFromView:self.mapView];
    self.picked = coord;
    self.hasPicked = YES;
    [self dropPin:coord title:@"解析中…"];
    [self updateCoordLabel];
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

// 搜索
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
- (void)tapHistory {
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
}

- (void)tapInputLocation {
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

- (void)tapInputAltitude {
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
    DKRefreshAllManagers();
}
- (void)altSwitchChanged {
    [DKDefaults() setBool:self.altitudeSwitch.on forKey:kKeyAltOn];
    [DKDefaults() synchronize];
    DKRefreshAllManagers();
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
    DKRefreshAllManagers();
    if (self.locationSwitch.on != YES) {
        [self.locationSwitch setOn:YES animated:YES];
    }

    CLLocationCoordinate2D coord = self.picked;
    CLLocation *loc = [[CLLocation alloc] initWithLatitude:coord.latitude longitude:coord.longitude];
    CLGeocoder *geo = [CLGeocoder new];
    __weak typeof(self) ws = self;
    [geo reverseGeocodeLocation:loc completionHandler:^(NSArray<CLPlacemark *> *placemarks, NSError *error) {
        NSString *finalName = nil;
        if (!error && placemarks.count > 0) {
            CLPlacemark *pm = placemarks.firstObject;
            NSMutableString *s = [NSMutableString string];
            if (pm.locality) [s appendString:pm.locality];
            if (pm.subLocality && ![s containsString:pm.subLocality]) [s appendString:pm.subLocality];
            if (pm.name.length && ![s containsString:pm.name]) { if (s.length) [s appendString:@" "]; [s appendString:pm.name]; }
            finalName = s.length ? s : pm.name;
        }
        if (!finalName.length) finalName = [NSString stringWithFormat:@"%.4f, %.4f", coord.latitude, coord.longitude];
        DKPlace *p = [DKPlace new];
        p.name = finalName; p.lat = coord.latitude; p.lon = coord.longitude;
        DKSavePlaceTo(kKeyHistory, p);
        if (ws.pin) ws.pin.title = finalName;
    }];

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
