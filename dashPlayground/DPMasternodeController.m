//
//  DPMasternodeController.m
//  dashPlayground
//
//  Created by Sam Westrich on 3/24/17.
//  Copyright © 2017 dashfoundation. All rights reserved.
//

#import "DPMasternodeController.h"
#import "Defines.h"
#import "AppDelegate.h"
#import "NSArray+SWAdditions.h"
#import "DPDataStore.h"
#import "CkoSFtp.h"
#import "CkoSsh.h"
#import "CkoSshKey.h"
#import "CkoStringBuilder.h"
#import "DPLocalNodeController.h"
#import "MasternodeStateTransformer.h"
#import "MasternodeSyncStatusTransformer.h"
//#import "DFSSHServer.h"
//#import "DFSSHConnector.h"
//#import "DFSSHOperator.h"
#import "DialogAlert.h"
#import "PreferenceViewController.h"
#import "PreferenceData.h"
#import <NMSSH/NMSSH.h>
#import "SshConnection.h"
#import "SentinelStateTransformer.h"
#import "DPChainSelectionController.h"

#define MASTERNODE_PRIVATE_KEY_STRING @"[MASTERNODE_PRIVATE_KEY]"
#define RPC_PASSWORD_STRING @"[RPC_PASSWORD]"
#define EXTERNAL_IP_STRING @"[EXTERNAL_IP]"

#define SSHPATH @"sshPath"
#define SSH_NAME_STRING @"SSH_NAME"

@interface DPMasternodeController ()

@end

@implementation DPMasternodeController

@synthesize masternodeViewController = _masternodeViewController;

-(NSString*)sshPath {
    NSUserDefaults * standardUserDefaults = [NSUserDefaults standardUserDefaults];
    return [standardUserDefaults stringForKey:SSHPATH];
}

-(void)setSshPath:(NSString*)sshPath {
    NSUserDefaults * standardUserDefaults = [NSUserDefaults standardUserDefaults];
    [standardUserDefaults setObject:sshPath forKey:SSHPATH];
}

-(NSString*)getSshName {
    NSUserDefaults * standardUserDefaults = [NSUserDefaults standardUserDefaults];
    return [standardUserDefaults stringForKey:SSH_NAME_STRING];
}

-(void)setSshName:(NSString*)sshName {
    NSUserDefaults * standardUserDefaults = [NSUserDefaults standardUserDefaults];
    [standardUserDefaults setObject:sshName forKey:SSH_NAME_STRING];
}

#pragma mark - Connectivity

//Toey

-(void)sendDashGitCloneCommandForRepositoryPath:(NSString*)repositoryPath toDirectory:(NSString*)directory onSSH:(NMSSHSession *)ssh error:(NSError*)error percentageClb:(dashPercentageClb)clb {
    
    NSString *command = [NSString stringWithFormat:@"git clone %@ ~/src/dash",repositoryPath];
    [self sendExecuteCommand:command onSSH:ssh error:error];
    
}

-(void)sendDashCommandsList:(NSArray*)commands onSSH:(NMSSHSession*)ssh onPath:(NSString*)path error:(NSError*)error percentageClb:(dashPercentageClb)clb {
    
    for (NSUInteger index = 0;index<[commands count];index++) {
        NSString * command = [commands objectAtIndex:index];
        
//        NSLog(@"Executing command %@", command);
        
        [self sendExecuteCommand:[NSString stringWithFormat:@"%@ %@",path, command] onSSH:ssh error:error];
        
        int currentCommand = (int)index;
        currentCommand = currentCommand+1;
        
        clb(command,(currentCommand*100)/[commands count]);
    }
}

-(void)sendExecuteCommand:(NSString*)command onSSH:(NMSSHSession*)ssh error:(NSError*)error {
    error = nil;
    [ssh.channel execute:command error:&error];
    if (error) {
        NSLog(@"SSH: error executing command %@ - %@", command, error);
        return;
    }
}

-(NSString*)getResponseExecuteCommand:(NSString*)command onSSH:(NMSSHSession*)ssh error:(NSError*)error {
    error = nil;
    NSString *response = [ssh.channel execute:command error:&error];
    if (error) {
        NSLog(@"SSH: error executing command %@ - %@", command, error);
        return [NSString stringWithFormat:@"%@", [error localizedDescription]];
    }
    return response;
}

//-(NSString*)sendGitCommand:(NSString*)command onSSH:(CkoSsh *)ssh {
//    return [[self sendGitCommands:@[command] onSSH:ssh] valueForKey:command];
//}

-(NSDictionary*)sendGitCommands:(NSArray*)commands onSSH:(NMSSHSession *)ssh {
    
    NSError *error = nil;
    [ssh.channel execute:@"cd src/dash\n" error:&error];
    if (error) {
        NSLog(@"location not found! %@",error.localizedDescription);
        return nil;
    }
    
    NSMutableDictionary * rDict = [NSMutableDictionary dictionaryWithCapacity:commands.count];
    for (NSString * gitCommand in commands) {
        //   Run the 2nd command in the remote shell, which will be
        //   to "ls" the directory.
        error = nil;
        NSString *cmdOutput = [ssh.channel execute:[NSString stringWithFormat:@"cd src/dash; git %@", gitCommand] error:&error];
        if (error) {
            NSLog(@"error trying to send git command! %@",error.localizedDescription);
            return nil;
        }
        else{
            NSArray * components = [cmdOutput componentsSeparatedByString:@"\r\n"];
            if ([components count] >= 2) {
                //                if ([[NSString stringWithFormat:@"git %@",gitCommand] isEqualToString:components[0]]) {
                //                    [rDict setObject:components[1] forKey:gitCommand];
                //                }
                for (id eachComponent in components) {
                    if(![eachComponent isEqualToString:@""])
                    {
                        if([gitCommand isEqualToString:@"remote -v"]) {
                            [rDict setObject:components[0] forKey:gitCommand];//set only (fetch) branch
                            break;
                        }
                        [rDict setObject:eachComponent forKey:gitCommand];
                    }
                }
            }
        }
    }
    
    return rDict;
}

-(NMSSHSession*)connectInstance:(NSManagedObject*)masternode {
    __block NMSSHSession *ssh;
    [[SshConnection sharedInstance] sshInWithKeyPath:[self sshPath] masternodeIp:[masternode valueForKey:@"publicIP"] openShell:NO clb:^(BOOL success, NSString *message, NMSSHSession *sshSession) {
        ssh = sshSession;
    }];
    
    return ssh;
}

//End Toey


//-(NSString*)sendGitCommand:(NSString*)command onSSH:(CkoSsh *)ssh {
//    return [[self sendGitCommands:@[command] onSSH:ssh] valueForKey:command];
//}
//
//-(NSDictionary*)sendGitCommands:(NSArray*)commands onSSH:(CkoSsh *)ssh {
//
//    NSInteger channelNum = [[ssh QuickShell] integerValue];
//    if (channelNum < 0) {
//        NSLog(@"%@",ssh.LastErrorText);
//        return nil;
//    }
//
//    //  This is the prompt we'll be expecting to find in
//    //  the output of the remote shell.
//    NSString *myPrompt = @":~/src/dash$";
//    //   Run the 1st command in the remote shell, which will be to
//    //   "cd" to a subdirectory.
//    BOOL success = [ssh ChannelSendString: @(channelNum) strData: @"cd src/dash/\n" charset: @"ansi"];
//    if (success != YES) {
//        NSLog(@"%@",ssh.LastErrorText);
//        return nil;
//    }
//
//    //    NSNumber * v = [ssh ChannelReadAndPoll:@(channelNum) pollTimeoutMs:@(5000)];
//    //
//    //    NSString *cmdOutpu2t = [ssh GetReceivedText: @(channelNum) charset: @"ansi"];
//    //    if (ssh.LastMethodSuccess != YES) {
//    //        NSLog(@"%@",ssh.LastErrorText);
//    //        return nil;
//    //    };
//    //  Retrieve the output.
//    success = [ssh ChannelReceiveUntilMatch: @(channelNum) matchPattern: myPrompt charset: @"ansi" caseSensitive: YES];
//    if (success != YES) {
//        NSLog(@"%@",ssh.LastErrorText);
//        return nil;
//    }
//
//    //   Display what we've received so far.  This clears
//    //   the internal receive buffer, which is important.
//    //   After we send the command, we'll be reading until
//    //   the next command prompt.  If the command prompt
//    //   is already in the internal receive buffer, it'll think it's
//    //   already finished...
//    NSString *cmdOutput = [ssh GetReceivedText: @(channelNum) charset: @"ansi"];
//    if (ssh.LastMethodSuccess != YES) {
//        NSLog(@"%@",ssh.LastErrorText);
//        return nil;
//    };
//    NSMutableDictionary * rDict = [NSMutableDictionary dictionaryWithCapacity:commands.count];
//    for (NSString * gitCommand in commands) {
//        //   Run the 2nd command in the remote shell, which will be
//        //   to "ls" the directory.
//        success = [ssh ChannelSendString: @(channelNum) strData:[NSString stringWithFormat:@"git %@\n",gitCommand] charset: @"ansi"];
//        if (success != YES) {
//            NSLog(@"%@",ssh.LastErrorText);
//            return nil;
//        }
//
//        //  Retrieve and display the output.
//        success = [ssh ChannelReceiveUntilMatch: @(channelNum) matchPattern: myPrompt charset: @"ansi" caseSensitive: YES];
//        if (success != YES) {
//            NSLog(@"%@",ssh.LastErrorText);
//            return nil;
//        }
//
//        cmdOutput = [ssh GetReceivedText: @(channelNum) charset: @"ansi"];
//        if (ssh.LastMethodSuccess != YES) {
//            NSLog(@"%@",ssh.LastErrorText);
//            return nil;
//        }
//        NSArray * components = [cmdOutput componentsSeparatedByString:@"\r\n"];
//        if ([components count] > 2) {
//            if ([[NSString stringWithFormat:@"git %@",gitCommand] isEqualToString:components[0]]) {
//                [rDict setObject:components[1] forKey:gitCommand];
//            }
//        }
//    }
//
//    //  Send an EOF.  This tells the server that no more data will
//    //  be sent on this channel.  The channel remains open, and
//    //  the SSH client may still receive output on this channel.
//    success = [ssh ChannelSendEof: @(channelNum)];
//    if (success != YES) {
//        NSLog(@"%@",ssh.LastErrorText);
//        return nil;
//    }
//
//    //  Close the channel:
//    success = [ssh ChannelSendClose: @(channelNum)];
//    if (success != YES) {
//        NSLog(@"%@",ssh.LastErrorText);
//        return nil;
//    }
//
//    return rDict;
//}

-(void)sendDashCommandList:(NSArray*)commands onSSH:(CkoSsh *)ssh error:(NSError**)error {
    [self sendDashCommandList:commands onSSH:ssh commandExpectedLineCounts:nil error:error percentageClb:nil];
}


-(void)sendDashCommandList:(NSArray*)commands onSSH:(CkoSsh *)ssh commandExpectedLineCounts:(NSArray*)expectedlineCounts error:(NSError**)error percentageClb:(dashPercentageClb)clb {
    [self sendCommandList:commands toPath:@"~/src/dash" onSSH:ssh commandExpectedLineCounts:expectedlineCounts error:error percentageClb:clb];
}

-(void)sendCommandList:(NSArray*)commands toPath:(NSString*)path onSSH:(CkoSsh *)ssh error:(NSError**)error {
    [self sendCommandList:commands toPath:path onSSH:ssh commandExpectedLineCounts:nil error:error percentageClb:nil];
}

