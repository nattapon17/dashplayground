//
//  BuildServerViewController.m
//  dashPlayground
//
//  Created by NATTAPON AIEMLAOR on 3/8/18.
//  Copyright © 2018 dashfoundation. All rights reserved.
//

#import "BuildServerViewController.h"
#import "DialogAlert.h"
#import "SshConnection.h"
#import "DPMasternodeController.h"
#import "ConsoleEventArray.h"
#import "DPBuildServerController.h"


@interface BuildServerViewController ()

@property (strong) IBOutlet NSTextField *buildServerIPText;
@property (strong) IBOutlet NSButton *connectButton;
@property (strong) IBOutlet NSTextField *buildServerStatusText;

@property (atomic) NMSSHSession* buildServerSession;

//Console
@property (strong) ConsoleEventArray * consoleEvents;
@property (strong) IBOutlet NSTextView *consoleTextField;

//Array Controller
@property (strong) IBOutlet NSArrayController *compileArrayController;
@property (strong) IBOutlet NSArrayController *downloadArrayController;
@property (strong) IBOutlet NSArrayController *buildArrayController;

//Table
@property (strong) IBOutlet NSTableView *compileTable;
@property (strong) IBOutlet NSTableView *downloadTable;
@property (strong) IBOutlet NSTableView *buildTable;

@property (atomic) NSInteger downloadTableIndex;

@end

@implementation BuildServerViewController


- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
    [self initialize];
    self.downloadTableIndex = -1;
}

- (void)initialize {
    if([[[DPBuildServerController sharedInstance] getBuildServerIP] length] == 0) {
        self.buildServerIPText.stringValue = @"Unknown";
    }
    else {
        self.buildServerIPText.stringValue = [[DPBuildServerController sharedInstance] getBuildServerIP];
    }
    
    self.consoleEvents = [[ConsoleEventArray alloc] init];
    
    [DPBuildServerController sharedInstance].buildServerViewController = self;
    
//    [self.commitTable setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleNone];
}

- (IBAction)changeServerIP:(id)sender {
    NSString *bsIP = [[DialogAlert sharedInstance] showAlertWithTextField:@"IP Address" message:@"Please input your build server public IP here." placeHolder:@""];
    
    if([bsIP length] > 0) {
        [[DPBuildServerController sharedInstance] setBuildServerIP:bsIP];
        self.buildServerIPText.stringValue = [[DPBuildServerController sharedInstance] getBuildServerIP];
    }
}

- (IBAction)connectBuildServer:(id)sender {
    
    if([self.connectButton.title isEqualToString:@"Connect"]) {
        [[SshConnection sharedInstance] sshInWithKeyPath:[[DPMasternodeController sharedInstance] sshPath] masternodeIp:[[DPBuildServerController sharedInstance] getBuildServerIP] openShell:NO clb:^(BOOL success, NSString *message, NMSSHSession *sshSession) {
            if(sshSession.isAuthorized) {
                
                self.buildServerSession = sshSession;
                
                self.buildServerStatusText.stringValue = @"Connected";
                self.buildServerStatusText.textColor = [NSColor systemGreenColor];
                
                self.connectButton.title = @"Disconnect";
                
                [self addStringEvent:@"Build server connected!"];
                
                [[DPBuildServerController sharedInstance] getAllRepository:sshSession dashClb:^(BOOL success, NSMutableArray *object) {
                    [self showTableContent:object onArrayController:self.downloadArrayController];
                }];
                
                [[DPBuildServerController sharedInstance] getCompileData:sshSession dashClb:^(BOOL success, NSMutableArray *object) {
                    [self showTableContent:object onArrayController:self.compileArrayController];
                }];
            }
            else {
                self.buildServerStatusText.stringValue = @"Disconnected";
                self.buildServerStatusText.textColor = [NSColor redColor];
                
                self.connectButton.title = @"Connect";
                
                [self addStringEvent:@"Failed connecting to build server!"];
            }
        }];
    }
    else {
        [self.buildServerSession disconnect];
        
        self.buildServerSession = nil;
        
        self.connectButton.title = @"Connect";
        
        self.buildServerStatusText.stringValue = @"Disconnected";
        self.buildServerStatusText.textColor = [NSColor redColor];
        
        [self.downloadArrayController setContent:nil];
        [self.buildArrayController setContent:nil];
        [self.compileArrayController setContent:nil];
        
        [self addStringEvent:@"Build server disconnected!"];
    }
}

#pragma mark - Download

- (IBAction)refreshDownload:(id)sender {
    
    if([self.buildServerStatusText.stringValue isEqualToString:@"Connected"]) {
        [self addStringEvent:@"Refreshing download data..."];
        [self.downloadArrayController setContent:nil];
        [[DPBuildServerController sharedInstance] getAllRepository:self.buildServerSession dashClb:^(BOOL success, NSMutableArray *object) {
            [self showTableContent:object onArrayController:self.downloadArrayController];
        }];
    }
}

- (IBAction)pressAddDownload:(id)sender {
    NSInteger row = self.compileTable.selectedRow;
    if(row == -1) {
        return;
    }
    NSManagedObject * object = [self.compileArrayController.arrangedObjects objectAtIndex:row];
    
    [self addStringEvent:@"Creating download link..."];
    
    [[DPBuildServerController sharedInstance] copyDashAppToApache:object buildServerSession:self.buildServerSession];
    
    [self.buildArrayController setContent:nil];
    [[DPBuildServerController sharedInstance] getAllRepository:self.buildServerSession dashClb:^(BOOL success, NSMutableArray *object) {
        [self showTableContent:object onArrayController:self.downloadArrayController];
    }];
}

