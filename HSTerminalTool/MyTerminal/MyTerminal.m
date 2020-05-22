//
//  MyTerminal.m
//  HSTerminalTool
//
//  Created by WeidongCao on 2020/5/22.
//  Copyright © 2020 WeidongCao. All rights reserved.
//

#import "MyTerminal.h"
#import "util.h"
@interface MyTerminal()

@property int filedescription;
@property pid_t childPID;
@property NSFileHandle *filehandle;

@end
@implementation MyTerminal

-(instancetype)init{
    if (self=[super init]) {
        self.childPID = -1;
        self.filehandle = nil;
        self.filedescription = -1;
    }
    
    return self;
}

-(BOOL)startTerminal{
    self.filedescription = -1;
    //pid_t    forkpty(int *, char *, struct termios *, struct winsize *);
    pid_t pid = forkpty(&_filedescription,nil,nil,nil);
    if (pid == -1) {
        NSLog(@"fork failed: %d: %s", errno, strerror(errno));
        return NO;
    }else if(pid == 0){
        // Handle the child subprocess. First try to use /bin/login since it’s a little nicer. Fall
        // back to /bin/bash if that is available.
        [self autoLogin];
    }else{
        NSLog(@"process forked: %d", pid);
        self.childPID = pid;
        self.filehandle = [[NSFileHandle alloc] initWithFileDescriptor:self.filedescription closeOnDealloc:YES];
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserver:self selector:@selector(didReceivedData:) name:NSFileHandleReadCompletionNotification object:self.filehandle];
        [self.filehandle readInBackgroundAndNotify];
    }
    
    return YES;
    
}
-(void)autoLogin{
    NSArray *args1 = @[@"login",@"-fp", NSUserName()];
    NSArray *args2 = @[@"bash",@"--login", @"-i"];
    NSArray *env = @[@"TERM=xterm-color",
                     @"LANG=en_US.UTF-8",
                     @"TERM_PROGRAM=NewTerm",
                     @"LC_TERMINAL=NewTerm"];
    //[self attemptStartProcessPath:@"/usr/bin/login" args:args1 env:env];
    [self attemptStartProcessPath:@"/bin/bash" args:args2 env:env];
}
-(void)writeCommand:(NSData *)cmd{
    [self.filehandle writeData:cmd];
}
-(void)stopTerminal{
    if (self.childPID == -1) {
        return;
    }
    kill(self.childPID,SIGKILL);
    
    int stat;
    waitpid(self.childPID, &stat, WUNTRACED);
    
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center removeObserver:self name:NSFileHandleReadCompletionNotification object:self.filehandle];
    self.childPID = -1;
    self.filedescription = -1;
    self.filehandle = nil;
    
}

-(BOOL)attemptStartProcessPath:(NSString *)path args:(NSArray *)args env:(NSArray *)env{
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:path] == NO) {
        return NO;
    }
    if ([fm isExecutableFileAtPath:path] == NO) {
        return NO;
    }
    const char* pathC = [path cStringUsingEncoding:NSUTF8StringEncoding];
    char** argsC = [self cStringArray:args];
    char** envC = [self cStringArray:env];
    if (execve(pathC, argsC, envC) == -1) {
        NSLog(@"%@: exec failed: %s", path, strerror(errno));
        return NO;
    }
    return YES;
}

- (char **)cStringArray:(NSArray *)array{
    // this is in objc because it’s impossibly complex to do this in Objective-C…
    NSUInteger count = array.count + 1;
    char **result = malloc(sizeof(char *) * count);

    for (NSUInteger i = 0; i < array.count; i++) {
        NSString *item = [array[i] isKindOfClass:NSString.class] ? array[i] : ((NSObject *)array[i]).description;
        result[i] = (char *)item.UTF8String;
    }

    result[count - 1] = NULL;
    return result;
}
-(void)didReceivedData:(NSNotification *)notification{
    NSData *data = [notification.userInfo objectForKey:NSFileHandleNotificationDataItem];
    if (data == nil) {
        NSLog(@"file handle read callback returned nil data");
        return;
    }
    if ([data length] == 0) {
        NSLog(@"terminal has exited!");
        return;
    }
    NSLog(@"recv data:%@",[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
    
    [self.filehandle readInBackgroundAndNotify];
}
@end