-(void)sendCommandList:(NSArray*)commands toPath:(NSString*)path onSSH:(CkoSsh *)ssh commandExpectedLineCounts:(NSArray*)expectedlineCounts error:(NSError**)error percentageClb:(dashPercentageClb)clb {
    //expected line counts are used to give back a percentage complete on this function;
    
    NSInteger channelNum = [[ssh QuickShell] integerValue];
    if (channelNum < 0) {
        *error = [NSError errorWithDomain:@"org.quantumexplorer.dashplayground" code:0 userInfo:@{NSLocalizedDescriptionKey:ssh.LastErrorText}];
        NSLog(@"%@",ssh.LastErrorText);
        return;
    }
    
    //  This is the prompt we'll be expecting to find in
    //  the output of the remote shell.
    NSString *myPrompt = [NSString stringWithFormat:@":%@$",path];
    //   Run the 1st command in the remote shell, which will be to
    //   "cd" to a subdirectory.
    BOOL success = [ssh ChannelSendString: @(channelNum) strData:[NSString stringWithFormat:@"cd %@\n",path] charset: @"ansi"];
    if (success != YES) {
        *error = [NSError errorWithDomain:@"org.quantumexplorer.dashplayground" code:0 userInfo:@{NSLocalizedDescriptionKey:ssh.LastErrorText}];
        NSLog(@"%@",ssh.LastErrorText);
        return;
    }
    
    //    NSNumber * v = [ssh ChannelReadAndPoll:@(channelNum) pollTimeoutMs:@(5000)];
    //
    //    NSString *cmdOutpu2t = [ssh GetReceivedText: @(channelNum) charset: @"ansi"];
    //    if (ssh.LastMethodSuccess != YES) {
    //        NSLog(@"%@",ssh.LastErrorText);
    //        return nil;
    //    };
    //  Retrieve the output.
    success = [ssh ChannelReceiveUntilMatch: @(channelNum) matchPattern: myPrompt charset: @"ansi" caseSensitive: YES];
    if (success != YES) {
        *error = [NSError errorWithDomain:@"org.quantumexplorer.dashplayground" code:0 userInfo:@{NSLocalizedDescriptionKey:ssh.LastErrorText}];
        NSLog(@"%@",ssh.LastErrorText);
        return;
    }
    
    //   Display what we've received so far.  This clears
    //   the internal receive buffer, which is important.
    //   After we send the command, we'll be reading until
    //   the next command prompt.  If the command prompt
    //   is already in the internal receive buffer, it'll think it's
    //   already finished...
    NSString *cmdOutput = [ssh GetReceivedText: @(channelNum) charset: @"ansi"];
    if (ssh.LastMethodSuccess != YES) {
        NSLog(@"%@",ssh.LastErrorText);
        return;
    };
    NSMutableDictionary * rDict = [NSMutableDictionary dictionaryWithCapacity:commands.count];
    for (NSUInteger index = 0;index<[commands count];index++) {
        NSString * command = [commands objectAtIndex:index];
        NSNumber * numberLines = ([expectedlineCounts count] > index)?[expectedlineCounts objectAtIndex:index]:nil;
        //   Run the 2nd command in the remote shell, which will be
        //   to "ls" the directory.
        success = [ssh ChannelSendString: @(channelNum) strData:[NSString stringWithFormat:@"%@\n",command] charset: @"ansi"];
        if (success != YES) {
            *error = [NSError errorWithDomain:@"org.quantumexplorer.dashplayground" code:0 userInfo:@{NSLocalizedDescriptionKey:ssh.LastErrorText}];
            NSLog(@"%@",ssh.LastErrorText);
            return;
        }
        if (numberLines && [numberLines integerValue] > 1) {
            NSMutableString * mOutput = [NSMutableString string];
            while (1) {
                NSNumber * poll = [ssh ChannelReadAndPoll: @(channelNum) pollTimeoutMs:@(3000)];
                if ([poll integerValue] == -1) {
                    *error = [NSError errorWithDomain:@"org.quantumexplorer.dashplayground" code:0 userInfo:@{NSLocalizedDescriptionKey:ssh.LastErrorText}];
                    NSLog(@"%@",ssh.LastErrorText);
                    return;
                } else if ([poll integerValue] > 0) {
                    [mOutput appendString:[ssh GetReceivedText: @(channelNum) charset: @"ansi"]];
                    NSUInteger numberOfLines, index, stringLength = [mOutput length];
                    
                    for (index = 0, numberOfLines = 0; index < stringLength; numberOfLines++)
                        index = NSMaxRange([mOutput lineRangeForRange:NSMakeRange(index, 0)]);
                    clb(command,numberOfLines / [numberLines floatValue]);
                }
                if ([[mOutput stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] hasSuffix:myPrompt]) {
                    clb(command,1.0);
                    [rDict setObject:[mOutput copy] forKey:command];
                    break;
                }
            }
        } else {
            //  Retrieve and display the output.
            success = [ssh ChannelReceiveUntilMatch: @(channelNum) matchPattern: myPrompt charset: @"ansi" caseSensitive: YES];
            if (success != YES) {
                *error = [NSError errorWithDomain:@"org.quantumexplorer.dashplayground" code:0 userInfo:@{NSLocalizedDescriptionKey:ssh.LastErrorText}];
                NSLog(@"%@",ssh.LastErrorText);
                return;
            }
            clb(command,1.0);
            cmdOutput = [ssh GetReceivedText: @(channelNum) charset: @"ansi"];
            if (ssh.LastMethodSuccess != YES) {
                *error = [NSError errorWithDomain:@"org.quantumexplorer.dashplayground" code:0 userInfo:@{NSLocalizedDescriptionKey:ssh.LastErrorText}];
                NSLog(@"%@",ssh.LastErrorText);
                return;
            }
            [rDict setObject:cmdOutput forKey:command];
        }
    }
    
    //  Send an EOF.  This tells the server that no more data will
    //  be sent on this channel.  The channel remains open, and
    //  the SSH client may still receive output on this channel.
    success = [ssh ChannelSendEof: @(channelNum)];
    if (success != YES) {
        *error = [NSError errorWithDomain:@"org.quantumexplorer.dashplayground" code:0 userInfo:@{NSLocalizedDescriptionKey:ssh.LastErrorText}];
        NSLog(@"%@",ssh.LastErrorText);
        return;
    }
    
    //  Close the channel:
    success = [ssh ChannelSendClose: @(channelNum)];
    if (success != YES) {
        *error = [NSError errorWithDomain:@"org.quantumexplorer.dashplayground" code:0 userInfo:@{NSLocalizedDescriptionKey:ssh.LastErrorText}];
        NSLog(@"%@",ssh.LastErrorText);
        return;
    }
}

-(CkoSshKey *)loginPrivateKeyAtPath:(NSString*)path {
    CkoSshKey *key = [[CkoSshKey alloc] init];
    
    //  Read the PEM file into a string variable:
    //  (This does not load the PEM file into the key.  The LoadText
    //  method is a convenience method for loading the full contents of ANY text
    //  file into a string variable.)
    NSString *privKey = [key LoadText:path];
    if (key.LastMethodSuccess != YES) {
        NSLog(@"%@",key.LastErrorText);
        return nil;
    }
    
    //  Load a private key from a PEM string:
    //  (Private keys may be loaded from OpenSSH and Putty formats.
    //  Both encrypted and unencrypted private key file formats
    //  are supported.  This example loads an unencrypted private
    //  key in OpenSSH format.  PuTTY keys typically use the .ppk
    //  file extension, while OpenSSH keys use the PEM format.
    //  (For PuTTY keys, call FromPuttyPrivateKey instead.)
    BOOL success = [key FromOpenSshPrivateKey: privKey];
    if (success != YES) {
        NSLog(@"%@",key.LastErrorText);
        return nil;
    }
    return key;
}

-(CkoSFtp*)sftpIn:(NSString*)masternodeIP {
    if (![self sshPath]) {
        DialogAlert *dialog=[[DialogAlert alloc]init];
        NSAlert *findPathAlert = [dialog getFindPathAlert:@"SSH_KEY.pem" exPath:@"~/Documents"];
        
        if ([findPathAlert runModal] == NSAlertFirstButtonReturn) {
            //Find clicked
            NSString *pathString = [dialog getLaunchPath];
            [self setSshPath:pathString];
            return [self sftpIn:masternodeIP privateKeyPath:pathString];
        }
    }
    else{
        return [self sftpIn:masternodeIP privateKeyPath:[self sshPath]];
    }
    
    return nil;
}

-(CkoSFtp*)sftpIn:(NSString*)masternodeIP privateKeyPath:(NSString*)privateKeyPath {
    //  Important: It is helpful to send the contents of the
    //  sftp.LastErrorText property when requesting support.
    
    CkoSFtp *sftp = [[CkoSFtp alloc] init];
    
    //  Any string automatically begins a fully-functional 30-day trial.
    BOOL success = [sftp UnlockComponent: @"Anything for 30-day trial"];
    if (success != YES) {
        NSLog(@"%@",sftp.LastErrorText);
        return nil;
    }
    
    //  Set some timeouts, in milliseconds:
    sftp.ConnectTimeoutMs = [NSNumber numberWithInt:15000];
    sftp.IdleTimeoutMs = [NSNumber numberWithInt:15000];
    
    //  Connect to the SSH server.
    //  The standard SSH port = 22
    //  The hostname may be a hostname or IP address.
    int port = 22;
    NSString *hostname = masternodeIP;
    success = [sftp Connect: hostname port: [NSNumber numberWithInt: port]];
    if (success != YES) {
        NSLog(@"%@",sftp.LastErrorText);
        return nil;
    }
    
    CkoSshKey * key = [self loginPrivateKeyAtPath:privateKeyPath];
    if (!key) return nil;
    //  Authenticate with the SSH server using the login and
    //  private key.  (The corresponding public key should've
    //  been installed on the SSH server beforehand.)
    success = [sftp AuthenticatePk: @"ubuntu" privateKey: key];
    if (success != YES) {
        NSLog(@"%@",sftp.LastErrorText);
        return nil;
    }
    NSLog(@"%@",@"Public-Key Authentication Successful!");
    
    //  After authenticating, the SFTP subsystem must be initialized:
    success = [sftp InitializeSftp];
    if (success != YES) {
        NSLog(@"%@",sftp.LastErrorText);
        return nil;
    }
    return sftp;
}


- (void)setUpMasternodeDashd:(NSManagedObject*)masternode clb:(dashClb)clb
{
//    __block NSString * publicIP = [masternode valueForKey:@"publicIP"];
//    __block NSString * repositoryPath = [masternode valueForKeyPath:@"branch.repository.url"];
//    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0),^{
//        CkoSsh * ssh = [self sshIn:publicIP] ;
//        if (!ssh){
//            dispatch_async(dispatch_get_main_queue(), ^{
//                clb(NO,@"Could not SSH in");
//            });
//            return;
//        }
//        //  Send some commands and get the output.
//        NSString *strOutput = [ssh QuickCommand: @"ls src | grep '^dash$'" charset: @"ansi"];
//        if (ssh.LastMethodSuccess != YES) {
//            NSLog(@"%@",ssh.LastErrorText);
//            dispatch_async(dispatch_get_main_queue(), ^{
//                clb(NO,ssh.LastErrorText);
//            });
//            return;
//        }
//        if ([strOutput hasPrefix:@"ls: cannot access src: No such file or directory"]) {
//            [ssh QuickCommand: @"mkdir src" charset: @"ansi"];
//            if (ssh.LastMethodSuccess != YES) {
//                NSLog(@"%@",ssh.LastErrorText);
//                dispatch_async(dispatch_get_main_queue(), ^{
//                    clb(NO,ssh.LastErrorText);
//                });
//                return;
//            }
//        }
//        BOOL justCloned = FALSE;
//        if (![strOutput isEqualToString:@"dash"]) {
//            justCloned = TRUE;
//            NSError * error = nil;
//            [self sendDashGitCloneCommandForRepositoryPath:repositoryPath toDirectory:@"~/src/dash" onSSH:ssh error:&error percentageClb:^(NSString *call, float percentage) {
//                dispatch_async(dispatch_get_main_queue(), ^{
//                    NSLog(@"%@ %.2f",call,percentage);
//                    [masternode setValue:@(percentage) forKey:@"operationPercentageDone"];
//                });
//            }];
//            strOutput = [ssh QuickCommand: [NSString stringWithFormat:@"git clone %@ ~/src/dash",repositoryPath] charset: @"ansi"];
//            if (ssh.LastMethodSuccess != YES) {
//                dispatch_async(dispatch_get_main_queue(), ^{
//                    clb(NO,ssh.LastErrorText);
//                });
//
//                return;
//            }
//        }
//
//        //now let's get git info
//        __block NSDictionary * gitValues = nil;
//        if (!justCloned) {
//            gitValues = [self sendGitCommands:@[@"pull",@"rev-parse --short HEAD"] onSSH:ssh];
//        } else {
//            gitValues = [self sendGitCommands:@[@"rev-parse --short HEAD"] onSSH:ssh];
//        }
//        dispatch_async(dispatch_get_main_queue(), ^{
//            [masternode setValue:gitValues[@"rev-parse --short HEAD"] forKey:@"gitCommit"];
//            [[DPDataStore sharedInstance] saveContext:masternode.managedObjectContext];
//        });
//
//        NSError * error = nil;
//
//        //now let's make all this shit
//        [self sendDashCommandList:@[@"./autogen.sh",@"./configure CPPFLAGS='-I/usr/local/BerkeleyDB.4.8/include -O2' LDFLAGS='-L/usr/local/BerkeleyDB.4.8/lib'",@"make",@"mkdir ~/.dashcore/",@"cp src/dashd ~/.dashcore/",@"cp src/dash-cli ~/.dashcore/",@"sudo cp src/dashd /usr/bin/dashd",@"sudo cp src/dash-cli /usr/bin/dash-cli"] onSSH:ssh commandExpectedLineCounts:@[@(52),@(481),@(301),@(1),@(1),@(1),@(1),@(1)] error:&error percentageClb:^(NSString *call, float percentage) {
//            dispatch_async(dispatch_get_main_queue(), ^{
//                NSLog(@"%@ %.2f",call,percentage);
//                [masternode setValue:@(percentage) forKey:@"operationPercentageDone"];
//            });
//        }];
//
//        [ssh Disconnect];
//
//        dispatch_async(dispatch_get_main_queue(), ^{
//            if ([[masternode valueForKey:@"masternodeState"] integerValue] == MasternodeState_Initial) {
//                [masternode setValue:@(MasternodeState_Installed) forKey:@"masternodeState"];
//            }
//            [[DPDataStore sharedInstance] saveContext:masternode.managedObjectContext];
//        });
//    });
    
    
}