#pragma mark - Compile

- (IBAction)refreshCompile:(id)sender {
    
    if([self.buildServerStatusText.stringValue isEqualToString:@"Connected"]) {
        [self addStringEvent:@"Refreshing compile data..."];
        [self refreshCompile];
    }
}

- (void)refreshCompile {
    [self.compileArrayController setContent:nil];
    [[DPBuildServerController sharedInstance] getCompileData:self.buildServerSession dashClb:^(BOOL success, NSMutableArray *object) {
        [self showTableContent:object onArrayController:self.compileArrayController];
    }];
}

- (IBAction)compileUpdate:(id)sender {
    NSInteger row = self.compileTable.selectedRow;
    if(row == -1) {
        return;
    }
    NSManagedObject * object = [self.compileArrayController.arrangedObjects objectAtIndex:row];
    
    [[DPBuildServerController sharedInstance] updateRepository:object buildServerSession:self.buildServerSession];
}

- (IBAction)addCompileRepo:(id)sender {
    if([self.buildServerStatusText.stringValue isEqualToString:@"Connected"]) {
        NSString *httpsLinkRepo = [[DialogAlert sharedInstance] showAlertWithTextField:@"Github link" message:@"Please enter repository link." placeHolder:@"(ex. https://github.com/owner/repo)"];
        NSString *branch = [[DialogAlert sharedInstance] showAlertWithTextField:@"Github branch" message:@"Please enter branch." placeHolder:@"(ex. master)"];
        
        if(httpsLinkRepo == nil || branch == nil) return;
        
        [[DPBuildServerController sharedInstance] cloneRepository:self.buildServerSession withGitLink:httpsLinkRepo withBranch:branch type:@"core"];
        
        [self.compileArrayController setContent:nil];
        [[DPBuildServerController sharedInstance] getCompileData:self.buildServerSession dashClb:^(BOOL success, NSMutableArray *object) {
            [self showTableContent:object onArrayController:self.compileArrayController];
        }];
    }
}

- (IBAction)pressSwitchHead:(id)sender {
    NSInteger row = self.compileTable.selectedRow;
    if(row == -1) {
        return;
    }
    NSManagedObject * object = [self.compileArrayController.arrangedObjects objectAtIndex:row];
    
    NSString *commitHead = [[DialogAlert sharedInstance] showAlertWithTextField:@"Commit Head" message:@"Please input commit sha that you want to switch" placeHolder:@""];
    if([commitHead length] > 0) {
        [[DPBuildServerController sharedInstance] switchRepositoryHead:object onHead:commitHead buildServerSession:self.buildServerSession];
    }
}

#pragma mark - Build

- (IBAction)addQueueUpload:(id)sender {
    NSInteger row = self.buildTable.selectedRow;
    if(row == -1) {
        [[DialogAlert sharedInstance] showAlertWithOkButton:@"Error" message:@"Please select version from build table."];
        return;
    }
    NSManagedObject * object = [self.buildArrayController.arrangedObjects objectAtIndex:row];
    [[DPBuildServerController sharedInstance] uploadToS3Bucket:self.buildServerSession gitOwner:[object valueForKey:@"owner"] gitRepo:[object valueForKey:@"repoName"] branch:[object valueForKey:@"branch"] type:[object valueForKey:@"type"] commitHash:[object valueForKey:@"commitSha"]];
}

-(void)addStringEvent:(NSString*)string {
    dispatch_async(dispatch_get_main_queue(), ^{
        if([string length] == 0 || string == nil) return;
        ConsoleEvent * consoleEvent = [ConsoleEvent consoleEventWithString:string];
        [self.consoleEvents addConsoleEvent:consoleEvent];
        [self updateConsole];
    });
}

-(void)updateConsole {
    NSString * consoleEventString = [self.consoleEvents printOut];
    self.consoleTextField.string = consoleEventString;
}

-(void)showTableContent:(NSMutableArray*)contentArray onArrayController:(NSArrayController*)arrayController {
    dispatch_async(dispatch_get_main_queue(), ^{
        for(NSDictionary *dict in contentArray) {
            [arrayController addObject:dict];
        }
        [arrayController rearrangeObjects];
    });
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = self.downloadTable.selectedRow;
    
    if(row == -1) {
        [self.buildArrayController setContent:nil];
        return;
    }
    
    if(self.downloadTableIndex != row || [[self.buildArrayController content] count] == 0) {
        NSManagedObject * object = [self.downloadArrayController.arrangedObjects objectAtIndex:row];
        
        if([[object valueForKey:@"commitInfo"] count] > 0) {
            [self.buildArrayController setContent:nil];
            
            NSArray *commitArray = [object valueForKey:@"commitInfo"];
            for(NSMutableArray *commitObject in commitArray) {
                [commitObject setValue:[object valueForKey:@"type"] forKey:@"type"];
                [commitObject setValue:[object valueForKey:@"owner"] forKey:@"owner"];
                [commitObject setValue:[object valueForKey:@"repo"] forKey:@"repoName"];
                [commitObject setValue:[object valueForKey:@"branch"] forKey:@"branch"];
                [self showTableContent:commitObject onArrayController:self.buildArrayController];
            }
        }
    }
    
    self.downloadTableIndex = row;
}

-(AppDelegate*)appDelegate {
    return [NSApplication sharedApplication].delegate;
}

#pragma mark - Singleton methods

+ (BuildServerViewController *)sharedInstance
{
    static BuildServerViewController *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[BuildServerViewController alloc] init];
        
        // Do any other initialisation stuff here
    });
    return sharedInstance;
}

@end
