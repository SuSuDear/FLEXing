//
//  FLEXClassHeaderViewController.m
//  FLEX
//

#import "FLEXClassHeaderViewController.h"
#import "FLEXClassHeaderGenerator.h"

@interface FLEXClassHeaderViewController () <UISearchBarDelegate>
@property (nonatomic) Class targetClass;
@property (nonatomic) UITextView *textView;
@property (nonatomic) UISearchBar *searchBar;
@property (nonatomic, copy) NSString *headerText;
@property (nonatomic) CGFloat fontSize;
@end

@implementation FLEXClassHeaderViewController

- (instancetype)initWithClass:(Class)cls {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _targetClass = cls;
        _fontSize = 12.0;
        _headerText = [FLEXClassHeaderGenerator headerForClass:cls];
        self.title = NSStringFromClass(cls) ?: @"Header";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.searchBar = [UISearchBar new];
    self.searchBar.placeholder = @"Search header contents…";
    self.searchBar.delegate = self;
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;

    self.textView = [UITextView new];
    self.textView.editable = NO;
    self.textView.alwaysBounceVertical = YES;
    self.textView.text = self.headerText;
    self.textView.translatesAutoresizingMaskIntoConstraints = NO;
    [self updateFont];

    if (@available(iOS 13.0, *)) {
        self.view.backgroundColor = UIColor.systemBackgroundColor;
        self.textView.backgroundColor = UIColor.systemBackgroundColor;
        self.textView.textColor = UIColor.labelColor;
    } else {
        self.view.backgroundColor = UIColor.whiteColor;
        self.textView.backgroundColor = UIColor.whiteColor;
        self.textView.textColor = UIColor.blackColor;
    }

    [self.view addSubview:self.searchBar];
    [self.view addSubview:self.textView];

    NSArray<NSLayoutConstraint *> *edgeConstraints = nil;
    if (@available(iOS 11.0, *)) {
        UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
        edgeConstraints = @[
            [self.searchBar.topAnchor constraintEqualToAnchor:guide.topAnchor],
            [self.searchBar.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
            [self.searchBar.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
            [self.textView.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor],
            [self.textView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor],
            [self.textView.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor],
            [self.textView.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor],
        ];
    } else {
        edgeConstraints = @[
            [self.searchBar.topAnchor constraintEqualToAnchor:self.topLayoutGuide.bottomAnchor],
            [self.searchBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [self.searchBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
            [self.textView.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor],
            [self.textView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
            [self.textView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
            [self.textView.bottomAnchor constraintEqualToAnchor:self.bottomLayoutGuide.topAnchor],
        ];
    }
    [NSLayoutConstraint activateConstraints:edgeConstraints];

    UIBarButtonItem *font = [[UIBarButtonItem alloc] initWithTitle:@"Font" style:UIBarButtonItemStylePlain target:self action:@selector(fontPressed:)];
    UIBarButtonItem *copy = [[UIBarButtonItem alloc] initWithTitle:@"Copy" style:UIBarButtonItemStylePlain target:self action:@selector(copyPressed:)];
    UIBarButtonItem *share = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(sharePressed:)];
    self.navigationItem.rightBarButtonItems = @[share, copy, font];
}

- (void)updateFont {
    if (@available(iOS 13.0, *)) {
        self.textView.font = [UIFont monospacedSystemFontOfSize:self.fontSize weight:UIFontWeightRegular];
    } else {
        self.textView.font = [UIFont fontWithName:@"Menlo" size:self.fontSize] ?: [UIFont systemFontOfSize:self.fontSize];
    }
}

- (void)fontPressed:(UIBarButtonItem *)sender {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Font Size" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"Small" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        self.fontSize = 10.0; [self updateFont];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Medium" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        self.fontSize = 12.0; [self updateFont];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Large" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        self.fontSize = 15.0; [self updateFont];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    alert.popoverPresentationController.barButtonItem = sender;
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)copyPressed:(id)sender {
    UIPasteboard.generalPasteboard.string = self.headerText;
}

- (void)sharePressed:(UIBarButtonItem *)sender {
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[self.headerText] applicationActivities:nil];
    activity.popoverPresentationController.barButtonItem = sender;
    [self presentViewController:activity animated:YES completion:nil];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if (!searchText.length) {
        self.textView.text = self.headerText;
        return;
    }

    NSRange range = [self.headerText rangeOfString:searchText options:NSCaseInsensitiveSearch];
    self.textView.text = self.headerText;
    if (range.location != NSNotFound) {
        [self.textView scrollRangeToVisible:range];
        self.textView.selectedRange = range;
    }
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

@end