- (void)setUpMasternodeConfiguration:(NSManagedObject*)masternode clb:(dashClb)clb {
    __block NSManagedObject * object = masternode;
    if (![masternode valueForKey:@"key"]) {
        [[DPLocalNodeController sharedInstance] startDash:^(BOOL success, NSString *message) {
            if (!success) return clb(success,message);
            
            NSString *eventMsg = [NSString stringWithFormat:@"[instance-id: %@]: -%@ masternode genkey", [masternode valueForKey:@"chainNetwork"], [masternode valueForKey:@"instanceId"]];
            clb(YES,eventMsg);
            
            NSString * key = [[DPLocalNodeController sharedInstance] runDashRPCCommandString:[NSString stringWithFormat:@"-%@ masternode genkey", [masternode valueForKey:@"chainNetwork"]] forChain:[masternode valueForKey:@"chainNetwork"]];
            if ([key length] == 51) {
                [object setValue:key forKey:@"key"];
                [[DPDataStore sharedInstance] saveContext:object.managedObjectContext];
                [self setUpMasternodeConfiguration:object clb:clb];
            } else {
                if (!success) return clb(FALSE,@"Error generating masternode key");
            }
        } forChain:[masternode valueForKey:@"chainNetwork"]];
        return;
    }
    
    
    if ([masternode valueForKey:@"transactionId"] && [masternode valueForKey:@"transactionOutputIndex"]) {
        NSString *eventMsg = [NSString stringWithFormat:@"[instance-id: %@]: configuring masternode configuration file...", [masternode valueForKey:@"instanceId"]];
        clb(YES,eventMsg);
        [[DPLocalNodeController sharedInstance] updateMasternodeConfigurationFileForMasternode:masternode clb:^(BOOL success, NSString *message) {
            if (success) {
                [self configureRemoteMasternode:object clb:^(BOOL success, NSString *message) {
                    if(success != YES) {
                        return clb(success,message);
                    }
                    NSString *eventMsg = [NSString stringWithFormat:@"[instance-id: %@]: configure masternode configuration file successfully. Please wait for updating dash.conf file...", [masternode valueForKey:@"instanceId"]];
                    clb(YES,eventMsg);
                    [masternode setValue:@(MasternodeState_Configured) forKey:@"masternodeState"];
                    [[DPDataStore sharedInstance] saveContext:object.managedObjectContext];
                }];
            }
            return clb(success,message);
        }];
    } else {
        [[DPLocalNodeController sharedInstance] startDash:^(BOOL success, NSString *message) {
            if (success) {
                
                NSString *eventMsg = [NSString stringWithFormat:@"[instance-id: %@]: configuring masternode configuration file...", [masternode valueForKey:@"instanceId"]];
                clb(YES,eventMsg);
                
                NSMutableArray * outputs = [[[DPLocalNodeController sharedInstance] outputs:[masternode valueForKey:@"chainNetwork"]] mutableCopy];
                
                if(outputs == nil) {
                    return clb(FALSE,@"No valid outputs (empty) please set up this instance first.");
                }
                
                NSArray * knownOutputs = [[[DPDataStore sharedInstance] allMasternodes] arrayOfArraysReferencedByKeyPaths:@[@"transactionId",@"transactionOutputIndex"] requiredKeyPaths:@[@"transactionId",@"transactionOutputIndex"]];
                for (int i = (int)[outputs count] -1;i> -1;i--) {
                    for (NSArray * knownOutput in knownOutputs) {
                        if ([outputs[i][0] isEqualToString:knownOutput[0]] && ([outputs[i][1] integerValue] == [knownOutput[1] integerValue])) [outputs removeObjectAtIndex:i];
                    }
                }
                if ([outputs count]) {
                    [masternode setValue:outputs[0][0] forKey:@"transactionId"];
                    [masternode setValue:@([outputs[0][1] integerValue]) forKey:@"transactionOutputIndex"];
                    [[DPDataStore sharedInstance] saveContext];
                    [[DPLocalNodeController sharedInstance] updateMasternodeConfigurationFileForMasternode:masternode clb:^(BOOL success, NSString *message) {
                        if (success) {
                            [self configureRemoteMasternode:object clb:^(BOOL success, NSString *message) {
                                if(success != YES) {
                                    return clb(success,message);
                                }
                                NSString *eventMsg = [NSString stringWithFormat:@"[instance-id: %@]: configure masternode configuration file successfully. Please wait for updating dash.conf file...", [masternode valueForKey:@"instanceId"]];
                                clb(YES,eventMsg);
                                [masternode setValue:@(MasternodeState_Configured) forKey:@"masternodeState"];
                                [[DPDataStore sharedInstance] saveContext:object.managedObjectContext];
                            }];
                        }
                        return clb(success,message);
                    }];
                } else {
                    return clb(FALSE,@"No valid outputs (1000 DASH) in local wallet.");
                }
            } else {
                return clb(FALSE,@"Dash server had a problem starting.");
            }
        } forChain:[masternode valueForKey:@"chainNetwork"]];
    }
}

- (void)setUpMasternodeSentinel:(NSManagedObject*)masternode clb:(dashClb)clb {
    
    [masternode setValue:@(SentinelState_Checking) forKey:@"sentinelState"];
    [[DPDataStore sharedInstance] saveContext];
    
    __block NSString *chainNetwork = [masternode valueForKey:@"chainNetwork"];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0),^{
        [[SshConnection sharedInstance] sshInWithKeyPath:[self sshPath] masternodeIp:[masternode valueForKey:@"publicIP"] openShell:NO clb:^(BOOL success, NSString *message, NMSSHSession *sshSession) {
            if(success == YES) {

                __block BOOL isContinue = true;
                
                NSError *error = nil;
                NSString *command = @"sudo apt-get update";
                
                [[SshConnection sharedInstance] sendExecuteCommand:command onSSH:sshSession error:error dashClb:^(BOOL success, NSString *message) {
                    isContinue = success;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        clb(isContinue, message);
                    });
                }];
                if(isContinue == NO) return;
                
                command = @"sudo apt-get install -y git python-virtualenv";
                
                [[SshConnection sharedInstance] sendExecuteCommand:command onSSH:sshSession error:error dashClb:^(BOOL success, NSString *message) {
                    isContinue = success;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        clb(isContinue, message);
                    });
                }];
                if(isContinue == NO) return;
                
                command = @"git clone -b develop https://github.com/dashpay/sentinel.git ~/.dashcore/sentinel";
                
                [[SshConnection sharedInstance] sendExecuteCommand:command onSSH:sshSession error:error dashClb:^(BOOL success, NSString *message) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        clb(success, message);
                    });
                }];
                
                command = @"cd ~/.dashcore/sentinel; virtualenv venv";
                
                [[SshConnection sharedInstance] sendExecuteCommand:command onSSH:sshSession error:error dashClb:^(BOOL success, NSString *message) {
                    isContinue = success;
                    if(success == NO){
                        dispatch_async(dispatch_get_main_queue(), ^{
                           clb(YES, message);
                        });
                        
                        //if failed try another command
                        NSString *command = @"cd ~/.dashcore/sentinel; sudo apt-get install -y virtualenv";
                        
                        [[SshConnection sharedInstance] sendExecuteCommand:command onSSH:sshSession error:error dashClb:^(BOOL success, NSString *message) {
                            isContinue = success;
                            dispatch_async(dispatch_get_main_queue(), ^{
                                clb(isContinue, message);
                            });
                        }];
                    }
                    else {
                        dispatch_async(dispatch_get_main_queue(), ^{
                           clb(YES, message);
                        });
                    }
                }];
                if(isContinue == NO) return;
                
                command = @"cd ~/.dashcore/sentinel; venv/bin/pip install -r requirements.txt";
                
                [[SshConnection sharedInstance] sendExecuteCommand:command onSSH:sshSession error:error dashClb:^(BOOL success, NSString *message) {
                    isContinue = success;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        clb(isContinue, message);
                    });
                }];
                if(isContinue == NO) return;
                
//                step 5) test sentinel is alive and talking to the still sync'ing wallet
//
//                venv/bin/python bin/sentinel.py
//
//                You should see: "dashd not synced with network! Awaiting full sync before running Sentinel."
//                This is exactly what we want to see at this stage
                command = @"cd ~/.dashcore/sentinel; venv/bin/python bin/sentinel.py";
                
                [[SshConnection sharedInstance] sendExecuteCommand:command onSSH:sshSession error:error dashClb:^(BOOL success, NSString *message) {
                    isContinue = success;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        clb(isContinue, message);
                    });
                }];
                if(isContinue == NO) return;
                
                error = nil;
                NSDictionary * dictionary = [self sendRPCCommandJSONDictionary:@"mnsync status" toPublicIP:[masternode valueForKey:@"publicIP"] rpcPassword:[masternode valueForKey:@"rpcPassword"] error:&error forChain:chainNetwork];
                
                if (error) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        NSString *eventMsg = [NSString stringWithFormat:@"[instance-id: %@]: %@", [masternode valueForKey:@"instanceId"], dictionary];
                        clb(NO,eventMsg);
                    });
                } else {
                    if (dictionary) {
                        if ([dictionary[@"AssetName"] isEqualToString:@"MASTERNODE_SYNC_FINISHED"]) {
                            dispatch_async(dispatch_get_main_queue(), ^{
                                [masternode setValue:@([MasternodeSyncStatusTransformer typeForTypeName:dictionary[@"AssetName"]]) forKey:@"syncStatus"];
                                [[DPDataStore sharedInstance] saveContext];
                                [self startRemoteMasternode:masternode clb:^(BOOL success, BOOL value, NSString *errorMessage) {
                                    if (!success) {
                                        NSString *eventMsg = [NSString stringWithFormat:@"[instance-id: %@]: %@", [masternode valueForKey:@"instanceId"], errorMessage];
                                        clb(NO,eventMsg);
                                    } else  if (value) {
                                        NSString *eventMsg = [NSString stringWithFormat:@"[instance-id: %@]: %@", [masternode valueForKey:@"instanceId"], dictionary];
                                        clb(YES,eventMsg);
                                    }
                                }];
                            });
                        }
                        else {
                            dispatch_async(dispatch_get_main_queue(), ^{
                                clb(NO,@"Sync in progress. Must wait until sync is complete to start Masternode.");
                            });
                        }
                    }
                }
                
                command = @"echo \"$(echo '* * * * * cd /home/ubuntu/.dashcore/sentinel && ./venv/bin/python bin/sentinel.py 2>&1 >> sentinel-cron.log' ; crontab -l)\" | crontab -";
                
                [[SshConnection sharedInstance] sendExecuteCommand:command onSSH:sshSession error:error dashClb:^(BOOL success, NSString *message) {
                    isContinue = success;
                    dispatch_async(dispatch_get_main_queue(), ^{
                        clb(isContinue, message);
                    });
                }];
                if(isContinue == NO) return;
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    [masternode setValue:@(SentinelState_Installed) forKey:@"sentinelState"];
                    [[DPDataStore sharedInstance] saveContext];
                });
            }
            else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    clb(NO, @"SSH: could not SSH in!");
                });
            }
        }];
    });
}

- (void)checkMasternodeSentinel:(NSManagedObject*)masternode clb:(dashClb)clb {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0),^{
        [[SshConnection sharedInstance] sshInWithKeyPath:[self sshPath] masternodeIp:[masternode valueForKey:@"publicIP"] openShell:NO clb:^(BOOL success, NSString *message, NMSSHSession *sshSession) {
            if(success == YES) {
                
                NSError *error = nil;
                NSString *command = @"cd ~/.dashcore/sentinel; venv/bin/python bin/sentinel.py";
                
                [[SshConnection sharedInstance] sendExecuteCommand:command onSSH:sshSession error:error dashClb:^(BOOL success, NSString *message) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        clb(success, message);
                    });
                }];
            }
        }];
    });
}

