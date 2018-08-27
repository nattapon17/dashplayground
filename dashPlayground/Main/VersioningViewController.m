//
//  VersioningViewController.m
//  dashPlayground
//
//  Created by NATTAPON AIEMLAOR on 27/7/18.
//  Copyright © 2018 dashfoundation. All rights reserved.
//

#import "VersioningViewController.h"
#import "DPMasternodeController.h"
#import "DPDataStore.h"
#import "ConsoleEventArray.h"
#import <AFNetworking/AFNetworking.h>
#import "DPLocalNodeController.h"
#import "DPVersioningController.h"
#import "MasternodeStateTransformer.h"
#import "DialogAlert.h"

@interface VersioningViewController ()

@property (strong) IBOutlet NSTableView *tableView;
@property (strong) IBOutlet NSArrayController *arrayController;

@property (strong) ConsoleEventArray * consoleEvents;
@property (strong) IBOutlet NSTextView *consoleTextField;

//Core
@property (strong) IBOutlet NSTextField *currentCoreTextField;
@property (strong) IBOutlet NSPopUpButton *versionCoreButton;
@property (strong) IBOutlet NSButton *coreUpdateButton;

//Sentinel
@property (strong) IBOutlet NSTextField *currentSentinelTextField;
@property (strong) IBOutlet NSComboBox *versionSentinelButton;
@property (strong) IBOutlet NSButton *sentinelUpdateButton;

@property (atomic) NSManagedObject* selectedObject;

//Table Column
@property (atomic) BOOL publicIPColumnBool;
@property (atomic) BOOL instanceIDColumnBool;
@property (atomic) BOOL instanceStateColumnBool;
@property (atomic) BOOL chainColumnBool;
@property (atomic) BOOL coreBranchColumnBool;
@property (atomic) BOOL coreHeadColumnBool;
@property (atomic) BOOL sentinelBranchColumnBool;
@property (atomic) BOOL sentinelHeadColumnBool;

@end

@implementation VersioningViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do view setup here.
    [self setUpConsole];
    [self initialize];
    
    [DPVersioningController sharedInstance].versioningViewController = self;
}

-(void)setUpConsole {
    self.consoleEvents = [[ConsoleEventArray alloc] init];
}

- (void)initialize {
//    [self addStringEvent:@"Initializing instances from AWS."];
    NSArray * masternodesArray = [[DPDataStore sharedInstance] allMasternodes];
    for (NSManagedObject * masternode in masternodesArray) {
        [self showTableContent:masternode];
//        [[DPMasternodeController sharedInstance] checkMasternode:masternode];
    }
    
    [self.versionCoreButton removeAllItems];
    [self.versionSentinelButton removeAllItems];
}

- (void)initializeColumnBool {
    _publicIPColumnBool = NO;
    _instanceIDColumnBool = NO;
    _instanceStateColumnBool = NO;
    _chainColumnBool = NO;
    _coreBranchColumnBool = NO;
    _coreHeadColumnBool = NO;
    _sentinelBranchColumnBool = NO;
    _sentinelHeadColumnBool = NO;
}

-(void)showTableContent:(NSManagedObject*)object
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.arrayController addObject:object];
        [self.arrayController rearrangeObjects];
    });
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

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = self.tableView.selectedRow;
    if(row == -1) {
        self.coreUpdateButton.enabled = false;
        self.currentCoreTextField.stringValue = @"";
        [self.versionCoreButton removeAllItems];
        
        self.sentinelUpdateButton.enabled = false;
        self.currentSentinelTextField.stringValue = @"";
        return;
    }
    NSManagedObject * object = [self.arrayController.arrangedObjects objectAtIndex:row];
    [self addStringEvent:@"Fetching information."];
    self.selectedObject = object;
    
    //Show current git head
    if([[object valueForKey:@"gitCommit"] length] > 0) {
        self.currentCoreTextField.stringValue = [object valueForKey:@"gitCommit"];
        self.coreUpdateButton.enabled = true;
    }
    else {
        self.coreUpdateButton.enabled = false;
        self.currentCoreTextField.stringValue = @"";
    }
    
    if([[object valueForKey:@"sentinelGitCommit"] length] > 0) {
        self.currentSentinelTextField.stringValue = [object valueForKey:@"sentinelGitCommit"];
        self.sentinelUpdateButton.enabled = true;
    }
    else {
        self.sentinelUpdateButton.enabled = false;
        self.currentSentinelTextField.stringValue = @"";
    }
    
    //Show repositories version
    if ([[object valueForKey:@"masternodeState"] integerValue] != MasternodeState_Initial || [[object valueForKey:@"masternodeState"] integerValue] != MasternodeState_SettingUp) {
        NSMutableArray *commitArrayData = [[DPVersioningController sharedInstance] getGitCommitInfo:object repositoryUrl:[object valueForKey:@"repositoryUrl"] onBranch:[object valueForKey:@"gitBranch"]];
        [self.versionCoreButton removeAllItems];
        if(commitArrayData != nil) [self.versionCoreButton addItemsWithTitles:commitArrayData];
    }
    
    [self addStringEvent:@"Fetched information."];
}

