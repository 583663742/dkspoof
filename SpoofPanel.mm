// DKSpoof v2 - UI 实现（三指双击唤出 + 地图选点面板）
// 功能：地图选点 / 搜索地点 / 保存常用 / 历史记录 / 确认修改 / 恢复修改

#import <UIKit/UIKit.h>
#import <MapKit/MapKit.h>
#import <CoreLocation/CoreLocation.h>
#import <objc/runtime.h>

extern NSUserDefaults *DKDefaults(void);
extern BOOL DKSpoofEnabled(void);
extern BOOL DKSpoofCoordinate(CLLocationCoordinate2D *outCoord);

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

#pragma mark - 工具

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

static void DKApplyCoordinate(double lat, double lon, NSString *name) {
    NSUserDefaults *d = DKDefaults();
    [d setDouble:lat forKey:kKeyLat];
    [d setDouble:lon forKey:kKeyLon];
    [d setBool:YES forKey:kKeyEnabled];
    [d synchronize];
    if (name.length) {
        DKPlace *p = [DKPlace new];
        p.name = name; p.lat = lat; p.lon = lon;
        DKSavePlaceTo(kKeyHistory, p);
    }
}

#pragma mark - 地图选点控制器

@interface DKMapPickerVC : UIViewController <MKMapViewDelegate, UISearchBarDelegate>
@property (nonatomic, strong) MKMapView *mapView;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UILabel *coordLabel;
@property (nonatomic, assign) CLLocationCoordinate2D picked;
@property (nonatomic, assign) BOOL hasPicked;
@property (nonatomic, copy) void (^onDone)(double lat, double lon, NSString *name);
@end

@implementation DKMapPickerVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = @"地图选点";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"确认修改"
        style:UIBarButtonItemStyleDone target:self action:@selector(confirmTapped)];

    // 搜索栏
    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 50)];
    self.searchBar.delegate = self;
    self.searchBar.placeholder = @"搜索地点";
    self.searchBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:self.searchBar];

    // 地图
    self.mapView = [[MKMapView alloc] initWithFrame:CGRectMake(0, 50, self.view.bounds.size.width, self.view.bounds.size.height - 50)];
    self.mapView.delegate = self;
    self.mapView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.mapView];

    // 长按选点
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(mapLongPressed:)];
    lp.minimumPressDuration = 0.4;
    [self.mapView addGestureRecognizer:lp];

    // 坐标标签
    self.coordLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, self.view.bounds.size.height - 90, self.view.bounds.size.width - 20, 60)];
    self.coordLabel.numberOfLines = 2;
    self.coordLabel.font = [UIFont systemFontOfSize:13];
    self.coordLabel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.6];
    self.coordLabel.textColor = [UIColor whiteColor];
    self.coordLabel.layer.cornerRadius = 8;
    self.coordLabel.clipsToBounds = YES;
    self.coordLabel.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth;
    self.coordLabel.text = @"长按地图选择位置，或搜索地点";
    [self.view addSubview:self.coordLabel];

    // 初始定位到当前伪造点或默认
    CLLocationCoordinate2D init = CLLocationCoordinate2DMake(27.758693, 106.927534);
    DKSpoofCoordinate(&init);
    [self.mapView setRegion:MKCoordinateRegionMakeWithDistance(init, 2000, 2000) animated:NO];
}

- (void)mapLongPressed:(UILongPressGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateBegan) return;
    CGPoint pt = [gr locationInView:self.mapView];
    CLLocationCoordinate2D coord = [self.mapView convertPoint:pt toCoordinateFromView:self.mapView];
    self.picked = coord;
    self.hasPicked = YES;
    [self.mapView removeAnnotations:self.mapView.annotations];
    MKPointAnnotation *ann = [MKPointAnnotation new];
    ann.coordinate = coord;
    [self.mapView addAnnotation:ann];
    self.coordLabel.text = [NSString stringWithFormat:@"%.6f, %.6f", coord.latitude, coord.longitude];
}

- (void)confirmTapped {
    if (!self.hasPicked) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"未选点" message:@"请先长按地图选择位置" preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }
    if (self.onDone) self.onDone(self.picked.latitude, self.picked.longitude, self.searchBar.text);
    [self.navigationController popViewControllerAnimated:YES];
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
        [self.mapView removeAnnotations:self.mapView.annotations];
        MKPointAnnotation *ann = [MKPointAnnotation new];
        ann.coordinate = c;
        ann.title = pm.name;
        [self.mapView addAnnotation:ann];
        [self.mapView setRegion:MKCoordinateRegionMakeWithDistance(c, 1500, 1500) animated:YES];
        self.coordLabel.text = [NSString stringWithFormat:@"%@\n%.6f, %.6f", pm.name ?: q, c.latitude, c.longitude];
    }];
}

@end

#pragma mark - 主设置面板