- (void)configureRemoteMasternode:(NSManagedObject*)masternode clb:(dashClb)clb {
    
    [[SshConnection sharedInstance] sshInWithKeyPath:[self sshPath] masternodeIp:[masternode valueForKey:@"publicIP"] openShell:NO clb:^(BOOL success, NSString *message, NMSSHSession *sshSession) {
        if(success == YES) {
            NSString *localFilePath = [self createConfigDashFileForMasternode:masternode];
            NSString *remoteFilePath = @"/home/ubuntu/.dashcore/dash.conf";
            BOOL uploadSuccess = [sshSession.channel uploadFile:localFilePath to:remoteFilePath];
            if (uploadSuccess != YES) {
                NSLog(@"%@",[[sshSession lastError] localizedDescription]);
                clb(NO, [[sshSession lastError] localizedDescription]);
            }
            else {
                clb(YES, nil);
            }
        }
    }];
}


#pragma mark - Start Remote

- (void)startDashd:(NSManagedObject*)masternode clb:(dashInfoClb)clb {
    
    if ([[masternode valueForKey:@"syncStatus"] integerValue] == MasternodeSync_Finished) {
        [self startRemoteMasternode:masternode clb:^(BOOL success, BOOL value, NSString *errorMessage) {
            if (!success || !value) {
                NSString *eventMsg = [NSString stringWithFormat:@"[instance-id: %@]: %@", [masternode valueForKey:@"instanceId"], errorMessage];
                clb(FALSE,nil,eventMsg);
            } else {
                [masternode setValue:@(MasternodeState_Running) forKey:@"masternodeState"];
                [[DPDataStore sharedInstance] saveContext];
                NSString *eventMsg = [NSString stringWithFormat:@"[instance-id: %@]: masternode started", [masternode valueForKey:@"instanceId"]];
                clb(TRUE,nil,eventMsg);
            }
        }];
    } else if ([[masternode valueForKey:@"syncStatus"] integerValue] == MasternodeSync_Initial) {
        __block NSString * publicIP = [masternode valueForKey:@"publicIP"];
        __block NSString * rpcPassword = [masternode valueForKey:@"rpcPassword"];
        __block NSString * chainNetwork = [masternode valueForKey:@"chainNetwork"];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0),^{
            
            __block NMSSHSession *ssh;
            [[SshConnection sharedInstance] sshInWithKeyPath:[self sshPath] masternodeIp:publicIP openShell:NO clb:^(BOOL success, NSString *message, NMSSHSession *sshSession) {
                ssh = sshSession;
                
            }];
            if(!ssh.authorized) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    clb(NO,nil,@"Could not SSH in");
                });
                return;
            }
            //  Send some commands and get the output.
//            NSString *exportCommand = @"export LD_LIBRARY_PATH=/usr/local/BerkeleyDB.4.8/lib && dashd";
            NSError *error = nil;
//            NSString *output = [ssh.channel execute:exportCommand error:&error];
            
            //start dashd
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *eventMsg = [NSString stringWithFormat:@"[instance-id: %@]: running dashd...", [masternode valueForKey:@"instanceId"]];
                clb(TRUE, nil, eventMsg);
            });
            if ([chainNetwork rangeOfString:@"devnet"].location != NSNotFound) {
                [ssh.channel execute:@"cd ~/src; ./dashd -devnet='DRA' -rpcport='12999' -port='12999'" error:&error];
            }
            else {
                [ssh.channel execute:@"cd ~/src; ./dashd" error:&error];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *eventMsg = [NSString stringWithFormat:@"[instance-id: %@]: running dashd successfully, trying to connect dashd server...", [masternode valueForKey:@"instanceId"]];
                clb(TRUE, nil, eventMsg);
            });
            
            if(error != nil) {
                NSLog(@"%@",[error localizedDescription]);
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSString *eventMsg = [NSString stringWithFormat:@"[instance-id: %@]: %@", [masternode valueForKey:@"instanceId"], [error localizedDescription]];
                    clb(FALSE, nil, eventMsg);
                });
            }
            
            sleep(20);
            NSString * previousSyncStatus = @"MASTERNODE_SYNC_INITIAL";
            int countConnect = 0;
            while (1) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSString *eventMsg = [NSString stringWithFormat:@"[instance-id: %@]: -%@ -rpcconnect=%@ -rpcuser=dash -rpcpassword=%@ mnsync status", [masternode valueForKey:@"instanceId"], chainNetwork, publicIP, rpcPassword];
                    clb(TRUE, nil, eventMsg);
                });
                NSError * error = nil;
                NSDictionary * dictionary = [self sendRPCCommandJSONDictionary:@"mnsync status" toPublicIP:publicIP rpcPassword:rpcPassword error:&error forChain:chainNetwork];
                countConnect = countConnect+1;
                
                if (error) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        NSString *eventMsg = [NSString stringWithFormat:@"[instance-id: %@]: %@", [masternode valueForKey:@"instanceId"], dictionary];
                        clb(FALSE, dictionary, eventMsg);
                    });
                    clb(NO,dictionary,nil);
                    break;
                } else {
                    if (dictionary) {
                        if (![previousSyncStatus isEqualToString:dictionary[@"AssetName"]]) {
                            if ([dictionary[@"AssetName"] isEqualToString:@"MASTERNODE_SYNC_FINISHED"]) {
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    [masternode setValue:@([MasternodeSyncStatusTransformer typeForTypeName:dictionary[@"AssetName"]]) forKey:@"syncStatus"];
                                    [[DPDataStore sharedInstance] saveContext];
                                    [self startRemoteMasternode:masternode clb:^(BOOL success, BOOL value, NSString *errorMessage) {
                                        if (!success) {
                                            NSString *eventMsg = [NSString stringWithFormat:@"[instance-id: %@]: %@", [masternode valueForKey:@"instanceId"], errorMessage];
                                            clb(FALSE, dictionary, eventMsg);
                                            clb(NO,dictionary,errorMessage);
                                        } else  if (value) {
                                            NSString *eventMsg = [NSString stringWithFormat:@"[instance-id: %@]: %@", [masternode valueForKey:@"instanceId"], dictionary];
                                            clb(TRUE, dictionary, eventMsg);
                                            clb(YES,dictionary,nil);
                                        }
                                    }];
                                });
                                break;
                            }else if ([dictionary[@"AssetName"] isEqualToString:@"MASTERNODE_SYNC_FAILED"]) {
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    [masternode setValue:@([MasternodeSyncStatusTransformer typeForTypeName:dictionary[@"AssetName"]]) forKey:@"syncStatus"];
                                    NSString *eventMsg = [NSString stringWithFormat:@"[instance-id: %@]: %@", [masternode valueForKey:@"instanceId"], dictionary];
                                    clb(FALSE, dictionary, eventMsg);
                                    clb(NO,dictionary,nil);
                                    [[DPDataStore sharedInstance] saveContext];
                                });
                                break;
                            }else {
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    [masternode setValue:@([MasternodeSyncStatusTransformer typeForTypeName:dictionary[@"AssetName"]]) forKey:@"syncStatus"];
                                    [[DPDataStore sharedInstance] saveContext];
                                });
                            }
                        }
                        else if ([dictionary[@"AssetName"] isEqualToString:@"MASTERNODE_SYNC_INITIAL"]) {
                            dispatch_async(dispatch_get_main_queue(), ^{
                                NSString *eventMsg = [NSString stringWithFormat:@"[instance-id: %@]: Error: Sync in progress. Must wait until sync is complete to start Masternode.", [masternode valueForKey:@"instanceId"]];
                                clb(FALSE, nil, eventMsg);
                            });
                            break;
                        }
                    }
                }
                if(countConnect >= 10) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        NSString *eventMsg = [NSString stringWithFormat:@"[instance-id: %@]: Error: could not retrieve server information! Make sure you already configure it.", [masternode valueForKey:@"instanceId"]];
                        clb(FALSE, nil, eventMsg);
                    });
                    break;
                }
                sleep(5);
            }
            [ssh disconnect];
        });
    } else {
        __block NSString * publicIP = [masternode valueForKey:@"publicIP"];
        __block NSString * rpcPassword = [masternode valueForKey:@"rpcPassword"];
        __block NSString * chainNetwork = [masternode valueForKey:@"chainNetwork"];
        __block NSString * previousSyncStatus = [MasternodeSyncStatusTransformer typeNameForType:[[masternode valueForKey:@"syncStatus"] unsignedIntegerValue]];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0),^{
//            CkoSsh * ssh = [self sshIn:publicIP] ;
//            if (!ssh){
//                dispatch_async(dispatch_get_main_queue(), ^{
//                    clb(NO,nil,@"Could not SSH in");
//                });
//                return;
//            }
            //  Send some commands and get the output.
            
            while (1) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSString *eventMsg = [NSString stringWithFormat:@"[instance-id: %@]: -%@ -rpcconnect=%@ -rpcuser=dash -rpcpassword=%@ mnsync status", chainNetwork, [masternode valueForKey:@"instanceId"], publicIP, rpcPassword];
                    clb(TRUE, nil, eventMsg);
                });
                NSError * error = nil;
                NSDictionary * dictionary = [self sendRPCCommandJSONDictionary:@"mnsync status" toPublicIP:publicIP rpcPassword:rpcPassword error:&error forChain:chainNetwork];
                
                if (error) {
                    clb(NO,dictionary,nil);
                    break;
                } else {
                    if (dictionary) {
                        if (![previousSyncStatus isEqualToString:dictionary[@"AssetName"]]) {
                            if ([dictionary[@"AssetName"] isEqualToString:@"MASTERNODE_SYNC_FINISHED"]) {
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    [masternode setValue:@([MasternodeSyncStatusTransformer typeForTypeName:dictionary[@"AssetName"]]) forKey:@"syncStatus"];
                                    [[DPDataStore sharedInstance] saveContext];
                                    [self startRemoteMasternode:masternode clb:^(BOOL success, BOOL value, NSString *errorMessage) {
                                        if (!success) {
                                            NSString *eventMsg = [NSString stringWithFormat:@"[instance-id: %@]: %@", [masternode valueForKey:@"instanceId"], errorMessage];
                                            clb(FALSE, dictionary, eventMsg);
                                            clb(NO,dictionary,errorMessage);
                                        } else  if (value) {
                                            NSString *eventMsg = [NSString stringWithFormat:@"[instance-id: %@]: %@", [masternode valueForKey:@"instanceId"], dictionary];
                                            clb(TRUE, dictionary, eventMsg);
                                            clb(YES,dictionary,nil);
                                        }
                                    }];
                                });
                                break;
                            }else if ([dictionary[@"AssetName"] isEqualToString:@"MASTERNODE_SYNC_FAILED"]) {
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    [masternode setValue:@([MasternodeSyncStatusTransformer typeForTypeName:dictionary[@"AssetName"]]) forKey:@"syncStatus"];
                                    NSString *eventMsg = [NSString stringWithFormat:@"[instance-id: %@]: %@", [masternode valueForKey:@"instanceId"], dictionary];
                                    clb(FALSE, dictionary, eventMsg);
                                    clb(NO,dictionary,nil);
                                    [[DPDataStore sharedInstance] saveContext];
                                });
                                break;
                            }else {
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    [masternode setValue:@([MasternodeSyncStatusTransformer typeForTypeName:dictionary[@"AssetName"]]) forKey:@"syncStatus"];
                                    [[DPDataStore sharedInstance] saveContext];
                                });
                            }
                        }
                    }
                }
                sleep(5);
            }
//            [ssh Disconnect];
        });
    }
}

- (void)startRemoteMasternode:(NSManagedObject*)masternode clb:(dashBoolClb)clb {
    NSString * string = [NSString stringWithFormat:@"-%@ masternode start-alias %@", [masternode valueForKey:@"chainNetwork"], [masternode valueForKey:@"instanceId"]];
    NSData * data = [[DPLocalNodeController sharedInstance] runDashRPCCommand:string];
    NSError * error = nil;
    NSDictionary * dictionary = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (error) return clb(NO,NO,[error localizedDescription]);
    if (dictionary && [dictionary[@"result"] isEqualToString:@"successful"]) clb(YES,YES,nil);
    else {
        clb(NO,NO,dictionary[@"result"]);
    }
}

#pragma mark - RPC Query Remote

-(NSData *)sendRPCCommand:(NSString*)command toPublicIP:(NSString*)publicIP rpcPassword:(NSString*)rpcPassword forChain:(NSString*)chainNetwork {
    NSString * fullCommand = [NSString stringWithFormat:@"-%@ -rpcconnect=%@ -rpcuser=dash -rpcpassword=%@ %@",chainNetwork,publicIP,rpcPassword, command];
    return [[DPLocalNodeController sharedInstance] runDashRPCCommand:fullCommand];
}

