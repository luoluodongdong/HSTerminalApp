//
//  HSPython.m
//  HSTerminalTool
//
//  Created by WeidongCao on 2020/5/21.
//  Copyright © 2020 WeidongCao. All rights reserved.
//

#import "HSPython.h"
#import "HSTerminal.h"
#define errDomain @"com.Apple.HWTE.ZynqTCP"
#define TID_WINDOW_SIZE 0xFFFF
#define PING_TIMEOUT_LIMIT 10.0
#define SEND_COOLDOWN 0.05
@interface HSPython()<HSTerminalStreamListener>
{
    NSTimeInterval lastSendTime;
    NSUInteger latestTID;
    
}
/*!
 @brief FFEthernet connection to the IA board ethernet port
 */
@property (strong) HSTerminal* connection;

-(void)onConnectionClosed:(NSError*)err;

@end

@implementation HSPython
-(id)init
{
    self = [super init];
    if(!self) return self;
    
    lastSendTime = CFAbsoluteTimeGetCurrent();
    latestTID = 0; //Initial state
    self.isConnected = FALSE;
    self.timeout = 5.0; //Default timeout
    
    return self;
}

-(NSError*)connectIP:(NSString*)ip port:(NSString*)port
{
    NSError *err = nil;
    //If we are currently open, close it.
    if(self.connection) {
        NSLog(@"%@ Closing existing connection", errDomain);
        [self.connection close];
        self.connection = nil;
    }
    
    //New node with this URL
    NSURL *newURL = [NSURL URLWithString:[NSString stringWithFormat:@"tcp://%@:%@",ip,port]];
    self.connection = [HSTerminal ezTelnetWithURL:newURL];
    //FIXME: Make this internal to the bundle!
    NSString *telnetPath = [NSString stringWithFormat:@"%@/TerminalApps/telnet",[[NSBundle mainBundle] resourcePath]];
    //NSLog(@"telnet:%@",telnetPath);
    self.connection.launchPath = @"/usr/bin/python";
    //self.connection.launchPath = telnetPath;
    NSLog(@"%@ Opening new connection %@", errDomain, [newURL description]);
    BOOL status = [self.connection openConnectionWithTimeout:self.timeout
                       connectionClosedHandler:^(NSError* err){[self onConnectionClosed:err];}
                                         error:&err];
    NSLog(@"connection status:%hhd",status);
    if(err) return err;
    self.connection.telnetListener = self;
    self.isConnected = TRUE;
    /*
    //Ping fixture until response happens
    CFAbsoluteTime startPinging = CFAbsoluteTimeGetCurrent();
    NSLog(@"Started trying to ping IA board.");
    double tempTimeout = self.timeout;
    self.timeout = PING_TIMEOUT_LIMIT;
    NSString *response = [self send:@"hello world()\n" withError:&err];
//    if(err) return err;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    err = nil;
    
    response = [self send:@"hello world()\n" withError:&err];
    if(err) return err;
    if([response length] > 0) {
        NSLog(@"IA board responded after %f seconds", (now - startPinging));
        self.timeout = tempTimeout;
        self.isConnected = TRUE;
        return nil;
    }
    return [NSError errorWithDomain:errDomain
                               code:-1
                           userInfo:@{NSLocalizedDescriptionKey : @"Timed out trying to ping IA board."}];
     */
    return nil;
}

-(NSError*)disconnect
{
    //If we are currently open, close it.
    if(self.connection) {
        NSLog(@"%@ Closing connection", errDomain);
        [self.connection close];
    } else {
        NSLog(@"%@ No open connection to close", errDomain);
    }
    return nil;
}

-(void)onConnectionClosed:(NSError*)err
{
    NSLog(@"%@ Connection was closed", errDomain);
    self.connection = nil;
    self.isConnected = FALSE;
}

-(NSString*)send:(NSString*)input withError:(NSError**)err;
{
    //Built-in anti-spam cooldown
    if((CFAbsoluteTimeGetCurrent() - lastSendTime) < SEND_COOLDOWN) {
        [NSThread sleepForTimeInterval:SEND_COOLDOWN];
    }
    lastSendTime = CFAbsoluteTimeGetCurrent();
    
    //Check that we actually have a connection
    if(!self.connection) {
        *err = [NSError errorWithDomain:errDomain
                                   code:-1
                               userInfo:@{NSLocalizedDescriptionKey : @"No existing connection"}];
        return nil;
    }
    
    //Generate a new transaction ID
    latestTID++;
    if(latestTID >= TID_WINDOW_SIZE) latestTID = 0;
    NSString *tidTag = [NSString stringWithFormat:@"[%lu]", (unsigned long)latestTID];
    NSString *regEx = [NSString stringWithFormat:@"\\%@(.*)", tidTag];
    NSString *actualTXString = [NSString stringWithFormat:@"%@%@", tidTag, input];
    
    NSLog(@"%@ SEND: %@", errDomain, input);
    NSString *responseString = nil;
    BOOL writeOK = [self.connection write:input
             waitForRegexMatch:@">>>"
                       timeout:self.timeout response:&responseString];
    
    if(!writeOK) {
        *err = [NSError errorWithDomain:errDomain
                                   code:-1
                               userInfo:@{NSLocalizedDescriptionKey : @"Failed to send data through port"}];
        return nil;
    }
    
    NSLog(@"%@ RECV: %@", errDomain, responseString);
    
    return responseString;
    
    //We expect a response of the form: [17cfacff023e]ACK(DONE;1516223748,53,1516223748,55,2)
    //Or of: [07bd5d0ee74c]ACK(average = 996.5417719900538 mV,max = 996.6974669746697 mV,min = 996.3849638496384 mV,vpp = 0.31250312503125033 mV,rms = 996.5417729412644 mV;DONE;1516223515,234,1516223516,238,1004)
    //[tid]ACK(<response text>;<start timestamp seconds>,<start time milliseconds>,<end time seconds>,<end time milliseconds>,<???>)
    
    //Parse out the ACK()
    NSRegularExpression *ackExpr =[NSRegularExpression regularExpressionWithPattern:regEx options:0 error:err];
    if(*err) return nil;
    NSArray *matches = [ackExpr matchesInString:responseString options:0 range:NSMakeRange(0, [responseString length])];
    if([matches count] == 0) {
        *err = [NSError errorWithDomain:errDomain
                                   code:-1
                               userInfo:@{NSLocalizedDescriptionKey : @"Did not match [tid] in response"}];
        return nil;
    }
    
    NSString *tidlessString = [responseString substringWithRange:[matches[0] rangeAtIndex:1]];
    *err = nil;
    //return tidlessString;
    //return responseString;
}
- (void)receiveStandardInData:(NSString *)str{
    NSLog(@"recv in data:%@",str);
}
- (void)receiveStandardOutData:(NSString *)str{
    NSLog(@"recv out data:%@",str);
}
- (void)receiveStandardErrorData:(NSString *)str{
    NSLog(@"recv err data:%@",str);
}
@end
