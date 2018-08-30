//
//  BuildServerViewController.h
//  dashPlayground
//
//  Created by NATTAPON AIEMLAOR on 3/8/18.
//  Copyright © 2018 dashfoundation. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "AppDelegate.h"
#import "DPTableView.h"

@interface BuildServerViewController : NSViewController

@property (readonly, strong, nonatomic) AppDelegate *appDelegate;

+(BuildServerViewController*)sharedInstance;

-(void)addStringEvent:(NSString*)string;

- (void)refreshCompile;

@end