-(NSData *)sendRPCCommand:(NSString*)command toMasternode:(NSManagedObject*)masternode {
    return [self sendRPCCommand:command toPublicIP:[masternode valueForKey:@"publicIP"] rpcPassword:[masternode valueForKey:@"rpcPassword"] forChain:[masternode valueForKey:@"chainNetwork"]];
}

-(NSDictionary *)sendRPCCommandJSONDictionary:(NSString*)command toPublicIP:(NSString*)publicIP rpcPassword:(NSString*)rpcPassword error:(NSError**)error
                                     forChain:(NSString*)chainNetwork {
    NSData * data = [self sendRPCCommand:command toPublicIP:publicIP rpcPassword:rpcPassword forChain:chainNetwork];
    if (!data || data.length == 0) return @{};
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
}

-(NSDictionary *)sendRPCCommandJSONDictionary:(NSString*)command toMasternode:(NSManagedObject*)masternode error:(NSError**)error {
    NSData * data = [self sendRPCCommand:command toMasternode:masternode];
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
}

-(NSString *)sendRPCCommandString:(NSString*)command toMasternode:(NSManagedObject*)masternode {
    NSString * fullCommand = [NSString stringWithFormat:@"-%@ -rpcconnect=%@ -rpcuser=dash -rpcpassword=%@ %@", [masternode valueForKey:@"chainNetwork"],[masternode valueForKey:@"publicIP"],[masternode valueForKey:@"rpcPassword"], command];
    return [[DPLocalNodeController sharedInstance] runDashRPCCommandString:fullCommand forChain:nil];
}

-(void)getInfo:(NSManagedObject*)masternode clb:(dashInfoClb)clb {
    __block NSString * publicIp = [masternode valueForKey:@"publicIP"];
    __block NSString * rpcPassword = [masternode valueForKey:@"rpcPassword"];
    __block NSString * chainNetwork = [masternode valueForKey:@"chainNetwork"];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0),^{
        NSError * error = nil;
        NSDictionary * dictionary = [self sendRPCCommandJSONDictionary:@"getinfo" toPublicIP:publicIp rpcPassword:rpcPassword error:&error forChain:chainNetwork];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                clb(NO,nil,[error localizedDescription]);
            } else {
                clb(YES,dictionary,nil);
            }
        });
    });
}

#pragma mark - SSH Query Remote

-(void)updateGitInfoForMasternode:(NSManagedObject*)masternode clb:(dashInfoClb)clb {
    __block NSString * publicIP = [masternode valueForKey:@"publicIP"];
    __block NSString * branchName = [masternode valueForKeyPath:@"branch.name"];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0),^{
        
        __block NMSSHSession *ssh;
        [[SshConnection sharedInstance] sshInWithKeyPath:[self sshPath] masternodeIp:publicIP openShell:YES clb:^(BOOL success, NSString *message, NMSSHSession *sshSession) {
            ssh = sshSession;
        }];
        
        if (!ssh.isAuthorized) {
            dispatch_async(dispatch_get_main_queue(), ^{
                clb(NO,nil,@"SSH: error authenticating with server.");
            });
            return;
        }
        
        ssh.channel.requestPty = YES;
        
        NSDictionary * gitValues = [self sendGitCommands:@[@"rev-parse --short HEAD",@"rev-parse --abbrev-ref HEAD",@"remote -v"] onSSH:ssh];
        [ssh disconnect];
        __block NSString * remote = nil;
        NSArray * remoteInfoLine = [gitValues[@"remote -v"] componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\t "]];
        
        if (remoteInfoLine.count > 2 && [remoteInfoLine[2] isEqualToString:@"(fetch)"]) {
            remote = remoteInfoLine[1];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (remote) {
                NSManagedObject * branch = [[DPDataStore sharedInstance] branchNamed:gitValues[@"rev-parse --abbrev-ref HEAD"] onRepositoryURLPath:remote];
                if (branch && [branchName isEqualToString:[branch valueForKey:@"name"]]) {
                    [masternode setValue:branch forKey:@"branch"];
                    if (clb) clb(YES,@{@"hasChanges":@(TRUE)},nil);
                    return;
                }
            }
            if (![[masternode valueForKey:@"gitCommit"] isEqualToString:gitValues[@"rev-parse --short HEAD"]]) {
                [masternode setValue:gitValues[@"rev-parse --short HEAD"] forKey:@"gitCommit"];
                if (clb) clb(YES,@{@"hasChanges":@(TRUE)},nil);
                return;
            }
        });

//        CkoSsh * ssh = [self sshIn:publicIP];
//        if (!ssh) {
//            dispatch_async(dispatch_get_main_queue(), ^{
//                clb(NO,nil,@"Could not ssh in");
//            });
//            return;
//        }
//
//        NSDictionary * gitValues = [self sendGitCommands:@[@"rev-parse --short HEAD",@"rev-parse --abbrev-ref HEAD",@"remote -v"] onSSH:ssh];
//        [ssh Disconnect];
//        __block NSString * remote = nil;
//        NSArray * remoteInfoLine = [gitValues[@"remote -v"] componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\t "]];
//
//        if (remoteInfoLine.count > 2 && [remoteInfoLine[2] isEqualToString:@"(fetch)"]) {
//            remote = remoteInfoLine[1];
//        }
//        dispatch_async(dispatch_get_main_queue(), ^{
//            if (remote) {
//                NSManagedObject * branch = [[DPDataStore sharedInstance] branchNamed:gitValues[@"rev-parse --abbrev-ref HEAD"] onRepositoryURLPath:remote];
//                if (branch && [branchName isEqualToString:[branch valueForKey:@"name"]]) {
//                    [masternode setValue:branch forKey:@"branch"];
//                    return clb(YES,@{@"hasChanges":@(TRUE)},nil);
//                }
//            }
//            if (![[masternode valueForKey:@"gitCommit"] isEqualToString:gitValues[@"rev-parse --short HEAD"]]) {
//                [masternode setValue:gitValues[@"rev-parse --short HEAD"] forKey:@"gitCommit"];
//                return clb(YES,@{@"hasChanges":@(TRUE)},nil);
//            }
//        });
        
    });
}

#pragma mark - SSH in info

-(void)retrieveConfigurationInfoThroughSSH:(NSManagedObject*)masternode clb:(dashInfoClb)clb {
    __block NSString * publicIP = [masternode valueForKey:@"publicIP"];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0),^{
        
        __block NMSSHSession *ssh;
        [[SshConnection sharedInstance] sshInWithKeyPath:[self sshPath] masternodeIp:publicIP openShell:NO clb:^(BOOL success, NSString *message, NMSSHSession *sshSession) {
            ssh = sshSession;
            if(!ssh.authorized) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    clb(NO,nil,@"Could not ssh in");
                });
                return;
            }
        }];
        
        NSError *error = nil;
        NSString *strOutput = [ssh.channel execute:@"cat .dashcore/dash.conf" error:&error];
        if(error) {
            NSLog(@"%@",[error localizedDescription]);
            dispatch_async(dispatch_get_main_queue(), ^{
                clb(NO,nil,@"Could not retieve configuration file");
            });
            return;
        }
        [ssh disconnect];
        
        NSArray * lines = [strOutput componentsSeparatedByString:@"\n"];
        __block NSMutableDictionary * rDict = [NSMutableDictionary dictionary];
        for (NSString * line in lines) {
            if ([line hasPrefix:@"#"] || ![line containsString:@"="]) continue;
            NSArray * valueKeys =[line componentsSeparatedByString:@"="];
            [rDict setObject:valueKeys[1] forKey:valueKeys[0]];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            return clb(YES,rDict,nil);
        });
    });
    
}

#pragma mark - Masternode Checks

- (void)checkMasternodeIsInstalled:(NSManagedObject*)masternode clb:(dashBoolClb)clb {
    __block NSString * publicIP = [masternode valueForKey:@"publicIP"];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0),^{
        
        __block NMSSHSession *ssh;
        [[SshConnection sharedInstance] sshInWithKeyPath:[self sshPath] masternodeIp:publicIP openShell:YES clb:^(BOOL success, NSString *message, NMSSHSession *sshSession) {
            ssh = sshSession;
        }];
        
        if (!ssh.isAuthorized) {
            dispatch_async(dispatch_get_main_queue(), ^{
                clb(NO,NO,@"SSH: error authenticating with server.");
            });
            return;
        }
        
        ssh.channel.requestPty = YES;
        
        NSError *error = nil;
        [ssh.channel execute:@"cd src/dash" error:&error];
        [ssh disconnect];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                return clb(YES,NO,nil);
            }
            else {
                return clb(YES,YES,nil);
            }
        });
        
//        CkoSsh * ssh = [self sshIn:publicIP];
//        if (!ssh) {
//            dispatch_async(dispatch_get_main_queue(), ^{
//                clb(NO,NO,@"Could not ssh in");
//            });
//            return;
//        }
//        //  Send some commands and get the output.
//        NSString *strOutput = [[ssh QuickCommand: @"ls src | grep '^dash$'" charset: @"ansi"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
//        if (ssh.LastMethodSuccess != YES) {
//            NSLog(@"%@",ssh.LastErrorText);
//            [ssh Disconnect];
//            dispatch_async(dispatch_get_main_queue(), ^{
//                clb(NO,NO,@"ssh failure");
//            });
//            return;
//        }
//        [ssh Disconnect];
//
//        dispatch_async(dispatch_get_main_queue(), ^{
//            if ([strOutput isEqualToString:@"dash"]) {
//                return clb(YES,YES,nil);
//            }else {
//                return clb(YES,NO,nil);
//            }
//        });
    });
}


-(BOOL)checkMasternodeIsProperlyConfigured:(NSManagedObject *)masternode {
    return TRUE;
}

-(void)checkMasternodeChainNetwork:(NSManagedObject*)masternode {
    
    if([masternode valueForKey:@"publicIP"] == nil) return;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0),^{
        [[SshConnection sharedInstance] sshInWithKeyPath:[self sshPath] masternodeIp:[masternode valueForKey:@"publicIP"] openShell:NO clb:^(BOOL success, NSString *message, NMSSHSession *sshSession) {
            
            if(success != YES) return;
            
            __block BOOL isSuccess = YES;
            NSError *error = nil;
            
            [[SshConnection sharedInstance] sendExecuteCommand:@"cd ~/.dashcore" onSSH:sshSession error:error dashClb:^(BOOL success, NSString *message) {
                isSuccess = success;
            }];
            if(isSuccess != YES) return;
            
            [[SshConnection sharedInstance] sendExecuteCommand:@"cd ~/.dashcore && cat dash.conf" onSSH:sshSession error:error dashClb:^(BOOL success, NSString *message) {
                isSuccess = success;
                if(success == YES && message != nil){
                    NSArray *dashConf = [message componentsSeparatedByString:@"\n"];
                    NSString *chainString = @"";
                    
                    for(NSString *line in dashConf) {
                        if ([line rangeOfString:@"mainnet"].location != NSNotFound)
                        {
                            chainString = @"mainnet";
                            break;
                        }
                        else if ([line rangeOfString:@"testnet"].location != NSNotFound)
                        {
                            chainString = @"testnet";
                            break;
                        }
                        else if ([line rangeOfString:@"devnet"].location != NSNotFound)
                        {
                            NSArray *netArray = [line componentsSeparatedByString:@"="];
                            if([netArray count] == 2) {
                                chainString = [NSString stringWithFormat:@"devnet-%@",[netArray objectAtIndex:1]];
                            }
                            else {
                                chainString = @"devnet-none";
                            }
                            break;
                        }
                    }
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [masternode setValue:chainString forKey:@"chainNetwork"];
                        [[DPDataStore sharedInstance] saveContext:masternode.managedObjectContext];
                    });
                }
                else {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [masternode setValue:@"none" forKey:@"chainNetwork"];
                        [[DPDataStore sharedInstance] saveContext:masternode.managedObjectContext];
                    });
                }
            }];
            if(isSuccess != YES) return;
        }];
    });
}

-(void)checkMasternodeIsProperlyInstalled:(NSManagedObject*)masternode onSSH:(NMSSHSession*)ssh {
    [self IsMasternodeIsProperlyInstalled:[masternode valueForKey:@"publicIP"] onSSH:ssh dashClb:^(BOOL success, NSString *message) {
        if(success == YES) {
            [masternode setValue:@(MasternodeState_Installed) forKey:@"masternodeState"];
            [[DPDataStore sharedInstance] saveContext:masternode.managedObjectContext];
        }
        else {
            [masternode setValue:@(MasternodeState_SettingUp) forKey:@"masternodeState"];
            [[DPDataStore sharedInstance] saveContext:masternode.managedObjectContext];
        }
    }];
}

