//
//  ChainSelectionViewController.m
//  dashPlayground
//
//  Created by NATTAPON AIEMLAOR on 8/6/18.
//  Copyright © 2018 dashfoundation. All rights reserved.
//

#import "ChainSelectionViewController.h"
#import "DPChainSelectionController.h"
#import "DPMasternodeController.h"
#import "DPDataStore.h"

@interface ChainSelectionViewController ()

@property (weak) IBOutlet NSPopUpButton *chainPopUp;
@property (weak) IBOutlet NSTextField *chainNameField;
@property (weak) IBOutlet NSTextField *nameLabel;

@end

@implementation ChainSelectionViewController

ChainSelectionViewController* _chainSelectionWindow;
NSManagedObject* _masternodeObject;

- (void)windowDidLoad {
    [super windowDidLoad];
    
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
}

- (void)showChainSelectionWindow:(NSManagedObject*)masternode {
    if([_chainSelectionWindow.window isVisible]) return;
    _masternodeObject = masternode;
    _chainSelectionWindow = [[ChainSelectionViewController alloc] initWithWindowNibName:@"ChainSelectionWindow"];
    [_chainSelectionWindow.window makeKeyAndOrderFront:self];
}

- (IBAction)pressOkButton:(id)sender {
    
    __block NSString *chainNetwork = @"";
    __block NSString *chainNetworkName = self.chainNameField.stringValue;
    
    if([self.chainPopUp.objectValue integerValue] == 0) {
        chainNetwork = @"mainnet";
    }
    else if([self.chainPopUp.objectValue integerValue] == 1) {
        chainNetwork = @"testnet";
    }
    else if([self.chainPopUp.objectValue integerValue] == 2) {
        chainNetwork = @"devnet=DRA";
    }
    
    [_masternodeObject setValue:chainNetwork forKey:@"chainNetwork"];
    [[DPDataStore sharedInstance] saveContext:_masternodeObject.managedObjectContext];
    
    [_chainSelectionWindow close];
    
    __block BOOL isSuccess = YES;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0),^{
        
        [[DPMasternodeController sharedInstance] setUpMasternodeConfiguration:_masternodeObject clb:^(BOOL success, NSString *message) {
            isSuccess = success;
            if (!success) {
                NSMutableDictionary *dict = [NSMutableDictionary dictionary];
                dict[NSLocalizedDescriptionKey] = message;
                NSError * error = [NSError errorWithDomain:@"DASH_PLAYGROUND" code:10 userInfo:dict];
                [[NSApplication sharedApplication] presentError:error];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[[DPMasternodeController sharedInstance] masternodeViewController] addStringEventToMasternodeConsole:message];
                });
                return;
            }
            else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[[DPMasternodeController sharedInstance] masternodeViewController] addStringEventToMasternodeConsole:message];
                });
            }
        }];
        
        sleep(30);
        if(isSuccess != YES) return;
        if([chainNetwork isEqualToString:@"devnet=DRA"]) chainNetwork = @"devnet";
        
        [[DPChainSelectionController sharedInstance] configureConfigDashFileForMasternode:_masternodeObject onChain:chainNetwork onName:chainNetworkName onClb:^(BOOL success, NSString *message) {
            if(success != YES) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[[DPMasternodeController sharedInstance] masternodeViewController] addStringEventToMasternodeConsole:@"configure chain network failed."];
                });
            }
            else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[[DPMasternodeController sharedInstance] masternodeViewController] addStringEventToMasternodeConsole:@"configure chain network successfully."];
                });
            }
        }];
    });
}

- (IBAction)selectChainNetwork:(id)sender {
    if([self.chainPopUp.objectValue integerValue] == 2) {
        self.nameLabel.hidden = false;
        self.chainNameField.hidden = false;
    }
    else {
        self.nameLabel.hidden = true;
        self.chainNameField.hidden = true;
    }
}


@end