- (IBAction)refresh:(id)sender {
    [self addStringEvent:@"Refreshing instance(s)."];
    NSArray * masternodesArray = [[DPDataStore sharedInstance] allMasternodes];
    for (NSManagedObject * masternode in masternodesArray) {
//        [self showTableContent:masternode];
        [[DPMasternodeController sharedInstance] checkMasternode:masternode];
    }
}

- (IBAction)updateCoreButton:(id)sender {
    NSArray *coreHead = [[self.versionCoreButton.selectedItem title] componentsSeparatedByString:@","];
    
    if([coreHead count] == 3)
    {
        NSAlert *alert = [[DialogAlert sharedInstance] showAlertWithYesNoButton:@"Warnning!" message:@"Are you sure you already stopped dashd server before updating new version?"];
        
        if ([alert runModal] == NSAlertFirstButtonReturn) {
            [[DPVersioningController sharedInstance] updateCore:[self.selectedObject valueForKey:@"publicIP"] repositoryUrl:[self.selectedObject valueForKey:@"repositoryUrl"] onBranch:[self.selectedObject valueForKey:@"gitBranch"] commitHead:[coreHead objectAtIndex:0]];
        }
    }
    
    
}

#pragma mark - Table View

- (void)tableView:(NSTableView *)tableView didClickTableColumn:(NSTableColumn *)tableColumn {
    if([[tableColumn title] isEqualToString:@"Instance ID"]) {
        NSSortDescriptor* sortDescriptor = [[NSSortDescriptor alloc] initWithKey: @"instanceId" ascending:_instanceIDColumnBool];
        [self.arrayController setSortDescriptors:[NSArray arrayWithObject:sortDescriptor]];
        if(_instanceIDColumnBool == YES) _instanceIDColumnBool = NO;
        else _instanceIDColumnBool = YES;
    }
    else if([[tableColumn title] isEqualToString:@"IP Address"]) {
        NSSortDescriptor* sortDescriptor = [[NSSortDescriptor alloc] initWithKey: @"publicIP" ascending:_publicIPColumnBool];
        [self.arrayController setSortDescriptors:[NSArray arrayWithObject:sortDescriptor]];
        if(_publicIPColumnBool == YES) _publicIPColumnBool = NO;
        else _publicIPColumnBool = YES;
    }
    else if([[tableColumn title] isEqualToString:@"Instance State"]) {
        NSSortDescriptor* sortDescriptor = [[NSSortDescriptor alloc] initWithKey: @"instanceState" ascending:_instanceStateColumnBool];
        [self.arrayController setSortDescriptors:[NSArray arrayWithObject:sortDescriptor]];
        if(_instanceStateColumnBool == YES) _instanceStateColumnBool = NO;
        else _instanceStateColumnBool = YES;
    }
    else if([[tableColumn title] isEqualToString:@"Chain"]) {
        NSSortDescriptor* sortDescriptor = [[NSSortDescriptor alloc] initWithKey: @"chainNetwork" ascending:_chainColumnBool];
        [self.arrayController setSortDescriptors:[NSArray arrayWithObject:sortDescriptor]];
        if(_chainColumnBool == YES) _chainColumnBool = NO;
        else _chainColumnBool = YES;
    }
    else if([[tableColumn title] isEqualToString:@"Core Branch"]) {
        NSSortDescriptor* sortDescriptor = [[NSSortDescriptor alloc] initWithKey: @"gitBranch" ascending:_coreBranchColumnBool];
        [self.arrayController setSortDescriptors:[NSArray arrayWithObject:sortDescriptor]];
        if(_coreBranchColumnBool == YES) _coreBranchColumnBool = NO;
        else _coreBranchColumnBool = YES;
    }
    else if([[tableColumn title] isEqualToString:@"Core Head"]) {
        NSSortDescriptor* sortDescriptor = [[NSSortDescriptor alloc] initWithKey: @"gitCommit" ascending:_coreHeadColumnBool];
        [self.arrayController setSortDescriptors:[NSArray arrayWithObject:sortDescriptor]];
        if(_coreHeadColumnBool == YES) _coreHeadColumnBool = NO;
        else _coreHeadColumnBool = YES;
    }
    else if([[tableColumn title] isEqualToString:@"Sentinel Branch"]) {
        NSSortDescriptor* sortDescriptor = [[NSSortDescriptor alloc] initWithKey: @"sentinelGitBranch" ascending:_sentinelBranchColumnBool];
        [self.arrayController setSortDescriptors:[NSArray arrayWithObject:sortDescriptor]];
        if(_sentinelBranchColumnBool == YES) _sentinelBranchColumnBool = NO;
        else _sentinelBranchColumnBool = YES;
    }
    else if([[tableColumn title] isEqualToString:@"Sentinel Head"]) {
        NSSortDescriptor* sortDescriptor = [[NSSortDescriptor alloc] initWithKey: @"sentinelGitCommit" ascending:_sentinelHeadColumnBool];
        [self.arrayController setSortDescriptors:[NSArray arrayWithObject:sortDescriptor]];
        if(_sentinelHeadColumnBool == YES) _sentinelHeadColumnBool = NO;
        else _sentinelHeadColumnBool = YES;
    }
    
}

- (IBAction)updateSentinelButton:(id)sender {
}


@end