-(void)IsMasternodeIsProperlyInstalled:(NSString*)publicIP onSSH:(NMSSHSession*)ssh dashClb:(dashClb)clb {
//    __block NSString * publicIP = [masternode valueForKey:@"publicIP"];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0),^{
        
        NSError *error;
        
        //does this masternode execute .autogen.sh?
        NSString *response = [ssh.channel execute:@"ls ~/src/dash/configure" error:&error];
        if(error || [response length] == 0) {//no
            
            [[SshConnection sharedInstance] sendDashCommandsList:@[@"autogen.sh",@"configure"] onSSH:ssh onPath:@"~/src/dash/" error:error dashClb:^(BOOL success, NSString *call) {
                NSLog(@"SSH-%@: %@", publicIP, call);
                clb(success,call);
            }];
            
            [[SshConnection sharedInstance] sendExecuteCommand:@"cd ~/src; make --file=~/src/Makefile" onSSH:ssh error:error dashClb:^(BOOL success, NSString *message) {
                NSLog(@"SSH-%@: %@", publicIP, message);
                clb(success,message);
            }];
        }
        else {//yes
            //does this masternode execute ./configure?
            NSString *response = [ssh.channel execute:@"ls ~/src/dash/Makefile" error:&error];
            if(error || [response length] == 0) {//no
                
                [[SshConnection sharedInstance] sendDashCommandsList:@[@"configure"] onSSH:ssh onPath:@"~/src/dash/" error:error dashClb:^(BOOL success, NSString *call) {
                    NSLog(@"SSH-%@: %@", publicIP, call);
                    clb(success,call);
                }];
                
                [[SshConnection sharedInstance] sendExecuteCommand:@"cd ~/src; make --file=~/src/Makefile" onSSH:ssh error:error dashClb:^(BOOL success, NSString *message) {
                    NSLog(@"SSH-%@: %@", publicIP, message);
                    clb(success,message);
                }];
            }
            else {//yes
                //does this masternode execute ./make?
                NSString *response = [ssh.channel execute:@"ls ~/src/dash/src/dashd" error:&error];
                if(error || [response length] == 0) {//no
                    
                    [[SshConnection sharedInstance] sendExecuteCommand:@"cd ~/src; make --file=~/src/Makefile" onSSH:ssh error:error dashClb:^(BOOL success, NSString *message) {
                        NSLog(@"SSH-%@: %@", publicIP, message);
                        clb(success,message);
                    }];
                    
                }
                else {
                    clb(YES,nil);
                }
            }
        }
        
        
    });
}

-(void)checkMasternode:(NSManagedObject*)masternode {
    [self checkMasternode:masternode saveContext:TRUE clb:nil];
}

-(void)checkMasternode:(NSManagedObject*)masternode saveContext:(BOOL)saveContext clb:(dashClb)clb {
    //we are going to check if a masternode is running, configured, etc...
    //first let's check to see if we have access to rpc
    if ([masternode valueForKey:@"rpcPassword"]) {
        //we most likely have access to rpc, it's running
        [self getInfo:masternode clb:^(BOOL success, NSDictionary *dictionary, NSString *errorMessage) {
            if (dictionary) {
                [masternode setValue:@(MasternodeState_Running) forKey:@"masternodeState"];
                [masternode setValue:dictionary[@"blocks"] forKey:@"lastBlock"];
                [[DPDataStore sharedInstance] saveContext:masternode.managedObjectContext];
            } else {
                [self checkMasternodeIsInstalled:masternode clb:^(BOOL success, BOOL value, NSString *errorMessage) {
                    if (value) {
                        NSDictionary * dictionary = [[DPLocalNodeController sharedInstance] masternodeInfoInMasternodeConfigurationFileForMasternode:masternode];
                        if (dictionary && [dictionary[@"publicIP"] isEqualToString:[masternode valueForKey:@"publicIP"]]) {
                            [masternode setValuesForKeysWithDictionary:dictionary];
                            [masternode setValue:@(MasternodeState_Configured) forKey:@"masternodeState"];
                            if ([masternode hasChanges]) {
                                [[DPDataStore sharedInstance] saveContext:masternode.managedObjectContext];
                            }
                            [self updateGitInfoForMasternode:masternode clb:nil];
                        } else {
                            if ([[masternode valueForKey:@"masternodeState"] integerValue] != MasternodeState_Installed) {
                                [masternode setValue:@(MasternodeState_Installed) forKey:@"masternodeState"];
                                [[DPDataStore sharedInstance] saveContext:masternode.managedObjectContext];
                            }
                            [self updateGitInfoForMasternode:masternode clb:nil];
                        }
                    } else {
                        if ([[masternode valueForKey:@"masternodeState"] integerValue] != MasternodeState_Initial) {
                            [masternode setValue:@(MasternodeState_Initial) forKey:@"masternodeState"];
                            [[DPDataStore sharedInstance] saveContext:masternode.managedObjectContext];
                        }
                    }
                }];
            }
        }];
        
        
    } else { //we don't have access to the rpc, let's ssh in and retrieve it.
        [self retrieveConfigurationInfoThroughSSH:masternode clb:^(BOOL success, NSDictionary *info, NSString *errorMessage) {
            
            if (![info[@"externalip"] isEqualToString:[masternode valueForKey:@"publicIP"]]) {
                //the masternode has never been configured
                [self checkMasternodeIsInstalled:masternode clb:^(BOOL success, BOOL value, NSString *errorMessage) {
                    if (value) {
                        if ([[masternode valueForKey:@"masternodeState"] integerValue] != MasternodeState_Installed) {
                            [masternode setValue:@(MasternodeState_Installed) forKey:@"masternodeState"];
                            [[DPDataStore sharedInstance] saveContext:masternode.managedObjectContext];
                        }
                        [self updateGitInfoForMasternode:masternode clb:nil];
                    } else {
                        if ([[masternode valueForKey:@"masternodeState"] integerValue] != MasternodeState_Initial) {
                            [masternode setValue:@(MasternodeState_Initial) forKey:@"masternodeState"];
                            [[DPDataStore sharedInstance] saveContext:masternode.managedObjectContext];
                        }
                    }
                }];
            } else {
                [masternode setValue:info[@"rpcpassword"] forKey:@"rpcPassword"];
                [masternode setValue:info[@"masternodeprivkey"] forKey:@"key"];
                [[DPDataStore sharedInstance] saveContext:masternode.managedObjectContext];
                [self getInfo:masternode clb:^(BOOL success, NSDictionary *dictionary, NSString *errorMessage) {
                    if (dictionary) {
                        [masternode setValue:@(MasternodeState_Running) forKey:@"masternodeState"];
                        [masternode setValue:dictionary[@"blocks"] forKey:@"lastBlock"];
                        [self updateGitInfoForMasternode:masternode clb:nil];
                        [[DPDataStore sharedInstance] saveContext:masternode.managedObjectContext];
                    } else {
                        [self checkMasternodeIsInstalled:masternode clb:^(BOOL success, BOOL value, NSString *errorMessage) {
                            if (value) {
                                NSDictionary * dictionary = [[DPLocalNodeController sharedInstance] masternodeInfoInMasternodeConfigurationFileForMasternode:masternode];
                                if (dictionary && [dictionary[@"publicIP"] isEqualToString:[masternode valueForKey:@"publicIP"]]) {
                                    [masternode setValuesForKeysWithDictionary:dictionary];
                                    [masternode setValue:@(MasternodeState_Configured) forKey:@"masternodeState"];
                                } else {
                                    [masternode setValue:@(MasternodeState_Installed) forKey:@"masternodeState"];
                                }
                                if ([masternode hasChanges]) {
                                    [[DPDataStore sharedInstance] saveContext:masternode.managedObjectContext];
                                }
                                [self updateGitInfoForMasternode:masternode clb:nil];
                            } else {
                                if ([[masternode valueForKey:@"masternodeState"] integerValue] != MasternodeState_Initial) {
                                    [masternode setValue:@(MasternodeState_Initial) forKey:@"masternodeState"];
                                    [[DPDataStore sharedInstance] saveContext:masternode.managedObjectContext];
                                }
                            }
                        }];
                    }
                }];
            }
        }];
        
    }
}

#pragma mark - Masternode Fixes

- (BOOL)removeDatFilesFromMasternode:(NSManagedObject*)masternode {
    
    __block NMSSHSession *ssh;
    [[SshConnection sharedInstance] sshInWithKeyPath:[self sshPath] masternodeIp:[masternode valueForKey:@"publicIP"] openShell:NO clb:^(BOOL success, NSString *message, NMSSHSession *sshSession) {
        ssh = sshSession;
    }];
    
    if(!ssh.authorized) {
        return FALSE;
    }
    
    NSError * error = nil;
    [[SshConnection sharedInstance] sendDashCommandsList:@[@"rm -rf {banlist,fee_estimates,budget,governance,mncache,mnpayments,netfulfilled,peers}.dat"] onSSH:ssh onPath:@"cd ~/.dashcore" error:error dashClb:^(BOOL success, NSString *call) {
        
    }];
    [ssh disconnect];
    
//    CkoSsh * ssh = [self sshIn:[masternode valueForKey:@"publicIP"]];
//    if (!ssh) return FALSE;
//    //now let's make all this shit
//    NSError * error = nil;
//    [self sendCommandList:@[@"rm -rf {banlist,fee_estimates,budget,governance,mncache,mnpayments,netfulfilled,peers}.dat"] toPath:@"~/.dashcore/" onSSH:ssh error:&error];
//
//    [ssh Disconnect];
    
    return TRUE;
    
    
}

#pragma mark - Sentinel Checks


#pragma mark - AWS Core

- (NSString *)runAWSCommandString:(NSString *)commandToRun
{
    
    NSString *output = [[NSString alloc] initWithData:[self runAWSCommand:commandToRun] encoding:NSUTF8StringEncoding];
    return output;
}

- (NSDictionary *)runAWSCommandJSON:(NSString *)commandToRun
{
    NSData * data = [self runAWSCommand:commandToRun];
    NSError * error = nil;
    NSDictionary *output = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error: &error];
    return output;
}

- (NSData *)runAWSCommand:(NSString *)commandToRun
{
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/usr/local/bin/aws"];
    
//    if([task isRunning])
//    {
//        NSLog(@"Aws is running!!");
//    }
//    else
//    {
//        NSLog(@"Aws not found!!");
//        return nil;
//    }
    
    
    NSArray *arguments = [commandToRun componentsSeparatedByString:@" "];
    
    //TOEY, add newArguments variable to handle a case that has sentence like "We are developer".
    NSMutableArray *newArguments = [self getArgumentsWithSentence:arguments];
    
    NSLog(@"run command:%@", commandToRun);
    [task setArguments:newArguments];
    
    NSPipe *pipe = [NSPipe pipe];
    [task setStandardOutput:pipe];
    
    NSFileHandle *file = [pipe fileHandleForReading];
    
    NSPipe *errorPipe = [NSPipe pipe];
    [task setStandardError:errorPipe];
    
    NSFileHandle *error = [errorPipe fileHandleForReading];
    
    [task launch];
    [task waitUntilExit]; //Toey, wait until finish launching task to show error.
    
    //Toey, add this stuff to show error alert.
    NSData * dataError = [error readDataToEndOfFile];
    NSString * strError = [[NSString alloc] initWithData:dataError encoding:NSUTF8StringEncoding];
    dispatch_async(dispatch_get_main_queue(), ^{
        if([strError length] != 0){
            [[DialogAlert sharedInstance] showWarningAlert:@"Error" message:[NSString stringWithFormat:@"%@", strError]];
            NSLog(@"%@", strError);
        }
    });
    
    return [file readDataToEndOfFile];
}

-(NSMutableArray*)getArgumentsWithSentence:(NSArray*)arguments {
    
    NSMutableArray *newArguments = [[NSMutableArray alloc] init];
    NSString *str = @"";
    BOOL isConcating = false;
    
    for (NSString *string in arguments)
    {
//        if(terminalType) {
//            if(arguments[0])
//            {
//                terminalType = false;
//                continue;
//            }
//        }
        if([string length] == 0) continue;
        
        NSString *firstChar = [string substringToIndex:1];
        NSString *lastChar = [string substringFromIndex:[string length] - 1];
        
        if([firstChar isEqualToString:@"\""] && [lastChar isEqualToString:@"\""])
        {
            NSString *cutFirst = [string substringFromIndex:1];
            NSString *cutLast = [cutFirst substringToIndex:[cutFirst length] - 1];
            [newArguments addObject:cutLast];
        }
        else if([firstChar isEqualToString:@"\""]) {
            str = [str stringByAppendingString:string];
            isConcating = true;
        }
        else if([lastChar isEqualToString:@"\""])
        {
            str = [str stringByAppendingString:[NSString stringWithFormat:@" %@",string]];
            NSString *cutFirst = [str substringFromIndex:1];
            NSString *cutLast = [cutFirst substringToIndex:[cutFirst length] - 1];
            //            NSLog(@"%@", cutLast);
            [newArguments addObject:cutLast];
            isConcating = false;
            str = @"";
        }
        else{
            if(isConcating)
            {
                str = [str stringByAppendingString:[NSString stringWithFormat:@" %@",string]];
            }
            else{
                [newArguments addObject:string];
                //                NSLog(@"%@", string);
            }
        }
    }
    return newArguments;
}

