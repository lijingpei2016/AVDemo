//
//  AppDelegate.m
//  AVDemo
//
//  Created by LJP on 2022/4/21.
//

#import "AppDelegate.h"
#import "ViewController.h"

@interface AppDelegate ()

@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    
    CGRect re = [UIScreen mainScreen].bounds;
    self.window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, re.size.width, re.size.height)];
    ViewController *vc = [[ViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];
    
    return YES;
}


@end