@interface DKPanelVC : UITableViewController
@property (nonatomic, strong) NSArray<DKPlace *> *saved;
@property (nonatomic, strong) NSArray<DKPlace *> *history;
@end

@implementation DKPanelVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"虚拟定位";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"关闭" style:UIBarButtonItemStylePlain target:self action:@selector(closeTapped)];
    [self reload];
}

- (void)closeTapped { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)reload {
    self.saved = DKLoadPlaces(kKeySaved);
    self.history = DKLoadPlaces(kKeyHistory);
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 3; }

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    if (s == 0) return @"状态";
    if (s == 1) return @"常用地点";
    return @"历史记录";
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if (s == 0) return 3;
    if (s == 1) return self.saved.count;
    return self.history.count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:@"c"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"c"];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.detailTextLabel.text = nil;

    if (ip.section == 0) {
        if (ip.row == 0) {
            cell.textLabel.text = @"定位伪造";
            cell.accessoryType = DKSpoofEnabled() ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        } else if (ip.row == 1) {
            cell.textLabel.text = @"地图选点";
            cell.detailTextLabel.text = @"长按地图选择位置";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else {
            CLLocationCoordinate2D c = {0,0};
            if (DKSpoofCoordinate(&c))
                cell.detailTextLabel.text = [NSString stringWithFormat:@"当前: %.6f, %.6f", c.latitude, c.longitude];
            else
                cell.detailTextLabel.text = @"当前: 未设置";
            cell.textLabel.text = @"恢复真实定位";
        }
    } else {
        DKPlace *p = (ip.section == 1) ? self.saved[ip.row] : self.history[ip.row];
        cell.textLabel.text = p.name.length ? p.name : [NSString stringWithFormat:@"%.5f, %.5f", p.lat, p.lon];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%.6f, %.6f", p.lat, p.lon];
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];

    if (ip.section == 0) {
        if (ip.row == 0) {
            BOOL en = DKSpoofEnabled();
            [DKDefaults() setBool:!en forKey:kKeyEnabled];
            [DKDefaults() synchronize];
            [self reload];
        } else if (ip.row == 1) {
            DKMapPickerVC *vc = [DKMapPickerVC new];
            __weak typeof(self) weakSelf = self;
            vc.onDone = ^(double lat, double lon, NSString *name) {
                if (name.length) {
                    DKPlace *p = [DKPlace new];
                    p.name = name; p.lat = lat; p.lon = lon;
                    // 保存到常用（长按可改名，此处直接存历史）
                    DKSavePlaceTo(kKeySaved, p);
                }
                [weakSelf reload];
            };
            [self.navigationController pushViewController:vc animated:YES];
        } else {
            // 恢复真实定位
            [DKDefaults() setBool:NO forKey:kKeyEnabled];
            [DKDefaults() synchronize];
            [self reload];
        }
    } else {
        DKPlace *p = (ip.section == 1) ? self.saved[ip.row] : self.history[ip.row];
        DKApplyCoordinate(p.lat, p.lon, p.name);
        [self reload];
    }
}

@end

#pragma mark - 手势 & 入口

// 前置声明（实现见文件末尾）
@interface DKGestureHandler : NSObject <UIGestureRecognizerDelegate>
+ (instancetype)shared;
- (void)handle:(UITapGestureRecognizer *)gr;
@end

static UIWindow *DKPanelWindow = nil;

static void DKOnThreeFingerDoubleTap(void) {
    if (DKPanelWindow) return;  // 已显示
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
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:panel];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;

    UIViewController *root = key.rootViewController;
    if (!root) return;
    [root presentViewController:nav animated:YES completion:nil];
}

void DKSetupGestureOnWindow(UIWindow *window) {
    if (!window) return;
    for (UIGestureRecognizer *g in window.gestureRecognizers) {
        if ([g isKindOfClass:[UITapGestureRecognizer class]]) {
            UITapGestureRecognizer *t = (UITapGestureRecognizer *)g;
            if (t.numberOfTapsRequired == 2 && t.numberOfTouchesRequired == 3) return; // 已安装
        }
    }
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:[DKGestureHandler class] action:@selector(handle:)];
    tap.numberOfTapsRequired = 2;
    tap.numberOfTouchesRequired = 3;
    tap.cancelsTouchesInView = NO;
    tap.delegate = [DKGestureHandler shared];
    window.multipleTouchEnabled = YES;
    [window addGestureRecognizer:tap];
}

#pragma mark - 手势处理器（单例）

@implementation DKGestureHandler
+ (instancetype)shared {
    static DKGestureHandler *h = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ h = [DKGestureHandler new]; });
    return h;
}
- (void)handle:(UITapGestureRecognizer *)gr {
    if (gr.state == UIGestureRecognizerStateEnded) {
        dispatch_async(dispatch_get_main_queue(), ^{ DKOnThreeFingerDoubleTap(); });
    }
}
// 三指双击不干扰其他手势
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}
@end