#pragma mark - Instances

-(void)setUpInstances:(NSInteger)count onBranch:(NSManagedObject*)branch clb:(dashInfoClb)clb onRegion:(NSMutableArray*)regionArray serverType:(NSString*)serverType {
    
    if (![self sshPath] || ![self getSshName]) {
        DialogAlert *dialog=[[DialogAlert alloc]init];
        NSAlert *findPathAlert = [dialog getFindPathAlert:@"SSH_KEY.pem" exPath:@"~/Documents"];
        
        if ([findPathAlert runModal] == NSAlertFirstButtonReturn) {
            //Find clicked
            NSArray *fileInfo = [dialog getSSHLaunchPathAndName];
            [self setSshPath:fileInfo[1]];
            
            NSArray* nameArray = [fileInfo[0] componentsSeparatedByString: @"."];
            NSString* nameString = [nameArray objectAtIndex: 0];
            
            [self setSshName:nameString];
        }
    }
    
    if([[PreferenceData sharedInstance] getSecurityGroupId]
       ||[[PreferenceData sharedInstance] getSubnetID]
       ||[[PreferenceData sharedInstance] getKeyName])
    {
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0),^{
            
            //check repository's AMI
            NSString *imageId = @"";
            if([[branch valueForKey:@"amiId"] isEqualToString:@""] || [branch valueForKey:@"amiId"] == nil)
            {
                imageId = @"ami-38ad8444"; //this is initial dash image id
            }
            else{
                imageId = [branch valueForKey:@"amiId"];
            }
            
            __block NSMutableDictionary * instances = [NSMutableDictionary dictionary];
            
            //loop for creating new instance
//            for (int i = 1; i <= count; i++)
//            {
//                NSInteger arrayIndex;
//                if([regionArray count] == 1){
//                    arrayIndex = 0;
//                }
//                else {
//                    arrayIndex = i-1;
//                }
//
//                NSDictionary *output = [self runAWSCommandJSON:[NSString stringWithFormat:@"ec2 run-instances --image-id %@ --instance-type %@ --key-name %@ --security-group-ids %@ --instance-initiated-shutdown-behavior terminate --subnet-id %@ --placement AvailabilityZone=%@a",
//                                                                   imageId,
//                                                                serverType,
//                                                                   [[PreferenceData sharedInstance] getKeyName],
//                                                                   [[PreferenceData sharedInstance] getSecurityGroupId],
//                                                                   [[PreferenceData sharedInstance] getSubnetID],
//                                                                   [regionArray objectAtIndex:arrayIndex]]];
//
//                //NSLog(@"%@",reservation[@"Instances"]);
//                for (NSDictionary * dictionary in output[@"Instances"]) {
//                    NSDictionary * rDict = [NSMutableDictionary dictionary];
//                    [rDict setValue:[dictionary valueForKey:@"InstanceId"] forKey:@"instanceId"];
//                    [rDict setValue:@(MasternodeState_Initial)  forKey:@"masternodeState"];
//                    [rDict setValue:@([self stateForStateName:[dictionary valueForKeyPath:@"State.Name"]]) forKey:@"instanceState"];
//                    [instances setObject:rDict forKey:[dictionary valueForKey:@"InstanceId"]];
//                }
//            }
            
            NSDictionary *output = [self runAWSCommandJSON:[NSString stringWithFormat:@"ec2 run-instances --image-id %@ --count %ld --instance-type %@ --key-name %@ --security-group-ids %@ --instance-initiated-shutdown-behavior terminate --subnet-id %@ ",imageId,count,serverType,[[PreferenceData sharedInstance] getKeyName],[[PreferenceData sharedInstance] getSecurityGroupId],[[PreferenceData sharedInstance] getSubnetID]]];
            
            //NSLog(@"%@",reservation[@"Instances"]);
            for (NSDictionary * dictionary in output[@"Instances"]) {
                NSDictionary * rDict = [NSMutableDictionary dictionary];
                [rDict setValue:[dictionary valueForKey:@"InstanceId"] forKey:@"instanceId"];
                [rDict setValue:@(MasternodeState_Initial)  forKey:@"masternodeState"];
                [rDict setValue:@([self stateForStateName:[dictionary valueForKeyPath:@"State.Name"]]) forKey:@"instanceState"];
                [instances setObject:rDict forKey:[dictionary valueForKey:@"InstanceId"]];
            }
            
        
            NSMutableArray * instanceIdsLeft = [[instances allKeys] mutableCopy];
            while ([instanceIdsLeft count]) {
                NSDictionary *output2 = [self runAWSCommandJSON:[NSString stringWithFormat:@"ec2 describe-instances --instance-ids %@ --filter Name=key-name,Values=%@",[instanceIdsLeft componentsJoinedByString:@" "], [[PreferenceData sharedInstance] getKeyName]] ];
                NSArray * reservations = output2[@"Reservations"];
                for (NSDictionary * reservation in reservations) {
                    //NSLog(@"%@",reservation[@"Instances"]);
                    for (NSDictionary * dictionary in reservation[@"Instances"]) {
                        if ([dictionary valueForKey:@"PublicIpAddress"] && ![[dictionary valueForKeyPath:@"State.Name"] isEqualToString:@"pending"]) {
                            
                            [[SshConnection sharedInstance] sshInWithKeyPath:[self sshPath] masternodeIp:[dictionary valueForKey:@"PublicIpAddress"] openShell:NO clb:^(BOOL success, NSString *message, NMSSHSession *sshSession) {
                                if (sshSession.isAuthorized) {
                                    [[instances objectForKey:[dictionary valueForKey:@"InstanceId"]] setValue:[dictionary valueForKey:@"PublicIpAddress"] forKey:@"publicIP"];
                                    [[instances objectForKey:[dictionary valueForKey:@"InstanceId"]] setValue:@([self stateForStateName:[dictionary valueForKeyPath:@"State.Name"]]) forKey:@"instanceState"];
                                    [instanceIdsLeft removeObject:[dictionary valueForKey:@"InstanceId"]];
                                    [sshSession disconnect];
                                }
                            }];
                        }
                    }
                }
                if (instanceIdsLeft) sleep(5);
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                NSArray * masternodes = [self saveInstances:[instances allValues]];
                for (NSManagedObject * masternode in masternodes) {
                    [masternode setValue:branch forKey:@"branch"];
                    [[DPDataStore sharedInstance] saveContext];
                    [self setUpMasternodeDashd:masternode clb:^(BOOL success, NSString *message) {
                        if (!success) {
                            clb(NO,nil,message);
                            NSLog(@"");
                        }
                    }];
                }
                [[DialogAlert sharedInstance] showAlertWithOkButton:@"Instance" message:@"Instance created successfully."];
            });
        });
    
    }
    else{
        [[DialogAlert sharedInstance] showAlertWithOkButton:@"Unable to create new instance!" message:@"Please configure your AWS account."];
        
        PreferenceViewController *prefController = [[PreferenceViewController alloc] init];
        [prefController showConfiguringWindow];
    }
}

-(void)keepTabsOnInstance:(NSString*)instanceId clb:(dashStateClb)clb  {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0),^{
        [NSTimer scheduledTimerWithTimeInterval:10 repeats:TRUE block:^(NSTimer * _Nonnull timer) {
            [self checkInstance:instanceId clb:^(BOOL success, InstanceState state, NSString *message) {
                if (!InstanceState_Transitional(state)) {
                    
                }
            }];
        }];
        
    });
}

- (void)runInstances:(NSInteger)count clb:(dashStateClb)clb serverType:(NSString*)serverType {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0),^{
        NSDictionary *output = [self runAWSCommandJSON:[NSString stringWithFormat:@"ec2 run-instances --image-id ami-38ad8444 --count %ld --instance-type %@ --key-name %@ --security-group-ids %@ --instance-initiated-shutdown-behavior terminate --subnet-id %@",
                                                        (long)count,
                                                        serverType,
                                                        [[PreferenceData sharedInstance] getKeyName],
                                                        [[PreferenceData sharedInstance] getSecurityGroupId],
                                                        [[PreferenceData sharedInstance] getSubnetID]] ];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (output[@"Instances"]) {
                NSMutableArray * instances = [NSMutableArray array];
                //NSLog(@"%@",reservation[@"Instances"]);
                for (NSDictionary * dictionary in output[@"Instances"]) {
                    NSDictionary * rDict = [NSMutableDictionary dictionary];
                    [rDict setValue:[dictionary valueForKey:@"InstanceId"] forKey:@"instanceId"];
                    [rDict setValue:[dictionary valueForKey:@"PublicIpAddress"] forKey:@"publicIP"];
                    [rDict setValue:@([self stateForStateName:[dictionary valueForKeyPath:@"State.Name"]]) forKey:@"instanceState"];
                    [instances addObject:rDict];
                }
                [self saveInstances:instances];
            } else {
                clb(FALSE,InstanceState_Unknown,FS(@"Unable to process the creation of %ld instance%@",count,count>1?@"s":@""));
            }
        });
    });
}

- (void)startInstance:(NSString*)instanceId clb:(dashStateClb)clb  {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0),^{
        NSDictionary *output = [self runAWSCommandJSON:[NSString stringWithFormat:@"ec2 start-instances --instance-ids %@",instanceId]];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (output[@"StartingInstances"]) {
                for (NSDictionary * instance in output[@"StartingInstances"]) {
                    if (instance[@"InstanceId"] && instance[@"CurrentState"] && instance[@"CurrentState"][@"Name"]) {
                        [[DPDataStore sharedInstance] updateMasternode:instance[@"InstanceId"] withState:[self stateForStateName:instance[@"CurrentState"][@"Name"]]];
                        clb(TRUE,[self stateForStateName:instance[@"CurrentState"][@"Name"]],instance[@"InstanceId"]);
                    }
                }
            } else {
                clb(FALSE,InstanceState_Unknown,@"Unable to process the start of instance(s)");
            }
        });
    });
}

- (void)stopInstance:(NSString*)instanceId clb:(dashStateClb)clb {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0),^{
        NSDictionary *output = [self runAWSCommandJSON:[NSString stringWithFormat:@"ec2 stop-instances --instance-ids %@",instanceId]];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (output[@"StoppingInstances"]) {
                for (NSDictionary * instance in output[@"StoppingInstances"]) {
                    if (instance[@"InstanceId"] && instance[@"CurrentState"] && instance[@"CurrentState"][@"Name"]) {
                        [[DPDataStore sharedInstance] updateMasternode:instance[@"InstanceId"] withState:[self stateForStateName:instance[@"CurrentState"][@"Name"]]];
                        clb(TRUE,[self stateForStateName:instance[@"CurrentState"][@"Name"]],instance[@"InstanceId"]);
                    }
                }
            } else {
                clb(FALSE,InstanceState_Unknown,@"Unable to process the stop of instance(s)");
            }
        });
    });
}

- (void)terminateInstance:(NSString*)instanceId clb:(dashStateClb)clb {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0),^{
        NSDictionary *output = [self runAWSCommandJSON:[NSString stringWithFormat:@"ec2 terminate-instances --instance-ids %@",instanceId]];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (output[@"TerminatingInstances"]) {
                for (NSDictionary * instance in output[@"TerminatingInstances"]) {
                    if (instance[@"InstanceId"] && instance[@"CurrentState"] && instance[@"CurrentState"][@"Name"]) {
                        [[DPDataStore sharedInstance] updateMasternode:instance[@"InstanceId"] withState:[self stateForStateName:instance[@"CurrentState"][@"Name"]]];
                        clb(TRUE,[self stateForStateName:instance[@"CurrentState"][@"Name"]],instance[@"InstanceId"]);
                    }
                }
            } else {
                clb(FALSE,InstanceState_Unknown,@"Unable to process the terminatation instance(s)");
            }
        });
    });
}

- (void)checkInstance:(NSString*)instanceId clb:(dashStateClb)clb {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0),^{
        NSDictionary *output = [self runAWSCommandJSON:[NSString stringWithFormat:@"ec2 describe-instances --filter Name=key-name,Values=%@",
                                                        [[PreferenceData sharedInstance] getKeyName]]];
        NSArray * reservations = output[@"Reservations"];
        NSMutableArray * instances = [NSMutableArray array];
        for (NSDictionary * reservation in reservations) {
            //NSLog(@"%@",reservation[@"Instances"]);
            for (NSDictionary * dictionary in reservation[@"Instances"]) {
                NSDictionary * rDict = [NSMutableDictionary dictionary];
                [rDict setValue:[dictionary valueForKey:@"InstanceId"] forKey:@"instanceId"];
                [rDict setValue:[dictionary valueForKey:@"PublicIpAddress"] forKey:@"publicIP"];
                [rDict setValue:@([self stateForStateName:[dictionary valueForKeyPath:@"State.Name"]]) forKey:@"instanceState"];
                [instances addObject:rDict];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            NSArray * newMasternodes = [self saveInstances:instances removeOthers:TRUE];
            for (NSManagedObject * masternode in newMasternodes) {
                [self checkMasternode:masternode];
            }
            clb(output?TRUE:FALSE,InstanceState_Unknown,@"Successfully refreshed");
        });
    });
}

- (void)createInstanceWithInitialAMI:(dashStateClb)clb serverType:(NSString*)serverType  {
    
    if (![self sshPath] || ![self getSshName]) {
        DialogAlert *dialog=[[DialogAlert alloc]init];
        NSAlert *findPathAlert = [dialog getFindPathAlert:@"SSH_KEY.pem" exPath:@"~/Documents"];
        
        if ([findPathAlert runModal] == NSAlertFirstButtonReturn) {
            //Find clicked
            NSArray *fileInfo = [dialog getSSHLaunchPathAndName];
            [self setSshPath:fileInfo[1]];
            
            NSArray* nameArray = [fileInfo[0] componentsSeparatedByString: @"."];
            NSString* nameString = [nameArray objectAtIndex: 0];
            
            [self setSshName:nameString];
        }
    }
    
    if([[PreferenceData sharedInstance] getSecurityGroupId]
       ||[[PreferenceData sharedInstance] getSubnetID]
       ||[[PreferenceData sharedInstance] getKeyName])
    {
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0),^{
            NSDictionary *output = [self runAWSCommandJSON:[NSString stringWithFormat:@"ec2 run-instances --image-id ami-38ad8444 --count 1 --instance-type %@ --key-name %@ --security-group-ids %@ --instance-initiated-shutdown-behavior terminate --subnet-id %@",
                                                            serverType,
                                                            [[PreferenceData sharedInstance] getKeyName],
                                                            [[PreferenceData sharedInstance] getSecurityGroupId],
                                                            [[PreferenceData sharedInstance] getSubnetID]] ];
            
            __block NSMutableDictionary * instances = [NSMutableDictionary dictionary];
            //NSLog(@"%@",reservation[@"Instances"]);
            for (NSDictionary * dictionary in output[@"Instances"]) {
                NSDictionary * rDict = [NSMutableDictionary dictionary];
                [rDict setValue:[dictionary valueForKey:@"InstanceId"] forKey:@"instanceId"];
                [rDict setValue:@(MasternodeState_Initial)  forKey:@"masternodeState"];
                [rDict setValue:@([self stateForStateName:[dictionary valueForKeyPath:@"State.Name"]]) forKey:@"instanceState"];
                [instances setObject:rDict forKey:[dictionary valueForKey:@"InstanceId"]];
            }
            NSMutableArray * instanceIdsLeft = [[instances allKeys] mutableCopy];
            while ([instanceIdsLeft count]) {
                NSDictionary *output2 = [self runAWSCommandJSON:[NSString stringWithFormat:@"ec2 describe-instances --instance-ids %@ --filter Name=key-name,Values=%@",[instanceIdsLeft componentsJoinedByString:@" "], [[PreferenceData sharedInstance] getKeyName]] ];
                NSArray * reservations = output2[@"Reservations"];
                for (NSDictionary * reservation in reservations) {
                    //NSLog(@"%@",reservation[@"Instances"]);
                    for (NSDictionary * dictionary in reservation[@"Instances"]) {
                        if ([dictionary valueForKey:@"PublicIpAddress"] && ![[dictionary valueForKeyPath:@"State.Name"] isEqualToString:@"pending"]) {
                            
                            [[SshConnection sharedInstance] sshInWithKeyPath:[self sshPath] masternodeIp:[dictionary valueForKey:@"PublicIpAddress"] openShell:NO clb:^(BOOL success, NSString *message, NMSSHSession *sshSession) {
                                if (sshSession.isAuthorized) {
                                    [[instances objectForKey:[dictionary valueForKey:@"InstanceId"]] setValue:[dictionary valueForKey:@"PublicIpAddress"] forKey:@"publicIP"];
                                    [[instances objectForKey:[dictionary valueForKey:@"InstanceId"]] setValue:@([self stateForStateName:[dictionary valueForKeyPath:@"State.Name"]]) forKey:@"instanceState"];
                                    [instanceIdsLeft removeObject:[dictionary valueForKey:@"InstanceId"]];
                                    [sshSession disconnect];
                                }
                            }];
                        }
                    }
                }
                if (instanceIdsLeft) sleep(5);
            }
        });
        
    }
    else{
        [[DialogAlert sharedInstance] showAlertWithOkButton:@"Unable to create instance!" message:@"Please configure your AWS account."];
        
        PreferenceViewController *prefController = [[PreferenceViewController alloc] init];
        [prefController showConfiguringWindow];
    }
    
}

-(InstanceState)stateForStateName:(NSString*)string {
    if ([string isEqualToString:@"running"]) {
        return InstanceState_Running;
    } else if ([string isEqualToString:@"pending"]) {
        return InstanceState_Pending;
    } else if ([string isEqualToString:@"stopped"]) {
        return InstanceState_Stopped;
    } else if ([string isEqualToString:@"terminated"]) {
        return InstanceState_Terminated;
    } else if ([string isEqualToString:@"stopping"]) {
        return InstanceState_Stopping;
    } else if ([string isEqualToString:@"rebooting"]) {
        return InstanceState_Rebooting;
    } else if ([string isEqualToString:@"shutting-down"]) {
        return InstanceState_Shutting_Down;
    } else if ([string isEqualToString:@"setting up"]) {
        return InstanceState_Setting_Up;
    }
    
    return InstanceState_Stopped;
}

-(NSArray*)saveInstances:(NSArray*)instances {
    return [self saveInstances:instances removeOthers:FALSE];
}

-(NSArray*)saveInstances:(NSArray*)instances removeOthers:(BOOL)removeOthers {
    NSDictionary * knownInstances = [[[DPDataStore sharedInstance] allMasternodes] dictionaryReferencedByKeyPath:@"instanceId"];
    NSDictionary * referencedInstances = [instances dictionaryReferencedByKeyPath:@"instanceId"];
    BOOL needsSave = FALSE;
    NSMutableArray * newMasternodes = [NSMutableArray array];
    for (NSString* reference in referencedInstances) {
        if ([knownInstances objectForKey:reference]) {
            if (![[[knownInstances objectForKey:reference] valueForKey:@"instanceState"] isEqualToNumber:[referencedInstances[reference] valueForKey:@"instanceState"]]) {
                needsSave = TRUE;
                [[knownInstances objectForKey:reference] setValue:[referencedInstances[reference] valueForKey:@"instanceState"] forKey:@"instanceState"];
                
            }
            if (![[[knownInstances objectForKey:reference] valueForKey:@"publicIP"] isEqualToString:[referencedInstances[reference] valueForKey:@"publicIP"]]) {
                needsSave = TRUE;
                [[knownInstances objectForKey:reference] setValue:[referencedInstances[reference] valueForKey:@"publicIP"] forKey:@"publicIP"];
            }
        } else {
            needsSave = TRUE;
            NSManagedObject * masternode = [[DPDataStore sharedInstance] addMasternode:referencedInstances[reference] saveContext:FALSE];
            [newMasternodes addObject:masternode];
        }
    }
    if (removeOthers) {
        for (NSString* knownInstance in knownInstances) {
            if (!referencedInstances[knownInstance]) {
                needsSave = TRUE;
                [[[DPDataStore sharedInstance] mainContext] deleteObject:knownInstances[knownInstance]];
            }
        }
    }
    if (needsSave) {
        [[DPDataStore sharedInstance] saveContext];
    }
    return newMasternodes;
}
                   


- (void)getInstancesClb:(dashClb)clb {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0),^{
        
        NSDictionary *output = [self runAWSCommandJSON:[NSString stringWithFormat:@"ec2 describe-instances --filter Name=key-name,Values=%@",
                                                        [[PreferenceData sharedInstance] getKeyName]]];
        NSArray * reservations = output[@"Reservations"];
        NSMutableArray * instances = [NSMutableArray array];
        for (NSDictionary * reservation in reservations) {
            //NSLog(@"%@",reservation[@"Instances"]);
            for (NSDictionary * dictionary in reservation[@"Instances"]) {
                NSDictionary * rDict = [NSMutableDictionary dictionary];
                [rDict setValue:[dictionary valueForKey:@"InstanceId"] forKey:@"instanceId"];
                [rDict setValue:[dictionary valueForKey:@"PublicIpAddress"] forKey:@"publicIP"];
                [rDict setValue:@([self stateForStateName:[dictionary valueForKeyPath:@"State.Name"]]) forKey:@"instanceState"];
                [instances addObject:rDict];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            NSArray * newMasternodes = [self saveInstances:instances removeOthers:TRUE];
            for (NSManagedObject * masternode in newMasternodes) {
                [self checkMasternode:masternode];
            }
            clb(output?TRUE:FALSE,@"Successfully refreshed");
        });
    });
}

#pragma mark - Util

-(NSString*)randomPassword:(NSUInteger)length {
    NSString *alphabet  = @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXZY0123456789";
    NSMutableString *s = [NSMutableString stringWithCapacity:20];
    for (NSUInteger i = 0U; i < length; i++) {
        u_int32_t r = arc4random() % [alphabet length];
        unichar c = [alphabet characterAtIndex:r];
        [s appendFormat:@"%C", c];
    }
    return s;
}

-(NSString*)createConfigDashFileForMasternode:(NSManagedObject*)masternode {
    if (![masternode valueForKey:@"rpcPassword"]) {
        [masternode setValue:[self randomPassword:15] forKey:@"rpcPassword"];
        [[DPDataStore sharedInstance] saveContext];
    }
    // First we need to make a proper configuration file
    NSString *configFilePath = [[NSBundle mainBundle] pathForResource: @"dash" ofType: @"conf"];
    NSString *configFileContents = [NSString stringWithContentsOfFile:configFilePath encoding:NSUTF8StringEncoding error:NULL];
    configFileContents = [configFileContents stringByReplacingOccurrencesOfString:MASTERNODE_PRIVATE_KEY_STRING withString:[masternode valueForKey:@"key"]];
    configFileContents = [configFileContents stringByReplacingOccurrencesOfString:EXTERNAL_IP_STRING withString:[masternode valueForKey:@"publicIP"]];
    configFileContents = [configFileContents stringByReplacingOccurrencesOfString:RPC_PASSWORD_STRING withString:[masternode valueForKey:@"rpcPassword"]];
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *cachesDirectory = [paths objectAtIndex:0];
    
    //make a file name to write the data to using the documents directory:
    NSString *fileName = [NSString stringWithFormat:@"%@/dash.conf",
                          cachesDirectory];
    //create content - four lines of text
    NSString *content = configFileContents;
    //save content to the documents directory
    [content writeToFile:fileName
              atomically:NO
                encoding:NSStringEncodingConversionAllowLossy
                   error:nil];
    
    return fileName;
}

-(NSString*)createSentinelConfFile {
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains
    (NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    
    //make a file name to write the data to using the documents directory:
    NSString *fileName = [NSString stringWithFormat:@"%@/sentinel.conf",
                          documentsDirectory];
    //create content - four lines of text
    NSString *content = @"# specify path to dash.conf or leave blankult=mainnet)\n# default is the same as DashCore\n#dash_conf=/home/evan82/.dashcore/dash.conf\n\n# valid options are mainnet, testnet (default=mainnet)\nnetwork=mainnet\n#network=testnet\n\n# database connection details\ndb_name=database/sentinel.db\ndb_driver=sqlite]";
    //save content to the documents directory
    [content writeToFile:fileName
              atomically:NO
                encoding:NSStringEncodingConversionAllowLossy
                   error:nil];
    
    return fileName;
}


#pragma mark - Singleton methods

+ (DPMasternodeController *)sharedInstance
{
    static DPMasternodeController *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[DPMasternodeController alloc] init];
        
        // Do any other initialisation stuff here
    });
    return sharedInstance;
}


@end
